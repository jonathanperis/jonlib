"""Independent Fraction/ordered-neighbor oracle for private bounded add/sub.

The reviewed binary64 decoder and nearest-neighbor search are shared with the
FMA oracle. No candidate limbs, alignment, normalization, or packing are used.
Subtraction flips the right operand's sign only after validating both inputs.
"""
from binary64_fma_oracle import SIGN, decode64, in_domain, nearest64, word

BOUNDS = ((-900, 130), (-900, 130))
KINDS = {'add': 0, 'sub': 1}


def checked(kind, ah, al, bh, bl):
    if type(kind) is not str or kind not in KINDS:
        raise ValueError('Unknown add/sub operation kind')
    fields = [word(value, 32) for value in (ah, al, bh, bl)]
    bits = [(fields[i] << 32) | fields[i + 1] for i in (0, 2)]
    if not all(in_domain(value, *bounds) for value, bounds in zip(bits, BOUNDS)):
        return None
    a, b = [decode64(value >> 32, value & 0xffffffff) for value in bits]
    exact = a + b if kind == 'add' else a - b
    a_sign = bits[0] & SIGN
    b_sign = (bits[1] ^ (SIGN if kind == 'sub' else 0)) & SIGN
    zero_sign = a_sign if not a and not b and a_sign == b_sign else 0
    rounded = nearest64(exact, zero_sign)
    return rounded >> 32, rounded & 0xffffffff


def checked_add(ah, al, bh, bl):
    return checked('add', ah, al, bh, bl)


def checked_sub(ah, al, bh, bl):
    return checked('sub', ah, al, bh, bl)
