public struct PackedAssetStorage: Sendable {
    public static let emptyDenseIndex = UInt32.max

    private(set) var sparse: [UInt32]
    private(set) var denseIDs: [EntityID]
    private(set) var values: [Double]
    private(set) var statuses: [UInt8]
    private(set) var nextEventTimes: [UInt64]

    public init(capacity: Int = 100_000) {
        precondition(capacity >= 0)
        sparse = []
        denseIDs = []
        values = []
        statuses = []
        nextEventTimes = []
        sparse.reserveCapacity(capacity)
        denseIDs.reserveCapacity(capacity)
        values.reserveCapacity(capacity)
        statuses.reserveCapacity(capacity)
        nextEventTimes.reserveCapacity(capacity)
    }

    public var count: Int { denseIDs.count }

    public func invariantHolds() -> Bool {
        denseIDs.count == values.count &&
        denseIDs.count == statuses.count &&
        denseIDs.count == nextEventTimes.count
    }

    @inline(__always)
    public func resolve(_ id: EntityID) -> Int? {
        let slot = Int(id.slot)
        guard slot < sparse.count else { return nil }
        let dense = sparse[slot]
        guard dense != Self.emptyDenseIndex else { return nil }
        let index = Int(dense)
        guard index < denseIDs.count, denseIDs[index] == id else { return nil }
        return index
    }

    public mutating func attach(id: EntityID, initial: AssetInitialState) -> AssetAttachResult {
        ensureSparseCapacity(for: Int(id.slot))
        let current = sparse[Int(id.slot)]
        if current != Self.emptyDenseIndex {
            let dense = Int(current)
            if dense < denseIDs.count, denseIDs[dense] == id {
                return .alreadyAttached(denseIndex: dense)
            }
            return .slotOccupiedByDifferentGeneration
        }

        let denseIndex = denseIDs.count
        precondition(denseIndex < Int(UInt32.max), "Dense asset storage exhausted UInt32 indices")
        denseIDs.append(id)
        values.append(initial.value)
        statuses.append(initial.status.rawValue)
        nextEventTimes.append(initial.nextEventTime)
        sparse[Int(id.slot)] = UInt32(denseIndex)
        assert(invariantHolds())
        return .attached(denseIndex: denseIndex)
    }

    @discardableResult
    public mutating func detach(id: EntityID) -> Bool {
        guard let denseIndex = resolve(id) else { return false }
        let last = denseIDs.count - 1
        let removedSlot = Int(id.slot)

        if denseIndex != last {
            let movedID = denseIDs[last]
            denseIDs[denseIndex] = movedID
            values[denseIndex] = values[last]
            statuses[denseIndex] = statuses[last]
            nextEventTimes[denseIndex] = nextEventTimes[last]
            sparse[Int(movedID.slot)] = UInt32(denseIndex)
        }

        denseIDs.removeLast()
        values.removeLast()
        statuses.removeLast()
        nextEventTimes.removeLast()
        sparse[removedSlot] = Self.emptyDenseIndex
        assert(invariantHolds())
        return true
    }

    @inline(__always)
    mutating func applyValidated(_ delta: AssetDelta) {
        let dense = resolve(delta.id)!
        values[dense] += delta.valueChange
    }

    func snapshot(revision: UInt64) -> AssetReadSnapshot {
        AssetReadSnapshot(
            revision: revision,
            ids: denseIDs,
            values: values,
            statuses: statuses,
            nextEventTimes: nextEventTimes
        )
    }

    func value(for id: EntityID) -> Double? {
        guard let dense = resolve(id) else { return nil }
        return values[dense]
    }

    private mutating func ensureSparseCapacity(for slot: Int) {
        if slot < sparse.count { return }
        sparse.append(contentsOf: repeatElement(Self.emptyDenseIndex, count: slot - sparse.count + 1))
    }
}
