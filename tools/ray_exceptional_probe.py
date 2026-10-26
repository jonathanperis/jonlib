#!/usr/bin/env python3
"""Compare ray queries on exceptional and subnormal inputs.

Sphere, triangle, quad and box. The uncontracted result is the pinned
rmodels.c ray functions compiled with contraction off, in their own
translation unit. The linked library is not that result: Apple clang fuses
it. The fused result uses the Apple-clang
shapes: dot products are
fma(z, w, fma(x, u, y*v)), cross-product terms fma(a, b, -(c*d)), the
sphere discriminant fma(r, r, -fma(dist, dist, -(v*v))) and the box
center fma(0.5, max-min, min). position + direction*t is not fused.
Box rows whose slab distance is NaN, or whose pre-cast normal is outside
the C int range, are None. Every other hit flag and field bit is compared on CPU-1, CPU-2 and
JavaScript. An uncontracted sphere normal or quad hit point may differ
by a quiet-NaN sign on the CPU lanes; the fused profile matches those
bits, and JavaScript matches every bit.
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
ZERO, ONE, NEG = 0x00000000, 0x3f800000, 0xbf800000
QUARTER, NEG5 = 0x3e800000, 0xc0a00000


def anchors():
    sphere_out = (ZERO, ZERO, NEG5, ZERO, ZERO, ONE, ZERO, ZERO, ZERO, ONE)
    sphere_in = (ZERO, ZERO, ZERO, ZERO, ZERO, ONE, ZERO, ZERO, ZERO, ONE)
    triangle = (QUARTER, QUARTER, NEG, ZERO, ZERO, ONE, ZERO, ZERO, ZERO, ONE, ZERO, ZERO, ZERO, ONE, ZERO)
    quad = (ZERO, ZERO, NEG, ZERO, ZERO, ONE,
            NEG, NEG, ZERO, ONE, NEG, ZERO, ONE, ONE, ZERO, NEG, ONE, ZERO)
    box_out = (ZERO, ZERO, NEG5, ZERO, ZERO, ONE, NEG, NEG, NEG, ONE, ONE, ONE)
    box_in = (ZERO, ZERO, ZERO, ZERO, ZERO, ONE, NEG, NEG, NEG, ONE, ONE, ONE)
    return (('sphere', sphere_out), ('sphere', sphere_in), ('triangle', triangle),
            ('quad', quad), ('box', box_out), ('box', box_in))


def cases():
    rows, seen = [], set()
    for kind, anchor in anchors():
        candidates = [anchor]
        for index in range(len(anchor)):
            for word in EDGE:
                changed = list(anchor)
                changed[index] = word
                candidates.append(tuple(changed))
        for args in candidates:
            key = (kind, args)
            if key not in seen:
                seen.add(key)
                rows.append(key)
    return rows


ORACLE = r'''
static unsigned sink;
static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}
static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}
static int nan_bits(float t){return (bits(t) & 2147483647u) > 2139095040u;}
static Vector3 sub3(Vector3 a, Vector3 b){return (Vector3){a.x-b.x, a.y-b.y, a.z-b.z};}
static Vector3 add3(Vector3 a, Vector3 b){return (Vector3){a.x+b.x, a.y+b.y, a.z+b.z};}
static Vector3 scale3(Vector3 a, float t){return (Vector3){a.x*t, a.y*t, a.z*t};}
static Vector3 neg3(Vector3 a){return (Vector3){-a.x, -a.y, -a.z};}
static float dot_f(Vector3 a, Vector3 b){return fmaf(a.z, b.z, fmaf(a.x, b.x, a.y*b.y));}
static Vector3 cross_f(Vector3 a, Vector3 b){
  return (Vector3){fmaf(a.y, b.z, -(a.z*b.y)), fmaf(a.z, b.x, -(a.x*b.z)), fmaf(a.x, b.y, -(a.y*b.x))};}
static float length_f(Vector3 v){return sqrtf(dot_f(v, v));}
static Vector3 normalize_f(Vector3 v){
  float length=length_f(v);
  if(length!=0.0f){float inverse=1.0f/length; v.x*=inverse; v.y*=inverse; v.z*=inverse;}
  return v;}
static RayCollision sphere_fused(Ray ray, Vector3 center, float radius){
  RayCollision collision={0};
  Vector3 offset=sub3(center, ray.position);
  float along=dot_f(offset, ray.direction);
  float distance=length_f(offset);
  float d=fmaf(radius, radius, -fmaf(distance, distance, -(along*along)));
  if(d>=0.0f){
    int inside=distance<radius;
    float hit_distance=inside? along+sqrtf(d) : along-sqrtf(d);
    if(hit_distance>=0.0f){
      Vector3 point=add3(ray.position, scale3(ray.direction, hit_distance));
      Vector3 normal=normalize_f(sub3(point, center));
      if(inside) normal=neg3(normal);
      collision.hit=true; collision.distance=hit_distance; collision.point=point; collision.normal=normal;
    }
  }
  return collision;}
static RayCollision triangle_fused(Ray ray, Vector3 p1, Vector3 p2, Vector3 p3){
  RayCollision collision={0};
  Vector3 edge1=sub3(p2, p1), edge2=sub3(p3, p1), p=cross_f(ray.direction, edge2);
  float det=dot_f(edge1, p);
  if((det>-0.000001f)&&(det<0.000001f)) return collision;
  float inverse=1.0f/det;
  Vector3 offset=sub3(ray.position, p1);
  float u=dot_f(offset, p)*inverse;
  if((u<0.0f)||(u>1.0f)) return collision;
  Vector3 q=cross_f(offset, edge1);
  float v=dot_f(ray.direction, q)*inverse;
  if((v<0.0f)||((u+v)>1.0f)) return collision;
  float t=dot_f(edge2, q)*inverse;
  if(!(t>0.000001f)) return collision;
  collision.hit=true; collision.distance=t;
  collision.normal=normalize_f(cross_f(edge1, edge2));
  collision.point=add3(ray.position, scale3(ray.direction, t));
  return collision;}
static RayCollision quad_fused(Ray ray, Vector3 p1, Vector3 p2, Vector3 p3, Vector3 p4){
  RayCollision collision=triangle_fused(ray, p1, p2, p4);
  if(!collision.hit) collision=triangle_fused(ray, p2, p3, p4);
  return collision;}
static int inside_box(Vector3 p, Vector3 lo, Vector3 hi){
  return (p.x>lo.x)&&(p.x<hi.x)&&(p.y>lo.y)&&(p.y<hi.y)&&(p.z>lo.z)&&(p.z<hi.z);}
static int refused(int fused, Ray ray, Vector3 lo, Vector3 hi){
  Vector3 dir=ray.direction;
  if(inside_box(ray.position, lo, hi)) dir=neg3(dir);
  float invx=1.0f/dir.x, invy=1.0f/dir.y, invz=1.0f/dir.z;
  float t0=(lo.x-ray.position.x)*invx, t1=(hi.x-ray.position.x)*invx;
  float t2=(lo.y-ray.position.y)*invy, t3=(hi.y-ray.position.y)*invy;
  float t4=(lo.z-ray.position.z)*invz, t5=(hi.z-ray.position.z)*invz;
  if(nan_bits(t0)||nan_bits(t1)||nan_bits(t2)||nan_bits(t3)||nan_bits(t4)||nan_bits(t5)) return 1;
  float near=fmaxf(fmaxf(fminf(t0, t1), fminf(t2, t3)), fminf(t4, t5));
  float px=ray.position.x+dir.x*near, py=ray.position.y+dir.y*near, pz=ray.position.z+dir.z*near;
  float cx=fused? fmaf(0.5f, hi.x-lo.x, lo.x) : lo.x+0.5f*(hi.x-lo.x);
  float cy=fused? fmaf(0.5f, hi.y-lo.y, lo.y) : lo.y+0.5f*(hi.y-lo.y);
  float cz=fused? fmaf(0.5f, hi.z-lo.z, lo.z) : lo.z+0.5f*(hi.z-lo.z);
  float nx=((px-cx)*2.01f)/(hi.x-lo.x), ny=((py-cy)*2.01f)/(hi.y-lo.y), nz=((pz-cz)*2.01f)/(hi.z-lo.z);
  return !(fabsf(nx)<2147483648.0f && fabsf(ny)<2147483648.0f && fabsf(nz)<2147483648.0f);
}
static RayCollision box_fused(Ray ray, Vector3 lo, Vector3 hi){
  RayCollision collision={0};
  Vector3 dir=ray.direction;
  int inside=inside_box(ray.position, lo, hi);
  if(inside) dir=neg3(dir);
  float invx=1.0f/dir.x, invy=1.0f/dir.y, invz=1.0f/dir.z;
  float t0=(lo.x-ray.position.x)*invx, t1=(hi.x-ray.position.x)*invx;
  float t2=(lo.y-ray.position.y)*invy, t3=(hi.y-ray.position.y)*invy;
  float t4=(lo.z-ray.position.z)*invz, t5=(hi.z-ray.position.z)*invz;
  float near=fmaxf(fmaxf(fminf(t0, t1), fminf(t2, t3)), fminf(t4, t5));
  float far=fminf(fminf(fmaxf(t0, t1), fmaxf(t2, t3)), fmaxf(t4, t5));
  Vector3 point=add3(ray.position, scale3(dir, near));
  float cx=fmaf(0.5f, hi.x-lo.x, lo.x), cy=fmaf(0.5f, hi.y-lo.y, lo.y), cz=fmaf(0.5f, hi.z-lo.z, lo.z);
  Vector3 normal={((point.x-cx)*2.01f)/(hi.x-lo.x), ((point.y-cy)*2.01f)/(hi.y-lo.y), ((point.z-cz)*2.01f)/(hi.z-lo.z)};
  normal.x=(float)(int)normal.x; normal.y=(float)(int)normal.y; normal.z=(float)(int)normal.z;
  normal=normalize_f(normal);
  collision.hit=!((far<0.0f)||(near>far));
  collision.distance=inside? -near : near;
  collision.point=point;
  collision.normal=inside? neg3(normal) : normal;
  return collision;}
static void show(RayCollision c){
  printf("[%d,%u,%u,%u,%u,%u,%u,%u]", c.hit?1:0, bits(c.distance), bits(c.point.x), bits(c.point.y), bits(c.point.z),
    bits(c.normal.x), bits(c.normal.y), bits(c.normal.z));}
'''


def c_vec(words):
    return '(Vector3){' + ','.join(f'load({word})' for word in words) + '}'


def native_case(kind, args):
    ray = f'(Ray){{{c_vec(args[0:3])}, {c_vec(args[3:6])}}}'
    if kind == 'sphere':
        return (f'{{Ray ray={ray}; Vector3 center={c_vec(args[6:9])}; float radius=load({args[9]}); '
                'printf("["); show(GetRayCollisionSphere(ray, center, radius)); printf(","); '
                'show(sphere_fused(ray, center, radius)); printf("]\\n");}')
    if kind == 'triangle':
        return (f'{{Ray ray={ray}; Vector3 p1={c_vec(args[6:9])}, p2={c_vec(args[9:12])}, p3={c_vec(args[12:15])}; '
                'printf("["); show(GetRayCollisionTriangle(ray, p1, p2, p3)); printf(","); '
                'show(triangle_fused(ray, p1, p2, p3)); printf("]\\n");}')
    if kind == 'quad':
        return (f'{{Ray ray={ray}; Vector3 p1={c_vec(args[6:9])}, p2={c_vec(args[9:12])}, '
                f'p3={c_vec(args[12:15])}, p4={c_vec(args[15:18])}; '
                'printf("["); show(GetRayCollisionQuad(ray, p1, p2, p3, p4)); printf(","); '
                'show(quad_fused(ray, p1, p2, p3, p4)); printf("]\\n");}')
    box = f'(BoundingBox){{{c_vec(args[6:9])}, {c_vec(args[9:12])}}}'
    return (f'{{Ray ray={ray}; Vector3 lo={c_vec(args[6:9])}, hi={c_vec(args[9:12])}; BoundingBox box={box}; '
            'printf("["); if(refused(0, ray, lo, hi)) printf("null"); else show(GetRayCollisionBox(ray, box)); '
            'printf(","); if(refused(1, ray, lo, hi)) printf("null"); else show(box_fused(ray, lo, hi)); '
            'printf("]\\n");}')


def uncontracted_excerpt(raylib_source):
    """The pinned ray queries, so the uncontracted column is not the host library."""
    source = (raylib_source / 'src/rmodels.c').read_text()
    begin = source.index('RayCollision GetRayCollisionSphere(')
    end = source.index('//----------------------------------------------------------------------------------', begin)
    return ('/* Unaltered ray collision functions from pinned raylib; zlib, LICENSES/raylib.txt. */\n'
            + source[begin:end])


def native(probe, rows):
    """The pinned queries are their own translation unit.

    A shared unit lets their `#define EPSILON` and their size change how the
    fused shapes are lowered, including quiet-NaN signs.
    """
    flags = ['clang', '-std=c11', '-O2', '-fno-builtin-atan2f', '-ffp-contract=off',
             '-I' + str(probe.args.raylib_source / 'src')]
    queries = probe.work / 'uncontracted.c'
    queries.write_text('#include "raylib.h"\n#include "raymath.h"\n#include <math.h>\n'
                       '#include <stdio.h>\n#include <string.h>\n'
                       + uncontracted_excerpt(probe.args.raylib_source) + '\n')
    lines = ['#include "raylib.h"', '#include <math.h>', '#include <stdio.h>', '#include <string.h>', ORACLE,
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    lines.extend(native_case(kind, args) for kind, args in rows)
    lines.append('(void)sink; return 0;}')
    oracle = probe.work / 'reference.c'
    oracle.write_text('\n'.join(lines) + '\n')
    objects = [probe.work / 'uncontracted.o', probe.work / 'reference.o']
    probekit.run([*flags, '-c', queries, '-o', objects[0]])
    probekit.run([*flags, '-c', oracle, '-o', objects[1]])
    binary = probe.work / 'reference'
    probekit.run([*flags, *objects, probe.library, '-lm', '-o', binary])
    return probekit.run([binary])


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def flag(hit: Bool) -> String:
  match hit:
    case True{}: "1"
    case False{}: "0"
def shown(collision: J.RayCollision) -> String:
  J.RayCollision{hit, distance, point, normal} = collision
  M.Vector3{x, y, z} = point
  M.Vector3{u, v, w} = normal
  "[" ++ flag(hit) ++ "," ++ U32.show(F32.bits(distance)) ++ "," ++ U32.show(F32.bits(x)) ++ ","
    ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ U32.show(F32.bits(u)) ++ ","
    ++ U32.show(F32.bits(v)) ++ "," ++ U32.show(F32.bits(w)) ++ "]"
def shown_box(result: Maybe<J.RayCollision>) -> String:
  match result:
    case None{}: "null"
    case Some{collision}: shown(collision)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def bend_vec(words):
    return 'M.Vector3{' + ', '.join(f'word({word})' for word in words) + '}'


def bend_call(kind, arithmetic, args, libm):
    ray = f'J.Ray{{{bend_vec(args[0:3])}, {bend_vec(args[3:6])}}}'
    if kind == 'sphere':
        return f'J.Collision.ray_sphere_for({arithmetic}, {ray}, {bend_vec(args[6:9])}, word({args[9]}))'
    if kind == 'triangle':
        return (f'J.Collision.ray_triangle_for({arithmetic}, {ray}, {bend_vec(args[6:9])}, '
                f'{bend_vec(args[9:12])}, {bend_vec(args[12:15])})')
    if kind == 'quad':
        return (f'J.Collision.ray_quad_for({arithmetic}, {ray}, {bend_vec(args[6:9])}, {bend_vec(args[9:12])}, '
                f'{bend_vec(args[12:15])}, {bend_vec(args[15:18])})')
    box = f'J.BoundingBox{{{bend_vec(args[6:9])}, {bend_vec(args[9:12])}}}'
    return f'J.Collision.ray_box_for({arithmetic}, M.{libm}{{}}, {ray}, {box})'


def render(libm):
    def emit(selected, gpu):
        body = PROGRAM
        for kind, args in selected:
            show = 'shown_box' if kind == 'box' else 'shown'
            left = bend_call(kind, 'M.Uncontracted{}', args, libm)
            right = bend_call(kind, 'M.Fused{}', args, libm)
            body += f'    IO.print("[" ++ {show}({left}) ++ "," ++ {show}({right}) ++ "]")\n'
        return body
    return emit


def field_diff(want, got):
    """ok, sign (quiet-NaN sign only) or value."""
    if want == got:
        return 'ok'
    if not isinstance(want, list) or not isinstance(got, list) or len(want) != 8 or len(got) != 8 or want[0] != got[0]:
        return 'value'
    sign = False
    for left, right in zip(want[1:], got[1:]):
        if left == right:
            continue
        if (left ^ right) == 0x80000000 and (left & 0x7FFFFFFF) > 0x7F800000 and (right & 0x7FFFFFFF) > 0x7F800000:
            sign = True
            continue
        return 'value'
    return 'sign' if sign else 'ok'


def main():
    probe = probekit.Probe('ray-exceptional', probekit.arguments(__doc__))
    libm = gradient_reference()
    rows = cases()
    if not rows or len(rows) > 4000:
        raise ProbeFailure(f'ray-exceptional: {len(rows)} cases is outside the probe budget')
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'ray-exceptional: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render(libm), rows, batch=120)
    sign_rows = {}
    for lane, actual in lanes.items():
        if len(actual) != len(expected):
            raise ProbeFailure(f'ray-exceptional: {lane} produced {len(actual)} rows, expected {len(expected)}')
        allowed, problems = [], []
        for index, (want, got) in enumerate(zip(expected, actual)):
            kind, _args = rows[index]
            for side, slot in ((0, 'uncontracted'), (1, 'fused')):
                diff = field_diff(want[side], got[side])
                if diff == 'ok':
                    continue
                # Clang and the CPU lanes disagree on these quiet-NaN signs.
                # The fused profile and JavaScript match the reference bits.
                if diff == 'sign' and lane != 'javascript' and slot == 'uncontracted' and kind in ('sphere', 'quad'):
                    allowed.append(index)
                    continue
                problems.append((kind, slot, diff, index))
        sign_rows[lane] = len(allowed)
        probe.report.setdefault('lanes', {})[lane] = dict(passed=not problems, rows=len(actual), sign_rows=len(allowed))
        probe.save()
        if problems:
            kind, slot, diff, index = problems[0]
            side = 0 if slot == 'uncontracted' else 1
            raise ProbeFailure(
                f'ray-exceptional: {lane} has {len(problems)} {diff} mismatches; first {slot} {kind} '
                f'{tuple(hex(word) for word in rows[index][1])}: reference={json.dumps(expected[index][side])} '
                f'jonlib={json.dumps(actual[index][side])}')
    counts = {kind: sum(row_kind == kind for row_kind, _ in rows) for kind in ('sphere', 'triangle', 'quad', 'box')}
    probe.finish(cases=len(rows), libm=libm, sign_rows=sign_rows, **counts,
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
