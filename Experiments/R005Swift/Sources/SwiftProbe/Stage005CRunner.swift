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
    // Diagnostics only, updated after both the timer and allocation scope.
    var phaseNS = [UInt64](repeating: 0, count: 3)
    var phaseEvents = [Int](repeating: 0, count: 3)
    var phaseUnits = [Int](repeating: 0, count: 3)
    var phaseCalls = [Int](repeating: 0, count: 3)
    var phaseBarrierChunks = [Int](repeating: 0, count: 3)

    while savesCommitted < requestedSaves {
        let savingBefore = state.inFlight
        let phase = savingBefore ? (state.capturing ? 1 : 2) : 0
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
        phaseNS[phase] += elapsed; phaseEvents[phase] += p.events
        phaseUnits[phase] += p.units; phaseCalls[phase] += 1
        phaseBarrierChunks[phase] += barrierDelta
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

    try require(phaseNS[0] == idleNS && phaseNS[1] + phaseNS[2] == savingNS &&
                phaseEvents[0] == idleEvents && phaseEvents[1] + phaseEvents[2] == savingEvents &&
                phaseCalls.reduce(0, +) == advanceCalls,
                "stage C phase diagnostics must cover every measured call")
    var phases: [String: Any] = [:]
    for (i, name) in ["idle", "capturing", "writerOnly"].enumerated() {
        phases[name] = ["ns":phaseNS[i], "events":phaseEvents[i], "workUnits":phaseUnits[i],
                        "calls":phaseCalls[i], "barrierChunks":phaseBarrierChunks[i],
                        "nsPerEvent":phaseEvents[i] > 0 ? Double(phaseNS[i])/Double(phaseEvents[i]) : 0,
                        "nsPerWorkUnit":phaseUnits[i] > 0 ? Double(phaseNS[i])/Double(phaseUnits[i]) : 0]
    }
    // Numerical acceptance gates are applied by stage005_c.py after this raw
    // measurement JSON is persisted, so a failing run retains every metric.
    return [
        "status":diagnosticOnly ? "diagnostic" : "measured", "variant":"S", "assets":count, "saves":savesCommitted,
        "advanceCalls":advanceCalls, "simulationPhases":phases,
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

// Diagnostic-only fixed-work telemetry.  This deliberately does not share the
// deadline-shaped C acceptance loop or its evaluator.
private struct StageCPairedScriptCall: Equatable {
    let events: Int
    let units: Int
    let stop: String
    let reached: UInt64
}

private struct StageCPairedMeasurement {
    let elapsedNS: UInt64
    let allocations: UInt64
    let allocationBytes: UInt64

    func json() -> [String: Any] {
        ["ns": elapsedNS, "allocations": allocations, "allocationBytes": allocationBytes]
    }
}

private func stageCPairedMeasure<T>(_ name: String, _ body: () throws -> T)
    throws -> (value: T, measurement: StageCPairedMeasurement) {
    nx_alloc_begin()
    let start = nx_now()
    let value: T
    do {
        value = try body()
    } catch {
        _ = nx_alloc_end()
        throw error
    }
    let elapsed = nx_now() - start
    let allocation = nx_alloc_end()
    try require(allocation.available == 1, "paired profile \(name) allocator unavailable")
    return (value, StageCPairedMeasurement(elapsedNS: elapsed,
                                            allocations: allocation.calls,
                                            allocationBytes: allocation.bytes))
}

private struct StageCPairedServiceSample {
    let phase: String
    let elapsedNS: UInt64
    let allocations: UInt64
    let allocationBytes: UInt64
    let barrierEmits: Int
}

private struct StageCPairedCallSample {
    let ordinal: Int
    let script: StageCPairedScriptCall
    let stateMode: String
    let saveActive: Bool
    let advanceNS: UInt64
    let advanceAllocations: UInt64
    let advanceAllocationBytes: UInt64
    let walAdvanceNS: UInt64
    let walAdvanceAllocations: UInt64
    let walAdvanceAllocationBytes: UInt64
    let service: StageCPairedServiceSample?

    func json() -> [String: Any] {
        var result: [String: Any] = [
            "ordinal": ordinal,
            "events": script.events,
            "workUnits": script.units,
            "stop": script.stop,
            "reached": script.reached,
            "stateMode": stateMode,
            "saveActive": saveActive,
            "advanceNS": advanceNS,
            "advanceAllocations": advanceAllocations,
            "advanceAllocationBytes": advanceAllocationBytes,
            "walAdvanceNS": walAdvanceNS,
            "walAdvanceAllocations": walAdvanceAllocations,
            "walAdvanceAllocationBytes": walAdvanceAllocationBytes
        ]
        if let service {
            result["service"] = [
                "phase": service.phase,
                "ns": service.elapsedNS,
                "allocations": service.allocations,
                "allocationBytes": service.allocationBytes,
                "barrierEmits": service.barrierEmits
            ]
        }
        return result
    }
}

private struct StageCPairedLegResult {
    let script: [StageCPairedScriptCall]
    let outputHash: String
    let finalDigest: String
    let stateInstallAfterAdvanceCalls: Int
    let json: [String: Any]
}

private func stageCPairedService(_ state: StageCState, world: SwiftWorld) throws -> StageCPairedServiceSample {
    let phase = state.capturing ? "capturing" : (state.inFlight ? "writerOnly" : "committed")
    let barrierBefore = state.barrierEmits
    let measured = try stageCPairedMeasure("service") {
        try state.service(world: world, budgetNS: 500_000)
    }
    return StageCPairedServiceSample(phase: phase, elapsedNS: measured.measurement.elapsedNS,
        allocations: measured.measurement.allocations,
        allocationBytes: measured.measurement.allocationBytes,
        barrierEmits: state.barrierEmits - barrierBefore)
}

private func stageCPairedLeg(fixtureDirectory: String, directory: String,
                             count: Int, saveStartCall: Int, save: Bool,
                             label: String, fixtureDigest: String) throws -> StageCPairedLegResult {
    let legStart = nx_now()
    let (_, fixtureCopy) = try stageCPairedMeasure("fixture copy") {
        try FileManager.default.copyItem(atPath: fixtureDirectory, toPath: directory)
    }
    let fixtureRecovery = try stageCPairedMeasure("fixture recovery") {
        try StageCSnapshotRestore.recoverLatest(directory)
    }
    let restored = fixtureRecovery.value
    guard restored.epoch == 1, restored.terminalWALEpoch == 1,
          restored.ignoredWALTailBytes == 0 else {
        throw ProbeError.invariant("paired profile fixture epoch")
    }
    let world = restored.world
    let initialDigest = stageCDigestString(Snapshot.worldDigest(world))
    try require(initialDigest == fixtureDigest, "paired profile fixture digest")

    let budget = 1_024
    let target: UInt64 = 600
    let profileStart = nx_now()
    let resumedWAL = try stageCPairedMeasure("WAL resume") {
        try StageCWAL.resume(directory: directory, epoch: restored.terminalWALEpoch,
                             replay: restored.terminalWALReplay)
    }
    var wal = resumedWAL.value
    var walTransitionClose: StageCPairedMeasurement? = nil
    var walTransitionOpen: StageCPairedMeasurement? = nil
    var walTransitioned = false
    var state: StageCState? = nil
    var stateInstall: StageCPairedMeasurement? = nil
    var sinkSetup: StageCPairedMeasurement? = nil
    var beginSave: StageCPairedMeasurement? = nil
    var stateInstallAfterAdvanceCalls = -1
    var advanceNS: UInt64 = 0
    var advanceAllocations: UInt64 = 0
    var advanceAllocationBytes: UInt64 = 0
    var walAdvanceNS: UInt64 = 0
    var walAdvanceAllocations: UInt64 = 0
    var walAdvanceAllocationBytes: UInt64 = 0
    var serviceNS: UInt64 = 0
    var serviceAllocations: UInt64 = 0
    var serviceAllocationBytes: UInt64 = 0
    var serviceCaptureNS: UInt64 = 0
    var serviceWriterOnlyNS: UInt64 = 0
    var serviceBarrierEmits = 0
    var rescheduleNS: UInt64 = 0
    var rescheduleAllocations: UInt64 = 0
    var rescheduleAllocationBytes: UInt64 = 0
    var rescheduleBarrierEmits = 0
    var walRescheduleNS: UInt64 = 0
    var walRescheduleAllocations: UInt64 = 0
    var walRescheduleAllocationBytes: UInt64 = 0
    var writerWaitNS: UInt64 = 0
    var drainServiceCalls = 0
    var cycleEvents = 0
    var advanceCalls = 0
    var outputHash: UInt64 = 14695981039346656037
    var script: [StageCPairedScriptCall] = []
    var calls: [StageCPairedCallSample] = []
    let estimatedCalls = max(64, count / budget + 128)
    script.reserveCapacity(estimatedCalls)
    calls.reserveCapacity(estimatedCalls)

    func accumulateService(_ sample: StageCPairedServiceSample) {
        serviceNS &+= sample.elapsedNS
        serviceAllocations &+= sample.allocations
        serviceAllocationBytes &+= sample.allocationBytes
        serviceBarrierEmits += sample.barrierEmits
        if sample.phase == "capturing" { serviceCaptureNS &+= sample.elapsedNS }
        if sample.phase == "writerOnly" { serviceWriterOnlyNS &+= sample.elapsedNS }
    }

    while true {
        if advanceCalls == saveStartCall {
            let closedWAL = try stageCPairedMeasure("WAL transition close") {
                try wal.close()
            }
            walTransitionClose = closedWAL.measurement
            let nextWAL = try stageCPairedMeasure("WAL transition open") {
                try StageCWAL(directory: directory, epoch: 2)
            }
            wal = nextWAL.value
            walTransitionOpen = nextWAL.measurement
            walTransitioned = true
            let installedState = try stageCPairedMeasure("state install") {
                let nextState = StageCState(world: world)
                world.stageCInstall(nextState)
                return nextState
            }
            state = installedState.value
            stateInstall = installedState.measurement
            stateInstallAfterAdvanceCalls = advanceCalls
            if save {
                guard let installedState = state else {
                    throw ProbeError.invariant("paired profile state install")
                }
                let preparedSink = try stageCPairedMeasure("snapshot sink setup") {
                    SnapshotSink(directory: directory, epoch: 2, expectedCounts: installedState.expectedCounts)
                }
                sinkSetup = preparedSink.measurement
                let beganSave = try stageCPairedMeasure("begin save") {
                    try installedState.begin(world: world, preparedSink: preparedSink.value)
                }
                beginSave = beganSave.measurement
            }
        }

        let stateMode: String
        if let state {
            stateMode = state.capturing ? "capturing" : (state.inFlight ? "writerOnly" : "idleInstalled")
        } else {
            stateMode = "notInstalled"
        }
        let saveActive = state?.inFlight ?? false
        nx_alloc_begin()
        let advanceStart = nx_now()
        let progress = try world.advance(to: target, budget: budget, workBudget: 65_536,
                                         deadlineNS: UInt64.max)
        let elapsed = nx_now() - advanceStart
        let allocation = nx_alloc_end()
        try require(allocation.available == 1, "paired profile advance allocator unavailable")
        advanceNS &+= elapsed
        advanceAllocations &+= allocation.calls
        advanceAllocationBytes &+= allocation.bytes

        nx_alloc_begin()
        let walStart = nx_now()
        try wal.appendAdvance(target: target, budget: budget, units: progress.units, events: progress.events)
        let walElapsed = nx_now() - walStart
        let walAllocation = nx_alloc_end()
        try require(walAllocation.available == 1, "paired profile WAL allocator unavailable")
        walAdvanceNS &+= walElapsed
        walAdvanceAllocations &+= walAllocation.calls
        walAdvanceAllocationBytes &+= walAllocation.bytes

        for i in 0..<progress.events {
            let completion = world.output(i)
            outputHash = (outputHash ^ completion.event.operation) &* 1099511628211
            outputHash = (outputHash ^ UInt64(completion.event.asset)) &* 1099511628211
            outputHash = (outputHash ^ completion.completed) &* 1099511628211
            cycleEvents += 1
        }

        var serviceSample: StageCPairedServiceSample? = nil
        if let state {
            let sample = try stageCPairedService(state, world: world)
            accumulateService(sample)
            serviceSample = sample
        }
        advanceCalls += 1
        let scriptCall = StageCPairedScriptCall(events: progress.events, units: progress.units,
                                                stop: progress.stop.rawValue, reached: progress.reached)
        script.append(scriptCall)
        calls.append(StageCPairedCallSample(ordinal: advanceCalls, script: scriptCall,
            stateMode: stateMode, saveActive: saveActive, advanceNS: elapsed, advanceAllocations: allocation.calls,
            advanceAllocationBytes: allocation.bytes, walAdvanceNS: walElapsed,
            walAdvanceAllocations: walAllocation.calls,
            walAdvanceAllocationBytes: walAllocation.bytes, service: serviceSample))

        if progress.stop == .target {
            try require(world.wheel.pending == 0 && cycleEvents == count,
                        "paired profile target cycle count")
            guard let installedState = state else {
                throw ProbeError.invariant("paired profile state missing at target")
            }
            let barrierBefore = installedState.barrierEmits
            nx_alloc_begin()
            let rescheduleStart = nx_now()
            try stageCRescheduleAll(world, baseNow: target, firstOperation: UInt64(count * 2 + 1))
            rescheduleNS = nx_now() - rescheduleStart
            let rescheduleAllocation = nx_alloc_end()
            try require(rescheduleAllocation.available == 1, "paired profile reschedule allocator unavailable")
            rescheduleAllocations = rescheduleAllocation.calls
            rescheduleAllocationBytes = rescheduleAllocation.bytes
            rescheduleBarrierEmits = installedState.barrierEmits - barrierBefore

            nx_alloc_begin()
            let walRescheduleStart = nx_now()
            try wal.appendRescheduleAll(baseNow: target, firstOperation: UInt64(count * 2 + 1))
            walRescheduleNS = nx_now() - walRescheduleStart
            let walRescheduleAllocation = nx_alloc_end()
            try require(walRescheduleAllocation.available == 1, "paired profile WAL reschedule allocator unavailable")
            walRescheduleAllocations = walRescheduleAllocation.calls
            walRescheduleAllocationBytes = walRescheduleAllocation.bytes
            break
        }
        try require(progress.stop != .blocked, "paired profile advance blocked")
        try require(advanceCalls < count * 4, "paired profile advance bound")
    }

    try require(walTransitioned, "paired profile save boundary not reached")
    if let state {
        while state.inFlight {
            let sample = try stageCPairedService(state, world: world)
            accumulateService(sample)
            drainServiceCalls += 1
            try require(drainServiceCalls <= 5_000_000, "paired profile writer timeout")
            if state.inFlight {
                let waitStart = nx_now()
                Thread.sleep(forTimeInterval: 0.00005)
                writerWaitNS &+= nx_now() - waitStart
            }
        }
    }
    let (_, walFinalClose) = try stageCPairedMeasure("WAL final close") {
        try wal.close()
    }
    let profileLoopNS = nx_now() - profileStart

    let finalDigest = stageCDigestString(Snapshot.worldDigest(world))
    let finalRecovery = try stageCPairedMeasure("final recovery") {
        try StageCSnapshotRestore.recoverLatest(directory)
    }
    let recovered = finalRecovery.value
    let recoveryDigest = stageCDigestString(Snapshot.worldDigest(recovered.world))
    try require(recoveryDigest == finalDigest, "paired profile recovery digest")
    let endToEndNS = nx_now() - legStart
    guard let installedState = state,
          let stateInstallMeasurement = stateInstall,
          let walTransitionCloseMeasurement = walTransitionClose,
          let walTransitionOpenMeasurement = walTransitionOpen else {
        throw ProbeError.invariant("paired profile missing boundary measurements")
    }
    let writer = installedState.lastResult
    if save { try require(writer != nil, "paired profile save did not commit") }
    let outputHashString = String(format: "%016llx", outputHash)

    var result: [String: Any] = [
        "label": label,
        "saveEnabled": save,
        "postBoundaryControlStateInstalled": !save,
        "stateInstallAfterAdvanceCalls": stateInstallAfterAdvanceCalls,
        "initialDigest": initialDigest,
        "finalDigest": finalDigest,
        "recoveryDigest": recoveryDigest,
        "recoveryExact": true,
        "recoveryNS": finalRecovery.measurement.elapsedNS,
        "advanceCalls": advanceCalls,
        "events": cycleEvents,
        "outputHash": outputHashString,
        "calls": calls.map { $0.json() },
        "fixtureTransport": ["copy": fixtureCopy.json(),
                             "recovery": fixtureRecovery.measurement.json(),
                             "finalRecovery": finalRecovery.measurement.json()],
        "simulationThread": [
            "setup": ["stateInstall": stateInstallMeasurement.json(),
                      "snapshotSink": sinkSetup?.json() ?? ["started": false],
                      "beginSave": beginSave?.json() ?? ["started": false]],
            "advance": ["ns": advanceNS, "allocations": advanceAllocations,
                        "allocationBytes": advanceAllocationBytes],
            "walAdvance": ["ns": walAdvanceNS, "allocations": walAdvanceAllocations,
                           "allocationBytes": walAdvanceAllocationBytes],
            "service": ["ns": serviceNS, "capturingNS": serviceCaptureNS,
                        "writerOnlyNS": serviceWriterOnlyNS, "allocations": serviceAllocations,
                        "allocationBytes": serviceAllocationBytes,
                        "barrierEmits": serviceBarrierEmits, "drainCalls": drainServiceCalls],
            "reschedule": ["ns": rescheduleNS, "allocations": rescheduleAllocations,
                           "allocationBytes": rescheduleAllocationBytes,
                           "barrierEmits": rescheduleBarrierEmits],
            "walReschedule": ["ns": walRescheduleNS, "allocations": walRescheduleAllocations,
                              "allocationBytes": walRescheduleAllocationBytes]
        ],
        "walLifecycle": ["resume": resumedWAL.measurement.json(),
                         "transitionClose": walTransitionCloseMeasurement.json(),
                         "transitionOpen": walTransitionOpenMeasurement.json(),
                         "finalClose": walFinalClose.json()],
        "fullLoopNS": profileLoopNS,
        "endToEndNS": endToEndNS,
        "writerPollSleepNS": writerWaitNS,
        "barrier": ["emits": installedState.barrierEmits,
                    "bytes": installedState.barrierBytes,
                    "copyNS": installedState.barrierNS]
    ]
    if let writer {
        result["writer"] = [
            "runNS": writer.writeNS,
            "dispatchToRunNS": writer.dispatchToRunNS,
            "queueWaitNS": writer.queueWaitNS,
            "recordProcessWriteNS": writer.recordProcessWriteNS,
            "finalizeNS": writer.finalizeNS,
            "bytes": writer.bytes,
            "chunks": writer.chunks,
            "peakQueuedBytes": writer.peakQueuedBytes,
            "allocations": writer.writerAllocations,
            "allocationBytes": writer.writerAllocationBytes,
            "allocationObserverAvailable": writer.writerAllocationObserverAvailable
        ]
    } else {
        result["writer"] = ["started": false]
    }
    return StageCPairedLegResult(script: script, outputHash: outputHashString,
                                 finalDigest: finalDigest,
                                 stateInstallAfterAdvanceCalls: stateInstallAfterAdvanceCalls,
                                 json: result)
}

private func stageCPairedProfileRun(_ directory: String, count: Int,
                                    smoke: Bool) throws -> [String: Any] {
    guard count == 4_096 || count == 1_000_000 else {
        throw ProbeError.invalid("paired profile requires 4096 or 1M assets")
    }
    guard !FileManager.default.fileExists(atPath: directory) else {
        throw ProbeError.invalid("paired profile directory already exists")
    }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let fixtureDirectory = directory + "/fixture"
    let prepared = try stageCPrepareInitial(directory: fixtureDirectory, count: count)
    try prepared.2.close()
    let fixtureDigest = stageCDigestString(Snapshot.worldDigest(prepared.0))
    let saveStartCall = count == 1_000_000 ? 64 : 2
    let orders: [[Bool]] = smoke ? [[false, true]] : [[false, true], [true, false]]
    var pairs: [[String: Any]] = []

    for (pairIndex, order) in orders.enumerated() {
        var legs: [StageCPairedLegResult] = []
        for (ordinal, save) in order.enumerated() {
            let name = save ? "save" : "no-save"
            let legDirectory = directory + "/pair-\(pairIndex + 1)-\(ordinal + 1)-\(name)"
            legs.append(try stageCPairedLeg(fixtureDirectory: fixtureDirectory, directory: legDirectory,
                                            count: count, saveStartCall: saveStartCall, save: save,
                                            label: name, fixtureDigest: fixtureDigest))
        }
        try require(legs.count == 2, "paired profile pair shape")
        let logicalTranscriptExact = legs[0].script == legs[1].script
        let outputHashExact = legs[0].outputHash == legs[1].outputHash
        let finalDigestExact = legs[0].finalDigest == legs[1].finalDigest
        let stateInstallAligned = legs[0].stateInstallAfterAdvanceCalls == saveStartCall &&
            legs[1].stateInstallAfterAdvanceCalls == saveStartCall
        try require(logicalTranscriptExact && outputHashExact && finalDigestExact && stateInstallAligned,
                    "paired profile exactness mismatch")
        pairs.append([
            "pair": pairIndex + 1,
            "order": order.map { $0 ? "save" : "no-save" },
            "logicalTranscriptExact": logicalTranscriptExact,
            "outputHashExact": outputHashExact,
            "finalDigestExact": finalDigestExact,
            "stateInstallAligned": stateInstallAligned,
            "legs": legs.map { $0.json }
        ])
    }
    return [
        "status": "diagnostic",
        "acceptance": false,
        "scope": smoke ? "4096 paired smoke; not Stage C acceptance" :
                          "1M paired S diagnostic; not Stage C acceptance",
        "instrumentation": "Writer telemetry uses per-record clocks and allocator observation; paired timings are diagnostic only, not uninstrumented production-C timing.",
        "variant": "S",
        "assets": count,
        "fixture": ["initialEpoch": 1, "digest": fixtureDigest,
                    "snapshotBytes": prepared.3.bytes, "target": 600,
                    "budget": 1_024, "workBudget": 65_536,
                    "saveStartCall": saveStartCall, "deadline": "none",
                    "postBoundaryNoSave": "installed idle StageCState"],
        "pairs": pairs,
        "limits": "Fixed-work paired diagnosis keeps WAL/reschedule in both arms. It changes no official C timer, deadline, cadence, formula or gate and is not a 100-save result."
    ]
}

func stageCPairedProfileSmoke(_ directory: String) throws -> [String: Any] {
    try stageCPairedProfileRun(directory, count: 4_096, smoke: true)
}

func stageCPairedProfile(_ directory: String) throws -> [String: Any] {
    try stageCPairedProfileRun(directory, count: 1_000_000, smoke: false)
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

func stageCWALResumeAppend(_ directory: String) throws -> [String: Any] {
    let recovered = try StageCSnapshotRestore.recoverLatest(directory)
    try require(recovered.ignoredWALTailBytes > 0, "stage C resume requires torn terminal WAL")
    let oldSequence = recovered.terminalWALReplay.commands
    let priorDigest = stageCDigestString(Snapshot.worldDigest(recovered.world))
    let walPath = directory + "/wal-\(recovered.terminalWALEpoch).log"
    let originalWAL = try Data(contentsOf: URL(fileURLWithPath: walPath))
    let expectedTail = Data(originalWAL.suffix(recovered.ignoredWALTailBytes))
    let wal = try StageCWAL.resume(directory: directory, epoch: recovered.terminalWALEpoch,
                                  replay: recovered.terminalWALReplay)
    try require(wal.sequence == oldSequence, "stage C WAL resume sequence")
    guard let discardedTailPath = wal.discardedTailPath else {
        throw ProbeError.invariant("stage C missing discarded WAL tail archive")
    }
    try require(try Data(contentsOf: URL(fileURLWithPath: discardedTailPath)) == expectedTail,
                "stage C discarded WAL tail exact archive")
    let p = try recovered.world.advance(to: 600, budget: 1)
    try require(p.events == 1 && p.units > 0, "stage C resume next event")
    try wal.appendAdvance(target: 600, budget: 1, units: p.units, events: p.events)
    try wal.synchronize()
    try wal.close()
    let expectedDigest = stageCDigestString(Snapshot.worldDigest(recovered.world))
    let again = try StageCSnapshotRestore.recoverLatest(directory)
    try require(again.epoch == recovered.epoch &&
                again.terminalWALEpoch == recovered.terminalWALEpoch &&
                again.terminalWALReplay.commands == oldSequence + 1 &&
                again.replayedCommands == recovered.replayedCommands + 1 &&
                again.ignoredWALTailBytes == 0 &&
                again.terminalWALReplay.validBytes == recovered.terminalWALReplay.validBytes + 72 &&
                stageCDigestString(Snapshot.worldDigest(again.world)) == expectedDigest,
                "stage C resume append second recovery")
    return ["status":"pass", "variant":"S", "assets":recovered.world.count,
            "snapshotEpoch":recovered.epoch, "walEpoch":recovered.terminalWALEpoch,
            "priorDigest":priorDigest, "exactDigest":expectedDigest,
            "priorTailBytes":recovered.ignoredWALTailBytes,
            "discardedTailArchived":true,
            "priorWALSequence":oldSequence, "finalWALSequence":again.terminalWALReplay.commands,
            "secondRecoveryExact":true]
}

// A prefix of a real second frame, used only by the continuation fixtures.
func stageCWALPartialAdvanceFrame(sequence: UInt64, prefixBytes: Int) -> [UInt8] {
    var frame = Data(capacity: 72)
    Snapshot.appendLE(UInt32(72), into: &frame)
    frame.append(StageCWALKind.advance.rawValue)
    frame.append(contentsOf: [0, 0, 0])
    Snapshot.appendLE(sequence, into: &frame)
    Snapshot.appendLE(UInt64(600), into: &frame)
    Snapshot.appendLE(UInt32(1), into: &frame)
    Snapshot.appendLE(UInt32(1), into: &frame)
    Snapshot.appendLE(UInt32(1), into: &frame)
    Snapshot.appendLE(UInt32(0), into: &frame)
    let digest = Snapshot.digestData(frame)
    frame.append(digest)
    precondition(frame.count == 72 && prefixBytes > 0 && prefixBytes < frame.count)
    return [UInt8](frame.prefix(prefixBytes))
}

func stageCWALContinuationFixture(_ directory: String) throws -> [String: Any] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let tails: [(String, [UInt8])] = [
        ("short-header", stageCWALPartialAdvanceFrame(sequence: 2, prefixBytes: 2)),
        ("short-body", stageCWALPartialAdvanceFrame(sequence: 2, prefixBytes: 8)),
        ("short-digest", stageCWALPartialAdvanceFrame(sequence: 2, prefixBytes: 54))
    ]
    var cases: [[String: Any]] = []
    for (name, tail) in tails {
        let path = directory + "/" + name
        let prepared = try stageCPrepareInitial(directory: path, count: 4_096)
        let first = try prepared.0.advance(to: 600, budget: 1)
        try require(first.events == 1, "stage C continuation first event")
        try prepared.2.appendAdvance(target: 600, budget: 1, units: first.units, events: first.events)
        try prepared.2.close()
        let file = path + "/wal-1.log"
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        try h.seekToEnd()
        try h.write(contentsOf: Data(tail))
        try h.synchronize()
        try h.close()
        let before = try StageCSnapshotRestore.recoverLatest(path)
        try require(before.terminalWALReplay.commands == 1 &&
                    before.ignoredWALTailBytes == tail.count &&
                    stageCDigestString(Snapshot.worldDigest(before.world)) ==
                        stageCDigestString(Snapshot.worldDigest(prepared.0)),
                    "stage C continuation valid prefix")
        let result = try stageCWALResumeAppend(path)
        try require(result["finalWALSequence"] as? UInt64 == 2,
                    "stage C continuation sequence after append")
        cases.append(["tail":name, "discardedBytes":tail.count,
                      "secondRecoveryExact":true, "finalSequence":2])
    }

    let corruptPath = directory + "/complete-frame-corrupt"
    let prepared = try stageCPrepareInitial(directory: corruptPath, count: 4_096)
    let first = try prepared.0.advance(to: 600, budget: 1)
    try prepared.2.appendAdvance(target: 600, budget: 1, units: first.units, events: first.events)
    try prepared.2.close()
    let lengthPath = directory + "/complete-length-corrupt"
    try FileManager.default.copyItem(atPath: corruptPath, toPath: lengthPath)
    let file = corruptPath + "/wal-1.log"
    var bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: file)))
    try require(bytes.count == 16 + 72, "stage C complete WAL frame size")
    bytes[16 + 20] ^= 1
    try Data(bytes).write(to: URL(fileURLWithPath: file), options: .atomic)
    var rejected = false
    do { _ = try StageCSnapshotRestore.recoverLatest(corruptPath) }
    catch ProbeError.corruption { rejected = true }
    try require(rejected, "stage C complete frame corruption must fail closed")
    let lengthFile = lengthPath + "/wal-1.log"
    var lengthBytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: lengthFile)))
    lengthBytes[16] = 73 // Header declares more than the complete 72-byte frame.
    try Data(lengthBytes).write(to: URL(fileURLWithPath: lengthFile), options: .atomic)
    var rejectedLength = false
    do { _ = try StageCSnapshotRestore.recoverLatest(lengthPath) }
    catch ProbeError.corruption { rejectedLength = true }
    let unchangedLengthFile = try Data(contentsOf: URL(fileURLWithPath: lengthFile))
    try require(rejectedLength && unchangedLengthFile == Data(lengthBytes),
                "stage C corrupt complete length cannot become torn tail")
    return ["status":"pass", "variant":"S", "population":4_096,
            "continuationCases":cases, "completeFrameCorruptionRejected":rejected,
            "completeLengthCorruptionRejected":rejectedLength]
}
#endif
