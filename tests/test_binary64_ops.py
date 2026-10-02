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
import binary64_ops_probe as probe
import binary64_ops_oracle as oracle


class Binary64OpsTests(unittest.TestCase):
    @staticmethod
    def result(kind, a, b=0):
        result = oracle.checked(kind, *(part for value in (a, b) for part in (value>>32, value&0xffffffff)))
        return None if result is None else (result[0]<<32)|result[1]

    @classmethod
    def setUpClass(cls):
        cls.corpus = probe.samples()
        cls.corpus_expected = [probe.expected_row(row) for row in cls.corpus]

    def setUp(self):
        self.rows = [dict(id=0, kind='mul', ah=0, al=0, bh=0, bl=0),
                     dict(id=1, kind='div', ah=0x7ff00000, al=0, bh=0, bl=0),
                     dict(id=2, kind='div', ah=0x3ff00000, al=1, bh=0x3ff00000, bl=0)]
        self.expected = [probe.expected_row(row) for row in self.rows]
        self.text = json.dumps([word for row in self.expected for word in row])+'\n'

    def test_fixed_product_ties_carry_and_quotient_controls(self):
        for kind, a, b, expected, label in probe.HAND:
            with self.subTest(label=label):
                self.assertEqual(self.result(kind, a, b), expected)
                for sa in (0, oracle.SIGN):
                    for sb in (0, oracle.SIGN):
                        self.assertEqual(self.result(kind, a^sa, b^sb), expected^sa^sb)
                        if kind == 'mul': self.assertEqual(self.result(kind, b^sb, a^sa), expected^sa^sb)

    def test_signed_zero_validates_both_inputs_before_shortcuts(self):
        for sa in (0, oracle.SIGN):
            for sb in (0, oracle.SIGN):
                self.assertEqual(self.result('mul', sa, sb), sa^sb)
                self.assertEqual(self.result('div', sa, probe.normal(0)^sb), sa^sb)
                self.assertIsNone(self.result('div', sa, sb))
                for kind in ('mul', 'div'):
                    for bad in (1, oracle.FRACTION, 0x7ff0000000000000, 0x7ff8000000000001):
                        self.assertIsNone(self.result(kind, sa, bad^sb))
                        self.assertIsNone(self.result(kind, bad^sa, sb))

    def test_multiply_operand_and_pair_exponent_boundaries(self):
        for ea, eb, accepted in ((-554,-279,True),(-554,-280,False),(-416,-417,True),
                                 (127,0,True),(127,1,False),(-554,127,True),(-555,0,False),(128,-1,False)):
            for f in (0, 1, oracle.FRACTION):
                for sa in (0, 1):
                    for sb in (0, 1):
                        a,b=probe.normal(ea,f,sa),probe.normal(eb,f,sb)
                        self.assertEqual(self.result('mul',a,b) is not None,accepted)
                        self.assertEqual(self.result('mul',b,a) is not None,accepted)
        self.assertEqual(self.result('mul',probe.normal(-554),probe.normal(-279)),probe.normal(-833))
        self.assertEqual(self.result('mul',probe.normal(127,oracle.FRACTION),probe.normal(0,oracle.FRACTION)),
                         probe.normal(128,oracle.FRACTION-1))

    def test_divide_operand_pair_and_zero_divisor_boundaries(self):
        for ea,eb,accepted in ((-225,-149,True),(-225,127,True),(-226,127,False),(-225,-150,False),
                               (-149,-149,True),(0,0,True),(1,0,False),(127,127,True),(127,128,False)):
            for f in (0,1,oracle.FRACTION):
                self.assertEqual(self.result('div',probe.normal(ea,f),probe.normal(eb,f)) is not None,accepted)
        self.assertEqual(self.result('div',probe.normal(-225),probe.normal(127)),probe.normal(-352))
        self.assertEqual(self.result('div',probe.normal(0),probe.normal(0,oracle.FRACTION)),0x3fe0000000000001)
        for numerator in (0,oracle.SIGN,probe.normal(0),probe.normal(-225)):
            for denominator in (0,oracle.SIGN): self.assertIsNone(self.result('div',numerator,denominator))

    def test_checked_entrypoint_aliases(self):
        for fields in ((0,0,0x3ff00000,0),(0x3ff00000,1,0x3ff80000,0),(0x7ff00000,0,0,0)):
            self.assertEqual(oracle.checked_multiply(*fields),oracle.checked('mul',*fields))
            self.assertEqual(oracle.checked_divide(*fields),oracle.checked('div',*fields))

    def test_identity_and_finite_have_distinct_subnormal_contracts(self):
        for bits in (0,oracle.SIGN,probe.normal(-1022),probe.normal(1023,oracle.FRACTION,1)):
            self.assertEqual(self.result('identity',bits),bits)
            self.assertEqual(self.result('finite',bits),bits)
        for bits in (1,oracle.FRACTION,oracle.SIGN|1,oracle.SIGN|oracle.FRACTION):
            self.assertIsNone(self.result('identity',bits))
            self.assertEqual(self.result('finite',bits),bits)
        for bits in (0x7ff0000000000000,0xfff0000000000000,0x7ff0000000000001,0xfff8000000000000):
            self.assertIsNone(self.result('identity',bits)); self.assertIsNone(self.result('finite',bits))

    def test_promotion_exact_direct_known_encodings_and_rejections(self):
        pairs=((0,0),(0x80000000,oracle.SIGN),(1,0x36a0000000000000),
               (0x007fffff,0x380fffffc0000000),(0x00800000,0x3810000000000000),
               (0x3f800001,0x3ff0000020000000),(0x7f7fffff,0x47efffffe0000000))
        for bits,expected in pairs:
            self.assertEqual(self.result('promote',bits),expected)
            if bits < 0x80000000: self.assertEqual(self.result('promote',bits|0x80000000),expected|oracle.SIGN)
        for bits in (0x7f800000,0xff800000,0x7f800001,0x7fc00000,0xffffffff):
            self.assertIsNone(self.result('promote',bits)); self.assertIsNone(oracle.decode32(bits))
        for row,expected in zip(self.corpus,self.corpus_expected):
            if row['kind']=='promote' and expected[2]:
                self.assertEqual(oracle.decode64(*expected[3:]),oracle.decode32(row['al']))

    def test_raw_word_helpers_carry_borrow_sign_and_special_encodings(self):
        for bits in (0,1,0xffffffff,0x100000000,0x7fffffffffffffff,oracle.SIGN,
                     0x80000000ffffffff,0x8000000100000000,0x7ff0000000000000,0xffffffffffffffff):
            self.assertEqual(self.result('negate',bits),bits^oracle.SIGN)
            self.assertEqual(self.result('increment',bits),(bits+1)&oracle.MASK64)
            self.assertEqual(self.result('decrement',bits),(bits-1)&oracle.MASK64)
            self.assertEqual(self.result('magnitude',bits,bits^oracle.SIGN),0)
        self.assertEqual(self.result('magnitude',0,1),1)
        self.assertEqual(self.result('magnitude',oracle.SIGN|2,1),2)

    def test_numerical_equality_is_finite_only_and_zero_sign_insensitive(self):
        for a in (0,oracle.SIGN):
            for b in (0,oracle.SIGN): self.assertEqual(self.result('equal',a,b),1)
        for a in (1,oracle.SIGN|1,probe.normal(0),probe.normal(1023,oracle.FRACTION)):
            self.assertEqual(self.result('equal',a,a),1)
            self.assertEqual(self.result('equal',a,a^oracle.SIGN),0)
        for a in (0x7ff0000000000000,0xfff0000000000000,0x7ff0000000000001,0xfff8000000000000):
            for b in (a,a^oracle.SIGN,0,oracle.SIGN): self.assertEqual(self.result('equal',a,b),0)

    def test_checked_power_uses_stored_exponents(self):
        for e in range(1,2047): self.assertEqual(self.result('power',e),e<<52)
        for e in (0,2047,2048,0x7fffffff,0x80000000,0xffffffff): self.assertIsNone(self.result('power',e))

    def test_invalid_words_kind_and_reserved_input_fields(self):
        for kind in oracle.KINDS:
            for field in range(4):
                for bad in (-1,1<<32,True,False,0.0,'0',None):
                    fields=[0]*4; fields[field]=bad
                    with self.assertRaises(ValueError): oracle.checked(kind,*fields)
        for kind in ('add','multiply','',0,True,None,[]):
            with self.assertRaises(ValueError): oracle.checked(kind,0,0,0,0)
        for kind in set(oracle.KINDS)-oracle.BINARY_KINDS:
            with self.assertRaises(ValueError): oracle.checked(kind,0,0,1,0)
            with self.assertRaises(ValueError): oracle.checked(kind,0,0,0,1)
        for kind in oracle.SCALAR_KINDS:
            with self.assertRaises(ValueError): oracle.checked(kind,1,0,0,0)
        for params in ((-1023,0,0),(1024,0,0),(0,-1,0),(0,1<<52,0),(0,0,2),(True,0,0),(0,True,0),(0,0,True)):
            with self.assertRaises(ValueError): probe.normal(*params)
        for bits in (-1,1<<32,True,None):
            with self.assertRaises(ValueError): oracle.decode32(bits)

    def test_internal_generic_rounder_synthetic_midpoints_not_division_claims(self):
        # These exact rational midpoints qualify the shared rounder only. No
        # normal-binary64 quotient corpus vector is described as a reachable tie.
        for lower in (0,1,2,(1<<52)-1,1<<52,0x3fefffffffffffff,0x3ff0000000000000,
                      0x3ff0000000000001,oracle.MAX_FINITE):
            left,right=oracle.positive64(lower),oracle.positive64(lower+1)
            middle=(left+right)/2
            for value,expected in ((left,lower),((left+middle)/2,lower),(middle,lower+lower%2),
                                   ((middle+right)/2,lower+1),(right,lower+1)):
                for sign in (0,oracle.SIGN):
                    self.assertEqual(oracle.nearest64(-value if sign else value,sign),expected|sign)

    def test_reachable_quotient_midpoint_distances_both_sides_and_parities(self):
        seen=set()
        for a,b,lower,side in probe.NEAR_MIDPOINT:
            av,bv=oracle.decode64(a>>32,a&0xffffffff),oracle.decode64(b>>32,b&0xffffffff)
            q=av/bv; left,right=oracle.positive64(lower),oracle.positive64(lower+1)
            offset=(q-(left+right)/2)/(right-left)
            denominator=(1<<52)+(b&oracle.FRACTION)
            self.assertEqual(offset,Fraction(side,2*denominator))
            self.assertEqual(self.result('div',a,b),lower+(side>0))
            seen.add((side,lower%2))
            label=f'quotient-near-midpoint-side-{side}-lower-parity-{lower % 2}'
            selected=[r for r in self.corpus if label in r['labels']]
            self.assertEqual(len(selected),16)
            for row in selected:
                numerator=(row['ah']<<32)|row['al']; denominator=(row['bh']<<32)|row['bl']
                q=abs(oracle.decode64(row['ah'],row['al'])/oracle.decode64(row['bh'],row['bl']))
                shift=oracle.exponent(numerator)-oracle.exponent(denominator)
                lo=lower+(shift<<52)
                l,r=oracle.positive64(lo),oracle.positive64(lo+1)
                self.assertEqual((q-(l+r)/2)/(r-l),offset)
        self.assertEqual(seen,{(-1,0),(-1,1),(1,0),(1,1)})

    def test_division_corpus_contains_no_reachable_midpoint(self):
        for row,expected in zip(self.corpus,self.corpus_expected):
            if row['kind']!='div' or not expected[2] or not ((row['ah']&0x7fffffff)|row['al']): continue
            a,b=oracle.decode64(row['ah'],row['al']),oracle.decode64(row['bh'],row['bl'])
            q=abs(a/b); bits=((expected[3]<<32)|expected[4])&~oracle.SIGN
            rounded=oracle.positive64(bits)
            neighbor=oracle.positive64(bits+1 if q>rounded else bits-1)
            self.assertNotEqual(q,(rounded+neighbor)/2)

    def test_corpus_is_deterministic_complete_and_declared(self):
        self.assertEqual(self.corpus,probe.samples())
        self.assertEqual([r['id'] for r in self.corpus],list(range(len(self.corpus))))
        self.assertEqual(len(self.corpus),36176)
        self.assertEqual(set(r['kind'] for r in self.corpus),set(oracle.KINDS))
        self.assertEqual(probe.CHUNK,256); self.assertEqual(probe.LINE,16)
        self.assertEqual(len({(r['kind'],*(r[f] for f in probe.FIELDS)) for r in self.corpus}),len(self.corpus))
        for row,result in zip(self.corpus,self.corpus_expected):
            if row['kind'] in ('mul','div') and result[2] and result[3]&0x7fffffff:
                self.assertNotIn((result[3]>>20)&2047,(0,2047))

    def test_all_arithmetic_exponents_signs_operands_accepted(self):
        for kind,bounds in (('mul',(oracle.MUL_BOUNDS,oracle.MUL_BOUNDS)),('div',oracle.DIV_BOUNDS)):
            for operand,(low,high) in enumerate(bounds):
                label=f'every-{ "multiply" if kind=="mul" else "divide"}-exponent-sign-operand-{operand}'
                selected=[row for row in self.corpus if label in row['labels']]
                fields=probe.FIELDS[2*operand:2*operand+2]
                observed={(((r[fields[0]]>>20)&2047)-1023,r[fields[0]]>>31) for r in selected}
                self.assertEqual(observed,{(e,s) for e in range(low,high+1) for s in (0,1)})
                self.assertTrue(all(probe.expected_row(r)[2] for r in selected))

    def test_adapter_promotion_power_and_significand_strata(self):
        for kind in ('identity','finite'):
            rows=[r for r in self.corpus if r['kind']==kind and 'all-binary64-normal-exponents-and-signs' in r['labels']]
            self.assertEqual({((r['ah']>>20)&2047,r['ah']>>31) for r in rows},{(e,s) for e in range(1,2047) for s in (0,1)})
        rows=[r for r in self.corpus if 'all-finite-binary32-exponents-and-signs' in r['labels']]
        self.assertEqual({((r['al']>>23)&255,r['al']>>31) for r in rows},{(e,s) for e in range(255) for s in (0,1)})
        labels={label for r in self.corpus for label in r['labels']}
        for prefix,n in (('product-significand-bit-',52),('quotient-significand-bit-',52),
                         ('promotion-subnormal-leading-bit-',23),('promotion-fraction-bit-',23)):
            self.assertTrue({prefix+str(i) for i in range(n)}<=labels)
        for kind in ('mul','div'):
            for operand in (0,1):
                rows=[r for r in self.corpus if f'reject-invalid-{kind}-operand-{operand}' in r['labels']]
                self.assertTrue(rows)
                self.assertTrue(all(probe.expected_row(r)[2:]==[0,0,0] for r in rows))

    def test_scalar_and_unconditional_result_parser_contracts(self):
        for kind in ('magnitude','equal'):
            row=dict(id=0,kind=kind,ah=0,al=0,bh=0,bl=0)
            for tag,high,low in ((0,0,0),(1,1,0),(1,0,3)):
                with self.assertRaises(ValueError): probe.parse_output(json.dumps([0,oracle.KINDS[kind],tag,high,low]),[row])
        for kind in ('negate','increment','decrement'):
            row=dict(id=0,kind=kind,ah=0,al=0,bh=0,bl=0)
            with self.assertRaises(ValueError): probe.parse_output(json.dumps([0,oracle.KINDS[kind],0,0,0]),[row])

    def test_bounded_program_shape_and_all_requested_entrypoints(self):
        selected=[]
        for kind in oracle.KINDS: selected.append(next(row for row in self.corpus if row['kind']==kind))
        source=probe.program(selected)
        for name in ('checked_multiply','checked_divide','checked_identity','checked_promote','checked_finite',
                     'negate','magnitude_order','numerical_equal','increment','decrement','checked_power'):
            self.assertIn('O.'+name+'(',source)
        self.assertIn('F.Words{high, low}',source)
        rows=self.corpus[:probe.CHUNK]; source=probe.program(rows)
        self.assertEqual(source.count('    IO.print('),(len(rows)+probe.LINE-1)//probe.LINE)
        for line in source.splitlines():
            if 'IO.print(' in line:
                self.assertLessEqual(sum(line.count(kind.title()+'{') for kind in oracle.KINDS),probe.LINE)
        for rows in ([],self.corpus[:probe.CHUNK+1]):
            with self.assertRaisesRegex(ValueError,'1..256'): probe.program(rows)

    def test_runtime_native_controls_qualify_ties_signs_subnormals_and_casts(self):
        self.assertEqual(probe.PREFLIGHT_COUNT,32)
        for kind,a,b,expected in probe.NATIVE_CONTROLS:
            x=oracle.decode32(a) if kind==3 else oracle.decode64(a>>32,a&0xffffffff)
            y=0 if kind==3 else oracle.decode64(b>>32,b&0xffffffff)
            exact=x if kind==3 else x*y if kind==0 else x/y
            sign=(oracle.SIGN if a>>31 else 0) if kind==3 else (a^b)&oracle.SIGN
            self.assertEqual(oracle.nearest64(exact,sign),expected)
        for text in ('(* volatile runtime_mul)','(* volatile runtime_div)','(* volatile runtime_promote)',
                     'volatile double va=a, vb=b','volatile float va=a','fesetround(FE_TONEAREST)',
                     'Runtime mul/div/promote preflight','memcpy(&bits,&result,8)','FLT_EVAL_METHOD == 0',
                     'expof(a)+expof(b)<-833','expof(a)>expof(b)'):
            self.assertIn(text,probe.NATIVE)
        self.assertIn('-fno-fast-math',probe.FLAGS); self.assertIn('-frounding-math',probe.FLAGS)

    def test_native_layout_and_promotion_qualification_is_strict(self):
        base=json.loads(self.native_text().splitlines()[0])
        for key,value in (('runtime_promote',False),('runtime_promote',1),('char_bit',True),('char_bit',16),
                          ('double_bytes',4),('float_bytes',8),('double_mantissa',64),('float_mantissa',53),
                          ('float_eval_method',1),('one_bits','0000000000000000')):
            with self.subTest(key=key),self.assertRaises(ValueError):
                probe.parse_native(self.native_text(dict(base,**{key:value})),self.rows)
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
                            control_name='mxcsr', control=8064, ftz=False, daz=False, runtime_mul=True,
                            runtime_div=True, runtime_promote=True, binary64_evaluation=True, preflight_count=probe.PREFLIGHT_COUNT,
                            char_bit=8, double_bytes=8, float_bytes=4, double_mantissa=53, float_mantissa=24,
                            float_eval_method=0, one_bits='3ff0000000000000')
        return json.dumps(metadata)+'\n'+'\n'.join(json.dumps(row) for row in (self.expected if records is None else records))+'\n'

    def test_native_valid_metadata_and_records(self):
        metadata, records = probe.parse_native(self.native_text(), self.rows)
        self.assertTrue(metadata['runtime_mul']); self.assertTrue(metadata['runtime_div'])
        self.assertEqual(records, self.expected)
        metadata.update(control_name='fpcr', control=0)
        self.assertEqual(probe.parse_native(self.native_text(metadata), self.rows)[1], self.expected)

    def test_native_rejects_unqualified_environment(self):
        base = json.loads(self.native_text().splitlines()[0])
        changes = (('ftz', True), ('ftz', 0), ('daz', True), ('runtime_mul', False), ('runtime_mul', 1),
                   ('runtime_div', False), ('runtime_div', 1), ('binary64_evaluation', False),
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
            report = json.loads((Path(directory)/'binary64-ops-probe/results.json').read_text())
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
            report = json.loads((Path(directory)/'binary64-ops-probe/results.json').read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})

    def test_source_dependencies_include_entire_harness_and_shared_oracle(self):
        self.assertTrue({'src/binary64_ops.bend', 'src/binary64_fma.bend', 'tools/binary64_ops_probe.py',
                         'tools/binary64_ops_oracle.py', 'tools/binary64_fma_oracle.py',
                         'tests/test_binary64_ops.py', 'tools/conformance.py', 'toolchain.json',
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
            work = Path(directory)/'binary64-ops-probe'; work.mkdir()
            result = work/'results.json'; result.write_text('{"passed":true}')
            with patch.object(probe, 'BUILD', Path(directory)), patch.object(probe, 'checkout', side_effect=ValueError('pin failure')), patch.object(sys, 'argv', ['probe', '--bend-source', directory]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'pin failure'): probe.main()
            report = json.loads(result.read_text())
            self.assertIs(report['passed'], False); self.assertEqual(report['lanes'], {})
            self.assertEqual(report['error'], 'pin failure')


if __name__ == '__main__':
    unittest.main()
