import NexoraSimulation
func invalid() async throws {
    var world = try TripSimulation(capacity: 1, eventCapacity: 1)
    async let a = world.advance(to: 1, eventBudget: 1)
    async let b = world.advance(to: 2, eventBudget: 1)
    _ = try await (a, b)
}
