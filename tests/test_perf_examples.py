"""The performance tool's pure helpers: statistics, the frame-time split, script selection and the tables."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import examples_probe as ep
import perf_examples as pe


class StatisticsTests(unittest.TestCase):
    def test_nearest_rank_percentile(self):
        values = list(range(1, 21))
        self.assertEqual(pe.percentile(values, 95), 19)
        self.assertEqual(pe.percentile(values, 100), 20)
        self.assertEqual(pe.percentile([7], 95), 7)
        self.assertEqual(pe.percentile([3, 1, 2], 50), 2)

    def test_percentile_of_nothing_is_an_error(self):
        with self.assertRaises(ValueError):
            pe.percentile([], 50)

    def test_summary(self):
        self.assertIsNone(pe.summary([]))
        s = pe.summary([0.01, 0.03, 0.02, 0.10])
        self.assertAlmostEqual(s['median'], 0.025)
        self.assertEqual(s['p95'], 0.10)
        self.assertEqual((s['min'], s['max'], s['samples']), (0.01, 0.10, 4))

    def test_intervals(self):
        self.assertEqual(pe.intervals([1.0, 1.5, 3.0]), [0.5, 1.5])
        self.assertEqual(pe.intervals([1.0]), [])

    def test_ratio_and_median_skip_missing_values(self):
        self.assertEqual(pe.ratio(2.0, 0.5), 4.0)
        self.assertIsNone(pe.ratio(None, 1.0))
        self.assertIsNone(pe.ratio(1.0, 0))
        self.assertEqual(pe.median_of([dict(a=1), dict(a=None), dict(a=3)], 'a'), 2)
        self.assertIsNone(pe.median_of([dict(a=None)], 'a'))


class SplitTests(unittest.TestCase):
    def test_three_lines_give_startup_base_and_frame_time(self):
        # startup 0.1, base 0.5 (setup + frames), steady 0.5 + 10 * 0.2 = 2.5, base again 0.5, exit 0.05
        split = pe.split_candidate([0.6, 3.1, 3.6], 3.65, 10)
        self.assertTrue(split['line_timing'])
        self.assertAlmostEqual(split['startup'], 0.1)
        self.assertAlmostEqual(split['base'], 0.5)
        self.assertAlmostEqual(split['per_frame'], 0.2)
        self.assertAlmostEqual(split['exit'], 0.05)

    def test_lines_that_come_out_together_give_nothing(self):
        split = pe.split_candidate([3.0, 3.0001, 3.0002], 3.1, 10)
        self.assertFalse(split['line_timing'])
        self.assertIsNone(split['per_frame'])

    def test_wrong_line_count_gives_nothing(self):
        self.assertIsNone(pe.split_candidate([1.0, 2.0], 3.0, 10)['per_frame'])

    def test_differential_from_walls(self):
        self.assertAlmostEqual(pe.per_frame_from_walls(0.2, 0.5, 30), 0.01)
        self.assertIsNone(pe.per_frame_from_walls(0.2, 0.5, 0))


class ScriptTests(unittest.TestCase):
    def test_steady_script_appends_idle_frames(self):
        script = dict(example='x', name='x-a', frames=[([(2, 1, 0, 0)], 0.003, 0.021)], seed=0, start=0.25)
        steady = pe.steady_script(script, 3)
        self.assertEqual(len(steady['frames']), 4)
        self.assertEqual(steady['frames'][1:], [([], 0.002, 0.004)] * 3)
        self.assertEqual(len(script['frames']), 1)
        with self.assertRaises(ValueError):
            pe.steady_script(script, -1)

    def test_raw_scripts_restore_the_probe(self):
        held = ep.timed
        raw = pe.raw_scripts()
        self.assertIs(ep.timed, held)
        self.assertIsInstance(raw[0]['frames'][0], tuple)
        self.assertEqual(ep.timed(raw[0]), ep.scripts()[0])

    def test_default_examples_are_registered_and_have_a_script(self):
        raw = pe.raw_scripts()
        for name in pe.DEFAULT_EXAMPLES:
            self.assertIn(name, ep.EXAMPLES)
            self.assertIsNone(pe.unsupported(name))
            self.assertIsNotNone(pe.choose_script(name, raw, 'Glibc239Libm'), name)

    def test_choose_script_skips_undefined_and_named(self):
        raw = pe.raw_scripts()
        self.assertEqual(pe.choose_script('gui_style', raw, 'Glibc239Libm', 'charmap')['name'], 'gui_style-charmap')
        self.assertIsNone(pe.choose_script('gui_style', raw, 'Glibc239Libm', 'cut'))
        self.assertIsNotNone(pe.unsupported('textures_logo_raylib'))


class TableTests(unittest.TestCase):
    def results(self):
        entry = dict(script='a-b', base_frames=4, extra_frames=30, output_equal=True, ratio=25.0,
                     native=dict(per_frame=0.002, steady_wall=0.15, peak_rss_kib=20480,
                                 frame_lines=dict(median=0.0018, p95=0.0031)),
                     **{'cpu-1': dict(per_frame=0.05, wall=2.5, peak_rss_kib=512000)})
        audio = dict(periods=300, output_equal=True, ratio=12.5, native=dict(per_period=0.0004, peak_rss_kib=10240),
                     **{'cpu-1': dict(per_period=0.005, peak_rss_kib=307200)})
        return dict(examples={'shapes_x': entry, 'core_y': dict(skipped='its setup takes directory listings')}, audio=audio)

    def test_table_rows(self):
        text = pe.render_table(self.results())
        self.assertIn('| shapes_x | 4 + 30 | 1.80, 3.10 | 2.00 | 50.00 | 25x | 150 | 2500 | 20 | 500 | yes |', text)
        self.assertIn('| core_y | its setup takes directory listings |', text)
        self.assertIn('| ms per 10 ms period (callback + UpdateMusicStream) | 0.40 | 5.00 | 12x |', text)
        self.assertIn('| share of real time | 4.0% | 50.0% | |', text)
        self.assertNotIn('JavaScript', text)

    def test_javascript_table_only_with_the_lane(self):
        results = self.results()
        results['examples']['shapes_x']['javascript'] = dict(per_frame=2.0, wall=90.0, peak_rss_kib=1048576)
        text = pe.render_table(results)
        self.assertIn('| shapes_x | 2000 | 1000x | 90000 | 1024 |', text)

    def test_formats(self):
        self.assertEqual(pe.ms(None), '-')
        self.assertEqual(pe.ms(0.0123), '12.30')
        self.assertEqual(pe.ms(1.5), '1500')
        self.assertEqual(pe.times_text(3.25), '3.2x')
        self.assertEqual(pe.mib(None), '-')


if __name__ == '__main__':
    unittest.main()
