#!/usr/bin/env python3
"""Compare MatrixTranslate and MatrixScale on exceptional components.

Both functions store the three arguments and constant 0/1 fields; they do no
arithmetic, so there is no contraction and no produced NaN. The probe loads
each component through a volatile and compares all sixteen fields as bits,
including signed zero, subnormals, infinities and NaN payloads of both signs.
CPU lanes must match every bit. JavaScript stores every NaN as the canonical
positive quiet NaN (0x7fc00000); any other difference fails.
"""
import json

import probekit
from probekit import ProbeFailure

# Words that define the corners, then payloads swept into one component.
CORE = (
    0x00000000, 0x80000000,
    0x00000001, 0x7f800000,
    0x7fc00000, 0xffc00000,
)
EDGE = (
    0x3f800000, 0xbf800000, 0x40000000, 0x40400000,
    0x007fffff, 0x00800000,
    0x7f7fffff, 0xff7fffff,
    0xff800000,
    0x7f800001, 0xff800001,
    0x7fffffff, 0xffffffff,
)
ANCHORS = (
    (0x3f800000, 0x40000000, 0x40400000),
    (0x80000000, 0x7f800000, 0xffc00000),
)
OPS = (
    ('translate', 'MatrixTranslate(x, y, z)', 'M.Matrix.translate(word({x}), word({y}), word({z}))'),
    ('scale', 'MatrixScale(x, y, z)', 'M.Matrix.scale(word({x}), word({y}), word({z}))'),
)


def triples():
    rows = [(x, y, z) for x in CORE for y in CORE for z in CORE]
    seen = set(rows)
    for anchor in ANCHORS:
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
    return [(name, args) for args in triples() for name, _, _ in OPS]


def native(probe, rows):
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static void emit(Matrix m){printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n",',
        '  bits(m.m0),bits(m.m4),bits(m.m8),bits(m.m12),bits(m.m1),bits(m.m5),bits(m.m9),bits(m.m13),',
        '  bits(m.m2),bits(m.m6),bits(m.m10),bits(m.m14),bits(m.m3),bits(m.m7),bits(m.m11),bits(m.m15));}',
        'static const unsigned triples[][3] = {',
    ]
    lines.extend('  {' + ','.join(f'0x{word:08x}u' for word in args) + '},' for args in rows)
    lines.append('};')
    lines.append('int main(void){')
    lines.append('  for (unsigned i = 0; i < sizeof triples / sizeof triples[0]; i++) {')
    lines.append('    float x = load(triples[i][0]), y = load(triples[i][1]), z = load(triples[i][2]);')
    for _, expr, _ in OPS:
        lines.append(f'    emit({expr});')
    lines.append('  }')
    lines.append('  (void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'matrix-place', extra_flags=('-ffp-contract=off',), link_raylib=False)


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def show(value: M.Matrix) -> IO(Unit):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(m0), F32.bits(m4), F32.bits(m8), F32.bits(m12), F32.bits(m1), F32.bits(m5), F32.bits(m9), F32.bits(m13), F32.bits(m2), F32.bits(m6), F32.bits(m10), F32.bits(m14), F32.bits(m3), F32.bits(m7), F32.bits(m11), F32.bits(m15)]))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    bend = {name: expr for name, _, expr in OPS}
    body = PROGRAM
    for name, (x, y, z) in selected:
        body += f'    show({bend[name].format(x=x, y=y, z=z)})\n'
    return body


def canonical_nan(expected, actual):
    """True when every changed field is a NaN stored as the canonical positive quiet NaN."""
    if type(expected) is not list or type(actual) is not list or len(expected) != len(actual):
        return False
    changed = False
    for left, right in zip(expected, actual):
        if left == right:
            continue
        if (left & 0x7fffffff) <= 0x7f800000 or right != 0x7fc00000:
            return False
        changed = True
    return changed


def compare(probe, expected, lanes, rows):
    canonical = 0
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'matrix-place: {lane} produced {len(actual)} rows, expected {len(expected)}')
        real = []
        signs = 0
        for index, (want, got) in enumerate(zip(expected, actual)):
            if want == got:
                continue
            if lane == 'javascript' and canonical_nan(want, got):
                signs += 1
            else:
                real.append(index)
        probe.report['lanes'][lane] = dict(passed=not real, rows=len(actual), different=real[:20], canonical_nan=signs)
        probe.save()
        canonical += signs
        if real:
            first = real[0]
            raise ProbeFailure(f'matrix-place: {lane} differs at {len(real)} rows; first '
                               f'{rows[first][0]} {tuple(hex(word) for word in rows[first][1])}: '
                               f'raylib={json.dumps(expected[first])} jonlib={json.dumps(actual[first])}')
    return canonical


def main():
    probe = probekit.Probe('matrix-place', probekit.arguments(__doc__))
    found = triples()
    rows = cases()
    text = native(probe, found)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'matrix-place: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=80)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    canonical = compare(probe, expected, lanes, rows)
    probe.finish(cases=len(rows), triples=len(found), javascript_canonical_nan=canonical)


if __name__ == '__main__':
    main()
