import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_length_probe as lp
import vorbis_ogg_probe as op
import vorbis_setup_probe as sp
import vorbis_wave_probe as wp


def source():
    """Two pages of headers and three of packets with their checksums, as the cases need them."""
    return lp.checksummed(op.page(2, 0, 0, [30]) + op.page(0, 0, 1, [255] * 9 + [40]) + b''.join(op.page(4 if k == 4 else 0, 900 * k, k, [255] * 9 + [12 * k]) for k in (2, 3, 4)))


def valid(data, at):
    size = 27 + data[at + 26] + sum(data[at + 27:at + 27 + data[at + 26]])
    return lp.crc(data[at:at + 22] + bytes(4) + data[at + 26:at + size]) == struct.unpack('<I', data[at + 22:at + 26])[0]


class BuiltTests(unittest.TestCase):
    def test_the_streams(self):
        streams = wp.built()
        self.assertEqual(sorted(streams), ['loud', 'louder', 'quiet', 'stated-less', 'stated-more', 'unsummed'])
        for name, data in streams.items():
            self.assertEqual(sp.model(data)[:4], (sp.GOING, 0, 5, [1, 8000, 64, 256]), name)
            where = op.pages(data)
            self.assertEqual(all(valid(data, at) for at, _ in where), name != 'unsummed', name)
            self.assertEqual(data[where[-1][0] + 5], 4, name)                          # the last page is flagged
        last = lambda name: struct.unpack('<Q', streams[name][op.pages(streams[name])[-1][0] + 6:][:8])[0]
        self.assertEqual([last(name) for name in ('loud', 'quiet', 'stated-less', 'stated-more', 'louder')], [667, 260, 500, 800, 667])
        # the first page of audio states no position: the last page's is the only one
        self.assertEqual(struct.unpack('<Q', streams['loud'][op.pages(streams['loud'])[-2][0] + 6:][:8])[0], wp.UNKNOWN)
        self.assertEqual(len(op.pages(streams['quiet'])), len(op.pages(streams['loud'])) - 1)

    def test_the_quiet_packets(self):
        packets = wp.quiet()
        self.assertEqual((len(packets), len(packets[0])), (1, 5))
        self.assertTrue(all(len(packet) in (11, 12) for packet in packets[0]))


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = source()
        self.cases = wp.cases(self.source)
        self.last = op.pages(self.source)[-1][0]

    def test_the_files(self):
        self.assertEqual(len(self.cases), 14 + 6)
        self.assertEqual(self.cases['whole'], (self.source, '.ogg'))
        self.assertEqual(self.cases['upper'], (self.source, '.OGG'))
        self.assertEqual({token for name, (_, token) in self.cases.items() if name != 'upper'}, {'.ogg'})
        self.assertEqual(wp.cases(self.source), self.cases)                           # seeded

    def test_the_cut_copies(self):
        second = op.pages(self.source)[1][0]
        self.assertEqual([len(self.cases[name][0]) for name in ('cut-page', 'cut-inside', 'cut-setup', 'cut-header')], [self.last, len(self.source) - 1, second + 2000, 20])
        self.assertTrue(all(self.source.startswith(self.cases[name][0]) for name in ('cut-page', 'cut-inside', 'cut-setup', 'cut-header')))

    def test_the_damaged_copies_keep_their_checksums(self):
        where = wp.bodies(self.source)
        for name in ('bits-0', 'bits-1'):
            data = self.cases[name][0]
            self.assertTrue(len(data) == len(self.source) and data != self.source, name)
            self.assertTrue(all(valid(data, at) for at, _ in op.pages(data)), name)
            # the packets' bytes and the checksums of their pages, nothing else
            changed = [at for at in range(len(data)) if data[at] != self.source[at]]
            starts = [at for at, _ in op.pages(data)]
            self.assertTrue(all(any(start <= at < end for start, end in where) or any(start + 22 <= at < start + 26 for start in starts) for at in changed), name)

    def test_the_last_page_s_positions(self):
        wanted = {'unknown': wp.UNKNOWN, 'zero': 0, 'fewer': 30000, 'more': 50000, 'past-32-bits': 0x100000000, 'past-an-int': 0x60000000}
        for name, granule in wanted.items():
            data = self.cases[name][0]
            self.assertEqual(struct.unpack('<Q', data[self.last + 6:self.last + 14])[0], granule, name)
            self.assertTrue(valid(data, self.last), name)
        # frames times two channels: past an int, and past an unsigned int
        self.assertTrue(0x60000000 * 2 >= 1 << 31 and 0xFFFFFFFE * 2 >= 1 << 32)


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_raudio(self):
        self.assertTrue(wp.NATIVE.startswith('#include "raudio.c"'))
        self.assertIn('Wave wave = LoadWave(files[a]);', wp.NATIVE)
        self.assertIn('if (!whole(files[a])) { printf("none\\n"); continue; }', wp.NATIVE)
        self.assertIn('fine = fine && (unsigned)n == frames;', wp.NATIVE)
        self.assertIn('-ffp-contract=off', wp.FLAGS)
        self.assertIn('-DMA_ENABLE_NULL', wp.FLAGS)

    def test_the_candidate_loads_under_the_profile(self):
        text = wp.render('Glibc239Libm')([('whole', 'a/b.ogg')], False)
        self.assertIn('J.Wave.load_for(M.Glibc239Libm{}, "a/b.ogg")', text)
        self.assertTrue(text.endswith('    IO.print("done")\n'))
        self.assertEqual(wp.parse('w1/2/16/1/5 s0\ndone\n', [('whole', 'a/b.ogg')]), ['w1/2/16/1/5 s0'])
        with self.assertRaises(ValueError):
            wp.parse('w1/2/16/1/5 s0\n', [('whole', 'a/b.ogg')])


if __name__ == '__main__':
    unittest.main()
