public enum AssetStatus: UInt8, Sendable {
    case idle = 0
    case active = 1
    case unavailable = 2
}

public struct AssetInitialState: Sendable {
    public var value: Double
    public var status: AssetStatus
    public var nextEventTime: UInt64

    public init(value: Double, status: AssetStatus = .idle, nextEventTime: UInt64 = 0) {
        self.value = value
        self.status = status
        self.nextEventTime = nextEventTime
    }
}

public struct AssetDelta: Sendable, Equatable {
    public let id: EntityID
    public let valueChange: Double

    public init(id: EntityID, valueChange: Double) {
        self.id = id
        self.valueChange = valueChange
    }
}

/// Explicit detached read batch.
///
/// The batch owns its buffers; it never aliases authoritative domain storage.
/// Only selected rows are gathered, so the cost scales with due/active work
/// rather than with every stored asset.
public struct AssetReadBatch: Sendable {
    public private(set) var revision: UInt64
    public private(set) var ids: [EntityID]
    public private(set) var values: [Double]
    public private(set) var statuses: [UInt8]
    public private(set) var nextEventTimes: [UInt64]

    public init(capacity: Int = 0) {
        precondition(capacity >= 0)
        revision = 0
        ids = []
        values = []
        statuses = []
        nextEventTimes = []
        ids.reserveCapacity(capacity)
        values.reserveCapacity(capacity)
        statuses.reserveCapacity(capacity)
        nextEventTimes.reserveCapacity(capacity)
    }

    public var count: Int { ids.count }

    mutating func reset(revision: UInt64) {
        self.revision = revision
        ids.removeAll(keepingCapacity: true)
        values.removeAll(keepingCapacity: true)
        statuses.removeAll(keepingCapacity: true)
        nextEventTimes.removeAll(keepingCapacity: true)
    }

    mutating func append(id: EntityID, value: Double, status: UInt8, nextEventTime: UInt64) {
        ids.append(id)
        values.append(value)
        statuses.append(status)
        nextEventTimes.append(nextEventTime)
    }

    public func invariantHolds() -> Bool {
        ids.count == values.count &&
        ids.count == statuses.count &&
        ids.count == nextEventTimes.count
    }
}

public struct AssetComputeOutput: Sendable {
    public let deltas: [AssetDelta]
    public let computeNanoseconds: UInt64
    public let mergeNanoseconds: UInt64
    public let workerCount: Int

    public init(deltas: [AssetDelta], computeNanoseconds: UInt64, mergeNanoseconds: UInt64, workerCount: Int) {
        self.deltas = deltas
        self.computeNanoseconds = computeNanoseconds
        self.mergeNanoseconds = mergeNanoseconds
        self.workerCount = workerCount
    }
}

public struct AssetTransactionPlan: Sendable {
    public let revision: UInt64
    public let deltas: [AssetDelta]

    public init(revision: UInt64, deltas: [AssetDelta]) {
        self.revision = revision
        self.deltas = deltas
    }
}

public enum AssetCommitResult: Sendable, Equatable {
    case committed(newRevision: UInt64, applied: Int)
    case rejectedRevision(expected: UInt64, actual: UInt64)
    case rejectedEntity(EntityID)
    case rejectedInvariant
}

public enum AssetAttachResult: Sendable, Equatable {
    case attached(denseIndex: Int)
    case alreadyAttached(denseIndex: Int)
    case slotOccupiedByDifferentGeneration
}
