#!/usr/bin/env python3
"""Exact-integer oracle for correctly rounded binary64 tan and binary32 asinf.

Independent of every C library and of CORE-MATH: values are fixed-point Python
integers, pi comes from Machin's formula, and every rounding decision is
checked against an explicit error bound (Ziv loop: the working precision is
raised until both ends of the error interval round to the same result).

    tan_bits(word64) -> word64      round-to-nearest-even tan of a binary64
    asinf_bits(word32) -> word32    round-to-nearest-even asin of a binary32

Both reject non-finite inputs (and asinf |x| > 1) with ValueError.
"""

from __future__ import annotations

import argparse
import struct
from fractions import Fraction
from functools import lru_cache


def f64(word: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", word))[0]


def w64(value: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def f32(word: int) -> float:
    return struct.unpack("<f", struct.pack("<I", word))[0]


def w32(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def exact64(word: int) -> Fraction:
    sign = -1 if word >> 63 else 1
    exponent = (word >> 52) & 2047
    mantissa = word & ((1 << 52) - 1)
    if exponent == 2047:
        raise ValueError("non-finite binary64")
    if exponent == 0:
        return sign * Fraction(mantissa, 1 << 1074)
    return sign * Fraction(mantissa | (1 << 52)) * Fraction(2) ** (exponent - 1075)


def exact32(word: int) -> Fraction:
    sign = -1 if word >> 31 else 1
    exponent = (word >> 23) & 255
    mantissa = word & ((1 << 23) - 1)
    if exponent == 255:
        raise ValueError("non-finite binary32")
    if exponent == 0:
        return sign * Fraction(mantissa, 1 << 149)
    return sign * Fraction(mantissa | (1 << 23)) * Fraction(2) ** (exponent - 150)


def round_format(value: Fraction, precision: int, emin: int, emax: int) -> tuple[int, int, int]:
    """Round a nonzero rational to (sign, integer significand, exponent) with
    `precision` bits, nearest-even, gradual underflow below 2^emin; the result
    is significand * 2^exponent.  Overflow returns significand 0, exponent None
    is never produced (callers check the magnitude)."""
    sign = 1 if value < 0 else 0
    magnitude = -value if sign else value
    n, d = magnitude.numerator, magnitude.denominator
    e = n.bit_length() - d.bit_length()
    if Fraction(n, d) < Fraction(2) ** e:
        e -= 1
    e = max(e, emin)
    quantum = e - (precision - 1)
    scaled = magnitude / Fraction(2) ** quantum
    q, r = divmod(scaled.numerator, scaled.denominator)
    twice = 2 * r
    if twice > scaled.denominator or (twice == scaled.denominator and q & 1):
        q += 1
    if q == 1 << precision:
        q >>= 1
        quantum += 1
    if quantum + precision - 1 > emax:
        raise OverflowError
    return sign, q, quantum


def pack64(sign: int, q: int, quantum: int) -> int:
    if q < (1 << 52):
        return (sign << 63) | q
    return (sign << 63) | ((quantum + 1075) << 52) | (q - (1 << 52))


def pack32(sign: int, q: int, quantum: int) -> int:
    if q < (1 << 23):
        return (sign << 31) | q
    return (sign << 31) | ((quantum + 150) << 23) | (q - (1 << 23))


def round64(value: Fraction) -> int:
    if value == 0:
        raise ValueError("exact zero has no sign")
    return pack64(*round_format(value, 53, -1022, 1023))


def round32(value: Fraction) -> int:
    if value == 0:
        raise ValueError("exact zero has no sign")
    return pack32(*round_format(value, 24, -126, 127))


@lru_cache(maxsize=None)
def pi_fixed(bits: int) -> int:
    """floor-ish pi * 2^bits with |error| < 2^-(bits)*... (Machin, guard bits)."""
    guard = 32
    scale = 1 << (bits + guard)

    def arctan_inverse(n: int) -> int:
        total, term, k, n2 = 0, scale // n, 0, n * n
        while term:
            total += term // (2 * k + 1) if k % 2 == 0 else -(term // (2 * k + 1))
            term //= n2
            k += 1
        return total

    value = 4 * (4 * arctan_inverse(5) - arctan_inverse(239))
    return value >> guard


def sin_cos_fixed(r: int, bits: int) -> tuple[int, int]:
    """sin and cos of r/2^bits (|r/2^bits| <= 1) as fixed-point integers with
    absolute error below bits + 64 units of 2^-bits (at most one
    truncation unit per term, fewer than `bits` terms)."""
    one = 1 << bits
    r2 = (r * r) >> bits
    s, term, k = 0, r, 1
    while term:
        s += term
        term = -((term * r2) >> bits) // ((k + 1) * (k + 2))
        k += 2
    c, term, k = 0, one, 0
    while term:
        c += term
        term = -((term * r2) >> bits) // ((k + 1) * (k + 2))
        k += 2
    return s, c


def tan_interval(x: Fraction, bits: int) -> tuple[Fraction, Fraction]:
    """An interval containing tan(x)."""
    pi_bits = bits + max(0, x.numerator.bit_length() - x.denominator.bit_length()) + 8
    pi = pi_fixed(pi_bits)  # |pi_fixed/2^pi_bits - pi| < 2^-(pi_bits-1)
    half_pi = Fraction(pi, 1 << (pi_bits + 1))
    k = round(x / half_pi)
    reduced = x - k * half_pi
    # |k| * 2^-(pi_bits) bounds the reduction error.
    reduction_error = Fraction(abs(k) + 1, 1 << pi_bits)
    r = round(reduced * (1 << bits))
    s, c = sin_cos_fixed(r, bits)
    slack = bits + 64 + int(reduction_error * (1 << bits)) + 2
    if k % 2:
        numerator, denominator = -c, s
    else:
        numerator, denominator = s, c
    # numerator/denominator with each within `slack` units of the true value.
    if abs(denominator) <= 4 * slack:
        raise ArithmeticError("insufficient precision")
    lo_n, hi_n = numerator - slack, numerator + slack
    lo_d, hi_d = denominator - slack, denominator + slack
    candidates = [Fraction(a, b) for a in (lo_n, hi_n) for b in (lo_d, hi_d)]
    return min(candidates), max(candidates)


def tan_bits(word: int) -> int:
    x = exact64(word)
    if x == 0:
        return word
    bits = 160 + max(0, x.denominator.bit_length() - x.numerator.bit_length())
    while True:
        try:
            lo, hi = tan_interval(x, bits)
        except ArithmeticError:
            bits *= 2
            continue
        if lo != 0 and hi != 0 and (lo > 0) == (hi > 0):
            a, b = round64(lo), round64(hi)
            if a == b:
                return a
        bits *= 2
        if bits > 1 << 16:
            raise ArithmeticError("Ziv loop did not converge")


def sin_interval(m: Fraction, bits: int) -> tuple[Fraction, Fraction]:
    r = round(m * (1 << bits))
    s, _ = sin_cos_fixed(r, bits)
    slack = bits + 64
    return Fraction(s - slack, 1 << bits), Fraction(s + slack, 1 << bits)


def asinf_bits(word: int) -> int:
    x = exact32(word)
    if abs(x) > 1:
        raise ValueError("asinf domain is [-1, 1]")
    if x == 0:
        return word
    sign = 1 if x < 0 else 0
    ax = -x if sign else x
    # Candidate from the host double asin, then walk until the midpoints
    # bracket asin(ax): sin(lower midpoint) < ax < sin(upper midpoint), with
    # sin increasing on [0, pi/2].  Every comparison is decided exactly.
    import math

    candidate = round32(Fraction(math.asin(float(ax))))
    bits = 200 + max(0, ax.denominator.bit_length() - ax.numerator.bit_length())
    half_pi_upper = Fraction(pi_fixed(bits) + 1, 1 << (bits + 1))

    def compare_sin(m: Fraction) -> int:
        """sign(sin(m) - ax) for a midpoint m, or +1 when m > pi/2."""
        if m >= half_pi_upper:
            return 1
        precision = bits
        while True:
            lo, hi = sin_interval(m, precision)
            if hi < ax:
                return -1
            if lo > ax:
                return 1
            precision *= 2
            if precision > 1 << 16:
                raise ArithmeticError("sin comparison did not converge")

    for _ in range(64):
        value = exact32(candidate)
        lower = (value + exact32(candidate - 1)) / 2 if candidate & 0x7FFFFFFF else Fraction(0)
        upper = (value + exact32(candidate + 1)) / 2
        if lower > 0 and compare_sin(lower) > 0:
            candidate -= 1
            continue
        if compare_sin(upper) < 0:
            candidate += 1
            continue
        return candidate | (sign << 31)
    raise ArithmeticError("asinf candidate walk did not converge")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("function", choices=["tan", "asinf"])
    parser.add_argument("words", nargs="+", help="hex input words")
    args = parser.parse_args()
    for text in args.words:
        word = int(text, 16)
        if args.function == "tan":
            print(f"{word:016x} {tan_bits(word):016x}")
        else:
            print(f"{word:08x} {asinf_bits(word):08x}")


if __name__ == "__main__":
    main()
