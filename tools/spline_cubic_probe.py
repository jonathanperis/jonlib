#!/usr/bin/env python3
"""Compare the Glibc239Libm powf kernel and GetSplinePointBezierCubic.

The reference compiles the unchanged GetSplinePointBezierCubic from the pinned
rshapes.c with powf replaced by a C model of glibc 2.39's x86_64 powf (Arm
optimized-routines, TOINT_INTRINSICS 0; MIT, LICENSES/arm-math.txt):
uncontracted on every host, and also contracted (FP_CONTRACT ON) on arm64
hosts for M.Fused. On a Linux x86_64 glibc 2.39 host (the CI runner) the
linked raylib with the host powf must print exactly the uncontracted rows;
elsewhere that check is reported as skipped. (Exhaustively, x86_64 glibc 2.39
powf(x, 2) and powf(x, 3) equal the model on every x in [0, 1].)

Inputs: powf(x, 2) and powf(x, 3) on random x in [0, 1], signed zeros, 1,
subnormals, the underflow edges near 2^-50 and 2^-75, x where powf differs from
x*x or the rounded double cube (found by the native model), and values outside
the profile; cubic points on random control points with t in [0, 1], the
retained counterexample t = 0x1.940af8p-2, t = +-0 and 1, tiny t and 1 - tiny,
and t outside [-0, 1]. Jonlib contracts: powf outside x in [-0, 1] or an
exponent other than 2 and 3, and cubic points with such t, are None;
AppleLibm and Glibc241Libm give None. CPU/JS.
"""
import hashlib
import os
import platform
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/spline-cubic-probe/cases'

MODEL = r'''/* Model of Arm optimized-routines powf (Copyright (c) 2017-2026 Arm Limited;
   MIT alternative, LICENSES/arm-math.txt) for x in [-0, 1] and y in {2, 3}, as
   glibc 2.39 builds it on x86_64 (TOINT_INTRINSICS 0, POWF_SCALE 1). */
#include <stdint.h>
#include <string.h>
static const struct { double invc, logc; } LT[16] = {
  { 0x1.661ec79f8f3bep+0, -0x1.efec65b963019p-2 }, { 0x1.571ed4aaf883dp+0, -0x1.b0b6832d4fca4p-2 },
  { 0x1.49539f0f010bp+0, -0x1.7418b0a1fb77bp-2 }, { 0x1.3c995b0b80385p+0, -0x1.39de91a6dcf7bp-2 },
  { 0x1.30d190c8864a5p+0, -0x1.01d9bf3f2b631p-2 }, { 0x1.25e227b0b8eap+0, -0x1.97c1d1b3b7afp-3 },
  { 0x1.1bb4a4a1a343fp+0, -0x1.2f9e393af3c9fp-3 }, { 0x1.12358f08ae5bap+0, -0x1.960cbbf788d5cp-4 },
  { 0x1.0953f419900a7p+0, -0x1.a6f9db6475fcep-5 }, { 0x1p+0, 0x0p+0 },
  { 0x1.e608cfd9a47acp-1, 0x1.338ca9f24f53dp-4 }, { 0x1.ca4b31f026aap-1, 0x1.476a9543891bap-3 },
  { 0x1.b2036576afce6p-1, 0x1.e840b4ac4e4d2p-3 }, { 0x1.9c2d163a1aa2dp-1, 0x1.40645f0c6651cp-2 },
  { 0x1.886e6037841edp-1, 0x1.88e9c2c1b9ff8p-2 }, { 0x1.767dcf5534862p-1, 0x1.ce0a44eb17bccp-2 } };
static const double A[5] = { 0x1.27616c9496e0bp-2, -0x1.71969a075c67ap-2, 0x1.ec70a6ca7baddp-2, -0x1.7154748bef6c8p-1, 0x1.71547652ab82bp0 };
static const uint64_t T[32] = {
0x3ff0000000000000, 0x3fefd9b0d3158574, 0x3fefb5586cf9890f, 0x3fef9301d0125b51, 0x3fef72b83c7d517b, 0x3fef54873168b9aa, 0x3fef387a6e756238, 0x3fef1e9df51fdee1,
0x3fef06fe0a31b715, 0x3feef1a7373aa9cb, 0x3feedea64c123422, 0x3feece086061892d, 0x3feebfdad5362a27, 0x3feeb42b569d4f82, 0x3feeab07dd485429, 0x3feea47eb03a5585,
0x3feea09e667f3bcd, 0x3fee9f75e8ec5f74, 0x3feea11473eb0187, 0x3feea589994cce13, 0x3feeace5422aa0db, 0x3feeb737b0cdc5e5, 0x3feec49182a3f090, 0x3feed503b23e255d,
0x3feee89f995ad3ad, 0x3feeff76f2fb5e47, 0x3fef199bdd85529c, 0x3fef3720dcef9069, 0x3fef5818dcfba487, 0x3fef7c97337b9b5f, 0x3fefa4afa2a490da, 0x3fefd0765b6e4540 };
static const double C[3] = { 0x1.c6af84b912394p-5, 0x1.ebfce50fac4f3p-3, 0x1.62e42ff0c52d6p-1 };
static double asd(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }
static uint64_t asu64(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }
float model_powf(float x, float y) {
  uint32_t ix; memcpy(&ix, &x, 4);
  if (ix == 0) return 0.0f;
  if (ix == 0x80000000) return y == 3.0f ? -0.0f : 0.0f;
  if (ix < 0x00800000) { float s = x * 0x1p23f; memcpy(&ix, &s, 4); ix &= 0x7fffffff; ix -= 23 << 23; }
  uint32_t tmp = ix - 0x3f330000; int i = (tmp >> 19) % 16; uint32_t top = tmp & 0xff800000; uint32_t iz = ix - top;
  int k = (int32_t)top >> 23; float zf; memcpy(&zf, &iz, 4); double z = zf;
  double r = z * LT[i].invc - 1, y0 = LT[i].logc + (double)k;
  double r2 = r * r, yy = A[0] * r + A[1], p = A[2] * r + A[3], r4 = r2 * r2, q = A[4] * r + y0;
  q = p * r2 + q; yy = yy * r4 + q;
  double xd = (double)y * yy;
  if ((asu64(xd) >> 47 & 0xffff) >= asu64(126.0) >> 47) { if (xd <= -150.0) return 0.0f; }
  double kd = xd + 0x1.8p+52 / 32; uint64_t ki = asu64(kd); kd -= 0x1.8p+52 / 32;
  double rr = xd - kd; uint64_t t = T[ki % 32]; t += ki << (52 - 5); double s = asd(t);
  double zz = C[0] * rr + C[1], rr2 = rr * rr, w = C[2] * rr + 1; w = zz * rr2 + w; w = w * s;
  return (float)w;
}
'''

DRIVER_HEAD = r'''#include "raylib.h"
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
float model_powf(float, float);
static unsigned bits(float x) { unsigned b; memcpy(&b, &x, 4); return b; }
static float value(unsigned b) { float x; memcpy(&x, &b, 4); return x; }
static int in_domain(unsigned b) { return b <= 0x3f800000u || b == 0x80000000u; }
static int load(const char *path, unsigned *out, int max) {
  FILE *f = fopen(path, "rb"); int n = 0; unsigned char c[4];
  while (n < max && fread(c, 1, 4, f) == 4) out[n++] = c[0] | c[1] << 8 | c[2] << 16 | (unsigned)c[3] << 24;
  fclose(f); return n;
}
'''

DRIVER_MAIN = r'''
static unsigned in[200000];
static float (*volatile host_powf)(float, float) = POWER;
int main(int argc, char **argv) {
  if (argc == 4 && !strcmp(argv[1], "find")) {
    unsigned start = strtoul(argv[2], 0, 10), count = strtoul(argv[3], 0, 10);
    for (unsigned b = start; b < start + count && b <= 0x3f800000u; b++) {
      float x = value(b);
      if (model_powf(x, 2.0f) != x * x || model_powf(x, 3.0f) != (float)((double)x * x * x)) printf("%u\n", b);
    }
    return 0;
  }
  for (int a = 1; a + 1 < argc; a += 2) {
    int n = load(argv[a + 1], in, 200000);
    if (!strcmp(argv[a], "kernel")) {
      for (int i = 0; i + 2 <= n; i += 2) {
        if (in_domain(in[i]) && (in[i + 1] == 2 || in[i + 1] == 3)) printf("%u ", bits(host_powf(value(in[i]), (float)in[i + 1])));
        else printf("none ");
      }
    } else {
      for (int i = 0; i + 9 <= n; i += 9) {
        Vector2 p[4];
        for (int j = 0; j < 4; j++) p[j] = (Vector2){ value(in[i + 2 * j]), value(in[i + 2 * j + 1]) };
        if (!in_domain(in[i + 8])) { printf("none "); continue; }
        Vector2 r = GetSplinePointBezierCubic(p[0], p[1], p[2], p[3], value(in[i + 8]));
        printf("%u,%u ", bits(r.x), bits(r.y));
      }
    }
    printf("\n");
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def float(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def words(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), words(rest)}
    case _: Nil{}
def scalar(m: Maybe<F32>) -> String:
  match m:
    case None{}: "none"
    case Some{v}: U32.show(F32.bits(v))
def kernel(values: +List<U32>) -> String:
  match values:
    case Con{x, Con{e, rest}}: scalar(M.Libm.pow(M.Glibc239Libm{}, float(x), e)) ++ " " ++ kernel(rest)
    case _: ""
def point(m: Maybe<M.Vector2>) -> String:
  match m:
    case None{}: "none"
    case Some{M.Vector2{x, y}}: U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y))
def vector(+x: U32, +y: U32) -> M.Vector2:
  M.Vector2{float(x), float(y)}
def cubics(+contraction: M.Contraction, +libm: M.Libm, values: +List<U32>) -> String:
  match values:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, Con{t, rest}}}}}}}}}:
      point(J.Spline.bezier_cubic_for(contraction, libm, vector(a, b), vector(c, d), vector(e, f), vector(g, h), float(t))) ++ " " ++ cubics(contraction, libm, rest)
    case _: ""
def text(kind: U32, values: +List<U32>) -> String:
  match kind:
    case 0: kernel(values)
    case 1: cubics(M.Uncontracted{}, M.Glibc239Libm{}, values)
    case 2: cubics(M.Fused{}, M.Glibc239Libm{}, values)
    case 3: cubics(M.Uncontracted{}, M.AppleLibm{}, values)
    case _: cubics(M.Uncontracted{}, M.Glibc241Libm{}, values)
def section(kind: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{bytes}: IO.print(text(kind, words(bytes)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def kernel_inputs(rng, found):
    xs = [0, 0x80000000, 0x3F800000, 1, 0x007FFFFF, 0x00800000, 0x3F7FFFFF, 0x3F000000, 0x3E99999A]
    for center in (0x26800000, 0x1A000000):
        xs += [center + d for d in range(-40, 41, 4)]
    xs += [rng.randrange(0x3F800001) for _ in range(2500)]
    xs += [word(rng.random()) for _ in range(1000)]
    xs += found
    rows = [[x, e] for x in xs for e in (2, 3)]
    rows += [[0x3F800001, 2], [0xBF000000, 3], [0x7FC00000, 2], [0x7F800000, 3], [0x3F000000, 4], [0x3F000000, 1], [0xFF800000, 2]]
    return rows


def cubic_inputs(rng):
    rows = []
    coords = lambda: [word(rng.uniform(-100, 100)) for _ in range(8)]
    for _ in range(500):
        rows.append(coords() + [word(rng.random())])
    unit = [word(v) for v in (0, 0, 0, 0, 0, 0, 1, 0)]
    for t in ('0x1.940af8p-2', '0x0p+0', '-0x0p+0', '0x1p+0', '0x1p-30', '0x1p-60', '0x1p-149', '0x1.fffffep-1', '0x1.fffffcp-1', '0x1p-1'):
        rows.append(unit + [word(float.fromhex(t))])
        rows.append(coords() + [word(float.fromhex(t))])
    for t in (1.5, -0.25, 2.0, float('nan'), float('inf'), -1e-30):
        rows.append(coords() + [word(t)])
    return rows


def chunks(rows, size):
    return [rows[i:i + size] for i in range(0, len(rows), size)]


def host_glibc239_x86():
    try:
        version = os.confstr('CS_GNU_LIBC_VERSION')
    except (ValueError, OSError, AttributeError):
        return False
    return platform.system() == 'Linux' and platform.machine() in ('x86_64', 'AMD64') and version == 'glibc 2.39'


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('spline-cubic', args)
    work = ROOT / WORK
    work.mkdir(parents=True, exist_ok=True)
    source = (args.raylib_source / 'src/rshapes.c').read_text()
    begin = source.index('Vector2 GetSplinePointBezierCubic(')
    end = source.index('\n}\n', begin) + 3
    function = source[begin:end]
    model = probe.work / 'model.c'
    model.write_text(MODEL)
    model_object = probe.work / 'model.o'
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-c', model, '-o', model_object])

    def control(name, pragma, flag):
        text = (DRIVER_HEAD + '/* Unaltered GetSplinePointBezierCubic from pinned raylib; zlib, LICENSES/raylib.txt. */\n'
                + f'#pragma STDC FP_CONTRACT {pragma}\n#define powf model_powf\n' + function + '#undef powf\n'
                + DRIVER_MAIN.replace('POWER', 'model_powf'))
        probe.native(text, name, extra_flags=[flag, model_object], link_raylib=False)
        return probe.work / name

    uncontracted = control('control-off', 'OFF', '-ffp-contract=off')
    fused = control('control-on', 'ON', '-ffp-contract=on') if platform.machine() in ('arm64', 'aarch64') else None

    rng = random.Random(0xB3C1)
    start = rng.randrange(0x3E000000, 0x3F000000 - 4_000_000)
    found = [int(line) for line in probekit.run([uncontracted, 'find', start, 4_000_000]).split()][:400]
    if len(found) < 100:
        raise ProbeFailure('spline-cubic: too few powf/product differences found')
    actions = []
    for section, parts in (('kernel', chunks(kernel_inputs(rng, found), 2500)), ('cubic', chunks(cubic_inputs(rng), 200))):
        for index, part in enumerate(parts):
            path = f'{WORK}/{section}-{index}.bin'
            (ROOT / path).write_bytes(b''.join(struct.pack('<I', w) for row in part for w in row))
            actions.append((section, path))
    argv = [part for section, path in actions for part in (section, path)]
    rows = probekit.run([uncontracted, *argv]).splitlines()
    fused_rows = probekit.run([fused, *argv]).splitlines() if fused else None
    native_checked = host_glibc239_x86()
    if native_checked:
        probe.native(DRIVER_HEAD + DRIVER_MAIN.replace('POWER', 'powf'), 'linked', extra_flags=['-ffp-contract=off', model_object])
        if probekit.run([probe.work / 'linked', *argv]).splitlines() != rows:
            raise ProbeFailure('spline-cubic: linked raylib with host glibc 2.39 powf differs from the pinned profile')
    if len(rows) != len(actions):
        raise ProbeFailure('spline-cubic: incomplete reference output')
    kinds = {'kernel': (0,), 'cubic': (1, 2, 3, 4) if fused else (1, 3, 4)}

    def render(selected, gpu):
        body = PROGRAM
        for section, path in selected:
            for kind in kinds[section]:
                body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{path}"), section({kind}))\n'
        return body + '    IO.print("done")\n'

    def parse(text, selected):
        lines = text.splitlines()
        if lines[-1:] != ['done']:
            raise ValueError('spline-cubic: candidate output did not finish')
        out, index = [], 0
        for section, _path in selected:
            out.append([lines[index + k].split() for k in range(len(kinds[section]))])
            index += len(kinds[section])
        return out

    expected = []
    for i, ((section, _path), line) in enumerate(zip(actions, rows)):
        items = line.split()
        if section == 'kernel':
            expected.append([items])
        else:
            nones = ['none'] * len(items)
            expected.append([items] + ([fused_rows[i].split()] if fused else []) + [nones, nones])
    lanes = probe.candidates(render, actions, batch=2, parse=parse)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{actions[i][0]} chunk {actions[i][1]}')
    probe.finish(kernel_inputs=sum(len(r[0]) for (s, _), r in zip(actions, expected) if s == 'kernel'),
                 product_differences=len(found), cubic_points=sum(len(r[0]) for (s, _), r in zip(actions, expected) if s == 'cubic'),
                 fused_control=bool(fused), host_libm_checked=native_checked,
                 inputs_sha256=hashlib.sha256(b''.join((ROOT / p).read_bytes() for _s, p in actions)).hexdigest())


if __name__ == '__main__':
    main()
