import copy
import json
from pathlib import Path
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from verify_epoch_micro import verify


class EpochObservationTests(unittest.TestCase):
    def fixture(self, mode='release'):
        # Old raw results lacked availability fields; their source required the
        # observer. Add those flags solely to this validation test fixture.
        with zipfile.ZipFile(ROOT / 'Evidence/20261007/37537195946-r005-epoch-pages-micro.zip') as archive:
            d = json.loads(archive.read(f'EPOCH-4096-{mode}.json'))
        d.update(allocatorRequired=True, allocationObserverAvailable=True)
        for leg in d['legs']:
            leg['setupAllocationAvailable'] = True
            for epoch in leg['epochs']:
                for prefix in ('begin', 'mutation', 'writer', 'writerSetup', 'release'):
                    if prefix + 'Allocations' in epoch:
                        epoch[prefix + 'AllocationAvailable'] = True
        return d

    def test_release_zero_and_debug_observations_stay_distinct(self):
        self.assertEqual(verify(self.fixture())['releaseAllocationGate'], 'verified-zero')
        debug = self.fixture('debug')
        with self.assertRaises(ValueError):
            verify(debug)
        self.assertIsNone(verify(debug, 'observe')['releaseAllocationGate'])

    def test_zero_counter_without_observer_is_rejected(self):
        d = self.fixture()
        d['legs'][0]['epochs'][0]['mutationAllocationAvailable'] = False
        with self.assertRaises(ValueError):
            verify(d)

    def test_functional_null_counters_can_never_claim_zero_allocations(self):
        d = self.fixture()
        d.update(allocatorRequired=False, allocationObserverAvailable=False,
                 cAllocationPositiveControl=None, swiftAllocationPositiveControl=None)
        for leg in d['legs']:
            leg.update(setupAllocationAvailable=False, setupAllocations=None, setupAllocationBytes=None)
            for epoch in leg['epochs']:
                for prefix in ('begin', 'mutation', 'writer', 'writerSetup', 'release'):
                    if prefix + 'Allocations' in epoch:
                        epoch[prefix + 'AllocationAvailable'] = False
                        epoch[prefix + 'Allocations'] = None
                        epoch[prefix + 'AllocationBytes'] = None
        self.assertIsNone(verify(d, 'functional')['releaseAllocationGate'])
        with self.assertRaises(ValueError):
            verify(d)
        bad = copy.deepcopy(d)
        bad['legs'][0]['epochs'][0]['mutationAllocations'] = 0
        with self.assertRaises(ValueError):
            verify(bad, 'functional')


if __name__ == '__main__':
    unittest.main()
