import XCTest
@testable import AtomicRescheduleMicro

final class ChunkedTransactionTests: XCTestCase {
    private func request(count: Int, operation: UInt64 = 1, time: UInt64 = 100,
                         id: String = "r1") -> RescheduleRequest {
        RescheduleRequest(id: id, time: time, firstOperation: operation, count: count)
    }

    private func complete(_ world: ChunkedTransactionWorld, request: RescheduleRequest,
                          journal: JournalMock, budget: Int = 17) throws -> (Int, Int) {
        XCTAssertNil(try world.begin(request, journal: journal))
        var calls = 0
        var units = 0
        while world.phaseForDiagnostics != .idle {
            let tick = try world.tick(budget: budget, journal: journal)
            XCTAssertLessThanOrEqual(tick.workItems, budget)
            XCTAssertGreaterThanOrEqual(tick.workItems, 0)
            calls += 1
            units += tick.workItems
            XCTAssertLessThan(calls, request.count * 2 + 4)
            if world.phaseForDiagnostics != .idle {
                XCTAssertThrowsError(try world.inspect()) { error in
                    XCTAssertEqual(error as? MicroFailure, .readDuringTransaction)
                }
            }
        }
        return (calls, units)
    }

    func test_bounded_chunks_and_atomic_visibility() throws {
        let count = 257
        let j = JournalMock()
        let w = try ChunkedTransactionWorld(count: count)
        let before = try w.inspect()
        let req = request(count: count)
        XCTAssertNil(try w.begin(req, journal: j))
        XCTAssertEqual(try w.tick(budget: 17, journal: j).workItems, 17)
        XCTAssertEqual(w.fixedEventSlots, count)
        XCTAssertThrowsError(try w.inspect())
        XCTAssertThrowsError(try w.begin(req, journal: j))
        var units = 17
        while w.phaseForDiagnostics != .idle {
            let t = try w.tick(budget: 17, journal: j)
            XCTAssertLessThanOrEqual(t.workItems, 17)
            units += t.workItems
        }
        let after = try w.inspect()
        XCTAssertEqual(units, 2 * count)
        XCTAssertEqual(after.publishedEvents, count)
        XCTAssertEqual(after.activeCount, count)
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
        XCTAssertEqual(j.status(for: req.id)?.0, req)
    }

    func test_request_and_time_overflow_rejected_before_any_write() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 3)
        let before = try w.inspect()
        XCTAssertThrowsError(try w.begin(request(count: 3, operation: .max), journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .operationOverflow)
        }
        XCTAssertThrowsError(try w.begin(request(count: 3, time: .max), journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .timeOverflow)
        }
        XCTAssertEqual(try w.inspect(), before)
        XCTAssertNil(j.committedRecord())
    }

    func test_late_validation_failure_has_no_partial_mutation() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 73)
        try w.prepareTestPriorOperation(asset: 72, lastOperation: 1000)
        let before = try w.inspect()
        try w.begin(request(count: 73, operation: 1), journal: j)
        XCTAssertEqual(try w.tick(budget: 70, journal: j).workItems, 70)
        XCTAssertThrowsError(try w.tick(budget: 70, journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .staleOrActiveAsset)
        }
        XCTAssertEqual(w.phaseForDiagnostics, .idle)
        XCTAssertEqual(try w.inspect(), before)
        XCTAssertNil(j.committedRecord())
    }

    func test_failure_after_first_staged_write_poison_and_recover_old_world() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 100)
        let baseline = try w.inspect()
        try w.injectStageFailure(at: 41)
        try w.begin(request(count: 100), journal: j)
        _ = try w.tick(budget: 100, journal: j)
        XCTAssertThrowsError(try w.inspect())
        _ = try w.tick(budget: 25, journal: j)
        XCTAssertThrowsError(try w.tick(budget: 30, journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .injectedFailure)
        }
        XCTAssertEqual(w.phaseForDiagnostics, .recoveryRequired)
        XCTAssertThrowsError(try w.inspect())
        XCTAssertThrowsError(try w.tick(budget: 1, journal: j))
        XCTAssertNil(j.committedRecord())
        XCTAssertEqual(try ChunkedTransactionWorld.recover(count: 100, from: j, expectedBase: baseline).inspect(), baseline)
    }

    func test_before_durable_failure_cannot_publish_partial() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 257)
        let baseline = try w.inspect()
        j.nextFailure = .beforeDurable
        try w.begin(request(count: 257), journal: j)
        while w.phaseForDiagnostics == .validating || w.phaseForDiagnostics == .staging {
            _ = try w.tick(budget: 19, journal: j)
        }
        XCTAssertThrowsError(try w.tick(budget: 19, journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .journalUnavailable)
        }
        XCTAssertEqual(w.phaseForDiagnostics, .recoveryRequired)
        XCTAssertThrowsError(try w.inspect())
        XCTAssertEqual(try ChunkedTransactionWorld.recover(count: 257, from: j, expectedBase: baseline).inspect(), baseline)
    }

    func test_durable_tip_before_ack_requires_query_and_recovery() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 257)
        let req = request(count: 257)
        let baseline = try w.inspect()
        j.nextFailure = .afterDurable
        try w.begin(req, journal: j)
        while w.phaseForDiagnostics == .validating || w.phaseForDiagnostics == .staging {
            _ = try w.tick(budget: 31, journal: j)
        }
        XCTAssertThrowsError(try w.tick(budget: 31, journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .uncertainCommit)
        }
        XCTAssertEqual(w.phaseForDiagnostics, .recoveryRequired)
        XCTAssertThrowsError(try w.inspect())
        XCTAssertNotNil(j.status(for: req.id))
        let fresh = try ChunkedTransactionWorld.recover(count: 257, from: j, expectedBase: baseline)
        XCTAssertEqual(try fresh.inspect().activeCount, 257)
        XCTAssertEqual(try fresh.inspect().publishedEvents, 257)
        XCTAssertEqual(try fresh.begin(req, journal: j), j.status(for: req.id)?.1)
        XCTAssertThrowsError(try fresh.begin(request(count: 257, operation: 2), journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .requestConflict)
        }
        XCTAssertEqual(try fresh.inspect().activeCount, 257)
    }

    func test_replay_determinism_across_budget_choices() throws {
        let budgets = [1, 2, 7, 64, 256, 1024]
        var expected: VisibleWorld?
        for budget in budgets {
            let j = JournalMock(), world = try ChunkedTransactionWorld(count: 4096)
            let baseline = try world.inspect()
            let outcome = try complete(world, request: request(count: 4096), journal: j, budget: budget)
            XCTAssertEqual(outcome.1, 8192)
            let actual = try world.inspect()
            XCTAssertEqual(actual, try ChunkedTransactionWorld.recover(count: 4096, from: j, expectedBase: baseline).inspect())
            if let expected { XCTAssertEqual(actual, expected) }
            expected = actual
        }
    }

    func test_bounded_hundred_thousand_fixture_not_device_benchmark() throws {
        let n = 100_000
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: n)
        let baseline = try w.inspect()
        let (calls, units) = try complete(w, request: request(count: n), journal: j, budget: 2_048)
        XCTAssertEqual(units, 2 * n)
        XCTAssertEqual(calls, 2 * ((n + 2047)/2048) + 1)
        XCTAssertEqual(try w.inspect(), try ChunkedTransactionWorld.recover(count: n, from: j, expectedBase: baseline).inspect())
    }

    func test_input_errors_and_transaction_reentrancy() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 2)
        XCTAssertThrowsError(try w.begin(request(count: 3), journal: j))
        XCTAssertThrowsError(try w.begin(request(count: 2, id: ""), journal: j))
        try w.begin(request(count: 2), journal: j)
        XCTAssertThrowsError(try w.tick(budget: 0, journal: j))
        XCTAssertThrowsError(try w.begin(request(count: 2), journal: j))
        XCTAssertThrowsError(try w.prepareTestPriorOperation(asset: 0, lastOperation: 9))
        XCTAssertThrowsError(try w.injectStageFailure(at: 1))
        XCTAssertThrowsError(try w.inspect())
    }

    func test_foreign_world_cannot_reuse_receipt_for_different_committed_state() throws {
        let count = 3
        let authoritativeJournal = JournalMock()
        let authoritativeWorld = try ChunkedTransactionWorld(count: count)
        let wanted = request(count: count, operation: 2, time: 100, id: "same-id")
        _ = try complete(authoritativeWorld, request: wanted, journal: authoritativeJournal, budget: 2)

        let foreignJournal = JournalMock()
        let foreignWorld = try ChunkedTransactionWorld(count: count)
        let other = request(count: count, operation: 40, time: 200, id: "another-id")
        _ = try complete(foreignWorld, request: other, journal: foreignJournal, budget: 2)
        XCTAssertNotEqual(try authoritativeWorld.inspect(), try foreignWorld.inspect())
        // Red-team: merely matching a receipt id and active count is insufficient.
        XCTAssertThrowsError(try foreignWorld.begin(wanted, journal: authoritativeJournal)) {
            XCTAssertEqual($0 as? MicroFailure, .requestConflict)
        }
    }

    func test_nonempty_pretransaction_baseline_recovery_fails_closed_without_checkpoint() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 4)
        try w.prepareTestPriorOperation(asset: 3, lastOperation: 7)
        let nonemptyBase = try w.inspect()
        try w.injectStageFailure(at: 2)
        try w.begin(request(count: 4, operation: 20), journal: j)
        _ = try w.tick(budget: 4, journal: j)
        XCTAssertThrowsError(try w.tick(budget: 4, journal: j)) {
            XCTAssertEqual($0 as? MicroFailure, .injectedFailure)
        }
        XCTAssertThrowsError(try ChunkedTransactionWorld.recover(
            count: 4, from: j, expectedBase: nonemptyBase)) {
            XCTAssertEqual($0 as? MicroFailure, .cannotRecover)
        }
    }

    func test_wrong_baseline_count_rejects_recovery_before_replay() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 4)
        let wrongBase = try ChunkedTransactionWorld(count: 5).inspect()
        _ = try complete(w, request: request(count: 4), journal: j, budget: 1)
        XCTAssertThrowsError(try ChunkedTransactionWorld.recover(
            count: 4, from: j, expectedBase: wrongBase)) {
            XCTAssertEqual($0 as? MicroFailure, .cannotRecover)
        }
    }

    func test_active_bulk_transaction_starves_regular_reads_until_final_publication() throws {
        // This is a NEGATIVE PRODUCT OBSERVATION, not an acceptable UI policy:
        // splitting the command into small calls still blocks business reads.
        let n = 4_096
        let w = try ChunkedTransactionWorld(count: n)
        let j = JournalMock()
        try w.begin(request(count: n), journal: j)
        var blockedReads = 0
        var calls = 0
        while w.phaseForDiagnostics != .idle {
            XCTAssertThrowsError(try w.inspect()) { error in
                XCTAssertEqual(error as? MicroFailure, .readDuringTransaction)
            }
            blockedReads += 1
            let tick = try w.tick(budget: 32, journal: j)
            XCTAssertLessThanOrEqual(tick.workItems, 32)
            calls += 1
        }
        XCTAssertEqual(calls, 2 * (n / 32) + 1)
        XCTAssertEqual(blockedReads, calls)
        XCTAssertEqual(try w.inspect().publishedEvents, n)
    }

    func test_cadence_calculation_is_not_latency_proof() {
        // Validation + staging needs 2N work units in this model. A 2,000-call
        // cadence therefore needs >=1,000 work units/call at 1M even before
        // journal publication, scheduler costs, writer, UI, payroll, or thermal.
        let count = 1_000_000
        let needed = 2 * count
        XCTAssertEqual((needed + 1999) / 2000, 1000)
        XCTAssertGreaterThan((needed + 999) / 1000, 1_999)
        // The first arithmetic floor is necessary but NOT sufficient because
        // validation and staging each round up to whole calls, and journal
        // publication consumes an extra call in this mock.
        func calls(_ budget: Int) -> Int { 2 * ((count + budget - 1) / budget) + 1 }
        XCTAssertEqual(calls(1_000), 2_001)
        XCTAssertEqual(calls(1_001), 2_001)
        XCTAssertEqual(calls(1_002), 1_999)
        XCTAssertEqual(calls(1_024), 1_955)
        XCTAssertGreaterThan(calls(1_001), 2_000)
        XCTAssertLessThanOrEqual(calls(1_002), 2_000)
    }
}
