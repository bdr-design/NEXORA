#if STAGE_C
import Foundation
import ProbePlatform
#if EPOCH_PAGES
import Synchronization
#endif

// Test-only adapters for the two existing owners. No new simulation model.
private protocol PagedCheckWorld: AnyObject {
    var count: Int { get }
    var processed: UInt64 { get }
    var sequenceHash: UInt64 { get }
    var ownedBytes: Int { get }
    func seedFixture() throws
    func advance(to: UInt64, budget: Int, workBudget: Int, checkLimit: Int,
                 deadlineNS: UInt64, injectFailureAt: UInt64?) throws -> SliceResult
    func output(_ index: Int) -> Completion
    func checkState() -> StageCState
    func checkInstall(_ state: StageCState)
    func checkBegin(_ state: StageCState, _ sink: SnapshotSink) throws
    func checkCommit(_ state: StageCState) throws -> StageCSnapshotFileResult
    func checkService(_ state: StageCState) throws
    func checkDigest() -> [UInt64]
    func checkReschedule(now: UInt64, operation: UInt64) throws
    static func checkSnapshot(_ path: String) throws -> Self
    static func checkRecover(_ directory: String) throws -> Self
}

extension SwiftWorld: PagedCheckWorld {
    fileprivate func checkState() -> StageCState { StageCState(world: self) }
    fileprivate func checkInstall(_ state: StageCState) { stageCInstall(state) }
    fileprivate func checkBegin(_ state: StageCState, _ sink: SnapshotSink) throws { try state.begin(world: self, preparedSink: sink) }
    fileprivate func checkCommit(_ state: StageCState) throws -> StageCSnapshotFileResult { try state.waitForCommit(world: self) }
    fileprivate func checkService(_ state: StageCState) throws { try state.service(world: self, budgetNS: 500_000) }
    fileprivate func checkDigest() -> [UInt64] { Snapshot.worldDigest(self) }
    fileprivate func checkReschedule(now: UInt64, operation: UInt64) throws { try stageCRescheduleAll(self, baseNow: now, firstOperation: operation) }
    fileprivate static func checkSnapshot(_ path: String) throws -> SwiftWorld { try StageCSnapshotRestore.restoreSnapshot(path) }
    fileprivate static func checkRecover(_ directory: String) throws -> SwiftWorld { try StageCSnapshotRestore.recoverLatest(directory).world }
}
extension HybridWorld: PagedCheckWorld {
    fileprivate func checkState() -> StageCState { StageCState(world: self) }
    fileprivate func checkInstall(_ state: StageCState) { stageCInstall(state) }
    fileprivate func checkBegin(_ state: StageCState, _ sink: SnapshotSink) throws { try state.begin(world: self, preparedSink: sink) }
    fileprivate func checkCommit(_ state: StageCState) throws -> StageCSnapshotFileResult { try state.waitForCommit(world: self) }
    fileprivate func checkService(_ state: StageCState) throws { try state.service(world: self, budgetNS: 500_000) }
    fileprivate func checkDigest() -> [UInt64] { Snapshot.worldDigest(self) }
    fileprivate func checkReschedule(now: UInt64, operation: UInt64) throws { try stageCHybridRescheduleAll(self, baseNow: now, firstOperation: operation) }
    fileprivate static func checkSnapshot(_ path: String) throws -> HybridWorld { try StageCHybridSnapshotRestore.restoreSnapshot(path) }
    fileprivate static func checkRecover(_ directory: String) throws -> HybridWorld { try StageCHybridSnapshotRestore.recoverLatest(directory).world }
}

private func pagedDigest(_ words: [UInt64]) -> String { words.map { String(format: "%016llx", $0) }.joined() }
private func pagedObservation(_ value: UInt64, available: Bool) -> Any { available ? value as Any : NSNull() }

private func pagedChecks<W: PagedCheckWorld>(_ directory: String, variant: String, count: Int,
                                           allocationPolicy: String, make: () throws -> W) throws -> [String: Any] {
    let observed = allocationPolicy != "functional", requireZero = allocationPolicy == "zero"
    let cControl = observed ? nx_alloc_calibrate() : 0
    nx_alloc_begin(); let value = allocationControl(8193); let swiftControl = nx_alloc_end()
    try require(value == 8193 * 7 + 2, "paged Swift allocation control computation")
    let available = observed && swiftControl.available == 1
    if observed { try require(cControl > 0 && available && swiftControl.calls > 0, "paged allocation observer/control unavailable") }
#if !EPOCH_PAGES
    try require(!requireZero, "zero policy is candidate-only; legacy copies are observed")
#endif
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let initStart = nx_now(), world = try make()
    try world.seedFixture()
    let worldSetupNS = nx_now() - initStart, liveOwned = world.ownedBytes
    let plain = try make(); try plain.seedFixture()
    let poolStart = nx_now(), state = world.checkState()
    world.checkInstall(state)
    let poolSetupNS = nx_now() - poolStart
    var wal = try StageCWAL(directory: directory, epoch: 1)
    try world.checkBegin(state, state.prepareSink(directory: directory, epoch: 1))
    let initial = try world.checkCommit(state)
    try wal.close()
    let fixtureSHA = pagedDigest(try fileHash(directory + "/snapshot-1.bin"))
    let fixtureDigest = pagedDigest(world.checkDigest())
    var epochs: [[String: Any]] = []
    let referenceEvents = reference(count)
    var target: UInt64 = 600, nextOperation = UInt64(count * 2 + 1)
    for epoch in UInt32(2)...UInt32(4) {
        wal = try StageCWAL(directory: directory, epoch: epoch)
        let frozenDigest = world.checkDigest()
        let sink = state.prepareSink(directory: directory, epoch: epoch)
        let beginStart = nx_now(); try world.checkBegin(state, sink); let beginNS = nx_now() - beginStart
        let loopStart = nx_now()
        var calls = 0, events = 0, advanceNS: UInt64 = 0, maxAlloc: UInt64 = 0, allocBytes: UInt64 = 0
        var scriptHash: UInt64 = 14695981039346656037, walNS: UInt64 = 0
        while true {
            let expected = try plain.advance(to: target, budget: 1024, workBudget: 65536, checkLimit: Int.max,
                                             deadlineNS: UInt64.max, injectFailureAt: nil)
            nx_alloc_begin()
            let start = nx_now()
            let actual = try world.advance(to: target, budget: 1024, workBudget: 65536, checkLimit: Int.max,
                                           deadlineNS: UInt64.max, injectFailureAt: nil)
            let elapsed = nx_now() - start, allocation = nx_alloc_end()
            if available { try require(allocation.available == 1, "paged allocation observer disappeared") }
            if requireZero { try require(allocation.calls == 0, "paged advance allocated") }
            maxAlloc = max(maxAlloc, allocation.calls); allocBytes += allocation.bytes; advanceNS += elapsed
            try require(actual.events == expected.events && actual.units == expected.units &&
                        actual.reached == expected.reached && actual.stop == expected.stop, "paged advance transcript")
            for index in 0..<actual.events {
                try require(world.output(index) == plain.output(index), "paged ordered output")
                if epoch == 2 { try require(world.output(index) == referenceEvents[events + index], "paged independent sorted reference") }
            }
            calls += 1; events += actual.events
            scriptHash = (scriptHash ^ UInt64(actual.units)) &* 1099511628211
            scriptHash = (scriptHash ^ UInt64(actual.events)) &* 1099511628211
            scriptHash = (scriptHash ^ actual.reached) &* 1099511628211
            let walStart = nx_now()
            try wal.appendAdvance(target: target, budget: 1024, units: actual.units, events: actual.events)
            walNS += nx_now() - walStart
            try require(calls < count * 100 + 100_000 && actual.stop != .blocked, "paged bounded liveness")
            if actual.stop == .target { break }
        }
        try require(events == count && world.checkDigest() == plain.checkDigest(), "paged full cycle state")
        var serviceNS: UInt64 = 0, serviceMaxAlloc: UInt64 = 0, serviceCalls = 0
        while state.inFlight {
            nx_alloc_begin(); let serviceStart = nx_now(); try world.checkService(state)
            let elapsed = nx_now() - serviceStart, allocation = nx_alloc_end()
            if available { try require(allocation.available == 1, "paged service observer disappeared") }
            if requireZero { try require(allocation.calls == 0, "paged completion service allocated") }
            serviceNS += elapsed; serviceMaxAlloc = max(serviceMaxAlloc, allocation.calls); serviceCalls += 1
            try require(serviceCalls < 5_000_000, "paged commit liveness")
            if state.inFlight { Thread.sleep(forTimeInterval: 0.00005) }
        }
        guard let result = state.lastResult else { throw ProbeError.invariant("paged missing writer result") }
        let loopNS = nx_now() - loopStart
        try wal.close()
        try require(try W.checkSnapshot(directory + "/snapshot-\(epoch).bin").checkDigest() == frozenDigest,
                    "paged immutable epoch snapshot")
        let recovered = try W.checkRecover(directory)
        try require(recovered.checkDigest() == world.checkDigest(), "paged snapshot plus WAL replay")
        nx_alloc_begin(); try world.checkService(state); let idleService = nx_alloc_end()
        if requireZero { try require(idleService.calls == 0, "paged idle service allocated") }
        epochs.append(["epoch": epoch, "events": events, "calls": calls, "scriptHash": String(scriptHash),
                       "frozenDigest": pagedDigest(frozenDigest), "liveDigest": pagedDigest(world.checkDigest()),
                       "recoveredDigest": pagedDigest(recovered.checkDigest()), "sequenceHash": String(world.sequenceHash),
                       "snapshotBytes": result.bytes, "snapshotSource": result.snapshotSource,
                       "peakQueuedBytes": result.peakQueuedBytes, "retainedEpochBufferBytes": result.retainedEpochBufferBytes,
                       "beginNS": beginNS, "advanceNS": advanceNS, "walNS": walNS, "fullLoopNS": loopNS, "writerNS": result.writeNS,
                       "serviceNS": serviceNS, "serviceCalls": serviceCalls,
                       "serviceAllocationsMax": pagedObservation(serviceMaxAlloc, available: available),
                       "barrierCopies": state.barrierEmits, "barrierBytes": state.barrierBytes, "barrierNS": state.barrierNS,
                       "allocationAvailable": available, "advanceAllocationsMax": pagedObservation(maxAlloc, available: available),
                       "advanceAllocationBytes": pagedObservation(allocBytes, available: available),
                       "idleServiceAllocations": pagedObservation(idleService.calls, available: available)])
        if epoch < 4 {
            try world.checkReschedule(now: target, operation: nextOperation)
            try plain.checkReschedule(now: target, operation: nextOperation)
            nextOperation += UInt64(count); target += 600
        }
    }
    return ["status": "diagnostic", "acceptance": false, "schemaVersion": 1,
            "variant": variant, "assets": count, "fixtureSHA256": fixtureSHA, "fixtureDigest": fixtureDigest,
            "snapshotBytes": initial.bytes, "worldSetupNS": worldSetupNS, "poolSetupNS": poolSetupNS, "liveOwnedBytes": liveOwned,
            "preparedOwnedBytes": world.ownedBytes, "allocationPolicy": allocationPolicy,
            "allocationAvailable": available, "cAllocationPositiveControl": pagedObservation(cControl, available: available),
            "swiftAllocationPositiveControl": pagedObservation(swiftControl.calls, available: available),
            "epochs": epochs, "independentReferenceEvents": count, "scope": "bounded full-state snapshot/WAL checks; no A/B/C acceptance"]
}

func stageCPagedChecks(_ directory: String, variant: String, count: Int, allocationPolicy: String) throws -> [String: Any] {
    guard [1, 3, 7, 8, 9, 15, 255, 256, 257, 513, 4096, 100_000].contains(count),
          ["observe", "zero", "functional"].contains(allocationPolicy) else { throw ProbeError.invalid("paged check size/policy") }
    if variant == "S" { return try pagedChecks(directory, variant: variant, count: count, allocationPolicy: allocationPolicy) { try SwiftWorld(count: count) } }
    if variant == "H" { return try pagedChecks(directory, variant: variant, count: count, allocationPolicy: allocationPolicy) { try HybridWorld(count: count) } }
    throw ProbeError.invalid("paged check variant")
}

#if EPOCH_PAGES
private func cancelledWriter(_ sink: SnapshotSink) throws {
    var polls = 0
    while sink.counters.done.load(ordering: .acquiring) == 0 {
        Thread.sleep(forTimeInterval: 0.00005); polls += 1
        try require(polls < 100_000, "cancelled prepared writer did not exit")
    }
    try require(sink.counters.failed.load(ordering: .acquiring) == 1, "cancelled writer falsely committed")
}

private func pagedLifecycle<W: PagedCheckWorld>(_ directory: String, make: () throws -> W) throws -> [String: Any] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let world = try make(), wrong = try make()
    try world.seedFixture(); try wrong.seedFixture()
    let state = world.checkState(); world.checkInstall(state)
    let baseline = world.checkDigest()
    let unused = state.prepareSink(directory: directory, epoch: 1)
    try require(unused.completionToken() == nil, "premature epoch completion token")
    unused.cancelUnused(); unused.cancelUnused()
    try cancelledWriter(unused)
    var cancelledRejected = false
    do { try world.checkBegin(state, unused) } catch { cancelledRejected = true }
    try require(cancelledRejected && state.epoch == 0 && !state.inFlight, "cancelled prepared writer reused")
    let wrongOwner = state.prepareSink(directory: directory, epoch: 1)
    var rejected = false
    do { try wrong.checkBegin(state, wrongOwner) } catch { rejected = true }
    try require(rejected && state.epoch == 0 && !state.inFlight && world.checkDigest() == baseline, "wrong save owner changed state")
    try cancelledWriter(wrongOwner)
    let wal = try StageCWAL(directory: directory, epoch: 1)
    let valid = state.prepareSink(directory: directory, epoch: 1)
    try world.checkBegin(state, valid)
    let overlap = state.prepareSink(directory: directory, epoch: 2)
    rejected = false
    do { try world.checkBegin(state, overlap) } catch { rejected = true }
    try require(rejected && state.epoch == 1 && state.inFlight, "overlap accepted or epoch changed")
    try cancelledWriter(overlap)
    _ = try world.checkCommit(state); try wal.close()
    try require(valid.completionToken()?.epoch == 1 && valid.completionToken()?.ownerID == ObjectIdentifier(world), "completed epoch token identity")
    let stale = state.prepareSink(directory: directory, epoch: 1)
    rejected = false
    do { try world.checkBegin(state, stale) } catch { rejected = true }
    try require(rejected && !state.inFlight && state.epoch == 1, "stale epoch accepted")
    try cancelledWriter(stale)
    let missing = directory + "/missing-parent/no-directory"
    let failing = state.prepareSink(directory: missing, epoch: 2)
    try world.checkBegin(state, failing)
    rejected = false
    do { _ = try world.checkCommit(state) } catch { rejected = true }
    try require(rejected && state.inFlight && !state.capturing && failing.completionToken() != nil,
                "writer failure must release roots and remain failed/in flight")
    let retry = state.prepareSink(directory: directory, epoch: 3)
    rejected = false
    do { try world.checkBegin(state, retry) } catch { rejected = true }
    try require(rejected && state.epoch == 2, "failed save silently retried")
    try cancelledWriter(retry)
    try require(world.checkDigest() == baseline && (try W.checkRecover(directory)).checkDigest() == baseline,
                "failed save changed live or last committed state")
    return ["status": "pass", "assets": world.count, "unusedCancelExits": true, "cancelIdempotent": true,
            "prematureCompletionUnavailable": true, "cancelledReuseRejected": true, "wrongOwnerRejected": true, "overlapRejected": true,
            "staleEpochRejected": true, "writerFailureReported": true, "failedRetryRejected": true,
            "lastCommitPreserved": true, "scope": "single directory owner; no cross-process locking"]
}

private func pagedColdEpoch(_ directory: String) throws {
    let count = 257
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let world = try HybridWorld(count: count), mirror = try HybridWorld(count: count)
    try world.seedFixture(); try mirror.seedFixture()
    let state = StageCState(world: world); world.stageCInstall(state)
    let initialWAL = try StageCWAL(directory: directory, epoch: 1)
    try state.begin(world: world, preparedSink: state.prepareSink(directory: directory, epoch: 1))
    _ = try state.waitForCommit(world: world); try initialWAL.close()
    let frozenDigest = Snapshot.worldDigest(world)
    let wal = try StageCWAL(directory: directory, epoch: 2)
    let held = state.prepareSink(directory: directory, epoch: 2, heldForKillFixture: true)
    defer { held.releaseKillFixtureWriter() }
    try state.begin(world: world, preparedSink: held)
    while true {
        let actual = try world.advance(to: 600, budget: 1024)
        let expected = try mirror.advance(to: 600, budget: 1024)
        try require(actual.events == expected.events && actual.units == expected.units &&
                    actual.reached == expected.reached && actual.stop == expected.stop, "cold epoch transcript")
        try wal.appendAdvance(target: 600, budget: 1024, units: actual.units, events: actual.events)
        if actual.stop == .target { break }
        try require(actual.stop != .blocked, "cold epoch blocked")
    }
    let hotNodeGroupBytes = count * 80 + ((count + 15) / 16) * 8
    try require(state.barrierBytes == hotNodeGroupBytes, "cold page copied during hot-only completion")
    try stageCHybridRescheduleAll(world, baseNow: 600, firstOperation: UInt64(count * 2 + 1))
    try stageCHybridRescheduleAll(mirror, baseNow: 600, firstOperation: UInt64(count * 2 + 1))
    try wal.appendRescheduleAll(baseNow: 600, firstOperation: UInt64(count * 2 + 1))
    try require(state.barrierBytes == hotNodeGroupBytes + count * 20,
                "cold mutation must copy and report every changed cold page")
    try require(Snapshot.worldDigest(world) == Snapshot.worldDigest(mirror), "cold epoch live mirror")
    held.releaseKillFixtureWriter()
    _ = try state.waitForCommit(world: world); try wal.close()
    let frozen = try StageCHybridSnapshotRestore.restoreSnapshot(directory + "/snapshot-2.bin")
    let recovered = try StageCHybridSnapshotRestore.recoverLatest(directory)
    try require(Snapshot.worldDigest(frozen) == frozenDigest, "cold mutation changed frozen snapshot")
    try require(Snapshot.worldDigest(recovered.world) == Snapshot.worldDigest(world),
                "cold mutation recovery lost live reschedule")
}

func stageCPagedLifecycle(_ directory: String, variant: String) throws -> [String: Any] {
    if variant == "S" { return try pagedLifecycle(directory) { try SwiftWorld(count: 257) } }
    if variant == "H" {
        var result = try pagedLifecycle(directory) { try HybridWorld(count: 257) }
        try pagedColdEpoch(directory + "/cold-epoch")
        result["coldMutationDuringFrozenEpochExact"] = true
        return result
    }
    throw ProbeError.invalid("paged lifecycle variant")
}
#endif
#endif
