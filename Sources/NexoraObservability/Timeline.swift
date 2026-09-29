public enum TraceStage: UInt8, Sendable {
    case creation = 1, verification = 2, destruction = 3
}

/// Minimum measurement envelope only. This is not yet a root-cause diagnosis engine.
public struct TraceEvent: Sendable, Equatable {
    public let sequence: UInt64
    public let parentSequence: UInt64?
    public let stage: TraceStage
    public let durationNanoseconds: UInt64
    public let itemCount: UInt32

    public init(sequence: UInt64, parentSequence: UInt64? = nil,
                stage: TraceStage, durationNanoseconds: UInt64, itemCount: UInt32) {
        self.sequence = sequence
        self.parentSequence = parentSequence
        self.stage = stage
        self.durationNanoseconds = durationNanoseconds
        self.itemCount = itemCount
    }
}

public enum TimelineFailure: Error, Sendable, Equatable {
    case invalidCapacity
    case nonMonotonicSequence
    case invalidParent
}

/// Single-owner bounded ring. No global counter, logging callback, or disk I/O.
/// Export is an explicit allocating operation outside measured hot work.
public struct Timeline: ~Copyable, Sendable {
    private var storage: [TraceEvent?]
    private var cursor = 0
    private var lastSequence: UInt64?
    public private(set) var count = 0
    public private(set) var overwritten: UInt64 = 0
    public var capacity: Int { storage.count }

    public init(capacity: Int) throws {
        guard (1...65_536).contains(capacity) else { throw TimelineFailure.invalidCapacity }
        storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ event: TraceEvent) throws {
        if let lastSequence, event.sequence <= lastSequence {
            throw TimelineFailure.nonMonotonicSequence
        }
        if let parent = event.parentSequence, parent >= event.sequence {
            throw TimelineFailure.invalidParent
        }
        storage[cursor] = event
        cursor = cursor + 1 == capacity ? 0 : cursor + 1
        if count < capacity {
            count += 1
        } else if overwritten < UInt64.max {
            overwritten += 1
        }
        lastSequence = event.sequence
    }

    public func export() -> [TraceEvent] {
        var events: [TraceEvent] = []
        events.reserveCapacity(count)
        let start = count == capacity ? cursor : 0
        for offset in 0..<count {
            if let event = storage[(start + offset) % capacity] { events.append(event) }
        }
        return events
    }
}
