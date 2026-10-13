import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import window_probe as wp


def header(data):
    return struct.unpack('>IIBB', data[16:26])


class StripTests(unittest.TestCase):
    def test_the_strips_are_within_a_texture_s_bounds_and_past_an_image_s(self):
        for name, (width, height, _) in wp.STRIPS.items():
            if name == 'strip-past.png':
                self.assertEqual(max(width, height), 16385)
                continue
            self.assertTrue(4096 < max(width, height) <= 16384 and width * height <= 4096 * 4096, name)

    def test_the_pixels_tell_their_place(self):
        pixels = wp.strip(3, 4)
        self.assertEqual((len(pixels), pixels[0], pixels[1], pixels[3]), (12, (0, 0, 0, 90), (37, 0, 1, 255), (11, 1, 0, 255)))
        self.assertEqual(len({p[:3] for p in wp.strip(3, 5000)}), 3 * 5000)

    def test_the_files(self):
        self.assertEqual(header(wp.png(3, 5000, wp.strip(3, 5000))), (3, 5000, 8, 6))
        many = wp.blank(16384, 1025)
        self.assertEqual((header(many), 16384 * 1025 > 4096 * 4096, len(many) < 200000), ((16384, 1025, 8, 2), True, True))
        # the black image is a whole PNG: its rows inflate to a filter byte and three bytes a pixel
        at = many.index(b'IDAT') + 4
        size = struct.unpack('>I', many[at - 8:at - 4])[0]
        self.assertEqual(len(zlib.decompress(many[at:at + size])), (16384 * 3 + 1) * 1025)

    def test_the_scripts(self):
        with tempfile.TemporaryDirectory() as work:
            paths = {name: f'x/{name}' for name in ('fixture-rgba.png', 'fixture-rgb.png', *wp.STRIPS, 'strip-many.png')}
            items = {item['name']: item for item in wp.scripts(paths)}
        strips = items['texture-strips']
        self.assertEqual(sum(o[0] == wp.TEXTURE for o in strips['ops']), 4)
        self.assertEqual(sum(o[0] == wp.FRAMEBUFFER for o in strips['ops']), 4)
        self.assertIsNone(strips.get('contract'))
        for name in ('texture-past-side', 'texture-past-pixels'):
            self.assertEqual((items[name]['contract'], items[name]['contract_token']), (0, 'T:null'))
        # a contract's reference runs the operations before it only
        self.assertNotIn('strip-past.png', wp.c_program(items['texture-past-side']))


if __name__ == '__main__':
    unittest.main()
