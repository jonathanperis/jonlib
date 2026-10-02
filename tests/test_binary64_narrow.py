import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import binary64_narrow_probe as probe
import binary64_narrow_oracle as oracle


class Binary64NarrowTests(unittest.TestCase):
    def setUp(self):
        self.rows = [dict(id=0,kind='narrow',high=0,low=0),
                     dict(id=1,kind='narrow',high=0x7ff00000,low=0),
                     dict(id=2,kind='jam',high=0,low=1,count=1),
                     dict(id=3,kind='round',value=12)]
        self.expected = [probe.expected_row(row) for row in self.rows]
        self.text = json.dumps([word for row in self.expected for word in row])+'\n'

    def test_hand_boundaries_and_signs(self):
        for high, low, expected in probe.HAND:
            self.assertEqual(oracle.nearest(high,low),expected)
            self.assertEqual(oracle.nearest(high|0x80000000,low),expected|0x80000000)

    def test_special_zero_and_extremes(self):
        for sign in (0,0x80000000):
            self.assertEqual(oracle.nearest(sign,0),sign)
            self.assertEqual(oracle.nearest(sign,1),sign)
            self.assertEqual(oracle.nearest(sign|0x000fffff,0xffffffff),sign)
            self.assertEqual(oracle.nearest(sign|0x7fefffff,0xffffffff),sign|0x7f800000)
            for fraction in (0,1,0x80000,0xfffff):
                self.assertIsNone(oracle.nearest(sign|0x7ff00000|fraction,0xffffffff))

    def test_invalid_words_fail(self):
        for value in (-1,1<<32,True,0.0,'0',None):
            with self.assertRaises(ValueError): oracle.nearest(value,0)
            with self.assertRaises(ValueError): oracle.nearest(0,value)
        with self.assertRaises(ValueError): oracle.positive32(0x7f800001)

    def test_exact_neighbor_ties(self):
        for lower in (0,1,2,0x7ffffe,0x7fffff,0x800000,0x3f800000,0x3f800001,0x7f7fffff):
            midpoint=(oracle.positive32(lower)+oracle.positive32(lower+1))/2
            bits=probe.rational64(midpoint)
            for delta,expected in ((-1,lower),(0,lower+(lower%2)),(1,lower+1)):
                word=bits+delta
                self.assertEqual(oracle.nearest(word>>32,word&0xffffffff),expected)

    def test_corpus_is_deterministic_and_covers_partitions(self):
        rows=probe.samples()
        self.assertEqual(rows,probe.samples())
        self.assertEqual([r['id'] for r in rows],list(range(len(rows))))
        finite=[r for r in rows if r['kind']=='narrow' and (r['high']>>20)&2047 != 2047]
        for sign in (0,1):
            self.assertEqual({(r['high']>>20)&2047 for r in finite if r['high']>>31==sign},set(range(2047)))
        self.assertTrue(any('finite32-promote-narrow' in r['labels'] for r in rows))
        self.assertEqual({r['count'] for r in rows if r['kind']=='jam'},set(range(66)))
        self.assertGreater(len(rows),30000)

    def test_parser_accepts_complete_records(self):
        self.assertEqual(probe.parse_output(self.text,self.rows),self.expected)
        probe.compare(self.expected,self.expected)

    def test_parser_rejects_malformed_truncated_extra_and_wrong_types(self):
        values=json.loads(self.text)
        bad=['',self.text+'\n',self.text+self.text,'noise\n'+self.text,'{}','null','[NaN]',json.dumps(values[:-1]),json.dumps(values+[0])]
        for value in (True,False,None,1.0,-1,1<<32,'0',[],{}):
            changed=values.copy();changed[0]=value;bad.append(json.dumps(changed))
        for text in bad:
            with self.subTest(text=text[:50]), self.assertRaises((ValueError,TypeError)):
                probe.parse_output(text,self.rows)

    def test_parser_rejects_reordering_tags_and_noncanonical_payloads(self):
        for index,value in ((0,1),(1,2),(6,1),(7,1),(13,1),(15,1)):
            changed=json.loads(self.text);changed[index]=value
            with self.assertRaises(ValueError): probe.parse_output(json.dumps(changed),self.rows)

    def test_comparison_rejects_missing_extra_and_mismatch(self):
        for actual in (self.expected[:-1],self.expected+[self.expected[-1]],[[0,1,1,0]]+self.expected[1:]):
            with self.assertRaises(ValueError): probe.compare(self.expected,actual)

    def native_text(self, metadata=None):
        if metadata is None:
            metadata=dict(rounding='FE_TONEAREST',initial_rounding=0,selected_rounding=0,control_name='mxcsr',control=8064,ftz=False,daz=False)
        return json.dumps(metadata)+'\n'+'\n'.join(json.dumps(row) for row in self.expected[:2])+'\n'

    def test_native_metadata_and_records(self):
        metadata,records=probe.parse_native(self.native_text(),self.rows[:2])
        self.assertFalse(metadata['ftz']);self.assertEqual(records,self.expected[:2])
        for key,value in (('ftz',True),('daz',True),('rounding','toward-zero'),('control',8064|64),('control',8064|32768),('control',8064|(1<<13)),('selected_rounding',1),('control',True),('control_name','unknown')):
            changed=json.loads(self.native_text().splitlines()[0]);changed[key]=value
            with self.assertRaises(ValueError): probe.parse_native(self.native_text(changed),self.rows[:2])
        for text in (self.native_text()+'[]\n',self.native_text().replace('[0, 1, 0, 0]','[0, true, 0, 0]'),self.native_text().replace('[1, 0, 0, 0]','[1, 0, 0]')):
            with self.assertRaises(ValueError): probe.parse_native(text,self.rows[:2])

    def test_source_drift_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'x').write_text('before')
            hashes={'x':probe.digest(root/'x')}
            with patch.object(probe,'ROOT',root):
                probe.assert_unchanged(hashes)
                (root/'x').write_text('after')
                with self.assertRaisesRegex(ValueError,'drift'): probe.assert_unchanged(hashes)

    def test_successful_compile_cannot_reuse_stale_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); binary=work/'candidate'; js=work/'candidate.js'
            binary.write_text('old binary'); js.write_text('old js')
            with patch.object(probe,'execute',return_value=''):
                with self.assertRaisesRegex(ValueError,'fresh nonempty'):
                    probe.compile_fresh(['compiler'],[binary,js],work,'compile')
            self.assertFalse(binary.exists()); self.assertFalse(js.exists())
            def partial(*args): binary.write_text('new binary')
            with patch.object(probe,'execute',side_effect=partial):
                with self.assertRaisesRegex(ValueError,'fresh nonempty'):
                    probe.compile_fresh(['compiler'],[binary,js],work,'compile')

    def test_final_toolchain_drift_fails_closed(self):
        report={'passed':False}
        lock={'bend':{'revision':'pinned','patch':{'sha256':'overlay'}}}
        with patch.object(probe,'assert_unchanged'), patch.object(probe,'checkout',side_effect=ValueError('overlay drift')) as check:
            with self.assertRaisesRegex(ValueError,'overlay drift'):
                probe.final_source_gate({},Path('/compiler'),lock)
                report['passed']=True
        self.assertIs(report['passed'],False)
        check.assert_called_once_with(Path('/compiler'),'pinned',{'sha256':'overlay'})

    def test_stale_success_invalidated_before_dependency_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory)/'binary64-narrow-probe';work.mkdir()
            result=work/'results.json';result.write_text('{"passed":true}')
            with patch.object(probe,'BUILD',Path(directory)), patch.object(probe,'checkout',side_effect=ValueError('pin failure')), patch.object(sys,'argv',['probe','--bend-source',directory]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError,'pin failure'): probe.main()
            report=json.loads(result.read_text())
            self.assertIs(report['passed'],False)
            self.assertEqual(report['lanes'],{})
            self.assertEqual(report['error'],'pin failure')


if __name__=='__main__':
    unittest.main()
