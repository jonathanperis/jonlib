import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import input_probe as ip


class ScriptTests(unittest.TestCase):
    def test_script_names_are_unique(self):
        names = [item['name'] for item in ip.scripts()]
        self.assertEqual(len(names), len(set(names)))

    def test_raylib_62_definitions_are_compared(self):
        items = {item['name']: item for item in ip.scripts()}
        # GetFPS answers 0 before its first sample since raylib 6.2.
        self.assertIsNone(items['fps-before-sample']['contract'])
        # Negative gamepad indexes are bounds-checked: the query rows ask them.
        self.assertNotIn('gamepad-available-negative', items)
        self.assertNotIn('gamepad-axis-count-4', items)
        # A negative button or axis of a ready gamepad is still undefined.
        self.assertIsNotNone(items['gamepad-button-negative']['contract'])
        self.assertIsNotNone(items['gamepad-axis-negative']['contract'])

    def test_load_texts(self):
        texts = {name: (text, defined, named) for name, text, defined, named in ip.load_texts()}
        self.assertTrue(texts['description-overflow'][1])
        self.assertTrue(texts['description-63-64'][1])
        text, defined, named = texts['too-many-events']
        self.assertTrue(defined)
        self.assertIsNone(named)
        self.assertEqual(text.count(b'\n'), 16386)
        self.assertTrue(text.endswith(b'\ne 2147483648 1 1 1 1 1\n'))
        self.assertFalse(texts['int-overflow'][1])

    def test_unexported_lists(self):
        ops = ip.load_scripts()[0]['ops']
        index = [k for k, op in enumerate(ops) if op[0] == 'load' and op[1] == 'too-many-events'][0]
        self.assertTrue(index + 1 == len(ops) or ops[index + 1][0] != 'export')


class RenderingTests(unittest.TestCase):
    def test_repeated_lines(self):
        self.assertEqual(ip.repeated_lines(b'e 1\n' * 100 + b'tail'), (100, b'tail'))
        self.assertEqual(ip.repeated_lines(b'e 1\n' * 3 + b'x'), (0, b'e 1\n' * 3 + b'x'))

    def test_load_defs_share_the_loop(self):
        items = [ip.script('a', [('load', 'too-many-events', b'e 1\n' * 100 + b'e 2\n', True),
                                 ('load', 'other-many', b'e 1\n' * 70, True), ('load', 'small', b'c 1\n', True)])]
        defs = ip.load_defs(items)
        self.assertEqual(sum(d.startswith('def load.repeat(') for d in defs), 1)
        self.assertIn('def LOAD_TOO_MANY_EVENTS() -> +List<U32>:\n  load.repeat(100n, [101, 32, 50, 10])', defs)
        self.assertIn('def LOAD_OTHER_MANY() -> +List<U32>:\n  load.repeat(70n, [])', defs)
        self.assertIn('def LOAD_SMALL() -> +List<U32>:\n  [99, 32, 49, 10]', defs)

    def test_queries_ask_gamepads_minus_one_to_four(self):
        source = ip.c_program(ip.scripts())
        self.assertIn('for (int g = -1; g <= 4; g++)', source)
        self.assertIn('if (name != NULL)', source)
        self.assertIn('q.pads(6n, c, 4294967295, PAD_BUTTONS) ++ q.counts(6n, c, 4294967295)', ip.PROGRAM)


if __name__ == '__main__':
    unittest.main()
