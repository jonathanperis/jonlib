import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import strtod_probe
from strtod_probe import expected, inside


class StrtodModelTests(unittest.TestCase):
    def test_words_of_known_values(self):
        self.assertEqual(expected('1'), [1, 0x3FF00000, 0, 1, 0x3F800000])
        self.assertEqual(expected('0.1'), [1, 0x3FB99999, 0x9999999A, 1, 0x3DCCCCCD])
        self.assertEqual(expected('-0'), [1, 0x80000000, 0, 1, 0x80000000])

    def test_a_half_goes_to_the_even_double(self):
        self.assertEqual(expected('9007199254740993')[1:3], [0x43400000, 0])
        self.assertEqual(expected('9007199254740995')[1:3], [0x43400000, 2])

    def test_the_narrowing_overflows_to_infinity(self):
        self.assertEqual(expected('1e39')[3:], [1, 0x7F800000])
        self.assertEqual(expected('3.4028235e38')[3:], [1, 0x7F7FFFFF])

    def test_the_domain(self):
        for text in ('0', '-1.5e-3', '9999999999999999999', '1e60', '1e-60', '0.000001', '1E5', '1e+005'[:5]):
            self.assertTrue(inside(text), text)
        for text in ('12345678901234567890', '1e61', '0.1e-60', '1e1000', '1e0001', '+1', '.5', '5.', '01', '', '-', '1e', 'nan', '1 '):
            self.assertFalse(inside(text), text)
            self.assertEqual(expected(text), [0, 0, 0, 0, 0])

    def test_the_cases_cover_both_answers_once_each(self):
        cases = strtod_probe.cases()
        self.assertEqual(len(cases), len(set(cases)))
        self.assertGreater(sum(inside(text) for text in cases), 300)
        self.assertGreater(sum(not inside(text) for text in cases), 25)


if __name__ == '__main__':
    unittest.main()
