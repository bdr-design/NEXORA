import NexoraIdentity
func misuse() {
    _ = EntityHandle(slot: 0, generation: 0) // Must fail: no public constructor.
}
