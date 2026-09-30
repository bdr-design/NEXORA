@testable import NexoraSimulation

var world = try TripSimulation(capacity: 1, eventCapacity: 1)
let made = try world.apply(.registerAircraft(at: 1), expected: world.inputToken)
_ = try world.apply(.depart(made.handle, destination: 2, durationSeconds: 10), expected: world.inputToken)
world.corruptJourneyForTesting(made.handle)
switch CommandLine.arguments.dropFirst().first {
case "read": _ = try world.read(made.handle)
case "advance": _ = try world.advance(to: 10, eventBudget: 1)
default: fatalError("Unknown probe argument")
}
print("PROBE_FAILED: corrupt trip operation returned instead of stopping")
