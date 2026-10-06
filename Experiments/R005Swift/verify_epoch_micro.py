#!/usr/bin/env python3
"""Validate the isolated ownership study; never evaluate Stage C performance."""
import json
import sys
from pathlib import Path


def verify(value):
    def check(condition, detail):
        if not condition:
            raise ValueError(detail)
    check(value['status'] == 'diagnostic' and value['acceptance'] is False, 'scope')
    check(value['assets'] in (4096, 100000), 'bounded assets')
    check(value['epochsPerLeg'] == 3 and value['writesPerAssetPerEpoch'] == 8, 'script')
    check(value['cAllocationPositiveControl'] > 0 and
          value['swiftAllocationPositiveControl'] > 0, 'allocator calibration')
    check(value['rowStride'] == 72 and value['packedBytesPerAsset'] == 65, 'row/SoA size')
    expected = [(rep, mode) for mode in ('none', 'direct', 'paced', 'none')
                for rep in ('rows', 'packedSoA')]
    check([(leg['representation'], leg['writerMode']) for leg in value['legs']] == expected,
          'control/direct/paced/control coverage')
    pages = (value['assets'] + 255) // 256
    leaves = (pages + 63) // 64
    for leg in value['legs']:
        check(len(leg['epochs']) == 3, 'three epochs')
        for index, epoch in enumerate(leg['epochs']):
            check(epoch['epoch'] == index + 1 and epoch['liveExact'] is True, 'live epoch')
            check(epoch['liveDigest'] == value['references'][index + 1], 'live digest')
            for field in ('mutationAllocations', 'mutationAllocationBytes'):
                check(type(epoch[field]) is int and epoch[field] == 0,
                      f'preallocated micro unexpectedly allocates: {field}')
            if leg['writerMode'] == 'none':
                continue
            check(epoch['frozenExact'] is True and epoch['writerDigest'] ==
                  value['references'][index], 'immutable writer digest')
            check(epoch['overlapRejected'] and epoch['prematureReleaseRejected'], 'lifecycle')
            for field in ('beginAllocations', 'beginAllocationBytes',
                          'releaseAllocations', 'releaseAllocationBytes'):
                check(type(epoch[field]) is int and epoch[field] == 0,
                      f'preallocated micro unexpectedly allocates: {field}')
            check(epoch['clonePages'] == pages and epoch['rootCopies'] == 1 and
                  epoch['leafCopies'] == leaves, 'first-write coverage')
            stride = 72 if leg['representation'] == 'rows' else 65
            check(epoch['cloneBytes'] == value['assets'] * stride, 'copy budget')
            check(epoch['writerBytes'] == value['assets'] * 65 + pages * 48, 'wire budget')
            check(epoch['writerSleepNS'] == 0 if leg['writerMode'] == 'direct'
                  else epoch['writerSleepNS'] > 0, 'explicit writer pacing')
    return {'status': 'micro-ownership-verified', 'acceptance': False,
            'assets': value['assets'], 'legs': len(value['legs']),
            'Cacceptance': 'OPEN independently on S and H'}


if __name__ == '__main__':
    for name in sys.argv[1:]:
        print(json.dumps({'file': name, **verify(json.loads(Path(name).read_text()))}))
