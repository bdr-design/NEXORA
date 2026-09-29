import Synchronization
import NEXORADiagnostics

/// Serializes short authoritative mutation windows across domains that participate
/// in one coordinated in-memory transaction.
///
/// This is deliberately not a general-purpose work executor. Heavy computation
/// must happen before entering the gate.
public final class TransactionGate: Sendable {
    private let lock = Mutex<Bool>(false)

    public init() {}

    @inline(__always)
    func withPermit<Result>(_ body: () -> Result) -> Result {
        lock.withLock { _ in body() }
    }
}

public enum TransactionStepValidation: Sendable, Equatable {
    case ready
    case rejectedRevision
    case rejectedEntity
    case rejectedInvariant
}

public enum CoordinatedTransactionResult: Sendable, Equatable {
    case committed(stepCount: Int)
    case rejectedGateMismatch(stepIndex: Int)
    case rejectedDuplicateParticipant(stepIndex: Int)
    case rejected(stepIndex: Int, reason: TransactionStepValidation)
}

/// A prepared domain mutation. The initializer is intentionally internal so
/// only NEXORACore domains can construct authoritative transaction steps.
public struct TransactionStep: Sendable {
    let gate: TransactionGate
    let participantID: UInt64
    let validate: @Sendable () -> TransactionStepValidation
    let applyPrepared: @Sendable () -> Void

    init(
        gate: TransactionGate,
        participantID: UInt64,
        validate: @escaping @Sendable () -> TransactionStepValidation,
        applyPrepared: @escaping @Sendable () -> Void
    ) {
        self.gate = gate
        self.participantID = participantID
        self.validate = validate
        self.applyPrepared = applyPrepared
    }
}

/// Minimal in-memory coordinator.
///
/// All public reads/mutations of a participating domain must use the same gate.
/// The coordinator validates every step before the first mutation, then applies
/// non-failing prepared steps while the gate remains held.
///
/// Durable crash atomicity is NOT claimed here; that belongs to Persistence/WAL.
public final class TransactionCoordinator: Sendable {
    public let gate: TransactionGate
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        gate: TransactionGate = TransactionGate(),
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        self.gate = gate
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    public func commit(_ steps: [TransactionStep]) -> CoordinatedTransactionResult {
        let rootTraceID = traceIDs.next()
        let prepareStart = MonotonicClock.nowNanoseconds()

        let measured = gate.withPermit { () -> (CoordinatedTransactionResult, UInt64, UInt64, UInt64) in
            for index in steps.indices {
                guard steps[index].gate === gate else {
                    let now = MonotonicClock.nowNanoseconds()
                    return (.rejectedGateMismatch(stepIndex: index), now &- prepareStart, 0, now)
                }
                for prior in 0..<index where steps[prior].participantID == steps[index].participantID {
                    let now = MonotonicClock.nowNanoseconds()
                    return (.rejectedDuplicateParticipant(stepIndex: index), now &- prepareStart, 0, now)
                }
            }

            for (index, step) in steps.enumerated() {
                let validation = step.validate()
                guard validation == .ready else {
                    let now = MonotonicClock.nowNanoseconds()
                    return (.rejected(stepIndex: index, reason: validation), now &- prepareStart, 0, now)
                }
            }

            let commitStart = MonotonicClock.nowNanoseconds()
            for step in steps {
                step.applyPrepared()
            }
            let commitEnd = MonotonicClock.nowNanoseconds()
            return (.committed(stepCount: steps.count), commitStart &- prepareStart, commitEnd &- commitStart, commitStart)
        }

        let result = measured.0
        let traceResult = Self.traceResult(for: result)
        traceSink.record(TraceRecord(
            traceID: rootTraceID,
            domain: .transactionCoordinator,
            operation: .transactionPrepare,
            startedNanoseconds: prepareStart,
            durationNanoseconds: measured.1,
            workCount: UInt32(clamping: steps.count),
            result: traceResult
        ))

        if measured.2 > 0 {
            traceSink.record(TraceRecord(
                traceID: traceIDs.next(),
                parentTraceID: rootTraceID,
                domain: .transactionCoordinator,
                operation: .transactionCommit,
                startedNanoseconds: measured.3,
                durationNanoseconds: measured.2,
                workCount: UInt32(clamping: steps.count),
                result: traceResult
            ))
        }
        return result
    }

    private static func traceResult(for result: CoordinatedTransactionResult) -> TraceResultCode {
        switch result {
        case .committed:
            return .success
        case .rejectedGateMismatch:
            return .rejectedGate
        case .rejectedDuplicateParticipant:
            return .rejectedParticipant
        case .rejected:
            return .rejectedTransactionStep
        }
    }
}
