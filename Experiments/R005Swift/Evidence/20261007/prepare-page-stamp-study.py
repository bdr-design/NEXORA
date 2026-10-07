"""Prepare disposable diagnostic packages; no actual Sources are modified."""
from pathlib import Path
import sys
package=Path(sys.argv[1]).resolve()
assert package.parent.name=='.page-stamp-study' and package.name in ('base','stamp')
source=package/'Sources/SwiftProbe'
p=source/'Stage005CPagedChecks.swift';s=p.read_text()
s=s.replace('    let initStart = nx_now(), world = try make()', '    nx_alloc_begin()\n    let initStart = nx_now(), world = try make()',1)
s=s.replace('    let worldSetupNS = nx_now() - initStart, liveOwned = world.ownedBytes', '    let worldSetupNS = nx_now() - initStart, setupAllocation = nx_alloc_end()\n    let liveOwned = world.ownedBytes',1)
needle='            "preparedOwnedBytes": world.ownedBytes, "allocationPolicy": allocationPolicy,'
assert needle in s
s=s.replace(needle,needle+'\n            "worldSetupAllocations": pagedObservation(setupAllocation.calls, available: available),\n            "worldSetupAllocationBytes": pagedObservation(setupAllocation.bytes, available: available),\n            "worldSetupAllocationAvailable": available,')
p.write_text(s)
if package.name=='stamp':
 p=source/'EpochPages.swift';s=p.read_text()
 s=s.replace('import Foundation\n','''import Foundation
import Synchronization

// Private simulation-owner metadata; never part of a frozen writer view.
private final class EpochPageStamp {
    let value = Atomic<UInt32>(0)
}
''',1)
 assert s.count('private var pageEpoch: ContiguousArray<UInt32>')==1
 s=s.replace('private var pageEpoch: ContiguousArray<UInt32>','private let pageEpoch: ContiguousArray<EpochPageStamp>')
 s=s.replace('pageEpoch = .init(repeating: 0, count: pageCount)','pageEpoch = .init((0..<pageCount).map { _ in EpochPageStamp() })')
 assert s.count('pageEpoch[page] != epoch')==2
 s=s.replace('pageEpoch[page] != epoch','pageEpoch[page].value.load(ordering: .relaxed) != epoch')
 assert s.count('pageEpoch[page] = epoch')==1
 s=s.replace('pageEpoch[page] = epoch','pageEpoch[page].value.store(epoch, ordering: .relaxed)')
 needle='        total += (leafEpoch.capacity + pageEpoch.capacity) * MemoryLayout<UInt32>.stride'
 assert needle in s
 s=s.replace(needle,'''        total += leafEpoch.capacity * MemoryLayout<UInt32>.stride
        total += pageEpoch.capacity * MemoryLayout<EpochPageStamp>.stride
        // Conservative declared page-box reserve, NOT measured phys_footprint.
        total += pageEpoch.count * 64''')
 p.write_text(s)
