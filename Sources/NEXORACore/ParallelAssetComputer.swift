import Synchronization
import NEXORADiagnostics

public struct ComputeConfiguration: Sendable {
    public let workerCount: Int

    public init(workerCount: Int) {
        precondition(workerCount > 0)
        self.workerCount = workerCount
    }
}

private final class WorkerDeltaBuffer: Sendable {
    private let buffer: Mutex<[AssetDelta]>

    init(capacity: Int) {
        var array: [AssetDelta] = []
        array.reserveCapacity(capacity)
        buffer = Mutex(array)
    }

    func fill(batch: AssetReadBatch, range: Range<Int>) {
        buffer.withLock { output in
            output.removeAll(keepingCapacity: true)
            guard !range.isEmpty else { return }
            for index in range {
                output.append(AssetDelta(id: batch.ids[index], valueChange: batch.values[index] * 0.01))
            }
        }
    }

    func append(to output: inout [AssetDelta]) {
        buffer.withLock { source in
            output.append(contentsOf: source)
        }
    }
}

public final class ParallelAssetComputer: Sendable {
    private let configuration: ComputeConfiguration
    private let workerBuffers: [WorkerDeltaBuffer]
    private let mergedBuffer: Mutex<[AssetDelta]>
    private let traceSink: any TraceSink
    private let traceIDs: TraceIDSource

    public init(
        configuration: ComputeConfiguration,
        maximumReadCount: Int,
        traceSink: any TraceSink = NullTraceSink(),
        traceIDs: TraceIDSource = TraceIDSource()
    ) {
        precondition(maximumReadCount >= 0)
        self.configuration = configuration
        let perWorker = max(1, maximumReadCount / configuration.workerCount + 16)
        self.workerBuffers = (0..<configuration.workerCount).map { _ in WorkerDeltaBuffer(capacity: perWorker) }
        var merged: [AssetDelta] = []
        merged.reserveCapacity(maximumReadCount + configuration.workerCount)
        self.mergedBuffer = Mutex(merged)
        self.traceSink = traceSink
        self.traceIDs = traceIDs
    }

    public func compute(batch: AssetReadBatch) async -> AssetComputeOutput {
        let computeStart = MonotonicClock.nowNanoseconds()
        let total = batch.count
        guard total > 0 else {
            return AssetComputeOutput(deltas: [], computeNanoseconds: 0, mergeNanoseconds: 0, workerCount: 0)
        }
        let workers = min(configuration.workerCount, total)
        let chunkSize = (total + workers - 1) / workers

        await withTaskGroup(of: Int.self) { group in
            for workerIndex in 0..<workers {
                let start = workerIndex * chunkSize
                let end = min(start + chunkSize, total)
                let worker = workerBuffers[workerIndex]
                group.addTask {
                    worker.fill(batch: batch, range: start..<end)
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
            revision: batch.revision
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
            revision: batch.revision
        ))

        return AssetComputeOutput(
            deltas: merged,
            computeNanoseconds: computeEnd &- computeStart,
            mergeNanoseconds: mergeEnd &- mergeStart,
            workerCount: workers
        )
    }
}
