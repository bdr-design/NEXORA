import XCTest
import NEXORADiagnostics

final class DiagnosticsTests: XCTestCase {
    func testRingBufferKeepsNewestRecordsInOrder() {
        let ring = TraceRingBuffer(capacity: 3)
        for id in 1...5 {
            ring.record(TraceRecord(
                traceID: UInt64(id), domain: .benchmark, operation: .benchmarkIteration,
                startedNanoseconds: 0, durationNanoseconds: 1
            ))
        }
        XCTAssertEqual(ring.snapshot().map(\.traceID), [3, 4, 5])
    }
}
