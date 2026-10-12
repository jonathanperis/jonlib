import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp3_layer3_probe as lp
from probekit import ProbeFailure

HEADER = '''static void drmp3_L3_huffman(float *dst, drmp3_bs *bs, const drmp3_L3_gr_info *gr_info, const float *scf, int layer3gr_limit)
{
    if (x)
    {
        y();
    }
    bs->pos = layer3gr_limit;
}

static void drmp3_L3_decode(drmp3dec *h, drmp3dec_scratch *s, drmp3_L3_gr_info *gr_info, int nch)
{
        drmp3_L3_huffman(s->grbuf[ch], &s->bs, gr_info + ch, s->scf, layer3gr_limit);
    for (ch = 0; ch < nch; ch++, gr_info++)
    {
        int aa_bands = 31;
            drmp3_L3_reorder(s->grbuf[ch] + n_long_bands*18, s->syn[0], gr_info->sfbtab + gr_info->n_long_sfb);
        drmp3_L3_change_sign(s->grbuf[ch]);
    }
}

DRMP3_API int drmp3dec_decode_frame(drmp3dec *dec, const drmp3_uint8 *mp3, int mp3_bytes, void *pcm, drmp3dec_frame_info *info)
{
                drmp3_L3_decode(dec, &dec->scratch, dec->scratch.gr_info + igr*info->channels, info->channels);
}
'''


class ReferenceTests(unittest.TestCase):
    def test_the_three_functions_are_copied_with_their_lines(self):
        source = lp.reference(HEADER, ['/tmp/a.mp3', '/tmp/b.mp3'])
        self.assertEqual((source.count('static void probe_L3_huffman('), source.count('static void probe_L3_decode('), source.count('static int probe_decode_frame(')), (1, 1, 1))
        self.assertIn('probe_outside = 1;\n    bs->pos = layer3gr_limit;\n}\n', source)
        self.assertIn('        probe_L3_huffman(s->grbuf[ch], &s->bs, gr_info + ch, s->scf, layer3gr_limit);\n    for (ch = 0; ch < nch; ch++, gr_info++)\n', source)
        self.assertIn('        drmp3_L3_change_sign(s->grbuf[ch]);\n        probe_values = probe_words(probe_values, s->grbuf[ch], 576);\n', source)
        self.assertIn('if (probe_end > 576) probe_outside = 1; }\n            drmp3_L3_reorder(s->grbuf[ch] + n_long_bands*18, ', source)
        self.assertIn('                probe_L3_decode(dec, &dec->scratch, ', source)
        self.assertIn('{ "/tmp/a.mp3", "/tmp/b.mp3" }', source)
        self.assertEqual(lp.function(HEADER, 'static void drmp3_L3_decode(drmp3dec *h, drmp3dec_scratch *s, drmp3_L3_gr_info *gr_info, int nch)').count('\n'), 10)

    def test_another_header_is_refused(self):
        with self.assertRaises(ProbeFailure):
            lp.reference(HEADER.replace('    bs->pos = layer3gr_limit;\n', ''), [])
        with self.assertRaises(ProbeFailure):
            lp.reference(HEADER.replace('static void drmp3_L3_decode(', 'static void drmp3_L3_decoded('), [])
        with self.assertRaises(ProbeFailure):
            lp.patched('a b a', [('a', 'c')])


class FrameTests(unittest.TestCase):
    def test_bits_are_written_the_first_the_highest(self):
        writer = lp.Writer()
        writer.put(5, 3)
        writer.put(1, 9)
        self.assertEqual(writer.bytes(), bytes([0b10100000, 0b00010000]))

    def test_frame_sizes(self):
        self.assertEqual([lp.frame_size(3, 9, 0, 0), lp.frame_size(3, 9, 0, 1), lp.frame_size(3, 14, 2, 0), lp.frame_size(2, 8, 1, 0), lp.frame_size(0, 1, 2, 0)], [417, 418, 1440, 192, 72])
        self.assertEqual([lp.side_size(3, False), lp.side_size(3, True), lp.side_size(2, False), lp.side_size(0, True)], [32, 17, 17, 9])
        self.assertEqual(lp.header(3, False, 9, 0, 0, 1), bytes([0xFF, 0xFB, 0x90, 0x40]))            # country.mp3's but for its mode extension
        self.assertEqual(lp.header(0, True, 1, 2, 1, 3, 0x7F), bytes([0xFF, 0xE2, 0x1B, 0xFF]))

    def test_side_information_fills_its_bytes(self):
        long = lp.granule(3, 4095, 511, 255, 15, None, (31, 31, 31), (15, 7), preflag=1, scale=1, count1=1)
        switching = lp.granule(3, 0, 0, 0, 0, 2, (1, 2, 0), gains=(7, 0, 7), mixed=1)
        self.assertEqual((sum(bits for _, bits in long), sum(bits for _, bits in switching), sum(bits for _, bits in lp.granule(2, 1, 2, 3, 4))), (59, 59, 63))
        stereo = lp.side_info(3, False, 511, 7, [15, 15], [long] * 4)
        # every bit set but each granule's window switching flag, 33 bits into its 59 (after 20 bits of frame fields)
        bits = ''.join(format(byte, '08b') for byte in stereo)
        self.assertEqual((len(stereo), [at for at, bit in enumerate(bits) if bit == '0']), (32, [20 + 59 * index + 33 for index in range(4)]))
        mono = lp.side_info(2, True, 255, 0, [], [lp.granule(2, 0, 0, 0, 0)])
        self.assertEqual((len(mono), mono[0], mono[1:]), (9, 255, bytes(8)))
        # a switching granule: 33 bits of zeros, the flag, block type 2, mixed, tables 1 and 2, gains 7, 0, 7
        writer = lp.Writer()
        for value, count in switching:
            writer.put(value, count)
        self.assertEqual(writer.bits[33:56], [1, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1])
        with self.assertRaises(ValueError):
            lp.side_info(3, True, 0, 0, [0], [long] * 4)

    def test_noise(self):
        rng = random.Random(1)
        self.assertEqual((len(lp.noise(rng, 64, 0.5)), lp.noise(rng, 8, 0.0), lp.noise(rng, 3, 1.0)), (64, bytes(8), b'\xff' * 3))


class CorpusTests(unittest.TestCase):
    def test_a_synthetic_stream_is_whole_frames_of_one_version_and_rate(self):
        data, drawn = lp.synthetic(random.Random(7), 2, 1, 12, 0.5)
        at, frames = 0, 0
        while at < len(data):
            self.assertEqual((data[at], data[at + 1] & 0xFE, data[at + 2] & 0x0C), (0xFF, 0xF2, 0x04))
            at += lp.frame_size(2, data[at + 2] >> 4, 1, data[at + 2] >> 1 & 1)
            frames += 1
        self.assertEqual((at, frames, drawn['frames']), (len(data), 12, 12))
        self.assertEqual(lp.synthetic(random.Random(7), 2, 1, 12, 0.5)[0], data)
        plain, _ = lp.synthetic(random.Random(7), 0, 2, 12, 0.5, mixed=False)
        self.assertEqual(lp.synthetic(random.Random(7), 0, 2, 12, 0.5, mixed=False)[1]['mixed'], 0)
        self.assertGreater(lp.synthetic(random.Random(7), 0, 2, 12, 0.5)[1]['mixed'], 0)
        free, _ = lp.synthetic(random.Random(7), 3, 0, 5, 0.5, free=300)
        self.assertEqual((len(free), [free[at + 2] >> 4 for at in range(0, 1500, 300)]), (1500, [0] * 5))

    def test_the_stream_that_leaves_the_array(self):
        data = lp.outside()
        self.assertEqual((len(data), [data[at:at + 4] for at in range(0, 9212, 2303)]), (4 * 2303, [bytes([0xFF, 0xFB, 0x00, 0x00])] * 4))
        second = data[2303:4606]
        self.assertEqual((second[4], second[5] >> 7), (255, 1))                # main_data_begin 511
        # the last granule's values begin at bit 12285 of the main data, 511 bytes of it the frame before's
        start = (4 + 32) * 8 + 3 * 4095 - 511 * 8
        bits = ''.join(format(byte, '08b') for byte in second)
        self.assertEqual((bits[start - 8:start], bits[start:start + 36], bits[start + 36:start + 44]), ('0' * 8, '00000011' + '1' * 28, '00000011'))

    def test_the_other_layers_are_whole_frames(self):
        rng = random.Random(3)
        first, second = lp.other_layer(rng, True), lp.other_layer(rng, False)
        self.assertEqual((len(first), first[:4], len(second), second[417:421]), (4 * 136, bytes([0xFF, 0xFF, 0x40, 0]), 4 * 417, bytes([0xFF, 0xFD, 0x80, 0])))


class RowsTests(unittest.TestCase):
    def test_a_file_is_its_lines_joined(self):
        text = lp.render([('a', 'x/a.mp3'), ('b', 'x/b.mp3')], False)
        self.assertEqual((text.count('J.Files.load_data('), text.count('"x/b.mp3"'), text.rstrip().endswith('IO.print("done")')), (2, 1, True))
        rows = lp.parse('frames\n1152:417:1:2\n0:5:3:4\nframes\nunread\nframes\nrefused\ndone\n', [1, 2, 3, 4])
        self.assertEqual(rows, ['frames 1152:417:1:2 0:5:3:4', 'frames', 'unread', 'frames refused'])
        with self.assertRaises(ValueError):
            lp.parse('frames\n', [1])
        with self.assertRaises(ValueError):
            lp.parse('1152:417:1:2\ndone\n', [1])

    def test_the_first_frame_that_differs_is_named(self):
        self.assertEqual(lp.first_difference('frames 1:2:3:4 5:6:7:8', 'frames 1:2:3:4 5:6:7:9'), 'frame 1: raylib=5:6:7:8 jonlib=5:6:7:9')
        self.assertEqual(lp.first_difference('frames 1:2:3:4 refused', 'frames 1:2:3:4'), 'frame 1: raylib=refused jonlib=(none)')


if __name__ == '__main__':
    unittest.main()
