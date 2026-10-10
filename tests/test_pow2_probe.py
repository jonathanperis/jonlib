import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import pow2_probe


class Pow2ModelTests(unittest.TestCase):
    def test_integral_exponents_are_exact_powers(self):
        for k in range(-125, 126):
            self.assertEqual(pow2_probe.model(pow2_probe.word(float(k))), pow2_probe.word(2.0 ** k), k)

    def test_known_fractions(self):
        self.assertEqual(pow2_probe.model(pow2_probe.word(0.5)), 0x3FB504F3)   # sqrt(2) to nearest
        self.assertEqual(pow2_probe.model(pow2_probe.word(-0.5)), 0x3F3504F3)
        self.assertEqual(pow2_probe.model(0x80000000), 0x3F800000)             # 2^-0 is 1
        self.assertEqual(pow2_probe.model(1), 0x3F800000)                      # the smallest subnormal

    def test_the_domain_is_below_126(self):
        self.assertTrue(pow2_probe.inside(pow2_probe.LIMIT - 1))
        self.assertTrue(pow2_probe.inside(0x80000000 | (pow2_probe.LIMIT - 1)))
        self.assertFalse(pow2_probe.inside(pow2_probe.LIMIT))
        self.assertFalse(pow2_probe.inside(0x7F800000))
        self.assertFalse(pow2_probe.inside(0x7FC00000))
        self.assertEqual(struct.unpack('<f', struct.pack('<I', pow2_probe.LIMIT))[0], 126.0)

    def test_cases_cover_the_domain_and_its_edges(self):
        chosen = pow2_probe.cases()
        self.assertEqual(len(chosen), 280)
        self.assertEqual(chosen, pow2_probe.cases())
        self.assertIn(pow2_probe.LIMIT, chosen)
        self.assertTrue(any(pow2_probe.inside(b) and (b & 0x7F800000) == 0 and b & 0x7FFFFF for b in chosen))


if __name__ == '__main__':
    unittest.main()
