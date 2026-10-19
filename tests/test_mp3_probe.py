import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp3_probe as mp
from probekit import ProbeFailure


def frame(index, padded=False, info=False):
    """A 417- or 418-byte frame as country.mp3's are laid out: its header, then bytes that tell the frames apart."""
    head = bytes([0xFF, 0xFB, 0x92 if padded else 0x90, 0x44])
    body = bytearray((index * 7 + i) & 255 for i in range(413 + padded))
    if info:
        body[32:36] = b'Info'
    return head + bytes(body)


def source():
    """3584 frames, the first an Info frame: what cases() checks before it edits anything."""
    return b''.join(frame(i, padded=i % 49 == 3, info=i == 0) for i in range(3584))


class FramesTests(unittest.TestCase):
    def test_frames_follow_one_another_by_their_padding_bit(self):
        data = frame(0) + frame(1, padded=True) + frame(2)
        self.assertEqual(mp.frame_offsets(data), [0, 417, 835])
        self.assertEqual(mp.frame_offsets(data[:835] + b'\x00' * 10), [0, 417])      # what follows is no header
        self.assertEqual(mp.frame_offsets(b'ID3' + data), [])

    def test_every_header_is_rewritten(self):
        data = frame(0) + frame(1)
        out = mp.rewritten(data, [0, 417], mp.header(2, 0xF0, 0))                  # free format: no bit rate
        self.assertEqual((out[2], out[419], out[:2], out[4:417]), (0x00, 0x00, data[:2], data[4:417]))
        out = mp.rewritten(data, [0, 417], mp.header(3, 0, 0xC0))                  # mono
        self.assertEqual((out[3], out[420]), (0xC4, 0xC4))
        self.assertEqual(mp.rewritten(data, [0, 900], mp.header(1, 0x06, 0x04))[1], 0xFD)       # an offset past the data is left alone


class CasesTests(unittest.TestCase):
    def test_the_corpus_is_cut_from_the_file_it_expects(self):
        with self.assertRaises(ProbeFailure):
            mp.cases(frame(0) * 12)
        files = mp.cases(source())
        self.assertEqual((len(files), files['whole'][:4], len(files['tiny']), len(files['header']), files['empty']), (92, b'\xff\xfb\x90D', 9, 4, b''))
        self.assertEqual((len(files['first12']), len(files['noinfo']), files['noinfo'][:4]), (12 * 417 + 1, 12 * 417 + 1, b'\xff\xfb\x90D'))
        self.assertEqual(files['first12'][36:40], b'Info')
        self.assertEqual((files['xing'][36:40], files['id3v2'][:3], files['id3v1'][-128:-125], files['ape'][-32:-24]), (b'Xing', b'ID3', b'TAG', b'APETAGEX'))
        self.assertEqual((files['free'][2] >> 4, files['crc'][1] & 1, files['mono'][3] >> 6, files['mpeg2'][1], files['mpeg25'][1], files['layer1'][1] & 6), (0, 0, 3, 0xF3, 0xE3, 6))
        self.assertNotEqual(files['othersr'], files['noinfo'])

    def test_the_lower_bit_rates_cut_every_frame(self):
        files = mp.cases(source())
        # 144 * kbit/s * 1000 // 44100 bytes a frame, thirteen frames from the Info frame, the bit rate index set and no padding
        for index, (rate, size) in enumerate(((32, 104), (40, 130), (48, 156), (56, 182), (64, 208)), 1):
            data = files[f'info{rate}k']
            self.assertEqual((len(data), data[36:40]), (13 * size, b'Info'), rate)
            self.assertEqual({data[at + 2] for at in range(0, 13 * size, size)}, {index << 4}, rate)

    def test_the_xing_counts_pass_32_bits(self):
        files = mp.cases(source())
        first = files['first12']
        for name, count, total in (('xinghuge', 3728271, 2 ** 32 + 896), ('xingwrap', 11184811, 3 * 2 ** 32 + 384)):
            data = files[name]
            self.assertEqual((len(data), data[:44], data[48:]), (len(first), first[:44], first[48:]), name)
            self.assertEqual((int.from_bytes(data[44:48], 'big'), int.from_bytes(data[44:48], 'big') * 1152), (count, total), name)

    def test_the_seeded_edits_do_not_change(self):
        first, second = mp.cases(source()), mp.cases(source())
        self.assertEqual(first, second)
        edits = [name for name in first if name.startswith('edit')]
        self.assertEqual((len(edits), len({first[name] for name in edits})), (48, 48))

    def test_the_candidate_reads_each_file_and_ends(self):
        text = mp.render([('a', 'x/a.mp3'), ('b', 'x/b.mp3')], False)
        self.assertEqual((text.count('J.Files.load_data('), text.count('"x/b.mp3"'), text.rstrip().endswith('IO.print("done")')), (2, 1, True))
        self.assertEqual(mp.parse('closed\nopen 2 44100 0 0 0 - 1 1152 1 1152\ndone\n', [1, 2]), ['closed', 'open 2 44100 0 0 0 - 1 1152 1 1152'])
        with self.assertRaises(ValueError):
            mp.parse('closed\n', [1, 2])


if __name__ == '__main__':
    unittest.main()
