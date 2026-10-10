"""The gate manifest, its sharding and the Conformance workflow stay consistent.

These are semantic checks (what runs, where, and that nothing can pass vacuously),
not snapshots of workflow text.
"""
import glob
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import run_gates

# Probe-like tools deliberately outside CI, with the reason.
EXEMPT = {
    'byte_probe.py': 'shared Bend emitter helpers used by other probes',
    'metal_probe.py': 'forced-GPU check; hosted runners have no Metal device',
}
WORKFLOW = ROOT / '.github/workflows/conformance.yml'


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.gates = run_gates.load()

    def test_entries_are_well_formed(self):
        for gate in self.gates:
            with self.subTest(gate=gate['id']):
                self.assertRegex(gate['id'], r'^[a-z0-9][a-z0-9-]*$')
                self.assertTrue(set(gate['os']) and set(gate['os']) <= {'linux', 'macos'})
                self.assertGreater(gate['minutes'], 0)
                script = next(p for p in gate['run'] if p.startswith('tools/'))
                self.assertTrue((ROOT / script).is_file(), script)
                self.assertNotIn('--reference-env', ' '.join(gate['run']))

    def test_every_probe_is_gated_or_explicitly_exempt(self):
        used = {Path(p).name for g in self.gates for p in g['run'] if p.startswith('tools/')}
        probes = {Path(p).name for p in glob.glob(str(ROOT / 'tools/*_probe.py'))}
        self.assertEqual(sorted(probes - used - set(EXEMPT)), [])
        self.assertEqual(sorted(set(EXEMPT) & used), [])

    def test_parity_gates_run_on_both_hosts(self):
        for gate in self.gates:
            if not gate.get('diagnostic'):
                self.assertEqual(sorted(gate['os']), ['linux', 'macos'], gate['id'])

    def test_shards_partition_every_gate(self):
        for count in range(1, 9):
            plan, _ = run_gates.shards(self.gates, count)
            ids = [g['id'] for shard in plan for g in shard]
            self.assertEqual(sorted(ids), sorted(g['id'] for g in self.gates))
            self.assertEqual(plan, run_gates.shards(self.gates, count)[0])


class EvidenceTests(unittest.TestCase):
    def test_records_only_results_the_gate_changed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'toolchain.json').write_text(json.dumps(
                {'bend': {'revision': 'b'}, 'raylib': {'revision': 'r'}, 'bun': {'version': '1'}}))
            for name in ('earlier-probe', 'own-probe'):
                (root / '.build' / name).mkdir(parents=True)
                (root / '.build' / name / 'results.json').write_text('{"passed": true}')
            with mock.patch.object(run_gates, 'ROOT', root), mock.patch.object(run_gates, 'OUT', root / '.build/gates'):
                before = run_gates.results_files()
                (root / '.build/own-probe/results.json').write_text('{"passed": true, "cases": 2}')
                record = run_gates.evidence({'id': 'own'}, before, True, 1.0, 'macos')
        self.assertEqual(list(record['reports']), ['.build/own-probe/results.json'])


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_matrix_runs_every_shard_on_both_hosts(self):
        count = int(re.search(r'run_gates\.py --shard \$\{\{ matrix\.shard \}\}/(\d+)', self.text).group(1))
        shards = re.search(r'shard: \[([^\]]*)\]', self.text).group(1)
        self.assertEqual([int(s) for s in shards.split(',')], list(range(1, count + 1)))
        self.assertIn('os: [ubuntu-24.04, macos-15]', self.text)

    def test_nothing_can_pass_vacuously(self):
        self.assertNotIn('continue-on-error', self.text)
        self.assertNotIn('|| true', self.text)
        self.assertIn('if-no-files-found: error', self.text)
        self.assertIn('fail-fast: false', self.text)
        for job in ('conformanceUbuntu', 'conformanceMac'):
            block = self.text.split(f'  {job}:')[1].split('\n  conformance')[0]
            self.assertIn('needs: [scope, gates, examples]', block)
            self.assertIn('if: ${{ always() }}', block)
            # The scope must have been computed, and each scope has exactly one way to pass.
            self.assertIn('test "$SCOPE_RESULT" = success', block)
            self.assertIn('full) test "$GATES_RESULT" = success ;;', block)
            self.assertIn('examples) test "$EXAMPLES_RESULT" = success ;;', block)
            self.assertIn('none) test "$GATES_RESULT" = skipped && test "$EXAMPLES_RESULT" = skipped ;;', block)
            self.assertIn('*) exit 1 ;;', block)

    def test_the_scope_selects_exactly_one_path(self):
        gates = self.text.split('\n  gates:')[1].split('\n  examples:')[0]
        examples = self.text.split('\n  examples:')[1].split('\n  conformanceUbuntu:')[0]
        self.assertIn("if: ${{ needs.scope.outputs.mode == 'full' }}", gates)
        self.assertIn("if: ${{ needs.scope.outputs.mode == 'examples' }}", examples)
        self.assertIn('os: [ubuntu-24.04, macos-15]', examples)
        self.assertIn('fetch-depth: 0', self.text.split('\n  scope:')[1].split('\n  gates:')[0])

    def test_the_nightly_run_is_not_cancelled_by_pushes(self):
        self.assertIn("group: conformance-${{ github.event_name == 'schedule' && 'nightly' || github.ref }}", self.text)
        self.assertRegex(self.text, r"schedule:\n    - cron: '")

    def test_actions_are_pinned_to_commits(self):
        for path in [WORKFLOW, ROOT / '.github/actions/setup-pinned/action.yml', ROOT / '.github/workflows/checks.yml']:
            for use in re.findall(r'uses: (\S+)', path.read_text()):
                if not use.startswith('./'):
                    self.assertRegex(use, r'@[0-9a-f]{40}$', f'{path.name}: {use}')


if __name__ == '__main__':
    unittest.main()
