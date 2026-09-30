"""A failed platform read may leave errno at zero; it is still a failed read."""
import unittest
from test_financial_diagnostics import diag, snapshot


class RawErrnoTests(unittest.TestCase):
    def test_zero_errno_preserves_failure_not_success(self):
        row = snapshot(0, 1)
        row.update(threadStatus='syscallFailure', threadErrno=0)
        del row['threadCPUNS']
        diag.validate_snapshot(row)
        self.assertEqual(diag.counter_delta({'before': row, 'after': row}, 'threadCPUNS'),
                         (None, 'syscallFailure/syscallFailure'))

    def test_errno_retains_signed_int32_range(self):
        row = snapshot(0, 1)
        row.update(threadStatus='syscallFailure')
        del row['threadCPUNS']
        for value in (-(1 << 31), -1, 0, 1, (1 << 31) - 1):
            with self.subTest(valid=value):
                row['threadErrno'] = value
                diag.validate_snapshot(row)
        for value in (None, False, 1 << 31, -(1 << 31) - 1, '0'):
            with self.subTest(invalid=value), self.assertRaises(ValueError):
                row['threadErrno'] = value
                diag.validate_snapshot(row)
