"""The exact tan/asinf oracle and the binary64 square-root oracle of the asinf probe."""
from pathlib import Path
import math
import random
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import cr_libm_oracle as oracle
import quaternion_euler_probe as euler


def word64(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


class TanOracle(unittest.TestCase):
    def test_known_values(self):
        self.assertEqual(oracle.tan_bits(word64(1.0)), 0x3FF8EB245CBEE3A6)
        # docs/PERSPECTIVE.md: Apple returns ...cee, the correct rounding is ...cef.
        self.assertEqual(oracle.tan_bits(0x3FECAAC02DACFEFE), 0x3FF3FDC710F27CEF)
        # BeginMode3D with fovy = 45: macOS returns ...94b07.
        self.assertEqual(oracle.tan_bits(0x3FD921FB51000000), 0x3FDA827996294B06)

    def test_signs_and_zero(self):
        self.assertEqual(oracle.tan_bits(0), 0)
        self.assertEqual(oracle.tan_bits(1 << 63), 1 << 63)
        self.assertEqual(oracle.tan_bits(word64(-1.0)), 0xBFF8EB245CBEE3A6)

    def test_tiny_argument_is_itself(self):
        self.assertEqual(oracle.tan_bits(0x3E46A09E80000000), 0x3E46A09E80000000)

    def test_rejects_nonfinite(self):
        with self.assertRaises(ValueError):
            oracle.tan_bits(0x7FF0000000000000)


class AsinfOracle(unittest.TestCase):
    def test_known_values(self):
        self.assertEqual(oracle.asinf_bits(0x3F800000), 0x3FC90FDB)
        self.assertEqual(oracle.asinf_bits(0xBF800000), 0xBFC90FDB)
        self.assertEqual(oracle.asinf_bits(0x3F000000), 0x3F060A92)
        # The smallest glibc 2.39 and Apple counterexamples (docs/INVERSE-TRIG.md).
        self.assertEqual(oracle.asinf_bits(0x39E8974F), 0x39E8974F)
        self.assertEqual(oracle.asinf_bits(0x39E89768), 0x39E89769)

    def test_subnormal_and_zero(self):
        self.assertEqual(oracle.asinf_bits(1), 1)
        self.assertEqual(oracle.asinf_bits(0x80000000), 0x80000000)

    def test_rejects_outside(self):
        with self.assertRaises(ValueError):
            oracle.asinf_bits(0x3F800001)


class SquareRootOracle(unittest.TestCase):
    def test_matches_correctly_rounded_host_sqrt(self):
        rng = random.Random(7)
        for _ in range(500):
            word = (rng.randrange(1, 2047) << 52) | rng.getrandbits(52)
            value = struct.unpack('<d', struct.pack('<Q', word))[0]
            root = word64(math.sqrt(value))
            self.assertEqual(euler.sqrt_expected(word >> 32, word & 0xFFFFFFFF), f'{root >> 32}:{root & 0xFFFFFFFF}')

    def test_zero_and_rejections(self):
        self.assertEqual(euler.sqrt_expected(1 << 31, 0), f'{1 << 31}:0')
        self.assertEqual(euler.sqrt_expected(0xBFF00000, 0), 'none')
        self.assertEqual(euler.sqrt_expected(0, 1), 'none')
        self.assertEqual(euler.sqrt_expected(0x7FF00000, 0), 'none')


if __name__ == '__main__':
    unittest.main()
