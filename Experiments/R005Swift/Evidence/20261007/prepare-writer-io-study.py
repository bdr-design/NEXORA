"""Patch only disposable study packages; main Sources remain byte identical."""
from pathlib import Path
import sys

package = Path(sys.argv[1]).resolve()
arm = sys.argv[2]
assert arm in ('base', 'packet') and package.name == arm
assert package.parent.name == '.writer-io-study'
source = package / 'Sources/SwiftProbe'

# The same diagnostic additions in both arms, outside timed/allocator scopes.
p = source / 'Stage005CPagedChecks.swift'
s = p.read_text()
needle = '"writerNS": result.writeNS,'
assert s.count(needle) == 1
s = s.replace(needle, needle + '\n'
    '                       "writerAllocatorAvailable": result.writerAllocationObserverAvailable,\n'
    '                       "writerAllocations": pagedObservation(result.writerAllocations, available: result.writerAllocationObserverAvailable),\n'
    '                       "writerAllocationBytes": pagedObservation(result.writerAllocationBytes, available: result.writerAllocationObserverAvailable),')
p.write_text(s)

if arm == 'packet':
    p = source / 'EpochSnapshot.swift'
    s = p.read_text()
    needle = '        var processNS: UInt64 = 0\n'
    assert s.count(needle) == 1
    s = s.replace(needle, needle +
        '        let splitForKill = ProcessInfo.processInfo.environment["NXR_KILL_AT"] == "c.k3.mid_record"\n')
    old = '''                if kind > 0 {
                    let split = max(16, scratch.count / 2)
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<split)
                    nx_kill_point("c.k3.mid_record")
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: split..<scratch.count)
                } else {
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<scratch.count)
                }
                try handle.write(contentsOf: parsed.2)
'''
    new = '''                let bodyBytes = scratch.count
                scratch.append(contentsOf: parsed.2)
                if kind > 0 && splitForKill {
                    // Exactly the original K3 payload prefix before SIGKILL.
                    let split = max(16, bodyBytes / 2)
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<split)
                    nx_kill_point("c.k3.mid_record")
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: split..<scratch.count)
                } else {
                    try Snapshot.writeRecord(scratch, descriptor: handle.fileDescriptor, range: 0..<scratch.count)
                }
'''
    assert s.count(old) == 1
    s = s.replace(old, new)
    old = 'bytesWritten += UInt64(scratch.count + parsed.2.count)'
    assert s.count(old) == 1
    s = s.replace(old, 'bytesWritten += UInt64(scratch.count)')
    p.write_text(s)
