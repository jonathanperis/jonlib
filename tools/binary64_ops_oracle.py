"""Exact independent oracle for private checked binary64 operations.

Rational arithmetic plus ordered-neighbor search is shared only with the generic
FMA oracle; no candidate multiplication/division limbs or packing are modeled.
Raw encoding helpers are deliberately distinguished from finite numeric equality.
"""
from fractions import Fraction
from binary64_fma_oracle import SIGN, decode64, in_domain, nearest64, power2, word

KINDS = dict(mul=0, div=1, identity=2, promote=3, finite=4, negate=5,
             magnitude=6, equal=7, increment=8, decrement=9, power=10)
MUL_BOUNDS = (-554, 127)
MUL_SUM_BOUNDS = (-833, 127)
DIV_BOUNDS = ((-225, 127), (-149, 127))
BINARY_KINDS = {'mul', 'div', 'magnitude', 'equal'}
SCALAR_KINDS = {'promote', 'power'}
MASK64 = (1 << 64) - 1


def inputs(kind, ah, al, bh=0, bl=0):
    if type(kind) is not str or kind not in KINDS:
        raise ValueError('Unknown binary64 operation kind')
    ah, al, bh, bl = [word(value, 32) for value in (ah, al, bh, bl)]
    if kind not in BINARY_KINDS and (bh or bl):
        raise ValueError('Noncanonical unused input words')
    if kind in SCALAR_KINDS and ah:
        raise ValueError('Noncanonical scalar input high word')
    return (ah << 32) | al, (bh << 32) | bl


def exponent(bits):
    return ((word(bits, 64) >> 52) & 2047) - 1023


def finite(bits):
    return (word(bits, 64) >> 52) & 2047 != 2047


def allowed(kind, a, b):
    """Checked arithmetic domain, evaluated before any zero shortcut."""
    word(a, 64); word(b, 64)
    if kind == 'mul':
        if not in_domain(a, *MUL_BOUNDS) or not in_domain(b, *MUL_BOUNDS):
            return False
        return (not (a & ~SIGN) or not (b & ~SIGN) or
                MUL_SUM_BOUNDS[0] <= exponent(a) + exponent(b) <= MUL_SUM_BOUNDS[1])
    if kind == 'div':
        return (in_domain(a, *DIV_BOUNDS[0]) and in_domain(b, *DIV_BOUNDS[1]) and
                bool(b & ~SIGN) and (not (a & ~SIGN) or exponent(a) <= exponent(b)))
    raise ValueError('Expected checked arithmetic kind')


def decode32(bits):
    """Exact finite IEEE binary32 rational, with no host float conversion."""
    word(bits, 32)
    exp, fraction = (bits >> 23) & 255, bits & ((1 << 23) - 1)
    if exp == 255:
        return None
    value = (Fraction(fraction) * power2(-149) if exp == 0 else
             Fraction((1 << 23) + fraction) * power2(exp - 150))
    return -value if bits >> 31 else value


def checked(kind, ah, al, bh=0, bl=0):
    a, b = inputs(kind, ah, al, bh, bl)
    if kind in ('mul', 'div'):
        if not allowed(kind, a, b):
            return None
        av, bv = decode64(ah, al), decode64(bh, bl)
        exact = av * bv if kind == 'mul' else av / bv
        result = nearest64(exact, (a ^ b) & SIGN)
    elif kind == 'identity':
        if not in_domain(a, -1022, 1023):
            return None
        result = a
    elif kind == 'promote':
        exact = decode32(al)
        if exact is None:
            return None
        result = nearest64(exact, SIGN if al >> 31 else 0)
    elif kind == 'finite':
        if not finite(a):
            return None
        result = a
    elif kind == 'negate':
        result = a ^ SIGN
    elif kind == 'magnitude':
        am, bm = a & ~SIGN, b & ~SIGN
        result = 0 if am == bm else 1 if am < bm else 2
    elif kind == 'equal':
        result = int(finite(a) and finite(b) and
                     decode64(ah, al) == decode64(bh, bl))
    elif kind == 'increment':
        result = (a + 1) & MASK64
    elif kind == 'decrement':
        result = (a - 1) & MASK64
    elif kind == 'power':
        if not 1 <= al <= 2046:
            return None
        result = al << 52
    return result >> 32, result & 0xffffffff


def checked_multiply(ah, al, bh, bl):
    return checked('mul', ah, al, bh, bl)


def checked_divide(ah, al, bh, bl):
    return checked('div', ah, al, bh, bl)
