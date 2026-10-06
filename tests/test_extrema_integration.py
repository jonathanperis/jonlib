import unittest
from unittest.mock import patch

from tools.conformance import LIBM_FOR_PROFILE, bend_source, cases_from, c_source, has_extrema


def scene(operations, **extra):
    return cases_from({'schema': 1, 'cases': [dict(
        id='profile-integration', width=16, height=2,
        background=[0, 0, 0, 0], operations=operations, **extra)]})


def operation(kind, function, args, x=0):
    return dict(op=kind, function=function, args=args, x=x, y=0)


class ExtremaIntegrationTests(unittest.TestCase):
    def test_every_extrema_api_requires_explicit_qualification(self):
        for kind, namespace, size in [('vector_value', 'Vector2', 2),
                                      ('vector3_value', 'Vector3', 3),
                                      ('vector4_value', 'Vector4', 4)]:
            for function in ['min', 'max', *(['clamp'] if size < 4 else [])]:
                with self.subTest(namespace=namespace, function=function):
                    vector = [0.0, -0.0, 1.0, -1.0][:size]
                    args = vector * (3 if function == 'clamp' else 2)
                    cases = scene([operation(kind, function, args)])
                    self.assertTrue(has_extrema(cases))
                    with self.assertRaisesRegex(ValueError, 'fresh canonical'):
                        bend_source(cases)
                    for profile in ('AccurateGradient', 'GnuGradient'):
                        for gpu in (False, True):
                            source = bend_source(cases, gpu=gpu, extrema_reference=profile)
                            self.assertIn(f'M.{namespace}.{function}_for(M.{LIBM_FOR_PROFILE[profile]}{{}}, ', source)

    def test_unknown_profiles_fail_closed(self):
        cases = scene([operation('vector_value', 'min', [0.0, -0.0, -0.0, 0.0])])
        for profile in ('native', 'SecondOperand', '', 0, True):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, 'Unknown extrema'):
                bend_source(cases, extrema_reference=profile)

    def test_extrema_selection_does_not_change_other_numeric_profiles(self):
        cases = scene([
            operation('vector_value', 'min', [0.0, -0.0, -0.0, 0.0]),
            operation('vector_value', 'angle', [1.0, 0.0, 0.0, 1.0], 2),
            operation('vector_value', 'rotate', [1.0, 0.0, 0.5], 3),
            operation('vector_value', 'clamp_value', [1.0, 0.0, 0.0, 2.0], 5),
            operation('number_value', 'clamp', [0.0, -1.0, 1.0], 7),
        ], gradient_linear={'direction': 45, 'outer': [255, 255, 255, 255]})
        native = c_source(cases)
        with patch('tools.conformance.gradient_reference', return_value='Glibc239Libm'):
            source = bend_source(cases, extrema_reference='AccurateGradient', angle_reference='Glibc241AngleRn')
        self.assertIn('M.Vector2.min_for(M.AppleLibm{}, ', source)
        self.assertIn('M.Vector2.angle_for(M.Glibc241Libm{}, ', source)
        self.assertIn('M.Vector2.rotate_for(M.Glibc239Libm{}, ', source)
        self.assertIn('J.Surface.create_gradient_linear_for(M.Glibc239Libm{}, ', source)
        self.assertIn('M.Vector2.clamp_value(', source)
        self.assertIn('M.Math.clamp(', source)
        self.assertNotIn('M.Math.clamp_for(', source)
        self.assertEqual(native, c_source(cases))
        self.assertNotIn('AppleLibm', native)
        self.assertNotIn('Glibc239Libm', native)

    def test_non_extrema_callers_remain_unchanged(self):
        cases = scene([dict(op='pixel', x=1, y=1, color=[1, 2, 3, 4])])
        self.assertFalse(has_extrema(cases))
        for gpu in (False, True):
            self.assertEqual(bend_source(cases, gpu=gpu),
                             bend_source(cases, gpu=gpu, extrema_reference='AccurateGradient'))


if __name__ == '__main__':
    unittest.main()
