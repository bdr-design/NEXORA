import NexoraIdentity
func allowed() throws {
    var space = try EntitySpace(capacity: 1)
    let handle = try space.create()
    guard space.contains(handle) else { return }
    try space.destroy(handle)
}
