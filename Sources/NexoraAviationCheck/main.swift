import Foundation
import NexoraIdentity
import NexoraAviation

struct LifecycleSample: Codable {
    let initializeNS: UInt64
    let createNS: UInt64
    let startNS: UInt64
    let completeNS: UInt64
    let readNS: UInt64
    let retireNS: UInt64
    let auditNS: UInt64
}
struct LifecycleScale: Codable {
    let aircraftRecords: Int
    let samples: [LifecycleSample]
}
struct LifecycleReport: Codable {
    let update: String
    let scope: String
    let operatingSystem: String
    let repetitions: Int
    let warmups: Int
    let scales: [LifecycleScale]
    let limitations: [String]
}
enum ProbeError: Error { case arguments, invariant, result }
func elapsed(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> UInt64 {
    let p = start.duration(to: end).components
    return UInt64(p.seconds) * 1_000_000_000 + UInt64(p.attoseconds / 1_000_000_000)
}
func measure(_ count: Int) throws -> LifecycleSample {
    let clock = ContinuousClock()
    let initializing = clock.now
    var store = try AircraftStore(capacity: count)
    let initialized = clock.now
    var handles: [EntityHandle] = []
    var operations: [UInt64] = []
    handles.reserveCapacity(count); operations.reserveCapacity(count)
    let creating = clock.now
    for _ in 0..<count { handles.append(try store.apply(.create, expected: store.token).handle) }
    let created = clock.now
    for h in handles {
        operations.append(try store.apply(.start(h), expected: store.token).token.revision)
    }
    let started = clock.now
    for (h, operation) in zip(handles, operations) {
        let result = try store.apply(.complete(h, operationID: operation), expected: store.token)
        guard result.completedOperations == 1 else { throw ProbeError.result }
    }
    let completed = clock.now
    for h in handles {
        let row = try store.read(h)
        guard row.state == .ready && row.completedOperations == 1 else { throw ProbeError.result }
    }
    let read = clock.now
    for h in handles { _ = try store.apply(.retire(h), expected: store.token) }
    let retired = clock.now
    guard store.checkInvariants(), store.liveCount == 0,
          store.token.revision == UInt64(count) * 4 else { throw ProbeError.invariant }
    let audited = clock.now
    return LifecycleSample(initializeNS: elapsed(initializing, initialized),
                           createNS: elapsed(creating, created), startNS: elapsed(created, started),
                           completeNS: elapsed(started, completed), readNS: elapsed(completed, read),
                           retireNS: elapsed(read, retired), auditNS: elapsed(retired, audited))
}
@main enum AircraftCheck {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2 && args[0] == "--json" else { throw ProbeError.arguments }
        var scales: [LifecycleScale] = []
        for count in [1_000, 5_000, 20_000, 50_000, 100_000] {
            for _ in 0..<3 { _ = try measure(count) }
            var samples: [LifecycleSample] = []
            for _ in 0..<30 { samples.append(try measure(count)) }
            scales.append(LifecycleScale(aircraftRecords: count, samples: samples))
            print("Verified aircraft-store lifecycle: \(count) records; 30 samples, not full gameplay")
        }
        let report = LifecycleReport(update: "NXR-R002", scope: "serial-aircraft-store-not-full-gameplay",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            repetitions: 30, warmups: 3, scales: scales,
            limitations: ["No scheduler, flights, finance, persistence, UI, or renderer in this fixture.",
                          "Initialization, validation and loop/receipt overhead are reported or included, not hidden.",
                          "No p99 certification, zero-allocation proof, physical memory, FPS, energy, or temperature result.",
                          "Mac/Linux timings are not iPhone certification."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[1]))
    }
}
