#if BOUNDED_EPOCH_MICRO
import Foundation
import ProbePlatform
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Disposable H-cold ownership micro. This file is copied into a temporary
// package by prepare-bounded-ownership-study.py. It is never a runtime input.
private let boundedPageAssets = 256
private let boundedBytesPerAsset = 20
private let boundedFullPageWords = boundedPageAssets * boundedBytesPerAsset / 8

private struct BoundedColdRecord: Equatable, Sendable {
    var entity: UInt32
    var policy: UInt32
    var origin: UInt32
    var departure: UInt64

    static func fixture(_ index: Int) -> Self {
        Self(entity: UInt32(index & 31), policy: UInt32(7 + index % 101),
             origin: UInt32(1 + index % 17), departure: UInt64(300 + index * 3))
    }

    mutating func apply(stamp: UInt32) {
        entity = (entity &+ stamp) & 31
        policy ^= stamp &* 0x9e37
        origin = 1 &+ ((origin &+ stamp) % 65_521)
        departure &+= UInt64(stamp) * 17 + 1
    }
}

private enum BoundedWordCodec {
    @inline(__always) static func get(_ words: ContiguousArray<UInt64>, offset: Int,
                                      width: Int) -> UInt64 {
        let index = offset >> 3, shift = (offset & 7) << 3
        let bits = width << 3
        let mask = bits == 64 ? UInt64.max : (UInt64(1) << bits) - 1
        var value = words[index] >> shift
        if shift + bits > 64 { value |= words[index + 1] << (64 - shift) }
        return value & mask
    }

    @inline(__always) static func put(_ value: UInt64, offset: Int, width: Int,
                                      into words: inout ContiguousArray<UInt64>) {
        let index = offset >> 3, shift = (offset & 7) << 3
        let bits = width << 3
        let mask = bits == 64 ? UInt64.max : (UInt64(1) << bits) - 1
        words[index] = (words[index] & ~(mask << shift)) | ((value & mask) << shift)
        if shift + bits > 64 {
            let highMask = mask >> (64 - shift)
            words[index + 1] = (words[index + 1] & ~highMask) | ((value & mask) >> (64 - shift))
        }
    }

    @inline(__always) static func readRecord(_ words: ContiguousArray<UInt64>, elements: Int,
                                              index: Int) -> BoundedColdRecord {
        BoundedColdRecord(
            entity: UInt32(truncatingIfNeeded: get(words, offset: index * 4, width: 4)),
            policy: UInt32(truncatingIfNeeded: get(words, offset: elements * 4 + index * 4, width: 4)),
            origin: UInt32(truncatingIfNeeded: get(words, offset: elements * 8 + index * 4, width: 4)),
            departure: get(words, offset: elements * 12 + index * 8, width: 8))
    }

    @inline(__always) static func writeRecord(_ value: BoundedColdRecord,
                                               into words: inout ContiguousArray<UInt64>,
                                               elements: Int, index: Int) {
        put(UInt64(value.entity), offset: index * 4, width: 4, into: &words)
        put(UInt64(value.policy), offset: elements * 4 + index * 4, width: 4, into: &words)
        put(UInt64(value.origin), offset: elements * 8 + index * 4, width: 4, into: &words)
        put(value.departure, offset: elements * 12 + index * 8, width: 8, into: &words)
    }
}

private final class BoundedColdPage: @unchecked Sendable {
    let serial: UInt32
    var words: ContiguousArray<UInt64>

    init(serial: UInt32, records: ArraySlice<BoundedColdRecord>) {
        self.serial = serial
        words = []
        words.reserveCapacity(boundedFullPageWords)
        let wordCount = (records.count * boundedBytesPerAsset + 7) >> 3
        for _ in 0..<wordCount { words.append(0) }
        for (local, value) in records.enumerated() {
            BoundedWordCodec.writeRecord(value, into: &words, elements: records.count, index: local)
        }
    }

    init(spareSerial: UInt32) {
        serial = spareSerial
        words = []
        words.reserveCapacity(boundedFullPageWords)
    }
}

// One writer-owned scratch record and one sequential file. No record array or
// whole-snapshot byte image is retained while prefix credit is published.
private final class BoundedWriterSink: @unchecked Sendable {
    private var handle: FileHandle?
    var scratch: [UInt8] = []
    private(set) var records = 0
    private(set) var bytesWritten = 0
    var buildNS: UInt64 = 0
    private(set) var writeNS: UInt64 = 0
    let path: String

    init(path: String) throws {
        self.path = path
        scratch.reserveCapacity(16 + boundedPageAssets * boundedBytesPerAsset)
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw ProbeError.invalid("bounded writer file creation")
        }
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }

    func writeScratch() throws {
        guard let handle else { throw ProbeError.invalid("bounded writer closed") }
        let start = nx_now()
        try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<scratch.count)
        writeNS &+= nx_now() - start
        bytesWritten += scratch.count
        records += 1
    }

    func finish() throws {
        guard let handle else { return }
        let start = nx_now()
        try handle.synchronize()
        try handle.close()
        writeNS &+= nx_now() - start
        self.handle = nil
    }

    func readFinishedBytes() throws -> [UInt8] {
        guard handle == nil else { throw ProbeError.invalid("bounded writer read before close") }
        return [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    }
}

private struct BoundedOwnerToken: Equatable, Sendable {
    let owner: UInt32
    let buffer: UInt32
    let epoch: UInt32
}

private enum BoundedMutationResult: String, Sendable {
    case accepted
    case gateBusy
    case invalidToken
    case invalidAsset
    case writerReading
    case capacity
    case notPublished
}

private enum BoundedTerminal: UInt32, Sendable {
    case none = 0
    case success = 1
    case failed = 2
    case cancelled = 3
}

private enum BoundedPhase: UInt8, Sendable {
    case idle = 0
    case reserved = 1
    case published = 2
    case terminal = 3
}

private struct BoundedSlot: Sendable {
    var buffer: BoundedColdPage?
    var claimedPage: Int32 = -1
    var returnedPage: Int32 = -1
    var ready = true
    var reuseCount: UInt32 = 0
}

private struct BoundedServiceResult: Sendable {
    let valid: Bool
    let credits: Int
    let prefix: Int
}

private final class BoundedColdStore: @unchecked Sendable {
    // 0 free, 1 owner. 2 writer. The owner attempts once and never waits.
    private let gate = Atomic<UInt8>(0)
    private let cursor = Atomic<UInt64>(0)
    private let terminal = Atomic<UInt64>(0)
    private var live: ContiguousArray<BoundedColdPage> = []
    private var snapshot: ContiguousArray<BoundedColdPage?>
    private var slots: ContiguousArray<BoundedSlot> = []
    private var pageToSlot: ContiguousArray<Int32>
    private var commandPages: ContiguousArray<Int32>
    private var commandSlots: ContiguousArray<Int32>
    private var token: BoundedOwnerToken? = nil
    private var phase = BoundedPhase.idle
    private var readingPage: Int32 = -1
    private var writerPoisoned = false
    private(set) var epoch: UInt32 = 0
    private(set) var controlVersion: UInt64 = 0
    private(set) var walRecords: UInt64 = 0
    private(set) var successfulCommits: UInt64 = 0
    private(set) var failedSaves: UInt64 = 0
    private(set) var cancelledSaves: UInt64 = 0
    private(set) var creditedBuffers: UInt64 = 0
    let count: Int
    let pageCount: Int
    let slotCount: Int

    init(records: [BoundedColdRecord], slots requestedSlots: Int, epochSeed: UInt32 = 0) {
        precondition(!records.isEmpty && requestedSlots > 0)
        count = records.count
        pageCount = (records.count + boundedPageAssets - 1) / boundedPageAssets
        slotCount = requestedSlots
        epoch = epochSeed
        snapshot = .init(repeating: nil, count: pageCount)
        pageToSlot = .init(repeating: -1, count: pageCount)
        commandPages = .init(repeating: -1, count: max(8, requestedSlots + 1))
        commandSlots = .init(repeating: -1, count: max(8, requestedSlots + 1))
        live.reserveCapacity(pageCount)
        var serial: UInt32 = 1
        for lower in stride(from: 0, to: records.count, by: boundedPageAssets) {
            let upper = min(lower + boundedPageAssets, records.count)
            live.append(BoundedColdPage(serial: serial, records: records[lower..<upper]))
            serial &+= 1
        }
        self.slots.reserveCapacity(requestedSlots)
        for _ in 0..<requestedSlots {
            self.slots.append(BoundedSlot(buffer: BoundedColdPage(spareSerial: serial)))
            serial &+= 1
        }
    }

    @inline(__always) private func packed(_ epoch: UInt32, _ value: Int) -> UInt64 {
        (UInt64(epoch) << 32) | UInt64(UInt32(value))
    }

    @inline(__always) private func ownerEnter() -> Bool {
        gate.compareExchange(expected: 0, desired: 1,
                             ordering: .acquiringAndReleasing).exchanged
    }

    @inline(__always) private func ownerLeave() { gate.store(0, ordering: .releasing) }

    @inline(__always) private func writerEnter() -> Bool {
        let deadline = nx_now() &+ 100_000_000
        repeat {
            if gate.compareExchange(expected: 0, desired: 2,
                                    ordering: .acquiringAndReleasing).exchanged { return true }
            _ = sched_yield()
        } while nx_now() < deadline
        return false
    }

    // Once a writer has published a page-local alias through readingPage it
    // owns a cleanup obligation. Owner critical sections contain no waits or
    // I/O, so the writer must reacquire rather than abandon a wedged alias.
    @inline(__always) private func writerReenterRequired() {
        while !gate.compareExchange(expected: 0, desired: 2,
                                    ordering: .acquiringAndReleasing).exchanged {
            _ = sched_yield()
        }
    }

    @inline(__always) private func writerLeave() { gate.store(0, ordering: .releasing) }

    // Test-only deterministic holder for the owner's try-once/no-wait path.
    func holdWriterGate(entered: DispatchSemaphore, release: DispatchSemaphore) -> Bool {
        guard writerEnter() else { return false }
        entered.signal()
        release.wait()
        writerLeave()
        return true
    }

    @inline(__always) private func matches(_ candidate: BoundedOwnerToken) -> Bool {
        token == candidate
    }

    @inline(__always) private func reserveLocked(owner: UInt32,
                                                 buffer: UInt32) -> BoundedOwnerToken? {
        guard phase == .idle, epoch < UInt32.max else { return nil }
        guard snapshot.allSatisfy({ $0 == nil }), pageToSlot.allSatisfy({ $0 == -1 }),
              slots.allSatisfy({ $0.buffer != nil && $0.ready && $0.claimedPage == -1 }) else { return nil }
        epoch &+= 1
        let next = BoundedOwnerToken(owner: owner, buffer: buffer, epoch: epoch)
        token = next
        phase = .reserved
        readingPage = -1
        writerPoisoned = false
        cursor.store(packed(epoch, 0), ordering: .releasing)
        terminal.store(packed(epoch, 0), ordering: .releasing)
        return next
    }

    func reserve(owner: UInt32, buffer: UInt32) -> BoundedOwnerToken? {
        guard ownerEnter() else { return nil }
        defer { ownerLeave() }
        return reserveLocked(owner: owner, buffer: buffer)
    }

    @inline(__always) private func publishLocked(_ candidate: BoundedOwnerToken) -> Bool {
        guard phase == .reserved, matches(candidate) else { return false }
        for page in 0..<pageCount { snapshot[page] = live[page] }
        phase = .published
        return true
    }

    func begin(owner: UInt32, buffer: UInt32) -> BoundedOwnerToken? {
        guard ownerEnter() else { return nil }
        defer { ownerLeave() }
        guard let value = reserveLocked(owner: owner, buffer: buffer) else { return nil }
        precondition(publishLocked(value))
        return value
    }

    func cancelReserved(_ candidate: BoundedOwnerToken) -> Bool {
        guard ownerEnter() else { return false }
        guard phase == .reserved, matches(candidate) else { ownerLeave(); return false }
        phase = .terminal
        ownerLeave()
        terminal.store(packed(candidate.epoch, Int(BoundedTerminal.cancelled.rawValue)), ordering: .releasing)
        return true
    }

    @inline(__always) private func cursorPrefix(_ candidate: BoundedOwnerToken) -> Int? {
        let observed = cursor.load(ordering: .acquiring)
        guard UInt32(truncatingIfNeeded: observed >> 32) == candidate.epoch else { return nil }
        return Int(UInt32(truncatingIfNeeded: observed))
    }

    func mutate(_ assets: [Int], stamp: UInt32,
                token candidate: BoundedOwnerToken) -> BoundedMutationResult {
        guard ownerEnter() else { return .gateBusy }
        defer { ownerLeave() }
        guard phase == .published else { return .notPublished }
        guard matches(candidate), let prefix = cursorPrefix(candidate) else { return .invalidToken }
        guard !assets.isEmpty, assets.count <= commandPages.count,
              assets.allSatisfy({ $0 >= 0 && $0 < count }) else { return .invalidAsset }

        var distinct = 0
        for asset in assets {
            let page = Int32(asset / boundedPageAssets)
            var duplicate = false
            for index in 0..<distinct where commandPages[index] == page { duplicate = true }
            if !duplicate { commandPages[distinct] = page; distinct += 1 }
        }

        var needed = 0
        for index in 0..<distinct {
            let page = Int(commandPages[index])
            if pageToSlot[page] >= 0 || page < prefix { continue }
            if readingPage == Int32(page) { return .writerReading }
            commandPages[needed] = Int32(page)
            needed += 1
        }
        var available = 0
        if needed > 0 {
            for slot in slots.indices where slots[slot].ready && slots[slot].buffer != nil {
                commandSlots[available] = Int32(slot)
                available += 1
                if available == needed { break }
            }
        }
        guard available >= needed else { return .capacity }

        // The complete command is now reserved. No live/control/WAL byte was
        // touched before this point, and the remaining operations cannot fail.
        for index in 0..<needed {
            let page = Int(commandPages[index]), slot = Int(commandSlots[index])
            let source = live[page]
            let replacement = slots[slot].buffer!
            replacement.words.removeAll(keepingCapacity: true)
            for word in source.words { replacement.words.append(word) }
            slots[slot].buffer = nil
            slots[slot].ready = false
            slots[slot].claimedPage = Int32(page)
            slots[slot].returnedPage = -1
            slots[slot].reuseCount &+= 1
            live[page] = replacement
            pageToSlot[page] = Int32(slot)
        }
        for asset in assets {
            let page = asset / boundedPageAssets
            let local = asset & (boundedPageAssets - 1)
            let elements = min(boundedPageAssets, count - page * boundedPageAssets)
            var value = BoundedWordCodec.readRecord(live[page].words, elements: elements, index: local)
            value.apply(stamp: stamp)
            BoundedWordCodec.writeRecord(value, into: &live[page].words,
                                         elements: elements, index: local)
        }
        controlVersion &+= 1
        walRecords &+= 1
        return .accepted
    }

    func service(_ candidate: BoundedOwnerToken) -> BoundedServiceResult {
        guard ownerEnter() else { return BoundedServiceResult(valid: false, credits: 0, prefix: -1) }
        defer { ownerLeave() }
        guard phase == .published, matches(candidate), let prefix = cursorPrefix(candidate) else {
            return BoundedServiceResult(valid: false, credits: 0, prefix: -1)
        }
        var credits = 0
        for slot in slots.indices {
            let returned = Int(slots[slot].returnedPage)
            if !slots[slot].ready && slots[slot].buffer != nil && returned >= 0 && returned < prefix {
                slots[slot].ready = true
                slots[slot].claimedPage = -1
                slots[slot].returnedPage = -1
                pageToSlot[returned] = -1
                credits += 1
            }
        }
        creditedBuffers &+= UInt64(credits)
        return BoundedServiceResult(valid: true, credits: credits, prefix: prefix)
    }

    @inline(never) private func fillAndHoldSnapshotRecord(page: Int, into record: inout [UInt8],
                                                          entered: DispatchSemaphore?,
                                                          release: DispatchSemaphore?) -> UInt64 {
        let source = snapshot[page]!
        let elements = min(boundedPageAssets, count - page * boundedPageAssets)
        let payloadBytes = elements * boundedBytesPerAsset
        let buildStart = nx_now()
        record.removeAll(keepingCapacity: true)
        Snapshot.appendLE(UInt16(1), into: &record)
        Snapshot.appendLE(UInt16(0), into: &record)
        Snapshot.appendLE(UInt32(page), into: &record)
        Snapshot.appendLE(UInt32(elements), into: &record)
        Snapshot.appendLE(UInt32(payloadBytes), into: &record)
        for word in source.words { Snapshot.appendLE(word, into: &record) }
        let excess = record.count - 16 - payloadBytes
        precondition(excess >= 0 && excess < 8)
        if excess > 0 { record.removeLast(excess) }
        let buildNS = nx_now() - buildStart
        entered?.signal()
        release?.wait()
        withExtendedLifetime(source) {}
        return buildNS
    }

    // This frame is the only transfer from the writer directory into a return
    // slot. It must finish before cursor.store(releasing) makes credit visible.
    @inline(never) private func retireSnapshotPage(_ page: Int) {
        let old = snapshot[page]!
        let slot = Int(pageToSlot[page])
        snapshot[page] = nil
        if slot >= 0 {
            precondition(slots[slot].buffer == nil && !slots[slot].ready)
            slots[slot].buffer = old
            slots[slot].returnedPage = Int32(page)
        }
    }

    func writerRecord(_ candidate: BoundedOwnerToken, page: Int, sink: BoundedWriterSink,
                      entered: DispatchSemaphore? = nil, release: DispatchSemaphore? = nil,
                      injectFailure: Bool = false) throws -> Bool {
        guard writerEnter() else { return false }
        guard phase == .published, matches(candidate), readingPage == -1, !writerPoisoned,
              let prefix = cursorPrefix(candidate), prefix == page,
              page >= 0, page < pageCount, snapshot[page] != nil else {
            writerLeave(); return false
        }
        readingPage = Int32(page)
        writerLeave()

        // The non-inlined helper owns the page-local alias through the test
        // barrier and returns before any file byte, retirement, or prefix.
        let recordBuildNS = fillAndHoldSnapshotRecord(page: page, into: &sink.scratch,
                                                       entered: entered, release: release)
        sink.buildNS &+= recordBuildNS
        if injectFailure {
            writerReenterRequired()
            precondition(readingPage == Int32(page))
            readingPage = -1
            writerPoisoned = true
            writerLeave()
            throw ProbeError.invalid("bounded injected writer failure")
        }
        do {
            try sink.writeScratch()
        } catch {
            writerReenterRequired()
            precondition(readingPage == Int32(page))
            readingPage = -1
            writerPoisoned = true
            writerLeave()
            throw error
        }

        writerReenterRequired()
        precondition(phase == .published && matches(candidate) && readingPage == Int32(page))
        retireSnapshotPage(page)
        // retireSnapshotPage's frame and page-local alias are gone here.
        cursor.store(packed(candidate.epoch, page + 1), ordering: .releasing)
        readingPage = -1
        writerLeave()
        return true
    }

    @inline(never) private func dropRemainingSnapshotAliases() {
        for page in 0..<pageCount where snapshot[page] != nil {
            let old = snapshot[page]!
            snapshot[page] = nil
            let slot = Int(pageToSlot[page])
            if slot >= 0 {
                precondition(slots[slot].buffer == nil && !slots[slot].ready)
                slots[slot].buffer = old
                slots[slot].returnedPage = Int32(page)
            }
        }
    }

    func finish(_ candidate: BoundedOwnerToken, outcome: BoundedTerminal) -> Bool {
        guard outcome != .none else { return false }
        guard writerEnter() else { return false }
        guard phase == .published, matches(candidate), readingPage == -1 else {
            writerLeave(); return false
        }
        guard !writerPoisoned || outcome == .failed else {
            writerLeave(); return false
        }
        if outcome == .success {
            guard cursorPrefix(candidate) == pageCount, snapshot.allSatisfy({ $0 == nil }) else {
                writerLeave(); return false
            }
        } else {
            dropRemainingSnapshotAliases()
        }
        phase = .terminal
        writerLeave()
        // All cleanup locals ended before the terminal release. A failure or
        // cancellation grants memory reclamation only, never save success.
        terminal.store(packed(candidate.epoch, Int(outcome.rawValue)), ordering: .releasing)
        return true
    }

    func serviceTerminal(_ candidate: BoundedOwnerToken) -> BoundedTerminal? {
        let observed = terminal.load(ordering: .acquiring)
        guard UInt32(truncatingIfNeeded: observed >> 32) == candidate.epoch,
              let outcome = BoundedTerminal(rawValue: UInt32(truncatingIfNeeded: observed)),
              outcome != .none else { return nil }
        guard ownerEnter() else { return nil }
        defer { ownerLeave() }
        guard phase == .terminal, matches(candidate) else { return nil }
        for slot in slots.indices where !slots[slot].ready {
            guard let _ = slots[slot].buffer else { return nil }
            let returned = Int(slots[slot].returnedPage)
            if returned >= 0 { pageToSlot[returned] = -1 }
            slots[slot].ready = true
            slots[slot].claimedPage = -1
            slots[slot].returnedPage = -1
            creditedBuffers &+= 1
        }
        guard snapshot.allSatisfy({ $0 == nil }), pageToSlot.allSatisfy({ $0 == -1 }),
              slots.allSatisfy({ $0.buffer != nil && $0.ready }) else { return nil }
        if outcome == .success { successfulCommits &+= 1 }
        else if outcome == .failed { failedSaves &+= 1 }
        else { cancelledSaves &+= 1 }
        token = nil
        phase = .idle
        return outcome
    }

    func liveBytes() -> [UInt8]? {
        guard ownerEnter() else { return nil }
        defer { ownerLeave() }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count * boundedBytesPerAsset + pageCount * 16)
        for page in 0..<pageCount {
            let elements = min(boundedPageAssets, count - page * boundedPageAssets)
            let payloadBytes = elements * boundedBytesPerAsset
            Snapshot.appendLE(UInt16(1), into: &bytes); Snapshot.appendLE(UInt16(0), into: &bytes)
            Snapshot.appendLE(UInt32(page), into: &bytes); Snapshot.appendLE(UInt32(elements), into: &bytes)
            Snapshot.appendLE(UInt32(payloadBytes), into: &bytes)
            let start = bytes.count
            for word in live[page].words { Snapshot.appendLE(word, into: &bytes) }
            let excess = bytes.count - start - payloadBytes
            if excess > 0 { bytes.removeLast(excess) }
        }
        return bytes
    }

    func debugState() -> [String: Any] {
        guard ownerEnter() else { return ["gateBusy": true] }
        defer { ownerLeave() }
        let observed = cursor.load(ordering: .acquiring)
        return [
            "phase": Int(phase.rawValue), "epoch": epoch,
            "prefix": Int(UInt32(truncatingIfNeeded: observed)),
            "readingPage": readingPage, "writerPoisoned": writerPoisoned,
            "controlVersion": controlVersion,
            "walRecords": walRecords, "successfulCommits": successfulCommits,
            "failedSaves": failedSaves, "cancelledSaves": cancelledSaves,
            "creditedBuffers": creditedBuffers,
            "slotReady": slots.map(\.ready), "slotReuse": slots.map(\.reuseCount),
            "slotSerial": slots.map { $0.buffer == nil ? NSNull() as Any : $0.buffer!.serial as Any },
            "liveSerial": live.map(\.serial),
            "liveWordCapacities": live.map { $0.words.capacity },
            "slotWordCapacities": slots.map {
                $0.buffer == nil ? NSNull() as Any : $0.buffer!.words.capacity as Any
            }
        ]
    }

    func ownedCapacityReport() -> [String: Any] {
        guard ownerEnter() else { return ["gateBusy": true] }
        defer { ownerLeave() }
        let livePayload = live.reduce(0) { $0 + $1.words.capacity * MemoryLayout<UInt64>.stride }
        let slotPayload = slots.reduce(0) { $0 + ($1.buffer?.words.capacity ?? 0) * MemoryLayout<UInt64>.stride }
        let refs = (live.capacity + snapshot.capacity) * MemoryLayout<BoundedColdPage?>.stride
        let maps = pageToSlot.capacity * MemoryLayout<Int32>.stride
        let records = slots.capacity * MemoryLayout<BoundedSlot>.stride
        let scratch = (commandPages.capacity + commandSlots.capacity) * MemoryLayout<Int32>.stride
        // Swift object/allocator headers are not introspectable here. Charge a
        // conservative fixed allowance per page wrapper plus store/atomic
        // controls; the artifact still labels physical footprint unmeasured.
        let pageWrapperCount = live.count + slots.count
        let pageWrapperAllowance = pageWrapperCount * 64
        let storeControlAllowance = 512
        let atomicControlAllowance = 192
        let tailElements = count - (pageCount - 1) * boundedPageAssets
        let declared = livePayload + slotPayload + refs + maps + records + scratch +
            pageWrapperAllowance + storeControlAllowance + atomicControlAllowance
        return ["livePayloadCapacityBytes": livePayload, "slotPayloadCapacityBytes": slotPayload,
                "directoryReferenceBytes": refs, "pageMapBytes": maps,
                "slotRecordBytes": records, "commandScratchBytes": scratch,
                "pageWrapperCount": pageWrapperCount,
                "pageWrapperAllowanceBytes": pageWrapperAllowance,
                "storeControlAllowanceBytes": storeControlAllowance,
                "atomicControlAllowanceBytes": atomicControlAllowance,
                "declaredBytesExcludingAllocatorHeaders": declared,
                "pageReferenceStride": MemoryLayout<BoundedColdPage?>.stride,
                "slotRecordStride": MemoryLayout<BoundedSlot>.stride,
                "tailElements": tailElements,
                "tailCanonicalBytes": tailElements * boundedBytesPerAsset,
                "tailPhysicalWordBytes": (tailElements * boundedBytesPerAsset + 7) / 8 * 8,
                "fullPageCapacityBytes": boundedFullPageWords * MemoryLayout<UInt64>.stride]
    }
}

private func boundedDigest(_ bytes: [UInt8]) -> String {
    let hash = Snapshot.hashBytes(bytes)
    precondition(hash.status == 0)
    return String(format: "%016llx%016llx%016llx%016llx", hash.a, hash.b, hash.c, hash.d)
}

private func boundedRead<T: FixedWidthInteger>(_ type: T.Type, _ bytes: [UInt8], _ offset: inout Int) throws -> T {
    guard offset + MemoryLayout<T>.size <= bytes.count else { throw ProbeError.corruption("bounded recovery truncation") }
    var value: T = 0
    for byte in 0..<MemoryLayout<T>.size {
        value |= T(truncatingIfNeeded: bytes[offset + byte]) << (byte * 8)
    }
    offset += MemoryLayout<T>.size
    return value
}

private func boundedOracleBytes(_ records: [BoundedColdRecord]) -> [UInt8] {
    var bytes: [UInt8] = []
    let pages = (records.count + boundedPageAssets - 1) / boundedPageAssets
    bytes.reserveCapacity(records.count * boundedBytesPerAsset + pages * 16)
    for page in 0..<pages {
        let lower = page * boundedPageAssets, upper = min(lower + boundedPageAssets, records.count)
        Snapshot.appendLE(UInt16(1), into: &bytes); Snapshot.appendLE(UInt16(0), into: &bytes)
        Snapshot.appendLE(UInt32(page), into: &bytes); Snapshot.appendLE(UInt32(upper - lower), into: &bytes)
        Snapshot.appendLE(UInt32((upper - lower) * boundedBytesPerAsset), into: &bytes)
        for index in lower..<upper { Snapshot.appendLE(records[index].entity, into: &bytes) }
        for index in lower..<upper { Snapshot.appendLE(records[index].policy, into: &bytes) }
        for index in lower..<upper { Snapshot.appendLE(records[index].origin, into: &bytes) }
        for index in lower..<upper { Snapshot.appendLE(records[index].departure, into: &bytes) }
    }
    return bytes
}

private func boundedRecover(_ bytes: [UInt8], count: Int) throws -> [String: Any] {
    let pages = (count + boundedPageAssets - 1) / boundedPageAssets
    var offset = 0
    var records = Array(repeating: BoundedColdRecord(entity: 0, policy: 0, origin: 0, departure: 0), count: count)
    var order: [Int] = []
    order.reserveCapacity(pages)
    for page in 0..<pages {
        let kind = try boundedRead(UInt16.self, bytes, &offset)
        let reserved = try boundedRead(UInt16.self, bytes, &offset)
        let index = try boundedRead(UInt32.self, bytes, &offset)
        let elements = Int(try boundedRead(UInt32.self, bytes, &offset))
        let payload = Int(try boundedRead(UInt32.self, bytes, &offset))
        let expected = min(boundedPageAssets, count - page * boundedPageAssets)
        guard kind == 1, reserved == 0, index == UInt32(page), elements == expected,
              payload == elements * boundedBytesPerAsset, offset + payload <= bytes.count else {
            throw ProbeError.corruption("bounded recovery record/order")
        }
        let start = offset, lower = page * boundedPageAssets
        for local in 0..<elements {
            var at = start + local * 4
            records[lower + local].entity = try boundedRead(UInt32.self, bytes, &at)
        }
        for local in 0..<elements {
            var at = start + elements * 4 + local * 4
            records[lower + local].policy = try boundedRead(UInt32.self, bytes, &at)
        }
        for local in 0..<elements {
            var at = start + elements * 8 + local * 4
            records[lower + local].origin = try boundedRead(UInt32.self, bytes, &at)
        }
        for local in 0..<elements {
            var at = start + elements * 12 + local * 8
            records[lower + local].departure = try boundedRead(UInt64.self, bytes, &at)
        }
        offset += payload
        order.append(page)
    }
    guard offset == bytes.count else { throw ProbeError.corruption("bounded recovery trailing bytes") }
    let rebuilt = boundedOracleBytes(records)
    return ["digest": boundedDigest(rebuilt), "byteExact": rebuilt == bytes,
            "orderExact": order == Array(0..<pages), "pages": pages]
}

private func boundedApply(_ assets: [Int], stamp: UInt32, to records: inout [BoundedColdRecord]) {
    for asset in assets { records[asset].apply(stamp: stamp) }
}

private func boundedObserved(_ value: UInt64, available: Bool) -> Any {
    available ? value as Any : NSNull()
}

private func boundedAllocationRow(_ label: String, elapsed: UInt64, allocation: NXRAlloc,
                                  policy: String) throws -> [String: Any] {
    let available = allocation.available == 1
    if policy == "zero" {
        try require(available && allocation.calls == 0 && allocation.bytes == 0,
                    "bounded \(label) release allocation")
    } else if policy == "observe" {
        try require(available, "bounded \(label) allocator unavailable")
    }
    return ["label": label, "ns": elapsed, "allocationAvailable": available,
            "allocations": boundedObserved(allocation.calls, available: available),
            "allocationBytes": boundedObserved(allocation.bytes, available: available)]
}

private func boundedRunWriter(_ store: BoundedColdStore, token: BoundedOwnerToken,
                              sink: BoundedWriterSink) throws -> (writerNS: UInt64, serviceNS: UInt64) {
    var writerNS: UInt64 = 0, serviceNS: UInt64 = 0
    for page in sink.records..<store.pageCount {
        let start = nx_now()
        guard try store.writerRecord(token, page: page, sink: sink) else {
            throw ProbeError.invariant("bounded writer canonical step")
        }
        writerNS &+= nx_now() - start
        let serviceStart = nx_now(), service = store.service(token)
        serviceNS &+= nx_now() - serviceStart
        try require(service.valid && service.prefix == page + 1, "bounded prefix service")
    }
    return (writerNS, serviceNS)
}

private func boundedMainEpochs(count: Int, slots: Int, policy: String,
                               allocations: inout [[String: Any]]) throws -> [String: Any] {
    var oracle = (0..<count).map(BoundedColdRecord.fixture)
    nx_alloc_begin(); let setupStart = nx_now()
    let store = BoundedColdStore(records: oracle, slots: slots)
    let setupNS = nx_now() - setupStart, setupAllocation = nx_alloc_end()
    if policy != "functional" {
        try require(setupAllocation.available == 1 && setupAllocation.calls > 0,
                    "bounded setup allocation observation")
    }
    let owner: UInt32 = 0x4e58524f, buffer: UInt32 = 0x434f4c44
    let initialMemory = store.ownedCapacityReport()
    var epochs: [[String: Any]] = []
    var partialReturnedSerial: UInt32? = nil
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("nxr-bounded-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }

    for epochNumber in 1...3 {
        let frozenOracle = boundedOracleBytes(oracle)
        let writerSetupStart = nx_now()
        let sink = try BoundedWriterSink(path: temporary.appendingPathComponent("epoch-\(epochNumber).bin").path)
        let writerSetupNS = nx_now() - writerSetupStart
        let runtimeStart = nx_now()
        var writerNS: UInt64 = 0, serviceNS: UInt64 = 0
        var writerAliasHeldDuringKPressure: Any = NSNull()
        var heldWriterWallNS: Any = NSNull()
        var kPressureOutcome: Any = NSNull()
        var ownerGateBusyNS: Any = NSNull()
        nx_alloc_begin(); let beginStart = nx_now()
        guard let token = store.begin(owner: owner, buffer: buffer) else {
            _ = nx_alloc_end(); throw ProbeError.invariant("bounded begin")
        }
        let beginNS = nx_now() - beginStart, beginAllocation = nx_alloc_end()
        allocations.append(try boundedAllocationRow("epoch\(epochNumber)-begin", elapsed: beginNS,
                                                     allocation: beginAllocation, policy: policy))
        try require(token.epoch == UInt32(epochNumber), "bounded epoch sequence")
        try require(store.begin(owner: owner, buffer: buffer) == nil, "bounded overlap reject")

        let wrongOwner = BoundedOwnerToken(owner: owner &+ 1, buffer: buffer, epoch: token.epoch)
        let wrongBuffer = BoundedOwnerToken(owner: owner, buffer: buffer &+ 1, epoch: token.epoch)
        let stale = BoundedOwnerToken(owner: owner, buffer: buffer, epoch: token.epoch &+ 1)
        let beforeForeign = store.liveBytes()!
        let foreignAssets = [0]
        for invalid in [wrongOwner, wrongBuffer, stale] {
            try require(store.mutate(foreignAssets, stamp: 1, token: invalid) == .invalidToken,
                        "bounded foreign mutation reject")
            try require(!store.service(invalid).valid,
                        "bounded foreign service reject")
            let invalidWriter = try store.writerRecord(invalid, page: 0, sink: sink)
            try require(!invalidWriter,
                        "bounded foreign writer reject")
            try require(!store.finish(invalid, outcome: .failed),
                        "bounded foreign terminal reject")
            try require(store.serviceTerminal(invalid) == nil,
                        "bounded foreign terminal service reject")
        }
        try require(sink.records == 0, "bounded foreign writer bytes unchanged")
        try require(store.liveBytes()! == beforeForeign, "bounded foreign bytes unchanged")

        if epochNumber == 1 {
            // First prove all-or-nothing reservation with no writer progress.
            let tooMany = slots == 1 ? [0, min(256, count - 1)] : [0, 256, 512]
            let before = store.liveBytes()!, stateBefore = store.debugState()
            nx_alloc_begin(); let rejectStart = nx_now()
            let rejected = store.mutate(tooMany, stamp: 101, token: token)
            let rejectNS = nx_now() - rejectStart, rejectAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch1-reserve-reject", elapsed: rejectNS,
                                                         allocation: rejectAllocation, policy: policy))
            try require(rejected == .capacity && store.liveBytes()! == before,
                        "bounded all-or-nothing capacity")
            let stateAfter = store.debugState()
            try require((stateBefore["controlVersion"] as? UInt64) == (stateAfter["controlVersion"] as? UInt64) &&
                        (stateBefore["walRecords"] as? UInt64) == (stateAfter["walRecords"] as? UInt64),
                        "bounded rejected control/WAL unchanged")

            let outOfOrder = try store.writerRecord(token, page: 1, sink: sink)
            try require(!outOfOrder, "bounded out-of-order writer reject")

            // Hold a real page-0 writer alias. While it is held, consume all K
            // buffers on other pages and prove K+1 rejection without progress.
            let writerEntered = DispatchSemaphore(value: 0), writerRelease = DispatchSemaphore(value: 0)
            let writerDone = DispatchSemaphore(value: 0), writerResult = Mutex<Bool?>(nil)
            let heldWriterStart = nx_now()
            DispatchQueue.global(qos: .utility).async {
                let written = (try? store.writerRecord(token, page: 0, sink: sink,
                                                       entered: writerEntered,
                                                       release: writerRelease)) ?? false
                writerResult.withLock { $0 = written }
                writerDone.signal()
            }
            try require(writerEntered.wait(timeout: .now() + 10) == .success,
                        "bounded real writer start barrier")
            writerAliasHeldDuringKPressure = true

            let acceptedAssets = slots == 1 ? [count - 1] : [256, 512]
            nx_alloc_begin(); let acceptStart = nx_now()
            let accepted = store.mutate(acceptedAssets, stamp: 11, token: token)
            let acceptNS = nx_now() - acceptStart, acceptAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch1-reserve-copy", elapsed: acceptNS,
                                                         allocation: acceptAllocation, policy: policy))
            try require(accepted == .accepted, "bounded first command")
            boundedApply(acceptedAssets, stamp: 11, to: &oracle)

            let nextPageAsset = slots == 1 ? 0 : 768
            let kPlusOneAssets = [nextPageAsset]
            let bytesBeforeK1 = store.liveBytes()!, stateBeforeK1 = store.debugState()
            nx_alloc_begin(); let kPressureStart = nx_now()
            let kPlusOne = store.mutate(kPlusOneAssets, stamp: 12, token: token)
            let kPressureNS = nx_now() - kPressureStart
            let kPressureAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch1-held-k-pressure-reject",
                                                         elapsed: kPressureNS,
                                                         allocation: kPressureAllocation,
                                                         policy: policy))
            let expectedKPlusOne: BoundedMutationResult = slots == 1 ? .writerReading : .capacity
            try require(kPlusOne == expectedKPlusOne, "bounded K plus one")
            kPressureOutcome = kPlusOne.rawValue
            try require(store.liveBytes()! == bytesBeforeK1, "bounded K plus one bytes")
            let stateAfterK1 = store.debugState()
            try require((stateBeforeK1["controlVersion"] as? UInt64) == (stateAfterK1["controlVersion"] as? UInt64) &&
                        (stateBeforeK1["walRecords"] as? UInt64) == (stateAfterK1["walRecords"] as? UInt64),
                        "bounded K plus one control/WAL")
            writerRelease.signal()
            try require(writerDone.wait(timeout: .now() + 10) == .success,
                        "bounded real writer release")
            try require(writerResult.withLock({ $0 }) == true,
                        "bounded real writer record")
            let heldWall = nx_now() - heldWriterStart
            heldWriterWallNS = heldWall
            writerNS &+= heldWall
            let duplicate = try store.writerRecord(token, page: 0, sink: sink)
            try require(!duplicate, "bounded duplicate writer reject")
            nx_alloc_begin(); let serviceStart = nx_now()
            let credit = store.service(token)
            let measuredServiceNS = nx_now() - serviceStart, serviceAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch1-prefix-service", elapsed: measuredServiceNS,
                                                         allocation: serviceAllocation, policy: policy))
            serviceNS &+= measuredServiceNS
            try require(credit.valid && credit.prefix == 1, "bounded first prefix")
            let pageOneStart = nx_now()
            try require(try store.writerRecord(token, page: 1, sink: sink),
                        "bounded page-one writer")
            writerNS &+= nx_now() - pageOneStart
            nx_alloc_begin(); let pageOneServiceStart = nx_now()
            let pageOneCredit = store.service(token)
            let pageOneServiceNS = nx_now() - pageOneServiceStart
            let pageOneServiceAllocation = nx_alloc_end()
            serviceNS &+= pageOneServiceNS
            allocations.append(try boundedAllocationRow("epoch1-prefix-credit-service",
                                                         elapsed: pageOneServiceNS,
                                                         allocation: pageOneServiceAllocation,
                                                         policy: policy))
            try require(pageOneCredit.valid && pageOneCredit.prefix == 2 &&
                        pageOneCredit.credits == 1, "bounded page-one credit")
            if slots == 2 {
                let retryAssets = [768]
                nx_alloc_begin(); let retryStart = nx_now()
                let retry = store.mutate(retryAssets, stamp: 13, token: token)
                let retryNS = nx_now() - retryStart, retryAllocation = nx_alloc_end()
                allocations.append(try boundedAllocationRow("epoch1-prefix-credit-reuse", elapsed: retryNS,
                                                             allocation: retryAllocation, policy: policy))
                try require(retry == .accepted, "bounded prefix retry")
                boundedApply(retryAssets, stamp: 13, to: &oracle)
            }
            let rest = try boundedRunWriter(store, token: token, sink: sink)
            writerNS &+= rest.writerNS; serviceNS &+= rest.serviceNS
        } else if epochNumber == 2 {
            let asset = 0
            let copyAssets = [asset]
            let beforeState = store.debugState()
            if slots == 1 {
                guard let serials = beforeState["slotSerial"] as? [Any],
                      let serial = serials.first as? UInt32 else {
                    throw ProbeError.invariant("bounded partial slot serial")
                }
                partialReturnedSerial = serial
            }
            nx_alloc_begin(); let copyStart = nx_now()
            let copied = store.mutate(copyAssets, stamp: 21, token: token)
            let copyNS = nx_now() - copyStart, copyAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch2-partial-to-full-copy", elapsed: copyNS,
                                                         allocation: copyAllocation, policy: policy))
            try require(copied == .accepted, "bounded epoch2 copy")
            boundedApply([asset], stamp: 21, to: &oracle)
            let rest = try boundedRunWriter(store, token: token, sink: sink)
            writerNS &+= rest.writerNS; serviceNS &+= rest.serviceNS
        } else {
            // Hold the metadata gate itself. The owner must try once, return
            // gateBusy promptly, allocate nothing and leave every byte unchanged.
            let gateBefore = store.liveBytes()!, gateStateBefore = store.debugState()
            let gateEntered = DispatchSemaphore(value: 0), gateRelease = DispatchSemaphore(value: 0)
            let gateDone = DispatchSemaphore(value: 0), gateResult = Mutex<Bool?>(nil)
            DispatchQueue.global(qos: .utility).async {
                let acquired = store.holdWriterGate(entered: gateEntered, release: gateRelease)
                gateResult.withLock { $0 = acquired }; gateDone.signal()
            }
            try require(gateEntered.wait(timeout: .now() + 10) == .success,
                        "bounded writer gate holder")
            let gateAssets = [0]
            nx_alloc_begin(); let gateBusyStart = nx_now()
            let gateBusy = store.mutate(gateAssets, stamp: 30, token: token)
            let gateBusyElapsed = nx_now() - gateBusyStart, gateBusyAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch3-owner-gate-busy-reject",
                                                         elapsed: gateBusyElapsed,
                                                         allocation: gateBusyAllocation, policy: policy))
            ownerGateBusyNS = gateBusyElapsed
            try require(gateBusy == .gateBusy && gateBusyElapsed < 50_000_000,
                        "bounded owner try-once no wait")
            gateRelease.signal()
            try require(gateDone.wait(timeout: .now() + 10) == .success &&
                        gateResult.withLock({ $0 }) == true,
                        "bounded writer gate release")
            let gateStateAfter = store.debugState()
            try require(store.liveBytes()! == gateBefore &&
                        (gateStateBefore["controlVersion"] as? UInt64) == (gateStateAfter["controlVersion"] as? UInt64) &&
                        (gateStateBefore["walRecords"] as? UInt64) == (gateStateAfter["walRecords"] as? UInt64),
                        "bounded gate busy unchanged")

            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            let result = Mutex<Bool?>(nil)
            let heldWriterStart = nx_now()
            DispatchQueue.global(qos: .utility).async {
                let written = (try? store.writerRecord(token, page: 0, sink: sink,
                                                       entered: entered, release: release)) ?? false
                result.withLock { $0 = written }
                done.signal()
            }
            try require(entered.wait(timeout: .now() + 10) == .success, "bounded held writer entered")
            let heldState = store.debugState()
            try require((heldState["prefix"] as? Int) == 0, "bounded held alias no prefix")
            let heldService = store.service(token)
            try require(heldService.valid && heldService.prefix == 0 && heldService.credits == 0,
                        "bounded held alias no credit")
            try require(store.mutate([0], stamp: 31, token: token) == .writerReading,
                        "bounded held shared page reject")
            release.signal()
            try require(done.wait(timeout: .now() + 10) == .success, "bounded held writer done")
            try require(result.withLock({ $0 }) == true, "bounded held writer record")
            let heldWall = nx_now() - heldWriterStart
            heldWriterWallNS = heldWall
            writerNS &+= heldWall
            let releasedStart = nx_now(), released = store.service(token)
            serviceNS &+= nx_now() - releasedStart
            try require(released.valid && released.prefix == 1, "bounded held release prefix")
            let inPlaceAssets = [0]
            nx_alloc_begin(); let inPlaceStart = nx_now()
            let inPlace = store.mutate(inPlaceAssets, stamp: 31, token: token)
            let inPlaceNS = nx_now() - inPlaceStart, inPlaceAllocation = nx_alloc_end()
            allocations.append(try boundedAllocationRow("epoch3-prefix-in-place", elapsed: inPlaceNS,
                                                         allocation: inPlaceAllocation, policy: policy))
            try require(inPlace == .accepted, "bounded prefix in-place")
            boundedApply([0], stamp: 31, to: &oracle)
            let rest = try boundedRunWriter(store, token: token, sink: sink)
            writerNS &+= rest.writerNS; serviceNS &+= rest.serviceNS
        }

        let closeStart = nx_now(); try sink.finish(); writerNS &+= nx_now() - closeStart
        try require(store.finish(token, outcome: .success), "bounded success terminal")
        nx_alloc_begin(); let terminalStart = nx_now()
        let terminalResult = store.serviceTerminal(token)
        let terminalNS = nx_now() - terminalStart, terminalAllocation = nx_alloc_end()
        allocations.append(try boundedAllocationRow("epoch\(epochNumber)-terminal-reclaim", elapsed: terminalNS,
                                                     allocation: terminalAllocation, policy: policy))
        try require(terminalResult == .success && store.serviceTerminal(token) == nil,
                    "bounded terminal/replay")
        let runtimeLoopNS = nx_now() - runtimeStart
        let frozenBytes = try sink.readFinishedBytes()
        let recovered = try boundedRecover(frozenBytes, count: count)
        try require(frozenBytes == frozenOracle && recovered["byteExact"] as? Bool == true &&
                    recovered["orderExact"] as? Bool == true &&
                    recovered["digest"] as? String == boundedDigest(frozenOracle),
                    "bounded frozen/recovered exact")
        let liveBytes = store.liveBytes()!, oracleBytes = boundedOracleBytes(oracle)
        try require(liveBytes == oracleBytes, "bounded live oracle exact")
        let afterState = store.debugState()
        if epochNumber == 2, slots == 1 {
            guard let serial = partialReturnedSerial else {
                throw ProbeError.invariant("bounded partial serial proof missing")
            }
            guard let liveSerial = afterState["liveSerial"] as? [UInt32], !liveSerial.isEmpty else {
                throw ProbeError.invariant("bounded partial live serial")
            }
            try require(liveSerial[0] == serial, "bounded partial buffer reused for full page")
        }
        epochs.append(["epoch": epochNumber, "frozenDigest": boundedDigest(frozenBytes),
                       "liveDigest": boundedDigest(liveBytes), "recovered": recovered,
                       "state": afterState, "writerSetupNS": writerSetupNS,
                       "writerCallWallNS": writerNS,
                       "writerBuildNS": sink.buildNS, "writerSinkNS": sink.writeNS,
                       "serviceNS": serviceNS, "runtimeLoopNS": runtimeLoopNS,
                       "writerScratchCapacityBytes": sink.scratch.capacity,
                       "writerBytes": sink.bytesWritten,
                       "writerAliasHeldDuringKPressure": writerAliasHeldDuringKPressure,
                       "heldWriterWallNS": heldWriterWallNS,
                       "kPressureOutcome": kPressureOutcome,
                       "ownerGateBusyNS": ownerGateBusyNS])
    }
    let setupAvailable = setupAllocation.available == 1
    return ["epochs": epochs, "memory": initialMemory, "finalState": store.debugState(),
            "setup": ["ns": setupNS, "allocationAvailable": setupAvailable,
                      "allocations": boundedObserved(setupAllocation.calls, available: setupAvailable),
                      "allocationBytes": boundedObserved(setupAllocation.bytes, available: setupAvailable)],
            "partialToFullSerialExact": slots == 1]
}

private func boundedNegativeLifecycles(count: Int, slots: Int, policy: String,
                                       allocations: inout [[String: Any]]) throws -> [String: Any] {
    let fixture = (0..<count).map(BoundedColdRecord.fixture)
    let owner: UInt32 = 0x10203040, buffer: UInt32 = 0x50607080

    let unpublished = BoundedColdStore(records: fixture, slots: slots)
    guard let reserved = unpublished.reserve(owner: owner, buffer: buffer) else {
        throw ProbeError.invariant("bounded reserved cancellation setup")
    }
    let before = unpublished.liveBytes()!
    try require(unpublished.cancelReserved(reserved), "bounded reserved cancellation")
    try require(unpublished.serviceTerminal(reserved) == .cancelled && unpublished.liveBytes()! == before,
                "bounded reserved cancellation exact")
    guard let afterCancel = unpublished.begin(owner: owner, buffer: buffer) else {
        throw ProbeError.invariant("bounded begin after reserved cancel")
    }
    try require(unpublished.mutate([count - 1], stamp: 66, token: afterCancel) == .accepted,
                "bounded published cancellation mutation")
    try require(unpublished.finish(afterCancel, outcome: .cancelled) &&
                unpublished.serviceTerminal(afterCancel) == .cancelled &&
                unpublished.successfulCommits == 0 && unpublished.cancelledSaves == 2,
                "bounded published cancellation")

    let contended = BoundedColdStore(records: fixture, slots: slots)
    let contentionEntered = DispatchSemaphore(value: 0)
    let contentionRelease = DispatchSemaphore(value: 0)
    let contentionDone = DispatchSemaphore(value: 0)
    let contentionResult = Mutex<Bool?>(nil)
    DispatchQueue.global(qos: .utility).async {
        let held = contended.holdWriterGate(entered: contentionEntered,
                                            release: contentionRelease)
        contentionResult.withLock { $0 = held }
        contentionDone.signal()
    }
    try require(contentionEntered.wait(timeout: .now() + 10) == .success,
                "bounded contended begin gate entered")
    let rejectedBegin = contended.begin(owner: owner, buffer: buffer)
    contentionRelease.signal()
    try require(contentionDone.wait(timeout: .now() + 10) == .success &&
                contentionResult.withLock({ $0 }) == true && rejectedBegin == nil,
                "bounded contended begin reject")
    guard let afterContention = contended.begin(owner: owner, buffer: buffer) else {
        throw ProbeError.invariant("bounded begin after contention")
    }
    try require(contended.finish(afterContention, outcome: .cancelled) &&
                contended.serviceTerminal(afterContention) == .cancelled,
                "bounded contended begin left idle")

    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("nxr-bounded-negative-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let failed = BoundedColdStore(records: fixture, slots: slots)
    let sink = try BoundedWriterSink(path: temporary.appendingPathComponent("failed.bin").path)
    guard let failedToken = failed.begin(owner: owner, buffer: buffer) else {
        throw ProbeError.invariant("bounded failure setup")
    }
    let accepted = failed.mutate([count - 1], stamp: 77, token: failedToken)
    try require(accepted == .accepted, "bounded failure mutation")
    try require(try failed.writerRecord(failedToken, page: 0, sink: sink),
                "bounded failure prefix record")
    let firstService = failed.service(failedToken)
    try require(firstService.valid && firstService.prefix == 1,
                "bounded failure prefix service")

    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let done = DispatchSemaphore(value: 0), injectedError = Mutex<Bool?>(nil)
    DispatchQueue.global(qos: .utility).async {
        do {
            _ = try failed.writerRecord(failedToken, page: 1, sink: sink,
                                        entered: entered, release: release,
                                        injectFailure: true)
            injectedError.withLock { $0 = false }
        } catch {
            injectedError.withLock { $0 = true }
        }
        done.signal()
    }
    try require(entered.wait(timeout: .now() + 10) == .success,
                "bounded injected failure alias entered")
    let heldState = failed.debugState()
    try require((heldState["prefix"] as? Int) == 1 &&
                !failed.finish(failedToken, outcome: .failed) &&
                failed.serviceTerminal(failedToken) == nil,
                "bounded alias blocks failure terminal")
    release.signal()
    try require(done.wait(timeout: .now() + 10) == .success &&
                injectedError.withLock({ $0 }) == true,
                "bounded injected writer failure observed")
    let failedState = failed.debugState()
    let poisonedRetry = try failed.writerRecord(failedToken, page: 1, sink: sink)
    try require((failedState["prefix"] as? Int) == 1 &&
                (failedState["writerPoisoned"] as? Bool) == true && sink.records == 1 &&
                !poisonedRetry && !failed.finish(failedToken, outcome: .success) &&
                !failed.finish(failedToken, outcome: .cancelled),
                "bounded failure no extra prefix/record")
    try require(failed.finish(failedToken, outcome: .failed), "bounded injected failure terminal")
    try sink.finish()
    nx_alloc_begin(); let failureStart = nx_now()
    let failedOutcome = failed.serviceTerminal(failedToken)
    let failureNS = nx_now() - failureStart, failureAllocation = nx_alloc_end()
    allocations.append(try boundedAllocationRow("failure-alias-reclaim", elapsed: failureNS,
                                                 allocation: failureAllocation, policy: policy))
    try require(failedOutcome == .failed && failed.successfulCommits == 0 && failed.failedSaves == 1,
                "bounded failure not commit")
    try require(failed.serviceTerminal(failedToken) == nil, "bounded failure replay")
    guard let afterFailure = failed.begin(owner: owner, buffer: buffer) else {
        throw ProbeError.invariant("bounded begin after failure")
    }
    let resetState = failed.debugState()
    try require((resetState["writerPoisoned"] as? Bool) == false &&
                failed.finish(afterFailure, outcome: .cancelled) &&
                failed.serviceTerminal(afterFailure) == .cancelled,
                "bounded writer poison reset")

    let overflow = BoundedColdStore(records: fixture, slots: slots, epochSeed: UInt32.max)
    try require(overflow.reserve(owner: owner, buffer: buffer) == nil, "bounded epoch overflow")
    return ["reservedUnpublishedCancel": true, "publishedCancel": true,
            "publishedCancelAfterMutation": true,
            "contendedBeginLeavesIdle": true,
            "injectedWriterFailure": true, "failureNotCommit": true,
            "writerFailurePoisonsEpoch": true, "writerPoisonResetOnNextEpoch": true,
            "aliasHeldBlockedTerminal": true,
            "terminalReplayRejected": true, "epochOverflowRejected": true,
            "partialWriterRecordsBeforeFailure": sink.records]
}

func boundedEpochOwnershipMicro(count: Int, slots: Int,
                                allocationPolicy: String) throws -> [String: Any] {
    guard (count == 257 && slots == 1) || (count == 4096 && slots == 2) ||
          (count == 100_000 && slots == 2) else {
        throw ProbeError.invalid("bounded-epoch-ownership-micro 257 1|4096 2|100000 2 observe|zero|functional")
    }
    guard ["observe", "zero", "functional"].contains(allocationPolicy) else {
        throw ProbeError.invalid("bounded allocation policy")
    }
    let cControl = nx_alloc_calibrate()
    nx_alloc_begin(); let swiftValue = allocationControl(8193); let swiftControl = nx_alloc_end()
    try require(swiftValue == 8193 * 7 + 2, "bounded Swift control computation")
    if allocationPolicy != "functional" {
        try require(cControl > 0 && swiftControl.available == 1 && swiftControl.calls > 0,
                    "bounded allocation positive controls")
    }
    var allocations: [[String: Any]] = []
    let main = try boundedMainEpochs(count: count, slots: slots,
                                     policy: allocationPolicy, allocations: &allocations)
    let negative = try boundedNegativeLifecycles(count: min(count, 4096), slots: slots,
                                                 policy: allocationPolicy, allocations: &allocations)
    return [
        "status": "diagnostic-pass", "acceptance": false,
        "decision": "MICRO_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE",
        "integrationEligible": false,
        "scope": "disposable H-cold20B bounded ownership micro; no actual runtime source, A/B/K/C, save-format, product, UI, or device qualification",
        "assets": count, "slots": slots, "epochs": 3, "pageAssets": boundedPageAssets,
        "bytesPerAsset": boundedBytesPerAsset, "fullPageBytes": boundedFullPageWords * 8,
        "allocationPolicy": allocationPolicy,
        "allocationObserverAvailable": swiftControl.available == 1,
        "cAllocationPositiveControl": boundedObserved(cControl, available: swiftControl.available == 1),
        "swiftAllocationPositiveControl": boundedObserved(swiftControl.calls, available: swiftControl.available == 1),
        "allocationSamples": allocations, "main": main, "negative": negative,
        "invariants": ["atomicBeginPublish", "reserveAllBeforePayloadControlWAL", "ownerTryOnceNoWait",
                       "writerIOOutsideGate", "boundedScratchWriteBeforePrefix",
                       "writerFailurePoisonsEpoch",
                       "exclusiveFlatSnapshotDirectory",
                       "retireFrameBeforeReleasePrefix", "acquirePrefixBeforeCredit",
                       "memoryReclaimSeparateFromCommit", "canonicalCold20Bytes"],
        "C100": "NOT_RUN", "safeToRunH100k": count <= 4096,
        "safeToRunH1M": false,
        "limitations": "Cold-only ownership/lifetime result. K+1 is explicit rejection and is not yet compatible with the unchanged gameplay transcript. No claim for current nested root/leaf integration, full H/S memory, C overhead, phys_footprint, application smoothness, or production cross-process ownership."
    ]
}
#endif
