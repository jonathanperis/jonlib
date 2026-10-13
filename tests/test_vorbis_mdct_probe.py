import math
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_mdct_probe as mp
from vorbis_codebook_probe import Rng


class BlocksTests(unittest.TestCase):
    def test_the_blocks_of_a_size(self):
        made = mp.blocks(64, Rng(5))
        names = [name for name, _ in made]
        self.assertEqual((len(names), len(set(names)), all(len(values) == 64 for _, values in made)), (10, 10, True))
        by = dict(made)
        # the spectrum is the first half; the second is not read
        self.assertEqual((by['silence'], by['first'][:3], by['last'][30:33], by['ones'][31:33]), ([0.0] * 64, [1.0, 0.0, 0.0], [0.0, -2.5, 0.0], [1.0, 0.0]))
        self.assertEqual((by['noise'][:32], by['noise'][32:], by['noise-over-junk'][32:]), (by['noise-over-junk'][:32], [0.0] * 32, [7.0] * 32))
        self.assertTrue(all(-1.0 <= value < 1.0 for value in by['noise'][:32]) and len(set(by['noise'][:32])) > 20)

    def test_no_block_overflows_a_float(self):
        # an infinity less an infinity is a NaN whose bits are the machine's
        for n in mp.SIZES:
            for name, values in mp.blocks(n, Rng(9)):
                self.assertTrue(all(math.isfinite(struct.unpack('<f', struct.pack('<f', value))[0]) for value in values), name)
                self.assertLess(sum(abs(value) for value in values), 3.0e38 / 8)

    def test_the_sizes_block_has_every_size_and_negative_zeros(self):
        values = dict(mp.blocks(256, Rng(1)))['sizes'][:128]
        self.assertTrue(1e30 in values and 1e-30 in values and any(value == 0.0 and math.copysign(1.0, value) < 0 for value in values))

    def test_packing(self):
        self.assertEqual(mp.packed([1.0, -0.0]), struct.pack('<I', 0x3F800000) + struct.pack('<I', 0x80000000))

    def test_the_reference_is_built_as_raylib_builds_it(self):
        self.assertTrue('-D_DEFAULT_SOURCE' in mp.FLAGS and '-ffp-contract=off' in mp.FLAGS)
        self.assertIn('inverse_mdct(floats, n, &p, 0);', mp.NATIVE)
        self.assertIn('init_blocksize(&p, 0, n)', mp.NATIVE)


if __name__ == '__main__':
    unittest.main()
