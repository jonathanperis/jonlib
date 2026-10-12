import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import powf_probe as pp

W = pp.word


class ModelTests(unittest.TestCase):
    def test_exact_powers(self):
        self.assertEqual([pp.model(W(2.0), W(3.0)), pp.model(W(4.0), W(0.5)), pp.model(W(1.0), W(123.456)), pp.model(W(0.5), W(-2.0))], [W(8.0), W(2.0), W(1.0), W(4.0)])
        self.assertEqual(pp.model(1, W(1.0)), 1)                                   # the smallest subnormal to the first power: itself

    def test_what_has_an_answer(self):
        self.assertEqual([pp.model(0, W(2.0)), pp.model(0, W(-1.0)), pp.model(W(2.0), 0), pp.model(W(float('inf')), 0x80000000)], [0, None, W(1.0), W(1.0)])
        for ix, iy in ((W(-2.0), W(2.0)), (0x80000000, W(2.0)), (W(float('inf')), W(1.0)), (0x7FC00000, W(1.0)), (0x7FC00000, 0), (W(2.0), 1), (W(2.0), 0x7F800000), (W(2.0), 0x7FC00000)):
            self.assertIsNone(pp.model(ix, iy))

    def test_the_ends_of_the_range(self):
        self.assertEqual([pp.model(W(2.0), W(-151.0)), pp.model(W(2.0), W(-150.0)), pp.model(W(2.0), W(-149.5)), pp.model(W(2.0), W(-149.0)), pp.model(W(2.0), W(-140.5))],
                         [0, 0, 1, 1, 362])                                          # an underflow is +0 or a subnormal
        self.assertEqual([pp.model(W(2.0), W(128.0)), pp.model(W(2.0), W(127.99)), pp.model(0x7F7FFFFF, W(1.0))], [None, None, None])
        self.assertEqual(pp.model(W(2.0), W(127.5)), W(2.0 ** 127.5))                # below the top 64th of the last binade
        self.assertEqual((pp.narrowed(1e300), pp.narrowed(-1e300), pp.narrowed(1.5)), (0x7F800000, 0xFF800000, W(1.5)))

    def test_a_fused_sum_is_rounded_once(self):
        a, b = 1.0 + 2.0 ** -30, 1.0 - 2.0 ** -30
        self.assertEqual((pp.madd(False, a, b, -1.0), pp.madd(True, a, b, -1.0)), (0.0, -(2.0 ** -60)))

    def test_both_builds_are_modelled(self):
        ix, iy = W(0.3333), W(1.05)
        self.assertEqual(pp.build(True, ix, iy), pp.build(False, ix, iy))
        self.assertEqual(pp.model(ix, iy), pp.build(True, ix, iy))


class CasesTests(unittest.TestCase):
    def test_the_example_s_exponents(self):
        found = pp.exponents()
        self.assertEqual((len(found), found[0], found[-1], W(1.0) in found), (112, W(0.5), W(3.0), True))
        # 0.55 reached going down from 1 and going up from 0.5 are different floats
        near = [w for w in found if abs(pp.real(w) - 0.55) < 1e-5]
        self.assertGreater(len(near), 1)

    def test_the_pairs(self):
        pairs = pp.cases()
        self.assertEqual((len(pairs), pairs[0], len(pp.sample(120)), pp.sample(3) == pp.sample(3)), (540, (0, 0), 120, True))
        answered = sum(pp.model(ix, iy) is not None for ix, iy in pairs)
        self.assertEqual((answered, all(0 < ix < 0x7F800000 for ix, _ in pp.sample(120))), (416, True))

    def test_the_builds_differ_on_the_pairs_found(self):
        for ix, iy in pp.DIFFERING:
            fused, plain = pp.build(True, ix, iy), pp.build(False, ix, iy)
            self.assertEqual((abs(fused - plain), pp.model(ix, iy)), (1, None))
        self.assertEqual((pp.build(True, 0x37E9149D, 0x3F733335), pp.build(False, 0x37E9149D, 0x3F733335)), (0x3844EAED, 0x3844EAEC))

    def test_the_candidate_takes_pairs(self):
        self.assertIn('M.Libm.powf(M.Glibc239Libm{}, float(x), float(y))', pp.PROGRAM)
        self.assertIn('host_powf(x, y)', pp.NATIVE)


if __name__ == '__main__':
    unittest.main()
