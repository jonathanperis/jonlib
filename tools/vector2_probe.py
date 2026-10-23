#!/usr/bin/env python3
"""Compare raymath Vector2 component arithmetic on exceptional inputs.

Add, AddValue, Subtract, SubtractValue, Scale, Multiply, Negate, Divide and
Invert, plus the component reductions Length, LengthSqr, Dot, Cross, Distance,
DistanceSqr, Normalize, Reflect, Equals and Lerp, are compiled from the pinned
raymath.h with contraction off (`clang -O2 -fno-builtin-atan2f`, `FP_CONTRACT
OFF`). Each input word is loaded through a volatile. Every result bit (and Equals' boolean) is compared on CPU-1, CPU-2 and
JavaScript. Inputs live in a table so clang emits the arithmetic instead of
constant-folding the literals. The sign of a quiet NaN that arithmetic
produces is not part of the comparison: clang's divss/mulss sign and Bend's
runtime operation disagree, and the JavaScript sign is not stable. Negate,
Invert, Normalize, Length, LengthSqr and Equals matched every bit on the
corpus, so a sign difference there still fails the probe. A payload change
or a NaN where raylib returned a number fails on every lane.
"""
import hashlib
import json
from collections import Counter

import probekit
from probekit import ProbeFailure, run

# The full grid uses the six words that define the exceptional corners.
# The other edge words are swept one component at a time.
CORE = (
    0x00000000, 0x80000000,
    0x3f800000, 0x00000001,
    0x7f800000, 0x7fc00000,
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
# Lerp amounts kept small: the component formula is Math.lerp, already
# compared on a wider scalar corpus.
AMOUNTS = (0x00000000, 0x3f800000, 0x7f800000, 0x7fc00000)

# (name, C expression with a and b in scope, Bend expression, 'v' vector / 'f' float / 'b' bool)
PAIR = (
    ('add', 'Vector2Add({a}, {b})', 'M.Vector2.add({a}, {b})', 'v'),
    ('subtract', 'Vector2Subtract({a}, {b})', 'M.Vector2.subtract({a}, {b})', 'v'),
    ('multiply', 'Vector2Multiply({a}, {b})', 'M.Vector2.multiply({a}, {b})', 'v'),
    ('divide', 'Vector2Divide({a}, {b})', 'M.Vector2.divide({a}, {b})', 'v'),
    ('negate', 'Vector2Negate({a})', 'M.Vector2.negate({a})', 'v'),
    ('invert', 'Vector2Invert({a})', 'M.Vector2.invert({a})', 'v'),
    ('reflect', 'Vector2Reflect({a}, {b})', 'M.Vector2.reflect({a}, {b})', 'v'),
    ('normalize', 'Vector2Normalize({a})', 'M.Vector2.normalize({a})', 'v'),
    ('length', 'Vector2Length({a})', 'M.Vector2.length({a})', 'f'),
    ('length_sqr', 'Vector2LengthSqr({a})', 'M.Vector2.length_sqr({a})', 'f'),
    ('dot', 'Vector2DotProduct({a}, {b})', 'M.Vector2.dot_product({a}, {b})', 'f'),
    ('cross', 'Vector2CrossProduct({a}, {b})', 'M.Vector2.cross_product({a}, {b})', 'f'),
    ('distance', 'Vector2Distance({a}, {b})', 'M.Vector2.distance({a}, {b})', 'f'),
    ('distance_sqr', 'Vector2DistanceSqr({a}, {b})', 'M.Vector2.distance_sqr({a}, {b})', 'f'),
    ('equals', 'Vector2Equals({a}, {b})', 'M.Vector2.equals({a}, {b})', 'b'),
)
SCALAR = (
    ('add_value', 'Vector2AddValue({a}, {s})', 'M.Vector2.add_value({a}, word({s}))', 'v'),
    ('subtract_value', 'Vector2SubtractValue({a}, {s})', 'M.Vector2.subtract_value({a}, word({s}))', 'v'),
    ('scale', 'Vector2Scale({a}, {s})', 'M.Vector2.scale({a}, word({s}))', 'v'),
)


def pairs():
    """Vector pairs: the core grid, then one-component sweeps of the wider edge."""
    rows = [(ax, ay, bx, by) for ax in CORE for ay in CORE for bx in CORE for by in CORE]
    seen = set(rows)
    anchors = (
        (0x3f800000, 0x00000000, 0xbf800000, 0x3fc00000),
        (0x00000000, 0x80000000, 0x7f800000, 0xff800000),
        (0x00000001, 0x7fc00000, 0x7f7fffff, 0x00800000),
    )
    for anchor in anchors:
        for index in range(4):
            for word in EDGE:
                args = list(anchor)
                args[index] = word
                key = tuple(args)
                if key not in seen:
                    seen.add(key)
                    rows.append(key)
    return rows


def triples():
    """(x, y, scalar) for AddValue, SubtractValue and Scale."""
    rows = [(x, y, scalar) for x in CORE for y in CORE for scalar in CORE]
    seen = set(rows)
    anchors = (
        (0x3f800000, 0xbf800000, 0x00000000),
        (0x7f800000, 0xff800000, 0x7fc00000),
        (0x00000001, 0x00800000, 0x7f7fffff),
    )
    for anchor in anchors:
        for index in range(3):
            for word in EDGE:
                args = list(anchor)
                args[index] = word
                key = tuple(args)
                if key not in seen:
                    seen.add(key)
                    rows.append(key)
    return rows


def cases():
    """One row is (function name, argument words). A vector result is one JSON list."""
    rows = []
    for args in pairs():
        for name, _, _, _ in PAIR:
            rows.append((name, args))
        for amount in AMOUNTS:
            rows.append(('lerp', args + (amount,)))
    for args in triples():
        for name, _, _, _ in SCALAR:
            rows.append((name, args))
    return rows


def native(probe, rows):
    """One loop over the input tables, so each raymath function is inlined once.

    The printed order is the order of `cases`: every pair operation, then Lerp
    for each amount, then the scalar-value operations.
    """
    pair_rows = [args for name, args in rows if name == 'add']
    triple_rows = [args for name, args in rows if name == 'add_value']
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Vector2 V(unsigned x,unsigned y){return (Vector2){load(x),load(y)};}',
        'static void emit2(Vector2 v){printf("[%u,%u]\\n", bits(v.x), bits(v.y));}',
        'static void emit1(float x){printf("%u\\n", bits(x));}',
        'static void emitb(int x){printf("%s\\n", x ? "true" : "false");}',
        'static const unsigned pairs[][4] = {',
    ]
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in pair_rows)
    lines.append('};')
    lines.append('static const unsigned triples[][3] = {')
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in triple_rows)
    lines.append('};')
    lines.append('static const unsigned amounts[] = {' + ','.join(f'0x{word:08x}u' for word in AMOUNTS) + '};')
    lines.append('int main(void){')
    lines.append('  for (unsigned i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {')
    lines.append('    Vector2 a = V(pairs[i][0], pairs[i][1]);')
    lines.append('    Vector2 b = V(pairs[i][2], pairs[i][3]);')
    for name, expr, _, shape in PAIR:
        emit = {'v': 'emit2', 'f': 'emit1', 'b': 'emitb'}[shape]
        lines.append(f'    {emit}({expr.format(a="a", b="b")});')
    lines.append('    for (unsigned k = 0; k < sizeof amounts / sizeof amounts[0]; k++)')
    lines.append('      emit2(Vector2Lerp(a, b, load(amounts[k])));')
    lines.append('  }')
    lines.append('  for (unsigned i = 0; i < sizeof triples / sizeof triples[0]; i++) {')
    lines.append('    Vector2 a = V(triples[i][0], triples[i][1]);')
    lines.append('    float s = load(triples[i][2]);')
    for name, expr, _, shape in SCALAR:
        lines.append(f'    emit2({expr.format(a="a", s="s")});')
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
def show2(value: M.Vector2) -> IO(Unit):
  M.Vector2{x, y} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y)]))
def flag(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("true")
    case False{}: IO.print("false")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def vec(x, y):
    return f'M.Vector2{{word({x}), word({y})}}'


def render(selected, gpu):
    bend = {name: expr for name, _, expr, _ in PAIR}
    scalar = {name: expr for name, _, expr, _ in SCALAR}
    shape = {name: kind for name, _, _, kind in PAIR + SCALAR}
    shape['lerp'] = 'v'
    emitter = {'v': 'show2', 'f': 'show', 'b': 'flag'}
    body = PROGRAM
    for name, args in selected:
        if name == 'lerp':
            ax, ay, bx, by, amount = args
            call = f'M.Vector2.lerp({vec(ax, ay)}, {vec(bx, by)}, word({amount}))'
        elif name in scalar:
            x, y, value = args
            call = scalar[name].format(a=vec(x, y), s=value)
        else:
            ax, ay, bx, by = args
            call = bend[name].format(a=vec(ax, ay), b=vec(bx, by))
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
EXACT = frozenset({'negate', 'invert', 'normalize', 'length', 'length_sqr', 'equals'})


def compare(probe, expected, lanes, rows):
    """Exact bits, except the quiet-NaN sign of operations that do not reproduce it."""
    signs = Counter()
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'vector2: {lane} produced {len(actual)} rows, expected {len(expected)}')
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
            raise ProbeFailure(f'vector2: {lane} differs at {len(real)} rows; first '
                               f'{rows[first][0]} {tuple(hex(word) for word in rows[first][1])}: '
                               f'raylib={json.dumps(expected[first])} jonlib={json.dumps(actual[first])}')
    return signs


def main():
    probe = probekit.Probe('vector2', probekit.arguments(__doc__))
    rows = cases()
    if len(rows) > 40000:
        raise ProbeFailure(f'vector2: {len(rows)} cases is more than the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'vector2: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=160, source_limit=48000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    signs = compare(probe, expected, lanes, rows)
    probe.finish(cases=len(rows), javascript_nan_sign=dict(signs),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
