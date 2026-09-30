/// Fixed-capacity min-heap. A coordinator preflights capacity before committing.
/// All mutations are bounded by the tree height; this storage never grows.
struct ArrivalHeap: ~Copyable, Sendable {
    private var nodes: [ScheduledArrival?]
    private(set) var count = 0
    var capacity: Int { nodes.count }
    init(capacity: Int) { nodes = Array(repeating: nil, count: capacity) }
    func peek() -> ScheduledArrival? { count == 0 ? nil : value(0) }

    private func value(_ index: Int) -> ScheduledArrival {
        guard index >= 0, index < count, let node = nodes[index] else {
            fatalError("NEXORA_TRIP_INVARIANT: heap hole or invalid index")
        }
        return node
    }
    private func precedes(_ left: ScheduledArrival, _ right: ScheduledArrival) -> Bool {
        left.arrivesAt < right.arrivesAt ||
            (left.arrivesAt == right.arrivesAt && left.operationID < right.operationID)
    }
    mutating func push(_ event: ScheduledArrival) {
        guard count < capacity else { fatalError("NEXORA_TRIP_INVARIANT: heap capacity not preflighted") }
        var index = count
        nodes[index] = event
        count += 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard precedes(value(index), value(parent)) else { break }
            nodes.swapAt(index, parent)
            index = parent
        }
    }
    mutating func pop() -> ScheduledArrival? {
        guard count > 0 else { return nil }
        let first = value(0)
        let last = value(count - 1)
        nodes[count - 1] = nil
        count -= 1
        guard count > 0 else { return first }
        nodes[0] = last
        var index = 0
        while index * 2 + 1 < count {
            let left = index * 2 + 1
            let right = left + 1
            let child = right < count && precedes(value(right), value(left)) ? right : left
            guard precedes(value(child), value(index)) else { break }
            nodes.swapAt(child, index)
            index = child
        }
        return first
    }
    func detachedEntries() -> [ScheduledArrival?] { nodes.map { $0 } }
    func checkInvariants() -> Bool {
        guard (0...capacity).contains(count) else { return false }
        for index in nodes.indices {
            if index >= count {
                guard nodes[index] == nil else { return false }
            } else {
                guard let node = nodes[index] else { return false }
                if index > 0 {
                    guard let parent = nodes[(index - 1) / 2], !precedes(node, parent) else { return false }
                }
            }
        }
        return true
    }
}
