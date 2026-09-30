import NexoraIdentity

private final class AircraftStamp: Sendable {}

/// Process-local expected revision. Only its store can issue it.
public struct RevisionToken: Equatable, Sendable {
    fileprivate let stamp: AircraftStamp
    public let revision: UInt64

    fileprivate init(stamp: AircraftStamp, revision: UInt64) {
        self.stamp = stamp
        self.revision = revision
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stamp === rhs.stamp && lhs.revision == rhs.revision
    }
}

public enum AircraftState: Equatable, Sendable {
    case ready
    case active(operationID: UInt64)
}

public enum AircraftCommand: Equatable, Sendable {
    case create
    case start(EntityHandle)
    case complete(EntityHandle, operationID: UInt64)
    case retire(EntityHandle)
}

public enum AircraftFailure: Error, Equatable, Sendable {
    case invalidCapacity, capacityExhausted
    case foreignToken, revisionConflict, revisionExhausted
    case invalidHandle, invalidTransition, operationMismatch, counterExhausted
}

/// Small immutable read. It never shares the store's array storage.
public struct AircraftView: Equatable, Sendable {
    public let handle: EntityHandle
    public let state: AircraftState
    public let completedOperations: UInt64
    public let token: RevisionToken
}

/// A successful result, not a durable receipt or retry cache.
public struct AircraftReceipt: Equatable, Sendable {
    public let handle: EntityHandle
    public let state: AircraftState?
    public let completedOperations: UInt64
    public let token: RevisionToken
}

private struct AircraftRecord: Equatable, Sendable {
    let handle: EntityHandle
    let state: AircraftState
    let completedOperations: UInt64
}

/// One synchronous owner of identity AND rows. No per-aircraft actor/lock/task.
/// This serial reference store is not a global revision gate for the whole game.
public struct AircraftStore: ~Copyable, Sendable {
    private let stamp: AircraftStamp
    private var identities: EntitySpace
    private var rows: [AircraftRecord?]
    private var revision: UInt64

    public var capacity: Int { rows.count }
    public var liveCount: Int { identities.liveCount }
    public var retiredSlotCount: Int { identities.retiredCount }
    public var token: RevisionToken { RevisionToken(stamp: stamp, revision: revision) }

    public init(capacity: Int) throws {
        try self.init(testingCapacity: capacity, initialRevision: 0, initialGeneration: 0)
    }

    // Test fixture construction is internal; it does not modify an existing store.
    init(testingCapacity: Int, initialRevision: UInt64 = 0,
         initialGeneration: UInt32 = 0) throws {
        guard (0...EntitySpace.maximumCapacity).contains(testingCapacity) else {
            throw AircraftFailure.invalidCapacity
        }
        identities = try EntitySpace(testingCapacity: testingCapacity,
                                     initialGeneration: initialGeneration)
        stamp = AircraftStamp()
        rows = Array(repeating: nil, count: testingCapacity)
        revision = initialRevision
    }

    public func read(_ handle: EntityHandle) throws -> AircraftView {
        let row = try record(for: handle)
        return AircraftView(handle: row.handle, state: row.state,
                            completedOperations: row.completedOperations, token: token)
    }

    /// Every expected error precedes the first write. No await, callback, I/O,
    /// diagnostic emission, growing array, or full-state snapshot inside this path.
    public mutating func apply(_ command: AircraftCommand,
                               expected: RevisionToken) throws -> AircraftReceipt {
        try applyCore(command, expected: expected, failureAt: nil)
    }

    private func nextRevision(expected: RevisionToken) throws -> UInt64 {
        guard expected.stamp === stamp else { throw AircraftFailure.foreignToken }
        guard expected.revision == revision else { throw AircraftFailure.revisionConflict }
        guard revision < UInt64.max else { throw AircraftFailure.revisionExhausted }
        return revision + 1
    }

    private func record(for handle: EntityHandle) throws -> AircraftRecord {
        guard identities.contains(handle) else { throw AircraftFailure.invalidHandle }
        guard let row = rows[Int(handle.slot)], row.handle == handle else {
            fatalError("NEXORA_AIRCRAFT_INVARIANT: live identity has no matching row")
        }
        return row
    }

    private mutating func applyCore(_ command: AircraftCommand, expected: RevisionToken,
                                   failureAt: AircraftTestFault?) throws -> AircraftReceipt {
        try inject(failureAt, at: .beforeValidation)
        let next = try nextRevision(expected: expected)
        switch command {
        case .create:
            try inject(failureAt, at: .afterPreparation)
            try inject(failureAt, at: .beforeCommit)
            // The allocator is the final expected failure point. Its exhaustion
            // check is before its first mutation. Never compensate with destroy.
            let handle: EntityHandle
            do { handle = try identities.create() }
            catch IdentityFailure.capacityExhausted { throw AircraftFailure.capacityExhausted }
            catch { fatalError("NEXORA_AIRCRAFT_INVARIANT: unexpected allocation error") }
            let index = Int(handle.slot)
            guard index < rows.count, rows[index] == nil else {
                fatalError("NEXORA_AIRCRAFT_INVARIANT: allocated slot is occupied")
            }
            let row = AircraftRecord(handle: handle, state: .ready, completedOperations: 0)
            rows[index] = row
            revision = next
            return receipt(row)

        case .start(let handle):
            let old = try record(for: handle)
            guard old.state == .ready else { throw AircraftFailure.invalidTransition }
            let replacement = AircraftRecord(handle: handle, state: .active(operationID: next),
                                             completedOperations: old.completedOperations)
            try inject(failureAt, at: .afterPreparation)
            try inject(failureAt, at: .beforeCommit)
            rows[Int(handle.slot)] = replacement
            revision = next
            return receipt(replacement)

        case .complete(let handle, let operationID):
            let old = try record(for: handle)
            guard case .active(let current) = old.state else {
                throw AircraftFailure.invalidTransition
            }
            guard operationID == current else { throw AircraftFailure.operationMismatch }
            guard old.completedOperations < UInt64.max else {
                throw AircraftFailure.counterExhausted
            }
            let replacement = AircraftRecord(handle: handle, state: .ready,
                                             completedOperations: old.completedOperations + 1)
            try inject(failureAt, at: .afterPreparation)
            try inject(failureAt, at: .beforeCommit)
            rows[Int(handle.slot)] = replacement
            revision = next
            return receipt(replacement)

        case .retire(let handle):
            let old = try record(for: handle)
            guard old.state == .ready else { throw AircraftFailure.invalidTransition }
            try inject(failureAt, at: .afterPreparation)
            try inject(failureAt, at: .beforeCommit)
            do { try identities.destroy(handle) }
            catch { fatalError("NEXORA_AIRCRAFT_INVARIANT: validated identity cannot retire") }
            rows[Int(handle.slot)] = nil
            revision = next
            return AircraftReceipt(handle: handle, state: nil,
                                   completedOperations: old.completedOperations, token: token)
        }
    }

    private func receipt(_ row: AircraftRecord) -> AircraftReceipt {
        AircraftReceipt(handle: row.handle, state: row.state,
                        completedOperations: row.completedOperations, token: token)
    }

    /// Explicit O(capacity) allocating diagnostic. Never used by apply/read.
    public func checkInvariants() -> Bool {
        guard identities.capacity == rows.count, identities.checkInvariants() else { return false }
        var count = 0
        for (index, row) in rows.enumerated() {
            guard let row else { continue }
            guard Int(row.handle.slot) == index, identities.contains(row.handle) else { return false }
            if case .active(let operationID) = row.state {
                guard operationID > 0, operationID <= revision else { return false }
            }
            count += 1
        }
        return count == identities.liveCount
    }

    // MARK: Internal test evidence. Not exported to ordinary external clients.

    func auditForTesting() -> AircraftAudit {
        AircraftAudit(identity: identities.auditIdentity(), token: token,
                      rows: rows.map { row in row.map {
                          AircraftAuditRow(handle: $0.handle, state: $0.state,
                                           completedOperations: $0.completedOperations)
                      } })
    }

    mutating func applyForTesting(_ command: AircraftCommand, expected: RevisionToken,
                                 failureAt: AircraftTestFault) throws -> AircraftReceipt {
        try applyCore(command, expected: expected, failureAt: failureAt)
    }

    private func inject(_ requested: AircraftTestFault?, at current: AircraftTestFault) throws {
        if requested == current { throw current }
    }

    /// Constructs otherwise unreachable numeric/corruption fixtures only for tests.
    /// Does not expose a general-purpose mutable array or mint an external handle.
    mutating func seedFixtureForTesting(_ fixture: AircraftFixture, handle: EntityHandle) {
        guard let row = rows[Int(handle.slot)] else { fatalError("Invalid test fixture") }
        switch fixture {
        case .maximumCompletions:
            rows[Int(handle.slot)] = AircraftRecord(handle: handle, state: row.state,
                                                   completedOperations: .max)
        case .missingLiveRow:
            rows[Int(handle.slot)] = nil
        case .occupiedFreeRow:
            do { try identities.destroy(handle) }
            catch { fatalError("Invalid test fixture") }
        }
    }
}

enum AircraftTestFault: Error, CaseIterable { case beforeValidation, afterPreparation, beforeCommit }
enum AircraftFixture { case maximumCompletions, missingLiveRow, occupiedFreeRow }
struct AircraftAuditRow: Equatable {
    let handle: EntityHandle
    let state: AircraftState
    let completedOperations: UInt64
}
struct AircraftAudit: Equatable {
    let identity: IdentityAudit
    let token: RevisionToken
    let rows: [AircraftAuditRow?]
}
