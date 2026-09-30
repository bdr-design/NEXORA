import NexoraAviation
func invalid() throws {
    var store = try AircraftStore(capacity: 1)
    let result = try store.apply(.create, expected: store.token)
    var view = try store.read(result.handle)
    view.completedOperations = 9
}
