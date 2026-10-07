# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image JPEG decoder (baseline and
# progressive, scalar paths: stb's SSE2 kernels are bit-identical to them).
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
#
# C ints are U32 two's-complement words; shifts of signed values are
# arithmetic and coefficients wrap to 16 bits like stb's shorts. The entropy
# reader keeps stb's 32-bit buffer, so markers, padding and the zero bytes
# read past the end of the data decode exactly as stb decodes them.
import Base
import ./codec.bend as C

# -----------------------------------------------------------------------------
# Two's-complement helpers

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# Arithmetic shift right.
def asr(+x: U32, +n: Nat) -> U32:
  Bool.pick(U32, negative(x), (((x .^. 4294967295) >> n) .^. 4294967295 : U32), (x >> n : U32))

def less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

# The 16-bit wrap of (short) casts, sign-extended.
def short(+x: U32) -> U32:
  +low = (x .&. 65535 : U32)
  Bool.pick(U32, (low >= 32768 : U32), (low .|. 4294901760 : U32), low)

def clamp(+x: U32) -> U32:
  Bool.pick(U32, negative(x), 0, Bool.pick(U32, (x > 255 : U32), 255, x))

# -----------------------------------------------------------------------------
# Byte cursor: stb's memory context returns 0 past the end.

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def nth(+values: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, values, U32.to_nat(index)))

def tail(rest: +List<U32>) -> +List<U32>:
  match rest:
    case Con{_, more}: more
    case Nil{}: Nil{}

def at_eof(rest: +List<U32>) -> Bool:
  match rest:
    case Nil{}: True{}
    case Con{_, _}: False{}

def get16(+rest: +List<U32>) -> U32:
  ((head(rest) << 8n) .|. head(tail(rest)) : U32)

def skip(rest: +List<U32>, n: Nat) -> +List<U32>:
  List.drop(&2, U32, rest, n)

# Repeated 0xFF fill bytes.
def fill(rest: +List<U32>) -> +List<U32>:
  match rest:
    case Con{255, more}: fill(more)
    case other: other

# -----------------------------------------------------------------------------
# Entropy-coded bit reader (stbi__grow_buffer_unsafe and friends)

type Bits is Data:
  Bits{buffer: U32, count: U32, marker: U32, nomore: Bool, rest: +List<U32>}

def Bits.fresh(rest: +List<U32>) -> Bits:
  Bits{0, 0, 255, False{}, rest}

type Step is Data:
  Step{bits: Bits, stop: Bool}

def grow.added(+buffer: U32, +count: U32, +marker: U32, +nomore: Bool, +byte: U32, rest: +List<U32>) -> Step:
  +total = (count + 8 : U32)
  Step{Bits{(buffer .|. (byte << U32.to_nat((24 - count : U32))) : U32), total, marker, nomore, rest}, (total > 24 : U32)}

# A 0xFF byte is data only when its fill bytes end in a stuffed zero.
def grow.marker(stuffed: Bool, +buffer: U32, +count: U32, +marker: U32, +code: U32, rest: +List<U32>) -> Step:
  match stuffed:
    case True{}: grow.added(buffer, count, marker, False{}, 255, rest)
    case False{}: Step{Bits{buffer, count, code, True{}, rest}, True{}}

def grow.data(ff: Bool, +buffer: U32, +count: U32, +marker: U32, +byte: U32, +rest: +List<U32>) -> Step:
  match ff:
    case True{}: grow.marker(U32.is_eq(head(fill(rest)), 0), buffer, count, marker, head(fill(rest)), tail(fill(rest)))
    case False{}: grow.added(buffer, count, marker, False{}, byte, rest)

def grow.byte(nomore: Bool, +buffer: U32, +count: U32, +marker: U32, +rest: +List<U32>) -> Step:
  match nomore:
    case True{}: grow.added(buffer, count, marker, True{}, 0, rest)
    case False{}: grow.data(U32.is_eq(head(rest), 255), buffer, count, marker, head(rest), tail(rest))

# One byte of the do-while loop.
def grow.step(bits: Bits) -> Step:
  Bits{buffer, count, marker, nomore, rest} = bits
  grow.byte(nomore, buffer, count, marker, rest)

def grow.loop(n: Nat, step: Step) -> Bits:
  match n step:
    case _ Step{bits, True{}}: bits
    case 0n Step{bits, False{}}: bits
    case 1n+k Step{bits, False{}}: grow.loop(k, grow.step(bits))

def grow(bits: Bits) -> Bits:
  grow.loop(4n, grow.step(bits))

def grow.below(below: Bool, bits: Bits) -> Bits:
  match below:
    case True{}: grow(bits)
    case False{}: bits

def Bits.count(+bits: Bits) -> U32:
  Bits{_, count, _, _, _} = bits
  count

def Bits.buffer(+bits: Bits) -> U32:
  Bits{buffer, _, _, _, _} = bits
  buffer

def Bits.marker(+bits: Bits) -> U32:
  Bits{_, _, marker, _, _} = bits
  marker

def Bits.rest(+bits: Bits) -> +List<U32>:
  Bits{_, _, _, _, rest} = bits
  rest

# Grows the buffer when it holds fewer than `need` bits.
def ensure(+need: U32, +bits: Bits) -> Bits:
  grow.below((Bits.count(bits) < need : U32), bits)

def consume(+n: U32, bits: Bits) -> Bits:
  Bits{buffer, count, marker, nomore, rest} = bits
  Bits{(buffer << U32.to_nat(n) : U32), (count - n : U32), marker, nomore, rest}

type Got is Data:
  Got{value: U32, bits: Bits}

def mask(+n: U32) -> U32:
  (((1 << U32.to_nat(n)) - 1) : U32)

def rotate(+x: U32, +n: U32) -> U32:
  ((x << U32.to_nat(n)) .|. (x >> U32.to_nat((32 - n : U32))) : U32)

def take.bits(+n: U32, +bits: Bits) -> U32:
  (rotate(Bits.buffer(bits), n) .&. mask(n) : U32)

def take.rest(+n: U32, bits: Bits) -> Bits:
  Bits{buffer, count, marker, nomore, rest} = bits
  Bits{(rotate(buffer, n) .&. (mask(n) .^. 4294967295) : U32), (count - n : U32), marker, nomore, rest}

# stbi__jpeg_get_bits: zero when the stream has run out of bits.
def get_bits.ready(enough: Bool, +n: U32, +bits: Bits) -> Got:
  match enough:
    case False{}: Got{0, bits}
    case True{}: Got{take.bits(n, bits), take.rest(n, bits)}

def get_bits(+n: U32, bits: Bits) -> Got:
  +grown = ensure(n, bits)
  get_bits.ready((Bits.count(grown) >= n : U32), n, grown)

# stbi__extend_receive: n bits, sign-extended by the JPEG rule.
def extend.ready(enough: Bool, +n: U32, +bits: Bits) -> Got:
  match enough:
    case False{}: Got{0, bits}
    case True{}:
      +positive = (Bits.buffer(bits) >= 2147483648 : U32)
      +k = take.bits(n, bits)
      Got{Bool.pick(U32, positive, k, (k - mask(n) : U32)), take.rest(n, bits)}

def extend(+n: U32, bits: Bits) -> Got:
  +grown = ensure(n, bits)
  extend.ready((Bits.count(grown) >= n : U32), n, grown)

# stbi__jpeg_get_bit: the top bit (nonzero or zero).
def get_bit(bits: Bits) -> Got:
  get_bits(1, bits)

# -----------------------------------------------------------------------------
# Huffman tables (stbi__build_huffman). Absent is the zeroed table of a stream
# that never defined it: it decodes symbol 0 without consuming bits.

type Huff is Data:
  Absent{}
  Table{bounds: +List<U32>, deltas: +List<U32>, values: +List<U32>}

type Built is Data:
  Built{bounds: +List<U32>, deltas: +List<U32>, valid: Bool}

# Per code length 1..16: one past the last code, and symbol index minus code.
def build(n: Nat, +length: U32, +code: U32, +symbols: U32, counts: +List<U32>, bounds: +List<U32>, deltas: +List<U32>, +valid: Bool) -> Built:
  match n counts:
    case 0n _: Built{List.reverse(&2, U32, bounds), List.reverse(&2, U32, deltas), valid}
    case _ Nil{}: Built{List.reverse(&2, U32, bounds), List.reverse(&2, U32, deltas), valid}
    case 1n+k Con{+count, rest}:
      +last = (code + count : U32)
      +fits = U32.is_eq(count, 0) || ((last - 1) < (1 << U32.to_nat(length)) : U32)
      build(k, (length + 1 : U32), (last << 1n : U32), (symbols + count : U32), rest,
        Con{last, bounds}, Con{(symbols - code : U32), deltas}, valid && fits)

def Huff.built(result: Built, values: +List<U32>) -> Maybe<&2, Huff>:
  match result:
    case Built{bounds, deltas, True{}}: Some{Table{bounds, deltas, values}}
    case Built{_, _, False{}}: None{}

def Huff.build(counts: +List<U32>, values: +List<U32>) -> Maybe<&2, Huff>:
  Huff.built(build(16n, 1, 0, 0, counts, Nil{}, Nil{}, True{}), values)

type Found is Data:
  Missing{}
  Found{length: U32, symbol: U32}

# Canonical decoding: the first length whose code is below its bound. Codes
# longer than `limit` bits are Missing (9 selects stb's fast table).
def search(n: Nat, +length: U32, +limit: U32, +buffer: U32, bounds: +List<U32>, deltas: +List<U32>) -> Found:
  match n bounds deltas:
    case 1n+k Con{bound, more} Con{delta, others}:
      +code = (buffer >> U32.to_nat((32 - length : U32)) : U32)
      Bool.pick(Found, (length > limit : U32), Missing{},
        Bool.pick(Found, (code < bound : U32), Found{length, (code + delta : U32)}, search(k, (length + 1 : U32), limit, buffer, more, others)))
    case _ _ _: Missing{}

def Huff.symbol(found: Found, +values: +List<U32>) -> Found:
  match found:
    case Missing{}: Missing{}
    case Found{length, index}: Found{length, nth(values, index)}

def Huff.lookup(+table: Huff, +limit: U32, +buffer: U32) -> Found:
  match table:
    case Absent{}: Found{0, 0}
    case Table{bounds, deltas, values}: Huff.symbol(search(16n, 1, limit, buffer, bounds, deltas), values)

# stbi__jpeg_huff_decode: 4294967295 for a missing code or too few bits.
def huff.found(found: Found, +bits: Bits) -> Got:
  match found:
    case Missing{}: Got{4294967295, bits}
    case Found{+length, symbol}:
      Bool.pick(Got, (length > Bits.count(bits) : U32), Got{4294967295, bits}, Got{symbol, consume(length, bits)})

def huff.decode(+table: Huff, bits: Bits) -> Got:
  +grown = ensure(16, bits)
  huff.found(Huff.lookup(table, 16, Bits.buffer(grown)), grown)

def failed(+value: U32) -> Bool:
  U32.is_eq(value, 4294967295)

# stbi__build_fast_ac: a code of at most 9 bits whose magnitude also fits in
# 9 bits and whose value fits in -128..127 decodes in one step.
type Fast is Data:
  Slow{}
  Quick{run: U32, total: U32, value: U32}

def fast.value(+magnitude: U32, +raw: U32) -> U32:
  Bool.pick(U32, (raw < (1 << U32.to_nat((magnitude - 1 : U32))) : U32), (raw - mask(magnitude) : U32), raw)

def fast.entry(+length: U32, +symbol: U32, +buffer: U32) -> Fast:
  +magnitude = (symbol .&. 15 : U32)
  +total = (length + magnitude : U32)
  +usable = U32.is_ne(magnitude, 0) && U32.is_ne(length, 0) && (total <= 9 : U32)
  +raw = Bool.pick(U32, usable, ((buffer << U32.to_nat(length)) >> U32.to_nat((32 - Bool.pick(U32, usable, magnitude, 1) : U32)) : U32), 0)
  +value = Bool.pick(U32, usable, fast.value(magnitude, raw), 0)
  Bool.pick(Fast, usable && Bool.not(less(value, (0 - 128 : U32))) && Bool.not(less(127, value)), Quick{(symbol >> 4n : U32), total, value}, Slow{})

def fast.found(found: Found, +buffer: U32) -> Fast:
  match found:
    case Missing{}: Slow{}
    case Found{length, symbol}: fast.entry(length, symbol, buffer)

def fast(+table: Huff, +buffer: U32) -> Fast:
  match table:
    case Absent{}: Slow{}
    case Table{_, _, _}: fast.found(Huff.lookup(table, 9, buffer), buffer)

# -----------------------------------------------------------------------------
# Coefficient blocks

def dezigzag() -> +List<U32>:
  [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
   35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

# Positions past 63 sample 63, as stb's padded table lets corrupt input do.
def zig(+k: U32) -> U32:
  Bool.pick(U32, (k < 64 : U32), nth(dezigzag(), k), 63)

def stored(data: Array<U32>, +index: U32, +value: U32) -> Array<U32>:
  Array.set(U32, data, index, value)

# stbi__addints_valid and stbi__mul2shorts_valid (b is a 0..65535 table value
# or a power of two).
def adds_valid(+a: U32, +b: U32) -> Bool:
  +sum = (a + b : U32)
  Bool.not(U32.is_eq((a >> 31n : U32), (b >> 31n : U32)) && U32.is_ne((sum >> 31n : U32), (a >> 31n : U32)))

def shorts_valid(+a: U32, +b: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(b, 0), True{},
    Bool.pick(Bool, negative(a), Bool.not(less(a, (0 - (32768 / b) : U32))), Bool.not(less((32767 / b : U32), a))))

# The 64 coefficients of one block, decoded from a stream position.
type Block is Type:
  Block{bits: Bits, pred: U32, data: Array<U32>}
  Broken{}

type Ac is Type:
  More{k: U32, bits: Bits, data: Array<U32>}
  Ended{bits: Bits, data: Array<U32>}
  Bad{}

def ac.put(data: Array<U32>, +z: U32, +value: U32, +scale: +List<U32>) -> Array<U32>:
  stored(data, z, short((value * nth(scale, z) : U32)))

def ac.next(going: Bool, +k: U32, bits: Bits, data: Array<U32>) -> Ac:
  match going:
    case True{}: More{k, bits, data}
    case False{}: Ended{bits, data}

def ac.advance(+k: U32, bits: Bits, data: Array<U32>) -> Ac:
  ac.next((k < 64 : U32), k, bits, data)

def ac.quick(bad: Bool, +k: U32, +total: U32, +value: U32, +scale: +List<U32>, +bits: Bits, data: Array<U32>) -> Ac:
  match bad:
    case True{}: Bad{}
    case False{}: ac.advance((k + 1 : U32), consume(total, bits), ac.put(data, zig(k), value, scale))

def ac.value(got: Got, +k: U32, +scale: +List<U32>, data: Array<U32>) -> Ac:
  match got:
    case Got{value, bits}: ac.advance((k + 1 : U32), bits, ac.put(data, zig(k), value, scale))

def ac.zrl(zrl: Bool, +k: U32, bits: Bits, data: Array<U32>) -> Ac:
  match zrl:
    case True{}: ac.advance((k + 16 : U32), bits, data)
    case False{}: Ended{bits, data}

def ac.run(zero: Bool, +rs: U32, +k: U32, +scale: +List<U32>, +bits: Bits, data: Array<U32>) -> Ac:
  match zero:
    case True{}: ac.zrl(U32.is_eq(rs, 240), k, bits, data)
    case False{}: ac.value(extend((rs .&. 15 : U32), bits), (k + (rs >> 4n) : U32), scale, data)

def ac.symbol(bad: Bool, +rs: U32, +k: U32, +scale: +List<U32>, +bits: Bits, data: Array<U32>) -> Ac:
  match bad:
    case True{}: Bad{}
    case False{}: ac.run(U32.is_eq((rs .&. 15 : U32), 0), rs, k, scale, bits, data)

def ac.slow(got: Got, +k: U32, +scale: +List<U32>, data: Array<U32>) -> Ac:
  match got:
    case Got{+rs, bits}: ac.symbol(failed(rs), rs, k, scale, bits, data)

def ac.fast(f: Fast, +k: U32, +table: Huff, +scale: +List<U32>, +bits: Bits, data: Array<U32>) -> Ac:
  match f:
    case Quick{run, +total, value}: ac.quick((total > Bits.count(bits) : U32), (k + run : U32), total, value, scale, bits, data)
    case Slow{}: ac.slow(huff.decode(table, bits), k, scale, data)

# One AC coefficient (or run) of stbi__jpeg_decode_block; `scale` is the
# dequantization table in natural order.
def ac.step(+k: U32, +table: Huff, +scale: +List<U32>, bits: Bits, data: Array<U32>) -> Ac:
  +grown = ensure(16, bits)
  ac.fast(fast(table, Bits.buffer(grown)), k, table, scale, grown, data)

def ac.loop(n: Nat, +table: Huff, +scale: +List<U32>, step: Ac) -> Ac:
  match n step:
    case 1n+m More{k, bits, data}: ac.loop(m, table, scale, ac.step(k, table, scale, bits, data))
    case 0n More{_, bits, data}: Ended{bits, data}
    case _ Ended{bits, data}: Ended{bits, data}
    case _ Bad{}: Bad{}

def block.ac(+dc: U32, ac: Ac) -> Block:
  match ac:
    case Ended{bits, data}: Block{bits, dc, data}
    case More{_, bits, data}: Block{bits, dc, data}
    case Bad{}: Broken{}

def block.store(valid: Bool, +dc: U32, +table: Huff, +scale: +List<U32>, +bits: Bits) -> Block:
  match valid:
    case False{}: Broken{}
    case True{}:
      first = stored(Array.new(U32, 6n, 0), 0, short((dc * head(scale) : U32)))
      block.ac(dc, ac.loop(64n, table, scale, More{1, bits, first}))

def block.value(valid: Bool, +dc: U32, +table: Huff, +scale: +List<U32>, +bits: Bits) -> Block:
  match valid:
    case False{}: Broken{}
    case True{}: block.store(shorts_valid(dc, head(scale)), dc, table, scale, bits)

def block.diff(got: Got, +pred: U32, +table: Huff, +scale: +List<U32>) -> Block:
  match got:
    case Got{+diff, bits}: block.value(adds_valid(pred, diff), (pred + diff : U32), table, scale, bits)

def dc.diff(zero: Bool, +t: U32, bits: Bits) -> Got:
  match zero:
    case True{}: Got{0, bits}
    case False{}: extend(t, bits)

def block.size(bad: Bool, +t: U32, +pred: U32, +table: Huff, +scale: +List<U32>, +bits: Bits) -> Block:
  match bad:
    case True{}: Broken{}
    case False{}: block.diff(dc.diff(U32.is_eq(t, 0), t, bits), pred, table, scale)

def block.dc(got: Got, +pred: U32, +table: Huff, +scale: +List<U32>) -> Block:
  match got:
    case Got{+t, bits}: block.size((t > 15 : U32), t, pred, table, scale, bits)

# stbi__jpeg_decode_block: DC difference, prediction checks, AC coefficients.
def block.base(+dc_table: Huff, +ac_table: Huff, +scale: +List<U32>, +pred: U32, bits: Bits) -> Block:
  block.dc(huff.decode(dc_table, ensure(16, bits)), pred, ac_table, scale)

# -----------------------------------------------------------------------------
# Inverse DCT (stbi__idct_block, integer DCT_ISLOW with stb's constants)

def plus.go(values: List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{value, rest}: plus.go(rest, Con{value, acc})

def plus(values: List<U32>) -> +List<U32>:
  plus.go(values, Nil{})

def rows(n: Nat, +values: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{List.take(&2, U32, values, 8n), rows(k, List.drop(&2, U32, values, 8n))}

def heads(lines: +List<+List<U32>>) -> +List<U32>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: Con{head(line), heads(rest)}

def tails(lines: +List<+List<U32>>) -> +List<+List<U32>>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: Con{tail(line), tails(rest)}

def transpose(n: Nat, +lines: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{heads(lines), transpose(k, tails(lines))}

def flat(lines: +List<+List<U32>>) -> +List<U32>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: List.append(&2, U32, line, flat(rest))

def zeros(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{value, rest}: U32.is_eq(value, 0) && zeros(rest)

type Idct is Data:
  Idct{x0: U32, x1: U32, x2: U32, x3: U32, t0: U32, t1: U32, t2: U32, t3: U32}

# STBI__IDCT_1D over s0..s7.
def core(+s: +List<U32>) -> Idct:
  +a2 = nth(s, 2)
  +a6 = nth(s, 6)
  +p1 = ((a2 + a6) * 2217 : U32)
  +e2 = (p1 + a6 * 4294959729 : U32)
  +e3 = (p1 + a2 * 3135 : U32)
  +e0 = ((nth(s, 0) + nth(s, 4)) * 4096 : U32)
  +e1 = ((nth(s, 0) - nth(s, 4)) * 4096 : U32)
  +o0 = nth(s, 7)
  +o1 = nth(s, 5)
  +o2 = nth(s, 3)
  +o3 = nth(s, 1)
  +q3 = (o0 + o2 : U32)
  +q4 = (o1 + o3 : U32)
  +q1 = (o0 + o3 : U32)
  +q2 = (o1 + o2 : U32)
  +p5 = ((q3 + q4) * 4816 : U32)
  +r1 = (p5 + q1 * 4294963611 : U32)
  +r2 = (p5 + q2 * 4294956799 : U32)
  +r3 = (q3 * 4294959262 : U32)
  +r4 = (q4 * 4294965699 : U32)
  Idct{(e0 + e3 : U32), (e1 + e2 : U32), (e1 - e2 : U32), (e0 - e3 : U32),
    (o0 * 1223 + r1 + r3 : U32), (o1 * 8410 + r2 + r4 : U32), (o2 * 12586 + r2 + r3 : U32), (o3 * 6149 + r1 + r4 : U32)}

def pass1.core(+r: Idct) -> +List<U32>:
  Idct{x0, x1, x2, x3, t0, t1, t2, t3} = r
  +y0 = (x0 + 512 : U32)
  +y1 = (x1 + 512 : U32)
  +y2 = (x2 + 512 : U32)
  +y3 = (x3 + 512 : U32)
  [asr((y0 + t3 : U32), 10n), asr((y1 + t2 : U32), 10n), asr((y2 + t1 : U32), 10n), asr((y3 + t0 : U32), 10n),
   asr((y3 - t0 : U32), 10n), asr((y2 - t1 : U32), 10n), asr((y1 - t2 : U32), 10n), asr((y0 - t3 : U32), 10n)]

def pass1.column(+column: +List<U32>) -> +List<U32>:
  +dc = (head(column) * 4 : U32)
  Bool.pick(+List<U32>, zeros(tail(column)), [dc, dc, dc, dc, dc, dc, dc, dc], pass1.core(core(column)))

def pass2.core(+r: Idct) -> +List<U32>:
  Idct{x0, x1, x2, x3, t0, t1, t2, t3} = r
  +bias = {16842752 : U32}
  +y0 = (x0 + bias : U32)
  +y1 = (x1 + bias : U32)
  +y2 = (x2 + bias : U32)
  +y3 = (x3 + bias : U32)
  [clamp(asr((y0 + t3 : U32), 17n)), clamp(asr((y1 + t2 : U32), 17n)), clamp(asr((y2 + t1 : U32), 17n)), clamp(asr((y3 + t0 : U32), 17n)),
   clamp(asr((y3 - t0 : U32), 17n)), clamp(asr((y2 - t1 : U32), 17n)), clamp(asr((y1 - t2 : U32), 17n)), clamp(asr((y0 - t3 : U32), 17n))]

def pass2.row(+row: +List<U32>) -> +List<U32>:
  pass2.core(core(row))

def map.columns(lines: +List<+List<U32>>) -> +List<+List<U32>>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: Con{pass1.column(line), map.columns(rest)}

def map.rows(lines: +List<+List<U32>>) -> +List<+List<U32>>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: Con{pass2.row(line), map.rows(rest)}

# The 64 output samples of a block (natural-order coefficients), row by row.
def idct.values(+coefficients: +List<U32>) -> +List<U32>:
  flat(map.rows(transpose(8n, map.columns(transpose(8n, rows(8n, coefficients))))))

def idct(data: Array<U32>) -> +List<U32>:
  idct.values(plus(Array.to_list(~U32, data)))

# -----------------------------------------------------------------------------
# Component planes: four arrays, one per frame component.

type Planes is Type:
  Planes{a: Array<U32>, b: Array<U32>, c: Array<U32>, d: Array<U32>}

type Taken is Type:
  Taken{array: Array<U32>, planes: Planes}

def Planes.take.at(n: U32, a: Array<U32>, b: Array<U32>, c: Array<U32>, d: Array<U32>) -> Taken:
  match n:
    case 0: Taken{a, Planes{Array.new(U32, 0n, 0), b, c, d}}
    case 1: Taken{b, Planes{a, Array.new(U32, 0n, 0), c, d}}
    case 2: Taken{c, Planes{a, b, Array.new(U32, 0n, 0), d}}
    case _: Taken{d, Planes{a, b, c, Array.new(U32, 0n, 0)}}

def Planes.take(+n: U32, planes: Planes) -> Taken:
  Planes{a, b, c, d} = planes
  Planes.take.at(n, a, b, c, d)

def Planes.put.at(n: U32, array: Array<U32>, a: Array<U32>, b: Array<U32>, c: Array<U32>, d: Array<U32>) -> Planes:
  match n:
    case 0: Planes{array, b, c, d}
    case 1: Planes{a, array, c, d}
    case 2: Planes{a, b, array, d}
    case _: Planes{a, b, c, array}

def Planes.put(+n: U32, taken: Taken) -> Planes:
  Taken{array, Planes{a, b, c, d}} = taken
  Planes.put.at(n, array, a, b, c, d)

# Writes a block's 8x8 samples at (x, y) of a plane `width` samples wide.
def plane.write(samples: +List<U32>, +x: U32, +y: U32, +width: U32, +i: U32, plane: Array<U32>) -> Array<U32>:
  match samples:
    case Nil{}: plane
    case Con{value, rest}:
      plane.write(rest, x, y, width, (i + 1 : U32), Array.set(U32, plane, ((y + i / 8) * width + x + i % 8 : U32), value))

def plane.block(+n: U32, +x: U32, +y: U32, +width: U32, samples: +List<U32>, taken: Taken) -> Planes:
  Taken{array, rest} = taken
  Planes.put(n, Taken{plane.write(samples, x, y, width, 0, array), rest})

def capacity(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

# -----------------------------------------------------------------------------
# Markers and segments

# A marker and the bytes after it; 255 is stb's STBI__MARKER_none.
type Mark is Data:
  Mark{value: U32, rest: +List<U32>}

def Mark.value(+mark: Mark) -> U32:
  Mark{value, _} = mark
  value

def Mark.rest(+mark: Mark) -> +List<U32>:
  Mark{_, rest} = mark
  rest

# stbi__get_marker: a pending marker, else 0xFF and its fill bytes.
def get_marker(+pending: U32, +rest: +List<U32>) -> Mark:
  Bool.pick(Mark, U32.is_ne(pending, 255), Mark{pending, rest},
    Bool.pick(Mark, U32.is_ne(head(rest), 255), Mark{255, tail(rest)}, Mark{head(fill(tail(rest))), tail(fill(tail(rest)))}))

def restart_marker(+m: U32) -> Bool:
  ((m >= 208) && (m <= 215) : U32)

# stbi__skip_jpeg_junk_at_end: the next marker past junk bytes.
def junk(rest: +List<U32>, +after: Bool) -> Mark:
  match rest:
    case Nil{}: Mark{255, Nil{}}
    case Con{+x, +more}:
      Bool.pick(Mark, after && U32.is_ne(x, 0) && U32.is_ne(x, 255), Mark{x, more}, junk(more, U32.is_eq(x, 255)))

type Tables is Data:
  Tables{dc: +List<Huff>, ac: +List<Huff>, quant: +List<+List<U32>>, restart: U32, jfif: Bool, transform: U32}

def Tables.empty() -> Tables:
  Tables{[Absent{}, Absent{}, Absent{}, Absent{}], [Absent{}, Absent{}, Absent{}, Absent{}],
    [[], [], [], []], 0, False{}, 4294967295}

def replace(-T: Data, values: +List<T>, +index: U32, +value: T) -> +List<T>:
  match values:
    case Nil{}: Nil{}
    case Con{first, +rest}: Bool.pick(+List<T>, U32.is_eq(index, 0), Con{value, rest}, Con{first, replace(T, rest, (index - 1 : U32), value)})

def pick(-T: Data, values: +List<T>, +index: U32, +default: T) -> T:
  match values:
    case Nil{}: default
    case Con{first, rest}: Bool.pick(T, U32.is_eq(index, 0), first, pick(T, rest, (index - 1 : U32), default))

# A segment's result: tables, the bytes after it and whether it was valid.
type Segment is Data:
  Segment{tables: Tables, rest: +List<U32>, valid: Bool}

# DQT: 8- or 16-bit tables in zigzag order, stored in natural order.
def quant.values(n: Nat, +sixteen: Bool, +i: U32, +rest: +List<U32>, table: Array<U32>) -> Array<U32>:
  match n:
    case 0n: table
    case 1n+k:
      +value = Bool.pick(U32, sixteen, get16(rest), head(rest))
      quant.values(k, sixteen, (i + 1 : U32), skip(rest, Bool.pick(Nat, sixteen, 2n, 1n)), Array.set(U32, table, zig(i), value))

def Tables.with_quant(tables: Tables, +t: U32, +values: +List<U32>) -> Tables:
  Tables{dcs, acs, scales, restart, jfif, transform} = tables
  Tables{dcs, acs, replace(+List<U32>, scales, t, values), restart, jfif, transform}

def quant.loop(n: Nat, +length: U32, +tables: Tables, +rest: +List<U32>) -> Segment:
  match n:
    case 0n: Segment{tables, rest, U32.is_eq(length, 0)}
    case 1n+k:
      +q = head(rest)
      +p = (q >> 4n : U32)
      +t = (q .&. 15 : U32)
      +sixteen = U32.is_ne(p, 0)
      +values = plus(Array.to_list(~U32, quant.values(64n, sixteen, 0, tail(rest), Array.new(U32, 6n, 0))))
      Bool.pick(Segment, Bool.not(less(0, length)), Segment{tables, rest, U32.is_eq(length, 0)},
        Bool.pick(Segment, (p > 1 : U32) || (t > 3 : U32), Segment{tables, rest, False{}},
          quant.loop(k, (length - Bool.pick(U32, sixteen, 129, 65) : U32),
            Tables.with_quant(tables, t, values), skip(tail(rest), Bool.pick(Nat, sixteen, 128n, 64n)))))

def sum(values: +List<U32>) -> U32:
  match values:
    case Nil{}: 0
    case Con{value, rest}: (value + sum(rest) : U32)

# DHT: class, index, 16 code counts, then the symbols.
def huff.store(+tc: U32, +th: U32, tables: Tables, +table: Huff) -> Tables:
  Tables{+dcs, +acs, +scales, +restart, +jfif, +transform} = tables
  Bool.pick(Tables, U32.is_eq(tc, 0), Tables{replace(Huff, dcs, th, table), acs, scales, restart, jfif, transform},
    Tables{dcs, replace(Huff, acs, th, table), scales, restart, jfif, transform})

def huff.built.store(built: Maybe<&2, Huff>, +tc: U32, +th: U32, +tables: Tables) -> Maybe<&2, Tables>:
  match built:
    case None{}: None{}
    case Some{table}: Some{huff.store(tc, th, tables, table)}

def huff.stored.tables(stored: Maybe<&2, Tables>, +tables: Tables) -> Tables:
  match stored:
    case None{}: tables
    case Some{updated}: updated

def huff.loop.done(stored: Maybe<&2, Tables>, +rest: +List<U32>, +next: Segment) -> Segment:
  match stored:
    case None{}: Segment{Tables.empty(), rest, False{}}
    case Some{_}: next

def huff.loop(n: Nat, +length: U32, +tables: Tables, +rest: +List<U32>) -> Segment:
  match n:
    case 0n: Segment{tables, rest, U32.is_eq(length, 0)}
    case 1n+k:
      +q = head(rest)
      +tc = (q >> 4n : U32)
      +th = (q .&. 15 : U32)
      +counts = List.take(&2, U32, tail(rest), 16n)
      +count = sum(counts)
      +after = skip(tail(rest), 16n)
      +symbols = List.take(&2, U32, after, U32.to_nat(count))
      +stored = huff.built.store(Huff.build(counts, symbols), tc, th, tables)
      Bool.pick(Segment, Bool.not(less(0, length)), Segment{tables, rest, U32.is_eq(length, 0)},
        Bool.pick(Segment, (tc > 1 : U32) || (th > 3 : U32) || (count > 256 : U32), Segment{tables, rest, False{}},
          huff.loop.done(stored, skip(after, U32.to_nat(count)), huff.loop(k, (length - 17 - count : U32), huff.stored.tables(stored, tables), skip(after, U32.to_nat(count))))))

def app.tag(+tag: +List<U32>, +rest: +List<U32>) -> Bool:
  match tag:
    case Nil{}: True{}
    case Con{+byte, more}: U32.is_eq(head(rest), byte) && app.tag(more, tail(rest))

def Tables.with_app(tables: Tables, +jfif: Bool, +adobe: Bool, +transform: U32) -> Tables:
  Tables{dcs, acs, scales, restart, was, previous} = tables
  Tables{dcs, acs, scales, restart, was || jfif, Bool.pick(U32, adobe, transform, previous)}

def Tables.with_restart(tables: Tables, +restart: U32) -> Tables:
  Tables{dcs, acs, scales, _, jfif, transform} = tables
  Tables{dcs, acs, scales, restart, jfif, transform}

# APPn and COM: JFIF and Adobe tags; the rest is skipped.
def app(+m: U32, +tables: Tables, +rest: +List<U32>) -> Segment:
  +length = (get16(rest) - 2 : U32)
  +body = skip(rest, 2n)
  +jfif = U32.is_eq(m, 224) && Bool.not(less(length, 5)) && app.tag([74, 70, 73, 70, 0], body)
  +adobe = U32.is_eq(m, 238) && Bool.not(less(length, 12)) && app.tag([65, 100, 111, 98, 101, 0], body)
  Bool.pick(Segment, less(length, 0), Segment{tables, rest, False{}},
    Segment{Tables.with_app(tables, jfif, adobe, head(skip(body, 11n))), skip(body, U32.to_nat(length)), True{}})

# stbi__process_marker: DRI, DQT, DHT, APPn and COM; anything else fails.
def segment(+m: U32, +tables: Tables, +rest: +List<U32>) -> Segment:
  Bool.pick(Segment, U32.is_eq(m, 221), Segment{Tables.with_restart(tables, get16(skip(rest, 2n))), skip(rest, 4n), U32.is_eq(get16(rest), 4)},
  Bool.pick(Segment, U32.is_eq(m, 219), quant.loop(5n, (get16(rest) - 2 : U32), tables, skip(rest, 2n)),
  Bool.pick(Segment, U32.is_eq(m, 196), huff.loop(9n, (get16(rest) - 2 : U32), tables, skip(rest, 2n)),
  Bool.pick(Segment, ((m >= 224) && (m <= 239) : U32) || U32.is_eq(m, 254), app(m, tables, rest),
    Segment{tables, rest, False{}}))))

# -----------------------------------------------------------------------------
# Frame (stbi__process_frame_header) and scan headers

type Comp is Data:
  Comp{id: U32, h: U32, v: U32, tq: U32, x: U32, y: U32, w2: U32, h2: U32}

type Frame is Data:
  Frame{progressive: Bool, width: U32, height: U32, comps: +List<Comp>, rgb: U32, hmax: U32, vmax: U32, mcux: U32, mcuy: U32}

# 0 valid, 1 invalid header, 2 dimensions above Jonlib's 4096.
type Framed is Data:
  Framed{frame: Frame, rest: +List<U32>, status: U32}

def Comp.empty() -> Comp:
  Comp{0, 0, 0, 0, 0, 0, 0, 0}

def Comp.h(+comp: Comp) -> U32:
  Comp{_, h, _, _, _, _, _, _} = comp
  h

def Comp.v(+comp: Comp) -> U32:
  Comp{_, _, v, _, _, _, _, _} = comp
  v

def Comp.tq(+comp: Comp) -> U32:
  Comp{_, _, _, tq, _, _, _, _} = comp
  tq

def Comp.x(+comp: Comp) -> U32:
  Comp{_, _, _, _, x, _, _, _} = comp
  x

def Comp.y(+comp: Comp) -> U32:
  Comp{_, _, _, _, _, y, _, _} = comp
  y

def Comp.w2(+comp: Comp) -> U32:
  Comp{_, _, _, _, _, _, w2, _} = comp
  w2

def Comp.h2(+comp: Comp) -> U32:
  Comp{_, _, _, _, _, _, _, h2} = comp
  h2

def frame.raw(n: Nat, +rest: +List<U32>) -> +List<Comp>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +q = head(tail(rest))
      Con{Comp{head(rest), (q >> 4n : U32), (q .&. 15 : U32), head(skip(rest, 2n)), 0, 0, 0, 0}, frame.raw(k, skip(rest, 3n))}

def frame.max.h(comps: +List<Comp>, +best: U32) -> U32:
  match comps:
    case Nil{}: best
    case Con{Comp{_, h, _, _, _, _, _, _}, rest}: frame.max.h(rest, U32.max(h, best))

def frame.max.v(comps: +List<Comp>, +best: U32) -> U32:
  match comps:
    case Nil{}: best
    case Con{Comp{_, _, v, _, _, _, _, _}, rest}: frame.max.v(rest, U32.max(v, best))

def frame.valid(comps: +List<Comp>, +hmax: U32, +vmax: U32) -> Bool:
  match comps:
    case Nil{}: True{}
    case Con{Comp{_, +h, +v, tq, _, _, _, _}, rest}:
      ((h >= 1) && (h <= 4) && (v >= 1) && (v <= 4) && (tq <= 3) : U32) && U32.is_eq((hmax % Bool.pick(U32, U32.is_eq(h, 0), 1, h) : U32), 0)
        && U32.is_eq((vmax % Bool.pick(U32, U32.is_eq(v, 0), 1, v) : U32), 0) && frame.valid(rest, hmax, vmax)

def frame.rgb(comps: +List<Comp>, +i: U32) -> U32:
  match comps:
    case Nil{}: 0
    case Con{Comp{id, _, _, _, _, _, _, _}, rest}:
      (Bool.pick(U32, (i < 3 : U32) && U32.is_eq(id, nth([82, 71, 66], i)), 1, 0) + frame.rgb(rest, (i + 1 : U32)) : U32)

def frame.sized(comps: +List<Comp>, +width: U32, +height: U32, +hmax: U32, +vmax: U32, +mcux: U32, +mcuy: U32) -> +List<Comp>:
  match comps:
    case Nil{}: Nil{}
    case Con{Comp{id, +h, +v, tq, _, _, _, _}, rest}:
      Con{Comp{id, h, v, tq, ((width * h + hmax - 1) / hmax : U32), ((height * v + vmax - 1) / vmax : U32), (mcux * h * 8 : U32), (mcuy * v * 8 : U32)},
        frame.sized(rest, width, height, hmax, vmax, mcux, mcuy)}

def frame(+progressive: Bool, +rest: +List<U32>) -> Framed:
  +length = get16(rest)
  +precision = head(skip(rest, 2n))
  +height = get16(skip(rest, 3n))
  +width = get16(skip(rest, 5n))
  +c = head(skip(rest, 7n))
  +raw = frame.raw(U32.to_nat(Bool.pick(U32, (c <= 4 : U32), c, 0)), skip(rest, 8n))
  +hmax = frame.max.h(raw, 1)
  +vmax = frame.max.v(raw, 1)
  +mcux = ((width + hmax * 8 - 1) / (hmax * 8) : U32)
  +mcuy = ((height + vmax * 8 - 1) / (vmax * 8) : U32)
  +valid = Bool.not(less(length, 11)) && U32.is_eq(precision, 8) && U32.is_ne(height, 0) && U32.is_ne(width, 0)
    && (U32.is_eq(c, 1) || U32.is_eq(c, 3) || U32.is_eq(c, 4)) && U32.is_eq(length, (8 + 3 * c : U32)) && frame.valid(raw, hmax, vmax)
  Framed{Frame{progressive, width, height, frame.sized(raw, width, height, hmax, vmax, mcux, mcuy), Bool.pick(U32, U32.is_eq(c, 3), frame.rgb(raw, 0), 0), hmax, vmax, mcux, mcuy},
    skip(rest, U32.to_nat(length)), Bool.pick(U32, Bool.not(valid), 1, Bool.pick(U32, (width > 4096 : U32) || (height > 4096 : U32), 2, 0))}

type ScanHead is Data:
  ScanHead{order: +List<U32>, selectors: +List<U32>, start: U32, finish: U32, high: U32, low: U32}

type Scanned is Data:
  Scanned{head: ScanHead, rest: +List<U32>, valid: Bool}

# The first component index with this id; 4 when there is none.
def comp.index(comps: +List<Comp>, +id: U32, +i: U32) -> U32:
  match comps:
    case Nil{}: 4
    case Con{Comp{cid, _, _, _, _, _, _, _}, rest}: Bool.pick(U32, U32.is_eq(cid, id), i, comp.index(rest, id, (i + 1 : U32)))

type Picked is Data:
  Picked{order: +List<U32>, selectors: +List<U32>, valid: Bool}

def scan.components(n: Nat, +comps: +List<Comp>, +rest: +List<U32>, +order: +List<U32>, +selectors: +List<U32>, +valid: Bool) -> Picked:
  match n:
    case 0n: Picked{List.reverse(&2, U32, order), selectors, valid}
    case 1n+k:
      +which = comp.index(comps, head(rest), 0)
      +q = head(tail(rest))
      +ok = (which < 4 : U32) && ((q >> 4n) <= 3 : U32) && ((q .&. 15) <= 3 : U32)
      scan.components(k, comps, skip(rest, 2n), Con{which, order}, Bool.pick(+List<U32>, (which < 4 : U32), replace(U32, selectors, which, q), selectors), valid && ok)

def scan.picked(picked: Picked, +progressive: Bool, +count: U32, +length: U32, +rest: +List<U32>) -> Scanned:
  match picked:
    case Picked{order, selectors, ok}:
      +start = head(rest)
      +finish = head(tail(rest))
      +aa = head(skip(rest, 2n))
      +high = (aa >> 4n : U32)
      +low = (aa .&. 15 : U32)
      +bounds = Bool.pick(Bool, progressive, (start <= 63 : U32) && (finish <= 63 : U32) && (start <= finish : U32) && (high <= 13 : U32) && (low <= 13 : U32),
        U32.is_eq(start, 0) && U32.is_eq(high, 0) && U32.is_eq(low, 0))
      Scanned{ScanHead{order, selectors, start, Bool.pick(U32, progressive, finish, 63), high, low}, skip(rest, 3n),
        ok && bounds && U32.is_eq(length, (6 + 2 * count : U32))}

# stbi__process_scan_header (the selectors persist across scans).
def scan.header(+frame: Frame, +selectors: +List<U32>, +rest: +List<U32>) -> Scanned:
  Frame{progressive, _, _, comps, _, _, _, _, _} = frame
  +count = head(skip(rest, 2n))
  +components = List.length(&2, Comp, comps)
  +fits = (count >= 1 : U32) && (count <= 4 : U32) && Nat.is_le(U32.to_nat(count), components)
  Bool.pick(Scanned, Bool.not(fits), Scanned{ScanHead{[], selectors, 0, 0, 0, 0}, rest, False{}},
    scan.picked(scan.components(U32.to_nat(count), comps, skip(rest, 3n), Nil{}, selectors, True{}), progressive, count, get16(rest),
      skip(rest, U32.to_nat((3 + 2 * count : U32)))))

# -----------------------------------------------------------------------------
# Scans: the blocks of a scan as a flat list, each with its plane position
# (baseline, in samples) or block position (progressive), and whether it ends
# a minimum coded unit (where the restart interval counts down).

type Unit is Data:
  Unit{comp: U32, x: U32, y: U32, last: Bool}

def units.row(n: Nat, +comp: U32, +i: U32, +y: U32, +scale: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.row(k, comp, (i + 1 : U32), y, scale, Con{Unit{comp, (i * scale : U32), y, True{}}, acc})

def units.single(n: Nat, +comp: U32, +w: U32, +j: U32, +scale: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.single(k, comp, w, (j + 1 : U32), scale, units.row(U32.to_nat(w), comp, 0, (j * scale : U32), scale, acc))

def units.blocks.row(n: Nat, +comp: U32, +bx: U32, +by: U32, +xx: U32, +h: U32, +scale: U32, +final: Bool, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.blocks.row(k, comp, bx, by, (xx + 1 : U32), h, scale, final,
      Con{Unit{comp, ((bx * h + xx) * scale : U32), by, final && U32.is_eq((xx + 1 : U32), h)}, acc})

def units.blocks(n: Nat, +comp: U32, +bx: U32, +by: U32, +yy: U32, +h: U32, +v: U32, +scale: U32, +final: Bool, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.blocks(k, comp, bx, by, (yy + 1 : U32), h, v, scale, final,
      units.blocks.row(U32.to_nat(h), comp, bx, ((by * v + yy) * scale : U32), 0, h, scale, final && U32.is_eq((yy + 1 : U32), v), acc))

def units.mcu(order: +List<U32>, +comps: +List<Comp>, +bx: U32, +by: U32, +scale: U32, +acc: +List<Unit>) -> +List<Unit>:
  match order:
    case Nil{}: acc
    case Con{+n, +rest}:
      +comp = pick(Comp, comps, n, Comp.empty())
      units.mcu(rest, comps, bx, by, scale, units.blocks(U32.to_nat(Comp.v(comp)), n, bx, by, 0, Comp.h(comp), Comp.v(comp), scale, List.is_empty(&2, U32, rest), acc))

def units.mcus.row(n: Nat, +order: +List<U32>, +comps: +List<Comp>, +i: U32, +j: U32, +scale: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.mcus.row(k, order, comps, (i + 1 : U32), j, scale, units.mcu(order, comps, i, j, scale, acc))

def units.mcus(n: Nat, +order: +List<U32>, +comps: +List<Comp>, +mcux: U32, +j: U32, +scale: U32, +acc: +List<Unit>) -> +List<Unit>:
  match n:
    case 0n: acc
    case 1n+k: units.mcus(k, order, comps, mcux, (j + 1 : U32), scale, units.mcus.row(U32.to_nat(mcux), order, comps, 0, j, scale, acc))

def units(+frame: Frame, +order: +List<U32>, +scale: U32) -> +List<Unit>:
  Frame{_, _, _, comps, _, _, _, mcux, mcuy} = frame
  +n = head(order)
  +comp = pick(Comp, comps, n, Comp.empty())
  +x = Comp.x(comp)
  +y = Comp.y(comp)
  List.reverse(&2, Unit, Bool.pick(+List<Unit>, U32.is_eq(U32.from_nat(List.length(&2, U32, order)), 1),
    units.single(U32.to_nat(((y + 7) >> 3n : U32)), n, ((x + 7) >> 3n : U32), 0, scale, Nil{}),
    units.mcus(U32.to_nat(mcuy), order, comps, mcux, 0, scale, Nil{})))

def Unit.comp(+unit: Unit) -> U32:
  Unit{comp, _, _, _} = unit
  comp

def Unit.x(+unit: Unit) -> U32:
  Unit{_, x, _, _} = unit
  x

def Unit.y(+unit: Unit) -> U32:
  Unit{_, _, y, _} = unit
  y

def Unit.last(+unit: Unit) -> Bool:
  Unit{_, _, _, last} = unit
  last

def Frame.comps(+frame: Frame) -> +List<Comp>:
  Frame{_, _, _, comps, _, _, _, _, _} = frame
  comps

def Frame.progressive(+frame: Frame) -> Bool:
  Frame{progressive, _, _, _, _, _, _, _, _} = frame
  progressive

def Frame.height(+frame: Frame) -> U32:
  Frame{_, _, height, _, _, _, _, _, _} = frame
  height

def Tables.dc(+tables: Tables, +i: U32) -> Huff:
  Tables{dcs, _, _, _, _, _} = tables
  pick(Huff, dcs, i, Absent{})

def Tables.ac(+tables: Tables, +i: U32) -> Huff:
  Tables{_, acs, _, _, _, _} = tables
  pick(Huff, acs, i, Absent{})

def Tables.quant(+tables: Tables, +i: U32) -> +List<U32>:
  Tables{_, _, scales, _, _, _} = tables
  pick(+List<U32>, scales, i, [])

def Tables.restart(+tables: Tables) -> U32:
  Tables{_, _, _, restart, _, _} = tables
  restart

def ScanHead.selectors(+head: ScanHead) -> +List<U32>:
  ScanHead{_, selectors, _, _, _, _} = head
  selectors

def ScanHead.order(+head: ScanHead) -> +List<U32>:
  ScanHead{order, _, _, _, _, _} = head
  order

# -----------------------------------------------------------------------------
# Progressive blocks (stbi__jpeg_decode_block_prog_dc/_ac) on a component's
# coefficient array, 64 entries per block from `base`.

type Prog is Type:
  Prog{bits: Bits, pred: U32, eob: U32, data: Array<U32>}
  ProgBad{}

def zero64(n: Nat, +i: U32, data: Array<U32>) -> Array<U32>:
  match n:
    case 0n: data
    case 1n+k: zero64(k, (i + 1 : U32), Array.set(U32, data, i, 0))

def prog.dc.stored(valid: Bool, +dc: U32, +low: U32, +base: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match valid:
    case False{}: ProgBad{}
    case True{}: Prog{bits, dc, eob, Array.set(U32, data, base, short((dc << U32.to_nat(low) : U32)))}

def prog.dc.value(valid: Bool, +dc: U32, +low: U32, +base: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match valid:
    case False{}: ProgBad{}
    case True{}: prog.dc.stored(shorts_valid(dc, (1 << U32.to_nat(low) : U32)), dc, low, base, eob, bits, data)

def prog.dc.diff(got: Got, +pred: U32, +low: U32, +base: U32, +eob: U32, data: Array<U32>) -> Prog:
  match got:
    case Got{+diff, bits}: prog.dc.value(adds_valid(pred, diff), (pred + diff : U32), low, base, eob, bits, data)

def prog.dc.size(bad: Bool, +t: U32, +pred: U32, +low: U32, +base: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match bad:
    case True{}: ProgBad{}
    case False{}: prog.dc.diff(dc.diff(U32.is_eq(t, 0), t, bits), pred, low, base, eob, data)

def prog.dc.first(got: Got, +pred: U32, +low: U32, +base: U32, +eob: U32, data: Array<U32>) -> Prog:
  match got:
    case Got{+t, bits}: prog.dc.size((t > 15 : U32), t, pred, low, base, eob, bits, data)

def prog.dc.refined(pair: Array<U32> & U32, +add: Bool, +low: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits) -> Prog:
  (data, +value) = pair
  Prog{bits, pred, eob, Array.set(U32, data, base, Bool.pick(U32, add, short((value + (1 << U32.to_nat(low)) : U32)), value))}

def prog.dc.refine(got: Got, +low: U32, +base: U32, +pred: U32, +eob: U32, data: Array<U32>) -> Prog:
  match got:
    case Got{value, bits}: prog.dc.refined(Array.get(U32, data, base), U32.is_ne(value, 0), low, base, pred, eob, bits)

def prog.dc.select(first: Bool, +table: Huff, +low: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match first:
    case True{}: prog.dc.first(huff.decode(table, bits), pred, low, base, eob, zero64(64n, base, data))
    case False{}: prog.dc.refine(get_bit(bits), low, base, pred, eob, data)

# The DC scan of one block; its band must be the DC coefficient alone.
def prog.dc(valid: Bool, +table: Huff, +high: U32, +low: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match valid:
    case False{}: ProgBad{}
    case True{}: prog.dc.select(U32.is_eq(high, 0), table, low, base, pred, eob, ensure(16, bits), data)

# AC first scans: values scaled by 2^low; an end-of-band run skips blocks.
type Pac is Type:
  PMore{k: U32, bits: Bits, data: Array<U32>}
  PEnd{bits: Bits, eob: U32, data: Array<U32>}
  PBad{}

def pac.next(going: Bool, +k: U32, bits: Bits, data: Array<U32>) -> Pac:
  match going:
    case True{}: PMore{k, bits, data}
    case False{}: PEnd{bits, 0, data}

def pac.put(data: Array<U32>, +base: U32, +z: U32, +value: U32, +shift: U32) -> Array<U32>:
  Array.set(U32, data, (base + z : U32), short((value << U32.to_nat(shift) : U32)))

def pac.quick(bad: Bool, +k: U32, +finish: U32, +total: U32, +value: U32, +shift: U32, +base: U32, +bits: Bits, data: Array<U32>) -> Pac:
  match bad:
    case True{}: PBad{}
    case False{}: pac.next(((k + 1) <= finish : U32), (k + 1 : U32), consume(total, bits), pac.put(data, base, zig(k), value, shift))

def pac.value(got: Got, +k: U32, +finish: U32, +shift: U32, +base: U32, data: Array<U32>) -> Pac:
  match got:
    case Got{value, bits}: pac.next(((k + 1) <= finish : U32), (k + 1 : U32), bits, pac.put(data, base, zig(k), value, shift))

def pac.eob(got: Got, +r: U32, data: Array<U32>) -> Pac:
  match got:
    case Got{extra, bits}: PEnd{bits, ((1 << U32.to_nat(r)) + extra - 1 : U32), data}

def pac.bits(zero: Bool, +r: U32, +bits: Bits) -> Got:
  match zero:
    case True{}: Got{0, bits}
    case False{}: get_bits(r, bits)

def pac.zero(run: Bool, +r: U32, +k: U32, +finish: U32, +bits: Bits, data: Array<U32>) -> Pac:
  match run:
    case True{}: pac.eob(pac.bits(U32.is_eq(r, 0), r, bits), r, data)
    case False{}: pac.next(((k + 16) <= finish : U32), (k + 16 : U32), bits, data)

def pac.kind(zero: Bool, +rs: U32, +k: U32, +finish: U32, +shift: U32, +base: U32, +bits: Bits, data: Array<U32>) -> Pac:
  match zero:
    case True{}: pac.zero(((rs >> 4n) < 15 : U32), (rs >> 4n : U32), k, finish, bits, data)
    case False{}: pac.value(extend((rs .&. 15 : U32), bits), (k + (rs >> 4n) : U32), finish, shift, base, data)

def pac.checked(bad: Bool, +rs: U32, +k: U32, +finish: U32, +shift: U32, +base: U32, +bits: Bits, data: Array<U32>) -> Pac:
  match bad:
    case True{}: PBad{}
    case False{}: pac.kind(U32.is_eq((rs .&. 15 : U32), 0), rs, k, finish, shift, base, bits, data)

def pac.slow(got: Got, +k: U32, +finish: U32, +shift: U32, +base: U32, data: Array<U32>) -> Pac:
  match got:
    case Got{+rs, bits}: pac.checked(failed(rs), rs, k, finish, shift, base, bits, data)

def pac.fast(f: Fast, +k: U32, +finish: U32, +table: Huff, +shift: U32, +base: U32, +bits: Bits, data: Array<U32>) -> Pac:
  match f:
    case Quick{run, +total, value}: pac.quick((total > Bits.count(bits) : U32), (k + run : U32), finish, total, value, shift, base, bits, data)
    case Slow{}: pac.slow(huff.decode(table, bits), k, finish, shift, base, data)

def pac.step(+k: U32, +finish: U32, +table: Huff, +shift: U32, +base: U32, bits: Bits, data: Array<U32>) -> Pac:
  +grown = ensure(16, bits)
  pac.fast(fast(table, Bits.buffer(grown)), k, finish, table, shift, base, grown, data)

def pac.loop(n: Nat, +finish: U32, +table: Huff, +shift: U32, +base: U32, step: Pac) -> Pac:
  match n step:
    case 1n+m PMore{k, bits, data}: pac.loop(m, finish, table, shift, base, pac.step(k, finish, table, shift, base, bits, data))
    case 0n PMore{_, bits, data}: PEnd{bits, 0, data}
    case _ other: other

def prog.pac(pac: Pac, +pred: U32) -> Prog:
  match pac:
    case PEnd{bits, eob, data}: Prog{bits, pred, eob, data}
    case PMore{_, bits, data}: Prog{bits, pred, 0, data}
    case PBad{}: ProgBad{}

def prog.ac.first(running: Bool, +table: Huff, +start: U32, +finish: U32, +shift: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match running:
    case True{}: Prog{bits, pred, (eob - 1 : U32), data}
    case False{}: prog.pac(pac.loop(80n, finish, table, shift, base, PMore{start, bits, data}), pred)

# AC refinement. A correction bit raises a nonzero coefficient's magnitude by
# `b` when that bit is not yet set.
type Fix is Type:
  Fix{bits: Bits, data: Array<U32>}

def fix.correct(got: Got, +p: U32, +index: U32, +b: U32, data: Array<U32>) -> Fix:
  match got:
    case Got{value, bits}:
      Fix{bits, Array.set(U32, data, index, Bool.pick(U32, U32.is_ne(value, 0) && U32.is_eq((p .&. b : U32), 0),
        short(Bool.pick(U32, less(0, p), (p + b : U32), (p - b : U32))), p))}

def band.nonzero(nonzero: Bool, +p: U32, +index: U32, +b: U32, +bits: Bits, data: Array<U32>) -> Fix:
  match nonzero:
    case False{}: Fix{bits, data}
    case True{}: fix.correct(get_bit(bits), p, index, b, data)

def band.peek(pair: Array<U32> & U32, +index: U32, +b: U32, +bits: Bits) -> Fix:
  (data, +p) = pair
  band.nonzero(U32.is_ne(p, 0), p, index, b, bits, data)

def band.at(going: Bool, +index: U32, +b: U32, +bits: Bits, data: Array<U32>) -> Fix:
  match going:
    case False{}: Fix{bits, data}
    case True{}: band.peek(Array.get(U32, data, index), index, b, bits)

# Inside an end-of-band run: corrections for the band's nonzero coefficients.
def band(n: Nat, +k: U32, +finish: U32, +base: U32, +b: U32, fix: Fix) -> Fix:
  match n fix:
    case 1n+m Fix{bits, data}: band(m, (k + 1 : U32), finish, base, b, band.at((k <= finish : U32), (base + zig(k) : U32), b, bits, data))
    case 0n other: other

# The walk after a refinement symbol: corrections for nonzero coefficients,
# the new value at the r-th zero, or to the end of the band.
type Inner is Type:
  Inner{k: U32, r: U32, bits: Bits, data: Array<U32>, done: Bool}

def walk.fixed(fix: Fix, +k: U32, +r: U32) -> Inner:
  match fix:
    case Fix{bits, data}: Inner{k, r, bits, data, False{}}

def walk.zero(here: Bool, +index: U32, +k: U32, +r: U32, +s: U32, +bits: Bits, data: Array<U32>) -> Inner:
  match here:
    case True{}: Inner{k, r, bits, Array.set(U32, data, index, s), True{}}
    case False{}: Inner{k, (r - 1 : U32), bits, data, False{}}

def walk.nonzero(nonzero: Bool, +p: U32, +index: U32, +k: U32, +r: U32, +b: U32, +s: U32, +bits: Bits, data: Array<U32>) -> Inner:
  match nonzero:
    case True{}: walk.fixed(fix.correct(get_bit(bits), p, index, b, data), k, r)
    case False{}: walk.zero(U32.is_eq(r, 0), index, k, r, s, bits, data)

def walk.peek(pair: Array<U32> & U32, +index: U32, +k: U32, +r: U32, +b: U32, +s: U32, +bits: Bits) -> Inner:
  (data, +p) = pair
  walk.nonzero(U32.is_ne(p, 0), p, index, k, r, b, s, bits, data)

def walk.at(going: Bool, +k: U32, +r: U32, +base: U32, +b: U32, +s: U32, +bits: Bits, data: Array<U32>) -> Inner:
  match going:
    case False{}: Inner{k, r, bits, data, True{}}
    case True{}: walk.peek(Array.get(U32, data, (base + zig(k) : U32)), (base + zig(k) : U32), (k + 1 : U32), r, b, s, bits)

def walk(n: Nat, +finish: U32, +base: U32, +b: U32, +s: U32, inner: Inner) -> Inner:
  match n inner:
    case 1n+m Inner{+k, r, bits, data, False{}}: walk(m, finish, base, b, s, walk.at((k <= finish : U32), k, r, base, b, s, bits, data))
    case _ other: other

type Ref is Type:
  Ref{k: U32, bits: Bits, eob: U32, data: Array<U32>}
  RefDone{bits: Bits, eob: U32, data: Array<U32>}
  RefBad{}

def ref.next(going: Bool, +k: U32, +eob: U32, bits: Bits, data: Array<U32>) -> Ref:
  match going:
    case True{}: Ref{k, bits, eob, data}
    case False{}: RefDone{bits, eob, data}

def ref.walked(inner: Inner, +finish: U32, +eob: U32) -> Ref:
  match inner:
    case Inner{+k, _, bits, data, _}: ref.next((k <= finish : U32), k, eob, bits, data)

def ref.walk(+k: U32, +r: U32, +s: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, bits: Bits, data: Array<U32>) -> Ref:
  ref.walked(walk(70n, finish, base, b, s, Inner{k, r, bits, data, False{}}), finish, eob)

def ref.run(got: Got, +r: U32, +k: U32, +finish: U32, +base: U32, +b: U32, data: Array<U32>) -> Ref:
  match got:
    case Got{extra, bits}: ref.walk(k, 64, 0, finish, base, b, ((1 << U32.to_nat(r)) - 1 + extra : U32), bits, data)

def ref.eob(run: Bool, +r: U32, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Ref:
  match run:
    case True{}: ref.run(pac.bits(U32.is_eq(r, 0), r, bits), r, k, finish, base, b, data)
    case False{}: ref.walk(k, r, 0, finish, base, b, eob, bits, data)

def ref.sign(got: Got, +r: U32, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, data: Array<U32>) -> Ref:
  match got:
    case Got{value, bits}: ref.walk(k, r, Bool.pick(U32, U32.is_ne(value, 0), b, short((0 - b : U32))), finish, base, b, eob, bits, data)

def ref.one(one: Bool, +r: U32, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Ref:
  match one:
    case False{}: RefBad{}
    case True{}: ref.sign(get_bit(bits), r, k, finish, base, b, eob, data)

def ref.kind(zero: Bool, +rs: U32, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Ref:
  match zero:
    case True{}: ref.eob(((rs >> 4n) < 15 : U32), (rs >> 4n : U32), k, finish, base, b, eob, bits, data)
    case False{}: ref.one(U32.is_eq((rs .&. 15 : U32), 1), (rs >> 4n : U32), k, finish, base, b, eob, bits, data)

def ref.checked(bad: Bool, +rs: U32, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Ref:
  match bad:
    case True{}: RefBad{}
    case False{}: ref.kind(U32.is_eq((rs .&. 15 : U32), 0), rs, k, finish, base, b, eob, bits, data)

def ref.symbol(got: Got, +k: U32, +finish: U32, +base: U32, +b: U32, +eob: U32, data: Array<U32>) -> Ref:
  match got:
    case Got{+rs, bits}: ref.checked(failed(rs), rs, k, finish, base, b, eob, bits, data)

def ref.loop(n: Nat, +finish: U32, +table: Huff, +base: U32, +b: U32, state: Ref) -> Ref:
  match n state:
    case 1n+m Ref{k, bits, eob, data}: ref.loop(m, finish, table, base, b, ref.symbol(huff.decode(table, bits), k, finish, base, b, eob, data))
    case 0n Ref{_, bits, eob, data}: RefDone{bits, eob, data}
    case _ other: other

def prog.ref(ref: Ref, +pred: U32) -> Prog:
  match ref:
    case RefDone{bits, eob, data}: Prog{bits, pred, eob, data}
    case Ref{_, bits, eob, data}: Prog{bits, pred, eob, data}
    case RefBad{}: ProgBad{}

def prog.fix(fix: Fix, +pred: U32, +eob: U32) -> Prog:
  match fix:
    case Fix{bits, data}: Prog{bits, pred, (eob - 1 : U32), data}

def prog.ac.refine(running: Bool, +table: Huff, +start: U32, +finish: U32, +low: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match running:
    case True{}: prog.fix(band(64n, start, finish, base, (1 << U32.to_nat(low) : U32), Fix{bits, data}), pred, eob)
    case False{}: prog.ref(ref.loop(64n, finish, table, base, (1 << U32.to_nat(low) : U32), Ref{start, bits, eob, data}), pred)

def prog.ac(first: Bool, +table: Huff, +start: U32, +finish: U32, +low: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match first:
    case True{}: prog.ac.first(U32.is_ne(eob, 0), table, start, finish, low, base, pred, eob, bits, data)
    case False{}: prog.ac.refine(U32.is_ne(eob, 0), table, start, finish, low, base, pred, eob, bits, data)

# The entropy decoder's state through a scan.
# Stopped: the restart interval ended without a restart marker (stb ends the
# scan there); Partial: blocks of the scan came after that stop.
type Driver is Type:
  Driver{bits: Bits, preds: +List<U32>, todo: U32, eob: U32, planes: Planes}
  Stopped{bits: Bits, planes: Planes}
  Partial{bits: Bits, planes: Planes}
  Failed{}

def interval(+restart: U32) -> U32:
  Bool.pick(U32, U32.is_eq(restart, 0), 2147483647, restart)

# stbi__jpeg_reset.
def Driver.reset(+restart: U32, rest: +List<U32>, planes: Planes) -> Driver:
  Driver{Bits.fresh(rest), [0, 0, 0, 0], interval(restart), 0, planes}

# After the restart interval: a restart marker resets the decoder; anything
# else ends the scan with the data decoded so far.
def countdown.restart(is_restart: Bool, +restart: U32, +bits: Bits, planes: Planes) -> Driver:
  match is_restart:
    case True{}: Driver.reset(restart, Bits.rest(bits), planes)
    case False{}: Stopped{bits, planes}

def countdown.due(due: Bool, +restart: U32, +bits: Bits, +preds: +List<U32>, +todo: U32, +eob: U32, planes: Planes) -> Driver:
  match due:
    case False{}: Driver{bits, preds, todo, eob, planes}
    case True{}: countdown.restart(restart_marker(Bits.marker(ensure(24, bits))), restart, ensure(24, bits), planes)

def countdown(last: Bool, +restart: U32, +bits: Bits, +preds: +List<U32>, +todo: U32, +eob: U32, planes: Planes) -> Driver:
  match last:
    case False{}: Driver{bits, preds, todo, eob, planes}
    case True{}: countdown.due(Bool.not(less(0, (todo - 1 : U32))), restart, bits, preds, (todo - 1 : U32), eob, planes)

def base.placed(block: Block, +n: U32, +x: U32, +y: U32, +last: Bool, +width: U32, +restart: U32, +preds: +List<U32>, +todo: U32, +eob: U32, planes: Planes) -> Driver:
  match block:
    case Broken{}: Failed{}
    case Block{bits, pred, data}:
      countdown(last, restart, bits, replace(U32, preds, n, pred), todo, eob, plane.block(n, x, y, width, idct(data), Planes.take(n, planes)))

# A baseline block: decode, inverse DCT into its plane, count down.
def base.unit(+unit: Unit, +frame: Frame, +tables: Tables, +head: ScanHead, driver: Driver) -> Driver:
  match driver:
    case Driver{bits, +preds, todo, eob, planes}:
      +n = Unit.comp(unit)
      +comp = pick(Comp, Frame.comps(frame), n, Comp.empty())
      +selector = nth(ScanHead.selectors(head), n)
      base.placed(block.base(Tables.dc(tables, (selector >> 4n : U32)), Tables.ac(tables, (selector .&. 15 : U32)), Tables.quant(tables, Comp.tq(comp)), nth(preds, n), bits),
        n, Unit.x(unit), Unit.y(unit), Unit.last(unit), Comp.w2(comp), Tables.restart(tables), preds, todo, eob, planes)
    case Stopped{bits, planes}: Partial{bits, planes}
    case Partial{bits, planes}: Partial{bits, planes}
    case Failed{}: Failed{}

def base.run(units: +List<Unit>, +frame: Frame, +tables: Tables, +head: ScanHead, driver: Driver) -> Driver:
  match units:
    case Nil{}: driver
    case Con{unit, rest}: base.run(rest, frame, tables, head, base.unit(unit, frame, tables, head, driver))

def ScanHead.start(+head: ScanHead) -> U32:
  ScanHead{_, _, start, _, _, _} = head
  start

def ScanHead.finish(+head: ScanHead) -> U32:
  ScanHead{_, _, _, finish, _, _} = head
  finish

def ScanHead.high(+head: ScanHead) -> U32:
  ScanHead{_, _, _, _, high, _} = head
  high

def ScanHead.low(+head: ScanHead) -> U32:
  ScanHead{_, _, _, _, _, low} = head
  low

def prog.placed(prog: Prog, +n: U32, +last: Bool, +restart: U32, +preds: +List<U32>, +todo: U32, rest: Planes) -> Driver:
  match prog:
    case ProgBad{}: Failed{}
    case Prog{bits, pred, eob, data}: countdown(last, restart, bits, replace(U32, preds, n, pred), todo, eob, Planes.put(n, Taken{data, rest}))

# Interleaved progressive scans decode DC coefficients only (stb calls the DC
# decoder for every interleaved block).
def prog.select(dc: Bool, +tables: Tables, +head: ScanHead, +selector: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, data: Array<U32>) -> Prog:
  match dc:
    case True{}: prog.dc(U32.is_eq(ScanHead.finish(head), 0), Tables.dc(tables, (selector >> 4n : U32)), ScanHead.high(head), ScanHead.low(head), base, pred, eob, bits, data)
    case False{}: prog.ac(U32.is_eq(ScanHead.high(head), 0), Tables.ac(tables, (selector .&. 15 : U32)), ScanHead.start(head), ScanHead.finish(head), ScanHead.low(head), base, pred, eob, bits, data)

def prog.block(+dc: Bool, +tables: Tables, +head: ScanHead, +selector: U32, +base: U32, +pred: U32, +eob: U32, +bits: Bits, taken: Taken, +n: U32, +last: Bool, +restart: U32, +preds: +List<U32>, +todo: U32) -> Driver:
  Taken{array, rest} = taken
  prog.placed(prog.select(dc, tables, head, selector, base, pred, eob, bits, array), n, last, restart, preds, todo, rest)

def prog.unit(+unit: Unit, +frame: Frame, +tables: Tables, +head: ScanHead, driver: Driver) -> Driver:
  match driver:
    case Driver{bits, +preds, todo, eob, planes}:
      +n = Unit.comp(unit)
      +comp = pick(Comp, Frame.comps(frame), n, Comp.empty())
      +dc = (U32.from_nat(List.length(&2, U32, ScanHead.order(head))) > 1 : U32) || U32.is_eq(ScanHead.start(head), 0)
      prog.block(dc, tables, head, nth(ScanHead.selectors(head), n), (64 * (Unit.x(unit) + Unit.y(unit) * (Comp.w2(comp) / 8)) : U32),
        nth(preds, n), eob, bits, Planes.take(n, planes), n, Unit.last(unit), Tables.restart(tables), preds, todo)
    case Stopped{bits, planes}: Partial{bits, planes}
    case Partial{bits, planes}: Partial{bits, planes}
    case Failed{}: Failed{}

def prog.run(units: +List<Unit>, +frame: Frame, +tables: Tables, +head: ScanHead, driver: Driver) -> Driver:
  match units:
    case Nil{}: driver
    case Con{unit, rest}: prog.run(rest, frame, tables, head, prog.unit(unit, frame, tables, head, driver))

# -----------------------------------------------------------------------------
# Header and image markers

type Head is Data:
  Head{m: U32, rest: +List<U32>, tables: Tables, skipping: Bool}
  Sof{m: U32, rest: +List<U32>, tables: Tables}
  HeadBad{}

def head.segment(segment: Segment) -> Head:
  match segment:
    case Segment{tables, rest, False{}}: HeadBad{}
    case Segment{tables, +rest, True{}}: Head{Mark.value(get_marker(255, rest)), Mark.rest(get_marker(255, rest)), tables, True{}}

# stbi__decode_jpeg_header after SOI: segments until SOF0/1/2, skipping
# padding between them.
def head.step(+m: U32, +rest: +List<U32>, +tables: Tables, +skipping: Bool) -> Head:
  Bool.pick(Head, skipping && U32.is_eq(m, 255),
    Bool.pick(Head, at_eof(rest), HeadBad{}, Head{Mark.value(get_marker(255, rest)), Mark.rest(get_marker(255, rest)), tables, True{}}),
    Bool.pick(Head, ((m >= 192) && (m <= 194) : U32), Sof{m, rest, tables}, head.segment(segment(m, tables, rest))))

def head.loop(n: Nat, state: Head) -> Head:
  match n state:
    case 1n+k Head{m, rest, tables, skipping}: head.loop(k, head.step(m, rest, tables, skipping))
    case 0n Head{_, _, _, _}: HeadBad{}
    case _ other: other

# The marker loop's state. `written` flags the components whose every block
# a scan has written (baseline) or initialized with a first DC scan
# (progressive): stb leaves other plane and coefficient memory uninitialized.
type Main is Type:
  Main{m: U32, rest: +List<U32>, tables: Tables, selectors: +List<U32>, written: +List<U32>, planes: Planes, coeffs: Planes}
  Finished{tables: Tables, written: +List<U32>, eoi: Bool, planes: Planes, coeffs: Planes}
  Error{kind: U32}

def mark(order: +List<U32>, +written: +List<U32>) -> +List<U32>:
  match order:
    case Nil{}: written
    case Con{n, rest}: mark(rest, replace(U32, written, n, 1))

# After a scan: the pending marker, else the next one past junk, then the
# marker after a restart marker.
def main.next.marker(+mark: Mark, +tables: Tables, +selectors: +List<U32>, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  +final = Bool.pick(Mark, restart_marker(Mark.value(mark)), get_marker(255, Mark.rest(mark)), mark)
  Main{Mark.value(final), Mark.rest(final), tables, selectors, written, planes, coeffs}

def main.after(+pending: U32, +rest: +List<U32>, +tables: Tables, +selectors: +List<U32>, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  +found = Bool.pick(Mark, U32.is_eq(pending, 255), junk(rest, False{}), Mark{pending, rest})
  main.next.marker(get_marker(Mark.value(found), Mark.rest(found)), tables, selectors, written, planes, coeffs)

def main.prog(driver: Driver, +tables: Tables, +head: ScanHead, +written: +List<U32>, planes: Planes) -> Main:
  match driver:
    case Failed{}: Error{3}
    case Driver{+bits, _, _, _, coeffs}:
      main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head),
        Bool.pick(+List<U32>, U32.is_eq(ScanHead.start(head), 0) && U32.is_eq(ScanHead.high(head), 0), mark(ScanHead.order(head), written), written), planes, coeffs)
    case Stopped{+bits, coeffs}:
      main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head),
        Bool.pick(+List<U32>, U32.is_eq(ScanHead.start(head), 0) && U32.is_eq(ScanHead.high(head), 0), mark(ScanHead.order(head), written), written), planes, coeffs)
    case Partial{+bits, coeffs}: main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head), written, planes, coeffs)

def main.base(driver: Driver, +tables: Tables, +head: ScanHead, +written: +List<U32>, coeffs: Planes) -> Main:
  match driver:
    case Failed{}: Error{3}
    case Driver{+bits, _, _, _, planes}: main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head), mark(ScanHead.order(head), written), planes, coeffs)
    case Stopped{+bits, planes}: main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head), mark(ScanHead.order(head), written), planes, coeffs)
    case Partial{+bits, planes}: main.after(Bits.marker(bits), Bits.rest(bits), tables, ScanHead.selectors(head), written, planes, coeffs)

def main.scan(progressive: Bool, +head: ScanHead, +rest: +List<U32>, +frame: Frame, +tables: Tables, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  match progressive:
    case False{}:
      main.base(base.run(units(frame, ScanHead.order(head), 8), frame, tables, head, Driver.reset(Tables.restart(tables), rest, planes)),
        tables, head, written, coeffs)
    case True{}:
      main.prog(prog.run(units(frame, ScanHead.order(head), 1), frame, tables, head, Driver.reset(Tables.restart(tables), rest, coeffs)),
        tables, head, written, planes)

def main.sos(scanned: Scanned, +frame: Frame, +tables: Tables, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  match scanned:
    case Scanned{_, _, False{}}: Error{1}
    case Scanned{+head, rest, True{}}:
      main.scan(Frame.progressive(frame), head, rest, frame, tables, written, planes, coeffs)

def main.segment(segment: Segment, +selectors: +List<U32>, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  match segment:
    case Segment{tables, _, False{}}: Finished{tables, written, False{}, planes, coeffs}
    case Segment{tables, +rest, True{}}: Main{Mark.value(get_marker(255, rest)), Mark.rest(get_marker(255, rest)), tables, selectors, written, planes, coeffs}

def main.dnl(valid: Bool, +rest: +List<U32>, +tables: Tables, +selectors: +List<U32>, +written: +List<U32>, planes: Planes, coeffs: Planes) -> Main:
  match valid:
    case False{}: Error{1}
    case True{}: Main{Mark.value(get_marker(255, rest)), Mark.rest(get_marker(255, rest)), tables, selectors, written, planes, coeffs}

# One marker of stbi__decode_jpeg_image's loop. An invalid segment ends the
# image successfully, as in stb, but without EOI.
def main.step(m: U32, +rest: +List<U32>, +tables: Tables, +selectors: +List<U32>, +written: +List<U32>, planes: Planes, coeffs: Planes, +frame: Frame) -> Main:
  match m:
    case 217: Finished{tables, written, True{}, planes, coeffs}
    case 218: main.sos(scan.header(frame, selectors, rest), frame, tables, written, planes, coeffs)
    case 220: main.dnl(U32.is_eq(get16(rest), 4) && U32.is_eq(get16(skip(rest, 2n)), Frame.height(frame)), skip(rest, 4n), tables, selectors, written, planes, coeffs)
    case _: main.segment(segment(m, tables, rest), selectors, written, planes, coeffs)

def main.loop(n: Nat, +frame: Frame, state: Main) -> Main:
  match n state:
    case 1n+k Main{m, rest, tables, selectors, written, planes, coeffs}: main.loop(k, frame, main.step(m, rest, tables, selectors, written, planes, coeffs, frame))
    case 0n Main{_, _, tables, _, written, planes, coeffs}: Finished{tables, written, False{}, planes, coeffs}
    case _ other: other

# -----------------------------------------------------------------------------
# Upsampling and color conversion (load_jpeg_image)

def div4(+x: U32) -> U32:
  ((x >> 2n) .&. 255 : U32)

def div16(+x: U32) -> U32:
  ((x >> 4n) .&. 255 : U32)

def rs.v2(near: +List<U32>, +far: +List<U32>) -> +List<U32>:
  match near:
    case Nil{}: Nil{}
    case Con{a, rest}: Con{div4((3 * a + head(far) + 2 : U32)), rs.v2(rest, tail(far))}

# stbi__resample_row_h_2; the last pair weights the sample before it by 3.
def rs.h2(values: +List<U32>, +previous: U32) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+x, +rest}:
      Bool.pick(+List<U32>, List.is_empty(&2, U32, rest), [div4((3 * previous + x + 2 : U32)), x],
        Con{div4((3 * x + 2 + previous : U32)), Con{div4((3 * x + 2 + head(rest) : U32)), rs.h2(rest, x)}})

def rs.sums(near: +List<U32>, +far: +List<U32>) -> +List<U32>:
  match near:
    case Nil{}: Nil{}
    case Con{a, rest}: Con{(3 * a + head(far) : U32), rs.sums(rest, tail(far))}

def rs.hv2.go(sums: +List<U32>, +previous: U32) -> +List<U32>:
  match sums:
    case Nil{}: [div4((previous + 2 : U32))]
    case Con{+t, rest}: Con{div16((3 * previous + t + 8 : U32)), Con{div16((3 * t + previous + 8 : U32)), rs.hv2.go(rest, t)}}

def rs.hv2(+sums: +List<U32>) -> +List<U32>:
  Con{div4((head(sums) + 2 : U32)), rs.hv2.go(tail(sums), head(sums))}

def rs.repeat(n: Nat, +x: U32, rest: +List<U32>) -> +List<U32>:
  match n:
    case 0n: rest
    case 1n+k: Con{x, rs.repeat(k, x, rest)}

def rs.generic(values: +List<U32>, +hs: U32) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{x, rest}: rs.repeat(U32.to_nat(hs), x, rs.generic(rest, hs))

# Resampler per expansion: 1x1 as is, 1x2 vertical, 2x1 horizontal, 2x2 both,
# other factors nearest-neighbor.
def resample(+hs: U32, +vs: U32, +near: +List<U32>, +far: +List<U32>, +wide: U32) -> +List<U32>:
  +a = List.take(&2, U32, near, U32.to_nat(wide))
  +b = List.take(&2, U32, far, U32.to_nat(wide))
  Bool.pick(+List<U32>, U32.is_eq(hs, 1) && U32.is_eq(vs, 1), a,
  Bool.pick(+List<U32>, U32.is_eq(hs, 1) && U32.is_eq(vs, 2), rs.v2(a, b),
  Bool.pick(+List<U32>, U32.is_eq(hs, 2) && U32.is_eq(vs, 1), rs.h2(a, head(a)),
  Bool.pick(+List<U32>, U32.is_eq(hs, 2) && U32.is_eq(vs, 2), rs.hv2(rs.sums(a, b)),
    rs.generic(a, hs)))))

# The upsampled rows of one component, one per image row.
def comp.rows(n: Nat, +plane: +List<+List<U32>>, +hs: U32, +vs: U32, +wide: U32, +cy: U32, +ystep: U32, +ypos: U32, +line0: U32, +line1: U32, +acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n: List.reverse(&2, +List<U32>, acc)
    case 1n+k:
      +bottom = (ystep >= (vs >> 1n) : U32)
      +near = pick(+List<U32>, plane, Bool.pick(U32, bottom, line1, line0), [])
      +far = pick(+List<U32>, plane, Bool.pick(U32, bottom, line0, line1), [])
      +next = (ystep + 1 : U32)
      +wrap = (next >= vs : U32)
      +position = Bool.pick(U32, wrap, (ypos + 1 : U32), ypos)
      comp.rows(k, plane, hs, vs, wide, cy, Bool.pick(U32, wrap, 0, next), position, Bool.pick(U32, wrap, line1, line0),
        Bool.pick(U32, wrap && (position < cy : U32), (line1 + 1 : U32), line1), Con{resample(hs, vs, near, far, wide), acc})

def plane.rows(n: Nat, +width: U32, +values: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{List.take(&2, U32, values, U32.to_nat(width)), plane.rows(k, width, List.drop(&2, U32, values, U32.to_nat(width)))}

def comp.output(+frame: Frame, +comp: Comp, plane: Array<U32>) -> +List<+List<U32>>:
  Frame{_, width, height, _, _, hmax, vmax, _, _} = frame
  +hs = (hmax / Comp.h(comp) : U32)
  +vs = (vmax / Comp.v(comp) : U32)
  +rows = plane.rows(U32.to_nat(Comp.h2(comp)), Comp.w2(comp), plus(Array.to_list(~U32, plane)))
  comp.rows(U32.to_nat(height), rows, hs, vs, ((width + hs - 1) / hs : U32), Comp.y(comp), (vs >> 1n : U32), 0, 0, 0, Nil{})

def blinn(+x: U32, +y: U32) -> U32:
  +t = (x * y + 128 : U32)
  ((t + (t >> 8n)) >> 8n : U32)

type Rgb is Data:
  Rgb{r: U32, g: U32, b: U32}

# stbi__YCbCr_to_RGB_row's fixed-point conversion.
def ycc(+y: U32, +cb: U32, +cr: U32) -> Rgb:
  +fixed = ((y << 20n) + 524288 : U32)
  +dr = (cr - 128 : U32)
  +db = (cb - 128 : U32)
  Rgb{clamp(asr((fixed + dr * 1470208 : U32), 20n)),
    clamp(asr((fixed + dr * 4294218496 + ((db * 4294606336) .&. 4294901760) : U32), 20n)),
    clamp(asr((fixed + db * 1858048 : U32), 20n))}

def word(+r: U32, +g: U32, +b: U32) -> U32:
  ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. 255 : U32)

def word.rgb(+rgb: Rgb) -> U32:
  Rgb{r, g, b} = rgb
  word(r, g, b)

def word.ycck(+rgb: Rgb, +m: U32) -> U32:
  Rgb{r, g, b} = rgb
  word(blinn((255 - r : U32), m), blinn((255 - g : U32), m), blinn((255 - b : U32), m))

# Color modes: 1 gray, 2 RGB, 3 YCbCr, 4 CMYK, 5 YCCK.
def pixel(+mode: U32, +c0: U32, +c1: U32, +c2: U32, +c3: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mode, 1), word(c0, c0, c0),
  Bool.pick(U32, U32.is_eq(mode, 2), word(c0, c1, c2),
  Bool.pick(U32, U32.is_eq(mode, 4), word(blinn(c0, c3), blinn(c1, c3), blinn(c2, c3)),
  Bool.pick(U32, U32.is_eq(mode, 5), word.ycck(ycc(c0, c1, c2), c3), word.rgb(ycc(c0, c1, c2))))))

def pixels.row(n: Nat, +mode: U32, +r0: +List<U32>, +r1: +List<U32>, +r2: +List<U32>, +r3: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: pixels.row(k, mode, tail(r0), tail(r1), tail(r2), tail(r3), Con{pixel(mode, head(r0), head(r1), head(r2), head(r3)), acc})

def lines.tail(lines: +List<+List<U32>>) -> +List<+List<U32>>:
  match lines:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def pixels(n: Nat, +width: U32, +mode: U32, +c0: +List<+List<U32>>, +c1: +List<+List<U32>>, +c2: +List<+List<U32>>, +c3: +List<+List<U32>>, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      pixels(k, width, mode, lines.tail(c0), lines.tail(c1), lines.tail(c2), lines.tail(c3),
        pixels.row(U32.to_nat(width), mode, pick(+List<U32>, c0, 0, []), pick(+List<U32>, c1, 0, []), pick(+List<U32>, c2, 0, []), pick(+List<U32>, c3, 0, []), acc))

def fill.array(values: +List<U32>, +i: U32, array: Array<U32>) -> Array<U32>:
  match values:
    case Nil{}: array
    case Con{value, rest}: fill.array(rest, (i + 1 : U32), Array.set(U32, array, i, value))

def Tables.jfif(+tables: Tables) -> Bool:
  Tables{_, _, _, _, jfif, _} = tables
  jfif

def Tables.transform(+tables: Tables) -> U32:
  Tables{_, _, _, _, _, transform} = tables
  transform

def comp.output.if(present: Bool, +frame: Frame, +comp: Comp, plane: Array<U32>) -> +List<+List<U32>>:
  match present:
    case False{}: Nil{}
    case True{}: comp.output(frame, comp, plane)

# stbi's color selection: gray, RGB by component ids or Adobe transform 0
# without JFIF, YCbCr, CMYK (transform 0) and YCCK (transform 2).
def mode(+count: U32, +rgb: U32, +transform: U32, +jfif: Bool) -> U32:
  Bool.pick(U32, U32.is_eq(count, 1), 1,
  Bool.pick(U32, U32.is_eq(count, 3), Bool.pick(U32, U32.is_eq(rgb, 3) || (U32.is_eq(transform, 0) && Bool.not(jfif)), 2, 3),
    Bool.pick(U32, U32.is_eq(transform, 0), 4, Bool.pick(U32, U32.is_eq(transform, 2), 5, 3))))

def output(+frame: Frame, +tables: Tables, planes: Planes) -> C.Image:
  Frame{_, width, height, comps, rgb, _, _, _, _} = frame
  Planes{a, b, c, d} = planes
  +count = U32.from_nat(List.length(&2, Comp, comps))
  +words = pixels(U32.to_nat(height), width, mode(count, rgb, Tables.transform(tables), Tables.jfif(tables)),
    comp.output.if((count > 0 : U32), frame, pick(Comp, comps, 0, Comp.empty()), a),
    comp.output.if((count > 1 : U32), frame, pick(Comp, comps, 1, Comp.empty()), b),
    comp.output.if((count > 2 : U32), frame, pick(Comp, comps, 2, Comp.empty()), c),
    comp.output.if((count > 3 : U32), frame, pick(Comp, comps, 3, Comp.empty()), d), Nil{})
  C.Image{width, height, Bool.pick(U32, (count >= 3 : U32), 3, 1), fill.array(words, 0, Array.new(U32, capacity((width * height : U32)), 0))}

def plane.new(+comp: Comp) -> Array<U32>:
  Array.new(U32, capacity((Comp.w2(comp) * Comp.h2(comp) : U32)), 0)

def planes.new(+comps: +List<Comp>) -> Planes:
  Planes{plane.new(pick(Comp, comps, 0, Comp.empty())), plane.new(pick(Comp, comps, 1, Comp.empty())),
    plane.new(pick(Comp, comps, 2, Comp.empty())), plane.new(pick(Comp, comps, 3, Comp.empty()))}

def coeffs.new(progressive: Bool, +comps: +List<Comp>) -> Planes:
  match progressive:
    case True{}: planes.new(comps)
    case False{}: planes.new([])

# stbi__jpeg_finish: dequantize each block of a progressive frame and
# transform it into its plane.
def dequantize(values: +List<U32>, +scale: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: Con{short((value * head(scale) : U32)), dequantize(rest, tail(scale))}

def finish.block(active: Bool, +comp: U32, +x: U32, +y: U32, +stride: U32, +block: +List<U32>, planes: Planes) -> Planes:
  match active:
    case False{}: planes
    case True{}: plane.block(comp, x, y, stride, idct.values(block), Planes.take(comp, planes))

def finish.loop(n: Nat, +values: +List<U32>, +index: U32, +cw: U32, +w: U32, +h: U32, +comp: U32, +scale: +List<U32>, +stride: U32, planes: Planes) -> Planes:
  match n:
    case 0n: planes
    case 1n+k:
      +bx = (index % cw : U32)
      +by = (index / cw : U32)
      finish.loop(k, List.drop(&2, U32, values, 64n), (index + 1 : U32), cw, w, h, comp, scale, stride,
        finish.block((bx < w : U32) && (by < h : U32), comp, (bx * 8 : U32), (by * 8 : U32), stride, dequantize(List.take(&2, U32, values, 64n), scale), planes))

def finish.present(present: Bool, +i: U32, +frame: Frame, +tables: Tables, planes: Planes, array: Array<U32>) -> Planes:
  match present:
    case False{}: planes
    case True{}:
      +comp = pick(Comp, Frame.comps(frame), i, Comp.empty())
      +cw = (Comp.w2(comp) / 8 : U32)
      finish.loop(U32.to_nat((cw * (Comp.h2(comp) / 8) : U32)), plus(Array.to_list(~U32, array)), 0, cw, ((Comp.x(comp) + 7) >> 3n : U32),
        ((Comp.y(comp) + 7) >> 3n : U32), i, Tables.quant(tables, Comp.tq(comp)), Comp.w2(comp), planes)

type Two is Type:
  Two{planes: Planes, coeffs: Planes}

def finish.comp(+i: U32, +frame: Frame, +tables: Tables, planes: Planes, taken: Taken) -> Two:
  Taken{array, rest} = taken
  Two{finish.present((i < U32.from_nat(List.length(&2, Comp, Frame.comps(frame))) : U32), i, frame, tables, planes, array), rest}

def finish.comps(n: Nat, +i: U32, +frame: Frame, +tables: Tables, two: Two) -> Two:
  match n two:
    case 1n+k Two{planes, coeffs}: finish.comps(k, (i + 1 : U32), frame, tables, finish.comp(i, frame, tables, planes, Planes.take(i, coeffs)))
    case 0n other: other

def finish.planes(two: Two) -> Planes:
  match two:
    case Two{planes, _}: planes

def finish.run(progressive: Bool, +frame: Frame, +tables: Tables, planes: Planes, coeffs: Planes) -> Planes:
  match progressive:
    case False{}: planes
    case True{}: finish.planes(finish.comps(4n, 0, frame, tables, Two{planes, coeffs}))

def finish(+frame: Frame, +tables: Tables, planes: Planes, coeffs: Planes) -> Planes:
  finish.run(Frame.progressive(frame), frame, tables, planes, coeffs)

def complete(n: Nat, written: +List<U32>) -> Bool:
  match n written:
    case 0n _: True{}
    case 1n+k Con{flag, rest}: U32.is_eq(flag, 1) && complete(k, rest)
    case _ Nil{}: False{}

# Planes stb would leave uninitialized (a component without a complete scan,
# or a progressive frame ending before EOI, which skips stbi__jpeg_finish)
# are InvalidImageStream rather than undefined samples.
def decode.defined(valid: Bool, +frame: Frame, +tables: Tables, planes: Planes, coeffs: Planes) -> Result<&1, &1, C.Error, C.Image>:
  match valid:
    case False{}: Fail{C.BadStream{}}
    case True{}: Done{output(frame, tables, finish(frame, tables, planes, coeffs))}

def decode.main(state: Main, +frame: Frame) -> Result<&1, &1, C.Error, C.Image>:
  match state:
    case Finished{+tables, written, eoi, planes, coeffs}:
      decode.defined(complete(List.length(&2, Comp, Frame.comps(frame)), written) && (eoi || Bool.not(Frame.progressive(frame))), frame, tables, planes, coeffs)
    case Main{_, _, _, _, _, _, _}: Fail{C.BadStream{}}
    case Error{kind}: Fail{Bool.pick(C.Error, U32.is_eq(kind, 3), C.BadStream{}, C.BadHeader{})}

def decode.status(status: U32, n: Nat, +frame: Frame, +rest: +List<U32>, +tables: Tables) -> Result<&1, &1, C.Error, C.Image>:
  match status:
    case 0:
      +first = get_marker(255, rest)
      decode.main(main.loop(n, frame, Main{Mark.value(first), Mark.rest(first), tables, [0, 0, 0, 0], [0, 0, 0, 0], planes.new(Frame.comps(frame)),
        coeffs.new(Frame.progressive(frame), Frame.comps(frame))}), frame)
    case 2: Fail{C.BadSize{}}
    case _: Fail{C.BadHeader{}}

def decode.frame(framed: Framed, n: Nat, +tables: Tables) -> Result<&1, &1, C.Error, C.Image>:
  match framed:
    case Framed{frame, rest, status}: decode.status(status, n, frame, rest, tables)

def decode.head(head: Head, n: Nat) -> Result<&1, &1, C.Error, C.Image>:
  match head:
    case Sof{m, rest, tables}: decode.frame(frame(U32.is_eq(m, 194), rest), n, tables)
    case Head{_, _, _, _}: Fail{C.BadHeader{}}
    case HeadBad{}: Fail{C.BadHeader{}}

def decode.soi(ok: Bool, +n: Nat, +rest: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  match ok:
    case False{}: Fail{C.BadHeader{}}
    case True{}:
      +first = get_marker(255, rest)
      decode.head(head.loop(n, Head{Mark.value(first), Mark.rest(first), Tables.empty(), False{}}), n)

# stbi__jpeg_test: 0xFF fill bytes then SOI.
def signature(+bytes: +List<U32>) -> Bool:
  U32.is_eq(Mark.value(get_marker(255, bytes)), 216)

# stbi__jpeg_load with raylib's desired channels 0: 1 for grayscale files,
# 3 otherwise; canonical RGBA words.
def decode(+bytes: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  +soi = get_marker(255, bytes)
  decode.soi(U32.is_eq(Mark.value(soi), 216), 1n+1n+C.byte_count(bytes, 0n), Mark.rest(soi))
