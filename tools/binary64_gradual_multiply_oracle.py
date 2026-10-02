"""Independent exact Fraction/adjacent-neighbor oracle for the private product.

Reuses the reviewed binary64 rational decoder and ordered-neighbor RN search
unchanged. No candidate product limbs, normalization, windows or pack are used.
"""
from binary64_fma_oracle import (FRACTION, SIGN, MAX_FINITE, decode64, in_domain,
                                nearest64, positive64, power2, word)

BOUNDS = ((-277, 0), (-885, 0))
KINDS = {'multiply': 0}


def checked(kind, ah, al, bh, bl):
    if type(kind) is not str or kind not in KINDS:
        raise ValueError('Unknown gradual multiplication operation kind')
    fields = [word(value, 32) for value in (ah, al, bh, bl)]
    bits = [(fields[i] << 32) | fields[i + 1] for i in (0, 2)]
    if not all(in_domain(value, *bounds) for value, bounds in zip(bits, BOUNDS)):
        return None
    a, b = [decode64(value >> 32, value & 0xffffffff) for value in bits]
    rounded = nearest64(a * b, (bits[0] ^ bits[1]) & SIGN)
    return rounded >> 32, rounded & 0xffffffff
