#!/usr/bin/env python3
"""Compare M.Libm.powf with glibc 2.39's powf.

The Glibc239Libm profile answers glibc's x86_64 powf(x, y) for an x that is
+0 or positive and finite and a finite y that is not subnormal, wherever the
two builds glibc selects between give the same float: the FMA one (hosts
with FMA; each a*b + c of the two polynomials is one fma, and so is
z*invc - 1) and the SSE2 one. The expected words come from `model`: Arm
optimized-routines' log2_inline and exp2_inline in Python's binary64, with a
fused a*b + c rounded once from the exact rational sum, computed for both
builds; tools/reference/glibc_powf checks that model in C against glibc
2.39's two builds on 30 billion seeded pairs each. The builds differ on
about 7 pairs in ten billion, by one unit in the last place: six of the
pairs found are cases here, and the profile has no answer for them. On a
host whose libm is glibc 2.39 the native powf (through a volatile pointer,
so it is not folded) must give the same words where there is one.

The pairs: the special values (zeros, ones, infinities, NaNs, subnormals,
negative bases), results that underflow to 0 and to subnormals, that
overflow and that are within a 64th of a binade of 2^128 (no answer: the
kernel's exact binary64 helpers do not take exp2_inline's scale there),
the exponents raylib's audio_mixed_processor example reaches (0.5
to 3 by float sums of 0.05) with bases from its samples' range, and a
seeded sample. Glibc241Libm and AppleLibm are None (not verified).
CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct
from fractions import Fraction

from conformance import gradient_reference
from pow2_probe import TABLE
import probekit
from probekit import ProbeFailure

# invc and logc of log2_inline's sixteen intervals, then its polynomial (powf_log2_data.c), as binary64 words.
LOG2 = [0x3ff661ec79f8f3be, 0xbfdefec65b963019, 0x3ff571ed4aaf883d, 0xbfdb0b6832d4fca4,
        0x3ff49539f0f010b0, 0xbfd7418b0a1fb77b, 0x3ff3c995b0b80385, 0xbfd39de91a6dcf7b,
        0x3ff30d190c8864a5, 0xbfd01d9bf3f2b631, 0x3ff25e227b0b8ea0, 0xbfc97c1d1b3b7af0,
        0x3ff1bb4a4a1a343f, 0xbfc2f9e393af3c9f, 0x3ff12358f08ae5ba, 0xbfb960cbbf788d5c,
        0x3ff0953f419900a7, 0xbfaa6f9db6475fce, 0x3ff0000000000000, 0x0000000000000000,
        0x3fee608cfd9a47ac, 0x3fb338ca9f24f53d, 0x3feca4b31f026aa0, 0x3fc476a9543891ba,
        0x3feb2036576afce6, 0x3fce840b4ac4e4d2, 0x3fe9c2d163a1aa2d, 0x3fd40645f0c6651c,
        0x3fe886e6037841ed, 0x3fd88e9c2c1b9ff8, 0x3fe767dcf5534862, 0x3fdce0a44eb17bcc]
POLY = [0x3fd27616c9496e0b, 0xbfd71969a075c67a, 0x3fdec70a6ca7badd, 0xbfe7154748bef6c8, 0x3ff71547652ab82b]
C0, C1, C2 = float.fromhex('0x1.c6af84b912394p-5'), float.fromhex('0x1.ebfce50fac4f3p-3'), float.fromhex('0x1.62e42ff0c52d6p-1')
SHIFT = float.fromhex('0x1.8p47')
# From here up the profile has no answer: exp2_inline's scale is 2^128, which Jonlib's exact binary64 helpers do not take
# (glibc overflows from 0x1.fffffffd1d571p+6 up, and answers below that).
TOP = 127.984375

# Pairs on which glibc 2.39's FMA and SSE2 builds give floats one unit apart (found by tools/reference/glibc_powf's sample of
# 30 billion): the first three with exponents near the example's.
DIFFERING = [(0x37E9149D, 0x3F733335), (0x31D8711E, 0x400FFFFC), (0x28E1C036, 0x401CCCC8), (0x789168CE, 0xBF849986), (0x3FC58C73, 0x4039A618),
             (0x3B6F621E, 0xC0708EE4)]

NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static float (*volatile host_powf)(float, float) = powf;
static const uint32_t words[] = {WORDS};
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
int main(void) {
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i += 2) {
    float x, y;
    memcpy(&x, &words[i], 4);
    memcpy(&y, &words[i + 1], 4);
    printf("%u\n", bits(host_powf(x, y)));
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
def float(word: U32) -> F32:
  U32{w} = word
  F32{w}
def one(+x: U32, +y: U32) -> List<U32>:
  List.append(&1, U32, show(M.Libm.powf(M.Glibc239Libm{}, float(x), float(y))),
    List.append(&1, U32, show(M.Libm.powf(M.Glibc241Libm{}, float(x), float(y))), show(M.Libm.powf(M.AppleLibm{}, float(x), float(y)))))
def all(words: List<U32>) -> List<U32>:
  match words:
    case Con{x, Con{y, rest}}: List.append(&1, U32, one(x, y), all(rest))
    case _: Nil{}
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([WORDS])))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def real(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def double(bits):
    return struct.unpack('<d', struct.pack('<Q', bits))[0]


def madd(fused, a, b, c):
    """a*b + c: one rounding of the exact sum in the FMA build, two in the SSE2 one."""
    return float(Fraction(a) * Fraction(b) + Fraction(c)) if fused else a * b + c


def narrowed(value):
    """(float) of a binary64: to nearest even, an infinity past the largest float."""
    try:
        return word(value)
    except OverflowError:
        return 0x7F800000 if value > 0 else 0xFF800000


def build(fused, ix, iy):
    """The word a build's main path gives for the words of a positive finite x and a finite y; None from TOP up."""
    if ix < 0x00800000:                                     # a subnormal x: x*2^23, 23 less in the exponent
        ix = (word(real(ix) * 8388608.0) & 0x7FFFFFFF) - (23 << 23) & 0xFFFFFFFF
    tmp = (ix - 0x3F330000) & 0xFFFFFFFF
    i, top = (tmp >> 19) % 16, tmp & 0xFF800000
    k = (top - (1 << 32) if top & 0x80000000 else top) >> 23
    z = real((ix - top) & 0xFFFFFFFF)
    r = madd(fused, z, double(LOG2[2 * i]), -1.0)
    y0 = double(LOG2[2 * i + 1]) + float(k)
    r2 = r * r
    y = madd(fused, double(POLY[0]), r, double(POLY[1]))
    p = madd(fused, double(POLY[2]), r, double(POLY[3]))
    r4 = r2 * r2
    logx = madd(fused, y, r4, madd(fused, p, r2, madd(fused, double(POLY[4]), r, y0)))
    xd = real(iy) * logx
    if xd >= TOP:
        return None
    if (struct.unpack('<Q', struct.pack('<d', xd))[0] >> 47 & 0xFFFF) >= 0x80BF:
        if xd <= -150.0:
            return 0
        if xd < -149.0:
            return 1
    kd = xd + SHIFT
    ki = struct.unpack('<Q', struct.pack('<d', kd))[0]
    kd -= SHIFT
    r = xd - kd
    s = double((TABLE[ki % 32] + (ki << 47)) & 0xFFFFFFFFFFFFFFFF)
    z = madd(fused, C0, r, C1)
    return narrowed(madd(fused, z, r * r, madd(fused, C2, r, 1.0)) * s)


def model(ix, iy):
    """What the profile answers for the words of x and y: the word, or None."""
    ay = iy & 0x7FFFFFFF
    if ay == 0:
        return 0x3F800000 if (ix & 0x7FFFFFFF) <= 0x7F800000 else None
    if not 0x00800000 <= ay < 0x7F800000:
        return None
    if ix == 0:
        return 0 if iy < 0x80000000 else None
    if ix >= 0x7F800000:
        return None
    fused, plain = build(True, ix, iy), build(False, ix, iy)
    return fused if fused is not None and fused == plain else None


def exponents():
    """The exponents the example's keys reach from 1: down to 0.5 and up to 3 by float sums of 0.05, clamped as it clamps them,
    and back from each end."""
    def f(v):
        return real(word(v))

    out, e = [], 1.0
    for step in (-0.05, 0.05, -0.05):
        for _ in range(60):
            e = f(e + f(step))
            e = 0.5 if e <= 0.5 else 3.0 if e >= 3.0 else e
            out.append(word(e))
    return sorted(set(out) | {word(1.0)})


def sample(count, seed=0x9E3779B9):
    """Deterministic pairs: a positive finite x of any exponent and a y of magnitude 2^-8 to 2^7."""
    out, state = [], seed
    for _ in range(count):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        x = ((state >> 8) % 0xFF) << 23 | (state * 2654435761 >> 9) & 0x7FFFFF
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        y = (119 + (state >> 8) % 16) << 23 | (state * 2654435761 >> 9) & 0x7FFFFF | state & 0x80000000
        out.append((x or 1, y))
    return out


def cases():
    """(word of x, word of y) pairs."""
    special = [0.0, -0.0, 1.0, -1.0, 2.0, 0.5, 3.0, 10.0, 1e-30, 1e30, float('inf'), float('-inf'), float('nan')]
    pairs = [(word(x), word(y)) for x in special for y in special]
    pairs += [(1, word(1.0)), (1, word(0.5)), (0x007FFFFF, word(2.0)), (0x00800000, word(1.0)), (0x7F7FFFFF, word(1.0)), (0x7F7FFFFF, word(1.0000001)),
              (word(2.0), word(127.99)), (word(2.0), word(128.0)), (word(2.0), word(-126.0)), (word(2.0), word(-140.5)), (word(2.0), word(-149.0)),
              (word(2.0), word(-149.5)), (word(2.0), word(-150.0)), (word(2.0), word(-151.0)), (word(2.0), 1), (word(2.0), 0x007FFFFF), (word(2.0), 0x00800000),
              (word(1.5), word(-2.5)), (word(0.75), word(1e10)), (word(1.25), word(-1e10)), (word(1.0000001), word(1e9))]
    # the example's bases: a mixed sample's magnitude, from the quietest a 16-bit sample gives to a little over 1
    bases = [word(v) for v in (1 / 32768, 3 / 32768, 0.001, 0.0101, 0.05, 0.1234, 0.25, 0.3333, 0.5, 0.707, 0.9, 0.99999994, 1.0, 1.1, 1.7)] + [0x00800000, 0x3F7FFFFE]
    chosen = exponents()
    pairs += [(bases[(3 * n + m) % len(bases)], y) for n, y in enumerate(chosen) for m in range(2)]
    return pairs + DIFFERING + sample(120)


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('powf', args)
    chosen = cases()
    flat = [w for pair in chosen for w in pair]
    native = [int(line) for line in probe.native(NATIVE.replace('WORDS', ', '.join(f'{w}u' for w in flat))).splitlines()]
    if len(native) != len(chosen):
        raise ProbeFailure('powf: incomplete native output')
    expected, answered = [], 0
    for ix, iy in chosen:
        value = model(ix, iy)
        answered += value is not None
        expected.append(([1, value] if value is not None else [0, 0]) + [0, 0, 0, 0])
    if answered < 200 or len(chosen) - answered < 60:
        raise ProbeFailure(f'powf: {answered} of {len(chosen)} pairs answered; the cases lost coverage')
    apart = [(ix, iy) for ix, iy in DIFFERING if build(True, ix, iy) == build(False, ix, iy)]
    if apart:
        raise ProbeFailure(f'powf: the model\'s two builds agree on {apart[0][0]:#010x}, {apart[0][1]:#010x}, where glibc\'s do not')
    compared = 0
    if gradient_reference() == 'Glibc239Libm':
        for (ix, iy), host, row in zip(chosen, native, expected):
            if row[0]:
                compared += 1
                if host != row[1]:
                    raise ProbeFailure(f'powf: the host powf differs from the model at x = {ix:#010x}, y = {iy:#010x}: {host:#010x} and {row[1]:#010x}')

    def render(pairs, gpu):
        return PROGRAM.replace('WORDS', ', '.join(str(w) for pair in pairs for w in pair)).replace('all([', 'all!([' if gpu else 'all([')

    def parse(text, pairs):
        values = [v for line in text.splitlines() if line.strip() for v in json.loads(line)]
        if len(values) != 6 * len(pairs):
            raise ProbeFailure('powf: wrong candidate output size')
        return [values[6 * i:6 * i + 6] for i in range(len(pairs))]

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse),
                  describe=lambda i: f'x = {chosen[i][0]:#010x}, y = {chosen[i][1]:#010x}')
    probe.finish(cases=len(chosen), answered=answered, native_compared=compared, exponents=len(exponents()), builds_differ=len(DIFFERING))


if __name__ == '__main__':
    main()
