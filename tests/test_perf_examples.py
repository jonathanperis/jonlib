"""The performance tool's pure helpers: statistics, the frame-time split, script selection and the tables."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

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
        self.assertAlmostEqual(split['first'], 0.6)
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


class ProcessTests(unittest.TestCase):
    def test_peak_rss_report_is_taken_out_of_stderr(self):
        with mock.patch.object(pe.sys, 'platform', 'linux'):
            self.assertEqual(pe.peak_rss('warning\n\nJONLIB_PERF_MAXRSS 2048\n'), (2048, 'warning'))
        self.assertEqual(pe.peak_rss('nothing'), (None, 'nothing'))

    def test_peak_rss_is_kib_for_both_kernel_conventions(self):
        # Linux ru_maxrss is KiB. macOS ru_maxrss is bytes: the nightly reading 10092544 is 9856 KiB, and treating
        # those bytes as KiB fails the 48 MiB child ceiling (48 << 10 == 49152).
        report = 'JONLIB_PERF_MAXRSS 10092544\n'
        with mock.patch.object(pe.sys, 'platform', 'linux'):
            self.assertEqual(pe.maxrss_kib(2048), 2048)
            self.assertEqual(pe.maxrss_kib(10092544), 10092544)
            self.assertEqual(pe.peak_rss(report), (10092544, ''))
            self.assertIsNone(pe.maxrss_kib(None))
        with mock.patch.object(pe.sys, 'platform', 'darwin'):
            self.assertEqual(pe.maxrss_kib(2048 * 1024), 2048)
            self.assertEqual(pe.maxrss_kib(1025), 1)
            self.assertEqual(pe.maxrss_kib(10092544), 10092544 // 1024)
            self.assertEqual(pe.peak_rss(report), (10092544 // 1024, ''))
            self.assertLess(pe.peak_rss(report)[0], 48 << 10)
            self.assertGreater(pe.peak_rss(report)[0], 0)
            self.assertIsNone(pe.maxrss_kib(None))

    def test_launcher_reports_the_child_not_this_process(self):
        held = bytearray(64 << 20)  # this process's high-water mark must not reach the child's
        measured = pe.measure([sys.executable, '-c', 'import sys; print("a"); sys.stdout.flush(); print("b")'], cwd=pe.ROOT)
        self.assertEqual(measured['lines'], ['a', 'b'])
        self.assertLess(measured['peak_rss_kib'], 48 << 10)
        self.assertGreater(measured['peak_rss_kib'], 0)
        del held

    def test_failed_program_raises(self):
        with self.assertRaises(pe.ProbeFailure):
            pe.measure([sys.executable, '-c', 'import sys; sys.exit(3)'], cwd=pe.ROOT)

    def test_compile_cache_skips_an_unchanged_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'a.bend', Path(directory) / 'a'
            source.write_text('def main() -> IO(Unit): IO.print("a")\n')
            compiled = []
            def compile_outputs(cli, src, out):
                compiled.append(out)
                out.write_text('binary')
            with mock.patch.object(pe.probekit, 'compile_outputs', compile_outputs):
                pe.compile_cached(['bun'], source, output, extra='x')
                pe.compile_cached(['bun'], source, output, extra='x')
                self.assertEqual(len(compiled), 1)
                pe.compile_cached(['bun'], source, output, extra='other compiler')
                self.assertEqual(len(compiled), 2)
                source.write_text('changed\n')
                pe.compile_cached(['bun'], source, output, extra='other compiler')
                self.assertEqual(len(compiled), 3)


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
                     native=dict(per_frame=0.002, steady_wall=0.15, base_wall=0.03, peak_rss_kib=20480,
                                 frame_lines=dict(median=0.0018, p95=0.0031)),
                     **{'cpu-1': dict(per_frame=0.05, wall=2.5, first=1.2, base=0.4, peak_rss_kib=512000)})
        audio = dict(periods=300, output_equal=True, ratio=12.5, native=dict(per_period=0.0004, peak_rss_kib=10240),
                     **{'cpu-1': dict(per_period=0.005, peak_rss_kib=307200)})
        return dict(examples={'shapes_x': entry, 'core_y': dict(skipped='its setup takes directory listings')}, audio=audio)

    def test_table_rows(self):
        text = pe.render_table(self.results())
        self.assertIn('| shapes_x | 4 + 30 | 1.80, 3.10 | 2.00 | 50.00 | 25x | 30.00 | 1200, 400 | 20 | 500 | yes |', text)
        self.assertIn('| core_y | its setup takes directory listings |', text)
        self.assertIn('| ms per 10 ms period (callback + UpdateMusicStream) | 0.4000 | 5.00 | 12x |', text)
        self.assertIn('| share of real time | 4.0% | 50.0% | |', text)
        self.assertIn('| peak MiB (300 / 300 periods) | 10 | 300 | |', text)
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
        self.assertEqual(pe.ms(0.0000138), '0.0138')
        self.assertEqual(pe.times_text(3.25), '3.2x')
        self.assertEqual(pe.mib(None), '-')


if __name__ == '__main__':
    unittest.main()
