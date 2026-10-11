import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import tanf_probe


class TanfCasesTests(unittest.TestCase):
    def test_cases_cover_every_exponent_and_the_region_edges(self):
        cases = tanf_probe.cases()
        self.assertEqual(len(cases), len(set(cases)))
        self.assertEqual({(bits >> 23) & 0xFF for bits in cases}, set(range(256)))
        for edge in (0x39000000, 0x3F2CA140, 0x3F490FDA, 0x42F00000):
            for bits in (edge - 1, edge, edge + 1, 0x80000000 | edge):
                self.assertIn(bits, cases)

    def test_non_finite_arguments_are_among_them(self):
        cases = tanf_probe.cases()
        self.assertFalse(tanf_probe.finite(0x7F800000))
        self.assertFalse(tanf_probe.finite(0x7FC00000))
        self.assertTrue(tanf_probe.finite(0x7F7FFFFF))
        self.assertGreaterEqual(sum(not tanf_probe.finite(bits) for bits in cases), 5)

    def test_the_model_and_its_results_are_in_the_repository(self):
        self.assertTrue(tanf_probe.MODEL.is_file())
        for name in ('glibc239.json', 'glibc241.json'):
            self.assertTrue((tanf_probe.MODEL.parent / 'results' / name).is_file(), name)


if __name__ == '__main__':
    unittest.main()
