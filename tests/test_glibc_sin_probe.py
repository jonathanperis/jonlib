import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import glibc_sin
import glibc_sin_probe as probe


class GlibcSinProbeTests(unittest.TestCase):
    def test_the_arguments_cover_every_region_and_exponent(self):
        cases = probe.arguments()
        words = [word for word, _ in cases]
        self.assertEqual(len(words), len(set(words)))
        exponents = {(word >> 52) & 2047 for word in words}
        self.assertEqual(exponents, set(range(2048)))
        labels = {label for _, label in cases}
        self.assertEqual(labels, {'random', 'promoted-binary32', 'region-boundary', 'quarter-turn', 'table-row', 'variant-control', 'special'})
        for bound in probe.BOUNDS:
            self.assertIn(bound, words)
            self.assertIn(bound | (1 << 63), words)

    def test_the_controls_span_the_table_the_middle_range_and_both_reductions(self):
        for controls in (glibc_sin.SIN_CONTROLS, glibc_sin.COS_CONTROLS):
            magnitudes = [(word & 0x7fffffffffffffff) >> 32 for word, _ in controls]
            self.assertTrue(any(k < 0x3feb6000 for k in magnitudes))
            self.assertTrue(any(0x3feb6000 <= k < 0x400368fd for k in magnitudes))
            self.assertTrue(any(0x400368fd <= k < 0x419921fb for k in magnitudes))
            self.assertTrue(any(k >= 0x419921fb for k in magnitudes))
            self.assertEqual(len({word for word, _ in controls}), len(controls))

    def test_the_check_program_names_both_models_and_every_control(self):
        source = glibc_sin.check_source()
        self.assertIn('double glibc_sin_fma(double);', source)
        self.assertIn('double glibc_cos_fma(double);', source)
        self.assertNotIn('@', source)
        self.assertEqual(source.count('UINT64_C('), 2 * (len(glibc_sin.SIN_CONTROLS) + len(glibc_sin.COS_CONTROLS)))

    def test_the_pinned_sources_are_the_documented_ones(self):
        import hashlib
        expected = {'s_sin.c': 'd607bcb0823bb793ecf917546266559aa6f3da6504719ecb90db8b6cb4bb8b1b',
                    'sincostab.c': '3233d23c6085ac87d47ce1fd7471d88533213f6271ba333e664df30f3172ab85',
                    'usncs.h': 'c1c081b3f99d023f5f4093e72e81c5eabe6fa3cc7389e37f9709d6c138eaef4a'}
        for name, digest in expected.items():
            self.assertEqual(hashlib.sha256((glibc_sin.GLIBC / name).read_bytes()).hexdigest(), digest)
        math = (Path(__file__).resolve().parents[1] / 'docs/MATH.md').read_text()
        for digest in expected.values():
            self.assertIn(digest, math)


if __name__ == '__main__':
    unittest.main()
