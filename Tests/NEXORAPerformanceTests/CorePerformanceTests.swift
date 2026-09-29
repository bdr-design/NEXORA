import XCTest
@testable import NEXORACore

final class CorePerformanceTests: XCTestCase {
#if os(macOS) || os(iOS)
    func testTwentyThousandCoreTickAppleMetrics() {
        let env = CoreBenchmarkEnvironment(capacity: 20_000)
        _ = env.seedAssets(count: 20_000)
        let computer = ParallelAssetComputer(
            configuration: ComputeConfiguration(workerCount: 4, activeStride: 10),
            maximumEntityCount: 20_000
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let done = expectation(description: "tick")
            Task {
                var snapshot: AssetReadSnapshot? = env.assets.snapshot()
                let revision = snapshot!.revision
                let output = await computer.compute(snapshot: snapshot!)
                snapshot = nil
                let result = env.assets.commit(AssetTransactionPlan(revision: revision, deltas: output.deltas))
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
