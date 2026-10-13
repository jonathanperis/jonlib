# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: what the
# setup makes of a codebook's code lengths (compute_codewords,
# compute_sorted_huffman, compute_accelerated_huffman), with ilog,
# bit_reverse, float32_unpack and lookup1_values. See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# This is the first part of the Ogg Vorbis decoder: nothing reads a file
# yet. C ints are U32 two's-complement words; a length of 255 is NO_CODE,
# a symbol without a code.
import Base

def bits.of(n: Nat, +value: U32, +count: U32) -> U32:
  match n:
    case 0n: count
    case 1n+k: Bool.pick(U32, U32.is_eq(value, 0), count, bits.of(k, (value >> 1n : U32), (count + 1 : U32)))

# ilog(n): the bits of a positive int (1 for 1, 2 for 2 and 3, 3 for 4), and
# 0 for 0 and for a negative one.
def ilog(+n: U32) -> U32:
  Bool.pick(U32, (n >= 2147483648 : U32), 0, bits.of(32n, n, 0))

# bit_reverse(n): the 32 bits in the opposite order.
def bit.reverse(+n: U32) -> U32:
  +a = (((n .&. 2863311530) >> 1n) .|. ((n .&. 1431655765) << 1n) : U32)
  +b = (((a .&. 3435973836) >> 2n) .|. ((a .&. 858993459) << 2n) : U32)
  +c = (((b .&. 4042322160) >> 4n) .|. ((b .&. 252645135) << 4n) : U32)
  +d = (((c .&. 4278255360) >> 8n) .|. ((c .&. 16711935) << 8n) : U32)
  ((d >> 16n) .|. (d << 16n) : U32)

def float.word(value: U32) -> F32:
  U32{word} = value
  F32{word}

# The float's bits below its sign for a mantissa m of p + 1 bits and the
# exponent field e of the packed word: m * 2^(e - 788), rounded once to
# nearest even where it is below the floats' normal range.
def unpack.bits(+m: U32, +p: U32, +e: U32) -> U32:
  +top = (p + e : U32)
  +down = (639 - U32.min(e, 639) : U32)
  +quotient = (m >> U32.to_nat(U32.min(down, 31)) : U32)
  +rest = (m .&. ((1 << U32.to_nat(U32.min(down, 31))) - 1) : U32)
  +half = (1 << U32.to_nat((U32.max(U32.min(down, 31), 1) - 1 : U32)) : U32)
  +up = (rest > half : U32) || (U32.is_eq(rest, half) && U32.is_eq((quotient .&. 1 : U32), 1))
  Bool.pick(U32, (top > 915 : U32), 2139095040,
    Bool.pick(U32, (top >= 662 : U32), ((((top - 661) << 23n) .|. ((m << U32.to_nat((23 - p : U32))) .&. 8388607)) : U32),
      Bool.pick(U32, (e >= 639 : U32), (m << U32.to_nat(U32.min((e - U32.min(e, 639) : U32), 31)) : U32),
        Bool.pick(U32, (down > 22 : U32), 0, (quotient + Bool.pick(U32, up, 1, 0) : U32)))))

# float32_unpack(x): the 21 low bits are the mantissa, the next 10 the
# exponent and the top one the sign; the value is
# (float)ldexp((float)mantissa, exponent - 788), with the sign. The
# mantissa is exact in a float and ldexp in binary64, so the narrowing is
# the one rounding: an infinity from 2^128 up, a subnormal or a zero below
# 2^-126.
def float32.unpack(+x: U32) -> F32:
  +m = (x .&. 2097151 : U32)
  +sign = (x .&. 2147483648 : U32)
  float.word(Bool.pick(U32, U32.is_eq(m, 0), sign, (sign .|. unpack.bits(m, (bits.of(32n, m, 0) - 1 : U32), ((x >> 21n) .&. 1023 : U32)) : U32)))

# A symbol with its code and its code's length.
type Entry is Data:
  Entry{symbol: U32, code: U32, length: U32}

def nth(xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, +rest}: Bool.pick(U32, U32.is_eq(i, 0), x, nth(rest, (i - 1 : U32)))

# The highest level up to `len` with a free leaf, 0 where there is none
# (`while (z > 0 && !available[z]) --z`).
def free.level(available: +List<U32>, +at: U32, +len: U32, +found: U32) -> U32:
  match available:
    case Nil{}: found
    case Con{+leaf, +rest}: free.level(rest, (at + 1 : U32), len, Bool.pick(U32, (at <= len : U32) && U32.is_ne(leaf, 0), at, found))

# available[] once the leaf `res` of level z is taken for a code of `len`
# bits: level z is empty and each level from z + 1 to len gets the leaf
# beside the path, res + (1 << (32 - y)).
def taken(available: +List<U32>, +at: U32, +z: U32, +len: U32, +res: U32, acc: +List<U32>) -> +List<U32>:
  match available:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+leaf, +rest}:
      +beside = (res + (1 << U32.to_nat((32 - U32.min(U32.max(at, 1), 32) : U32))) : U32)
      taken(rest, (at + 1 : U32), z, len, res, Con{Bool.pick(U32, U32.is_eq(at, z), 0, Bool.pick(U32, (at > z : U32) && (at <= len : U32), beside, leaf)), acc})

# available[] after the first code, which is 0: the leaf 1 << (32 - i) at
# each level i from 1 to its length. Level 0 is not used.
def first.levels(n: Nat, +at: U32, +len: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: first.levels(k, (at + 1 : U32), len, Con{Bool.pick(U32, (at >= 1 : U32) && (at <= len : U32), (1 << U32.to_nat((32 - U32.min(U32.max(at, 1), 32) : U32)) : U32), 0), acc})

# The codes so far: whether a first symbol has its code, whether every
# symbol found a leaf (compute_codewords answers FALSE otherwise),
# available[] and the entries, the last first.
type Coding is Data:
  Coding{started: Bool, fine: Bool, available: +List<U32>, entries: +List<Entry>}

def Coding.started(coding: Coding) -> Bool:
  Coding{started, _, _, _} = coding
  started

def Coding.fine(coding: Coding) -> Bool:
  Coding{_, fine, _, _} = coding
  fine

def Coding.available(coding: Coding) -> +List<U32>:
  Coding{_, _, available, _} = coding
  available

def Coding.entries(coding: Coding) -> +List<Entry>:
  Coding{_, _, _, entries} = coding
  entries

# A symbol after the first: the lowest free leaf at its length or above.
def code.leaf(none: Bool, +z: U32, +symbol: U32, +len: U32, +available: +List<U32>, +entries: +List<Entry>) -> Coding:
  match none:
    case True{}: Coding{True{}, False{}, available, entries}
    case False{}: Coding{True{}, True{}, taken(available, 0, z, len, nth(available, z), Nil{}), Con{Entry{symbol, bit.reverse(nth(available, z)), len}, entries}}

def code.later(+z: U32, +symbol: U32, +len: U32, +available: +List<U32>, +entries: +List<Entry>) -> Coding:
  code.leaf(U32.is_eq(z, 0), z, symbol, len, available, entries)

# kind: 0 the symbol has no code (or an earlier one found no leaf), 1 it is
# the first with a code, which is 0, 2 a later one.
def code.symbol(kind: U32, +symbol: U32, +len: U32, +coding: Coding) -> Coding:
  match kind:
    case 0: coding
    case 1: Coding{True{}, True{}, first.levels(33n, 0, len, Nil{}), [Entry{symbol, 0, len}]}
    case _: code.later(free.level(Coding.available(coding), 0, len, 0), symbol, len, Coding.available(coding), Coding.entries(coding))

def code.all(lengths: +List<U32>, +symbol: U32, +coding: Coding) -> Coding:
  match lengths:
    case Nil{}: coding
    case Con{+len, +rest}:
      code.all(rest, (symbol + 1 : U32), code.symbol(Bool.pick(U32, U32.is_eq(len, 255) || Bool.not(Coding.fine(coding)), 0, Bool.pick(U32, Coding.started(coding), 2, 1)), symbol, len, coding))

def entries.result(+coding: Coding) -> Maybe<+List<Entry>>:
  Bool.pick(Maybe<+List<Entry>>, Coding.fine(coding), Some{List.reverse(&2, Entry, Coding.entries(coding))}, None{})

# compute_codewords(c, len, n, values): each symbol's code, in the symbols'
# order, for lengths of 1 to 31 bits or 255 (no code). The first symbol
# with a code takes 0; every later one takes the lowest free leaf at its
# length or above, and leaves the leaves beside its path free. None where a
# symbol finds no leaf (the lengths ask for more codes than a tree has).
# The codes are in stb_vorbis's order: the first bit read is the lowest.
def codewords(+lengths: +List<U32>) -> Maybe<+List<Entry>>:
  entries.result(code.all(lengths, 0, Coding{False{}, True{}, Nil{}, Nil{}}))

# -----------------------------------------------------------------------------
# lookup1_values

# p * base, or 2^26 from there up.
def times.capped(+p: U32, +base: U32) -> U32:
  Bool.pick(U32, (p > (67108864 / U32.max(base, 1)) : U32), 67108864, (p * base : U32))

def power.steps(n: Nat, +base: U32, +left: U32, +p: U32) -> U32:
  match n:
    case 0n: p
    case 1n+k: power.steps(k, base, (left - U32.min(left, 1) : U32), Bool.pick(U32, U32.is_eq(left, 0), p, times.capped(p, base)))

# base^dim for dim >= 1, or 2^26 from there up (26 products reach it from
# any base above 1).
def power.capped(+base: U32, +dim: U32) -> U32:
  Bool.pick(U32, (base <= 1 : U32), base, power.steps(26n, base, dim, 1))

def root.bits(n: Nat, +bit: U32, +entries: U32, +dim: U32, +r: U32) -> U32:
  match n:
    case 0n: r
    case 1n+k: root.bits(k, (bit >> 1n : U32), entries, dim, Bool.pick(U32, (power.capped((r .|. bit : U32), dim) <= entries : U32), (r .|. bit : U32), r))

# The largest r whose dim-th power is at most `entries`, for entries below
# 2^24 and dim >= 1.
def root(+entries: U32, +dim: U32) -> U32:
  root.bits(24n, 8388608, entries, dim, 0)

# Whether stb_vorbis's estimate of the root r is surely r or r - 1, which
# its correction turns into r, for entries from 1 to 2^24 - 1 and dim >= 1.
# The estimate is floor(exp((float)log((float)entries)/dim)): the root times
# e^(ln(entries)*d), |d| <= 2^-23 from the two float roundings. It stays
# below r + 1 when 17*P < (P - entries)*2^23 for P = (r + 1)^dim, and for
# every entries up to 2^19; it is at least r - 1 from 2 dimensions up, and
# with one for entries up to 2^19. Outside, the answer hangs on the last
# bits of the C library's log and exp.
def root.sure(+entries: U32, +dim: U32, +r: U32) -> Bool:
  +p = power.capped((r + 1 : U32), dim)
  (entries <= 524288 : U32) || (U32.is_ne(dim, 1) && ((p >= (entries * 2) : U32) || ((p - U32.min(entries, p)) > ((17 * p) >> 23n) : U32)))

# Whether (r + 1)^dim is 2^31 or more: `(int) floor(pow((float) r+1, dim))`
# is then a conversion C leaves undefined (x86-64 gives INT_MIN and
# stb_vorbis answers r + 1). r is 1 from 24 dimensions up.
def root.undefined(+dim: U32, +r: U32) -> Bool:
  (U32.is_eq(r, 1) && (dim >= 31 : U32)) || (U32.is_eq(r, 2) && (dim >= 20 : U32))

def lookup1.rooted(+entries: U32, +dim: U32, +r: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, Bool.not(root.undefined(dim, r)) && root.sure(entries, dim, r), Some{r}, None{})

# lookup1_values(entries, dim), the C int as a word: how many values a
# lookup of type 1 has for each dimension, the largest r with r^dim <=
# entries. stb_vorbis does not compute the root: it estimates it through the
# C library's binary64 log and exp with two float roundings between them,
# and corrects the estimate by one upward only. The answer here is the root
# where the estimate is surely within that correction (root.sure: every
# codebook of up to 2^19 entries, and a larger one of 2 dimensions or more
# that is not just under a perfect power), which
# tools/reference/stb_vorbis_lookup1 checks against stb_vorbis for every
# entries of 24 bits. None where it is not sure, where stb_vorbis converts
# a power of 2^31 or more to int (root.undefined), for a codebook of no
# dimension with entries (a conversion of an infinity or a NaN), and
# outside what the setup reads (24 bits of entries, 16 of dimensions).
# Without entries the C answer is 0, and -1 without dimensions as well.
def lookup1.values(+entries: U32, +dim: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, (entries >= 16777216 : U32) || (dim >= 65536 : U32), None{},
    Bool.pick(Maybe<U32>, U32.is_eq(entries, 0), Some{Bool.pick(U32, U32.is_eq(dim, 0), 4294967295, 0)},
      Bool.pick(Maybe<U32>, U32.is_eq(dim, 0), None{}, lookup1.rooted(entries, dim, root(entries, dim)))))

# -----------------------------------------------------------------------------
# The sorted table (compute_sorted_huffman)

def Entry.symbol(entry: Entry) -> U32:
  Entry{symbol, _, _} = entry
  symbol

def Entry.code(entry: Entry) -> U32:
  Entry{_, code, _} = entry
  code

def Entry.length(entry: Entry) -> U32:
  Entry{_, _, length} = entry
  length

# A turn of a merge: the entry taken and what is left of the two lists.
type Turn is Data:
  Turn{entry: Entry, a: +List<Entry>, b: +List<Entry>}

# The lower of the two heads by its code read the other way (bit_reverse),
# the order of the sorted table.
def turn.of(a: +List<Entry>, b: +List<Entry>) -> Turn:
  match a b:
    case Con{+x, +ra} Con{+y, +rb}:
      Bool.pick(Turn, (bit.reverse(Entry.code(x)) <= bit.reverse(Entry.code(y)) : U32), Turn{x, ra, Con{y, rb}}, Turn{y, Con{x, ra}, rb})
    case Con{+x, +ra} Nil{}: Turn{x, ra, Nil{}}
    case Nil{} Con{+y, +rb}: Turn{y, Nil{}, rb}
    case Nil{} Nil{}: Turn{Entry{0, 0, 0}, Nil{}, Nil{}}

def Turn.entry(t: Turn) -> Entry:
  Turn{entry, _, _} = t
  entry

def Turn.a(t: Turn) -> +List<Entry>:
  Turn{_, a, _} = t
  a

def Turn.b(t: Turn) -> +List<Entry>:
  Turn{_, _, b} = t
  b

def count(xs: +List<Entry>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count(rest, (n + 1 : U32))

# Two sorted lists as one, `n` entries in all.
def merged(n: Nat, +a: +List<Entry>, +b: +List<Entry>, acc: +List<Entry>) -> +List<Entry>:
  match n:
    case 0n: List.reverse(&2, Entry, acc)
    case 1n+k:
      +t = turn.of(a, b)
      merged(k, Turn.a(t), Turn.b(t), Con{Turn.entry(t), acc})

# A pass of the sort: the runs merged two by two.
def pass(runs: +List<+List<Entry>>, acc: +List<+List<Entry>>) -> +List<+List<Entry>>:
  match runs:
    case Con{+a, Con{+b, +rest}}: pass(rest, Con{merged(U32.to_nat((count(a, 0) + count(b, 0) : U32)), a, b, Nil{}), acc})
    case Con{+a, Nil{}}: List.reverse(&2, +List<Entry>, Con{a, acc})
    case Nil{}: List.reverse(&2, +List<Entry>, acc)

def runs.of(entries: +List<Entry>, acc: +List<+List<Entry>>) -> +List<+List<Entry>>:
  match entries:
    case Nil{}: List.reverse(&2, +List<Entry>, acc)
    case Con{+e, +rest}: runs.of(rest, Con{[e], acc})

def first.run(runs: +List<+List<Entry>>) -> +List<Entry>:
  match runs:
    case Nil{}: Nil{}
    case Con{+a, _}: a

def single(runs: +List<+List<Entry>>) -> Bool:
  match runs:
    case Con{_, Con{_, _}}: False{}
    case _: True{}

# qsort by the codes read the other way: 32 passes halve any count of runs
# to one.
def sorted.runs(n: Nat, +runs: +List<+List<Entry>>) -> +List<Entry>:
  match n:
    case 0n: first.run(runs)
    case 1n+k: sorted.runs(k, Bool.pick(+List<+List<Entry>>, single(runs), runs, pass(runs, Nil{})))

# The entries the sorted table has: every one of a sparse codebook, and of
# another the codes longer than STB_VORBIS_FAST_HUFFMAN_LENGTH (10) bits.
def kept(entries: +List<Entry>, +sparse: Bool, +acc: +List<Entry>) -> +List<Entry>:
  match entries:
    case Nil{}: List.reverse(&2, Entry, acc)
    case Con{+e, +rest}: kept(rest, sparse, Bool.pick(+List<Entry>, sparse || (Entry.length(e) > 10 : U32), Con{e, acc}, acc))

def codes.reversed(entries: +List<Entry>, acc: +List<U32>) -> +List<U32>:
  match entries:
    case Nil{}: List.reverse(&2, U32, Con{4294967295, acc})
    case Con{+e, +rest}: codes.reversed(rest, Con{bit.reverse(Entry.code(e)), acc})

def symbols(entries: +List<Entry>, acc: +List<U32>) -> +List<U32>:
  match entries:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+e, +rest}: symbols(rest, Con{Entry.symbol(e), acc})

def lengths.of(entries: +List<Entry>, acc: +List<U32>) -> +List<U32>:
  match entries:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+e, +rest}: lengths.of(rest, Con{Entry.length(e), acc})

# -----------------------------------------------------------------------------
# The accelerated table (compute_accelerated_huffman)

# fast_huffman[z] = i for z, z + step, ... below 1024: `n` places.
def fast.fill(n: Nat, +z: U32, +step: U32, +i: U32, table: Array<U32>) -> Array<U32>:
  match n:
    case 0n: table
    case 1n+k: fast.fill(k, (z + step : U32), step, i, Array.set(U32, table, z, i))

# An entry of at most 10 bits fills its places; a longer one, and one past
# the 32767th (the table's shorts hold no more), fills none.
def fast.entry(short: Bool, +code: U32, +length: U32, +i: U32, table: Array<U32>) -> Array<U32>:
  match short:
    case False{}: table
    case True{}:
      +step = (1 << U32.to_nat(U32.min(length, 10)) : U32)
      fast.fill(U32.to_nat(((((1024 - U32.min(code, 1024)) + step) - 1) / step : U32)), code, step, i, table)

# The table over the entries: `by_symbol` takes each entry's symbol for its
# index (a codebook that is not sparse), otherwise its place in the list
# (the sorted table of a sparse one).
def fast.entries(entries: +List<Entry>, +by_symbol: Bool, +place: U32, table: Array<U32>) -> Array<U32>:
  match entries:
    case Nil{}: table
    case Con{Entry{+symbol, +code, +length}, +rest}:
      +i = Bool.pick(U32, by_symbol, symbol, place)
      fast.entries(rest, by_symbol, (place + 1 : U32), fast.entry((length <= 10 : U32) && (i < 32767 : U32), code, length, i, table))

def listed(xs: List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+x, rest}: listed(rest, Con{x, acc})

# The 1024 entries of fast_huffman: an index, or -1 (4294967295).
def fast(+entries: +List<Entry>, +by_symbol: Bool) -> +List<U32>:
  listed(Array.to_list(~U32, fast.entries(entries, by_symbol, 0, Array.new(U32, 10n, 4294967295))), Nil{})

# -----------------------------------------------------------------------------
# A codebook's tables

# What the setup keeps of a codebook's codes. Not sparse: codeword_lengths
# and codewords by symbol (a symbol without a code has length 255 and, here,
# codeword 0: stb_vorbis leaves it unset and never reads it). Sparse:
# codeword_lengths in the sorted table's order and no codewords.
# sorted_codewords are the codes read the other way, ascending, with the
# sentinel 0xffffffff after them, and sorted_values their symbols.
type Book is Data:
  Book{sparse: Bool, entries: U32, lengths: +List<U32>, codewords: +List<U32>, sorted: U32, sorted_codewords: +List<U32>, sorted_values: +List<U32>, fast: +List<U32>}

def Book.lengths(book: Book) -> +List<U32>:
  Book{_, _, lengths, _, _, _, _, _} = book
  lengths

def Book.codewords(book: Book) -> +List<U32>:
  Book{_, _, _, codewords, _, _, _, _} = book
  codewords

# sorted_entries: how many codes the sorted table has.
def Book.count(book: Book) -> U32:
  Book{_, _, _, _, sorted, _, _, _} = book
  sorted

def Book.sorted_codewords(book: Book) -> +List<U32>:
  Book{_, _, _, _, _, sorted_codewords, _, _} = book
  sorted_codewords

def Book.sorted_values(book: Book) -> +List<U32>:
  Book{_, _, _, _, _, _, sorted_values, _} = book
  sorted_values

# codewords[symbol] for every symbol, from the coded ones in their order.
def by.symbol(lengths: +List<U32>, +coded: +List<Entry>, acc: +List<U32>) -> +List<U32>:
  match lengths:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+len, +rest}:
      match coded:
        case Nil{}: by.symbol(rest, Nil{}, Con{0, acc})
        case Con{+e, +more}: by.symbol(rest, Bool.pick(+List<Entry>, U32.is_eq(len, 255), Con{e, more}, more), Con{Bool.pick(U32, U32.is_eq(len, 255), 0, Entry.code(e)), acc})

def length.count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: length.count(rest, (n + 1 : U32))

def book.tables(+lengths: +List<U32>, +sparse: Bool, +coded: +List<Entry>, +sorted: +List<Entry>) -> Book:
  Book{sparse, length.count(lengths, 0), Bool.pick(+List<U32>, sparse, lengths.of(sorted, Nil{}), lengths), Bool.pick(+List<U32>, sparse, Nil{}, by.symbol(lengths, coded, Nil{})), count(sorted, 0),
    codes.reversed(sorted, Nil{}), symbols(sorted, Nil{}), fast(Bool.pick(+List<Entry>, sparse, sorted, coded), Bool.not(sparse))}

def book.coded(coded: Maybe<+List<Entry>>, +lengths: +List<U32>, +sparse: Bool) -> Maybe<Book>:
  match coded:
    case None{}: None{}
    case Some{+entries}: Some{book.tables(lengths, sparse, entries, sorted.runs(32n, runs.of(kept(entries, sparse, Nil{}), Nil{})))}

# The tables of a codebook with these code lengths (1 to 31, or 255 for a
# symbol without a code), as start_decoder makes them once it has decided
# whether the codebook is sparse. None where the lengths are no tree.
def book.of(+lengths: +List<U32>, +sparse: Bool) -> Maybe<Book>:
  book.coded(codewords(lengths), lengths, sparse)
