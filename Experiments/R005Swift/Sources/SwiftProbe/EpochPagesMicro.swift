#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

// Isolated ownership study. SwiftWorld/HybridWorld and their saves never use it.
private struct EpochMicroAsset: BitwiseCopyable, Sendable, Equatable {
    var departure: UInt64 = 300
    var fare: Int64 = 100
    var completed: UInt64 = 0
    var operation: UInt64 = 0
    var generation: UInt32 = 1
    var airport: UInt32 = 1
    var destination: UInt32 = 2
    var contract: UInt32 = 0
    var changeEpoch: UInt32 = 0
    var entity: UInt32 = 0
    var policy: UInt32 = 7
    var origin: UInt32 = 1
    var active: UInt8 = 1

    static func fixture(_ index: Int) -> Self {
        var value = Self()
        value.fare += Int64(index % 73)
        value.contract = UInt32(index / 16)
        value.entity = UInt32(index % 32)
        return value
    }

    mutating func apply(_ index: Int, round: Int, count: Int, epoch: UInt64) {
        completed += 1
        operation = (epoch - 1) * UInt64(count * 8) + UInt64(round * count + index + 1)
        airport = destination
        active = 0
        changeEpoch = UInt32(epoch)
    }

    func appendColumn(_ column: Int, into bytes: inout [UInt8]) {
        switch column {
        case 0: Snapshot.appendLE(generation, into: &bytes)
        case 1: Snapshot.appendLE(airport, into: &bytes)
        case 2: Snapshot.appendLE(destination, into: &bytes)
        case 3: Snapshot.appendLE(departure, into: &bytes)
        case 4: Snapshot.appendLE(fare, into: &bytes)
        case 5: Snapshot.appendLE(completed, into: &bytes)
        case 6: Snapshot.appendLE(operation, into: &bytes)
        case 7: Snapshot.appendLE(active, into: &bytes)
        case 8: Snapshot.appendLE(contract, into: &bytes)
        case 9: Snapshot.appendLE(changeEpoch, into: &bytes)
        case 10: Snapshot.appendLE(entity, into: &bytes)
        case 11: Snapshot.appendLE(policy, into: &bytes)
        default: Snapshot.appendLE(origin, into: &bytes)
        }
    }
}

private typealias EpochMicroPage<T> = ContiguousArray<T>
private typealias EpochMicroLeaf<T> = ContiguousArray<EpochMicroPage<T>>
private typealias EpochMicroRoot<T> = ContiguousArray<EpochMicroLeaf<T>>

private struct EpochMicroFrozen<T: BitwiseCopyable & Sendable>: Sendable {
    let root: EpochMicroRoot<T>
    let epoch: UInt64
    let assets: Int
}

// Single simulation owner. A published value root is immutable; a writer reads
// only that value. All root/leaf/page replacement buffers are prepared at setup.
private final class EpochMicroStore<T: BitwiseCopyable & Sendable> {
    private var root: EpochMicroRoot<T>
    private var spareRoot: EpochMicroRoot<T>
    private var spareLeaves: ContiguousArray<EpochMicroLeaf<T>>
    private var sparePages: ContiguousArray<EpochMicroPage<T>>
    private var leafEpoch: ContiguousArray<UInt64>
    private var pageEpoch: ContiguousArray<UInt64>
    private var rootEpoch: UInt64 = 0
    private(set) var epoch: UInt64 = 0
    private(set) var active = false
    private(set) var clonePages = 0
    private(set) var cloneBytes = 0
    private(set) var cloneNS: UInt64 = 0
    private(set) var rootCopies = 0
    private(set) var leafCopies = 0
    let assets: Int
    let pageCount: Int
    let reservedPayloadBytes: Int

    init(assets: Int, pages: [EpochMicroPage<T>]) {
        self.assets = assets
        pageCount = pages.count
        root = []
        spareRoot = []
        spareLeaves = []
        sparePages = []
        var payload = 0
        for start in stride(from: 0, to: pages.count, by: 64) {
            let end = min(start + 64, pages.count)
            root.append(EpochMicroLeaf(pages[start..<end]))
            spareRoot.append([])
            spareLeaves.append(.init(repeating: [], count: end - start))
        }
        for page in pages {
            // Distinct storage even when initial contents are equal.
            var spare = EpochMicroPage<T>()
            spare.reserveCapacity(page.count)
            for element in page { spare.append(element) }
            sparePages.append(spare)
            payload += (page.capacity + spare.capacity) * MemoryLayout<T>.stride
        }
        reservedPayloadBytes = payload
        leafEpoch = .init(repeating: 0, count: root.count)
        pageEpoch = .init(repeating: 0, count: pages.count)
    }

    func freeze() throws -> EpochMicroFrozen<T> {
        guard !active, epoch < UInt64(UInt32.max) else {
            throw ProbeError.invalid("epoch micro overlapping freeze/epoch overflow")
        }
        active = true
        epoch += 1
        clonePages = 0; cloneBytes = 0; cloneNS = 0; rootCopies = 0; leafCopies = 0
        return EpochMicroFrozen(root: root, epoch: epoch, assets: assets)
    }

    @inline(__always) func mutate(_ page: Int, _ body: (inout EpochMicroPage<T>) -> Void) {
        let leaf = page >> 6, slot = page & 63
        if active && pageEpoch[page] != epoch {
            let start = nx_now()
            if rootEpoch != epoch {
                for index in root.indices { spareRoot[index] = root[index] }
                swap(&root, &spareRoot)
                rootEpoch = epoch
                rootCopies += 1
            }
            if leafEpoch[leaf] != epoch {
                for index in root[leaf].indices { spareLeaves[leaf][index] = root[leaf][index] }
                swap(&root[leaf], &spareLeaves[leaf])
                leafEpoch[leaf] = epoch
                leafCopies += 1
            }
            for index in root[leaf][slot].indices {
                sparePages[page][index] = root[leaf][slot][index]
            }
            swap(&root[leaf][slot], &sparePages[page])
            pageEpoch[page] = epoch
            clonePages += 1
            cloneBytes += root[leaf][slot].count * MemoryLayout<T>.stride
            cloneNS += nx_now() - start
        }
        body(&root[leaf][slot])
    }

    func readPage(_ index: Int) -> EpochMicroPage<T> { root[index >> 6][index & 63] }

    func releaseCompleted(epoch completedEpoch: UInt64, writerDone: Bool) throws {
        guard active, completedEpoch == epoch, writerDone else {
            throw ProbeError.invalid("epoch micro premature/stale release")
        }
        // Caller has joined the writer and released the frozen value first.
        // Release old directories before reusing their page buffers next epoch.
        for index in spareRoot.indices { spareRoot[index] = [] }
        for leaf in spareLeaves.indices {
            for index in spareLeaves[leaf].indices { spareLeaves[leaf][index] = [] }
        }
        active = false
    }
}

private struct EpochMicroWriterResult: Sendable {
    let ns: UInt64
    let sleepNS: UInt64
    let allocations: UInt64
    let allocationBytes: UInt64
    let allocationAvailable: Bool
    let bytes: UInt64
    let digest: String
}

private func epochMicroFileDigest(_ path: String) throws -> String {
    try fileHash(path).map { String(format: "%016llx", $0) }.joined()
}

private struct EpochMicroWriterState<T: BitwiseCopyable & Sendable>: Sendable {
    var view: EpochMicroFrozen<T>?
    var result: EpochMicroWriterResult?
    var failure: String?
}

private final class EpochMicroWriter<T: BitwiseCopyable & Sendable>: Sendable {
    private let state: Mutex<EpochMicroWriterState<T>>
    private let finished = DispatchSemaphore(value: 0)
    let done = Atomic<Int>(0)
    let epoch: UInt64

    init(_ frozen: EpochMicroFrozen<T>) {
        epoch = frozen.epoch
        state = Mutex(EpochMicroWriterState(view: frozen))
    }

    func start(path: String, paced: Bool,
               serialize: @escaping @Sendable (EpochMicroPage<T>, Int, inout [UInt8]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var view = self.state.withLock { value -> EpochMicroFrozen<T>? in
                let result = value.view
                value.view = nil
                return result
            }
            let start = nx_now()
            nx_alloc_begin()
            var result: EpochMicroWriterResult?
            var failure: String?
            do {
                guard let frozen = view else { throw ProbeError.invalid("epoch micro missing writer root") }
                guard FileManager.default.createFile(atPath: path, contents: nil) else {
                    throw ProbeError.invalid("epoch micro file creation")
                }
                let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                defer { try? file.close() }
                var bytes: [UInt8] = []
                bytes.reserveCapacity(16 + 256 * 65)
                var total: UInt64 = 0
                var sleepNS: UInt64 = 0
                let pages = (frozen.assets + 255) >> 8
                for page in 0..<pages {
                    bytes.removeAll(keepingCapacity: true)
                    let elements = min(256, frozen.assets - page * 256)
                    Snapshot.appendLE(UInt16(1), into: &bytes)
                    Snapshot.appendLE(UInt16(0), into: &bytes)
                    Snapshot.appendLE(UInt32(page), into: &bytes)
                    Snapshot.appendLE(UInt32(elements), into: &bytes)
                    Snapshot.appendLE(UInt32(elements * 65), into: &bytes)
                    serialize(frozen.root[page >> 6][page & 63], elements, &bytes)
                    let digest = Snapshot.digestBytes(bytes, range: 16..<bytes.count)
                    try Snapshot.writeRecord(bytes, descriptor: file.fileDescriptor, range: 0..<bytes.count)
                    try file.write(contentsOf: digest)
                    total += UInt64(bytes.count + digest.count)
                    if paced && page % 4 == 3 && page + 1 < pages {
                        let before = nx_now()
                        Thread.sleep(forTimeInterval: 0.00005)
                        sleepNS += nx_now() - before
                    }
                }
                try file.synchronize()
                let digest = try epochMicroFileDigest(path)
                let allocation = nx_alloc_end()
                result = EpochMicroWriterResult(ns: nx_now() - start, sleepNS: sleepNS,
                    allocations: allocation.calls, allocationBytes: allocation.bytes,
                    allocationAvailable: allocation.available == 1, bytes: total, digest: digest)
            } catch {
                _ = nx_alloc_end()
                failure = String(describing: error)
            }
            // Release the writer's immutable root before advertising completion.
            view = nil
            self.state.withLock { value in value.result = result; value.failure = failure }
            self.done.store(1, ordering: .releasing)
            self.finished.signal()
        }
    }

    func wait() throws -> EpochMicroWriterResult {
        guard finished.wait(timeout: .now() + 30) == .success else {
            throw ProbeError.invalid("epoch micro writer timeout")
        }
        return try state.withLock { value in
            guard value.failure == nil, let result = value.result else {
                throw ProbeError.invalid(value.failure ?? "epoch micro missing result")
            }
            return result
        }
    }
}

@inline(__always) private func epochMicroPut(_ value: UInt64, at offset: Int,
                                           width: Int, into bytes: inout ContiguousArray<UInt8>) {
    for byte in 0..<width { bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
}

private func epochMicroFixture<T: BitwiseCopyable & Sendable>(count: Int,
                 makePage: (Range<Int>) -> EpochMicroPage<T>) -> EpochMicroStore<T> {
    var pages: [EpochMicroPage<T>] = []
    for start in stride(from: 0, to: count, by: 256) { pages.append(makePage(start..<min(start + 256, count))) }
    return EpochMicroStore(assets: count, pages: pages)
}

private func epochMicroReferenceFile(_ path: String, count: Int, completedEpochs: Int) throws -> String {
    let world = try SwiftWorld(count: count)
    for index in 0..<count {
        var row = EpochMicroAsset.fixture(index)
        for epoch in 1...max(1, completedEpochs) where completedEpochs > 0 {
            for round in 0..<8 { row.apply(index, round: round, count: count, epoch: UInt64(epoch)) }
        }
        try world.restoreAsset(index, gen: row.generation, airport: row.airport,
            destination: row.destination, departure: row.departure, fare: row.fare,
            trips: row.completed, last: row.operation, active: row.active,
            contract: row.contract, assetChangeEpoch: row.changeEpoch, entity: row.entity,
            policy: row.policy, origin: row.origin)
    }
    guard FileManager.default.createFile(atPath: path, contents: nil) else {
        throw ProbeError.invalid("epoch micro reference creation")
    }
    let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? file.close() }
    for page in 0..<((count + 255) >> 8) {
        let bytes = Snapshot.assetRecord(world, chunk: page)
        try Snapshot.writeRecord(bytes, descriptor: file.fileDescriptor, range: 0..<bytes.count)
        try file.write(contentsOf: Snapshot.digestBytes(bytes, range: 16..<bytes.count))
    }
    try file.synchronize()
    return try epochMicroFileDigest(path)
}

private func epochMicroSaving<T: BitwiseCopyable & Sendable>(_ store: EpochMicroStore<T>,
        path: String, paced: Bool, count: Int,
        mutate: (inout EpochMicroPage<T>, Int, Int, UInt64) -> Void,
        serialize: @escaping @Sendable (EpochMicroPage<T>, Int, inout [UInt8]) -> Void) throws -> [String: Any] {
    let loopStart = nx_now()
    nx_alloc_begin()
    let beginStart = nx_now()
    var frozen: EpochMicroFrozen<T>? = try store.freeze()
    let beginNS = nx_now() - beginStart
    let beginAlloc = nx_alloc_end()
    var rejectedOverlap = false
    do { _ = try store.freeze() } catch { rejectedOverlap = true }
    nx_alloc_begin()
    let writerSetupStart = nx_now()
    let writer = EpochMicroWriter(frozen!)
    frozen = nil
    let writerSetupNS = nx_now() - writerSetupStart
    let writerSetupAlloc = nx_alloc_end()
    var rejectedPremature = false
    do { try store.releaseCompleted(epoch: writer.epoch, writerDone: false) }
    catch { rejectedPremature = true }
    writer.start(path: path, paced: paced, serialize: serialize)
    nx_alloc_begin()
    let mutationStart = nx_now()
    for round in 0..<8 {
        for page in 0..<store.pageCount {
            store.mutate(page) { mutate(&$0, page, round, writer.epoch) }
        }
    }
    let mutationNS = nx_now() - mutationStart
    let mutationAlloc = nx_alloc_end()
    let afterMutationFootprint = nx_footprint()
    let result = try writer.wait()
    try require(beginAlloc.available == 1 && mutationAlloc.available == 1 &&
                result.allocationAvailable, "epoch micro allocator unavailable")
    try require(rejectedOverlap && rejectedPremature, "epoch micro lifecycle rejects")
    return ["epoch": writer.epoch, "beginNS": beginNS,
        "beginAllocations": beginAlloc.calls, "beginAllocationBytes": beginAlloc.bytes,
        "writerSetupNS": writerSetupNS, "writerSetupAllocations": writerSetupAlloc.calls,
        "writerSetupAllocationBytes": writerSetupAlloc.bytes,
        "mutationNS": mutationNS, "mutationAllocations": mutationAlloc.calls,
        "mutationAllocationBytes": mutationAlloc.bytes,
        "afterMutationPhysicalFootprint": ["status": afterMutationFootprint.status,
                                            "bytes": afterMutationFootprint.bytes],
        "clonePages": store.clonePages, "cloneBytes": store.cloneBytes, "cloneNS": store.cloneNS,
        "rootCopies": store.rootCopies, "leafCopies": store.leafCopies,
        "writerNS": result.ns, "writerSleepNS": result.sleepNS,
        "writerAllocations": result.allocations, "writerAllocationBytes": result.allocationBytes,
        "writerBytes": result.bytes, "writerDigest": result.digest,
        "loopBeforeReleaseNS": nx_now() - loopStart,
        "overlapRejected": rejectedOverlap, "prematureReleaseRejected": rejectedPremature]
}

private func epochMicroLeg<T: BitwiseCopyable & Sendable>(directory: String, name: String,
        count: Int, writerMode: String, fixture: () -> EpochMicroStore<T>,
        mutate: (inout EpochMicroPage<T>, Int, Int, UInt64) -> Void,
        serialize: @escaping @Sendable (EpochMicroPage<T>, Int, inout [UInt8]) -> Void,
        references: [String]) throws -> [String: Any] {
    let beforeFootprint = nx_footprint()
    nx_alloc_begin()
    let setupStart = nx_now()
    let store = fixture()
    let setupNS = nx_now() - setupStart
    let setupAlloc = nx_alloc_end()
    let setupFootprint = nx_footprint()
    var epochs: [[String: Any]] = []
    for epoch in 1...3 {
        let epochStart = nx_now()
        let path = directory + "/\(name)-\(writerMode)-\(epoch).bin"
        var value: [String: Any]
        if writerMode == "none" {
            nx_alloc_begin()
            let start = nx_now()
            for round in 0..<8 {
                for page in 0..<store.pageCount { store.mutate(page) { mutate(&$0, page, round, UInt64(epoch)) } }
            }
            let elapsed = nx_now() - start
            let allocation = nx_alloc_end()
            try require(allocation.available == 1, "epoch micro control allocator unavailable")
            value = ["epoch": epoch, "mutationNS": elapsed, "mutationAllocations": allocation.calls,
                     "mutationAllocationBytes": allocation.bytes]
        } else {
            value = try epochMicroSaving(store, path: path, paced: writerMode == "paced", count: count,
                                         mutate: mutate, serialize: serialize)
            try require(value["writerDigest"] as? String == references[epoch - 1], "epoch micro frozen digest")
            nx_alloc_begin()
            let releaseStart = nx_now()
            try store.releaseCompleted(epoch: UInt64(epoch), writerDone: true)
            let releaseNS = nx_now() - releaseStart
            let allocation = nx_alloc_end()
            value["releaseNS"] = releaseNS
            value["releaseAllocations"] = allocation.calls
            value["releaseAllocationBytes"] = allocation.bytes
            try require(allocation.available == 1, "epoch micro release allocator unavailable")
            try FileManager.default.removeItem(atPath: path)
        }
        value["ownerLoopNS"] = nx_now() - epochStart
        let releasedFootprint = nx_footprint()
        value["releasedPhysicalFootprint"] = ["status": releasedFootprint.status,
                                               "bytes": releasedFootprint.bytes]
        // Build canonical asset records from the live view, independently compared
        // with existing S Snapshot.assetRecord on a restored SwiftWorld fixture.
        guard FileManager.default.createFile(atPath: path, contents: nil) else { throw ProbeError.invalid("epoch micro live file") }
        let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        for page in 0..<store.pageCount {
            let elements = min(256, count - page * 256)
            let bytes = Snapshot.record(kind: 1, index: UInt32(page), elements: UInt32(elements),
                                        payloadBytes: elements * 65) {
                serialize(store.readPage(page), elements, &$0)
            }
            try Snapshot.writeRecord(bytes, descriptor: file.fileDescriptor, range: 0..<bytes.count)
            try file.write(contentsOf: Snapshot.digestBytes(bytes, range: 16..<bytes.count))
        }
        try file.synchronize()
        try file.close()
        let liveDigest = try epochMicroFileDigest(path)
        try require(liveDigest == references[epoch], "epoch micro live digest")
        try FileManager.default.removeItem(atPath: path)
        value["frozenExact"] = writerMode == "none" ? NSNull() : true
        value["liveExact"] = true
        value["liveDigest"] = liveDigest
        epochs.append(value)
    }
    return ["representation": name, "writerMode": writerMode, "assets": count,
            "setupNS": setupNS, "setupAllocations": setupAlloc.calls,
            "setupAllocationBytes": setupAlloc.bytes, "reservedPayloadBytes": store.reservedPayloadBytes,
            "beforePhysicalFootprint": ["status": beforeFootprint.status, "bytes": beforeFootprint.bytes],
            "setupPhysicalFootprint": ["status": setupFootprint.status, "bytes": setupFootprint.bytes],
            "epochs": epochs]
}

func epochPagesMicro(_ directory: String, count: Int) throws -> [String: Any] {
    guard count == 4096 || count == 100_000 else { throw ProbeError.invalid("epoch-pages-micro directory 4096|100000") }
    guard !FileManager.default.fileExists(atPath: directory) else { throw ProbeError.invalid("epoch micro directory already exists") }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let cControl = nx_alloc_calibrate()
    nx_alloc_begin()
    let swiftComputation = allocationControl(8193)
    let swiftControl = nx_alloc_end()
    try require(cControl > 0 && swiftControl.available == 1 && swiftControl.calls > 0 &&
                swiftComputation == 8193 * 7 + 2, "epoch micro C/Swift allocator calibration")
    var references: [String] = []
    for epoch in 0...3 {
        let path = directory + "/reference-\(epoch).bin"
        references.append(try epochMicroReferenceFile(path, count: count, completedEpochs: epoch))
        try FileManager.default.removeItem(atPath: path)
    }
    let rowFixture = { epochMicroFixture(count: count) { EpochMicroPage($0.map(EpochMicroAsset.fixture)) } }
    let rowMutation: (inout EpochMicroPage<EpochMicroAsset>, Int, Int, UInt64) -> Void = { page, chunk, round, epoch in
        for index in page.indices { page[index].apply(chunk * 256 + index, round: round, count: count, epoch: epoch) }
    }
    let rowSerialize: @Sendable (EpochMicroPage<EpochMicroAsset>, Int, inout [UInt8]) -> Void = { page, _, bytes in
        for column in 0..<13 { for row in page { row.appendColumn(column, into: &bytes) } }
    }
    let packedFixture = { epochMicroFixture(count: count) { range -> EpochMicroPage<UInt8> in
        var bytes: [UInt8] = []
        bytes.reserveCapacity(range.count * 65)
        for column in 0..<13 { for index in range { EpochMicroAsset.fixture(index).appendColumn(column, into: &bytes) } }
        return EpochMicroPage(bytes)
    } }
    let packedMutation: (inout EpochMicroPage<UInt8>, Int, Int, UInt64) -> Void = { bytes, chunk, round, epoch in
        let n = bytes.count / 65
        for index in 0..<n {
            epochMicroPut(2, at: n * 4 + index * 4, width: 4, into: &bytes)
            epochMicroPut((epoch - 1) * 8 + UInt64(round + 1), at: n * 28 + index * 8, width: 8, into: &bytes)
            let operation = (epoch - 1) * UInt64(count * 8) + UInt64(round * count + chunk * 256 + index + 1)
            epochMicroPut(operation, at: n * 36 + index * 8, width: 8, into: &bytes)
            bytes[n * 44 + index] = 0
            epochMicroPut(epoch, at: n * 49 + index * 4, width: 4, into: &bytes)
        }
    }
    let packedSerialize: @Sendable (EpochMicroPage<UInt8>, Int, inout [UInt8]) -> Void = { page, _, bytes in bytes.append(contentsOf: page) }
    var legs: [[String: Any]] = []
    for mode in ["none", "direct", "paced", "none"] {
        legs.append(try epochMicroLeg(directory: directory, name: "rows", count: count,
            writerMode: mode, fixture: rowFixture, mutate: rowMutation, serialize: rowSerialize, references: references))
        legs.append(try epochMicroLeg(directory: directory, name: "packedSoA", count: count,
            writerMode: mode, fixture: packedFixture, mutate: packedMutation, serialize: packedSerialize, references: references))
    }
    return ["status": "diagnostic", "acceptance": false, "scope": "isolated asset-page ownership micro; no S/H hot-state integration",
            "assets": count, "epochsPerLeg": 3, "writesPerAssetPerEpoch": 8,
            "rowStride": MemoryLayout<EpochMicroAsset>.stride, "packedBytesPerAsset": 65,
            "cAllocationPositiveControl": cControl, "swiftAllocationPositiveControl": swiftControl.calls,
            "references": references, "legs": legs,
            "limitations": "Assets only, no timing wheel, financial lifecycle, snapshot commit/WAL/recovery, A/B/K1-K10, 1M/100-save C, UI/device/thermal acceptance. Physical footprint samples are process-wide and do not certify peak RSS. Pacing sleep and writer lifetime are explicit. No performance PASS is asserted."]
}
#endif
