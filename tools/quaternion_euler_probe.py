#!/usr/bin/env python3
"""Compare M.Libm.asin and Quaternion.to_euler_for (raymath QuaternionToEuler).

The asinf references are the pinned glibc 2.41 e_asinf.c (CORE-MATH, MIT;
tools/reference/core_math), correctly rounded on [-1, 1] (tools/libm_survey.py
checks it exhaustively against CORE-MATH and the exact oracle), and the pinned
glibc 2.39 e_asinf.c (Sun/Moshier, LGPL-2.1+; tools/reference/glibc239), both
compiled with contraction off. Expected rows per profile:

- Glibc241Libm: the 2.41 source's result on [-1, 1], None for |x| > 1 and NaN;
- Glibc239Libm: the 2.39 source's result on [-1, 1] (the LGPL module
  src/lgpl/asin.bend), None for |x| > 1 and NaN;
- AppleLibm: the 2.41 result for |x| below 0x39e89768 (where macOS asinf
  equals correct rounding), None elsewhere.

QuaternionToEuler is the pinned raymath.h compiled with contraction off, with
asinf routed to the profile's source and atan2f to its kernel (the pinned glibc
2.41 and Sun 2.39 sources; native atan2f for AppleLibm, on Darwin only); a C
oracle repeats Jonmath's refusal contract (finite components, signed-zero or
normal intermediates and atan2f results, the profile's asinf domain).

On the host whose libm a profile names (Darwin arm64: AppleLibm; Linux x86_64
glibc 2.39: Glibc239Libm) the probe also requires the native asinf to equal the
profile's source on every binary32 of its domain (exhaustively: below the Apple
bound, or all of [-1, 1] for glibc 2.39), and native raymath (host asinf and
atan2f) to equal every accepted Euler row.
The private binary64 square root (src/binary64_sqrt.bend) the kernel uses is
compared with an exact integer-square-root oracle on zeros, exact squares,
every exponent parity, the asinf argument grid 1 - |x| and rejected inputs.
CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import math
import os
import platform
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure
from angle_kernel_probe import build_oracle
import cr_libm_oracle as oracle

WORK = '.build/quaternion-euler-probe/cases'
SOURCE = ROOT / 'tools/reference/core_math/glibc241_e_asinf.c'
SOURCE_SHA256 = '8b34f085bb2a64a15c75212ec4a0cc3a2eddc7d35583bf2c5921257158339061'
BOUNDS = {'AppleLibm': 0x39E89768, 'Glibc239Libm': 0x7FFFFFFF, 'Glibc241Libm': 0x7FFFFFFF}
# Exhaustive host checks stop at |x| = 1: beyond it the sources return a NaN whose bits depend on the host.
HOST_BOUNDS = {'AppleLibm': 0x39E89768, 'Glibc239Libm': 0x3F800001}
GLIBC239 = ROOT / 'tools/reference/glibc239/e_asinf.c'
GLIBC239_SHA256 = 'bb3e68b0ae3736d4c4f41c9e8d11416d8423ab8577696a33dade0b5afd402ffd'
GLIBC_SHIMS = ROOT / 'tools/reference/glibc_tan'
# The asinf source each profile's rows and Euler oracle use.
ASINF = {'Glibc241Libm': 'glibc241_asinf', 'Glibc239Libm': 'glibc239_asinf', 'AppleLibm': 'glibc241_asinf'}
PROFILES = ('Glibc241Libm', 'Glibc239Libm', 'AppleLibm')
ATAN2F = {'Glibc241Libm': 'glibc241_atan2f', 'Glibc239Libm': 'sun239_atan2f', 'AppleLibm': None}


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def unit(rng, scale=1.0):
    values = [rng.gauss(0, 1) for _ in range(4)]
    length = sum(v * v for v in values) ** 0.5
    return [scale * v / length for v in values]


def kernel_inputs(rng, slow):
    words = [0, 0x80000000, 0x3F800000, 0xBF800000, 0x3F800001, 0xBF800001, 0x7F800000, 0xFF800000, 0x7FC00000,
             0xFFC00000, 1, 0x80000001, 0x007FFFFF, 0x807FFFFF, 0x00800000, 0x40000000, 0xC0000000, 0x3F2AB445,
             0xBF2AB445, 0x3F083A1A, 0xBF083A1A]
    # 2.41 branch edges, the Apple bound, the former glibc 2.39 bound and the 2.39 source's branches (2^-27, 0.5, 0.975).
    for edge in (0x39800000, 0x3F000000, 0x3F614800, 0x3F7FFFFF, 0x39E89768, 0x39E8974F, 0x32000000, 0x3F79999A):
        for delta in range(-3, 4):
            words += [(edge + delta) & 0x7FFFFFFF, ((edge + delta) & 0x7FFFFFFF) | 0x80000000]
    words += slow
    words += [(rng.randrange(2) << 31) | rng.randrange(0x3F800001) for _ in range(1500)]
    words += [word(rng.uniform(-1, 1)) for _ in range(600)]
    words += [(rng.randrange(2) << 31) | rng.randrange(0x3F600000, 0x3F800001) for _ in range(300)]
    words += [(rng.randrange(2) << 31) | rng.randrange(0x39000000, 0x3A800000) for _ in range(300)]
    return words


def euler_inputs(rng):
    cases = []
    add = lambda q: cases.append([word(v) for v in q])
    for _ in range(240):
        add(unit(rng))
    for _ in range(60):
        add(unit(rng, rng.uniform(0.2, 3)))
    for _ in range(50):
        half = rng.uniform(-3.2, 3.2) / 2
        add([math.sin(half), 0.0, 0.0, math.cos(half)])
        add([0.0, 0.0, math.sin(half), math.cos(half)])
    for _ in range(80):
        half = rng.uniform(-2e-3, 2e-3) / 2
        a, b = rng.uniform(-3.2, 3.2) / 2, rng.uniform(-3.2, 3.2) / 2
        add([math.sin(a) * math.cos(half), math.sin(half), math.sin(b) * math.cos(half), math.cos(a) * math.cos(half)])
        add([0.0, math.sin(half), 0.0, math.cos(half)])
    for _ in range(40):
        q = unit(rng)
        add([q[0] * 1e-3, 0.70710678 + q[1] * 1e-3, q[2] * 1e-3, 0.70710678 + q[3] * 1e-3])
        add([0.5 + q[0] * 1e-4, 0.5 + q[1] * 1e-4, -0.5 + q[2] * 1e-4, 0.5 + q[3] * 1e-4])
    for q in ([0, 0, 0, 1], [0, 0, 0, -1], [0, 0, 0, 0], [-0.0, -0.0, -0.0, -0.0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
              [0.5, 0.5, 0.5, 0.5], [0.5, -0.5, 0.5, -0.5], [0, 0.70710677, 0, 0.70710677], [0, 0.70710683, 0, 0.70710683],
              [1e-30, 0, 0, 1], [1e-20, 1e-20, 1e-20, 1], [0, 1e-40, 0, 1], [1e-45, 0, 0, 1], [2e19, 0, 0, 1], [1e30, 1e30, 0, 0],
              [float('nan'), 0, 0, 1], [0, float('inf'), 0, 1], [0, 0, 0, float('-inf')], [3e38, 3e38, 3e38, 3e38],
              [0, 1e-4, 0, 1], [0, 2.2e-4, 0, 0.99999994], [0, -2.2e-4, 0, 0.99999994], [0, 2.3e-4, 0, 1]):
        add(q)
    return cases


def sqrt_inputs(rng):
    words = [0, 1 << 63, 0x3FF0000000000000, 0x4000000000000000, 0x4010000000000000, 0x4022000000000000,
             0x3FE0000000000000, 0x4008000000000000, 0x0010000000000000, 0x0010000000000001, 0x7FEFFFFFFFFFFFFF,
             0x3E70000000000000, 0x3E80000000000000, 0xBFF0000000000000, 0x8010000000000000, 0x0000000000000001,
             0x000FFFFFFFFFFFFF, 0x7FF0000000000000, 0x7FF8000000000000, 0xFFF0000000000000]
    for _ in range(300):
        words.append((rng.randrange(1, 2047) << 52) | rng.getrandbits(52))
    for _ in range(200):
        k = rng.randrange(1, 1 << 23)
        words.append(struct.unpack('<Q', struct.pack('<d', k * 2.0 ** -24))[0])
    for _ in range(60):
        r = rng.randrange(1 << 26, 1 << 27)
        words.append(struct.unpack('<Q', struct.pack('<d', float(r * r) * 2.0 ** rng.randrange(-200, 200, 2)))[0])
    return [[w >> 32, w & 0xFFFFFFFF] for w in words]


def sqrt_expected(high, low):
    """Correctly rounded sqrt words by exact integer square roots, or 'none'."""
    word = high << 32 | low
    stored, fraction = (word >> 52) & 2047, word & ((1 << 52) - 1)
    if word & ~(1 << 63) == 0:
        return f'{high}:{low}'
    if word >> 63 or stored in (0, 2047):
        return 'none'
    exponent = stored - 1075
    mantissa = fraction | 1 << 52
    shift = 120 + (exponent & 1)
    root = math.isqrt(mantissa << shift)
    sticky = root * root != mantissa << shift
    scale = (exponent - shift) // 2
    bits = root.bit_length() - 53
    keep, rest = root >> bits, root & ((1 << bits) - 1)
    half = 1 << (bits - 1)
    if rest > half or (rest == half and (sticky or keep & 1)):
        keep += 1
    if keep == 1 << 53:
        keep >>= 1
        bits += 1
    result_stored = scale + bits + 52 + 1023
    result = result_stored << 52 | (keep - (1 << 52))
    return f'{result >> 32}:{result & 0xFFFFFFFF}'


def chunks(rows, size):
    return [rows[i:i + size] for i in range(0, len(rows), size)]


SUPPORT = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
float glibc241_asinf(float);
static unsigned bits(float x) { unsigned b; memcpy(&b, &x, 4); return b; }
static float value(unsigned b) { float x; memcpy(&x, &b, 4); return x; }
static unsigned in[400000];
static int load(const char *path) {
  FILE *f = fopen(path, "rb"); int n = 0; unsigned char b[4];
  while (n < 400000 && fread(b, 1, 4, f) == 4) in[n++] = b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
  fclose(f); return n;
}
'''

# The Euler program: raymath with asinf -> glibc241_asinf and atan2f -> ATAN2F
# (native when empty); `bound` is the profile's asinf domain (magnitude words).
EULER = SUPPORT + r'''
#ifdef ROUTE_ASINF
#define asinf glibc241_asinf
#endif
#ifdef ATAN2F
float ATAN2F(float, float);
#define atan2f ATAN2F
#endif
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
static int finite(float x) { return (bits(x) & 0x7fffffffu) < 0x7f800000u; }
static int normal(float x) { unsigned m = bits(x) & 0x7fffffffu; return m == 0 || (m >= 0x00800000u && m < 0x7f800000u); }
static int accepted(Quaternion q, unsigned bound) {
  volatile float x = q.x, y = q.y, z = q.z, w = q.w, t[22];
  if (!finite(x) || !finite(y) || !finite(z) || !finite(w)) return 0;
  t[0] = w*x; t[1] = y*z; t[2] = t[0] + t[1]; t[3] = 2.0f*t[2];
  t[4] = x*x; t[5] = y*y; t[6] = t[4] + t[5]; t[7] = 2.0f*t[6]; t[8] = 1.0f - t[7];
  t[9] = w*y; t[10] = z*x; t[11] = t[9] - t[10]; t[12] = 2.0f*t[11];
  t[13] = w*z; t[14] = x*y; t[15] = t[13] + t[14]; t[16] = 2.0f*t[15];
  t[17] = y*y; t[18] = z*z; t[19] = t[17] + t[18]; t[20] = 2.0f*t[19]; t[21] = 1.0f - t[20];
  for (int i = 0; i < 22; i++) if (!normal(t[i])) return 0;
  if (!normal(atan2f(t[3], t[8])) || !normal(atan2f(t[16], t[21]))) return 0;
  float p = t[12] > 1.0f ? 1.0f : t[12];
  p = p < -1.0f ? -1.0f : p;
  return (bits(p) & 0x7fffffffu) < bound;
}
int main(int argc, char **argv) {
  if (argc < 2) return 0;  /* the build step runs the program once without arguments */
  unsigned bound = (unsigned)strtoul(argv[1], 0, 16);
  for (int a = 2; a < argc; a++) {
    int n = load(argv[a]);
    for (int i = 0; i + 4 <= n; i += 4) {
      Quaternion q = {value(in[i]), value(in[i+1]), value(in[i+2]), value(in[i+3])};
      Vector3 r = QuaternionToEuler(q);
      if (!accepted(q, bound)) printf("none ");
      else printf("%u,%u,%u ", bits(r.x), bits(r.y), bits(r.z));
    }
    printf("\n");
  }
  return 0;
}
'''

KERNEL = SUPPORT + r'''
static float (*volatile host_asinf)(float) = asinf;
/* The fast-path rounding test of glibc241_e_asinf.c (MIT, Copyright (c) 2023-2024
   Alexei Sibidanov), repeated to find inputs that take its slower branches. */
static int fast_fails(float x) {
  static const double b[] = {0x1.0000000000005p+0, 0x1.55557aeca105dp-3, 0x1.3314ec3db7d12p-4, 0x1.775738a5a6f92p-5,
    0x1.5d5f7ce1c8538p-8, 0x1.605c6d58740fp-2, -0x1.5728b732d73c6p+1, 0x1.f152170f151ebp+3, -0x1.f962ea3ca992ep+5,
    0x1.71971e17375ap+7, -0x1.860512b4ba23p+8, 0x1.26a3b8d4bdb14p+9, -0x1.36f2ea5698b51p+9, 0x1.b3d722aebfa2ep+8,
    -0x1.6cf89703b1289p+7, 0x1.1518af6a65e2dp+5};
  double z = x, z2 = z*z, z4 = z2*z2, z8 = z4*z4, z16 = z8*z8;
  double r = z*((((b[0] + z2*b[1]) + z4*(b[2] + z2*b[3])) + z8*((b[4] + z2*b[5]) + z4*(b[6] + z2*b[7]))) +
    z16*(((b[8] + z2*b[9]) + z4*(b[10] + z2*b[11])) + z8*((b[12] + z2*b[13]) + z4*(b[14] + z2*b[15]))));
  float ub = r, lb = r - z*0x1.efa8ebp-31;
  return ub != lb;
}
int main(int argc, char **argv) {
  if (argc < 2) return 0;
  if (!strcmp(argv[1], "slow")) {
    int want = atoi(argv[2]), found = 0;
    for (unsigned u = 0x39800000u; u < 0x3f614800u && found < want; u += 7919)
      if (fast_fails(value(u))) { printf("%u ", u); found++; }
    printf("\n");
    return 0;
  }
  if (!strcmp(argv[1], "host")) {
    unsigned bound = (unsigned)strtoul(argv[2], 0, 16), first = 0, bad = 0;
    unsigned long long n = 0;
    for (unsigned m = 0; m < bound; m++)
      for (int s = 0; s < 2; s++) {
        unsigned u = m | (unsigned)s << 31; float x = value(u);
        n++;
        if (bits(host_asinf(x)) != bits(glibc241_asinf(x)) && !bad++) first = u;
      }
    printf("%llu %u %u %d\n", n, bad, first, bits(host_asinf(value(bound))) != bits(glibc241_asinf(value(bound))));
    return 0;
  }
  for (int a = 1; a < argc; a++) {
    int n = load(argv[a]);
    for (int i = 0; i < n; i++) { float x = value(in[i]); if (fabsf(x) <= 1.0f) printf("%u ", bits(glibc241_asinf(x))); else printf("none "); }
    printf("\n");
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/binary64_sqrt.bend as Sqrt
import ../../src/binary64_fma.bend as Words
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
def kernel(+libm: M.Libm, values: +List<U32>) -> String:
  match values:
    case Con{w, rest}: scalar(M.Libm.asin(libm, float(w))) ++ " " ++ kernel(libm, rest)
    case Nil{}: ""
def angles(m: Maybe<M.Vector3>) -> String:
  match m:
    case None{}: "none"
    case Some{M.Vector3{x, y, z}}: bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z)
def eulers(+libm: M.Libm, values: +List<U32>) -> String:
  match values:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: angles(M.Quaternion.to_euler_for(libm, M.Vector4{float(a), float(b), float(c), float(d)})) ++ " " ++ eulers(libm, rest)
    case _: ""
def root(m: Maybe<Words.Words>) -> String:
  match m:
    case None{}: "none"
    case Some{Words.Words{h, l}}: U32.show(h) ++ ":" ++ U32.show(l)
def roots(values: +List<U32>) -> String:
  match values:
    case Con{h, Con{l, rest}}: root(Sqrt.checked(h, l)) ++ " " ++ roots(rest)
    case _: ""
def text(kind: U32, values: +List<U32>) -> String:
  match kind:
    case 6: roots(values)
    case 0: kernel(M.Glibc241Libm{}, values)
    case 1: kernel(M.Glibc239Libm{}, values)
    case 2: kernel(M.AppleLibm{}, values)
    case 3: eulers(M.Glibc241Libm{}, values)
    case 4: eulers(M.Glibc239Libm{}, values)
    case _: eulers(M.AppleLibm{}, values)
def section(kind: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{bytes}: IO.print(text(kind, words(bytes)))
def main() -> IO(Unit):
  do IO<Unit>:
'''

KINDS = {'kernel': (0, 1, 2), 'euler': (3, 4, 5), 'sqrt': (6,)}


def render(selected, gpu):
    body = PROGRAM
    for section, path in selected:
        for kind in KINDS[section]:
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{path}"), section({kind}))\n'
    return body + '    IO.print("done")\n'


def parse(text, selected):
    lines = text.splitlines()
    if lines[-1:] != ['done'] or len(lines) != sum(len(KINDS[section]) for section, _ in selected) + 1:
        raise ProbeFailure('quaternion-euler: candidate output did not finish')
    rows, index = [], 0
    for section, _path in selected:
        rows.append([lines[index + k].split() for k in range(len(KINDS[section]))])
        index += len(KINDS[section])
    return rows


def host_profile():
    if platform.system() == 'Darwin' and platform.machine() == 'arm64':
        return 'AppleLibm'
    try:
        version = os.confstr('CS_GNU_LIBC_VERSION')
    except (ValueError, OSError, AttributeError):
        version = None
    if platform.system() == 'Linux' and platform.machine() in ('x86_64', 'AMD64') and version == 'glibc 2.39':
        return 'Glibc239Libm'
    return None


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('quaternion-euler', args)
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ProbeFailure('quaternion-euler: pinned glibc 2.41 e_asinf.c changed')
    if hashlib.sha256(GLIBC239.read_bytes()).hexdigest() != GLIBC239_SHA256:
        raise ProbeFailure('quaternion-euler: pinned glibc 2.39 e_asinf.c changed')
    include = probe.work / 'asinf-include'  # build_oracle owns probe.work/include
    include.mkdir(parents=True, exist_ok=True)
    from libm_survey import SHIMS
    for name, text in SHIMS.items():
        (include / name).write_text(text)
    asinf_object = probe.work / 'glibc241_asinf.o'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-I' + str(include), '-D__ieee754_asinf=glibc241_asinf',
                  '-c', SOURCE, '-o', asinf_object])
    glibc239_object = probe.work / 'glibc239_asinf.o'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-iquote', GLIBC_SHIMS / 'quote', '-I', GLIBC_SHIMS / 'shim',
                  '-I', GLIBC239.parent, '-D__ieee754_asinf=glibc239_asinf', '-c', GLIBC239, '-o', glibc239_object])
    _cc, atan2_objects, _driver = build_oracle(probe)
    flags = ['-ffp-contract=off', '-fno-builtin']
    probe.native(KERNEL, 'kernel-build', extra_flags=[*flags, asinf_object], link_raylib=False)
    kernel_binary = probe.work / 'kernel-build'
    probe.native(KERNEL, 'kernel239-build', extra_flags=[*flags, '-Dglibc241_asinf=glibc239_asinf', glibc239_object], link_raylib=False)
    kernel_binaries = {'glibc241_asinf': kernel_binary, 'glibc239_asinf': probe.work / 'kernel239-build'}
    slow = [int(w) for w in probekit.run([kernel_binary, 'slow', '120']).split()]
    if len(slow) < 40:
        raise ProbeFailure('quaternion-euler: too few slow-path asinf inputs found')
    slow += [w | 0x80000000 for w in slow[:40]]
    rng = random.Random(0xE01E5)
    work = ROOT / WORK
    work.mkdir(parents=True, exist_ok=True)
    sections = {'kernel': chunks([[w] for w in kernel_inputs(rng, slow)], 1000), 'euler': chunks(euler_inputs(rng), 200),
                'sqrt': chunks(sqrt_inputs(rng), 300)}
    actions = []
    for section, parts in sections.items():
        for index, part in enumerate(parts):
            path = f'{WORK}/{section}-{index}.bin'
            (ROOT / path).write_bytes(b''.join(struct.pack('<I', w) for case in part for w in case))
            actions.append((section, path))
    kernel_paths = [path for section, path in actions if section == 'kernel']
    euler_paths = [path for section, path in actions if section == 'euler']
    kernel_lines = probekit.run([kernel_binary, *kernel_paths]).splitlines()
    source_lines = {'glibc241_asinf': kernel_lines,
                    'glibc239_asinf': probekit.run([kernel_binaries['glibc239_asinf'], *kernel_paths]).splitlines()}
    # The pinned source is correctly rounded; spot-check it with the exact oracle.
    checked = 0
    for path, line in zip(kernel_paths, kernel_lines):
        data = (ROOT / path).read_bytes()
        inputs = [struct.unpack_from('<I', data, 4 * i)[0] for i in range(len(data) // 4)]
        for x, result in list(zip(inputs, line.split()))[::7]:
            if result != 'none' and oracle.asinf_bits(x) != int(result):
                raise ProbeFailure(f'quaternion-euler: pinned asinf source is not correctly rounded at {x:08x}')
            checked += 1
    euler = {}
    available = [p for p in PROFILES if ATAN2F[p] or platform.system() == 'Darwin']
    for profile in available:
        defines = (['-DROUTE_ASINF', f'-Dglibc241_asinf={ASINF[profile]}'] + ([f'-DATAN2F={ATAN2F[profile]}'] if ATAN2F[profile] else []))
        probe.native(EULER, f'euler-{profile}', extra_flags=[*flags, *defines, asinf_object, glibc239_object, *atan2_objects],
                     link_raylib=False)
        euler[profile] = probekit.run([probe.work / f'euler-{profile}', f'{BOUNDS[profile]:x}', *euler_paths]).splitlines()
    host = host_profile()
    host_check = None
    if host:
        checker = kernel_binaries[ASINF[host]]
        count, bad, first, edge = map(int, probekit.run([checker, 'host', f'{HOST_BOUNDS[host]:x}'], timeout=3600).split())
        if bad:
            raise ProbeFailure(f'quaternion-euler: host asinf differs from the {host} source ({ASINF[host]}) in its domain '
                               f'on {bad} inputs, first {first:08x}')
        probe.native(EULER, 'euler-native', extra_flags=[*flags, *atan2_objects], link_raylib=False)
        native = probekit.run([probe.work / 'euler-native', f'{BOUNDS[host]:x}', *euler_paths]).splitlines()
        for line_native, line_expected in zip(native, euler[host]):
            for a, b in zip(line_native.split(), line_expected.split()):
                if b != 'none' and a != b:
                    raise ProbeFailure(f'quaternion-euler: native raymath differs from the {host} profile: {a} vs {b}')
        host_check = dict(profile=host, inputs_below_bound=count, bound_word_differs=bool(edge))
    expected = []
    euler_index = 0
    kernel_iters = {name: iter(lines) for name, lines in source_lines.items()}
    for section, _path in actions:
        if section == 'sqrt':
            data = (ROOT / _path).read_bytes()
            words = [struct.unpack_from('<I', data, 4 * i)[0] for i in range(len(data) // 4)]
            rows = [[sqrt_expected(words[i], words[i + 1]) for i in range(0, len(words), 2)]]
        elif section == 'kernel':
            items = {name: next(lines).split() for name, lines in kernel_iters.items()}
            data = (ROOT / _path).read_bytes()
            inputs = [struct.unpack_from('<I', data, 4 * i)[0] for i in range(len(data) // 4)]
            rows = [[r if r == 'none' or (x & 0x7FFFFFFF) < BOUNDS[p] else 'none' for x, r in zip(inputs, items[ASINF[p]])]
                    for p in PROFILES]
        else:
            rows = [euler[p][euler_index].split() if p in euler else None for p in PROFILES]
            euler_index += 1
        expected.append(rows)
    lanes = probe.candidates(render, actions, batch=4, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    if 'AppleLibm' not in euler:
        # Without a portable Apple atan2f the Euler rows of that profile are not compared.
        for rows in [expected, *lanes.values()]:
            for (section, _path), row in zip(actions, rows):
                if section == 'euler':
                    row[2] = None
    probe.compare(expected, lanes, describe=lambda i: f'{actions[i][0]} chunk {actions[i][1]}')
    flat = [item for (section, _), rows in zip(actions, expected) if section == 'euler' for row in rows if row for item in row]
    probe.finish(kernel_inputs=sum(len(p) for p in sections['kernel']), slow_path_inputs=len(slow),
                 sqrt_inputs=sum(len(p) for p in sections['sqrt']),
                 euler_cases=sum(len(p) for p in sections['euler']), euler_profiles=sorted(euler),
                 euler_refused=flat.count('none'), oracle_checked=checked, host_check=host_check,
                 source_sha256=SOURCE_SHA256, glibc239_source_sha256=GLIBC239_SHA256)


if __name__ == '__main__':
    main()
