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
        XCTAssertEqual(try ChunkedTransactionWorld.recover(count: 100, from: j).inspect(), baseline)
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
        XCTAssertEqual(try ChunkedTransactionWorld.recover(count: 257, from: j).inspect(), baseline)
    }

    func test_durable_tip_before_ack_requires_query_and_recovery() throws {
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: 257)
        let req = request(count: 257)
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
        let fresh = try ChunkedTransactionWorld.recover(count: 257, from: j)
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
            let outcome = try complete(world, request: request(count: 4096), journal: j, budget: budget)
            XCTAssertEqual(outcome.1, 8192)
            let actual = try world.inspect()
            XCTAssertEqual(actual, try ChunkedTransactionWorld.recover(count: 4096, from: j).inspect())
            if let expected { XCTAssertEqual(actual, expected) }
            expected = actual
        }
    }

    func test_bounded_hundred_thousand_fixture_not_device_benchmark() throws {
        let n = 100_000
        let j = JournalMock(), w = try ChunkedTransactionWorld(count: n)
        let (calls, units) = try complete(w, request: request(count: n), journal: j, budget: 2_048)
        XCTAssertEqual(units, 2 * n)
        XCTAssertEqual(calls, 2 * ((n + 2047)/2048) + 1)
        XCTAssertEqual(try w.inspect(), try ChunkedTransactionWorld.recover(count: n, from: j).inspect())
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

    func test_cadence_calculation_is_not_latency_proof() {
        // Validation + staging needs 2N work units in this model. A 2,000-call
        // cadence therefore needs >=1,000 work units/call at 1M even before
        // journal publication, scheduler costs, writer, UI, payroll, or thermal.
        let count = 1_000_000
        let needed = 2 * count
        XCTAssertEqual((needed + 1999) / 2000, 1000)
        XCTAssertGreaterThan((needed + 999) / 1000, 1_999)
    }
}
