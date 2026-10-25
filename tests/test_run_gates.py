"""Argument parsing, the gate result file and failed-gate selection."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import run_gates


def gate(name, minutes=1, hosts=('linux', 'macos'), script=None):
    return dict(id=name, title=name, run=['{python}', script or f'tools/{name}_probe.py'], os=list(hosts), minutes=minutes)


def document(os_name, **passed):
    return dict(os=os_name, gates=[dict(id=name, passed=flag) for name, flag in passed.items()])


class ParseTests(unittest.TestCase):
    def test_one_id_and_several_ids(self):
        self.assertEqual(run_gates.split_ids(['bmp-format']), ['bmp-format'])
        self.assertEqual(run_gates.split_ids(['extrema,bmp-format']), ['extrema', 'bmp-format'])
        self.assertEqual(run_gates.split_ids(['extrema, bmp-format']), ['extrema', 'bmp-format'])
        self.assertEqual(run_gates.split_ids(['extrema bmp-format']), ['extrema', 'bmp-format'])
        self.assertEqual(run_gates.split_ids(['extrema', 'bmp-format', 'extrema']), ['extrema', 'bmp-format'])
        self.assertEqual(run_gates.split_ids(['  extrema,, bmp-format  ']), ['extrema', 'bmp-format'])

    def test_an_unknown_id_fails_before_a_gate_runs(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = run_gates.main(['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux', '--only', 'bmp-format,not-a-gate'])
        self.assertEqual(code, 2)
        self.assertIn('unknown gate id: not-a-gate', err.getvalue())


class ResultFileTests(unittest.TestCase):
    def test_the_file_lists_id_and_pass_fail_in_run_order(self):
        gates = [gate('alpha'), gate('beta', script='tools/beta_probe.py')]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            results = root / 'gate-results.json'
            calls = []

            def fake_run(cmd, **kwargs):
                calls.append(cmd[1])
                return mock.Mock(returncode=1 if cmd[1].endswith('beta_probe.py') else 0)

            with mock.patch.object(run_gates, 'load', return_value=gates), \
                    mock.patch.object(run_gates, 'OUT', root / 'gates'), \
                    mock.patch.object(run_gates.subprocess, 'run', side_effect=fake_run):
                code = run_gates.main(['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux',
                                       '--only', 'beta, alpha', '--results', str(results)])
            document = json.loads(results.read_text())
        self.assertEqual(code, 1)
        self.assertEqual(set(document), {'os', 'gates'})
        self.assertEqual(document['os'], 'linux')
        self.assertEqual(document['gates'], [dict(id='alpha', passed=True), dict(id='beta', passed=False)])
        self.assertIsInstance(document['gates'][0]['passed'], bool)
        self.assertEqual([Path(cmd).name for cmd in calls], ['alpha_probe.py', 'beta_probe.py'])

    def test_a_single_only_still_runs_that_gate(self):
        gates = [gate('alpha'), gate('beta', script='tools/beta_probe.py')]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            results = root / 'gate-results.json'
            calls = []
            with mock.patch.object(run_gates, 'load', return_value=gates), \
                    mock.patch.object(run_gates, 'OUT', root / 'gates'), \
                    mock.patch.object(run_gates.subprocess, 'run', side_effect=lambda cmd, **kwargs: calls.append(cmd[1]) or mock.Mock(returncode=0)):
                code = run_gates.main(['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux',
                                       '--only', 'beta', '--results', str(results)])
            text = results.read_text()
        self.assertEqual(code, 0)
        self.assertEqual(calls, ['tools/beta_probe.py'])
        self.assertEqual(json.loads(text)['gates'], [dict(id='beta', passed=True)])

    def test_the_default_path_is_gitignored(self):
        self.assertEqual(run_gates.RESULTS, ROOT / '.build' / 'gate-results.json')
        self.assertEqual(subprocess.run(['git', 'check-ignore', '-q', '--', str(run_gates.RESULTS)], cwd=ROOT).returncode, 0)

    def test_a_result_entry_must_be_a_boolean(self):
        with self.assertRaises(ValueError):
            run_gates.failed_ids(dict(os='linux', gates=[dict(id='alpha', passed=0)]))
        with self.assertRaises(ValueError):
            run_gates.read_results(Path('/no/such/gate-results.json'))


class FailedSelectionTests(unittest.TestCase):
    GATES = [gate('alpha'), gate('beta', minutes=2, script='tools/beta_probe.py'), gate('gamma', minutes=3, script='tools/gamma_probe.py')]

    def run_main(self, argv, results, codes=None):
        codes = codes or {}
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(Path(cmd[1]).stem.replace('_probe', ''))
            return mock.Mock(returncode=codes.get(calls[-1], 0))

        with mock.patch.object(run_gates, 'load', return_value=self.GATES), \
                mock.patch.object(run_gates, 'OUT', results.parent / 'gates'), \
                mock.patch.object(run_gates.subprocess, 'run', side_effect=fake_run):
            code = run_gates.main(argv + ['--results', str(results)])
        return code, calls, json.loads(results.read_text()) if results.exists() else None

    def test_failed_from_reruns_only_the_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'previous.json'
            source.write_text(json.dumps(document('linux', alpha=True, beta=False, gamma=False)) + '\n')
            code, calls, written = self.run_main(
                ['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux', '--failed-from', str(source)],
                root / 'gate-results.json', codes=dict(beta=0, gamma=1))
        self.assertEqual(calls, ['beta', 'gamma'])
        self.assertEqual(code, 1)
        self.assertEqual(written['gates'], [dict(id='beta', passed=True), dict(id='gamma', passed=False)])

    def test_only_narrows_a_failed_from_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'previous.json'
            source.write_text(json.dumps(document('linux', alpha=False, beta=False)) + '\n')
            code, calls, written = self.run_main(
                ['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux', '--only', 'alpha', '--failed-from', str(source)],
                root / 'gate-results.json')
        self.assertEqual((code, calls), (0, ['alpha']))
        self.assertEqual(written['gates'], [dict(id='alpha', passed=True)])

    def test_a_file_from_the_other_host_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'previous.json'
            source.write_text(json.dumps(document('macos', alpha=False)) + '\n')
            err = io.StringIO()
            with redirect_stderr(err):
                code, calls, written = self.run_main(
                    ['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux', '--failed-from', str(source)],
                    root / 'gate-results.json')
        self.assertEqual(code, 2)
        self.assertEqual(calls, [])
        self.assertIn('results file is for macos, this run is linux', err.getvalue())
        self.assertIsNone(written)

    def test_nothing_failed_writes_an_empty_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'previous.json'
            source.write_text(json.dumps(document('linux', alpha=True)) + '\n')
            code, calls, written = self.run_main(
                ['--bend-source', 'bend', '--raylib-source', 'raylib', '--os', 'linux', '--failed-from', str(source)],
                root / 'gate-results.json')
        self.assertEqual((code, calls, written['gates']), (0, [], []))

    def test_merge_keeps_a_failure_from_any_shard(self):
        merged = run_gates.merge_results([
            document('linux', alpha=True, beta=True),
            document('linux', beta=False, gamma=True),
        ])
        self.assertEqual(merged, [document('linux', alpha=True, beta=False, gamma=True)])
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'a.json').write_text(json.dumps(document('linux', alpha=False)) + '\n')
            (root / 'b.json').write_text(json.dumps(document('macos', alpha=True)) + '\n')
            with self.assertRaises(ValueError):
                run_gates.merge_result_tree(root)


class DispatchPlanTests(unittest.TestCase):
    def manifest(self, count, minutes=1, hosts=('linux', 'macos')):
        return [gate(f'gate-{index}', minutes=minutes, hosts=hosts) for index in range(count)]

    def test_a_few_gates_stay_one_shard_and_more_are_split(self):
        one = run_gates.dispatch_plan('gate-0', 'linux', '', self.manifest(1))
        self.assertEqual(one['linux'], [dict(shard='1', count='1', gates='gate-0')])
        four = run_gates.dispatch_plan('gate-0, gate-1 gate-2,gate-3', 'both', '', self.manifest(4))
        self.assertEqual([row['gates'] for row in four['linux']], ['gate-0,gate-1,gate-2,gate-3'])
        self.assertEqual(four['linux'], four['macos'])
        five = run_gates.dispatch_plan(','.join(f'gate-{index}' for index in range(5)), 'linux', '', self.manifest(5))
        ids = [gate_id for row in five['linux'] for gate_id in row['gates'].split(',')]
        self.assertEqual(sorted(ids), [f'gate-{index}' for index in range(5)])
        self.assertGreater(len(five['linux']), 1)
        self.assertNotIn('macos', five)
        heavy = run_gates.dispatch_plan('gate-0,gate-1', 'linux', '', self.manifest(2, minutes=80))
        self.assertEqual(len(heavy['linux']), 2)

    def test_an_unknown_id_or_both_inputs_fail(self):
        manifest = self.manifest(1)
        with self.assertRaisesRegex(ValueError, 'unknown gate id: nope'):
            run_gates.dispatch_plan('gate-0,nope', 'linux', '', manifest)
        with self.assertRaisesRegex(ValueError, 'not both'):
            run_gates.dispatch_plan('gate-0', 'linux', '12', manifest)
        with self.assertRaisesRegex(ValueError, 'set gates or rerun_failed_from'):
            run_gates.dispatch_plan('  ', 'linux', '', manifest)
        with self.assertRaisesRegex(ValueError, 'rerun_failed_from must be a run id'):
            run_gates.dispatch_plan('', 'linux', '12;rm', manifest, documents=[])

    def test_a_gate_missing_on_the_chosen_host_fails(self):
        manifest = [gate('alpha', hosts=('linux',))]
        with self.assertRaisesRegex(ValueError, 'not declared for macos: alpha'):
            run_gates.dispatch_plan('alpha', 'macos', '', manifest)
        rows = run_gates.dispatch_plan('alpha', 'both', '', manifest)
        self.assertEqual(list(rows), ['linux'])

    def test_a_rerun_uses_the_hosts_where_gates_failed(self):
        manifest = self.manifest(3)
        documents = [
            document('linux', **{'gate-0': True, 'gate-1': False}),
            document('macos', **{'gate-0': False, 'gate-2': True}),
        ]
        rows = run_gates.dispatch_plan('', 'linux', '4400', manifest, documents=documents)
        self.assertEqual(rows['linux'], [dict(shard='1', count='1', gates='gate-1')])
        self.assertEqual(rows['macos'], [dict(shard='1', count='1', gates='gate-0')])
        self.assertEqual(run_gates.dispatch_plan('', 'macos', '4400', manifest, documents=[document('linux', **{'gate-0': True})]), {})
        self.assertEqual(run_gates.describe_plan({}), 'No failed gates to rerun.')

    def test_shard_artifacts_fill_in_a_missing_host(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def fake(cmd, **kwargs):
                if '--name' in cmd:
                    name = cmd[cmd.index('--name') + 1]
                    if 'ubuntu' in name:
                        dest = Path(cmd[cmd.index('--dir') + 1])
                        dest.mkdir(parents=True, exist_ok=True)
                        (dest / 'gate-results.json').write_text(json.dumps(document('linux', alpha=False)) + '\n')
                        return mock.Mock(returncode=0, stdout='', stderr='')
                    return mock.Mock(returncode=1, stdout='', stderr='no artifact matches')
                dest = Path(cmd[cmd.index('--dir') + 1])
                shard = dest / 'gate-results-macos-15-1'
                shard.mkdir(parents=True)
                (shard / 'gate-results.json').write_text(json.dumps(document('macos', beta=False)) + '\n')
                linux = dest / 'gate-results-ubuntu-24.04'
                linux.mkdir()
                (linux / 'gate-results.json').write_text(json.dumps(document('linux', alpha=True)) + '\n')
                return mock.Mock(returncode=0, stdout='', stderr='')

            documents = run_gates.download_run_results('77', 'owner/repo', root / 'out', run=fake)
        by_os = {item['os']: item for item in documents}
        self.assertEqual(by_os['linux']['gates'], [dict(id='alpha', passed=False)])
        self.assertEqual(by_os['macos']['gates'], [dict(id='beta', passed=False)])

    def test_the_plan_command_rejects_an_unknown_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'github-output'
            err = io.StringIO()
            with redirect_stderr(err), mock.patch.dict(os.environ, {'GITHUB_OUTPUT': str(output)}):
                code = run_gates.main(['--plan-dispatch', '--gates', 'not-a-gate', '--hosts', 'linux'])
            text = output.read_text()
        self.assertEqual(code, 2)
        self.assertIn('unknown gate id: not-a-gate', err.getvalue())
        self.assertIn('run_linux=no\n', text)
        self.assertIn('run_macos=no\n', text)
        self.assertIn('"gates": ""', text)


if __name__ == '__main__':
    unittest.main()
