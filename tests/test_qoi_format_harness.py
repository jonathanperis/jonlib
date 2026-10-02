import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import qoi_format_probe as probe


class QoiFormatHarnessTests(unittest.TestCase):
    def setUp(self):
        self.case=dict(id='test',width=1,height=1,channels=3,space=0,bytes=probe.stream(1,1,3,0,[192]),extended=False)
        self.action=dict(case=self.case,role='raw')
        self.row=probe.meta(self.case,'raw')

    def encoded(self,row=None,parts=None):
        return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,*([[1,2,3],'end'] if parts is None else parts)])+'\n'

    def test_complete_raw_bytes(self):
        self.assertEqual(probe.parse_rows(self.encoded(),[self.action]),[dict(self.row,bytes=[1,2,3])])
        rgba=dict(self.case,channels=4)
        action=dict(case=rgba,role='raw')
        self.assertEqual(probe.parse_rows(self.encoded(probe.meta(rgba,'raw'),[[1,2,3,4],'end']),[action])[0]['format'],7)

    def test_metadata_is_exact_and_typed(self):
        for key,value in [('id','other'),('role','bridge'),('width',2),('height',2),('format',7),('mipmaps',2),('width',True),('height',1.0),('mipmaps',True),('format',4.0),('extra',1)]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                probe.parse_rows(self.encoded(dict(self.row,**{key:value})),[self.action])
        for key in self.row:
            row=self.row.copy();del row[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):probe.parse_rows(self.encoded(row),[self.action])

    def test_bad_framing_fails_closed(self):
        for text in ('',self.encoded().replace('"end"\n',''),self.encoded()+self.encoded(),self.encoded()+json.dumps('end'),self.encoded(parts=['end']),self.encoded(parts=[[1,2],'end']),self.encoded(parts=[[1,2,3,4],'end']),self.encoded(parts=[[],'end']),self.encoded(parts=[[0]*257,'end']),self.encoded(parts=[None]),self.encoded(parts=[[True,2,3],'end']),self.encoded(parts=[[1,2,256],'end']),self.encoded(parts=[[1,2,-1],'end'])):
            with self.subTest(text=text[:90]),self.assertRaises(ValueError):probe.parse_rows(text,[self.action])

    def test_chunk_boundaries_keep_all_bytes(self):
        case=dict(self.case,width=86)
        text=self.encoded(probe.meta(case,'raw'),[[i%256 for i in range(256)],[0,1],'end'])
        self.assertEqual(len(probe.parse_rows(text,[dict(case=case,role='raw')])[0]['bytes']),258)

    def test_duplicate_fields_rejected(self):
        with self.assertRaises(ValueError):probe.strict_json('{"format":4,"format":7}')

    def test_error_records_are_exact(self):
        c=probe.controls()[0];action=dict(case=c,role='error')
        row=dict(id=c['id'],role='error',error=c['error'])
        self.assertEqual(probe.parse_rows(json.dumps(row),[action]),[row])
        for wrong in (99,True,0.0):
            with self.assertRaises(ValueError):probe.parse_rows(json.dumps(dict(row,error=wrong)),[action])
        with self.assertRaises(ValueError):probe.parse_rows(json.dumps(row)+'\n"end"',[action])

    def test_native_raw_observed_before_normalization(self):
        program=probe.reference_program([self.case],[])
        self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
        self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
        self.assertIn('GetPixelDataSize(image.width,image.height,image.format)',program)
        self.assertIn('image.mipmaps',program)
        self.assertNotIn('LoadImageColors',program)
        self.assertEqual(program.count('UnloadImage(image)'),1)

    def test_native_rejections_never_use_short_backing_or_huge_sizes(self):
        rejected=[c for c in probe.controls() if c['native']]
        self.assertEqual(len(rejected),8)
        for c in rejected:
            self.assertGreaterEqual(len(c['bytes']),22)
            self.assertLessEqual(int.from_bytes(bytes(c['bytes'][4:8]),'big'),1)
            self.assertLessEqual(int.from_bytes(bytes(c['bytes'][8:12]),'big'),1)
        with self.assertRaises(ValueError):probe.reference_program([],[dict(id='unsafe',bytes=[0])])
        self.assertIn('if(image.data)',probe.reference_program([],rejected))

    def test_fixture_coverage_and_independent_discriminators(self):
        cases=probe.fixtures();by_id={c['id']:c for c in cases}
        self.assertEqual(len(cases),len(by_id))
        self.assertEqual(sum(c['id'].startswith('legacy-') for c in cases),5)
        for channels in (3,4):
            for space in (0,1):
                c=by_id[f'c{channels}-s{space}-hidden-alpha-cache']
                self.assertEqual(c['bytes'][14:-8],[255,12,34,56,0,255,200,100,50,64,22])
                self.assertEqual(c['bytes'][12:14],[channels,space])
                self.assertTrue(c['extended'])
                for name in ('all-diff','luma-boundaries','byte-alpha-ramps','noncanonical-repeated-index','run-inserts-black','row-crossing-run','cache-index0-index63'):
                    self.assertIn(f'c{channels}-s{space}-{name}',by_id)
            for name,shape in [('axis-row',(4096,1)),('axis-column',(1,4096)),('moderate-nonuniform',(81,63))]:
                c=by_id[f'c{channels}-{name}'];self.assertEqual((c['width'],c['height']),shape)
        controls={c['id']:c for c in probe.controls()}
        for name in ('run-overflow-first','run-overflow-62','run-overflow-late'):
            self.assertEqual(controls[name]['error'],4)
            self.assertFalse(controls[name]['native'])
        self.assertEqual(controls['bad-byte-before-bad-header']['error'],1)
        self.assertEqual(controls['marker-absorbed-255']['error'],4)

    def test_candidate_ownership_and_error_routes(self):
        c=dict(self.case,extended=True)
        actions=[dict(case=c,role=r,expected=dict(bytes=[0,0,0])) for r in ('raw','bridge','surface','dispatch','upper','uncontracted','fused','factory','owner')]
        actions += [dict(case=probe.controls()[0],role='error',mode=mode) for mode in ('formatted','surface')]
        program=probe.candidate_program(actions)
        for call in ('J.Image.Formatted.decode_qoi','J.Image.Formatted.to_surface','J.Surface.to_formatted','J.Image.Formatted.get','J.Image.Formatted.from_bytes','J.Surface.decode_qoi','J.Surface.decode_image(', 'J.UncontractedDecode{}','J.FusedDecode{}'):
            self.assertIn(call,program)
        self.assertIn('word <= 16777215',program)
        self.assertIn('formatted.error(J.Image.Formatted.decode_qoi',program)
        self.assertIn('surface.error(J.Surface.decode_qoi',program)
        self.assertIn('J.Image.Formatted.export(image)',program)

    def test_comparison_reports_every_difference(self):
        rows=[dict(self.row,bytes=[1,2,3]),dict(self.row,bytes=[4,5,6])]
        actual=[dict(self.row,bytes=[1,9,3]),dict(self.row,bytes=[9,5,6])]
        self.assertEqual([v['first_byte'] for v in probe.differences(rows,actual)],[1,0])
        with self.assertRaises(ValueError):probe.differences(rows,actual[:1])


if __name__=='__main__':unittest.main()
