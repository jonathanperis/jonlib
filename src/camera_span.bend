# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Binary64 orthographic spans of the screen-space queries in raylib 6.0 rcore.c
# (GetWorldToScreenEx, GetScreenToWorldRayEx): aspect = (double)width/(double)height,
# right = (fovy/2.0)*aspect, then MatrixOrtho's (float)(right - left) and
# (float)right. Altered Bend adaptation; see LICENSES/raylib.txt.
import Base
import ./binary64_fma.bend as W
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as Narrow

def exponent(+high: U32) -> U32:
  ((high >> 20n) .&. 2047 : U32)

# Exact binary64 words of an integer 1 <= value < 2^31.
def integer(+value: U32) -> W.Words:
  +top = U32.from_nat(U32.log2(value))
  +aligned = U32.shln(value, U32.to_nat((31 - top : U32)))
  W.Words{(((1023 + top) << 20n) .|. ((aligned >> 11n) .&. 1048575) : U32), (aligned << 21n : U32)}

def scaled(+shift: U32, quotient: Maybe<W.Words>) -> Maybe<W.Words>:
  match quotient:
    case None{}: None{}
    case Some{W.Words{high, low}}: Some{W.Words{(high + (shift << 20n) : U32), low}}

# The checked divider needs the numerator's binade at or below the
# denominator's: divide by the scaled numerator, then restore the exact power of two.
def divide(+numerator: W.Words, +denominator: W.Words) -> Maybe<W.Words>:
  W.Words{+wh, +wl} = numerator
  W.Words{+hh, +hl} = denominator
  +shift = (U32.max(exponent(wh), exponent(hh)) - exponent(hh) : U32)
  scaled(shift, O.checked_divide((wh - (shift << 20n) : U32), wl, hh, hl))

def aspect(+width: U32, +height: U32) -> Maybe<W.Words>:
  divide(integer(width), integer(height))

# value * 2^step for a signed zero or a normal value that stays normal.
def power(+step: U32, +value: W.Words) -> W.Words:
  W.Words{+high, +low} = value
  Bool.pick(W.Words, U32.is_eq((high .&. 2147483647 : U32), 0) && U32.is_eq(low, 0), W.Words{high, low}, W.Words{(high + (step << 20n) : U32), low})

def halved(+value: W.Words) -> W.Words:
  W.Words{+high, +low} = value
  Bool.pick(W.Words, U32.is_eq((high .&. 2147483647 : U32), 0) && U32.is_eq(low, 0), W.Words{high, low}, W.Words{(high - 1048576 : U32), low})

def multiply(+left: W.Words, +right: W.Words) -> Maybe<W.Words>:
  W.Words{+ah, +al} = left
  W.Words{+bh, +bl} = right
  O.checked_multiply(ah, al, bh, bl)

def narrow(+value: W.Words) -> Maybe<U32>:
  W.Words{+high, +low} = value
  Narrow.checked(high, low)

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# Some((float)(right - left), (float)right) with right = (fovy/2.0)*aspect and
# left = -right, so right - left is exactly 2*right. None when fovy is not
# finite or the product leaves the checked multiplier's domain.
def spans(+fovy: F32, +width: U32, +height: U32) -> Maybe<(F32 & F32)>:
  do Maybe<&1, (F32 & F32)>:
    ratio : W.Words <- aspect(width, height)
    fovy_words : W.Words <- O.checked_promote(F32.bits(fovy))
    +right : W.Words <- multiply(halved(fovy_words), ratio)
    span : U32 <- narrow(power(1, right))
    value : U32 <- narrow(right)
    return (float(span), float(value))
