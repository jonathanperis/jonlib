#!/usr/bin/env python3
"""Exact finite checks for the pinned atan2f bounds; no compilation or repository changes.

The algebraic reduction and error envelopes are in docs/MODERN-ANGLE-BOUNDS.md. This program checks
only finite coefficient claims, candidate necessity sets, and exact underflow vectors.
All logical checks use integers/Fraction, not sampled inputs or floating tolerances.
float.fromhex only decodes exact binary64 hexadecimal constants; the helper below
cross-checks that each decimal-to-rational conversion equals a manual hex decode.
"""
from fractions import Fraction as F
from pathlib import Path
import hashlib
import re

SOURCE_SHA256 = '96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38'
SOURCE_BLOB = '82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4'
if not __debug__:
    raise RuntimeError('Bounds checker requires enabled exact assertions')
data = (Path(__file__).parent / 'reference' / 'modern_atan2f_glibc241.c').read_bytes()
assert hashlib.sha256(data).hexdigest() == SOURCE_SHA256
assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == SOURCE_BLOB

def p(e):
    return F(2) ** e

def hex_fraction(text):
    sign = -1 if text.startswith('-') else 1
    mantissa, exponent = text.lstrip('+-').split('p')
    digits = mantissa[2:]
    whole, _, frac = digits.partition('.')
    exact = sign * F(int(whole + frac, 16)) * p(int(exponent) - 4 * len(frac))
    assert exact == F(float.fromhex(text))
    return exact

def exponent(x):
    x = abs(x)
    assert x
    e = x.numerator.bit_length() - x.denominator.bit_length()
    return e - (x < p(e))

def quantum(x):
    assert x and x.denominator & (x.denominator - 1) == 0
    n = abs(x.numerator)
    return (n & -n).bit_length() - 1 - (x.denominator.bit_length() - 1)

def binary64_exact(x):
    if not x:
        return True
    e = exponent(x)
    return -1022 <= e <= 1023 and quantum(x) >= e - 52

# Independently retained constant inequalities used by the RN-only tiny-branch
# reachability argument. These are finite constant checks, not the whole proof.
def rational_coefficients(name):
    body = re.search(r'static const double ' + name + r'\[\] =\s*\{(.*?)\};', data.decode(), re.S)[1]
    result = [hex_fraction(token) for token in re.findall(r'0x[0-9a-f.]+p[+-]\d+', body)]
    assert len(result) == 7
    return result

cn, cd = rational_coefficients('cn'), rational_coefficients('cd')
assert all(0 < n <= d < 4 for n, d in zip(cn, cd))
assert 0 < cn[1] < cd[1] < 3 and cd[1] - cn[1] < F(1, 2)
assert cn[2] + p(-50) * cn[3] < 4
assert cd[2] + p(-50) * cd[3] < 4

section = data.decode().split('static const double c[32][2] =', 1)[1].split('};', 1)[0]
tokens = re.findall(r'\{\s*([+-]?0x[0-9a-f.]+p[+-]\d+),\s*([+-]?0x[0-9a-f.]+p[+-]\d+)\s*\}', section)
assert len(tokens) == 32
canonical = ''.join(a + ',' + b + '\n' for a, b in tokens).encode('ascii')
c = [tuple(hex_fraction(x) for x in pair) for pair in tokens]
a = [abs(pair[0]) for pair in c]
assert all(c[i][0] * c[i + 1][0] < 0 and a[i] > a[i + 1] for i in range(31))
assert all(x >= p(-23) for x in a)
assert all(a[i] - a[i + 1] >= p(-23) for i in range(31))
assert all(p(-87) <= abs(lo) < p(-55) for _, lo in c)
assert all(quantum(lo) < exponent(hi) - 53 for hi, lo in c)
assert max(p(quantum(lo) + 53) for _, lo in c[:-1]) <= p(-54)

# If the loop's s_i=RN(tl+c[i][1]) equals zero, tl=-c[i][1] exactly.
# FastTwoSum and Sterbenz give h=(th-c_hi)-c_lo and |h|<2^(q(c_lo)+53).
# th-c_hi is an integer multiple of delta=2^(floor(log2 |c_hi|)-53).
# Enumerate a conservative superset of the possible product-high h values.
candidates = []
for i, (hi, lo) in enumerate(c[:-1]):
    bound = p(quantum(lo) + 53)
    delta = p(exponent(hi) - 53)
    max_k = (bound + abs(lo)) // delta + 1
    ratios = []
    for k in range(-int(max_k), int(max_k) + 1):
        h = k * delta - lo
        if 0 < abs(h) < bound and h * hi < 0 and binary64_exact(h):
            ratios.append(h / c[i + 1][0])
    candidates.append(ratios)

assert all(x > 0 for row in candidates for x in row)
assert all(abs(x-y) * 128 > max(x, y)
           for i in range(30) for x in candidates[i] for y in candidates[i+1])
assert all(x < p(-47) for row in candidates for x in row)
gaps = [(abs(x-y)/max(x,y), i) for i in range(30)
        for x in candidates[i] for y in candidates[i+1]]
minimum_gap, minimum_i = min(gaps)

# Exact RN subnormal results for the tiny sign-test multiply. These deliberately
# do not rely on the host floating-point environment or native math library.
def round_even_integer(x):
    sign = -1 if x < 0 else 1
    x = abs(x)
    q, r = divmod(x.numerator, x.denominator)
    return sign * (q + (2*r > x.denominator or (2*r == x.denominator and q & 1)))

coefficient = hex_fraction('-0x1.5555555555555p-2')
underflows = []
for ez, expected in [(-256, 0x1555555555555), (-268, 1), (-269, 0), (-276, 0)]:
    z = p(ez)
    # Both scaling multiplications producing c*z^3 are exact normal binary64.
    correction = coefficient * z**3
    assert binary64_exact(correction)
    exact_product = z * correction
    subnormal_significand = -round_even_integer(exact_product / p(-1074))
    assert subnormal_significand == expected
    word = (1 << 63) | subnormal_significand
    underflows.append((ez, f'{word:016x}'))

print('source_sha256:', SOURCE_SHA256)
print('source_git_blob:', SOURCE_BLOB)
print('canonical_coefficient_tokens_sha256:', hashlib.sha256(canonical).hexdigest())
print('candidate counts:', list(map(len, candidates)))
print('exact adjacent separation > max/128: PASS')
print('minimum separation exact fraction:', minimum_gap)
print('minimum separation adjacent coefficient indices:', minimum_i, minimum_i + 1)
print('coefficient size/sign/gap checks: PASS')
print('rational coefficient RN tiny-reachability inequalities: PASS')
print('tiny sign-test exact result words (z exponent, word):', underflows)
print('This checks finite coefficient facts; read docs/MODERN-ANGLE-BOUNDS.md for algebraic assumptions and remaining gates.')
