import Synchronization

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

    public init(gate: TransactionGate = TransactionGate()) {
        self.gate = gate
    }

    public func commit(_ steps: [TransactionStep]) -> CoordinatedTransactionResult {
        gate.withPermit {
            for index in steps.indices {
                guard steps[index].gate === gate else {
                    return .rejectedGateMismatch(stepIndex: index)
                }
                for prior in 0..<index where steps[prior].participantID == steps[index].participantID {
                    return .rejectedDuplicateParticipant(stepIndex: index)
                }
            }

            for (index, step) in steps.enumerated() {
                let result = step.validate()
                guard result == .ready else {
                    return .rejected(stepIndex: index, reason: result)
                }
            }

            for step in steps {
                step.applyPrepared()
            }
            return .committed(stepCount: steps.count)
        }
    }
}
