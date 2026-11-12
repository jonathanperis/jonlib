#!/usr/bin/env python3
"""Exceptional inputs for raymath's pure arithmetic shapes.

Determinant, invert, quaternion/matrix conversion, rotate-by-quaternion,
project, reject, look-at, ortho-normalize, unproject and decompose. Ortho and
frustum are omitted: a zero or infinite span disagrees on the sign of an
infinity, which IEEE 754 specifies. Every non-NaN bit is compared. A quiet
NaN, whose sign these formulas do not fix, is folded to the canonical
positive payload before probe.compare.

On arm64 every one of these but ortho and frustum is also compared under
M.Fused{} against the same raymath compiled with clang's default
`-ffp-contract=on` (tools/fused_rows.py), on the exceptional fills and on
seeded finite matrices and vectors with distinct components. QuaternionFrom-
Matrix contracts nothing, so its plain Jonmath form is compared there.
"""
import json
import random

import fused_rows
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


# Fused rows: (C call over a/b/c, Bend call over a/b/c, operand kinds, result emitter)
FUSED = {
    'det': ('e1(MatrixDeterminant({a}))', 'show1(matrix_determinant_for_owned(M.Fused{{}}, {a}))', 'M', '1'),
    'invert': ('em(MatrixInvert({a}))', 'showm(matrix_invert_for_owned(M.Fused{{}}, {a}))', 'M', 'm'),
    'to_matrix': ('em(QuaternionToMatrix({a}))', 'showm(quaternion_to_matrix_for_owned(M.Fused{{}}, {a}))', '4', 'm'),
    'from_matrix': ('e4(QuaternionFromMatrix({a}))', 'show4(quaternion_from_matrix_owned({a}))', 'M', '4'),
    'decompose': ('edec({a})', 'show_dec(matrix_decompose_for_owned(M.Fused{{}}, {a}))', 'M', 'd'),
    'unproject': ('e3(Vector3Unproject({a}, {b}, {c}))', 'show3(vector3_unproject_for_owned(M.Fused{{}}, {a}, {b}, {c}))', '3MM', '3'),
    'rotq': ('e3(Vector3RotateByQuaternion({a}, {b}))', 'show3(vector3_rotate_by_quaternion_for_owned(M.Fused{{}}, {a}, {b}))', '34', '3'),
    'project': ('e3(Vector3Project({a}, {b}))', 'show3(vector3_project_for_owned(M.Fused{{}}, {a}, {b}))', '33', '3'),
    'reject': ('e3(Vector3Reject({a}, {b}))', 'show3(vector3_reject_for_owned(M.Fused{{}}, {a}, {b}))', '33', '3'),
    'ortho_n': ('eortho2({a}, {b})', 'show_ortho(vector3_ortho_normalize_for_owned(M.Fused{{}}, {a}, {b}))', '33', 'o'),
    'from_v3': ('e4(QuaternionFromVector3ToVector3({a}, {b}))', 'show4(quaternion_from_vector3_to_vector3_for_owned(M.Fused{{}}, {a}, {b}))', '33', '4'),
    'look': ('em(MatrixLookAt({a}, {b}, {c}))', 'showm(matrix_look_at_for_owned(M.Fused{{}}, {a}, {b}, {c}))', '333', 'm'),
}
WIDTH = {'M': 16, '3': 3, '4': 4}


def fused_cases():
    """Each exceptional row with its fill spread over every component, then seeded finite rows."""
    rows = []
    for name, args in cases():
        if name not in FUSED:
            continue
        kinds = FUSED[name][2]
        words = args if len(args) == len(kinds) else (args[0],) * len(kinds)
        rows.append(('fused_' + name, tuple(w for kind, word in zip(kinds, words) for w in (word,) * WIDTH[kind])))
    rng = random.Random(0xF05EDE)
    for name, (_, _, kinds, _) in FUSED.items():
        for _ in range(120):
            rows.append(('fused_' + name, tuple(fused_rows.finite(rng) for kind in kinds for _ in range(WIDTH[kind]))))
    return rows


def operands(kinds, words, make):
    out, at = [], 0
    for kind in kinds:
        out.append(make(kind, words[at:at + WIDTH[kind]]))
        at += WIDTH[kind]
    return out


def native_fused(probe, rows):
    def make(kind, words):
        values = ','.join(f'load(0x{word:08x}u)' for word in words)
        return {'M': f'(Matrix){{{values}}}', '3': f'(Vector3){{{values}}}', '4': f'(Vector4){{{values}}}'}[kind]
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static void e1(float x){printf("%u\\n", bits(x));}',
        'static void e3(Vector3 v){printf("[%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z));}',
        'static void e4(Vector4 v){printf("[%u,%u,%u,%u]\\n", bits(v.x), bits(v.y), bits(v.z), bits(v.w));}',
        'static void em(Matrix m){printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n",',
        '  bits(m.m0),bits(m.m4),bits(m.m8),bits(m.m12),bits(m.m1),bits(m.m5),bits(m.m9),bits(m.m13),',
        '  bits(m.m2),bits(m.m6),bits(m.m10),bits(m.m14),bits(m.m3),bits(m.m7),bits(m.m11),bits(m.m15));}',
        'static void edec(Matrix m){Vector3 t; Quaternion q; Vector3 s; MatrixDecompose(m,&t,&q,&s);',
        '  printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n", bits(t.x),bits(t.y),bits(t.z),bits(q.x),bits(q.y),bits(q.z),bits(q.w),bits(s.x),bits(s.y),bits(s.z));}',
        'static void eortho2(Vector3 u, Vector3 v){Vector3OrthoNormalize(&u,&v);',
        '  printf("[%u,%u,%u,%u,%u,%u]\\n", bits(u.x),bits(u.y),bits(u.z),bits(v.x),bits(v.y),bits(v.z));}',
        'int main(void){',
    ]
    for name, words in rows:
        c_call, _, kinds, _ = FUSED[name[len('fused_'):]]
        values = operands(kinds, words, make)
        lines.append('  ' + c_call.format(**dict(zip('abc', values))) + ';')
    lines.append('  (void)sink; return 0;}')
    source = probe.work / 'shape-fused.c'
    source.write_text('\n'.join(lines) + '\n')
    return fused_rows.levels(probe, source, fold)


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
def mat(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32) -> M.Matrix:
  M.Matrix{word(a), word(b), word(c), word(d), word(e), word(f), word(g), word(h), word(i), word(j), word(k), word(l), word(m), word(n), word(o), word(p)}
def vec3(a: U32, b: U32, c: U32) -> M.Vector3:
  M.Vector3{word(a), word(b), word(c)}
def vec4(a: U32, b: U32, c: U32, d: U32) -> M.Vector4:
  M.Vector4{word(a), word(b), word(c), word(d)}
def show_ortho(value: M.Vector3 & M.Vector3) -> IO(Unit):
  (first, second) = value
  M.Vector3{ax, ay, az} = first
  M.Vector3{bx, by, bz} = second
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(ax), F32.bits(ay), F32.bits(az), F32.bits(bx), F32.bits(by), F32.bits(bz)]))
# Ownership: these defs copy the library signatures (+ borrows, the rest
# consumed) and return values the caller owns; the affine checker
# enforces them on every compared call.
def quaternion_from_matrix_owned(matrix: M.Matrix) -> M.Vector4:
  M.Quaternion.from_matrix(matrix)
def matrix_determinant_for_owned(+arithmetic: M.Contraction, matrix: M.Matrix) -> F32:
  M.Matrix.determinant_for(arithmetic, matrix)
def matrix_invert_for_owned(+arithmetic: M.Contraction, matrix: M.Matrix) -> M.Matrix:
  M.Matrix.invert_for(arithmetic, matrix)
def quaternion_to_matrix_for_owned(+arithmetic: M.Contraction, quaternion: M.Vector4) -> M.Matrix:
  M.Quaternion.to_matrix_for(arithmetic, quaternion)
def matrix_decompose_for_owned(+arithmetic: M.Contraction, matrix: M.Matrix) -> M.Matrix.Decomposition:
  M.Matrix.decompose_for(arithmetic, matrix)
def vector3_unproject_for_owned(+arithmetic: M.Contraction, source: M.Vector3, projection: M.Matrix, view: M.Matrix) -> M.Vector3:
  M.Vector3.unproject_for(arithmetic, source, projection, view)
def vector3_rotate_by_quaternion_for_owned(+arithmetic: M.Contraction, vector: M.Vector3, quaternion: M.Vector4) -> M.Vector3:
  M.Vector3.rotate_by_quaternion_for(arithmetic, vector, quaternion)
def vector3_project_for_owned(+arithmetic: M.Contraction, vector: M.Vector3, +onto: M.Vector3) -> M.Vector3:
  M.Vector3.project_for(arithmetic, vector, onto)
def vector3_reject_for_owned(+arithmetic: M.Contraction, +vector: M.Vector3, onto: M.Vector3) -> M.Vector3:
  M.Vector3.reject_for(arithmetic, vector, onto)
def vector3_ortho_normalize_for_owned(+arithmetic: M.Contraction, first: M.Vector3, second: M.Vector3) -> M.Vector3 & M.Vector3:
  M.Vector3.ortho_normalize_for(arithmetic, first, second)
def quaternion_from_vector3_to_vector3_for_owned(+arithmetic: M.Contraction, +first: M.Vector3, +second: M.Vector3) -> M.Vector4:
  M.Quaternion.from_vector3_to_vector3_for(arithmetic, first, second)
def matrix_look_at_for_owned(+arithmetic: M.Contraction, +eye: M.Vector3, target: M.Vector3, up: M.Vector3) -> M.Matrix:
  M.Matrix.look_at_for(arithmetic, eye, target, up)
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
        if name.startswith('fused_'):
            _, bend, kinds, _ = FUSED[name[len('fused_'):]]
            values = operands(kinds, args, lambda kind, words: {'M': 'mat', '3': 'vec3', '4': 'vec4'}[kind] + '(' + ', '.join(map(str, words)) + ')')
            body += '    ' + bend.format(**dict(zip('abc', values))) + '\n'
            continue
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
    if fused_rows.available():
        extra = fused_cases()
        fused_text = native_fused(probe, extra)
        fused_expected = [json.loads(line) for line in fused_text.splitlines() if line.strip()]
        if len(fused_expected) != len(extra):
            raise ProbeFailure(f'shape: fused native produced {len(fused_expected)} rows for {len(extra)}')
        rows, expected = rows + extra, expected + fused_expected
    else:
        probe.report['fused'] = 'no contracted reference on this host'
    lanes = probe.candidates(render, rows, batch=80, source_limit=70000)
    expected_n = [fold(value) for value in expected]
    lanes_n = {lane: [fold(value) for value in values] for lane, values in lanes.items()}
    fresh = sum(before != after for before, after in zip(expected, expected_n))
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0]} {tuple(hex(w) for w in rows[i][1])}')
    probe.finish(cases=len(rows), fresh_nan_rows=fresh)


if __name__ == '__main__':
    main()
