"""The shared probe runner batches actions faithfully and reports failed commands and resource limits."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import probekit
from probekit import ProbeFailure, plan_batches


class BatchPlanTests(unittest.TestCase):
    def test_count_limited_batches_keep_order_and_cover_everything(self):
        batches = plan_batches(list(range(10)), 4)
        self.assertEqual(batches, [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]])

    def test_source_limit_splits_before_exceeding_budget(self):
        measure = lambda selected: sum(selected)
        self.assertEqual(plan_batches([5, 5, 5, 1, 9], 10, measure, 11), [[5, 5], [5, 1], [9]])

    def test_single_oversized_action_is_an_error(self):
        with self.assertRaises(ProbeFailure):
            plan_batches([3, 50], 10, sum, 10)

    def test_nonpositive_batch_rejected(self):
        with self.assertRaises(ValueError):
            plan_batches([1], 0)


class RunTests(unittest.TestCase):
    def test_failed_command_reports_output(self):
        with self.assertRaisesRegex(ProbeFailure, 'boom'):
            probekit.run([sys.executable, '-c', 'import sys; print("boom"); sys.exit(3)'])

    def test_fd_limit_applies_to_child(self):
        out = probekit.run([sys.executable, '-c', 'import resource; print(resource.getrlimit(resource.RLIMIT_NOFILE)[0])'],
                           fd_limit=64)
        self.assertEqual(out.strip(), '64')


class LaneTests(unittest.TestCase):
    """Drive candidates()/compare() with stand-in compiled programs."""

    def make_probe(self, work, gpu=False, jobs=2):
        probe = probekit.Probe.__new__(probekit.Probe)
        probe.name, probe.args = 'fake', SimpleNamespace(gpu=gpu, jobs=jobs, bend_source=Path('/unused'))
        probe.work, probe.results = work, work / 'results.json'
        probe.report = dict(passed=False, lanes={})
        return probe

    def fake_compile(self, probe, outputs):
        """Each lane 'binary' prints one JSON row per selected action, transformed per lane."""
        def compile_batch(index, render):
            selected = json.loads(render(False))
            return {lane: [sys.executable, '-c', 'import json,sys;[print(json.dumps(x)) for x in json.loads(sys.argv[1])]',
                           json.dumps([outputs(lane, a) for a in selected])] for lane in probe.lanes}
        return compile_batch

    def test_matching_lanes_pass_and_keep_plan_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = self.make_probe(Path(tmp))
            probe._compile = self.fake_compile(probe, lambda lane, a: a * 10)
            lanes = probe.candidates(lambda selected, gpu: json.dumps(selected), list(range(7)), batch=3)
            self.assertEqual(set(lanes), {'cpu-1', 'cpu-2', 'javascript'})
            probe.compare([a * 10 for a in range(7)], lanes)
            self.assertTrue(all(lane['passed'] for lane in probe.report['lanes'].values()))
            self.assertEqual(probe.report['batches'], 3)

    def test_single_lane_mismatch_fails_with_location(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = self.make_probe(Path(tmp))
            probe._compile = self.fake_compile(probe, lambda lane, a: a + (1 if lane == 'javascript' and a == 5 else 0))
            lanes = probe.candidates(lambda selected, gpu: json.dumps(selected), list(range(7)), batch=3)
            with self.assertRaisesRegex(ProbeFailure, 'javascript differs at 1 rows; first action 5'):
                probe.compare(list(range(7)), lanes)

    def test_missing_rows_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = self.make_probe(Path(tmp))
            def compile_batch(index, render):
                return {lane: [sys.executable, '-c', 'print(1)'] for lane in probe.lanes}
            probe._compile = compile_batch
            with self.assertRaisesRegex(ProbeFailure, 'produced 1 rows for 2 actions'):
                probe.candidates(lambda selected, gpu: '', [1, 2], batch=2)

    def test_gpu_flag_adds_mandatory_lane(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = self.make_probe(Path(tmp), gpu=True)
            self.assertEqual(probe.lanes, ('cpu-1', 'cpu-2', 'javascript', 'gpu'))

    def test_empty_actions_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ProbeFailure):
                self.make_probe(Path(tmp)).candidates(lambda s, g: '', [])


if __name__ == '__main__':
    unittest.main()


class CompileTests(unittest.TestCase):
    def test_one_compiler_process_per_output(self):
        calls = []
        with mock.patch.object(probekit, 'run', side_effect=lambda command, **kw: calls.append((command, kw))):
            probekit.compile_outputs(['bun', 'main.ts'], 'p.bend', 'p', 'p.js')
        self.assertEqual([c for c, _ in calls], [['bun', 'main.ts', 'p.bend', '-o', 'p'], ['bun', 'main.ts', 'p.bend', '-o', 'p.js']])
        self.assertTrue(all(kw['timeout'] == probekit.COMPILE_TIMEOUT for _, kw in calls))


class JobTests(unittest.TestCase):
    def jobs(self, cpus, gib, cgroup=None):
        pages = {'SC_PAGE_SIZE': 4096, 'SC_PHYS_PAGES': gib * (1 << 30) // 4096}
        with tempfile.TemporaryDirectory() as tmp:
            limit = Path(tmp) / 'memory.max'
            if cgroup is not None:
                limit.write_text(cgroup)
            with mock.patch.object(probekit.os, 'cpu_count', return_value=cpus), \
                 mock.patch.object(probekit.os, 'sysconf', side_effect=pages.__getitem__), \
                 mock.patch.object(probekit, 'CGROUP_MEMORY', limit):
                return probekit.default_jobs()

    def test_memory_bounds_concurrent_batches(self):
        self.assertEqual(self.jobs(4, 16), 1)   # hosted Linux runner: one 8 GB compile at a time
        self.assertEqual(self.jobs(3, 7), 1)    # hosted macOS runner
        self.assertEqual(self.jobs(16, 64), 4)  # never above four
        self.assertEqual(self.jobs(8, 2), 1)    # small hosts still run
        self.assertEqual(self.jobs(8, 32), 3)

    def test_cgroup_limit_bounds_concurrent_batches(self):
        self.assertEqual(self.jobs(8, 64, str(8 << 30)), 1)   # a container capped below the host
        self.assertEqual(self.jobs(8, 64, str(20 << 30)), 2)
        self.assertEqual(self.jobs(8, 64, 'max'), 4)          # unlimited cgroup
