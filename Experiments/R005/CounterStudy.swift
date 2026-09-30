// Injected into a disposable check executable. No production business changes.
import NXRProbePlatform

struct V4Value: Codable {
    let status: String
    let value: UInt64?
    let reason: String
}
func v4Value(_ raw: UInt64, _ status: Int32) -> V4Value {
    if status == 1 { return V4Value(status: "unsupported", value: nil, reason: "platform") }
    if status != 0 { return V4Value(status: "readFailure", value: nil, reason: "syscall") }
    if raw == 0 { return V4Value(status: "unsupported", value: nil,
        reason: "zero-reading-policy; not proof of unavailable hardware") }
    return V4Value(status: "ok", value: raw, reason: "observed-positive")
}
struct V4Snapshot: Codable {
    let beginNS: UInt64
    let endNS: UInt64
    let error: Int32?
    let instructions: V4Value
    let cycles: V4Value
    let runnableRaw: V4Value
    init(_ raw: NXRUsage) {
        beginNS = raw.begin_ns; endNS = raw.end_ns
        error = raw.status == 2 ? raw.error : nil
        instructions = v4Value(raw.instructions, raw.status)
        cycles = v4Value(raw.cycles, raw.status)
        runnableRaw = v4Value(raw.runnable_raw, raw.status)
    }
}
struct V4Pair: Codable { let before: V4Snapshot; let after: V4Snapshot }
final class V4Capture {
    private var before: NXRUsage?
    private var pairs: [V4Pair?]
    private var count = 0
    init(capacity: Int) { pairs = Array(repeating: nil, count: capacity) }
    func begin() { precondition(before == nil); before = nxr_usage() }
    func end() {
        let after = nxr_usage()
        precondition(count < pairs.count)
        pairs[count] = V4Pair(before: V4Snapshot(before!), after: V4Snapshot(after))
        count += 1; before = nil
    }
    func export() -> [V4Pair] {
        precondition(count == pairs.count && before == nil)
        return pairs.map { $0! }
    }
}
struct StudyMetadata: Encodable {
    let kind = "metadata"
    let schema = "NXR-R004-V4-1"
    let sourceCommit: String
    let transformedSourceSHA256: String
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let processID = ProcessInfo.processInfo.processIdentifier
    let run: Int
    let repetitions: Int
    let sizes = [20_000, 50_000, 100_000]
    let warmups = 3
    let modes = ["control", "v4"]
    let scope = "process-wide endpoints enclose batch; diagnostic syscall cost included in outer CPU interval"
    let runnableUnit = "raw kernel value; no conversion or waiting-time interpretation in this experiment"
    let zeroPolicy = "unsupported/null with zero-reading reason, not hardware attestation"
}
struct StudySample: Encodable {
    let kind = "sample"
    let size: Int
    let run: Int
    let sample: Int
    let warmup: Bool
    let mode: String
    let fixture: DiagnosticResult
    let v4: [V4Pair]
}
struct EventStudy: Encodable {
    let kind = "events"
    let sourceCommit: String
    let transformedSourceSHA256: String
    let size: Int
    let sample: Int
    let fixture: DiagnosticResult
    let eventStartNS: [UInt64]
    let allocationNS: [UInt64]
    let interpretation = "one start timestamp/event; last event duration not independently timed; all allocation instrumentation outside production source"
}
enum ExtraStudy {
    static func result(_ r: MeasuredFixture, count: Int, sample: Int, run: Int, position: Int) -> DiagnosticResult {
        DiagnosticResult(aircraft: count, sample: sample, warmup: sample <= 3,
            mode: "counters", runID: run, executionOrder: position, aggregate: r.aggregate,
            bufferPreparationNS: r.bufferPreparationNS, seedAndHandlePreparationNS: r.seedAndHandlePreparationNS,
            finalAuditNS: r.finalAuditNS, explicitWorldReleaseNS: r.explicitWorldReleaseNS,
            workloadNS: r.workloadNS, phases: r.phases, records: r.records)
    }
    static func run(_ args: [String]) throws {
        guard args.count == 5, let run = Int(args[2]), (1...3).contains(run),
            let repetitions = Int(args[3]), (1...30).contains(repetitions),
            args[4].utf8.count == 40,
            args[4].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let transformedHash = ProcessInfo.processInfo.environment["NXR_GENERATED_SHA256"], transformedHash.count == 64
        else { throw FixtureFailure.arguments }
        let writer = try DiagnosticWriter(path: args[1])
        do {
            try writer.write(StudyMetadata(sourceCommit: args[4], transformedSourceSHA256: transformedHash,
                run: run, repetitions: repetitions))
            for mode in [ProbeMode.wall, .counters] { try writer.write(calibrate(mode, iterations: 2000)) }
            // Empty V4 brackets preserve observer overhead separately from business timing.
            let calibration = V4Capture(capacity: 2000)
            for _ in 0..<2000 { calibration.begin(); calibration.end() }
            struct V4Calibration: Encodable { let kind = "v4Calibration"; let records: [V4Pair] }
            try writer.write(V4Calibration(records: calibration.export()))
            for n in [20_000, 50_000, 100_000] {
                for s in 1...(3 + repetitions) {
                    let order = (s + run) % 2 == 0 ? [false,true] : [true,false]
                    var previous: FinancialSample?
                    for (position, enabled) in order.enumerated() {
                        let capture = enabled ? V4Capture(capacity: ((n + 255) / 256) * 3) : nil
                        let r = try measuredFixture(n, sampleIndex: s, mode: .counters, v4: capture)
                        if let previous { guard sameEconomics(previous,r.aggregate) else { throw FixtureFailure.correctness } }
                        previous = r.aggregate
                        try writer.write(StudySample(size: n, run: run, sample: s, warmup: s <= 3,
                            mode: enabled ? "v4" : "control", fixture: result(r,count:n,sample:s,run:run,position:position),
                            v4: capture?.export() ?? []))
                    }
                }
            }
            try writer.write(["kind":"complete", "status":"success"])
            try writer.close()
        } catch {
            try? writer.write(["kind":"failure", "error":String(describing:error)])
            try? writer.close(); throw error
        }
    }
    static func events(_ args: [String]) throws {
        guard args.count == 3, args[2].utf8.count == 40,
            args[2].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let generated = ProcessInfo.processInfo.environment["NXR_GENERATED_SHA256"], generated.count == 64
        else { throw FixtureFailure.arguments }
        let writer = try DiagnosticWriter(path: args[1])
        do {
            for n in [20_000,50_000,100_000] {
                for s in 1...3 {
                    let capture = NXRAdvanceCapture(capacity: n)
                    let r = try measuredFixture(n,sampleIndex:s,mode:.counters,eventCapture:capture)
                    guard capture.written == n, capture.batches == (n+255)/256 else { throw FixtureFailure.correctness }
                    try writer.write(EventStudy(sourceCommit:args[2],transformedSourceSHA256:generated,size:n,sample:s,
                        fixture: result(r,count:n,sample:s,run:1,position:0),
                        eventStartNS:capture.exportedEvents(),allocationNS:capture.exportedAllocations()))
                }
            }
            try writer.write(["kind":"complete","status":"success"]); try writer.close()
        } catch { try? writer.write(["kind":"failure","error":String(describing:error)]); try? writer.close(); throw error }
    }
    static func selftest() throws {
        for n in [64,255,256,257,1_000,5_000,20_000,50_000,100_000] {
            let a = try measuredFixture(n,sampleIndex:1,mode:.counters,captureTruth:true)
            let v = V4Capture(capacity: ((n+255)/256)*3)
            let e = NXRAdvanceCapture(capacity:n)
            let b = try measuredFixture(n,sampleIndex:1,mode:.counters,captureTruth:true,v4:v,eventCapture:e)
            guard a.truth == b.truth, sameEconomics(a.aggregate,b.aggregate), e.written == n,
                  e.batches == (n+255)/256, v.export().count == ((n+255)/256)*3
            else { throw FixtureFailure.correctness }
            let times=e.exportedEvents()
            guard zip(times,times.dropFirst()).allSatisfy({ $0 <= $1 }) else { throw FixtureFailure.correctness }
            print("PASS additional V4/event instrumentation transcript: \(n)")
        }
        guard v4Value(0,0).value == nil, v4Value(1,0).value == 1,
              v4Value(1,2).value == nil, v4Value(1,1).value == nil else { throw FixtureFailure.correctness }
        print("PASS extra measurement selftest; no production or device performance acceptance")
    }
}
