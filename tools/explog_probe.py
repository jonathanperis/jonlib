#!/usr/bin/env python3
"""Compare M.Libm.exp and M.Libm.log with the host's expf and logf.

The glibc profiles answer glibc's x86_64 expf for every finite x below 87 in
magnitude (a normal result) except the two arguments at which its SSE2 and
FMA variants differ, and its logf for every positive normal x. The expected
words come from `exp_model` and `log_model`: the kernels' arithmetic (Arm
optimized-routines' expf.c and logf.c) in Python's binary64, which
tools/reference/glibc_explog checks against glibc 2.39 and 2.41, in both
variants, on every such argument. On a glibc host the native expf and logf
(through volatile pointers) must give the same words. AppleLibm and every
other argument are None. CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

# 2^(i/32) as raw binary64 words minus i << 47 (exp2f_data.c, EXP2F_TABLE_BITS 5).
TABLE = [0x3ff0000000000000, 0x3fefd9b0d3158574, 0x3fefb5586cf9890f, 0x3fef9301d0125b51,
         0x3fef72b83c7d517b, 0x3fef54873168b9aa, 0x3fef387a6e756238, 0x3fef1e9df51fdee1,
         0x3fef06fe0a31b715, 0x3feef1a7373aa9cb, 0x3feedea64c123422, 0x3feece086061892d,
         0x3feebfdad5362a27, 0x3feeb42b569d4f82, 0x3feeab07dd485429, 0x3feea47eb03a5585,
         0x3feea09e667f3bcd, 0x3fee9f75e8ec5f74, 0x3feea11473eb0187, 0x3feea589994cce13,
         0x3feeace5422aa0db, 0x3feeb737b0cdc5e5, 0x3feec49182a3f090, 0x3feed503b23e255d,
         0x3feee89f995ad3ad, 0x3feeff76f2fb5e47, 0x3fef199bdd85529c, 0x3fef3720dcef9069,
         0x3fef5818dcfba487, 0x3fef7c97337b9b5f, 0x3fefa4afa2a490da, 0x3fefd0765b6e4540]
INVLN2N, SHIFT = float.fromhex('0x1.71547652b82fep+0') * 32, float.fromhex('0x1.8p+52')
C0, C1, C2 = float.fromhex('0x1.c6af84b912394p-5') / 32 / 32 / 32, float.fromhex('0x1.ebfce50fac4f3p-3') / 32 / 32, float.fromhex('0x1.62e42ff0c52d6p-1') / 32
# logf_data.c: 1/c and log(c) for the 16 subintervals, ln2 and the polynomial.
INVC = [float.fromhex(v) for v in ('0x1.661ec79f8f3bep+0', '0x1.571ed4aaf883dp+0', '0x1.49539f0f010bp+0', '0x1.3c995b0b80385p+0', '0x1.30d190c8864a5p+0', '0x1.25e227b0b8eap+0', '0x1.1bb4a4a1a343fp+0', '0x1.12358f08ae5bap+0', '0x1.0953f419900a7p+0', '0x1p+0', '0x1.e608cfd9a47acp-1', '0x1.ca4b31f026aap-1', '0x1.b2036576afce6p-1', '0x1.9c2d163a1aa2dp-1', '0x1.886e6037841edp-1', '0x1.767dcf5534862p-1',)]
LOGC = [float.fromhex(v) for v in ('-0x1.57bf7808caadep-2', '-0x1.2bef0a7c06ddbp-2', '-0x1.01eae7f513a67p-2', '-0x1.b31d8a68224e9p-3', '-0x1.6574f0ac07758p-3', '-0x1.1aa2bc79c81p-3', '-0x1.a4e76ce8c0e5ep-4', '-0x1.1973c5a611cccp-4', '-0x1.252f438e10c1ep-5', '0x0p+0', '0x1.aa5aa5df25984p-5', '0x1.c5e53aa362eb4p-4', '0x1.526e57720db08p-3', '0x1.bc2860d22477p-3', '0x1.1058bc8a07ee1p-2', '0x1.4043057b6ee09p-2',)]
LN2 = float.fromhex('0x1.62e42fefa39efp-1')
A0, A1, A2 = float.fromhex('-0x1.00ea348b88334p-2'), float.fromhex('0x1.5575b0be00b6ap-2'), float.fromhex('-0x1.ffffef20a4123p-2')
EXP_LIMIT = 0x42AE0000                       # 87.0f
EXP_VARIANTS = (0x4202422F, 0xC27C65D9)      # the SSE2 and FMA variants of expf differ here

NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static float (*volatile host_expf)(float) = expf;
static float (*volatile host_logf)(float) = logf;
static const uint32_t words[] = {WORDS};
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
int main(void) {
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i++) {
    float x;
    memcpy(&x, &words[i], 4);
    printf("%u %u\n", bits(host_expf(x)), bits(host_logf(x)));
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def show(value: Maybe<F32>) -> List<U32>:
  match value:
    case None{}: [0, 0]
    case Some{v}: [1, F32.bits(v)]
def exps(+word: U32) -> List<U32>:
  U32{w} = word
  List.append(&1, U32, show(M.Libm.exp(M.Glibc239Libm{}, F32{w})),
    List.append(&1, U32, show(M.Libm.exp(M.Glibc241Libm{}, F32{w})), show(M.Libm.exp(M.AppleLibm{}, F32{w}))))
def logs(+word: U32) -> List<U32>:
  U32{w} = word
  List.append(&1, U32, show(M.Libm.log(M.Glibc239Libm{}, F32{w})),
    List.append(&1, U32, show(M.Libm.log(M.Glibc241Libm{}, F32{w})), show(M.Libm.log(M.AppleLibm{}, F32{w}))))
def one(+word: U32) -> List<U32>:
  List.append(&1, U32, exps(word), logs(word))
def all(words: List<U32>) -> List<U32>:
  match words:
    case Nil{}: Nil{}
    case Con{w, rest}: List.append(&1, U32, one(w), all(rest))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([WORDS])))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def number(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def exp_inside(bits):
    """A finite x below 87 in magnitude that both variants of glibc's expf answer alike."""
    return (bits & 0x7FFFFFFF) < EXP_LIMIT and bits not in EXP_VARIANTS


def log_inside(bits):
    """A positive normal x."""
    return 0x00800000 <= bits < 0x7F800000


def exp_model(bits):
    """The word of expf(x): every operation is one binary64 rounding, then (float)."""
    z = INVLN2N * number(bits)
    kd = z + SHIFT
    ki = struct.unpack('<Q', struct.pack('<d', kd))[0]
    kd -= SHIFT
    r = z - kd
    s = struct.unpack('<d', struct.pack('<Q', (TABLE[ki % 32] + (ki << 47)) & 0xFFFFFFFFFFFFFFFF))[0]
    z = C0 * r + C1
    r2 = r * r
    y = C2 * r + 1.0
    y = z * r2 + y
    return word(y * s)


def log_model(bits):
    """The word of logf(x) for a positive normal x."""
    tmp = (bits - 0x3F330000) & 0xFFFFFFFF
    i = (tmp >> 19) % 16
    k = (tmp >> 23) - (512 if tmp & 0x80000000 else 0)
    z = number((bits - (tmp & 0xFF800000)) & 0xFFFFFFFF)
    r = z * INVC[i] - 1.0
    y0 = LOGC[i] + k * LN2
    r2 = r * r
    y = A1 * r + A2
    y = A0 * r2 + y
    y = y * r2 + (y0 + r)
    return word(y)


def sample(count, seed):
    """Deterministic words over every exponent and both signs."""
    out, state = [], seed
    while len(out) < count:
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        out.append(((state >> 8) % 0xFF) << 23 | (state * 2654435761 >> 9) & 0x7FFFFF | (state & 0x80000000))
    return out


def cases():
    values = [float(k) for k in range(-90, 91, 6)] + [0.0, -0.0, 1.0, -1.0, 0.5, 2.0, 0.125, 64.0, 2.718281828, 0.1, -0.1, 1e-10, 1e-30, 1e30, 86.5, -86.5,
                                                    0.2, -0.2, 2.0794415, 4.158883, float('inf'), float('-inf')]
    # The zoom steps of core_2d_camera_mouse_zoom: logf(zoom) + 0.2*wheel for zooms from 0.125 to 64.
    values += [number(word(0.125 * 1.2214028 ** n)) for n in range(0, 32, 3)]
    words = [word(v) for v in values]
    words += [EXP_LIMIT - 1, EXP_LIMIT, 0x80000000 | (EXP_LIMIT - 1), 0x80000000 | EXP_LIMIT, *EXP_VARIANTS, EXP_VARIANTS[0] + 1, EXP_VARIANTS[1] - 1,
              1, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0x7F800000, 0x7FC00000, 0x3F7FFFFF, 0x3F800001, 0x3F330000, 0x3F32FFFF]
    return words + sample(160, 0x51F15E5D)


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('explog', args)
    chosen = cases()
    native = [[int(v) for v in line.split()] for line in probe.native(NATIVE.replace('WORDS', ', '.join(f'{w}u' for w in chosen))).splitlines()]
    if len(native) != len(chosen):
        raise ProbeFailure('explog: incomplete native output')
    glibc = gradient_reference() != 'AppleLibm'
    compared = 0
    if glibc:
        for bits, (exp, log) in zip(chosen, native):
            if exp_inside(bits):
                compared += 1
                if exp != exp_model(bits):
                    raise ProbeFailure(f'explog: the host expf differs from the model at x = {bits:#010x}')
            if log_inside(bits):
                compared += 1
                if log != log_model(bits):
                    raise ProbeFailure(f'explog: the host logf differs from the model at x = {bits:#010x}')
    expected = []
    for bits in chosen:
        exp = [1, exp_model(bits)] if exp_inside(bits) else [0, 0]
        log = [1, log_model(bits)] if log_inside(bits) else [0, 0]
        expected.append(exp + exp + [0, 0] + log + log + [0, 0])

    def render(words, gpu):
        return PROGRAM.replace('WORDS', ', '.join(str(w) for w in words)).replace('all([', 'all!([' if gpu else 'all([')

    def parse(text, words):
        values = [v for line in text.splitlines() if line.strip() for v in json.loads(line)]
        if len(values) != 12 * len(words):
            raise ProbeFailure('explog: wrong candidate output size')
        return [values[12 * i:12 * i + 12] for i in range(len(words))]

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse),
                  describe=lambda i: f'x = {chosen[i]:#010x}')
    probe.finish(cases=len(chosen), exp_inside=sum(1 for b in chosen if exp_inside(b)), log_inside=sum(1 for b in chosen if log_inside(b)), native_compared=compared)


if __name__ == '__main__':
    main()
