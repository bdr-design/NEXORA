public struct EntityID: Hashable, Equatable, Sendable, Comparable, CustomStringConvertible {
    public let slot: UInt32
    public let generation: UInt32

    public init(slot: UInt32, generation: UInt32) {
        self.slot = slot
        self.generation = generation
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.slot == rhs.slot ? lhs.generation < rhs.generation : lhs.slot < rhs.slot
    }

    public var description: String { "\(slot):\(generation)" }
}
