#!/usr/bin/env python3
"""Compare raymath value constructors and exact field permutations.

Vector2/3/4 Zero and One, MatrixIdentity, QuaternionIdentity, MatrixTranspose,
Vector3ToFloatV and MatrixToFloatV run with contraction off. Transpose and the
float exports see signed zero, a subnormal, both infinities and the canonical
quiet NaN. Every result bit is compared on CPU-1, CPU-2 and JavaScript.
"""
import json

import probekit
from probekit import ProbeFailure

WORDS = (
    0x00000000, 0x80000000, 0x00000001, 0x00800000,
    0x3f800000, 0xbf800000, 0x7f800000, 0xff800000,
    0x7fc00000,
)


def cases():
    rows = [('zero2', ()), ('one2', ()), ('zero3', ()), ('one3', ()), ('zero4', ()), ('one4', ()),
            ('identity', ()), ('qidentity', ())]
    for word in WORDS:
        rows.append(('transpose', (word,)))
        rows.append(('v3float', (word,)))
        rows.append(('mfloat', (word,)))
    return rows


def native(probe, rows):
    cells = ','.join(f'bits(v.v[{index}])' for index in range(16))
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static void emit2(Vector2 v){printf("[%u,%u]\\n", bits(v.x), bits(v.y));}',
        'static void emit3(Vector3 v){printf("[%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z));}',
        'static void emit4(Vector4 v){printf("[%u,%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z), bits(v.w));}',
        'static void emitm(Matrix m){printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n",',
        '  bits(m.m0),bits(m.m4),bits(m.m8),bits(m.m12),bits(m.m1),bits(m.m5),bits(m.m9),bits(m.m13),',
        '  bits(m.m2),bits(m.m6),bits(m.m10),bits(m.m14),bits(m.m3),bits(m.m7),bits(m.m11),bits(m.m15));}',
        'static void emitf3(float3 v){printf("[%u,%u,%u]\\n", bits(v.v[0]), bits(v.v[1]), bits(v.v[2]));}',
        'static void emitf16(float16 v){printf("[' + '%u,' * 15 + '%u]\\n", ' + cells + ');}',
        'static Matrix sample(unsigned w){Matrix m={0}; m.m0=load(w); m.m4=load(0x80000000u); m.m1=load(0x3f800000u); return m;}',
        'int main(void){',
    ]
    calls = {
        'zero2': 'emit2(Vector2Zero());',
        'one2': 'emit2(Vector2One());',
        'zero3': 'emit3(Vector3Zero());',
        'one3': 'emit3(Vector3One());',
        'zero4': 'emit4(Vector4Zero());',
        'one4': 'emit4(Vector4One());',
        'identity': 'emitm(MatrixIdentity());',
        'qidentity': 'emit4(QuaternionIdentity());',
        'transpose': 'emitm(MatrixTranspose(sample(0x{word:08x}u)));',
        'v3float': 'emitf3(Vector3ToFloatV((Vector3){{load(0x{word:08x}u), load(0x80000000u), load(0x3f800000u)}}));',
        'mfloat': 'emitf16(MatrixToFloatV(sample(0x{word:08x}u)));',
    }
    for name, args in rows:
        word = args[0] if args else 0
        lines.append('  ' + calls[name].format(word=word))
    lines.append('  (void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'math-values', extra_flags=('-ffp-contract=off',), link_raylib=False)


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
def showm(value: M.Matrix) -> IO(Unit):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(m0), F32.bits(m4), F32.bits(m8), F32.bits(m12), F32.bits(m1), F32.bits(m5), F32.bits(m9), F32.bits(m13), F32.bits(m2), F32.bits(m6), F32.bits(m10), F32.bits(m14), F32.bits(m3), F32.bits(m7), F32.bits(m11), F32.bits(m15)]))
def pack(values: List<&2, F32>) -> List<U32>:
  match values:
    case []: []
    case head <> tail: F32.bits(head) <> pack(tail)
def show_list(values: List<&2, F32>) -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, pack(values)))
def main() -> IO(Unit):
  do IO<Unit>:
'''

# Constructor order is m0, m4, m8, m12, m1, ... The sample stores the word in
# m0, signed zero in m4 and 1 in m1.
SAMPLE = 'M.Matrix{{word({word}), word(2147483648), word(0), word(0), word(1065353216), word(0), word(0), word(0), word(0), word(0), word(0), word(0), word(0), word(0), word(0), word(0)}}'

# Dotted Bend symbols this probe runs.
CALLS = {
    'zero2': 'show2(M.Vector2.zero())',
    'one2': 'show2(M.Vector2.one())',
    'zero3': 'show3(M.Vector3.zero())',
    'one3': 'show3(M.Vector3.one())',
    'zero4': 'show4(M.Vector4.zero())',
    'one4': 'show4(M.Vector4.one())',
    'identity': 'showm(M.Matrix.identity())',
    'qidentity': 'show4(M.Quaternion.identity())',
    'transpose': 'showm(M.Matrix.transpose(' + SAMPLE + '))',
    'v3float': 'show_list(M.Vector3.to_float_v(M.Vector3{{word({word}), word(2147483648), word(1065353216)}}))',
    'mfloat': 'show_list(M.Matrix.to_float_v(' + SAMPLE + '))',
}


def render(selected, gpu):
    body = PROGRAM
    for name, args in selected:
        word = args[0] if args else 0
        body += f'    {CALLS[name].format(word=word)}\n'
    return body


def main():
    probe = probekit.Probe('math-values', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'math-values: native produced {len(expected)} rows for {len(rows)}')
    lanes = probe.candidates(render, rows, batch=len(rows))
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: rows[i][0])
    probe.finish(cases=len(rows))


if __name__ == '__main__':
    main()
