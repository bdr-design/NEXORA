#!/usr/bin/env python3
"""Reanalyze pinned prior Apple evidence; this is NOT a new performance run."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    'batches-1.ndjson': '2bbbad1b01fbbd209381f745c027f8378ee572c96780fe11622721b45e48a6ad',
    'batches-2.ndjson': '4c24716e43d109ce00aea143133a97dba3868a390f4cf5e3f56ef57fe8cb9465',
    'batches-3.ndjson': '55349eb527df1d1ae5dbab37d61131cc5df9a8fe7e44480922db6782f0bc502f',
    'batch-summary.json': 'cacb2a57f19b5921d0fac993ae6f7b785df9f83836e59a5442bb1a2563aa6567',
    'NEXORA_R004_DIAGNOSTIC_SOURCE.zip': 'cf171610aea628944235d6072fb09fa4878b5370859eebafd1436af0d7dc24bc',
}


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: revalidate_apple.py PRIOR_EVIDENCE_DIR OUTPUT_JSON')
    prior, output = map(Path, sys.argv[1:])
    for name, wanted in EXPECTED.items():
        digest = hashlib.sha256()
        with (prior / name).open('rb') as reader:
            for block in iter(lambda: reader.read(1 << 20), b''):
                digest.update(block)
        if digest.hexdigest() != wanted:
            raise ValueError('prior evidence hash mismatch: ' + name)
    spec = importlib.util.spec_from_file_location('financial_diagnostics', ROOT / 'Checks/financial-diagnostics.py')
    analyzer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyzer)
    result = analyzer.analyze([prior / ('batches-%d.ndjson' % n) for n in (1, 2, 3)])
    measured = sum(row['wallNS']['count'] for row in result['batchDistributions'])
    if measured != 372_600:
        raise ValueError('changed measured batch count')
    data = (json.dumps(result, indent=2, sort_keys=True) + '\n').encode('utf-8')
    if data != (prior / 'batch-summary.json').read_bytes():
        raise ValueError('summary differs from pinned original Apple report')
    output.write_bytes(data)
    print('PASS pinned Apple run 36692367500: 372600 measured records; summary byte-identical')
    print('Reanalysis only; no new performance, device or causal evidence.')


if __name__ == '__main__':
    main()
