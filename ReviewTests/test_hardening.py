"""Strict schema/source regressions. All mutations are synthetic, isolated copies."""
import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from test_financial_diagnostics import diag, raw_fixture, first_sample


class SchemaHardeningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.control = raw_fixture()

    def analyze(self, rows, edit_text=None):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic.ndjson'
            text = ''.join(json.dumps(r, separators=(',', ':')) + '\n' for r in rows)
            if edit_text:
                text = edit_text(text)
            path.write_text(text)
            return diag.analyze([path])

    def reject(self, mutate):
        rows = copy.deepcopy(self.control)
        mutate(rows)
        with self.assertRaises(ValueError):
            self.analyze(rows)

    def test_every_metadata_field_is_required(self):
        for key in self.control[0]:
            with self.subTest(field=key):
                self.reject(lambda rows: rows[0].pop(key))

    def test_every_aggregate_field_is_required_in_every_mode(self):
        for mode in diag.MODES:
            for key in first_sample(self.control, mode)['aggregate']:
                with self.subTest(mode=mode, field=key):
                    self.reject(lambda rows: first_sample(rows, mode)['aggregate'].pop(key))

    def test_each_counter_definition_must_match_units_and_scope(self):
        for field in diag.FIELDS:
            with self.subTest(counter=field):
                self.reject(lambda rows: rows[0]['counterDefinitions'].__setitem__(field, 'wrong units; per-event'))

    def test_missing_counter_definition(self):
        self.reject(lambda rows: rows[0]['counterDefinitions'].pop('threadCPUNS'))

    def test_extra_counter_definition(self):
        self.reject(lambda rows: rows[0]['counterDefinitions'].update(unmeasuredCounter='ns'))

    def test_invalid_main_thread_type(self):
        self.reject(lambda rows: rows[0].update(mainThread='true'))

    def test_wrong_sample_indexing(self):
        self.reject(lambda rows: rows[0].update(sampleIndexing='0-based samples'))

    def test_float_world_size_rejected(self):
        self.reject(lambda rows: rows[0]['sizes'].__setitem__(0, 1000.0))

    def test_non_integer_economic_values_rejected(self):
        for field in diag.AGGREGATE_COUNTS + ('revenueMinor', 'cashMinor'):
            with self.subTest(field=field):
                self.reject(lambda rows: first_sample(rows)['aggregate'].__setitem__(field,
                    float(first_sample(rows)['aggregate'][field])))

    def test_unknown_top_level_field(self):
        self.reject(lambda rows: rows[3].update(extraUnvalidatedTiming=1))

    def test_unknown_aggregate_field(self):
        self.reject(lambda rows: first_sample(rows)['aggregate'].update(extraNS=0))

    def test_unknown_phase_field(self):
        self.reject(lambda rows: first_sample(rows)['phases'][0].update(extra=0))

    def test_unknown_batch_field(self):
        self.reject(lambda rows: first_sample(rows)['records'][0].update(extra=0))

    def test_unknown_snapshot_field(self):
        self.reject(lambda rows: first_sample(rows)['records'][0]['before'].update(extra=0))

    def test_duplicate_json_metadata_key(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            self.analyze(self.control, lambda text: text.replace('"runID":1', '"runID":99,"runID":1', 1))

    def test_duplicate_json_nested_counter_key(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            self.analyze(self.control, lambda text: text.replace('"threadCPUNS":0', '"threadCPUNS":9,"threadCPUNS":0', 1))

    def test_nonfinite_json_number(self):
        for token in ('NaN', 'Infinity', '-Infinity'):
            with self.subTest(token=token), self.assertRaisesRegex(ValueError, 'non-finite JSON'):
                self.analyze(self.control, lambda text: text.replace('"runID":1', '"runID":' + token, 1))

    def test_no_input_is_not_a_complete_report(self):
        with self.assertRaisesRegex(ValueError, 'no input'):
            diag.analyze([])

    def test_valid_exact_protocol_control(self):
        self.assertEqual(self.analyze(self.control)['status'], 'complete-raw-files-validated')


class SourceHardeningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'source'
        self.root.mkdir()
        for name in ('Sources', 'Tests', 'Checks'):
            shutil.copytree(diag.ROOT / name, self.root / name)
        for name in ('Package.swift', 'AGENTS.md', '.github/workflows/restart.yml'):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(diag.ROOT / name, p)

    def tearDown(self):
        self.tmp.cleanup()

    def guard(self):
        with patch.object(diag, 'ROOT', self.root):
            diag.source_guard()

    def test_valid_frozen_source_passes(self):
        self.guard()

    def test_compilable_file_under_python_cache_name_rejected(self):
        p = self.root / 'Sources/NexoraFinance/__pycache__/Sentinel.swift'
        p.parent.mkdir(); p.write_text('let auditSentinel = 1\n')
        with self.assertRaises(ValueError): self.guard()

    def test_cache_named_file_in_original_tests_rejected(self):
        p = self.root / 'Tests/NexoraFinanceTests/__pycache__'
        p.write_text('not an allowed source exclusion\n')
        with self.assertRaises(ValueError): self.guard()

    def test_extra_regular_source_rejected(self):
        (self.root / 'Sources/NexoraFinance/Extra.swift').write_text('let extra = 1\n')
        with self.assertRaises(ValueError): self.guard()

    def test_deleted_original_file_rejected(self):
        (self.root / 'Sources/NexoraFinance/FinanceStore.swift').unlink()
        with self.assertRaises((ValueError, FileNotFoundError)): self.guard()

    def test_changed_file_mode_rejected(self):
        p = self.root / 'Sources/NexoraFinance/FinanceStore.swift'
        p.chmod(0o755)
        with self.assertRaises(ValueError): self.guard()

    def test_symlink_to_identical_source_rejected(self):
        p = self.root / 'Sources/NexoraFinance/FinanceStore.swift'
        target = Path(self.tmp.name) / 'same.swift'; target.write_bytes(p.read_bytes())
        p.unlink(); p.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symlink'): self.guard()

    def test_directory_symlink_rejected(self):
        p = self.root / 'Sources/NexoraFinance'
        target = Path(self.tmp.name) / 'finance'; p.rename(target); p.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'): self.guard()

    def test_excluded_analyzer_itself_cannot_be_symlink(self):
        p = self.root / 'Checks/financial-diagnostics.py'
        target = Path(self.tmp.name) / 'same.py'; target.write_bytes(p.read_bytes())
        p.unlink(); p.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symlink'): self.guard()

    def test_python_cache_is_not_a_general_exemption(self):
        p = self.root / 'Checks/__pycache__/Extra.swift'
        p.parent.mkdir(); p.write_text('let extra = 1\n')
        with self.assertRaises(ValueError): self.guard()

    def test_business_prefix_changed_rejected(self):
        p = self.root / 'Sources/NexoraFinancialCheck/main.swift'
        p.write_text(p.read_text().replace('let initializing = clock.now', 'let initializing = clock.now // altered', 1))
        with self.assertRaises(ValueError): self.guard()


class OutputAndWorkflowTests(unittest.TestCase):
    def output_probe(self, raw_as_destination):
        with tempfile.TemporaryDirectory() as folder:
            raw = Path(folder) / "synthetic.ndjson"
            raw.write_text("".join(json.dumps(row) + "\n" for row in raw_fixture()))
            output = raw if raw_as_destination else Path(folder) / "existing.json"
            if not raw_as_destination: output.write_bytes(b"ORIGINAL REPORT\n")
            original = output.read_bytes()
            result = subprocess.run([sys.executable, "-B", str(diag.ROOT / "Checks/financial-diagnostics.py"),
                                     "--output", str(output), str(raw)], capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            self.assertIn(b"FileExistsError", result.stderr)

    def test_existing_summary_not_replaced(self):
        self.output_probe(False)

    def test_raw_input_cannot_be_overwritten_by_output(self):
        self.output_probe(True)

    def test_gate_has_no_path_filter(self):
        for name in ("r004-audit.yml", "r004-diagnostics.yml"):
            text = (diag.ROOT / ".github/workflows" / name).read_text()
            self.assertNotIn("    paths:", text)
            self.assertNotIn("    paths-ignore:", text)
        self.assertIn("fix/r004-evidence-hardening-20260930", text if name == "r004-audit.yml"
                      else (diag.ROOT / ".github/workflows/r004-audit.yml").read_text())

    def test_diagnostic_program_is_executed_from_sanitized_build(self):
        text = (diag.ROOT / ".github/workflows/r004-audit.yml").read_text()
        step = text.split("name: Fresh Apple Thread Sanitizer including the diagnostic executable", 1)[1].split("      - name:", 1)[0]
        self.assertIn("--sanitize=thread --product nexora-financial-check", step)
        self.assertIn("--sanitize=thread --show-bin-path", step)
        self.assertIn('"$bin/nexora-financial-check" --diagnostic-selftest', step)


if __name__ == '__main__':
    unittest.main(verbosity=2)
