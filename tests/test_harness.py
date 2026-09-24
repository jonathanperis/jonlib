import copy
import json
import unittest

from tools.conformance import cases_from, compare, parse_output


class HarnessTests(unittest.TestCase):
    def test_mismatch_and_missing_results_cannot_pass(self):
        reference = [dict(id='pixel', width=1, height=1, pixels=[0x11223344])]
        compare(reference, copy.deepcopy(reference))
        altered = copy.deepcopy(reference)
        altered[0]['pixels'][0] ^= 1
        with self.assertRaisesRegex(ValueError, r'pixel \(0, 0\)'):
            compare(reference, altered)
        for a, b in [(reference, []), ([], [])]:
            with self.assertRaises(ValueError):
                compare(a, b)
        with self.assertRaises(ValueError):
            parse_output('', [dict(id='pixel', width=1, height=1)])
        for invalid in [True, 1.0]:
            malformed = dict(reference[0], width=invalid)
            with self.assertRaisesRegex(ValueError, 'Invalid output dimensions'):
                parse_output(json.dumps(malformed), [dict(id='pixel', width=1, height=1)])

    def test_empty_or_invalid_fixtures_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, 'empty'):
            cases_from(dict(schema=1, cases=[]))
        case = dict(id='pixel', width=1, height=1, background=[0, 0, 0, 255], operations=[])
        for bad in [dict(case, width=0), dict(case, height=True),
                    dict(case, operations=[dict(op='unknown', color=[0, 0, 0, 255])])]:
            with self.assertRaises(ValueError):
                cases_from(dict(schema=1, cases=[bad]))


if __name__ == '__main__':
    unittest.main()
