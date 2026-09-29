import XCTest
@testable import NEXORACore

final class ParallelComputeTests: XCTestCase {
    func testParallelComputeProducesDeterministicOrder() async {
        let env = CoreBenchmarkEnvironment(capacity: 10_000)
        _ = env.seedAssets(count: 10_000)
        let computer = ParallelAssetComputer(
            configuration: ComputeConfiguration(workerCount: 4, activeStride: 10),
            maximumEntityCount: 10_000
        )

        let snapshot = env.assets.snapshot()
        let first = await computer.compute(snapshot: snapshot).deltas
        let second = await computer.compute(snapshot: snapshot).deltas
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 1_000)
        XCTAssertEqual(first.map(\.id), first.map(\.id).sorted())
    }
}
