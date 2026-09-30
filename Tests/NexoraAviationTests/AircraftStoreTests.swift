import Testing
import NexoraIdentity
import NexoraObservability
@testable import NexoraAviation

func check(_ condition: Bool, fileID: String = #fileID, filePath: String = #filePath,
           line: Int = #line, column: Int = #column) {
    #expect(condition, sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                                     line: line, column: column))
}

@discardableResult
func create(_ store: inout AircraftStore) throws -> EntityHandle {
    try store.apply(.create, expected: store.token).handle
}

func reject(_ command: AircraftCommand, _ error: AircraftFailure,
            store: inout AircraftStore, token: RevisionToken? = nil) {
    let before = store.auditForTesting()
    do {
        _ = try store.apply(command, expected: token ?? store.token)
        Issue.record("Expected rejection: \(error)")
    } catch let actual as AircraftFailure { check(actual == error) }
      catch { Issue.record("Unexpected error: \(error)") }
    check(store.auditForTesting() == before)
    check(store.checkInvariants())
}

struct AircraftStoreTests {
    @Test(arguments: [-1, Int.max, 1_000_001])
    func T01_invalidCapacity(_ size: Int) {
        do { _ = try AircraftStore(capacity: size); Issue.record("Expected invalid capacity") }
        catch { check(error as? AircraftFailure == .invalidCapacity) }
    }

    @Test func T02_zeroCapacityDoesNotMutate() throws {
        var store = try AircraftStore(capacity: 0)
        check(store.capacity == 0 && store.liveCount == 0)
        reject(.create, .capacityExhausted, store: &store)
    }

    @Test func T03_creationOwnsIdentityAndRow() throws {
        var store = try AircraftStore(capacity: 3)
        let before = store.token
        let receipt = try store.apply(.create, expected: before)
        let view = try store.read(receipt.handle)
        check(view.state == .ready && view.completedOperations == 0)
        check(view.token == receipt.token && view.token.revision == before.revision + 1)
        check(receipt.handle.slot == 0 && store.liveCount == 1)
        check(store.checkInvariants())
    }

    @Test func T04_fullCapacityPreservesExactState() throws {
        var store = try AircraftStore(capacity: 7)
        for _ in 0..<7 { try create(&store) }
        reject(.create, .capacityExhausted, store: &store)
    }

    @Test func T05_foreignTokenWinsErrorPrecedence() throws {
        let other = try AircraftStore(capacity: 0)
        var store = try AircraftStore(testingCapacity: 0, initialRevision: .max)
        reject(.create, .foreignToken, store: &store, token: other.token)
    }

    @Test func T06_staleTokenDoesNotMutate() throws {
        var store = try AircraftStore(capacity: 1)
        let old = store.token
        try create(&store)
        reject(.create, .revisionConflict, store: &store, token: old)
    }

    @Test func T07_repeatedCreationCannotCreateTwice() throws {
        var store = try AircraftStore(capacity: 2)
        let original = store.token
        let first = try store.apply(.create, expected: original)
        reject(.create, .revisionConflict, store: &store, token: original)
        check(store.liveCount == 1 && first.token == store.token)
    }

    @Test func T08_foreignHandleCannotReadOrWrite() throws {
        var left = try AircraftStore(capacity: 1)
        var right = try AircraftStore(capacity: 1)
        let a = try create(&left), b = try create(&right)
        check(a.slot == b.slot && a.generation == b.generation && a != b)
        let before = right.auditForTesting()
        do { _ = try right.read(a); Issue.record("Foreign read succeeded") }
        catch { check(error as? AircraftFailure == .invalidHandle) }
        check(right.auditForTesting() == before)
        for cmd: AircraftCommand in [.start(a), .complete(a, operationID: 2), .retire(a)] {
            reject(cmd, .invalidHandle, store: &right)
        }
    }

    @Test func T09_retiredHandleCannotReadOrWrite() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        _ = try store.apply(.retire(h), expected: store.token)
        do { _ = try store.read(h); Issue.record("Stale read succeeded") }
        catch { check(error as? AircraftFailure == .invalidHandle) }
        for cmd: AircraftCommand in [.start(h), .complete(h, operationID: 2), .retire(h)] {
            reject(cmd, .invalidHandle, store: &store)
        }
    }

    @Test func T10_slotReuseCannotReviveOldHandle() throws {
        var store = try AircraftStore(capacity: 1)
        let old = try create(&store)
        _ = try store.apply(.retire(old), expected: store.token)
        let new = try create(&store)
        check(old.slot == new.slot && new.generation == old.generation + 1)
        reject(.start(old), .invalidHandle, store: &store)
        check(try store.read(new).state == .ready)
    }

    @Test func T11_startIssuesUniqueOperation() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let start = try store.apply(.start(h), expected: store.token)
        check(start.state == .active(operationID: start.token.revision))
        check(start.completedOperations == 0 && start.token.revision == 2)
    }

    @Test func T12_startCannotRepeatWithFreshToken() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        _ = try store.apply(.start(h), expected: store.token)
        reject(.start(h), .invalidTransition, store: &store)
    }

    @Test func T13_completionHasOneEffect() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let started = try store.apply(.start(h), expected: store.token)
        let done = try store.apply(.complete(h, operationID: started.token.revision), expected: store.token)
        check(done.state == .ready && done.completedOperations == 1 && done.token.revision == 3)
        check(try store.read(h).completedOperations == 1)
    }

    @Test func T14_readyCannotComplete() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        reject(.complete(h, operationID: .max), .invalidTransition, store: &store)
    }

    @Test func T15_wrongOperationCannotComplete() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        _ = try store.apply(.start(h), expected: store.token)
        reject(.complete(h, operationID: 0), .operationMismatch, store: &store)
    }

    @Test func T16_delayedCompletionCannotAffectNewOperation() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let first = try store.apply(.start(h), expected: store.token)
        _ = try store.apply(.complete(h, operationID: first.token.revision), expected: store.token)
        let second = try store.apply(.start(h), expected: store.token)
        check(first.token.revision != second.token.revision)
        reject(.complete(h, operationID: first.token.revision), .operationMismatch, store: &store)
        check(try store.read(h).state == second.state)
    }

    @Test func T17_retirementRemovesBothIdentityAndRow() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let retired = try store.apply(.retire(h), expected: store.token)
        let audit = store.auditForTesting()
        check(retired.state == nil && retired.token.revision == 2)
        check(audit.rows == [nil] && audit.identity.flags == [0])
        check(audit.identity.epochs == [1] && store.liveCount == 0 && store.checkInvariants())
    }

    @Test func T18_activeCannotRetire() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        _ = try store.apply(.start(h), expected: store.token)
        reject(.retire(h), .invalidTransition, store: &store)
    }

    @Test func T19_repeatedCommandsAreRejected() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        var original = store.token
        let started = try store.apply(.start(h), expected: original)
        reject(.start(h), .revisionConflict, store: &store, token: original)
        original = store.token
        let complete: AircraftCommand = .complete(h, operationID: started.token.revision)
        _ = try store.apply(complete, expected: original)
        reject(complete, .revisionConflict, store: &store, token: original)
        original = store.token
        _ = try store.apply(.retire(h), expected: original)
        reject(.retire(h), .revisionConflict, store: &store, token: original)
    }

    @Test func T20_revisionNeverWrapsAndReadSurvives() throws {
        var store = try AircraftStore(testingCapacity: 1, initialRevision: UInt64.max - 1)
        let previous = store.token
        let h = try create(&store)
        check(store.token.revision == .max)
        reject(.start(h), .revisionConflict, store: &store, token: previous)
        for cmd: AircraftCommand in [.create, .start(h), .complete(h, operationID: 0), .retire(h)] {
            reject(cmd, .revisionExhausted, store: &store)
        }
        check(try store.read(h).state == .ready)
    }

    @Test func T21_completionCounterNeverWrapsAndErrorOrderIsStable() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let started = try store.apply(.start(h), expected: store.token)
        store.seedFixtureForTesting(.maximumCompletions, handle: h)
        reject(.complete(h, operationID: 0), .operationMismatch, store: &store)
        reject(.complete(h, operationID: started.token.revision), .counterExhausted, store: &store)
    }

    @Test(arguments: [UInt32.max - 1, UInt32.max])
    func T22_generationRetirement(_ generation: UInt32) throws {
        var store = try AircraftStore(testingCapacity: 1, initialGeneration: generation)
        var h = try create(&store)
        _ = try store.apply(.retire(h), expected: store.token)
        if generation < .max {
            h = try create(&store)
            check(h.generation == .max)
            _ = try store.apply(.retire(h), expected: store.token)
        }
        let audit = store.auditForTesting()
        check(audit.rows == [nil] && audit.identity.flags == [2])
        check(store.retiredSlotCount == 1 && store.liveCount == 0)
        reject(.create, .capacityExhausted, store: &store)
    }

    @Test func T23_faultInjectionPreservesEveryStateColumn() throws {
        for fault in AircraftTestFault.allCases {
            var store = try AircraftStore(capacity: 2)
            func fail(_ command: AircraftCommand, _ store: inout AircraftStore) {
                let before = store.auditForTesting()
                do {
                    _ = try store.applyForTesting(command, expected: store.token, failureAt: fault)
                    Issue.record("Injected fault was not reached")
                } catch { check(error as? AircraftTestFault == fault) }
                check(before == store.auditForTesting())
                check(store.checkInvariants())
            }
            fail(.create, &store)
            let h = try create(&store)
            fail(.start(h), &store)
            fail(.retire(h), &store)
            let start = try store.apply(.start(h), expected: store.token)
            fail(.complete(h, operationID: start.token.revision), &store)
        }
    }

    @Test func T24_failedCreateDoesNotConsumeFreeListOrGeneration() throws {
        var store = try AircraftStore(capacity: 2)
        let one = try create(&store), two = try create(&store)
        _ = try store.apply(.retire(one), expected: store.token)
        _ = try store.apply(.retire(two), expected: store.token)
        let before = store.auditForTesting()
        do { _ = try store.applyForTesting(.create, expected: store.token, failureAt: .beforeCommit) }
        catch { check(error as? AircraftTestFault == .beforeCommit) }
        check(store.auditForTesting() == before)
        let next = try create(&store)
        check(next.slot == two.slot && next.generation == two.generation + 1)
    }

    // T25 is an external compiler gate, not a runtime assertion.

    @Test func T26_readAndAuditViewsAreDetached() throws {
        var store = try AircraftStore(capacity: 1)
        let h = try create(&store)
        let old = try store.read(h)
        var audit = store.auditForTesting().identity.flags
        audit[0] = 99
        _ = try store.apply(.start(h), expected: store.token)
        check(old.state == .ready && old.token.revision == 1)
        check(store.auditForTesting().identity.flags == [1])
        check(try store.read(h).state == .active(operationID: 2))
        check(store.checkInvariants())
    }

    @Test func T27_corruptionIsDetectedByDeepAudit() throws {
        for fixture: AircraftFixture in [.missingLiveRow, .occupiedFreeRow] {
            var store = try AircraftStore(capacity: 1)
            let h = try create(&store)
            store.seedFixtureForTesting(fixture, handle: h)
            check(!store.checkInvariants())
        }
        // Crash behavior of read/create is verified in separate Debug/Release processes.
    }

    @Test func T28_diagnosticFailureCannotTurnSuccessIntoRetry() throws {
        var store = try AircraftStore(capacity: 1)
        var timeline = try Timeline(capacity: 1)
        try timeline.append(TraceEvent(sequence: 1, stage: .creation, durationNanoseconds: 1, itemCount: 1))
        let original = store.token
        let result = try store.apply(.create, expected: original)
        let committed = store.auditForTesting()
        do {
            try timeline.append(TraceEvent(sequence: 1, stage: .creation, durationNanoseconds: 1, itemCount: 1))
            Issue.record("Expected diagnostic rejection")
        } catch { check(error as? TimelineFailure == .nonMonotonicSequence) }
        check(result.token == store.token && committed == store.auditForTesting())
        reject(.create, .revisionConflict, store: &store, token: original)
    }

    // T29 is the independent serial-model suite in SerialReferenceTests.swift.

    @Test(arguments: [1_000, 5_000, 20_000, 50_000, 100_000])
    func T30_completeStoreLifecycleAtScale(_ size: Int) throws {
        var store = try AircraftStore(capacity: size)
        var handles: [EntityHandle] = []
        var operations: [UInt64] = []
        handles.reserveCapacity(size); operations.reserveCapacity(size)
        for _ in 0..<size { handles.append(try create(&store)) }
        check(store.checkInvariants() && store.liveCount == size)
        for h in handles {
            operations.append(try store.apply(.start(h), expected: store.token).token.revision)
        }
        check(store.checkInvariants())
        for (h, operation) in zip(handles, operations) {
            let result = try store.apply(.complete(h, operationID: operation), expected: store.token)
            check(result.completedOperations == 1 && result.state == .ready)
        }
        check(store.checkInvariants())
        for h in handles { _ = try store.apply(.retire(h), expected: store.token) }
        check(store.liveCount == 0 && store.token.revision == UInt64(size) * 4)
        check(store.checkInvariants())
    }

    // T31 is the source-path review gate, separate from executable tests.

    @Test func T32_logicalReplayMatchesButCrossWorldHandlesDoNot() throws {
        var a = try AircraftStore(capacity: 1), b = try AircraftStore(capacity: 1)
        let ha = try create(&a), hb = try create(&b)
        for _ in 0..<16 {
            let sa = try a.apply(.start(ha), expected: a.token)
            let sb = try b.apply(.start(hb), expected: b.token)
            check(sa.state == sb.state)
            let ca = try a.apply(.complete(ha, operationID: sa.token.revision), expected: a.token)
            let cb = try b.apply(.complete(hb, operationID: sb.token.revision), expected: b.token)
            check(ca.state == cb.state && ca.completedOperations == cb.completedOperations)
        }
        reject(.start(ha), .invalidHandle, store: &b)
        reject(.start(hb), .invalidHandle, store: &a)
        let replacement = try AircraftStore(capacity: 1)
        do { _ = try replacement.read(ha); Issue.record("Old world handle accepted") }
        catch { check(error as? AircraftFailure == .invalidHandle) }
    }
}
