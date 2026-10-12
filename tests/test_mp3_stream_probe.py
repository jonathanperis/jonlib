import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp3_stream_probe as sp


class ScriptTests(unittest.TestCase):
    def test_the_last_read_is_long_for_the_files_read_to_their_end(self):
        self.assertEqual((sp.last_read('first12'), sp.last_read('edit17'), sp.SCRIPT[-1]), (20000, 2500, ('r', 2500)))
        ops = sp.operations('whole')
        self.assertEqual((len(ops), ops[:4], ops[-2:]), (2 * len(sp.SCRIPT), [ord('c'), 0, ord('r'), 100], [ord('r'), 20000]))
        self.assertEqual(sp.operations('edit17')[-2:], [ord('r'), 2500])

    def test_the_script_has_every_operation(self):
        self.assertEqual({code for code, _ in sp.SCRIPT}, set('crfkeb'))
        # a seek back (500 after 3100 frames were read), one forward, and the start between them
        codes = ''.join(code for code, _ in sp.SCRIPT)
        self.assertLess(codes.index('k'), codes.index('b'))
        self.assertLess(codes.index('b'), codes.rindex('k'))

    def test_the_reference_takes_the_script_and_each_file_s_last_read(self):
        source = sp.reference([('first12', 'x/first12.mp3'), ('edit17', 'x/edit17.mp3')])
        self.assertIn('static const unsigned lasts[] = { 20000, 2500 };', source)
        self.assertIn('static const char codes[] = "crfrkrebfkrcr";', source)
        self.assertIn('static const unsigned args[] = { 0, 100, 1000, 2000, 500, 300, 0, 0, 1200, 3000, 50, 0, 2500 };', source)
        self.assertIn('static drmp3_int16 shorts[2*20000];', source)
        self.assertEqual(source.count('x/edit17.mp3"'), 1)
        for name in ('drmp3_init_file', 'drmp3_get_pcm_frame_count', 'drmp3_read_pcm_frames_s16', 'drmp3_read_pcm_frames_f32', 'drmp3_seek_to_pcm_frame', 'drmp3_seek_to_start_of_stream'):
            self.assertIn(name + '(', source)

    def test_the_candidate_runs_each_file_s_script(self):
        text = sp.render([('first12', 'x/a.mp3'), ('edit17', 'x/b.mp3')], False)
        self.assertEqual((text.count('J.Files.load_data('), text.count('"x/b.mp3"'), text.rstrip().endswith('IO.print("done")')), (2, 1, True))
        self.assertIn('[99, 0, 114, 100, 102, 1000, 114, 2000, 107, 500, 114, 300, 101, 0, 98, 0, 102, 1200, 107, 3000, 114, 50, 99, 0, 114, 20000]', text)
        self.assertIn('99, 0, 114, 2500]', text)
        # the operation codes the program matches are the script's letters
        for letter in 'crfke':
            self.assertIn(f'    case {ord(letter)}: ', text)

    def test_rows(self):
        self.assertEqual(sp.parse('closed\no2/44100/0/0/0/2 c5/0/0/0/2\ndone\n', [1, 2]), ['closed', 'o2/44100/0/0/0/2 c5/0/0/0/2'])
        with self.assertRaises(ValueError):
            sp.parse('closed\n', [1])
        self.assertEqual(sp.first_difference('o1 c5 r100/7', 'o1 c5 r100/8'), 'operation 2: raylib=r100/7 jonlib=r100/8')
        self.assertEqual(sp.first_difference('o1 c5 layer12', 'o1 c5'), 'operation 2: raylib=layer12 jonlib=(none)')


if __name__ == '__main__':
    unittest.main()
