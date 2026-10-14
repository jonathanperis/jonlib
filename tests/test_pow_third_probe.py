import json
import re
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import glibc_pow
import pow_third_probe as probe


def model_words(name):
    text = (glibc_pow.MODEL / 'model.c').read_text()
    body = text[text.index(f'static const uint64_t {name}['):]
    return [int(word, 16) for word in re.findall(r'0x([0-9a-f]{16})ULL', body[:body.index('};')])]


def bend_table(name):
    text = (ROOT / 'src/power64.bend').read_text()
    body = text[text.index(f'def {name}() -> +List<U32>:'):]
    values = [int(value) for value in re.findall(r'\d+', body[body.index('[') + 1:body.index(']')])]
    return [high << 32 | low for high, low in zip(values[0::2], values[1::2])]


def bend_constant(name):
    text = (ROOT / 'src/power64.bend').read_text()
    found = re.search(rf'def {re.escape(name)}\(\) -> V:\n  Ok\{{(\d+), (\d+)\}}', text)
    return int(found.group(1)) << 32 | int(found.group(2))


class TableTests(unittest.TestCase):
    def test_the_port_s_tables_are_the_model_s(self):
        self.assertEqual(bend_table('log_table'), model_words('L'))
        self.assertEqual(bend_table('exp_table'), model_words('T'))
        self.assertEqual((len(model_words('L')), len(model_words('T'))), (384, 256))

    def test_the_port_s_constants_are_the_model_s(self):
        self.assertEqual([bend_constant('ln2hi'), bend_constant('ln2lo')], model_words('LN2'))
        self.assertEqual([bend_constant(f'a{i}') for i in range(7)], model_words('A'))
        self.assertEqual([bend_constant(name) for name in ('invln2n', 'shift', 'negln2hin', 'negln2lon')], model_words('E'))
        self.assertEqual([bend_constant(f'c{i}') for i in range(2, 6)], model_words('C'))
        # A[0] is -0.5, the shift 0x1.8p52, and the exponent (double) (1.0f/3.0f)
        third = struct.unpack('<Q', struct.pack('<d', struct.unpack('<f', struct.pack('<f', 1.0 / 3.0))[0]))[0]
        self.assertEqual((bend_constant('a0'), bend_constant('shift'), bend_constant('third.exponent')), (0xBFE0000000000000, 0x4338000000000000, third))
        self.assertEqual(glibc_pow.THIRD, third)

    def test_the_recorded_run_is_every_float(self):
        rows = [json.loads(line) for line in (glibc_pow.MODEL / 'results').read_text().splitlines()]
        self.assertEqual([row['comparison'] for row in rows], ['fma', 'sse2', 'variants'])
        for row in rows:
            self.assertEqual((row['floats'], row['narrowed_floats_that_differ'], row['refused']), (1 << 32, 0, 0))
        self.assertEqual([row['doubles_that_differ'] for row in rows], [0, 0, 1515625])


class ProbeTests(unittest.TestCase):
    def test_the_arguments(self):
        cases = probe.arguments()
        words = [word for word, _ in cases]
        self.assertEqual(len(words), len(set(words)))
        labels = {label for _, label in cases}
        self.assertEqual(labels, {'random', 'table-interval', 'near-one', 'cube', 'power-of-two', 'extreme', 'variant-control', 'zero', 'refused'})
        positive = [word for word in words if 0 < word < probe.INFINITY]
        self.assertEqual({word >> 23 for word in positive}, set(range(255)))
        # every interval of the logarithm's table: the top seven bits of the significand
        for exponent in (1, 127, 200):
            self.assertEqual({(word >> 16) & 127 for word in positive if word >> 23 == exponent}, set(range(128)))
        for word in (1, 0x007fffff, 0x00800000, 0x7f7fffff, probe.ONE, probe.ONE - 1, probe.ONE + 1, probe.bits(27.0), probe.bits(64000.0)):
            self.assertIn(word, positive)
        by_label = dict((word, label) for word, label in cases)
        self.assertEqual((by_label[0], by_label[0x80000000]), ('zero', 'zero'))
        for word in (probe.INFINITY, 0xff800000, 0x7fc00000, probe.bits(-1.0), 0x80000001):
            self.assertEqual(by_label[word], 'refused')

    def test_the_controls_are_two_in_each_of_sixteen_ranges_of_the_exponent(self):
        self.assertEqual(len(glibc_pow.CONTROLS), 32)
        self.assertEqual(sorted({x >> 27 for x, _, _ in glibc_pow.CONTROLS}), list(range(16)))
        for x, double, narrowed in glibc_pow.CONTROLS:
            value = struct.unpack('<d', struct.pack('<Q', double))[0]
            self.assertEqual(struct.unpack('<I', struct.pack('<f', value))[0], narrowed)
            # a cube root, to a part in a million
            x_value = struct.unpack('<f', struct.pack('<I', x))[0]
            self.assertAlmostEqual(value ** 3 / x_value, 1.0, places=5)

    def test_the_check_program_names_the_model_and_every_control(self):
        source = glibc_pow.check_source()
        self.assertIn('double glibc_pow_fma(double, double, int *);', source)
        self.assertNotIn('@', source)
        self.assertEqual(source.count('UINT64_C('), 2 * len(glibc_pow.CONTROLS) + 1)

    def test_the_candidate_is_the_port_s_function(self):
        self.assertIn('import ../../src/power64.bend as P\n', probe.PROGRAM)
        self.assertIn('show(P.third(bits))', probe.PROGRAM)


if __name__ == '__main__':
    unittest.main()
