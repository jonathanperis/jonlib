# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private binary64 product with gradual output and one final RN-even rounding.
# a: signed zero or normal E[-277,0]; b: signed zero or normal E[-885,0].
# Nonzero subnormal inputs are rejected. No existing library consumers.
import Base
import ./binary64_fma.bend as F

# In the gradual branch the rounded integer Q counts 2^-1074 quanta.
# Q <= 2^53-2: its raw bits already encode zero, subnormal, or stored exponent 1.
# The window has three guard/round/sticky bits. Do not pre-round to 53 bits.
def gradual(sign: U32, value: F.Words) -> F.Words:
  F.Words{+h, +l} = value
  +tail = (l .&. 7 : U32)
  up = ((tail > 4) || (U32.is_eq(tail, 4) && U32.is_ne((l .&. 8 : U32), 0)) : U32)
  +rounded = F.Words.add(
    F.Words{(h >> 3n : U32), ((l >> 3n) .|. (h << 29n) : U32)},
    F.Words{0, Bool.to_u32(up)})
  F.Words{(sign .|. F.Words.high(rounded) : U32), F.Words.low(rounded)}

# B is the sum of stored exponents. B>=970 here; P has at most 106 bits.
# B<=1023: k=1076-B in 53..106; jam only at the final quantum window.
# B>=1024: exact product is normal; h selects leading product bit 104/105.
def finish(small: Bool, sign: U32, +biased_sum: U32, +product: F.Product) -> F.Words:
  match small:
    case True{}:
      +shift = (1073 - biased_sum : U32)
      gradual(sign, F.Magnitude.window(U32.to_nat((shift >> 5n : U32)),
        F.Product.limbs(product), (shift .&. 31 : U32), False{}))
    case False{}:
      F.Product{F.Words{top, _}, _} = product
      +h = Bool.to_u32(U32.is_ne((top .&. 512 : U32), 0))
      F.pack(sign, (biased_sum - 1023 + h : U32),
        F.Magnitude.window(1n, F.Product.limbs(product), (17 + h : U32), False{}))

# For B<=969, k>=107 and P<2^106<=2^(k-1), strictly below half minsubnormal.
# The same branch handles exact signed zero, after both operands are validated.
def calculate.zero(zero: Bool, sign: U32, +biased_sum: U32, ah: U32, al: U32, bh: U32, bl: U32) -> F.Words:
  match zero:
    case True{}: F.Words{sign, 0}
    case False{}:
      product = F.Product.mul(53n, F.significand(bh, bl),
        F.Product{F.Words{0, 0}, F.significand(ah, al)},
        F.Product{F.Words{0, 0}, F.Words{0, 0}})
      finish((biased_sum <= 1023 : U32), sign, biased_sum, product)

def calculate(+ah: U32, al: U32, +bh: U32, bl: U32) -> F.Words:
  +ae = ((ah >> 20n) .&. 2047 : U32)
  +be = ((bh >> 20n) .&. 2047 : U32)
  +biased_sum = (ae + be : U32)
  sign = ((ah .^. bh) .&. 2147483648 : U32)
  calculate.zero(U32.is_eq(ae, 0) || U32.is_eq(be, 0) || (biased_sum <= 969 : U32),
    sign, biased_sum, ah, al, bh, bl)

def checked.valid(accepted: Bool, ah: U32, al: U32, bh: U32, bl: U32) -> Maybe<F.Words>:
  match accepted:
    case False{}: None{}
    case True{}: Some{calculate(ah, al, bh, bl)}

# Validate both inputs before zero shortcuts, including invalid-with-zero pairs.
# Only this checked boundary establishes the private helper's input contract.
def checked(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<F.Words>:
  checked.valid(F.valid(ah, al, 746, 1023) && F.valid(bh, bl, 138, 1023), ah, al, bh, bl)
