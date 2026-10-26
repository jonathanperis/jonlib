"""Quiet-NaN signs on the unstable spline queries are not parity bits."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import spline_exceptional_probe as probe


class SplineSignTests(unittest.TestCase):
    def test_only_the_unstable_queries_drop_the_quiet_sign(self):
        self.assertTrue(probe.quiet_sign_uncompared('linear'))
        self.assertTrue(probe.quiet_sign_uncompared('basis'))
        self.assertTrue(probe.quiet_sign_uncompared('quad'))
        self.assertFalse(probe.quiet_sign_uncompared('catmull'))
        self.assertFalse(probe.quiet_sign_uncompared('cubic'))
