#!/usr/bin/env python3
"""Small text-level guards, not proof of runtime behavior or time bounds."""
import pathlib, re
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'Sources/NexoraSimulation/TripSimulation.swift').read_text()
heap=(root/'Sources/NexoraSimulation/ArrivalHeap.swift').read_text()
input_body=source.split('private mutating func applyCore',1)[1].split('/// Throws only',1)[0]
advance=source.split('private mutating func advanceCore',1)[1].split('private func progress',1)[0]
input_body=re.sub(r'//[^\n]*','',input_body)
advance=re.sub(r'//[^\n]*','',advance)
for region in (input_body,advance):
    for pattern in (r'\bawait\b', r'\bTask\b', r'FileManager', r'JSON', r'Timeline',
                    r'checkInvariants', r'auditForTesting', r'\bfor\s+[^\n]*\bin\b'):
        assert not re.search(pattern,region),pattern
assert not re.search(r'\bwhile\b|\.append\(',input_body)
assert advance.count('while ') == 1
assert 'while completed.count < eventBudget' in advance
assert 'completed.reserveCapacity(min(eventBudget, arrivals.count))' in advance
assert '(1...Self.maximumEventsPerAdvance).contains(eventBudget)' in advance
assert 'inputSequence =' not in advance
assert 'public struct TripSimulation: ~Copyable, Sendable' in source
assert 'private var aircraft: AircraftStore' in source
assert 'private var arrivals: ArrivalHeap' in source
assert '.addingReportingOverflow(duration)' in input_body
assert '.blocked(.aircraft(error))' in advance
# Fixed heap mutators may sift but cannot append/grow storage.
assert 'nodes.append' not in heap and 'nodes.insert' not in heap
assert 'nodes = Array(repeating: nil, count: capacity)' in heap
assert 'left.operationID < right.operationID' in heap
print('PASS R003 bounded source guards; text inspection only, not wall-time/allocation proof')
