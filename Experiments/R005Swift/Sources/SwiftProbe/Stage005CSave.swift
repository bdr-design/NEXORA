#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

struct StageCSnapshotFileResult: Sendable {
    let bytes: UInt64
    let chunks: Int
    let writeNS: UInt64
    let peakQueuedBytes: Int
    let batchFlushes: Int
    let threadQoS: String
}

final class StageCWriterCounters: Sendable {
    let queued = Atomic<Int>(0)
    let peak = Atomic<Int>(0)
    let done = Atomic<Int>(0)
    let failed = Atomic<Int>(0)
    let bytes = Atomic<UInt64>(0)
    let chunks = Atomic<Int>(0)
    let writeNS = Atomic<UInt64>(0)
    let batchFlushes = Atomic<Int>(0)
    let threadQoS = Mutex<String>("unmeasured")
}

struct StageCRecordQueueState: Sendable {
    var slots: [[UInt8]?]
    var head: Int = 0
    var tail: Int = 0
    var finished = false
}

final class StageCRecordQueue: Sendable {
    private let state: Mutex<StageCRecordQueueState>
    private let available = DispatchSemaphore(value: 0)

    init(capacity: Int) {
        precondition(capacity > 0)
        state = Mutex(StageCRecordQueueState(slots: Array(repeating: nil, count: capacity)))
    }

    func push(_ record: [UInt8]) {
        state.withLock { value in
            precondition(!value.finished && value.tail < value.slots.count)
            precondition(value.slots[value.tail] == nil)
            value.slots[value.tail] = record
            value.tail += 1
        }
        available.signal()
    }

    func pop() -> [UInt8]? {
        state.withLock { value in
            guard value.head < value.tail else { return nil }
            let record = value.slots[value.head]
            value.slots[value.head] = nil
            value.head += 1
            return record
        }
    }

    func finish() {
        state.withLock { $0.finished = true }
        available.signal()
    }

    func waitAndPop() -> [UInt8]? {
        available.wait()
        return state.withLock { value in
            guard value.head < value.tail else {
                precondition(value.finished)
                return nil
            }
            let record = value.slots[value.head]
            value.slots[value.head] = nil
            value.head += 1
            return record
        }
    }

    var isDrained: Bool {
        state.withLock { $0.finished && $0.head == $0.tail }
    }
}

final class SnapshotSink: Sendable {
    let epoch: UInt32
    let counters: StageCWriterCounters
    private let queue: StageCRecordQueue

    init(directory: String, epoch: UInt32, expectedCounts: [UInt32]) {
        self.epoch = epoch
        let counters = StageCWriterCounters()
        let capacity = expectedCounts.reduce(0) { $0 + Int($1) }
        let queue = StageCRecordQueue(capacity: capacity)
        self.counters = counters
        self.queue = queue
        DispatchQueue.global(qos: .utility).async(qos: .utility, flags: [.enforceQoS, .detached]) {
            do {
                let result = try StageCSnapshotWriter.run(queue, counters: counters,
                    directory: directory, epoch: epoch, expectedCounts: expectedCounts)
                counters.bytes.store(result.bytes, ordering: .releasing)
                counters.chunks.store(result.chunks, ordering: .releasing)
                counters.writeNS.store(result.writeNS, ordering: .releasing)
                counters.batchFlushes.store(result.batchFlushes, ordering: .releasing)
            } catch {
                counters.failed.store(1, ordering: .releasing)
            }
            counters.done.store(1, ordering: .releasing)
        }
    }

    func emit(_ record: [UInt8]) {
        let queuedBytes = record.count + 32
        let now = counters.queued.add(queuedBytes, ordering: .relaxed).newValue
        var seen = counters.peak.load(ordering: .relaxed)
        while now > seen {
            let result = counters.peak.compareExchange(expected: seen, desired: now, ordering: .relaxed)
            if result.exchanged {
                nx_kill_point("c.k10.peak_queue")
                break
            }
            seen = result.original
        }
        queue.push(record)
    }

    func finish() { queue.finish() }

    func resultIfDone() throws -> StageCSnapshotFileResult? {
        guard counters.done.load(ordering: .acquiring) == 1 else { return nil }
        guard counters.failed.load(ordering: .acquiring) == 0 else {
            throw ProbeError.invalid("stage C background snapshot writer failed")
        }
        return StageCSnapshotFileResult(bytes: counters.bytes.load(ordering: .acquiring),
            chunks: counters.chunks.load(ordering: .acquiring),
            writeNS: counters.writeNS.load(ordering: .acquiring),
            peakQueuedBytes: counters.peak.load(ordering: .acquiring),
            batchFlushes: counters.batchFlushes.load(ordering: .acquiring),
            threadQoS: counters.threadQoS.withLock { $0 })
    }
}

enum StageCSnapshotWriter {
    static let batchBytes = 256 * 1024

    static func parseRecord(_ record: [UInt8]) throws -> (StageCRecordKey, UInt32, NXRHash) {
        guard record.count >= 16 else { throw ProbeError.corruption("stage C short record") }
        var r = StageCByteReader(bytes: record)
        let kind = try r.u16(), reserved = try r.u16(), index = try r.u32()
        let elements = try r.u32(), payloadBytes = Int(try r.u32())
        guard reserved == 0, kind <= 3, payloadBytes >= 0,
              record.count == 16 + payloadBytes else {
            throw ProbeError.corruption("stage C record header")
        }
        let digest = Snapshot.hashBytes(record, range: 16..<record.count)
        return (StageCRecordKey(kind: kind, index: index), elements, digest)
    }

    static func run(_ queue: StageCRecordQueue, counters: StageCWriterCounters,
                    directory: String, epoch: UInt32,
                    expectedCounts: [UInt32]) throws -> StageCSnapshotFileResult {
        guard expectedCounts.count == 4, expectedCounts[0] == 1 else {
            throw ProbeError.invalid("stage C expected record counts")
        }
        let start = nx_now()
        let threadQoS = Snapshot.currentThreadQoS()
        counters.threadQoS.withLock { $0 = threadQoS }
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
        let recordCount = expectedCounts.reduce(0) { $0 + Int($1) }
        let offsets = [0, Int(expectedCounts[0]), Int(expectedCounts[0]) + Int(expectedCounts[1]),
                       Int(expectedCounts[0]) + Int(expectedCounts[1]) + Int(expectedCounts[2])]
        var seen = ContiguousArray<UInt8>(repeating: 0, count: recordCount)
        var canonical = Snapshot.canonicalMetadata(expectedCounts)
        var batch: [UInt8] = []
        batch.reserveCapacity(batchBytes + 18_876)
        var pendingRecordBytes = 0
        var batchFlushes = 0
        var midpointWritten = false
        func flush() throws {
            guard !batch.isEmpty else { return }
            try Snapshot.writeRecord(batch, descriptor: handle.fileDescriptor, range: 0..<batch.count)
            batchFlushes += 1
            batch.removeAll(keepingCapacity: true)
            _ = counters.queued.subtract(pendingRecordBytes, ordering: .relaxed)
            pendingRecordBytes = 0
        }

        while true {
            guard let record = queue.waitAndPop() else { break }
            let parsed = try parseRecord(record)
            let key = parsed.0
            guard key.kind < 4, key.index < expectedCounts[Int(key.kind)] else {
                throw ProbeError.corruption("stage C out-of-range record")
            }
            let slot = offsets[Int(key.kind)] + Int(key.index)
            guard seen[slot] == 0 else { throw ProbeError.corruption("stage C duplicate record") }
            seen[slot] = 1
            let digestOffset = slot * 38 + 6
            Snapshot.storeDigest(parsed.2, into: &canonical, at: digestOffset)
            counts[Int(key.kind)] += 1
            if key.kind > 0 && !midpointWritten {
                let split = max(16, record.count / 2)
                batch.append(contentsOf: record[0..<split])
                // Keep K3 at a physically written incomplete record, including
                // its complete byte count until the remainder is flushed.
                try flush()
                nx_kill_point("c.k3.mid_record")
                midpointWritten = true
                batch.append(contentsOf: record[split..<record.count])
            } else {
                batch.append(contentsOf: record)
            }
            batch.append(contentsOf: canonical[digestOffset..<(digestOffset + 32)])
            bytesWritten += UInt64(record.count + 32)
            pendingRecordBytes += record.count + 32
            if batch.count >= batchBytes { try flush() }
        }

        try flush()
        guard counters.queued.load(ordering: .relaxed) == 0 else {
            throw ProbeError.invariant("stage C queued byte accounting")
        }
        guard counts == expectedCounts else { throw ProbeError.corruption("stage C missing record") }
        nx_kill_point("c.k4.before_footer")
        let totalBytes = bytesWritten + 64
        let footer = Snapshot.footer(counts: counts, totalBytes: totalBytes, canonicalDigestInput: Data(canonical))
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
        return StageCSnapshotFileResult(bytes: totalBytes, chunks: recordCount,
            writeNS: nx_now() - start, peakQueuedBytes: counters.peak.load(ordering: .relaxed),
            batchFlushes: batchFlushes, threadQoS: threadQoS)
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
    private(set) var barrierBytes = 0
    private(set) var barrierNS: UInt64 = 0
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
    init(world: HybridWorld) {
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
        barrierBytes = 0
        barrierNS = 0
        lastResult = nil
        preparedSink.emit(Snapshot.controlRecord(world))
        nx_kill_point("c.k1.after_begin")
    }
    func begin(world: HybridWorld, preparedSink: SnapshotSink) throws {
        guard sink == nil, !capturing, preparedSink.epoch > epoch else {
            throw ProbeError.invalid("stage C save already active/epoch")
        }
        epoch=preparedSink.epoch;sink=preparedSink;capturing=true;serviceCursor=0
        barrierEmits=0;barrierBytes=0;barrierNS=0;lastResult=nil
        preparedSink.emit(Snapshot.controlRecord(world))
        nx_kill_point("c.k1.after_begin")
    }

    @inline(__always) func willWriteAsset(_ world: SwiftWorld, index: Int) {
        guard capturing else { return }
        let chunk = index >> 8
        if assetSaved[chunk] != epoch, let sink {
            let start = nx_now()
            let record = Snapshot.assetRecord(world, chunk: chunk)
            sink.emit(record)
            barrierNS += nx_now() - start
            barrierBytes += record.count + 32
            assetSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }

    @inline(__always) func willWriteNode(_ wheel: TimingWheel, index: Int) {
        guard capturing else { return }
        let chunk = index >> 9
        if nodeSaved[chunk] != epoch, let sink {
            let start = nx_now()
            let record = Snapshot.nodeRecord(wheel, chunk: chunk)
            sink.emit(record)
            barrierNS += nx_now() - start
            barrierBytes += record.count + 32
            nodeSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }

    @inline(__always) func willWriteGroup(_ world: SwiftWorld, index: Int) {
        guard capturing else { return }
        let chunk = index >> 11
        if groupSaved[chunk] != epoch, let sink {
            let start = nx_now()
            let record = Snapshot.groupRecord(world, chunk: chunk)
            sink.emit(record)
            barrierNS += nx_now() - start
            barrierBytes += record.count + 32
            groupSaved[chunk] = epoch
            barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }
    @inline(__always) func willWriteAsset(_ world: HybridWorld, index: Int) {
        guard capturing else { return }
        let chunk=index>>8
        if assetSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.assetRecord(world,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            assetSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }
    @inline(__always) func willWriteNode(_ wheel: HybridTimingWheel, index: Int) {
        guard capturing else { return }
        let chunk=index>>9
        if nodeSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.nodeRecord(wheel,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            nodeSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
        }
    }
    @inline(__always) func willWriteGroup(_ world: HybridWorld, index: Int) {
        guard capturing else { return }
        let chunk=index>>11
        if groupSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.groupRecord(world,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            groupSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
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
    private func emitCanonicalIfUnsaved(_ world: HybridWorld, canonical: Int) {
        guard let sink else { return }
        if canonical < assetChunks {
            if assetSaved[canonical] != epoch {
                sink.emit(Snapshot.assetRecord(world,chunk:canonical));assetSaved[canonical]=epoch
            }
            return
        }
        let nodeBase=assetChunks
        if canonical < nodeBase+nodeChunks {
            let chunk=canonical-nodeBase
            if nodeSaved[chunk] != epoch {
                sink.emit(Snapshot.nodeRecord(world.wheel,chunk:chunk));nodeSaved[chunk]=epoch
            }
            return
        }
        let chunk=canonical-nodeBase-nodeChunks
        if groupSaved[chunk] != epoch {
            sink.emit(Snapshot.groupRecord(world,chunk:chunk));groupSaved[chunk]=epoch
        }
    }
    func service(world: HybridWorld, budgetNS: UInt64) throws {
        guard sink != nil else { return }
        if capturing {
            let deadline=nx_now() &+ budgetNS
            while serviceCursor<totalChunks && nx_now()<deadline {
                emitCanonicalIfUnsaved(world,canonical:serviceCursor);serviceCursor += 1
            }
            if serviceCursor==totalChunks { sink?.finish();capturing=false }
        }
        if !capturing,let result=try sink?.resultIfDone() { lastResult=result;sink=nil }
    }
    func waitForCommit(world: HybridWorld, serviceBudgetNS: UInt64 = 500_000) throws -> StageCSnapshotFileResult {
        var spins=0
        while sink != nil {
            try service(world:world,budgetNS:serviceBudgetNS)
            if sink != nil {
                spins += 1
                if spins>5_000_000 { throw ProbeError.invalid("stage C hybrid writer did not finish") }
                Thread.sleep(forTimeInterval:0.00005)
            }
        }
        guard let lastResult else { throw ProbeError.invalid("stage C hybrid missing save result") }
        return lastResult
    }
}
#endif
