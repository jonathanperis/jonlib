import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import gui_icon_files_probe as gp


class CorpusTests(unittest.TestCase):
    def test_the_header_is_little_endian_shorts(self):
        data = gp.rgi(3, -16, [b'AB'], [1])
        self.assertEqual(data[:4], b'rGI ')
        self.assertEqual(struct.unpack('<hhhh', data[4:12]), (100, 0, 3, -16))
        self.assertEqual(data[12:44], b'AB'.ljust(32, b'\0'))
        self.assertEqual(data[44:], struct.pack('<I', 1))

    def test_the_new_table_is_count_times_words_per_icon(self):
        self.assertEqual(gp.table(gp.rgi(3, 16, [], [])), 24)
        self.assertEqual(gp.table(gp.rgi(2, 32, [], [])), 64)
        self.assertEqual(gp.table(gp.rgi(4, -16, [], [])), 32)
        self.assertEqual(gp.table(gp.rgi(5, 0, [], [])), 0)
        self.assertEqual(gp.table(gp.rgi(3, 5, [], [])), 0)

    def test_what_raygui_leaves_undefined(self):
        self.assertTrue(gp.defined(None, True))
        self.assertTrue(gp.defined('dir', True))
        self.assertTrue(gp.defined(b'', True))
        self.assertTrue(gp.defined(gp.rgi(3, 16, [], [0] * 24, signature=b'rGIx'), True))
        # raygui copies the 12-byte header out of the data before anything else.
        self.assertFalse(gp.defined(gp.rgi(9, 16, [], [], cut=10), False))
        self.assertFalse(gp.defined(gp.rgi(9, 16, [], [], cut=11), False))
        self.assertTrue(gp.defined(gp.rgi(0, 16, [], []), True))
        self.assertFalse(gp.defined(gp.rgi(-1, 16, [], [0] * 8), False))
        # The data must hold every word; the table is new, of any size.
        self.assertFalse(gp.defined(gp.rgi(257, 16, [], [0] * 8), False))
        self.assertTrue(gp.defined(gp.rgi(513, 16, [b'M'] * 513, [0] * (513 * 8)), False))
        # raygui's name array has 512 slots.
        self.assertFalse(gp.defined(gp.rgi(513, 16, [b'M'] * 513, [0] * (513 * 8)), True))
        self.assertTrue(gp.defined(gp.rgi(512, 16, [b'M'] * 512, [0] * (512 * 8)), True))
        self.assertFalse(gp.defined(gp.rgi(32767, 32767, [], [0] * 8), False))
        self.assertFalse(gp.defined(gp.rgi(2, 16, [b'T1', b'T2'], [0] * 16, cut=12 + 64 + 60), False))
        self.assertTrue(gp.defined(gp.rgi(2, 16, [b'T1', b'T2'], [0] * 16), False))
        # Name ids past the data only matter when they are asked for.
        self.assertFalse(gp.defined(gp.rgi(3, 0, [b'A'], []), True))
        self.assertTrue(gp.defined(gp.rgi(3, 0, [b'A'], []), False))


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.ops = gp.script()
        self.work = ROOT / '.build/gui-icon-files-probe'

    def test_the_script(self):
        loads = [op for op in self.ops if op[0] == 'load']
        texts = [op for op in self.ops if op[0] == 'text']
        self.assertEqual(len(loads), len(gp.corpus()) + 1)
        self.assertEqual(len(texts), len(gp.ICON_IDS) * len(gp.icon_texts()))
        self.assertEqual(sorted(op[1] for op in loads if not op[3]),
                         ['eleven-bytes.rgi', 'more-named.rgi', 'negative-count.rgi', 'overflow.rgi', 'short-data.rgi', 'short-names.rgi',
                          'six-bytes.rgi', 'torn-word.rgi'])
        self.assertTrue(all(len(op[2]) >= 1019 for op in texts if not op[3]))
        words = {op[1]: op[4] for op in loads[:-1]}
        self.assertEqual(words['three.rgi'], 24)
        self.assertEqual(words['all.rgi'], 4096)
        self.assertEqual(words['more.rgi'], 4104)
        self.assertEqual(words['empty.rgi'], 4104)
        self.assertEqual(words['twelve-bytes.rgi'], 0)
        self.assertEqual(loads[-1][4], 24)

    def test_the_programs(self):
        source = gp.native_source(self.ops, self.work)
        self.assertIn('GuiLoadIcons(path, names)', source)
        self.assertIn('GuiIconText(id, t)', source)
        self.assertIn('more.rgi", false, 513, 4104);', source)
        self.assertNotIn('more-named.rgi', source)
        program = gp.render(self.ops, self.work)
        self.assertIn('import ../../jongui.bend as G\n', program)
        self.assertIn('G.Gui.load_icons(gui, ', program)
        self.assertIn('G.Gui.icon_text(4294967291, ', program)
        self.assertTrue(program.rstrip().endswith('IO.print("done")'))

    def test_rows(self):
        self.assertEqual(gp.parse('a\nb\ndone\n'), ['a', 'b'])
        with self.assertRaises(gp.ProbeFailure):
            gp.parse('a\nb\n')
        ops = [('load', 'x.rgi', True, False, 0), ('text', 1, 'two\nlines', True)]
        self.assertEqual(gp.candidate_rows(ops, 'undefined 0 123\n#001two\nlines\ndone\n'), ['undefined', '#001two\nlines'])
        self.assertEqual(gp.expected_rows(ops, '#001two\nlines\n'), ['undefined', '#001two\nlines'])


if __name__ == '__main__':
    unittest.main()
