import Synchronization
import NEXORADiagnostics

public enum EntityDestroyResult: Sendable, Equatable {
    case destroyed
    case stale
    case invalidSlot
    case retiredGeneration
}

public final class EntityRegistry: Sendable {
    private struct RegistryState: Sendable {
        var generations: [UInt32]
        var alive: [UInt8]
        var freeSlots: [UInt32]
        var liveCount: Int

        init(capacity: Int) {
            generations = []
            alive = []
            freeSlots = []
            liveCount = 0
            generations.reserveCapacity(capacity)
            alive.reserveCapacity(capacity)
            freeSlots.reserveCapacity(capacity)
        }
    }

    private let state: Mutex<RegistryState>
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        capacity: Int = 100_000,
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        precondition(capacity >= 0)
        self.state = Mutex(RegistryState(capacity: capacity))
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    @inline(__always)
    public func create() -> EntityID {
        let start = MonotonicClock.nowNanoseconds()
        let id = state.withLock { state -> EntityID in
            let slot: UInt32
            if let reused = state.freeSlots.popLast() {
                slot = reused
                state.alive[Int(slot)] = 1
            } else {
                precondition(state.generations.count < Int(UInt32.max), "Entity registry exhausted UInt32 slots")
                slot = UInt32(state.generations.count)
                state.generations.append(0)
                state.alive.append(1)
            }
            state.liveCount += 1
            return EntityID(slot: slot, generation: state.generations[Int(slot)])
        }
        let end = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .entityRegistry,
            operation: .entityCreate,
            startedNanoseconds: start,
            durationNanoseconds: end &- start,
            workCount: 1
        ))
        return id
    }

    public func isAlive(_ id: EntityID) -> Bool {
        state.withLock { state in
            let slot = Int(id.slot)
            guard slot < state.generations.count, state.alive[slot] == 1 else { return false }
            return state.generations[slot] == id.generation
        }
    }

    @discardableResult
    public func destroy(_ id: EntityID) -> EntityDestroyResult {
        let start = MonotonicClock.nowNanoseconds()
        let result = state.withLock { state -> EntityDestroyResult in
            let slot = Int(id.slot)
            guard slot < state.generations.count else { return .invalidSlot }
            guard state.alive[slot] == 1, state.generations[slot] == id.generation else { return .stale }

            state.alive[slot] = 0
            state.liveCount -= 1

            if state.generations[slot] == UInt32.max {
                return .retiredGeneration
            }
            state.generations[slot] &+= 1
            state.freeSlots.append(id.slot)
            return .destroyed
        }
        let end = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .entityRegistry,
            operation: .entityDestroy,
            startedNanoseconds: start,
            durationNanoseconds: end &- start,
            workCount: 1,
            result: result == .destroyed ? .success : .rejectedEntity
        ))
        return result
    }

    public var count: Int {
        state.withLock { $0.liveCount }
    }
}
