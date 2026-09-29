import XCTest
@testable import NEXORACore

final class NXR0003AdversarialComputeTests: XCTestCase {
    func testConcurrentComputeCallsOnSameComputerRemainIsolated() async {
        let count = 20_000
        let computer = ParallelAssetComputer(
            configuration: ComputeConfiguration(workerCount: 4),
            maximumReadCount: count
        )

        var batchA = AssetReadBatch(capacity: count)
        var batchB = AssetReadBatch(capacity: count)
        batchA.reset(revision: 1)
        batchB.reset(revision: 2)

        for slot in 0..<count {
            let id = EntityID(slot: UInt32(slot), generation: 0)
            batchA.append(id: id, value: 100, status: 0, nextEventTime: 0)
            batchB.append(id: id, value: 200, status: 0, nextEventTime: 0)
        }

        for _ in 0..<50 {
            async let a = computer.compute(batch: batchA)
            async let b = computer.compute(batch: batchB)
            let (left, right) = await (a, b)

            XCTAssertEqual(left.deltas.count, count)
            XCTAssertEqual(right.deltas.count, count)
            XCTAssertTrue(left.deltas.allSatisfy { $0.valueChange == 1.0 })
            XCTAssertTrue(right.deltas.allSatisfy { $0.valueChange == 2.0 })
        }
    }
}
