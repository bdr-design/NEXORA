import Foundation
import NexoraIdentity
import NexoraObservability

struct Sample: Codable {
    let createNanoseconds: UInt64
    let validateNanoseconds: UInt64
    let destroyNanoseconds: UInt64
}
struct ScaleResult: Codable {
    let identities: Int
    let samples: [Sample]
}
struct Report: Codable {
    let update: String
    let kind: String
    let operatingSystem: String
    let handleStrideBytes: Int
    let measuredIterations: Int
    let warmupIterations: Int
    let results: [ScaleResult]
    let limitations: [String]
}

enum ProbeFailure: Error { case invalidArguments, invariant, missingHandle, staleAccepted }

func ns(_ duration: Duration) -> UInt64 {
    let parts = duration.components
    return UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
}

func runScale(_ count: Int) throws -> Sample {
    var space = try EntitySpace(capacity: count)
    var timeline = try Timeline(capacity: 3)
    var handles: [EntityHandle] = []
    handles.reserveCapacity(count)
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<count { handles.append(try space.create()) }
    let created = clock.now
    for handle in handles {
        guard space.contains(handle) else { throw ProbeFailure.missingHandle }
    }
    let validated = clock.now
    for handle in handles { try space.destroy(handle) }
    let destroyed = clock.now
    // Correctness checks and logging are deliberately outside timed phases.
    for handle in handles {
        guard !space.contains(handle) else { throw ProbeFailure.staleAccepted }
    }
    guard space.liveCount == 0, space.checkInvariants() else { throw ProbeFailure.invariant }
    let result = Sample(createNanoseconds: ns(start.duration(to: created)),
                        validateNanoseconds: ns(created.duration(to: validated)),
                        destroyNanoseconds: ns(validated.duration(to: destroyed)))
    try timeline.append(TraceEvent(sequence: 1, stage: .creation,
                                  durationNanoseconds: result.createNanoseconds, itemCount: UInt32(count)))
    try timeline.append(TraceEvent(sequence: 2, parentSequence: 1, stage: .verification,
                                  durationNanoseconds: result.validateNanoseconds, itemCount: UInt32(count)))
    try timeline.append(TraceEvent(sequence: 3, parentSequence: 2, stage: .destruction,
                                  durationNanoseconds: result.destroyNanoseconds, itemCount: UInt32(count)))
    guard timeline.export().count == 3 else { throw ProbeFailure.invariant }
    return result
}

@main enum Check {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.isEmpty || (args.count == 2 && args[0] == "--json") else {
            throw ProbeFailure.invalidArguments
        }
        let iterations = 30
        var scales: [ScaleResult] = []
        for size in [1_000, 5_000, 20_000, 50_000, 100_000] {
            for _ in 0..<3 { _ = try runScale(size) }
            var samples: [Sample] = []
            for _ in 0..<iterations { samples.append(try runScale(size)) }
            scales.append(ScaleResult(identities: size, samples: samples))
            print("Identity lifecycle verified: \(size) handles, \(iterations) measured repetitions")
        }
        let report = Report(update: "NXR-R001", kind: "identity-lifecycle-smoke-not-gameplay",
                            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                            handleStrideBytes: MemoryLayout<EntityHandle>.stride,
                            measuredIterations: iterations, warmupIterations: 3, results: scales,
                            limitations: ["No gameplay, domain state, scheduler, persistence, or rendering.",
                                          "No p99, zero-allocation, RAM-footprint, FPS or thermal certification.",
                                          "Handle stride is layout size, not process memory."])
        if args.count == 2 {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: args[1]))
        }
    }
}
