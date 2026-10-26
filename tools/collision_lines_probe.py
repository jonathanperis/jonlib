#!/usr/bin/env python3
"""Compare CheckCollisionLines on exceptional and subnormal inputs.

The uncontracted result is the linked raylib. The fused result uses the
Apple-clang shapes: fma(a, b, -(c*d)) for the determinant and parameters,
and fma(t, r, start) for the hit point. Misses do not compare a point.
Every hit flag and every hit coordinate bit is compared on CPU-1, CPU-2
and JavaScript.
"""
import hashlib
import json

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


def cases():
    anchors = (
        (ZERO, ZERO, ONE, ONE, ZERO, ONE, ONE, ZERO),
        (ZERO, ZERO, ONE, ZERO, ZERO, ONE, ONE, ONE),
        (ZERO, ZERO, ONE, ZERO, ONE, ZERO, ONE, ONE),
        (ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO, ZERO),
    )
    rows, seen = [], set()
    for anchor in anchors:
        candidates = [anchor]
        for index in range(8):
            for word in EDGE:
                changed = list(anchor)
                changed[index] = word
                candidates.append(tuple(changed))
        for word in EDGE:
            candidates.append((word,) * 8)
        for args in candidates:
            if args not in seen:
                seen.add(args)
                rows.append(args)
    return rows


NATIVE = r'''
#include "raylib.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
static unsigned sink;
static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}
static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}
static void fused(float x,float y,float ex,float ey,float u,float v,float eu,float ev,int *hit,unsigned *px,unsigned *py){
  float rx=ex-x, ry=ey-y, sx=eu-u, sy=ev-v;
  float divisor=fmaf(rx, sy, -(ry*sx));
  *hit=0; *px=0; *py=0;
  if(!(fabsf(divisor)>=1.1920928955078125e-7f)) return;
  float dx=u-x, dy=v-y;
  float t=fmaf(dx, sy, -(dy*sx))/divisor;
  float s=fmaf(dx, ry, -(dy*rx))/divisor;
  if(!((0.0f<=t)&&(t<=1.0f)&&(0.0f<=s)&&(s<=1.0f))) return;
  float hx=fmaf(t, rx, x), hy=fmaf(t, ry, y);
  *hit=1; *px=bits(hx); *py=bits(hy);
}
int main(void){
  SetTraceLogLevel(LOG_NONE);
'''


def native(probe, rows):
    lines = [NATIVE]
    for args in rows:
        loaded = ','.join(f'load({word})' for word in args)
        lines.append(
            '{Vector2 p={0}; int hit=CheckCollisionLines('
            f'(Vector2){{load({args[0]}),load({args[1]})}},'
            f'(Vector2){{load({args[2]}),load({args[3]})}},'
            f'(Vector2){{load({args[4]}),load({args[5]})}},'
            f'(Vector2){{load({args[6]}),load({args[7]})}}, &p);'
            'int fh; unsigned fx, fy;'
            f'fused({loaded}, &fh, &fx, &fy);'
            'printf("[%d,%u,%u,%d,%u,%u]\\n", hit, hit?bits(p.x):0, hit?bits(p.y):0, fh, fx, fy);}'
        )
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def text(hit: Maybe<&2, M.Vector2>) -> String:
  match hit:
    case None{}: "0,0,0"
    case Some{point}:
      M.Vector2{x, y} = point
      "1," ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def bend_segment(words):
    return 'M.Vector2{{{0}, {1}}}'.format(*(f'word({word})' for word in words))


def render(selected, gpu):
    body = PROGRAM
    for args in selected:
        call = ', '.join(bend_segment(args[i:i + 2]) for i in range(0, 8, 2))
        body += (
            '    IO.print("[" ++ text(J.Collision.lines_for(M.Uncontracted{}, '
            + call + ')) ++ "," ++ text(J.Collision.lines_for(M.Fused{}, ' + call + ')) ++ "]")\n'
        )
    return body


def main():
    probe = probekit.Probe('collision-lines', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'collision-lines: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=200)
    probe.compare(expected, lanes, lambda index: str(tuple(hex(word) for word in rows[index])))
    probe.finish(cases=len(rows),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
