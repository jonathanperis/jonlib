import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_tables_probe as tp


class TablesTests(unittest.TestCase):
    def test_the_block_sizes(self):
        self.assertEqual(tp.SIZES, [1 << k for k in range(6, 14)])              # the format's: 64 to 8192

    def test_the_reference_is_built_as_raylib_builds_it(self):
        # <math.h>'s double M_PI: without _DEFAULT_SOURCE stb_vorbis would define a float one, and other tables
        self.assertIn('-D_DEFAULT_SOURCE', tp.FLAGS)
        self.assertIn('-ffp-contract=off', tp.FLAGS)

    def test_the_reference_calls_stb_vorbis(self):
        for call in ('compute_twiddle_factors(n, ', 'compute_window(n, ', 'compute_bitreverse(n, ', '#include "external/stb_vorbis.c"'):
            self.assertIn(call, tp.NATIVE)
        # stb_vorbis.c leaves L, C and R defined as macros: no variable of the reference is named so
        self.assertIsNone(re.search(r'\*\s*[LCR]\s*=', tp.NATIVE))

    def test_the_candidate_prints_what_the_reference_prints(self):
        # four tables of floats, each a list ending with its hash and its count, then the bit reversal's hash, count and two values
        self.assertEqual(tp.NATIVE.count('floats('), 5)
        self.assertEqual(tp.PROGRAM.count('floats(a, 0') + tp.PROGRAM.count('floats(b, 0') + tp.PROGRAM.count('floats(c, 0') + tp.PROGRAM.count('floats(window, 0'), 4)


if __name__ == '__main__':
    unittest.main()
