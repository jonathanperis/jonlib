import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import example_tables


class LayoutTests(unittest.TestCase):
    def test_numbers_keep_c_integer_arithmetic_exact(self):
        self.assertEqual(example_tables.number('317'), '317.0')
        self.assertEqual(example_tables.number('0.5f'), '0.5')
        self.assertEqual(example_tables.number('202 + 45'), '(202.0 + 45.0 : F32)')
        self.assertEqual(example_tables.number('259 + (int)(leftStickX*20)'), '(259.0 + F32.trunc((lx * 20.0 : F32)) : F32)')
        self.assertEqual(example_tables.number('(int)(((1 + rightTrigger)/2)*70)'), 'F32.trunc((((1.0 + rt) / 2.0) * 70.0 : F32))')
        with self.assertRaises(SystemExit):
            example_tables.number('x*y')

    def test_arguments_split_at_the_top_level_only(self):
        self.assertEqual(example_tables.split('(Vector2){ 1, 2 }, (Vector2){ 3, 4 }, RED'), ['(Vector2){ 1, 2 }', '(Vector2){ 3, 4 }', 'RED'])

    def test_a_layout_is_a_chain_of_conditional_draws(self):
        block = '''DrawTexture(texXboxPad, 0, 0, DARKGRAY);
            // a comment
            if (IsGamepadButtonDown(gamepad, GAMEPAD_BUTTON_MIDDLE)) DrawCircle(394, 89, 19, RED);
            Color leftGamepadColor = BLACK;
            if (IsGamepadButtonDown(gamepad, GAMEPAD_BUTTON_LEFT_THUMB)) leftGamepadColor = RED;
            DrawRectangle(151, 110, 15, (int)(((1 + leftTrigger)/2)*70), RED);
            DrawCircle(259 + (int)(leftStickX*20), 152, 25, leftGamepadColor);'''
        lines = example_tables.layout('pad.test', block, 'A test layout.').split('\n')
        self.assertEqual(lines[0], '# A test layout.')
        self.assertTrue(lines[1].startswith('def pad.test(+libm: M.Libm, +core: J.Core, +pad: U32,'))
        self.assertEqual(lines[2], '  f1 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE()), libm, frame, 394.0, 89.0, 19.0, J.Color.RED())')
        self.assertEqual(lines[3], '  +left = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_THUMB()), J.Color.RED(), J.Color.BLACK())')
        self.assertEqual(lines[4], '  f2 = box(True{}, f1, 151.0, 110.0, 15.0, F32.trunc((((1.0 + lt) / 2.0) * 70.0 : F32)), J.Color.RED())')
        self.assertEqual(lines[5], '  circle(True{}, libm, f2, (259.0 + F32.trunc((lx * 20.0 : F32)) : F32), 152.0, 25.0, left)')

    def test_an_unknown_statement_stops_the_generator(self):
        with self.assertRaises(SystemExit):
            example_tables.layout('pad.test', 'DrawPoly(center, 6, 10, 0, RED);', 'x')

    @unittest.skipUnless(os.environ.get('JONLIB_RAYLIB_SOURCE'), 'needs the pinned raylib checkout (JONLIB_RAYLIB_SOURCE)')
    def test_the_ports_hold_the_generated_tables(self):
        raylib = Path(os.environ['JONLIB_RAYLIB_SOURCE'])
        self.assertIn(example_tables.keyboard(raylib), (ROOT / 'examples/core_keyboard_testbed.bend').read_text())
        self.assertIn(example_tables.gamepad(raylib), (ROOT / 'examples/core_input_gamepad.bend').read_text())


if __name__ == '__main__':
    unittest.main()
