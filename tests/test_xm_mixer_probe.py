import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import xm_mixer_probe as mp
import xm_module_probe as xp
import xm_player_probe as pp


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = xp.module([xp.pattern(4)], channels=2)
        self.cases = mp.cases(self.source)

    def test_the_modules_and_their_calls(self):
        self.assertEqual(len(self.cases), 3 + 4 * 2 + 6 + 6)
        # as raylib plays a module: the length, the reset, the stream's frames, at the device's rate
        self.assertEqual(self.cases['mini'], (self.source, [mp.OWN, mp.RESET, mp.own(4096), mp.own(4096), mp.own(2048), mp.own(1)], 48000))
        for name, (data, calls, rate) in self.cases.items():
            self.assertEqual(xp.model(data)[0], 'loaded', name)
            self.assertEqual(rate, 48000 if name in ('mini', 'mini-frames') else 8000, name)
            for op in calls:
                frames = op if op > 0 else mp.OWN_FRAMES - op if op <= mp.OWN_FRAMES else 0
                self.assertTrue(op in (mp.REMAINING, mp.RESET, mp.OWN) or 0 < frames <= mp.MOST, (name, op))
            # jar_xm's own functions only where no row can leave its pattern
            own = any(op == mp.OWN or op <= mp.OWN_FRAMES for op in calls)
            self.assertTrue(not own or name.startswith('mini') or name.startswith('tame'), name)

    def test_frames_by_jar_xm_s_own_function(self):
        self.assertEqual((mp.own(1), mp.own(4096)), (-1001, -5096))
        self.assertEqual(mp.OWN_FRAMES - mp.own(300), 300)
        # as the candidate reads them
        self.assertEqual(4294966296 - (mp.own(300) & 0xFFFFFFFF), 300)

    def test_the_built_modules_are_the_player_gate_s(self):
        built = pp.built()
        for name, data in built.items():
            self.assertEqual(self.cases[name][0], data)
        self.assertEqual(self.cases['tame-0-frames'][0], built['tame-0'])


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_the_player_gate_s_with_the_mixer(self):
        self.assertIn('static unsigned digest(jar_xm_context_t *ctx)', mp.NATIVE)
        self.assertIn('static int outside(jar_xm_context_t *ctx)', mp.NATIVE)
        self.assertEqual(mp.NATIVE.count('static void run('), 1)
        self.assertIn('jar_xm_mixdown(ctx, output + 2*i, output + 2*i + 1);', mp.NATIVE)
        self.assertIn('jar_xm_generate_samples(ctx, output, (size_t)made);', mp.NATIVE)
        self.assertIn('static int beyond(jar_xm_channel_context_t *ch)', mp.NATIVE)
        self.assertIn('child = fork();', mp.NATIVE)
        self.assertNotIn('MOST', mp.NATIVE)
        self.assertNotIn('OWN_FRAMES', mp.NATIVE)

    def test_the_candidate_is_the_player_gate_s_with_the_mixer(self):
        self.assertIn('def digest(player: Pl.Player) -> U32:', mp.PROGRAM)
        self.assertEqual(mp.PROGRAM.count('type Run is Data:'), 1)
        self.assertIn('import ../../src/xm_mixer.bend as Mx\n', mp.PROGRAM)
        self.assertIn('Mx.generate(Run.player(run), count)', mp.PROGRAM)
        self.assertIn('Pl.player.new(M.LIBM{}, module, rate, 24492)', mp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
