import importlib.util, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('analysis',HERE/'analyze.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class CounterContractTests(unittest.TestCase):
    def test_zero_is_not_evidence(self):
        with self.assertRaises(ValueError):m.value({'status':'ok','value':0,'reason':'zero'})
    def test_absence_has_no_numeric_value(self):
        m.value({'status':'unsupported','reason':'zero policy'})
        with self.assertRaises(ValueError):m.value({'status':'unsupported','value':0,'reason':'zero policy'})
    def test_missing_reason_rejected(self):
        with self.assertRaises(ValueError):m.value({'status':'unsupported'})
    def test_same_instructions_do_not_prove_external_pause(self):
        self.assertEqual(m.classify(100,[90,110]),'within-peer-instruction-range; cause-unresolved')
    def test_growth_requires_attribution(self):
        self.assertEqual(m.classify(150,[90,100]),'instruction-growth-observed; symbolized-profile-needed')
    def test_no_peers_no_verdict(self):
        self.assertEqual(m.classify(100,[]),'unavailable-or-no-comparable-peers')
    def test_unavailable_no_zero(self):
        self.assertEqual(m.classify(None,[100]),'unavailable-or-no-comparable-peers')
    def test_counter_decrease_is_invalid(self):
        self.assertIsNone(m.delta({'before':{'instructions':{'status':'ok','value':5}},'after':{'instructions':{'status':'ok','value':4}}},'instructions'))
    def test_observed_zero_delta_is_valid(self):
        self.assertEqual(m.delta({'before':{'instructions':{'status':'ok','value':5}},'after':{'instructions':{'status':'ok','value':5}}},'instructions'),0)
    def test_bool_is_not_count(self):
        with self.assertRaises(ValueError):m.uint(True)
    def test_large_count_rejected(self):
        with self.assertRaises(ValueError):m.uint(2**64)
    def test_unknown_status_rejected(self):
        with self.assertRaises(ValueError):m.value({'status':'assumed','reason':'x'})
if __name__=='__main__':unittest.main(verbosity=2)
