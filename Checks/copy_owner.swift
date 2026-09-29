import NexoraIdentity
func misuse() throws {
    let original = try EntitySpace(capacity: 1)
    let other = consume original
    print(other.liveCount)
    print(original.liveCount) // Must fail: use after ownership transfer.
}
