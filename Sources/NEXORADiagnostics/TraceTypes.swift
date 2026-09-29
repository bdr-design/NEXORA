import Synchronization

public enum TraceDomain: UInt8, Sendable, CaseIterable {
    case entityRegistry = 1
    case assetDomain = 2
    case compute = 3
    case merge = 4
    case commit = 5
    case benchmark = 6
    case transactionCoordinator = 7
}

public enum TraceOperation: UInt8, Sendable, CaseIterable {
    case entityCreate = 1
    case entityDestroy = 2
    case snapshot = 3
    case compute = 4
    case merge = 5
    case validate = 6
    case commit = 7
    case benchmarkIteration = 8
    case readGather = 9
    case transactionPrepare = 10
    case transactionCommit = 11
}

public enum TraceResultCode: UInt8, Sendable {
    case success = 0
    case rejectedRevision = 1
    case rejectedEntity = 2
    case rejectedInvariant = 3
    case rejectedGate = 4
    case rejectedParticipant = 5
    case rejectedTransactionStep = 6
}

public struct TraceRecord: Sendable, Equatable {
    public let traceID: UInt64
    public let parentTraceID: UInt64
    public let domain: TraceDomain
    public let operation: TraceOperation
    public let startedNanoseconds: UInt64
    public let durationNanoseconds: UInt64
    public let workCount: UInt32
    public let revision: UInt64
    public let result: TraceResultCode

    public init(
        traceID: UInt64,
        parentTraceID: UInt64 = 0,
        domain: TraceDomain,
        operation: TraceOperation,
        startedNanoseconds: UInt64,
        durationNanoseconds: UInt64,
        workCount: UInt32 = 0,
        revision: UInt64 = 0,
        result: TraceResultCode = .success
    ) {
        self.traceID = traceID
        self.parentTraceID = parentTraceID
        self.domain = domain
        self.operation = operation
        self.startedNanoseconds = startedNanoseconds
        self.durationNanoseconds = durationNanoseconds
        self.workCount = workCount
        self.revision = revision
        self.result = result
    }
}

public protocol TraceSink: Sendable {
    func record(_ record: TraceRecord)
}

public struct NullTraceSink: TraceSink {
    public init() {}
    @inline(__always)
    public func record(_ record: TraceRecord) {}
}

public final class TraceIDSource: Sendable {
    private let nextID = Mutex<UInt64>(1)

    public init() {}

    @inline(__always)
    public func next() -> UInt64 {
        nextID.withLock { value in
            let result = value
            value &+= 1
            if value == 0 { value = 1 }
            return result
        }
    }
}
