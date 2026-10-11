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

    def test_the_blind_scenarios_compare_the_screen_of_a_small_window(self):
        blind = [name for name in probe.SCENARIOS if name.startswith('blind')]
        self.assertEqual(blind, ['blind', 'blind-clear', 'blind-bare', 'blind-after', 'blind-gbuffer'])
        self.assertEqual({probe.size(name) for name in blind}, {8})
        self.assertEqual(probe.size('loader'), 64)
        self.assertNotIn('@', probe.PROGRAM)
        self.assertEqual(probe.word('RED'), 0xe62937ff)
        self.assertEqual(probe.pixels('blind 1 0 ' + '00e430ff' * 2), ['00e430ff', '00e430ff'])
        source = probe.native_source()
        for call in ('BeginTextureMode(target);', 'ClearBackground(WHITE);', 'rlClearScreenBuffers();', 'rlUnloadFramebuffer(blind.id);', 'dump();'):
            self.assertIn(call, source)
        for call in ('J.Rlgl.render_texture_depth(fb, 4, 2, id)', 'J.Frame.framebuffer(', 'J.Rlgl.get_matrix_projection(', 'J.Rlgl.clear_screen_buffers(frame)'):
            self.assertIn(call, probe.PROGRAM)

    def test_the_depth_target_contracts_refuse_all_but_the_depth_only_framebuffer(self):
        rows = {name: row for name, row in probe.CONTRACTS.items() if name.startswith('depth-target') or name == 'blind-nested'}
        self.assertEqual([name for name, row in rows.items() if row.endswith(' 1')], ['depth-target'])
        self.assertEqual(len(rows), 6)

    def test_the_gbuffer_scenario_binds_to_draw_and_binds_for_reading(self):
        source = probe.native_source()
        gbuffer = source[source.index('"blind-gbuffer"'):]
        order = ['rlLoadTexture(0, 8, 8, 12, 1)', 'RL_ATTACHMENT_COLOR_CHANNEL2', 'RL_ATTACHMENT_COLOR_CHANNEL0', 'rlEnableFramebuffer(fbo);', 'rlClearColor(0, 0, 0, 0);', 'rlDisableFramebuffer();',
                 'rlBindFramebuffer(RL_READ_FRAMEBUFFER, fbo);', 'rlBindFramebuffer(RL_DRAW_FRAMEBUFFER, 0);', 'DrawTexture((Texture2D){ position, 8, 8, 1, 12 }']
        places = [gbuffer.index(step) for step in order]
        self.assertEqual(places, sorted(places))
        self.assertEqual(probe.size('blind-gbuffer'), 8)
        for call in ('J.Rlgl.enable_framebuffer_incomplete(', 'J.Rlgl.bind_framebuffer(J.Rlgl.clear_screen_buffers(frame), 36008, fb)', '36009, J.Rlgl.Framebuffer.none())',
                     'J.Rlgl.clear_color(', 'J.Rlgl.disable_framebuffer(frame)'):
            self.assertIn(call, probe.PROGRAM)

    def test_the_float_formats_are_loaded_and_the_binding_contracts_refuse(self):
        self.assertIn('for (int format = 8; format <= 11; format++)', probe.C_SOURCE)
        for format in (8, 9, 10, 11, 12, 13):
            self.assertIn(f'16, 16, {format})', probe.PROGRAM)
        rows = {name: row for name, row in probe.CONTRACTS.items() if name.startswith('incomplete')}
        self.assertEqual(set(rows.values()), {'incomplete-complete 0', 'incomplete-zero 0', 'incomplete-in-mode 0'})
        self.assertEqual(probe.CONTRACTS['format-compressed'], 'format-compressed 0 0')
        self.assertIn('    case _: refused.texture(J.Rlgl.load_texture(frame, 8, 8, 14, 1), name)', probe.PROGRAM)

    def test_the_bound_scenario_uses_the_bound_frame(self):
        for call in ('J.Rlgl.enable_framebuffer(frame, fb)', 'J.Rlgl.Bound.load_texture(', 'J.Rlgl.Bound.load_texture_depth(', 'J.Rlgl.Bound.attach(', 'J.Rlgl.Bound.disable('):
            self.assertIn(call, probe.PROGRAM)


if __name__ == '__main__':
    unittest.main()
