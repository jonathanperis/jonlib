#!/usr/bin/env python3
"""Compare raymath's scalar functions on exceptional and subnormal inputs.

Clamp, Lerp, Normalize, Remap, Wrap and FloatEquals are compiled from the
pinned raymath.h with contraction off, the same flags as the main corpus
(`clang -O2 -fno-builtin-atan2f`, `FP_CONTRACT OFF`). Each input word is loaded
through a volatile so `floorf`, `fabsf` and `fmaxf` run as they do for a
non-constant call, not as a folded literal. Every result bit (and FloatEquals'
boolean) is compared on CPU-1, CPU-2 and JavaScript. JavaScript does not
reproduce the sign of a quiet NaN an arithmetic formula produces: the sign can
differ from raylib and is not stable across runs. That sign is recorded and is
not a value mismatch. A payload change, a NaN where raylib returned a number,
or any difference on a CPU lane fails the probe.
"""
import hashlib
import json

import probekit
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
    'clamp': ('Clamp', 'M.Math.clamp({})', 'f'),
    'lerp': ('Lerp', 'M.Math.lerp({})', 'f'),
    'normalize': ('Normalize', 'M.Math.normalize({})', 'f'),
    'remap': ('Remap', 'M.Math.remap({})', 'f'),
    'wrap': ('Wrap', 'M.Math.wrap({})', 'f'),
    'float_equals': ('FloatEquals', 'M.Math.float_equals({})', 'b'),
}


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


def quiet_nan_sign(expected, actual):
    """True when two words are NaNs that differ only in the sign bit."""
    if type(expected) is not int or type(actual) is not int:
        return False
    if (expected & 0x7fffffff) <= 0x7f800000 or (actual & 0x7fffffff) <= 0x7f800000:
        return False
    return (expected ^ actual) == 0x80000000


def compare(probe, expected, lanes, rows):
    """Exact bits on every lane. JavaScript may use either sign for a produced NaN."""
    signs = 0
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'scalars: {lane} produced {len(actual)} rows, expected {len(expected)}')
        real, flipped = [], []
        for index, (want, got) in enumerate(zip(expected, actual)):
            if want == got:
                continue
            if lane == 'javascript' and quiet_nan_sign(want, got):
                flipped.append(index)
            else:
                real.append(index)
        probe.report['lanes'][lane] = dict(passed=not real, rows=len(actual), different=real[:20])
        if lane == 'javascript':
            probe.report['lanes'][lane]['nan_sign'] = len(flipped)
            signs = len(flipped)
        probe.save()
        if real:
            first = real[0]
            raise ProbeFailure(f'scalars: {lane} differs at {len(real)} rows; first '
                               f'{rows[first][0]} {tuple(hex(word) for word in rows[first][1])}: '
                               f'raylib={json.dumps(expected[first])} jonlib={json.dumps(actual[first])}')
    return signs


def main():
    probe = probekit.Probe('scalars', probekit.arguments(__doc__))
    rows = cases()
    if len(rows) > 20000:
        raise ProbeFailure(f'scalars: {len(rows)} cases is more than the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'scalars: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=240)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    signs = compare(probe, expected, lanes, rows)
    probe.finish(cases=len(rows), javascript_nan_sign=signs,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
