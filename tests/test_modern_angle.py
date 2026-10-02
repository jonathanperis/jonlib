import contextlib
import copy
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import angle_probe
import modern_angle_probe as probe
import modern_angle_reference as reference


class ModernAngleTests(unittest.TestCase):
    def setUp(self):
        self.rows = [dict(id=0, y=0, x=0x3f800000, labels=['zero']),
                     dict(id=1, y=0x7f800000, x=0x3f800000, labels=['rejected']),
                     dict(id=2, y=0x3f800000, x=0x3f800000, labels=['synthetic'])]
        # These are framing fixtures, not atan2 numerical expectations.
        self.records = [self.record(self.rows[0], 0, [0, 0], mask=2048),
                        self.record(self.rows[1], None, None, accepted=False, mask=4096),
                        self.record(self.rows[2], 0x3f800000, [0x3ff00000, 0], events=[[1, 0, 0], [11, 0x3ff00000, 0]])]
        self.expected = probe.expected_records(self.rows, self.records)
        self.text = self.lines(self.expected)

    @staticmethod
    def record(row, result, final, accepted=True, mask=1, events=None):
        return dict(id=row['id'], y=row['y'], x=row['x'], accepted=accepted, pinned=result,
                    original=result, native=result, sun=result, mask=mask, index=0, gt=0,
                    final=final, events=[] if events is None else events)

    @staticmethod
    def lines(records):
        return ''.join(json.dumps(record)+'\n' for record in records)

    def test_original_1086_corpus_is_preserved_in_exact_order(self):
        corpus = reference.samples()
        probe.validate_rows(corpus)
        self.assertEqual(corpus, reference.samples())
        self.assertEqual([row['id'] for row in corpus], list(range(len(corpus))))
        prior = angle_probe.samples()
        self.assertEqual(len(prior), 1086)
        words = lambda number: struct.unpack('<I', struct.pack('<f', number))[0]
        self.assertEqual([(row['y'], row['x']) for row in corpus[:1086]],
                         [(words(y), words(x)) for y, x in prior])
        self.assertGreater(len(corpus), 1086)
        self.assertTrue(all(row['labels'] for row in corpus))
        self.assertTrue(any((row['y'] >> 23 & 255) == 255 or (row['x'] >> 23 & 255) == 255 for row in corpus))

    def test_input_validation_rejects_duplicates_extras_missing_and_types(self):
        bad = [None, (), [], [self.rows[0], self.rows[0]],
               [dict(self.rows[0], extra=0)], [{key: value for key, value in self.rows[0].items() if key != 'x'}]]
        for field in ('id', 'y', 'x'):
            for value in (True, False, None, -1, 1 << 32, 0.0, '0', [], {}):
                bad.append([dict(self.rows[0], **{field: value})])
        for labels in ('zero', [''], [1], ['a', 'a'], None):
            bad.append([dict(self.rows[0], labels=labels)])
        for rows in bad:
            with self.subTest(rows=rows), self.assertRaises(ValueError): probe.validate_rows(rows)
        probe.validate_rows([{key: value for key, value in self.rows[0].items() if key != 'labels'}])

    def test_json_duplicate_keys_constants_and_types_rejected(self):
        for text in ('{"a":1,"a":2}', '[NaN]', '[Infinity]', '[-Infinity]', 'junk', None, 0):
            with self.assertRaises((ValueError, TypeError)): probe.strict_json(text)

    def test_parser_accepts_explicit_success_failure_and_traces(self):
        self.assertEqual(probe.parse_output(self.text, self.rows), self.expected)
        probe.compare(self.expected, self.expected)
        self.assertEqual(self.expected[1], [1, 4096, 0, 0, 0, 0, 0, 1, 2, 0x7f800000, 0x3f800000, 0])

    def test_parser_rejects_extra_missing_reordered_noise_and_coalesced_lines(self):
        for text in ('', '\n'+self.text, self.text+'\n', self.text+self.text,
                     'noise\n'+self.text, self.lines(self.expected[:-1]),
                     self.lines(self.expected[::-1]), json.dumps(self.expected),
                     json.dumps([word for row in self.expected for word in row]),
                     self.text.replace('[0,', '[2,', 1)):
            with self.subTest(text=text[:60]), self.assertRaises(ValueError): probe.parse_output(text, self.rows)

    def test_parser_rejects_every_nonword_field(self):
        for row_index, row in enumerate(self.expected):
            for column in range(len(row)):
                for value in (True, False, None, -1, 1 << 32, 1.0, '0', [], {}):
                    changed = copy.deepcopy(self.expected); changed[row_index][column] = value
                    with self.subTest(row=row_index, column=column, value=value), self.assertRaises(ValueError):
                        probe.parse_output(self.lines(changed), self.rows)

    def test_parser_rejects_bad_branch_checked_and_success_fields(self):
        for column, value in ((1, 8192), (2, 8), (3, 2), (4, 2), (4, 0), (5, 0x7f800000),
                              (6, 2), (7, 0x7ff00000), (9, probe.MAX_EVENTS+1), (10, 0), (11, 2)):
            changed = copy.deepcopy(self.expected); changed[2][column] = value
            with self.subTest(column=column, value=value), self.assertRaises(ValueError):
                probe.parse_output(self.lines(changed), self.rows)
        changed = copy.deepcopy(self.expected); changed[1][5] = 1
        with self.assertRaises(ValueError): probe.parse_output(self.lines(changed), self.rows)
        changed = copy.deepcopy(self.expected); changed[2][5] ^= 1
        with self.assertRaisesRegex(ValueError, 'directly narrow'): probe.parse_output(self.lines(changed), self.rows)

    def test_failure_operation_operand_counts_and_explicit_propagation(self):
        for operation, count in probe.FAILURE_ARITIES.items():
            words = [0, 1, 0, 0, 0, 0, 0, operation, count, *range(count), 0]
            self.assertEqual(probe.parse_record(words, {'id': 0}), words)
            for changed in (words[:8]+[count+1]+words[9:], words[:-1], words+[0]):
                with self.assertRaises(ValueError): probe.parse_record(changed, {'id': 0})
        for operation in (0, 9, 19, 79, 1000+15, 99999):
            with self.assertRaises(ValueError): probe.parse_record([0, 1, 0, 0, 0, 0, 0, operation, 0, 0], {'id': 0})
        with self.assertRaises(ValueError): probe.parse_record([0, 1, 0, 0, 1, 0, 0, 222, 0, 0], {'id': 0})

    def test_exact_comparison_checks_all_branches_bits_and_event_order(self):
        changed = copy.deepcopy(self.expected); changed[2][1] ^= 2
        changed_index = copy.deepcopy(self.expected); changed_index[2][2] = 1
        changed_gt = copy.deepcopy(self.expected); changed_gt[2][3] = 1
        changed_word = copy.deepcopy(self.expected); changed_word[2][13] ^= 1
        reordered = copy.deepcopy(self.expected); reordered[2][10:] = reordered[2][14:18]+reordered[2][10:14]
        missing = copy.deepcopy(self.expected); missing[2][9] = 1; del missing[2][14:]
        duplicate = copy.deepcopy(self.expected); duplicate[2][9] = 3; duplicate[2].extend(duplicate[2][10:14])
        for actual in (self.expected[:-1], self.expected+[self.expected[-1]], self.expected[::-1],
                       changed, changed_index, changed_gt, changed_word, reordered, missing, duplicate, [], None):
            with self.assertRaises(ValueError): probe.compare(self.expected, actual)

    def test_expected_reference_never_selects_host_or_sun_outputs(self):
        altered = copy.deepcopy(self.records)
        for record in altered:
            if record['accepted']:
                record['native'] ^= 1; record['sun'] ^= 2
        self.assertEqual(probe.expected_records(self.rows, altered), self.expected)
        for field in ('pinned', 'original'):
            altered = copy.deepcopy(self.records); altered[2][field] ^= 1
            with self.assertRaises(ValueError): probe.expected_records(self.rows, altered)

    def test_expected_reference_rejects_wrong_accepted_ids_final_and_events(self):
        changes = [(0, 'accepted', 1), (1, 'accepted', False), (1, 'accepted', True), (2, 'id', 1),
                   (2, 'y', 1), (2, 'x', 1), (2, 'final', None), (2, 'final', [0]),
                   (2, 'final', [0x7ff00000, 0]), (2, 'final', [0, 0]), (2, 'events', None),
                   (2, 'events', [[1, 0]]), (2, 'events', [[999, 0, 0]]),
                   (1, 'mask', 0), (1, 'index', 1), (1, 'gt', 1), (1, 'final', [0, 0]),
                   (1, 'native', 0), (1, 'events', [[1, 0, 0]])]
        for index, field, value in changes:
            if (index, field, value) == (1, 'accepted', False): continue
            records = copy.deepcopy(self.records); records[index][field] = value
            with self.subTest(index=index, field=field, value=value), self.assertRaises(ValueError):
                probe.expected_records(self.rows, records)
        for records in (None, [], self.records[:-1], self.records[::-1], [dict(self.records[0], extra=1), *self.records[1:]]):
            with self.assertRaises(ValueError): probe.expected_records(self.rows, records)

    def test_program_is_bounded_serial_and_observes_both_entrypoints(self):
        rows = [dict(self.rows[0], id=index) for index in range(probe.CHUNK)]
        source = probe.program(rows)
        self.assertEqual(source.count('IO.print('), 1)
        self.assertEqual(source.count('A.traced('), 1)
        self.assertEqual(source.count('A.checked('), 1)
        self.assertIn('case A.Failed{operation, +operands}:', source)
        self.assertIn('case A.Good{F.Words{high, low}}:', source)
        self.assertIn('A.TraceEvent{tag, value}', source)
        self.assertIn('def emit(tasks: +List<AngleTask>) -> IO(Unit):', source)
        self.assertEqual(source.count('AngleTask{'), len(rows)+2)
        self.assertNotIn('calculate!', source)
        for line in source.splitlines():
            if 'IO.print(' in line: self.assertEqual(line.count('observe('), 1)
        with self.assertRaises(ValueError): probe.program(rows+[dict(self.rows[0], id=probe.CHUNK)])

    def test_lane_commands_force_both_cpu_threads_and_javascript(self):
        self.assertEqual(probe.lane_commands('binary', 'code.js', '/pinned/bun'),
                         (('cpu-1', ['binary', '--gpu', 'off', '--threads', '1']),
                          ('cpu-2', ['binary', '--gpu', 'off', '--threads', '2']),
                          ('javascript', ['/pinned/bun', 'code.js'])))

    def test_source_dependencies_cover_harness_corpus_and_narrowing(self):
        self.assertTrue({'src/modern_angle.bend', 'tools/modern_angle_probe.py', 'tools/modern_angle_reference.py',
                         'tools/angle_probe.py', 'tests/test_modern_angle.py', 'tools/binary64_narrow_oracle.py',
                         'tools/conformance.py', 'toolchain.json'} <= set(probe.DEPENDENCIES))

    def test_compile_removes_stale_and_rejects_missing_partial_or_empty_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory); binary = work/'candidate'; js = work/'candidate.js'
            for mode in ('missing', 'partial', 'empty'):
                binary.write_text('old binary'); js.write_text('old js')
                def compile(*args, **kwargs):
                    self.assertFalse(binary.exists()); self.assertFalse(js.exists())
                    if mode in ('partial', 'empty'): binary.write_text('new')
                    if mode == 'empty': js.write_text('')
                with patch.object(probe, 'execute', side_effect=compile), self.assertRaisesRegex(ValueError, 'fresh nonempty'):
                    probe.compile_fresh(['compiler'], [binary, js], work, 'compile')
            def complete(*args, **kwargs): binary.write_text('new'); js.write_text('new js')
            with patch.object(probe, 'execute', side_effect=complete): probe.compile_fresh(['compiler'], [binary, js], work, 'compile')

    def test_execute_retains_failure_timeout_and_replaces_old_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for suffix in ('stdout', 'stderr'): (work/('failure.'+suffix)).write_text('stale')
            with self.assertRaisesRegex(ValueError, 'exited 4'):
                probe.execute([sys.executable, '-c', 'import sys; print("out"); print("err",file=sys.stderr); sys.exit(4)'], work, 'failure')
            self.assertEqual((work/'failure.stdout').read_text(), 'out\n')
            self.assertEqual((work/'failure.stderr').read_text(), 'err\n')
            error = probe.subprocess.TimeoutExpired('command', 1, output=b'partial-out', stderr=b'partial-err')
            with patch.object(probe.subprocess, 'run', side_effect=error), self.assertRaises(probe.subprocess.TimeoutExpired):
                probe.execute(['command'], work, 'timeout')
            self.assertEqual((work/'timeout.stdout').read_text(), 'partial-out')
            self.assertEqual((work/'timeout.stderr').read_text(), 'partial-err')

    def test_cpu_compiler_identity_rejects_silent_fallback_and_overrides_cc(self):
        compiler = dict(path='/recorded/clang', version='Debian clang version 19.1.7')
        environment = probe.candidate_environment(compiler)
        self.assertEqual(environment, {'CC': '/recorded/clang'})
        for version in ('gcc 15', 'clang version 13.0', 'unknown'):
            with self.assertRaises(ValueError): probe.candidate_environment(dict(compiler, version=version))
        with tempfile.TemporaryDirectory() as directory, patch.dict(probe.os.environ, {'CC': '/wrong/compiler'}):
            process = probe.subprocess.CompletedProcess(['command'], 0, '', '')
            with patch.object(probe.subprocess, 'run', return_value=process) as run:
                probe.execute(['command'], Path(directory), 'compile', env=environment)
            self.assertEqual(run.call_args.kwargs['env']['CC'], '/recorded/clang')

    def test_artifacts_are_pinned_when_consumed_and_later_drift_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory); artifact = work/'program.bend'; artifact.write_text('original')
            report = {'artifacts': {}}
            probe.retain_artifacts(report, work, [artifact.name]); probe.assert_artifacts_unchanged(report, work)
            artifact.write_text('changed')
            with self.assertRaisesRegex(ValueError, 'artifact drift'): probe.assert_artifacts_unchanged(report, work)
            with self.assertRaisesRegex(ValueError, 'artifact drift'): probe.retain_artifacts(report, work, [artifact.name])

    def test_native_artifact_hashes_not_reblessed_or_escaped(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory); artifact = work/'reference'; artifact.write_text('binary')
            native = {'artifacts': {str(artifact): probe.digest(artifact)}}
            report = {'artifacts': {}}
            probe.merge_native_artifacts(report, native, work)
            self.assertEqual(set(report['artifacts']), {'reference'})
            for bad in ({}, {'artifacts': {}}, {'artifacts': {str(artifact): 'invalid'}},
                        {'artifacts': {'../elsewhere': 'a'*64}}, {'artifacts': {str(artifact): 'a'*64}}):
                with self.assertRaises(ValueError): probe.merge_native_artifacts({}, bad, work)
            artifact.write_text('changed')
            with self.assertRaises(ValueError): probe.merge_native_artifacts(report, native, work)

    def test_source_content_and_inventory_drift_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'x').write_text('before'); (root/'tools/reference').mkdir(parents=True)
            lock = {'bend': {}}
            with patch.object(probe, 'ROOT', root), patch.object(probe, 'DEPENDENCIES', ('x',)), patch.object(probe, 'source_gate', return_value={}), patch.object(reference, 'source_paths', return_value=[]):
                hashes = probe.source_hashes(lock); probe.assert_unchanged(hashes, lock)
                (root/'x').write_text('after')
                with self.assertRaisesRegex(ValueError, 'drift'): probe.assert_unchanged(hashes, lock)
                (root/'x').write_text('before'); (root/'tools/reference/modern_atan2f_extra.c').write_text('extra')
                with self.assertRaisesRegex(ValueError, 'drift'): probe.assert_unchanged(hashes, lock)

    def test_final_overlay_and_compiler_drift_fail_closed(self):
        lock = {'bend': {'revision': 'pinned', 'patch': {'sha256': 'overlay'}}}
        with patch.object(probe, 'assert_unchanged'), patch.object(probe, 'checkout', side_effect=ValueError('overlay drift')) as check:
            with self.assertRaisesRegex(ValueError, 'overlay drift'): probe.final_source_gate({}, Path('/compiler'), lock)
        check.assert_called_once_with(Path('/compiler'), 'pinned', {'sha256': 'overlay'})
        with patch.object(probe, 'assert_unchanged'), patch.object(probe, 'checkout'), patch.object(probe, 'compiler_identity', return_value={'sha256': 'new'}):
            with self.assertRaisesRegex(ValueError, 'executable drift'):
                probe.final_source_gate({}, Path('/compiler'), lock, {'clang': ('clang', {'sha256': 'old'})}, Path('/work'))

    def test_stale_success_invalidated_before_source_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)/'modern-angle-probe'; work.mkdir(); result = work/'results.json'; result.write_text('{"passed":true}')
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout', side_effect=ValueError('pin failure')), patch.object(sys, 'argv', ['probe', '--bend-source', directory]):
                with self.assertRaisesRegex(ValueError, 'pin failure'): probe.main()
            report = json.loads(result.read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {}); self.assertEqual(report['error'], 'pin failure')

    def test_native_only_never_claims_candidate_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            compiler = dict(path='/compiler', version='clang version 19.1.7', sha256='compiler')
            bun = dict(path='/bun', version='1.3.12', sha256='bun')
            identity = lambda command, *args: bun if command == 'bun' else compiler
            native = {'environment': {}, 'artifacts': {'reference': 'a'*64}}
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout'), \
                    patch.object(reference, 'assert_pins'), patch.object(probe, 'source_hashes', return_value={}), \
                    patch.object(probe, 'validate_candidate_constants'), patch.object(probe, 'compiler_identity', side_effect=identity), \
                    patch.object(probe, 'retain_artifacts'), patch.object(probe, 'assert_artifacts_unchanged'), \
                    patch.object(probe, 'merge_native_artifacts'), patch.object(reference, 'validate_metadata'), patch.object(probe, 'assert_runtime_libraries'), patch.object(probe, 'validate_coverage', return_value={}), \
                    patch.object(reference, 'samples', return_value=self.rows), \
                    patch.object(reference, 'native_reference', return_value=(native, self.records)), \
                    patch.object(probe, 'final_source_gate') as gate, \
                    patch.object(sys, 'argv', ['probe', '--bend-source', directory, '--native-only']), contextlib.redirect_stdout(io.StringIO()):
                probe.main()
            report = json.loads((Path(directory)/'modern-angle-probe/results.json').read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})
            self.assertEqual(report['phase'], 'native-only-complete'); self.assertEqual(report['accepted'], 2)
            gate.assert_called_once()


    def test_constants_match_all_102_independent_pinned_words(self):
        source = (probe.ROOT/'src/modern_angle.bend').read_text()
        self.assertEqual(len(probe.validate_candidate_constants(source)), 102)
        self.assertEqual(probe.validate_candidate_constants(source), reference.CONSTANTS)
        # Change each literal occurrence in the actual constant declarations.
        start = source.index('def constant.zero('); end = source.index('def muldd(')
        block = source[start:end]
        import re
        for match in re.finditer(r'F\.Words\{([0-9]+),\s*([0-9]+)\}', block):
            for group in (1, 2):
                left, right = match.span(group)
                changed = source[:start+left]+str(int(match[group]) ^ 1)+source[start+right:]
                with self.subTest(literal=match[group]), self.assertRaisesRegex(ValueError, 'word mismatch'):
                    probe.validate_candidate_constants(changed)
        for changed in (source.replace('def constant.zero()', 'def constant.missing()', 1),
                        source+source[source.index('def constant.zero()'):source.index('def constant.one()')],
                        source.replace('case 31: DoubleDouble', 'case 30: DoubleDouble', 1),
                        source.replace('Failed{9000,[index]}', 'Failed{9000,[0]}', 1)):
            with self.assertRaises(ValueError): probe.validate_candidate_constants(changed)

    @staticmethod
    def qualification():
        return dict(kind='qualification', rounding='FE_TONEAREST', initial_rounding=0, control=8064,
                    ftz=False, daz=False, binary32=True, binary64=True, excess_precision=False,
                    fma_controls=9, narrow_controls=7, gradual_controls=4,
                    atan2_library='/qualified/libm.so', fma_library='/qualified/libm.so',
                    literal_atan2=1070141403, pointer_atan2=1070141403, original_atan2=1070141403,
                    libc='glibc', libc_version='2.41')

    def native_text(self, records=None, metadata=None):
        # Zero/rejection cases are enough to exercise parsing without compiling C.
        records = self.records[:2] if records is None else records
        return json.dumps(self.qualification() if metadata is None else metadata)+'\n'+self.lines(records)

    def test_native_metadata_requires_exact_layout_rounding_and_preflight(self):
        good = self.qualification()
        with patch.object(reference.platform, 'machine', return_value='x86_64'):
            self.assertEqual(reference.validate_metadata(good), good)
            changes = [('rounding', 'FE_UPWARD'), ('initial_rounding', 1), ('initial_rounding', True),
                       ('control', -1), ('control', True), ('control', 1 << 64),
                       ('ftz', True), ('daz', True), ('binary32', False), ('binary64', False),
                       ('excess_precision', True), ('fma_controls', 8), ('narrow_controls', 6),
                       ('gradual_controls', 3), ('atan2_library', 'relative.so'), ('fma_library', ''),
                       ('literal_atan2', True), ('pointer_atan2', 1 << 32), ('original_atan2', -1),
                       ('libc', None), ('libc_version', 2.41)]
            changes += [('control', good['control'] | bits) for bits in ((1 << 15), (1 << 6), (1 << 13), (1 << 14))]
            for key, value in changes:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    reference.validate_metadata(dict(good, **{key: value}))
            for bad in (None, [], dict(good, extra=1), {k:v for k,v in good.items() if k != 'ftz'}):
                with self.assertRaises(ValueError): reference.validate_metadata(bad)
        with patch.object(reference.platform, 'machine', return_value='aarch64'):
            reference.validate_metadata(dict(good, control=0))
            for bits in ((1 << 24), (1 << 19), (1 << 22), 1, 2):
                with self.assertRaises(ValueError): reference.validate_metadata(dict(good, control=bits))
        with patch.object(reference.platform, 'machine', return_value='unsupported'):
            with self.assertRaises(ValueError): reference.validate_metadata(good)

    def test_native_parser_rejects_missing_extra_reordered_duplicate_and_bad_fields(self):
        with patch.object(reference.platform, 'machine', return_value='x86_64'):
            metadata, records = reference.parse_native(self.native_text(), self.rows[:2])
            self.assertEqual(records, self.records[:2]); self.assertEqual(metadata, self.qualification())
            for text in ('', self.native_text()+'\n', '\n'+self.native_text(), self.native_text(records=[]),
                         self.native_text(records=self.records[:2][::-1]),
                         self.native_text().replace('"ftz": false', '"ftz": true, "ftz": false'),
                         self.native_text().replace('"accepted": true', '"accepted": 1')):
                with self.assertRaises(ValueError): reference.parse_native(text, self.rows[:2])
            for field in self.records[0]:
                bad = copy.deepcopy(self.records[:2]); del bad[0][field]
                with self.assertRaises(ValueError): reference.parse_native(self.native_text(records=bad), self.rows[:2])
            for field in ('id', 'y', 'x', 'mask', 'index', 'gt', 'pinned', 'original', 'native', 'sun'):
                for value in (True, -1, 1 << 32, 1.0, None):
                    bad = copy.deepcopy(self.records[:2]); bad[0][field] = value
                    with self.assertRaises(ValueError): reference.parse_native(self.native_text(records=bad), self.rows[:2])

    def test_native_trace_branch_schema_rejects_conflicts_missing_and_reordered(self):
        row = self.rows[2]
        record = self.record(row, 0x3f800000, [0x3ff00000, 0], mask=1,
                             events=[[tag, 0x3ff00000 if tag == 39 else 0, 16 if tag == 13 else 0] for tag in reference._expected_tags(1)])
        with patch.object(reference.platform, 'machine', return_value='x86_64'):
            reference.parse_native(self.native_text(records=[record]), [row])
            for mask in (0, 3, 4, 8, 16, 32, 128, 256, 512, 2049, 4096, 8192,
                         1|4|8|16|32|64, 1|4|128|256|512|1024):
                bad = dict(record, mask=mask)
                with self.assertRaises(ValueError): reference.parse_native(self.native_text(records=[bad]), [row])
            for events in (record['events'][:-1], record['events'][::-1], record['events']+[record['events'][-1]],
                           [[1, 0, True]]+record['events'][1:], [[1, 0]]+record['events'][1:]):
                with self.assertRaises(ValueError): reference.parse_native(self.native_text(records=[dict(record, events=events)]), [row])

    def test_native_source_pins_and_compile_flags_remain_independent(self):
        pins = reference.assert_pins()
        self.assertEqual(reference.hash_json(reference.CONSTANTS), reference.CONSTANTS_SHA256)
        self.assertEqual(reference.sha256(reference.REFERENCE/'modern_atan2f_glibc241.c'), reference.SOURCE_SHA256)
        for flag in ('-frounding-math', '-fno-fast-math', '-ffp-contract=off', '-fno-builtin-fma', '-fno-builtin-atan2f', '-fno-lto'):
            self.assertIn(flag, reference.FLAGS)
        self.assertTrue(all(Path(path).is_file() for path in pins))
        with patch.object(reference, 'SOURCE_SHA256', '0'*64):
            with self.assertRaisesRegex(ValueError, 'source hash'): reference.assert_pins()
        with patch.object(reference, 'CONSTANTS_SHA256', '0'*64):
            with self.assertRaisesRegex(ValueError, 'coefficient'): reference.assert_pins()


    def test_synthetic_controls_are_separate_fixed_and_bounded(self):
        cases = probe.synthetic_cases()
        self.assertEqual(cases, probe.synthetic_cases())
        self.assertLessEqual(len(cases), probe.CHUNK)
        self.assertEqual([case['id'] for case in cases], list(range(len(cases))))
        self.assertTrue(all(case['label'].startswith('synthetic-') for case in cases))
        labels = {case['label'] for case in cases}
        for name in ('add', 'sub', 'mul', 'div', 'gradual', 'fma', 'promote'):
            self.assertIn('synthetic-invalid-'+name, labels)
        self.assertIn('synthetic-final-correction-guard-false', labels)
        self.assertIn('synthetic-tiny-nonboundary-propagation', labels)
        source = probe.synthetic_program(cases)
        self.assertEqual(source.count('    IO.print('), len(cases))
        self.assertNotIn('A.traced(', source)
        for case in cases: probe.parse_record(case['expected'], {'id': case['id']})
        for bad in ([], None, cases+[cases[0]], cases*2):
            with self.assertRaises(ValueError): probe.synthetic_program(bad)

    def test_runtime_libraries_rechecked_after_all_candidate_work(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'libm.so'; path.write_text('qualified')
            native = {'libraries': {key: dict(path=str(path), sha256=probe.digest(path)) for key in ('atan2_library', 'fma_library')}}
            probe.assert_runtime_libraries(native)
            path.write_text('drift')
            with self.assertRaisesRegex(ValueError, 'library drift'): probe.assert_runtime_libraries(native)
            for bad in ({}, {'libraries': {}}, {'libraries': {'atan2_library': {}}}):
                with self.assertRaises(ValueError): probe.assert_runtime_libraries(bad)

    def test_required_coverage_rejects_shrunken_native_corpus(self):
        records = [dict(mask=1, accepted=True, y=(index>>2)<<31, x=((index>>1)&1)<<31,
                        index=index, gt=index&1, events=[]) for index in range(8)]
        for name, mask in reference.BRANCHES.items():
            if name != 'tiny_increment': records.append(dict(records[0], mask=mask))
        for high, low in ((0x80000000, 0), (0x80000000, 1), (0xbff00000, 0)):
            records.append(dict(records[0], events=[[reference.TRACE_TAGS['tiny_product'], high, low]]))
        coverage = probe.validate_coverage(records)
        self.assertEqual(coverage['reduction_indices'], list(range(8)))
        self.assertTrue(coverage['required_strata_covered'])
        self.assertIn('tiny_increment', coverage['unhit_excluded'])
        self.assertIn('tiny_nonboundary', coverage['excluded_from_required'])
        for name in set(reference.BRANCHES)-{'tiny_increment'}:
            subset = [record for record in records if not record['mask'] & reference.BRANCHES[name]]
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'coverage'): probe.validate_coverage(subset)
        for subset in ([], records[:8], [record for record in records if record['index'] != 7]):
            with self.assertRaises(ValueError): probe.validate_coverage(subset)


    def test_native_final_control_state_must_still_be_qualified(self):
        good = dict(kind='final-context', rounding='FE_TONEAREST', rounding_code=0, control=8064, ftz=False, daz=False)
        with patch.object(reference.platform, 'machine', return_value='x86_64'):
            self.assertEqual(reference.validate_final_context(good), good)
            for key, value in (('kind', 'other'), ('rounding', 'FE_UPWARD'), ('rounding_code', True),
                               ('rounding_code', 1), ('control', True), ('control', 8064|64),
                               ('control', 8064|32768), ('control', 1<<64), ('ftz', 0), ('daz', True)):
                with self.assertRaises(ValueError): reference.validate_final_context(dict(good, **{key: value}))
            for bad in ([], dict(good, extra=1), {k:v for k,v in good.items() if k!='control'}):
                with self.assertRaises(ValueError): reference.validate_final_context(bad)
        with patch.object(reference.platform, 'machine', return_value='aarch64'):
            reference.validate_final_context(dict(good, control=0))
            for bits in ((1<<24), (1<<19), (1<<22), 1, 2):
                with self.assertRaises(ValueError): reference.validate_final_context(dict(good, control=bits))


if __name__ == '__main__':
    unittest.main()
