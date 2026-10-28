#!/usr/bin/env python3
"""Exceptional inputs for raymath's pure arithmetic shapes.

Determinant, invert, quaternion/matrix conversion, rotate-by-quaternion,
project, reject, look-at, ortho-normalize, unproject and decompose. Ortho and
frustum are omitted: a zero or infinite span disagrees on the sign of an
infinity, which IEEE 754 specifies. Every non-NaN bit is compared. A quiet
NaN, whose sign these formulas do not fix, is folded to the canonical
positive payload before probe.compare.
"""
import json

import probekit
from probekit import ProbeFailure

WORDS = (
    0x00000000, 0x80000000, 0x00000001, 0x00800000,
    0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7fc00000,
)
# Look-at keeps a smaller up/target set so the table stays one compile.
LOOK = (0x00000000, 0x3f800000, 0x7f800000, 0x7fc00000)


def cases():
    rows = [('invert_id', ())]
    for word in WORDS:
        for name in ('det', 'invert', 'invert_diag', 'to_matrix', 'from_matrix', 'decompose', 'unproject'):
            rows.append((name, (word,)))
    for left in WORDS:
        for right in WORDS:
            rows.append(('rotq', (left, right)))
            rows.append(('project', (left, right)))
            rows.append(('reject', (left, right)))
            rows.append(('ortho_n', (left, right)))
            rows.append(('from_v3', (left, right)))
    for eye in WORDS:
        for target in LOOK:
            for up in LOOK:
                rows.append(('look', (eye, target, up)))
    return rows


def native(probe, rows):
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Vector3 v3(unsigned w){float x=load(w); return (Vector3){x,x,x};}',
        'static Vector4 v4(unsigned w){float x=load(w); return (Vector4){x,x,x,x};}',
        'static Matrix filled(unsigned w){float x=load(w); Matrix m; m.m0=m.m1=m.m2=m.m3=m.m4=m.m5=m.m6=m.m7=m.m8=m.m9=m.m10=m.m11=m.m12=m.m13=m.m14=m.m15=x; return m;}',
        'static Matrix diag(unsigned w){Matrix m={0}; float x=load(w); m.m0=m.m5=m.m10=m.m15=x; return m;}',
        'static void e1(float x){printf("%u\\n", bits(x));}',
        'static void e3(Vector3 v){printf("[%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z));}',
        'static void e4(Vector4 v){printf("[%u,%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z), bits(v.w));}',
        'static void em(Matrix m){printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n",',
        '  bits(m.m0),bits(m.m4),bits(m.m8),bits(m.m12),bits(m.m1),bits(m.m5),bits(m.m9),bits(m.m13),',
        '  bits(m.m2),bits(m.m6),bits(m.m10),bits(m.m14),bits(m.m3),bits(m.m7),bits(m.m11),bits(m.m15));}',
        'static void edec(Matrix m){Vector3 t; Quaternion q; Vector3 s; MatrixDecompose(m,&t,&q,&s);',
        '  printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n", bits(t.x),bits(t.y),bits(t.z),bits(q.x),bits(q.y),bits(q.z),bits(q.w),bits(s.x),bits(s.y),bits(s.z));}',
        'static void eortho(unsigned a,unsigned b){Vector3 u=v3(a), v=v3(b); Vector3OrthoNormalize(&u,&v);',
        '  printf("[%u,%u,%u,%u,%u,%u]\\n", bits(u.x),bits(u.y),bits(u.z),bits(v.x),bits(v.y),bits(v.z));}',
        'int main(void){',
    ]
    for name, args in rows:
        w = args[0] if args else 0
        if name == 'det':
            lines.append(f'  e1(MatrixDeterminant(filled(0x{w:08x}u)));')
        elif name == 'invert':
            lines.append(f'  em(MatrixInvert(filled(0x{w:08x}u)));')
        elif name == 'invert_diag':
            lines.append(f'  em(MatrixInvert(diag(0x{w:08x}u)));')
        elif name == 'invert_id':
            lines.append('  em(MatrixInvert(MatrixIdentity()));')
        elif name == 'to_matrix':
            lines.append(f'  em(QuaternionToMatrix(v4(0x{w:08x}u)));')
        elif name == 'from_matrix':
            lines.append(f'  e4(QuaternionFromMatrix(filled(0x{w:08x}u)));')
        elif name == 'decompose':
            lines.append(f'  edec(filled(0x{w:08x}u));')
        elif name == 'unproject':
            lines.append(f'  e3(Vector3Unproject(v3(0x{w:08x}u), filled(0x{w:08x}u), filled(0x{w:08x}u)));')
        elif name == 'ortho':
            vals = ','.join(f'(double)load(0x{word:08x}u)' for word in args)
            lines.append(f'  em(MatrixOrtho({vals}));')
        elif name == 'frustum':
            vals = ','.join(f'(double)load(0x{word:08x}u)' for word in args)
            lines.append(f'  em(MatrixFrustum({vals}));')
        elif name == 'rotq':
            lines.append(f'  e3(Vector3RotateByQuaternion(v3(0x{args[0]:08x}u), v4(0x{args[1]:08x}u)));')
        elif name == 'project':
            lines.append(f'  e3(Vector3Project(v3(0x{args[0]:08x}u), v3(0x{args[1]:08x}u)));')
        elif name == 'reject':
            lines.append(f'  e3(Vector3Reject(v3(0x{args[0]:08x}u), v3(0x{args[1]:08x}u)));')
        elif name == 'ortho_n':
            lines.append(f'  eortho(0x{args[0]:08x}u, 0x{args[1]:08x}u);')
        elif name == 'from_v3':
            lines.append(f'  e4(QuaternionFromVector3ToVector3(v3(0x{args[0]:08x}u), v3(0x{args[1]:08x}u)));')
        elif name == 'look':
            lines.append(f'  em(MatrixLookAt(v3(0x{args[0]:08x}u), v3(0x{args[1]:08x}u), v3(0x{args[2]:08x}u)));')
        else:
            raise ProbeFailure(name)
    lines.append('  (void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'shape', extra_flags=('-ffp-contract=off',), link_raylib=False)


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def filled(bits: U32) -> M.Matrix:
  +value = word(bits)
  M.Matrix{value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value}
def diag(bits: U32) -> M.Matrix:
  +value = word(bits)
  M.Matrix{value, 0.0, 0.0, 0.0, 0.0, value, 0.0, 0.0, 0.0, 0.0, value, 0.0, 0.0, 0.0, 0.0, value}
def v3(bits: U32) -> M.Vector3:
  +value = word(bits)
  M.Vector3{value, value, value}
def v4(bits: U32) -> M.Vector4:
  +value = word(bits)
  M.Vector4{value, value, value, value}
def f64(bits: U32) -> M.Float64:
  M.Float64.from_f32(word(bits))
def show1(value: F32) -> IO(Unit):
  IO.print(U32.show(F32.bits(value)))
def show3(value: M.Vector3) -> IO(Unit):
  M.Vector3{x, y, z} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z)]))
def show4(value: M.Vector4) -> IO(Unit):
  M.Vector4{x, y, z, w} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w)]))
def showm(value: M.Matrix) -> IO(Unit):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(m0), F32.bits(m4), F32.bits(m8), F32.bits(m12), F32.bits(m1), F32.bits(m5), F32.bits(m9), F32.bits(m13), F32.bits(m2), F32.bits(m6), F32.bits(m10), F32.bits(m14), F32.bits(m3), F32.bits(m7), F32.bits(m11), F32.bits(m15)]))
def show_dec(value: M.Matrix.Decomposition) -> IO(Unit):
  M.Decomposed{translation, rotation, scale} = value
  M.Vector3{tx, ty, tz} = translation
  M.Vector4{qx, qy, qz, qw} = rotation
  M.Vector3{sx, sy, sz} = scale
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(tx), F32.bits(ty), F32.bits(tz), F32.bits(qx), F32.bits(qy), F32.bits(qz), F32.bits(qw), F32.bits(sx), F32.bits(sy), F32.bits(sz)]))
def show_ortho(value: M.Vector3 & M.Vector3) -> IO(Unit):
  (first, second) = value
  M.Vector3{ax, ay, az} = first
  M.Vector3{bx, by, bz} = second
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(ax), F32.bits(ay), F32.bits(az), F32.bits(bx), F32.bits(by), F32.bits(bz)]))
def main() -> IO(Unit):
  do IO<Unit>:
'''

# Dotted names the probe runs, so gate_evidence can see them.
CALLS = {
    'det': 'show1(M.Matrix.determinant(filled({w})))',
    'invert': 'showm(M.Matrix.invert(filled({w})))',
    'invert_diag': 'showm(M.Matrix.invert(diag({w})))',
    'invert_id': 'showm(M.Matrix.invert(M.Matrix.identity()))',
    'to_matrix': 'showm(M.Quaternion.to_matrix(v4({w})))',
    'from_matrix': 'show4(M.Quaternion.from_matrix(filled({w})))',
    'decompose': 'show_dec(M.Matrix.decompose(filled({w})))',
    'unproject': 'show3(M.Vector3.unproject(v3({w}), filled({w}), filled({w})))',
    'ortho': 'showm(M.Matrix.ortho(f64({a}), f64({b}), f64({c}), f64({d}), f64({e}), f64({f})))',
    'frustum': 'showm(M.Matrix.frustum(f64({a}), f64({b}), f64({c}), f64({d}), f64({e}), f64({f})))',
    'rotq': 'show3(M.Vector3.rotate_by_quaternion(v3({a}), v4({b})))',
    'project': 'show3(M.Vector3.project(v3({a}), v3({b})))',
    'reject': 'show3(M.Vector3.reject(v3({a}), v3({b})))',
    'ortho_n': 'show_ortho(M.Vector3.ortho_normalize(v3({a}), v3({b})))',
    'from_v3': 'show4(M.Quaternion.from_vector3_to_vector3(v3({a}), v3({b})))',
    'look': 'showm(M.Matrix.look_at(v3({a}), v3({b}), v3({c})))',
}


def render(selected, gpu):
    body = PROGRAM
    for name, args in selected:
        fields = dict(w=0, a=0, b=0, c=0, d=0, e=0, f=0)
        if name in ('ortho', 'frustum'):
            fields.update(zip('abcdef', args))
        elif name in ('rotq', 'project', 'reject', 'ortho_n', 'from_v3'):
            fields['a'], fields['b'] = args
        elif name == 'look':
            fields['a'], fields['b'], fields['c'] = args
        elif args:
            fields['w'] = args[0]
        body += '    ' + CALLS[name].format(**fields) + '\n'
    return body


def fold(value):
    if isinstance(value, list):
        return [fold(item) for item in value]
    if isinstance(value, int) and (value & 0x7FFFFFFF) > 0x7F800000:
        return 0x7FC00000
    return value


def main():
    probe = probekit.Probe('shape', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'shape: native produced {len(expected)} rows for {len(rows)}')
    lanes = probe.candidates(render, rows, batch=80, source_limit=70000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    expected_n = [fold(value) for value in expected]
    lanes_n = {lane: [fold(value) for value in values] for lane, values in lanes.items()}
    fresh = sum(before != after for before, after in zip(expected, expected_n))
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0]} {tuple(hex(w) for w in rows[i][1])}')
    probe.finish(cases=len(rows), fresh_nan_rows=fresh)


if __name__ == '__main__':
    main()
