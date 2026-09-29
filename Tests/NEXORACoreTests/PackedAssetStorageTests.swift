import XCTest
@testable import NEXORACore

final class PackedAssetStorageTests: XCTestCase {
    func testSwapAndPopRepairsSparseDenseMapping() {
        var storage = PackedAssetStorage(capacity: 3)
        let a = EntityID(slot: 0, generation: 0)
        let b = EntityID(slot: 1, generation: 0)
        let c = EntityID(slot: 2, generation: 0)
        _ = storage.attach(id: a, initial: AssetInitialState(value: 10))
        _ = storage.attach(id: b, initial: AssetInitialState(value: 20))
        _ = storage.attach(id: c, initial: AssetInitialState(value: 30))

        XCTAssertTrue(storage.detach(id: b))
        XCTAssertNil(storage.resolve(b))
        XCTAssertNotNil(storage.resolve(a))
        XCTAssertNotNil(storage.resolve(c))
        XCTAssertEqual(storage.count, 2)
        XCTAssertTrue(storage.invariantHolds())
        XCTAssertEqual(storage.value(for: c), 30)
    }

    func testSlotCannotAttachDifferentGenerationWhileOccupied() {
        var storage = PackedAssetStorage(capacity: 1)
        let old = EntityID(slot: 0, generation: 0)
        let new = EntityID(slot: 0, generation: 1)
        XCTAssertEqual(storage.attach(id: old, initial: AssetInitialState(value: 1)), .attached(denseIndex: 0))
        XCTAssertEqual(storage.attach(id: new, initial: AssetInitialState(value: 2)), .slotOccupiedByDifferentGeneration)
    }
}
