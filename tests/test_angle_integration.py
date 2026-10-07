"""Compiler-free routing, domain staging and fatal-angle harness regression."""
from contextlib import ExitStack
import json
import hashlib
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

from tools import conformance as c


def operation(kind='vector_value', function='angle', args=None):
    return dict(op=kind, function=function, args=args or [1, 0, 0, 1], x=0, y=0)


def scene(operations=None):
    return c.cases_from(dict(schema=1, cases=[dict(
        id='checked-angle', width=4, height=2, background=[0, 0, 0, 0],
        operations=operations or [operation()])]))


def receipt(profile='Glibc241AngleRn'):
    return dict(contract='native-angle-profile-v2', selected_profile=profile, matching_profiles=[profile])


class StopAfterCandidates(Exception):
    pass


class AngleRouteTests(unittest.TestCase):
    def test_all_angle_apis_require_independent_selection_in_each_mode(self):
        for kind, namespace, function, args in [
                ('vector_value', 'Vector2', 'angle', [1, 0, 0, 1]),
                ('vector_value', 'Vector2', 'line_angle', [0, 0, 1, 1]),
                ('vector3_value', 'Vector3', 'angle', [1, 0, 0, 0, 1, 0])]:
            cases = scene([operation(kind, function, args)])
            self.assertTrue(c.has_angles(cases))
            for gpu in (False, True):
                with self.subTest(kind=kind, function=function, gpu=gpu):
                    with self.assertRaisesRegex(ValueError, 'fresh independent'):
                        c.bend_source(cases, gpu=gpu, extrema_reference='Glibc239Libm')
                    for profile in c.ANGLE_REFERENCES:
                        with patch.object(c, 'gradient_reference', side_effect=AssertionError('gradient inferred')):
                            source = c.bend_source(cases, gpu=gpu, angle_reference=profile)
                        self.assertIn(f'M.{namespace}.{function}_for(M.{c.LIBM_FOR_PROFILE[profile]}{{}}, ', source)
                        self.assertIn('s0 : J.Surface <- write_angle(', source)

    def test_invalid_choices_cannot_generate_source(self):
        for profile in ('', 'native', 'Glibc239Libm', 'Sun1993Angle', 'Apple2007Angle',
                        0, True, [], {}, receipt(), ['Glibc241AngleRn']):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, 'Unknown angle'):
                c.bend_source(scene(), angle_reference=profile)

    def test_non_angle_behavior_does_not_depend_on_angle_selection(self):
        cases = scene([dict(op='pixel', x=0, y=0, color=[1, 2, 3, 4])])
        self.assertFalse(c.has_angles(cases))
        for gpu in (False, True):
            baseline = c.bend_source(cases, gpu=gpu)
            for profile in c.ANGLE_REFERENCES:
                self.assertEqual(baseline, c.bend_source(cases, gpu=gpu, angle_reference=profile))
        native = c.c_source(cases)
        self.assertNotIn('angle_valid_', native)

    def test_rejection_remains_result_bound_before_clear_and_overwrite(self):
        cases = scene([operation(function='line_angle', args=[0, 0, 1, 1e-40]),
                       dict(op='clear', color=[0, 0, 0, 0]),
                       dict(op='pixel', x=0, y=0, color=[1, 2, 3, 4])])
        for gpu in (False, True):
            source = c.bend_source(cases, gpu=gpu, angle_reference='Glibc241AngleRn')
            self.assertIn('case None{}: Fail{(surface, AngleRejected{case_id, operation})}', source)
            self.assertIn('IO.die(Unit, 1, "angle fixture rejected: " ++ case_id', source)
            draw = source.split('def draw_0(', 1)[1].split('def case_0(', 1)[0]
            self.assertIn('do Result<&1, &1, J.Surface & Harness.Error, J.Surface>:', draw)
            self.assertLess(draw.index('s0 : J.Surface <- write_angle('), draw.index('J.Surface.clear(s0,'))
            self.assertLess(draw.index('J.Surface.clear(s0,'), draw.index('J.Surface.draw_pixel(s1,'))
            self.assertIn('"checked-angle", 0, M.Vector2.line_angle_for(', draw)
            self.assertNotIn('Bool.pick', draw)
            self.assertNotIn('4294967295', draw)
        native = c.c_source(cases)
        body = native.split('int main(void)', 1)[1]
        self.assertLess(body.index('invalid angle intermediate domain'), body.index('float angle=Vector2LineAngle('))
        self.assertLess(body.index('invalid angle intermediate domain'), body.index('ImageClearBackground('))

    def test_surface_errors_are_lifted_without_changing_public_surface_error(self):
        operations = [dict(op='crop', x=0, y=0, width=2, height=2),
                      dict(op='resize_nn', width=4, height=2),
                      dict(op='resize', width=4, height=2),
                      dict(op='resize_canvas', width=4, height=2, x=0, y=0, color=[0,0,0,0]),
                      dict(op='rotate_degrees', degrees=0, result_width=4, result_height=2),
                      dict(op='to_pot', color=[0,0,0,0])]
        with patch.object(c, 'gradient_reference', return_value='Glibc239Libm'):
            source = c.bend_source(scene(operations))
        for method in ('crop', 'resize_nn', 'resize', 'resize_canvas', 'rotate_degrees_for', 'to_pot'):
            self.assertIn('<- lift_surface(J.Surface.'+method+'(', source)
        self.assertIn('Fail{(surface, SurfaceRejected{error})}', source)
        self.assertIn('SurfaceRejected{J.InvalidSize{}}', source)
        self.assertIn('SurfaceRejected{J.InvalidRectangle{}}', source)
        self.assertIn('SurfaceRejected{error})}', source)
        self.assertNotIn('J.AngleRejected', source)


class NativeAngleDomainTests(unittest.TestCase):
    def test_all_inputs_precede_arithmetic_and_every_intermediate_is_guarded(self):
        guards = '\n'.join(c.native_angle_guards())
        for api, fields, expected in [
            ('Vector2Angle', ('x', 'y'), ['p0','p1','dot','q0','q1','det']),
            ('Vector2LineAngle', ('x', 'y'), ['dy','dx']),
            ('Vector3Angle', ('x', 'y', 'z'),
             ['cx0','cx1','cy0','cy1','cz0','cz1','cx','cy','cz','sx','sy','sz','sxy','square','length','p0','p1','p2','dxy','dot'])]:
            body = guards.split('angle_valid_'+api+'(', 1)[1].split('return 1;', 1)[0]
            first_arithmetic = body.index('\nfloat ')
            for side in ('left', 'right'):
                for field in fields:
                    self.assertLess(body.index(f'angle_finite({side}.{field})'), first_arithmetic)
            expressions = re.findall(r'float (\w+)=([^;]+);\nif\(!angle_normal_or_zero\((\w+)\)\) return 0;', body)
            self.assertEqual([name for name, _, _ in expressions], expected)
            self.assertTrue(all(name == guarded for name, _, guarded in expressions))
        v3 = guards.split('angle_valid_Vector3Angle(', 1)[1]
        self.assertLess(v3.index('angle_normal_or_zero(square)'), v3.index('if(square<0.0f)'))
        self.assertLess(v3.index('if(square<0.0f)'), v3.index('sqrtf(square)'))
        self.assertNotIn('atan2', guards)
        self.assertIn('m==0 || (m>=0x00800000u && m<0x7f800000u)', guards)

    def test_original_native_calls_and_observation_are_preserved(self):
        for op, api in [(operation(), 'Vector2Angle'),
                        (operation(function='line_angle'), 'Vector2LineAngle'),
                        (operation('vector3_value', 'angle', [1,0,0,0,1,0]), 'Vector3Angle')]:
            source = c.c_source(scene([op]))
            body = source.split('int main(void)', 1)[1]
            self.assertEqual(body.count(f'float angle={api}('), 1)
            self.assertIn('ImageDrawPixel(&image, 0, 0, float_bits(angle));', body)
            self.assertIn('invalid angle result', body)
            self.assertLess(source.index('#pragma STDC FP_CONTRACT OFF'), source.index('#include "raymath.h"'))

    def test_true_output_only_control_does_not_expand_fixture_bounds(self):
        with self.assertRaisesRegex(ValueError, 'arity/domain'):
            scene([operation(function='line_angle', args=[0, 0, 2**127, 1])])
        source = c.native_angle_output_control_source()
        self.assertIn('input_end={0x1p127f,1.0f}', source)
        self.assertIn('float angle=Vector2LineAngle(start,end);', source)
        self.assertIn('unexpected angle intermediate rejection', source)
        self.assertIn('invalid angle result', source)
        with patch.object(c, 'verify_native_rejection') as intermediate, patch.object(c, 'verify_native_source_rejection') as output:
            self.assertEqual(c.verify_angle_rejections(Path('/raylib'), Path('/library')), 2)
        case = intermediate.call_args.args[2]
        self.assertEqual(case['operations'][0]['args'], [0,0,1,1e-40])
        self.assertEqual(intermediate.call_args.args[-1], 'invalid angle intermediate domain')
        self.assertEqual(output.call_args.args[-1], 'invalid angle result')

    def test_rejection_controls_require_fresh_binary_expected_exit_and_no_success(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(c, 'BUILD', Path(temp)):
            binary = Path(temp)/'rejection'
            binary.write_text('stale')
            with patch.object(c, 'run'), patch.object(c.subprocess, 'run') as execute:
                with self.assertRaisesRegex(ValueError, 'fresh native rejection'):
                    c.verify_native_source_rejection(Path('/raylib'), Path('/library'), 'rejection', 'C', 10, 'invalid angle')
                execute.assert_not_called()
            def compile_control(command, **kwargs):
                self.assertFalse(binary.exists())
                Path(command[-1]).write_text('fresh')
                self.assertEqual(command[1:4], ['-std=c11', '-O2', '-fno-builtin-atan2f'])
            for code, stdout, stderr in [(0, '', 'invalid angle'), (10, 'success row', 'invalid angle'), (10, '', 'other error')]:
                with patch.object(c, 'run', side_effect=compile_control), patch.object(c.subprocess, 'run', return_value=subprocess.CompletedProcess([],code,stdout,stderr)):
                    with self.assertRaisesRegex(ValueError, 'fail closed'):
                        c.verify_native_source_rejection(Path('/raylib'), Path('/library'), 'rejection', 'C', 10, 'invalid angle')
            with patch.object(c, 'run', side_effect=compile_control), patch.object(c.subprocess, 'run', return_value=subprocess.CompletedProcess([],10,'','invalid angle')):
                c.verify_native_source_rejection(Path('/raylib'), Path('/library'), 'rejection', 'C', 10, 'invalid angle')


class AngleQualificationRoutingTests(unittest.TestCase):
    def test_selection_is_fresh_and_must_name_a_profile(self):
        for profile in c.ANGLE_REFERENCES:
            result = receipt(profile)
            with patch.object(c.native_profiles, 'angle_profile', return_value=result) as gate:
                self.assertIs(c.qualify_angles(Path('/raylib'), Path('/library')), result)
            self.assertEqual(gate.call_args.args[:2], (Path('/raylib'), c.BUILD / 'native-profiles'))
        for result in ({}, dict(receipt(), selected_profile='unknown'), dict(receipt(), selected_profile=None)):
            with patch.object(c.native_profiles, 'angle_profile', return_value=result), self.assertRaisesRegex(ValueError, 'uniquely selected'):
                c.qualify_angles(Path('/raylib'), Path('/library'))
        with patch.object(c.native_profiles, 'angle_profile', side_effect=ValueError('Ambiguous')), self.assertRaisesRegex(ValueError, 'Ambiguous'):
            c.qualify_angles(Path('/raylib'), Path('/library'))

    def run_main_until_candidate(self, gate_result=None, gate_error=None, gpu=False, policy=None):
        with tempfile.TemporaryDirectory() as temp, ExitStack() as stack:
            work = Path(temp); raylib = work/'raylib'; (raylib/'src').mkdir(parents=True)
            (raylib/'src/raylib.h').write_text('mock header')
            cases = scene(); fixture = work/'fixtures.json'
            fixture.write_text(json.dumps(dict(schema=1,cases=cases)))
            reference = json.dumps(dict(id='checked-angle',width=4,height=2,pixels=[0]*8))+'\n'
            calls = []; self.executions=[]
            original = c.bend_source
            def generate(*args, **kwargs):
                calls.append(kwargs.copy())
                return original(*args, **kwargs)
            def run(command, **kwargs):
                self.executions.append((command,kwargs))
                if '--check-only' in command: return 'All terms check.'
                if '--version' in command: return 'mock version'
                if Path(command[0]).name == 'reference': return reference
                if '-o' in command:
                    targets = [Path(command[n+1]) for n, token in enumerate(command[:-1]) if token == '-o']
                    for target in targets: target.write_text('fresh mock artifact')
                    if any(p.name == ('candidate-gpu-0' if gpu else 'candidate-0') for p in targets):
                        raise StopAfterCandidates()
                return ''
            stack.enter_context(patch.object(c, 'BUILD', work))
            stack.enter_context(patch.object(c, 'checkout'))
            stack.enter_context(patch.object(c, 'inventory', return_value=[]))
            stack.enter_context(patch.object(c, 'source_gate', return_value={}))
            stack.enter_context(patch.object(c, 'run', side_effect=run))
            stack.enter_context(patch.object(c, 'verify_angle_rejections', return_value=2))
            generator = stack.enter_context(patch.object(c, 'bend_source', side_effect=generate))
            gate = stack.enter_context(patch.object(c.native_profiles, 'angle_profile', return_value=gate_result, side_effect=gate_error))
            argv = ['conformance', '--fixtures', str(fixture), '--raylib-source', str(raylib)] + (['--gpu'] if gpu else []) + (['--reference-loader-policy',policy] if policy else [])
            stack.enter_context(patch.object(sys, 'argv', argv))
            (work/'conformance.json').write_text(json.dumps(dict(passed=True,angle_reference=receipt('Sun239AngleRn'))))
            (work/'candidate-0.bend').write_text('stale candidate')
            expected = StopAfterCandidates if gate_error is None and gate_result == receipt() else ValueError
            with self.assertRaises(expected): c.main()
            gate.assert_called_once()
            report = json.loads((work/'conformance.json').read_text())
            self.assertFalse(report['passed'])
            if expected is ValueError:
                generator.assert_not_called()
                self.assertEqual((work/'candidate-0.bend').read_text(), 'stale candidate')
                self.assertNotIn('angle_reference', report)
            return calls, report

    def test_cpu_javascript_and_forced_gpu_use_same_fresh_selection(self):
        for gpu in (False, True):
            calls, report = self.run_main_until_candidate(gate_result=receipt(), gpu=gpu)
            self.assertEqual([call['angle_reference'] for call in calls], ['Glibc241AngleRn']*(2 if gpu else 1))
            self.assertEqual([call.get('gpu', False) for call in calls], [False, True] if gpu else [False])
            self.assertEqual(report['angle_reference'], receipt())

    def test_full_canonical_native_compiler_and_execution_use_clean_snapshot(self):
        with patch.dict(c.os.environ,{'LD_LIBRARY_PATH':'/opt/hostedtoolcache/Python/3.12.14/x64/lib'}):
            _,report=self.run_main_until_candidate(gate_result=receipt(),policy='clean-loader')
            native=[(command,kwargs) for command,kwargs in self.executions
                    if str(command[0]) in ('clang','cmake') or Path(command[0]).name=='reference']
            self.assertEqual(len(native),5)
            self.assertTrue(all('LD_LIBRARY_PATH' not in kwargs['env'] for _,kwargs in native))
            self.assertTrue(all(kwargs['env']==native[0][1]['env'] for _,kwargs in native))
            candidate=[kwargs for command,kwargs in self.executions if command[0]=='bun']
            self.assertTrue(candidate);self.assertTrue(all('env' not in kwargs for kwargs in candidate))
            self.assertEqual(c.os.environ['LD_LIBRARY_PATH'],'/opt/hostedtoolcache/Python/3.12.14/x64/lib')
            self.assertEqual(report['reference_environment']['policy'],'clean-loader')

    def test_failed_unknown_or_mixed_qualification_cannot_emit_candidate(self):
        for result in (dict(receipt(), selected_profile='unknown'), dict(receipt(), selected_profile=None)):
            self.run_main_until_candidate(gate_result=result)
        for error in ('Ambiguous native profile', 'Unsupported or mixed native profile', 'Frozen angle derivation mismatches'):
            self.run_main_until_candidate(gate_error=ValueError(error))

    def test_metal_probe_qualifies_before_each_run_and_passes_selection(self):
        with patch.object(sys, 'path', [str(c.ROOT/'tools'), *sys.path]):
            probe = runpy.run_path(str(c.ROOT/'tools/metal_probe.py'))
        main = probe['main']; env = main.__globals__
        cases = scene(); rows = [dict(id='checked-angle',width=4,height=2,pixels=[0]*8)]
        for fail in (False, True):
            with tempfile.TemporaryDirectory() as temp, ExitStack() as stack:
                work = Path(temp)
                (work/'scenarios.json').write_text(json.dumps(cases))
                (work/'reference.jsonl').write_text(json.dumps(rows[0])+'\n')
                for name in ('reference.c','reference'): (work/name).write_text('native fixture')
                # Prefix diagnosis remains available after a failed candidate lane.
                (work/'conformance.json').write_text(json.dumps(dict(passed=False,
                    reference_environment=c.reference_environment.ReferenceEnvironment().receipt(),
                    reference_artifacts={name:hashlib.sha256((work/name).read_bytes()).hexdigest()
                        for name in ('reference.c','reference','reference.jsonl')})))
                generator = Mock(side_effect=StopAfterCandidates())
                qualifier = Mock(side_effect=ValueError('unqualified') if fail else None, return_value=receipt())
                stack.enter_context(patch.dict(env, BUILD=work, checkout=Mock(), cases_from=Mock(return_value=cases),
                                               source_gate=Mock(return_value={}), qualify_angles=qualifier, bend_source=generator,
                                               run=Mock(return_value=(work/'reference.jsonl').read_text())))
                stack.enter_context(patch.object(env['platform'], 'system', return_value='Darwin'))
                stack.enter_context(patch.object(sys, 'argv', ['metal-probe', '--counts', '1']))
                with self.assertRaises(ValueError if fail else StopAfterCandidates): main()
                qualifier.assert_called_once()
                if fail: generator.assert_not_called()
                else:
                    self.assertEqual(generator.call_args.kwargs,
                                     dict(gpu=True,extrema_reference=None,angle_reference='Glibc241AngleRn'))
                    self.assertEqual(json.loads((work/'metal-probe.json').read_text())['angle_reference'], receipt())


if __name__ == '__main__':
    unittest.main()
