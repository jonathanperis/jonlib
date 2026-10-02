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
import binary64_gradual_multiply_probe as probe
import binary64_gradual_multiply_oracle as oracle


class Binary64GradualMultiplyTests(unittest.TestCase):
    @staticmethod
    def result(a,b):
        r=oracle.checked('multiply',a>>32,a&0xffffffff,b>>32,b&0xffffffff)
        return None if r is None else (r[0]<<32)|r[1]

    @classmethod
    def setUpClass(cls):
        cls.corpus=probe.samples()
        cls.corpus_expected=[probe.expected_row(row) for row in cls.corpus]

    def setUp(self):
        self.rows=[dict(id=0,kind='multiply',ah=0,al=0,bh=0,bl=0),
                   dict(id=1,kind='multiply',ah=0x7ff00000,al=0,bh=0,bl=0),
                   dict(id=2,kind='multiply',ah=0x3ff00000,al=1,bh=0x3ff00000,bl=0)]
        self.expected=[probe.expected_row(row) for row in self.rows]
        self.text=json.dumps([word for row in self.expected for word in row])+'\n'

    def test_all_fixed_vectors(self):
        self.assertEqual(len(probe.HAND),116)
        for a,b,expected,label in probe.HAND:
            with self.subTest(label=label): self.assertEqual(self.result(a,b),expected)

    def test_zero_sign_xor_and_validation_before_zero(self):
        for a in (0,oracle.SIGN):
            for b in (0,oracle.SIGN): self.assertEqual(self.result(a,b),a^b)
        for operand,bounds in enumerate(oracle.BOUNDS):
            for exponent in bounds:
                for fraction in (0,1,oracle.FRACTION):
                    for sign in (0,1):
                        value=probe.normal(exponent,fraction,sign)
                        for zero in (0,oracle.SIGN):
                            pair=[zero,zero]; pair[operand]=value
                            self.assertEqual(self.result(*pair),(value^zero)&oracle.SIGN)
            invalid=[probe.normal(e,f,s) for e in (-1022,bounds[0]-1,1,1023)
                     for f in (0,1,oracle.FRACTION) for s in (0,1)]
            invalid += [v|sign for v in (1,1<<32,oracle.FRACTION,0x7ff0000000000000,0x7ff0000000000001,0x7ff8000000000000)
                        for sign in (0,oracle.SIGN)]
            for bad in invalid:
                for other in (0,oracle.SIGN,probe.normal(0)):
                    pair=[other,other]; pair[operand]=bad
                    self.assertIsNone(self.result(*pair))

    def test_invalid_words_kinds_and_normal_parameters(self):
        for value in (-1,1<<32,True,False,0.0,'0',None):
            for field in range(4):
                fields=[0]*4; fields[field]=value
                with self.assertRaises(ValueError): oracle.checked('multiply',*fields)
        for kind in ('add','',0,False,None,[]):
            with self.assertRaises(ValueError): oracle.checked(kind,0,0,0,0)
        for args in ((-1023,0,0),(1024,0,0),(0,-1,0),(0,1<<52,0),(0,0,2),(True,0,0),(0,True,0),(0,0,True)):
            with self.assertRaises(ValueError): probe.normal(*args)

    def test_corpus_counts_determinism_unique_ids(self):
        self.assertEqual(self.corpus,probe.samples())
        self.assertEqual(len(self.corpus),30861)
        self.assertEqual(sum(r[2] for r in self.corpus_expected),30509)
        self.assertEqual(sum(r[2]==0 for r in self.corpus_expected),352)
        self.assertEqual([r['id'] for r in self.corpus],list(range(len(self.corpus))))
        keys=[tuple(r[f] for f in probe.FIELDS) for r in self.corpus]
        self.assertEqual(len(keys),len(set(keys)))

    def test_every_exponent_sign_operand_and_product_top(self):
        for operand,(minimum,maximum) in enumerate(oracle.BOUNDS):
            for top in (0,1):
                rows=[r for r in self.corpus if f'every-exponent-operand-{operand}-top-{top}' in r['labels']]
                high=probe.FIELDS[operand*2]
                for sign in (0,1):
                    self.assertEqual({(r[high]>>20&2047)-1023 for r in rows if r[high]>>31==sign},set(range(minimum,maximum+1)))
                for r in rows:
                    ma=(1<<52)|((r['ah']&0xfffff)<<32)|r['al']
                    mb=(1<<52)|((r['bh']&0xfffff)<<32)|r['bl']
                    self.assertEqual((ma*mb).bit_length()-105,top)

    def test_all_gradual_shifts_signs_and_limb_boundaries(self):
        labels={label for r in self.corpus for label in r['labels']}
        self.assertTrue({f'gradual-shift-k-{k}' for k in range(53,193)}<=labels)
        self.assertTrue({f'significand-bit-{b}' for b in range(52)}<=labels)
        for k in range(53,193):
            rows=[r for r in self.corpus if f'gradual-shift-k-{k}' in r['labels']]
            self.assertEqual({(r['ah']>>31,r['bh']>>31) for r in rows},{(0,0),(0,1),(1,0),(1,1)})
            for r in rows:
                total=(r['ah']>>20&2047)+(r['bh']>>20&2047)-2046
                self.assertEqual(-total-970,k)
        self.assertTrue({f'exponent-sum-{s}' for s in (-1024,-1023,-1022,-1075,-1076,-1077,-1162)}<=labels)

    def test_exact_product_domain_bounds_and_signed_zero(self):
        for r,out in zip(self.corpus,self.corpus_expected):
            bits=[(r[a]<<32)|r[b] for a,b in (('ah','al'),('bh','bl'))]
            valid=all(oracle.in_domain(v,*bounds) for v,bounds in zip(bits,oracle.BOUNDS))
            self.assertEqual(bool(out[2]),valid)
            if not valid: continue
            exact=oracle.decode64(r['ah'],r['al'])*oracle.decode64(r['bh'],r['bl'])
            self.assertLess(abs(exact),4)
            self.assertEqual(out[3]>>31,(r['ah']^r['bh'])>>31)
            if bits[0]&~oracle.SIGN and bits[1]&~oracle.SIGN:
                self.assertGreaterEqual(abs(exact),oracle.power2(-1162))
                total=(r['ah']>>20&2047)+(r['bh']>>20&2047)-2046
                if total<=-1077: self.assertEqual(out[3:] ,[(r['ah']^r['bh'])&0x80000000,0])

    def test_double_rounding_witnesses_both_signs(self):
        vectors=((0x1150000000000004,0x0008000000000003,0x0008000000000002),
                 (0x115ffffffffffffd,0x000fffffffffffff,0x0010000000000000),
                 (0x0e0fffffffffffff,1,0))
        for b,expected,wrong in vectors:
            for sign in (0,oracle.SIGN):
                a=0x2ea0000000000001|sign
                self.assertEqual(self.result(a,b),expected|sign)
                self.assertNotEqual(self.result(a,b),wrong|sign)

    def test_internal_synthetic_k106_half_tie_not_reachable_pair(self):
        # Internal exact P=2^105 at k=106, not an accepted significand pair.
        self.assertEqual(oracle.nearest64(Fraction(1<<105,1<<106)*oracle.power2(-1074)),0)
        self.assertEqual(oracle.nearest64(Fraction((1<<105)+1,1<<106)*oracle.power2(-1074)),1)
        # All factors of 2^105 are powers of two; only 2^52 lies in [2^52,2^53).
        self.assertEqual([p for p in range(106) if (1<<52)<=1<<p<(1<<53)],[52])
        self.assertNotEqual(52+52,105)

    def native_text(self,metadata=None,records=None):
        if metadata is None:
            metadata=dict(rounding='FE_TONEAREST',initial_rounding=0,selected_rounding=0,
                          control_name='mxcsr',control=8064,control_after=8114,ftz=False,daz=False,
                          runtime_mul=True,binary64_evaluation=True,preflight_count=probe.PREFLIGHT_COUNT)
        return json.dumps(metadata)+'\n'+'\n'.join(json.dumps(r) for r in (self.expected if records is None else records))+'\n'

    def test_native_valid_and_unqualified_environments(self):
        base,records=probe.parse_native(self.native_text(),self.rows)
        self.assertEqual(records,self.expected)
        for name,fields in (('mxcsr',((1<<15),(1<<6),(1<<13),1<<32)),('fpcr',((1<<24),(1<<19),(1<<22),1,2,1<<64))):
            valid=dict(base,control_name=name,control=0,control_after=0)
            self.assertEqual(probe.parse_native(self.native_text(valid),self.rows)[1],self.expected)
            for field in ('control','control_after'):
                for mask in fields:
                    with self.assertRaises(ValueError): probe.parse_native(self.native_text(dict(valid,**{field:mask})),self.rows)
        for field in ('ftz','daz','runtime_mul','binary64_evaluation'):
            for value in (not base[field],int(base[field])):
                with self.assertRaises(ValueError): probe.parse_native(self.native_text(dict(base,**{field:value})),self.rows)
        for field,value in (('rounding','up'),('selected_rounding',1),('initial_rounding',-1),('control',True),('control_after',1.0),('control_name','unknown'),('preflight_count',62)):
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(dict(base,**{field:value})),self.rows)
        for value in ([],dict(base,extra=1),{k:v for k,v in base.items() if k!='control_after'}):
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(value),self.rows)

    def test_native_malformed_records_and_keys(self):
        valid=self.native_text()
        for text in ('','null\n'+'\n'.join(valid.splitlines()[1:]),valid+'[]\n','\n'+valid,
                     valid.replace('"ftz": false','"ftz": true, "ftz": false')):
            with self.assertRaises(ValueError): probe.parse_native(text,self.rows)
        for record in (None,{},[0,0,1,0,0,0],[0,0,1,0],[0,0,1,-1,0],[0,0,1,0,1<<32],[0,True,1,0,0]):
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(records=[record,*self.expected[1:]]),self.rows)

    def test_native_controls_exact_and_multiply_qualification(self):
        self.assertEqual(probe.PREFLIGHT_COUNT,63)
        for a,b,expected in probe.NATIVE_CONTROLS:
            exact=oracle.decode64(a>>32,a&0xffffffff)*oracle.decode64(b>>32,b&0xffffffff)
            self.assertEqual(oracle.nearest64(exact,(a^b)&oracle.SIGN),expected)
        for text in ('(* volatile runtime_mul)','volatile double va=a, vb=b','result=va*vb',
                     'DBL_HAS_SUBNORM == 1','FLT_EVAL_METHOD == 0','get_control() & forbidden',
                     'fesetround(FE_TONEAREST)','memcpy(&bits,&result,8)'):
            self.assertIn(text,probe.NATIVE)
        self.assertNotIn('runtime_add',probe.NATIVE); self.assertNotIn('fma(',probe.NATIVE)
        self.assertEqual(probe.FLAGS,['-std=c11','-O2','-frounding-math','-fno-fast-math','-ffp-contract=off','-fno-lto'])

    def test_program_bound_shape_and_entrypoint(self):
        rows=self.corpus[:probe.CHUNK]; source=probe.program(rows)
        self.assertIn('G.checked(ah, al, bh, bl)',source)
        self.assertEqual(source.count('Multiply{'),len(rows)+2)
        for line in source.splitlines():
            if 'IO.print(' in line: self.assertLessEqual(line.count('Multiply{'),probe.LINE)
        for selected in ([],self.corpus[:probe.CHUNK+1]):
            with self.assertRaises(ValueError): probe.program(selected)

    def test_parser_ids_tags_kinds_and_payloads(self):
        for index,value in ((0,1),(5,0),(10,1),(1,1),(6,1),(11,1),(2,2),(7,2),(12,2),(8,1),(9,1)):
            changed=json.loads(self.text); changed[index]=value
            with self.assertRaises(ValueError): probe.parse_output(json.dumps(changed),self.rows)

    def test_general_neighbor_rounder_control_ties_and_subnormals(self):
        for lower in (0, 1, 2, (1<<52)-1, 1<<52, 0x3fefffffffffffff,
                      0x3ff0000000000000, 0x3ff0000000000001, oracle.MAX_FINITE):
            left, right = oracle.positive64(lower), oracle.positive64(lower+1)
            middle = (left+right)/2
            for value, expected in ((left, lower), ((left+middle)/2, lower), (middle, lower+lower%2),
                                    ((middle+right)/2, lower+1), (right, lower+1)):
                for sign in (0, oracle.SIGN):
                    self.assertEqual(oracle.nearest64(-value if sign else value, sign), expected | sign)


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
            report = json.loads((Path(directory)/'binary64-gradual-multiply-probe/results.json').read_text())
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
            report = json.loads((Path(directory)/'binary64-gradual-multiply-probe/results.json').read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})


    def test_source_dependencies_include_entire_harness_and_shared_oracle(self):
        self.assertTrue({'src/binary64_gradual_multiply.bend', 'src/binary64_fma.bend', 'tools/binary64_gradual_multiply_probe.py',
                         'tools/binary64_gradual_multiply_oracle.py', 'tools/binary64_fma_oracle.py',
                         'tests/test_binary64_gradual_multiply.py', 'tools/conformance.py', 'toolchain.json',
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
            work = Path(directory)/'binary64-gradual-multiply-probe'; work.mkdir()
            result = work/'results.json'; result.write_text('{"passed":true}')
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout', side_effect=ValueError('pin failure')), patch.object(sys, 'argv', ['probe', '--bend-source', directory]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'pin failure'): probe.main()
            report = json.loads(result.read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})
            self.assertEqual(report['error'], 'pin failure')



if __name__ == '__main__':
    unittest.main()
