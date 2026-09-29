import Testing
@testable import NexoraIdentity

struct IdentityTests {
    @Test func emptySpaceIsValidButExhausted() throws {
        var space = try EntitySpace(capacity: 0)
        verify(space.checkInvariants())
        do { _ = try space.create(); Issue.record("Expected exhaustion") }
        catch { verify(error as? IdentityFailure == .capacityExhausted) }
    }

    @Test(arguments: [-1, Int.max, 1_000_001])
    func badCapacityIsRejected(_ count: Int) {
        do { _ = try EntitySpace(capacity: count); Issue.record("Expected invalid capacity") }
        catch { verify(error as? IdentityFailure == .invalidCapacity) }
    }

    @Test func creationAndExhaustionDoNotCorruptState() throws {
        var space = try EntitySpace(capacity: 1)
        let handle = try space.create()
        do { _ = try space.create(); Issue.record("Expected exhaustion") }
        catch { verify(error as? IdentityFailure == .capacityExhausted) }
        verify(space.contains(handle))
        verify(space.liveCount == 1)
        verify(space.checkInvariants())
    }

    @Test func destroyedHandleIsImmediatelyStale() throws {
        var space = try EntitySpace(capacity: 1)
        let handle = try space.create()
        try space.destroy(handle)
        verify(!space.contains(handle))
        do { try space.destroy(handle); Issue.record("Expected stale rejection") }
        catch { verify(error as? IdentityFailure == .staleHandle) }
        verify(space.liveCount == 0)
        verify(space.checkInvariants())
    }

    @Test func reuseChangesGenerationAndNotSlot() throws {
        var space = try EntitySpace(capacity: 1)
        let before = try space.create()
        try space.destroy(before)
        let after = try space.create()
        verify(before.slot == after.slot)
        verify(after.generation == before.generation + 1)
        verify(before != after)
        verify(!space.contains(before))
        verify(space.contains(after))
    }

    @Test func foreignHandlesCannotMutateAnIdenticallyShapedSpace() throws {
        var left = try EntitySpace(capacity: 1)
        var right = try EntitySpace(capacity: 1)
        let a = try left.create()
        let b = try right.create()
        verify(a.slot == b.slot && a.generation == b.generation)
        verify(a != b)
        verify(!right.contains(a))
        do { try right.destroy(a); Issue.record("Expected foreign rejection") }
        catch { verify(error as? IdentityFailure == .foreignSpace) }
        verify(left.contains(a) && right.contains(b))
        verify(left.checkInvariants() && right.checkInvariants())
    }

    @Test func maximumGenerationRetiresWithoutWrapping() throws {
        var space = try EntitySpace(capacity: 1, initialGeneration: .max)
        let handle = try space.create()
        try space.destroy(handle)
        verify(space.retiredCount == 1 && space.liveCount == 0)
        verify(space.checkInvariants())
        do { _ = try space.create(); Issue.record("Retired slot was reused") }
        catch { verify(error as? IdentityFailure == .capacityExhausted) }
    }

    @Test func penultimateGenerationCanBeUsedOnceMore() throws {
        var space = try EntitySpace(capacity: 1, initialGeneration: UInt32.max - 1)
        let first = try space.create()
        try space.destroy(first)
        let last = try space.create()
        verify(last.generation == UInt32.max)
        try space.destroy(last)
        verify(space.retiredCount == 1 && space.checkInvariants())
    }

    @Test func handleRemainsForeignAfterItsSpaceIsReleased() throws {
        func oldHandle() throws -> EntityHandle {
            var space = try EntitySpace(capacity: 1)
            return try space.create()
        }
        let staleWorldHandle = try oldHandle()
        var replacement = try EntitySpace(capacity: 1)
        let current = try replacement.create()
        verify(staleWorldHandle != current)
        verify(!replacement.contains(staleWorldHandle))
    }

    @Test func mixedLifecycleMatchesReferenceModel() throws {
        var space = try EntitySpace(capacity: 127)
        var live: [EntityHandle] = []
        var dead: [EntityHandle] = []
        var random: UInt64 = 12345
        for step in 0..<20_000 {
            random = random &* 6364136223846793005 &+ 1
            if live.isEmpty || (live.count < 127 && (random >> 32) % 100 < 62) {
                let created = try space.create()
                verify(!live.contains(created))
                live.append(created)
            } else {
                let index = Int((random >> 8) % UInt64(live.count))
                let removed = live.remove(at: index)
                try space.destroy(removed)
                dead.append(removed)
            }
            verify(space.liveCount == live.count)
            if step % 97 == 0 {
                verify(space.checkInvariants())
                for handle in live { verify(space.contains(handle)) }
                for handle in dead.suffix(256) { verify(!space.contains(handle)) }
            }
        }
    }

    @Test(arguments: [1_000, 5_000, 20_000, 50_000, 100_000])
    func scaleLifecycle(_ size: Int) throws {
        var space = try EntitySpace(capacity: size)
        var handles: [EntityHandle] = []
        handles.reserveCapacity(size)
        for _ in 0..<size { handles.append(try space.create()) }
        verify(Set(handles).count == size)
        verify(space.liveCount == size && space.checkInvariants())
        for handle in handles.reversed() { try space.destroy(handle) }
        verify(space.liveCount == 0 && space.checkInvariants())
        for handle in handles { verify(!space.contains(handle)) }
    }

    @Test func independentTasksHaveNoSharedMutableWorkspace() async throws {
        try await withThrowingTaskGroup(of: EntityHandle.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    var space = try EntitySpace(capacity: 1)
                    for _ in 0..<1_000 {
                        let handle = try space.create()
                        try space.destroy(handle)
                    }
                    return try space.create()
                }
            }
            var identities = Set<EntityHandle>()
            for try await handle in group { identities.insert(handle) }
            verify(identities.count == 16)
        }
    }
}
