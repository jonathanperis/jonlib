"""Pure checks for native profile selection and the angle kernel/wrapper gate (no compiler)."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import native_profiles as profiles  # noqa: E402
import angle_kernel_probe as gate  # noqa: E402
from angle_probe import samples as historical  # noqa: E402
from probekit import ProbeFailure  # noqa: E402

# Frozen corpus fingerprints carried over from the replaced probes.
KERNEL_INPUTS_SHA256 = 'f290c0d90d9e6b7e8db334edeaed6fca6cd1336022ba6516be82a80699ebb100'  # first 8,317 rows
WRAPPER_CORPUS_SHA256 = '5ce3b55c06361617b3f1f431bf19ca326af5833099823baeaf2f26b6781216d9'


def fake_run(stdout):
    def run(command):
        return stdout if len(command) == 1 else ''
    return run


class ProfileSelectionTests(unittest.TestCase):
    def test_select_requires_exactly_one_matching_profile(self):
        expected = dict(A=[1, 2, 3], B=[1, 2, 4])
        self.assertEqual(profiles.select(expected, [1, 2, 4]), ('B', dict(A=1, B=0)))
        for observed, message in (([1, 9, 9], 'Unsupported'), ([1, 2], 'Incomplete')):
            with self.assertRaisesRegex(ValueError, message):
                profiles.select(expected, observed)
        with self.assertRaisesRegex(ValueError, 'Ambiguous'):
            profiles.select(dict(A=[1], B=[1]), [1])

    def test_manifest_expectations_are_rederived_exactly(self):
        manifest = profiles.load_manifest()
        self.assertEqual((len(manifest['scalar_controls']), len(manifest['wrapper_controls'])), (76, 205))
        for field, mutate in (('scalar_controls', lambda row: row['expected'].update(Sun239AngleRn='40490fda')),
                              ('wrapper_controls', lambda row: row['intermediates'][0].__setitem__(1, '00000001'))):
            broken = copy.deepcopy(manifest); mutate(broken[field][0])
            with tempfile.TemporaryDirectory() as directory, self.subTest(field=field):
                path = Path(directory) / 'manifest.json'; path.write_text(json.dumps(broken))
                with self.assertRaisesRegex(ValueError, 'derivation mismatches'):
                    profiles.load_manifest(path)

    def angle_output(self, manifest, profile, scalar_override=None):
        lines = [row['expected'][profile] for row in manifest['scalar_controls']]
        if scalar_override is not None:
            lines[0] = scalar_override
        lines += [' '.join([v for _, v in row['intermediates']] + [row['expected'][profile]]) for row in manifest['wrapper_controls']]
        return '\n'.join(lines) + '\n'

    def test_angle_profile_selects_from_fixed_native_outputs(self):
        manifest = profiles.load_manifest()
        with tempfile.TemporaryDirectory() as work:
            for profile in profiles.ANGLE_PROFILES:
                result = profiles.angle_profile(Path('/raylib'), work, fake_run(self.angle_output(manifest, profile)))
                self.assertEqual(result['selected_profile'], profile)
                self.assertEqual(result['mismatch_counts'][profile], 0)
            near = next(row for row in manifest['scalar_controls'] if row['derivation'] == 'near-half-k70' and int(row['x'], 16) >> 31)
            mixed = self.angle_output(manifest, 'Apple2007AngleRn').splitlines()
            mixed[manifest['scalar_controls'].index(near)] = near['expected']['Sun239AngleRn']
            with self.assertRaisesRegex(ValueError, 'Unsupported or mixed'):
                profiles.angle_profile(Path('/raylib'), work, fake_run('\n'.join(mixed) + '\n'))
            drifted = self.angle_output(manifest, 'Glibc241AngleRn').splitlines()
            index = len(manifest['scalar_controls'])
            drifted[index] = '3f800001 ' + drifted[index].split(' ', 1)[1]
            with self.assertRaisesRegex(ValueError, 'intermediates differ'):
                profiles.angle_profile(Path('/raylib'), work, fake_run('\n'.join(drifted) + '\n'))

    def test_extrema_profile_selects_from_fixed_truth_tables(self):
        cases = profiles.extrema_controls()
        self.assertEqual((len(cases), sum(case['width'] for case in cases)), (832, 2368))
        tables = {p: profiles.extrema_expected(cases, p) for p in profiles.EXTREMA_PROFILES}
        self.assertEqual(sum(a != b for a, b in zip(*tables.values())), 76)
        for profile, words in tables.items():
            def parse(text, cases, words=words):
                it = iter(words)
                return [dict(id=c['id'], width=c['width'], height=1, pixels=[next(it) for _ in range(c['width'])]) for c in cases]
            with tempfile.TemporaryDirectory() as work:
                result = profiles.extrema_profile('/lib.a', '/raylib', work, c_source=lambda cases: 'C', cases_from=lambda doc: doc['cases'],
                                                  parse_output=parse, run=fake_run(''))
            self.assertEqual(result['selected_profile'], profile)
        with self.assertRaisesRegex(ValueError, 'validator changed'):
            profiles.extrema_profile('/lib.a', '/raylib', '/unused', c_source=None, cases_from=lambda doc: doc['cases'][1:],
                                     parse_output=None, run=None)


class AngleCorpusTests(unittest.TestCase):
    def test_kernel_corpus_preserves_historical_order_and_adds_manifest_controls(self):
        rows = gate.kernel_rows()
        self.assertEqual(len(rows), 8393)
        self.assertEqual([(r['y'], r['x']) for r in rows[:1086]], [(gate.bits(y), gate.bits(x)) for y, x in historical()])
        old = [{key: r[key] for key in ('id', 'y', 'x', 'labels')} for r in rows[:8317]]
        self.assertEqual(hashlib.sha256((json.dumps(old, indent=2, sort_keys=True) + '\n').encode()).hexdigest(), KERNEL_INPUTS_SHA256)
        self.assertEqual(sum('frozen' in r for r in rows[8317:]), 76)
        self.assertEqual([r['id'] for r in rows], list(range(len(rows))))

    def test_wrapper_corpus_fingerprint_and_reachable_stages(self):
        rows = gate.wrapper_rows()
        self.assertEqual(len(rows), 428)
        self.assertEqual(hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest(), WRAPPER_CORPUS_SHA256)
        stages = {row['label']: gate.domain(row)[0] for row in rows}
        self.assertEqual((stages['v2-dot-product-10'], stages['line-overflow-dx'], stages['v3-square-overflow']), (10, 11, 21))
        for label in ('output-only-subnormal', 'underflow-to-zero-allowed', 'left-associated-dot', 'fma-sensitive-determinant'):
            self.assertEqual(stages[label], 0, label)

    def test_exact_rational_arithmetic_and_rejection_domain(self):
        one, minimum, maximum = 0x3f800000, 0x00800000, 0x7f7fffff
        self.assertEqual(gate.multiply(maximum, 0x40000000), 0x7f800000)
        self.assertEqual(gate.multiply(minimum, 0x3f000000), 0x00400000)
        self.assertEqual(gate.plus(0x80000000, 0x80000000), 0x80000000)
        self.assertEqual(gate.minus(0, 0), 0)
        self.assertEqual(gate.square_root(0x40800000), 0x40000000)
        self.assertEqual(gate.square_root(0x80000000), 0x80000000)
        self.assertEqual(gate.square_root(0x40000000), struct.unpack('<I', struct.pack('<f', 2 ** 0.5))[0])
        stage, trace, pair = gate.domain(dict(api=0, args=[minimum, one, 0x3f000000, one]))
        self.assertEqual((stage, trace, pair), (10, [[10, 0x00400000]], None))
        stage, trace, pair = gate.domain(dict(api=1, args=[0, 0, 0x7f000000, one]))
        self.assertEqual((stage, pair), (0, [one, 0x7f000000]))
        self.assertEqual(gate.domain(dict(api=2, args=[0x7fc00000] + [0] * 5))[0], 1)


class AngleParserTests(unittest.TestCase):
    def native_line(self, row, scalar):
        stage, trace, pair = gate.domain(row)
        if stage:
            return json.dumps([row['id'], 0, stage, 0, 0, 0, len(trace), *sum(trace, [])])
        final = scalar ^ (0x80000000 if row['api'] == 1 else 0)
        trace = trace + [[32, scalar]] + ([[33, final]] if row['api'] == 1 else [])
        return json.dumps([row['id'], 1, 0, final, final, scalar, len(trace), *sum(trace, [])])

    def test_wrapper_native_records_must_agree_with_exact_domain(self):
        rows = [dict(id=0, api=1, args=[0, 0, 0x3f800000, 0x3f800000], label='line', frozen=None),
                dict(id=1, api=0, args=[0x00800000, 0x3f800000, 0x3f000000, 0x3f800000], label='rejected', frozen=None)]
        text = '\n'.join(self.native_line(row, 0x3f490fdb) for row in rows)
        records = gate.parse_wrapper_native(text, rows, 'Sun239AngleRn')
        self.assertEqual([r['private'] for r in records], [[1, 0, 0xbf490fdb], [0, 10, 0]])
        broken = json.loads(self.native_line(rows[1], 0)); broken[2] = 11
        with self.assertRaisesRegex(ProbeFailure, 'exact domain disagree'):
            gate.parse_wrapper_native(self.native_line(rows[0], 0x3f490fdb) + '\n' + json.dumps(broken), rows, 'Sun239AngleRn')
        frozen = dict(rows[0], frozen={p: 0xbf490fda for p in gate.PROFILES})
        with self.assertRaisesRegex(ProbeFailure, 'frozen control'):
            gate.parse_wrapper_native(self.native_line(frozen, 0x3f490fdb), [frozen], 'Sun239AngleRn')

    def test_wrapper_candidate_invariants(self):
        row = dict(id=0, api=0, args=[0x3f800000, 0, 0, 0x3f800000], label='quarter', frozen=None)
        good = [0] + [1, 0, 0x3fc90fdb, 1, 0x3fc90fdb] * 3 + [1, 0x3fc90fdb, 0x3fc90fdb, 0x3fc90fdb]
        self.assertEqual(gate.wrapper_consistency(row, good), good)
        for index, value in ((4, 0), (2, 0x3fc90fda), (19, 0), (17, 1)):
            bad = list(good); bad[index] = value
            with self.subTest(index=index), self.assertRaises(ProbeFailure):
                gate.wrapper_consistency(row, bad)

    def test_kernel_native_record_and_modern_packet_framing(self):
        row = dict(id=7, y=0, x=0x3f800000, labels=['zero'])
        record = dict(id=7, y=0, x=0x3f800000, accepted=True, pinned=0, original=0, native=0, sun=0,
                      mask=2048, index=0, gt=0, final=[0, 0], events=[])
        self.assertEqual(gate.parse_kernel_native(json.dumps(record), [row])[0], record)
        for field, value in (('original', 1), ('mask', 1), ('events', [[1, 0, 0]])):
            with self.subTest(field=field), self.assertRaises(ProbeFailure):
                gate.parse_kernel_native(json.dumps(dict(record, **{field: value})), [row])
        self.assertEqual(gate.expected_tags(1 | 4 | 128 | 256 | 512)[-3:], [37, 38, 39])
        packet = gate.kernel_expected([row], [record], True)[0]
        self.assertEqual(packet, dict(modern=[7, 2048, 0, 0, 1, 0, 1, 0, 0, 0], sun=0, apple=0))
        self.assertEqual(gate.parse_modern(packet['modern'], 7), packet['modern'])
        with self.assertRaises(ProbeFailure):
            gate.parse_modern([7, 2048, 0, 0, 1, 1, 1, 0, 0, 0], 7)
        failure = [7, 0, 0, 0, 0, 0, 0, 81, 6, 1, 2, 3, 4, 5, 6, 0]
        self.assertEqual(gate.parse_modern(failure, 7), failure)
        with self.assertRaises(ProbeFailure):
            gate.parse_modern(failure[:-2] + [0], 7)


if __name__ == '__main__':
    unittest.main()
