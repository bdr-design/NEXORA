"""Verify a complete parallel ZIP against an independently verified base.

This offline verifier cannot launch a measurement or classify C as accepted.
Run from the repository root; --base-proof names the already verified base JSON.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from candidate_proof_inputs import functional_summary, manifest, quotas
from proof_gates import stage_a_failures
from stage005_c_crash import POINTS


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    a = argparse.ArgumentParser()
    a.add_argument('zip', type=Path)
    a.add_argument('--sha256', required=True)
    a.add_argument('--source', required=True)
    a.add_argument('--tree', required=True)
    a.add_argument('--run', required=True, type=int)
    a.add_argument('--artifact', required=True, type=int)
    a.add_argument('--base-proof', required=True, type=Path)
    a.add_argument('--output', required=True, type=Path)
    args = a.parse_args()
    assert digest(args.zip) == args.sha256
    base = json.loads(args.base_proof.read_text())
    assert base['status'] == 'pass' and base['acceptance'] is False
    assert (base['source'], base['tree'], base['run']) == (args.source, args.tree, args.run)
    assert (base['runtimeInputs'], base['boundedCases'], base['boundedEpochs'],
            base['canonicalComparisons'], base['lifecycleCases']) == (42, 44, 132, 32, 6)
    with tempfile.TemporaryDirectory(prefix='nxr-source-verification-') as temp:
        p = Path(temp)
        with ZipFile(args.zip) as z:
            assert len(z.namelist()) == len(set(z.namelist()))
            assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
            assert sum(f.file_size for f in z.infolist()) < 64 * 1024 * 1024
            z.extractall(p)
        # Every previously verified A/B/bounded byte must survive aggregation.
        for name, sha in base['evidenceSHA256'].items():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts
            assert digest(p / name) == sha, name
        for prefix in ('', 'aggregate-'):
            assert (p / f'{prefix}commit.txt').read_text().strip() == args.source
            assert (p / f'{prefix}tree.txt').read_text().strip() == args.tree
        inputs = manifest()
        assert len(inputs['paths']) == 42
        for name in ('runtime-inputs.json', 'aggregate-runtime-inputs.json'):
            assert json.loads((p / name).read_text()) == inputs
        expected = {f'k-meta-{m}-{v}' for m in ('debug', 'release', 'tsan') for v in ('S', 'H')}
        assert {q.name for q in p.glob('k-meta-*')} == expected
        for mode in ('debug', 'release', 'tsan'):
            for variant in ('S', 'H'):
                q = p / f'k-meta-{mode}-{variant}'
                assert (q / 'commit.txt').read_text().strip() == args.source
                assert (q / 'tree.txt').read_text().strip() == args.tree
                assert json.loads((q / 'runtime-inputs.json').read_text()) == inputs
                assert json.loads((q / 'build-flags.json').read_text()) == dict(
                    mode=mode, variant=variant, flags=['STAGE_C', 'EPOCH_PAGES'],
                    threadSanitizer=mode == 'tsan', population=1000000, C100='NOT_RUN')
                for phase in ('before', 'after'):
                    assert 'PASS baseline' in (q / f'source-guard-{phase}.txt').read_text()
                lines = {line.split('  ', 1)[1]: line.split('  ', 1)[0]
                         for line in (q / 'source-sha256.txt').read_text().splitlines()}
                assert set(lines) == {n for n in inputs['paths'] if '/Sources/' in n}
                assert all(inputs['paths'][n] == sha for n, sha in lines.items())
                kills = json.loads((p / f'KILLS-1M-{mode}-{variant}.json').read_text())
                assert [r['point'] for r in kills['results']] == [point for point, _ in POINTS]
                for row, (_, epoch) in zip(kills['results'], POINTS):
                    assert row['expectedEpoch'] == row['restoredEpoch'] == epoch
                assert kills['chainFallback']['point'] == 'c.chain.after_wal'
                assert kills['chainFallback']['signal'] == 'SIGKILL'
                assert kills['chainFallback']['baseSnapshotEpoch'] == 1
                assert kills['chainFallback']['replayedThroughWAL'] == 2
        arow = json.loads((p / 'STAGE005-A.json').read_text())
        assert arow['status'] == 'pass' and not arow['gateFailures']
        assert not stage_a_failures(arow['A'], arow['health'])
        assert arow['decisionA'] == base['sourceDecisionA']
        assert json.loads((p / 'B-QUOTA.json').read_text()) == quotas(
            p / 'STAGE005-B.json', p / 'SNAPSHOT-1M-CHOSEN.json')
        stored = json.loads((p / 'SOURCE-FUNCTIONAL-PROOF.json').read_text())
        assert stored == functional_summary(p)
        parts = json.loads((p / 'parallel-part-proof.json').read_text())
        assert parts['status'] == 'pass' and parts['C100'] == 'NOT_RUN'
        assert (parts['source'], parts['tree'], set(parts['parts'])) == (args.source, args.tree, expected)
        proof = dict(status='pass', acceptance=False, source=args.source, tree=args.tree,
                     run=args.run, artifact=args.artifact, zipSHA256=args.sha256,
                     requiredParts=sorted(expected), runtimeInputs=42,
                     baseProofSHA256=digest(args.base_proof), verifiedBaseArtifact=base['artifact'],
                     sourceDecisionA=arow['decisionA'], ADecisionForC=base['ADecisionForC'],
                     boundedCases=44, boundedEpochs=132, canonicalComparisons=32, lifecycleCases=6,
                     functionalProof=stored, BQuota=json.loads((p / 'B-QUOTA.json').read_text()),
                     scope='source-bound A/B and complete Debug/Release/TSan S/H1M K/WAL proof; no C acceptance',
                     C100='NOT_RUN', CPerformance={'S': 'OPEN', 'H': 'OPEN'},
                     physicalMemoryAndDeviceSmoothness='NOT_PROVED',
                     evidenceSHA256={str(r.relative_to(p)): digest(r)
                                     for r in sorted(p.rglob('*')) if r.is_file()})
    args.output.write_text(json.dumps(proof, indent=2) + '\n')
    shutil.copyfile(args.zip, args.output.with_name(f'{args.run}-r005-paged-source-proof.zip'))
    print(json.dumps({k: proof[k] for k in ('status', 'source', 'zipSHA256', 'sourceDecisionA',
                                          'boundedCases', 'functionalProof', 'BQuota')}, indent=2))


if __name__ == '__main__':
    main()
