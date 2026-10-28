"""Behavior and ownership gates are derived from probes, not from a hand edit."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import enums_probe
import macros_probe
from tools import api_plan, gate_evidence


def _facts(path, text):
    """file_facts reads the repository. These tests hand it the text instead."""
    coded = gate_evidence.code_text(path, text)
    return dict(strings={match.group(2) for match in gate_evidence.STRING_NAME.finditer(coded)},
                dotted=gate_evidence.dotted_suffixes(coded),
                ownership=gate_evidence.ownership_symbols(coded),
                owner_calls=gate_evidence.owner_calls(coded))


class DerivationTests(unittest.TestCase):
    def index(self, files, catalogs=None):
        script = 'tools/fake_probe.py'
        witnesses = [dict(id='fake', script=script, files=[script], catalog=None)]
        return gate_evidence.EvidenceIndex(
            witnesses, {script: _facts(script, files[script])},
            catalogs or dict(enumerator=set(), macro=set()), set(), 'abc')

    def entry(self, **changes):
        record = dict(status='partial', jonlib='Surface.copy', scope='Returns an independent clone of the owner.',
                      gaps=['Targets: desktop', 'Performance: not measured'],
                      evidence=['tools/fake_probe.py'],
                      gates=dict(availability='partial', targets='partial'))
        record.update(changes)
        return record

    def test_behavior_verified_requires_a_named_exact_probe_and_no_open_gap(self):
        program = 'def main():\n  J.Surface.copy(image)\n'
        index = self.index({ 'tools/fake_probe.py': program })
        gates = gate_evidence.derive(index, 'raylib:function:ImageCopy', self.entry())
        self.assertEqual(gates['behavior'], 'verified')
        self.assertEqual(gates['ownership'], 'partial')  # mapping, but no ownership def
        blocked = self.entry(gaps=['Libm: host atan2f', 'Targets: desktop'])
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:ImageCopy', blocked)['behavior'], 'partial')
        linux_only = self.entry(gaps=['Targets: CPU-1, CPU-2 and JavaScript lanes on Linux; macOS is not verified'])
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:ImageCopy', linux_only)['behavior'], 'partial')
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:ImageCopy', self.entry(evidence=['docs/API.md']))['behavior'], 'unverified')

    def test_a_cleanup_call_is_not_coverage(self):
        program = 'void done(void) { CloseWindow(); }\n'
        index = self.index({'tools/fake_probe.py': program})
        record = self.entry(jonlib='Frame.close_window', evidence=['tools/fake_probe.py'])
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:CloseWindow', record)['behavior'], 'partial')
        named = program + "cases = ['CloseWindow']\n"
        index = self.index({'tools/fake_probe.py': named})
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:CloseWindow', record)['behavior'], 'verified')

    def test_ownership_verified_needs_the_mapping_and_a_test_the_probe_runs(self):
        program = 'def copied(image):\n  J.Surface.copy(image)\ndef owned(image):\n  copied(image)\n'
        index = self.index({'tools/fake_probe.py': program})
        record = self.entry()
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:ImageCopy', record)['ownership'], 'verified')
        unstated = self.entry(scope='Exact stored samples for every format.')
        self.assertEqual(gate_evidence.derive(index, 'raylib:function:ImageCopy', unstated)['ownership'], 'partial')
        behavior, ownership = gate_evidence.blockers(index, 'raylib:function:ImageCopy', unstated)
        self.assertEqual(behavior, [])
        self.assertEqual(ownership, ['scope/adaptations do not state the owner mapping'])

    def test_integration_and_performance_are_tracked_and_not_verified(self):
        program = 'J.Surface.copy(image)\n'
        index = self.index({'tools/fake_probe.py': program})
        record = self.entry(evidence=['tools/fake_probe.py', 'examples/core.bend', 'docs/PERFORMANCE.md'])
        gates = gate_evidence.derive(index, 'raylib:function:ImageCopy', record)
        self.assertEqual((gates['integration'], gates['performance']), ('partial', 'partial'))
        self.assertNotEqual(gates['integration'], 'verified')
        self.assertNotEqual(gates['performance'], 'verified')
        bare = gate_evidence.derive(index, 'raylib:function:ImageCopy', self.entry())
        self.assertEqual((bare['integration'], bare['performance']), ('unverified', 'partial'))

    def test_a_verified_availability_claim_is_rejected(self):
        program = 'J.Surface.copy(image)\n'
        index = self.index({'tools/fake_probe.py': program})
        record = self.entry(gates=dict(availability='verified', targets='verified'))
        gates = gate_evidence.derive(index, 'raylib:function:ImageCopy', record)
        self.assertEqual(gates['availability'], 'unverified')
        self.assertEqual(gates['targets'], 'unverified')

    def test_catalog_selectors_match_the_enum_and_macro_probes(self):
        keys = gate_evidence.catalog_keys()
        reference = json.loads((api_plan.ROOT / 'api/reference.json').read_text())['entries']
        enums = {(header, name) for header, _enum, name in enums_probe.enumerators()}
        macros = {(header, name) for header, name, _kind, _bend in macros_probe.macros()}
        macros.update((header, name) for (header, name, _kind, _bend), _other in macros_probe.shared_options())
        self.assertEqual(keys['enumerator'], enums)
        self.assertEqual(keys['macro'], macros)
        bools = {(row['header'], row['name']) for row in reference if row['kind'] == 'enumerator' and row.get('enum') == 'bool'}
        self.assertTrue(bools)
        self.assertFalse(bools & keys['enumerator'])

    def test_phase1_functions_with_proved_behavior_have_ownership_too(self):
        progress = json.loads((api_plan.ROOT / 'api/progress.json').read_text())
        reference = {row['id']: row for row in api_plan.read('reference.json')['entries']}
        phases = {item['id']: item['phase'] for item in api_plan.read('milestones.json')['milestones']}
        rows = gate_evidence.assessments(gate_evidence.EvidenceIndex.load(), progress)
        proved = [row['id'] for row in rows
                  if reference[row['id']]['kind'] == 'function'
                  and phases[api_plan.classify(reference[row['id']])] == 1
                  and row['gates']['behavior'] == 'verified' and row['gates']['ownership'] == 'verified']
        self.assertGreaterEqual(len(proved), 11)
        for api_id in ('raylib:function:ImageDrawTextPro', 'raylib:function:SetTraceLogLevel',
                       'raylib:function:FileTextReplace', 'raylib:function:UnloadDroppedFiles',
                       'raylib:function:ImageDrawCircleGradient', 'raylib:function:GetMeshBoundingBox'):
            self.assertIn(api_id, proved)

    def test_metal_witness_is_the_current_bend_pin(self):
        self.assertFalse(gate_evidence.metal_proven(dict(id='raylib:function:ImageCopy', evidence=['docs/API.md'])))
        self.assertTrue(gate_evidence.metal_proven(dict(metal_witness=True)))
        self.assertFalse(gate_evidence.metal_proven(dict(metal_witness=False)))


if __name__ == '__main__':
    unittest.main()
