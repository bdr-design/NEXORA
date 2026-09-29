import Testing
import NexoraObservability

struct TimelineTests {
    private func event(_ sequence: UInt64, parent: UInt64? = nil) -> TraceEvent {
        TraceEvent(sequence: sequence, parentSequence: parent, stage: .verification,
                   durationNanoseconds: 1, itemCount: 1)
    }

    @Test(arguments: [0, -1, 65_537, Int.max])
    func invalidCapacity(_ count: Int) {
        do { _ = try Timeline(capacity: count); Issue.record("Expected invalid capacity") }
        catch { verify(error as? TimelineFailure == .invalidCapacity) }
    }

    @Test func emptyExport() throws {
        let timeline = try Timeline(capacity: 3)
        verify(timeline.export().isEmpty)
        verify(timeline.count == 0)
    }

    @Test func wrapKeepsNewestInOrder() throws {
        var timeline = try Timeline(capacity: 3)
        for id: UInt64 in 1...20 { try timeline.append(event(id)) }
        verify(timeline.export().map(\.sequence) == [18, 19, 20])
        verify(timeline.count == 3 && timeline.overwritten == 17)
    }

    @Test func exportedArrayDoesNotAliasStorage() throws {
        var timeline = try Timeline(capacity: 1)
        try timeline.append(event(1))
        let old = timeline.export()
        try timeline.append(event(2))
        verify(old == [event(1)])
        verify(timeline.export() == [event(2)])
    }

    @Test func rejectedSequenceLeavesRingUnchanged() throws {
        var timeline = try Timeline(capacity: 3)
        try timeline.append(event(10))
        for sequence: UInt64 in [9, 10] {
            do { try timeline.append(event(sequence)); Issue.record("Expected sequence rejection") }
            catch { verify(error as? TimelineFailure == .nonMonotonicSequence) }
        }
        verify(timeline.export() == [event(10)])
        verify(timeline.overwritten == 0)
    }

    @Test func parentMustPrecedeChildButMayHaveBeenEvicted() throws {
        var timeline = try Timeline(capacity: 1)
        try timeline.append(event(1))
        try timeline.append(event(2, parent: 1))
        try timeline.append(event(3, parent: 1))
        do { try timeline.append(event(4, parent: 4)); Issue.record("Expected parent rejection") }
        catch { verify(error as? TimelineFailure == .invalidParent) }
        verify(timeline.export() == [event(3, parent: 1)])
        verify(timeline.overwritten == 2)
    }

    @Test func sequenceMaximumDoesNotWrap() throws {
        var timeline = try Timeline(capacity: 1)
        try timeline.append(event(.max))
        do { try timeline.append(event(0)); Issue.record("Expected wrap rejection") }
        catch { verify(error as? TimelineFailure == .nonMonotonicSequence) }
        verify(timeline.export().first?.sequence == UInt64.max)
    }
}
