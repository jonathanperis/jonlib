import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import explog_probe as probe


class ExpLogModelTests(unittest.TestCase):
    def test_exact_results(self):
        self.assertEqual(probe.exp_model(probe.word(0.0)), 0x3F800000)
        self.assertEqual(probe.exp_model(0x80000000), 0x3F800000)
        self.assertEqual(probe.log_model(probe.word(1.0)), 0)

    def test_results_are_within_an_ulp_of_the_real_functions(self):
        for value in (0.5, -3.25, 10.0, -80.0, 86.0):
            got = probe.number(probe.exp_model(probe.word(value)))
            self.assertAlmostEqual(got / math.exp(value), 1.0, delta=3e-7)
        for value in (0.125, 0.75, 2.0, 64.0, 1e-30, 1e30):
            got = probe.number(probe.log_model(probe.word(value)))
            self.assertAlmostEqual(got, math.log(probe.number(probe.word(value))), delta=3e-7 * max(1.0, abs(math.log(value))))

    def test_domains(self):
        self.assertTrue(probe.exp_inside(probe.EXP_LIMIT - 1))
        self.assertFalse(probe.exp_inside(probe.EXP_LIMIT))
        self.assertFalse(probe.exp_inside(0x7FC00000))
        for bits in probe.EXP_VARIANTS:
            self.assertFalse(probe.exp_inside(bits))
            self.assertTrue(probe.exp_inside(bits + 1))
        self.assertTrue(probe.log_inside(0x00800000))
        self.assertFalse(probe.log_inside(0x007FFFFF))
        self.assertFalse(probe.log_inside(0))
        self.assertFalse(probe.log_inside(0xBF800000))
        self.assertFalse(probe.log_inside(0x7F800000))

    def test_cases_are_deterministic_and_reach_the_edges(self):
        chosen = probe.cases()
        self.assertEqual(chosen, probe.cases())
        self.assertEqual(len(chosen), 242)
        for bits in (probe.EXP_LIMIT, *probe.EXP_VARIANTS, 0x00800000, 0x7F800000):
            self.assertIn(bits, chosen)


if __name__ == '__main__':
    unittest.main()
