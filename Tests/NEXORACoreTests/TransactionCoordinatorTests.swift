import XCTest
@testable import NEXORACore

final class TransactionCoordinatorTests: XCTestCase {
    func testPrepareFailureLeavesEarlierDomainUntouched() {
        let gate = TransactionGate()
        let coordinator = TransactionCoordinator(gate: gate)
        let left = AssetDomain(capacity: 1, gate: gate)
        let right = AssetDomain(capacity: 1, gate: gate)
        let leftID = EntityID(slot: 0, generation: 0)
        let rightID = EntityID(slot: 1, generation: 0)
        XCTAssertEqual(left.attach(id: leftID, initial: AssetInitialState(value: 10)), .attached(denseIndex: 0))
        XCTAssertEqual(right.attach(id: rightID, initial: AssetInitialState(value: 20)), .attached(denseIndex: 0))

        let leftRevision = left.revision
        let rightRevision = right.revision
        let staleRight = EntityID(slot: rightID.slot, generation: rightID.generation &+ 1)

        let result = coordinator.commit([
            left.transactionStep(for: AssetTransactionPlan(
                revision: leftRevision,
                deltas: [AssetDelta(id: leftID, valueChange: 5)]
            )),
            right.transactionStep(for: AssetTransactionPlan(
                revision: rightRevision,
                deltas: [AssetDelta(id: staleRight, valueChange: 5)]
            ))
        ])

        XCTAssertEqual(result, .rejected(stepIndex: 1, reason: .rejectedEntity))
        XCTAssertEqual(left.value(for: leftID), 10)
        XCTAssertEqual(right.value(for: rightID), 20)
        XCTAssertEqual(left.revision, leftRevision)
        XCTAssertEqual(right.revision, rightRevision)
    }

    func testSuccessfulCoordinatedCommitUpdatesBothDomains() {
        let gate = TransactionGate()
        let coordinator = TransactionCoordinator(gate: gate)
        let left = AssetDomain(capacity: 1, gate: gate)
        let right = AssetDomain(capacity: 1, gate: gate)
        let leftID = EntityID(slot: 0, generation: 0)
        let rightID = EntityID(slot: 1, generation: 0)
        _ = left.attach(id: leftID, initial: AssetInitialState(value: 10))
        _ = right.attach(id: rightID, initial: AssetInitialState(value: 20))

        let result = coordinator.commit([
            left.transactionStep(for: AssetTransactionPlan(
                revision: left.revision,
                deltas: [AssetDelta(id: leftID, valueChange: 5)]
            )),
            right.transactionStep(for: AssetTransactionPlan(
                revision: right.revision,
                deltas: [AssetDelta(id: rightID, valueChange: -5)]
            ))
        ])

        XCTAssertEqual(result, .committed(stepCount: 2))
        XCTAssertEqual(left.value(for: leftID), 15)
        XCTAssertEqual(right.value(for: rightID), 15)
    }

    func testDuplicateDomainStepIsRejectedBeforeMutation() {
        let gate = TransactionGate()
        let coordinator = TransactionCoordinator(gate: gate)
        let domain = AssetDomain(capacity: 1, gate: gate)
        let id = EntityID(slot: 0, generation: 0)
        _ = domain.attach(id: id, initial: AssetInitialState(value: 10))
        let revision = domain.revision
        let step = domain.transactionStep(for: AssetTransactionPlan(
            revision: revision,
            deltas: [AssetDelta(id: id, valueChange: 1)]
        ))

        XCTAssertEqual(coordinator.commit([step, step]), .rejectedDuplicateParticipant(stepIndex: 1))
        XCTAssertEqual(domain.value(for: id), 10)
        XCTAssertEqual(domain.revision, revision)
    }
}
