import NexoraIdentity
func invalid() throws {
    let space = try EntitySpace(capacity: 1)
    _ = space.auditIdentity()
}
