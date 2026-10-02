"""Independent Fraction/ordered-neighbor oracle for the private bounded FMA.

This deliberately does not use the candidate's limbs, lattice accumulator,
normalization, packing, or guard/round/sticky logic.  The only arithmetic here
is exact rational multiplication/addition and a search of ordered IEEE values.
"""
from fractions import Fraction
from functools import lru_cache

SIGN = 1 << 63
FRACTION = (1 << 52) - 1
MAX_FINITE = 0x7fefffffffffffff
OVERFLOW_ENDPOINT = 0x7ff0000000000000
BOUNDS = ((-277, 127), (-277, 127), (-554, 255))


def word(value, width):
    if type(value) is not int or not 0 <= value < (1 << width):
        raise ValueError(f'Expected unsigned {width}-bit integer')
    return value


def power2(exponent):
    return Fraction(1 << exponent) if exponent >= 0 else Fraction(1, 1 << -exponent)


def decode64(high, low):
    bits = (word(high, 32) << 32) | word(low, 32)
    exponent, fraction = (bits >> 52) & 2047, bits & FRACTION
    if exponent == 2047:
        return None
    value = (Fraction(fraction) * power2(-1074) if exponent == 0 else
             Fraction((1 << 52) + fraction) * power2(exponent - 1075))
    return -value if bits & SIGN else value


def in_domain(bits, minimum, maximum):
    word(bits, 64)
    exponent = (bits >> 52) & 2047
    if exponent == 0:
        return bits & ~SIGN == 0
    return minimum <= exponent - 1023 <= maximum


@lru_cache(maxsize=131072)
def positive64(bits):
    word(bits, 64)
    if bits == OVERFLOW_ENDPOINT:
        # Hypothetical next finite endpoint makes the RN-even overflow tie exact.
        return power2(1024)
    if bits > MAX_FINITE:
        raise ValueError('Not a positive finite binary64 encoding or overflow endpoint')
    return decode64(bits >> 32, bits & 0xffffffff)


def nearest64(value, zero_sign=0):
    """Return binary64 bits by rational neighbor search; signed zero is explicit."""
    if type(value) not in (int, Fraction):
        raise ValueError('Expected an exact rational')
    if type(zero_sign) is not int or zero_sign not in (0, SIGN):
        raise ValueError('Expected a binary64 zero sign')
    if not value:
        return zero_sign
    sign = SIGN if value < 0 else 0
    value = abs(value)
    if value >= positive64(OVERFLOW_ENDPOINT):
        return sign | OVERFLOW_ENDPOINT
    left, right = 0, OVERFLOW_ENDPOINT
    while left + 1 < right:
        middle = (left + right) // 2
        if positive64(middle) <= value:
            left = middle
        else:
            right = middle
    lower_distance = value - positive64(left)
    upper_distance = positive64(right) - value
    selected = (left if lower_distance < upper_distance else right
                if upper_distance < lower_distance else left if left % 2 == 0 else right)
    return sign | selected


def checked(ah, al, bh, bl, ch, cl):
    fields = [word(value, 32) for value in (ah, al, bh, bl, ch, cl)]
    bits = [(fields[i] << 32) | fields[i + 1] for i in (0, 2, 4)]
    if not all(in_domain(value, *bounds) for value, bounds in zip(bits, BOUNDS)):
        return None
    a, b, c = [decode64(value >> 32, value & 0xffffffff) for value in bits]
    exact = a * b + c
    # Only two zero terms of the same sign retain -0 under round-to-nearest.
    product_sign = (bits[0] ^ bits[1]) & SIGN
    c_sign = bits[2] & SIGN
    zero_sign = product_sign if not a * b and not c and product_sign == c_sign else 0
    rounded = nearest64(exact, zero_sign)
    return rounded >> 32, rounded & 0xffffffff
