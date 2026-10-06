"""Exact rational oracles and corpora behind the private binary64 probes."""
from fractions import Fraction
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import binary64_add_sub_oracle as add_sub
import binary64_add_sub_probe as add_sub_probe
import binary64_fma_oracle as fma
import binary64_fma_probe as fma_probe
import binary64_gradual_multiply_oracle as gradual
import binary64_gradual_multiply_probe as gradual_probe
from binary64_harness import SIGN, FRACTION, check_environment, normal
import binary64_narrow_oracle as narrow
import binary64_narrow_probe as narrow_probe
import binary64_ops_oracle as ops
import binary64_ops_probe as ops_probe
from probekit import ProbeFailure


def bits(result):
    return None if result is None else (result[0] << 32) | result[1]


def split(*values):
    return [part for value in values for part in (value >> 32, value & 0xffffffff)]


class NearestTests(unittest.TestCase):
    def test_binary64_neighbor_search_ties_to_even_and_overflows(self):
        for lower in (0, 1, (1 << 52) - 1, 1 << 52, 0x3ff0000000000000, 0x3ff0000000000001, fma.MAX_FINITE):
            left, right = fma.positive64(lower), fma.positive64(lower + 1)
            middle = (left + right) / 2
            for value, expected in ((left, lower), ((left + middle) / 2, lower), (middle, lower + lower % 2),
                                    ((middle + right) / 2, lower + 1), (right, lower + 1)):
                for sign in (0, SIGN):
                    self.assertEqual(fma.nearest64(-value if sign else value, sign), expected | sign)
        self.assertEqual(fma.nearest64(fma.power2(1025)), fma.OVERFLOW_ENDPOINT)
        for value in (1.0, True, '1'):
            with self.assertRaises(ValueError): fma.nearest64(value)

    def test_rejects_non_word_inputs(self):
        for value in (-1, 1 << 32, True, 0.0, None):
            with self.assertRaises(ValueError): narrow.nearest(value, 0)
            with self.assertRaises(ValueError): fma.checked(value, 0, 0, 0, 0, 0)
            with self.assertRaises(ValueError): add_sub.checked('add', 0, value, 0, 0)
            with self.assertRaises(ValueError): ops.checked('mul', 0, 0, value, 0)
            with self.assertRaises(ValueError): gradual.checked('multiply', 0, 0, 0, value)
        for kind in ('ADD', 'mul', '', None):
            with self.assertRaises(ValueError): add_sub.checked(kind, 0, 0, 0, 0)
        with self.assertRaises(ValueError): ops.checked('negate', 0, 0, 0, 1)  # unused operand must be zero
        with self.assertRaises(ValueError): normal(1024)


class NarrowTests(unittest.TestCase):
    def test_hand_boundaries_signs_and_specials(self):
        for high, low, expected in narrow_probe.HAND:
            self.assertEqual(narrow.nearest(high, low), expected)
            self.assertEqual(narrow.nearest(high | 0x80000000, low), expected | 0x80000000)
        for sign in (0, 0x80000000):
            self.assertEqual(narrow.nearest(sign | 0x000fffff, 0xffffffff), sign)  # binary64 subnormal -> signed zero
            self.assertEqual(narrow.nearest(sign | 0x7fefffff, 0xffffffff), sign | 0x7f800000)  # RN overflow
            for fraction in (0, 1, 0xfffff):
                self.assertIsNone(narrow.nearest(sign | 0x7ff00000 | fraction, 0))

    def test_binary32_midpoints_round_to_even(self):
        for lower in (0, 1, 2, 0x7fffff, 0x800000, 0x3f800000, 0x3f800001, 0x7f7fffff):
            value = narrow_probe.rational64((narrow.positive32(lower) + narrow.positive32(lower + 1)) / 2)
            for delta, expected in ((-1, lower), (0, lower + lower % 2), (1, lower + 1)):
                self.assertEqual(narrow.nearest((value + delta) >> 32, (value + delta) & 0xffffffff), expected)

    def test_jam_and_round_invariants(self):
        row = lambda **fields: narrow_probe.expected_row(dict(id=0, **fields))
        self.assertEqual(row(kind='jam', count=1, high=0, low=3), [0, 2, 0, 1 | 1])
        self.assertEqual(row(kind='jam', count=65, high=0, low=1), [0, 2, 0, 1])
        self.assertEqual(row(kind='jam', count=0, high=0, low=0), [0, 2, 0, 0])
        self.assertEqual([row(kind='round', value=(2 << 3) | tail)[2] for tail in range(8)], [2, 2, 2, 2, 2, 3, 3, 3])
        self.assertEqual([row(kind='round', value=(3 << 3) | tail)[2] for tail in range(8)], [3, 3, 3, 3, 4, 4, 4, 4])


class FmaTests(unittest.TestCase):
    def result(self, a, b, c):
        return bits(fma.checked(*split(a, b, c)))

    def test_hand_vectors_and_fused_single_rounding(self):
        for a, b, c, expected, label in fma_probe.HAND:
            with self.subTest(label): self.assertEqual(self.result(a, b, c), expected)
        one, delta = Fraction(1), fma.power2(-52)
        self.assertEqual((one + delta) * (one - delta) - one, -fma.power2(-104))
        self.assertEqual(float(one + delta) * float(one - delta) - 1.0, 0.0)  # split evaluation loses it

    def test_signed_zero_results(self):
        for sa in (0, 1):
            for sb in (0, 1):
                for sc in (0, 1):
                    expected = SIGN if sa ^ sb == sc == 1 else 0
                    self.assertEqual(self.result(sa << 63, normal(0, sign=sb), sc << 63), expected)
        for sign in (0, 1):  # nonzero exact cancellation is +0 in RN
            self.assertEqual(self.result(normal(0, sign=sign), normal(0), normal(0, sign=1 - sign)), 0)

    def test_domain_rejects_before_zero_shortcut(self):
        for index, (minimum, maximum) in enumerate(fma.BOUNDS):
            for exponent in (minimum, maximum):
                values = [normal(0), normal(0), 0]; values[index] = normal(exponent)
                self.assertIsNotNone(self.result(*values))
            for bad in (normal(minimum - 1), normal(maximum + 1), 1, 0x7ff0000000000000, 0x7ff8000000000000):
                values = [0, 0, 0]; values[index] = bad
                self.assertIsNone(self.result(*values))


class AddSubTests(unittest.TestCase):
    def result(self, kind, a, b):
        return bits(add_sub.checked(kind, *split(a, b)))

    def test_hand_vectors(self):
        for kind, a, b, expected, label in add_sub_probe.HAND:
            with self.subTest(label): self.assertEqual(self.result(kind, a, b), expected)

    def test_signed_zeros_and_subtraction_as_negated_addition(self):
        for sa in (0, 1):
            for sb in (0, 1):
                self.assertEqual(self.result('add', sa << 63, sb << 63), SIGN if sa == sb == 1 else 0)
                self.assertEqual(self.result('sub', sa << 63, sb << 63), SIGN if sa == 1 and sb == 0 else 0)
        for a, b in ((normal(0, 1), normal(-52)), (normal(-900, 5, 1), normal(130)), (0, SIGN)):
            self.assertEqual(add_sub.checked_sub(*split(a, b)), add_sub.checked_add(*split(a, b ^ SIGN)))
            if a & ~SIGN:  # nonzero exact cancellation is +0 in RN
                self.assertEqual(self.result('sub', a, a), 0)
                self.assertEqual(self.result('add', a, a ^ SIGN), 0)

    def test_domain(self):
        for bad in (normal(-901), normal(131), 1, 0x7ff0000000000000):
            for kind in add_sub.KINDS:
                self.assertIsNone(self.result(kind, bad, 0))
                self.assertIsNone(self.result(kind, SIGN, bad))
        self.assertIsNotNone(self.result('add', normal(-900), normal(130, FRACTION, 1)))


class OpsTests(unittest.TestCase):
    def result(self, kind, a, b=0):
        return bits(ops.checked(kind, *split(a, b)))

    def test_hand_vectors_with_sign_symmetry(self):
        for kind, a, b, expected, label in ops_probe.HAND:
            for sa in (0, SIGN):
                for sb in (0, SIGN):
                    with self.subTest(label): self.assertEqual(self.result(kind, a ^ sa, b ^ sb), expected ^ sa ^ sb)

    def test_zero_signs_and_zero_divisor(self):
        for sa in (0, SIGN):
            for sb in (0, SIGN):
                self.assertEqual(self.result('mul', sa, sb), sa ^ sb)
                self.assertEqual(self.result('div', sa, normal(0) ^ sb), sa ^ sb)
                self.assertIsNone(self.result('div', normal(0) ^ sa, sb))
                self.assertIsNone(self.result('mul', sa, 0x7ff0000000000000 ^ sb))  # validated before shortcut

    def test_operand_and_pair_exponent_domains(self):
        self.assertEqual(self.result('mul', normal(-554), normal(-279)), normal(-833))
        self.assertIsNone(self.result('mul', normal(-554), normal(-280)))
        self.assertIsNone(self.result('mul', normal(127), normal(1)))
        self.assertEqual(self.result('div', normal(-225), normal(127)), normal(-352))
        self.assertIsNone(self.result('div', normal(1), normal(0)))  # quotient exponent must not grow

    def test_adapters_promotion_and_raw_words(self):
        for value in (1, FRACTION):  # identity rejects subnormals, finite keeps them
            self.assertIsNone(self.result('identity', value))
            self.assertEqual(self.result('finite', value), value)
        for word32, expected in ((1, 0x36a0000000000000), (0x007fffff, 0x380fffffc0000000), (0x7f7fffff, 0x47efffffe0000000)):
            self.assertEqual(self.result('promote', word32), expected)
            self.assertEqual(self.result('promote', word32 | 0x80000000), expected | SIGN)
        self.assertIsNone(self.result('promote', 0x7fc00000))
        self.assertEqual(self.result('increment', (1 << 64) - 1), 0)
        self.assertEqual(self.result('decrement', 0), (1 << 64) - 1)
        self.assertEqual(self.result('negate', 0x7ff0000000000001), 0xfff0000000000001)
        self.assertEqual(self.result('magnitude', SIGN | 2, 1), 2)
        self.assertEqual(self.result('equal', 0, SIGN), 1)
        self.assertEqual(self.result('equal', 0x7ff8000000000000, 0x7ff8000000000000), 0)
        self.assertEqual(self.result('power', 1023), 0x3ff0000000000000)
        self.assertIsNone(self.result('power', 2047))


class GradualMultiplyTests(unittest.TestCase):
    def test_hand_vectors_including_rejections(self):
        for a, b, expected, label in gradual_probe.HAND:
            with self.subTest(label): self.assertEqual(bits(gradual.checked('multiply', *split(a, b))), expected)

    def test_single_rounding_into_subnormals(self):
        # Rounding once to the subnormal lattice differs from rounding to 53 bits first.
        for b, expected, double_rounded in ((0x1150000000000004, 0x0008000000000003, 0x0008000000000002),
                                            (0x115ffffffffffffd, 0x000fffffffffffff, 0x0010000000000000),
                                            (0x0e0fffffffffffff, 1, 0)):
            for sign in (0, SIGN):
                result = bits(gradual.checked('multiply', *split(0x2ea0000000000001 | sign, b)))
                self.assertEqual(result, expected | sign)
                self.assertNotEqual(result, double_rounded | sign)


class CorpusTests(unittest.TestCase):
    def test_corpora_sizes_unique_inputs_and_rejections(self):
        counts = {narrow_probe: (40276, 12), fma_probe: (11038, 312), add_sub_probe: (47464, 816),
                  ops_probe: (36176, 1112), gradual_probe: (30861, 352)}
        for module, (size, rejected) in counts.items():
            with self.subTest(module.__name__):
                rows = module.samples()
                self.assertEqual(len(rows), size)
                self.assertEqual([row['id'] for row in rows], list(range(size)))
                keys = {tuple(value for key, value in sorted(row.items()) if key not in ('id', 'labels')) for row in rows}
                self.assertEqual(len(keys), size)
                tags = [module.expected_row(row)[-3] for row in rows]
                self.assertEqual(tags.count(0), rejected)


class EnvironmentTests(unittest.TestCase):
    def test_native_oracle_requires_round_to_nearest_without_flush_to_zero(self):
        keys = ('rounding', 'initial_rounding', 'selected_rounding', 'control_name', 'control', 'ftz', 'daz', 'runtime_mul')
        good = dict(rounding='FE_TONEAREST', initial_rounding=0, selected_rounding=0, control_name='fpcr',
                    control=0, ftz=False, daz=False, runtime_mul=True)
        check_environment(good, keys)
        for change in (dict(control=1 << 24), dict(ftz=True), dict(selected_rounding=1), dict(runtime_mul=False),
                       dict(control_name='mxcsr', control=1 << 15)):
            with self.assertRaises(ProbeFailure): check_environment({**good, **change}, keys)


if __name__ == '__main__':
    unittest.main()
