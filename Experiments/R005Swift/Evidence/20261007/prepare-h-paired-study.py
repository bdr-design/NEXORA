"""Retarget only the existing paired harness in a disposable current-source copy.

No change to actual Sources, S/H owners, snapshot writer, WAL or C evaluator.
"""
from pathlib import Path
import sys

package = Path(sys.argv[1]).resolve()
assert package.name == '.h-paired-study'
source = package / 'Sources/SwiftProbe'
p = source / 'Stage005CRunner.swift'
s = p.read_text()
start = s.index('private struct StageCPairedScriptCall')
end = s.index('func stageCPairedProfile(_ directory: String)')
end = s.index('\n}', end) + 2
section = s[start:end]
assert section.count('SwiftWorld') == 1
assert section.count('StageCSnapshotRestore') == 2
assert section.count('stageCPrepareInitial') == 1
assert section.count('stageCRescheduleAll') == 1
section = section.replace('SwiftWorld', 'HybridWorld')
section = section.replace('StageCSnapshotRestore', 'StageCHybridSnapshotRestore')
section = section.replace('stageCPrepareInitial', 'stageCPairedHybridPrepareInitial')
section = section.replace('stageCRescheduleAll', 'stageCHybridRescheduleAll')
section = section.replace('1M paired S diagnostic', '1M paired H diagnostic')
assert section.count('"variant": "S"') == 1
section = section.replace('"variant": "S"', '"variant": "H"')
needle = '    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)\n'
assert section.count(needle) == 1
section = section.replace(needle,
    '    let cPositive = nx_alloc_calibrate()\n'
    '    nx_alloc_begin(); let positiveValue = allocationControl(8193); let swiftPositive = nx_alloc_end()\n'
    '    try require(positiveValue == 8193 * 7 + 2 && cPositive > 0 && swiftPositive.available == 1 && swiftPositive.calls > 0, "paired H positive controls")\n' + needle)
section = section.replace('        "variant": "H",\n',
    '        "variant": "H",\n'
    '        "cAllocationPositiveControl": cPositive,\n'
    '        "swiftAllocationPositiveControl": swiftPositive.calls,\n')
# Capacity is sampled after every timed profile phase; timing samples cannot
# be improved by the capacity scan. The scan time is separately disclosed.
needle = '    let writer = installedState.lastResult\n'
assert section.count(needle) == 1
section = section.replace(needle, '    let capacityStart = nx_now()\n'
    '    let postProfileOwnedBytes = world.ownedBytes\n'
    '    let capacitySampleNS = nx_now() - capacityStart\n' + needle)
needle = '        "writerPollSleepNS": writerWaitNS,\n'
assert section.count(needle) == 1
section = section.replace(needle, needle +
    '        "postProfileOwnedBytes": postProfileOwnedBytes,\n'
    '        "ownedCapacitySampleNS": capacitySampleNS,\n')
helper = '''private func stageCPairedHybridPrepareInitial(directory: String, count: Int)
    throws -> (HybridWorld, StageCState, StageCWAL, StageCSnapshotFileResult) {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    let world = try HybridWorld(count: count)
    try world.seedFixture()
    let state = StageCState(world: world)
    world.stageCInstall(state)
    let wal = try StageCWAL(directory: directory, epoch: 1)
    let sink = state.prepareSink(directory: directory, epoch: 1)
    try state.begin(world: world, preparedSink: sink)
    let result = try state.waitForCommit(world: world)
    return (world, state, wal, result)
}

'''
p.write_text(s[:start] + helper + section + s[end:])

p = source / 'Main.swift'
s = p.read_text()
for command in ('stage-c-paired-profile-smoke', 'stage-c-paired-profile'):
    start = s.index(f'case "{command}":')
    end = s.index('\n        case ', start + 1)
    section = s[start:end]
    assert section.count('args[2] == "S"') == 1
    section = section.replace('args[2] == "S"', 'args[2] == "H"')
    section = section.replace('directory S', 'directory H')
    s = s[:start] + section + s[end:]
p.write_text(s)
