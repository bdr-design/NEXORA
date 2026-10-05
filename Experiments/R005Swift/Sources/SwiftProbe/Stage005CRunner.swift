#if STAGE_C
import Foundation
import ProbePlatform

private let stageCBeginP99LimitNS: UInt64 = 100_000
private let stageCAdvanceP99LimitNS: UInt64 = 1_100_000
private let stageCOverheadRatioLimit = 1.10

func stageCRescheduleAll(_ world: SwiftWorld, baseNow: UInt64,
                         firstOperation: UInt64) throws {
    guard world.wheel.pending == 0, baseNow == world.now else {
        throw ProbeError.invariant("stage C reschedule requires drained target")
    }
    var operation = firstOperation
    for i in 0..<world.count {
        guard world.active[i] == 0 else { throw ProbeError.invariant("stage C reschedule active") }
        try world.schedule(asset: i, due: baseNow + UInt64(i % 600 + 1),
                           operation: operation, amount: Int64(i % 97 + 101))
        operation &+= 1
        guard operation > 0 else { throw ProbeError.invalid("stage C operation overflow") }
    }
}

private func stageCQuantile(_ values: [UInt64], numerator: Int, denominator: Int) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, (sorted.count * numerator) / denominator)
    return sorted[index]
}

func stageCAllocationProbes() throws -> [String: Any] {
    let world = try SwiftWorld(count: 1_024)
    let positive = nx_alloc_calibrate()
#if os(macOS)
    try require(positive > 0, "stage C allocation probe positive control")
#endif
    nx_alloc_begin()
    let record = Snapshot.assetRecord(world, chunk: 0)
    let recordAlloc = nx_alloc_end()
    try require(recordAlloc.available == 1 && recordAlloc.calls == 1,
                "stage C record must allocate exactly once")

    let queue = StageCRecordQueue(capacity: 10_000)
    nx_alloc_begin()
    for _ in 0..<10_000 { queue.push(record) }
    let queueAlloc = nx_alloc_end()
    try require(queueAlloc.available == 1 && queueAlloc.calls == 0,
                "stage C preallocated queue producer allocation")

    var controlTimes: [UInt64] = []
    controlTimes.reserveCapacity(1_000)
    var controlAllocMax: UInt64 = 0
    var controlBytes = 0
    for _ in 0..<1_000 {
        nx_alloc_begin()
        let start = nx_now()
        let control = Snapshot.controlRecord(world)
        let finish = nx_now()
        let allocation = nx_alloc_end()
        controlAllocMax = max(controlAllocMax, allocation.calls)
        controlBytes = control.count + 32
        controlTimes.append(finish - start)
    }
    let controlP99 = stageCQuantile(controlTimes,numerator:99,denominator:100)
    try require(controlP99 <= stageCBeginP99LimitNS,
                "stage C control record p99 \(controlP99) > \(stageCBeginP99LimitNS) ns")

    return [
        "status":"pass",
        "assetRecord":["producerAllocations":recordAlloc.calls,
                       "requestedBytes":recordAlloc.bytes,
                       "fileBytes":record.count + 32],
        "queue10000":["producerAllocations":queueAlloc.calls],
        "controlRecord1000":["p50":stageCQuantile(controlTimes,numerator:50,denominator:100),
                             "p99":controlP99,
                             "max":controlTimes.max() ?? 0,
                             "samples":controlTimes.count,
                             "limitP99NS":stageCBeginP99LimitNS,
                             "marginNS":Int64(stageCBeginP99LimitNS)-Int64(controlP99),
                             "maxAllocations":controlAllocMax,
                             "fileBytes":controlBytes]
    ]
}

private func stageCDigestString(_ words: [UInt64]) -> String {
    words.map { String(format: "%016llx", $0) }.joined()
}

private func stageCPrepareInitial(directory: String, count: Int)
    throws -> (SwiftWorld, StageCState, StageCWAL, StageCSnapshotFileResult) {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let world = try SwiftWorld(count: count)
    try world.seedFixture()
    let state = StageCState(world: world)
    world.stageCInstall(state)
    let wal = try StageCWAL(directory: directory, epoch: 1)
    let sink = SnapshotSink(directory: directory, epoch: 1, expectedCounts: state.expectedCounts)
    try state.begin(world: world, preparedSink: sink)
    let result = try state.waitForCommit(world: world)
    return (world, state, wal, result)
}

func stageCSmoke(_ directory: String, count: Int) throws -> [String: Any] {
    guard count == 100_000 else { throw ProbeError.invalid("stage C smoke requires 100k") }
    let prepared = try stageCPrepareInitial(directory: directory, count: count)
    try prepared.2.close()
    let restored = try StageCSnapshotRestore.recoverLatest(directory)
    let live = stageCDigestString(Snapshot.worldDigest(prepared.0))
    let back = stageCDigestString(Snapshot.worldDigest(restored.world))
    try require(live == back, "stage C smoke restore")
    return ["status":"pass","variant":"S","assets":count,
            "snapshotBytes":prepared.3.bytes,"exactDigest":true]
}

func stageCRun(_ directory: String, count: Int = 1_000_000,
               requestedSaves: Int = 100, diagnosticOnly: Bool = false) throws -> [String: Any] {
    guard count == 1_000_000, (requestedSaves >= 100 || (diagnosticOnly && requestedSaves == 5)) else {
        throw ProbeError.invalid("stage C requires 1M and >=100 saves")
    }
    let prepared = try stageCPrepareInitial(directory: directory, count: count)
    let world = prepared.0, state = prepared.1
    var wal = prepared.2
    var epoch: UInt32 = 1
    var target: UInt64 = 600
    var firstOperation = UInt64(count * 2 + 1)
    var cycleEvents = 0
    var cycleNumber: UInt32 = 1
    var seen = ContiguousArray(repeating: UInt32(0), count: count)

    var advanceCalls = 0
    var savesStarted = 0
    var savesCommitted = 0
    var beginTimes: [UInt64] = []
    var savingAdvanceTimes: [UInt64] = []
    var writeTimes: [UInt64] = []
    var snapshotSizes: [UInt64] = []
    var peakQueues: [Int] = []
    var barrierBytesPerSave: [Int] = []
    var barrierNSPerSave: [UInt64] = []
    var idleNS: UInt64 = 0, idleEvents = 0
    var savingNS: UInt64 = 0, savingEvents = 0
    var idleMaxAlloc: UInt64 = 0, savingMaxAlloc: UInt64 = 0
    var savingMaxBarrierChunks = 0
    var allocationPairSamples = 0, allocationPairViolations = 0
    var allocationPairMaxExcess: UInt64 = 0
    var firstViolationCall = -1, firstViolationChunks = 0
    var firstViolationAllocations: UInt64 = 0
    var priorResultEpoch: UInt32 = 1

    while savesCommitted < requestedSaves {
        let savingBefore = state.inFlight
        let barrierBefore = state.barrierEmits
        let deadline = nx_now() &+ 1_000_000
        nx_alloc_begin()
        let start = nx_now()
        let p = try world.advance(to: target, budget: 1024, deadlineNS: deadline)
        let end = nx_now()
        let allocations = nx_alloc_end()
        let elapsed = end - start
        advanceCalls += 1
        try wal.appendAdvance(target: target, budget: 1024, units: p.units, events: p.events)

        for i in 0..<p.events {
            let asset = Int(world.output(i).event.asset)
            try require(asset < count && seen[asset] != cycleNumber, "stage C duplicate completion in cycle")
            seen[asset] = cycleNumber
            cycleEvents += 1
        }

        let barrierDelta = state.barrierEmits - barrierBefore
        if savingBefore {
            savingAdvanceTimes.append(elapsed); savingNS += elapsed; savingEvents += p.events
            savingMaxAlloc = max(savingMaxAlloc, allocations.calls)
            savingMaxBarrierChunks = max(savingMaxBarrierChunks, barrierDelta)
            allocationPairSamples += 1
            if allocations.calls > UInt64(barrierDelta) {
                allocationPairViolations += 1
                allocationPairMaxExcess = max(allocationPairMaxExcess, allocations.calls - UInt64(barrierDelta))
                if firstViolationCall == -1 {
                    firstViolationCall = advanceCalls
                    firstViolationAllocations = allocations.calls
                    firstViolationChunks = barrierDelta
                }
            }
            try require(allocations.available == 1, "stage C allocator unavailable")
        } else {
            idleNS += elapsed; idleEvents += p.events
            idleMaxAlloc = max(idleMaxAlloc, allocations.calls)
            try require(allocations.available == 1, "stage C allocator unavailable")
        }

        if p.stop == .target {
            try require(world.wheel.pending == 0 && cycleEvents == count,
                        "stage C target cycle count")
            try stageCRescheduleAll(world, baseNow: target, firstOperation: firstOperation)
            try wal.appendRescheduleAll(baseNow: target, firstOperation: firstOperation)
            firstOperation += UInt64(count)
            target += 600
            cycleEvents = 0
            cycleNumber &+= 1
            if cycleNumber == 0 {
                seen = .init(repeating: 0, count: count)
                cycleNumber = 1
            }
        } else {
            try require(p.stop != .blocked, "stage C advance blocked")
        }

        try state.service(world: world, budgetNS: 500_000)
        if !state.inFlight, state.lastResult != nil, priorResultEpoch < state.epoch {
            let result = state.lastResult!
            writeTimes.append(result.writeNS); snapshotSizes.append(result.bytes)
            peakQueues.append(result.peakQueuedBytes)
            barrierBytesPerSave.append(state.barrierBytes)
            barrierNSPerSave.append(state.barrierNS)
            priorResultEpoch = state.epoch
            savesCommitted += 1
        }

        if advanceCalls % 2_000 == 0 && savesStarted < requestedSaves {
            try require(!state.inFlight, "stage C save did not commit within 2000 advance calls")
            try wal.close()
            epoch &+= 1
            guard epoch > 1 else { throw ProbeError.invalid("stage C epoch overflow") }
            let nextWAL = try StageCWAL(directory: directory, epoch: epoch)
            let sink = SnapshotSink(directory: directory, epoch: epoch,
                                    expectedCounts: state.expectedCounts)
            let begin = nx_now()
            try state.begin(world: world, preparedSink: sink)
            let finish = nx_now()
            beginTimes.append(finish - begin)
            wal = nextWAL
            savesStarted += 1
        }
    }

    while state.inFlight {
        try state.service(world: world, budgetNS: 500_000)
        Thread.sleep(forTimeInterval: 0.00005)
    }
    try wal.close()
    guard savesStarted == requestedSaves, savesCommitted >= requestedSaves,
          !beginTimes.isEmpty, !savingAdvanceTimes.isEmpty,
          idleEvents > 0, savingEvents > 0 else {
        throw ProbeError.invariant("stage C incomplete workload")
    }

    let restoreStart = nx_now()
    let restored = try StageCSnapshotRestore.recoverLatest(directory)
    let restoreNS = nx_now() - restoreStart
    let liveDigest = stageCDigestString(Snapshot.worldDigest(world))
    let restoredDigest = stageCDigestString(Snapshot.worldDigest(restored.world))
    try require(liveDigest == restoredDigest, "stage C recovery != connected state")
    let idleNSEvent = Double(idleNS) / Double(idleEvents)
    let savingNSEvent = Double(savingNS) / Double(savingEvents)
    let overhead = savingNSEvent / idleNSEvent
    let beginP99 = stageCQuantile(beginTimes, numerator: 99, denominator: 100)
    let advanceP99 = stageCQuantile(savingAdvanceTimes, numerator: 99, denominator: 100)
    let beginMargin = Int64(stageCBeginP99LimitNS) - Int64(beginP99)
    let advanceMargin = Int64(stageCAdvanceP99LimitNS) - Int64(advanceP99)
    let overheadMargin = stageCOverheadRatioLimit - overhead

    // Numerical acceptance gates are applied by stage005_c.py after this raw
    // measurement JSON is persisted, so a failing run retains every metric.
    return [
        "status":diagnosticOnly ? "diagnostic" : "measured", "variant":"S", "assets":count, "saves":savesCommitted,
        "advanceCalls":advanceCalls,
        "thresholds":["beginSaveP99NS":stageCBeginP99LimitNS,
                      "advanceDuringSaveP99NS":stageCAdvanceP99LimitNS,
                      "overheadRatio":stageCOverheadRatioLimit,
                      "idleAllocationsPerAdvance":0],
        "beginSaveNS":["p50":stageCQuantile(beginTimes,numerator:50,denominator:100),
                       "p99":beginP99,"max":beginTimes.max() ?? 0,
                       "samples":beginTimes.count,"marginNS":beginMargin],
        "advanceDuringSaveNS":["p50":stageCQuantile(savingAdvanceTimes,numerator:50,denominator:100),
                               "p99":advanceP99,"max":savingAdvanceTimes.max() ?? 0,
                               "samples":savingAdvanceTimes.count,"marginNS":advanceMargin],
        "idleNSPerEvent":idleNSEvent, "saveNSPerEvent":savingNSEvent,
        "idleEvents":idleEvents, "savingEvents":savingEvents,
        "overheadRatio":overhead, "overheadRatioMargin":overheadMargin,
        "snapshotBytes":snapshotSizes.last ?? prepared.3.bytes,
        "snapshotBytesMin":snapshotSizes.min() ?? prepared.3.bytes,
        "snapshotBytesMax":snapshotSizes.max() ?? prepared.3.bytes,
        "writeNS":["p50":stageCQuantile(writeTimes,numerator:50,denominator:100),
                   "p99":stageCQuantile(writeTimes,numerator:99,denominator:100),
                   "max":writeTimes.max() ?? 0,"samples":writeTimes.count],
        "restoreNS":restoreNS,
        "peakQueuedBytes":peakQueues.max() ?? prepared.3.peakQueuedBytes,
        "barrierCopy":["bytesPerSave":barrierBytesPerSave,
                       "nsPerSave":barrierNSPerSave,
                       "samples":barrierNSPerSave.count,
                       "nsP50":stageCQuantile(barrierNSPerSave,numerator:50,denominator:100),
                       "nsP99":stageCQuantile(barrierNSPerSave,numerator:99,denominator:100),
                       "nsMax":barrierNSPerSave.max() ?? 0],
        "allocationsIdleMaxPerAdvance":idleMaxAlloc,
        "allocationsWhileSavingMaxPerAdvance":savingMaxAlloc,
        "barrierChunksMaxPerAdvance":savingMaxBarrierChunks,
        "allocationPairing":["samples":allocationPairSamples,
            "violations":allocationPairViolations,"maxExcess":allocationPairMaxExcess,
            "firstViolationCall":firstViolationCall,"firstViolationAllocations":firstViolationAllocations,
            "firstViolationChunks":firstViolationChunks],
        "recoveredEpoch":restored.epoch,
        "replayedCommands":restored.replayedCommands,
        "ignoredWALTailBytes":restored.ignoredWALTailBytes,
        "exactRecoveredDigest":liveDigest,
        "limits":"Apple CI process/SIGKILL proof; WAL full-record process persistence, not physical power-cut certification; not iPhone acceptance"
    ]
}

func stageCCrashBootstrap(_ directory: String, count: Int) throws -> [String: Any] {
    guard count == 1_000_000 else { throw ProbeError.invalid("stage C crash population") }
    let prepared = try stageCPrepareInitial(directory: directory, count: count)
    try prepared.2.close()
    let digest = stageCDigestString(Snapshot.worldDigest(prepared.0))
    return ["status":"pass","epoch":1,"digest":digest,"snapshotBytes":prepared.3.bytes]
}

func stageCCrashAction(_ directory: String, point: String) throws -> [String: Any] {
    let recovered = try StageCSnapshotRestore.recoverLatest(directory)
    let world = recovered.world
    let baseline = stageCDigestString(Snapshot.worldDigest(world))
    let state = StageCState(world: world); world.stageCInstall(state)
    guard recovered.epoch == 1 else { throw ProbeError.invariant("stage C crash base epoch") }
    let wal2 = try StageCWAL(directory: directory, epoch: 2)
    let sink = SnapshotSink(directory: directory, epoch: 2, expectedCounts: state.expectedCounts)
    try state.begin(world: world, preparedSink: sink)

    if point == "c.k2.after_first_barrier" {
        _ = try world.advance(to: 600, budget: 1)
    } else if point == "c.k9.mid_wal_record" {
        _ = try state.waitForCommit(world: world)
        let p = try world.advance(to: 600, budget: 1)
        try wal2.appendAdvance(target: 600, budget: 1, units: p.units, events: p.events)
    } else {
        _ = try state.waitForCommit(world: world)
    }
    try wal2.close()
    return ["status":"unexpected-no-kill","baseline":baseline]
}

func stageCWALChainExpected(_ directory: String) throws -> [String: Any] {
    let recovered = try StageCSnapshotRestore.recoverLatest(directory)
    guard recovered.epoch == 1 else { throw ProbeError.invariant("stage C chain base epoch") }
    let world = recovered.world
    let p = try world.advance(to: 600, budget: 1)
    try require(p.events == 1, "stage C chain expected event")
    return ["status":"pass","processed":world.processed,
            "digest":stageCDigestString(Snapshot.worldDigest(world))]
}

func stageCWALChainCrashAction(_ directory: String) throws -> [String: Any] {
    let recovered = try StageCSnapshotRestore.recoverLatest(directory)
    guard recovered.epoch == 1 else { throw ProbeError.invariant("stage C chain crash base epoch") }
    let world = recovered.world
    let state = StageCState(world: world); world.stageCInstall(state)
    let wal2 = try StageCWAL(directory: directory, epoch: 2)
    let sink = SnapshotSink(directory: directory, epoch: 2, expectedCounts: state.expectedCounts)
    try state.begin(world: world, preparedSink: sink)
    let p = try world.advance(to: 600, budget: 1)
    try require(p.events == 1, "stage C chain crash event")
    try wal2.appendAdvance(target: 600, budget: 1, units: p.units, events: p.events)
    nx_kill_point("c.chain.after_wal")
    try wal2.close()
    return ["status":"unexpected-no-kill"]
}

func stageCRecoverCrash(_ directory: String) throws -> [String: Any] {
    let start = nx_now()
    let recovered = try StageCSnapshotRestore.recoverLatest(directory)
    let elapsed = nx_now() - start
    return ["status":"pass","epoch":recovered.epoch,
            "digest":stageCDigestString(Snapshot.worldDigest(recovered.world)),
            "processed":recovered.world.processed,
            "sequenceHash":recovered.world.sequenceHash,
            "replayedCommands":recovered.replayedCommands,
            "ignoredWALTailBytes":recovered.ignoredWALTailBytes,
            "restoreNS":elapsed]
}
#endif
