#!/usr/bin/env python3
"""Compare Jonlib's Vr.load_stereo_config_for with LoadVrStereoConfig of the pinned raylib.

The reference is the uncontracted memory-platform raylib (its software
renderer is not OpenGL 1.1 for LoadVrStereoConfig, which computes the whole
configuration there). For each device both sides print every word of the
configuration: the two projection matrices, the two view offset matrices,
the lens and screen centers and the two distortion scales (binary32 bits).

The devices: the one of core_vr_simulator; other resolutions (portrait, one
pixel, odd and negative C ints); screens from a millimetre to ten metres;
lenses further apart than half the screen (a negative lens shift), on the
screen's edge and together; eyes from a millimetre to a metre from the
screen; distortion polynomials of zeros, negative and large coefficients
and one that cancels to a scale near 0; interpupillary distances of 0,
negative and large; values drawn from a seeded generator.

Contracts (Jonlib must answer null, and the reference is not compared): a
resolution or a screen width of 0, NaN and infinite fields (a result that is
not finite), a distortion scale of 0 (the scales divide by it), a screen
height of 0 (a perspective of no height), and M.AppleLibm for every device.
CPU-1, CPU-2 and JavaScript lanes.
"""
import math
import random
import struct

from conformance import gradient_reference
import frame_probe as fp
import probekit
from probekit import ProbeFailure


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


EXAMPLE = dict(h=2160, v=1200, width=0.133793, height=0.0669, eye=0.041, separation=0.07, ipd=0.07, distortion=(1.0, 0.22, 0.24, 0.0), chroma=(0.996, -0.004, 1.014, 0.0))


def cases():
    out = []

    def add(name, contract=False, **changes):
        out.append(dict(id=name, contract=contract, device=dict(EXAMPLE, **changes)))

    add('example')
    add('full-hd', h=1920, v=1080)
    add('portrait', h=1200, v=2160)
    add('one-pixel', h=1, v=1)
    add('odd', h=2161, v=1199)
    add('negative-width', h=-2160)
    add('negative-height', v=-1200)
    add('wide', h=7680, v=1080)
    add('small-screen', width=0.001, height=0.0005, separation=0.0004)
    add('large-screen', width=10.0, height=5.0, separation=4.0)
    add('lenses-apart', separation=0.1)
    add('lenses-on-the-edge', separation=0.133793)
    add('lenses-together', separation=0.0)
    add('lenses-quarter', separation=0.0668965)
    add('eye-near', eye=0.001)
    add('eye-far', eye=1.0)
    add('eye-behind', eye=-0.041)
    add('tall-screen', height=0.5)
    add('flipped-screen', height=-0.0669)
    add('no-distortion', distortion=(1.0, 0.0, 0.0, 0.0))
    add('negative-distortion', distortion=(1.0, -0.2, 0.05, -0.01))
    add('large-distortion', distortion=(2.5, 4.0, 8.0, 16.0))
    add('negative-scale', distortion=(-1.0, 0.0, 0.0, 0.0))
    add('cubic-distortion', distortion=(0.5, 0.25, 0.125, 0.0625))
    add('no-ipd', ipd=0.0)
    add('negative-ipd', ipd=-0.07)
    add('large-ipd', ipd=3.0e30)
    add('chroma-ignored', chroma=(0.0, 0.0, 0.0, 0.0))
    rng = random.Random(20261012)
    for index in range(12):
        add(f'seeded-{index}', h=rng.randrange(320, 4096), v=rng.randrange(240, 2160), width=rng.uniform(0.05, 0.3), height=rng.uniform(0.03, 0.2), eye=rng.uniform(0.02, 0.08),
            separation=rng.uniform(0.03, 0.12), ipd=rng.uniform(0.05, 0.08), distortion=tuple(rng.uniform(-0.5, 1.5) for _ in range(4)))
    add('zero-height-resolution', True, v=0)
    add('zero-width-resolution', True, h=0, width=0.0)
    add('zero-screen-width', True, width=0.0)
    add('zero-screen-height', True, height=0.0)
    add('zero-distortion-scale', True, distortion=(0.0, 0.0, 0.0, 0.0))
    add('nan-width', True, width=math.nan)
    add('nan-distortion', True, distortion=(1.0, math.nan, 0.24, 0.0))
    add('infinite-ipd', True, ipd=math.inf)
    add('infinite-eye', True, eye=math.inf)
    add('nan-eye', True, eye=math.nan)
    return out


def fields(device):
    """The device as words: two C ints, then the float fields in struct order."""
    return [device['h'] & 0xFFFFFFFF, device['v'] & 0xFFFFFFFF, *(bits(device[k]) for k in ('width', 'height', 'eye', 'separation', 'ipd')), *map(bits, device['distortion']),
            *map(bits, device['chroma'])]


C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static unsigned w(float x) { unsigned v; memcpy(&v, &x, 4); return v; }
static float f(unsigned v) { float x; memcpy(&x, &v, 4); return x; }
static void matrix(Matrix m)
{
    float c[16] = { m.m0, m.m4, m.m8, m.m12, m.m1, m.m5, m.m9, m.m13, m.m2, m.m6, m.m10, m.m14, m.m3, m.m7, m.m11, m.m15 };
    for (int i = 0; i < 16; i++) printf(" %u", w(c[i]));
}
static void pair(const float *v) { printf(" %u %u", w(v[0]), w(v[1])); }
static void row(const unsigned *d)
{
    VrDeviceInfo device = { (int)d[0], (int)d[1], f(d[2]), f(d[3]), f(d[4]), f(d[5]), f(d[6]), { f(d[7]), f(d[8]), f(d[9]), f(d[10]) }, { f(d[11]), f(d[12]), f(d[13]), f(d[14]) } };
    VrStereoConfig config = LoadVrStereoConfig(device);
    printf("c");
    matrix(config.projection[0]); matrix(config.projection[1]); matrix(config.viewOffset[0]); matrix(config.viewOffset[1]);
    pair(config.leftLensCenter); pair(config.rightLensCenter); pair(config.leftScreenCenter); pair(config.rightScreenCenter); pair(config.scale); pair(config.scaleIn);
    printf("\n");
    UnloadVrStereoConfig(config);
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def b(word: U32) -> F32:
  J.Wave.float_bits(word)

def cell(value: F32) -> String:
  " " ++ U32.show(F32.bits(value))

def matrix(m: M.Matrix) -> String:
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = m
  cell(m0) ++ cell(m4) ++ cell(m8) ++ cell(m12) ++ cell(m1) ++ cell(m5) ++ cell(m9) ++ cell(m13) ++ cell(m2) ++ cell(m6) ++ cell(m10) ++ cell(m14) ++ cell(m3) ++ cell(m7) ++ cell(m11) ++ cell(m15)

def pair(v: M.Vector2) -> String:
  M.Vector2{x, y} = v
  cell(x) ++ cell(y)

def row(config: Maybe<&2, J.VrStereoConfig>) -> String:
  match config:
    case None{}: "null"
    case Some{J.VrStereoConfig{pl, pr, vl, vr, ll, rl, ls, rs, scale, scale_in}}:
      "c" ++ matrix(pl) ++ matrix(pr) ++ matrix(vl) ++ matrix(vr) ++ pair(ll) ++ pair(rl) ++ pair(ls) ++ pair(rs) ++ pair(scale) ++ pair(scale_in)

def device(+d: +List<U32>) -> J.VrDeviceInfo:
  J.VrDeviceInfo{at(d, 0), at(d, 1), b(at(d, 2)), b(at(d, 3)), b(at(d, 4)), b(at(d, 5)), b(at(d, 6)), M.Vector4{b(at(d, 7)), b(at(d, 8)), b(at(d, 9)), b(at(d, 10))},
    M.Vector4{b(at(d, 11)), b(at(d, 12)), b(at(d, 13)), b(at(d, 14))}}
'''

AT = '''def at(xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, rest}: Bool.pick(U32, U32.is_eq(i, 0), x, at(rest, (i - 1 : U32)))

'''


def render_for(libm):
    def render(selected, gpu):
        head, rest = PROGRAM.split('def device(', 1)
        lines = [head + AT + 'def device(' + rest, 'def main() -> IO(Unit):\n  do IO<Unit>:']
        lines += [f'    IO.print(row(J.Vr.load_stereo_config_for(M.{libm}{{}}, device([{", ".join(map(str, fields(case["device"])))}]))))' for _, case in selected]
        return '\n'.join(lines) + '\n'
    return render


def main():
    def configure(parser):
        parser.add_argument('--apple-contract', action='store_true', help='every device under M.AppleLibm must be null (no reference comparison)')
    args = probekit.arguments(__doc__, configure)
    probe = probekit.Probe('vr-apple' if args.apple_contract else 'vr', args, raylib_options=fp.OPTIONS)
    items = cases()
    native = [c for c in items if not c['contract']]
    contracts = [c for c in items if c['contract']]
    if len(native) < 35 or len(contracts) < 8:
        raise ProbeFailure(f'vr: {len(native)} compared and {len(contracts)} refused devices; the corpus lost coverage')
    parse = lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()]
    if args.apple_contract:
        lanes = probe.candidates(render_for('AppleLibm'), list(enumerate(items)), batch=64, parse=parse)
        probe.compare(['null'] * len(items), lanes, describe=lambda index: items[index]['id'])
        probe.finish(cases=len(items), compared=0, contracts=len(items))
        return
    source = C_PREFIX + '\n'.join('    { const unsigned d[15] = { %s }; row(d); }' % ', '.join(f'{w}u' for w in fields(c['device'])) for c in native) + '\n    return 0;\n}\n'
    output = [line.rstrip() for line in probe.native(source, 'reference').splitlines() if line[:1] == 'c']
    if len(output) != len(native):
        raise ProbeFailure(f'vr: reference printed {len(output)} lines for {len(native)} devices')
    expected_by_id = {c['id']: line for c, line in zip(native, output)}
    example = expected_by_id['example'].split()
    if len(example) != 77 or example[69:73] != [str(bits(v)) for v in (0.25, 0.5, 0.75, 0.5)] or example[75] != str(bits(4.0)):
        raise ProbeFailure('vr: the reference did not compute the example device as expected')
    # Two pairs are equal by construction: the chroma values are not read, and a negative width or height gives the same aspect.
    if len(set(output)) != len(native) - 2 or expected_by_id['example'] != expected_by_id['chroma-ignored'] or expected_by_id['negative-width'] != expected_by_id['negative-height']:
        raise ProbeFailure('vr: the devices did not give the configurations expected to differ')
    for c in contracts:
        expected_by_id[c['id']] = 'null'
    libm = gradient_reference()
    lanes = probe.candidates(render_for(libm), list(enumerate(items)), batch=64, parse=parse)
    # On a host whose libm Jonlib does not reproduce for the perspective (M.AppleLibm) every device is a refusal.
    probe.compare(['null' if libm == 'AppleLibm' else expected_by_id[c['id']] for c in items], lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts), refused=[c['id'] for c in contracts], libm=libm)


if __name__ == '__main__':
    main()
