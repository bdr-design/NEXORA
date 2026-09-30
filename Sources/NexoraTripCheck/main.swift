import Foundation
import NexoraSimulation
import NexoraIdentity

enum ProbeFailure: Error { case invalidArguments, incorrectState }
func nanoseconds(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> UInt64 {
    let p = a.duration(to: b).components
    return UInt64(p.seconds) * 1_000_000_000 + UInt64(p.attoseconds / 1_000_000_000)
}
struct TripSample: Codable {
    let registerAllNS: UInt64
    let departAllNS: UInt64
    let advanceAllNS: UInt64
    let largestAdvanceNS: UInt64
    let batches: Int
    let completed: Int
}
struct TripScale: Codable { let aircraft: Int; let samples: [TripSample] }
struct TripReport: Codable {
    let scope: String
    let budget: Int
    let scales: [TripScale]
    let limitations: [String]
}
func measure(_ count: Int) throws -> TripSample {
    var simulation = try TripSimulation(capacity: count, eventCapacity: count)
    var handles: [EntityHandle] = []; handles.reserveCapacity(count)
    let clock = ContinuousClock()
    let registering = clock.now
    for _ in 0..<count {
        handles.append(try simulation.apply(.registerAircraft(at: 1), expected: simulation.inputToken).handle)
    }
    let registered = clock.now
    for (index, h) in handles.enumerated() {
        _ = try simulation.apply(.depart(h, destination: 2, durationSeconds: UInt64(index % 600 + 1)),
                                 expected: simulation.inputToken)
    }
    let departed = clock.now
    var completed = 0, batches = 0
    var largest: UInt64 = 0
    repeat {
        let begin = clock.now
        let result = try simulation.advance(to: 600, eventBudget: 256)
        let end = clock.now
        largest = max(largest, nanoseconds(begin, end))
        guard result.stop == .reachedTarget || result.stop == .eventBudgetReached else {
            throw ProbeFailure.incorrectState
        }
        completed += result.processedEvents; batches += 1
    } while simulation.now != 600 || simulation.pendingArrivals > 0
    let advanced = clock.now
    guard completed == count, simulation.checkInvariants() else { throw ProbeFailure.incorrectState }
    for h in handles {
        let row = try simulation.read(h)
        guard row.currentAirport == 2, row.completedTrips == 1, row.activeTrip == nil else {
            throw ProbeFailure.incorrectState
        }
    }
    return TripSample(registerAllNS: nanoseconds(registering, registered),
                      departAllNS: nanoseconds(registered, departed),
                      advanceAllNS: nanoseconds(departed, advanced), largestAdvanceNS: largest,
                      batches: batches, completed: completed)
}
@main enum TripCheck {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2 && args[0] == "--json" else { throw ProbeFailure.invalidArguments }
        var scales: [TripScale] = []
        for count in [1_000, 5_000, 20_000, 50_000, 100_000] {
            for _ in 0..<3 { _ = try measure(count) }
            var samples: [TripSample] = []
            for _ in 0..<30 { samples.append(try measure(count)) }
            scales.append(TripScale(aircraft: count, samples: samples))
            print("Timed-trip fixture verified: \(count) aircraft, budget 256, 30 samples; not full gameplay")
        }
        let report = TripReport(scope: "bounded-in-memory-timed-trip-fixture", budget: 256, scales: scales,
            limitations: ["No real route network, finance, payroll, maintenance, storage, UI or renderer.",
                          "Advance timing includes capped result arrays and loop/result checks.",
                          "Largest observed sample is not a certified p99 or hard frame-time guarantee.",
                          "No iPhone, FPS, physical RAM, zero-allocation, energy or thermal certification."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[1]))
    }
}
