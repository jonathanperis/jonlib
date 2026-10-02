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
import binary64_fma_probe as probe
import binary64_fma_oracle as oracle


class Binary64FmaTests(unittest.TestCase):
    @staticmethod
    def result(a, b, c):
        result = oracle.checked(*(field for value in (a, b, c) for field in (value >> 32, value & 0xffffffff)))
        return None if result is None else (result[0] << 32) | result[1]

    @classmethod
    def setUpClass(cls):
        cls.corpus = probe.samples()

    def setUp(self):
        self.rows = [dict(id=0, kind='fma', ah=0, al=0, bh=0, bl=0, ch=0, cl=0),
                     dict(id=1, kind='fma', ah=0x7ff00000, al=0, bh=0, bl=0, ch=0, cl=0),
                     dict(id=2, kind='fma', ah=0x3ff00000, al=1, bh=0x3ff00000, bl=0, ch=0, cl=0)]
        self.expected = [probe.expected_row(row) for row in self.rows]
        self.text = json.dumps([word for row in self.expected for word in row])+'\n'

    def test_fixed_fused_floor_and_tie_controls(self):
        for a, b, c, expected, label in probe.HAND:
            with self.subTest(label=label):
                self.assertEqual(self.result(a, b, c), expected)
        one = Fraction(1)
        delta = oracle.power2(-52)
        self.assertEqual((one+delta)*(one-delta)-one, -oracle.power2(-104))
        self.assertEqual((one+delta)**2*oracle.power2(-554)-(one+2*delta)*oracle.power2(-554), oracle.power2(-658))
        self.assertEqual(float(one+delta)*float(one-delta)-1.0, 0.0)

    def test_signed_zero_and_nonzero_cancellation(self):
        for sa in (0, 1):
            for sb in (0, 1):
                for sc in (0, 1):
                    expected = oracle.SIGN if sa ^ sb == sc == 1 else 0
                    for b in (sb << 63, probe.normal(-277, sign=sb), probe.normal(127, oracle.FRACTION, sb)):
                        self.assertEqual(self.result(sa << 63, b, sc << 63), expected)
                    for a in (probe.normal(-277, sign=sa), probe.normal(127, oracle.FRACTION, sa)):
                        self.assertEqual(self.result(a, sb << 63, sc << 63), expected)
        for e in (-554, -1, 0, 254):
            ea=e//2
            for sign in (0, 1):
                self.assertEqual(self.result(probe.normal(ea, sign=sign), probe.normal(e-ea), probe.normal(e, sign=1-sign)), 0)

    def test_each_operand_domain_boundaries_and_zero_shortcuts(self):
        one=probe.normal(0)
        for index,(minimum,maximum) in enumerate(oracle.BOUNDS):
            for exponent in (minimum, maximum):
                for sign in (0, 1):
                    for fraction in (0, oracle.FRACTION):
                        values=[one,one,0];values[index]=probe.normal(exponent,fraction,sign)
                        self.assertIsNotNone(self.result(*values))
            for exponent in (-1022,minimum-1,maximum+1,1023):
                for sign in (0,1):
                    for base in ([one,one,one],[0,0,0],[oracle.SIGN]*3):
                        values=list(base);values[index]=probe.normal(exponent,oracle.FRACTION,sign)
                        self.assertIsNone(self.result(*values))
            for invalid in (1,1<<51,oracle.FRACTION,0x7ff0000000000000,0x7ff0000000000001,0x7ff8000000000000,0x7fffffffffffffff):
                for sign in (0,oracle.SIGN):
                    values=[0,0,0];values[index]=invalid|sign
                    self.assertIsNone(self.result(*values))

    def test_invalid_words_and_rationals_fail(self):
        for value in (-1,1<<32,True,False,0.0,'0',None):
            for field in range(6):
                values=[0]*6;values[field]=value
                with self.assertRaises(ValueError):oracle.checked(*values)
        for bits in (-1,oracle.OVERFLOW_ENDPOINT+1,oracle.SIGN,True):
            with self.assertRaises(ValueError):oracle.positive64(bits)
        for value in (1.0,True,'1',None):
            with self.assertRaises(ValueError):oracle.nearest64(value)
        for sign in (-1,1,True,1<<64):
            with self.assertRaises(ValueError):oracle.nearest64(Fraction(0),sign)

    def test_general_neighbor_oracle_exact_values_and_even_odd_ties(self):
        lowers=(0,1,2,(1<<52)-1,1<<52,0x3fefffffffffffff,0x3ff0000000000000,
                0x3ff0000000000001,0x4ffffffffffeffff,oracle.MAX_FINITE)
        for lower in lowers:
            left,right=oracle.positive64(lower),oracle.positive64(lower+1)
            middle=(left+right)/2
            for value,expected in ((left,lower),((left+middle)/2,lower),(middle,lower+lower%2),((middle+right)/2,lower+1),(right,lower+1)):
                for sign in (0,oracle.SIGN):
                    self.assertEqual(oracle.nearest64(-value if sign else value,sign),expected|sign)
        self.assertEqual(oracle.nearest64(oracle.power2(1025)),oracle.OVERFLOW_ENDPOINT)

    def test_corpus_deterministic_ids_and_all_operand_exponents(self):
        self.assertEqual(self.corpus,probe.samples())
        self.assertEqual([r['id'] for r in self.corpus],list(range(len(self.corpus))))
        for operand,(minimum,maximum) in enumerate(oracle.BOUNDS):
            label=f'every-exponent-operand-{operand}'
            high=probe.FIELDS[operand*2]
            for sign in (0,1):
                actual={(r[high]>>20&2047)-1023 for r in self.corpus if label in r['labels'] and r[high]>>31==sign}
                self.assertEqual(actual,set(range(minimum,maximum+1)))
        labels={label for r in self.corpus for label in r['labels']}
        for prefix,count,start in (('alignment-residual-shift-',32,0),('normalization-residual-shift-',32,0),('normalization-left-shift-',55,1)):
            self.assertTrue({f'{prefix}{i}' for i in range(start,start+count)}<=labels)
        self.assertIn('retained-53-bit-rounding-carry',labels)
        self.assertIn('nonzero-exact-cancellation',labels)
        self.assertGreater(len(self.corpus),10000)

    def test_corpus_exact_lattice_and_magnitude_bounds(self):
        floor=oracle.power2(-658)
        for row in self.corpus:
            bits=[(row[probe.FIELDS[i]]<<32)|row[probe.FIELDS[i+1]] for i in (0,2,4)]
            if not all(oracle.in_domain(value,*bounds) for value,bounds in zip(bits,oracle.BOUNDS)):
                continue
            a,b,c=[oracle.decode64(value>>32,value&0xffffffff) for value in bits]
            exact=a*b+c
            self.assertEqual((exact/floor).denominator,1)
            self.assertLess(abs(exact),oracle.power2(257))
            if exact:self.assertGreaterEqual(abs(exact),floor)
            for label in row['labels']:
                if label.startswith('normalization-left-shift-'):
                    shift=int(label.rsplit('-',1)[1])
                    self.assertEqual(abs(exact),oracle.power2(-603-shift))

    def test_all_corpus_rows_have_unique_input_triplets(self):
        keys=[tuple(r[field] for field in probe.FIELDS) for r in self.corpus]
        self.assertEqual(len(keys),len(set(keys)))

    def test_parser_accepts_exact_framing_and_complete_records(self):
        self.assertEqual(probe.parse_output(self.text,self.rows),self.expected)
        probe.compare(self.expected,self.expected)
        rows=[dict(self.rows[0],id=index) for index in range(probe.LINE+1)]
        expected=[probe.expected_row(row) for row in rows]
        lines=[json.dumps([v for row in expected[i:i+probe.LINE] for v in row]) for i in range(0,len(rows),probe.LINE)]
        self.assertEqual(probe.parse_output('\n'.join(lines)+'\n',rows),expected)
        with self.assertRaises(ValueError):probe.parse_output(json.dumps([v for row in expected for v in row]),rows)

    def test_parser_rejects_malformed_extra_missing_and_wrong_types(self):
        values=json.loads(self.text)
        bad=['',self.text+'\n',self.text+self.text,'noise\n'+self.text,'{}','null','[NaN]','[Infinity]',json.dumps(values[:-1]),json.dumps(values+[0])]
        for index in range(len(values)):
            for value in (True,False,None,1.0,-1,1<<32,'0',[],{}):
                changed=values.copy();changed[index]=value;bad.append(json.dumps(changed))
        for text in bad:
            with self.subTest(text=text[:50]),self.assertRaises((ValueError,TypeError)):
                probe.parse_output(text,self.rows)

    def test_parser_rejects_ids_tags_and_rejection_payloads(self):
        for index,value in ((0,1),(4,0),(8,1),(1,2),(5,2),(9,2),(6,1),(7,1)):
            changed=json.loads(self.text);changed[index]=value
            with self.assertRaises(ValueError):probe.parse_output(json.dumps(changed),self.rows)
        for value in ({'id':0,'kind':'unknown'},dict(self.rows[0],id=True)):
            with self.assertRaises(ValueError):probe.expected_row(value)

    def test_compare_rejects_incomplete_or_any_bit_difference(self):
        for actual in (self.expected[:-1],self.expected+[self.expected[-1]],[[0,1,1,0]]+self.expected[1:],self.expected[:2]+[[2,1,0x3ff00000,0]]):
            with self.assertRaises(ValueError):probe.compare(self.expected,actual)

    def native_text(self,metadata=None,records=None):
        if metadata is None:
            metadata=dict(rounding='FE_TONEAREST',initial_rounding=0,selected_rounding=0,
                          control_name='mxcsr',control=8064,ftz=False,daz=False,runtime_fma=True,
                          preflight_count=probe.PREFLIGHT_COUNT)
        return json.dumps(metadata)+'\n'+'\n'.join(json.dumps(row) for row in (self.expected if records is None else records))+'\n'

    def test_native_valid_metadata_and_records(self):
        metadata,records=probe.parse_native(self.native_text(),self.rows)
        self.assertTrue(metadata['runtime_fma']);self.assertEqual(records,self.expected)
        metadata.update(control_name='fpcr',control=0)
        self.assertEqual(probe.parse_native(self.native_text(metadata),self.rows)[1],self.expected)

    def test_native_rejects_unqualified_environment(self):
        base=json.loads(self.native_text().splitlines()[0])
        changes=(('ftz',True),('ftz',0),('daz',True),('runtime_fma',False),('runtime_fma',1),
                 ('rounding','toward-zero'),('selected_rounding',1),('initial_rounding',-1),
                 ('control',True),('control',1.0),('control',8064|64),('control',8064|32768),
                 ('control',8064|(1<<13)),('control_name','unknown'),('preflight_count',probe.PREFLIGHT_COUNT-1))
        for key,value in changes:
            changed=dict(base);changed[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                probe.parse_native(self.native_text(changed),self.rows)
        for value in ([],dict(base,extra=1),{k:v for k,v in base.items() if k!='ftz'}):
            with self.assertRaises(ValueError):probe.parse_native(self.native_text(value),self.rows)
        for control in ((1<<24),(1<<19),(1<<22),1,2):
            changed=dict(base,control_name='fpcr',control=control)
            with self.assertRaises(ValueError):probe.parse_native(self.native_text(changed),self.rows)

    def test_native_rejects_malformed_records_and_duplicate_keys(self):
        valid=self.native_text()
        for text in ('','null\n'+'\n'.join(valid.splitlines()[1:]),valid+'[]\n','\n'+valid,valid.replace('[0, 1, 0, 0]','[0, true, 0, 0]'),
                     valid.replace('[1, 0, 0, 0]','[1, 0, 0]'),valid.replace('[2, 1,','[0, 1,'),
                     valid.replace('"ftz": false','"ftz": true, "ftz": false')):
            with self.assertRaises(ValueError):probe.parse_native(text,self.rows)
        malformed=[None,{},[0,1,0,0,0],[0,1,0],[0,1,-1,0],[0,1,0,1<<32]]
        for record in malformed:
            with self.assertRaises(ValueError):probe.parse_native(self.native_text(records=[record,*self.expected[1:]]),self.rows)

    def test_bounded_program_shape_and_requested_api(self):
        rows=self.corpus[:probe.CHUNK]
        source=probe.program(rows)
        self.assertEqual(source.count('    IO.print('),(len(rows)+probe.LINE-1)//probe.LINE)
        self.assertIn('F.checked(ah, al, bh, bl, ch, cl)',source)
        self.assertIn('F.Words{high, low}',source)
        for line in source.splitlines():
            if 'IO.print(' in line:self.assertLessEqual(line.count('Fma{'),probe.LINE)
        self.assertEqual(source.count('Fma{'),len(rows)+2)

    def test_native_has_volatile_runtime_and_no_builtin_qualification(self):
        self.assertIn('-fno-builtin-fma',probe.FLAGS)
        self.assertIn('(* volatile runtime_fma)',probe.NATIVE)
        self.assertIn('volatile double va=da, vb=db, vc=dc',probe.NATIVE)
        self.assertIn('fesetround(FE_TONEAREST)',probe.NATIVE)
        self.assertIn('Runtime libm fma preflight',probe.NATIVE)
        self.assertIn('memcpy(&bits,&result,8)',probe.NATIVE)

    def test_candidate_compiler_overrides_inherited_cc_and_rejects_fallback(self):
        compiler={'path':'/recorded/clang','version':'Debian clang version 19.1.7'}
        with patch.dict(probe.os.environ,{'CC':'/unrecorded/compiler'}):
            env=probe.candidate_environment(compiler)
            self.assertEqual(env,{'CC':'/recorded/clang'})
            with tempfile.TemporaryDirectory() as directory:
                process=probe.subprocess.CompletedProcess(['command'],0,'','')
                with patch.object(probe.subprocess,'run',return_value=process) as run:
                    probe.execute(['command'],Path(directory),'compile',env=env)
                self.assertEqual(run.call_args.kwargs['env']['CC'],'/recorded/clang')
        for version in ('gcc 15.0','clang version 13.0','unknown','not a compiler'):
            with self.assertRaises(ValueError):probe.candidate_environment(dict(compiler,version=version))
        self.assertEqual(probe.candidate_environment(dict(compiler,version='Apple clang version 17.0'))['CC'],compiler['path'])

    def test_native_only_never_claims_candidate_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            compiler={'path':'/compiler','version':'clang version 19.1.7','sha256':'compiler'}
            native={'passed':True,'observations':len(self.rows),'compiler':compiler}
            bun={'path':'/bun','version':'1.3.12','sha256':'bun'}
            with patch.object(probe,'BUILD',Path(directory)),patch.object(probe,'checkout'),patch.object(probe,'source_gate',return_value={}),patch.object(probe,'digest',return_value='hash'),patch.object(probe,'compiler_identity',return_value=bun),patch.object(probe,'samples',return_value=[dict(row,labels=[]) for row in self.rows]),patch.object(probe,'native_reference',return_value=native),patch.object(probe,'final_source_gate') as gate,patch.object(sys,'argv',['probe','--bend-source',directory,'--native-only']),contextlib.redirect_stdout(io.StringIO()):
                probe.main()
            report=json.loads((Path(directory)/'binary64-fma-probe/results.json').read_text())
            self.assertIs(report['passed'],False);self.assertEqual(report['lanes'],{})
            self.assertEqual(report['phase'],'native-only-complete');self.assertTrue(report['native']['passed'])
            gate.assert_called_once()

    def test_source_dependencies_include_entire_harness(self):
        self.assertTrue({'src/binary64_fma.bend','tools/binary64_fma_probe.py','tools/binary64_fma_oracle.py',
                         'tests/test_binary64_fma.py','tools/conformance.py','toolchain.json'}<=set(probe.DEPENDENCIES))

    def test_source_drift_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'x').write_text('before')
            hashes={'x':probe.digest(root/'x')}
            with patch.object(probe,'ROOT',root):
                probe.assert_unchanged(hashes)
                (root/'x').write_text('after')
                with self.assertRaisesRegex(ValueError,'drift'):probe.assert_unchanged(hashes)

    def test_successful_compile_cannot_reuse_stale_or_partial_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);binary=work/'candidate';js=work/'candidate.js'
            binary.write_text('old binary');js.write_text('old js')
            with patch.object(probe,'execute',return_value=''):
                with self.assertRaisesRegex(ValueError,'fresh nonempty'):probe.compile_fresh(['compiler'],[binary,js],work,'compile')
            self.assertFalse(binary.exists());self.assertFalse(js.exists())
            def partial(*args,**kwargs):binary.write_text('new binary')
            with patch.object(probe,'execute',side_effect=partial):
                with self.assertRaisesRegex(ValueError,'fresh nonempty'):probe.compile_fresh(['compiler'],[binary,js],work,'compile')

    def test_execute_retains_failure_and_timeout_output(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory)
            with self.assertRaisesRegex(ValueError,'exited 4'):
                probe.execute([sys.executable,'-c','import sys; print("out"); print("err",file=sys.stderr); sys.exit(4)'],work,'failure')
            self.assertEqual((work/'failure.stdout').read_text(),'out\n')
            self.assertEqual((work/'failure.stderr').read_text(),'err\n')
            error=probe.subprocess.TimeoutExpired('command',1,output=b'partial-out',stderr=b'partial-err')
            with patch.object(probe.subprocess,'run',side_effect=error),self.assertRaises(probe.subprocess.TimeoutExpired):
                probe.execute(['command'],work,'timeout')
            self.assertEqual((work/'timeout.stdout').read_text(),'partial-out')
            self.assertEqual((work/'timeout.stderr').read_text(),'partial-err')

    def test_final_toolchain_and_compiler_drift_fail_closed(self):
        lock={'bend':{'revision':'pinned','patch':{'sha256':'overlay'}}}
        with patch.object(probe,'assert_unchanged'),patch.object(probe,'checkout',side_effect=ValueError('overlay drift')) as check:
            with self.assertRaisesRegex(ValueError,'overlay drift'):probe.final_source_gate({},Path('/compiler'),lock)
        check.assert_called_once_with(Path('/compiler'),'pinned',{'sha256':'overlay'})
        with patch.object(probe,'assert_unchanged'),patch.object(probe,'checkout'),patch.object(probe,'compiler_identity',return_value={'sha256':'new'}):
            with self.assertRaisesRegex(ValueError,'executable drift'):
                probe.final_source_gate({},Path('/compiler'),lock,{'clang':('clang',{'sha256':'old'})},Path('/work'))

    def test_stale_success_invalidated_before_dependency_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory)/'binary64-fma-probe';work.mkdir()
            result=work/'results.json';result.write_text('{"passed":true}')
            with patch.object(probe,'BUILD',Path(directory)),patch.object(probe,'checkout',side_effect=ValueError('pin failure')),patch.object(sys,'argv',['probe','--bend-source',directory]),contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError,'pin failure'):probe.main()
            report=json.loads(result.read_text())
            self.assertIs(report['passed'],False);self.assertEqual(report['lanes'],{})
            self.assertEqual(report['error'],'pin failure')


if __name__=='__main__':
    unittest.main()
