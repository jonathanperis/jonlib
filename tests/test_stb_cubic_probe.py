import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import stb_cubic_probe as probe


class PoolTests(unittest.TestCase):
    def test_the_pool(self):
        pool = probe.pool()
        triples = [triple for triple, _ in pool]
        self.assertEqual(len(triples), len(set(triples)))
        labels = {label for _, label in pool}
        self.assertEqual(labels, {'sdf', 'random', 'near-double-root', 'double-root', 'edge'})
        self.assertGreater(sum(label == 'sdf' for _, label in pool), 20000)
        self.assertGreater(sum(label == 'double-root' for _, label in pool), 30000)
        by_label = dict(pool)
        for edge in ((0, 0, 0), (0x7f800000, 0, 0), (0, 0x7fc00000, 0)):
            self.assertEqual(by_label[edge], 'edge')

    def test_an_sdf_triple_is_the_call_site_s_in_float(self):
        import random
        triple = None
        rng = random.Random(1)
        while triple is None:
            triple = probe.sdf_triple(rng)
        for value in triple:
            self.assertEqual(probe.f32(value), value)

    def test_the_kinds_kept(self):
        self.assertEqual(probe.KEEP, {1: 400, 3: 900, 4: 40, 0: 40})

    def test_the_programs(self):
        self.assertIn('int num = stbtt__solve_cubic(a, b, c, r)', probe.REFERENCE)
        self.assertIn('double argument = -sqrt(w) * q / 2;', probe.REFERENCE)
        self.assertIn('show(Cubic.solve(flt(a), flt(b), flt(c)))', probe.PROGRAM)
        self.assertIn('import ../../src/stb_cubic.bend as Cubic\n', probe.PROGRAM)


if __name__ == '__main__':
    unittest.main()
