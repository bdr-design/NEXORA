import XCTest
@testable import NEXORACore

final class AssetDomainTests: XCTestCase {
    func testCommitIsAllOrRejectForInvalidEntity() {
        let env = CoreBenchmarkEnvironment(capacity: 2)
        let ids = env.seedAssets(count: 2)
        let beforeA = env.assets.value(for: ids[0])!
        let beforeB = env.assets.value(for: ids[1])!
        let snapshot = env.assets.snapshot()
        let stale = EntityID(slot: ids[1].slot, generation: ids[1].generation &+ 1)

        let result = env.assets.commit(AssetTransactionPlan(
            revision: snapshot.revision,
            deltas: [
                AssetDelta(id: ids[0], valueChange: 10),
                AssetDelta(id: stale, valueChange: 10)
            ]
        ))

        XCTAssertEqual(result, .rejectedEntity(stale))
        XCTAssertEqual(env.assets.value(for: ids[0]), beforeA)
        XCTAssertEqual(env.assets.value(for: ids[1]), beforeB)
    }

    func testRevisionConflictRejectsWithoutMutation() {
        let env = CoreBenchmarkEnvironment(capacity: 1)
        let id = env.seedAssets(count: 1)[0]
        let snap = env.assets.snapshot()
        XCTAssertEqual(env.assets.commit(AssetTransactionPlan(revision: snap.revision, deltas: [AssetDelta(id: id, valueChange: 1)])), .committed(newRevision: snap.revision + 1, applied: 1))
        let value = env.assets.value(for: id)
        let staleResult = env.assets.commit(AssetTransactionPlan(revision: snap.revision, deltas: [AssetDelta(id: id, valueChange: 100)]))
        guard case .rejectedRevision = staleResult else { return XCTFail("Expected revision rejection") }
        XCTAssertEqual(env.assets.value(for: id), value)
    }
}
