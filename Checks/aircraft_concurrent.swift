import NexoraAviation
func invalid() async throws {
    var store = try AircraftStore(capacity: 2)
    let token = store.token
    async let left = store.apply(.create, expected: token)
    async let right = store.apply(.create, expected: token)
    _ = try await (left, right)
}
