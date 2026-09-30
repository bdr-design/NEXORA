/// One immutable stamp per space, NOT one reference object per entity.
/// Its identity prevents a handle from a different space from being accepted.
private final class SpaceStamp: Sendable {}

/// A process-local capability, not a persistence/replay identifier.
/// Only EntitySpace can mint one. Slot order is not simulation event order.
public struct EntityHandle: Sendable, Hashable {
    private let stamp: SpaceStamp
    public let slot: UInt32
    public let generation: UInt32

    fileprivate init(stamp: SpaceStamp, slot: UInt32, generation: UInt32) {
        self.stamp = stamp
        self.slot = slot
        self.generation = generation
    }

    fileprivate func belongs(to owner: SpaceStamp) -> Bool { stamp === owner }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stamp === rhs.stamp && lhs.slot == rhs.slot && lhs.generation == rhs.generation
    }

    public func hash(into hasher: inout Hasher) {
        // Collection membership only. Never a persistent or replay hash.
        hasher.combine(ObjectIdentifier(stamp))
        hasher.combine(slot)
        hasher.combine(generation)
    }
}

public enum IdentityFailure: Error, Sendable, Equatable {
    case invalidCapacity
    case capacityExhausted
    case foreignSpace
    case staleHandle
}

/// A bounded, uniquely owned identity store. No singleton, actor mailbox,
/// locks, callbacks, public mutable columns, or business values are present.
/// The owner must not call this synchronous store from UI-critical work.
public struct EntitySpace: ~Copyable, Sendable {
    public static var maximumCapacity: Int { 1_000_000 }
    private static var none: UInt32 { .max }
    private let stamp: SpaceStamp
    private var epochs: [UInt32]
    private var flags: [UInt8] // 0: free, 1: live, 2: permanently retired
    private var nextFree: [UInt32]
    private var freeHead: UInt32
    public private(set) var liveCount: Int
    public private(set) var retiredCount: Int
    public var capacity: Int { epochs.count }

    public init(capacity: Int) throws {
        try self.init(capacity: capacity, initialGeneration: 0)
    }

    // Test seam for otherwise impractical generation-exhaustion testing.
    // Not available to other modules, and cannot change an existing space.
    init(capacity: Int, initialGeneration: UInt32) throws {
        guard (0...Self.maximumCapacity).contains(capacity) else {
            throw IdentityFailure.invalidCapacity
        }
        stamp = SpaceStamp()
        epochs = Array(repeating: initialGeneration, count: capacity)
        flags = Array(repeating: 0, count: capacity)
        nextFree = (0..<capacity).map { i in
            i + 1 < capacity ? UInt32(i + 1) : Self.none
        }
        freeHead = capacity == 0 ? Self.none : 0
        liveCount = 0
        retiredCount = 0
    }

    public mutating func create() throws -> EntityHandle {
        guard freeHead != Self.none else { throw IdentityFailure.capacityExhausted }
        let index = Int(freeHead)
        let handle = EntityHandle(stamp: stamp, slot: freeHead, generation: epochs[index])
        freeHead = nextFree[index]
        nextFree[index] = Self.none
        flags[index] = 1
        liveCount += 1
        return handle
    }

    public func contains(_ handle: EntityHandle) -> Bool {
        guard handle.belongs(to: stamp) else { return false }
        let index = Int(handle.slot)
        return index < capacity && flags[index] == 1 && epochs[index] == handle.generation
    }

    public mutating func destroy(_ handle: EntityHandle) throws {
        guard handle.belongs(to: stamp) else { throw IdentityFailure.foreignSpace }
        guard contains(handle) else { throw IdentityFailure.staleHandle }
        let index = Int(handle.slot)
        liveCount -= 1
        if epochs[index] == UInt32.max {
            flags[index] = 2
            retiredCount += 1
        } else {
            epochs[index] += 1
            flags[index] = 0
            nextFree[index] = freeHead
            freeHead = handle.slot
        }
    }

    /// Deep O(capacity) audit with temporary scratch memory. NOT a hot-path check.
    public func checkInvariants() -> Bool {
        guard epochs.count == flags.count, epochs.count == nextFree.count else { return false }
        var visited = Array(repeating: false, count: capacity)
        var free = 0
        var cursor = freeHead
        while cursor != Self.none {
            let index = Int(cursor)
            guard index < capacity, !visited[index], flags[index] == 0 else { return false }
            visited[index] = true
            free += 1
            cursor = nextFree[index]
        }
        var live = 0
        var retired = 0
        for index in flags.indices {
            switch flags[index] {
            case 0:
                guard visited[index] else { return false }
            case 1:
                guard !visited[index], nextFree[index] == Self.none else { return false }
                live += 1
            case 2:
                guard !visited[index], nextFree[index] == Self.none,
                      epochs[index] == UInt32.max else { return false }
                retired += 1
            default: return false
            }
        }
        return live == liveCount && retired == retiredCount && free + live + retired == capacity
    }

    /// Package-only, detached read-only evidence. Never called by apply or per-frame work.
    package func auditIdentity() -> IdentityAudit {
        IdentityAudit(spaceID: ObjectIdentifier(stamp), epochs: epochs.map { $0 },
                      flags: flags.map { $0 }, nextFree: nextFree.map { $0 },
                      freeHead: freeHead, liveCount: liveCount, retiredCount: retiredCount)
    }

    /// Constructs a new test fixture; cannot alter an existing identity space.
    package init(testingCapacity: Int, initialGeneration: UInt32) throws {
        try self.init(capacity: testingCapacity, initialGeneration: initialGeneration)
    }

}


/// Exact diagnostic state, not a serialization format or a mutable storage view.
package struct IdentityAudit: Equatable, Sendable {
    package let spaceID: ObjectIdentifier
    package let epochs: [UInt32]
    package let flags: [UInt8]
    package let nextFree: [UInt32]
    package let freeHead: UInt32
    package let liveCount: Int
    package let retiredCount: Int
}
