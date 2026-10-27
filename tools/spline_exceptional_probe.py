#!/usr/bin/env python3
"""Compare spline points on exceptional, subnormal and extrapolated inputs.

Linear, B-spline, Catmull-Rom and quadratic Bezier. The uncontracted result
is the pinned rshapes.c functions compiled with FP_CONTRACT OFF (the Linux
linked library is that profile). The fused result is those Bend nestings
with fmaf: finite normals stay on the integer kernel and a non-finite
factor or addend uses the total fma. t is not clamped. A quiet-NaN sign
on linear, basis or quadratic points is not compared: Apple clang's sign
disagrees with both Bend lanes, and Linux clang agrees with JavaScript.
Catmull-Rom matches every bit on every lane. Cubic Bezier is included only
on a Glibc239 host, for t in
{-0, 0, 0.5, 1} (the cubes stay inside the powf profile) with exceptional
control points; its squares stay products and t is not swept.
"""
import hashlib
import json

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

EDGE = (
    0x00000000, 0x80000000,
    0x3f800000, 0xbf800000,
    0x3fc00000, 0x4b800000,
    0x00000001, 0x00800000,
    0x7f7fffff,
    0x7f800000, 0xff800000,
    0x7fc00000,
)
ZERO, ONE = 0x00000000, 0x3f800000
HALF, NEG_ZERO = 0x3f000000, 0x80000000
CUBIC_T = (ZERO, NEG_ZERO, HALF, ONE)


def sweep(kind, anchor, limit=None):
    rows = [anchor]
    last = len(anchor) if limit is None else limit
    for index in range(last):
        for word in EDGE:
            changed = list(anchor)
            changed[index] = word
            rows.append(tuple(changed))
    return [(kind, row) for row in rows]


def cases(include_cubic):
    rows, seen = [], set()
    linear = (ZERO, ZERO, ONE, ZERO, HALF)
    four = (ZERO, ZERO, ONE, ZERO, ONE, ONE, ZERO, ONE, HALF)
    quad = (ZERO, ZERO, HALF, ONE, ONE, ZERO, HALF)
    generated = sweep('linear', linear) + sweep('basis', four) + sweep('catmull', four) + sweep('quad', quad)
    if include_cubic:
        for t in CUBIC_T:
            generated.extend(sweep('cubic', four[:8] + (t,), 8))
    for kind, args in generated:
        key = (kind, args)
        if key not in seen:
            seen.add(key)
            rows.append(key)
    return rows


FUSED = r'''
static unsigned sink;
static float load(unsigned bits){volatile union { unsigned u; float x; } v; v.u=bits; sink+=v.u; return v.x;}
static unsigned bits(float x){union { float x; unsigned u; } v; v.x=x; return v.u;}
static void show(Vector2 p){printf("[%u,%u]", bits(p.x), bits(p.y));}
static Vector2 linear_fused(Vector2 a, Vector2 b, float t){
  return (Vector2){fmaf(a.x, 1.0f-t, b.x*t), fmaf(a.y, 1.0f-t, b.y*t)};}
static float basis_axis(float a, float b, float c, float d, float t){
  float q0=(fmaf(-3.0f, c, fmaf(3.0f, b, -a))+d)/6.0f;
  float q1=fmaf(3.0f, c, fmaf(3.0f, a, (-6.0f)*b))/6.0f;
  float q2=fmaf(-3.0f, a, 3.0f*c)/6.0f;
  float q3=(fmaf(4.0f, b, a)+c)/6.0f;
  return fmaf(t, fmaf(t, fmaf(t, q0, q1), q2), q3);}
static Vector2 basis_fused(Vector2 a, Vector2 b, Vector2 c, Vector2 d, float t){
  return (Vector2){basis_axis(a.x,b.x,c.x,d.x,t), basis_axis(a.y,b.y,c.y,d.y,t)};}
static void catmull_weights(float t, float *q0, float *q1, float *q2, float *q3){
  *q0=fmaf((-t)*t, t, (2.0f*t)*t)-t;
  *q1=fmaf((3.0f*t)*t, t, ((-5.0f)*t)*t)+2.0f;
  *q2=fmaf(((-3.0f)*t)*t, t, (4.0f*t)*t)+t;
  *q3=fmaf(t*t, t, -(t*t));}
static float catmull_axis(float q0, float q1, float q2, float q3, float a, float b, float c, float d){
  return 0.5f*fmaf(d, q3, fmaf(c, q2, fmaf(a, q0, b*q1)));}
static Vector2 catmull_fused(Vector2 a, Vector2 b, Vector2 c, Vector2 d, float t){
  float q0,q1,q2,q3; catmull_weights(t,&q0,&q1,&q2,&q3);
  return (Vector2){catmull_axis(q0,q1,q2,q3,a.x,b.x,c.x,d.x), catmull_axis(q0,q1,q2,q3,a.y,b.y,c.y,d.y)};}
static Vector2 quad_fused(Vector2 a, Vector2 b, Vector2 c, float t){
  float one=1.0f-t, qa=one*one, qb=(2.0f*one)*t, qc=t*t;
  return (Vector2){fmaf(qc, c.x, fmaf(qa, a.x, qb*b.x)), fmaf(qc, c.y, fmaf(qa, a.y, qb*b.y))};}
static Vector2 cubic_fused(Vector2 a, Vector2 b, Vector2 c, Vector2 d, float t){
  float one=1.0f-t, wa=powf(one, 3.0f), wb=(3.0f*(one*one))*t, wc=(3.0f*(1.0f-t))*(t*t), wd=powf(t, 3.0f);
  return (Vector2){fmaf(wd, d.x, fmaf(wc, c.x, fmaf(wa, a.x, wb*b.x))),
                   fmaf(wd, d.y, fmaf(wc, c.y, fmaf(wa, a.y, wb*b.y)))};}
'''


def c_vec(words):
    return '(Vector2){' + ','.join(f'load({word})' for word in words) + '}'


def native_case(kind, args):
    a, b = c_vec(args[0:2]), c_vec(args[2:4])
    if kind == 'linear':
        return (f'{{Vector2 a={a}, b={b}; float t=load({args[4]}); '
                'printf("["); show(GetSplinePointLinear(a,b,t)); printf(","); show(linear_fused(a,b,t)); printf("]\\n");}')
    c = c_vec(args[4:6])
    if kind == 'quad':
        return (f'{{Vector2 a={a}, b={b}, c={c}; float t=load({args[6]}); '
                'printf("["); show(GetSplinePointBezierQuadratic(a,b,c,t)); printf(","); '
                'show(quad_fused(a,b,c,t)); printf("]\\n");}')
    d = c_vec(args[6:8])
    t = args[8]
    if kind == 'basis':
        return (f'{{Vector2 a={a}, b={b}, c={c}, d={d}; float t=load({t}); '
                'printf("["); show(GetSplinePointBasis(a,b,c,d,t)); printf(","); '
                'show(basis_fused(a,b,c,d,t)); printf("]\\n");}')
    if kind == 'catmull':
        return (f'{{Vector2 a={a}, b={b}, c={c}, d={d}; float t=load({t}); '
                'printf("["); show(GetSplinePointCatmullRom(a,b,c,d,t)); printf(","); '
                'show(catmull_fused(a,b,c,d,t)); printf("]\\n");}')
    return (f'{{Vector2 a={a}, b={b}, c={c}, d={d}; float t=load({t}); '
            'printf("["); show(GetSplinePointBezierCubic(a,b,c,d,t)); printf(","); '
            'show(cubic_fused(a,b,c,d,t)); printf("]\\n");}')


def native(probe, rows):
    source = (probe.args.raylib_source / 'src/rshapes.c').read_text()
    begin = source.index('Vector2 GetSplinePointLinear(')
    end = source.index('//----------------------------------------------------------------------------------', begin)
    lines = ['#include <math.h>', '#include <stdio.h>',
             'typedef struct Vector2 { float x; float y; } Vector2;',
             '/* Unaltered spline functions from pinned raylib; zlib, LICENSES/raylib.txt. */',
             '#pragma STDC FP_CONTRACT OFF', source[begin:end], FUSED,
             'int main(void){']
    lines.extend(native_case(kind, args) for kind, args in rows)
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', extra_flags=('-ffp-contract=off',), link_raylib=False)


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def pair(point: M.Vector2) -> String:
  M.Vector2{x, y} = point
  "[" ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "]"
def maybe_pair(point: Maybe<M.Vector2>) -> String:
  match point:
    case None{}: "null"
    case Some{value}: pair(value)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def bend_vec(words):
    return 'M.Vector2{' + ', '.join(f'word({word})' for word in words) + '}'


def bend_call(kind, arithmetic, args, libm):
    a, b = bend_vec(args[0:2]), bend_vec(args[2:4])
    if kind == 'linear':
        return f'J.Spline.linear_for({arithmetic}, {a}, {b}, word({args[4]}))'
    c = bend_vec(args[4:6])
    if kind == 'quad':
        return f'J.Spline.bezier_quad_for({arithmetic}, {a}, {b}, {c}, word({args[6]}))'
    d = bend_vec(args[6:8])
    t = f'word({args[8]})'
    if kind == 'basis':
        return f'J.Spline.basis_for({arithmetic}, {a}, {b}, {c}, {d}, {t})'
    if kind == 'catmull':
        return f'J.Spline.catmull_rom_for({arithmetic}, {a}, {b}, {c}, {d}, {t})'
    return (f'J.Spline.bezier_cubic_for({arithmetic}, M.{libm}{{}}, {a}, {b}, {c}, {d}, {t})')


def render(libm):
    def emit(selected, gpu):
        body = PROGRAM
        for kind, args in selected:
            show = 'maybe_pair' if kind == 'cubic' else 'pair'
            left = bend_call(kind, 'M.Uncontracted{}', args, libm)
            right = bend_call(kind, 'M.Fused{}', args, libm)
            body += f'    IO.print("[" ++ {show}({left}) ++ "," ++ {show}({right}) ++ "]")\n'
        return body
    return emit


def point_diff(want, got):
    """ok, sign (quiet-NaN sign only) or value."""
    if want == got:
        return 'ok'
    if not isinstance(want, list) or not isinstance(got, list) or len(want) != 2 or len(got) != 2:
        return 'value'
    sign = False
    for left, right in zip(want, got):
        if left == right:
            continue
        if (left ^ right) == 0x80000000 and (left & 0x7FFFFFFF) > 0x7F800000 and (right & 0x7FFFFFFF) > 0x7F800000:
            sign = True
            continue
        return 'value'
    return 'sign' if sign else 'ok'


def quiet_sign_uncompared(kind, slot, lane):
    """Recorded CPU quiet-NaN signs: linear, quadratic, and fused basis.

    JavaScript matches every bit, and an uncontracted basis point does too.
    """
    if lane == 'javascript':
        return False
    if kind in ('linear', 'quad'):
        return True
    return kind == 'basis' and slot == 'fused'


def main():
    probe = probekit.Probe('spline-exceptional', probekit.arguments(__doc__))
    libm = gradient_reference()
    rows = cases(libm == 'Glibc239Libm')
    if not rows or len(rows) > 4000:
        raise ProbeFailure(f'spline-exceptional: {len(rows)} cases is outside the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'spline-exceptional: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render(libm), rows, batch=160, timeout=900)
    sign_rows = {}
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'spline-exceptional: {lane} produced {len(actual)} rows, expected {len(expected)}')
        allowed, problems = [], []
        for index, (want, got) in enumerate(zip(expected, actual)):
            kind, _args = rows[index]
            for side, slot in ((0, 'uncontracted'), (1, 'fused')):
                diff = point_diff(want[side], got[side])
                if diff == 'ok':
                    continue
                # CPU lanes disagree with clang on the recorded quiet-NaN signs.
                # JavaScript matches every bit, and an uncontracted basis point does too.
                if diff == 'sign' and quiet_sign_uncompared(kind, slot, lane):
                    allowed.append((kind, slot, index))
                    continue
                problems.append((kind, slot, diff, index))
        sign_rows[lane] = len(allowed)
        probe.report.setdefault('lanes', {})[lane] = dict(passed=not problems, rows=len(actual), sign_rows=len(allowed))
        probe.save()
        if problems:
            kind, slot, diff, index = problems[0]
            side = 0 if slot == 'uncontracted' else 1
            raise ProbeFailure(
                f'spline-exceptional: {lane} has {len(problems)} {diff} mismatches; first {slot} {kind} '
                f'{tuple(hex(word) for word in rows[index][1])}: reference={json.dumps(expected[index][side])} '
                f'jonlib={json.dumps(actual[index][side])}')
    counts = {kind: sum(row_kind == kind for row_kind, _ in rows)
              for kind in ('linear', 'basis', 'catmull', 'quad', 'cubic')}
    probe.finish(cases=len(rows), libm=libm, sign_rows=sign_rows, **counts,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
