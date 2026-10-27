"""CPU quiet-NaN signs stay uncompared only where the recorded gaps allow."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import spline_exceptional_probe as probe


class SplineSignTests(unittest.TestCase):
    def test_only_the_recorded_cpu_sign_gaps_are_uncompared(self):
        for lane in ('cpu-1', 'cpu-2'):
            self.assertTrue(probe.quiet_sign_uncompared('linear', 'uncontracted', lane))
            self.assertTrue(probe.quiet_sign_uncompared('linear', 'fused', lane))
            self.assertTrue(probe.quiet_sign_uncompared('quad', 'uncontracted', lane))
            self.assertTrue(probe.quiet_sign_uncompared('quad', 'fused', lane))
            self.assertTrue(probe.quiet_sign_uncompared('basis', 'fused', lane))
            self.assertFalse(probe.quiet_sign_uncompared('basis', 'uncontracted', lane))
            self.assertFalse(probe.quiet_sign_uncompared('catmull', 'uncontracted', lane))
            self.assertFalse(probe.quiet_sign_uncompared('catmull', 'fused', lane))
            self.assertFalse(probe.quiet_sign_uncompared('cubic', 'uncontracted', lane))
            self.assertFalse(probe.quiet_sign_uncompared('cubic', 'fused', lane))
        for kind, slot in (
            ('linear', 'fused'),
            ('linear', 'uncontracted'),
            ('quad', 'fused'),
            ('basis', 'fused'),
            ('basis', 'uncontracted'),
            ('catmull', 'fused'),
            ('cubic', 'fused'),
        ):
            self.assertFalse(probe.quiet_sign_uncompared(kind, slot, 'javascript'))
