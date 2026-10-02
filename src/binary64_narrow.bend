# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private finite IEEE binary64 words -> checked binary32 word, nearest/even.
# No F32 arithmetic, scaling, existing consumers or ambient rounding mode.
import Base

type Wide is Data:
  Wide{high: U32, low: U32}

# For unsigned V, jam(n,V) = floor(V/2^n) OR [V mod 2^n != 0].
# The loop uses only one-bit shifts, including across the limb boundary.
def Wide.jam1(value: Wide) -> Wide:
  Wide{+high, +low} = value
  Wide{(high >> 1n : U32), ((low >> 1n) .|. (high << 31n) .|. (low .&. 1) : U32)}

def Wide.jam(count: Nat, value: Wide) -> Wide:
  match count:
    case 0n: value
    case 1n+rest: Wide.jam(rest, Wide.jam1(value))

# The caller retained three low guard/round/sticky bits and high == 0.
def round(+value: U32) -> U32:
  +tail = (value .&. 7 : U32)
  +quotient = (value >> 3n : U32)
  up = ((tail > 4) || (U32.is_eq(tail, 4) && U32.is_ne((quotient .&. 1 : U32), 0)) : U32)
  (quotient + Bool.to_u32(up) : U32)

def rounded.low(value: Wide) -> U32:
  Wide{_, low} = value
  round(low)

def rounded(count: Nat, value: Wide) -> U32:
  rounded.low(Wide.jam(count, value))

def finite.middle(normal: Bool, +exponent: U32, sign: U32, value: Wide) -> U32:
  match normal:
    case True{}:
      # Addition carries a rounded 2^24 through the exponent, even to infinity.
      (sign .|. (((exponent - 897) << 23n) + rounded(26n, value)) : U32)
    case False{}:
      # Units are 2^-149. A rounded 2^23 is already the minimum normal word.
      (sign .|. rounded(U32.to_nat((923 - exponent : U32)), value) : U32)

def finite.range(tiny: Bool, huge: Bool, +exponent: U32, sign: U32, value: Wide) -> U32:
  match tiny huge:
    case True{} _: sign
    case False{} True{}: (sign .|. 2139095040 : U32)
    case False{} False{}: finite.middle((exponent >= 897 : U32), exponent, sign, value)

def checked.special(special: Bool, +exponent: U32, sign: U32, value: Wide) -> Maybe<U32>:
  match special:
    case True{}: None{}
    case False{}:
      Some{finite.range((exponent < 873 : U32), (exponent > 1150 : U32), exponent, sign, value)}

# All 2^64 input words classify deterministically. All finite values are accepted,
# including binary64 subnormals and signed zero. Exponent 2047 is rejected.
# Result bits preserve zero sign, gradual binary32 underflow and signed overflow.
def checked(+high: U32, low: U32) -> Maybe<U32>:
  +exponent = ((high >> 20n) .&. 2047 : U32)
  checked.special(U32.is_eq(exponent, 2047), exponent, (high .&. 2147483648 : U32),
    Wide{((high .&. 1048575) .|. 1048576 : U32), low})
