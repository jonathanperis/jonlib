import sys
import tempfile
import types
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import examples_probe as ep


class ListedTests(unittest.TestCase):
    def test_a_script_s_files_may_be_in_directories(self):
        with tempfile.TemporaryDirectory() as work:
            probe = types.SimpleNamespace(work=Path(work))
            items = [dict(example='core_directory_files', name='core_directory_files-browse')]
            ep.scratch_reset(probe, items, native=True)
            root = ep.scratch(probe, 0, native=True)
            left = ep.scratch_left(probe, 0, native=True)
            self.assertEqual(left, {name: data for name, data in ep.FILES['core_directory_files-browse'].items()})
            self.assertTrue((root / 'top/mid/cwd/sub').is_dir() and (root / 'top/mid/build/out.o').is_file())
            self.assertEqual(ep.scratch_left(probe, 0, native=True)['top/readme'], b'read me')

    def test_the_listings_go_up_to_the_script_s_directory(self):
        with tempfile.TemporaryDirectory() as work:
            probe = types.SimpleNamespace(work=Path(work))
            items = [dict(example='core_directory_files', name='core_directory_files-browse')]
            ep.scratch_reset(probe, items, native=True)
            root = ep.scratch(probe, 0, native=True).resolve()
            found = ep.listings(root, ep.WORKING['core_directory_files'])
            self.assertEqual([path for path, _ in found], [str(root / 'top/mid/cwd'), str(root / 'top/mid'), str(root / 'top'), str(root)])
            self.assertEqual(sorted(found[1][1]), [('build', False), ('cwd', False), ('notes.md', True), ('photo.png', True)])
            self.assertEqual(sorted(found[2][1]), [('mid', False), ('readme', True)])
            self.assertEqual(found[3][1], [('top', False)])
            here = dict(found[0][1])
            self.assertEqual((len(here), here['sub'], here['alpha.png'], here['.hidden.c']), (34, False, True, True))
            # read again, the order is the same: what the reference lists is what the port was handed
            self.assertEqual(found, ep.listings(root, ep.WORKING['core_directory_files']))

    def test_the_listings_as_bend(self):
        text = ep.listings_text([('/a/b', [('x.c', True), ('d', False)]), ('/a', [])])
        self.assertEqual(text, '[Ex.Listing{"/a/b", [Ex.Entry{"x.c", True{}}, Ex.Entry{"d", False{}}]}, Ex.Listing{"/a", Nil{}}]')

    def test_the_example_is_handed_its_listings(self):
        self.assertEqual(ep.EXAMPLES['core_directory_files'][1], 'Ex.setup(listings, core, frame)')
        self.assertTrue({'core_directory_files'} <= ep.LISTED and {'core_directory_files'} <= ep.SCRATCH)
        # every file the filtered script lists has an extension of its own: the path's first dot is the probe's
        self.assertTrue(all('.' in Path(name).name for name in ep.FILES['core_directory_files-browse'] if name.startswith('top/mid/cwd/') and name.count('/') == 3))
        self.assertEqual((ep.UNDEFINED_FROM['core_directory_files-noext'], 'top/mid/cwd/noext' in ep.FILES['core_directory_files-noext']), (0, True))
        names = [item['name'] for item in ep.scripts() if item['example'] == 'core_directory_files']
        self.assertEqual(names, ['core_directory_files-browse', 'core_directory_files-noext'])

    def test_touch_points_press_buttons(self):
        browse = next(item for item in ep.scripts() if item['name'] == 'core_directory_files-browse')
        kinds = [event[0] for frame in browse['frames'] for event in frame['events']]
        self.assertEqual((kinds.count(ep.TOUCH_DOWN), kinds.count(ep.TOUCH_UP)), (2, 2))


if __name__ == '__main__':
    unittest.main()
