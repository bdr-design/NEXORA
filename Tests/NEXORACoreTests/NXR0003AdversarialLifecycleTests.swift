import XCTest
@testable import NEXORACore

final class NXR0003AdversarialLifecycleTests: XCTestCase {
    func testDestroyedGlobalEntityCannotStillMutateDomainState() {
        let env = CoreBenchmarkEnvironment(capacity: 1)
        let id = env.seedAssets(count: 1)[0]
        XCTAssertEqual(env.registry.destroy(id), .destroyed)
        XCTAssertFalse(env.registry.isAlive(id))

        let revision = env.assets.revision
        let result = env.assets.commit(AssetTransactionPlan(
            revision: revision,
            deltas: [AssetDelta(id: id, valueChange: 1)]
        ))

        XCTAssertEqual(
            result,
            .rejectedEntity(id),
            "A globally dead EntityID must not remain writable in a domain."
        )
    }

    func testDomainCannotAttachNeverCreatedEntityHandle() {
        let env = CoreBenchmarkEnvironment(capacity: 1)
        let forged = EntityID(slot: 999, generation: 0)
        XCTAssertFalse(env.registry.isAlive(forged))

        let result = env.assets.attach(
            id: forged,
            initial: AssetInitialState(value: 100)
        )

        if case .attached = result {
            XCTFail("AssetDomain accepted an EntityID that the global registry never created.")
        }
    }
}
