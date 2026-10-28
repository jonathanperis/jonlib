#!/usr/bin/env python3
"""Compare raymath Vector4 and Quaternion component arithmetic on exceptional inputs.

Vector4 Add, AddValue, Subtract, SubtractValue, Scale, Multiply, Negate,
Divide, Invert, Length, LengthSqr, Dot, Distance, DistanceSqr, Normalize,
Equals and Lerp, and the Quaternion operations with the same component
formulas plus Hamilton Multiply, conjugate Invert, Normalize, Nlerp and
Equals, are compiled from the pinned raymath.h with contraction off
(`clang -O2 -fno-builtin-atan2f`, `FP_CONTRACT OFF`). Inputs live in a table
so clang emits the arithmetic instead of constant-folding the literals. A
fresh quiet NaN is folded to the canonical positive payload before an exact
comparison. Every other bit stays exact on CPU-1, CPU-2 and JavaScript. A
payload change or a NaN where raylib returned a number fails on every lane.
Slerp and the axis/Euler conversions stay out:
they call libm functions whose host profiles are not this corpus. Vector4 min
and max stay on the signed-zero profiles.
"""
import hashlib
import json
from itertools import product

import probekit
import quiet_nan
from probekit import ProbeFailure, run

# Eight components make a 3-word grid 6561 pairs. Three disjoint 2-word
# families stay inside the probe budget; the wider edge is swept one slot
# at a time.
GRIDS = (
    (0x00000000, 0x7f800000),
    (0x80000000, 0x7fc00000),
    (0x3f800000, 0x00000001),
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
VPAIR = (
    ('add', 'Vector4Add({a}, {b})', 'M.Vector4.add({a}, {b})', 'v'),
    ('subtract', 'Vector4Subtract({a}, {b})', 'M.Vector4.subtract({a}, {b})', 'v'),
    ('multiply', 'Vector4Multiply({a}, {b})', 'M.Vector4.multiply({a}, {b})', 'v'),
    ('divide', 'Vector4Divide({a}, {b})', 'M.Vector4.divide({a}, {b})', 'v'),
    ('negate', 'Vector4Negate({a})', 'M.Vector4.negate({a})', 'v'),
    ('invert', 'Vector4Invert({a})', 'M.Vector4.invert({a})', 'v'),
    ('normalize', 'Vector4Normalize({a})', 'M.Vector4.normalize({a})', 'v'),
    ('length', 'Vector4Length({a})', 'M.Vector4.length({a})', 'f'),
    ('length_sqr', 'Vector4LengthSqr({a})', 'M.Vector4.length_sqr({a})', 'f'),
    ('dot', 'Vector4DotProduct({a}, {b})', 'M.Vector4.dot_product({a}, {b})', 'f'),
    ('distance', 'Vector4Distance({a}, {b})', 'M.Vector4.distance({a}, {b})', 'f'),
    ('distance_sqr', 'Vector4DistanceSqr({a}, {b})', 'M.Vector4.distance_sqr({a}, {b})', 'f'),
    ('equals', 'Vector4Equals({a}, {b})', 'M.Vector4.equals({a}, {b})', 'b'),
)
QPAIR = (
    ('q_add', 'QuaternionAdd({a}, {b})', 'M.Quaternion.add({a}, {b})', 'v'),
    ('q_subtract', 'QuaternionSubtract({a}, {b})', 'M.Quaternion.subtract({a}, {b})', 'v'),
    ('q_multiply', 'QuaternionMultiply({a}, {b})', 'M.Quaternion.multiply({a}, {b})', 'v'),
    ('q_divide', 'QuaternionDivide({a}, {b})', 'M.Quaternion.divide({a}, {b})', 'v'),
    ('q_invert', 'QuaternionInvert({a})', 'M.Quaternion.invert({a})', 'v'),
    ('q_normalize', 'QuaternionNormalize({a})', 'M.Quaternion.normalize({a})', 'v'),
    ('q_length', 'QuaternionLength({a})', 'M.Quaternion.length({a})', 'f'),
    ('q_equals', 'QuaternionEquals({a}, {b})', 'M.Quaternion.equals({a}, {b})', 'b'),
)
VSCALAR = (
    ('add_value', 'Vector4AddValue({a}, {s})', 'M.Vector4.add_value({a}, word({s}))', 'v'),
    ('subtract_value', 'Vector4SubtractValue({a}, {s})', 'M.Vector4.subtract_value({a}, word({s}))', 'v'),
    ('scale', 'Vector4Scale({a}, {s})', 'M.Vector4.scale({a}, word({s}))', 'v'),
)
QSCALAR = (
    ('q_add_value', 'QuaternionAddValue({a}, {s})', 'M.Quaternion.add_value({a}, word({s}))', 'v'),
    ('q_subtract_value', 'QuaternionSubtractValue({a}, {s})', 'M.Quaternion.subtract_value({a}, word({s}))', 'v'),
    ('q_scale', 'QuaternionScale({a}, {s})', 'M.Quaternion.scale({a}, word({s}))', 'v'),
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
    return _sweep(8, (
        (0x3f800000, 0xbf800000, 0x3fc00000, 0x4b800000, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00000),
        (0x00000000, 0x00000001, 0x00800000, 0x7f7fffff, 0x7fc00000, 0xbf800000, 0x7f800000, 0x80000000),
    ))


def quints():
    return _sweep(5, (
        (0x3f800000, 0xbf800000, 0x7f800000, 0x7fc00000, 0x00000000),
        (0x00000001, 0x00800000, 0x7f7fffff, 0xff800000, 0x4b800000),
    ))


def cases():
    rows = []
    for args in pairs():
        for name, _, _, _ in VPAIR + QPAIR:
            rows.append((name, args))
        for amount in AMOUNTS:
            wider = args + (amount,)
            rows.append(('lerp', wider))
            rows.append(('q_lerp', wider))
            rows.append(('q_nlerp', wider))
    for args in quints():
        for name, _, _, _ in VSCALAR + QSCALAR:
            rows.append((name, args))
    return rows


def native(probe, rows):
    """One loop over the input tables, so each raymath function is inlined once."""
    pair_rows = [args for name, args in rows if name == 'add']
    quint_rows = [args for name, args in rows if name == 'add_value']
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Vector4 V(unsigned x,unsigned y,unsigned z,unsigned w){return (Vector4){load(x),load(y),load(z),load(w)};}',
        'static void emit4(Vector4 v){printf("[%u,%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z), bits(v.w));}',
        'static void emit1(float x){printf("%u\\n", bits(x));}',
        'static void emitb(int x){printf("%s\\n", x ? "true" : "false");}',
        'static const unsigned pairs[][8] = {',
    ]
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in pair_rows)
    lines.append('};')
    lines.append('static const unsigned quints[][5] = {')
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in quint_rows)
    lines.append('};')
    lines.append('static const unsigned amounts[] = {' + ','.join(f'0x{word:08x}u' for word in AMOUNTS) + '};')
    lines.append('int main(void){')
    lines.append('  for (unsigned i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {')
    lines.append('    Vector4 a = V(pairs[i][0], pairs[i][1], pairs[i][2], pairs[i][3]);')
    lines.append('    Vector4 b = V(pairs[i][4], pairs[i][5], pairs[i][6], pairs[i][7]);')
    for group in (VPAIR, QPAIR):
        for _, expr, _, shape in group:
            emit = {'v': 'emit4', 'f': 'emit1', 'b': 'emitb'}[shape]
            lines.append(f'    {emit}({expr.format(a="a", b="b")});')
    lines.append('    for (unsigned k = 0; k < sizeof amounts / sizeof amounts[0]; k++) {')
    lines.append('      float amount = load(amounts[k]);')
    lines.append('      emit4(Vector4Lerp(a, b, amount));')
    lines.append('      emit4(QuaternionLerp(a, b, amount));')
    lines.append('      emit4(QuaternionNlerp(a, b, amount));')
    lines.append('    }')
    lines.append('  }')
    lines.append('  for (unsigned i = 0; i < sizeof quints / sizeof quints[0]; i++) {')
    lines.append('    Vector4 a = V(quints[i][0], quints[i][1], quints[i][2], quints[i][3]);')
    lines.append('    float s = load(quints[i][4]);')
    for group in (VSCALAR, QSCALAR):
        for _, expr, _, _ in group:
            lines.append(f'    emit4({expr.format(a="a", s="s")});')
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
def show4(value: M.Vector4) -> IO(Unit):
  M.Vector4{x, y, z, w} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w)]))
def flag(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("true")
    case False{}: IO.print("false")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def vec(x, y, z, w):
    return f'M.Vector4{{word({x}), word({y}), word({z}), word({w})}}'


def render(selected, gpu):
    bend = {name: expr for name, _, expr, _ in VPAIR + QPAIR + VSCALAR + QSCALAR}
    scalar = {name for name, _, _, _ in VSCALAR + QSCALAR}
    shape = {name: kind for name, _, _, kind in VPAIR + QPAIR + VSCALAR + QSCALAR}
    for name in ('lerp', 'q_lerp', 'q_nlerp'):
        shape[name] = 'v'
    bend['lerp'] = 'M.Vector4.lerp({a}, {b}, word({s}))'
    bend['q_lerp'] = 'M.Quaternion.lerp({a}, {b}, word({s}))'
    bend['q_nlerp'] = 'M.Quaternion.nlerp({a}, {b}, word({s}))'
    emitter = {'v': 'show4', 'f': 'show', 'b': 'flag'}
    body = PROGRAM
    for name, args in selected:
        if name in ('lerp', 'q_lerp', 'q_nlerp'):
            *components, amount = args
            call = bend[name].format(a=vec(*components[:4]), b=vec(*components[4:8]), s=amount)
        elif name in scalar:
            *components, value = args
            call = bend[name].format(a=vec(*components), s=value)
        else:
            call = bend[name].format(a=vec(*args[:4]), b=vec(*args[4:8]))
        body += f'    {emitter[shape[name]]}({call})\n'
    return body


def aligned(rows, values):
    return [quiet_nan.canonical(name, args, value) for (name, args), value in zip(rows, values)]


def main():
    probe = probekit.Probe('vector4', probekit.arguments(__doc__))
    rows = cases()
    if len(rows) > 40000:
        raise ProbeFailure(f'vector4: {len(rows)} cases is more than the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'vector4: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=100, source_limit=48000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    expected_n = aligned(rows, expected)
    lanes_n = {lane: aligned(rows, values) for lane, values in lanes.items()}
    fresh = sum(before != after for before, after in zip(expected, expected_n))
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0]} {tuple(hex(word) for word in rows[i][1])}')
    probe.finish(cases=len(rows), fresh_nan_rows=fresh,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
