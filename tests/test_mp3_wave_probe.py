import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp3_wave_probe as wp


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_raylib_s_loadwave(self):
        for text in ('#include "raudio.c"', 'LoadWave(files[a])', 'LoadSoundFromWave(wave)', 'if (wave.sampleSize != 32) return 3;', 'printf("none\\n")'):
            self.assertIn(text, wp.NATIVE)
        # every stream is decoded as LoadWave decodes it, Layer I and II ones too
        self.assertNotIn('layer12', wp.NATIVE)

    def test_the_candidate_loads_each_file(self):
        text = wp.render([('first12', 'x/first12.mp3'), ('upper', 'x/upper.MP3')], False)
        self.assertEqual((text.count('J.Wave.load_mp3('), text.count('"x/upper.MP3"'), text.rstrip().endswith('IO.print("done")')), (2, 1, True))
        self.assertIn('J.Sound.load_from_wave(audio, J.Wave{frames, rate, size, channels, data})', text)
        self.assertNotIn('layer12', text)

    def test_rows(self):
        self.assertEqual(wp.parse('none\nw5/44100/32/2/7 s6\ndone\n', [1, 2]), ['none', 'w5/44100/32/2/7 s6'])
        with self.assertRaises(ValueError):
            wp.parse('none\n', [1])

    def test_the_upper_case_token_is_a_copy(self):
        self.assertEqual(wp.RENAMED, {'upper': ('first12', '.MP3')})


if __name__ == '__main__':
    unittest.main()
