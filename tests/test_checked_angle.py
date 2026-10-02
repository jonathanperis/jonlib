import contextlib
import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import checked_angle_probe as probe


class CheckedAngleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corpus=probe.samples()
        cls.by_label={row['label']:row for row in cls.corpus}

    def setUp(self):
        self.rows=[dict(id=0,api=0,args=[0]*4,label='zero',frozen=None),
                   dict(id=1,api=1,args=[0,0,0x7f000000,0x3f800000],label='output',frozen=None),
                   dict(id=2,api=2,args=[0x7f800000,0,0,0,0,0],label='input',frozen=None)]
        self.native=[self.native_record(self.rows[0],0,0),
                     self.native_record(self.rows[1],0x00400000,0x80400000),
                     self.native_record(self.rows[2],0,0x7fc00000)]
        self.actual=[[0,1,0,0,1,0,1,0,1,0,1,0,0,0],
                     [1,0,32,0,0,0,0,0,0,0,1,0x80400000,0x80400000,0x80400000],
                     [2,0,1,0,0,0,0,0,0,0,0,0,0,0]]

    @staticmethod
    def lines(values): return ''.join(json.dumps(value)+'\n' for value in values)

    @staticmethod
    def native_record(row,scalar,actual):
        stage,trace,pair=probe.domain(row)
        if not stage:
            trace=trace+[[32,scalar]]
            if probe.normal(scalar):
                if row['api']==1: trace.append([33,scalar^0x80000000])
            else: stage=32
        return dict(id=row['id'],tag=int(not stage),stage=stage,word=0 if stage else actual,
                    scalar=scalar,actual=actual,trace=trace,pre_scalar_valid=pair is not None)

    @staticmethod
    def wire(row,record):
        return [row['id'],row['api'],len(row['args']),*row['args'],record['tag'],record['stage'],record['word'],
                record['actual'],record['scalar'],len(record['trace']),*(item for pair in record['trace'] for item in pair)]

    def test_corpus_has_exact_frozen_controls_and_stable_ids(self):
        probe.validate_rows(self.corpus)
        self.assertEqual(self.corpus,probe.samples())
        self.assertEqual([row['id'] for row in self.corpus],list(range(len(self.corpus))))
        frozen=[row for row in self.corpus if row['frozen'] is not None]
        self.assertEqual(len(frozen),205)
        self.assertEqual([sum(row['api']==api for row in frozen) for api in range(3)],[77,76,52])
        # The existing 1,086-scalar regression is deliberately not folded into this wrapper corpus.
        self.assertFalse(any(row['label'].startswith('historical-') for row in self.corpus))

    def test_all_nonfinite_words_in_every_input_field(self):
        for api,arity in enumerate(probe.ARITIES):
            for position in range(arity):
                rows=[row for row in self.corpus if row['label'].startswith(f'nonfinite-api{api}-field{position}-')]
                self.assertEqual(len(rows),6)
                for row in rows:
                    self.assertEqual(probe.domain(row),(1,[],None))

    def test_all_signed_zero_permutations(self):
        for api,arity in enumerate(probe.ARITIES):
            rows=[row for row in self.corpus if row['label'].startswith(f'all-signed-zeros-{api}-')]
            self.assertEqual(len(rows),2**arity)
            self.assertEqual(len({tuple(row['args']) for row in rows}),2**arity)
            self.assertTrue(all(probe.domain(row)[0]==0 for row in rows))

    def test_required_reachable_stages_and_specific_rejections(self):
        seen={api:set() for api in range(3)}
        for row in self.corpus:
            stage,trace,pair=probe.domain(row)
            if stage: seen[row['api']].add(stage)
        self.assertEqual(seen[0],{1,*range(10,16)})
        self.assertEqual(seen[1],{1,10,11})
        self.assertEqual(seen[2],{1,*range(10,24),*range(26,31)})
        for label,stage in [('v2-dot-product-10',10),('v2-dot-cancellation-12',12),
            ('v2-det-cancellation-15',15),('v3-first-length-sum-overflow-22',22),
            ('v3-final-length-sum-overflow-23',23),('v3-dot-sum-overflow-30',30)]:
            self.assertEqual(probe.domain(self.by_label[label])[0],stage)

    def test_zero_underflow_and_finite_subnormal_inputs_are_not_blanket_rejected(self):
        for label in ('subnormal-input-accepted-zero-products','subnormal-input-accepted-normal-product',
                      'underflow-to-zero-allowed','v3-subnormal-input-accepted-zero-products',
                      'line-subnormal-input-normal-difference','accepted-tiny-negative-zero'):
            self.assertEqual(probe.domain(self.by_label[label])[0],0,label)
        row=self.by_label['underflow-to-zero-allowed']
        self.assertEqual(probe.domain(row)[1][0],[10,0])
        row=self.by_label['output-only-subnormal']
        self.assertEqual(probe.domain(row)[2],[0x3f800000,0x7f000000])

    def test_fma_and_association_controls_have_independent_exact_intermediates(self):
        trace=dict(probe.domain(self.by_label['fma-sensitive-determinant'])[1])
        self.assertEqual([trace[key] for key in (12,13,14,15)],[0x40000000,0x3f800000,0x3f800000,0])
        trace=dict(probe.domain(self.by_label['left-associated-dot'])[1])
        self.assertEqual(trace[30],0x3f800000)
        self.assertEqual(probe.add(trace[26],probe.add(trace[27],trace[28])),0)
        trace=dict(probe.domain(self.by_label['left-associated-squares'])[1])
        self.assertEqual(trace[23],0x3fa9b9b4)
        right=probe.add(trace[19],probe.add(trace[20],trace[21]))
        self.assertEqual(right,0x3fa9b9b5)
        self.assertEqual(probe.square_root(trace[23]),0x3f9364be)
        self.assertEqual(probe.square_root(right),0x3f9364bf)
        self.assertEqual(trace[30],0x3f000000)

    def test_exact_rational_boundaries_signed_zero_and_sqrt(self):
        f=probe.Fraction
        self.assertEqual(probe.round32(f(2)**128-f(2)**103),0x7f800000)
        self.assertEqual(probe.round32(f(2)**128-f(2)**103-1),0x7f7fffff)
        self.assertEqual(probe.round32(f(2)**-150),0)
        self.assertEqual(probe.round32(-f(2)**-150),0x80000000)
        self.assertEqual(probe.multiply(0x80000000,0x3f800000),0x80000000)
        self.assertEqual(probe.subtract(0x80000000,0),0x80000000)
        self.assertEqual(probe.subtract(0x80000000,0x80000000),0)
        self.assertEqual(probe.square_root(0x80000000),0x80000000)
        self.assertEqual(probe.square_root(0x40000000),0x3fb504f3)
        with self.assertRaises(ValueError): probe.square_root(0xbf800000)

    def test_input_validation_rejects_shapes_types_duplicate_ids_and_labels(self):
        bad=[None,(),[],[self.rows[0],self.rows[0]], [dict(self.rows[0],extra=1)],
             [dict(self.rows[0],api=3)],[dict(self.rows[0],args=[0])],
             [self.rows[0],dict(self.rows[1],label='zero')]]
        for field in ('id','api'):
            for value in (True,False,None,-1,2**32,1.0,'0',[]): bad.append([dict(self.rows[0],**{field:value})])
        for value in (True,None,-1,2**32,0.0,'0'): bad.append([dict(self.rows[0],args=[value,0,0,0])])
        for frozen in ({},[],{'Glibc241AngleRn':0},{name:True for name in probe.PROFILES}):
            bad.append([dict(self.rows[0],frozen=frozen)])
        for rows in bad:
            with self.subTest(rows=rows),self.assertRaises(ValueError): probe.validate_rows(rows)

    def test_candidate_acceptance_failure_and_compatibility(self):
        self.assertEqual(probe.parse_output(self.lines(self.actual),self.rows),self.actual)
        probe.compare(self.rows,self.native,self.actual)
        changed=copy.deepcopy(self.actual); changed[0][11]=0x3f800000
        with self.assertRaises(ValueError): probe.parse_output(self.lines(changed),self.rows)
        changed=copy.deepcopy(self.actual); changed[0][13]=0x80000000
        with self.assertRaisesRegex(ValueError,'default'): probe.parse_output(self.lines(changed),self.rows)

    def test_candidate_parser_rejects_noise_missing_extra_reordered_and_coalesced(self):
        text=self.lines(self.actual)
        for value in ('',text+'\n','\n'+text,'noise\n'+text,self.lines(self.actual[::-1]),
                      self.lines(self.actual[:-1]),self.lines(self.actual+self.actual),json.dumps(self.actual)):
            with self.assertRaises(ValueError): probe.parse_output(value,self.rows)
        for index,row in enumerate(self.actual):
            for column in range(len(row)):
                for value in (True,False,None,-1,2**32,0.0,'0',[],{}):
                    bad=copy.deepcopy(self.actual); bad[index][column]=value
                    with self.assertRaises(ValueError): probe.parse_output(self.lines(bad),self.rows)

    def test_candidate_tags_stages_public_none_and_payload_canonicalization(self):
        for column,value in ((1,2),(2,10),(3,1),(4,0),(5,0x7f800000),(6,0),(7,1),(8,2),(10,2)):
            bad=copy.deepcopy(self.actual); bad[0][column]=value
            with self.assertRaises(ValueError): probe.parse_output(self.lines(bad),self.rows)
        for column,value in ((1,1),(2,0),(2,99),(3,1),(5,1),(6,1),(11,1)):
            bad=copy.deepcopy(self.actual); bad[2][column]=value
            with self.assertRaises(ValueError): probe.parse_output(self.lines(bad),self.rows)

    def test_native_uses_original_result_with_exact_domain_adaptation(self):
        values=[self.wire(row,record) for row,record in zip(self.rows,self.native)]
        self.assertEqual(probe.parse_native(self.lines(values),self.rows),self.native)
        # Original unguarded NaN is diagnostic only, never an accepted checked result.
        values[2][3+len(self.rows[2]['args'])+3]=0xffc00001
        result=probe.parse_native(self.lines(values),self.rows)
        self.assertEqual(result[2]['stage'],1)
        self.assertEqual(result[2]['actual'],0xffc00001)

    def test_native_rejects_input_drift_wrong_scalar_actual_stage_and_trace(self):
        base=[self.wire(row,record) for row,record in zip(self.rows,self.native)]
        changes=[(0,0,1),(0,1,1),(0,2,6),(0,3,1),(0,7,0),(0,8,10),(0,9,1),
                 (0,10,1),(0,11,1),(0,12,0),(0,13,99),(0,14,1),
                 (1,8,31),(1,11,0),(2,10,0),(2,11,2),(2,13,1)]
        for index,column,value in changes:
            bad=copy.deepcopy(base); bad[index][column]=value
            with self.subTest(index=index,column=column),self.assertRaises(ValueError):
                probe.parse_native(self.lines(bad),self.rows)
        for text in ('',self.lines(base[::-1]),self.lines(base)+'\n',json.dumps(base)):
            with self.assertRaises(ValueError): probe.parse_native(text,self.rows)
        for column in range(len(base[0])):
            for value in (True,None,-1,2**32,0.0,'0'):
                bad=copy.deepcopy(base); bad[0][column]=value
                with self.assertRaises(ValueError): probe.parse_native(self.lines(bad),self.rows)

    def test_compare_rejects_missing_reordered_mismatched_and_unexpected_records(self):
        for native,actual in ((self.native[:-1],self.actual),(self.native,self.actual[::-1]),
            (self.native[::-1],self.actual),(None,self.actual),(self.native,None)):
            with self.assertRaises(ValueError): probe.compare(self.rows,native,actual)
        for field,value in (('tag',1),('stage',11),('word',1),('id',0),('pre_scalar_valid',1)):
            bad=copy.deepcopy(self.native); bad[2][field]=value
            with self.assertRaises(ValueError): probe.compare(self.rows,bad,self.actual)
        bad=copy.deepcopy(self.native); bad[0]['extra']=1
        with self.assertRaises(ValueError): probe.compare(self.rows,bad,self.actual)

    def test_bounded_serial_candidate_observes_public_private_and_legacy(self):
        rows=[dict(self.rows[0],id=i,label='row-'+str(i)) for i in range(probe.CHUNK)]
        source=probe.program(rows)
        self.assertEqual(source.count('IO.print('),1)
        self.assertIn('emit(rest)',source)
        self.assertNotIn('calculate!',source)
        for name in ('vector2','line','vector3'): self.assertIn('C.'+name+'(2,',source)
        for profile in probe.PROFILES: self.assertEqual(source.count('M.'+profile+'{}'),3)
        for name in ('M.Vector2.angle','M.Vector2.line_angle','M.Vector3.angle'):
            self.assertIn(name+'_for(M.AccurateGradient{}',source)
            self.assertIn(name+'(left,right)',source)
        with self.assertRaises(ValueError): probe.program(rows+[dict(self.rows[0],id=999,label='extra')])
        with self.assertRaises(ValueError): probe.program(self.rows,'../../evil\nimport Base')

    def test_native_source_preserves_original_runtime_calls_and_pinned_source_separation(self):
        source=probe.native_source(self.rows)
        self.assertIn('static volatile uint32_t inputs',source)
        self.assertIn('__attribute__((noinline)) static float original',source)
        for name in probe.APIS: self.assertIn('return '+name+'(a,b);',source)
        self.assertIn('float scalar=aq_pinned_atan2f(yarg,xarg)',source)
        self.assertLess(source.index('FP_CONTRACT OFF'),source.index('#include "raymath.h"'))
        self.assertLess(source.index('STEP(c1,15'),source.index('STEP(cx,16'))
        self.assertLess(source.index('STEP(p2,28'),source.index('STEP(dxy,29'))
        self.assertIn('-ffp-contract=off',probe.FLAGS)
        self.assertIn('-fno-lto',probe.FLAGS)
        self.assertIn('-fno-fast-math',probe.FLAGS)

    def test_synthetic_none_invalid_payload_sqrt_stages_and_profiles(self):
        cases=probe.synthetic_cases()
        self.assertLessEqual(len(cases),probe.CHUNK)
        self.assertTrue(any(case['expression']=='C.scalar_result(None{})' and case['expected'][2]==31 for case in cases))
        self.assertEqual({case['expected'][2] for case in cases if not case['expected'][1]}, {2,*range(10,34)})
        source=probe.synthetic_program(cases)
        self.assertEqual(source.count('IO.print('),len(cases))
        self.assertEqual(probe.parse_synthetic(self.lines([case['expected'] for case in cases]),cases),[case['expected'] for case in cases])
        for text in ('',self.lines([case['expected'] for case in cases[::-1]])):
            with self.assertRaises(ValueError): probe.parse_synthetic(text,cases)
        bad=[case['expected'][:] for case in cases]; bad[0][1]=True
        with self.assertRaises(ValueError): probe.parse_synthetic(self.lines(bad),cases)

    def test_compile_removes_stale_and_requires_all_nonempty_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); binary=work/'binary'; javascript=work/'code.js'
            for mode in ('missing','partial','empty','complete'):
                binary.write_text('stale'); javascript.write_text('stale')
                def compiler(*args,**kwargs):
                    self.assertFalse(binary.exists()); self.assertFalse(javascript.exists())
                    if mode!='missing': binary.write_text('new')
                    if mode in ('empty','complete'): javascript.write_text('' if mode=='empty' else 'new')
                with patch.object(probe,'execute',side_effect=compiler):
                    if mode=='complete': probe.compile_fresh(['compiler'],[binary,javascript],work,'compile')
                    else:
                        with self.assertRaisesRegex(ValueError,'fresh nonempty'):
                            probe.compile_fresh(['compiler'],[binary,javascript],work,'compile')

    def test_execute_nonzero_and_timeout_preserve_fresh_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); report={}
            (work/'fail.stdout').write_text('stale')
            with self.assertRaisesRegex(ValueError,'exited 3'):
                probe.execute([sys.executable,'-c','import sys; print("out"); print("err",file=sys.stderr); sys.exit(3)'],work,'fail',report=report)
            self.assertEqual((work/'fail.stdout').read_text(),'out\n')
            self.assertEqual((work/'fail.stderr').read_text(),'err\n')
            self.assertFalse(report['commands'][0]['completed'])
            error=subprocess.TimeoutExpired('cmd',1,output=b'partial',stderr=b'problem')
            with patch.object(probe.subprocess,'run',side_effect=error),self.assertRaises(subprocess.TimeoutExpired):
                probe.execute(['cmd'],work,'timeout')
            self.assertEqual((work/'timeout.stdout').read_text(),'partial')

    def test_receipt_rejects_stale_unknown_mixed_missing_and_artifact_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'artifact'; path.write_text('new')
            receipt=dict(qualified=True,selected_profile='Glibc241AngleRn',phase='qualified',matching_profiles=['Glibc241AngleRn'],
                         candidate_executed=False,run_id='fresh',started_at='2026-10-02T10:00:01+00:00',
                         contexts={'native':{}},artifacts={str(path):probe.digest(path)})
            started='2026-10-02T10:00:00+00:00'
            probe.assert_qualification(receipt,started)
            for key,value in (('qualified',1),('selected_profile','Sun239AngleRn'),('matching_profiles',probe.PROFILES),
                              ('candidate_executed',True),('run_id',''),('contexts',{}),('artifacts',{}),
                              ('started_at','2026-10-02T09:59:59+00:00')):
                with self.assertRaises(ValueError): probe.assert_qualification(dict(receipt,**{key:value}),started)
            path.write_text('changed')
            with self.assertRaisesRegex(ValueError,'drift'): probe.assert_qualification(receipt,started)

    def test_qualification_failure_never_generates_or_runs_candidates(self):
        with tempfile.TemporaryDirectory() as directory:
            args=probe.argparse.Namespace(bend_source=Path('/bend'),raylib_source=Path('/raylib'),library=Path('/archive'),timeout=1,native_only=False)
            work=Path(directory); report={'started_at':'2026-10-02T00:00:00+00:00'}
            with patch.object(probe.conformance,'checkout'),patch.object(probe,'source_hashes',return_value={}), \
                 patch.object(probe.common,'compiler_identity',return_value={'version':'1.3.12'}), \
                 patch.object(probe.qualification,'qualify',side_effect=ValueError('unsupported')), \
                 patch.object(probe,'native_reference') as native,patch.object(probe,'run_candidates') as candidate:
                with self.assertRaisesRegex(ValueError,'unsupported'): probe.run(args,report,work/'results.json')
                native.assert_not_called(); candidate.assert_not_called()

    def test_cli_all_admitted_failures_and_help_invalidate_stale_success(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); path=work/'results.json'
            valid=['--build-dir',str(work),'--bend-source','/bend','--raylib-source','/raylib','--library','/archive']
            for extra in (['--bad'],['--timeout','0'],['--time','2'],['--help']):
                path.write_text('{"passed":true}')
                with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    probe.main(valid+extra)
                self.assertIs(json.loads(path.read_text())['passed'],False)
            for error in (ValueError('fail'),KeyboardInterrupt()):
                path.write_text('{"passed":true}')
                with patch.object(probe,'run',side_effect=error),self.assertRaises(type(error)): probe.main(valid)
                self.assertIs(json.loads(path.read_text())['passed'],False)
                self.assertEqual(json.loads(path.read_text())['phase'],'failed')

    def test_full_corpus_fingerprint_rejects_deleted_reordered_or_weakened_controls(self):
        probe.validate_corpus(self.corpus)
        for index in (0,204,205,len(self.corpus)-1):
            bad=copy.deepcopy(self.corpus); del bad[index]
            with self.assertRaisesRegex(ValueError,'corpus'): probe.validate_corpus(bad)
        for field,value in (('label','changed'),('args',[0]*4),('frozen',None)):
            bad=copy.deepcopy(self.corpus); bad[0][field]=value
            with self.assertRaisesRegex(ValueError,'corpus'): probe.validate_corpus(bad)
        with self.assertRaisesRegex(ValueError,'corpus'): probe.validate_corpus(self.corpus[::-1])

    def test_cli_destination_matrix_invalidates_exact_effective_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); default=root/'.build/checked-angle-probe'; first=root/'first'; second=root/'second'
            required=['--bend-source','/bend','--raylib-source','/raylib','--library','/archive']
            matrix=[
                (['--timeout','oops','--build-dir',str(first)],first),
                (['--timeout','oops','--build-dir='+str(first)],first),
                (['--help','--build-dir',str(first)],first),
                (['--help','--build-dir='+str(first)],first),
                (['--bad','--build-dir',str(first)],first),
                (['--build-dir',str(first),'--timeout','oops'],first),
                (['--build-dir='+str(first),'--help'],first),
                (['--build-dir',str(first),'--timeout','oops','--build-dir',str(second)],second),
                (['--build-dir',str(first),'--help','--build-dir='+str(second)],second),
                (['--build-dir='+str(first),'--build-dir',str(second),'--help'],second),
                (['--build-dir',str(first),'--build-dir='+str(second),'--timeout','0'],second),
                (['--build-dir',str(first),'--','--build-dir',str(second)],first),
                (['--','--build-dir',str(first)],default),
                (['--help','--','--build-dir',str(first)],default),
                (['--build',str(first)],default),
                (['--build-dir',str(first),'--build',str(second)],first),
                (['--build-dir',str(first),'--build-dir'],first),
                (['--build-dir','--help'],default),
                (['--timeout','-1','--build-dir',str(first)],first),
                (['--build-dir',str(first),'--timeout'],first),
                (['--library=--build-dir='+str(second),'--help'],default),
            ]
            for extra,effective in matrix:
                with self.subTest(extra=extra):
                    for target in (default,first,second):
                        target.mkdir(parents=True,exist_ok=True); (target/'results.json').write_text('{"passed":true}')
                    with patch.object(probe,'ROOT',root),contextlib.redirect_stdout(io.StringIO()), \
                         contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                        probe.main(required+extra)
                    for target in (default,first,second):
                        self.assertIs(json.loads((target/'results.json').read_text())['passed'],target!=effective)

    def test_argparse_negative_number_and_dash_directory_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name in ('-1','-1.0','-.5','-'):
                target=root/name; target.mkdir(); path=target/'results.json'
                path.write_text('{"passed":true}')
                argv=['--build-dir',name,'--bend-source','/bend','--raylib-source','/raylib','--library','/archive']
                with patch.object(probe.os,'getcwd',return_value=str(root)), \
                     patch.object(probe,'run',side_effect=ValueError('planned stop')),self.assertRaisesRegex(ValueError,'planned stop'):
                    probe.main(argv)
                self.assertIs(json.loads(path.read_text())['passed'],False)
                path.write_text('{"passed":true}')
                with patch.object(probe.os,'getcwd',return_value=str(root)),contextlib.redirect_stdout(io.StringIO()), \
                     self.assertRaises(SystemExit): probe.main(['--help',*argv])
                self.assertIs(json.loads(path.read_text())['passed'],False)

    def test_context_rejects_mixed_process_or_loaded_library_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'libm.so'; path.write_text('library')
            st=path.stat()
            initial=dict(kind='initial-context',architecture='x86_64',control=0x1f80,rounding=0,
                         library_path=str(path),library_realpath=str(path),
                         library_stat=[st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns//10**9,st.st_mtime_ns%10**9])
            context=dict(initial=initial,final=dict(initial,kind='final-context'))
            receipt={'contexts':{'one':dict(initial=initial,library={'sha256':probe.digest(path)})}}
            with patch.object(probe.qualification,'parse_context',return_value=context):
                self.assertEqual(probe.check_context('metadata',receipt),context)
                bad=copy.deepcopy(receipt); bad['contexts']['one']['initial']['rounding']=1
                with self.assertRaisesRegex(ValueError,'differs'): probe.check_context('metadata',bad)
                bad=copy.deepcopy(receipt); bad['contexts']['one']['library']['sha256']='0'*64
                with self.assertRaisesRegex(ValueError,'drift'): probe.check_context('metadata',bad)
                path.write_text('changed')
                with self.assertRaisesRegex(ValueError,'drift'): probe.check_context('metadata',receipt)
            with patch.object(probe.qualification,'parse_context',side_effect=ValueError('FTZ')):
                with self.assertRaisesRegex(ValueError,'FTZ'): probe.check_context('metadata',receipt)

    def test_lane_commands_and_dependency_inventory(self):
        self.assertEqual(probe.lane_commands('bin','js','bun'),(
            ('cpu-1',['bin','--gpu','off','--threads','1']),('cpu-2',['bin','--gpu','off','--threads','2']),('javascript',['bun','js'])))
        self.assertTrue({'tools/checked_angle_probe.py','tests/test_checked_angle.py','tools/angle_reference.py',
                         'tools/conformance.py','toolchain.json'}<=set(probe.DEPENDENCIES))


if __name__=='__main__': unittest.main()
