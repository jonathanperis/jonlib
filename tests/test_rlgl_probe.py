import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import frame_probe
import rlgl_probe as probe

RASTER_62 = ('rl-color-interp', 'rl-color-interp-frustum', 'rl-texture-filter-pick-0', 'rl-texture-filter-pick-1', 'rl-viewport-overscan')


class RlglProbeTests(unittest.TestCase):
    def scene(self, name, scenes=None):
        found = [s for s in (scenes or probe.scenes()) if s['id'] == name]
        self.assertEqual(len(found), 1, name)
        return found[0]

    def test_the_raylib_62_raster_scenes_are_compared_on_every_host(self):
        for name in RASTER_62:
            scene = self.scene(name)
            for libm in ('AppleLibm', 'Glibc239Libm', 'Glibc241Libm'):
                self.assertFalse(probe.refused(scene, libm), (name, libm))
            source = probe.c_scene(scene)
            self.assertIn('dump(', source)
            self.assertIn(f'def scene.7() -> +List<Op>:', probe.b_scene(7, scene))

    def test_texture_parameters_reach_rlgl_and_the_texture_step(self):
        scene = self.scene('rl-texture-filter-pick-0')
        params = [op for op in scene['ops'] if op[0] == 'params']
        self.assertEqual(params, [('params', 0, 0x2801, 0x2601), ('params', 0, 0x2800, 0x2600)])
        self.assertEqual(probe.c_op(params[0]).strip(), 'rlTextureParameters(t[0].id, 10241, 9729);')
        self.assertEqual(probe.op_words(params[0]), (99, [0, 0, 111, 10241, 9729]))
        swapped = self.scene('rl-texture-filter-pick-1')
        self.assertIn(('params', 0, 0x2801, 0x2600), swapped['ops'])

    def test_flat_and_interpolated_primitives_both_occur(self):
        scene = self.scene('rl-color-interp')
        primitives, current, colors = [], None, []
        for op in scene['ops']:
            if op[0] == 'rl_begin':
                colors = [current]
            elif op[0] in ('c4ub', 'c4f'):
                current = op[1:]
                colors.append(current)
            elif op[0] == 'rl_end':
                primitives.append(len(set(c for c in colors if c is not None)) > 1)
        self.assertIn(True, primitives)
        self.assertIn(False, primitives)

    def test_the_overscan_viewport_reaches_past_every_edge(self):
        ops = self.scene('rl-viewport-overscan')['ops']
        x, y, w, h = [op for op in ops if op[0] == 'viewport'][0][1:]
        self.assertLess(x, 0.0)
        self.assertLess(y, 0.0)
        self.assertGreater(x + w, 32.0)
        self.assertGreater(y + h, 24.0)
        self.assertEqual(ops[-2], ('rect', 14.0, 9.0, 4.0, 4.0, probe.WHITE))
        self.assertIn(('viewport', 0.0, 0.0, 32.0, 24.0), ops)

    def test_the_frame_probe_compares_flat_and_gradient_shapes(self):
        scene = self.scene('flat-or-gradient', frame_probe.scenes())
        self.assertFalse(any(frame_probe.refused(op, 'AppleLibm') for op in scene['ops']))
        source = frame_probe.c_scene(scene)
        self.assertIn('DrawCircleGradient', source)
        self.assertIn('DrawRectangleGradientEx', source)


if __name__ == '__main__':
    unittest.main()
