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

    private let state: Mutex<DomainState>
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        capacity: Int = 100_000,
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        self.state = Mutex(DomainState(capacity: capacity))
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    @discardableResult
    public func attach(id: EntityID, initial: AssetInitialState) -> AssetAttachResult {
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

    @discardableResult
    public func detach(id: EntityID) -> Bool {
        state.withLock { state in
            let removed = state.storage.detach(id: id)
            if removed { state.revision &+= 1 }
            return removed
        }
    }

    public func snapshot() -> AssetReadSnapshot {
        let start = MonotonicClock.nowNanoseconds()
        let snapshot = state.withLock { $0.storage.snapshot(revision: $0.revision) }
        let end = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .assetDomain,
            operation: .snapshot,
            startedNanoseconds: start,
            durationNanoseconds: end &- start,
            workCount: UInt32(clamping: snapshot.count),
            revision: snapshot.revision
        ))
        return snapshot
    }

    public func commit(_ plan: AssetTransactionPlan) -> AssetCommitResult {
        let start = MonotonicClock.nowNanoseconds()
        let result = state.withLock { state -> AssetCommitResult in
            guard state.revision == plan.revision else {
                return .rejectedRevision(expected: plan.revision, actual: state.revision)
            }
            guard state.storage.invariantHolds() else {
                return .rejectedInvariant
            }

            for delta in plan.deltas {
                guard delta.valueChange.isFinite, state.storage.resolve(delta.id) != nil else {
                    return .rejectedEntity(delta.id)
                }
            }

            for delta in plan.deltas {
                state.storage.applyValidated(delta)
            }
            state.revision &+= 1
            return .committed(newRevision: state.revision, applied: plan.deltas.count)
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

    public func value(for id: EntityID) -> Double? {
        state.withLock { $0.storage.value(for: id) }
    }

    public var count: Int {
        state.withLock { $0.storage.count }
    }

    public var revision: UInt64 {
        state.withLock { $0.revision }
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
