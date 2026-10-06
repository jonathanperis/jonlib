import copy
import json
import hashlib
import runpy
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tools.conformance import BUILD, ROOT, cases_from, checkout, compare, parse_output, result_size, source_gate
from tools.resize_conformance import verify_images
from tools.byte_probe import parse_results


class HarnessTests(unittest.TestCase):
    def image_export_probe(self):
        with patch('sys.path', [str(ROOT/'tools'), *sys.path]):
            return runpy.run_path(str(ROOT/'tools/image_export_probe.py'))

    def test_image_export_rejects_incomplete_or_malformed_results(self):
        probe = self.image_export_probe()
        case = dict(id='pixel', status='ok', width=1, height=1, pixels=[0x01020300], codec='png')
        row = dict(id='pixel', status='ok', width=1, height=1, pixels=[0x01020300], bytes=[0, 255])
        closure = dict(closure_checks=True, iterations=100)
        encoded = lambda rows: '\n'.join(map(json.dumps, rows))
        parse = probe['parse_rows']
        self.assertEqual(parse(encoded([row, closure]), [case], candidate=True), [row, closure])
        invalid = [[], [row], [row, row, closure], [row, dict(closure, closure_checks=1)],
                   [row, dict(closure, iterations=99)], [dict(row, id='other'), closure],
                   [dict(row, width=True), closure], [dict(row, height=2), closure],
                   [dict(row, pixels=[]), closure], [dict(row, pixels=[True]), closure],
                   [dict(row, pixels=[0x010203ff]), closure], [dict(row, bytes=[]), closure],
                   [dict(row, bytes=[True]), closure], [dict(row, bytes=[256]), closure],
                   [dict(row, bytes=[-1]), closure], [dict(row, extra=True), closure]]
        for rows in invalid:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                parse(encoded(rows), [case], candidate=True)
        with self.assertRaisesRegex(ValueError, 'comparison result count'):
            probe['compare_rows']([case], [row], [row])
        changed = dict(row, bytes=[0, 254])
        with self.assertRaisesRegex(ValueError, 'bytes/pixels/dispatch'):
            probe['compare_rows']([case], [row], [changed, closure])

    def test_image_export_checks_raw_owner_and_io_error_details(self):
        probe = self.image_export_probe()
        encoded = lambda rows: '\n'.join(map(json.dumps, rows))
        closure = dict(closure_checks=True, iterations=100)
        raw = dict(id='raw', status='ok', width=1, height=1, pixels=[0x01020300], codec='raw')
        raw_row = dict(id='raw', status='ok', bytes=[1, 2, 3, 0])
        owner = dict(raw, id='owner', status='unsupported', codec=None)
        owner_row = dict(id='owner', status='unsupported', width=1, height=1, pixels=[0x01020300])
        error = dict(raw, id='file', status='file')
        error_row = dict(id='file', status='file', code=2, message_empty=0)
        cases, rows = [raw, owner, error], [raw_row, owner_row, error_row, closure]
        self.assertEqual(probe['parse_rows'](encoded(rows), cases, candidate=True), rows)
        for index, bad in [(0, dict(raw_row, bytes=[1, 2, 3, 255])),
                           (0, dict(raw_row, bytes=[1, 2, 3, 0, 0])),
                           (1, dict(owner_row, pixels=[0x010203ff])),
                           (1, dict(owner_row, width=2)),
                           (2, dict(error_row, code=0)), (2, dict(error_row, code=True)),
                           (2, dict(error_row, message_empty=1)),
                           (2, dict(error_row, message_empty=False))]:
            changed = copy.deepcopy(rows)
            changed[index] = bad
            with self.subTest(index=index, bad=bad), self.assertRaises(ValueError):
                probe['parse_rows'](encoded(changed), cases, candidate=True)

    def test_image_export_verifies_complete_files_and_rejected_sentinels(self):
        probe = self.image_export_probe()
        cases = [dict(id='ok', status='ok', path='out.raw'),
                 dict(id='reject', status='unsupported', path='rejected.data'),
                 dict(id='missing', status='file', path='missing-parent/output.png'),
                 dict(id='directory', status='file', path='directory.png')]
        rows = [dict(bytes=[1, 2, 3, 0]), {}, {}, {}]
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='image-export-files-') as directory:
            work = Path(directory)
            probe['prepare_paths'](work, cases)
            (work/'out.raw').write_bytes(bytes(rows[0]['bytes']))
            probe['verify_files'](work, cases, rows)
            for path, data, error in [('out.raw', b'\1\2\3\0extra', 'Complete image-export file'),
                                      ('rejected.data', b'', 'sentinel changed'),
                                      ('directory.png/entry', b'', 'directory control changed'),
                                      ('closure.data', b'', 'closure sentinel changed')]:
                original = (work/path).read_bytes()
                (work/path).write_bytes(data)
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, error):
                    probe['verify_files'](work, cases, rows)
                (work/path).write_bytes(original)
            with self.assertRaisesRegex(ValueError, 'file result count'):
                probe['verify_files'](work, cases, rows[:-1])
            (work/'missing-parent').mkdir()
            with self.assertRaisesRegex(ValueError, 'created missing parent'):
                probe['verify_files'](work, cases, rows)

    def test_image_export_invalidates_previous_success_before_checkout(self):
        main = self.image_export_probe()['main']
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='image-export-negative-') as directory:
            work = Path(directory)
            report = work/'image-export-probe/results.json'
            report.parent.mkdir()
            report.write_text(json.dumps(dict(passed=True)))
            def failed_checkout(*args):
                raise ValueError('forced provenance failure')
            argv = ['image_export_probe.py', '--bend-source', str(work/'bend'), '--raylib-source', str(work/'raylib')]
            with patch.dict(main.__globals__, BUILD=work, checkout=failed_checkout), patch('sys.argv', argv):
                with self.assertRaisesRegex(ValueError, 'forced provenance failure'):
                    main()
            self.assertEqual(json.loads(report.read_text()), dict(passed=False))

    def test_image_export_checks_every_successful_closure_file(self):
        probe = self.image_export_probe()
        reference = {codec: [index, 0, 255] for index, codec in enumerate(probe['CODECS'])}
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='image-export-closure-') as directory:
            work = Path(directory)
            for codec, data in reference.items():
                (work/('closure.'+codec)).write_bytes(bytes(data))
            probe['verify_closure_files'](work, reference)
            for codec in reference:
                path = work/('closure.'+codec)
                path.write_bytes(bytes(reference[codec])+b'\0')
                with self.subTest(codec=codec), self.assertRaisesRegex(ValueError, 'closure file differs'):
                    probe['verify_closure_files'](work, reference)
                path.write_bytes(bytes(reference[codec]))
            with self.assertRaisesRegex(ValueError, 'Incomplete.*closure reference'):
                probe['verify_closure_files'](work, dict(raw=reference['raw']))

    def test_image_export_post_open_limits_are_child_only(self):
        probe = self.image_export_probe()
        resource, signal = probe['resource'], probe['signal']
        with patch.object(resource, 'setrlimit') as limits, patch.object(signal, 'signal') as signals:
            probe['limit_write_failures']()
        self.assertEqual([call.args for call in limits.call_args_list],
                         [(resource.RLIMIT_NOFILE, (64, 64)), (resource.RLIMIT_FSIZE, (0, 0))])
        signals.assert_called_once_with(signal.SIGXFSZ, signal.SIG_IGN)

    def test_image_export_rejects_incomplete_post_open_failure_evidence(self):
        probe = self.image_export_probe()
        marker = probe['write_failure_marker']()
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='image-export-write-failure-') as directory:
            work = Path(directory)
            probe['prepare_write_failure_paths'](work)
            text = json.dumps(marker)
            with self.assertRaisesRegex(ValueError, 'not truncated'):
                probe['verify_write_failures'](work, text)
            for codec in probe['CODECS']:
                (work/('write-failure.'+codec)).write_bytes(b'')
            self.assertEqual(probe['verify_write_failures'](work, text), marker)
            for invalid in ['', text+'\n'+text, json.dumps(dict(marker, writes=499)),
                            json.dumps(dict(marker, write_failure_checks=1)),
                            json.dumps(dict(marker, error_code=24)),
                            json.dumps(dict(marker, iterations=99))]:
                with self.subTest(text=invalid), self.assertRaisesRegex(ValueError, 'Incomplete post-open'):
                    probe['verify_write_failures'](work, invalid)
            for codec in probe['CODECS']:
                path = work/('write-failure.'+codec)
                path.write_bytes(b'partial')
                with self.subTest(codec=codec), self.assertRaisesRegex(ValueError, 'not truncated'):
                    probe['verify_write_failures'](work, text)
                path.write_bytes(b'')
            (work/'write-failure.data').write_bytes(b'')
            with self.assertRaisesRegex(ValueError, 'unsupported.*sentinel changed'):
                probe['verify_write_failures'](work, text)

    def test_image_export_post_open_subprocess_failure_is_mandatory(self):
        probe = self.image_export_probe()
        run_lane = probe['run_write_failure_lane']
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='image-export-subprocess-') as directory:
            work = Path(directory)
            args = SimpleNamespace(bend_source=work/'bend')
            with patch.dict(run_lane.__globals__, run=lambda *args, **kwargs: ''):
                for lane in ('cpu', 'javascript'):
                    failed = SimpleNamespace(returncode=1, stderr='forced write-failure process error', stdout='')
                    with patch.object(probe['subprocess'], 'run', return_value=failed) as process:
                        with self.assertRaisesRegex(RuntimeError, 'post-open.*run failed'):
                            run_lane(args, work, lane)
                        self.assertIs(process.call_args.kwargs['preexec_fn'], probe['limit_write_failures'])
                    incomplete = SimpleNamespace(returncode=0, stderr='', stdout='')
                    with patch.object(probe['subprocess'], 'run', return_value=incomplete):
                        with self.assertRaisesRegex(ValueError, 'Incomplete post-open'):
                            run_lane(args, work, lane)

    def test_memory_probe_rejects_cross_batch_result_cancellation(self):
        BUILD.mkdir(exist_ok=True)
        with patch('sys.path',[str(ROOT/'tools'),*sys.path]):
            main=runpy.run_path(str(ROOT/'tools/image_memory_probe.py'))['main']
        with tempfile.TemporaryDirectory(dir=BUILD,prefix='memory-negative-') as directory:
            work=Path(directory);report=work/'image-memory-probe/results.json'
            report.parent.mkdir();report.write_text(json.dumps(dict(passed=True)))
            reference=[dict(loaded=False)]*72
            wanted=reference+[1,1,0,0,0]
            def fake_run(command,**kwargs):
                name=Path(command[0]).name
                if name=='reference':return '\n'.join(map(json.dumps,reference))
                if name.startswith('candidate-cpu-'):
                    index=int(name.rsplit('-',1)[1]);rows=wanted[index*64:(index+1)*64]
                    # Removing/adding identical rows across batches would fool only a global comparison.
                    rows=rows[:-1] if index==0 else [dict(loaded=False),*rows]
                    return '\n'.join(map(json.dumps,rows))
                return ''
            overrides=dict(BUILD=work,checkout=lambda *args:None,source_gate=lambda:{},run=fake_run,
                           image_streams=lambda:dict(png=b'0',bmp=b'1',tga=b'2'))
            argv=['image_memory_probe.py','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]
            with patch.dict(main.__globals__,overrides),patch('sys.argv',argv):
                with self.assertRaisesRegex(ValueError,'batch 0 result count differs'):main()
            result=json.loads(report.read_text())
            self.assertFalse(result['passed'])
            self.assertEqual(result['lanes']['cpu']['batches'][0]['result_rows'],63)

    def test_source_gate_covers_jonmath_root(self):
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD,prefix='jonmath-source-') as directory:
            root=Path(directory)
            (root/'src').mkdir()
            (root/'jonlib.bend').write_text('import Base\n')
            math=root/'jonmath.bend';math.write_text('import Base\n')
            with patch('tools.conformance.ROOT',root):
                self.assertEqual(set(source_gate()),{'jonlib.bend','jonmath.bend'})
                for invalid in ('@unsafe\ndef hidden() -> U32:\n  0\n','import "hidden.c"\n'):
                    math.write_text(invalid)
                    with self.assertRaises(ValueError):source_gate()

    def test_inflate_chunk_protocol_rejects_incomplete_results(self):
        encoded=lambda rows:'\n'.join(json.dumps(row) for row in rows)
        rows=[None,'end',list(range(256)),[0,255],'end']
        self.assertEqual(parse_results(encoded(rows)),[None,[],[*range(256),0,255]])
        for rows in ([[1]],[[1],None],[[True],'end'],[[],'end'],[[0]*257,'end'],[[256],'end'],[{}]):
            with self.subTest(rows=rows):
                with self.assertRaises(ValueError):
                    parse_results(encoded(rows))

    def test_failed_resize_probe_invalidates_previous_success(self):
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='resize-negative-') as directory:
            work = Path(directory)
            report = work / 'images-results.json'
            report.write_text(json.dumps(dict(passed=True)))
            with self.assertRaisesRegex(ValueError, 'empty conformance'):
                verify_images(SimpleNamespace(case_prefix='no-such-resize-'), work)
            self.assertEqual(json.loads(report.read_text()), dict(passed=False))

    def test_mismatch_and_missing_results_cannot_pass(self):
        reference = [dict(id='pixel', width=1, height=1, pixels=[0x11223344])]
        scenario = dict(id='pixel', width=1, height=1, operations=[])
        compare(reference, copy.deepcopy(reference))
        altered = copy.deepcopy(reference)
        altered[0]['pixels'][0] ^= 1
        with self.assertRaisesRegex(ValueError, r'pixel \(0, 0\)'):
            compare(reference, altered)
        for a, b in [(reference, []), ([], [])]:
            with self.assertRaises(ValueError):
                compare(a, b)
        with self.assertRaises(ValueError):
            parse_output('', [scenario])
        for invalid in [True, 1.0]:
            malformed = dict(reference[0], width=invalid)
            with self.assertRaisesRegex(ValueError, 'Invalid output dimensions'):
                parse_output(json.dumps(malformed), [scenario])
        encoded = dict(reference[0], pixels=[255], qoi=[113,111,105,102,0,0,0,1,0,0,0,1,4,0,192,0,0,0,0,0,0,0,1])
        altered = copy.deepcopy(encoded)
        altered['qoi'][-1] = 2
        with self.assertRaisesRegex(ValueError, 'QOI export bytes differ'):
            compare([encoded], [altered])
        for invalid in (None, [], [True], [256]):
            malformed = dict(encoded, qoi=invalid)
            with self.assertRaisesRegex(ValueError, 'Invalid QOI bytes'):
                parse_output(json.dumps(malformed), [dict(scenario, export_qoi=True)])
        bounded = dict(reference[0], alpha_border=[0,0,1,1])
        with self.assertRaisesRegex(ValueError, 'alpha border differs'):
            compare([bounded], [dict(bounded, alpha_border=[0,0,0,0])])
        for invalid in ([True,0,1,1], [0,0,2,1]):
            with self.assertRaises(ValueError):
                parse_output(json.dumps(dict(bounded, alpha_border=invalid)), [dict(scenario, alpha_border=0)])
        palette = dict(reference[0], palette_count=1, palette=[0x11223344,0])
        for altered in (dict(palette,palette_count=0),dict(palette,palette=[0x11223344,1])):
            with self.assertRaisesRegex(ValueError, 'palette differs'):
                compare([palette],[altered])
        for altered in (dict(palette,palette_count=True),dict(palette,palette=[0x11223344])):
            with self.assertRaisesRegex(ValueError, 'Invalid palette result'):
                parse_output(json.dumps(altered),[dict(scenario,palette=2)])

    def test_empty_or_invalid_fixtures_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, 'empty'):
            cases_from(dict(schema=1, cases=[]))
        case = dict(id='pixel', width=1, height=1, background=[0, 0, 0, 255], operations=[])
        blit = dict(op='blit', x=0, y=0, tint=[255, 255, 255, 255],
                    source=dict(width=1, height=1, pixels=[[1, 2, 3, 4]]))
        for bad in [dict(case, width=0), dict(case, height=True),
                    dict(case, operations=[dict(op=[], color=[0,0,0,255])]),
                    dict(case, operations=[dict(op='unknown', color=[0, 0, 0, 255])]),
                    dict(case, operations=[dict(blit, source=dict(width=1, height=1, pixels=[]))]),
                    dict(case, operations=[dict(blit, observe_source=1)]),
                    dict(case, operations=[dict(op='resize_nn', width=0, height=1)]),
                    dict(case, operations=[dict(op='resize', width=1, height=4097)]),
                    dict(case, operations=[dict(op='resize_canvas', width=2, height=2, x=2, y=0, color=[0,0,0,0])]),
                    dict(case, operations=[dict(op='alpha_crop', threshold=0)]),
                    dict(case, operations=[dict(op='rotate_degrees', degrees=361, result_width=1, result_height=1)]),
                    dict(case, operations=[dict(op='rotate_degrees', degrees=45, result_width=True, result_height=1)]),
                    dict(case, operations=[dict(op='collision_value', function='rectangle', args=[0,0,1,1,0,0,1,1], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='collision_value', function='rectangle', args=[0,0,1,1,0,0,1], x=0, y=0)]),
                    dict(case, operations=[dict(op='from_channel', channel=0.5)]),
                    dict(case, width=2, operations=[dict(op='collision_value', function='lines', args=[0,0,1,1,0,1,1,0], x=0, y=0)]),
                    dict(case, operations=[dict(op='collision_value', function='point_line', args=[0,0,1,1,2,2,float('nan')], x=0, y=0)]),
                    dict(case, operations=[dict(op='collision_value', function='point_poly', args=[0,0], points=[[1]], x=0, y=0)]),
                    dict(case, width=2, operations=[dict(op='vector3_value', function='one', args=[], x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector3_value', function='add', args=[1,2,3,4,5], x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector3_value', function='divide', args=[1,2,3,4,5,1e-50], x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector3_value', function='project', args=[1,2,3,0,0,0], x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector3_value', function='reject', args=[1,2,3,1e-30,1e-30,1e-30], x=0, y=0)]),
                    dict(case, width=15, operations=[dict(op='matrix_value', function='identity', args=[], x=0, y=0)]),
                    dict(case, width=5, operations=[dict(op='vector3_value', function='ortho_normalize', args=[1,2,3,4,5,6], x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector3_value', function='barycenter', args=[1,1,1,0,0,0,1,1,1,2,2,2], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='invert', args=[1,1,0,0,1,1,0,0,0,0,1,0,0,0,0,1], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='rotate', args=[0,1,0,7], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='rotate_xyz', args=[0,7,0], x=0, y=0)]),
                    dict(case, width=15, operations=[dict(op='matrix_value', function='to_float_v', args=list(range(16)), x=0, y=0)]),
                    dict(case, width=3, operations=[dict(op='vector4_value', function='one', args=[], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='vector4_value', function='divide', args=[1,2,3,4,2,3,4,1e-50], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='vector4_value', function='invert', args=[1,2,3,0], x=0, y=0)]),
                    dict(case, operations=[dict(op='color_numeric_value', function='from_normalized', args=[1.01,0,0,0], x=0, y=0)]),
                    dict(case, operations=[dict(op='color_numeric_value', function='from_hsv', args=[361,1,1], x=0, y=0)]),
                    dict(case, operations=[dict(op='color_numeric_value', function='from_hsv', args=[60,-0.1,1], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='color_vector4_value', function='normalize', args=[0,1.5,254,255], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='quaternion_value', function='divide', args=[0,1,0,1,1,2,3,0], x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='quaternion_value', function='to_matrix', args=[0,0,0,1], x=0, y=0)]),
                    dict(case, white_noise=dict(seed=-1,factor=0.5)),
                    dict(case, white_noise=dict(seed=0,factor=1.5)),
                    dict(case, cellular=dict(seed=0,tile=0)),
                    dict(case, cellular=dict(seed=0,tile=4097)),
                    dict(case, perlin=dict(offset_x=0.5,offset_y=0,scale=1)),
                    dict(case, perlin=dict(offset_x=0,offset_y=0,scale=1e-30)),
                    dict(case, palette=0),
                    dict(case, text_bytes=[0,256]),
                    dict(case, width=2, operations=[dict(op='spline_value',function='linear',args=[0,0,1,1,1.1],x=0,y=0)]),
                    dict(case, width=9, operations=[dict(op='matrix_value', function='decompose', args=list(range(16)), x=0, y=0)]),
                    dict(case, width=4, operations=[dict(op='quaternion_value', function='from_euler', args=[7,0,0], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='frustum', args=[1,1,-1,1,0.1,10], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='ortho', args=[-1,1,-1,1,0,1e-40], x=0, y=0)]),
                    dict(case, width=16, operations=[dict(op='matrix_value', function='frustum', args=[-1,1,-1,1,1e-20,2e-20], x=0, y=0)]),
                    dict(case, operations=[dict(op='float64_value', function='from_f32', args=[1], x=0, y=0)]),
                    dict(case, operations=[dict(op='float64_value', function='internal.f32', args=[1e-40], x=0, y=0)]),
                    dict(case, alpha_border=True),
                    dict(case, gradient_square=dict(density=1.5, outer=[0,0,0,0])),
                    dict(case, width=2, height=2, gradient_linear=dict(direction=361, outer=[0,0,0,0])),
                    dict(case, operations=[dict(op='triangle_fan', points=[[float('inf'),1],[2,3],[4,5]], color=[0,0,0,255])]),
                    dict(case, operations=[dict(op='triangle_ex', x0=0, y0=0, x1=1, y1=1, x2=2, y2=2, color=[255,0,0,255], color2=[0,255,0,255], color3=[0,0,255,255])]),
                    dict(case, operations=[dict(op='color_brightness', amount=float('inf'))]),
                    dict(case, operations=[dict(op='number_value', function='normalize', x=0, y=0, args=[1,0,1e-50])]),
                    dict(case, operations=[dict(op='crop', x=1, y=0, width=1, height=1)]),
                    dict(case, operations=[dict(op='extract', x=0, y=0, width=2, height=1)]),
                    dict(case, operations=[dict(op='line_v', x0=float('nan'), y0=0, x1=1, y1=1, color=[0, 0, 0, 255])])]:
            with self.assertRaises(ValueError):
                cases_from(dict(schema=1, cases=[bad]))
        unsafe = dict(case, width=2, operations=[dict(op='resize_nn', width=512, height=1)])
        with self.assertRaisesRegex(ValueError, 'reads outside'):
            cases_from(dict(schema=1, cases=[unsafe]))
        filtered = dict(case, width=2, operations=[dict(op='resize', width=512, height=1)])
        self.assertEqual(result_size(cases_from(dict(schema=1, cases=[filtered]))[0]), (512, 1))

    def test_compiler_overlay_requires_exact_declared_sources(self):
        BUILD.mkdir(exist_ok=True)
        revision = 'a' * 40
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='provenance-') as directory:
            root = Path(directory)
            dependency = root / 'bend'
            source = dependency / 'bend2/comp.ts'
            source.parent.mkdir(parents=True)
            source.write_text('reviewed compiler')
            manifest_patch = root / 'compiler.patch'
            manifest_patch.write_text('reviewed patch')
            overlay = dict(path='compiler.patch',
                           sha256=hashlib.sha256(manifest_patch.read_bytes()).hexdigest(),
                           files={'bend2/comp.ts': hashlib.sha256(source.read_bytes()).hexdigest()})
            with patch('tools.conformance.ROOT', root):
                with patch('tools.conformance.run', side_effect=[revision, 'bend2/comp.ts\n']):
                    checkout(dependency, revision, overlay)
                source.write_text('unreviewed compiler')
                with patch('tools.conformance.run', side_effect=[revision, 'bend2/comp.ts\n']):
                    with self.assertRaisesRegex(ValueError, 'overlay mismatch'):
                        checkout(dependency, revision, overlay)
                source.write_text('reviewed compiler')
                with patch('tools.conformance.run', side_effect=[revision, 'bend2/main.ts\n']):
                    with self.assertRaisesRegex(ValueError, 'unexpected tracked changes'):
                        checkout(dependency, revision, overlay)
                manifest_patch.write_text('unreviewed patch')
                with patch('tools.conformance.run', return_value=revision):
                    with self.assertRaisesRegex(ValueError, 'patch hash mismatch'):
                        checkout(dependency, revision, overlay)
                with patch('tools.conformance.run', side_effect=[revision, ' M bend2/comp.ts\n']):
                    with self.assertRaisesRegex(ValueError, 'tracked changes invalidate'):
                        checkout(dependency, revision)


if __name__ == '__main__':
    unittest.main()
