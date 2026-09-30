#!/usr/bin/env python3
"""Exercise the actual Swift output owner, never a reimplemented Python writer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BINARY = None


class WriterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def probe(self, path):
        result = subprocess.run([str(BINARY), '--diagnostic-writer-probe', str(path)],
                                capture_output=True, timeout=30)
        self.assertNotIn(b'ThreadSanitizer:', result.stdout + result.stderr)
        return result

    def test_new_file_complete_and_write_after_close_rejected(self):
        p = self.root / 'new.ndjson'
        self.assertEqual(self.probe(p).returncode, 0)
        self.assertEqual(json.loads(p.read_text()), {'kind': 'writer-probe', 'status': 'complete'})
        self.assertEqual(p.read_bytes().count(b'\n'), 1)
        self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_existing_file_bytes_preserved(self):
        p = self.root / 'old.ndjson'; data = b'original evidence\n'
        p.write_bytes(data)
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertEqual(p.read_bytes(), data)

    def test_second_attempt_does_not_replace_completed_first(self):
        p = self.root / 'same.ndjson'
        self.assertEqual(self.probe(p).returncode, 0)
        digest = hashlib.sha256(p.read_bytes()).digest()
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertEqual(hashlib.sha256(p.read_bytes()).digest(), digest)

    def test_existing_empty_file_preserved(self):
        p = self.root / 'empty'; p.touch()
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertEqual(p.read_bytes(), b'')

    def test_symlink_to_existing_file_preserved(self):
        target = self.root / 'target'; target.write_bytes(b'original')
        p = self.root / 'link'; p.symlink_to(target)
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertTrue(p.is_symlink()); self.assertEqual(target.read_bytes(), b'original')

    def test_dangling_symlink_never_creates_target(self):
        target = self.root / 'missing'; p = self.root / 'link'; p.symlink_to(target)
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertTrue(p.is_symlink()); self.assertFalse(target.exists())

    def test_hardlink_does_not_modify_other_name(self):
        target = self.root / 'target'; target.write_bytes(b'original')
        p = self.root / 'alias'; os.link(target, p)
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertEqual(target.read_bytes(), b'original'); self.assertEqual(p.read_bytes(), b'original')

    def test_existing_directory_rejected(self):
        p = self.root / 'directory'; p.mkdir()
        self.assertNotEqual(self.probe(p).returncode, 0); self.assertTrue(p.is_dir())

    def test_existing_fifo_rejected_without_blocking(self):
        p = self.root / 'pipe'; os.mkfifo(p)
        self.assertNotEqual(self.probe(p).returncode, 0)

    def test_missing_parent_rejected_without_creating_directories(self):
        p = self.root / 'absent/file'
        self.assertNotEqual(self.probe(p).returncode, 0)
        self.assertFalse(p.parent.exists())

    def test_empty_path_rejected(self):
        self.assertNotEqual(self.probe('').returncode, 0)

    def test_exclusive_create_race_has_exactly_one_winner(self):
        p = self.root / 'race.ndjson'
        processes = [subprocess.Popen([str(BINARY), '--diagnostic-writer-probe', str(p)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(8)]
        try:
            for process in processes:
                stdout, stderr = process.communicate(timeout=30)
                self.assertNotIn(b'ThreadSanitizer:', stdout + stderr)
            self.assertEqual(sum(process.returncode == 0 for process in processes), 1)
            self.assertEqual(json.loads(p.read_text()), {'kind': 'writer-probe', 'status': 'complete'})
        finally:
            for process in processes:
                if process.poll() is None: process.kill(); process.communicate()

    def test_missing_source_identity_rejects_before_creating_raw(self):
        p = self.root / 'unidentified.ndjson'; env = dict(os.environ); env.pop('NEXORA_SOURCE_COMMIT', None)
        result = subprocess.run([str(BINARY), '--diagnostics', str(p), '--quick'],
                                env=env, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0); self.assertFalse(p.exists())

    def test_invalid_source_identity_rejects_before_creating_raw(self):
        p = self.root / 'invalid.ndjson'; env = dict(os.environ, NEXORA_SOURCE_COMMIT='not-a-source-sha')
        result = subprocess.run([str(BINARY), '--diagnostics', str(p), '--quick'],
                                env=env, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0); self.assertFalse(p.exists())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('binary', type=Path)
    args = parser.parse_args(); BINARY = args.binary.resolve(strict=True)
    unittest.main(argv=['verify_writer.py'], verbosity=2)
