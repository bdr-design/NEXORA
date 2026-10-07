#!/usr/bin/env python3
"""Independent immutable-mode evidence analysis; never runs or qualifies C100."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import zipfile

EXPERIMENT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(EXPERIMENT))
from candidate_proof_inputs import manifest

COMPONENTS = ('advance', 'service', 'reschedule', 'walAdvance', 'walReschedule')
TRANSCRIPT = ('ordinal', 'events', 'workUnits', 'stop', 'reached')


def verify_pair(pair, fixture, count):
    assert pair['order'] == [leg['label'] for leg in pair['legs']]
    arms = {leg['label']: leg for leg in pair['legs']}
    assert len(pair['legs']) == 2 and set(arms) == {'save', 'no-save'}
    save, control = arms['save'], arms['no-save']
    assert save['saveEnabled'] is True and control['saveEnabled'] is False
    assert control['postBoundaryControlStateInstalled'] is True
    assert all(pair[key] is True for key in ('logicalTranscriptExact', 'outputHashExact',
                                           'finalDigestExact', 'stateInstallAligned'))
    assert len(save['calls']) == len(control['calls']) == save['advanceCalls'] == control['advanceCalls']
    assert all(all(a[key] == b[key] for key in TRANSCRIPT)
               for a, b in zip(save['calls'], control['calls']))
    assert save['finalDigest'] == control['finalDigest'] and save['outputHash'] == control['outputHash']
    for leg in (save, control):
        assert leg['events'] == sum(call['events'] for call in leg['calls']) == count
        assert leg['initialDigest'] == fixture['digest']
        assert leg['recoveryExact'] is True and leg['recoveryDigest'] == leg['finalDigest']
        assert leg['stateInstallAfterAdvanceCalls'] == fixture['saveStartCall']
        assert sum(call['advanceNS'] for call in leg['calls']) == leg['simulationThread']['advance']['ns']
        assert sum(leg['simulationThread'][key]['ns'] for key in COMPONENTS) <= leg['fullLoopNS']
        for key in COMPONENTS:
            for field in ('ns', 'allocations', 'allocationBytes'):
                value = leg['simulationThread'][key][field]
                assert type(value) is int and value >= 0
        for key in ('advance', 'service'):
            assert leg['simulationThread'][key]['allocations'] == 0
            assert leg['simulationThread'][key]['allocationBytes'] == 0
    writer = save['writer']
    assert control['writer'] == {'started': False}
    assert writer['allocationObserverAvailable'] is True and writer['peakQueuedBytes'] == 0
    assert writer['bytes'] == fixture['snapshotBytes'] and writer['chunks'] > 0
    # In qualified EPOCH_PAGES, runNS starts AFTER the one-time handoff wait.
    # queueWaitNS remains a separate, pre-run observation. Historical queue-mode
    # evidence uses its original analyzer and is never reinterpreted here.
    assert writer['recordProcessWriteNS'] + writer['finalizeNS'] <= writer['runNS']
    phases = []
    for mode in ['all', 'saveActive'] + sorted({call['stateMode'] for call in save['calls']}):
        selected = [i for i, call in enumerate(save['calls']) if mode == 'all' or
                    (mode == 'saveActive' and call['saveActive']) or call['stateMode'] == mode]
        if not selected:
            continue
        a = sum(save['calls'][i]['advanceNS'] for i in selected)
        b = sum(control['calls'][i]['advanceNS'] for i in selected)
        times = sorted(save['calls'][i]['advanceNS'] for i in selected)
        phases.append(dict(mode=mode, matchedCalls=len(selected),
                           events=sum(save['calls'][i]['events'] for i in selected),
                           saveAdvanceNS=a, controlAdvanceNS=b, deltaNS=a-b,
                           diagnosticMatchedRatio=a/b, saveAdvanceP99NS=times[math.ceil(.99*len(times))-1]))
    return dict(pair=pair['pair'], order=pair['order'], matchedPhases=phases,
                components={key: dict(save=save['simulationThread'][key],
                    control=control['simulationThread'][key],
                    deltaNS=save['simulationThread'][key]['ns']-control['simulationThread'][key]['ns'])
                    for key in COMPONENTS},
                fullLoop=dict(saveNS=save['fullLoopNS'], controlNS=control['fullLoopNS'],
                    diagnosticRatio=save['fullLoopNS']/control['fullLoopNS']),
                writer=writer, barrier=save['barrier'],
                setup=dict(save=save['simulationThread']['setup'],control=control['simulationThread']['setup']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('output', type=Path)
    for name in ('source', 'tree', 'sha256', 'run', 'artifact-id'):
        parser.add_argument('--'+name, required=True)
    args = parser.parse_args()
    assert hashlib.sha256(args.artifact.read_bytes()).hexdigest() == args.sha256
    with zipfile.ZipFile(args.artifact) as z:
        assert z.read('commit.txt').decode().strip() == args.source
        assert z.read('tree.txt').decode().strip() == args.tree
        assert json.loads(z.read('runtime-inputs.json')) == manifest()
        assert 'STAGE_C EPOCH_PAGES Release' in z.read('build-flags.txt').decode()
        for phase in ('before', 'after'):
            assert 'PASS baseline' in z.read(f'source-guard-{phase}.txt').decode()
        a = json.loads(z.read('STAGE005-A.json'))
        r = json.loads(z.read('CANDIDATE-MICRO.json'))
        assert r['status'] == 'diagnostic' and r['assets'] == 1000000 and r['saves'] == 5
        assert r['variant'] == a['decisionA']['chosen']
        # The unchanged C raw schema has no snapshotSource field. Immutable
        # ownership is bound by the exact runtime manifest and compiler flags.
        gates = dict(beginP99=r['beginSaveNS']['p99'] <= 100000,
            advanceP99=r['advanceDuringSaveNS']['p99'] <= 1100000,
            overhead=math.isfinite(r['overheadRatio']) and r['overheadRatio'] <= 1.10,
            beginSamples=r['beginSaveNS']['samples'] == 5,
            advanceSamples=r['advanceDuringSaveNS']['samples'] >= 5,
            pairedCoverage=r['allocationPairing']['samples'] == r['advanceDuringSaveNS']['samples'],
            pairedBound=r['allocationPairing']['violations'] == r['allocationPairing']['maxExcess'] == 0,
            idleZero=r['allocationsIdleMaxPerAdvance'] == 0, queueZero=r['peakQueuedBytes'] == 0)
        e = json.loads(z.read('MICRO-ELIGIBILITY.json'))
        assert e['gates'] == gates and e['failedGates'] == [key for key, value in gates.items() if not value]
        assert e['status'] == ('pass' if all(gates.values()) else 'failure') and e['acceptance'] is False
        phases = r['simulationPhases']
        assert phases['idle']['events'] == r['idleEvents']
        assert phases['capturing']['events'] + phases['writerOnly']['events'] == r['savingEvents']
        assert sum(x['calls'] for x in phases.values()) == r['advanceCalls']
        idle = phases['idle']['ns']/r['idleEvents']
        saving = (phases['capturing']['ns']+phases['writerOnly']['ns'])/r['savingEvents']
        assert idle == r['idleNSPerEvent'] and saving == r['saveNSPerEvent']
        assert saving/idle == r['overheadRatio']
        profiles = {}
        for name, count, pairs in (('PAIRED-SMOKE-S.json',4096,1),('PAIRED-PROFILE-S.json',1000000,2)):
            row = json.loads(z.read(name))
            assert row['status'] == 'diagnostic' and row['acceptance'] is False and row['variant'] == 'S'
            assert row['assets'] == count and len(row['pairs']) == pairs
            assert row['fixture']['deadline'] == 'none' and row['fixture']['budget'] == 1024
            assert row['fixture']['workBudget'] == 65536 and row['fixture']['target'] == 600
            assert [pair['order'] for pair in row['pairs']] == [['no-save','save'],['save','no-save']][:pairs]
            profiles[name] = [verify_pair(pair,row['fixture'],count) for pair in row['pairs']]
        for name in ('micro.stderr.txt','paired.stderr.txt','paired-smoke.stderr.txt'):
            assert not z.read(name)
        proof = dict(status='diagnostic-verified',acceptance=False,source=args.source,tree=args.tree,
            run=int(args.run),artifact=int(args.artifact_id),zipSHA256=args.sha256,
            micro=r,microEligibility=e,pairedProfiles=profiles,
            C100='NOT_RUN',CPerformance=dict(S='OPEN',H='OPEN'),
            limitations=['Five saves cannot close C. Original failures and 1.10 remain.',
                'S matched ABBA ratios are diagnostic, not H or official C acceptance.',
                'Writer and simulation overlap; their wall times cannot be added.',
                'Full spare-image owned capacities exclude complete physical memory and device acceptance.'],
            evidenceSHA256={name:hashlib.sha256(z.read(name)).hexdigest() for name in sorted(z.namelist()) if not name.endswith('/')})
    args.output.write_text(json.dumps(proof,indent=2)+'\n')
    print(json.dumps(dict(status=proof['status'],eligibility=e['status'],failedGates=e['failedGates'],
                         variant=r['variant'],overheadRatio=r['overheadRatio'])))


if __name__ == '__main__':
    main()
