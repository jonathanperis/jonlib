#!/usr/bin/env python3
"""Compare raymath Vector3 component arithmetic on exceptional inputs.

Add, AddValue, Subtract, SubtractValue, Scale, Multiply, Negate, Divide and
Invert, plus Length, LengthSqr, Dot, Cross, Distance, DistanceSqr, Normalize,
Reflect, Equals and Lerp, are compiled from the pinned raymath.h with
contraction off (`clang -O2 -fno-builtin-atan2f`, `FP_CONTRACT OFF`). Inputs
live in a table so clang emits the arithmetic instead of constant-folding the
literals. The sign of a quiet NaN that arithmetic produces is not part of the
comparison: clang's divss/mulss sign and Bend's runtime operation disagree,
and the JavaScript sign is not stable. Negate, Invert, Length, LengthSqr and
Equals matched every bit on this corpus, so a sign difference there still
fails. Normalize scales by a reciprocal length, and that product's quiet-NaN
sign is not reproduced. A payload change or a NaN where raylib returned a
number fails on every lane. Min, max and clamp stay on the signed-zero
profiles. Angle stays on atan2.
"""
import hashlib
import json
from collections import Counter
from itertools import product

import probekit
from probekit import ProbeFailure, run

# Two disjoint 3-word families. Six components of one family is 729 vectors;
# the full 6-word grid used for Vector2 would be 46656 pairs.
GRIDS = (
    (0x00000000, 0x7f800000, 0x7fc00000),
    (0x80000000, 0x3f800000, 0x00000001),
)
EDGE = (
    0x00000000, 0x80000000,
    0x3f800000, 0xbf800000,
    0x3fc00000, 0x4b800000,
    0x00000001, 0x00800000,
    0x7f7fffff,
    0x7f800000, 0xff800000,
    0x7fc00000,
)
AMOUNTS = (0x00000000, 0x3f800000, 0x7f800000, 0x7fc00000)

# (name, C expression, Bend expression, 'v' vector / 'f' float / 'b' bool)
PAIR = (
    ('add', 'Vector3Add({a}, {b})', 'M.Vector3.add({a}, {b})', 'v'),
    ('subtract', 'Vector3Subtract({a}, {b})', 'M.Vector3.subtract({a}, {b})', 'v'),
    ('multiply', 'Vector3Multiply({a}, {b})', 'M.Vector3.multiply({a}, {b})', 'v'),
    ('divide', 'Vector3Divide({a}, {b})', 'M.Vector3.divide({a}, {b})', 'v'),
    ('negate', 'Vector3Negate({a})', 'M.Vector3.negate({a})', 'v'),
    ('invert', 'Vector3Invert({a})', 'M.Vector3.invert({a})', 'v'),
    ('reflect', 'Vector3Reflect({a}, {b})', 'M.Vector3.reflect({a}, {b})', 'v'),
    ('normalize', 'Vector3Normalize({a})', 'M.Vector3.normalize({a})', 'v'),
    ('length', 'Vector3Length({a})', 'M.Vector3.length({a})', 'f'),
    ('length_sqr', 'Vector3LengthSqr({a})', 'M.Vector3.length_sqr({a})', 'f'),
    ('dot', 'Vector3DotProduct({a}, {b})', 'M.Vector3.dot_product({a}, {b})', 'f'),
    ('cross', 'Vector3CrossProduct({a}, {b})', 'M.Vector3.cross_product({a}, {b})', 'v'),
    ('distance', 'Vector3Distance({a}, {b})', 'M.Vector3.distance({a}, {b})', 'f'),
    ('distance_sqr', 'Vector3DistanceSqr({a}, {b})', 'M.Vector3.distance_sqr({a}, {b})', 'f'),
    ('equals', 'Vector3Equals({a}, {b})', 'M.Vector3.equals({a}, {b})', 'b'),
)
SCALAR = (
    ('add_value', 'Vector3AddValue({a}, {s})', 'M.Vector3.add_value({a}, word({s}))', 'v'),
    ('subtract_value', 'Vector3SubtractValue({a}, {s})', 'M.Vector3.subtract_value({a}, word({s}))', 'v'),
    ('scale', 'Vector3Scale({a}, {s})', 'M.Vector3.scale({a}, word({s}))', 'v'),
)


def _sweep(width, anchors):
    rows = []
    seen = set()
    for grid in GRIDS:
        for combo in product(grid, repeat=width):
            seen.add(combo)
            rows.append(combo)
    for anchor in anchors:
        for index in range(width):
            for word in EDGE:
                args = list(anchor)
                args[index] = word
                key = tuple(args)
                if key not in seen:
                    seen.add(key)
                    rows.append(key)
    return rows


def pairs():
    """Vector pairs: two 3-word grids, then one-component sweeps of the wider edge."""
    return _sweep(6, (
        (0x3f800000, 0xbf800000, 0x3fc00000, 0x80000000, 0x7f800000, 0x7fc00000),
        (0x00000000, 0x80000000, 0x7f800000, 0xff800000, 0x00000001, 0x7f7fffff),
        (0x00800000, 0x4b800000, 0xbf800000, 0x7fc00000, 0x00000000, 0x3f800000),
    ))


def quads():
    """(x, y, z, scalar) for AddValue, SubtractValue and Scale."""
    return _sweep(4, (
        (0x3f800000, 0xbf800000, 0x00000000, 0x7fc00000),
        (0x7f800000, 0xff800000, 0x00000001, 0x7f7fffff),
        (0x00800000, 0x4b800000, 0x80000000, 0x3fc00000),
    ))


def cases():
    """One row is (function name, argument words)."""
    rows = []
    for args in pairs():
        for name, _, _, _ in PAIR:
            rows.append((name, args))
        for amount in AMOUNTS:
            rows.append(('lerp', args + (amount,)))
    for args in quads():
        for name, _, _, _ in SCALAR:
            rows.append((name, args))
    return rows


def native(probe, rows):
    """One loop over the input tables, so each raymath function is inlined once."""
    pair_rows = [args for name, args in rows if name == 'add']
    quad_rows = [args for name, args in rows if name == 'add_value']
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Vector3 V(unsigned x,unsigned y,unsigned z){return (Vector3){load(x),load(y),load(z)};}',
        'static void emit3(Vector3 v){printf("[%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z));}',
        'static void emit1(float x){printf("%u\\n", bits(x));}',
        'static void emitb(int x){printf("%s\\n", x ? "true" : "false");}',
        'static const unsigned pairs[][6] = {',
    ]
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in pair_rows)
    lines.append('};')
    lines.append('static const unsigned quads[][4] = {')
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in quad_rows)
    lines.append('};')
    lines.append('static const unsigned amounts[] = {' + ','.join(f'0x{word:08x}u' for word in AMOUNTS) + '};')
    lines.append('int main(void){')
    lines.append('  for (unsigned i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {')
    lines.append('    Vector3 a = V(pairs[i][0], pairs[i][1], pairs[i][2]);')
    lines.append('    Vector3 b = V(pairs[i][3], pairs[i][4], pairs[i][5]);')
    for _, expr, _, shape in PAIR:
        emit = {'v': 'emit3', 'f': 'emit1', 'b': 'emitb'}[shape]
        lines.append(f'    {emit}({expr.format(a="a", b="b")});')
    lines.append('    for (unsigned k = 0; k < sizeof amounts / sizeof amounts[0]; k++)')
    lines.append('      emit3(Vector3Lerp(a, b, load(amounts[k])));')
    lines.append('  }')
    lines.append('  for (unsigned i = 0; i < sizeof quads / sizeof quads[0]; i++) {')
    lines.append('    Vector3 a = V(quads[i][0], quads[i][1], quads[i][2]);')
    lines.append('    float s = load(quads[i][3]);')
    for _, expr, _, _ in SCALAR:
        lines.append(f'    emit3({expr.format(a="a", s="s")});')
    lines.append('  }')
    lines.append('  (void)sink; return 0;}')
    source, binary = probe.work / 'reference.c', probe.work / 'reference'
    source.write_text('\n'.join(lines) + '\n')
    run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin-atan2f',
         '-I' + str(probe.args.raylib_source / 'src'), source, '-lm', '-o', binary])
    return run([binary])


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def show(value: F32) -> IO(Unit):
  IO.print(U32.show(F32.bits(value)))
def show3(value: M.Vector3) -> IO(Unit):
  M.Vector3{x, y, z} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z)]))
def flag(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("true")
    case False{}: IO.print("false")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def vec(x, y, z):
    return f'M.Vector3{{word({x}), word({y}), word({z})}}'


def render(selected, gpu):
    bend = {name: expr for name, _, expr, _ in PAIR}
    scalar = {name: expr for name, _, expr, _ in SCALAR}
    shape = {name: kind for name, _, _, kind in PAIR + SCALAR}
    shape['lerp'] = 'v'
    emitter = {'v': 'show3', 'f': 'show', 'b': 'flag'}
    body = PROGRAM
    for name, args in selected:
        if name == 'lerp':
            ax, ay, az, bx, by, bz, amount = args
            call = f'M.Vector3.lerp({vec(ax, ay, az)}, {vec(bx, by, bz)}, word({amount}))'
        elif name in scalar:
            x, y, z, value = args
            call = scalar[name].format(a=vec(x, y, z), s=value)
        else:
            ax, ay, az, bx, by, bz = args
            call = bend[name].format(a=vec(ax, ay, az), b=vec(bx, by, bz))
        body += f'    {emitter[shape[name]]}({call})\n'
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


# These matched every bit of the corpus, including quiet-NaN signs.
# Normalize is not in this set: scaling by the reciprocal length flips one
# quiet-NaN sign on CPU.
EXACT = frozenset({'negate', 'invert', 'length', 'length_sqr', 'equals'})


def compare(probe, expected, lanes, rows):
    """Exact bits, except the quiet-NaN sign of operations that do not reproduce it."""
    signs = Counter()
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'vector3: {lane} produced {len(actual)} rows, expected {len(expected)}')
        real = []
        for index, (want, got) in enumerate(zip(expected, actual)):
            if want == got:
                continue
            if rows[index][0] not in EXACT and sign_only(want, got):
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
            raise ProbeFailure(f'vector3: {lane} differs at {len(real)} rows; first '
                               f'{rows[first][0]} {tuple(hex(word) for word in rows[first][1])}: '
                               f'raylib={json.dumps(expected[first])} jonlib={json.dumps(actual[first])}')
    return signs


def main():
    probe = probekit.Probe('vector3', probekit.arguments(__doc__))
    rows = cases()
    if len(rows) > 40000:
        raise ProbeFailure(f'vector3: {len(rows)} cases is more than the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'vector3: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=140, source_limit=48000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    signs = compare(probe, expected, lanes, rows)
    probe.finish(cases=len(rows), javascript_nan_sign=dict(signs),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
