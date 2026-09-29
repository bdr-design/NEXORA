import NexoraIdentity
func misuse() async throws {
    var space = try EntitySpace(capacity: 2)
    async let a = space.create()
    async let b = space.create()
    _ = try await (a, b) // Must fail: concurrent mutation of one owner.
}
