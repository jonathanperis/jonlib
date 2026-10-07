"""Select the host's native atan2f and fminf/fmaxf profiles for conformance fixtures.

Each selection compiles a small program with the canonical reference flags, observes
native bits for frozen controls and selects the single profile whose independently
derived expectations match every control. Zero or several matches fail closed.
A selection names a numerical contract; it is not a parity claim for Jonlib.
"""
from fractions import Fraction
import itertools
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools/reference/angle_qualification_v1.json'
ANGLE_PROFILES = ('Apple2007AngleRn', 'Sun239AngleRn', 'Glibc241AngleRn')
EXTREMA_PROFILES = ('AppleLibm', 'Glibc239Libm')
CANONICAL_FLAGS = ['-std=c11', '-O2', '-fno-builtin-atan2f']
APIS = ('Vector2Angle', 'Vector2LineAngle', 'Vector3Angle')


# Exact binary32 arithmetic: RN-even over Fractions with signed zero (no host floats).
def fp(word):
    sign = -1 if word >> 31 else 1
    exponent, significand = (word >> 23) & 255, word & 0x7fffff
    if exponent:
        return sign * Fraction(significand | 0x800000) * Fraction(2) ** (exponent - 150)
    return sign * Fraction(significand) * Fraction(2) ** -149


def rn(value, zero=0):
    """Round to nearest-even binary32, saturating at the largest finite word."""
    if not value:
        return zero
    sign = 0x80000000 if value < 0 else 0
    value = abs(value)
    low, high = 0, 0x7f7fffff
    while low < high:
        middle = (low + high + 1) // 2
        if fp(middle) <= value:
            low = middle
        else:
            high = middle - 1
    below, above = value - fp(low), fp(low + 1) - value
    return sign | (low if below < above or (below == above and low % 2 == 0) else low + 1)


def mul(a, b):
    return rn(fp(a) * fp(b), (a ^ b) & 0x80000000)


def add(a, b):
    return rn(fp(a) + fp(b), 0x80000000 if a == b == 0x80000000 else 0)


def sub(a, b):
    return add(a, b ^ 0x80000000)


def exact_sqrt(word):
    value = fp(word)
    numerator, denominator = math.isqrt(value.numerator), math.isqrt(value.denominator)
    if value < 0 or numerator ** 2 != value.numerator or denominator ** 2 != value.denominator:
        raise ValueError(f'Nonexact frozen square root: {word:08x}')
    return rn(Fraction(numerator, denominator))


def intermediates(api, a):
    """Source-order raymath intermediates and the atan2 (y, x) pair, as words."""
    if api == 'Vector2Angle':
        p, q, u, w = mul(a[0], a[2]), mul(a[1], a[3]), mul(a[0], a[3]), mul(a[1], a[2])
        dot, det = add(p, q), sub(u, w)
        return [p, q, dot, u, w, det], (det, dot)
    if api == 'Vector2LineAngle':
        dy, dx = sub(a[3], a[1]), sub(a[2], a[0])
        return [dy, dx], (dy, dx)
    p, q = mul(a[1], a[5]), mul(a[2], a[4]); cx = sub(p, q)
    u, w = mul(a[2], a[3]), mul(a[0], a[5]); cy = sub(u, w)
    j, k = mul(a[0], a[4]), mul(a[1], a[3]); cz = sub(j, k)
    xx, yy, zz = mul(cx, cx), mul(cy, cy), mul(cz, cz)
    xy = add(xx, yy); xyz = add(xy, zz); length = exact_sqrt(xyz)
    p0, p1 = mul(a[0], a[3]), mul(a[1], a[4]); p01 = add(p0, p1); p2 = mul(a[2], a[5]); dot = add(p01, p2)
    return [p, q, cx, u, w, cy, j, k, cz, xx, yy, zz, xy, xyz, length, p0, p1, p01, p2, dot], (length, dot)


def derived_scalar(row):
    """Frozen scalar expectations from the documented source-branch derivations."""
    y, x = int(row['y'], 16), int(row['x'], 16)
    tag, negative_x = row['derivation'], bool(x >> 31)
    if tag in ('zero-y-axis', 'zero-origin'):
        values = [0x40490fda, 0x40490fdb, 0x40490fdb] if negative_x else [0] * 3
    elif tag == 'zero-x-axis':
        values = [0x3fc90fdb] * 3
    elif tag == 'equal-magnitude':
        values = [0x4016cbe4 if negative_x else 0x3f490fdb] * 3
    elif tag in ('near-half-k70', 'sun-k60-neighbor'):
        values = [0x3fc90fdb, 0x3fc90fda if negative_x else 0x3fc90fdb, 0x3fc90fdb]
    elif tag == 'apple-ratio-2^-22-neighbor':
        values = [0x40490fda if negative_x else y & 0x7fffffff] * 3
    else:
        raise ValueError('Unknown scalar branch derivation: ' + tag)
    return {profile: f'{value ^ (y & 0x80000000):08x}' for profile, value in zip(ANGLE_PROFILES, values)}


def load_manifest(path=MANIFEST):
    """Load the frozen controls and re-derive every expectation with exact arithmetic."""
    manifest = json.loads(Path(path).read_text())
    if tuple(manifest['profiles']) != ANGLE_PROFILES:
        raise ValueError('Angle profile manifest drift')
    controls = manifest['scalar_controls'] + manifest['wrapper_controls']
    if not manifest['scalar_controls'] or not manifest['wrapper_controls'] or len({r['id'] for r in controls}) != len(controls):
        raise ValueError('Empty or duplicate angle controls')
    scalar = {(row['y'], row['x']): derived_scalar(row) for row in manifest['scalar_controls']}
    problems = [row['id'] for row in manifest['scalar_controls'] if row['expected'] != scalar[row['y'], row['x']]]
    for row in manifest['wrapper_controls']:
        words, pair = intermediates(row['api'], [int(value, 16) for value in row['args']])
        pair = [f'{value:08x}' for value in pair]
        expected = scalar.get(tuple(pair))
        if expected and row['api'] == 'Vector2LineAngle':
            expected = {p: f'{int(v, 16) ^ 0x80000000:08x}' for p, v in expected.items()}
        if ([f'{value:08x}' for value in words] != [value for _, value in row['intermediates']]
                or pair != row['atan2_inputs'] or expected != row['expected']):
            problems.append(row['id'])
    if problems:
        raise ValueError(f'Frozen angle derivation mismatches: {problems[:8]}')
    return manifest


def select(expected, observed):
    """expected: {profile: [words]}; return (the unique matching profile, mismatch counts)."""
    mismatches = {profile: [i for i, (a, b) in enumerate(zip(words, observed)) if a != b]
                  for profile, words in expected.items()}
    if any(len(words) != len(observed) for words in expected.values()):
        raise ValueError('Incomplete native profile observations')
    matches = [profile for profile, different in mismatches.items() if not different]
    if len(matches) != 1:
        raise ValueError(f'{"Ambiguous" if matches else "Unsupported or mixed"} native profile; '
                         f'mismatch counts {({p: len(d) for p, d in mismatches.items()})}')
    return matches[0], {profile: len(different) for profile, different in mismatches.items()}


def angle_source(manifest):
    """Native atan2f for scalar controls; source-order mirror and raymath for wrapper controls."""
    out = ['#include <math.h>', '#include <stdint.h>', '#include <stdio.h>', '#include <string.h>',
           '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
           'static float from(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }',
           'static unsigned bits(float f) { unsigned u; memcpy(&u, &f, 4); return u; }',
           'int main(void) {']
    for row in manifest['scalar_controls']:
        out.append(f'{{ volatile float y = from(0x{row["y"]}u), x = from(0x{row["x"]}u); printf("%08x\\n", bits(atan2f(y, x))); }}')
    mirror = {'Vector2Angle': ['a0*a2', 'a1*a3', 'v0+v1', 'a0*a3', 'a1*a2', 'v3-v4'],
              'Vector2LineAngle': ['a3-a1', 'a2-a0'],
              'Vector3Angle': ['a1*a5', 'a2*a4', 'v0-v1', 'a2*a3', 'a0*a5', 'v3-v4', 'a0*a4', 'a1*a3', 'v6-v7',
                               'v2*v2', 'v5*v5', 'v8*v8', 'v9+v10', 'v12+v11', 'sqrtf(v13)',
                               'a0*a3', 'a1*a4', 'v15+v16', 'a2*a5', 'v17+v18']}
    for row in manifest['wrapper_controls']:
        size = 3 if row['api'] == 'Vector3Angle' else 2
        args = ''.join(f'volatile float a{i} = from(0x{raw}u); ' for i, raw in enumerate(row['args']))
        steps = ''.join(f'float v{i} = {e}; printf("%08x ", bits(v{i})); ' for i, e in enumerate(mirror[row['api']]))
        left = ','.join(f'a{i}' for i in range(size))
        right = ','.join(f'a{i}' for i in range(size, 2 * size))
        out.append(f'{{ {args}{steps}printf("%08x\\n", bits({row["api"]}((Vector{size}){{{left}}}, (Vector{size}){{{right}}}))); }}')
    return '\n'.join(out + ['return 0; }', ''])


def angle_profile(raylib_source, work, run):
    """Compile/run the angle controls; run(argv) returns stdout and raises on failure."""
    manifest = load_manifest()
    work = Path(work); work.mkdir(parents=True, exist_ok=True)
    source, binary = work / 'angle-profile.c', work / 'angle-profile'
    source.write_text(angle_source(manifest))
    binary.unlink(missing_ok=True)
    run(['clang', *CANONICAL_FLAGS, '-I' + str(Path(raylib_source) / 'src'), source, '-lm', '-o', binary])
    lines = run([binary]).splitlines()
    scalar, wrapper = manifest['scalar_controls'], manifest['wrapper_controls']
    if len(lines) != len(scalar) + len(wrapper):
        raise ValueError('Incomplete native angle observations')
    wrappers = [line.split() for line in lines[len(scalar):]]
    drift = [row['id'] for row, words in zip(wrapper, wrappers) if words[:-1] != [v for _, v in row['intermediates']]]
    if drift:
        raise ValueError(f'Native source-order intermediates differ from frozen exact arithmetic: {drift[:8]}')
    controls = scalar + wrapper
    observed = lines[:len(scalar)] + [words[-1] for words in wrappers]
    selected, mismatches = select({p: [row['expected'][p] for row in controls] for p in ANGLE_PROFILES}, observed)
    return dict(contract='native-angle-profile-v2', selected_profile=selected, matching_profiles=[selected],
                mismatch_counts=mismatches, scalar_controls=len(scalar), wrapper_controls=len(wrapper),
                exact_intermediates=sum(len(row['intermediates']) for row in wrapper))


# Literal raymath extrema: fminf/fmaxf signed-zero ties via predefined truth tables.
CONTROL_VALUES = (-1.0, -0.0, 0.0, 1.0)
CONTROL_BITS = (0xbf800000, 0x80000000, 0x00000000, 0x3f800000)
KINDS = {2: 'vector_value', 3: 'vector3_value', 4: 'vector4_value'}
# Indices into CONTROL_BITS. Accurate: min zero-sign OR / max zero-sign AND. GNU: first zero operand.
TABLES = {
    'AppleLibm': {'min': ((0, 0, 0, 0), (0, 1, 1, 1), (0, 1, 2, 2), (0, 1, 2, 3)),
                         'max': ((0, 1, 2, 3), (1, 1, 2, 3), (2, 2, 2, 3), (3, 3, 3, 3))},
    'Glibc239Libm': {'min': ((0, 0, 0, 0), (0, 1, 1, 1), (0, 2, 2, 2), (0, 1, 2, 3)),
                    'max': ((0, 1, 2, 3), (1, 1, 1, 3), (2, 2, 2, 3), (3, 3, 3, 3))},
}


def _bits(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def extrema_controls():
    """All ordered pairs/triples, uniform and isolated in every vector lane."""
    cases = []
    for size, kind in KINDS.items():
        for function in ('min', 'max', 'clamp'):
            if function == 'clamp' and size == 4:
                continue
            for indices in itertools.product(range(4), repeat=3 if function == 'clamp' else 2):
                values = [CONTROL_VALUES[index] for index in indices]
                for lane in (None, *range(size)):
                    if lane is None:
                        vectors = [[value] * size for value in values]
                    else:
                        # Lane-distinct finite nonzero sentinels expose component routing errors.
                        if function == 'clamp':
                            vectors = [[(-8.0 - j if j % 2 == 0 else 8.0 + j) for j in range(size)],
                                       [-4.0 - j for j in range(size)], [4.0 + j for j in range(size)]]
                        else:
                            left = [(-2.0 - j if j % 2 == 0 else 2.0 + j) for j in range(size)]
                            vectors = [left, [-value for value in left]]
                        for vector, value in zip(vectors, values):
                            vector[lane] = value
                    context = 'uniform' if lane is None else f'lane-{lane}'
                    cases.append(dict(id=f'extrema-v{size}-{function}-{"".join(map(str, indices))}-{context}',
                                      width=size, height=1, background=[0, 0, 0, 0],
                                      operations=[dict(op=kind, function=function, x=0, y=0,
                                                       args=list(itertools.chain.from_iterable(vectors)))]))
    return cases


def extrema_expected(cases, profile):
    def extreme(function, left, right):
        if left in CONTROL_BITS and right in CONTROL_BITS:
            return CONTROL_BITS[TABLES[profile][function][CONTROL_BITS.index(left)][CONTROL_BITS.index(right)]]
        a, b = struct.unpack('>2f', struct.pack('>2I', left, right))  # finite nonzero sentinels
        return left if (a < b if function == 'min' else a > b) else right
    words = []
    for case in cases:
        size, operation = case['width'], case['operations'][0]
        args = list(map(_bits, operation['args']))
        for lane in range(size):
            if operation['function'] == 'clamp':  # raymath order: min(upper, max(lower, value))
                words.append(extreme('min', args[2 * size + lane], extreme('max', args[size + lane], args[lane])))
            else:
                words.append(extreme(operation['function'], args[lane], args[size + lane]))
    return words


def extrema_profile(library, raylib_source, work, *, c_source, cases_from, parse_output, run):
    """Run the controls through the unchanged canonical generator/parser and select a profile."""
    cases = extrema_controls()
    if json.dumps(cases_from(dict(schema=1, cases=json.loads(json.dumps(cases)))), sort_keys=True) != json.dumps(cases, sort_keys=True):
        raise ValueError('Canonical validator changed the fixed extrema controls')
    work = Path(work); work.mkdir(parents=True, exist_ok=True)
    source, binary = work / 'extrema-profile.c', work / 'extrema-profile'
    source.write_text(c_source(cases))
    binary.unlink(missing_ok=True)
    run(['clang', *CANONICAL_FLAGS, '-I' + str(Path(raylib_source) / 'src'), source, library, '-lm', '-o', binary])
    rows = parse_output(run([binary]), cases)
    if [(row['id'], row['width'], len(row['pixels'])) for row in rows] != [(c['id'], c['width'], c['width']) for c in cases]:
        raise ValueError('Incomplete native extrema observations')
    observed = [pixel for row in rows for pixel in row['pixels']]
    selected, mismatches = select({p: extrema_expected(cases, p) for p in EXTREMA_PROFILES}, observed)
    return dict(contract='literal-vector-extrema-v1', selected_profile=selected, matching_profiles=[selected],
                mismatch_counts=mismatches, control_cases=len(cases), control_components=len(observed))
