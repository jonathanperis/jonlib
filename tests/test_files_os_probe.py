import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import files_os_probe as fp


def listing(top):
    """Every path under top (links not followed), its kind, its bytes and its mode, in the order os.scandir gives them."""
    out = []

    def walk(fd, prefix):
        for entry in sorted(os.scandir(fd), key=lambda e: e.name):
            st = entry.stat(follow_symlinks=False)
            out.append((prefix + entry.name, entry.is_symlink(), entry.is_dir(follow_symlinks=False), st.st_mode & 0o777, st.st_size))
            if entry.is_dir(follow_symlinks=False) and st.st_mode & 0o500 == 0o500:
                inner = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
                walk(inner, prefix + entry.name + '/')
                os.close(inner)

    fd = os.open(top, os.O_RDONLY | os.O_DIRECTORY)
    walk(fd, '')
    os.close(fd)
    return out


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.tree = ROOT / '.build/files-os-probe/tree'

    def test_every_operation_has_a_reference_and_a_candidate(self):
        ops = fp.script(self.tree)
        self.assertEqual(len(ops), 234)
        for op, args, defined in ops:
            fp.bend_op(op, args)
            if defined:
                fp.c_op(op, args, self.tree)
        self.assertEqual({op for op, _, _ in ops}, {'is_dir', 'absolute', 'hidden', 'exists', 'is_file', 'dir_exists', 'mod_time', 'count', 'count_ex', 'load', 'load_ex', 'rename',
                                                     'remove', 'make', 'copy', 'move', 'text', 'change', 'cwd', 'app', 'url'})
        # no contracts: raylib 6.2's IsFileExtension bounds the 17-byte extension 6.0 overflowed
        self.assertEqual([(op, args[0][-8:], args[1]) for op, args, defined in ops if not defined], [])
        # the working directory changes last
        ops_names = [op for op, _, _ in ops]
        self.assertGreater(ops_names.index('change'), max(i for i, op in enumerate(ops_names) if op in ('copy', 'move', 'url')))

    def test_the_chains_reach_past_and_exactly_at_the_limit(self):
        base = len('.build/files-os-probe/tree') + 1
        long = fp.chain_names(base + len('long'), 4200, False)
        exact = fp.chain_names(base + len('exact'), 4095, True)
        self.assertEqual(base + len('exact') + sum(1 + len(n) for n in exact), 4095)
        self.assertGreater(base + len('long') + sum(1 + len(n) for n in long), 4096)
        self.assertTrue(all(0 < len(n) <= 255 for n in long + exact))

    def test_the_reference_program_writes_one_line_an_operation(self):
        source = fp.native_source(fp.script(self.tree), self.tree)
        self.assertIn('GetDirectoryFileCountEx(', source)
        self.assertIn('FileMove(', source)
        self.assertIn('OpenURL(', source)
        self.assertNotIn('"tree-odd", ".png"', source)

    def test_the_candidate_program_imports_jonlib(self):
        text = fp.render(fp.script(self.tree))
        self.assertIn('import ../../jonlib.bend as J\n', text)
        self.assertIn('J.Files.load_directory_files_ex(', text)
        self.assertIn('J.System.open_url(', text)
        self.assertTrue(text.rstrip().endswith('IO.print("done")'))

    def test_parse_requires_the_end(self):
        self.assertEqual(fp.parse('1\n0\ndone\n'), ['1', '0'])
        with self.assertRaises(fp.ProbeFailure):
            fp.parse('1\n0\n')


class TreeTests(unittest.TestCase):
    def test_the_tree_is_the_same_every_time(self):
        build_dir = ROOT / '.build'
        build_dir.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build_dir, prefix='files-os-') as directory:
            tree = Path(directory) / 'tree'
            with mock.patch.object(fp, 'ROOT', ROOT):
                fp.build(tree)
                first = listing(tree), listing(tree.parent / 'tree-odd')
                fp.build(tree)
                second = listing(tree), listing(tree.parent / 'tree-odd')
                fp.unlock(tree)
        self.assertEqual(first, second)
        names = [entry[0] for entry in first[0]]
        for name in ('a.png', 'C.PNG', 'empty.dat', 'link', 'dangling', 'noread', 'unreadable.txt', 'sub/deep/d.txt', 'bin/explorer'):
            self.assertIn(name, names)
        modes = {entry[0]: entry[3] for entry in first[0]}
        self.assertEqual((modes['noread'], modes['unreadable.txt']), (0, 0))


if __name__ == '__main__':
    unittest.main()
