#!/usr/bin/env python3
"""Compare the Glibc239Libm acosf kernel, QuaternionSlerp and QuaternionToAxisAngle.

The reference is the pinned raymath.h compiled with contraction off, with
acosf from the unmodified glibc 2.39 e_acosf.c (tools/reference/acos_sources,
Sun notice) and sinf from the glibc sinf model of tools/trig_probe.py. On a
Linux x86_64 glibc 2.39 host (the CI runner) the same program is also built
against the host libm and must print exactly the same rows; elsewhere that
check is reported as skipped. (Exhaustively, glibc 2.39's x86_64 acosf equals
the pinned source compiled uncontracted on every input in [-1, 1]; its aarch64
build contracts into FMA and is a different profile.)

Inputs: acosf on region boundaries, signed zeros, +-1, subnormals, values
past 1, infinities and NaN, and random words and values in [-1, 1]; slerp on
random, nearby, opposite, non-unit, zero and nonfinite quaternion pairs with
amounts inside and outside [0, 1]; to-axis-angle on unit, non-unit (|w| > 1
normalized), w = +-1, near-identity, zero, huge and nonfinite quaternions.
Jonlib contracts: inputs acosf refuses (|x| > 1, NaN) and infinite or NaN
slerp sinf arguments are None; AppleLibm and Glibc241Libm are None exactly
where the result needs acosf. CPU/JS.
"""
import hashlib
import os
import platform
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure
from trig_probe import REFERENCE as TRIG_REFERENCE

WORK = '.build/quaternion-angle-probe/cases'
SOURCE = ROOT / 'tools/reference/acos_sources/sun_e_acosf.c'
SOURCE_SHA256 = '60a8c9b2d14409971adc930bfa386014230e3c7e21a8cd1fdc8178128800d8ba'
SECTIONS = {'kernel': 1, 'slerp': 9, 'axis': 4}


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def unit(rng, scale=1.0):
    values = [rng.gauss(0, 1) for _ in range(4)]
    length = sum(v * v for v in values) ** 0.5
    return [scale * v / length for v in values]


def kernel_inputs(rng):
    words = [0, 0x80000000, 0x3F800000, 0xBF800000, 0x3F800001, 0xBF800001, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
             1, 0x80000001, 0x007FFFFF, 0x807FFFFF, 0x00800000, 0x40000000, 0xC0000000]
    for edge in (0x32800000, 0x3F000000, 0x3F7FFFFF):
        for delta in range(-3, 4):
            words += [(edge + delta) & 0x7FFFFFFF, ((edge + delta) & 0x7FFFFFFF) | 0x80000000]
    words += [(rng.randrange(2) << 31) | rng.randrange(0x3F800001) for _ in range(16000)]
    words += [word(rng.uniform(-1, 1)) for _ in range(6000)]
    words += [(rng.randrange(2) << 31) | rng.randrange(0x3F700000, 0x3F800001) for _ in range(2000)]
    return [[w] for w in words]


def slerp_inputs(rng):
    cases = []
    add = lambda q1, q2, t: cases.append([word(v) for v in (*q1, *q2, t)])
    for _ in range(700):
        add(unit(rng), unit(rng), rng.uniform(0, 1))
    for _ in range(150):
        q = unit(rng)
        add(q, [v + rng.uniform(-0.15, 0.15) for v in q], rng.uniform(0, 1))
    for _ in range(100):
        q = unit(rng)
        add(q, [-v + rng.uniform(-0.1, 0.1) for v in q], rng.uniform(0, 1))
    for _ in range(150):
        add(unit(rng, rng.uniform(0.2, 3)), unit(rng, rng.uniform(0.2, 3)), rng.uniform(0, 1))
    for _ in range(150):
        add(unit(rng), unit(rng), rng.uniform(-6, 6))
    for t in (0.0, -0.0, 1.0, 0.5, 1e-7, 1e-40, -1e-30, 2.0, -3.0, 5.0, float('inf'), float('-inf'), float('nan')):
        add(unit(rng), unit(rng), t)
    identity, zero = [0, 0, 0, 1], [0, 0, 0, 0]
    for q1, q2 in ((identity, identity), (identity, [0, 0, 0, -1]), (identity, [1, 0, 0, 0]), (zero, zero), (zero, identity),
                   ([0.5, 0.5, 0.5, 0.5], [0.5, -0.5, 0.5, -0.5]), ([1, 0, 0, 0], [0, 1, 0, 0]), (identity, [0, 0, 0.3, 0.95393920]),
                   ([float('nan'), 0, 0, 1], identity), ([float('inf'), 0, 0, 1], identity), ([1e30, 0, 0, 0], [1e30, 0, 0, 0])):
        for t in (0.25, 0.75):
            add(q1, q2, t)
    return cases


def axis_inputs(rng):
    cases = [[word(v) for v in unit(rng)] for _ in range(500)]
    cases += [[word(v) for v in unit(rng, rng.uniform(0.1, 3))] for _ in range(300)]
    for _ in range(100):
        angle = rng.uniform(-1e-3, 1e-3)
        cases.append([word(v) for v in (angle, 0.0, 0.0, 1.0 - angle * angle / 2)])
    for q in ([0, 0, 0, 1], [0, 0, 0, -1], [0, 0, 0, 0], [-0.0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 1.0000001], [0, 0, 0, -1.0000001],
              [0, 0, 0, 2], [0.1, 0.2, 0.3, 4], [1e30, 1e30, 0, 2], [1e-30, 0, 0, 1], [0, 0, 0, 1e-40], [float('nan'), 0, 0, 0.5],
              [0, 0, 0, float('nan')], [0, 0, 0, float('inf')], [float('inf'), 0, 0, 0.5], [3e38, 3e38, 3e38, 3e38]):
        cases.append([word(v) for v in q])
    return cases


def chunks(rows, size):
    return [rows[i:i + size] for i in range(0, len(rows), size)]


ARM_MODEL = TRIG_REFERENCE[TRIG_REFERENCE.index('/* Arm'):TRIG_REFERENCE.index('int main')].replace('\\\\', '\\')

DRIVER = r'''#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
#ifdef PINNED
float sun239_acosf(float);
ARM_MODEL
static float model_sinf(float x) { float c, s; arm_model(x, &c, &s); return s; }
#define acosf sun239_acosf
#define sinf model_sinf
#endif
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
static float (*volatile kernel_acosf)(float) = acosf;
static unsigned bits(float x) { unsigned b; memcpy(&b, &x, 4); return b; }
static float value(unsigned b) { float x; memcpy(&x, &b, 4); return x; }
static int load(const char *path, unsigned *out, int max) {
  FILE *f = fopen(path, "rb"); int n = 0; unsigned char b[4];
  while (n < max && fread(b, 1, 4, f) == 4) out[n++] = b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
  fclose(f); return n;
}
static unsigned in[400000];
static void kernel(const char *path) {
  int n = load(path, in, 400000);
  for (int i = 0; i < n; i++) { float x = value(in[i]); if (fabsf(x) <= 1.0f) printf("%u ", bits(kernel_acosf(x))); else printf("none "); }
  printf("\n");
}
static void slerp(const char *path) {
  int n = load(path, in, 400000);
  for (int i = 0; i + 9 <= n; i += 9) {
    Quaternion q1 = {value(in[i]), value(in[i+1]), value(in[i+2]), value(in[i+3])};
    Quaternion q2 = {value(in[i+4]), value(in[i+5]), value(in[i+6]), value(in[i+7])};
    float t = value(in[i+8]);
    float c = q1.x*q2.x + q1.y*q2.y + q1.z*q2.z + q1.w*q2.w;
    if (c < 0) c = -c;
    int branch = fabsf(c) >= 1.0f ? 0 : c > 0.95f ? 1 : 2;
    if (branch == 2) {
      if (!(fabsf(c) <= 1.0f)) branch = 3;
      else {
        float half = acosf(c), s = sqrtf(1.0f - c*c);
        if (!(fabsf(s) < 0.000001f) && !(isfinite((1 - t)*half) && isfinite(t*half))) branch = 3;
      }
    }
    Quaternion r = QuaternionSlerp(q1, q2, t);
    if (branch == 3) printf("3:none "); else printf("%d:%u,%u,%u,%u ", branch, bits(r.x), bits(r.y), bits(r.z), bits(r.w));
  }
  printf("\n");
}
static void axis(const char *path) {
  int n = load(path, in, 400000);
  for (int i = 0; i + 4 <= n; i += 4) {
    Quaternion q = {value(in[i]), value(in[i+1]), value(in[i+2]), value(in[i+3])};
    float w = q.w;
    if (fabsf(q.w) > 1.0f) {
      float length = sqrtf(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
      if (length == 0.0f) length = 1.0f;
      w = q.w*(1.0f/length);
    }
    Vector3 a; float angle;
    QuaternionToAxisAngle(q, &a, &angle);
    if (!(fabsf(w) <= 1.0f)) printf("none "); else printf("%u,%u,%u,%u ", bits(a.x), bits(a.y), bits(a.z), bits(angle));
  }
  printf("\n");
}
int main(int argc, char **argv) {
  for (int i = 1; i + 1 < argc; i += 2) {
    if (!strcmp(argv[i], "kernel")) kernel(argv[i+1]);
    else if (!strcmp(argv[i], "slerp")) slerp(argv[i+1]);
    else axis(argv[i+1]);
  }
  return 0;
}
'''.replace('ARM_MODEL', ARM_MODEL)

SHIMS = {'libm-alias-finite.h': '#define libm_alias_finite(a,b)\n',
         'math_private.h': '#include <stdint.h>\n#include <string.h>\n'
                           '#define GET_FLOAT_WORD(i,d) do { float f_=(d); uint32_t u_; memcpy(&u_,&f_,4); (i)=u_; } while (0)\n'
                           '#define SET_FLOAT_WORD(d,i) do { uint32_t u_=(i); float f_; memcpy(&f_,&u_,4); (d)=f_; } while (0)\n'}

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
def bits(+x: F32) -> String:
  U32.show(F32.bits(x))
def scalar(m: Maybe<F32>) -> String:
  match m:
    case None{}: "none"
    case Some{v}: bits(v)
def kernel(values: +List<U32>) -> String:
  match values:
    case Con{w, rest}: scalar(M.Libm.acos(M.Glibc239Libm{}, float(w))) ++ " " ++ kernel(rest)
    case Nil{}: ""
def quaternion(m: Maybe<M.Vector4>) -> String:
  match m:
    case None{}: "none"
    case Some{M.Vector4{x, y, z, w}}: bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z) ++ "," ++ bits(w)
def slerps(+libm: M.Libm, values: +List<U32>) -> String:
  match values:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, Con{t, rest}}}}}}}}}:
      quaternion(M.Quaternion.slerp_for(libm, M.Vector4{float(a), float(b), float(c), float(d)}, M.Vector4{float(e), float(f), float(g), float(h)}, float(t))) ++ " " ++ slerps(libm, rest)
    case _: ""
def axis_angle(m: Maybe<(M.Vector3 & F32)>) -> String:
  match m:
    case None{}: "none"
    case Some{(M.Vector3{x, y, z}, angle)}: bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z) ++ "," ++ bits(angle)
def axes(+libm: M.Libm, values: +List<U32>) -> String:
  match values:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: axis_angle(M.Quaternion.to_axis_angle_for(libm, M.Vector4{float(a), float(b), float(c), float(d)})) ++ " " ++ axes(libm, rest)
    case _: ""
def text(kind: U32, values: +List<U32>) -> String:
  match kind:
    case 0: kernel(values)
    case 1: slerps(M.Glibc239Libm{}, values)
    case 2: slerps(M.AppleLibm{}, values)
    case 3: slerps(M.Glibc241Libm{}, values)
    case 4: axes(M.Glibc239Libm{}, values)
    case 5: axes(M.AppleLibm{}, values)
    case _: axes(M.Glibc241Libm{}, values)
def section(kind: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{bytes}: IO.print(text(kind, words(bytes)))
def main() -> IO(Unit):
  do IO<Unit>:
'''

KINDS = {'kernel': (0,), 'slerp': (1, 2, 3), 'axis': (4, 5, 6)}


def render(selected, gpu):
    body = PROGRAM
    for section, path in selected:
        for kind in KINDS[section]:
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{path}"), section({kind}))\n'
    return body + '    IO.print("done")\n'


def parse(text, selected):
    lines = text.splitlines()
    if lines[-1:] != ['done']:
        raise ValueError('quaternion-angle: candidate output did not finish')
    rows, index = [], 0
    for section, _path in selected:
        rows.append([lines[index + k].split() for k in range(len(KINDS[section]))])
        index += len(KINDS[section])
    return rows


def expected_rows(section, line):
    items = line.split()
    if section == 'kernel':
        return [items]
    branches = [item.split(':', 1) for item in items]
    glibc = [value for _branch, value in branches]
    others = ['none' if branch in ('2', '3') else value for branch, value in branches]
    return [glibc, others, others]


def axis_expected(line):
    items = line.split()
    return [items, ['none'] * len(items), ['none'] * len(items)]


def host_glibc239_x86():
    try:
        version = os.confstr('CS_GNU_LIBC_VERSION')
    except (ValueError, OSError, AttributeError):
        return False
    return platform.system() == 'Linux' and platform.machine() in ('x86_64', 'AMD64') and version == 'glibc 2.39'


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('quaternion-angle', args)
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ProbeFailure('quaternion-angle: pinned e_acosf.c changed')
    work = ROOT / WORK
    (work / 'include').mkdir(parents=True, exist_ok=True)
    for name, text in SHIMS.items():
        (work / 'include' / name).write_text(text)
    rng = random.Random(0xAC05)
    sections = {'kernel': chunks(kernel_inputs(rng), 4000), 'slerp': chunks(slerp_inputs(rng), 400), 'axis': chunks(axis_inputs(rng), 300)}
    actions = []
    for section, parts in sections.items():
        for index, part in enumerate(parts):
            path = f'{WORK}/{section}-{index}.bin'
            (ROOT / path).write_bytes(b''.join(struct.pack('<I', w) for case in part for w in case))
            actions.append((section, path))
    kernel_object = probe.work / 'sun239_acosf.o'
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-I' + str(work / 'include'), '-D__ieee754_acosf=sun239_acosf',
                  '-c', SOURCE, '-o', kernel_object])
    argv = [part for section, path in actions for part in (section, path)]
    flags = ['-ffp-contract=off', '-fno-builtin']
    pinned = probe.native(DRIVER, 'pinned-build', extra_flags=[*flags, '-DPINNED', kernel_object], link_raylib=False)
    pinned = probekit.run([probe.work / 'pinned-build', *argv]).splitlines()
    native_checked = host_glibc239_x86()
    if native_checked:
        probe.native(DRIVER, 'native-build', extra_flags=flags, link_raylib=False)
        native = probekit.run([probe.work / 'native-build', *argv]).splitlines()
        if native != pinned:
            different = next(i for i, (a, b) in enumerate(zip(native, pinned)) if a != b)
            raise ProbeFailure(f'quaternion-angle: host glibc 2.39 differs from the pinned profile in {actions[different]}')
    if len(pinned) != len(actions):
        raise ProbeFailure('quaternion-angle: incomplete reference output')
    expected = []
    for (section, _path), line in zip(actions, pinned):
        expected.append(axis_expected(line) if section == 'axis' else expected_rows(section, line))
    lanes = probe.candidates(render, actions, batch=3, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{actions[i][0]} chunk {actions[i][1]}')
    flat = [item for row in expected for item in row[0]]
    probe.finish(kernel_inputs=sum(len(p) for p in sections['kernel']), slerp_cases=sum(len(p) for p in sections['slerp']),
                 axis_cases=sum(len(p) for p in sections['axis']), refused=flat.count('none'),
                 host_libm_checked=native_checked, source_sha256=SOURCE_SHA256)


if __name__ == '__main__':
    main()
