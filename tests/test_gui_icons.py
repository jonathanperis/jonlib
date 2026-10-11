import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import gui_icons


def header(words):
    rows = ', '.join(f'0x{word:08x}' for word in words)
    return f'// raygui\n{gui_icons.START}\n    {rows},      // ICON\n}};\n'


def checkout(root, tables):
    for index, words in enumerate(tables):
        directory = root / 'examples' / f'category{index}'
        directory.mkdir(parents=True)
        (directory / 'raygui.h').write_text(header(words))
    return root


class GuiIconsTests(unittest.TestCase):
    def test_the_table_is_read_from_every_copy(self):
        words = [(index * 2654435761) & 0xFFFFFFFF for index in range(2048)]
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(gui_icons.icons(checkout(Path(directory), [words, words])), words)

    def test_copies_that_disagree_stop_the_tool(self):
        words = list(range(2048))
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(AssertionError):
                gui_icons.icons(checkout(Path(directory), [words, words[::-1]]))

    def test_a_short_table_stops_the_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(AssertionError):
                gui_icons.icons(checkout(Path(directory), [list(range(2040))]))

    def test_the_module_lists_eight_words_an_icon(self):
        words = list(range(2048))
        text = gui_icons.module(words)
        body = text[text.index('['):text.index(']')]
        self.assertEqual([int(word) for word in re.findall(r'\d+', body)], words)
        self.assertEqual(len([line for line in body.splitlines() if line.strip().strip('[')]), 256)
        self.assertIn('LICENSES/raygui.txt', text)
        self.assertIn('def word(+id: U32, +index: U32) -> U32:', text)

    def test_the_committed_module_has_the_generated_shape(self):
        text = (gui_icons.ROOT / 'src/gui_icons.bend').read_text()
        body = text[text.index('['):text.index(']')]
        words = [int(word) for word in re.findall(r'\d+', body)]
        self.assertEqual(len(words), 2048)
        self.assertEqual(text, gui_icons.module(words))
        self.assertEqual(words[:8], [0] * 8)


if __name__ == '__main__':
    unittest.main()
