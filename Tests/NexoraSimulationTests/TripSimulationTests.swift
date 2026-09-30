import Testing
import NexoraIdentity
import NexoraAviation
@testable import NexoraSimulation

func verifyTrip(_ condition: Bool, fileID: String = #fileID, filePath: String = #filePath,
                line: Int = #line, column: Int = #column) {
    #expect(condition, sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                                     line: line, column: column))
}
@discardableResult
func register(_ simulation: inout TripSimulation, airport: UInt32 = 1) throws -> EntityHandle {
    try simulation.apply(.registerAircraft(at: airport), expected: simulation.inputToken).handle
}
@discardableResult
func depart(_ simulation: inout TripSimulation, _ handle: EntityHandle,
            to airport: UInt32 = 2, duration: UInt64 = 10) throws -> ScheduledArrival {
    let result = try simulation.apply(.depart(handle, destination: airport, durationSeconds: duration),
                                      expected: simulation.inputToken)
    return try #require(result.activeTrip)
}
func rejectTrip(_ command: TripCommand, _ expectedError: TripFailure,
                simulation: inout TripSimulation, token: TripInputToken? = nil) {
    let before = simulation.auditForTesting()
    do {
        _ = try simulation.apply(command, expected: token ?? simulation.inputToken)
        Issue.record("Expected input rejection")
    } catch { verifyTrip(error as? TripFailure == expectedError) }
    verifyTrip(before == simulation.auditForTesting())
    verifyTrip(simulation.checkInvariants())
}
func rejectAdvance(_ target: UInt64, budget: Int, _ expectedError: TripFailure,
                   simulation: inout TripSimulation) {
    let before = simulation.auditForTesting()
    do { _ = try simulation.advance(to: target, eventBudget: budget); Issue.record("Expected advance rejection") }
    catch { verifyTrip(error as? TripFailure == expectedError) }
    verifyTrip(before == simulation.auditForTesting())
    verifyTrip(simulation.checkInvariants())
}

struct TripSimulationTests {
    @Test(arguments: [-1, 1_000_001, Int.max])
    func S01_invalidCapacities(_ bad: Int) {
        do { _ = try TripSimulation(capacity: bad, eventCapacity: 0); Issue.record("Expected bad capacity") }
        catch { verifyTrip(error as? TripFailure == .invalidCapacity) }
        do { _ = try TripSimulation(capacity: 0, eventCapacity: bad); Issue.record("Expected bad queue capacity") }
        catch { verifyTrip(error as? TripFailure == .invalidCapacity) }
    }

    @Test func S02_emptyWorldHasHonestTime() throws {
        var simulation = try TripSimulation(capacity: 0, eventCapacity: 0)
        let result = try simulation.advance(to: 1_000, eventBudget: 1)
        verifyTrip(result.fromTime == 0 && result.reachedTime == 1_000 && result.requestedTime == 1_000)
        verifyTrip(result.processedEvents == 0 && result.nextDueTime == nil && result.stop == .reachedTarget)
        verifyTrip(simulation.checkInvariants())
        rejectTrip(.registerAircraft(at: 1), .aircraft(.capacityExhausted), simulation: &simulation)
    }

    @Test func S03_registrationHasOneLocationAndLifetime() throws {
        var simulation = try TripSimulation(capacity: 2, eventCapacity: 2)
        let h = try register(&simulation, airport: 7)
        let row = try simulation.read(h)
        verifyTrip(row.handle == h && row.currentAirport == 7 && row.activeTrip == nil)
        verifyTrip(row.completedTrips == 0 && row.inputToken.sequence == 1)
        verifyTrip(simulation.liveAircraft == 1 && simulation.pendingArrivals == 0)
        verifyTrip(simulation.checkInvariants())
    }

    @Test func S04_departureEnqueuesMatchingTimedTrip() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        _ = try simulation.advance(to: 50, eventBudget: 1)
        let h = try register(&simulation, airport: 7)
        let plan = try depart(&simulation, h, to: 9, duration: 70)
        let row = try simulation.read(h)
        verifyTrip(plan.departedAt == 50 && plan.arrivesAt == 120)
        verifyTrip(plan.origin == 7 && plan.destination == 9 && plan.operationID == 2)
        verifyTrip(row.activeTrip == plan && row.currentAirport == 7 && simulation.nextArrival == plan)
        verifyTrip(simulation.pendingArrivals == 1 && simulation.checkInvariants())
    }

    @Test func S05_arrivalMovesAirportAndCompletesExactlyOnce() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation)
        let plan = try depart(&simulation, h)
        let input = simulation.inputToken
        let result = try simulation.advance(to: 100, eventBudget: 1)
        verifyTrip(result.stop == .reachedTarget && result.reachedTime == 100)
        verifyTrip(result.completions.count == 1 && result.completions[0].trip == plan)
        let row = try simulation.read(h)
        verifyTrip(row.currentAirport == 2 && row.activeTrip == nil && row.completedTrips == 1)
        verifyTrip(simulation.inputToken == input && simulation.pendingArrivals == 0)
        verifyTrip(simulation.checkInvariants())
    }

    @Test func S06_invalidAirportsAndDurationPreserveState() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        rejectTrip(.registerAircraft(at: 0), .invalidAirport, simulation: &simulation)
        let h = try register(&simulation)
        rejectTrip(.depart(h, destination: 0, durationSeconds: 0), .invalidAirport, simulation: &simulation)
        rejectTrip(.depart(h, destination: 1, durationSeconds: 0), .sameAirport, simulation: &simulation)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 0), .invalidDuration, simulation: &simulation)
    }

    @Test func S07_foreignInputTokenIsRejectedFirst() throws {
        var simulation = try TripSimulation(testingCapacity: 0, eventCapacity: 0,
                                            initialInputSequence: .max)
        let other = try TripSimulation(capacity: 0, eventCapacity: 0)
        rejectTrip(.registerAircraft(at: 0), .foreignInputToken, simulation: &simulation, token: other.inputToken)
    }

    @Test func S08_repeatedInputsCannotRepeatEffects() throws {
        var simulation = try TripSimulation(capacity: 2, eventCapacity: 1)
        var old = simulation.inputToken
        let h = try register(&simulation)
        rejectTrip(.registerAircraft(at: 1), .inputConflict, simulation: &simulation, token: old)
        old = simulation.inputToken
        try depart(&simulation, h)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 10), .inputConflict,
                   simulation: &simulation, token: old)
        _ = try simulation.advance(to: 10, eventBudget: 1)
        old = simulation.inputToken
        _ = try simulation.apply(.retireAircraft(h), expected: old)
        rejectTrip(.retireAircraft(h), .inputConflict, simulation: &simulation, token: old)
    }

    @Test func S09_foreignAndStaleHandlesCannotAffectRows() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        var other = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation), foreign = try register(&other)
        verifyTrip(h.slot == foreign.slot && h.generation == foreign.generation)
        for bad in [foreign, h] {
            if bad == h { _ = try simulation.apply(.retireAircraft(h), expected: simulation.inputToken) }
            do { _ = try simulation.read(bad); Issue.record("Invalid read accepted") }
            catch { verifyTrip(error as? TripFailure == .aircraft(.invalidHandle)) }
            rejectTrip(.depart(bad, destination: 2, durationSeconds: 1), .aircraft(.invalidHandle),
                       simulation: &simulation)
            rejectTrip(.retireAircraft(bad), .aircraft(.invalidHandle), simulation: &simulation)
        }
    }

    @Test func S10_activeAircraftCannotDepartOrRetire() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation)
        try depart(&simulation, h)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 10), .aircraft(.invalidTransition),
                   simulation: &simulation)
        rejectTrip(.retireAircraft(h), .aircraft(.invalidTransition), simulation: &simulation)
    }

    @Test func S11_queueExhaustionDoesNotStartAircraft() throws {
        var simulation = try TripSimulation(capacity: 2, eventCapacity: 1)
        let first = try register(&simulation), second = try register(&simulation)
        try depart(&simulation, first)
        rejectTrip(.depart(second, destination: 3, durationSeconds: 1), .eventCapacityExhausted,
                   simulation: &simulation)
        verifyTrip(try simulation.read(second).activeTrip == nil)
        _ = try simulation.advance(to: 10, eventBudget: 1)
        try depart(&simulation, second, to: 3)
        verifyTrip(simulation.pendingArrivals == 1 && simulation.checkInvariants())
    }

    @Test func S12_timeAdditionCannotWrap() throws {
        var simulation = try TripSimulation(testingCapacity: 1, eventCapacity: 1, initialTime: .max - 5)
        let h = try register(&simulation)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 6), .timeOverflow, simulation: &simulation)
        rejectTrip(.depart(h, destination: 2, durationSeconds: .max), .timeOverflow, simulation: &simulation)
    }

    @Test func S13_equalTimeOrderUsesUniqueOperationNotSlot() throws {
        var simulation = try TripSimulation(capacity: 7, eventCapacity: 7)
        var handles: [EntityHandle] = []
        for _ in 0..<7 { handles.append(try register(&simulation)) }
        var expected: [ScheduledArrival] = []
        for h in handles.reversed() { expected.append(try depart(&simulation, h, duration: 100)) }
        var actual: [ScheduledArrival] = []
        while simulation.pendingArrivals > 0 {
            let result = try simulation.advance(to: 100, eventBudget: 1)
            actual += result.completions.map(\.trip)
            verifyTrip(result.reachedTime == 100)
            verifyTrip(result.stop == (simulation.pendingArrivals > 0 ? .eventBudgetReached : .reachedTarget))
        }
        verifyTrip(actual == expected && simulation.checkInvariants())
    }

    @Test func S14_mixedDueTimesAreSortedDeterministically() throws {
        var simulation = try TripSimulation(capacity: 9, eventCapacity: 9)
        var expected: [ScheduledArrival] = []
        for time: UInt64 in [90, 20, 60, 40, 20, 90, 1, 1, 45] {
            let h = try register(&simulation)
            expected.append(try depart(&simulation, h, duration: time))
        }
        expected.sort {
            if $0.arrivesAt == $1.arrivesAt { return $0.operationID < $1.operationID }
            return $0.arrivesAt < $1.arrivesAt
        }
        let result = try simulation.advance(to: 100, eventBudget: 9)
        verifyTrip(result.completions.map(\.trip) == expected && result.stop == .reachedTarget)
        verifyTrip(simulation.checkInvariants())
    }

    @Test func S15_budgetDoesNotLieAboutReachedTime() throws {
        var simulation = try TripSimulation(capacity: 3, eventCapacity: 3)
        for time: UInt64 in [10, 20, 30] { try depart(&simulation, try register(&simulation), duration: time) }
        let first = try simulation.advance(to: 500, eventBudget: 1)
        verifyTrip(first.reachedTime == 10 && first.requestedTime == 500 && first.nextDueTime == 20)
        verifyTrip(first.stop == .eventBudgetReached && first.processedEvents == 1)
        let second = try simulation.advance(to: 500, eventBudget: 1)
        verifyTrip(second.reachedTime == 20 && second.nextDueTime == 30)
        let third = try simulation.advance(to: 500, eventBudget: 1)
        verifyTrip(third.reachedTime == 500 && third.stop == .reachedTarget)
        verifyTrip(simulation.checkInvariants())
    }

    @Test func S16_futureEventSurvivesPartialTimeAdvance() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let plan = try depart(&simulation, try register(&simulation), duration: 100)
        let result = try simulation.advance(to: 70, eventBudget: 1)
        verifyTrip(result.reachedTime == 70 && result.processedEvents == 0 && result.stop == .reachedTarget)
        verifyTrip(simulation.nextArrival == plan && simulation.pendingArrivals == 1)
        verifyTrip(simulation.checkInvariants())
    }

    @Test(arguments: [-1, 0, 1_025, Int.max])
    func S17_invalidAdvanceDoesNotTouchDueWork(_ budget: Int) throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        try depart(&simulation, try register(&simulation))
        rejectAdvance(100, budget: budget, .invalidEventBudget, simulation: &simulation)
        _ = try simulation.advance(to: 5, eventBudget: 1)
        rejectAdvance(4, budget: 1, .invalidTargetTime, simulation: &simulation)
    }

    @Test func S18_inputFailurePreservesAllStoresAndHeap() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        func injected(_ command: TripCommand, _ simulation: inout TripSimulation) {
            let before = simulation.auditForTesting()
            do {
                _ = try simulation.applyForTesting(command, expected: simulation.inputToken)
                Issue.record("Expected input injection")
            } catch { verifyTrip(error as? TripTestFailure == .beforeInputCommit) }
            verifyTrip(simulation.auditForTesting() == before && simulation.checkInvariants())
        }
        injected(.registerAircraft(at: 1), &simulation)
        let h = try register(&simulation)
        injected(.depart(h, destination: 2, durationSeconds: 10), &simulation)
        injected(.retireAircraft(h), &simulation)
    }

    @Test func S19_blockBeforeFirstEventPreservesExactState() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        try depart(&simulation, try register(&simulation))
        let before = simulation.auditForTesting()
        let result = try simulation.advanceForTesting(to: 100, eventBudget: 1, failAtEventIndex: 0)
        verifyTrip(result.stop == .blocked(.injectedPreparationFailure))
        verifyTrip(result.processedEvents == 0 && result.reachedTime == 0 && result.nextDueTime == 10)
        verifyTrip(before == simulation.auditForTesting())
    }

    @Test func S20_blockReportsCommittedPrefixAndRetryNeverDuplicates() throws {
        var simulation = try TripSimulation(capacity: 3, eventCapacity: 3)
        var handles: [EntityHandle] = []
        for time: UInt64 in [10, 20, 30] {
            let h = try register(&simulation); handles.append(h)
            try depart(&simulation, h, duration: time)
        }
        let result = try simulation.advanceForTesting(to: 500, eventBudget: 3, failAtEventIndex: 1)
        verifyTrip(result.stop == .blocked(.injectedPreparationFailure) && result.processedEvents == 1)
        verifyTrip(result.reachedTime == 10 && result.nextDueTime == 20 && simulation.pendingArrivals == 2)
        verifyTrip(try simulation.read(handles[0]).completedTrips == 1)
        verifyTrip(try simulation.read(handles[1]).completedTrips == 0)
        verifyTrip(simulation.checkInvariants())
        let rest = try simulation.advance(to: 500, eventBudget: 3)
        verifyTrip(rest.processedEvents == 2 && rest.stop == .reachedTarget)
        for h in handles { verifyTrip(try simulation.read(h).completedTrips == 1) }
        verifyTrip(try simulation.advance(to: 500, eventBudget: 3).processedEvents == 0)
    }

    @Test func S21_actualAircraftRevisionExhaustionBlocksWithoutLosingEvent() throws {
        var simulation = try TripSimulation(testingCapacity: 1, eventCapacity: 1,
                                            initialAircraftRevision: .max - 2)
        let h = try register(&simulation)
        let plan = try depart(&simulation, h)
        verifyTrip(plan.operationID == .max)
        let before = simulation.auditForTesting()
        let result = try simulation.advance(to: 100, eventBudget: 1)
        verifyTrip(result.stop == .blocked(.aircraft(.revisionExhausted)))
        verifyTrip(result.processedEvents == 0 && result.reachedTime == 0 && simulation.nextArrival == plan)
        verifyTrip(before == simulation.auditForTesting() && simulation.checkInvariants())
    }

    @Test func S22_inputSequenceExhaustionDoesNotFreezeAutomaticTime() throws {
        var simulation = try TripSimulation(testingCapacity: 1, eventCapacity: 1,
                                            initialInputSequence: .max - 2)
        let h = try register(&simulation)
        try depart(&simulation, h)
        verifyTrip(simulation.inputToken.sequence == .max)
        rejectTrip(.retireAircraft(h), .inputSequenceExhausted, simulation: &simulation)
        let result = try simulation.advance(to: 100, eventBudget: 1)
        verifyTrip(result.processedEvents == 1 && result.reachedTime == 100)
        verifyTrip(simulation.inputToken.sequence == .max && simulation.checkInvariants())
    }

    @Test func S23_automaticArrivalDoesNotInvalidatePendingInput() throws {
        var simulation = try TripSimulation(capacity: 2, eventCapacity: 2)
        let h = try register(&simulation)
        try depart(&simulation, h)
        let pendingInput = simulation.inputToken
        _ = try simulation.advance(to: 100, eventBudget: 1)
        let result = try simulation.apply(.depart(h, destination: 3, durationSeconds: 25), expected: pendingInput)
        verifyTrip(result.activeTrip?.departedAt == 100 && result.activeTrip?.origin == 2)
        verifyTrip(result.inputToken.sequence == pendingInput.sequence + 1)
        verifyTrip(simulation.checkInvariants())
    }

    @Test func S24_slotReuseCannotCarryOldJourneyOrEvent() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation)
        let first = try depart(&simulation, h)
        _ = try simulation.advance(to: 10, eventBudget: 1)
        _ = try simulation.apply(.retireAircraft(h), expected: simulation.inputToken)
        let replacement = try register(&simulation, airport: 8)
        let next = try depart(&simulation, replacement, to: 9)
        verifyTrip(replacement.slot == h.slot && replacement.generation == h.generation + 1)
        verifyTrip(next.operationID > first.operationID && next.origin == 8 && next.departedAt == 10)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 1), .aircraft(.invalidHandle), simulation: &simulation)
        let result = try simulation.advance(to: 20, eventBudget: 1)
        verifyTrip(result.completions.count == 1 && result.completions[0].trip.handle == replacement)
        verifyTrip(try simulation.read(replacement).completedTrips == 1)
    }

    @Test func S25_readsResultsAndAuditsRemainDetached() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation)
        let old = try simulation.read(h)
        let first = try depart(&simulation, h)
        var heapImage = simulation.auditForTesting().heap
        heapImage[0] = nil
        let result = try simulation.advance(to: 10, eventBudget: 1)
        try depart(&simulation, h, to: 3)
        verifyTrip(old.currentAirport == 1 && old.activeTrip == nil)
        verifyTrip(result.completions[0].trip == first && result.completions[0].completedTrips == 1)
        verifyTrip(simulation.nextArrival != nil && simulation.checkInvariants())
    }

    @Test func S26_corruptPairedJourneyIsDetected() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&simulation)
        try depart(&simulation, h)
        simulation.corruptJourneyForTesting(h)
        verifyTrip(!simulation.checkInvariants())
        // Runtime fail-stop behavior is tested in isolated Debug/Release processes.
    }

    @Test func S27_maximumBudgetCommitsNoMoreThan1024() throws {
        var simulation = try TripSimulation(capacity: 1_025, eventCapacity: 1_025)
        for _ in 0..<1_025 { try depart(&simulation, try register(&simulation)) }
        let result = try simulation.advance(to: 100, eventBudget: 1_024)
        verifyTrip(result.processedEvents == 1_024 && result.stop == .eventBudgetReached)
        verifyTrip(result.reachedTime == 10 && result.nextDueTime == 10 && simulation.pendingArrivals == 1)
        verifyTrip(simulation.checkInvariants())
        let final = try simulation.advance(to: 100, eventBudget: 1_024)
        verifyTrip(final.processedEvents == 1 && final.reachedTime == 100 && final.stop == .reachedTarget)
    }

    @Test func S28_maximumTimeCanBeReachedButNeverWrapped() throws {
        var simulation = try TripSimulation(testingCapacity: 1, eventCapacity: 1, initialTime: .max - 1)
        let h = try register(&simulation)
        try depart(&simulation, h, duration: 1)
        let result = try simulation.advance(to: .max, eventBudget: 1)
        verifyTrip(result.reachedTime == .max && result.processedEvents == 1)
        rejectTrip(.depart(h, destination: 3, durationSeconds: 1), .timeOverflow, simulation: &simulation)
        verifyTrip(try simulation.advance(to: .max, eventBudget: 1).processedEvents == 0)
        rejectAdvance(0, budget: 1, .invalidTargetTime, simulation: &simulation)
    }

    @Test func S29_zeroEventCapacityNeverSilentlyDropsDeparture() throws {
        var simulation = try TripSimulation(capacity: 1, eventCapacity: 0)
        let h = try register(&simulation)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 1), .eventCapacityExhausted, simulation: &simulation)
        let result = try simulation.advance(to: 1_000, eventBudget: 1)
        verifyTrip(result.processedEvents == 0 && simulation.pendingArrivals == 0)
        verifyTrip(try simulation.read(h).completedTrips == 0)
    }

    @Test func S30_repeatedAdvancesAndInterleavedInputsDoNotDuplicate() throws {
        var simulation = try TripSimulation(capacity: 2, eventCapacity: 2)
        let h = try register(&simulation)
        try depart(&simulation, h)
        _ = try simulation.advance(to: 10, eventBudget: 1)
        verifyTrip(try simulation.advance(to: 10, eventBudget: 1).processedEvents == 0)
        let second = try register(&simulation)
        try depart(&simulation, second)
        try depart(&simulation, h, to: 3)
        let result = try simulation.advance(to: 20, eventBudget: 2)
        verifyTrip(result.processedEvents == 2 && result.completions[0].trip.handle == second)
        verifyTrip(try simulation.read(h).completedTrips == 2)
        verifyTrip(try simulation.read(second).completedTrips == 1)
        verifyTrip(simulation.checkInvariants())
    }

    @Test(arguments: [1_000, 5_000, 20_000, 50_000, 100_000])
    func S31_completeTimedTripFixtureAtScale(_ size: Int) throws {
        var simulation = try TripSimulation(capacity: size, eventCapacity: size)
        var handles: [EntityHandle] = []; handles.reserveCapacity(size)
        for index in 0..<size {
            let h = try register(&simulation); handles.append(h)
            try depart(&simulation, h, duration: UInt64(index % 700 + 1))
        }
        verifyTrip(simulation.checkInvariants() && simulation.pendingArrivals == size)
        var count = 0
        var previousDue: UInt64 = 0, previousID: UInt64 = 0
        while simulation.pendingArrivals > 0 {
            let result = try simulation.advance(to: 700, eventBudget: 128)
            verifyTrip(result.processedEvents <= 128)
            for completion in result.completions {
                let plan = completion.trip
                verifyTrip(plan.arrivesAt > previousDue ||
                           (plan.arrivesAt == previousDue && plan.operationID > previousID))
                previousDue = plan.arrivesAt; previousID = plan.operationID
            }
            count += result.processedEvents
        }
        verifyTrip(count == size && simulation.now == 700 && simulation.checkInvariants())
        for h in handles {
            let row = try simulation.read(h)
            verifyTrip(row.completedTrips == 1 && row.currentAirport == 2 && row.activeTrip == nil)
        }
    }

    @Test func S32_independentConcurrentWorldsDoNotShareQueues() async throws {
        try await withThrowingTaskGroup(of: EntityHandle.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    var simulation = try TripSimulation(capacity: 1, eventCapacity: 1)
                    let h = try register(&simulation)
                    for index in 0..<32 {
                        try depart(&simulation, h, to: UInt32(index + 2), duration: 1)
                        _ = try simulation.advance(to: UInt64(index + 1), eventBudget: 1)
                    }
                    verifyTrip(try simulation.read(h).completedTrips == 32)
                    verifyTrip(simulation.checkInvariants())
                    return h
                }
            }
            var handles = Set<EntityHandle>()
            for try await h in group { handles.insert(h) }
            verifyTrip(handles.count == 16)
        }
    }
}
