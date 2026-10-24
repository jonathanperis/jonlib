#!/usr/bin/env python3
"""Compare M.Libm.pow2 (powf(2, y)) with the host's powf and exp2f.

The glibc profiles answer glibc's x86_64 powf(2, y), which is also its
exp2f(y), for every finite y below 126 in magnitude (a normal result). The
expected words come from `model`: the kernel's arithmetic (Arm
optimized-routines' exp2_inline) in Python's binary64, which
tools/reference/glibc_pow2 checks against glibc 2.39 and 2.41, in their SSE2
and FMA variants, on every such y. On a glibc host the native powf(2, y) and
exp2f(y) (through volatile pointers, so neither is folded) must give the same
words. AppleLibm answers the measured exponents in src/apple_exp2.bend and
None for every other y (126 and beyond, infinities, NaN, and any exponent
the measurement did not reach). On macOS those measured words are checked
against the host's powf(2, y) and exp2f(y). CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import re
import struct
from pathlib import Path

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
C0, C1, C2 = float.fromhex('0x1.c6af84b912394p-5'), float.fromhex('0x1.ebfce50fac4f3p-3'), float.fromhex('0x1.62e42ff0c52d6p-1')
SHIFT = float.fromhex('0x1.8p47')
LIMIT = 0x42FC0000  # 126.0f
_APPLE = None


def apple_answers():
    """y word -> result word, from the Apple.at leaves in src/apple_exp2.bend."""
    global _APPLE
    if _APPLE is None:
        text = (Path(__file__).resolve().parents[1] / 'src' / 'apple_exp2.bend').read_text()
        body = text.split('def table', 1)[1].split('def search', 1)[0]
        # The tree repeats its last leaf to fill a power of two; the first copy wins.
        _APPLE = {}
        for key, value in re.findall(r'PowTip\{(\d+), (\d+)\}', body):
            _APPLE.setdefault(int(key), int(value))
    return _APPLE


def apple_waves():
    """Argument word -> sinf word, from Apple.wave."""
    text = (Path(__file__).resolve().parents[1] / 'src' / 'apple_exp2.bend').read_text()
    body = text.split('def wave', 1)[1].split('def at.', 1)[0]
    return {int(key): int(value) for key, value in re.findall(r'case (\d+): Some\{float\((\d+)\)\}', body)}

NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static float (*volatile host_powf)(float, float) = powf;
static float (*volatile host_exp2f)(float) = exp2f;
static volatile float two = 2.0f;
static const uint32_t words[] = {WORDS};
static uint32_t bits(float v) { uint32_t b; memcpy(&b, &v, 4); return b; }
int main(void) {
  for (unsigned i = 0; i < sizeof words / sizeof words[0]; i++) {
    float y;
    memcpy(&y, &words[i], 4);
    printf("%u %u\n", bits(host_powf(two, y)), bits(host_exp2f(y)));
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
def one(+word: U32) -> List<U32>:
  U32{w} = word
  List.append(&1, U32, show(M.Libm.pow2(M.Glibc239Libm{}, F32{w})),
    List.append(&1, U32, show(M.Libm.pow2(M.Glibc241Libm{}, F32{w})), show(M.Libm.pow2(M.AppleLibm{}, F32{w}))))
# A flat walk of the words is not a tail call, and the JavaScript lane
# overflows on a few thousand of them. One fuelled loop drains each word's
# six results onto the front and reverses once. 65536 steps cover a batch
# of 4096 words (eight steps a word). phase True reads words; False drains extra.
def all.go(+fuel: Nat, phase: Bool, words: List<U32>, extra: List<U32>, acc: List<U32>) -> List<U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match phase:
        case True{}:
          match words:
            case Nil{}:
              List.reverse(&1, U32, acc)
            case Con{+w, rest}:
              all.go(p, False{}, rest, one(w), acc)
        case False{}:
          match extra:
            case Nil{}:
              all.go(p, True{}, words, Nil{}, acc)
            case Con{h, t}:
              all.go(p, False{}, words, t, h <> acc)
def all(words: List<U32>) -> List<U32>:
  all.go(65536n, True{}, words, Nil{}, Nil{})
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([WORDS])))
'''


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def inside(bits):
    """A finite y below 126 in magnitude."""
    return (bits & 0x7FFFFFFF) < LIMIT


def model(bits):
    """The word of powf(2, y) for the word of y: every operation is one binary64 rounding, then (float)."""
    xd = struct.unpack('<f', struct.pack('<I', bits))[0]
    kd = xd + SHIFT
    ki = struct.unpack('<Q', struct.pack('<d', kd))[0]
    kd -= SHIFT
    r = xd - kd
    s = struct.unpack('<d', struct.pack('<Q', (TABLE[ki % 32] + (ki << 47)) & 0xFFFFFFFFFFFFFFFF))[0]
    z = C0 * r + C1
    r2 = r * r
    q = C2 * r + 1.0
    q = z * r2 + q
    return word(q * s)


def sample(count, seed=0x9E3779B9):
    """Deterministic words over the whole domain (every exponent, both signs)."""
    out, state = [], seed
    while len(out) < count:
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        magnitude = ((state >> 8) % 0x86) << 23 | (state * 2654435761 >> 9) & 0x7FFFFF
        if magnitude < LIMIT:
            out.append(magnitude | (state & 0x80000000))
    return out


def cases():
    values = [float(k) for k in range(-130, 131, 5)] + [float(k) for k in range(-24, 35)]
    values += [0.5, -0.5, 1.5, 0.1, -0.1, 1 / 3, -9.75, 29.999998, -20.000002, 125.5, -125.5, 1e-10, -1e-30, 1e9, -1e9, float('inf'), float('-inf'), -0.0]
    # The easings' exponents: -10*t and 10*(t - 1) for t = n/120.
    values += [struct.unpack('<f', struct.pack('<f', -10.0 * struct.unpack('<f', struct.pack('<f', n / 120))[0]))[0] for n in range(0, 121, 7)]
    words = [word(v) for v in values]
    words += [LIMIT - 1, LIMIT, LIMIT + 1, 0x80000000 | (LIMIT - 1), 0x80000000 | LIMIT, 1, 0x007FFFFF, 0x00800000, 0x80000001, 0x7FC00000, 0xFFC00000, 0x7F7FFFFF]
    return words + sample(120)


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('pow2', args)
    chosen = cases()
    native = [[int(v) for v in line.split()] for line in probe.native(NATIVE.replace('WORDS', ', '.join(f'{w}u' for w in chosen))).splitlines()]
    if len(native) != len(chosen):
        raise ProbeFailure('pow2: incomplete native output')
    glibc = gradient_reference() != 'AppleLibm'
    compared = 0
    if glibc:
        for bits, (power, exp2) in zip(chosen, native):
            if inside(bits):
                compared += 1
                if power != model(bits) or exp2 != model(bits):
                    raise ProbeFailure(f'pow2: the host powf(2, y) or exp2f(y) differs from the model at y = {bits:#010x}')
    answers = apple_answers()
    if not glibc:
        measured = list(answers)
        native_measured = [[int(v) for v in line.split()] for line in probe.native(NATIVE.replace('WORDS', ', '.join(f'{w}u' for w in measured))).splitlines()]
        if len(native_measured) != len(measured):
            raise ProbeFailure('pow2: incomplete native output for the Apple exponents')
        for bits, (power, exp2) in zip(measured, native_measured):
            if power != answers[bits] or exp2 != answers[bits]:
                raise ProbeFailure(f'pow2: the host powf(2, y) or exp2f(y) differs from the measured word at y = {bits:#010x}')
    expected = []
    for bits in chosen:
        some = [1, model(bits)] if inside(bits) else [0, 0]
        apple = [1, answers[bits]] if bits in answers else [0, 0]
        expected.append(some + some + apple)

    def render(words, gpu):
        return PROGRAM.replace('WORDS', ', '.join(str(w) for w in words)).replace('all([', 'all!([' if gpu else 'all([')

    def parse(text, words):
        values = [v for line in text.splitlines() if line.strip() for v in json.loads(line)]
        if len(values) != 6 * len(words):
            raise ProbeFailure('pow2: wrong candidate output size')
        return [values[6 * i:6 * i + 6] for i in range(len(words))]

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), parse=parse),
                  describe=lambda i: f'y = {chosen[i]:#010x}')
    measured = list(answers)
    measured_expected = []
    for bits in measured:
        some = [1, model(bits)]
        measured_expected.append(some + some + [1, answers[bits]])
    # A Bend list longer than 4096 overflows the checker. A JavaScript list
    # literal deeper than about 2500 overflows the lane that evaluates it, so
    # the measured words are batches of 1024. The expectations are still every
    # recorded word.
    probe.compare(measured_expected, probe.candidates(render, measured, batch=1024, parse=parse),
                  describe=lambda i: f'apple y = {measured[i]:#010x}')
    probe.finish(cases=len(chosen), inside=sum(1 for b in chosen if inside(b)), native_compared=compared, apple=len(answers))


if __name__ == '__main__':
    main()
