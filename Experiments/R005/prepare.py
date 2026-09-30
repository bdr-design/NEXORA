#!/usr/bin/env python3
"""Create a disposable, auditable instrumentation build. Never edit production files."""
import hashlib, json, shutil, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def replace_once(text, old, new):
    if text.count(old)!=1: raise ValueError('instrumentation anchor is not unique: '+old[:90])
    return text.replace(old,new,1)

def prepare(destination):
    if destination.exists(): raise ValueError('refuse existing generated directory')
    destination.mkdir(parents=True)
    original={}
    for folder in ('Sources','Tests'):
        shutil.copytree(ROOT/folder,destination/folder)
    shutil.copy2(ROOT/'Package.swift',destination/'Package.swift')
    for p in destination.rglob('*'):
        if p.is_file(): original[str(p.relative_to(destination))]=hashlib.sha256(p.read_bytes()).hexdigest()
    package=(destination/'Package.swift').read_text()
    package=replace_once(package,'    targets: [','    targets: [\n        .target(name: "NXRProbePlatform", path: "ProbePlatform", publicHeadersPath: "include"),')
    package=replace_once(package,'.target(name: "NexoraSimulation", dependencies: [','.target(name: "NexoraSimulation", dependencies: ["NXRProbePlatform", ')
    package=replace_once(package,'.executableTarget(name: "NexoraFinancialCheck", dependencies: [','.executableTarget(name: "NexoraFinancialCheck", dependencies: ["NXRProbePlatform", ')
    (destination/'Package.swift').write_text(package)
    shutil.copytree(HERE/'Platform',destination/'ProbePlatform')
    p=destination/'Sources/NexoraSimulation/TripSimulation.swift';text=p.read_text()
    text='import NXRProbePlatform\n'+text
    signature='                                     failAtEventIndex: Int?) throws -> AdvanceResult {'
    text=replace_once(text,signature,'                                     failAtEventIndex: Int?, eventProbe: NXRAdvanceCapture? = nil) throws -> AdvanceResult {')
    old='        completed.reserveCapacity(min(eventBudget, arrivals.count))'
    text=replace_once(text,old,'        let allocationStart = eventProbe == nil ? 0 : nxr_now_ns()\n'+old+'\n        if let eventProbe { eventProbe.markAllocation(nxr_now_ns() - allocationStart) }')
    old='        while completed.count < eventBudget, let trip = arrivals.peek(), trip.arrivesAt <= target {'
    text=replace_once(text,old,old+'\n            eventProbe?.markEvent()')
    old='    private mutating func advanceCore(to target: UInt64, eventBudget: Int,'
    text=replace_once(text,old,'''    package mutating func advanceWithCapture(to target: UInt64, eventBudget: Int,
                                            capture: NXRAdvanceCapture) throws -> AdvanceResult {
        try advanceCore(to: target, eventBudget: eventBudget, failAtEventIndex: nil, eventProbe: capture)
    }

'''+old)
    p.write_text(text)
    shutil.copy2(HERE/'EventCapture.swift',p.parent/'EventCapture.swift')
    p=destination/'Sources/NexoraFinancialCheck/main.swift';text=p.read_text()
    text=replace_once(text,'        guard let first = args.first else { return false }','''        guard let first = args.first else { return false }
        if first == "--v4-study" { try ExtraStudy.run(args); return true }
        if first == "--event-study" { try ExtraStudy.events(args); return true }
        if first == "--extra-selftest" { try ExtraStudy.selftest(); return true }''')
    text=replace_once(text,'captureTruth: Bool = false, trace: BatchTrace? = nil) throws -> MeasuredFixture {',
        'captureTruth: Bool = false, trace: BatchTrace? = nil, v4: V4Capture? = nil, eventCapture: NXRAdvanceCapture? = nil) throws -> MeasuredFixture {')
    # Exactly the three existing batch phase brackets; not calibration or a production function.
    for phase in (0,1,2):
        needle=f'        trace?.begin(aircraft: count, world: sampleIndex, phase: {phase}, batch:'
        if text.count(needle)!=1: raise ValueError('missing phase')
        text=text.replace(needle,'        v4?.begin()\n'+needle,1)
    needle='        let finished = clock.now\n        trace?.finish()'
    if text.count(needle)!=3: raise ValueError('changed phase end anchors')
    text=text.replace(needle,'        let finished = clock.now\n        v4?.end()\n        trace?.finish()')
    measured_start=text.index('func measuredFixture(')
    text=text[:measured_start]+replace_once(text[measured_start:],'        let progress = try world.advance(to: 600, eventBudget: 256)',
        '''        let progress: AdvanceResult
        if let eventCapture {
            progress = try world.advanceWithCapture(to: 600, eventBudget: 256, capture: eventCapture)
        } else { progress = try world.advance(to: 600, eventBudget: 256) }''')
    text+='\n'+(HERE/'CounterStudy.swift').read_text();p.write_text(text)
    transformed={str(p.relative_to(destination)):hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in destination.rglob('*') if p.is_file()}
    changed=[n for n,v in original.items() if transformed[n]!=v]
    assert set(changed)=={'Package.swift','Sources/NexoraSimulation/TripSimulation.swift','Sources/NexoraFinancialCheck/main.swift'}
    # The original files must remain unchanged despite generation.
    for n,v in original.items(): assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==v
    identity=hashlib.sha256(json.dumps(transformed,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    (destination/'instrumentation-manifest.json').write_text(json.dumps({
        'scope':'disposable measurement only; production files unchanged','original':original,
        'generated':transformed,'changed':changed,'sha256':identity},indent=2)+'\n')
    print(identity)

if __name__=='__main__':
    if len(sys.argv)!=2: raise SystemExit('usage: prepare.py NEW_DISPOSABLE_DIRECTORY')
    prepare(Path(sys.argv[1]).resolve())
