import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp3_wave_probe as wp


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_raylib_s_loadwave(self):
        for text in ('#include "raudio.c"', 'LoadWave(files[a])', 'LoadSoundFromWave(wave)', 'if (wave.sampleSize != 32) return 3;', 'printf("layer12\\n")', 'printf("none\\n")'):
            self.assertIn(text, wp.NATIVE)
        # the layer question is put to dr_mp3 itself, read to the stream's end
        self.assertIn('drmp3_read_pcm_frames_f32(&mp3, 4096/mp3.channels, chunk) == 0', wp.NATIVE)

    def test_the_candidate_loads_each_file(self):
        text = wp.render([('first12', 'x/first12.mp3'), ('upper', 'x/upper.MP3')], False)
        self.assertEqual((text.count('J.Wave.load('), text.count('"x/upper.MP3"'), text.rstrip().endswith('IO.print("done")')), (2, 1, True))
        self.assertIn('J.Sound.load_from_wave(audio, J.Wave{frames, rate, size, channels, data})', text)
        self.assertIn('case Fail{J.WaveDataError{J.UnsupportedWaveFormat{}}}: IO.print("layer12")', text)

    def test_rows(self):
        self.assertEqual(wp.parse('none\nw5/44100/32/2/7 s6\ndone\n', [1, 2]), ['none', 'w5/44100/32/2/7 s6'])
        with self.assertRaises(ValueError):
            wp.parse('none\n', [1])

    def test_the_upper_case_token_is_a_copy(self):
        self.assertEqual(wp.RENAMED, {'upper': ('first12', '.MP3')})


if __name__ == '__main__':
    unittest.main()
