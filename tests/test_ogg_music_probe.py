import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ogg_music_probe as probe
import sound_probe as sp


class CasesTests(unittest.TestCase):
    def test_the_cases(self):
        cases = {case['id']: case for case in probe.cases()}
        self.assertEqual(set(cases), {'play', 'once', 'pause', 'unready', 'two', 'not-ogg'})
        for name, case in cases.items():
            for step in case['steps']:
                if step[0] == 'music':
                    self.assertIn(step[2], ('target', 'text'), name)
                    self.assertLess(step[1], sp.SLOTS)
        self.assertEqual(cases['not-ogg']['tags'], {1: 'data'})
        self.assertEqual(cases['play']['tags'], {})
        self.assertEqual(cases['once']['steps'][3], ('looping', 0, 0))

    def test_the_candidate_s_row(self):
        case = dict(id='x', steps=[('init',), ('music', 0, 'text')], tags={1: 'data'})
        self.assertEqual(probe.tagged(case, 'a;b'), 'E:- a;E:data b')

    def test_the_programs_know_an_ogg_music(self):
        self.assertIn('(m.ctxType == MUSIC_AUDIO_OGG)? (unsigned)stb_vorbis_get_sample_offset((stb_vorbis *)m.ctxData)', sp.NATIVE)
        self.assertIn('case J.MusicOgg{_, frames, _, _}: ogg.offset(VorbisF.Frames.state(frames))', sp.PROGRAM)
        self.assertLess(sp.PROGRAM.index('def ogg.offset('), sp.PROGRAM.index('def music.at('))


if __name__ == '__main__':
    unittest.main()
