#!/usr/bin/env python3
"""Compare GetRayCollisionSphere/Box/Triangle/Quad with Jonlib's ray collisions.

Every result's hit flag and F32 distance, point and normal bits must equal
the linked raylib's under the host contraction profile (conformance.contraction)
and the host libm's signed-zero fmin/fmax ties (conformance.gradient_reference).
NaN results (sphere misses take sqrtf of a negative) compare as one NaN class,
since their sign and payload are not portable. Box inputs where a slab
distance is NaN or a pre-cast normal component is outside the int range are
None in Jonlib: raylib's arm64 build and C disagree on NaN slabs and the int
cast is undefined. A C oracle that repeats the slab and normal arithmetic
decides which inputs Jonlib must refuse, and native results for the others
must match exactly. --uncontracted-control compiles the pinned rmodels.c ray
functions with contraction off, to check the Uncontracted profile on any host.
CPU/JS lanes.
"""
import hashlib
import json
import random
import struct

from conformance import contraction, f32, gradient_reference
import probekit
from probekit import ProbeFailure

NAN = 0x7FC00000


def fp(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def cases():
    rng = random.Random(0x4A7)
    uniform = lambda low, high: fp(rng.uniform(low, high))
    vector = lambda low=-10.0, high=10.0: [uniform(low, high) for _ in range(3)]
    grid = lambda: [fp(rng.choice((-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0))) for _ in range(3)]
    unit = lambda: [fp(rng.choice((-1.0, 0.0, 1.0))) for _ in range(3)]
    rows = []

    def add(kind, *values):
        rows.append((kind, [fp(v) for part in values for v in (part if isinstance(part, list) else [part])]))

    # Spheres: ray position, direction, center, radius.
    for _ in range(70):
        add('sphere', vector(), vector(-1, 1), vector(), uniform(0.1, 8.0))
    for _ in range(20):  # aimed at the center, from inside and outside
        center, position = vector(), vector()
        add('sphere', position, [c - p for c, p in zip(center, position)], center, uniform(0.5, 20.0))
    add('sphere', [0.0, 0.0, -5.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 1.0)
    add('sphere', [0.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 1.0)
    add('sphere', [0.0, 1.0, -5.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 1.0)
    add('sphere', [0.0, 2.0, -5.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 1.0)
    add('sphere', [0.0, 0.0, 5.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 1.0)
    add('sphere', [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 3.0)
    add('sphere', [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [1.0, 1.0, 1.0], 0.0)
    add('sphere', [-0.0, 0.0, -0.0], [0.0, -0.0, 2.0], [0.0, 0.0, 4.0], 0.5)

    # Triangles: ray position, direction, p1, p2, p3.
    for index in range(90):
        p1, p2, p3, position = vector(), vector(), vector(), vector()
        if index % 3:
            a, b = rng.random(), rng.random()
            a, b = (a, b) if a + b <= 1 else (1 - a, 1 - b)
            target = [x + a * (y - x) + b * (z - x) for x, y, z in zip(p1, p2, p3)]
            direction = [t - p for t, p in zip(target, position)]
            if index % 9 == 1:
                direction = [-d for d in direction]
        else:
            direction = vector(-1, 1)
        add('triangle', position, direction, p1, p2, p3)
    add('triangle', [0.25, 0.25, -1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.25, 0.25, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.0, 0.0, -1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.5, 0.5, -1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.25, 0.25, 0.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.25, 0.25, -1.0], [1.0, 0.0, 0.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    add('triangle', [0.25, 0.25, -1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [2.0, 0.0, 0.0])

    # Quads: ray position, direction, p1, p2, p3, p4 (planar and skewed).
    for index in range(40):
        corners = [vector() for _ in range(4)] if index % 2 else \
            [[x, y, 1.5] for x, y in ((-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0))]
        position = vector()
        target = [uniform(-1, 1), uniform(-1, 1), 1.5] if not index % 2 else vector()
        add('quad', position, [t - p for t, p in zip(target, position)], *corners)

    # Boxes: ray position, direction, min, max.
    for _ in range(80):
        low, size = vector(), vector(0.1, 6.0)
        add('box', vector(), vector(-1, 1), low, [l + s for l, s in zip(low, size)])
    for _ in range(30):  # from inside
        low, size = vector(), vector(0.5, 6.0)
        position = [l + s * rng.random() for l, s in zip(low, size)]
        add('box', position, vector(-1, 1), low, [l + s for l, s in zip(low, size)])
    for _ in range(90):  # unit grid: zero direction components, origins on faces, signed-zero ties
        add('box', grid(), unit(), [-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    add('box', [0.0, 0.0, -5.0], [0.0, 0.0, 1.0], [-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    add('box', [1.0, 1.0, -5.0], [0.0, -1.0, 1.0], [-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    add('box', [1.0, 0.0, 0.0], [-1.0, 1.0, 0.0], [-1.0, 0.0, -1.0], [1.0, 1.0, 1.0])
    add('box', [5.0, 0.0, 0.0], [-1.0, 0.0, 0.0], [-1.0, -1.0, 0.0], [1.0, 1.0, 0.0])
    add('box', [5.0, 0.5, 0.25], [-1.0, 0.0, 0.0], [-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    add('box', [0.0, 0.0, 0.0], [1.0, 1.0, 1.0], [2.0, 2.0, 2.0], [-2.0, -2.0, -2.0])
    add('box', [1e30, 0.0, 0.0], [-1.0, 0.0, 0.0], [-1e-30, -1.0, -1.0], [1e-30, 1.0, 1.0])
    return rows


SIGNATURES = {'sphere': ('ttts', 'GetRayCollisionSphere', 'ray_sphere_for'), 'triangle': ('ttttt', 'GetRayCollisionTriangle', 'ray_triangle_for'),
              'quad': ('tttttt', 'GetRayCollisionQuad', 'ray_quad_for'), 'box': ('tttt', 'GetRayCollisionBox', 'ray_box_for')}


def split(kind, values):
    """(ray position, ray direction, remaining arguments as 3-vectors or scalars)."""
    parts, at = [], 0
    for letter in SIGNATURES[kind][0]:
        size = 3 if letter == 't' else 1
        parts.append(values[at:at + size])
        at += size
    return parts[0], parts[1], parts[2:]


def c_vector(values):
    return '(Vector3){' + ','.join(x.hex() + 'f' for x in values) + '}'


def c_arguments(kind, values):
    position, direction, rest = split(kind, values)
    ray = f'(Ray){{{c_vector(position)},{c_vector(direction)}}}'
    if kind == 'box':
        return ray, f'(BoundingBox){{{c_vector(rest[0])},{c_vector(rest[1])}}}'
    return ','.join([ray] + [c_vector(p) if len(p) == 3 else p[0].hex() + 'f' for p in rest])


def bend_arguments(kind, values):
    position, direction, rest = split(kind, values)
    vec = lambda v: 'M.Vector3{' + ', '.join(f32(x) for x in v) + '}'
    ray = f'J.Ray{{{vec(position)}, {vec(direction)}}}'
    if kind == 'box':
        return f'{ray}, J.BoundingBox{{{vec(rest[0])}, {vec(rest[1])}}}'
    return ', '.join([ray] + [vec(p) if len(p) == 3 else f32(p[0]) for p in rest])


# The refusal oracle repeats Jonlib's box contract: NaN slab distances or
# normals outside the int range (compiled with contraction off; the fused
# profile's lerp is the explicit fmaf the arm64 build uses).
ORACLE = '''static int refused(Ray r, BoundingBox b){
  int inside=(r.position.x>b.min.x)&&(r.position.x<b.max.x)&&(r.position.y>b.min.y)&&(r.position.y<b.max.y)&&(r.position.z>b.min.z)&&(r.position.z<b.max.z);
  if(inside)r.direction=(Vector3){-r.direction.x,-r.direction.y,-r.direction.z};
  float p[3]={r.position.x,r.position.y,r.position.z},d[3]={r.direction.x,r.direction.y,r.direction.z};
  float lo[3]={b.min.x,b.min.y,b.min.z},hi[3]={b.max.x,b.max.y,b.max.z},t[6];
  for(int k=0;k<3;k++){float inv=1.0f/d[k];t[2*k]=(lo[k]-p[k])*inv;t[2*k+1]=(hi[k]-p[k])*inv;}
  for(int k=0;k<6;k++)if(isnan(t[k]))return 1;
  float near=fmaxf(fmaxf(fminf(t[0],t[1]),fminf(t[2],t[3])),fminf(t[4],t[5]));
  for(int k=0;k<3;k++){float q=p[k]+d[k]*near;float c=FUSED?fmaf(0.5f,hi[k]-lo[k],lo[k]):lo[k]+0.5f*(hi[k]-lo[k]);
    float n=((q-c)*2.01f)/(hi[k]-lo[k]);if(!(fabsf(n)<2147483648.0f))return 1;}
  return 0;}
'''


def native(probe, rows, profile, control):
    lines = ['#include "raylib.h"', '#include "raymath.h"', '#include <math.h>', '#include <stdio.h>', '#include <string.h>']
    if control:
        source = (probe.args.raylib_source / 'src/rmodels.c').read_text()
        begin = source.index('RayCollision GetRayCollisionSphere(')
        end = source.index('//----------------------------------------------------------------------------------', begin)
        lines += ['/* Unaltered ray collision functions from pinned raylib; zlib, LICENSES/raylib.txt. */', source[begin:end]]
    lines += [f'#define FUSED {int(profile == "Fused")}', ORACLE,
              'static unsigned bits(float x){unsigned b;memcpy(&b,&x,4);return b;}',
              'static void emit(RayCollision c){printf("[%d,%u,%u,%u,%u,%u,%u,%u]\\n",c.hit?1:0,bits(c.distance),'
              'bits(c.point.x),bits(c.point.y),bits(c.point.z),bits(c.normal.x),bits(c.normal.y),bits(c.normal.z));}',
              'int main(void){']
    for kind, values in rows:
        if kind == 'box':
            ray, box = c_arguments(kind, values)
            lines.append(f'{{Ray r={ray};BoundingBox b={box};if(refused(r,b))puts("null");else emit(GetRayCollisionBox(r,b));}}')
        else:
            lines.append(f'emit({SIGNATURES[kind][1]}({c_arguments(kind, values)}));')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n', extra_flags=('-ffp-contract=off',))


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def flag(hit: Bool) -> U32:
  match hit:
    case True{}: 1
    case False{}: 0
def bits3(vector: M.Vector3, rest: List<U32>) -> List<U32>:
  M.Vector3{x, y, z} = vector
  Con{F32.bits(x), Con{F32.bits(y), Con{F32.bits(z), rest}}}
def emit(collision: J.RayCollision) -> IO(Unit):
  J.RayCollision{hit, distance, point, normal} = collision
  IO.print(List.show(~&1, ~U32, ~U32.show, Con{flag(hit), Con{F32.bits(distance), bits3(point, bits3(normal, Nil{}))}}))
def emit_box(result: Maybe<J.RayCollision>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{collision}: emit(collision)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(profile, libm):
    def emit(selected, gpu):
        body = PROGRAM
        for kind, values in selected:
            extra = f'M.{libm}{{}}, ' if kind == 'box' else ''
            call = f'J.Collision.{SIGNATURES[kind][2]}(M.{profile}{{}}, {extra}{bend_arguments(kind, values)})'
            body += f'    {"emit_box" if kind == "box" else "emit"}({call})\n'
        return body
    return emit


def canonical(row):
    """NaN words as one class; None for a refused box."""
    if row is None:
        return None
    return [row[0]] + [NAN if (word & 0x7FFFFFFF) > 0x7F800000 else word for word in row[1:]]


def main():
    args = probekit.arguments(__doc__, lambda parser: parser.add_argument('--uncontracted-control', action='store_true'))
    control = args.uncontracted_control
    probe = probekit.Probe('ray-uncontracted' if control else 'ray', args)
    profile = 'Uncontracted' if control else contraction()
    libm = gradient_reference()
    rows = cases()
    text = native(probe, rows, profile, control)
    expected = [canonical(json.loads(line)) for line in text.splitlines()]
    if len(expected) != len(rows):
        raise ProbeFailure('ray: incomplete native output')
    lanes = probe.candidates(render(profile, libm), rows, batch=64,
                             parse=lambda text, selected: [canonical(json.loads(line)) for line in text.splitlines()])
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{rows[i][0]} #{i} {rows[i][1]}')
    counts = {kind: sum(k == kind for k, _ in rows) for kind in SIGNATURES}
    probe.finish(reference='uncontracted source control' if control else 'linked raylib', profile=profile, libm=libm,
                 **counts, hits=sum(bool(row and row[0]) for row in expected), refused_boxes=sum(row is None for row in expected),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
