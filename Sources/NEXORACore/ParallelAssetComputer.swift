import Synchronization
import NEXORADiagnostics

public struct ComputeConfiguration: Sendable {
    public let workerCount: Int
    public let activeStride: Int

    public init(workerCount: Int, activeStride: Int = 10) {
        precondition(workerCount > 0)
        precondition(activeStride > 0)
        self.workerCount = workerCount
        self.activeStride = activeStride
    }
}

private final class WorkerDeltaBuffer: Sendable {
    private let buffer: Mutex<[AssetDelta]>

    init(capacity: Int) {
        var array: [AssetDelta] = []
        array.reserveCapacity(capacity)
        buffer = Mutex(array)
    }

    func fill(snapshot: AssetReadSnapshot, range: Range<Int>, stride: Int) {
        buffer.withLock { output in
            output.removeAll(keepingCapacity: true)
            guard !range.isEmpty else { return }
            for denseIndex in range where denseIndex % stride == 0 {
                let value = snapshot.values[denseIndex]
                output.append(AssetDelta(id: snapshot.ids[denseIndex], valueChange: value * 0.01))
            }
        }
    }

    func append(to output: inout [AssetDelta]) {
        buffer.withLock { source in
            output.append(contentsOf: source)
        }
    }

    var count: Int { buffer.withLock { $0.count } }
}

public final class ParallelAssetComputer: Sendable {
    private let configuration: ComputeConfiguration
    private let workerBuffers: [WorkerDeltaBuffer]
    private let mergedBuffer: Mutex<[AssetDelta]>
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        configuration: ComputeConfiguration,
        maximumEntityCount: Int,
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        self.configuration = configuration
        let perWorker = max(1, (maximumEntityCount / configuration.activeStride) / configuration.workerCount + 16)
        self.workerBuffers = (0..<configuration.workerCount).map { _ in WorkerDeltaBuffer(capacity: perWorker) }
        var merged: [AssetDelta] = []
        merged.reserveCapacity(maximumEntityCount / configuration.activeStride + configuration.workerCount)
        self.mergedBuffer = Mutex(merged)
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    public func compute(snapshot: AssetReadSnapshot) async -> AssetComputeOutput {
        let computeStart = MonotonicClock.nowNanoseconds()
        let total = snapshot.count
        guard total > 0 else { return AssetComputeOutput(deltas: [], computeNanoseconds: 0, mergeNanoseconds: 0, workerCount: 0) }
        let workers = min(configuration.workerCount, total)
        let chunkSize = (total + workers - 1) / workers

        await withTaskGroup(of: Int.self) { group in
            for workerIndex in 0..<workers {
                let start = workerIndex * chunkSize
                let end = min(start + chunkSize, total)
                let worker = workerBuffers[workerIndex]
                let stride = configuration.activeStride
                group.addTask {
                    worker.fill(snapshot: snapshot, range: start..<end, stride: stride)
                    return workerIndex
                }
            }
            for await _ in group {}
        }
        let computeEnd = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .compute,
            operation: .compute,
            startedNanoseconds: computeStart,
            durationNanoseconds: computeEnd &- computeStart,
            workCount: UInt32(clamping: total),
            revision: snapshot.revision
        ))

        let mergeStart = MonotonicClock.nowNanoseconds()
        let merged = mergedBuffer.withLock { output -> [AssetDelta] in
            output.removeAll(keepingCapacity: true)
            for workerIndex in 0..<workers {
                workerBuffers[workerIndex].append(to: &output)
            }
            return output
        }
        let mergeEnd = MonotonicClock.nowNanoseconds()
        traceSink.record(TraceRecord(
            traceID: traceIDs.next(),
            domain: .merge,
            operation: .merge,
            startedNanoseconds: mergeStart,
            durationNanoseconds: mergeEnd &- mergeStart,
            workCount: UInt32(clamping: merged.count),
            revision: snapshot.revision
        ))
        return AssetComputeOutput(
            deltas: merged,
            computeNanoseconds: computeEnd &- computeStart,
            mergeNanoseconds: mergeEnd &- mergeStart,
            workerCount: workers
        )
    }
}
