import contextlib
from fractions import Fraction
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import binary64_add_sub_probe as probe
import binary64_add_sub_oracle as oracle


class Binary64AddSubTests(unittest.TestCase):
    @staticmethod
    def result(kind, a, b):
        result = oracle.checked(kind, *(field for value in (a, b) for field in (value >> 32, value & 0xffffffff)))
        return None if result is None else (result[0] << 32) | result[1]

    @classmethod
    def setUpClass(cls):
        cls.corpus = probe.samples()
        cls.corpus_expected = [probe.expected_row(row) for row in cls.corpus]

    def setUp(self):
        self.rows = [dict(id=0, kind='add', ah=0, al=0, bh=0, bl=0),
                     dict(id=1, kind='sub', ah=0x7ff00000, al=0, bh=0, bl=0),
                     dict(id=2, kind='sub', ah=0x3ff00000, al=1, bh=0x3ff00000, bl=0)]
        self.expected = [probe.expected_row(row) for row in self.rows]
        self.text = json.dumps([word for row in self.expected for word in row])+'\n'

    def test_fixed_floor_extrema_and_rounding_controls(self):
        for kind, a, b, expected, label in probe.HAND:
            with self.subTest(label=label):
                self.assertEqual(self.result(kind, a, b), expected)
        self.assertEqual(oracle.decode64(0x04700000, 0), oracle.power2(-952))
        self.assertEqual(self.result('add', 0x07b0000000000001, 0x87b0000000000000), 0x0470000000000000)
        self.assertEqual(self.result('sub', 0x07b0000000000000, 0x07b0000000000001), 0x8470000000000000)

    def test_signed_zero_and_nonzero_cancellation(self):
        for kind in oracle.KINDS:
            for sa in (0, 1):
                for sb in (0, 1):
                    effective_sb = sb ^ (kind == 'sub')
                    expected = oracle.SIGN if sa == effective_sb == 1 else 0
                    self.assertEqual(self.result(kind, sa << 63, sb << 63), expected)
            for exponent in (-900, -899, -1, 0, 1, 129, 130):
                for fraction in (0, 1, oracle.FRACTION):
                    for sign in (0, 1):
                        a = probe.normal(exponent, fraction, sign)
                        b = a ^ (oracle.SIGN if kind == 'add' else 0)
                        self.assertEqual(self.result(kind, a, b), 0)
                        for zero in (0, oracle.SIGN):
                            self.assertEqual(self.result(kind, a, zero), a)
                            self.assertEqual(self.result(kind, zero, a), a ^ (oracle.SIGN if kind == 'sub' else 0))

    def test_checked_entrypoints_and_sub_sign_inversion(self):
        for ah, al, bh, bl in ((0, 0, 0x80000000, 0), (0x3ff00000, 1, 0x3ff00000, 0),
                              (0x87b00000, 1, 0x07b00000, 0)):
            self.assertEqual(oracle.checked_add(ah, al, bh, bl), oracle.checked('add', ah, al, bh, bl))
            self.assertEqual(oracle.checked_sub(ah, al, bh, bl), oracle.checked('sub', ah, al, bh, bl))
            self.assertEqual(oracle.checked_sub(ah, al, bh, bl), oracle.checked_add(ah, al, bh ^ 0x80000000, bl))

    def test_each_operand_domain_boundaries_and_zero_shortcuts(self):
        for kind in oracle.KINDS:
            for operand, (minimum, maximum) in enumerate(oracle.BOUNDS):
                for exponent in (minimum, maximum):
                    for sign in (0, 1):
                        for fraction in (0, oracle.FRACTION):
                            values = [0, 0]; values[operand] = probe.normal(exponent, fraction, sign)
                            self.assertIsNotNone(self.result(kind, *values))
                invalid = [probe.normal(e, f, s) for e in (-1022, minimum-1, maximum+1, 1023)
                           for f in (0, 1, oracle.FRACTION) for s in (0, 1)]
                invalid += [x | sign for x in (1, 1<<51, oracle.FRACTION, 0x7ff0000000000000,
                                               0x7ff0000000000001, 0x7ff8000000000000, 0x7fffffffffffffff)
                            for sign in (0, oracle.SIGN)]
                for bad in invalid:
                    for other in (0, oracle.SIGN, probe.normal(0)):
                        values = [other, other]; values[operand] = bad
                        self.assertIsNone(self.result(kind, *values))

    def test_invalid_words_kinds_and_normal_parameters_fail(self):
        for value in (-1, 1<<32, True, False, 0.0, '0', None):
            for field in range(4):
                values = [0]*4; values[field] = value
                with self.assertRaises(ValueError): oracle.checked('add', *values)
                with self.assertRaises(ValueError): oracle.checked('sub', *values)
        for kind in ('mul', 'ADD', '', 0, 1, True, None, []):
            with self.assertRaises(ValueError): oracle.checked(kind, 0, 0, 0, 0)
        for values in ((-1023, 0, 0), (1024, 0, 0), (0, -1, 0), (0, 1<<52, 0),
                       (0, 0, 2), (True, 0, 0), (0, True, 0), (0, 0, True)):
            with self.assertRaises(ValueError): probe.normal(*values)

    def test_general_neighbor_rounder_control_ties_and_subnormals(self):
        for lower in (0, 1, 2, (1<<52)-1, 1<<52, 0x3fefffffffffffff,
                      0x3ff0000000000000, 0x3ff0000000000001, oracle.MAX_FINITE):
            left, right = oracle.positive64(lower), oracle.positive64(lower+1)
            middle = (left+right)/2
            for value, expected in ((left, lower), ((left+middle)/2, lower), (middle, lower+lower%2),
                                    ((middle+right)/2, lower+1), (right, lower+1)):
                for sign in (0, oracle.SIGN):
                    self.assertEqual(oracle.nearest64(-value if sign else value, sign), expected | sign)

    def test_corpus_deterministic_ids_and_exact_counts(self):
        self.assertEqual(self.corpus, probe.samples())
        self.assertEqual([r['id'] for r in self.corpus], list(range(len(self.corpus))))
        self.assertEqual(len(self.corpus), 47464)
        self.assertEqual(sum(row[2] for row in self.corpus_expected), 46648)
        self.assertEqual(sum(row[2] == 0 for row in self.corpus_expected), 816)
        self.assertEqual(probe.Counter(row['kind'] for row in self.corpus), {'add': 23732, 'sub': 23732})

    def test_every_exponent_sign_operand_and_operation(self):
        for kind in oracle.KINDS:
            for operand, (minimum, maximum) in enumerate(oracle.BOUNDS):
                high = probe.FIELDS[operand*2]
                label = f'every-exponent-operand-{operand}'
                for sign in (0, 1):
                    actual = {(r[high] >> 20 & 2047)-1023 for r in self.corpus
                              if label in r['labels'] and r['kind'] == kind and r[high] >> 31 == sign}
                    self.assertEqual(actual, set(range(minimum, maximum+1)))

    def test_corpus_unique_inputs_and_both_orders_and_operations(self):
        keys = [(r['kind'], (r['ah'] << 32) | r['al'], (r['bh'] << 32) | r['bl']) for r in self.corpus]
        self.assertEqual(len(keys), len(set(keys)))
        all_keys = set(keys)
        for kind, a, b in keys:
            self.assertIn((kind, b, a), all_keys)
            self.assertIn(('sub' if kind == 'add' else 'add', a, b), all_keys)

    def test_corpus_exact_lattice_magnitude_and_normal_result_bounds(self):
        floor = oracle.power2(-952)
        for row, result in zip(self.corpus, self.corpus_expected):
            a_bits = (row['ah'] << 32) | row['al']; b_bits = (row['bh'] << 32) | row['bl']
            valid = all(oracle.in_domain(bits, -900, 130) for bits in (a_bits, b_bits))
            self.assertEqual(bool(result[2]), valid)
            if not valid: continue
            a, b = oracle.decode64(row['ah'], row['al']), oracle.decode64(row['bh'], row['bl'])
            exact = a+b if row['kind'] == 'add' else a-b
            self.assertEqual((exact/floor).denominator, 1)
            self.assertLess(abs(exact), oracle.power2(132))
            if exact:
                self.assertGreaterEqual(abs(exact), floor)
                exponent = ((result[3] >> 20) & 2047)-1023
                self.assertLessEqual(exponent, 131); self.assertGreaterEqual(exponent, -952)

    def test_lattice_floor_adjacency_at_every_bit_and_carry_boundary(self):
        rows = [row for row in self.corpus if 'lattice-floor-adjacent-bit-and-carry-boundaries' in row['labels']]
        self.assertTrue(rows)
        fractions = set()
        for row in rows:
            a_bits = (row['ah'] << 32) | row['al']; b_bits = (row['bh'] << 32) | row['bl']
            a_frac, b_frac = a_bits & oracle.FRACTION, b_bits & oracle.FRACTION
            self.assertEqual(abs(a_frac-b_frac), 1)
            self.assertEqual((a_bits >> 52) & 2047, 123)
            self.assertEqual((b_bits >> 52) & 2047, 123)
            fractions.add(min(a_frac, b_frac))
            a, b = oracle.decode64(row['ah'], row['al']), oracle.decode64(row['bh'], row['bl'])
            exact = a+b if row['kind'] == 'add' else a-b
            if (a < 0) != ((b < 0) ^ (row['kind'] == 'sub')):
                self.assertEqual(abs(exact), oracle.power2(-952))
        for bit in range(1, 53):
            self.assertIn((1<<bit)-2, fractions)
            self.assertIn((1<<bit)-1, fractions) if bit < 52 else None
        self.assertIn(oracle.FRACTION-1, fractions)

    def test_all_55_left_normalization_and_32_right_residual_counts(self):
        left_labels = {f'normalization-left-shift-{shift}' for shift in range(1, 56)}
        right_labels = {f'normalization-right-residual-shift-{residue}' for residue in range(32)}
        seen = set()
        for row in self.corpus:
            relevant = set(row['labels']) & (left_labels | right_labels)
            if not relevant: continue
            a, b = oracle.decode64(row['ah'], row['al']), oracle.decode64(row['bh'], row['bl'])
            exact = a+b if row['kind'] == 'add' else a-b
            top = (abs(exact)/oracle.power2(-952)).numerator.bit_length()-1
            for label in relevant:
                seen.add(label)
                count = int(label.rsplit('-', 1)[1])
                if label in left_labels:
                    self.assertEqual(abs(exact), oracle.power2(-897-count))
                    self.assertEqual(55-top, count)
                else:
                    self.assertGreaterEqual(top, 55)
                    self.assertEqual((top-55) % 32, count)
        self.assertEqual(seen, left_labels | right_labels)

    def test_gap_mantissa_tie_cancellation_and_rejection_coverage(self):
        labels = {label for row in self.corpus for label in row['labels']}
        self.assertTrue({f'significand-bit-{bit}' for bit in range(52)} <= labels)
        self.assertTrue({f'exponent-gap-{gap}' for gap in (0, 1, 31, 32, 33, 52, 53, 54, 55, 1030)} <= labels)
        self.assertTrue({'retained-53-bit-rounding-carry', 'nonzero-exact-cancellation',
                         'deep-cancellation-and-neighbors', 'subtraction-lower-binade-midpoint-neighbors',
                         'extrema-long-carry-borrow'} <= labels)
        for operand in (0, 1):
            selected = [row for row in self.corpus if f'reject-invalid-operand-{operand}' in row['labels']]
            self.assertTrue(selected)
            for row in selected: self.assertEqual(probe.expected_row(row)[2:], [0, 0, 0])
            other_high, other_low = probe.FIELDS[(1-operand)*2:(1-operand)*2+2]
            self.assertTrue({0, oracle.SIGN} <= {(r[other_high] << 32) | r[other_low] for r in selected})

    def test_parser_accepts_exact_framing_and_complete_records(self):
        self.assertEqual(probe.parse_output(self.text, self.rows), self.expected)
        probe.compare(self.expected, self.expected)
        rows = [dict(self.rows[index % len(self.rows)], id=index) for index in range(probe.LINE+1)]
        expected = [probe.expected_row(row) for row in rows]
        lines = [json.dumps([v for row in expected[i:i+probe.LINE] for v in row]) for i in range(0, len(rows), probe.LINE)]
        self.assertEqual(probe.parse_output('\n'.join(lines)+'\n', rows), expected)
        with self.assertRaises(ValueError): probe.parse_output(json.dumps([v for row in expected for v in row]), rows)
        self.assertEqual(probe.parse_output('', []), [])

    def test_parser_rejects_malformed_extra_missing_and_wrong_types(self):
        values = json.loads(self.text)
        bad = ['', self.text+'\n', self.text+self.text, 'noise\n'+self.text, '{}', 'null', '[NaN]', '[Infinity]',
               json.dumps(values[:-1]), json.dumps(values+[0])]
        for index in range(len(values)):
            for value in (True, False, None, 1.0, -1, 1<<32, '0', [], {}):
                changed = values.copy(); changed[index] = value; bad.append(json.dumps(changed))
        for text in (None, 1, True, b'[]'):
            with self.assertRaises(ValueError): probe.parse_output(text, self.rows)
            with self.assertRaises(ValueError): probe.parse_native(text, self.rows)
        for text in bad:
            with self.subTest(text=text[:50]), self.assertRaises(ValueError): probe.parse_output(text, self.rows)

    def test_parser_rejects_ids_kinds_tags_and_rejection_payloads(self):
        for index, value in ((0, 1), (5, 0), (10, 1), (1, 1), (6, 0), (11, 2),
                             (2, 2), (7, 2), (12, 2), (8, 1), (9, 1)):
            changed = json.loads(self.text); changed[index] = value
            with self.assertRaises(ValueError): probe.parse_output(json.dumps(changed), self.rows)

    def test_input_rows_reject_shape_duplicate_ids_words_and_kinds(self):
        for row in ({}, None, [], dict(self.rows[0], id=True), dict(self.rows[0], kind='fma'),
                    dict(self.rows[0], kind=0), dict(self.rows[0], extra=0), dict(self.rows[0], ah=True),
                    dict(self.rows[0], labels='label'), dict(self.rows[0], labels=['']),
                    dict(self.rows[0], labels=['a', 'a']), dict(self.rows[0], labels=[1])):
            with self.assertRaises(ValueError): probe.expected_row(row)
        with self.assertRaises(ValueError): probe.validate_rows(tuple(self.rows))
        with self.assertRaises(ValueError): probe.parse_output(self.text, [self.rows[0], self.rows[0], self.rows[2]])

    def test_compare_rejects_incomplete_any_bit_and_untyped_difference(self):
        alternatives = [self.expected[:-1], self.expected+[self.expected[-1]],
                        [[0, 0, 1, 1, 0]]+self.expected[1:],
                        self.expected[:2]+[[2, 1, 1, 0x3ff00000, 0]],
                        [[0, False, 1, 0, 0]]+self.expected[1:],
                        [[0, 0, 1, 0]]+self.expected[1:]]
        for actual in alternatives:
            with self.assertRaises(ValueError): probe.compare(self.expected, actual)

    def native_text(self, metadata=None, records=None):
        if metadata is None:
            metadata = dict(rounding='FE_TONEAREST', initial_rounding=0, selected_rounding=0,
                            control_name='mxcsr', control=8064, ftz=False, daz=False, runtime_add=True,
                            runtime_sub=True, binary64_evaluation=True, preflight_count=probe.PREFLIGHT_COUNT)
        return json.dumps(metadata)+'\n'+'\n'.join(json.dumps(row) for row in (self.expected if records is None else records))+'\n'

    def test_native_valid_metadata_and_records(self):
        metadata, records = probe.parse_native(self.native_text(), self.rows)
        self.assertTrue(metadata['runtime_add']); self.assertTrue(metadata['runtime_sub'])
        self.assertEqual(records, self.expected)
        metadata.update(control_name='fpcr', control=0)
        self.assertEqual(probe.parse_native(self.native_text(metadata), self.rows)[1], self.expected)

    def test_native_rejects_unqualified_environment(self):
        base = json.loads(self.native_text().splitlines()[0])
        changes = (('ftz', True), ('ftz', 0), ('daz', True), ('runtime_add', False), ('runtime_add', 1),
                   ('runtime_sub', False), ('runtime_sub', 1), ('binary64_evaluation', False),
                   ('binary64_evaluation', 1), ('rounding', 'toward-zero'), ('selected_rounding', 1),
                   ('initial_rounding', -1), ('control', True), ('control', 1.0), ('control', 1<<32),
                   ('control', 8064|64), ('control', 8064|32768), ('control', 8064|(1<<13)),
                   ('control_name', 'unknown'), ('preflight_count', probe.PREFLIGHT_COUNT-1))
        for key, value in changes:
            changed = dict(base); changed[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                probe.parse_native(self.native_text(changed), self.rows)
        for value in ([], dict(base, extra=1), {k:v for k,v in base.items() if k != 'ftz'}):
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(value), self.rows)
        for control in ((1<<24), (1<<19), (1<<22), 1, 2, 1<<64):
            changed = dict(base, control_name='fpcr', control=control)
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(changed), self.rows)

    def test_native_rejects_malformed_records_and_duplicate_keys(self):
        valid = self.native_text()
        for text in ('', 'null\n'+'\n'.join(valid.splitlines()[1:]), valid+'[]\n', '\n'+valid,
                     valid.replace('[0, 0, 1, 0, 0]', '[0, 0, true, 0, 0]'),
                     valid.replace('[1, 1, 0, 0, 0]', '[1, 1, 0, 0]'),
                     valid.replace('[2, 1, 1,', '[0, 1, 1,'),
                     valid.replace('"ftz": false', '"ftz": true, "ftz": false')):
            with self.assertRaises(ValueError): probe.parse_native(text, self.rows)
        for record in (None, {}, [0, 0, 1, 0, 0, 0], [0, 0, 1, 0], [0, 0, 1, -1, 0], [0, 0, 1, 0, 1<<32]):
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(records=[record, *self.expected[1:]]), self.rows)

    def test_bounded_program_shape_and_requested_entrypoints(self):
        rows = self.corpus[:probe.CHUNK]
        source = probe.program(rows)
        self.assertEqual(source.count('    IO.print('), (len(rows)+probe.LINE-1)//probe.LINE)
        self.assertIn('A.checked_add(ah, al, bh, bl)', source)
        self.assertIn('A.checked_sub(ah, al, bh, bl)', source)
        self.assertIn('F.Words{high, low}', source)
        for line in source.splitlines():
            if 'IO.print(' in line: self.assertLessEqual(line.count('Add{')+line.count('Sub{'), probe.LINE)
        self.assertEqual(source.count('Add{')+source.count('Sub{'), len(rows)+4)
        for selected in ([], self.corpus[:probe.CHUNK+1]):
            with self.assertRaisesRegex(ValueError, '1..256'): probe.program(selected)

    def test_runtime_controls_independently_qualify_ties_signs_and_subnormals(self):
        self.assertEqual(probe.PREFLIGHT_COUNT, 24)
        subnormal_controls = 0
        for kind, a_bits, b_bits, expected in probe.NATIVE_CONTROLS:
            a, b = [oracle.decode64(bits >> 32, bits & 0xffffffff) for bits in (a_bits, b_bits)]
            exact = a+b if kind == 0 else a-b
            a_sign = a_bits & oracle.SIGN
            b_sign = (b_bits ^ (oracle.SIGN if kind else 0)) & oracle.SIGN
            zero_sign = a_sign if not a and not b and a_sign == b_sign else 0
            self.assertEqual(oracle.nearest64(exact, zero_sign), expected)
            subnormal_controls += any(bits & ~oracle.SIGN and (bits >> 52 & 2047) == 0 for bits in (a_bits, b_bits, expected))
        self.assertGreaterEqual(subnormal_controls, 8)
        for text in ('(* volatile runtime_add)', '(* volatile runtime_sub)', 'volatile double va=a, vb=b',
                     'fesetround(FE_TONEAREST)', 'Runtime add/sub preflight', 'memcpy(&bits,&result,8)',
                     'FLT_EVAL_METHOD == 0'):
            self.assertIn(text, probe.NATIVE)
        self.assertIn('-fno-fast-math', probe.FLAGS); self.assertIn('-frounding-math', probe.FLAGS)

    def test_candidate_compiler_overrides_inherited_cc_and_rejects_fallback(self):
        compiler = {'path':'/recorded/clang', 'version':'Debian clang version 19.1.7'}
        with patch.dict(probe.os.environ, {'CC':'/unrecorded/compiler'}):
            env = probe.candidate_environment(compiler)
            self.assertEqual(env, {'CC':'/recorded/clang'})
            with tempfile.TemporaryDirectory() as directory:
                process = probe.subprocess.CompletedProcess(['command'], 0, '', '')
                with patch.object(probe.subprocess, 'run', return_value=process) as run:
                    probe.execute(['command'], Path(directory), 'compile', env=env)
                self.assertEqual(run.call_args.kwargs['env']['CC'], '/recorded/clang')
        for version in ('gcc 15.0', 'clang version 13.0', 'unknown', 'not a compiler'):
            with self.assertRaises(ValueError): probe.candidate_environment(dict(compiler, version=version))
        self.assertEqual(probe.candidate_environment(dict(compiler, version='Apple clang version 17.0'))['CC'], compiler['path'])

    def test_native_only_never_claims_candidate_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            compiler = {'path':'/compiler', 'version':'clang version 19.1.7', 'sha256':'compiler'}
            native = {'passed':True, 'observations':len(self.rows), 'compiler':compiler, 'artifacts':{}}
            bun = {'path':'/bun', 'version':'1.3.12', 'sha256':'bun'}
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout'), patch.object(probe, 'source_gate', return_value={}), patch.object(probe, 'digest', return_value='hash'), patch.object(probe, 'compiler_identity', return_value=bun), patch.object(probe, 'samples', return_value=[dict(row, labels=[]) for row in self.rows]), patch.object(probe, 'native_reference', return_value=native), patch.object(probe, 'final_source_gate') as gate, patch.object(sys, 'argv', ['probe', '--bend-source', directory, '--native-only']), contextlib.redirect_stdout(io.StringIO()):
                probe.main()
            report = json.loads((Path(directory)/'binary64-add-sub-probe/results.json').read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})
            self.assertEqual(report['phase'], 'native-only-complete'); self.assertTrue(report['native']['passed'])
            self.assertEqual(report['accepted'], 2); self.assertEqual(report['rejected'], 1)
            gate.assert_called_once()

    def test_native_comparison_failure_prevents_candidate_work(self):
        with tempfile.TemporaryDirectory() as directory:
            bun = {'path':'/bun', 'version':'1.3.12', 'sha256':'bun'}
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout'), patch.object(probe, 'source_gate', return_value={}), patch.object(probe, 'digest', return_value='hash'), patch.object(probe, 'compiler_identity', return_value=bun), patch.object(probe, 'samples', return_value=[dict(row, labels=[]) for row in self.rows]), patch.object(probe, 'native_reference', side_effect=ValueError('native mismatch')), patch.object(probe, 'compile_fresh') as compile_fresh, patch.object(sys, 'argv', ['probe', '--bend-source', directory]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'native mismatch'): probe.main()
            compile_fresh.assert_not_called()
            report = json.loads((Path(directory)/'binary64-add-sub-probe/results.json').read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})

    def test_source_dependencies_include_entire_harness_and_shared_oracle(self):
        self.assertTrue({'src/binary64_add_sub.bend', 'src/binary64_fma.bend', 'tools/binary64_add_sub_probe.py',
                         'tools/binary64_add_sub_oracle.py', 'tools/binary64_fma_oracle.py',
                         'tests/test_binary64_add_sub.py', 'tools/conformance.py', 'toolchain.json',
                         'LAWS.bend', 'PROOF.bend'} <= set(probe.DEPENDENCIES))

    def test_source_drift_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'x').write_text('before')
            hashes = {'x':probe.digest(root/'x')}
            with patch.object(probe, 'ROOT', root):
                probe.assert_unchanged(hashes)
                (root/'x').write_text('after')
                with self.assertRaisesRegex(ValueError, 'drift'): probe.assert_unchanged(hashes)

    def test_artifact_hashes_pin_consumed_inputs_programs_and_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory); names = ['inputs.json', 'candidate.bend', 'cpu-1.stdout']
            for name in names: (work/name).write_text(name)
            report = {}
            probe.retain_artifacts(report, work, names)
            self.assertEqual(set(report['artifacts']), set(names))
            probe.assert_artifacts_unchanged(report, work)
            (work/'cpu-1.stdout').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'artifact drift'): probe.assert_artifacts_unchanged(report, work)
            with self.assertRaisesRegex(ValueError, 'artifact drift'): probe.retain_artifacts(report, work, names)
            self.assertNotEqual(report['artifacts']['cpu-1.stdout'], probe.digest(work/'cpu-1.stdout'))

    def test_successful_compile_cannot_reuse_stale_or_partial_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory); binary = work/'candidate'; js = work/'candidate.js'
            binary.write_text('old binary'); js.write_text('old js')
            with patch.object(probe, 'execute', return_value=''):
                with self.assertRaisesRegex(ValueError, 'fresh nonempty'): probe.compile_fresh(['compiler'], [binary, js], work, 'compile')
            self.assertFalse(binary.exists()); self.assertFalse(js.exists())
            def partial(*args, **kwargs): binary.write_text('new binary')
            with patch.object(probe, 'execute', side_effect=partial):
                with self.assertRaisesRegex(ValueError, 'fresh nonempty'): probe.compile_fresh(['compiler'], [binary, js], work, 'compile')

    def test_execute_retains_failure_and_timeout_output(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            with self.assertRaisesRegex(ValueError, 'exited 4'):
                probe.execute([sys.executable, '-c', 'import sys; print("out"); print("err",file=sys.stderr); sys.exit(4)'], work, 'failure')
            self.assertEqual((work/'failure.stdout').read_text(), 'out\n')
            self.assertEqual((work/'failure.stderr').read_text(), 'err\n')
            error = probe.subprocess.TimeoutExpired('command', 1, output=b'partial-out', stderr=b'partial-err')
            with patch.object(probe.subprocess, 'run', side_effect=error), self.assertRaises(probe.subprocess.TimeoutExpired):
                probe.execute(['command'], work, 'timeout')
            self.assertEqual((work/'timeout.stdout').read_text(), 'partial-out')
            self.assertEqual((work/'timeout.stderr').read_text(), 'partial-err')

    def test_execute_cannot_leave_stale_logs_on_launch_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for suffix in ('stdout', 'stderr'): (work/('run.'+suffix)).write_text('old-success')
            with patch.object(probe.subprocess, 'run', side_effect=FileNotFoundError('missing')), self.assertRaises(FileNotFoundError):
                probe.execute(['missing'], work, 'run')
            for suffix in ('stdout', 'stderr'): self.assertFalse((work/('run.'+suffix)).exists())

    def test_final_toolchain_and_compiler_drift_fail_closed(self):
        lock = {'bend':{'revision':'pinned', 'patch':{'sha256':'overlay'}}}
        with patch.object(probe, 'assert_unchanged'), patch.object(probe, 'checkout', side_effect=ValueError('overlay drift')) as check:
            with self.assertRaisesRegex(ValueError, 'overlay drift'): probe.final_source_gate({}, Path('/compiler'), lock)
        check.assert_called_once_with(Path('/compiler'), 'pinned', {'sha256':'overlay'})
        with patch.object(probe, 'assert_unchanged'), patch.object(probe, 'checkout'), patch.object(probe, 'compiler_identity', return_value={'sha256':'new'}):
            with self.assertRaisesRegex(ValueError, 'executable drift'):
                probe.final_source_gate({}, Path('/compiler'), lock, {'clang':('clang', {'sha256':'old'})}, Path('/work'))

    def test_stale_success_invalidated_before_dependency_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)/'binary64-add-sub-probe'; work.mkdir()
            result = work/'results.json'; result.write_text('{"passed":true}')
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout', side_effect=ValueError('pin failure')), patch.object(sys, 'argv', ['probe', '--bend-source', directory]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'pin failure'): probe.main()
            report = json.loads(result.read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})
            self.assertEqual(report['error'], 'pin failure')


if __name__ == '__main__':
    unittest.main()
