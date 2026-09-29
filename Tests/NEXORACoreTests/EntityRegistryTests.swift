import XCTest
@testable import NEXORACore

final class EntityRegistryTests: XCTestCase {
    func testGenerationRejectsStaleHandleAfterRecycle() {
        let registry = EntityRegistry(capacity: 1)
        let first = registry.create()
        XCTAssertTrue(registry.isAlive(first))
        XCTAssertEqual(registry.destroy(first), .destroyed)
        XCTAssertFalse(registry.isAlive(first))

        let second = registry.create()
        XCTAssertEqual(second.slot, first.slot)
        XCTAssertNotEqual(second.generation, first.generation)
        XCTAssertFalse(registry.isAlive(first))
        XCTAssertTrue(registry.isAlive(second))
    }

    func testCreatesOneHundredThousandUniqueLiveHandles() {
        let registry = EntityRegistry(capacity: 100_000)
        var ids = Set<EntityID>()
        ids.reserveCapacity(100_000)
        for _ in 0..<100_000 { ids.insert(registry.create()) }
        XCTAssertEqual(ids.count, 100_000)
        XCTAssertEqual(registry.count, 100_000)
    }
}
