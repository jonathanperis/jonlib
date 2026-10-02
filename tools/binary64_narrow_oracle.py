"""Independent exact rational neighbor oracle; no candidate packing or jam code."""
from fractions import Fraction
from functools import lru_cache


def word(value, width):
    if type(value) is not int or not 0 <= value < (1 << width):
        raise ValueError(f'Expected unsigned {width}-bit integer')
    return value


def power2(exponent):
    return Fraction(1 << exponent) if exponent >= 0 else Fraction(1, 1 << -exponent)


def decode64(high, low):
    bits = (word(high, 32) << 32) | word(low, 32)
    exponent, fraction = (bits >> 52) & 2047, bits & ((1 << 52) - 1)
    if exponent == 2047:
        return None
    magnitude = (Fraction(fraction) * power2(-1074) if exponent == 0 else
                 Fraction((1 << 52) + fraction) * power2(exponent - 1075))
    return -magnitude if bits >> 63 else magnitude


@lru_cache(maxsize=65536)
def positive32(bits):
    word(bits, 32)
    if bits == 0x7f800000:
        # The hypothetical next finite endpoint supplies IEEE RN overflow's tie.
        return power2(128)
    if bits > 0x7f7fffff:
        raise ValueError('Not a positive finite binary32 word or overflow endpoint')
    exponent, fraction = bits >> 23, bits & 0x7fffff
    return (Fraction(fraction) * power2(-149) if exponent == 0 else
            Fraction((1 << 23) + fraction) * power2(exponent - 150))


def nearest(high, low):
    value = decode64(high, low)
    if value is None:
        return None
    sign = high & 0x80000000
    value = abs(value)
    if value >= positive32(0x7f800000):
        return sign | 0x7f800000
    # Ordered positive binary32 encodings are ordered by rational value.
    left, right = 0, 0x7f800000
    while left + 1 < right:
        middle = (left + right) // 2
        if positive32(middle) <= value:
            left = middle
        else:
            right = middle
    lower_distance = value - positive32(left)
    upper_distance = positive32(right) - value
    selected = (left if lower_distance < upper_distance else right
                if upper_distance < lower_distance else left if left % 2 == 0 else right)
    return sign | selected
