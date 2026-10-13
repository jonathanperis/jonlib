import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_frame_probe as fp
import vorbis_length_probe as lp
import vorbis_ogg_probe as op
import vorbis_setup_probe as sp
from vorbis_codebook_probe import Rng


def source():
    """Two pages of headers and three of packets with their checksums, as the cases need them."""
    return lp.checksummed(op.page(2, 0, 0, [30]) + op.page(0, 0, 1, [255, 40]) + b''.join(op.page(4 if k == 4 else 0, 900 * k, k, [255] * 9 + [12 * k]) for k in (2, 3, 4)))


def valid(data, at):
    """Whether the page at `at` has the checksum it states."""
    size = 27 + data[at + 26] + sum(data[at + 27:at + 27 + data[at + 26]])
    return len(data) >= at + size and lp.crc(data[at:at + 22] + bytes(4) + data[at + 26:at + size]) == struct.unpack('<I', data[at + 22:at + 26])[0]


class ChecksumTests(unittest.TestCase):
    def test_the_table(self):
        self.assertEqual((len(lp.TABLE), lp.TABLE[0], lp.TABLE[1], lp.TABLE[255]), (256, 0, 0x04C11DB7, 0xB1F740B4))

    def test_the_checksum(self):
        self.assertEqual((lp.crc(b''), lp.crc(bytes(9)), lp.crc(b'\x01')), (0, 0, 0x04C11DB7))
        self.assertEqual(lp.crc(b'OggS'), 1605413199)
        # the polynomial of CRC-32/MPEG-2 from 0 and without its last inversion: zlib's reflected one is another
        self.assertNotEqual(lp.crc(b'123456789'), zlib.crc32(b'123456789'))
        self.assertEqual(lp.crc(b'123456789'), 0x89A1897F)

    def test_a_page_with_its_checksum(self):
        made = lp.summed(op.page(4, 77, 9, []))
        self.assertEqual(list(made[22:26]), [188, 39, 167, 220])
        self.assertTrue(valid(made, 0))
        self.assertFalse(valid(op.page(4, 77, 9, []), 0))
        two = op.page(0, 5, 1, [3]) + op.page(4, 9, 2, [200, 7])
        self.assertTrue(valid(lp.summed(two, 31), 31) and not valid(lp.summed(two, 31), 0))
        both = lp.checksummed(two)
        self.assertTrue(valid(both, 0) and valid(both, 31))
        self.assertEqual(lp.summed(both, 31), both)

    def test_a_page_of_seeded_bytes(self):
        made = lp.junk(Rng(5), 7, 1234, [255, 20], flag=4)
        self.assertEqual((len(made), made[5], struct.unpack('<Q', made[6:14])[0], struct.unpack('<I', made[18:22])[0]), (27 + 2 + 275, 4, 1234, 7))
        self.assertTrue(valid(made, 0))


class BuiltTests(unittest.TestCase):
    def setUp(self):
        self.streams = lp.built()

    def test_the_streams(self):
        self.assertEqual(len(self.streams), 15)
        loose = {'big-junk-after', 'big-some-after', 'table-cut', 'zeros-cut', 'header-cut'}       # what follows their pages is no page
        for name, data in self.streams.items():
            if name not in loose:
                self.assertEqual(sp.model(data)[:3], (sp.GOING, 0, 5), name)
            self.assertEqual(name.startswith('big'), len(data) > 65536 + 4096, name)

    def test_the_big_streams_pages(self):
        where = op.pages(self.streams['big'])
        self.assertEqual(len(where), 6)                                              # two of headers, one of audio, three of bytes
        self.assertTrue(all(valid(self.streams['big'], at) for at, _ in where))
        self.assertEqual([self.streams['big'][at + 5] for at, _ in where][-3:], [0, 0, 4])
        self.assertEqual([self.streams['big-early-last'][at + 5] for at, _ in op.pages(self.streams['big-early-last'])][-4:], [0, 0, 4, 0])
        self.assertEqual({self.streams['big-none-last'][at + 5] for at, _ in op.pages(self.streams['big-none-last'])[1:]}, {0})
        # the search begins 64 KiB before the end: inside the first page of bytes, before what is put in its body
        for name in ('big-captures', 'big-page-inside'):
            data = self.streams[name]
            at, size = op.pages(data)[3]
            inside = data.index(b'OggS', at + 4)
            self.assertTrue(at < len(data) - 65536 < inside < at + size, name)
        data = self.streams['big-page-inside']
        inner = data.index(b'OggS', data.index(b'OggS', op.pages(data)[3][0] + 4) + 4)
        self.assertTrue(valid(data, inner) and data[inner + 5] == 4 and data[inner + 26] == 0)
        data = self.streams['big-captures']
        inner = data.index(b'OggS', data.index(b'OggS', op.pages(data)[3][0] + 4) + 4)
        self.assertFalse(valid(data, inner))

    def test_what_follows_the_pages(self):
        base = len(lp.checksummed(fp.headers(5) + fp.audio(fp.blocks(), [500, 800], last=-1)))
        cut = self.streams['table-cut']
        self.assertEqual((cut[base:base + 4], cut[base + 26], len(cut) - base - 27), (b'OggS', 255, 59))      # a table of 255 with 59 bytes left
        self.assertTrue(valid(cut, base + 27))
        self.assertEqual((len(self.streams['zeros-cut']) - base, len(self.streams['header-cut']) - base), (27 + 12 - 5, 20))
        self.assertTrue(len(self.streams['big-junk-after']) > 65536 + 66000)
        self.assertEqual(self.streams['big-some-after'][-2:], b'Og')
        self.assertFalse(any(valid(self.streams['unsummed'], at) for at, _ in op.pages(self.streams['unsummed'])))
        # audio on the setup's page: a page fewer
        self.assertEqual(len(op.pages(self.streams['shared-page'])), len(op.pages(self.streams['small'])) - 1)


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = source()
        self.cases = lp.cases(self.source)
        self.last, self.size = op.pages(self.source)[-1]

    def test_the_files_and_their_calls(self):
        self.assertEqual(len(self.cases), 17 + 15)
        self.assertEqual(self.cases['whole'], (self.source, lp.FIRST))
        self.assertEqual((lp.FIRST[0], lp.FIRST[1]), (lp.LENGTH, 88200))              # the length first, as LoadWave asks
        self.assertEqual(lp.AFTER[:2], [lp.MOST, lp.LENGTH])
        for name, (_, calls) in self.cases.items():
            self.assertTrue(lp.LENGTH in calls and all(op == lp.LENGTH or 0 <= op <= lp.MOST for op in calls), name)

    def test_the_cut_copies(self):
        cuts = sorted(len(data) for name, (data, _) in self.cases.items() if name.startswith('cut-'))
        self.assertEqual(cuts, [self.last - 700, self.last, self.last + 40, len(self.source) - 1])
        self.assertTrue(all(self.source.startswith(data) for name, (data, _) in self.cases.items() if name.startswith('cut-')))

    def test_the_last_page_s_edits(self):
        for name, granule in (('unknown', 0xFFFFFFFFFFFFFFFF), ('past-32-bits', 0x100000000), ('zero', 0), ('early', 30000), ('high-ones', 0xFFFFFFFF00000005), ('low-ones', 0xFFFFFFFF)):
            data = self.cases[name][0]
            self.assertEqual(struct.unpack('<Q', data[self.last + 6:self.last + 14])[0], granule, name)
            self.assertTrue(valid(data, self.last), name)
            self.assertEqual(data[:self.last], self.source[:self.last], name)
        self.assertTrue(self.cases['version'][0][self.last + 4] == 1 and valid(self.cases['version'][0], self.last))
        self.assertTrue(self.cases['unflagged'][0][self.last + 5] == 0 and valid(self.cases['unflagged'][0], self.last))
        # a body's byte changed leaves the checksum wrong
        self.assertFalse(valid(self.cases['body-last'][0], self.last))
        first = op.pages(self.source)[2][0]
        self.assertFalse(valid(self.cases['body-first'][0], first))
        self.assertTrue(valid(self.cases['body-first'][0], self.last))


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_the_frame_gate_s_with_the_length(self):
        self.assertIn('static unsigned digest(stb_vorbis *f)', lp.NATIVE)
        self.assertIn('static int clean(stb_vorbis *f, int channels, int num_shorts)', lp.NATIVE)
        self.assertEqual(lp.NATIVE.count('static void run('), 1)
        self.assertNotIn('static void floats(', lp.NATIVE)
        self.assertIn('got = stb_vorbis_stream_length_in_samples(f);', lp.NATIVE)
        self.assertIn('if (VORBIS_cant_find_last_page != 36) return 8;', lp.NATIVE)
        self.assertNotIn('MOST', lp.NATIVE)

    def test_the_candidate_is_the_frame_gate_s_with_the_length(self):
        self.assertIn('def digest(frames: Fr.Frames) -> U32:', lp.PROGRAM)
        self.assertEqual(lp.PROGRAM.count('type Run is Data:'), 1)
        self.assertIn('import ../../src/vorbis_length.bend as L\n', lp.PROGRAM)
        self.assertIn('L.stream.length(Run.frames(run), first, Run.kept(run))', lp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
