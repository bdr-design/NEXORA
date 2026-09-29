import Synchronization
import NEXORADiagnostics

public final class AssetDomain: Sendable {
    private struct DomainState: Sendable {
        var storage: PackedAssetStorage
        var revision: UInt64

        init(capacity: Int) {
            storage = PackedAssetStorage(capacity: capacity)
            revision = 0
        }
    }

    private static let participantIDs = Mutex<UInt64>(1)

    private let state: Mutex<DomainState>
    private let gate: TransactionGate
    private let participantID: UInt64
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        capacity: Int = 100_000,
        gate: TransactionGate = TransactionGate(),
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        self.state = Mutex(DomainState(capacity: capacity))
        self.gate = gate
        self.participantID = Self.participantIDs.withLock { value in
            let id = value
            value &+= 1
            if value == 0 { value = 1 }
            return id
        }
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    @discardableResult
    public func attach(id: EntityID, initial: AssetInitialState) -> AssetAttachResult {
        gate.withPermit {
            state.withLock { state in
                let result = state.storage.attach(id: id, initial: initial)
                switch result {
                case .attached:
                    state.revision &+= 1
                case .alreadyAttached, .slotOccupiedByDifferentGeneration:
                    break
                }
                return result
            }
        }
    }

    @discardableResult
    public func detach(id: EntityID) -> Bool {
        gate.withPermit {
            state.withLock { state in
                let removed = state.storage.detach(id: id)
                if removed { state.revision &+= 1 }
                return removed
            }
        }
    }

    /// Gathers only selected rows into caller-owned detached buffers.
    /// This removes the old full-Array snapshot aliasing/CoW boundary.
    public func fillReadBatch(selectionStride: Int, into batch: inout AssetReadBatch) {
        let start = MonotonicClock.nowNanoseconds()
        gate.withPermit {
            state.withLock { state in
                state.storage.fillReadBatch(
                    revision: state.revision,
                    selectionStride: selectionStride,
                    into: &batch
                )
            }
        }
        let end = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .assetDomain,
            operation: .readGather,
            startedNanoseconds: start,
            durationNanoseconds: end &- start,
            workCount: UInt32(clamping: batch.count),
            revision: batch.revision
        ))
    }

    public func commit(_ plan: AssetTransactionPlan) -> AssetCommitResult {
        let start = MonotonicClock.nowNanoseconds()
        let result = gate.withPermit {
            let validation = validateWithoutGate(plan)
            switch validation {
            case .ready:
                return applyPreparedWithoutGate(plan)
            case .rejectedRevision:
                let actual = state.withLock { $0.revision }
                return .rejectedRevision(expected: plan.revision, actual: actual)
            case .rejectedEntity:
                let rejected = plan.deltas.first { delta in
                    state.withLock { $0.storage.resolve(delta.id) == nil || !delta.valueChange.isFinite }
                }?.id ?? EntityID(slot: 0, generation: 0)
                return .rejectedEntity(rejected)
            case .rejectedInvariant:
                return .rejectedInvariant
            }
        }
        let end = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .commit,
            operation: .commit,
            startedNanoseconds: start,
            durationNanoseconds: end &- start,
            workCount: UInt32(clamping: plan.deltas.count),
            revision: plan.revision,
            result: Self.traceResult(for: result)
        ))
        return result
    }

    /// Produces one coordinator step. The coordinator must share this domain's gate.
    public func transactionStep(for plan: AssetTransactionPlan) -> TransactionStep {
        TransactionStep(
            gate: gate,
            participantID: participantID,
            validate: { [self] in validateWithoutGate(plan) },
            applyPrepared: { [self] in _ = applyPreparedWithoutGate(plan) }
        )
    }

    public func value(for id: EntityID) -> Double? {
        gate.withPermit {
            state.withLock { $0.storage.value(for: id) }
        }
    }

    public var count: Int {
        gate.withPermit {
            state.withLock { $0.storage.count }
        }
    }

    public var revision: UInt64 {
        gate.withPermit {
            state.withLock { $0.revision }
        }
    }

    private func validateWithoutGate(_ plan: AssetTransactionPlan) -> TransactionStepValidation {
        state.withLock { state in
            guard state.revision == plan.revision else { return .rejectedRevision }
            guard state.storage.invariantHolds() else { return .rejectedInvariant }
            for delta in plan.deltas {
                guard delta.valueChange.isFinite, state.storage.resolve(delta.id) != nil else {
                    return .rejectedEntity
                }
            }
            return .ready
        }
    }

    private func applyPreparedWithoutGate(_ plan: AssetTransactionPlan) -> AssetCommitResult {
        state.withLock { state in
            precondition(state.revision == plan.revision, "Prepared transaction revision changed while gate was held")
            for delta in plan.deltas {
                state.storage.applyValidated(delta)
            }
            state.revision &+= 1
            return .committed(newRevision: state.revision, applied: plan.deltas.count)
        }
    }

    private static func traceResult(for result: AssetCommitResult) -> TraceResultCode {
        switch result {
        case .committed: return .success
        case .rejectedRevision: return .rejectedRevision
        case .rejectedEntity: return .rejectedEntity
        case .rejectedInvariant: return .rejectedInvariant
        }
    }
}
