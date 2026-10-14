import hashlib
import re
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import glibc_acos
import glibc_acos_probe as probe

GLIBC = ROOT / 'tools/reference/glibc239'
PINNED = {'e_asin.c': 'cf56fcbf627fd8d57ca280e95ec891b978c70ae54f0f5929cc017003a3256eeb',
          'uasncs.h': '27a627aae3639ad30b30cd77193c6e2f62ea662b24e5fc94b7617ffbaf61fff7',
          'asincos.tbl': '067c3b7047ab28b087262ba26a839ad23bf39236a843897306d5c828d69904f0',
          'root.tbl': 'f3c9d14fdf380e8db2098a183266721cd800ddeb4745ef14f2a491c35b17f5eb',
          'powtwo.tbl': 'e66e94adcd700010aa6ea5407130486ef4dba610311c1aab74bda7952bd67f53'}


def bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def asncs():
    """The 2568 doubles of the pinned table, from its little-endian words (low, high)."""
    text = (GLIBC / 'asincos.tbl').read_text()
    little = text[text.index('#ifdef LITTLE_ENDI'):]
    words = [int(word, 16) for word in re.findall(r'0x([0-9A-Fa-f]{8})', little)]
    return [high << 32 | low for low, high in zip(words[0::2], words[1::2])]


def decimals(name, table):
    text = (GLIBC / name).read_text()
    body = text[text.index(table):]
    body = body[body.index('{') + 1:body.index('}')]
    return [bits(float(value)) for value in body.replace('\n', ' ').split(',') if value.strip()]


def model_words(name):
    text = (glibc_acos.MODEL / 'model.c').read_text()
    body = text[text.index(f'static const uint64_t {name}['):]
    return [int(word, 16) for word in re.findall(r'0x([0-9a-f]{16})ULL', body[:body.index('};')])]


def bend_words(name):
    text = (ROOT / 'src/lgpl/acos_table.bend').read_text()
    body = text[text.index(f'def {name}() -> +List<U32>:'):]
    values = [int(value) for value in re.findall(r'\d+', body[body.index('[') + 1:body.index(']')])]
    return [high << 32 | low for high, low in zip(values[0::2], values[1::2])]


class TableTests(unittest.TestCase):
    def test_the_pinned_sources_are_the_documented_ones(self):
        math = (ROOT / 'docs/MATH.md').read_text()
        for name, digest in PINNED.items():
            self.assertEqual(hashlib.sha256((GLIBC / name).read_bytes()).hexdigest(), digest, name)
            self.assertIn(digest, math, name)

    def test_the_model_s_tables_are_the_pinned_ones(self):
        table = asncs()
        self.assertEqual(len(table), 2568)
        self.assertEqual(model_words('S'), table)
        self.assertEqual(model_words('INROOT'), decimals('root.tbl', 'inroot[128]'))
        self.assertEqual(model_words('POWTWO'), decimals('powtwo.tbl', 'powtwo[]'))
        self.assertEqual(len(model_words('INROOT')), 128)
        self.assertEqual(model_words('POWTWO'), [bits(2.0 ** k) for k in range(28)])

    def test_the_port_s_tables_are_the_pinned_ones_in_the_order_acos_reads_them(self):
        table = asncs()
        # (the list, the entries' first index and step in asncs, the entries, the polynomial's coefficients)
        for name, first, step, count, terms in (('eighth', 0, 11, 32, 5), ('quarter', 352, 11, 64, 5), ('half', 1056, 12, 64, 6),
                                                ('high', 992 + 13 * 64, 13, 44, 7), ('higher', 884 + 14 * 108, 14, 8, 8),
                                                ('highest', 768 + 15 * 116, 15, 4, 9)):
            words, width = bend_words(name), 4 + terms
            self.assertEqual(len(words), count * width, name)
            for row in range(count):
                n = first + step * row
                order = [n] + [n + 1 + i for i in range(terms, 0, -1)] + [n + 1, n + 2 + terms, n + 3 + terms]
                self.assertEqual(words[row * width:(row + 1) * width], [table[i] for i in order], (name, row))
        self.assertEqual(bend_words('inroot'), decimals('root.tbl', 'inroot[128]'))
        self.assertEqual(bend_words('powtwo'), decimals('powtwo.tbl', 'powtwo[]'))

    def test_the_port_s_constants_are_uasncs_h_s(self):
        header = (GLIBC / 'uasncs.h').read_text()
        port = (ROOT / 'src/lgpl/acos.bend').read_text()

        def constant(name):
            found = re.search(rf'def {name}\(\) -> T\.V:\n  T\.Ok\{{(\d+), (\d+)\}}', port)
            return int(found.group(1)) << 32 | int(found.group(2))

        for name in ('f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'rt0', 'rt1', 'rt2', 'rt3'):
            value = re.search(rf'\b{name} = +([-0-9.E+]+)', header).group(1)
            self.assertEqual(constant(name), bits(float(value)), name)
        self.assertEqual((constant('hp0'), constant('hp1')), (0x3FF921FB54442D18, 0x3C91A62633145C07))
        self.assertIn('hp0 = {{0x54442D18, 0x3FF921FB }}', header)
        self.assertIn('hp1 = {{0x33145C07, 0x3C91A626 }}', header)
        self.assertEqual((constant('pi'), constant('t27'), constant('half'), constant('three_halves')),
                         (bits(2.0 * 1.5707963267948966), bits(134217728.0), bits(0.5), bits(1.5)))


class ProbeTests(unittest.TestCase):
    def test_the_arguments_cover_every_interval_entry_and_root(self):
        cases = probe.arguments()
        words = [word for word, _ in cases]
        self.assertEqual(len(words), len(set(words)))
        labels = {label for _, label in cases}
        self.assertEqual(labels, {'random', 'interval', 'promoted-binary32', 'interval-bound', 'table-entry', 'below-one', 'root-table',
                                  'variant-control', 'special', 'outside'})
        for bound in probe.BOUNDS:
            self.assertIn(bound, words)
            self.assertIn(bound | (1 << 63), words)
        magnitudes = [word & 0x7fffffffffffffff for word in words]
        for low, high in zip(probe.BOUNDS, probe.BOUNDS[1:]):
            self.assertGreater(sum(low <= m < high for m in magnitudes), 40)
        # every entry of the table: the high words where an interval's index changes
        entries = probe.entries()
        self.assertEqual(len(entries), 32 + 64 + 120)
        self.assertTrue(all(entry in magnitudes for entry in entries))
        # below 1: every entry of inroot and every power of two from 2^3 up
        roots, powers = set(), set()
        for m in magnitudes:
            if 0x3fef000000000000 <= m < probe.ONE:
                k = probe.bits(0.5 * (1.0 - struct.unpack('<d', struct.pack('<Q', m))[0])) >> 32
                roots.add((k & 0x001fffff) >> 14)
                powers.add(511 - (k >> 21))
        self.assertEqual(roots, set(range(128)))
        self.assertTrue(set(range(3, 27)) <= powers)
        self.assertLessEqual(max(powers), 27)

    def test_the_controls_are_four_an_interval_two_a_sign(self):
        self.assertEqual(len(glibc_acos.CONTROLS), 32)
        self.assertEqual(len({word for word, _ in glibc_acos.CONTROLS}), 32)
        for index, (low, high) in enumerate(zip(probe.BOUNDS, probe.BOUNDS[1:])):
            inside = [word for word, _ in glibc_acos.CONTROLS if low <= (word & 0x7fffffffffffffff) < high]
            self.assertEqual((len(inside), sum(word >> 63 for word in inside)), (4, 2), index)

    def test_the_check_program_names_the_model_and_every_control(self):
        source = glibc_acos.check_source()
        self.assertIn('double glibc_acos_fma(double);', source)
        self.assertNotIn('@', source)
        self.assertEqual(source.count('UINT64_C('), 2 * len(glibc_acos.CONTROLS))
        self.assertIn('printf("%u %u\\n", equal(glibc_acos_fma), equal(host_acos));', source)

    def test_the_candidate_asks_every_profile(self):
        self.assertIn('M.Libm.acos64(M.Glibc239Libm{}, M.Float64{high, low})', probe.PROGRAM)
        self.assertIn('M.Libm.acos64(M.AppleLibm{}, M.Float64{high, low})', probe.PROGRAM)
        self.assertIn('M.Libm.acos64(M.Glibc241Libm{}, M.Float64{high, low})', probe.PROGRAM)


if __name__ == '__main__':
    unittest.main()
