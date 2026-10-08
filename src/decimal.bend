# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Exact C printf "%.Nf" text for F32 values (promoted to double, as varargs
# do): the exact binary value rounded half to even at N decimals, as glibc
# and Apple libc print it. NaN, whose spelling differs between C libraries,
# is None.
import Base

# A 64-bit value as two U32 words.
type W is Data:
  W{hi: U32, lo: U32}

def W.mul10(+w: W) -> W:
  W{+hi, +lo} = w
  +b = ((lo .&. 65535) * 10 : U32)
  +a = ((lo >> 16n) * 10 : U32)
  +low = (b + ((a .&. 65535) << 16n) : U32)
  W{(hi * 10 + (a >> 16n) + Bool.pick(U32, (low < b : U32), 1, 0) : U32), low}

def W.shr(+w: W, +k: U32) -> U32:
  W{+hi, +lo} = w
  Bool.pick(U32, (k >= 32 : U32), (hi >> U32.to_nat((k - 32 : U32)) : U32),
    Bool.pick(U32, U32.is_eq(k, 0), lo, ((hi << U32.to_nat((32 - k : U32))) .|. (lo >> U32.to_nat(k)) : U32)))

def mask(+k: U32) -> U32:
  Bool.pick(U32, (k >= 32 : U32), 4294967295, ((1 << U32.to_nat(k)) - 1 : U32))

def W.low(+w: W, +k: U32) -> W:
  W{+hi, +lo} = w
  Bool.pick(W, (k >= 32 : U32), W{(hi .&. mask((k - 32 : U32)) : U32), lo}, W{0, (lo .&. mask(k) : U32)})

def W.hi(+w: W) -> U32:
  W{hi, _} = w
  hi

def W.lo(+w: W) -> U32:
  W{_, lo} = w
  lo

# 2^(k-1) compared with w (w < 2^k): 0 below, 1 equal, 2 above.
def W.half(+w: W, +k: U32) -> U32:
  +h = (k - 1 : U32)
  +th = Bool.pick(U32, (h >= 32 : U32), (1 << U32.to_nat((h - 32 : U32)) : U32), 0)
  +tl = Bool.pick(U32, (h >= 32 : U32), 0, (1 << U32.to_nat(h) : U32))
  +hi = W.hi(w)
  +lo = W.lo(w)
  Bool.pick(U32, U32.is_eq(hi, th) && U32.is_eq(lo, tl), 1, Bool.pick(U32, (hi > th : U32) || (U32.is_eq(hi, th) && (lo > tl : U32)), 2, 0))

def digits.show(+n: U32) -> String:
  U32.show(n)

def zeros(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+k: "0" ++ zeros(k)

def pad(+text: String, +width: Nat) -> String:
  zeros(Nat.sub(width, String.length(text))) ++ text

# The fraction f / 2^k as n digits (most significant first) and how its
# remainder compares with one half.
type Digits is Data:
  Digits{values: +List<U32>, half: U32}

def Digits.values(+d: Digits) -> +List<U32>:
  Digits{values, _} = d
  values

def Digits.half(+d: Digits) -> U32:
  Digits{_, half} = d
  half

def fraction(n: Nat, +f: W, +k: U32, +acc: +List<U32>) -> Digits:
  match n:
    case 0n: Digits{List.reverse(&2, U32, acc), W.half(f, k)}
    case 1n+m:
      +f10 = W.mul10(f)
      fraction(m, W.low(f10, k), k, Con{W.shr(f10, k), acc})

# Adds one to a digit list (least significant first); the carry out is 1.
type Carried is Data:
  Carried{values: +List<U32>, carry: U32}

def increment.more(carried: Carried) -> Carried:
  match carried:
    case Carried{values, carry}: Carried{Con{0, values}, carry}

def increment(digits: +List<U32>) -> Carried:
  match digits:
    case Nil{}: Carried{Nil{}, 1}
    case Con{+d, +rest}: Bool.pick(Carried, U32.is_eq(d, 9), increment.more(increment(rest)), Carried{Con{(d + 1 : U32), rest}, 0})

def Carried.values(+c: Carried) -> +List<U32>:
  Carried{values, _} = c
  values

def Carried.carry(+c: Carried) -> U32:
  Carried{_, carry} = c
  carry

def text(digits: +List<U32>) -> String:
  match digits:
    case Nil{}: ""
    case Con{d, rest}: U32.show(d) ++ text(rest)

# Base-1e9 limbs (least significant first) of an integer m * 2^e.
def limbs.double(limbs: +List<U32>, +carry: U32) -> +List<U32>:
  match limbs:
    case Nil{}: Bool.pick(+List<U32>, U32.is_eq(carry, 0), [], [carry])
    case Con{limb, rest}:
      +v = (limb * 2 + carry : U32)
      Con{(v % 1000000000 : U32), limbs.double(rest, (v / 1000000000 : U32))}

def limbs.shift(n: Nat, +limbs: +List<U32>) -> +List<U32>:
  match n:
    case 0n: limbs
    case 1n+k: limbs.shift(k, limbs.double(limbs, 0))

def limbs.text(limbs: +List<U32>) -> String:
  match limbs:
    case Nil{}: ""
    case Con{limb, Nil{}}: U32.show(limb)
    case Con{limb, rest}: limbs.text(rest) ++ pad(U32.show(limb), 9n)

def point(+places: Nat, +fraction: String) -> String:
  Bool.pick(String, Nat.is_eq(places, 0n), "", "." ++ fraction)

def last(values: +List<U32>, +previous: U32) -> U32:
  match values:
    case Nil{}: previous
    case Con{value, rest}: last(rest, value)

# |x| = m * 2^-k with m < 2^24: integer part m >> k, fraction rounded.
def small(+m: U32, +k: U32, +places: Nat) -> String:
  +integer = Bool.pick(U32, (k >= 32 : U32), 0, (m >> U32.to_nat(k) : U32))
  +f = Bool.pick(W, (k >= 32 : U32), W{0, m}, W{0, (m .&. mask(k) : U32)})
  +bound = (k > (25 + 4 * U32.from_nat(places)) : U32)
  +digits = Bool.pick(Digits, bound, Digits{[], 0}, fraction(places, f, k, Nil{}))
  +half = Digits.half(digits)
  +padded = Bool.pick(+List<U32>, bound, List.take(&2, U32, [0, 0, 0, 0, 0, 0, 0, 0, 0], places), Digits.values(digits))
  +last = Bool.pick(U32, Nat.is_eq(places, 0n), (integer .&. 1 : U32), (last(padded, 0) .&. 1 : U32))
  +up = U32.is_eq(half, 2) || (U32.is_eq(half, 1) && U32.is_eq(last, 1))
  +rounded = increment(List.reverse(&2, U32, padded))
  +frac = Carried.values(rounded)
  +whole = Bool.pick(U32, up, (integer + Carried.carry(rounded) : U32), integer)
  U32.show(whole) ++ point(places, Bool.pick(String, up, text(List.reverse(&2, U32, frac)), text(padded)))

def magnitude.at(large: Bool, +exponent: U32, +m: U32, +places: Nat) -> String:
  match large:
    case True{}: limbs.text(limbs.shift(U32.to_nat((exponent - 150 : U32)), [m])) ++ point(places, zeros(places))
    case False{}: small(m, (150 - exponent : U32), places)

def magnitude(+exponent: U32, +m: U32, +places: Nat) -> String:
  magnitude.at((exponent >= 150 : U32), exponent, m, places)

def fixed.kind(kind: U32, +sign: String, +exponent: U32, +m: U32, +places: Nat) -> Maybe<String>:
  match kind:
    case 0: Some{sign ++ magnitude(exponent, m, places)}
    case 1: Some{sign ++ "inf"}
    case _: None{}

# "%.<places>f" of the F32 with these bits.
def fixed(+bits: U32, +places: Nat) -> Maybe<String>:
  +exponent = ((bits >> 23n) .&. 255 : U32)
  +fraction = (bits .&. 8388607 : U32)
  +sign = Bool.pick(String, (bits >= 2147483648 : U32), "-", "")
  fixed.kind(Bool.pick(U32, U32.is_eq(exponent, 255), Bool.pick(U32, U32.is_eq(fraction, 0), 1, 2), 0), sign,
    Bool.pick(U32, U32.is_eq(exponent, 0), 1, exponent), Bool.pick(U32, U32.is_eq(exponent, 0), fraction, (fraction .|. 8388608 : U32)), places)
