import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import effects_probe as probe
import examples_probe as ep

ROOT = Path(__file__).resolve().parents[1]


class EffectsProbeTests(unittest.TestCase):
    def test_the_reference_loop_does_io_before_begin_drawing_and_after_end_drawing(self):
        source = (ROOT / 'tools/reference/driver_effects.c').read_text()
        order = ['InitWindow(160, 90', 'IsKeyPressed(KEY_S)', 'SaveFileText("effects.txt"', 'IsKeyPressed(KEY_L)', 'LoadFileText("effects.txt")', 'BeginDrawing();',
                 'EndDrawing();', 'IsKeyDown(KEY_F)', 'counter + 1000']
        places = [source.index(step) for step in order]
        self.assertEqual(places, sorted(places))

    def test_the_bend_module_is_an_effects_program_with_the_same_steps(self):
        module = (ROOT / 'tools/reference/driver_effects.bend').read_text()
        for call in ('J.Effects{', 'J.Files.save_text(file(state), U32.show(counter.of(state)))', 'J.Files.load_text(file(state))', 'J.Input.is_key_down(core, 70)',
                     '(counter.of(state) + 1000 : U32)', 'J.Input.is_key_pressed(core, 83)', 'J.Input.is_key_pressed(core, 76)'):
            self.assertIn(call, module)

    def test_the_scripts_read_a_missing_file_first_and_every_write_back(self):
        missing, files = probe.scripts()
        self.assertEqual(missing['name'], 'driver_effects-missing')
        keys = lambda item: [[(event[1], event[0]) for event in frame['events']] for frame in item['frames']]
        self.assertFalse(any(code in (probe.KEY_S, probe.KEY_F) for frame in keys(missing) for code, _ in frame))
        pressed = [code for frame in keys(files) for code, _ in frame]
        self.assertLess(pressed.index(probe.KEY_S), pressed.index(probe.KEY_L))
        self.assertLess(pressed.index(probe.KEY_F), len(pressed) - 1 - pressed[::-1].index(probe.KEY_L))
        self.assertEqual(len(files['frames']), 8)

    def test_registering_makes_it_an_effects_program_of_the_examples_probe(self):
        probe.register()
        try:
            self.assertIn(probe.NAME, ep.EFFECTS)
            self.assertIn(probe.NAME, ep.IO_SETUP)
            self.assertIn(probe.NAME, ep.SCRATCH)
            self.assertEqual(ep.size_of(probe.NAME), (160, 90))
            ep.DIRECTORIES[probe.NAME] = '/tmp/x/'
            text = ep.render(probe.scripts(), 'Glibc239Libm', None, Path('/raylib'))([probe.NAME], False)
            self.assertIn('import ../../tools/reference/driver_effects.bend as Ex', text)
            self.assertIn('J.Program.replay_io(~Ex.State, ~Ex.program(M.Glibc239Libm{})', text)
            self.assertIn('Ex.setup("/tmp/x/", core, frame)', text)
            self.assertIn('J.Core.init_window_flags(0, 160, 90', text)
        finally:
            for table in (ep.EXAMPLES, ep.MODULES, ep.SIZES, ep.DIRECTORIES):
                table.pop(probe.NAME, None)
            for names in (ep.IO_SETUP, ep.EFFECTS, ep.SCRATCH):
                names.discard(probe.NAME)

    def test_an_example_keeps_its_module_and_the_pure_replay(self):
        text = ep.render([item for item in ep.scripts() if item['example'] == 'core_basic_window'], 'Glibc239Libm', None, Path('/raylib'))(['core_basic_window'], False)
        self.assertIn('import ../../examples/core_basic_window.bend as Ex', text)
        self.assertIn('join(J.Program.replay(~Ex.State', text)
        self.assertNotIn('replay_io', text)
        shadow = ep.render([item for item in ep.scripts() if item['example'] == 'shaders_shadowmap_rendering'], 'Glibc239Libm', None, Path('/raylib'))(
            ['shaders_shadowmap_rendering'], False)
        self.assertIn('J.Program.replay_io(~Ex.State', shadow)


if __name__ == '__main__':
    unittest.main()
