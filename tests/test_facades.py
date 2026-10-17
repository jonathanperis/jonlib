import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import facades


class FacadeTests(unittest.TestCase):
    def test_modules_are_current(self):
        for module in facades.MODULES:
            self.assertEqual((ROOT / module).read_text(), facades.generate(module), f'{module} is stale: rerun tools/facades.py')

    def test_wrapper(self):
        text = facades.wrapper('Rlgl.begin', 'frame: Frame, +mode: U32', 'Frame', {'Frame'})
        self.assertEqual(text, 'def Rlgl.begin(frame: J.Frame, +mode: U32) -> J.Frame:\n  J.Rlgl.begin(frame, mode)\n')
        self.assertEqual(facades.split_params('a: Maybe<(U32 & U32)>, +b: F32'), ['a: Maybe<(U32 & U32)>', '+b: F32'])

    def test_names(self):
        self.assertIn('Rlgl.set_clip_planes', facades.ledger_names('rlgl'))
        self.assertNotIn('Bool', facades.ledger_names('rlgl'))


if __name__ == '__main__':
    unittest.main()
