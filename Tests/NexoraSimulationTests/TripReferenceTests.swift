import Testing
import NexoraIdentity
import NexoraAviation
@testable import NexoraSimulation

// Independent logical reference: dictionary aircraft, free-slot stack, sorted
// event list. It never invokes a production store, heap, or commit helper.
private struct RefEvent: Equatable {
    let slot: UInt32
    let generation: UInt32
    let operation: UInt64
    let origin: UInt32
    let destination: UInt32
    let from: UInt64
    let due: UInt64
}
private struct RefPlane {
    let generation: UInt32
    var airport: UInt32
    var active: RefEvent?
    var completed: UInt64
}
private struct RefInput: Equatable {
    let slot: UInt32
    let generation: UInt32
    let active: RefEvent?
    let retired: Bool
    let sequence: UInt64
}
private struct RefCompletion: Equatable { let trip: RefEvent; let completed: UInt64 }
private struct RefProgress: Equatable {
    let from: UInt64
    let target: UInt64
    let reached: UInt64
    let completions: [RefCompletion]
    let next: UInt64?
    let stop: AdvanceStop
}
private struct ReferenceWorld {
    var time: UInt64 = 0
    var sequence: UInt64 = 0
    var revision: UInt64 = 0
    var generations: [UInt32]
    var free: [UInt32]
    var planes: [UInt32: RefPlane] = [:]
    var events: [RefEvent] = []
    let eventCapacity: Int
    init(capacity: Int, eventCapacity: Int) {
        generations = Array(repeating: 0, count: capacity)
        free = (0..<capacity).reversed().map(UInt32.init)
        self.eventCapacity = eventCapacity
    }
    mutating func input(_ command: TripCommand, expected: UInt64, foreignToken: Bool,
                        foreignHandle: Bool) throws -> RefInput {
        if foreignToken { throw TripFailure.foreignInputToken }
        if expected != sequence { throw TripFailure.inputConflict }
        if sequence == UInt64.max { throw TripFailure.inputSequenceExhausted }
        switch command {
        case .registerAircraft(let airport):
            if airport == 0 { throw TripFailure.invalidAirport }
            guard let slot = free.last else { throw TripFailure.aircraft(.capacityExhausted) }
            free.removeLast()
            let generation = generations[Int(slot)]
            planes[slot] = RefPlane(generation: generation, airport: airport, active: nil, completed: 0)
            sequence += 1; revision += 1
            return RefInput(slot: slot, generation: generation, active: nil, retired: false, sequence: sequence)
        case .depart(let h, _, _), .retireAircraft(let h):
            guard !foreignHandle, var row = planes[h.slot], row.generation == h.generation else {
                throw TripFailure.aircraft(.invalidHandle)
            }
            if row.active != nil { throw TripFailure.aircraft(.invalidTransition) }
            switch command {
            case .depart(_, let destination, let duration):
                if destination == 0 { throw TripFailure.invalidAirport }
                if destination == row.airport { throw TripFailure.sameAirport }
                if duration == 0 { throw TripFailure.invalidDuration }
                if duration > UInt64.max - time { throw TripFailure.timeOverflow }
                if events.count == eventCapacity { throw TripFailure.eventCapacityExhausted }
                let event = RefEvent(slot: h.slot, generation: h.generation, operation: revision + 1,
                                     origin: row.airport, destination: destination, from: time, due: time + duration)
                row.active = event; planes[h.slot] = row
                events.append(event)
                events.sort {
                    if $0.due != $1.due { return $0.due < $1.due }
                    return $0.operation < $1.operation
                }
                sequence += 1; revision += 1
                return RefInput(slot: h.slot, generation: h.generation, active: event, retired: false,
                                sequence: sequence)
            case .retireAircraft:
                planes.removeValue(forKey: h.slot)
                generations[Int(h.slot)] += 1; free.append(h.slot)
                sequence += 1; revision += 1
                return RefInput(slot: h.slot, generation: h.generation, active: nil, retired: true,
                                sequence: sequence)
            default: fatalError("Bad reference classification")
            }
        }
    }
    mutating func advance(to target: UInt64, budget: Int, failIndex: Int?) throws -> RefProgress {
        if target < time { throw TripFailure.invalidTargetTime }
        if budget < 1 || budget > 1_024 { throw TripFailure.invalidEventBudget }
        let from = time
        var completions: [RefCompletion] = []
        while let event = events.first, event.due <= target, completions.count < budget {
            if completions.count == failIndex {
                return RefProgress(from: from, target: target, reached: time, completions: completions,
                                   next: events.first?.due, stop: .blocked(.injectedPreparationFailure))
            }
            guard var plane = planes[event.slot], plane.active == event else { fatalError("Reference mismatch") }
            plane.active = nil; plane.airport = event.destination; plane.completed += 1
            planes[event.slot] = plane
            events.removeFirst(); revision += 1; time = event.due
            completions.append(RefCompletion(trip: event, completed: plane.completed))
        }
        if let event = events.first, event.due <= target {
            return RefProgress(from: from, target: target, reached: time, completions: completions,
                               next: event.due, stop: .eventBudgetReached)
        }
        time = target
        return RefProgress(from: from, target: target, reached: time, completions: completions,
                           next: events.first?.due, stop: .reachedTarget)
    }
}
private func normalize(_ plan: ScheduledArrival) -> RefEvent {
    RefEvent(slot: plan.handle.slot, generation: plan.handle.generation, operation: plan.operationID,
             origin: plan.origin, destination: plan.destination, from: plan.departedAt, due: plan.arrivesAt)
}
private func normalize(_ input: TripInputReceipt) -> RefInput {
    RefInput(slot: input.handle.slot, generation: input.handle.generation,
             active: input.activeTrip.map(normalize), retired: input.retired, sequence: input.inputToken.sequence)
}
private func normalize(_ progress: AdvanceResult) -> RefProgress {
    RefProgress(from: progress.fromTime, target: progress.requestedTime, reached: progress.reachedTime,
                completions: progress.completions.map { RefCompletion(trip: normalize($0.trip), completed: $0.completedTrips) },
                next: progress.nextDueTime, stop: progress.stop)
}
private struct TripRandom {
    var state: UInt64
    mutating func next(_ limit: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 28) % UInt64(limit))
    }
}
struct TripReferenceTests {
    @Test(arguments: [UInt64(17), 701, 123_456, 0xABCDE])
    func independentSortedListMatchesInputsTimeAndFailures(_ seed: UInt64) throws {
        let size = 23, eventCapacity = 7
        var simulation = try TripSimulation(capacity: size, eventCapacity: eventCapacity)
        var reference = ReferenceWorld(capacity: size, eventCapacity: eventCapacity)
        var other = try TripSimulation(capacity: size, eventCapacity: eventCapacity)
        let foreignHandle = try register(&other)
        var tokens = [simulation.inputToken]
        var liveHandles: [UInt32: EntityHandle] = [:]
        var known: [EntityHandle] = []
        var random = TripRandom(state: seed)
        var accepted = 0, rejected = 0, arrivals = 0, blocked = 0
        for _ in 0..<5_000 {
            let before = simulation.auditForTesting()
            let kind = random.next(5)
            if kind == 4 {
                let target = reference.time + UInt64(random.next(19))
                let budget = random.next(8) // Includes invalid zero.
                let fault: Int? = random.next(5) == 0 ? random.next(3) : nil
                var expected: RefProgress?, expectedError: TripFailure?
                do { expected = try reference.advance(to: target, budget: budget, failIndex: fault) }
                catch { expectedError = error as? TripFailure; verifyTrip(expectedError != nil) }
                do {
                    let result: AdvanceResult
                    if let fault {
                        result = try simulation.advanceForTesting(to: target, eventBudget: budget, failAtEventIndex: fault)
                    } else { result = try simulation.advance(to: target, eventBudget: budget) }
                    verifyTrip(normalize(result) == expected && expectedError == nil)
                    arrivals += result.processedEvents
                    if case .blocked = result.stop { blocked += 1 }
                } catch {
                    verifyTrip(error as? TripFailure == expectedError && expected == nil)
                    verifyTrip(simulation.auditForTesting() == before)
                }
            } else {
                let foreignToken = random.next(31) == 0
                let token = foreignToken ? other.inputToken :
                    (random.next(7) == 0 ? tokens[random.next(tokens.count)] : simulation.inputToken)
                let foreignHandleSelected = random.next(17) == 0
                let handle: EntityHandle
                if foreignHandleSelected || known.isEmpty { handle = foreignHandle }
                else if !liveHandles.isEmpty && random.next(6) != 0 {
                    let slot = liveHandles.keys.sorted()[random.next(liveHandles.count)]
                    handle = try #require(liveHandles[slot])
                } else { handle = known[random.next(known.count)] }
                let command: TripCommand
                if kind == 0 || known.isEmpty { command = .registerAircraft(at: UInt32(random.next(9))) }
                else if kind == 1 || kind == 2 {
                    command = .depart(handle, destination: UInt32(random.next(9)),
                                      durationSeconds: UInt64(random.next(31)))
                } else { command = .retireAircraft(handle) }
                var expected: RefInput?, expectedError: TripFailure?
                do {
                    expected = try reference.input(command, expected: token.sequence, foreignToken: foreignToken,
                                                   foreignHandle: foreignHandleSelected || known.isEmpty)
                } catch { expectedError = error as? TripFailure; verifyTrip(expectedError != nil) }
                do {
                    let result = try simulation.apply(command, expected: token)
                    verifyTrip(normalize(result) == expected && expectedError == nil)
                    if case .registerAircraft = command { known.append(result.handle); liveHandles[result.handle.slot] = result.handle }
                    if result.retired { liveHandles.removeValue(forKey: result.handle.slot) }
                    tokens.append(result.inputToken); accepted += 1
                } catch {
                    verifyTrip(error as? TripFailure == expectedError && expected == nil)
                    verifyTrip(simulation.auditForTesting() == before); rejected += 1
                }
            }
            let audit = simulation.auditForTesting()
            verifyTrip(audit.now == reference.time && audit.token.sequence == reference.sequence)
            verifyTrip(audit.aircraft.token.revision == reference.revision)
            verifyTrip(audit.aircraft.identity.epochs == reference.generations)
            verifyTrip(audit.aircraft.identity.liveCount == reference.planes.count)
            verifyTrip(audit.aircraft.identity.freeHead == reference.free.last ?? UInt32.max)
            var nextFree = Array(repeating: UInt32.max, count: size)
            let chain = Array(reference.free.reversed())
            for i in chain.indices where i + 1 < chain.count { nextFree[Int(chain[i])] = chain[i + 1] }
            verifyTrip(audit.aircraft.identity.nextFree == nextFree)
            verifyTrip(audit.heapCount == reference.events.count)
            let normalizedEvents = audit.heap.compactMap { $0 }.map(normalize).sorted {
                if $0.due != $1.due { return $0.due < $1.due }
                return $0.operation < $1.operation
            }
            verifyTrip(normalizedEvents == reference.events)
            for slot in 0..<size {
                if let expected = reference.planes[UInt32(slot)] {
                    let row = try #require(audit.rows[slot]), aircraft = try #require(audit.aircraft.rows[slot])
                    verifyTrip(row.handle.generation == expected.generation && row.currentAirport == expected.airport)
                    verifyTrip(row.active.map(normalize) == expected.active && aircraft.completedOperations == expected.completed)
                    verifyTrip(audit.aircraft.identity.flags[slot] == 1)
                } else {
                    verifyTrip(audit.rows[slot] == nil && audit.aircraft.rows[slot] == nil)
                    verifyTrip(audit.aircraft.identity.flags[slot] == 0)
                }
            }
            verifyTrip(simulation.checkInvariants())
        }
        verifyTrip(accepted > 100 && rejected > 100 && arrivals > 50 && blocked > 5)
        print("Trip reference seed \(seed): 5000 commands, accepted \(accepted), rejected \(rejected), arrivals \(arrivals), blocked prefixes \(blocked)")
    }

    @Test func standaloneHeapMatchesSortedOracle() throws {
        var owner = try AircraftStore(capacity: 1)
        let h = try owner.apply(.create, expected: owner.token).handle
        var random = TripRandom(state: 7)
        var heap = ArrivalHeap(capacity: 10_000)
        var oracle: [ScheduledArrival] = []
        for id: UInt64 in 1...10_000 {
            let event = ScheduledArrival(handle: h, operationID: id, origin: 1, destination: 2,
                                         departedAt: 0, arrivesAt: UInt64(random.next(101) + 1))
            heap.push(event); oracle.append(event)
        }
        oracle.sort {
            if $0.arrivesAt != $1.arrivesAt { return $0.arrivesAt < $1.arrivesAt }
            return $0.operationID < $1.operationID
        }
        verifyTrip(heap.checkInvariants())
        for expected in oracle { verifyTrip(heap.pop() == expected) }
        verifyTrip(heap.peek() == nil && heap.pop() == nil && heap.count == 0 && heap.checkInvariants())
    }

    @Test func movingSimulationKeepsItsQueueAndTokenOwner() throws {
        var original = try TripSimulation(capacity: 1, eventCapacity: 1)
        let h = try register(&original)
        try depart(&original, h)
        let token = original.inputToken
        var moved = consume original
        verifyTrip(moved.inputToken == token)
        verifyTrip(try moved.advance(to: 10, eventBudget: 1).processedEvents == 1)
        verifyTrip(try moved.read(h).currentAirport == 2 && moved.checkInvariants())
    }
}
