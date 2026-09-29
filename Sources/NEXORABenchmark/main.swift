import Foundation
import NEXORACore
import NEXORADiagnostics

#if canImport(Darwin)
import Darwin
#endif
#if os(Linux)
import Glibc
#endif

struct Percentiles: Codable {
    let p50: Double
    let p95: Double
    let p99: Double
    let max: Double
}

struct BenchmarkRecord: Codable {
    let size: Int
    let selectedPerTick: Int
    let workers: Int
    let iterations: Int
    let warmup: Int
    let deltasPerTick: Int
    let gather: Percentiles
    let compute: Percentiles
    let merge: Percentiles
    let commit: Percentiles
    let endToEnd: Percentiles
    let rssBeforeBytes: UInt64?
    let rssAfterBytes: UInt64?
    let gatherRawNanoseconds: [UInt64]
    let computeRawNanoseconds: [UInt64]
    let mergeRawNanoseconds: [UInt64]
    let commitRawNanoseconds: [UInt64]
    let endToEndRawNanoseconds: [UInt64]
}

struct BenchmarkReport: Codable {
    let generatedAtUTC: String
    let operatingSystem: String
    let activeProcessorCount: Int
    let diagnosticsEnabled: Bool
    let records: [BenchmarkRecord]
}

@inline(__always)
func nsToMS(_ value: UInt64) -> Double { Double(value) / 1_000_000.0 }

func percentiles(_ samples: [UInt64]) -> Percentiles {
    let sorted = samples.sorted()
    func sample(_ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded(.down)))
        return nsToMS(sorted[index])
    }
    return Percentiles(p50: sample(0.50), p95: sample(0.95), p99: sample(0.99), max: nsToMS(sorted.last ?? 0))
}

func residentMemoryBytes() -> UInt64? {
#if os(Linux)
    guard let content = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
          let pagesText = content.split(separator: " ").dropFirst().first,
          let pages = UInt64(pagesText) else { return nil }
    return pages * UInt64(getpagesize())
#elseif canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
#else
    return nil
#endif
}

struct Arguments {
    var sizes = [1_000, 5_000, 20_000, 50_000, 100_000]
    var iterations = 500
    var warmup = 20
    var workers = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
    var selectionStride = 10
    var diagnosticsEnabled = true
    var jsonOutputPath: String?

    init() {
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--sizes":
                if let value = iterator.next() {
                    sizes = value.split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
                }
            case "--iterations":
                if let value = iterator.next(), let n = Int(value), n > 0 { iterations = n }
            case "--warmup":
                if let value = iterator.next(), let n = Int(value), n >= 0 { warmup = n }
            case "--workers":
                if let value = iterator.next(), let n = Int(value), n > 0 { workers = n }
            case "--selection-stride":
                if let value = iterator.next(), let n = Int(value), n > 0 { selectionStride = n }
            case "--diagnostics":
                if let value = iterator.next() { diagnosticsEnabled = value.lowercased() != "off" }
            case "--json":
                jsonOutputPath = iterator.next()
            default:
                break
            }
        }
    }
}

@main
struct NEXORABenchmarkMain {
    static func main() async throws {
        let args = Arguments()
        print("NEXORA Core Benchmark")
        print("workers=\(args.workers) selectionStride=\(args.selectionStride) iterations=\(args.iterations) warmup=\(args.warmup) diagnostics=\(args.diagnosticsEnabled ? "on" : "off")")
        var records: [BenchmarkRecord] = []
        records.reserveCapacity(args.sizes.count)

        for size in args.sizes {
            let ring = TraceRingBuffer(capacity: 16_384)
            let sink: any TraceSink = args.diagnosticsEnabled ? ring : NullTraceSink()
            let env = CoreBenchmarkEnvironment(capacity: size, traceSink: sink)
            _ = env.seedAssets(count: size)

            let selectedCapacity = max(1, (size + args.selectionStride - 1) / args.selectionStride)
            var batch = AssetReadBatch(capacity: selectedCapacity)
            let computer = ParallelAssetComputer(
                configuration: ComputeConfiguration(workerCount: args.workers),
                maximumReadCount: selectedCapacity,
                traceSink: sink
            )

            for _ in 0..<args.warmup {
                env.assets.fillReadBatch(selectionStride: args.selectionStride, into: &batch)
                let output = await computer.compute(batch: batch)
                _ = env.assets.commit(AssetTransactionPlan(revision: batch.revision, deltas: output.deltas))
            }

            var gatherSamples: [UInt64] = []
            var computeSamples: [UInt64] = []
            var mergeSamples: [UInt64] = []
            var commitSamples: [UInt64] = []
            var endToEndSamples: [UInt64] = []
            gatherSamples.reserveCapacity(args.iterations)
            computeSamples.reserveCapacity(args.iterations)
            mergeSamples.reserveCapacity(args.iterations)
            commitSamples.reserveCapacity(args.iterations)
            endToEndSamples.reserveCapacity(args.iterations)

            var generated = 0
            var selected = 0
            let rssBefore = residentMemoryBytes()

            for _ in 0..<args.iterations {
                let iterationStart = MonotonicClock.nowNanoseconds()

                let gatherStart = MonotonicClock.nowNanoseconds()
                env.assets.fillReadBatch(selectionStride: args.selectionStride, into: &batch)
                let gatherEnd = MonotonicClock.nowNanoseconds()
                selected = batch.count

                let output = await computer.compute(batch: batch)
                generated = output.deltas.count

                let commitStart = MonotonicClock.nowNanoseconds()
                let result = env.assets.commit(AssetTransactionPlan(revision: batch.revision, deltas: output.deltas))
                let commitEnd = MonotonicClock.nowNanoseconds()
                guard case .committed = result else {
                    fatalError("Benchmark commit failed: \(result)")
                }
                let iterationEnd = MonotonicClock.nowNanoseconds()

                gatherSamples.append(gatherEnd &- gatherStart)
                computeSamples.append(output.computeNanoseconds)
                mergeSamples.append(output.mergeNanoseconds)
                commitSamples.append(commitEnd &- commitStart)
                endToEndSamples.append(iterationEnd &- iterationStart)
            }
            let rssAfter = residentMemoryBytes()

            let g = percentiles(gatherSamples)
            let c = percentiles(computeSamples)
            let m = percentiles(mergeSamples)
            let k = percentiles(commitSamples)
            let e = percentiles(endToEndSamples)

            print("\nsize=\(size) selected/tick=\(selected) deltas/tick=\(generated)")
            print(String(format: "gather   p50=%7.3f p95=%7.3f p99=%7.3f max=%7.3f ms", g.p50, g.p95, g.p99, g.max))
            print(String(format: "compute  p50=%7.3f p95=%7.3f p99=%7.3f max=%7.3f ms", c.p50, c.p95, c.p99, c.max))
            print(String(format: "merge    p50=%7.3f p95=%7.3f p99=%7.3f max=%7.3f ms", m.p50, m.p95, m.p99, m.max))
            print(String(format: "commit   p50=%7.3f p95=%7.3f p99=%7.3f max=%7.3f ms", k.p50, k.p95, k.p99, k.max))
            print(String(format: "end2end  p50=%7.3f p95=%7.3f p99=%7.3f max=%7.3f ms", e.p50, e.p95, e.p99, e.max))
            if let before = rssBefore, let after = rssAfter {
                print(String(format: "rss before=%.2f MiB after=%.2f MiB delta=%+.2f MiB", Double(before)/1_048_576, Double(after)/1_048_576, Double(Int64(after)-Int64(before))/1_048_576))
            }
            print("trace_records=\(args.diagnosticsEnabled ? ring.snapshot().count : 0)")

            records.append(BenchmarkRecord(
                size: size,
                selectedPerTick: selected,
                workers: args.workers,
                iterations: args.iterations,
                warmup: args.warmup,
                deltasPerTick: generated,
                gather: g,
                compute: c,
                merge: m,
                commit: k,
                endToEnd: e,
                rssBeforeBytes: rssBefore,
                rssAfterBytes: rssAfter,
                gatherRawNanoseconds: gatherSamples,
                computeRawNanoseconds: computeSamples,
                mergeRawNanoseconds: mergeSamples,
                commitRawNanoseconds: commitSamples,
                endToEndRawNanoseconds: endToEndSamples
            ))
        }

        if let path = args.jsonOutputPath {
            let formatter = ISO8601DateFormatter()
            let report = BenchmarkReport(
                generatedAtUTC: formatter.string(from: Date()),
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
                diagnosticsEnabled: args.diagnosticsEnabled,
                records: records
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: path))
            print("json=\(path)")
        }
    }
}
