#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

struct StageCSnapshotFileResult: Sendable {
    let bytes: UInt64
    let chunks: Int
    let writeNS: UInt64
    let dispatchToRunNS: UInt64
    let queueWaitNS: UInt64
    let recordProcessWriteNS: UInt64
    let finalizeNS: UInt64
    let writerAllocations: UInt64
    let writerAllocationBytes: UInt64
    let writerAllocationObserverAvailable: Bool
    let peakQueuedBytes: Int
    var retainedEpochBufferBytes: Int = 0
    var snapshotSource: String = "record_queue"
}

#if EPOCH_PAGES
struct StageCEpochCompletion {
    let epoch: UInt32
    let ownerID: ObjectIdentifier
    fileprivate init(epoch: UInt32, ownerID: ObjectIdentifier) { self.epoch = epoch; self.ownerID = ownerID }
}
#endif

final class StageCWriterCounters: Sendable {
    let queued = Atomic<Int>(0)
    let peak = Atomic<Int>(0)
    let done = Atomic<Int>(0)
    let failed = Atomic<Int>(0)
    let bytes = Atomic<UInt64>(0)
    let chunks = Atomic<Int>(0)
    let writeNS = Atomic<UInt64>(0)
    let dispatchToRunNS = Atomic<UInt64>(0)
    let queueWaitNS = Atomic<UInt64>(0)
    let recordProcessWriteNS = Atomic<UInt64>(0)
    let finalizeNS = Atomic<UInt64>(0)
    let writerAllocations = Atomic<UInt64>(0)
    let writerAllocationBytes = Atomic<UInt64>(0)
    let writerAllocationObserverAvailable = Atomic<Int>(0)
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
    private let queue: StageCRecordQueue?
#if EPOCH_PAGES
    private let pendingEpoch: PendingEpochSnapshot?
    private let ownerID: ObjectIdentifier?
    private let expectedCounts: [UInt32]
    private let retainedEpochBufferBytes: Int
    private let heldForKillFixture: Bool
#endif

    init(directory: String, epoch: UInt32, expectedCounts: [UInt32]) {
        self.epoch = epoch
        let counters = StageCWriterCounters()
        let capacity = expectedCounts.reduce(0) { $0 + Int($1) }
        let queue = StageCRecordQueue(capacity: capacity)
        self.counters = counters
        self.queue = queue
#if EPOCH_PAGES
        pendingEpoch = nil; ownerID = nil
        self.expectedCounts = expectedCounts; retainedEpochBufferBytes = 0
        heldForKillFixture = false
#endif
        let dispatchSubmittedNS = nx_now()
        DispatchQueue.global(qos: .utility).async {
            let writerStartNS = nx_now()
            counters.dispatchToRunNS.store(writerStartNS >= dispatchSubmittedNS ?
                                           writerStartNS - dispatchSubmittedNS : 0,
                                           ordering: .releasing)
            nx_alloc_begin()
            do {
                let result = try StageCSnapshotWriter.run(queue, counters: counters,
                    directory: directory, epoch: epoch, expectedCounts: expectedCounts)
                let allocation = nx_alloc_end()
                counters.bytes.store(result.bytes, ordering: .releasing)
                counters.chunks.store(result.chunks, ordering: .releasing)
                counters.writeNS.store(result.writeNS, ordering: .releasing)
                counters.queueWaitNS.store(result.queueWaitNS, ordering: .releasing)
                counters.recordProcessWriteNS.store(result.recordProcessWriteNS, ordering: .releasing)
                counters.finalizeNS.store(result.finalizeNS, ordering: .releasing)
                counters.writerAllocations.store(allocation.calls, ordering: .releasing)
                counters.writerAllocationBytes.store(allocation.bytes, ordering: .releasing)
                counters.writerAllocationObserverAvailable.store(Int(allocation.available), ordering: .releasing)
            } catch {
                let allocation = nx_alloc_end()
                counters.writerAllocations.store(allocation.calls, ordering: .releasing)
                counters.writerAllocationBytes.store(allocation.bytes, ordering: .releasing)
                counters.writerAllocationObserverAvailable.store(Int(allocation.available), ordering: .releasing)
                counters.failed.store(1, ordering: .releasing)
            }
            counters.done.store(1, ordering: .releasing)
        }
    }

#if EPOCH_PAGES
    init(pagedDirectory directory: String, epoch: UInt32, expectedCounts: [UInt32],
         ownerID: ObjectIdentifier, retainedEpochBufferBytes: Int, heldForKillFixture: Bool) {
        self.epoch = epoch; self.expectedCounts = expectedCounts; self.ownerID = ownerID
        self.retainedEpochBufferBytes = retainedEpochBufferBytes
        self.heldForKillFixture = heldForKillFixture
        queue = nil
        let counters = StageCWriterCounters(), pending = PendingEpochSnapshot()
        self.counters = counters; pendingEpoch = pending
        let submitted = nx_now()
        DispatchQueue.global(qos: .utility).async {
            let running = nx_now()
            counters.dispatchToRunNS.store(running >= submitted ? running - submitted : 0, ordering: .releasing)
            nx_alloc_begin()
            do {
                if let consumed = try StageCSnapshotWriter.consumePending(pending, directory: directory, expectedCounts: expectedCounts) {
                    let result = consumed.0, waitNS = consumed.1
                    counters.bytes.store(result.bytes, ordering: .releasing)
                    counters.chunks.store(result.chunks, ordering: .releasing)
                    counters.writeNS.store(result.writeNS, ordering: .releasing)
                    counters.queueWaitNS.store(waitNS, ordering: .releasing)
                    counters.recordProcessWriteNS.store(result.recordProcessWriteNS, ordering: .releasing)
                    counters.finalizeNS.store(result.finalizeNS, ordering: .releasing)
                } else { counters.failed.store(1, ordering: .releasing) }
            } catch { counters.failed.store(1, ordering: .releasing) }
            let allocation = nx_alloc_end()
            counters.writerAllocations.store(allocation.calls, ordering: .releasing)
            counters.writerAllocationBytes.store(allocation.bytes, ordering: .releasing)
            counters.writerAllocationObserverAvailable.store(Int(allocation.available), ordering: .releasing)
            // Every temporary frozen value above has left scope before release.
            counters.done.store(1, ordering: .releasing)
        }
    }

    deinit { pendingEpoch?.cancelIfUnused() }
    func reserveBegin(owner: AnyObject, counts: [UInt32]) -> Bool {
        guard let pendingEpoch, ownerID == ObjectIdentifier(owner), expectedCounts == counts else { return false }
        return pendingEpoch.reserveBegin()
    }
    func publish(_ view: FrozenStageCSnapshot) {
        precondition(view.epoch == epoch)
        pendingEpoch!.publish(view, heldForKillFixture: heldForKillFixture)
    }
    func releaseKillFixtureWriter() { pendingEpoch?.releaseWriter() }
    func cancelUnused() {
        if let pendingEpoch { pendingEpoch.cancelIfUnused() }
        else if counters.done.load(ordering: .acquiring) == 0 { queue?.finish() }
    }
    func completionToken() -> StageCEpochCompletion? {
        guard pendingEpoch != nil, let ownerID, counters.done.load(ordering: .acquiring) == 1 else { return nil }
        return StageCEpochCompletion(epoch: epoch, ownerID: ownerID)
    }
#endif

    func emit(_ record: [UInt8]) {
        guard let queue else { preconditionFailure("immutable snapshot has no record queue") }
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

    func finish() { queue?.finish() }

    func resultIfDone() throws -> StageCSnapshotFileResult? {
        guard counters.done.load(ordering: .acquiring) == 1 else { return nil }
        guard counters.failed.load(ordering: .acquiring) == 0 else {
            throw ProbeError.invalid("stage C background snapshot writer failed")
        }
        let result = StageCSnapshotFileResult(bytes: counters.bytes.load(ordering: .acquiring),
            chunks: counters.chunks.load(ordering: .acquiring),
            writeNS: counters.writeNS.load(ordering: .acquiring),
            dispatchToRunNS: counters.dispatchToRunNS.load(ordering: .acquiring),
            queueWaitNS: counters.queueWaitNS.load(ordering: .acquiring),
            recordProcessWriteNS: counters.recordProcessWriteNS.load(ordering: .acquiring),
            finalizeNS: counters.finalizeNS.load(ordering: .acquiring),
            writerAllocations: counters.writerAllocations.load(ordering: .acquiring),
            writerAllocationBytes: counters.writerAllocationBytes.load(ordering: .acquiring),
            writerAllocationObserverAvailable: counters.writerAllocationObserverAvailable.load(ordering: .acquiring) == 1,
            peakQueuedBytes: counters.peak.load(ordering: .acquiring))
#if EPOCH_PAGES
        var decorated = result
        if pendingEpoch != nil {
            decorated.retainedEpochBufferBytes = retainedEpochBufferBytes
            decorated.snapshotSource = "immutable_epoch_pages"
        }
        return decorated
#else
        return result
#endif
    }
}

enum StageCSnapshotWriter {
    static func parseRecord(_ record: [UInt8]) throws -> (StageCRecordKey, UInt32, Data) {
        guard record.count >= 16 else { throw ProbeError.corruption("stage C short record") }
        var r = StageCByteReader(bytes: record)
        let kind = try r.u16(), reserved = try r.u16(), index = try r.u32()
        let elements = try r.u32(), payloadBytes = Int(try r.u32())
        guard reserved == 0, kind <= 3, payloadBytes >= 0,
              record.count == 16 + payloadBytes else {
            throw ProbeError.corruption("stage C record header")
        }
        let digest = Snapshot.digestBytes(record, range: 16..<record.count)
        return (StageCRecordKey(kind: kind, index: index), elements, digest)
    }

    static func run(_ queue: StageCRecordQueue, counters: StageCWriterCounters,
                    directory: String, epoch: UInt32,
                    expectedCounts: [UInt32]) throws -> StageCSnapshotFileResult {
        guard expectedCounts.count == 4, expectedCounts[0] == 1 else {
            throw ProbeError.invalid("stage C expected record counts")
        }
        let start = nx_now()
        let tmp = directory + "/snapshot-\(epoch).tmp"
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
        var queueWaitNS: UInt64 = 0
        var recordProcessWriteNS: UInt64 = 0

        while true {
            let waitStart = nx_now()
            guard let record = queue.waitAndPop() else {
                queueWaitNS &+= nx_now() - waitStart
                break
            }
            queueWaitNS &+= nx_now() - waitStart
            let recordStart = nx_now()
            let parsed = try parseRecord(record)
            let key = parsed.0
            guard key.kind < 4, key.index < expectedCounts[Int(key.kind)],
                  digests[key] == nil else {
                throw ProbeError.corruption("stage C duplicate/out-of-range record")
            }
            digests[key] = parsed.2
            counts[Int(key.kind)] += 1
            if key.kind > 0 {
                let split = max(16, record.count / 2)
                try Snapshot.writeRecord(record, descriptor: handle.fileDescriptor, range: 0..<split)
                nx_kill_point("c.k3.mid_record")
                try Snapshot.writeRecord(record, descriptor: handle.fileDescriptor, range: split..<record.count)
            } else {
                try Snapshot.writeRecord(record, descriptor: handle.fileDescriptor, range: 0..<record.count)
            }
            try handle.write(contentsOf: parsed.2)
            bytesWritten += UInt64(record.count + parsed.2.count)
            _ = counters.queued.subtract(record.count + parsed.2.count, ordering: .relaxed)
            recordProcessWriteNS &+= nx_now() - recordStart
        }

        guard counts == expectedCounts else { throw ProbeError.corruption("stage C missing record") }
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
        return try finalize(handle: handle, directory: directory, epoch: epoch, counts: counts,
                            canonical: canonical, bytesWritten: bytesWritten, start: start,
                            queueWaitNS: queueWaitNS, recordProcessWriteNS: recordProcessWriteNS,
                            peakQueuedBytes: counters.peak.load(ordering: .relaxed))
    }

    static func finalize(handle: FileHandle, directory: String, epoch: UInt32,
                         counts: [UInt32], canonical: Data, bytesWritten: UInt64,
                         start: UInt64, queueWaitNS: UInt64, recordProcessWriteNS: UInt64,
                         peakQueuedBytes: Int) throws -> StageCSnapshotFileResult {
        let finalizeStart = nx_now()
        let tmp = directory + "/snapshot-\(epoch).tmp"
        let final = directory + "/snapshot-\(epoch).bin"
        nx_kill_point("c.k4.before_footer")
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
        return StageCSnapshotFileResult(bytes: totalBytes, chunks: counts.reduce(0) { $0 + Int($1) },
            writeNS: nx_now() - start, dispatchToRunNS: 0, queueWaitNS: queueWaitNS,
            recordProcessWriteNS: recordProcessWriteNS, finalizeNS: nx_now() - finalizeStart,
            writerAllocations: 0, writerAllocationBytes: 0,
            writerAllocationObserverAvailable: false,
            peakQueuedBytes: peakQueuedBytes)
    }
}

final class StageCState {
#if EPOCH_PAGES
    private let ownerID: ObjectIdentifier
    let preparedOwnedBytes: Int
#endif
    let assetChunks: Int
    let nodeChunks: Int
    let groupChunks: Int
    let expectedCounts: [UInt32]
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
#if EPOCH_PAGES
        ownerID = ObjectIdentifier(world)
        world.stageCPreparePages()
        preparedOwnedBytes = world.ownedBytes
#endif
        assetChunks = (world.count + 255) >> 8
        nodeChunks = (world.wheel.capacity + 511) >> 9
        groupChunks = (world.groupAmounts.count + 2047) >> 11
        expectedCounts = [1, UInt32(assetChunks), UInt32(nodeChunks), UInt32(groupChunks)]
        assetSaved = .init(repeating: 0, count: assetChunks)
        nodeSaved = .init(repeating: 0, count: nodeChunks)
        groupSaved = .init(repeating: 0, count: groupChunks)
    }
    init(world: HybridWorld) {
#if EPOCH_PAGES
        ownerID = ObjectIdentifier(world)
        world.stageCPreparePages()
        preparedOwnedBytes = world.ownedBytes
#endif
        assetChunks = (world.count + 255) >> 8
        nodeChunks = (world.wheel.capacity + 511) >> 9
        groupChunks = (world.groupAmounts.count + 2047) >> 11
        expectedCounts = [1, UInt32(assetChunks), UInt32(nodeChunks), UInt32(groupChunks)]
        assetSaved = .init(repeating: 0, count: assetChunks)
        nodeSaved = .init(repeating: 0, count: nodeChunks)
        groupSaved = .init(repeating: 0, count: groupChunks)
    }

    var totalChunks: Int { assetChunks + nodeChunks + groupChunks }
    var inFlight: Bool { sink != nil }

    func prepareSink(directory: String, epoch: UInt32, heldForKillFixture: Bool = false) -> SnapshotSink {
#if EPOCH_PAGES
        return SnapshotSink(pagedDirectory: directory, epoch: epoch, expectedCounts: expectedCounts,
                            ownerID: ownerID, retainedEpochBufferBytes: preparedOwnedBytes,
                            heldForKillFixture: heldForKillFixture)
#else
        return SnapshotSink(directory: directory, epoch: epoch, expectedCounts: expectedCounts)
#endif
    }

    func begin(world: SwiftWorld, preparedSink: SnapshotSink) throws {
#if EPOCH_PAGES
        guard ownerID == ObjectIdentifier(world), sink == nil, !capturing, preparedSink.epoch > epoch,
              world.stageCCanFreezePages(preparedSink.epoch), preparedSink.reserveBegin(owner: world, counts: expectedCounts) else {
            preparedSink.cancelUnused()
            throw ProbeError.invalid("stage C frozen save owner/pool/epoch")
        }
#endif
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
#if EPOCH_PAGES
        let frozen = world.stageCFreezePages(epoch)
        nx_kill_point("c.k1.after_begin")
        preparedSink.publish(frozen)
#else
        preparedSink.emit(Snapshot.controlRecord(world))
        nx_kill_point("c.k1.after_begin")
#endif
    }
    func begin(world: HybridWorld, preparedSink: SnapshotSink) throws {
#if EPOCH_PAGES
        guard ownerID == ObjectIdentifier(world), sink == nil, !capturing, preparedSink.epoch > epoch,
              world.stageCCanFreezePages(preparedSink.epoch), preparedSink.reserveBegin(owner: world, counts: expectedCounts) else {
            preparedSink.cancelUnused()
            throw ProbeError.invalid("stage C frozen save owner/pool/epoch")
        }
#endif
        guard sink == nil, !capturing, preparedSink.epoch > epoch else {
            throw ProbeError.invalid("stage C save already active/epoch")
        }
        epoch=preparedSink.epoch;sink=preparedSink;capturing=true;serviceCursor=0
        barrierEmits=0;barrierBytes=0;barrierNS=0;lastResult=nil
#if EPOCH_PAGES
        let frozen = world.stageCFreezePages(epoch)
        nx_kill_point("c.k1.after_begin")
        preparedSink.publish(frozen)
#else
        preparedSink.emit(Snapshot.controlRecord(world))
        nx_kill_point("c.k1.after_begin")
#endif
    }

    @inline(__always) func willWriteAsset(_ world: SwiftWorld, index: Int) {
#if EPOCH_PAGES
        guard capturing && world.stageCNeedsAssetCopy(index) else { return }
        let start = nx_now(), bytes = world.stageCCloneAsset(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
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
#endif
    }

    @inline(__always) func willWriteNode(_ wheel: TimingWheel, index: Int) {
#if EPOCH_PAGES
        guard capturing && wheel.stageCNeedsNodeCopy(index) else { return }
        let start = nx_now(), bytes = wheel.stageCClonePage(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
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
#endif
    }

    @inline(__always) func willWriteGroup(_ world: SwiftWorld, index: Int) {
#if EPOCH_PAGES
        guard capturing && world.stageCNeedsGroupCopy(index) else { return }
        let start = nx_now(), bytes = world.stageCCloneGroup(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
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
#endif
    }
    @inline(__always) func willWriteAsset(_ world: HybridWorld, index: Int) {
#if EPOCH_PAGES
        guard capturing && world.stageCNeedsAssetCopy(index) else { return }
        let start = nx_now(), bytes = world.stageCCloneAsset(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
        guard capturing else { return }
        let chunk=index>>8
        if assetSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.assetRecord(world,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            assetSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#endif
    }
    @inline(__always) func willWriteNode(_ wheel: HybridTimingWheel, index: Int) {
#if EPOCH_PAGES
        guard capturing && wheel.stageCNeedsNodeCopy(index) else { return }
        let start = nx_now(), bytes = wheel.stageCClonePage(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
        guard capturing else { return }
        let chunk=index>>9
        if nodeSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.nodeRecord(wheel,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            nodeSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#endif
    }
    @inline(__always) func willWriteGroup(_ world: HybridWorld, index: Int) {
#if EPOCH_PAGES
        guard capturing && world.stageCNeedsGroupCopy(index) else { return }
        let start = nx_now(), bytes = world.stageCCloneGroup(index)
        if bytes > 0 {
            barrierNS += nx_now() - start; barrierBytes += bytes; barrierEmits += 1
            if barrierEmits == 1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#else
        guard capturing else { return }
        let chunk=index>>11
        if groupSaved[chunk] != epoch, let sink {
            let start=nx_now();let record=Snapshot.groupRecord(world,chunk:chunk);sink.emit(record)
            barrierNS += nx_now()-start;barrierBytes += record.count+32
            groupSaved[chunk]=epoch;barrierEmits += 1
            if barrierEmits==1 { nx_kill_point("c.k2.after_first_barrier") }
        }
#endif
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
#if EPOCH_PAGES
        guard let currentSink = sink else { return }
        do {
            if let result = try currentSink.resultIfDone() {
                guard let completion = currentSink.completionToken() else { throw ProbeError.invariant("missing epoch completion") }
                world.stageCReleasePages(completion)
                capturing = false; serviceCursor = totalChunks; lastResult = result; sink = nil
            }
        } catch {
            if capturing, let completion = currentSink.completionToken() { world.stageCReleasePages(completion); capturing = false }
            // Keep the failed sink in flight; a failed save requires recovery.
            throw error
        }
#else
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
#endif
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
#if EPOCH_PAGES
        guard let currentSink = sink else { return }
        do {
            if let result = try currentSink.resultIfDone() {
                guard let completion = currentSink.completionToken() else { throw ProbeError.invariant("missing epoch completion") }
                world.stageCReleasePages(completion)
                capturing = false; serviceCursor = totalChunks; lastResult = result; sink = nil
            }
        } catch {
            if capturing, let completion = currentSink.completionToken() { world.stageCReleasePages(completion); capturing = false }
            // Keep the failed sink in flight; a failed save requires recovery.
            throw error
        }
#else
        guard sink != nil else { return }
        if capturing {
            let deadline=nx_now() &+ budgetNS
            while serviceCursor<totalChunks && nx_now()<deadline {
                emitCanonicalIfUnsaved(world,canonical:serviceCursor);serviceCursor += 1
            }
            if serviceCursor==totalChunks { sink?.finish();capturing=false }
        }
        if !capturing,let result=try sink?.resultIfDone() { lastResult=result;sink=nil }
#endif
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
