import NexoraAviation
func invalid() throws {
    let original = try AircraftStore(capacity: 1)
    let moved = consume original
    print(moved.liveCount)
    print(original.liveCount)
}
