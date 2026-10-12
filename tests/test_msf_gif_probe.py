import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import msf_gif_probe as gp
from probekit import ProbeFailure

HEAD = [71, 73, 70, 56, 57, 97, 0, 0, 1, 0, 112, 0, 0, 33, 255, 11, 78, 69, 84, 83, 67, 65, 80, 69, 50, 46, 48, 3, 1, 0, 0, 0]
# msf_gif.h's files for one white pixel, and for a red and a white pixel written twice
WHITE = bytes(HEAD[:6] + [1] + HEAD[7:] + [33, 249, 4, 5, 5, 0, 0, 0, 44, 0, 0, 0, 0, 1, 0, 1, 0, 129, 0, 0, 0, 255, 255, 255, 0, 0, 0, 0, 0, 0, 2, 2, 76, 1, 0, 59])
FRAME = [33, 249, 4, 5, 0, 0, 0, 0, 44, 0, 0, 0, 0, 2, 0, 1, 0, 129, 0, 0, 0, 222, 40, 49, 255, 255, 255, 0, 0, 0, 2, 2]
TWICE = bytes(HEAD[:6] + [2] + HEAD[7:] + FRAME + [140, 10, 0] + FRAME + [4, 10, 0, 59])


class GeneratorTests(unittest.TestCase):
    def test_a_frame_s_words(self):
        self.assertEqual(gp.image(3, 0, 5, 3, 1, 0), [gp.hashed(5)] * 3)
        noise = gp.image(4, 1, 7, 2, 2, 0)
        self.assertEqual(noise, [gp.lcg(7), gp.lcg(gp.lcg(7)), gp.lcg(gp.lcg(gp.lcg(7))), gp.lcg(gp.lcg(gp.lcg(gp.lcg(7))))])
        self.assertNotEqual(gp.image(4, 1, 7, 2, 2, 1), noise)                       # the frame's time moves the noise
        self.assertEqual(gp.image(4, 2, 0, 2, 2, 0), [0x000000FF, 0xFF0001FF, 0x00FF01FF, 0xFFFF02FF])
        self.assertEqual({w & 0x3F3F3F00 for w in gp.image(64, 5, 9, 8, 8, 0)}, {0})  # two bits a channel
        self.assertTrue(all(w & 255 == 255 for kind in (0, 2, 3, 4, 5) for w in gp.image(30, kind, 3, 6, 5, 2)))

    def test_shapes_on_the_ground(self):
        frame = gp.image(160 * 90, 3, 11, 160, 90, 0)
        self.assertEqual(set(frame), {gp.RAYWHITE, gp.RED, gp.MAROON})
        self.assertEqual((frame[22 * 160 + 4], frame[22 * 160 + 43], frame[22 * 160 + 44] != gp.RED, frame[21 * 160 + 4] != gp.RED), (gp.RED, gp.RED, True, True))
        moved = gp.image(160 * 90, 3, 11, 160, 90, 2)
        self.assertEqual((moved[22 * 160 + 4] != gp.RED, moved[22 * 160 + 10]), (True, gp.RED))

    def test_the_hash(self):
        self.assertEqual((gp.fnv([]), gp.fnv([1]), gp.fnv([1, 2]) != gp.fnv([2, 1])), (2166136261, ((2166136261 ^ 1) * 16777619) & 0xFFFFFFFF, True))


class ReadBackTests(unittest.TestCase):
    def test_one_pixel(self):
        self.assertEqual(gp.read_back(WHITE, gp.case(0, 0, 1, 1, [(0, 5, 16)])), dict(frames=1, resets=0, blocks=1, transparent=0, boundary=0, overflows=0))

    def test_a_frame_equal_to_the_one_before(self):
        self.assertEqual(gp.read_back(TWICE, gp.case(0, 0, 2, 1, [(0, 0, 16)] * 2)), dict(frames=2, resets=0, blocks=2, transparent=1, boundary=0, overflows=0))

    def test_a_file_that_is_not_the_case_s(self):
        for data, item in ((WHITE, gp.case(0, 0, 2, 1, [])), (WHITE[:-1] + b'\x00', gp.case(0, 0, 1, 1, [])), (b'GIF87a' + WHITE[6:], gp.case(0, 0, 1, 1, [])),
                           (TWICE, gp.case(0, 0, 1, 2, [])), (WHITE[:64] + bytes([77]) + WHITE[65:], gp.case(0, 0, 1, 1, []))):
            with self.assertRaises(ProbeFailure):
                gp.read_back(data, item)

    def test_the_buffer_s_limit(self):
        # 128 colors need a table of 256: 279 + 768 bytes, with 800 + pixels*3/2 to hold them
        fits = lambda pixels, table, full: 279 + table * 3 + 256 * (full // 255) <= 800 + pixels * 3 // 2
        self.assertEqual((fits(165, 256, 186), fits(164, 256, 185), fits(256, 256, 288), fits(400, 256, 460), fits(1, 4, 2)), (True, False, False, True, True))


class CasesTests(unittest.TestCase):
    def test_the_cases(self):
        chosen = gp.cases()
        refused = [item for item in chosen if gp.refused(item)]
        self.assertEqual((len(chosen), len(refused)), (72, 8))
        self.assertEqual({(item['w'], item['h'], item['extra']) for item in refused},
                         {(6, 4, 1), (6, 4, 2), (0, 4, 0), (4, 0, 0), (4097, 1, 0), (1, 4097, 0), (0, 0, 0)})
        self.assertFalse(gp.refused(gp.case(0, 88, 4096, 4096, [])))
        depths = {depth for item in chosen for _, _, depth in item['frames']}
        self.assertTrue({0, 1, 8, 16, 20, 0xFFFFFFFD} <= depths)
        self.assertTrue({0, 5, 300, 70000, 0xFFFFFFFF} <= {delay for item in chosen for _, delay, _ in item['frames']})
        self.assertTrue(any(item['w'] % 4 for item in chosen) and any(item['w'] % 4 == 0 for item in chosen))

    def test_the_reference_s_input(self):
        data = gp.packed([gp.case(0, 5, 2, 1, [(0, 7, 16)]), gp.case(1, 6, 1, 1, [])])
        self.assertEqual(struct.unpack('<11I', data), (2, 2, 1, 1, 7, 16, gp.hashed(5), gp.hashed(5), 1, 1, 0))

    def test_the_candidate(self):
        text = gp.bend_case(gp.case(4, 27, 80, 60, [(0, 0, 16), (5, 0, 16)], extra=1))
        self.assertEqual(text.strip(), 'IO.print(run([0, 0, 16, 5, 0, 16], 1, 4, 27, 80, 60, 2166136261, G.begin(80, 60)))')
        self.assertIn('G.frame(g, made, centiseconds, depth)', gp.PROGRAM)
        self.assertIn('msf_gif_frame(&state, pixels, centiseconds, depth, width*4)', gp.NATIVE)
        self.assertIn('malloc((size) + 4096)', gp.NATIVE)


if __name__ == '__main__':
    unittest.main()
