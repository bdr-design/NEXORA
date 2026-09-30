import NexoraSimulation
func allowedTripClient() throws {
    var world = try TripSimulation(capacity: 1, eventCapacity: 1)
    let made = try world.apply(.registerAircraft(at: 1), expected: world.inputToken)
    _ = try world.apply(.depart(made.handle, destination: 2, durationSeconds: 10), expected: world.inputToken)
    let progress = try world.advance(to: 10, eventBudget: 1)
    print(progress.reachedTime)
    _ = try world.read(made.handle)
    _ = try world.apply(.retireAircraft(made.handle), expected: world.inputToken)
}
