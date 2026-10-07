"""Verify disposable writer/1M contention evidence; never qualifies C."""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import argparse
import hashlib
import importlib.util
import json
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'Experiments/R005Swift'))
from candidate_proof_inputs import manifest
from paged_candidate import comparable, validate
HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location('paired', HERE / 'verify-paged-c.py')
paired = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paired)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(args):
    assert sha(args.archive) == args.sha256
    with tempfile.TemporaryDirectory(prefix='nxr-writer-contention-verify-') as temporary:
        scratch = Path(temporary)
        raw = scratch / 'raw'
        with ZipFile(args.archive) as zipped:
            assert len(zipped.namelist()) == len(set(zipped.namelist()))
            assert sum(p.file_size for p in zipped.infolist()) < 64 * 1024 * 1024
            for item in zipped.infolist():
                path = PurePosixPath(item.filename)
                assert not path.is_absolute() and '..' not in path.parts
                assert (item.external_attr >> 16) & 0o170000 != 0o120000
            zipped.extractall(raw)
        assert (raw / 'commit.txt').read_text().strip() == args.source
        assert (raw / 'tree.txt').read_text().strip() == args.tree
        inputs = json.loads((raw / 'runtime-inputs.json').read_text())
        assert inputs == manifest() and len(inputs['paths']) == 42
        for phase in ('before', 'after'):
            assert 'PASS baseline' in (raw / f'source-guard-{phase}.txt').read_text()
        sources = json.loads((raw / 'study-source.json').read_text())
        assert set(sources) == {'base', 'packet'}
        actual = ROOT / 'Experiments/R005Swift/Sources'
        for arm in ('base', 'packet'):
            package = scratch / '.writer-io-study' / arm
            shutil.copytree(actual, package / 'Sources')
            subprocess.run([sys.executable, '-B', str(HERE / 'prepare-writer-io-study.py'), str(package), arm], check=True)
            subprocess.run([sys.executable, '-B', str(HERE / 'prepare-writer-contention-study.py'), str(package)], check=True)
            assert set(sources[arm]) == {str(p.relative_to(actual)) for p in actual.rglob('*') if p.is_file()}
            changed = []
            for name, hashes in sources[arm].items():
                assert hashes == {'actual': sha(actual / name), 'temporary': sha(package / 'Sources' / name)}
                assert inputs['paths']['Experiments/R005Swift/Sources/' + name] == hashes['actual']
                if hashes['actual'] != hashes['temporary']:
                    changed.append(name)
            expected = {'SwiftProbe/Stage005CPagedChecks.swift', 'SwiftProbe/Main.swift', 'SwiftProbe/Stage005CRunner.swift'}
            if arm == 'packet':
                expected.add('SwiftProbe/EpochSnapshot.swift')
            assert set(changed) == expected
            for mode in ('debug', 'release', 'tsan'):
                assert 'Build complete!' in (raw / f'build-{arm}-{mode}.txt').read_text()
        for name in ('study-patch-sha256.txt', 'paired-patch-sha256.txt'):
            for line in (raw / name).read_text().splitlines():
                digest, path = line.split(None, 1)
                assert sha(ROOT / path.strip()) == digest

        study = json.loads((raw / 'WRITER-IO-STUDY.json').read_text())
        assert study['status'] == 'diagnostic-verified' and study['acceptance'] is False and study['C100'] == 'NOT_RUN'
        assert len(study['rows']) == 16 and len(study['K3']) == len(study['lifecycles']) == 12
        expected = [f'bounded-{arm}-{mode}-{variant}.json' for mode in ('debug', 'release', 'tsan')
                    for variant in ('S', 'H') for arm in ('base', 'packet')]
        expected += [f'abba-{ordinal}-{arm}.json' for ordinal, arm in enumerate(('base', 'packet', 'packet', 'base'), 1)]
        assert [r['file'] for r in study['rows']] == expected
        references, held = {}, []
        for meta in study['rows']:
            path = raw / meta['file']
            assert sha(path) == meta['sha256'] and not path.with_name(path.stem + '.stderr.txt').read_text()
            row = json.loads(path.read_text())
            policy = 'functional' if meta['mode'] == 'tsan' else 'zero' if meta['mode'] == 'release' else 'observe'
            validate(row, variant=meta['variant'], count=meta['assets'], policy=policy, candidate=True)
            key = meta['variant'], meta['assets']
            if key in references:
                assert comparable(row) == references[key]
            else:
                references[key] = comparable(row)
            for epoch in row['epochs']:
                observed = policy != 'functional'
                assert epoch['writerAllocatorAvailable'] is observed
                for field in ('writerAllocations', 'writerAllocationBytes'):
                    assert type(epoch[field]) is int and epoch[field] > 0 if observed else epoch[field] is None
            assert meta['writerNS'] == [e['writerNS'] for e in row['epochs']]
            assert meta['writerAllocationBytes'] == [e['writerAllocationBytes'] for e in row['epochs']]
            if meta['assets'] == 100000:
                held.append((meta, row))
        expected_lifecycle = [f'lifecycle-{arm}-{mode}-{variant}.json' for mode in ('debug', 'release', 'tsan')
                              for variant in ('S', 'H') for arm in ('base', 'packet')]
        assert [r['file'] for r in study['lifecycles']] == expected_lifecycle
        for meta in study['lifecycles']:
            path = raw / meta['file']
            assert sha(path) == meta['sha256'] and not path.with_name(path.stem + '.stderr.txt').read_text()
            row = json.loads(path.read_text())
            assert row['status'] == 'pass' and row['assets'] == 257
            assert all(v is True for k, v in row.items() if k not in ('status', 'assets', 'scope'))
            assert row['copyObserverOwnerExact'] is True
            if path.name.endswith('-H.json'):
                assert row['coldMutationDuringFrozenEpochExact'] is True
        expected_kills = [(arm, mode, variant) for mode in ('debug', 'release', 'tsan')
                          for variant in ('S', 'H') for arm in ('base', 'packet')]
        assert [(r['arm'], r['mode'], r['variant']) for r in study['K3']] == expected_kills
        for meta in study['K3']:
            assert meta['population'] == 1000000 and meta['point'] == 'c.k3.mid_record'
            assert meta['signal'] == 'SIGKILL' and meta['exactDigest'] is True
            path = raw / meta['raw']
            assert sha(path) == meta['sha256']
            row = json.loads(path.read_text())
            assert row['bootstrap']['status'] == row['recovery']['status'] == 'pass'
            assert row['bootstrap']['epoch'] == row['recovery']['epoch'] == 1
            assert row['bootstrap']['digest'] == row['recovery']['digest']

        expected_profiles = [f'PAIRED-H-{n}-{ordinal}-{arm}.json' for n in (4096, 1000000)
                             for ordinal, arm in enumerate(('base', 'packet', 'packet', 'base'), 1)]
        assert [r['file'] for r in study['HConcurrentProfiles']] == expected_profiles
        profile_references, measured = {}, []
        for meta in study['HConcurrentProfiles']:
            path = raw / meta['file']
            assert sha(path) == meta['sha256'] and not path.with_name(path.stem + '.stderr.txt').read_text()
            row = json.loads(path.read_text())
            count = meta['assets']
            assert row['status'] == 'diagnostic' and row['acceptance'] is False
            assert row['variant'] == 'H' and row['assets'] == count
            assert row['cAllocationPositiveControl'] > 0 and row['swiftAllocationPositiveControl'] > 0
            assert row['fixture']['deadline'] == 'none' and row['fixture']['budget'] == 1024 and row['fixture']['workBudget'] == 65536
            assert [p['order'] for p in row['pairs']] == [['no-save', 'save'], ['save', 'no-save']][:1 if count == 4096 else 2]
            observations = [paired.verify_pair(p, row['fixture'], count) for p in row['pairs']]
            assert observations == meta['pairs']
            exact = {'fixture': row['fixture'], 'legs': [{'label': leg['label'], 'finalDigest': leg['finalDigest'],
                     'outputHash': leg['outputHash'], 'calls': [{k: c[k] for k in paired.TRANSCRIPT} for c in leg['calls']]}
                     for p in row['pairs'] for leg in p['legs']]}
            if count in profile_references:
                assert exact == profile_references[count]
            else:
                profile_references[count] = exact
            capacities = [leg['postProfileOwnedBytes'] for p in row['pairs'] for leg in p['legs']]
            assert capacities == meta['postProfileOwnedBytes'] and all(type(n) is int and n > 0 for n in capacities)
            if count == 1000000:
                assert all(n == 210772320 for n in capacities)
            measured.append((meta, observations))
        summaries = {}
        for count in (4096, 1000000):
            arms = {}
            for arm in ('base', 'packet'):
                observations = [pair for meta, pairs in measured if meta['assets'] == count and meta['arm'] == arm for pair in pairs]
                arms[arm] = {'advanceSaveNS': [p['components']['advance']['save']['ns'] for p in observations],
                             'advanceControlNS': [p['components']['advance']['control']['ns'] for p in observations],
                             'matchedAllAdvanceDeltaNS': [p['components']['advance']['deltaNS'] for p in observations],
                             'fullLoopDeltaNS': [p['fullLoop']['saveNS'] - p['fullLoop']['controlNS'] for p in observations],
                             'writerRunNS': [p['writer']['runNS'] for p in observations],
                             'writerRequestedBytes': [p['writer']['allocationBytes'] for p in observations],
                             'saveActiveMatchedRatios': [r['diagnosticMatchedRatio'] for p in observations for r in p['matchedPhases'] if r['mode'] == 'saveActive']}
                arms[arm]['medians'] = {k: statistics.median(v) for k, v in arms[arm].items() if isinstance(v, list)}
            summaries[str(count)] = arms
        held_medians = {arm: statistics.median(n for meta, row in held if meta['arm'] == arm for n in meta['writerNS']) for arm in ('base', 'packet')}
        assert held_medians == study['medianWriterNS']
        assert held_medians['packet'] / held_medians['base'] == study['diagnosticPacketToBaseRatio']
        proof = dict(status='diagnostic-verified', acceptance=False, source=args.source, tree=args.tree,
                     run=args.run, artifact=args.artifact, zipSHA256=args.sha256, runtimeInputs=42,
                     canonicalCases=16, epochs=48, lifecycleCases=12, limitedK3Cases=12,
                     K3Scope='source-bound SIGKILL harness assertion plus raw bootstrap/recovery equality; not full K1-K10',
                     heldH100kMedianWriterNS=held_medians, HConcurrentABBA=summaries,
                     C100='NOT_RUN', CPerformance={'S': 'OPEN', 'H': 'OPEN'},
                     memory='NOT_FIXED: H1M main-world owned210772320B excludes allocator/other worlds/UI/physical footprint',
                     limitations=['Nested/outer ABBA samples are bounded; paired ratios never replace C.',
                                  'All-call paired deltas avoid choosing a favorable asynchronous save-active interval.',
                                  'Writer and simulation wall times overlap; do not add them.'],
                     evidenceSHA256={str(p.relative_to(raw)): sha(p) for p in sorted(raw.rglob('*')) if p.is_file()})
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(proof, indent=2) + '\n')
        shutil.copyfile(args.archive, args.output.with_name(f'{args.run}-r005-writer-io-study.zip'))
        return proof


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    for field in ('sha256', 'source', 'tree'):
        parser.add_argument('--' + field, required=True)
    for field in ('run', 'artifact'):
        parser.add_argument('--' + field, required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    result = verify(parser.parse_args())
    print(json.dumps({k: result[k] for k in ('status', 'canonicalCases', 'epochs', 'lifecycleCases', 'limitedK3Cases', 'heldH100kMedianWriterNS', 'HConcurrentABBA')}, indent=2))
