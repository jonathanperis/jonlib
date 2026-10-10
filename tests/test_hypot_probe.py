import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import hypot_probe
from hypot_probe import exact, kernel, word


class HypotModelTests(unittest.TestCase):
    def test_a_pythagorean_triple_is_inside_and_its_neighbours_follow(self):
        self.assertIs(kernel(word(3.0), word(4.0), word(5.0)), True)
        self.assertIs(kernel(word(3.0), word(4.0), word(5.0) - 1), False)
        self.assertIs(kernel(word(3.0), word(4.0), word(5.0) + 1), True)
        self.assertIs(kernel(word(24.0) + 1, word(32.0), word(40.0)), False)

    def test_a_sum_inside_the_band_is_refused(self):
        self.assertIsNone(kernel(word(1e-10), word(40.0), word(40.0)))
        self.assertIsNone(exact(word(1e-10), word(40.0), word(40.0)))
        self.assertIs(kernel(word(1e-3), word(40.0), word(40.0)), False)

    def test_a_negative_radius_is_below_every_distance(self):
        self.assertIs(kernel(0, 0, word(-1.0)), False)
        self.assertIs(kernel(word(1e30), 0, word(-1.0)), False)
        self.assertIs(kernel(0, 0, 0x80000000), True)

    def test_non_finite_values_and_large_magnitudes_are_refused(self):
        for case in ((0x7F800000, 0, word(1.0)), (0, 0x7FC00000, word(1.0)), (0, 0, 0x7F800000), (0x7F800000, 0, word(-1.0)),
                     (word(2.0 ** 64), 0, word(2.0 ** 64)), (0, 0, word(2.0 ** 64))):
            self.assertIsNone(kernel(*case), case)
        self.assertIs(kernel(word(2.0 ** 63), 0, word(2.0 ** 63)), True)

    def test_the_search_finds_sums_that_round_onto_the_square(self):
        found = hypot_probe.rounded_onto()
        self.assertEqual(len(found), 8)
        self.assertEqual([kernel(*case) for case in found], [True] * 4 + [None] * 4)
        self.assertEqual([exact(*case) for case in found], [True] * 4 + [None] * 4)

    def test_the_kernel_never_contradicts_the_contract(self):
        cases = hypot_probe.cases()
        self.assertGreater(len(cases), 200)
        answers = [kernel(*case) for case in cases]
        for case, answer in zip(cases, answers):
            if answer is not None:
                self.assertIs(answer, exact(*case), case)
        self.assertGreater(answers.count(True), 50)
        self.assertGreater(answers.count(False), 50)
        self.assertGreater(answers.count(None), 10)


if __name__ == '__main__':
    unittest.main()
