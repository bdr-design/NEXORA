#!/usr/bin/env python3
"""Verify and summarize the fixed-work paired diagnostic, never C acceptance."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile


SCRIPT_FIELDS = ('ordinal', 'events', 'workUnits', 'stop', 'reached')
COMPONENTS = ('advance', 'service', 'reschedule', 'walAdvance', 'walReschedule')


def check(condition, message):
    if not condition:
        raise ValueError(message)


def nonnegative_int(value, message):
    check(type(value) is int and value >= 0, message)
    return value


def summarize_pair(pair, fixture):
    legs = pair['legs']
    check(len(legs) == 2, 'exactly two legs required')
    check([leg['label'] for leg in legs] == pair['order'], 'order mismatch')
    arms = {leg['label']: leg for leg in legs}
    check(set(arms) == {'save', 'no-save'}, 'save/control labels')
    save, control = arms['save'], arms['no-save']
    check(save['saveEnabled'] is True and control['saveEnabled'] is False,
          'save/control ownership')
    check(control['postBoundaryControlStateInstalled'] is True,
          'control must retain idle StageCState hooks')
    for leg in legs:
        check(leg['stateInstallAfterAdvanceCalls'] == fixture['saveStartCall'],
              'state installation boundary')
        check(leg['initialDigest'] == fixture['digest'], 'fixture digest')
        check(leg['recoveryExact'] is True and
              leg['recoveryDigest'] == leg['finalDigest'], 'recovery equality')
        check(leg['advanceCalls'] == len(leg['calls']), 'call coverage')
        check(leg['events'] == sum(c['events'] for c in leg['calls']), 'event sum')
        for component in COMPONENTS:
            observation = leg['simulationThread'][component]
            for key in ('ns', 'allocations', 'allocationBytes'):
                nonnegative_int(observation[key], f'{component}.{key}')
        check(sum(c['advanceNS'] for c in leg['calls']) ==
              leg['simulationThread']['advance']['ns'], 'advance time sum')
        for call in leg['calls']:
            for key in ('advanceNS', 'advanceAllocations', 'advanceAllocationBytes',
                        'events', 'workUnits'):
                nonnegative_int(call[key], f'call.{key}')
    for key in ('initialDigest', 'finalDigest', 'outputHash'):
        check(save[key] == control[key], f'paired {key}')
    check(len(save['calls']) == len(control['calls']), 'paired call count')
    for a, b in zip(save['calls'], control['calls']):
        check(all(a[k] == b[k] for k in SCRIPT_FIELDS), 'logical transcript')
    writer = save['writer']
    check(writer['allocationObserverAvailable'] is True, 'writer allocator unavailable')
    check(writer['bytes'] == fixture['snapshotBytes'] and writer['chunks'] > 0,
          'writer exact snapshot result')
    check(control['writer'] == {'started': False}, 'control writer unexpectedly active')
    for key in ('runNS', 'queueWaitNS', 'recordProcessWriteNS', 'finalizeNS',
                'dispatchToRunNS', 'allocations', 'allocationBytes', 'peakQueuedBytes'):
        nonnegative_int(writer[key], f'writer.{key}')
    check(writer['queueWaitNS'] + writer['recordProcessWriteNS'] + writer['finalizeNS']
          <= writer['runNS'], 'writer components exceed run lifetime')
    phases = []
    modes = sorted({c['stateMode'] for c in save['calls']})
    for mode in ['all', 'saveActive'] + modes:
        selected = [i for i, c in enumerate(save['calls']) if mode == 'all' or
                    (mode == 'saveActive' and c['saveActive']) or c['stateMode'] == mode]
        if not selected:
            continue
        saving = sum(save['calls'][i]['advanceNS'] for i in selected)
        baseline = sum(control['calls'][i]['advanceNS'] for i in selected)
        times = sorted(save['calls'][i]['advanceNS'] for i in selected)
        phases.append({'mode': mode, 'matchedCalls': len(selected),
                       'events': sum(save['calls'][i]['events'] for i in selected),
                       'saveAdvanceNS': saving, 'controlAdvanceNS': baseline,
                       'deltaNS': saving - baseline,
                       'diagnosticMatchedRatio': saving / baseline if baseline else None,
                       'saveAdvanceP99NS': times[math.ceil(.99 * len(times)) - 1]})
    return {'pair': pair['pair'], 'order': pair['order'], 'calls': len(save['calls']),
            'events': save['events'], 'matchedPhases': phases,
            'components': {k: {'save': save['simulationThread'][k],
                               'control': control['simulationThread'][k],
                               'deltaNS': save['simulationThread'][k]['ns'] -
                                          control['simulationThread'][k]['ns']}
                           for k in COMPONENTS},
            'fullLoop': {'saveNS': save['fullLoopNS'], 'controlNS': control['fullLoopNS'],
                         'diagnosticRatio': save['fullLoopNS'] / control['fullLoopNS']},
            'barrier': save['barrier'], 'writer': writer,
            'setup': {'save': save['simulationThread']['setup'],
                      'control': control['simulationThread']['setup']},
            'finalDigest': save['finalDigest'], 'outputHash': save['outputHash']}


def analyze(profile):
    check(profile['acceptance'] is False and profile['status'] == 'diagnostic',
          'diagnostic identity')
    check(profile['variant'] == 'S', 'only S is covered by this runner')
    fixture = profile['fixture']
    check(fixture['deadline'] == 'none', 'fixed-work profile must have no deadline')
    check(fixture['budget'] == 1024 and fixture['workBudget'] == 65536 and
          fixture['target'] == 600, 'fixed script')
    pairs = [summarize_pair(p, fixture) for p in profile['pairs']]
    if profile['assets'] == 1_000_000:
        check([p['order'] for p in pairs] == [['no-save', 'save'], ['save', 'no-save']],
              '1M requires ABBA order')
        check(all(p['events'] == 1_000_000 for p in pairs), '1M event coverage')
    else:
        check(profile['assets'] == 4096 and len(pairs) == 1, 'bounded smoke scope')
    return {'status': 'diagnostic-verified', 'acceptance': False,
            'layout': 'S', 'assets': profile['assets'], 'fixture': fixture, 'pairs': pairs,
            'C100SavePerformance': None, 'Cacceptance': 'OPEN independently on S and H',
            'limitations': [profile['instrumentation'], profile['limits'],
                'Two hosted-runner pairs cannot establish stable writer causality or device smoothness.',
                'Writer wall time overlaps simulation; component totals must not be added across threads.',
                'Matched fixed-work ratios are not the official deadline-shaped C overhead ratio.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--tree', required=True)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    raw = args.artifact.read_bytes()
    check(hashlib.sha256(raw).hexdigest() == args.sha256, 'ZIP SHA256 mismatch')
    with zipfile.ZipFile(args.artifact) as archive:
        check(archive.read('commit.txt').decode().strip() == args.source, 'source mismatch')
        check(archive.read('tree.txt').decode().strip() == args.tree, 'tree mismatch')
        result = analyze(json.loads(archive.read('PAIRED-PROFILE-S.json')))
        for mode in ('debug', 'release'):
            analyze(json.loads(archive.read(f'PAIRED-PROFILE-SMOKE-{mode}.json')))
        result['source'] = args.source
        result['tree'] = args.tree
        result['artifactSHA256'] = args.sha256
        result['rawEntries'] = [{'name': entry.filename, 'bytes': entry.file_size,
                                'sha256': hashlib.sha256(archive.read(entry)).hexdigest()}
                               for entry in archive.infolist()]
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'acceptance': False,
                      'pairs': len(result['pairs']), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
