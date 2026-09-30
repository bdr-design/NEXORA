@testable import NexoraAviation

// Deliberately corrupt only a test-owned fixture. The harness requires the
// invariant marker AND a failed process. Ordinary thrown errors do not qualify.
var store = try AircraftStore(capacity: 1)
let made = try store.apply(.create, expected: store.token)
switch CommandLine.arguments.dropFirst().first {
case "missing-row":
    store.seedFixtureForTesting(.missingLiveRow, handle: made.handle)
    _ = try store.read(made.handle)
case "occupied-slot":
    store.seedFixtureForTesting(.occupiedFreeRow, handle: made.handle)
    _ = try store.apply(.create, expected: store.token)
default:
    fatalError("Unknown probe argument")
}
print("PROBE_FAILED: corrupt operation returned instead of stopping")
