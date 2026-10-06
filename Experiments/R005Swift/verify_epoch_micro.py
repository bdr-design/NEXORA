#!/usr/bin/env python3
"""Validate the isolated ownership study; never evaluate Stage C performance."""
import json
import sys
import argparse
from pathlib import Path


def verify(value, allocation_policy='zero'):
    def check(condition, detail):
        if not condition:
            raise ValueError(detail)
    check(value['status'] == 'diagnostic' and value['acceptance'] is False, 'scope')
    check(value['assets'] in (4096, 100000), 'bounded assets')
    check(value['epochsPerLeg'] == 3 and value['writesPerAssetPerEpoch'] == 8, 'script')
    check(allocation_policy in ('zero', 'observe', 'functional'), 'allocation policy')
    if allocation_policy == 'functional':
        check(value['allocatorRequired'] is False and
              value['allocationObserverAvailable'] is False and
              value['cAllocationPositiveControl'] is None and
              value['swiftAllocationPositiveControl'] is None, 'functional scope must disclose unavailable allocator')
    else:
        check(value['allocatorRequired'] is True and
              value['allocationObserverAvailable'] is True and
              value['cAllocationPositiveControl'] > 0 and
              value['swiftAllocationPositiveControl'] > 0, 'allocator calibration')

    def allocations(observation, prefixes, require_zero=True):
        for prefix in prefixes:
            available = observation[prefix + 'AllocationAvailable']
            fields = (prefix + 'Allocations', prefix + 'AllocationBytes')
            if allocation_policy == 'functional':
                check(available is False and all(observation[f] is None for f in fields),
                      f'unavailable {prefix} allocation must be null, never zero')
            else:
                check(available is True, f'{prefix} allocator missing')
                check(all(type(observation[f]) is int and observation[f] >= 0 for f in fields),
                      f'{prefix} counters malformed')
                if allocation_policy == 'zero' and require_zero:
                    check(all(observation[f] == 0 for f in fields),
                          f'preallocated Release micro unexpectedly allocates: {prefix}')
    check(value['rowStride'] == 72 and value['packedBytesPerAsset'] == 65, 'row/SoA size')
    expected = [(rep, mode) for mode in ('none', 'direct', 'paced', 'none')
                for rep in ('rows', 'packedSoA')]
    check([(leg['representation'], leg['writerMode']) for leg in value['legs']] == expected,
          'control/direct/paced/control coverage')
    pages = (value['assets'] + 255) // 256
    leaves = (pages + 63) // 64
    for leg in value['legs']:
        check(len(leg['epochs']) == 3, 'three epochs')
        allocations(leg, ('setup',), require_zero=False)
        for index, epoch in enumerate(leg['epochs']):
            check(epoch['epoch'] == index + 1 and epoch['liveExact'] is True, 'live epoch')
            check(epoch['liveDigest'] == value['references'][index + 1], 'live digest')
            allocations(epoch, ('mutation',))
            if leg['writerMode'] == 'none':
                continue
            check(epoch['frozenExact'] is True and epoch['writerDigest'] ==
                  value['references'][index], 'immutable writer digest')
            check(epoch['overlapRejected'] and epoch['prematureReleaseRejected'], 'lifecycle')
            allocations(epoch, ('begin', 'release'))
            allocations(epoch, ('writer', 'writerSetup'), require_zero=False)
            check(epoch['clonePages'] == pages and epoch['rootCopies'] == 1 and
                  epoch['leafCopies'] == leaves, 'first-write coverage')
            stride = 72 if leg['representation'] == 'rows' else 65
            check(epoch['cloneBytes'] == value['assets'] * stride, 'copy budget')
            check(epoch['writerBytes'] == value['assets'] * 65 + pages * 48, 'wire budget')
            check(epoch['writerSleepNS'] == 0 if leg['writerMode'] == 'direct'
                  else epoch['writerSleepNS'] > 0, 'explicit writer pacing')
    return {'status': 'micro-ownership-verified', 'acceptance': False,
            'assets': value['assets'], 'legs': len(value['legs']),
            'allocationPolicy': allocation_policy,
            'releaseAllocationGate': 'verified-zero' if allocation_policy == 'zero' else None,
            'Cacceptance': 'OPEN independently on S and H'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allocation-policy', choices=('zero', 'observe', 'functional'), default='zero')
    parser.add_argument('files', nargs='+')
    args = parser.parse_args()
    for name in args.files:
        print(json.dumps({'file': name, **verify(json.loads(Path(name).read_text()), args.allocation_policy)}))
