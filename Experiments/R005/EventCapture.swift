// Generated diagnostic-package addition only. Never part of production Sources.
import NXRProbePlatform
package final class NXRAdvanceCapture {
    private let storage: UnsafeMutableBufferPointer<UInt64>
    private let allocations: UnsafeMutableBufferPointer<UInt64>
    package private(set) var written = 0
    package private(set) var batches = 0
    package init(capacity: Int) {
        precondition(capacity > 0)
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0)
        allocations = .allocate(capacity: (capacity + 255) / 256)
        allocations.initialize(repeating: 0)
    }
    deinit {
        storage.deinitialize(); storage.deallocate()
        allocations.deinitialize(); allocations.deallocate()
    }
    package func markEvent() {
        precondition(written < storage.count)
        storage[written] = nxr_now_ns(); written += 1
    }
    package func markAllocation(_ duration: UInt64) {
        precondition(batches < allocations.count)
        allocations[batches] = duration; batches += 1
    }
    package func exportedEvents() -> [UInt64] { Array(storage.prefix(written)) }
    package func exportedAllocations() -> [UInt64] { Array(allocations.prefix(batches)) }
}
