#!/usr/bin/env python3
"""Compare Jonlights with rlights.h.

The native reference links raylib (the gates' software-renderer build), loads
the default shader (LoadShader(0, 0)) after InitWindow and calls rlights.h's
CreateLight six times (directional and point lights, positions, targets and
colors from the corpus) and UpdateLightValues on each, printing every Light
field (the floats as words, the bool as 0/1, the locations as ints) and the
shader's id. Jonlights runs Light.create over a threaded Lights value and
Light.update_values the same way: the first MAX_LIGHTS (4) lights take the
shader's locations for lights[0..3] (-1 on the software renderer, which has
no shaders), the later ones are zero lights. CPU-1, CPU-2 and JavaScript
lanes.
"""
import struct

import probekit
from probekit import ProbeFailure

LIGHTS = [
    (1, (-2.0, 1.0, -2.0), (0.0, 0.0, 0.0), (253, 249, 0, 255)),
    (1, (2.0, 1.0, 2.0), (0.0, 0.0, 0.0), (230, 41, 55, 255)),
    (0, (-2.0, 1.0, 2.0), (0.5, -0.25, 3.0), (0, 228, 48, 255)),
    (1, (2.0, 1.0, -2.0), (0.0, 0.0, 0.0), (0, 121, 241, 128)),
    (1, (0.0, 4.0, 0.0), (1.0, 1.0, 1.0), (255, 255, 255, 255)),
    (0, (1.5, -3.0, 0.125), (0.0, 0.0, 0.0), (17, 34, 51, 68)),
]


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


NATIVE = r'''#include <stdio.h>
#include <string.h>
#include "raylib.h"
#define RLIGHTS_IMPLEMENTATION
#include "HEADER_PATH"
static unsigned w(float v) { unsigned u; memcpy(&u, &v, 4); return u; }
static void show(Light l) {
  printf("%d %d %u %u %u %u %u %u %u %u %u %u %u %d %d %d %d %d %d\n", l.type, l.enabled ? 1 : 0,
         w(l.position.x), w(l.position.y), w(l.position.z), w(l.target.x), w(l.target.y), w(l.target.z),
         l.color.r, l.color.g, l.color.b, l.color.a, w(l.attenuation),
         l.enabledLoc, l.typeLoc, l.positionLoc, l.targetLoc, l.colorLoc, l.attenuationLoc);
}
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  InitWindow(16, 16, "");
  Shader shader = LoadShader(0, 0);
CALLS  printf("%u\n", shader.id);
  CloseWindow();
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
import ../../jonlib.bend as J
import ../../jonlights.bend as L
def f(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def int(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))
def show(+light: L.Light) -> String:
  L.Light{+kind, +enabled, +position, +target, +color, +attenuation, +el, +tl, +pl, +gl, +cl, +al} = light
  M.Vector3{+px, +py, +pz} = position
  M.Vector3{+tx, +ty, +tz} = target
  int(kind) ++ " " ++ U32.show(Bool.to_u32(enabled)) ++ " " ++ U32.show(F32.bits(px)) ++ " " ++ U32.show(F32.bits(py)) ++ " " ++ U32.show(F32.bits(pz))
    ++ " " ++ U32.show(F32.bits(tx)) ++ " " ++ U32.show(F32.bits(ty)) ++ " " ++ U32.show(F32.bits(tz))
    ++ " " ++ U32.show((color >> 24n : U32)) ++ " " ++ U32.show(((color >> 16n) .&. 255 : U32)) ++ " " ++ U32.show(((color >> 8n) .&. 255 : U32)) ++ " " ++ U32.show((color .&. 255 : U32))
    ++ " " ++ U32.show(F32.bits(attenuation)) ++ " " ++ int(el) ++ " " ++ int(tl) ++ " " ++ int(pl) ++ " " ++ int(gl) ++ " " ++ int(cl) ++ " " ++ int(al)
type St is Data:
  St{lights: L.Lights, text: String, shader: J.Shader}
def step.light(+text: String, +shader: J.Shader, inner: L.Lights & L.Light) -> St:
  (lights, +light) = inner
  St{lights, text ++ show(light) ++ "\\n", L.Light.update_values(shader, light)}
def step.made(+text: String, made: (L.Lights & L.Light) & J.Shader) -> St:
  (inner, +shader) = made
  step.light(text, shader, inner)
def step(state: St, +kind: U32, +position: M.Vector3, +target: M.Vector3, +color: U32) -> St:
  St{lights, +text, +shader} = state
  step.made(text, L.Light.create(lights, kind, position, target, color, shader))
def finish(state: St) -> String:
  St{_, +text, +shader} = state
  J.Shader{+id, _} = shader
  text ++ U32.show(id)
def main() -> IO(Unit):
  IO.print(finish(STEPS))
'''


def c_calls():
    lines = []
    for type_, p, t, c in LIGHTS:
        lines.append(f'  {{ Light l = CreateLight({type_}, (Vector3){{ {p[0]}f, {p[1]}f, {p[2]}f }}, (Vector3){{ {t[0]}f, {t[1]}f, {t[2]}f }}, '
                     f'(Color){{ {c[0]}, {c[1]}, {c[2]}, {c[3]} }}, shader); UpdateLightValues(shader, l); show(l); }}\n')
    return ''.join(lines)


def bend_steps():
    state = 'St{L.Lights.new(), "", J.Shader.load(None{}, None{})}'
    for type_, p, t, c in LIGHTS:
        color = (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | c[3]
        v = lambda xs: 'M.Vector3{' + ', '.join(f'f({word(x)})' for x in xs) + '}'
        state = f'step({state}, {type_}, {v(p)}, {v(t)}, {color})'
    return state


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('lights', args)
    header = args.raylib_source / 'examples' / 'shaders' / 'rlights.h'
    if header.read_text() != (args.raylib_source / 'examples' / 'models' / 'rlights.h').read_text():
        raise ProbeFailure('lights: the shaders and models copies of rlights.h differ')
    expected = probe.native(NATIVE.replace("HEADER_PATH", str(header)).replace('CALLS', c_calls())).splitlines()
    # rlsw reports its initialization on stdout whatever the trace level.
    expected = [line for line in expected if not line.startswith('INFO: RLSW')]
    if len(expected) != len(LIGHTS) + 1:
        raise ProbeFailure(f'lights: the reference printed {len(expected)} lines')

    def render(items, gpu):
        return PROGRAM.replace('STEPS', bend_steps())

    def parse(text, items):
        return [[line for line in text.split('\n') if line.strip()]]

    lanes = probe.candidates(render, [0], batch=1, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare([expected], lanes, describe=lambda i: 'CreateLight sequence')
    probe.finish(lights=len(LIGHTS), created=min(len(LIGHTS), 4), shader_id=expected[-1])


if __name__ == '__main__':
    main()
