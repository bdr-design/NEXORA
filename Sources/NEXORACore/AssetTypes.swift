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

public struct AssetReadSnapshot: Sendable {
    public let revision: UInt64
    public let ids: [EntityID]
    public let values: [Double]
    public let statuses: [UInt8]
    public let nextEventTimes: [UInt64]

    public var count: Int { ids.count }
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
