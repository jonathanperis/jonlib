#!/usr/bin/env python3
"""Compare raymath extrema to the glibc fminf/fmaxf builtin profile.

Vector2/3/4 min and max, and Vector2/3 component clamp, are compiled from the
pinned raymath.h with contraction off (`clang -O2 -fno-builtin-atan2f`,
`FP_CONTRACT OFF`). Inputs live in a table and each word is loaded through a
volatile, so clang lowers fminf/fmaxf instead of folding the literals and
instead of calling the native glibc pointer (a different signed-zero tie).
Jonmath selects `Glibc239Libm`: a signed-zero tie keeps the first operand, a
NaN loses to a number, and two NaNs keep the second operand. CPU-1 and CPU-2
must match every result bit. JavaScript may quiet a returned negative quiet
NaN to a positive one; any other difference fails. Signaling NaNs are outside
this corpus. There is no Vector4 component clamp in raymath.
"""
import hashlib
import itertools
import json
from collections import Counter

import probekit
from probekit import ProbeFailure

P0, N0 = 0x00000000, 0x80000000
P1, N1 = 0x3f800000, 0xbf800000
PINF, NINF = 0x7f800000, 0xff800000
SUB, LEAST = 0x00000001, 0x00800000
BIG, POW24, HALF = 0x7f7fffff, 0x4b800000, 0x3fc00000
QNAN, NQNAN = 0x7fc00000, 0xffc00000

EDGE = (P0, N0, P1, N1, HALF, POW24, SUB, LEAST, BIG, PINF, NINF, QNAN, NQNAN)

# (name, width, operation names emitted for every input of that width)
GROUPS = (
    ('v2', 4, ('v2_min', 'v2_max')),
    ('v2c', 6, ('v2_clamp',)),
    ('v3', 6, ('v3_min', 'v3_max')),
    ('v3c', 9, ('v3_clamp',)),
    ('v4', 8, ('v4_min', 'v4_max')),
)


def product(words, width):
    rows = [()]
    for _ in range(width):
        rows = [row + (word,) for row in rows for word in words]
    return rows


def inputs(width, families, anchors):
    """Disjoint word families, then one-component sweeps of the wider edge."""
    seen, rows = set(), []
    for family in families:
        for row in product(family, width):
            if row not in seen:
                seen.add(row)
                rows.append(row)
    for anchor in anchors:
        for index, word in itertools.product(range(width), EDGE):
            args = list(anchor)
            args[index] = word
            key = tuple(args)
            if key not in seen:
                seen.add(key)
                rows.append(key)
    return rows


def tables():
    """Input rows for each group, built once so the oracle and the cases agree."""
    v2 = inputs(4, [(P0, N0, P1, SUB, PINF, QNAN)], (
        (P1, N1, P0, QNAN), (PINF, NINF, SUB, N0)))
    v2c = inputs(6, [(P0, N0, QNAN), (P1, N1, NQNAN), (PINF, NINF, SUB)], (
        (P1, N1, P0, N0, QNAN, NQNAN), (PINF, NINF, SUB, LEAST, BIG, HALF)))
    v3 = inputs(6, [(P0, N0, QNAN), (P1, N1, NQNAN), (PINF, NINF, SUB)], (
        (P1, N1, P0, N0, QNAN, NQNAN), (PINF, NINF, SUB, LEAST, BIG, HALF)))
    v3c = inputs(9, [(P0, N0), (QNAN, NQNAN), (P1, N1), (PINF, NINF)], (
        (P1, N1, P0, N0, QNAN, NQNAN, SUB, PINF, NINF),
        (HALF, BIG, LEAST, POW24, P0, N0, P1, N1, QNAN)))
    v4 = inputs(8, [(P0, N0), (QNAN, NQNAN), (P1, N1), (PINF, NINF)], (
        (P1, N1, P0, N0, QNAN, NQNAN, PINF, NINF),
        (HALF, BIG, LEAST, POW24, SUB, P0, N1, QNAN)))
    return {'v2': v2, 'v2c': v2c, 'v3': v3, 'v3c': v3c, 'v4': v4}


def cases(built):
    rows = []
    for key, _, names in GROUPS:
        for args in built[key]:
            for name in names:
                rows.append((name, args))
    return rows


def native(probe, built):
    """One loop per width, so each raymath function is inlined once."""
    def array(name, width, rows):
        lines = [f'static const unsigned {name}[][{width}] = {{']
        lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in rows)
        lines.append('};')
        return lines

    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Vector2 V2(unsigned x,unsigned y){return (Vector2){load(x),load(y)};}',
        'static Vector3 V3(unsigned x,unsigned y,unsigned z){return (Vector3){load(x),load(y),load(z)};}',
        'static Vector4 V4(unsigned x,unsigned y,unsigned z,unsigned w){return (Vector4){load(x),load(y),load(z),load(w)};}',
        'static void emit2(Vector2 v){printf("[%u,%u]\\n", bits(v.x), bits(v.y));}',
        'static void emit3(Vector3 v){printf("[%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z));}',
        'static void emit4(Vector4 v){printf("[%u,%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z), bits(v.w));}',
    ]
    lines += array('v2', 4, built['v2'])
    lines += array('v2c', 6, built['v2c'])
    lines += array('v3', 6, built['v3'])
    lines += array('v3c', 9, built['v3c'])
    lines += array('v4', 8, built['v4'])
    lines += [
        'int main(void){',
        '  for (unsigned i = 0; i < sizeof v2 / sizeof v2[0]; i++) {',
        '    Vector2 a = V2(v2[i][0], v2[i][1]);',
        '    Vector2 b = V2(v2[i][2], v2[i][3]);',
        '    emit2(Vector2Min(a, b));',
        '    emit2(Vector2Max(a, b));',
        '  }',
        '  for (unsigned i = 0; i < sizeof v2c / sizeof v2c[0]; i++) {',
        '    Vector2 v = V2(v2c[i][0], v2c[i][1]);',
        '    Vector2 lo = V2(v2c[i][2], v2c[i][3]);',
        '    Vector2 hi = V2(v2c[i][4], v2c[i][5]);',
        '    emit2(Vector2Clamp(v, lo, hi));',
        '  }',
        '  for (unsigned i = 0; i < sizeof v3 / sizeof v3[0]; i++) {',
        '    Vector3 a = V3(v3[i][0], v3[i][1], v3[i][2]);',
        '    Vector3 b = V3(v3[i][3], v3[i][4], v3[i][5]);',
        '    emit3(Vector3Min(a, b));',
        '    emit3(Vector3Max(a, b));',
        '  }',
        '  for (unsigned i = 0; i < sizeof v3c / sizeof v3c[0]; i++) {',
        '    Vector3 v = V3(v3c[i][0], v3c[i][1], v3c[i][2]);',
        '    Vector3 lo = V3(v3c[i][3], v3c[i][4], v3c[i][5]);',
        '    Vector3 hi = V3(v3c[i][6], v3c[i][7], v3c[i][8]);',
        '    emit3(Vector3Clamp(v, lo, hi));',
        '  }',
        '  for (unsigned i = 0; i < sizeof v4 / sizeof v4[0]; i++) {',
        '    Vector4 a = V4(v4[i][0], v4[i][1], v4[i][2], v4[i][3]);',
        '    Vector4 b = V4(v4[i][4], v4[i][5], v4[i][6], v4[i][7]);',
        '    emit4(Vector4Min(a, b));',
        '    emit4(Vector4Max(a, b));',
        '  }',
        '  (void)sink; return 0;',
        '}',
    ]
    source, binary = probe.work / 'reference.c', probe.work / 'reference'
    source.write_text('\n'.join(lines) + '\n')
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin-atan2f',
                   '-I' + str(probe.args.raylib_source / 'src'), source, '-lm', '-o', binary])
    return probekit.run([binary])


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def show2(value: M.Vector2) -> IO(Unit):
  M.Vector2{x, y} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y)]))
def show3(value: M.Vector3) -> IO(Unit):
  M.Vector3{x, y, z} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z)]))
def show4(value: M.Vector4) -> IO(Unit):
  M.Vector4{x, y, z, w} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w)]))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def vec(kind, words):
    fields = ', '.join(f'word({word})' for word in words)
    return f'M.{kind}{{{fields}}}'


def render(selected, gpu):
    body = PROGRAM
    libm = 'M.Glibc239Libm{}'
    for name, args in selected:
        if name == 'v2_min':
            call = f'M.Vector2.min_for({libm}, {vec("Vector2", args[:2])}, {vec("Vector2", args[2:])})'
            show = 'show2'
        elif name == 'v2_max':
            call = f'M.Vector2.max_for({libm}, {vec("Vector2", args[:2])}, {vec("Vector2", args[2:])})'
            show = 'show2'
        elif name == 'v2_clamp':
            call = (f'M.Vector2.clamp_for({libm}, {vec("Vector2", args[:2])}, '
                    f'{vec("Vector2", args[2:4])}, {vec("Vector2", args[4:])})')
            show = 'show2'
        elif name == 'v3_min':
            call = f'M.Vector3.min_for({libm}, {vec("Vector3", args[:3])}, {vec("Vector3", args[3:])})'
            show = 'show3'
        elif name == 'v3_max':
            call = f'M.Vector3.max_for({libm}, {vec("Vector3", args[:3])}, {vec("Vector3", args[3:])})'
            show = 'show3'
        elif name == 'v3_clamp':
            call = (f'M.Vector3.clamp_for({libm}, {vec("Vector3", args[:3])}, '
                    f'{vec("Vector3", args[3:6])}, {vec("Vector3", args[6:])})')
            show = 'show3'
        elif name == 'v4_min':
            call = f'M.Vector4.min_for({libm}, {vec("Vector4", args[:4])}, {vec("Vector4", args[4:])})'
            show = 'show4'
        elif name == 'v4_max':
            call = f'M.Vector4.max_for({libm}, {vec("Vector4", args[:4])}, {vec("Vector4", args[4:])})'
            show = 'show4'
        else:
            raise ProbeFailure(f'extrema: unknown operation {name}')
        body += f'    {show}({call})\n'
    return body


def sign_only(expected, actual):
    """True when two results differ only by NaN signs."""
    if type(expected) is int and type(actual) is int:
        if (expected & 0x7fffffff) <= 0x7f800000 or (actual & 0x7fffffff) <= 0x7f800000:
            return False
        return (expected ^ actual) == 0x80000000
    if type(expected) is list and type(actual) is list and len(expected) == len(actual):
        changed = False
        for left, right in zip(expected, actual):
            if left == right:
                continue
            if not sign_only(left, right):
                return False
            changed = True
        return changed
    return False


def compare(probe, expected, lanes, rows):
    """CPU lanes are exact. JavaScript may quiet a negative NaN's sign."""
    signs = Counter()
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'extrema: {lane} produced {len(actual)} rows, expected {len(expected)}')
        real = []
        for index, (want, got) in enumerate(zip(expected, actual)):
            if want == got:
                continue
            if lane == 'javascript' and sign_only(want, got):
                signs[rows[index][0]] += 1
            else:
                real.append(index)
        entry = dict(passed=not real, rows=len(actual), different=real[:20])
        if lane == 'javascript':
            entry['nan_sign'] = sum(signs.values())
        probe.report['lanes'][lane] = entry
        probe.save()
        if real:
            first = real[0]
            raise ProbeFailure(f'extrema: {lane} differs at {len(real)} rows; first '
                               f'{rows[first][0]} {tuple(hex(word) for word in rows[first][1])}: '
                               f'raylib={json.dumps(expected[first])} jonlib={json.dumps(actual[first])}')
    return signs


def main():
    probe = probekit.Probe('extrema', probekit.arguments(__doc__))
    built = tables()
    rows = cases(built)
    if len(rows) > 40000:
        raise ProbeFailure(f'extrema: {len(rows)} cases is more than the probe budget')
    text = native(probe, built)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'extrema: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=120, source_limit=48000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    signs = compare(probe, expected, lanes, rows)
    probe.finish(cases=len(rows), javascript_nan_sign=dict(signs),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
