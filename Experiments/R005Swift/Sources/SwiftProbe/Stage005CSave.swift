#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

struct StageCSnapshotFileResult: Sendable {
    let bytes: UInt64
    let chunks: Int
    let writeNS: UInt64
    let peakQueuedBytes: Int
}

final class StageCWriterCounters: Sendable {
    let queued = Atomic<Int>(0)
    let peak = Atomic<Int>(0)
    let done = Atomic<Int>(0)
    let failed = Atomic<Int>(0)
    let bytes = Atomic<UInt64>(0)
    let chunks = Atomic<Int>(0)
    let writeNS = Atomic<UInt64>(0)
}

final class SnapshotSink: Sendable {
    let epoch: UInt32
    let counters: StageCWriterCounters
    private let continuation: AsyncStream<Data>.Continuation

    init(directory: String, epoch: UInt32, expectedCounts: [UInt32]) {
        self.epoch = epoch
        let counters = StageCWriterCounters()
        let pair = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        self.counters = counters
        self.continuation = pair.continuation
        Task.detached(priority: .utility) {
            do {
                let result = try await StageCSnapshotWriter.run(pair.stream, counters: counters,
                    directory: directory, epoch: epoch, expectedCounts: expectedCounts)
                counters.bytes.store(result.bytes, ordering: .releasing)
                counters.chunks.store(result.chunks, ordering: .releasing)
                counters.writeNS.store(result.writeNS, ordering: .releasing)
            } catch {
                counters.failed.store(1, ordering: .releasing)
            }
            counters.done.store(1, ordering: .releasing)
        }
    }

    func emit(_ record: Data) {
        let now = counters.queued.add(record.count, ordering: .relaxed).newValue
        var seen = counters.peak.load(ordering: .relaxed)
        while now > seen {
            let result = counters.peak.compareExchange(expected: seen, desired: now, ordering: .relaxed)
            if result.exchanged {
                nx_kill_point("c.k10.peak_queue")
                break
            }
            seen = result.original
        }
        continuation.yield(record)
    }

    func finish() { continuation.finish() }

    func resultIfDone() throws -> StageCSnapshotFileResult? {
        guard counters.done.load(ordering: .acquiring) == 1 else { return nil }
        guard counters.failed.load(ordering: .acquiring) == 0 else {
            throw ProbeError.invalid("stage C background snapshot writer failed")
        }
        return StageCSnapshotFileResult(bytes: counters.bytes.load(ordering: .acquiring),
            chunks: counters.chunks.load(ordering: .acquiring),
            writeNS: counters.writeNS.load(ordering: .acquiring),
            peakQueuedBytes: counters.peak.load(ordering: .acquiring))
    }
}

enum StageCSnapshotWriter {
    static func parseRecord(_ record: Data) throws -> (StageCRecordKey, UInt32, Data, Data) {
        guard record.count >= 48 else { throw ProbeError.corruption("stage C short record") }
        var r = StageCByteReader(bytes: Array(record.prefix(16)))
        let kind = try r.u16(), reserved = try r.u16(), index = try r.u32()
        let elements = try r.u32(), payloadBytes = Int(try r.u32())
        guard reserved == 0, kind <= 3, payloadBytes >= 0,
              record.count == 16 + payloadBytes + 32 else {
            throw ProbeError.corruption("stage C record header")
        }
        let payload = record.subdata(in: 16..<(16 + payloadBytes))
        let digest = record.subdata(in: (16 + payloadBytes)..<record.count)
        guard digest == Snapshot.digestData(payload) else {
            throw ProbeError.corruption("stage C record payload hash")
        }
        return (StageCRecordKey(kind: kind, index: index), elements, payload, digest)
    }

    static func run(_ stream: AsyncStream<Data>, counters: StageCWriterCounters,
                    directory: String, epoch: UInt32,
                    expectedCounts: [UInt32]) async throws -> StageCSnapshotFileResult {
        guard expectedCounts.count == 4, expectedCounts[0] == 1 else {
            throw ProbeError.invalid("stage C expected record counts")
        }
        let start = nx_now()
        let tmp = directory + "/snapshot-\(epoch).tmp"
        let final = directory + "/snapshot-\(epoch).bin"
        guard FileManager.default.createFile(atPath: tmp, contents: nil) else {
            throw ProbeError.invalid("stage C tmp create")
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmp))
        defer { try? handle.close() }
        let prefix = Snapshot.filePrefix()
        try handle.write(contentsOf: prefix)
        var bytesWritten = UInt64(prefix.count)
        var counts = [UInt32](repeating: 0, count: 4)
        var digests: [StageCRecordKey: Data] = [:]
        digests.reserveCapacity(expectedCounts.reduce(0) { $0 + Int($1) })

        for await record in stream {
            let parsed = try parseRecord(record)
            let key = parsed.0
            guard key.kind < 4, key.index < expectedCounts[Int(key.kind)],
                  digests[key] == nil else {
                throw ProbeError.corruption("stage C duplicate/out-of-range record")
            }
            digests[key] = parsed.3
            counts[Int(key.kind)] += 1
            if key.kind > 0 {
                let split = max(16, record.count / 2)
                try handle.write(contentsOf: record.prefix(split))
                nx_kill_point("c.k3.mid_record")
                try handle.write(contentsOf: record.suffix(record.count - split))
            } else {
                try handle.write(contentsOf: record)
            }
            bytesWritten += UInt64(record.count)
            _ = counters.queued.subtract(record.count, ordering: .relaxed)
        }

        guard counts == expectedCounts else { throw ProbeError.corruption("stage C missing record") }
        nx_kill_point("c.k4.before_footer")
        var canonical = Data(capacity: digests.count * 38)
        for kind in UInt16(0)...UInt16(3) {
            for index in UInt32(0)..<expectedCounts[Int(kind)] {
                let key = StageCRecordKey(kind: kind, index: index)
                guard let digest = digests[key] else { throw ProbeError.corruption("stage C canonical record") }
                Snapshot.appendLE(kind, into: &canonical)
                Snapshot.appendLE(index, into: &canonical)
                canonical.append(digest)
            }
        }
        let totalBytes = bytesWritten + 64
        let footer = Snapshot.footer(counts: counts, totalBytes: totalBytes, canonicalDigestInput: canonical)
        try handle.write(contentsOf: footer)
        nx_kill_point("c.k5.after_footer")
        try handle.synchronize()
        nx_kill_point("c.k6.after_fsync")
        try handle.close()
        guard nx_replace_file(tmp, final) == 0 else { throw ProbeError.invalid("stage C snapshot rename") }
        nx_kill_point("c.k7.after_rename")
        guard nx_sync_dir(directory) == 0 else { throw ProbeError.invalid("stage C snapshot directory sync") }
        let markerTmp = directory + "/snapshot-\(epoch).commit.tmp"
        let marker = directory + "/snapshot-\(epoch).commit"
        var markerData = Data()
        Snapshot.appendLE(epoch, into: &markerData)
        Snapshot.appendLE(UInt32(0x54494d43), into: &markerData)
        let markerHandle = try exclusiveHandle(markerTmp)
        try markerHandle.write(contentsOf: markerData)
        try markerHandle.synchronize()
        try markerHandle.close()
        guard nx_replace_file(markerTmp, marker) == 0 else { throw ProbeError.invalid("stage C marker rename") }
        guard nx_sync_dir(directory) == 0 else { throw ProbeError.invalid("stage C marker directory sync") }
        nx_kill_point("c.k8.after_dirsync")
        if epoch > 0 {
            let oldSnapshot = directory + "/snapshot-\(epoch - 1).bin"
            let oldWAL = directory + "/wal-\(epoch - 1).log"
            let oldMarker = directory + "/snapshot-\(epoch - 1).commit"
            if FileManager.default.fileExists(atPath: oldSnapshot) { try FileManager.default.removeItem(atPath: oldSnapshot) }
            if FileManager.default.fileExists(atPath: oldWAL) { try FileManager.default.removeItem(atPath: oldWAL) }
            if FileManager.default.fileExists(atPath: oldMarker) { try FileManager.default.removeItem(atPath: oldMarker) }
            guard nx_sync_dir(directory) == 0 else { throw ProbeError.invalid("stage C generation cleanup sync") }
        }
        return StageCSnapshotFileResult(bytes: totalBytes, chunks: digests.count,
            writeNS: nx_now() - start, peakQueuedBytes: counters.peak.load(ordering: .relaxed))
    }
}

final class StageCState {
    let assetChunks: Int
    let nodeChunks: Int
    let groupChunks: Int
    private var assetSaved: ContiguousArray<UInt32>
    private var nodeSaved: ContiguousArray<UInt32>
    private var groupSaved: ContiguousArray<UInt32>
    private(set) var epoch: UInt32 = 0
    private(set) var capturing = false
    private(set) var serviceCursor = 0
    private(set) var barrierEmits = 0
    private var sink: SnapshotSink? = nil
    private(set) var lastResult: StageCSnapshotFileResult? = nil

    init(world: SwiftWorld) {
        assetChunks = (world.count + 255) >> 8
        nodeChunks = (world.wheel.capacity + 511) >> 9
        groupChunks = (world.groupAmounts.count + 2047) >> 11
        assetSaved = .init(repeating: 0, count: assetChunks)
        nodeSaved = .init(repeating: 0, count: nodeChunks)
        groupSaved = .init(repeating: 0, count: groupChunks)
    }

    var expectedCounts: [UInt32] {
        [1, UInt32(assetChunks), UInt32(nodeChunks), UInt32(groupChunks)]
    }
    var totalChunks: Int { assetChunks + nodeChunks + groupChunks }
    var inFlight: Bool { sink != nil }

    func begin(world: SwiftWorld, preparedSink: SnapshotSink) throws {
        guard sink == nil, !capturing, preparedSink.epoch > epoch else {
            throw ProbeError.invalid("stage C save already active/epoch")
        }
        epoch = preparedSink.epoch
        sink = preparedSink
        capturing = true
        serviceCursor = 0
        barrierEmits = 0
        lastResult = nil
        preparedSink.emit(Snapshot.controlRecord(world))
        nx_kill_point("c.k1.after_begin")
    }

    @inline(__always) func willWriteAsset(_ world: SwiftWorld, index: Int) {
        guard capturing, let sink else { return }
        let chunk = index >> 8
        if assetSaved[chunk] != epoch {
            sink.emit(Snapshot.assetRecord(world, chunk: chunk))
            assetSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }

    @inline(__always) func willWriteNode(_ wheel: TimingWheel, index: Int) {
        guard capturing, let sink else { return }
        let chunk = index >> 9
        if nodeSaved[chunk] != epoch {
            sink.emit(Snapshot.nodeRecord(wheel, chunk: chunk))
            nodeSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }

    @inline(__always) func willWriteGroup(_ world: SwiftWorld, index: Int) {
        guard capturing, let sink else { return }
        let chunk = index >> 11
        if groupSaved[chunk] != epoch {
            sink.emit(Snapshot.groupRecord(world, chunk: chunk))
            groupSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }

    private func emitCanonicalIfUnsaved(_ world: SwiftWorld, canonical: Int) {
        guard let sink else { return }
        if canonical < assetChunks {
            if assetSaved[canonical] != epoch {
                sink.emit(Snapshot.assetRecord(world, chunk: canonical)); assetSaved[canonical] = epoch
            }
            return
        }
        let nodeBase = assetChunks
        if canonical < nodeBase + nodeChunks {
            let chunk = canonical - nodeBase
            if nodeSaved[chunk] != epoch {
                sink.emit(Snapshot.nodeRecord(world.wheel, chunk: chunk)); nodeSaved[chunk] = epoch
            }
            return
        }
        let chunk = canonical - nodeBase - nodeChunks
        if groupSaved[chunk] != epoch {
            sink.emit(Snapshot.groupRecord(world, chunk: chunk)); groupSaved[chunk] = epoch
        }
    }

    func service(world: SwiftWorld, budgetNS: UInt64) throws {
        guard sink != nil else { return }
        if capturing {
            let deadline = nx_now() &+ budgetNS
            while serviceCursor < totalChunks && nx_now() < deadline {
                emitCanonicalIfUnsaved(world, canonical: serviceCursor)
                serviceCursor += 1
            }
            if serviceCursor == totalChunks {
                sink?.finish()
                capturing = false
            }
        }
        if !capturing, let result = try sink?.resultIfDone() {
            lastResult = result
            sink = nil
        }
    }

    func waitForCommit(world: SwiftWorld, serviceBudgetNS: UInt64 = 500_000) throws -> StageCSnapshotFileResult {
        var spins = 0
        while sink != nil {
            try service(world: world, budgetNS: serviceBudgetNS)
            if sink != nil {
                spins += 1
                if spins > 5_000_000 { throw ProbeError.invalid("stage C writer did not finish") }
                Thread.sleep(forTimeInterval: 0.00005)
            }
        }
        guard let lastResult else { throw ProbeError.invalid("stage C missing save result") }
        return lastResult
    }
}
#endif
