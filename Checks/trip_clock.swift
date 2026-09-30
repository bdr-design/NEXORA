import NexoraSimulation
func invalid() throws {
    var world = try TripSimulation(capacity: 1, eventCapacity: 1)
    world.now = 999
}
