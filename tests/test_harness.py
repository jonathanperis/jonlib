import copy
import json
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.conformance import BUILD, cases_from, checkout, compare, parse_output


class HarnessTests(unittest.TestCase):
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

    def test_empty_or_invalid_fixtures_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, 'empty'):
            cases_from(dict(schema=1, cases=[]))
        case = dict(id='pixel', width=1, height=1, background=[0, 0, 0, 255], operations=[])
        blit = dict(op='blit', x=0, y=0, tint=[255, 255, 255, 255],
                    source=dict(width=1, height=1, pixels=[[1, 2, 3, 4]]))
        for bad in [dict(case, width=0), dict(case, height=True),
                    dict(case, operations=[dict(op='unknown', color=[0, 0, 0, 255])]),
                    dict(case, operations=[dict(blit, source=dict(width=1, height=1, pixels=[]))]),
                    dict(case, operations=[dict(blit, observe_source=1)]),
                    dict(case, operations=[dict(op='resize_nn', width=0, height=1)]),
                    dict(case, operations=[dict(op='crop', x=1, y=0, width=1, height=1)]),
                    dict(case, operations=[dict(op='extract', x=0, y=0, width=2, height=1)]),
                    dict(case, operations=[dict(op='line_v', x0=float('nan'), y0=0, x1=1, y1=1, color=[0, 0, 0, 255])])]:
            with self.assertRaises(ValueError):
                cases_from(dict(schema=1, cases=[bad]))
        unsafe = dict(case, width=2, operations=[dict(op='resize_nn', width=512, height=1)])
        with self.assertRaisesRegex(ValueError, 'reads outside'):
            cases_from(dict(schema=1, cases=[unsafe]))

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
