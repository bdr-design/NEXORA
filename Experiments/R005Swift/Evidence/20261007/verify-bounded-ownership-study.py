"""Independently verify the disposable bounded cold-ownership Apple artifact."""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile

if not __debug__:
    raise RuntimeError('bounded ownership verifier requires Python assertions')

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).parent
sys.path.insert(0, str(ROOT / 'Experiments/R005Swift'))
from candidate_proof_inputs import manifest

REQUIRED_INVARIANTS = {
    'atomicBeginPublish', 'reserveAllBeforePayloadControlWAL', 'ownerTryOnceNoWait',
    'writerIOOutsideGate', 'boundedScratchWriteBeforePrefix', 'writerFailurePoisonsEpoch',
    'exclusiveFlatSnapshotDirectory', 'retireFrameBeforeReleasePrefix',
    'acquirePrefixBeforeCredit', 'memoryReclaimSeparateFromCommit', 'canonicalCold20Bytes'
}
ALLOWED_STUDY_INPUTS = {
    '.github/workflows/r005-bounded-epoch-micro.yml',
    'Checks/financial-diagnostics.py',
    'Experiments/R005Swift/Evidence/20261007/BoundedEpochOwnershipMicro.swift',
    'Experiments/R005Swift/Evidence/20261007/prepare-bounded-ownership-study.py',
    'Experiments/R005Swift/Evidence/20261007/verify-bounded-ownership-study.py'
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_extract(archive, destination):
    with ZipFile(archive) as zipped:
        assert len(zipped.infolist()) < 256
        assert sum(item.file_size for item in zipped.infolist()) < 96 * 1024 * 1024
        normalized = set()
        for item in zipped.infolist():
            path = PurePosixPath(item.filename)
            assert item.filename and '\\' not in item.filename
            assert not path.is_absolute() and '..' not in path.parts
            parts = tuple(part for part in path.parts if part not in ('', '.'))
            assert parts and parts not in normalized
            normalized.add(parts)
            assert (item.external_attr >> 16) & 0o170000 != 0o120000
        zipped.extractall(destination)


def validate_row(row, *, count, slots, policy):
    assert row['status'] == 'diagnostic-pass' and row['acceptance'] is False
    assert row['decision'] == 'MICRO_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE'
    assert row['integrationEligible'] is False
    assert row['assets'] == count and row['slots'] == slots and row['epochs'] == 3
    assert row['pageAssets'] == 256 and row['bytesPerAsset'] == 20 and row['fullPageBytes'] == 5120
    assert row['allocationPolicy'] == policy and row['C100'] == 'NOT_RUN'
    assert row['safeToRunH100k'] is (count <= 4096)
    assert row['safeToRunH1M'] is False and set(row['invariants']) == REQUIRED_INVARIANTS
    assert len(row['main']['epochs']) == 3
    assert row['main']['partialToFullSerialExact'] is (slots == 1)
    setup = row['main']['setup']
    assert type(setup['ns']) is int and setup['ns'] > 0
    if policy == 'functional':
        assert setup['allocationAvailable'] is False
        assert setup['allocations'] is None and setup['allocationBytes'] is None
    else:
        assert setup['allocationAvailable'] is True
        assert type(setup['allocations']) is int and setup['allocations'] > 0
        assert type(setup['allocationBytes']) is int and setup['allocationBytes'] > 0
    pages = (count + 255) // 256
    expected_writer_bytes = count * 20 + pages * 16
    for epoch, value in enumerate(row['main']['epochs'], 1):
        assert value['epoch'] == epoch
        assert value['recovered']['byteExact'] is True and value['recovered']['orderExact'] is True
        assert value['frozenDigest'] == value['recovered']['digest']
        assert value['recovered']['pages'] == pages
        assert value['state']['successfulCommits'] == epoch
        assert value['state']['writerPoisoned'] is False
        assert all(value['state']['slotReady'])
        assert all(type(capacity) is int and 640 <= capacity <= 1280
                   for capacity in value['state']['slotWordCapacities'])
        assert all(type(capacity) is int and 640 <= capacity <= 1280
                   for capacity in value['state']['liveWordCapacities'])
        for field in ('writerSetupNS', 'writerCallWallNS', 'writerBuildNS',
                      'writerSinkNS', 'serviceNS', 'runtimeLoopNS'):
            assert type(value[field]) is int and value[field] > 0, (field, value[field])
        assert value['writerBuildNS'] <= value['writerCallWallNS'] <= value['runtimeLoopNS']
        assert value['writerSinkNS'] <= value['writerCallWallNS']
        assert value['serviceNS'] <= value['runtimeLoopNS']
        assert value['writerBytes'] == expected_writer_bytes
        assert 5136 <= value['writerScratchCapacityBytes'] <= 10240
        if epoch == 1:
            assert value['writerAliasHeldDuringKPressure'] is True
            assert type(value['heldWriterWallNS']) is int and value['heldWriterWallNS'] > 0
            assert value['kPressureOutcome'] == ('writerReading' if slots == 1 else 'capacity')
            assert value['ownerGateBusyNS'] is None
        elif epoch == 2:
            assert value['writerAliasHeldDuringKPressure'] is None
            assert value['heldWriterWallNS'] is None and value['kPressureOutcome'] is None
            assert value['ownerGateBusyNS'] is None
        else:
            assert value['writerAliasHeldDuringKPressure'] is None
            assert type(value['heldWriterWallNS']) is int and value['heldWriterWallNS'] > 0
            assert value['kPressureOutcome'] is None
            assert type(value['ownerGateBusyNS']) is int
            assert 0 < value['ownerGateBusyNS'] < 50_000_000
    memory = row['main']['memory']
    assert memory['fullPageCapacityBytes'] == 5120
    assert pages * 5120 <= memory['livePayloadCapacityBytes'] <= pages * 10240
    assert slots * 5120 <= memory['slotPayloadCapacityBytes'] <= slots * 10240
    assert 0 < memory['directoryReferenceBytes'] <= pages * 32
    assert 0 < memory['pageMapBytes'] <= pages * 8
    assert 0 < memory['slotRecordBytes'] <= slots * 128
    assert 0 < memory['commandScratchBytes'] <= max(8, slots + 1) * 16
    assert memory['pageWrapperCount'] == pages + slots
    assert memory['pageWrapperAllowanceBytes'] == (pages + slots) * 64
    assert memory['storeControlAllowanceBytes'] == 512
    assert memory['atomicControlAllowanceBytes'] == 192
    components = ('livePayloadCapacityBytes', 'slotPayloadCapacityBytes',
                  'directoryReferenceBytes', 'pageMapBytes', 'slotRecordBytes',
                  'commandScratchBytes', 'pageWrapperAllowanceBytes',
                  'storeControlAllowanceBytes', 'atomicControlAllowanceBytes')
    assert memory['declaredBytesExcludingAllocatorHeaders'] == sum(memory[key] for key in components)
    tail = count - (pages - 1) * 256
    assert memory['tailElements'] == tail
    assert memory['tailCanonicalBytes'] == tail * 20
    assert memory['tailPhysicalWordBytes'] == ((tail * 20 + 7) // 8) * 8
    assert memory['pageReferenceStride'] == 8
    assert 0 < memory['slotRecordStride'] <= 64
    expected_negative = {
        'reservedUnpublishedCancel', 'publishedCancel', 'publishedCancelAfterMutation',
        'contendedBeginLeavesIdle', 'injectedWriterFailure', 'failureNotCommit',
        'writerFailurePoisonsEpoch', 'writerPoisonResetOnNextEpoch',
        'aliasHeldBlockedTerminal',
        'terminalReplayRejected', 'epochOverflowRejected'
    }
    assert all(row['negative'][key] is True for key in expected_negative)
    assert row['negative']['partialWriterRecordsBeforeFailure'] == 1
    labels = [sample['label'] for sample in row['allocationSamples']]
    assert {'epoch1-reserve-reject', 'epoch1-reserve-copy', 'epoch1-prefix-service',
            'epoch1-held-k-pressure-reject', 'epoch1-prefix-credit-service',
            'epoch3-owner-gate-busy-reject',
            'epoch2-partial-to-full-copy', 'epoch3-prefix-in-place',
            'failure-alias-reclaim'}.issubset(set(labels))
    assert labels.count('epoch1-held-k-pressure-reject') == 1
    assert labels.count('epoch1-prefix-credit-service') == 1
    assert labels.count('epoch3-owner-gate-busy-reject') == 1
    if policy == 'functional':
        assert row['allocationObserverAvailable'] is False
        assert row['cAllocationPositiveControl'] is None and row['swiftAllocationPositiveControl'] is None
        for sample in row['allocationSamples']:
            assert type(sample['ns']) is int and sample['ns'] > 0
            assert sample['allocationAvailable'] is False
            assert sample['allocations'] is None and sample['allocationBytes'] is None
    else:
        assert row['allocationObserverAvailable'] is True
        assert type(row['cAllocationPositiveControl']) is int and row['cAllocationPositiveControl'] > 0
        assert type(row['swiftAllocationPositiveControl']) is int and row['swiftAllocationPositiveControl'] > 0
        for sample in row['allocationSamples']:
            assert type(sample['ns']) is int and sample['ns'] > 0
            assert sample['allocationAvailable'] is True
            assert type(sample['allocations']) is int and type(sample['allocationBytes']) is int
            if policy == 'zero':
                assert sample['allocations'] == sample['allocationBytes'] == 0
    return [(value['frozenDigest'], value['liveDigest'], value['recovered']['digest'])
            for value in row['main']['epochs']]


def verify(args):
    assert sha(args.archive) == args.sha256
    with tempfile.TemporaryDirectory(prefix='nxr-bounded-ownership-verify-') as temporary:
        scratch = Path(temporary)
        raw = scratch / 'raw'
        safe_extract(args.archive, raw)
        assert (raw / 'commit.txt').read_text().strip() == args.source
        assert (raw / 'tree.txt').read_text().strip() == args.tree
        inputs = json.loads((raw / 'runtime-inputs.json').read_text())
        assert inputs == manifest() and len(inputs['paths']) == 42
        for phase in ('before', 'after'):
            assert 'PASS baseline' in (raw / f'source-guard-{phase}.txt').read_text()
        for mode in ('debug', 'release', 'tsan'):
            assert 'Build complete!' in (raw / f'build-{mode}.txt').read_text()

        study_inputs = {}
        for line in (raw / 'study-input-sha256.txt').read_text().splitlines():
            digest, name = line.split(None, 1)
            name = name.strip()
            assert name in ALLOWED_STUDY_INPUTS and name not in study_inputs
            assert len(digest) == 64 and all(character in '0123456789abcdef' for character in digest)
            study_inputs[name] = digest
        assert set(study_inputs) == ALLOWED_STUDY_INPUTS
        for name, digest in study_inputs.items():
            path = ROOT / name
            assert path.is_file() and sha(path) == digest

        sources = json.loads((raw / 'study-source.json').read_text())
        actual = ROOT / 'Experiments/R005Swift/Sources'
        package = scratch / '.bounded-ownership-study/current'
        shutil.copytree(actual, package / 'Sources')
        subprocess.run([sys.executable, '-B', str(HERE / 'prepare-bounded-ownership-study.py'), str(package)],
                       check=True)
        actual_files = {str(path.relative_to(actual)): sha(path)
                        for path in sorted(actual.rglob('*')) if path.is_file()}
        temporary_files = {str(path.relative_to(package / 'Sources')): sha(path)
                           for path in sorted((package / 'Sources').rglob('*')) if path.is_file()}
        assert sources == {'actual': actual_files, 'temporary': temporary_files,
                           'changed': ['SwiftProbe/Main.swift'],
                           'added': ['SwiftProbe/BoundedEpochOwnershipMicro.swift']}
        assert len(actual_files) == 24
        assert all(inputs['paths']['Experiments/R005Swift/Sources/' + name] == digest
                   for name, digest in actual_files.items())

        raw_manifest = json.loads((raw / 'RAW-MANIFEST.json').read_text())['files']
        evidence_files = {str(path.relative_to(raw)): sha(path)
                          for path in sorted(raw.rglob('*'))
                          if path.is_file() and path.name != 'RAW-MANIFEST.json'}
        assert raw_manifest == evidence_files

        report = json.loads((raw / 'BOUNDED-OWNERSHIP-STUDY.json').read_text())
        assert report['status'] == 'diagnostic-verified' and report['acceptance'] is False
        assert report['decision'] == 'MICRO_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE'
        assert report['integrationEligible'] is False
        assert report['smallGateCases'] == 6 and report['scaledCases'] == 1
        assert report['safeToRunH100k'] is True and report['safeToRunH1M'] is False
        assert report['H1M'] == report['C5'] == report['C100'] == 'NOT_RUN'
        assert report['fullH'] == 'NOT_MEASURED'
        assert report['fullHMemoryVerdict'] == 'NOT_FIXED'
        assert report['actualRuntimeInputsUnchanged'] is True
        assert 'NOT_MEASURED_FULL_H' in report['memoryVerdict']
        assert 'NOT_FIXED' in report['memoryVerdict']
        expected = [(mode, count, slots, policy)
                    for mode, policy in (('debug', 'observe'), ('release', 'zero'), ('tsan', 'functional'))
                    for count, slots in ((257, 1), (4096, 2))]
        expected.append(('release', 100000, 2, 'zero'))
        expected_rows = [(mode, count, slots, policy, f'{mode}-{count}-K{slots}.json')
                         for mode, count, slots, policy in expected]
        assert [(row['mode'], row['assets'], row['slots'], row['policy'], row['file'])
                for row in report['rows']] == expected_rows
        references = {}
        for metadata in report['rows']:
            path = raw / metadata['file']
            assert sha(path) == metadata['sha256']
            assert not path.with_name(path.stem + '.stderr.txt').read_text()
            row = json.loads(path.read_text())
            exact = validate_row(row, count=metadata['assets'], slots=metadata['slots'],
                                 policy=metadata['policy'])
            count = metadata['assets']
            if count in references:
                assert references[count] == exact
            else:
                references[count] = exact

        proof = {
            'status': 'diagnostic-verified', 'acceptance': False,
            'decision': 'MICRO_PROTOCOL_PASS_NOT_INTEGRATION_ELIGIBLE',
            'integrationEligible': False,
            'source': args.source, 'tree': args.tree, 'run': args.run,
            'artifact': args.artifact, 'zipSHA256': args.sha256,
            'runtimeInputs': 42, 'smallGateCases': 6, 'scaledCases': 1,
            'smallGate': 'Debug/Release/TSan x 257/K1 and4096/K2 PASS',
            'scale': 'Release100k/K2 diagnostic PASS; H1M NOT_RUN',
            'C100': 'NOT_RUN', 'CPerformance': {'S': 'OPEN', 'H': 'OPEN'},
            'memory': 'NOT_FIXED / NOT_MEASURED_FULL_H: artifact measures bounded small/100k components only; preflight H1M arithmetic remains above128 target',
            'limitations': report['limitations'],
            'evidenceSHA256': evidence_files
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(proof, indent=2) + '\n')
        shutil.copyfile(args.archive, args.output.with_name(f'{args.run}-r005-bounded-epoch-ownership-micro.zip'))
        return proof


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    for field in ('sha256', 'source', 'tree'):
        parser.add_argument('--' + field, required=True)
    for field in ('run', 'artifact'):
        parser.add_argument('--' + field, required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    proof = verify(parser.parse_args())
    print(json.dumps({key: proof[key] for key in
                      ('status', 'decision', 'smallGateCases', 'scaledCases', 'scale', 'C100', 'memory')}, indent=2))
