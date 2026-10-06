#if STAGE_C && EPOCH_PAGES
import Foundation
import ProbePlatform
import Synchronization

struct FrozenStageCSnapshot: Sendable {
    enum Layout: Sendable {
        case s(assets: FrozenEpochBuffer<UInt64>, nodes: FrozenEpochBuffer<UInt64>, groups: FrozenEpochBuffer<Int64>)
        case h(hot: FrozenEpochBuffer<HotAsset>, cold: FrozenEpochBuffer<UInt64>,
               nodes: FrozenEpochBuffer<EventNode>, groups: FrozenEpochBuffer<Int64>)
    }
    let epoch: UInt32
    let control: [UInt8]
    let layout: Layout

    var expectedCounts: [UInt32] {
        switch layout {
        case .s(let a, let n, let g): return [1, UInt32(a.pageCount), UInt32(n.pageCount), UInt32(g.pageCount)]
        case .h(let a, _, let n, let g): return [1, UInt32(a.pageCount), UInt32(n.pageCount), UInt32(g.pageCount)]
        }
    }
    private func append<T: BitwiseCopyable & Sendable>(_ frozen: FrozenEpochBuffer<T>, page: Int, payloadBytes: Int, into bytes: inout [UInt8]) {
        let values = frozen.page(page)
        let padding = values.count * MemoryLayout<T>.stride - payloadBytes
        precondition(padding >= 0 && padding < 8)
        Snapshot.append(values, 0..<values.count, into: &bytes)
        if padding > 0 { bytes.removeLast(padding) }
    }
    func fillRecord(kind: UInt16, index: Int, into bytes: inout [UInt8]) {
        bytes.removeAll(keepingCapacity: true)
        if kind == 0 { precondition(index == 0); bytes.append(contentsOf: control); return }
        let elements: Int, payloadBytes: Int
        switch layout {
        case .s(let a, let n, let g):
            elements = kind == 1 ? a.elements(in: index) : kind == 2 ? n.elements(in: index) : g.elements(in: index)
            payloadBytes = elements * (kind == 1 ? 65 : kind == 2 ? 30 : 8)
        case .h(let a, _, let n, let g):
            elements = kind == 1 ? a.elements(in: index) : kind == 2 ? n.elements(in: index) : g.elements(in: index)
            payloadBytes = elements * (kind == 1 ? 68 : kind == 2 ? 32 : 8)
        }
        precondition((1...3).contains(kind) && elements > 0)
        Snapshot.appendLE(kind, into: &bytes); Snapshot.appendLE(UInt16(0), into: &bytes)
        Snapshot.appendLE(UInt32(index), into: &bytes); Snapshot.appendLE(UInt32(elements), into: &bytes)
        Snapshot.appendLE(UInt32(payloadBytes), into: &bytes)
        switch layout {
        case .s(let a, let n, let g):
            if kind == 1 { append(a, page: index, payloadBytes: payloadBytes, into: &bytes) }
            else if kind == 2 { append(n, page: index, payloadBytes: payloadBytes, into: &bytes) }
            else { append(g, page: index, payloadBytes: payloadBytes, into: &bytes) }
        case .h(let a, let c, let n, let g):
            if kind == 1 {
                append(a, page: index, payloadBytes: elements * 48, into: &bytes)
                append(c, page: index, payloadBytes: elements * 20, into: &bytes)
            } else if kind == 2 { append(n, page: index, payloadBytes: payloadBytes, into: &bytes) }
            else { append(g, page: index, payloadBytes: payloadBytes, into: &bytes) }
        }
        precondition(bytes.count == 16 + payloadBytes)
    }
}

private struct PendingEpochState: Sendable {
    var view: FrozenStageCSnapshot? = nil
    var published = false
    var cancelled = false
}

// One handoff per whole save, not one lock/message per entity or page. The
// worker owns its value after take; completion is published only after release.
final class PendingEpochSnapshot: Sendable {
    private let state = Mutex(PendingEpochState())
    private let ready = DispatchSemaphore(value: 0)
    func publish(_ view: FrozenStageCSnapshot) {
        state.withLock { value in
            precondition(!value.published && !value.cancelled)
            value.view = view; value.published = true
        }
        // Historical K10 token now targets the fully retained immutable epoch
        // and its prepared spare buffers. Queue bytes are truthfully zero.
        nx_kill_point("c.k10.peak_queue")
        ready.signal()
    }
    func cancelIfUnused() {
        let signal = state.withLock { value in
            guard !value.published && !value.cancelled else { return false }
            value.cancelled = true; return true
        }
        if signal { ready.signal() }
    }
    func take() -> FrozenStageCSnapshot? {
        ready.wait()
        return state.withLock { value in
            let result = value.view; value.view = nil; return result
        }
    }
}

extension StageCSnapshotWriter {
    // Keep frozen roots in a separate non-inlined frame. That frame, including
    // all temporary root values, ends before the worker publishes completion.
    @inline(never) static func consumePending(_ pending: PendingEpochSnapshot, directory: String,
                                              expectedCounts: [UInt32]) throws -> (StageCSnapshotFileResult, UInt64)? {
        let start = nx_now()
        guard let view = pending.take() else { return nil }
        let waitNS = nx_now() - start
        return (try runFrozen(view, directory: directory, expectedCounts: expectedCounts), waitNS)
    }

    static func runFrozen(_ view: FrozenStageCSnapshot, directory: String,
                          expectedCounts: [UInt32]) throws -> StageCSnapshotFileResult {
        guard expectedCounts == view.expectedCounts else { throw ProbeError.invalid("frozen snapshot counts") }
        let start = nx_now()
        let tmp = directory + "/snapshot-\(view.epoch).tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: nil) else { throw ProbeError.invalid("frozen snapshot tmp create") }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmp))
        defer { try? handle.close() }
        let prefix = Snapshot.filePrefix()
        try handle.write(contentsOf: prefix)
        var bytesWritten = UInt64(prefix.count)
        let chunks = expectedCounts.reduce(0) { $0 + Int($1) }
        var canonical = Data(capacity: chunks * 38)
        var scratch: [UInt8] = []
        scratch.reserveCapacity(32_768)
        var processNS: UInt64 = 0
        for kind in UInt16(0)...UInt16(3) {
            for index in 0..<Int(expectedCounts[Int(kind)]) {
                let recordStart = nx_now()
                view.fillRecord(kind: kind, index: index, into: &scratch)
                let parsed = try parseRecord(scratch)
                guard parsed.0 == StageCRecordKey(kind: kind, index: UInt32(index)) else { throw ProbeError.corruption("frozen snapshot record key") }
                if kind > 0 {
                    let split = max(16, scratch.count / 2)
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<split)
                    nx_kill_point("c.k3.mid_record")
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: split..<scratch.count)
                } else {
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<scratch.count)
                }
                try handle.write(contentsOf: parsed.2)
                Snapshot.appendLE(kind, into: &canonical); Snapshot.appendLE(UInt32(index), into: &canonical)
                canonical.append(parsed.2)
                bytesWritten += UInt64(scratch.count + parsed.2.count)
                processNS += nx_now() - recordStart
            }
        }
        return try finalize(handle: handle, directory: directory, epoch: view.epoch,
                            counts: expectedCounts, canonical: canonical, bytesWritten: bytesWritten,
                            start: start, queueWaitNS: 0, recordProcessWriteNS: processNS, peakQueuedBytes: 0)
    }
}
#endif
