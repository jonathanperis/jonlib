"""Independent, compiler-free qualification regression tests."""
import copy
import itertools
import json
from pathlib import Path
import runpy
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools import conformance
from tools import extrema_reference as extrema


def word(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def independent_rows(cases, contract='accurate'):
    """Emulate declared contracts without using production tables/predictions."""
    def extreme(function, a, b):
        if a == 0.0 and b == 0.0:
            if contract == 'gnu':
                return a
            if contract == 'second':
                return b
            negative_a, negative_b = bool(word(a) >> 31), bool(word(b) >> 31)
            negative = (negative_a or negative_b) if function == 'min' else (negative_a and negative_b)
            return -0.0 if negative else 0.0
        return min(a, b) if function == 'min' else max(a, b)

    rows = []
    for case in cases:
        size, op = case['width'], case['operations'][0]
        pixels = []
        for lane in range(size):
            values = op['args'][lane::size]
            if op['function'] == 'clamp':
                value, lower, upper = values
                result = extreme('min', upper, extreme('max', lower, value))
            else:
                result = extreme(op['function'], *values)
            pixels.append(word(result))
        rows.append(dict(id=case['id'], width=size, height=1, pixels=pixels))
    return rows


class ExtremaReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.raylib, self.build = self.root / 'raylib', self.root / 'build'
        (self.raylib / 'src').mkdir(parents=True)
        for header in ('raymath.h', 'raylib.h'):
            (self.raylib / 'src' / header).write_text('test header ' + header + '\n')
        self.library = self.root / 'libraylib.a'
        self.library.write_bytes(b'test archive')
        self.output = self.build / 'extrema-reference'
        self.output.mkdir(parents=True)
        self.path = self.output / 'results.json'
        self.path.write_text(json.dumps(dict(qualified=True, selected_profile='StaleProfile', old_field=True)))
        (self.output / 'reference').write_text('stale executable')
        self.cases = extrema.control_document()['cases']
        self.rows = independent_rows(self.cases)
        self.calls, self.snapshots = [], []
        self.fail = None
        self.identity = 'test clang version 19.1.7\nTarget: test-target\n'
        self.raw = None

    def fake_run(self, command):
        self.calls.append(command[:])
        snapshot = json.loads(self.path.read_text())
        self.snapshots.append(snapshot)
        if '--version' in command:
            phase, value = 'compiler-identity', self.identity
        elif '-o' in command:
            phase, value = 'compile', ''
            self.assertFalse((self.output / 'reference').exists(), 'A stale native binary survived')
        else:
            phase = 'native-run'
            value = self.raw if self.raw is not None else '\n'.join(map(json.dumps, self.rows)) + '\n'
        if self.fail == phase:
            raise RuntimeError('synthetic ' + phase + ' failure')
        if isinstance(self.fail, subprocess.TimeoutExpired) and phase == 'compile':
            raise self.fail
        return value

    def qualify(self, **callbacks):
        with patch('tools.extrema_reference.shutil.which', return_value='/mock/bin/clang'), \
                patch('subprocess.run', side_effect=AssertionError('Unexpected native execution')):
            return extrema.qualify(self.raylib, self.library, self.build,
                                   c_source=callbacks.get('c_source', conformance.c_source),
                                   cases_from=callbacks.get('cases_from', conformance.cases_from),
                                   parse_output=callbacks.get('parse_output', conformance.parse_output),
                                   run=self.fake_run)

    def report(self):
        return json.loads(self.path.read_text())

    def assert_failed(self):
        report = self.report()
        self.assertFalse(report['qualified'])
        self.assertIsNone(report['selected_profile'])
        self.assertFalse(report['parity_established'])
        self.assertTrue(report['error'])
        self.assertNotIn('old_field', report)
        return report

    def test_accepts_accurate_and_gnu_with_full_observations(self):
        for contract, profile in [('accurate', 'AccurateGradient'), ('gnu', 'GnuGradient')]:
            with self.subTest(contract=contract):
                self.rows = independent_rows(self.cases, contract)
                report = self.qualify()
                self.assertTrue(report['qualified'])
                self.assertEqual(report['selected_profile'], profile)
                self.assertEqual(report['matching_profiles'], [profile])
                self.assertEqual(report['native_observations'], self.rows)
                self.assertEqual(report['control_cases'], 832)
                self.assertEqual(report['control_components'], 2368)
                self.assertEqual(report['comparisons'][profile]['mismatch_count'], 0)
                self.assertFalse(report['parity_established'])
                self.assertTrue(report['numeric_reference_only'])
                self.assertEqual(report, self.report())

    def test_control_domain_permutations_and_every_lane_are_complete(self):
        bit_domain = (0xbf800000, 0x80000000, 0, 0x3f800000)
        for size in (2, 3, 4):
            functions = ('min', 'max', 'clamp') if size < 4 else ('min', 'max')
            for function in functions:
                arity = 3 if function == 'clamp' else 2
                cases = [case for case in self.cases
                         if case['width'] == size and case['operations'][0]['function'] == function]
                all_inputs = set(itertools.product(bit_domain, repeat=arity))
                self.assertEqual(len(cases), (4 ** arity) * (size + 1))
                uniform = [case for case in cases if case['id'].endswith('-uniform')]
                self.assertEqual(len(uniform), 4 ** arity)
                for lane in range(size):
                    self.assertEqual({tuple(map(word, case['operations'][0]['args'][lane::size]))
                                      for case in uniform}, all_inputs)
                    mixed = [case for case in cases if case['id'].endswith(f'-lane-{lane}')]
                    self.assertEqual(len(mixed), 4 ** arity)
                    self.assertEqual({tuple(map(word, case['operations'][0]['args'][lane::size]))
                                      for case in mixed}, all_inputs)
                    for case in mixed:
                        args = case['operations'][0]['args']
                        for other in range(size):
                            if other != lane:
                                self.assertTrue(all(abs(value) >= 2 for value in args[other::size]))
                # Every vector cell is filled once, in canonical image context.
                for case in cases:
                    self.assertEqual(case['height'], 1)
                    self.assertEqual(len(case['operations']), 1)
                    self.assertEqual((case['operations'][0]['x'], case['operations'][0]['y']), (0, 0))
        self.assertEqual(len({case['id'] for case in self.cases}), 832)
        self.assertEqual(conformance.cases_from(extrema.control_document()), self.cases)

    def test_predefined_tables_match_independent_contracts_including_clamp_order(self):
        for contract, profile in [('accurate', 'AccurateGradient'), ('gnu', 'GnuGradient')]:
            self.assertEqual(extrema._expected_rows(self.cases, profile), independent_rows(self.cases, contract))
        # All signed-zero ordered triples are independently represented. Swapping
        # either clamp operand order changes this GNU result.
        gnu = {row['id']: row for row in independent_rows(self.cases, 'gnu')}
        self.assertEqual(gnu['extrema-v2-clamp-121-uniform']['pixels'], [0x80000000] * 2)
        self.assertEqual(gnu['extrema-v2-clamp-212-uniform']['pixels'], [0] * 2)

    def test_native_second_operand_contract_is_rejected(self):
        self.rows = independent_rows(self.cases, 'second')
        with self.assertRaisesRegex(ValueError, 'unsupported or mixed'):
            self.qualify()
        report = self.assert_failed()
        self.assertEqual(report['native_observations'], self.rows)
        self.assertEqual(report['matching_profiles'], [])

    def test_mixed_profiles_across_operations_contexts_and_components_are_rejected(self):
        accurate, gnu = independent_rows(self.cases), independent_rows(self.cases, 'gnu')
        for split in ('operation', 'context', 'component', 'dimension'):
            self.rows = copy.deepcopy(accurate)
            for index, (case, gnu_row) in enumerate(zip(self.cases, gnu)):
                if split == 'operation' and case['operations'][0]['function'] == 'max':
                    self.rows[index] = gnu_row
                elif split == 'context' and case['id'].endswith('-uniform'):
                    self.rows[index] = gnu_row
                elif split == 'component':
                    self.rows[index]['pixels'][0] = gnu_row['pixels'][0]
                elif split == 'dimension' and case['width'] == 3:
                    self.rows[index] = gnu_row
            with self.subTest(split=split), self.assertRaisesRegex(ValueError, 'unsupported or mixed'):
                self.qualify()
            self.assert_failed()

    def test_finite_wrong_result_rejected_even_with_supported_zero_ties(self):
        self.rows[0]['pixels'][0] = 0x3f800000
        with self.assertRaisesRegex(ValueError, 'unsupported or mixed'):
            self.qualify()
        self.assert_failed()

    def test_ambiguous_signatures_are_rejected(self):
        same_tables = {profile: extrema.TABLES['AccurateGradient'] for profile in extrema.PROFILES}
        with patch.object(extrema, 'TABLES', same_tables), self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.qualify()
        self.assertEqual(self.assert_failed()['matching_profiles'], list(extrema.PROFILES))

    def test_canonical_source_and_compilation_are_unchanged(self):
        report = self.qualify()
        self.assertEqual((self.output / 'reference.c').read_text(), conformance.c_source(self.cases))
        source = (self.output / 'reference.c').read_text()
        self.assertIn('#define RAYMATH_STATIC_INLINE', source)
        self.assertIn('(Vector2){-0.0f, -0.0f}', source)
        self.assertIn('ImageDrawPixel(&image', source)
        expected = ['clang', '-std=c11', '-O2', '-fno-builtin-atan2f',
                    '-I' + str(self.raylib / 'src'), str(self.output / 'reference.c'),
                    str(self.library), '-lm', '-o', str(self.output / 'reference')]
        self.assertEqual(self.calls, [['clang', '--version'], expected, [str(self.output / 'reference')]])
        self.assertEqual(report['compile_command'], expected)
        self.assertEqual(report['compiler']['identity'], self.identity.strip())
        self.assertEqual(report['compiler']['path'], '/mock/bin/clang')

    def test_hashes_cover_tools_headers_controls_library_and_generated_source(self):
        report = self.qualify()
        self.assertEqual(report['controls_sha256'], extrema._hash(self.output / 'controls.json'))
        self.assertEqual(report['generated_source_sha256'], extrema._hash(self.output / 'reference.c'))
        self.assertEqual(report['raylib']['library_sha256'], extrema._hash(self.library))
        self.assertEqual(set(report['raylib']['headers_sha256']), {'raymath.h', 'raylib.h'})
        self.assertEqual(set(report['source_sha256']), {str(Path(extrema.__file__).resolve()),
                                                     str(Path(conformance.__file__).resolve())})
        self.assertTrue(all(len(value) == 64 for value in report['source_sha256'].values()))
        controls = json.loads((self.output / 'controls.json').read_text())
        self.assertEqual(controls['bits'], ['bf800000', '80000000', '00000000', '3f800000'])
        self.assertEqual(controls['clamp_order'], 'min(upper,max(lower,value))')
        self.assertEqual(controls['document']['cases'], self.cases)

    def test_stale_success_is_invalidated_before_every_command_and_never_reused(self):
        first = self.qualify()
        self.assertTrue(all(not state['qualified'] for state in self.snapshots))
        self.assertTrue(all(state['selected_profile'] is None for state in self.snapshots))
        self.assertTrue(all('old_field' not in state for state in self.snapshots))
        self.fail = 'compile'
        with self.assertRaisesRegex(RuntimeError, 'synthetic compile failure'):
            self.qualify()
        second = self.assert_failed()
        self.assertNotEqual(first['run_id'], second['run_id'])
        self.assertEqual(second['native_observations'], [])
        self.assertEqual(len(second['commands']), 2)

    def test_setup_and_command_errors_are_persisted(self):
        for stage in ('compiler-identity', 'compile', 'native-run'):
            self.fail = stage
            with self.subTest(stage=stage), self.assertRaisesRegex(RuntimeError, 'synthetic'):
                self.qualify()
            report = self.assert_failed()
            self.assertEqual(report['phase'], stage)
            self.assertFalse(report['commands'][-1]['completed'])
        self.fail = None
        (self.raylib / 'src' / 'raymath.h').unlink()
        self.calls = []
        with self.assertRaises(FileNotFoundError):
            self.qualify()
        self.assertEqual(self.calls, [])
        report = self.assert_failed()
        self.assertEqual(report['phase'], 'setup')
        self.assertEqual(report['controls_sha256'], extrema._hash(self.output / 'controls.json'))
        self.assertEqual(report['generated_source_sha256'], extrema._hash(self.output / 'reference.c'))

    def test_timeout_diagnostics_are_preserved(self):
        self.fail = subprocess.TimeoutExpired(['clang'], 240, output=b'partial output', stderr=b'partial error')
        with self.assertRaises(subprocess.TimeoutExpired):
            self.qualify()
        report = self.assert_failed()
        log = (self.output / 'compile.log').read_text()
        self.assertIn('partial output', log)
        self.assertIn('partial error', log)
        self.assertEqual(report['error']['type'], 'TimeoutExpired')

    def test_empty_or_missing_compiler_identity_fails_closed(self):
        self.identity = ' \n'
        with self.assertRaisesRegex(ValueError, 'Empty canonical compiler identity'):
            self.qualify()
        self.assert_failed()
        with patch.object(extrema.shutil, 'which', return_value=None), self.assertRaisesRegex(ValueError, 'not found'):
            extrema.qualify(self.raylib, self.library, self.build, c_source=conformance.c_source,
                            cases_from=conformance.cases_from, parse_output=conformance.parse_output, run=self.fake_run)
        self.assert_failed()

    def test_missing_duplicate_extra_reordered_and_renamed_rows_fail_closed(self):
        original = independent_rows(self.cases)
        variants = [original[:-1], original + [original[-1]],
                    [original[1], *original[1:]], [original[1], original[0], *original[2:]],
                    [dict(original[0], id='unknown-observation'), *original[1:]]]
        for rows in variants:
            self.rows = rows
            with self.subTest(first=rows[0]['id'], count=len(rows)), self.assertRaises(ValueError):
                self.qualify()
            self.assert_failed()

    def test_missing_extra_and_invalid_components_fail_closed(self):
        original = independent_rows(self.cases)
        for size in (2, 3, 4):
            at = next(index for index, row in enumerate(original) if row['width'] == size)
            pixels = original[at]['pixels']
            for changed in (pixels[:-1], pixels + [0], [True] + pixels[1:], [-1] + pixels[1:],
                            [2**32] + pixels[1:], [0.0] + pixels[1:], ['0'] + pixels[1:]):
                self.rows = copy.deepcopy(original)
                self.rows[at]['pixels'] = changed
                with self.subTest(size=size, changed=changed), self.assertRaises(ValueError):
                    self.qualify()
                self.assert_failed()

    def test_malformed_json_fields_dimensions_and_non_array_components_fail_closed(self):
        original = independent_rows(self.cases)
        for first in (dict(original[0], extra=0), dict(original[0], width=True),
                      dict(original[0], height=2), dict(original[0], pixels={}), [], None):
            self.raw = '\n'.join(map(json.dumps, [first, *original[1:]]))
            with self.subTest(first=first), self.assertRaises(ValueError):
                self.qualify()
            self.assert_failed()
        for raw in ('not json\n', '{"id":"one","id":"two"}\n', ''):
            self.raw = raw
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.qualify()
            self.assert_failed()
            self.assertEqual((self.output / 'observations.jsonl').read_text(), raw)

    def test_controls_are_fresh_and_validator_cannot_replace_them(self):
        original = extrema.control_document()
        first = extrema.control_document()
        first['cases'].clear()
        self.assertEqual(extrema.control_document(), original)

        def changed_validator(document):
            return document['cases'][:-1]

        with self.assertRaisesRegex(ValueError, 'changed the fixed extrema controls'):
            self.qualify(cases_from=changed_validator)
        self.assert_failed()
        self.assertEqual(self.calls, [])

    def test_parser_cannot_replace_observations(self):
        def changed_parser(output, cases):
            return independent_rows(cases, 'gnu')

        with self.assertRaisesRegex(ValueError, 'parser changed the output'):
            self.qualify(parse_output=changed_parser)
        self.assert_failed()

    def test_package_and_script_imports_require_no_conformance_import(self):
        namespace = runpy.run_path(str(Path(extrema.__file__)))
        self.assertEqual(namespace['control_document'](), extrema.control_document())
        self.assertEqual(namespace['PROFILES'], ('AccurateGradient', 'GnuGradient'))
        self.assertNotIn('conformance', namespace)


if __name__ == '__main__':
    unittest.main()
