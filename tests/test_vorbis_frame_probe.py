import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_frame_probe as fp
import vorbis_ogg_probe as op
import vorbis_setup_probe as sp


def source():
    """Two pages of headers and three of packets, as the cases need them."""
    return op.page(2, 0, 0, [30]) + op.page(0, 0, 1, [255, 40]) + b''.join(op.page(4 if k == 4 else 0, 900 * k, k, [255] * 9 + [12 * k]) for k in (2, 3, 4))


class BuiltTests(unittest.TestCase):
    def test_an_integer_as_a_vorbis_float(self):
        self.assertEqual(fp.packed(1), 788 << 21 | 1)
        self.assertEqual(fp.packed(-20), 0x80000000 | 788 << 21 | 20)
        self.assertEqual(fp.packed(0), 788 << 21)

    def test_the_headers(self):
        made = sp.model(fp.headers(20))
        self.assertEqual(made[:4], (sp.GOING, 0, 5, [1, 8000, 64, 256]))
        books, floors, residues, mappings, modes = made[4:9]
        self.assertEqual((len(books), len(floors), len(residues), len(mappings)), (2, 1, 1, 1))
        self.assertEqual(floors[0][2:5], [1, 5, [0, 32]])                             # two points, at 0 and 32
        self.assertEqual(residues[0][:6], [1, 0, 32, 8, 1, 0])                        # type 1, 32 values in partitions of 8
        self.assertEqual(modes, [[0, 0], [1, 0]])                                     # a short block's mode and a long one's

    def test_a_packet(self):
        short = sp.Packet(fp.packet(0, fp.one(3)))
        self.assertEqual([short.bits(1), short.bits(1), short.bits(1), short.bits(8), short.bits(8)], [0, 0, 1, 255, 255])
        values = []
        for _ in range(4):
            self.assertEqual(short.bits(1), 0)                                         # the partition's class
            values += [short.bits(1) << 1 | short.bits(1) for _ in range(8)]           # a code's first bit is read first
        self.assertEqual(values, fp.one(3))
        long = sp.Packet(fp.packet(1, [0] * 32, before=0, after=1, y=(7, 9)))
        self.assertEqual([long.bits(1), long.bits(1), long.bits(1), long.bits(1), long.bits(1), long.bits(8), long.bits(8)], [0, 1, 0, 1, 1, 7, 9])
        self.assertEqual((len(fp.packet(0, [0] * 32)), len(fp.packet(1, [0] * 32))), (11, 12))    # 87 bits, and two more

    def test_the_pages_of_packets(self):
        groups = [[b'abc', b'de'], [b'f' * 40], [b'gh']]
        data = fp.audio(groups, [100, 200, 0xFFFFFFFFFFFFFFFF])
        where = op.pages(data)
        self.assertEqual(len(where), 3)
        self.assertEqual([data[at + 5] for at, _ in where], [0, 0, 4])                # the last page is flagged
        self.assertEqual([struct.unpack('<Q', data[at + 6:at + 14])[0] for at, _ in where], [100, 200, 0xFFFFFFFFFFFFFFFF])
        self.assertEqual([struct.unpack('<I', data[at + 18:at + 22])[0] for at, _ in where], [2, 3, 4])
        self.assertEqual((data[26], list(data[27:29]), data[29:34]), (2, [3, 2], b'abcde'))   # a segment a packet
        self.assertEqual([fp.audio(groups, [1, 2, 3], last=1)[at + 5] for at, _ in where], [0, 4, 0])

    def test_the_streams(self):
        streams = fp.built()
        self.assertEqual(len(streams), 14)
        for name, data in streams.items():
            self.assertEqual(sp.model(data)[:3], (sp.GOING, 0, 5), name)
            where = op.pages(data)
            self.assertEqual(sum(size for _, size in where), len(data), name)
        flags = lambda name: [streams[name][at + 5] for at, _ in op.pages(streams[name])]
        self.assertEqual(flags('loud')[-2:], [0, 4])
        self.assertEqual(flags('after-last-730')[-3:], [0, 4, 0])                     # pages after the last
        # the loudness is the codebook's alone: the packets are the same
        self.assertEqual(streams['loud'][-200:], streams['louder'][-200:])
        self.assertNotEqual(streams['loud'], streams['louder'])
        self.assertEqual(len({bytes(data) for data in streams.values()}), 14)
        # audio packets on the setup's page: one page fewer than their own page would make
        self.assertEqual(len(op.pages(streams['shared-page'])), len(op.pages(streams['loud'])) - 1)
        self.assertEqual(fp.headers(5, more=[b'ab'])[-2:], b'ab')


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = source()
        self.cases = fp.cases(self.source)

    def test_the_files_and_their_calls(self):
        self.assertEqual(len(self.cases), 22)
        self.assertEqual(self.cases['whole'], (self.source, fp.WHOLE))
        self.assertEqual(self.cases['stream'], (self.source, fp.STREAM))
        self.assertEqual(fp.cases(self.source), self.cases)                           # seeded
        for name, (data, calls) in self.cases.items():
            self.assertTrue(calls and all(0 <= op <= fp.MOST for op in calls), name)
        cuts = [data for name, (data, _) in self.cases.items() if name.startswith('cut-') and name[4].isdigit()]
        self.assertEqual(len(cuts), 2)
        self.assertTrue(all(self.source.startswith(data) and len(data) < len(self.source) for data in cuts))
        self.assertEqual(self.cases['loud-whole'][0], self.cases['loud'][0])
        self.assertEqual(self.cases['loud-whole'][1][0], fp.MOST)

    def test_the_damage_is_in_the_packets(self):
        where = fp.bodies(self.source)
        for name in ('bits-0', 'bits-1', 'bytes-0'):
            data = self.cases[name][0]
            changed = [at for at in range(len(data)) if data[at] != self.source[at]]
            self.assertTrue(changed and len(data) == len(self.source), name)
            self.assertTrue(all(any(start <= at < end for start, end in where) for at in changed), name)

    def test_the_calls(self):
        self.assertEqual(fp.WHOLE[0], 44100 * 2)                                      # target.ogg's samples, as LoadWave asks
        self.assertIn(0, fp.STREAM)
        self.assertIn(0, fp.STEPS)
        self.assertTrue(any(op % 2 for op in fp.STREAM) and 1 in fp.STREAM)            # counts that are not whole frames of two channels
        self.assertEqual(fp.STREAM[:6], [4096] * 6)


class WordsTests(unittest.TestCase):
    def test_the_table(self):
        words = fp.words()
        self.assertEqual(fp.words(), words)
        self.assertEqual(len(words), 12 + 17 * 6 + 160 + 40)
        self.assertTrue(all(0 <= word < 1 << 32 for word in words))
        for word in (0, 0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0x3F800000, 0xBF800000, 0xC3C00000, 0xC3C00001, 0xC4400000, 0xC43FFFFF):
            self.assertIn(word, words)
        band = [word for word in words[-40:]]
        self.assertTrue(all(0xC3BFFFFF <= word <= 0xC4400000 for word in band))

    def test_the_reference_holds_the_macro(self):
        self.assertIn('MAGIC(15)', fp.NATIVE)
        self.assertIn('if (w != 0x43C00000u || (unsigned)ADDEND(15) != 0x43C00000u) return 8;', fp.NATIVE)
        self.assertIn('stb_vorbis_get_samples_short_interleaved(f, f->channels, shorts, ops[k])', fp.NATIVE)
        self.assertIn('if (digest(shadow) != digest(f)) exit(7);', fp.NATIVE)
        self.assertNotIn('MOST', fp.NATIVE)
        self.assertIn('-ffp-contract=off', fp.FLAGS)


if __name__ == '__main__':
    unittest.main()
