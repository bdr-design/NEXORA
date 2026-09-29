import XCTest
@testable import NEXORACore

final class ParallelComputeTests: XCTestCase {
    func testParallelComputeProducesDeterministicOrder() async {
        let env = CoreBenchmarkEnvironment(capacity: 10_000)
        _ = env.seedAssets(count: 10_000)
        let computer = ParallelAssetComputer(
            configuration: ComputeConfiguration(workerCount: 4),
            maximumReadCount: 1_000
        )

        var batch = AssetReadBatch(capacity: 1_000)
        env.assets.fillReadBatch(selectionStride: 10, into: &batch)
        let first = await computer.compute(batch: batch).deltas
        let second = await computer.compute(batch: batch).deltas
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 1_000)
        XCTAssertEqual(first.map(\.id), first.map(\.id).sorted())
    }
}
