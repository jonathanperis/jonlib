"""Python-only validation for the diagnostic; no compiler or native execution."""
import copy
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
HOST = dict(system='Linux', machine='x86_64', libc=('glibc', '2.41'))
VALUES = [(0., 0.), (1., -1e-20), (-0., -1.)]
CASES = [
    dict(id='vector2-angle-profiles', operations=[dict(op='vector_value', function='angle', x=6, args=[1,0,-1e-20,1])]),
    dict(id='vector2-extrema', operations=[dict(op='vector_value', function='min', x=4, args=[0.,-0.,-0.,0.])]),
    dict(id='vector3-extrema', operations=[dict(op='vector3_value', function='max', x=6, args=[0.,-0.,0.,-0.,0.,0.])]),
    dict(id='vector4-extrema', operations=[dict(op='vector4_value', function='min', x=0, args=[-0.,2,-3,0.,0.,1,-4,-0.])]),
    dict(id='vector2-clamp-components', operations=[dict(op='vector_value', function='clamp', x=4, args=[0.,-0.,-0.,0.,1,1])]),
    dict(id='vector3-clamp-components', operations=[dict(op='vector3_value', function='clamp', x=3, args=[0.,-0.,0.,-0.,0.,-1,1,1,-0.])]),
]


class NativeMathProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with patch('sys.path', [str(ROOT/'tools'), *sys.path]):
            cls.probe = runpy.run_path(str(ROOT/'tools/native_math_profile_probe.py'))

    def setUp(self):
        # Construct independent, valid protocol rows; do not derive these from
        # the production observation_schema, which is itself under test.
        self.rows = [
            ['host','glibc','2.41'], ['host','rounding_mode','FE_TONEAREST'],
            ['host','atan2_library','/lib/libm.so.6'],
            ['host','fmin_library','/lib/libm.so.6'],
            ['host','fmax_library','/lib/libm.so.6'],
        ]
        for label in ('00000000,00000000','00000000,80000000','80000000,00000000',
                      '80000000,80000000','3f800000,bf800000','bf800000,3f800000'):
            for operation in ('min','max'):
                for mode in ('literal','volatile','native','gnu','accurate'):
                    self.rows.append([f'{operation}.{mode}',label,'00000000'])
        for label in ('near-half-neg','near-half-pos','pi-poszero','pi-negzero','huge-ratio-neg','near-half-neg-y'):
            for mode in ('literal','volatile','native','sun-literal','sun-runtime'):
                self.rows.append([f'atan2.{mode}',label,'00000000'])
        for label in ('half','low','z','z-low','pi-(z-low)'):
            self.rows.append(['sun-steps',label,'00000000'])
        for label, components, angle in [
            ('vector2-angle-profiles@6.angle',1,True),
            ('vector2-extrema@4.min',2,False),
            ('vector3-extrema@6.max',3,False),
            ('vector4-extrema@0.min',4,False),
            ('vector2-clamp-components@4.clamp',2,False),
            ('vector3-clamp-components@3.clamp',3,False),
        ]:
            modes = ['raymath.literal','raymath.volatile']
            if not angle:
                modes += ['profile.gnu','profile.accurate','profile.native']
            for mode in modes:
                self.rows.append([mode,label,*(['00000000']*components)])
        self.rows += [
            ['sample','0','00000000','00000000','00000000','00000000','00000000'],
            ['sample','1','3f800000','9e3ce508','3fc90fdb','3fc90fda','3fc90fdb'],
            ['sample','2','80000000','bf800000','c0490fdb','c0490fdb','c0490fda'],
        ]

    def encoded(self, rows=None):
        return '\n'.join('\t'.join(row) for row in (self.rows if rows is None else rows))+'\n'

    def parse(self, rows=None, host=HOST):
        return self.probe['parse_output'](self.encoded(rows), VALUES, CASES, host)

    def test_valid_output_counts_distinct_comparisons(self):
        result = self.parse()
        self.assertEqual(result['samples_observed'], 3)
        self.assertEqual(result['sun_control_vs_native_mismatch_count'], 1)
        self.assertEqual(result['sun_control_vs_native_differences'][0]['index'], 1)
        self.assertEqual(result['direct_volatile_vs_native_mismatch_count'], 1)
        self.assertEqual(result['direct_volatile_vs_native_differences'][0]['index'], 2)
        self.assertEqual(len(result['observations']), 122)

    def test_observation_ids_cannot_be_renamed_or_replaced(self):
        for index, cell, replacement in [(5,0,'min.invented'), (5,1,'renamed'),
                                          (5,0,'sun-steps-invented'), (100,1,'vector2-angle-profiles@7.angle')]:
            rows = copy.deepcopy(self.rows)
            rows[index][cell] = replacement
            with self.subTest(index=index, replacement=replacement), self.assertRaises(ValueError):
                self.parse(rows)
        rows = copy.deepcopy(self.rows)
        rows[5] = rows[6][:]  # Same total row count, duplicate ID, missing original ID.
        with self.assertRaisesRegex(ValueError, 'Duplicate diagnostic observation'):
            self.parse(rows)

    def test_scalar_and_vector_component_counts_are_exact(self):
        for index in [5,100,102,107,112]:  # Scalar angle and Vector2/3/4 observations.
            self.assertNotEqual(self.rows[index][0], 'sample')
            for change in ('missing','extra'):
                rows = copy.deepcopy(self.rows)
                if change == 'missing':
                    rows[index].pop()
                else:
                    rows[index].append('00000000')
                with self.subTest(index=index, change=change), self.assertRaisesRegex(ValueError, 'component count'):
                    self.parse(rows)

    def test_missing_duplicate_and_unknown_rows_are_rejected(self):
        variants = [self.rows[:5]+self.rows[6:], self.rows+[self.rows[5]],
                    self.rows+[['unknown','row','00000000']], self.rows+[[]]]
        for rows in variants:
            with self.subTest(rows=rows[-1:]), self.assertRaises(ValueError):
                self.parse(rows)

    def test_missing_duplicate_or_invalid_host_identity_is_rejected(self):
        for index in range(5):
            variants = [self.rows[:index]+self.rows[index+1:], self.rows+[self.rows[index]]]
            for replacement in ('',' ', ' '+self.rows[index][2]):
                rows = copy.deepcopy(self.rows)
                rows[index][2] = replacement
                variants.append(rows)
            for rows in variants:
                with self.subTest(index=index), self.assertRaises(ValueError):
                    self.parse(rows)
        for index, replacement in [(0,'2.40'),(1,'other'),(2,'relative/libm.so'),
                                   (3,'relative/libm.so'),(4,'relative/libm.so')]:
            rows = copy.deepcopy(self.rows)
            rows[index][2] = replacement
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                self.parse(rows)
        with self.assertRaises(ValueError):
            self.parse(self.rows+[['host','unknown','value']])

    def test_required_host_fields_follow_recorded_platform(self):
        rows = self.rows[1:]  # Darwin must not invent a GNU libc version.
        result = self.parse(rows, dict(system='Darwin',libc=('', '')))
        self.assertNotIn('glibc',result['host'])
        with self.assertRaises(ValueError):
            self.parse(host=dict(system='Darwin',libc=('', '')))

    def test_sample_indices_inputs_lengths_and_bits_are_strict(self):
        variants = [self.rows[:-1], self.rows+[self.rows[-1]],
                    self.rows[:-3]+[self.rows[-2],self.rows[-3],self.rows[-1]]]
        for cell, replacement in [(1,'01'),(2,'00000000'),(3,'9e3ce509'),
                                   (4,'3FC90FDB'),(5,'not-hex!'),(6,'000000000')]:
            rows = copy.deepcopy(self.rows)
            rows[-2][cell] = replacement
            variants.append(rows)
        variants += [self.rows[:-1]+[self.rows[-1][:-1]],
                     self.rows[:-1]+[[*self.rows[-1],'00000000']]]
        for rows in variants:
            with self.subTest(row=rows[-2:]), self.assertRaises(ValueError):
                self.parse(rows)
        for bad in ('NaN','1234567g','000000000','-0000000'):
            rows = copy.deepcopy(self.rows)
            rows[5][-1] = bad
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.parse(rows)

    def test_duplicate_expected_fixture_identity_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate expected'):
            self.probe['observation_schema']([*CASES,CASES[0]])


if __name__ == '__main__':
    unittest.main()
