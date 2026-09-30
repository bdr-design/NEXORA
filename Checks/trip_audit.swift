import NexoraSimulation
func invalid() throws {
    let world = try TripSimulation(capacity: 1, eventCapacity: 1)
    _ = world.auditForTesting()
}
