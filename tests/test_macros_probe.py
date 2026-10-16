import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import macros_probe as mp


class SelectionTests(unittest.TestCase):
    def test_value_macros_by_kind(self):
        enumerators = {'MOUSE_BUTTON_LEFT'}
        cases = {'0x0001': 'int', '8192': 'int', '0.05': 'double', '4000.0': 'double', '"6.0"': 'string', '1.5f': 'float',
                 'MOUSE_BUTTON_LEFT': 'int', 'GetScreenToWorldRay': None, '': None, 'malloc(sz)': None, 'UNKNOWN_NAME': None,
                 'CLITERAL(Color){ 200, 200, 200, 255 }': None}
        self.assertEqual({value: mp.kind_of(value, enumerators) for value in cases}, cases)

    def test_the_catalog_selection(self):
        selected = mp.macros()
        names = {b for _, _, _, b in selected}
        self.assertIn('Rlgl.RL_TEXTURE_WRAP_S', names)
        self.assertIn('Math.PI', names)
        self.assertIn('Config.JONLIB_VERSION', names)
        self.assertEqual(len(selected), len(names))

    def test_bend_values(self):
        self.assertEqual(mp.bend_value('double', '1068079513 2576980378'), ('M.Float64', 'M.Float64{1068079513, 2576980378}'))
        self.assertEqual(mp.bend_value('string', '6.0'), ('String', '"6.0"'))
        self.assertEqual(mp.bend_value('int', '10242'), ('U32', '10242'))


if __name__ == '__main__':
    unittest.main()
