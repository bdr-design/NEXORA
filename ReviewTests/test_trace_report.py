"""Synthetic trace-protocol rejection tests; no performance observations."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from test_financial_diagnostics import raw_fixture, sample
import trace_report


def fixture():
    counters=copy.deepcopy(raw_fixture()[0]); counters.update(warmups=3,repetitions=1)
    meta={'kind':'traceMetadata','schema':'NXR-R004-CAUSAL-1','sourceBase':trace_report.BASE,
        'sourceCommit':counters['sourceCommit'],'aircraft':20000,'repetitions':1,'warmups':3,
        'processID':counters['processID'],'os':counters['os'],'profileLabel':'unprofiled',
        'counters':counters,'limitations':['SYNTHETIC validation fixture, not a measurement']}
    rows=[meta]
    for marked in (False,True):
        rows.append({'kind':'traceCalibration','marked':marked,'loopNS':2000,'samplesNS':[0]*2000,
                     'begins':2000 if marked else 0,'ends':2000 if marked else 0})
    for world in range(1,5):
        order=(False,True) if world%2==0 else (True,False)
        for position,marked in enumerate(order):
            data=sample(20000,'counters',position,1);data.update(sample=world,warmup=world<=3)
            for row in data['records']:row['sample']=world
            rows.append({'kind':'traceSample','marked':marked,'world':world,'fixture':data,
                'begins':len(data['records']) if marked else 0,'ends':len(data['records']) if marked else 0})
    rows.append({'kind':'traceComplete','status':'all-fixture-checks-passed'})
    return rows


class TraceProtocolTests(unittest.TestCase):
    def run_rows(self,rows):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'synthetic.ndjson';p.write_text(''.join(json.dumps(row)+'\n' for row in rows))
            return trace_report.analyze(p)

    def reject(self,mutate):
        rows=fixture();mutate(rows)
        with self.assertRaises(ValueError):self.run_rows(rows)

    def test_complete_control(self):
        result=self.run_rows(fixture())
        self.assertEqual(sum(r['wallNS']['count'] for r in result['batches']),474)
        self.assertEqual(result['spikesAbove1ms'],[])

    def test_missing_complete(self):self.reject(lambda r:r.pop())
    def test_failed_completion(self):self.reject(lambda r:r[-1].update(status='failed'))
    def test_wrong_base(self):self.reject(lambda r:r[0].update(sourceBase='0'*40))
    def test_inconsistent_counter_source(self):self.reject(lambda r:r[0]['counters'].update(sourceCommit='0'*40))
    def test_duplicate_world(self):self.reject(lambda r:r[5].update(world=1))
    def test_reordered_mark_modes(self):self.reject(lambda r:r[3].update(marked=False))
    def test_unpaired_marks(self):self.reject(lambda r:r[3].update(ends=0))
    def test_unknown_fields(self):self.reject(lambda r:r[3].update(extra=1))
    def test_changed_economics(self):self.reject(lambda r:r[3]['fixture']['aggregate'].update(cashMinor=0))
    def test_counter_unit_mismatch(self):self.reject(lambda r:r[0]['counters']['counterDefinitions'].update(threadCPUNS='cycles'))
    def test_negative_calibration(self):self.reject(lambda r:r[1]['samplesNS'].__setitem__(0,-1))
    def test_duplicate_calibration(self):self.reject(lambda r:r[2].update(marked=False))
    def test_missing_batch(self):self.reject(lambda r:r[3]['fixture']['records'].pop())
    def test_extra_world(self):self.reject(lambda r:r.insert(-1,copy.deepcopy(r[-2])))


if __name__=='__main__':unittest.main(verbosity=2)
