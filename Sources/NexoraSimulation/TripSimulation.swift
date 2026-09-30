import NexoraIdentity
import NexoraAviation
import NexoraFinance

private final class InputStamp: Sendable {}

/// Process-local input sequence, independent of automatic simulation progress.
public struct TripInputToken: Equatable, Sendable {
    fileprivate let stamp: InputStamp
    public let sequence: UInt64
    fileprivate init(stamp: InputStamp, sequence: UInt64) {
        self.stamp = stamp
        self.sequence = sequence
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stamp === rhs.stamp && lhs.sequence == rhs.sequence
    }
}

public enum TripCommand: Sendable, Equatable {
    case registerAircraft(at: UInt32)
    case depart(EntityHandle, destination: UInt32, durationSeconds: UInt64)
    case retireAircraft(EntityHandle)
}

public enum TripFailure: Error, Sendable, Equatable {
    case invalidCapacity, invalidAirport, sameAirport, invalidDuration, timeOverflow
    case foreignInputToken, inputConflict, inputSequenceExhausted, eventCapacityExhausted
    case invalidTargetTime, invalidEventBudget
    case aircraft(AircraftFailure)
    case finance(FinanceFailure)
}

/// A tiny timed-trip fixture. Numeric airports are not a geographic catalog.
public struct ScheduledArrival: Sendable, Equatable {
    public let handle: EntityHandle
    public let operationID: UInt64
    public let origin: UInt32
    public let destination: UInt32
    public let departedAt: UInt64
    public let arrivesAt: UInt64
    public let fareMinor: Int64

    // Legacy unpriced fixtures default to zero. Priced public input requires a positive fare.
    init(handle: EntityHandle, operationID: UInt64, origin: UInt32, destination: UInt32,
         departedAt: UInt64, arrivesAt: UInt64, fareMinor: Int64 = 0) {
        self.handle = handle; self.operationID = operationID
        self.origin = origin; self.destination = destination
        self.departedAt = departedAt; self.arrivesAt = arrivesAt; self.fareMinor = fareMinor
    }
}

public struct TripAircraftView: Sendable, Equatable {
    public let handle: EntityHandle
    public let currentAirport: UInt32
    public let activeTrip: ScheduledArrival?
    public let completedTrips: UInt64
    public let inputToken: TripInputToken
}

public struct TripInputReceipt: Sendable, Equatable {
    public let handle: EntityHandle
    public let activeTrip: ScheduledArrival?
    public let retired: Bool
    public let inputToken: TripInputToken
}

public struct TripCompletion: Sendable, Equatable {
    public let trip: ScheduledArrival
    public let completedTrips: UInt64
    public let invoice: InvoiceView?
}

public enum FinancialInputCommand: Sendable, Equatable {
    case contributeCapital(amountMinor: Int64)
    case collectInvoice(InvoiceHandle, amountMinor: Int64)
    case payExpense(CashExpenseKind, amountMinor: Int64)
}
public struct FinancialInputReceipt: Sendable, Equatable {
    public let posting: FinanceReceipt
    public let inputToken: TripInputToken
}

public enum AdvanceBlock: Sendable, Equatable {
    case aircraft(AircraftFailure)
    case finance(FinanceFailure)
    /// Produced only by internal test injection, never the ordinary advance path.
    case injectedPreparationFailure
}

public enum AdvanceStop: Sendable, Equatable {
    case reachedTarget, eventBudgetReached
    case blocked(AdvanceBlock)
}

/// Prefix-committing progress: a block never conceals already committed events.
public struct AdvanceResult: Sendable, Equatable {
    public let fromTime: UInt64
    public let requestedTime: UInt64
    public let reachedTime: UInt64
    public let completions: [TripCompletion]
    public let nextDueTime: UInt64?
    public let stop: AdvanceStop
    public var processedEvents: Int { completions.count }
}

private struct JourneyRow: Sendable, Equatable {
    let handle: EntityHandle
    let currentAirport: UInt32
    let active: ScheduledArrival?
}

/// Serial timed-trip owner. No per-aircraft executor, hot world scan or I/O.
/// It is deliberately NOT a general multi-domain transaction/persistence engine.
public struct TripSimulation: ~Copyable, Sendable {
    public static var maximumEventsPerAdvance: Int { 1_024 }
    private let stamp: InputStamp
    private var aircraft: AircraftStore
    private var finance: FinanceStore
    private var journeys: [JourneyRow?]
    private var arrivals: ArrivalHeap
    private var inputSequence: UInt64
    public private(set) var now: UInt64

    public var capacity: Int { journeys.count }
    public var liveAircraft: Int { aircraft.liveCount }
    public var pendingArrivals: Int { arrivals.count }
    public var eventCapacity: Int { arrivals.capacity }
    public var nextArrival: ScheduledArrival? { arrivals.peek() }
    public var inputToken: TripInputToken { TripInputToken(stamp: stamp, sequence: inputSequence) }

    public init(capacity: Int, eventCapacity: Int, financeLimits: FinanceLimits = .disabled,
                currency: CurrencySpec = .sar) throws {
        try self.init(testingCapacity: capacity, eventCapacity: eventCapacity,
                      financeLimits: financeLimits, currency: currency)
    }

    // New-world fixtures only. Ordinary external clients cannot access them.
    init(testingCapacity: Int, eventCapacity: Int, initialTime: UInt64 = 0,
         initialInputSequence: UInt64 = 0, initialAircraftRevision: UInt64 = 0,
         financeLimits: FinanceLimits = .disabled, currency: CurrencySpec = .sar,
         initialFinanceRevision: UInt64 = 0) throws {
        guard (0...EntitySpace.maximumCapacity).contains(testingCapacity),
              (0...EntitySpace.maximumCapacity).contains(eventCapacity) else {
            throw TripFailure.invalidCapacity
        }
        let newFinance = try Self.makeFinance(limits: financeLimits, currency: currency,
                                              revision: initialFinanceRevision, time: initialTime)
        let newAircraft = try AircraftStore(testingCapacity: testingCapacity,
                                            initialRevision: initialAircraftRevision)
        finance = consume newFinance
        aircraft = consume newAircraft
        arrivals = ArrivalHeap(capacity: eventCapacity)
        journeys = Array(repeating: nil, count: testingCapacity)
        stamp = InputStamp()
        inputSequence = initialInputSequence
        now = initialTime
    }

    // Keep error translation outside partial noncopyable-self initialization.
    private static func makeFinance(limits: FinanceLimits, currency: CurrencySpec,
                                    revision: UInt64, time: UInt64) throws -> FinanceStore {
        do {
            return try FinanceStore(testingLimits: limits, currency: currency,
                                     initialRevision: revision, initialTime: time)
        } catch let error as FinanceFailure { throw TripFailure.finance(error) }
        catch { fatalError("NEXORA_TRIP_INVARIANT: unexpected financial initialization failure") }
    }

    public func read(_ handle: EntityHandle) throws -> TripAircraftView {
        let (state, journey) = try checkedRow(handle)
        return TripAircraftView(handle: handle, currentAirport: journey.currentAirport,
                                activeTrip: journey.active, completedTrips: state.completedOperations,
                                inputToken: inputToken)
    }

    public mutating func apply(_ command: TripCommand,
                               expected: TripInputToken) throws -> TripInputReceipt {
        try applyCore(command, expected: expected, failBeforeCommit: false)
    }

    public mutating func departPriced(_ handle: EntityHandle, destination: UInt32,
                                      durationSeconds: UInt64, fareMinor: Int64,
                                      expected: TripInputToken) throws -> TripInputReceipt {
        try applyCore(.depart(handle, destination: destination, durationSeconds: durationSeconds),
                      expected: expected, failBeforeCommit: false, fareMinor: fareMinor)
    }

    public var financialSummary: FinanceSummary { finance.summary }
    public func readInvoice(_ handle: InvoiceHandle) throws -> InvoiceView { try finance.readInvoice(handle) }
    public func invoicePage(offset: Int, limit: Int) throws -> [InvoiceView] {
        try finance.invoicePage(offset: offset, limit: limit)
    }
    public func journalPage(offset: Int, limit: Int) throws -> [JournalEntry] {
        try finance.journalPage(offset: offset, limit: limit)
    }

    public mutating func applyFinance(_ command: FinancialInputCommand,
                                      expected: TripInputToken) throws -> FinancialInputReceipt {
        try applyFinanceCore(command, expected: expected, failBeforeCommit: false)
    }
    private mutating func applyFinanceCore(_ command: FinancialInputCommand, expected: TripInputToken,
                                          failBeforeCommit: Bool) throws -> FinancialInputReceipt {
        let next = try nextInput(expected: expected)
        let posting: FinanceCommand
        switch command {
        case .contributeCapital(let amount): posting = .contributeCapital(amountMinor: amount, at: now)
        case .collectInvoice(let handle, let amount): posting = .collectInvoice(handle, amountMinor: amount, at: now)
        case .payExpense(let kind, let amount): posting = .payExpense(kind, amountMinor: amount, at: now)
        }
        let prepared: PreparedFinance
        do { prepared = try finance.prepare(posting, expected: finance.token) }
        catch let error as FinanceFailure { throw TripFailure.finance(error) }
        catch { fatalError("NEXORA_TRIP_INVARIANT: unexpected financial preparation failure") }
        if failBeforeCommit { throw TripTestFailure.beforeInputCommit }
        let receipt = finance.commit(consume prepared)
        inputSequence = next
        return FinancialInputReceipt(posting: receipt, inputToken: inputToken)
    }

    private func nextInput(expected: TripInputToken) throws -> UInt64 {
        guard expected.stamp === stamp else { throw TripFailure.foreignInputToken }
        guard expected.sequence == inputSequence else { throw TripFailure.inputConflict }
        guard inputSequence < UInt64.max else { throw TripFailure.inputSequenceExhausted }
        return inputSequence + 1
    }

    private func checkedRow(_ handle: EntityHandle) throws -> (AircraftView, JourneyRow) {
        let state: AircraftView
        do { state = try aircraft.read(handle) }
        catch let error as AircraftFailure { throw TripFailure.aircraft(error) }
        catch { fatalError("NEXORA_TRIP_INVARIANT: unknown aircraft read failure") }
        guard let row = journeys[Int(handle.slot)], row.handle == handle else {
            fatalError("NEXORA_TRIP_INVARIANT: missing journey row")
        }
        switch (state.state, row.active) {
        case (.ready, nil): break
        case (.active(let operationID), .some(let plan)):
            guard plan.handle == handle, plan.operationID == operationID,
                  plan.origin == row.currentAirport else {
                fatalError("NEXORA_TRIP_INVARIANT: mismatched active journey")
            }
        default: fatalError("NEXORA_TRIP_INVARIANT: aircraft and journey state disagree")
        }
        return (state, row)
    }

    private mutating func applyCore(_ command: TripCommand, expected: TripInputToken,
                                   failBeforeCommit: Bool, fareMinor: Int64? = nil) throws -> TripInputReceipt {
        let next = try nextInput(expected: expected)
        switch command {
        case .registerAircraft(let airport):
            guard airport > 0 else { throw TripFailure.invalidAirport }
            if failBeforeCommit { throw TripTestFailure.beforeInputCommit }
            let result: AircraftReceipt
            do { result = try aircraft.apply(.create, expected: aircraft.token) }
            catch let error as AircraftFailure { throw TripFailure.aircraft(error) }
            catch { fatalError("NEXORA_TRIP_INVARIANT: unknown create failure") }
            let index = Int(result.handle.slot)
            guard index < journeys.count, journeys[index] == nil else {
                fatalError("NEXORA_TRIP_INVARIANT: occupied registration slot")
            }
            journeys[index] = JourneyRow(handle: result.handle, currentAirport: airport, active: nil)
            inputSequence = next
            return TripInputReceipt(handle: result.handle, activeTrip: nil, retired: false,
                                    inputToken: inputToken)

        case .depart(let handle, let destination, let duration):
            let (state, old) = try checkedRow(handle)
            guard state.state == .ready else { throw TripFailure.aircraft(.invalidTransition) }
            guard destination > 0 else { throw TripFailure.invalidAirport }
            guard destination != old.currentAirport else { throw TripFailure.sameAirport }
            guard duration > 0 else { throw TripFailure.invalidDuration }
            if let fareMinor, fareMinor <= 0 { throw TripFailure.finance(.invalidAmount) }
            let due = now.addingReportingOverflow(duration)
            guard !due.overflow else { throw TripFailure.timeOverflow }
            guard arrivals.count < arrivals.capacity else { throw TripFailure.eventCapacityExhausted }
            if failBeforeCommit { throw TripTestFailure.beforeInputCommit }
            let result: AircraftReceipt
            do { result = try aircraft.apply(.start(handle), expected: aircraft.token) }
            catch let error as AircraftFailure { throw TripFailure.aircraft(error) }
            catch { fatalError("NEXORA_TRIP_INVARIANT: unknown departure failure") }
            let trip = ScheduledArrival(handle: handle, operationID: result.token.revision,
                                        origin: old.currentAirport, destination: destination,
                                        departedAt: now, arrivesAt: due.partialValue, fareMinor: fareMinor ?? 0)
            journeys[Int(handle.slot)] = JourneyRow(handle: handle, currentAirport: old.currentAirport,
                                                    active: trip)
            arrivals.push(trip)
            inputSequence = next
            return TripInputReceipt(handle: handle, activeTrip: trip, retired: false,
                                    inputToken: inputToken)

        case .retireAircraft(let handle):
            let (state, _) = try checkedRow(handle)
            guard state.state == .ready else { throw TripFailure.aircraft(.invalidTransition) }
            if failBeforeCommit { throw TripTestFailure.beforeInputCommit }
            do { _ = try aircraft.apply(.retire(handle), expected: aircraft.token) }
            catch let error as AircraftFailure { throw TripFailure.aircraft(error) }
            catch { fatalError("NEXORA_TRIP_INVARIANT: unknown retirement failure") }
            journeys[Int(handle.slot)] = nil
            inputSequence = next
            return TripInputReceipt(handle: handle, activeTrip: nil, retired: true,
                                    inputToken: inputToken)
        }
    }

    /// Throws only for invalid request parameters, before any mutation.
    /// A per-event failure is a blocked result with its exact committed prefix.
    public mutating func advance(to target: UInt64, eventBudget: Int) throws -> AdvanceResult {
        try advanceCore(to: target, eventBudget: eventBudget, failAtEventIndex: nil)
    }

    private mutating func advanceCore(to target: UInt64, eventBudget: Int,
                                     failAtEventIndex: Int?) throws -> AdvanceResult {
        guard target >= now else { throw TripFailure.invalidTargetTime }
        guard (1...Self.maximumEventsPerAdvance).contains(eventBudget) else {
            throw TripFailure.invalidEventBudget
        }
        let from = now
        var completed: [TripCompletion] = []
        completed.reserveCapacity(min(eventBudget, arrivals.count))
        while completed.count < eventBudget, let trip = arrivals.peek(), trip.arrivesAt <= target {
            // Check all paired-state assumptions before the event's first write.
            guard trip.arrivesAt >= now, trip.departedAt < trip.arrivesAt,
                  trip.departedAt <= now else {
                fatalError("NEXORA_TRIP_INVARIANT: invalid due event time")
            }
            let state: AircraftView
            let row: JourneyRow
            do { (state, row) = try checkedRow(trip.handle) }
            catch { fatalError("NEXORA_TRIP_INVARIANT: due event has no live aircraft") }
            guard row.active == trip, state.state == .active(operationID: trip.operationID) else {
                fatalError("NEXORA_TRIP_INVARIANT: due event does not match active journey")
            }
            // Prepare all fallible financial effects before touching aircraft state.
            let preparedFinance: PreparedFinance?
            if trip.fareMinor > 0 {
                do {
                    preparedFinance = try finance.prepare(
                        .issueInvoice(origin: InvoiceOrigin(aircraft: trip.handle, operationID: trip.operationID),
                                      amountMinor: trip.fareMinor, at: trip.arrivesAt), expected: finance.token)
                } catch let error as FinanceFailure {
                    return progress(from: from, target: target, completed: completed, stop: .blocked(.finance(error)))
                } catch { fatalError("NEXORA_TRIP_INVARIANT: unexpected invoice preparation failure") }
            } else {
                guard trip.fareMinor == 0 else { fatalError("NEXORA_TRIP_INVARIANT: negative scheduled fare") }
                preparedFinance = nil
            }
            if failAtEventIndex == completed.count {
                return progress(from: from, target: target, completed: completed,
                                stop: .blocked(.injectedPreparationFailure))
            }
            let result: AircraftReceipt
            do {
                result = try aircraft.apply(.complete(trip.handle, operationID: trip.operationID),
                                            expected: aircraft.token)
            } catch let error as AircraftFailure {
                return progress(from: from, target: target, completed: completed,
                                stop: .blocked(.aircraft(error)))
            } catch { fatalError("NEXORA_TRIP_INVARIANT: unknown arrival failure") }
            let invoice: InvoiceView?
            switch consume preparedFinance {
            case .some(let plan): invoice = finance.commit(consume plan).invoice
            case .none: invoice = nil
            }
            journeys[Int(trip.handle.slot)] = JourneyRow(handle: trip.handle,
                                                         currentAirport: trip.destination, active: nil)
            let removed = arrivals.pop()
            guard removed == trip else { fatalError("NEXORA_TRIP_INVARIANT: wrong heap head removed") }
            now = trip.arrivesAt
            completed.append(TripCompletion(trip: trip, completedTrips: result.completedOperations, invoice: invoice))
        }
        if let head = arrivals.peek(), head.arrivesAt <= target {
            return progress(from: from, target: target, completed: completed, stop: .eventBudgetReached)
        }
        now = target
        return progress(from: from, target: target, completed: completed, stop: .reachedTarget)
    }

    private func progress(from: UInt64, target: UInt64, completed: [TripCompletion],
                          stop: AdvanceStop) -> AdvanceResult {
        AdvanceResult(fromTime: from, requestedTime: target, reachedTime: now,
                      completions: completed, nextDueTime: arrivals.peek()?.arrivesAt, stop: stop)
    }

    /// O(capacity + pending), allocating diagnostic only, never an apply/advance gate.
    public func checkInvariants() -> Bool {
        guard aircraft.capacity == journeys.count, aircraft.checkInvariants(),
              arrivals.checkInvariants(), finance.checkInvariants(),
              finance.lastPostedTime <= now else { return false }
        var seen = Array(repeating: false, count: journeys.count)
        var activeCount = 0, liveCount = 0
        for plan in arrivals.detachedEntries().prefix(arrivals.count) {
            guard let plan else { return false }
            let slot = Int(plan.handle.slot)
            guard slot < journeys.count, !seen[slot], let row = journeys[slot],
                  row.active == plan, plan.handle == row.handle, row.currentAirport == plan.origin,
                  plan.origin > 0, plan.destination > 0, plan.origin != plan.destination,
                  plan.departedAt < plan.arrivesAt, plan.departedAt <= now, plan.arrivesAt >= now,
                  plan.fareMinor >= 0 else {
                return false
            }
            seen[slot] = true
        }
        for (slot, row) in journeys.enumerated() {
            guard let row else { continue }
            guard Int(row.handle.slot) == slot, row.currentAirport > 0,
                  let state = try? aircraft.read(row.handle) else { return false }
            switch (state.state, row.active) {
            case (.ready, nil): if seen[slot] { return false }
            case (.active(let operationID), .some(let plan)):
                guard seen[slot], plan.operationID == operationID else { return false }
                activeCount += 1
            default: return false
            }
            liveCount += 1
        }
        return liveCount == aircraft.liveCount && activeCount == arrivals.count
    }

    // MARK: Internal, detached test evidence; no public mutable workspace.
    func auditForTesting() -> TripAudit {
        TripAudit(aircraft: aircraft.auditForTesting(), finance: finance.auditForTesting(), token: inputToken, now: now,
                  rows: journeys.map { $0.map { TripAuditRow(handle: $0.handle,
                    currentAirport: $0.currentAirport, active: $0.active) } },
                  heap: arrivals.detachedEntries(), heapCount: arrivals.count)
    }
    mutating func applyForTesting(_ command: TripCommand, expected: TripInputToken) throws -> TripInputReceipt {
        try applyCore(command, expected: expected, failBeforeCommit: true)
    }
    mutating func advanceForTesting(to target: UInt64, eventBudget: Int,
                                    failAtEventIndex: Int) throws -> AdvanceResult {
        try advanceCore(to: target, eventBudget: eventBudget, failAtEventIndex: failAtEventIndex)
    }
    mutating func applyFinanceForTesting(_ command: FinancialInputCommand,
                                         expected: TripInputToken) throws -> FinancialInputReceipt {
        try applyFinanceCore(command, expected: expected, failBeforeCommit: true)
    }
    mutating func corruptJourneyForTesting(_ handle: EntityHandle) {
        guard let row = journeys[Int(handle.slot)] else { fatalError("Invalid fixture") }
        journeys[Int(handle.slot)] = JourneyRow(handle: row.handle, currentAirport: row.currentAirport,
                                                active: nil)
    }
}

enum TripTestFailure: Error { case beforeInputCommit }
struct TripAuditRow: Equatable {
    let handle: EntityHandle
    let currentAirport: UInt32
    let active: ScheduledArrival?
}
struct TripAudit: Equatable {
    let aircraft: AircraftAudit
    let finance: FinanceAudit
    let token: TripInputToken
    let now: UInt64
    let rows: [TripAuditRow?]
    let heap: [ScheduledArrival?]
    let heapCount: Int
}
