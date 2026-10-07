#!/usr/bin/env python3
"""Compare raylib's named colors and math constants with Jonlib/Jonmath.

The 26 raylib.h color macros and the PI, DEG2RAD, RAD2DEG and EPSILON macros are
compiled from the pinned headers. raymath's C++ `static constexpr` conveniences
(Vector2Zeros ... MatrixUnit) are read from the pinned raymath.h initializers,
since the reference tooling compiles C. Every value compares bit for bit on
CPU-1, CPU-2 and JavaScript.
"""
import hashlib
import json
import re
import struct

from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
import probekit
from probekit import ProbeFailure

COLORS = ['LIGHTGRAY', 'GRAY', 'DARKGRAY', 'YELLOW', 'GOLD', 'ORANGE', 'PINK', 'RED', 'MAROON', 'GREEN', 'LIME',
          'DARKGREEN', 'SKYBLUE', 'BLUE', 'DARKBLUE', 'PURPLE', 'VIOLET', 'DARKPURPLE', 'BEIGE', 'BROWN',
          'DARKBROWN', 'WHITE', 'BLACK', 'BLANK', 'MAGENTA', 'RAYWHITE']
SCALARS = ['PI', 'DEG2RAD', 'RAD2DEG', 'EPSILON']
# raymath C++ constant: Jonmath expression yielding its F32 fields in declaration order.
VECTORS = {
    'Vector2Zeros': 'v2(M.Vector2.zero())', 'Vector2Ones': 'v2(M.Vector2.one())',
    'Vector2UnitX': 'v2(M.Vector2.unit_x())', 'Vector2UnitY': 'v2(M.Vector2.unit_y())',
    'Vector3Zeros': 'v3(M.Vector3.zero())', 'Vector3Ones': 'v3(M.Vector3.one())',
    'Vector3UnitX': 'v3(M.Vector3.unit_x())', 'Vector3UnitY': 'v3(M.Vector3.unit_y())', 'Vector3UnitZ': 'v3(M.Vector3.unit_z())',
    'Vector4Zeros': 'v4(M.Vector4.zero())', 'Vector4Ones': 'v4(M.Vector4.one())',
    'Vector4UnitX': 'v4(M.Vector4.unit_x())', 'Vector4UnitY': 'v4(M.Vector4.unit_y())',
    'Vector4UnitZ': 'v4(M.Vector4.unit_z())', 'Vector4UnitW': 'v4(M.Vector4.unit_w())',
    'QuaternionZeros': 'v4(M.Vector4.zero())', 'QuaternionOnes': 'v4(M.Vector4.one())',
    'QuaternionUnitX': 'v4(M.Quaternion.identity())', 'MatrixUnit': 'matrix(M.Matrix.identity())',
}


def header_vectors(raymath):
    """F32 bits of each constexpr initializer, in declaration order."""
    values = {}
    for name in VECTORS:
        match = re.search(r'static constexpr \w+ ' + name + r'\s*=\s*\{([^}]*)\}', raymath)
        if not match:
            raise ProbeFailure(f'{name}: initializer not found in raymath.h')
        floats = [float(v) for v in match.group(1).replace('\n', ' ').split(',') if v.strip()]
        values[name] = list(struct.pack('<' + 'f' * len(floats), *floats))
    return values


def native(probe):
    lines = ['#include "raylib.h"', '#include "raymath.h"', '#include <stdio.h>', '#include <string.h>', C_EMITTER,
             'static void color(Color c){byte(c.r);byte(c.g);byte(c.b);byte(c.a);end();}',
             'static void scalar(float f){unsigned u;memcpy(&u,&f,4);word(u);end();}',
             'int main(void){']
    lines += [f'color({name});' for name in COLORS]
    lines += [f'scalar({name});' for name in SCALARS]
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
''' + BEND_EMITTER + '''def word(+value: U32, rest: List<U32>) -> List<U32>:
  Con{(value .&. 255 : U32), Con{((value >> 8n) .&. 255 : U32), Con{((value >> 16n) .&. 255 : U32), Con{(value >> 24n : U32), rest}}}}
def floats(values: +List<F32>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: word(F32.bits(value), floats(rest))
def color(+value: U32) -> IO(Unit):
  emit_bytes(~&1, [J.Color.red(value), J.Color.green(value), J.Color.blue(value), J.Color.alpha(value)])
def scalar(value: F32) -> IO(Unit):
  emit_bytes(~&1, word(F32.bits(value), Nil{}))
def v2(value: M.Vector2) -> IO(Unit):
  M.Vector2{x, y} = value
  emit_bytes(~&1, floats([x, y]))
def v3(value: M.Vector3) -> IO(Unit):
  M.Vector3{x, y, z} = value
  emit_bytes(~&1, floats([x, y, z]))
def v4(value: M.Vector4) -> IO(Unit):
  M.Vector4{x, y, z, w} = value
  emit_bytes(~&1, floats([x, y, z, w]))
def matrix(value: M.Matrix) -> IO(Unit):
  emit_bytes(~&1, floats(M.Matrix.to_float_v(value)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for kind, name in selected:
        if kind == 'color':
            body += f'    color(J.Color.{name}())\n'
        elif kind == 'scalar':
            body += f'    scalar(M.Math.{name}())\n'
        else:
            body += f'    {VECTORS[name]}\n'
    return body


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('constants', args)
    raymath = (args.raylib_source / 'src/raymath.h').read_text()
    expected = parse_results(native(probe))
    vectors = header_vectors(raymath)
    actions = [('color', name) for name in COLORS] + [('scalar', name) for name in SCALARS] + [('vector', name) for name in VECTORS]
    expected += [vectors[name] for name in VECTORS]
    if len(expected) != len(actions):
        raise ProbeFailure('constants: incomplete native output')
    lanes = probe.candidates(render, actions, batch=len(actions), parse=lambda text, selected: parse_results(text))
    probe.compare(expected, lanes, describe=lambda i: actions[i][1])
    probe.finish(colors=len(COLORS), scalars=len(SCALARS), vectors=len(VECTORS),
                 reference_sha256=hashlib.sha256(json.dumps(expected).encode()).hexdigest())


if __name__ == '__main__':
    main()
