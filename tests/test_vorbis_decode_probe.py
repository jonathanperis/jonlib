import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_decode_probe as dp
import vorbis_setup_probe as sp
from vorbis_ogg_probe import pages


class StreamsTests(unittest.TestCase):
    def test_the_streams_set_up(self):
        files, names = dp.streams()
        self.assertEqual((sorted(files), len(names), len(set(names))), (['cut', 'packets', 'unflagged'], 12, 12))
        made = sp.model(files['packets'])
        self.assertEqual((made[:3], len(made[4])), ((sp.GOING, 0, 5), 12))
        # one codebook for each way a symbol is found
        by = dict(zip(names, made[4]))
        self.assertEqual((by['sparse']['sparse'], by['sparse-small']['sparse'], by['none']['sparse'], by['sorted']['sparse']), (1, 1, 1, 0))
        self.assertEqual((by['fast']['entries'], by['searched']['entries'], by['searched-incomplete']['entries'], by['one']['entries']), (8, 8, 12, 1))
        self.assertEqual({by[name]['lookup'] for name in names}, {0, 2})                 # lookups are type 2 once read
        self.assertEqual((by['fast-sequence']['sequence'], by['fast-lookup-1']['sequence']), (1, 0))
        self.assertEqual(sp.model(files['cut'])[:3], (sp.GOING, 0, 5))

    def test_the_packets_follow_the_headers(self):
        files, _ = dp.streams()
        where = pages(files['packets'])
        self.assertTrue(len(where) == 3 and sum(size for _, size in where) == len(files["packets"]))   # the two pages of headers, one of packets
        self.assertEqual(len(files['cut']), sum(size for _, size in where[:2]) + 900)
        # the unflagged stream: a page of two full segments, then a page that does not say it goes on
        at = sum(size for _, size in where[:2])
        data = files['unflagged']
        self.assertEqual((data[at + 5], list(data[at + 27:at + 29]), data[at + 29 + 510 + 5], data[at + 29 + 510 + 26]), (0, [255, 255], 0, 3))

    def test_the_streams_are_seeded(self):
        self.assertEqual(dp.streams(), dp.streams())


class ScriptsTests(unittest.TestCase):
    def test_the_scripts(self):
        _, names = dp.streams()
        scripts = dp.scripts(names)
        self.assertEqual([name for name, _, _ in scripts], [name for name, _, _ in dp.scripts(names)])
        calls = [call for _, script, _ in scripts for call in script]
        self.assertEqual({function for function, _, _ in calls}, set(range(10)))                                    # every function
        self.assertEqual({a for function, a, _ in calls if function == dp.GET_BITS}, set(range(33)))               # every width
        self.assertTrue(all(a < len(names) for function, a, _ in calls if function in (dp.DECODE_RAW, dp.DECODE, dp.SCALAR_RAW, dp.CODEBOOK_DECODE, dp.CODEBOOK_DECODE_STEP)))
        # the floats a vector is added to stay inside the 64: place + count * step
        for function, _, b in calls:
            if function == dp.CODEBOOK_DECODE:
                self.assertLessEqual((b & 63) + (b >> 6 & 63), 64)
            if function == dp.CODEBOOK_DECODE_STEP:
                self.assertLess((b & 63) + max((b >> 6 & 63) - 1, 0) * (b >> 12 & 63), 64)

    def test_what_the_port_refuses_is_not_run(self):
        _, names = dp.streams()
        scripts = dp.scripts(names)
        none = names.index('none')
        refused = {name: files for name, _, files in scripts if files}
        self.assertEqual(refused, {'decode-none': ('packets', 'cut', 'unflagged'), 'past-unflagged': ('unflagged',), 'past-unflagged-prep': ('unflagged',)})
        # DECODE of the codebook without a code is in no other script
        for name, calls, _ in scripts:
            if name != 'decode-none':
                self.assertFalse(any(function == dp.DECODE and a == none for function, a, _ in calls), name)
        # the bits of the unflagged stream's first packet: 170 reads of 24 bits are its 510 bytes
        past = dict((name, calls) for name, calls, _ in scripts)['past-unflagged']
        self.assertEqual(sum(a for function, a, _ in past[1:171]), 510 * 8)


if __name__ == '__main__':
    unittest.main()
