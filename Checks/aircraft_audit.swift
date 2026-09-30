import NexoraAviation
func invalid() throws {
    let store = try AircraftStore(capacity: 1)
    _ = store.auditForTesting()
}
