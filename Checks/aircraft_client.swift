import NexoraAviation
func allowedAircraftClient() throws {
    var store = try AircraftStore(capacity: 1)
    let made = try store.apply(.create, expected: store.token)
    let start = try store.apply(.start(made.handle), expected: store.token)
    _ = try store.apply(.complete(made.handle, operationID: start.token.revision), expected: store.token)
    _ = try store.read(made.handle)
    _ = try store.apply(.retire(made.handle), expected: store.token)
}
