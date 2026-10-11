import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import rlgl_framebuffer_probe as probe


class RlglFramebufferProbeTests(unittest.TestCase):
    def test_every_scenario_runs_natively_and_has_a_candidate_branch(self):
        source = probe.native_source()
        for index, name in enumerate(probe.SCENARIOS):
            self.assertIn(f'run("{name}");', source)
            self.assertIn(f'"{name}"', probe.C_SOURCE)
            self.assertIn(f'    case {index}: ', probe.PROGRAM)
        self.assertNotIn('SCENARIOS\n    return 0;', source)

    def test_the_contracts_follow_the_scenarios_and_expect_refusals(self):
        names = list(probe.SCENARIOS) + list(probe.CONTRACTS)
        self.assertEqual(len(names), len(set(names)))
        for name, row in probe.CONTRACTS.items():
            self.assertTrue(row.startswith(name + ' '))
        self.assertEqual(probe.CONTRACTS['target'], 'target 1')
        self.assertEqual(probe.CONTRACTS['texture-mode'], 'texture-mode 0')
        self.assertIn(f'    case {len(probe.SCENARIOS)}: refused.texture(J.Rlgl.load_texture(frame, 8, 8, 4, 1), name)', probe.PROGRAM)
        self.assertIn('    case _: ', probe.PROGRAM)

    def test_the_loader_scenario_is_the_examples_sequence(self):
        loader = probe.C_SOURCE[probe.C_SOURCE.index('"loader"'):probe.C_SOURCE.index('"sizes"')]
        order = ['rlLoadFramebuffer()', 'rlEnableFramebuffer(fbo)', 'rlLoadTexture(0, 64, 48, 7, 1)', 'rlLoadTextureDepth(64, 48, false)',
                 'RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D', 'RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D', 'rlDisableFramebuffer()']
        places = [loader.index(step) for step in order]
        self.assertEqual(places, sorted(places))

    def test_the_bound_scenario_uses_the_bound_frame(self):
        for call in ('J.Rlgl.enable_framebuffer(frame, fb)', 'J.Rlgl.Bound.load_texture(', 'J.Rlgl.Bound.load_texture_depth(', 'J.Rlgl.Bound.attach(', 'J.Rlgl.Bound.disable('):
            self.assertIn(call, probe.PROGRAM)


if __name__ == '__main__':
    unittest.main()
