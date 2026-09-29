import XCTest
@testable import NEXORACore

final class CorePerformanceTests: XCTestCase {
#if os(macOS) || os(iOS)
    func testTwentyThousandCoreTickAppleMetrics() {
        let env = CoreBenchmarkEnvironment(capacity: 20_000)
        _ = env.seedAssets(count: 20_000)
        let computer = ParallelAssetComputer(
            configuration: ComputeConfiguration(workerCount: 4),
            maximumReadCount: 2_000
        )
        var batch = AssetReadBatch(capacity: 2_000)

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let done = expectation(description: "tick")
            Task {
                env.assets.fillReadBatch(selectionStride: 10, into: &batch)
                let output = await computer.compute(batch: batch)
                let result = env.assets.commit(AssetTransactionPlan(revision: batch.revision, deltas: output.deltas))
                guard case .committed = result else {
                    XCTFail("Commit failed: \(result)")
                    done.fulfill()
                    return
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }
#endif
}
