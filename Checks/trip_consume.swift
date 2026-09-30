import NexoraSimulation
func invalid() throws {
    let original = try TripSimulation(capacity: 1, eventCapacity: 1)
    let moved = consume original
    print(moved.now)
    print(original.now)
}
