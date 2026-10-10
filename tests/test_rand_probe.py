import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import rand_probe


class RandModelTests(unittest.TestCase):
    def test_the_default_seed_gives_the_well_known_values(self):
        self.assertEqual(rand_probe.model(1, 8), [1804289383, 846930886, 1681692777, 1714636915, 1957747793, 424238335, 719885386, 1649760492])

    def test_a_zero_seed_is_the_seed_one(self):
        self.assertEqual(rand_probe.model(0), rand_probe.model(1))

    def test_values_fit_31_bits(self):
        for seed in rand_probe.SEEDS:
            self.assertTrue(all(0 <= value < 2 ** 31 for value in rand_probe.model(seed)))
            self.assertEqual(len(rand_probe.model(seed)), rand_probe.COUNT)

    def test_another_seed(self):
        self.assertEqual(rand_probe.model(12345, 4), [383100999, 858300821, 357768173, 455528251])


if __name__ == '__main__':
    unittest.main()
