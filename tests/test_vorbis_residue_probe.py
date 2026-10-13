import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_residue_probe as rp
import vorbis_setup_probe as sp


class StreamsTests(unittest.TestCase):
    def test_the_streams_set_up(self):
        files, names, residues = rp.streams()
        made = sp.model(files['packets'])
        self.assertEqual((made[:3], made[3][0], len(made[4]), len(made[6]), residues), ((sp.GOING, 0, 5), rp.CHANNELS, len(names), residues, 11))
        # the names say the codebooks' dimensions
        self.assertEqual([book['dimensions'] for book in made[4]], [rp.DIMENSIONS[name] for name in names])
        # residues of each type; some begin past the vectors' end, some end far past it
        self.assertEqual(({made_[0] for made_ in made[6]}, max(made_[1] for made_ in made[6]) >= 128, max(made_[2] for made_ in made[6]) > 512), ({0, 1, 2}, True, True))
        # every classbook's entries are the classifications to the power of its dimensions, or fewer classes than that
        for made_ in made[6]:
            book = made[4][made_[5]]
            self.assertLessEqual(book['entries'], made_[4] ** book['dimensions'])
        self.assertEqual(sp.model(files['cut'])[:3], (sp.GOING, 0, 5))
        self.assertEqual(rp.streams(), rp.streams())

    def test_the_first_packet_begins_with_a_clear_bit(self):
        files, _, _ = rp.streams()
        from vorbis_ogg_probe import pages
        at, _ = pages(files['packets'])[2]
        count = files['packets'][at + 26]
        self.assertEqual(files['packets'][at + 27 + count] & 1, 0)


class ScriptsTests(unittest.TestCase):
    def setUp(self):
        _, self.names, self.residues = rp.streams()
        self.scripts = rp.scripts(self.names, self.residues)

    def test_the_scripts(self):
        self.assertEqual([name for name, _ in self.scripts], [name for name, _ in rp.scripts(self.names, self.residues)])
        calls = [call for _, script in self.scripts for call in script]
        self.assertEqual({function for function, _, _ in calls}, set(range(5)))
        residues = [(a & 255, a >> 8 & 15, a >> 12 & 15, b) for function, a, b in calls if function == rp.DECODE_RESIDUE]
        self.assertEqual(({number for number, _, _, _ in residues}, {channels for _, channels, _, _ in residues}, {n for _, _, _, n in residues}), (set(range(self.residues)), {1, 2, 3, 4}, {32, 64}))
        self.assertTrue(all(mask < 1 << channels for _, channels, mask, _ in residues))
        self.assertTrue(any(mask == 0 for _, _, mask, _ in residues) and any(mask == 15 for _, _, mask, _ in residues))

    def test_the_woven_vectors_keep_clear_of_what_stb_vorbis_reads_past(self):
        # a call stays clear of the end of the floats, or keeps to the first channel at each vector
        seen = set()
        for name, calls in self.scripts:
            if not name.endswith('-woven'):
                continue
            dimensions = rp.DIMENSIONS[name[:-6]]
            for function, a, b in calls:
                if function != rp.DEINTERLEAVE:
                    continue
                channels, first, place, length, total = b & 7, b >> 3 & 7, b >> 6 & 127, b >> 13 & 255, b >> 21 & 255
                aligned = first == 0 and dimensions % channels == 0
                clear = place * channels + first + total + 2 * dimensions <= length * channels
                self.assertTrue(aligned or clear, (name, channels, first, place, length, total))
                self.assertTrue(1 <= channels <= 4 and first < channels and (a >> 8 & 15) < 1 << channels)
                seen.add('aligned' if aligned and not clear else 'clear')
        self.assertEqual(seen, {'aligned', 'clear'})

    def test_the_refusal(self):
        name, calls = self.scripts[-1]
        function, a, b = calls[-1]
        single = self.names.index('single')
        self.assertEqual((name, function, a & 255, b & 7, b >> 3 & 7, b >> 6 & 127, b >> 13 & 255), ('refused', rp.DEINTERLEAVE, single, 3, 2, 9, 10))
        # 5 values are taken at the end of the floats and the single symbol has 4: len*ch - (p*ch - c) with c added
        self.assertEqual(10 * 3 - (9 * 3 - 2), 5)
        self.assertEqual(rp.DIMENSIONS['single'], 4)


if __name__ == '__main__':
    unittest.main()
