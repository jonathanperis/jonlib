import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import sound_probe as sp
import xm_module_probe as xp
import xm_music_probe as mp
import xm_player_probe as pp


class ModulesTests(unittest.TestCase):
    def setUp(self):
        self.source = xp.module([xp.pattern(4)], channels=2)
        self.files = mp.modules(self.source)

    def test_the_modules(self):
        built = pp.built()
        self.assertEqual(self.files['mini'], self.source)
        self.assertEqual((self.files['linear'], self.files['amiga'], self.files['short']), (built['tame-0'], built['tame-1'], built['finetune-high']))
        for name, data in self.files.items():
            kind = xp.model(data)[0]
            self.assertEqual(kind, 'refused' if name == 'channels' else 'failed' if name == 'text' else 'loaded', name)
        # Amiga frequencies (no power of two) and an instrument without a vibrato (no sine)
        bare = self.files['bare']
        self.assertEqual(bare[74] & 1, 0)
        self.assertEqual(self.files['linear'][74] & 1, 1)
        self.assertEqual(self.files['amiga'][74] & 1, 0)

    def test_what_jonlib_does_not_load(self):
        self.assertEqual(set(mp.REFUSED), {'delay-bare', 'finetune-low', 'sustain-past', 'break-past', 'channels'})
        self.assertTrue(set(mp.REFUSED) < set(self.files))
        self.assertEqual(set(mp.REFUSED.values()), {'data'})


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.cases = {case['id']: case for case in mp.cases()}

    def test_the_cases(self):
        self.assertEqual(len(self.cases), 9 + 5 + 1)
        files = set(mp.modules(b''))
        for name, case in self.cases.items():
            for step in case['steps']:
                self.assertIn(step[0], ('init', 'close', 'default', 'music', 'play', 'pause', 'resume', 'volume', 'pitch', 'pan', 'mix', 'seek', 'looping',
                                        'musicupdate', 'musicstop', 'musicunload'), name)
                if step[0] == 'music':
                    self.assertIn(step[2], files, name)
                    self.assertLess(step[1], sp.SLOTS, name)
            self.assertEqual(name.startswith('refused-'), bool(case['tags']) and name != 'not-a-module', name)

    def test_the_errors(self):
        self.assertEqual(self.cases['play']['tags'], {})
        self.assertEqual(self.cases['not-a-module']['tags'], {1: 'header'})
        self.assertEqual(self.cases['refused-channels']['tags'], {1: 'data'})
        self.assertEqual(self.cases['refused-break-past']['tags'], {1: 'data'})
        # Music.load: raylib's module needs a power of two, which the AppleLibm profile does not give
        self.assertEqual(self.cases['refused-default-profile']['tags'], {1: 'unsupported'})
        self.assertEqual(self.cases['default-profile']['tags'], {})
        self.assertEqual(self.cases['default-profile']['steps'][2], ('music', 3, 'bare'))

    def test_raylib_runs_a_file_it_does_not_take_where_jonlib_refuses(self):
        refused = self.cases['refused-delay-bare']
        self.assertEqual(mp.native_steps(refused), [('init',), ('music', 0, 'text'), ('play', 0), ('musicupdate', 0), ('close',)])
        self.assertEqual(mp.native_steps(self.cases['refused-default-profile'])[1], ('music', 3, 'text'))
        self.assertEqual(mp.native_steps(self.cases['play']), self.cases['play']['steps'])

    def test_the_candidate_s_row_for_a_reference_row(self):
        case = dict(id='x', steps=[('init',), ('music', 0, 'text'), ('close',)], tags={1: 'header'})
        self.assertEqual(mp.tagged(case, 'a;b;c'), 'E:- a;E:header b;E:- c')
        with self.assertRaises(mp.ProbeFailure):
            mp.tagged(case, 'a;b')

    def test_the_music_that_does_not_loop(self):
        steps = self.cases['once']['steps']
        self.assertEqual(steps[2:5], [('music', 0, 'short'), ('looping', 0, 0), ('play', 0)])
        self.assertEqual(steps[-5:], [('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 200), ('close',)])


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_the_sound_gate_s_a_case_a_process(self):
        self.assertIn('-DALONE', mp.FLAGS)
        self.assertNotIn('-DALONE', sp.FLAGS)
        self.assertIn('#ifdef ALONE\n        // A case in a process of its own', sp.NATIVE)
        self.assertIn('pid_t child = fork();', sp.NATIVE)
        self.assertIn('(m.ctxType == MUSIC_MODULE_XM)? (unsigned)((jar_xm_context_t *)m.ctxData)->generated_samples', sp.NATIVE)
        self.assertIn('static unsigned timed(float x) { return (x != x)? 2143289344u : word(x); }', sp.NATIVE)

    def test_the_candidate_loads_under_the_machine_s_profile(self):
        text = mp.program('Glibc239Libm')
        self.assertNotIn('LIBM', text)
        self.assertIn('result : J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music> <- music.load(U32.is_eq(slot, 3), audio, path)', text)
        self.assertIn('    case True{}: J.Music.load(audio, path)\n    case False{}: J.Music.load_for(M.Glibc239Libm{}, audio, path)\n', text)
        self.assertEqual(text.count('\ndef step('), 1)
        self.assertLess(text.index('def music.load('), text.index('\ndef step('))
        self.assertIn('case J.MusicXm{player}: U32.show(XmX.generated.of(player))', text)


if __name__ == '__main__':
    unittest.main()
