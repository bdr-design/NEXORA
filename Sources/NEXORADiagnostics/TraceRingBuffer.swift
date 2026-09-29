import Synchronization

public final class TraceRingBuffer: TraceSink, Sendable {
    private struct State: Sendable {
        var records: [TraceRecord?]
        var nextIndex: Int
        var count: Int

        init(capacity: Int) {
            records = Array(repeating: nil, count: capacity)
            nextIndex = 0
            count = 0
        }
    }

    private let capacityValue: Int
    private let state: Mutex<State>

    public init(capacity: Int = 4_096) {
        precondition(capacity > 0)
        self.capacityValue = capacity
        self.state = Mutex(State(capacity: capacity))
    }

    public var capacity: Int { capacityValue }

    @inline(__always)
    public func record(_ record: TraceRecord) {
        state.withLock { state in
            state.records[state.nextIndex] = record
            state.nextIndex += 1
            if state.nextIndex == capacityValue { state.nextIndex = 0 }
            if state.count < capacityValue { state.count += 1 }
        }
    }

    public func snapshot() -> [TraceRecord] {
        state.withLock { state in
            guard state.count > 0 else { return [] }
            var result: [TraceRecord] = []
            result.reserveCapacity(state.count)
            let start = state.count == capacityValue ? state.nextIndex : 0
            for offset in 0..<state.count {
                let index = (start + offset) % capacityValue
                if let record = state.records[index] {
                    result.append(record)
                }
            }
            return result
        }
    }
}
