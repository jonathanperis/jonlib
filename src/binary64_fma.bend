# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Private bounded binary64 FMA. Integer arithmetic only; one final RN-even pack.
# a,b: signed zero or normal E in [-277,127]; c: zero or normal E in [-554,255].
# Reject all other encodings. No consumers, universal FMA or underflow contract.
import Base

type Words is Data:
  Words{high: U32, low: U32}

def Words.high(value: Words) -> U32:
  Words{high, _} = value
  high

def Words.low(value: Words) -> U32:
  Words{_, low} = value
  low

def Words.add(a: Words, b: Words) -> Words:
  Words{ah, +al} = a
  Words{bh, bl} = b
  +low = (al + bl : U32)
  Words{(ah + bh + Bool.to_u32((low < al : U32)) : U32), low}

def Words.shl1(value: Words) -> Words:
  Words{high, +low} = value
  Words{((high << 1n) .|. (low >> 31n) : U32), (low << 1n : U32)}

def Words.shl(count: Nat, value: Words) -> Words:
  match count:
    case 0n: value
    case 1n+rest: Words.shl(rest, Words.shl1(value))

def Words.shr1(value: Words) -> Words:
  Words{+high, low} = value
  Words{(high >> 1n : U32), ((low >> 1n) .|. (high << 31n) : U32)}

type Product is Data:
  Product{high: Words, low: Words}

def Product.add(a: Product, b: Product) -> Product:
  Product{ah, Words{+a1, +a0}} = a
  Product{bh, Words{b1, b0}} = b
  +sum = Words.add(Words{a1, a0}, Words{b1, b0})
  +s1 = Words.high(sum)
  +s0 = Words.low(sum)
  carry = ((s1 < a1) || (U32.is_eq(s1, a1) && (s0 < a0)) : U32)
  Product{Words.add(Words.add(ah, bh), Words{0, Bool.to_u32(carry)}), Words{s1, s0}}

def Product.shl(value: Product) -> Product:
  Product{high, Words{+h, l}} = value
  Product{Words.add(Words.shl1(high), Words{0, (h >> 31n : U32)}), Words.shl1(Words{h, l})}

# 53 exact shift/add iterations in 128 bits; the product occupies at most 106.
def Product.mul(count: Nat, +bits: Words, +value: Product, +acc: Product) -> Product:
  match count:
    case 0n: acc
    case 1n+rest:
      Words{_, low} = bits
      Product.mul(rest, Words.shr1(bits), Product.shl(value),
        Bool.pick(Product, U32.is_ne((low .&. 1 : U32), 0), Product.add(acc, value), acc))

def Product.limbs(value: Product) -> +List<U32>:
  Product{Words{a3, a2}, Words{a1, a0}} = value
  [a0, a1, a2, a3]

# Little-endian 29-U32 magnitudes, in units of 2^-658. Internal list helpers
# require the stated width; checked is the sole supported entry point.
# No low bits are discarded before signed addition/subtraction has completed.
def Magnitude.fit(count: Nat, values: +List<U32>) -> +List<U32>:
  match count values:
    case 0n _: Nil{}
    case 1n+rest Nil{}: Con{0, Magnitude.fit(rest, Nil{})}
    case 1n+rest Con{head, tail}: Con{head, Magnitude.fit(rest, tail)}

def Magnitude.prefix(count: Nat, values: +List<U32>) -> +List<U32>:
  match count:
    case 0n: values
    case 1n+rest: Con{0, Magnitude.prefix(rest, values)}

# shift and back are in 1..31 and sum to 32.
def Magnitude.shift_bits(values: +List<U32>, +shift: Nat, +back: Nat, carry: U32) -> +List<U32>:
  match values:
    case Nil{}: [carry]
    case Con{+head, tail}:
      Con{((head << shift) .|. carry : U32), Magnitude.shift_bits(tail, shift, back, (head >> back : U32))}

def Magnitude.shift_ready(zero: Bool, +shift: U32, values: +List<U32>) -> +List<U32>:
  match zero:
    case True{}: values
    case False{}: Magnitude.shift_bits(values, U32.to_nat(shift), U32.to_nat((32 - shift : U32)), 0)

def Magnitude.align(+shift: U32, values: +List<U32>) -> +List<U32>:
  +bits = (shift .&. 31 : U32)
  Magnitude.fit(29n, Magnitude.prefix(U32.to_nat((shift >> 5n : U32)),
    Magnitude.shift_ready(U32.is_eq(bits, 0), bits, values)))

# Carry/borrow detection is split into two U32 operations; no wider host integer.
def Magnitude.add(a: +List<U32>, b: +List<U32>, carry: U32) -> +List<U32>:
  match a b:
    case Con{+ah, at} Con{bh, bt}:
      +sum = (ah + bh : U32)
      +out = (sum + carry : U32)
      next = Bool.to_u32(((sum < ah) || (out < sum) : U32))
      Con{out, Magnitude.add(at, bt, next)}
    case _ _: Nil{}

def Magnitude.sub(a: +List<U32>, b: +List<U32>, +borrow: U32) -> +List<U32>:
  match a b:
    case Con{+ah, at} Con{+bh, bt}:
      +difference = (ah - bh : U32)
      +out = (difference - borrow : U32)
      next = Bool.to_u32(((ah < bh) || (difference < borrow) : U32))
      Con{out, Magnitude.sub(at, bt, next)}
    case _ _: Nil{}

# Ordering codes: 0 equal, 1 less, 2 greater. Highest differing limb wins.
def Magnitude.order_head(same: Bool, tail_order: U32, +a: U32, +b: U32) -> U32:
  match same:
    case False{}: tail_order
    case True{}: Bool.pick(U32, U32.is_eq(a, b), 0, Bool.pick(U32, (a < b : U32), 1, 2))

def Magnitude.order(a: +List<U32>, b: +List<U32>) -> U32:
  match a b:
    case Con{ah, at} Con{bh, bt}:
      +tail_order = Magnitude.order(at, bt)
      Magnitude.order_head(U32.is_eq(tail_order, 0), tail_order, ah, bh)
    case _ _: 0

type Top is Data:
  Top{found: Bool, index: U32}

def Magnitude.top(values: +List<U32>, +offset: U32, last: Top) -> Top:
  match values:
    case Nil{}: last
    case Con{+head, tail}:
      next = Bool.pick(Top, U32.is_eq(head, 0), last, Top{True{}, (offset + U32.from_nat(U32.log2(head)) : U32)})
      Magnitude.top(tail, (offset + 32 : U32), next)

type Triple is Data:
  Triple{a: U32, b: U32, c: U32}

def Magnitude.first3(values: +List<U32>) -> Triple:
  match values:
    case Con{a, Con{b, Con{c, _}}}: Triple{a, b, c}
    case Con{a, Con{b, Nil{}}}: Triple{a, b, 0}
    case Con{a, Nil{}}: Triple{a, 0, 0}
    case Nil{}: Triple{0, 0, 0}

# Only now, after cancellation, can discarded bits become a sticky bit.
def Magnitude.window_bits(zero: Bool, +bits: U32, sticky: Bool, value: Triple) -> Words:
  match zero:
    case True{}:
      Triple{a, b, _} = value
      Words{b, (a .|. Bool.to_u32(sticky) : U32)}
    case False{}:
      Triple{+a, +b, c} = value
      +shift = U32.to_nat(bits)
      +back = U32.to_nat((32 - bits : U32))
      tail = U32.is_ne((a .&. ((1 << shift) - 1) : U32), 0) || sticky
      Words{((b >> shift) .|. (c << back) : U32),
        ((a >> shift) .|. (b << back) .|. Bool.to_u32(tail) : U32)}

def Magnitude.window(count: Nat, values: +List<U32>, +bits: U32, sticky: Bool) -> Words:
  match count values:
    case 0n _: Magnitude.window_bits(U32.is_eq(bits, 0), bits, sticky, Magnitude.first3(values))
    case 1n+rest Con{head, tail}: Magnitude.window(rest, tail, bits, sticky || U32.is_ne(head, 0))
    case 1n+_ Nil{}: Words{0, Bool.to_u32(sticky)}

def Triple.words(value: Triple) -> Words:
  Triple{a, b, _} = value
  Words{b, a}

def Magnitude.normalize(large: Bool, +top: U32, values: +List<U32>) -> Words:
  match large:
    case True{}:
      +shift = (top - 55 : U32)
      Magnitude.window(U32.to_nat((shift >> 5n : U32)), values, (shift .&. 31 : U32), False{})
    case False{}:
      Words.shl(U32.to_nat((55 - top : U32)), Triple.words(Magnitude.first3(values)))

def pack.carry(carry: Bool, sign: U32, exponent: U32, words: Words) -> Words:
  match carry:
    case False{}:
      Words{h, l} = words
      Words{(sign .|. (exponent << 20n) .|. (h .&. 1048575) : U32), l}
    case True{}:
      +shifted = Words.shr1(words)
      h = Words.high(shifted)
      l = Words.low(shifted)
      Words{(sign .|. ((exponent + 1) << 20n) .|. (h .&. 1048575) : U32), l}

def pack(sign: U32, exponent: U32, value: Words) -> Words:
  Words{+h, +l} = value
  +tail = (l .&. 7 : U32)
  up = ((tail > 4) || (U32.is_eq(tail, 4) && U32.is_ne((l .&. 8 : U32), 0)) : U32)
  +rounded = Words.add(Words{(h >> 3n : U32), ((l >> 3n) .|. (h << 29n) : U32)}, Words{0, Bool.to_u32(up)})
  rh = Words.high(rounded)
  pack.carry((rh >= 2097152 : U32), sign, exponent, rounded)

def finish.top(info: Top, sign: U32, values: +List<U32>) -> Words:
  Top{found, +top} = info
  match found:
    case False{}: Words{sign, 0}
    case True{}: pack(sign, (top + 365 : U32), Magnitude.normalize((top >= 55 : U32), top, values))

def finish(sign: U32, +values: +List<U32>) -> Words:
  finish.top(Magnitude.top(values, 0, Top{False{}, 0}), sign, values)

def combine.opposite(+order: U32, ps: U32, cs: U32, +product: +List<U32>, +addend: +List<U32>) -> Words:
  +less = U32.is_eq(order, 1)
  # Equal magnitudes under opposite signs always cancel to +0.
  sign = Bool.pick(U32, U32.is_eq(order, 0), 0, Bool.pick(U32, less, cs, ps))
  finish(sign, Bool.pick(+List<U32>, less, Magnitude.sub(addend, product, 0), Magnitude.sub(product, addend, 0)))

def combine(same: Bool, ps: U32, cs: U32, +product: +List<U32>, +addend: +List<U32>) -> Words:
  match same:
    case True{}: finish(ps, Magnitude.add(product, addend, 0))
    case False{}: combine.opposite(Magnitude.order(product, addend), ps, cs, product, addend)

def valid(+high: U32, low: U32, minimum: U32, maximum: U32) -> Bool:
  +exponent = ((high >> 20n) .&. 2047 : U32)
  zero = U32.is_eq(((high .&. 2147483647) .|. low : U32), 0)
  zero || ((exponent >= minimum) && (exponent <= maximum) : U32)

def significand(+high: U32, low: U32) -> Words:
  hidden = Bool.pick(U32, U32.is_eq((high .&. 2147483647 : U32), 0), 0, 1048576)
  Words{((high .&. 1048575) .|. hidden : U32), low}

def calculate(+ah: U32, al: U32, +bh: U32, bl: U32, +ch: U32, cl: U32) -> Words:
  +ps = ((ah .^. bh) .&. 2147483648 : U32)
  +cs = (ch .&. 2147483648 : U32)
  +ae = ((ah >> 20n) .&. 2047 : U32)
  +be = ((bh >> 20n) .&. 2047 : U32)
  +ce = ((ch >> 20n) .&. 2047 : U32)
  product_shift = Bool.pick(U32, U32.is_eq(ae, 0) || U32.is_eq(be, 0), 0, (ae + be - 1492 : U32))
  addend_shift = Bool.pick(U32, U32.is_eq(ce, 0), 0, (ce - 417 : U32))
  product = Product.mul(53n, significand(bh, bl), Product{Words{0, 0}, significand(ah, al)}, Product{Words{0, 0}, Words{0, 0}})
  +mantissa = significand(ch, cl)
  mh = Words.high(mantissa)
  ml = Words.low(mantissa)
  combine(U32.is_eq(ps, cs), ps, cs,
    Magnitude.align(product_shift, Product.limbs(product)), Magnitude.align(addend_shift, [ml, mh]))

def checked.valid(accepted: Bool, ah: U32, al: U32, bh: U32, bl: U32, ch: U32, cl: U32) -> Maybe<Words>:
  match accepted:
    case False{}: None{}
    case True{}: Some{calculate(ah, al, bh, bl, ch, cl)}

# Validate all three inputs before entering arithmetic. Unchecked helpers above
# are private implementation details and do not broaden any existing contract.
def checked(+ah: U32, +al: U32, +bh: U32, +bl: U32, +ch: U32, +cl: U32) -> Maybe<Words>:
  checked.valid(valid(ah, al, 746, 1150) && valid(bh, bl, 746, 1150) && valid(ch, cl, 469, 1278),
    ah, al, bh, bl, ch, cl)
