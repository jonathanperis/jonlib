import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_ogg_probe as op
import vorbis_packet_probe as pp


def stream():
    """Two pages of headers and three of packets, as the cases need them."""
    return op.page(2, 0, 0, [30]) + op.page(0, 0, 1, [255, 40]) + b''.join(op.page(4 if k == 4 else 0, 900 * k, k, [255] * 9 + [12 * k]) for k in (2, 3, 4))


def bits(a, b):
    return sum(bin(x ^ y).count('1') for x, y in zip(a, b))


class BodiesTests(unittest.TestCase):
    def test_the_packets_bytes_of_the_audio_pages(self):
        data = stream()
        where = pp.bodies(data)
        pages = op.pages(data)
        self.assertEqual(len(where), 3)
        self.assertEqual(where[0], (pages[2][0] + 27 + 10, pages[3][0]))             # after the page's header and its 10 segments
        self.assertEqual([end - start for start, end in where], [9 * 255 + 24, 9 * 255 + 36, 9 * 255 + 48])
        self.assertEqual(where[-1][1], len(data))


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = stream()
        self.cases = pp.cases(self.source)
        self.where = pp.bodies(self.source)

    def inside(self, data):
        """Whether a copy differs from the source in its packets' bytes alone."""
        return len(data) == len(self.source) and all(any(start <= at < end for start, end in self.where) for at in range(len(data)) if data[at] != self.source[at])

    def test_the_names(self):
        self.assertEqual(len(self.cases), 12)
        self.assertEqual([name.split('-')[0] for name in self.cases], ['whole'] + ['cut'] * 4 + ['bits'] * 4 + ['bytes'] * 3)
        self.assertEqual(pp.cases(self.source), self.cases)                           # seeded: the same files each run
        self.assertEqual(len(set(self.cases.values())), 12)

    def test_the_cut_copies(self):
        self.assertEqual(self.cases['whole'], self.source)
        cuts = [data for name, data in self.cases.items() if name.startswith('cut-')]
        self.assertTrue(all(self.source.startswith(data) and len(data) < len(self.source) for data in cuts))
        # in the first audio page's first packet, further in it, in the second page and at the stream's end
        start = self.where[0][0]
        self.assertEqual([len(data) for data in cuts], [start + 1, start + 700, self.where[1][0] + 2000, len(self.source) - 3])

    def test_the_damage_is_in_the_packets(self):
        for index in range(4):
            data = self.cases[f'bits-{index}']
            self.assertTrue(self.inside(data))
            self.assertTrue(1 <= bits(data, self.source) <= 1 + index % 4)
        for index in range(3):
            data = self.cases[f'bytes-{index}']
            self.assertTrue(self.inside(data))
            changed = [at for at in range(len(data)) if data[at] != self.source[at]]
            start, end = self.where[index]
            self.assertTrue(start <= changed[0] and changed[-1] < end and changed[-1] - changed[0] < 64 and len(changed) >= 2)
        # the pages are where they were: no header or segment table is touched
        self.assertTrue(all(op.pages(data) == op.pages(self.source) for name, data in self.cases.items() if not name.startswith('cut-')))


class ProgramTests(unittest.TestCase):
    def test_both_sides_decode_as_many_packets(self):
        self.assertEqual(pp.CALLS, 120)
        self.assertIn('for (k = 0; k < 120; k++)', pp.NATIVE)
        self.assertIn('run(120n, 0, 2166136261, 0, 0, plan, state, "[")', pp.PROGRAM)
        self.assertNotIn('CALLS', pp.NATIVE + pp.PROGRAM)

    def test_the_reference_is_the_static_function(self):
        self.assertIn('#include "external/stb_vorbis.c"', pp.NATIVE)
        self.assertIn('vorbis_decode_packet(&p, &length, &left, &right)', pp.NATIVE)
        self.assertIn('-ffp-contract=off', pp.FLAGS)
        self.assertIn('-D_DEFAULT_SOURCE', pp.FLAGS)                                 # without it stb_vorbis's M_PI is a float

    def test_what_is_hashed(self):
        for name in ('current_loc', 'current_loc_valid', 'discard_samples_deferred', 'channel_buffers', 'known_loc_for_packet', 'valid_bits', 'last_seg_which'):
            self.assertIn(name, pp.NATIVE)
        for name in ('known_seg', 'known_loc', 'discard', 'mixed.rows(rows'):
            self.assertIn(name, pp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
