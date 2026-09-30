import NexoraSimulation
func invalid() throws {
    _ = try TripSimulation(testingCapacity: 1, eventCapacity: 1, initialTime: 0)
}
