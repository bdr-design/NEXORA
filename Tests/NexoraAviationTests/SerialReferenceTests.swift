import Testing
import NexoraIdentity
@testable import NexoraAviation

// Deliberately independent test model: dictionary rows + stack of free slots.
// It never calls AircraftStore/EntitySpace or their validation/commit helpers.
private struct ModelRow: Equatable {
    var generation: UInt32
    var operation: UInt64?
    var completed: UInt64
}
private struct ModelResult: Equatable {
    let slot: UInt32
    let generation: UInt32
    let operation: UInt64?
    let completed: UInt64
    let revision: UInt64
    let retired: Bool
}
private struct SerialModel {
    var revision: UInt64 = 0
    var generations: [UInt32]
    var live: [UInt32: ModelRow] = [:]
    var permanentlyRetired: Set<UInt32> = []
    var free: [UInt32]

    init(capacity: Int, generation: UInt32) {
        generations = Array(repeating: generation, count: capacity)
        free = (0..<capacity).reversed().map(UInt32.init)
    }

    mutating func apply(_ command: AircraftCommand, expected: UInt64,
                        foreignToken: Bool, foreignHandle: Bool) throws -> ModelResult {
        if foreignToken { throw AircraftFailure.foreignToken }
        if expected != revision { throw AircraftFailure.revisionConflict }
        if revision == .max { throw AircraftFailure.revisionExhausted }
        let newRevision = revision + 1
        switch command {
        case .create:
            guard let slot = free.last else { throw AircraftFailure.capacityExhausted }
            let generation = generations[Int(slot)]
            free.removeLast()
            live[slot] = ModelRow(generation: generation, operation: nil, completed: 0)
            revision = newRevision
            return ModelResult(slot: slot, generation: generation, operation: nil,
                               completed: 0, revision: revision, retired: false)
        case .start(let h), .complete(let h, _), .retire(let h):
            guard !foreignHandle, var row = live[h.slot], row.generation == h.generation else {
                throw AircraftFailure.invalidHandle
            }
            switch command {
            case .start:
                if row.operation != nil { throw AircraftFailure.invalidTransition }
                row.operation = newRevision
                live[h.slot] = row
            case .complete(_, let id):
                guard let current = row.operation else { throw AircraftFailure.invalidTransition }
                if current != id { throw AircraftFailure.operationMismatch }
                if row.completed == .max { throw AircraftFailure.counterExhausted }
                row.completed += 1
                row.operation = nil
                live[h.slot] = row
            case .retire:
                if row.operation != nil { throw AircraftFailure.invalidTransition }
                live.removeValue(forKey: h.slot)
                if row.generation == .max {
                    permanentlyRetired.insert(h.slot)
                } else {
                    generations[Int(h.slot)] += 1
                    free.append(h.slot)
                }
            case .create: fatalError("Model command classification")
            }
            revision = newRevision
            return ModelResult(slot: h.slot, generation: h.generation, operation: row.operation,
                               completed: row.completed, revision: revision, retired: live[h.slot] == nil)
        }
    }
}

private struct SeededGenerator {
    var value: UInt64
    mutating func next(_ limit: Int) -> Int {
        value = value &* 2862933555777941757 &+ 3037000493
        return Int((value >> 24) % UInt64(limit))
    }
}

struct SerialReferenceTests {
    @Test(arguments: [UInt64(1), 73, 12345, 998])
    func T29_randomCommandsMatchIndependentReference(_ seed: UInt64) throws {
        let capacity = 17
        let generation: UInt32 = seed == 998 ? .max - 2 : 0
        var store = try AircraftStore(testingCapacity: capacity, initialGeneration: generation)
        var foreign = try AircraftStore(capacity: capacity)
        let foreignHandle = try create(&foreign)
        var model = SerialModel(capacity: capacity, generation: generation)
        var random = SeededGenerator(value: seed)
        var known: [EntityHandle] = []
        var tokens: [RevisionToken] = [store.token]
        var successes = 0, rejections = 0
        for _ in 0..<5_000 {
            let kind = known.isEmpty ? 0 : random.next(4)
            let isForeignHandle = kind != 0 && random.next(13) == 0
            let h = kind == 0 ? foreignHandle :
                (isForeignHandle ? foreignHandle : known[random.next(known.count)])
            let currentID = model.live[h.slot]?.operation ?? 0
            let operationID = random.next(3) == 0 ? UInt64(random.next(1000)) : currentID
            let command: AircraftCommand
            switch kind {
            case 0: command = .create
            case 1: command = .start(h)
            case 2: command = .complete(h, operationID: operationID)
            default: command = .retire(h)
            }
            let isForeignToken = random.next(19) == 0
            let expected: RevisionToken = isForeignToken ? foreign.token :
                (random.next(5) == 0 ? tokens[random.next(tokens.count)] : store.token)
            let before = store.auditForTesting()
            var modelResult: ModelResult?
            var modelError: AircraftFailure?
            do { modelResult = try model.apply(command, expected: expected.revision,
                                                foreignToken: isForeignToken, foreignHandle: isForeignHandle) }
            catch { modelError = error as? AircraftFailure; check(modelError != nil) }
            do {
                let actual = try store.apply(command, expected: expected)
                var op: UInt64?
                if case .active(let id) = actual.state { op = id }
                let normalized = ModelResult(slot: actual.handle.slot, generation: actual.handle.generation,
                                             operation: op, completed: actual.completedOperations,
                                             revision: actual.token.revision, retired: actual.state == nil)
                check(modelError == nil && modelResult == normalized)
                if kind == 0 { known.append(actual.handle) }
                tokens.append(actual.token)
                successes += 1
            } catch {
                check(error as? AircraftFailure == modelError && modelResult == nil)
                check(store.auditForTesting() == before)
                rejections += 1
            }
            let audit = store.auditForTesting()
            check(audit.token.revision == model.revision)
            check(audit.identity.epochs == model.generations)
            check(audit.identity.liveCount == model.live.count)
            check(audit.identity.retiredCount == model.permanentlyRetired.count)
            check(audit.identity.freeHead == model.free.last ?? UInt32.max)
            var expectedNext = Array(repeating: UInt32.max, count: capacity)
            let chain = Array(model.free.reversed())
            for i in chain.indices where i + 1 < chain.count {
                expectedNext[Int(chain[i])] = chain[i + 1]
            }
            check(audit.identity.nextFree == expectedNext)
            for slot in 0..<capacity {
                let key = UInt32(slot)
                let expectedFlag: UInt8 = model.live[key] != nil ? 1 :
                    (model.permanentlyRetired.contains(key) ? 2 : 0)
                check(audit.identity.flags[slot] == expectedFlag)
                if let row = model.live[key], let actual = audit.rows[slot] {
                    let expectedState: AircraftState = row.operation.map { .active(operationID: $0) } ?? .ready
                    check(actual.handle.slot == key && actual.handle.generation == row.generation)
                    check(actual.state == expectedState && actual.completedOperations == row.completed)
                } else { check(model.live[key] == nil && audit.rows[slot] == nil) }
            }
            check(store.checkInvariants())
        }
        check(successes > 50 && rejections > 50)
    }

    @Test func movingOwnerDoesNotInvalidateItsHandles() throws {
        var original = try AircraftStore(capacity: 1)
        let h = try create(&original)
        var moved = consume original
        check(try moved.read(h).state == .ready)
        _ = try moved.apply(.start(h), expected: moved.token)
        check(moved.checkInvariants())
    }

    @Test func concurrentIndependentOwnersDoNotShareMutableState() async throws {
        try await withThrowingTaskGroup(of: EntityHandle.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    var store = try AircraftStore(capacity: 1)
                    let h = try create(&store)
                    for _ in 0..<128 {
                        let start = try store.apply(.start(h), expected: store.token)
                        _ = try store.apply(.complete(h, operationID: start.token.revision), expected: store.token)
                    }
                    check(try store.read(h).completedOperations == 128)
                    return h
                }
            }
            var handles = Set<EntityHandle>()
            for try await h in group { handles.insert(h) }
            check(handles.count == 16)
        }
    }
}
