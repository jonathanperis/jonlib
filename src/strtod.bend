# Original work: zlib, Copyright (c) 2026 Jonathan Peris.
# The binary64 value the C library's strtod (and atof) gives a decimal number
# in JSON's grammar: -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?.
# strtod is correctly rounded (round to nearest, ties to even), so the value
# is decided by exact integer arithmetic: the digits D and the decimal
# exponent e give N/M = D*10^e (N = D*10^e and M = 1, or N = D and
# M = 10^-e); N or M is scaled by a power of two so that the quotient
# Q = floor(N/M) has 54 or 55 bits, Q comes from 55 steps of binary long
# division, and its low one or two bits with the remainder round the top 53.
# Numbers are little-endian lists of 16-bit limbs. None outside the domain:
# another form, more than 19 significant digits (D below 2^64), a decimal
# exponent beyond 60 in magnitude after the fraction digits, or an exponent
# field of more than three digits. Zero keeps its sign.
import Base
import ./binary64_fma.bend as F
import ./binary64_narrow.bend as N

def head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

# limbs*m + carry for m up to 65535.
def big.muladd(limbs: +List<U32>, +m: U32, +carry: U32) -> +List<U32>:
  match limbs:
    case Nil{}: Bool.pick(+List<U32>, U32.is_eq(carry, 0), Nil{}, [carry])
    case Con{+x, rest}: Con{((x * m + carry) .&. 65535 : U32), big.muladd(rest, m, ((x * m + carry) >> 16n : U32))}

def big.times10(n: Nat, +limbs: +List<U32>) -> +List<U32>:
  match n:
    case 0n: limbs
    case 1n+p: big.times10(p, big.muladd(limbs, 10, 0))

def bits16(n: Nat, +x: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+p: Bool.pick(U32, U32.is_eq(x, 0), 0, (1 + bits16(p, (x >> 1n : U32)) : U32))

# The bit length: 16*index + the length of the highest nonzero limb.
def big.bits(limbs: +List<U32>, +index: U32, +best: U32) -> U32:
  match limbs:
    case Nil{}: best
    case Con{+x, rest}: big.bits(rest, (index + 1 : U32), Bool.pick(U32, U32.is_eq(x, 0), best, (16 * index + bits16(16n, x) : U32)))

def big.zeros(n: Nat, +limbs: +List<U32>) -> +List<U32>:
  match n:
    case 0n: limbs
    case 1n+p: Con{0, big.zeros(p, limbs)}

def big.shl.bits(limbs: +List<U32>, +r: Nat, +carry: U32) -> +List<U32>:
  match limbs:
    case Nil{}: Bool.pick(+List<U32>, U32.is_eq(carry, 0), Nil{}, [carry])
    case Con{+x, rest}: Con{(((x << r) .|. carry) .&. 65535 : U32), big.shl.bits(rest, r, (((x << r) .|. carry) >> 16n : U32))}

def big.shl(+limbs: +List<U32>, +s: U32) -> +List<U32>:
  big.zeros(U32.to_nat((s / 16 : U32)), big.shl.bits(limbs, U32.to_nat((s % 16 : U32)), 0))

def big.shr1(limbs: +List<U32>) -> +List<U32>:
  match limbs:
    case Nil{}: Nil{}
    case Con{+x, +rest}: Con{((x >> 1n) .|. ((head(rest) .&. 1) << 15n) : U32), big.shr1(rest)}

# 0 equal, 1 less, 2 greater (the first number against the second).
def order(+higher: U32, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, U32.is_eq(higher, 0), Bool.pick(U32, U32.is_eq(x, y), 0, Bool.pick(U32, (x < y : U32), 1, 2)), higher)

def big.cmp(a: +List<U32>, b: +List<U32>) -> U32:
  match a b:
    case Nil{} Nil{}: 0
    case Con{+x, xs} Nil{}: order(big.cmp(xs, Nil{}), x, 0)
    case Nil{} Con{+y, ys}: order(big.cmp(Nil{}, ys), 0, y)
    case Con{+x, xs} Con{+y, ys}: order(big.cmp(xs, ys), x, y)

# a - b for a >= b.
def big.sub(a: +List<U32>, b: +List<U32>, +borrow: U32) -> +List<U32>:
  match a b:
    case Nil{} _: Nil{}
    case Con{+x, xs} Nil{}: Con{((x + 65536 - borrow) .&. 65535 : U32), big.sub(xs, Nil{}, (1 - ((x + 65536 - borrow) >> 16n) : U32))}
    case Con{+x, xs} Con{+y, ys}: Con{((x + 65536 - y - borrow) .&. 65535 : U32), big.sub(xs, ys, (1 - ((x + 65536 - y - borrow) >> 16n) : U32))}

# The quotient so far (64 bits) and the remainder.
type Division is Data:
  Division{high: U32, low: U32, rest: +List<U32>}

def divide.step(+division: Division, +term: +List<U32>) -> Division:
  Division{+high, +low, +rest} = division
  +reached = Bool.not(U32.is_eq(big.cmp(rest, term), 1))
  Division{((high << 1n) .|. (low >> 31n) : U32), ((low << 1n) .|. Bool.to_u32(reached) : U32), Bool.pick(+List<U32>, reached, big.sub(rest, term, 0), rest)}

# One quotient bit per step, the term halving from divisor*2^(steps - 1).
def divide(n: Nat, +division: Division, +term: +List<U32>) -> Division:
  match n:
    case 0n: division
    case 1n+p: divide(p, divide.step(division, term), big.shr1(term))

def words(valid: Bool, +negative: Bool, +biased: U32, +high: U32, +low: U32) -> Maybe<F.Words>:
  match valid:
    case False{}: None{}
    case True{}: Some{F.Words{((Bool.to_u32(negative) << 31n) .|. (biased << 20n) .|. (high .&. 1048575) : U32), low}}

# The 53-bit significand (high: 21 bits) after rounding: a carry into bit 53
# is 2^52 with the exponent one higher.
def rounded(+negative: Bool, +biased: U32, +high: U32, +low: U32, +up: Bool) -> Maybe<F.Words>:
  +l = (low + Bool.to_u32(up) : U32)
  +h = (high + Bool.to_u32(up && U32.is_eq(low, 4294967295)) : U32)
  +over = U32.is_eq((h >> 21n : U32), 1)
  +exponent = (biased + Bool.to_u32(over) : U32)
  words(((exponent >= 1) && (exponent <= 2046) : U32), negative, exponent, Bool.pick(U32, over, 1048576, h), Bool.pick(U32, over, 0, l))

# A quotient of 55 bits loses two (guard, then a sticky bit with the
# remainder); one of 54 bits loses one.
def finish.wide(wide: Bool, +negative: Bool, +biased: U32, +high: U32, +low: U32, +sticky: Bool) -> Maybe<F.Words>:
  match wide:
    case True{}:
      +h = (high >> 2n : U32)
      +l = ((low >> 2n) .|. (high << 30n) : U32)
      rounded(negative, (biased + 1 : U32), h, l, U32.is_eq(((low >> 1n) .&. 1 : U32), 1) && (sticky || U32.is_eq((low .&. 1 : U32), 1) || U32.is_eq((l .&. 1 : U32), 1)))
    case False{}:
      +h = (high >> 1n : U32)
      +l = ((low >> 1n) .|. (high << 31n) : U32)
      rounded(negative, biased, h, l, U32.is_eq((low .&. 1 : U32), 1) && (sticky || U32.is_eq((l .&. 1 : U32), 1)))

# biased is the exponent field of a 54-bit quotient.
def finish(+negative: Bool, +biased: U32, division: Division) -> Maybe<F.Words>:
  Division{+high, +low, +rest} = division
  finish.wide(U32.is_eq((high >> 22n : U32), 1), negative, biased, high, low, Bool.not(U32.is_eq(big.bits(rest, 0, 0), 0)))

# N/M with s = 54 + bits(M) - bits(N): N*2^s/M (or N/(M*2^-s)) is between
# 2^53 and 2^55, and a 54-bit quotient q is the value q*2^-s, 2^(53 - s) at
# least: the exponent field is 1076 - s.
def quotient(up: Bool, +negative: Bool, +n: +List<U32>, +m: +List<U32>, +shift: U32) -> Maybe<F.Words>:
  match up:
    case True{}: Bool.pick(Maybe<F.Words>, (shift > 1075 : U32), None{}, finish(negative, (1076 - shift : U32), divide(55n, Division{0, 0, big.shl(n, shift)}, big.shl(m, 54))))
    case False{}: finish(negative, (1076 + shift : U32), divide(55n, Division{0, 0, n}, big.shl(m, (shift + 54 : U32))))

def scaled(+negative: Bool, +n: +List<U32>, +m: +List<U32>) -> Maybe<F.Words>:
  +a = (54 + big.bits(m, 0, 0) : U32)
  +b = big.bits(n, 0, 0)
  quotient((a >= b : U32), negative, n, m, Bool.pick(U32, (a >= b : U32), (a - b : U32), (b - a : U32)))

# D*10^e: e is given as its sign and magnitude.
def value(zero: Bool, +negative: Bool, +digits: +List<U32>, +down: Bool, +power: U32) -> Maybe<F.Words>:
  match zero:
    case True{}: Some{F.Words{(Bool.to_u32(negative) << 31n : U32), 0}}
    case False{}:
      Bool.pick(Maybe<F.Words>, down, scaled(negative, digits, big.times10(U32.to_nat(power), [1])), scaled(negative, big.times10(U32.to_nat(power), digits), [1]))

# The scan of a number: where in the grammar it is (0 start, 1 after the
# sign, 2 a leading zero, 3 integer digits, 4 after the point, 5 fraction
# digits, 6 after e, 7 after the exponent's sign, 8 exponent digits, 9 not a
# number), the digits as a number, how many are significant, how many
# followed the point, the exponent field with its sign and its digit count.
type Scan is Data:
  Scan{phase: U32, negative: Bool, digits: +List<U32>, count: U32, fraction: U32, minus: Bool, exponent: U32, seen: U32}

def digit(+byte: U32) -> Bool:
  (byte >= 48 : U32) && (byte <= 57 : U32)

def letter_e(+byte: U32) -> Bool:
  U32.is_eq(byte, 101) || U32.is_eq(byte, 69)

# A digit joins the number; a leading zero is not significant.
def joined(+digits: +List<U32>, +count: U32, +byte: U32) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(count, 0) && U32.is_eq(byte, 48), digits, big.muladd(digits, 10, (byte - 48 : U32)))

def counted(+count: U32, +byte: U32) -> U32:
  Bool.pick(U32, U32.is_eq(count, 0) && U32.is_eq(byte, 48), 0, (count + 1 : U32))

def to(+phase: U32, +scan: Scan) -> Scan:
  Scan{_, +negative, +digits, +count, +fraction, +minus, +exponent, +seen} = scan
  Scan{phase, negative, digits, count, fraction, minus, exponent, seen}

def with_digit(+phase: U32, +scan: Scan, +byte: U32, +after_point: U32) -> Scan:
  Scan{_, +negative, +digits, +count, +fraction, +minus, +exponent, +seen} = scan
  Scan{phase, negative, joined(digits, count, byte), counted(count, byte), (fraction + after_point : U32), minus, exponent, seen}

def with_exponent(+scan: Scan, +byte: U32) -> Scan:
  Scan{_, +negative, +digits, +count, +fraction, +minus, +exponent, +seen} = scan
  Scan{Bool.pick(U32, (seen < 3 : U32), 8, 9), negative, digits, count, fraction, minus, (exponent * 10 + (byte - 48) : U32), (seen + 1 : U32)}

def signed(+scan: Scan, +negative: Bool) -> Scan:
  Scan{_, _, +digits, +count, +fraction, +minus, +exponent, +seen} = scan
  Scan{1, negative, digits, count, fraction, minus, exponent, seen}

def exponent_signed(+scan: Scan, +minus: Bool) -> Scan:
  Scan{_, +negative, +digits, +count, +fraction, _, +exponent, +seen} = scan
  Scan{7, negative, digits, count, fraction, minus, exponent, seen}

# The first digit: a zero stands alone, another digit may be followed by more.
def first(+scan: Scan, +byte: U32) -> Scan:
  Bool.pick(Scan, U32.is_eq(byte, 48), to(2, scan), Bool.pick(Scan, digit(byte), with_digit(3, scan, byte, 0), to(9, scan)))

def point_or_e(+scan: Scan, +byte: U32) -> Scan:
  Bool.pick(Scan, U32.is_eq(byte, 46), to(4, scan), Bool.pick(Scan, letter_e(byte), to(6, scan), to(9, scan)))

def step(phase: U32, +scan: Scan, +byte: U32) -> Scan:
  match phase:
    case 0: Bool.pick(Scan, U32.is_eq(byte, 45), signed(scan, True{}), first(scan, byte))
    case 1: first(scan, byte)
    case 2: point_or_e(scan, byte)
    case 3: Bool.pick(Scan, digit(byte), with_digit(3, scan, byte, 0), point_or_e(scan, byte))
    case 4: Bool.pick(Scan, digit(byte), with_digit(5, scan, byte, 1), to(9, scan))
    case 5: Bool.pick(Scan, digit(byte), with_digit(5, scan, byte, 1), Bool.pick(Scan, letter_e(byte), to(6, scan), to(9, scan)))
    case 6: Bool.pick(Scan, U32.is_eq(byte, 43), exponent_signed(scan, False{}), Bool.pick(Scan, U32.is_eq(byte, 45), exponent_signed(scan, True{}),
      Bool.pick(Scan, digit(byte), with_exponent(scan, byte), to(9, scan))))
    case 7: Bool.pick(Scan, digit(byte), with_exponent(scan, byte), to(9, scan))
    case 8: Bool.pick(Scan, digit(byte), with_exponent(scan, byte), to(9, scan))
    case _: scan

def Scan.phase(+scan: Scan) -> U32:
  Scan{+phase, _, _, _, _, _, _, _} = scan
  phase

def scan(bytes: +List<U32>, +state: Scan) -> Scan:
  match bytes:
    case Nil{}: state
    case Con{+byte, rest}: scan(rest, step(Scan.phase(state), state, byte))

# A number ends on a leading zero, integer digits, fraction digits or
# exponent digits. Its decimal exponent is the field less the fraction
# digits: its direction and magnitude.
def parsed(+state: Scan) -> Maybe<F.Words>:
  Scan{+phase, +negative, +digits, +count, +fraction, +minus, +exponent, _} = state
  +ended = U32.is_eq(phase, 2) || U32.is_eq(phase, 3) || U32.is_eq(phase, 5) || U32.is_eq(phase, 8)
  +down = minus || (fraction > exponent : U32)
  +power = Bool.pick(U32, minus, (exponent + fraction : U32), Bool.pick(U32, (fraction > exponent : U32), (fraction - exponent : U32), (exponent - fraction : U32)))
  Bool.pick(Maybe<F.Words>, ended && (count <= 19 : U32) && (power <= 60 : U32), value(U32.is_eq(count, 0), negative, digits, down, power), None{})

# strtod of the bytes of a JSON number: the binary64 words.
def double(bytes: +List<U32>) -> Maybe<F.Words>:
  parsed(scan(bytes, Scan{0, False{}, Nil{}, 0, 0, False{}, 0, 0}))

def narrowed(value: Maybe<F.Words>) -> Maybe<U32>:
  match value:
    case None{}: None{}
    case Some{F.Words{high, low}}: N.checked(high, low)

# (float)strtod(...): the binary32 word, where the narrowing is defined.
def float(bytes: +List<U32>) -> Maybe<U32>:
  narrowed(double(bytes))
