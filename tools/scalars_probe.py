#!/usr/bin/env python3
"""Compare raymath's scalar functions on exceptional and subnormal inputs.

Clamp, Lerp, Normalize, Remap, Wrap and FloatEquals are compiled from the
pinned raymath.h with contraction off, the same flags as the main corpus
(`clang -O2 -fno-builtin-atan2f`, `FP_CONTRACT OFF`). Each input word is loaded
through a volatile so `floorf`, `fabsf` and `fmaxf` run as they do for a
non-constant call, not as a folded literal. Every result bit (and FloatEquals'
boolean) is compared on CPU-1, CPU-2 and JavaScript. A fresh quiet NaN is
folded to the canonical positive payload before that exact comparison. Every
other bit stays exact. A payload change, a NaN where raylib returned a
number, or any other difference fails the probe.

On arm64 Lerp, Remap and Wrap are also compared under M.Fused{} against the
same raymath compiled with clang's default `-ffp-contract=on` (each a*b + c of
one expression fused), on the same inputs plus seeded finite ones whose
roundings differ when fused. Other hosts have no contracted reference and
skip those rows.
"""
import hashlib
import json
import platform
import random
import struct

import fused_rows
import probekit
import quiet_nan
from probekit import ProbeFailure, run

# Signed zeros, a fraction, the 2^24 floor boundary, a subnormal, the least
# normal, the largest finite, both infinities and a quiet NaN.
EDGE = (
    0x00000000, 0x80000000,
    0x3f800000, 0xbf800000,
    0x3fc00000, 0x4b800000,
    0x00000001, 0x00800000,
    0x7f7fffff,
    0x7f800000, 0xff800000,
    0x7fc00000,
)
# Remap's full grid is four of those words; the rest are swept one argument
# at a time so five-argument products stay inside one compile budget.
REMAP = (0x00000000, 0x3f800000, 0xbf800000, 0x7fc00000)

FUNCTIONS = {
    'clamp': ('Clamp', 'math_clamp_owned({})', 'f'),
    'lerp': ('Lerp', 'M.Math.lerp({})', 'f'),
    'normalize': ('Normalize', 'math_normalize_owned({})', 'f'),
    'remap': ('Remap', 'M.Math.remap({})', 'f'),
    'wrap': ('Wrap', 'M.Math.wrap({})', 'f'),
    'float_equals': ('FloatEquals', 'math_float_equals_owned({})', 'b'),
    'fused_lerp': ('Lerp', 'math_lerp_for_owned(M.Fused{{}}, {})', 'f'),
    'fused_remap': ('Remap', 'math_remap_for_owned(M.Fused{{}}, {})', 'f'),
    'fused_wrap': ('Wrap', 'math_wrap_for_owned(M.Fused{{}}, {})', 'f'),
}
FUSED = ('lerp', 'remap', 'wrap')


def fused_cases():
    """The contracted three on the exceptional rows and on seeded finite ones."""
    rows = [('fused_' + name, args) for name, args in cases() if name in FUSED]
    rng = random.Random(0xF05ED5)

    def word():
        return (rng.getrandbits(1) << 31) | (rng.randrange(97, 158) << 23) | rng.getrandbits(23)

    def unit():
        return struct.unpack('<I', struct.pack('<f', rng.random()))[0]
    for _ in range(1500):
        rows.append(('fused_lerp', (word(), word(), unit())))
        rows.append(('fused_remap', (word(), word(), word(), word(), word())))
        low = word()
        rows.append(('fused_wrap', (word(), low, word())))
    return rows


def cases():
    """One row is (function name, argument words)."""
    rows = []
    triples = ('clamp', 'lerp', 'normalize', 'wrap')
    for name in triples:
        for a in EDGE:
            for b in EDGE:
                for c in EDGE:
                    rows.append((name, (a, b, c)))
    for left in EDGE:
        for right in EDGE:
            rows.append(('float_equals', (left, right)))
    anchors = (
        (0x3f800000, 0x00000000, 0x40000000, 0x00000000, 0x3f800000),
        (0xbf800000, 0x7f800000, 0xff800000, 0x7fc00000, 0x3fc00000),
        (0x00000001, 0x80000000, 0x3f800000, 0xbf800000, 0x00000000),
    )
    for anchor in anchors:
        for index in range(5):
            for word in EDGE:
                args = list(anchor)
                args[index] = word
                rows.append(('remap', tuple(args)))
    for a in REMAP:
        for b in REMAP:
            for c in REMAP:
                for d in REMAP:
                    for e in REMAP:
                        rows.append(('remap', (a, b, c, d, e)))
    return rows


def native_fused(probe, rows):
    """The fused rows as one table loop (contraction on), checked at -O1, -O2 and -O3."""
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static const unsigned rows[][6] = {',
    ]
    kinds = {'fused_lerp': 0, 'fused_remap': 1, 'fused_wrap': 2}
    for name, args in rows:
        words = [kinds[name], *args, *([0] * (5 - len(args)))]
        lines.append('  {' + ','.join(f'0x{word:08x}u' for word in words) + '},')
    lines += [
        '};',
        'int main(void){',
        '  for (unsigned i = 0; i < sizeof rows / sizeof rows[0]; i++) {',
        '    float a = load(rows[i][1]), b = load(rows[i][2]), c = load(rows[i][3]), d = load(rows[i][4]), e = load(rows[i][5]);',
        '    float r = rows[i][0] == 0 ? Lerp(a, b, c) : rows[i][0] == 1 ? Remap(a, b, c, d, e) : Wrap(a, b, c);',
        '    printf("%u\\n", bits(r));',
        '  }',
        '  (void)sink; return 0;}',
    ]
    source = probe.work / 'reference-fused.c'
    source.write_text('\n'.join(lines) + '\n')
    return fused_rows.levels(probe, source)


def native(probe, rows):
    lines = [
        '#include <stdio.h>', '#include <string.h>', '#include <stdint.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'int main(void){',
    ]
    for name, args in rows:
        loaded = ', '.join(f'load(0x{word:08x}u)' for word in args)
        call = f'{FUNCTIONS[name][0]}({loaded})'
        if FUNCTIONS[name][2] == 'b':
            lines.append(f'printf("%s\\n", {call} ? "true" : "false");')
        else:
            lines.append(f'printf("%u\\n", bits({call}));')
    lines.append('(void)sink; return 0;}')
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
def flag(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("true")
    case False{}: IO.print("false")
# Ownership: these defs copy the library signatures (+ borrows, the rest
# consumed) and return values the caller owns; the affine checker
# enforces them on every compared call.
def math_clamp_owned(+value: F32, +lower: F32, +upper: F32) -> F32:
  M.Math.clamp(value, lower, upper)
def math_normalize_owned(value: F32, +start: F32, end: F32) -> F32:
  M.Math.normalize(value, start, end)
def math_float_equals_owned(+left: F32, +right: F32) -> Bool:
  M.Math.float_equals(left, right)
def math_lerp_for_owned(+arithmetic: M.Contraction, +start: F32, end: F32, amount: F32) -> F32:
  M.Math.lerp_for(arithmetic, start, end, amount)
def math_remap_for_owned(+arithmetic: M.Contraction, value: F32, +input_start: F32, input_end: F32, +output_start: F32, output_end: F32) -> F32:
  M.Math.remap_for(arithmetic, value, input_start, input_end, output_start, output_end)
def math_wrap_for_owned(+arithmetic: M.Contraction, +value: F32, +lower: F32, +upper: F32) -> F32:
  M.Math.wrap_for(arithmetic, value, lower, upper)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for name, args in selected:
        call = FUNCTIONS[name][1].format(', '.join(f'word({word})' for word in args))
        emitter = 'flag' if FUNCTIONS[name][2] == 'b' else 'show'
        body += f'    {emitter}({call})\n'
    return body


def aligned(rows, values):
    return [quiet_nan.canonical(name.removeprefix('fused_'), args, value) for (name, args), value in zip(rows, values)]


def main():
    probe = probekit.Probe('scalars', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'scalars: native produced {len(expected)} rows for {len(rows)} cases')
    if fused_rows.available():
        extra = fused_cases()
        fused_text = native_fused(probe, extra)
        fused_expected = [json.loads(line) for line in fused_text.splitlines() if line.strip()]
        if len(fused_expected) != len(extra):
            raise ProbeFailure(f'scalars: fused native produced {len(fused_expected)} rows for {len(extra)} cases')
        rows, expected, text = rows + extra, expected + fused_expected, text + fused_text
    else:
        probe.report['fused'] = f'not on {platform.machine()}: no contracted reference'
    if len(rows) > 30000:
        raise ProbeFailure(f'scalars: {len(rows)} cases is more than the probe budget')
    lanes = probe.candidates(render, rows, batch=240)
    expected_n = aligned(rows, expected)
    lanes_n = {lane: aligned(rows, values) for lane, values in lanes.items()}
    fresh = sum(before != after for before, after in zip(expected, expected_n))
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0]} {tuple(hex(word) for word in rows[i][1])}')
    probe.finish(cases=len(rows), fresh_nan_rows=fresh,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
