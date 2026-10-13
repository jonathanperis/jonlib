# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Rows of floats and of words that are read and written by index: binary
# trees that are plain values (a write gives a new row and leaves the old
# one as it was), for code that walks buffers the way C walks arrays. A row
# has a power of two of places; a read or a write takes as many steps as
# the power.
import Base

# The places of a row of floats.
type Floats is Data:
  FOne{value: F32}
  FTwo{low: Floats, high: Floats}

# A row of floats: `top` is half its size (0 for a row of one place), the
# bit that says which half an index is in.
type Row is Data:
  Row{top: U32, places: Floats}

def floats.doubled(+half: Floats) -> Floats:
  FTwo{half, half}

# 2^depth places of one value: the two halves of each level are one tree.
def floats.new(depth: Nat, +value: F32) -> Floats:
  match depth:
    case 0n: FOne{value}
    case 1n+k: floats.doubled(floats.new(k, value))

# `upper` says which half of the row the index is in; `bit` is the half's
# size.
def floats.get(places: Floats, upper: Bool, +i: U32, +bit: U32) -> F32:
  match places upper:
    case FOne{+value} _: value
    case FTwo{+a, _} False{}: floats.get(a, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32))
    case FTwo{_, +b} True{}: floats.get(b, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32))

def floats.set(places: Floats, upper: Bool, +i: U32, +bit: U32, +value: F32) -> Floats:
  match places upper:
    case FOne{_} _: FOne{value}
    case FTwo{+a, +b} False{}: FTwo{floats.set(a, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32), value), b}
    case FTwo{+a, +b} True{}: FTwo{a, floats.set(b, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32), value)}

def floats.listed(places: Floats, acc: +List<F32>) -> +List<F32>:
  match places:
    case FOne{+value}: Con{value, acc}
    case FTwo{+a, +b}: floats.listed(a, floats.listed(b, acc))

# 2^depth places, each `value`.
def Row.new(+depth: U32, +value: F32) -> Row:
  Row{Bool.pick(U32, U32.is_eq(depth, 0), 0, (1 << U32.to_nat((U32.max(depth, 1) - 1 : U32)) : U32)), floats.new(U32.to_nat(depth), value)}

# The float at index i (i under the row's size).
def Row.get(row: Row, +i: U32) -> F32:
  Row{+top, places} = row
  floats.get(places, U32.is_ne((i .&. top : U32), 0), i, top)

# The row with `value` at index i.
def Row.set(row: Row, +i: U32, +value: F32) -> Row:
  Row{+top, places} = row
  Row{top, floats.set(places, U32.is_ne((i .&. top : U32), 0), i, top, value)}

# Every place in order.
def Row.list(row: Row) -> +List<F32>:
  Row{_, places} = row
  floats.listed(places, Nil{})

def row.filled(values: +List<F32>, +i: U32, +row: Row) -> Row:
  match values:
    case Nil{}: row
    case Con{+v, +rest}: row.filled(rest, (i + 1 : U32), Row.set(row, i, v))

# How many bits an index under `count` takes: the depth of a row with room
# for `count` places.
def depth.for(n: Nat, +count: U32, +depth: U32) -> U32:
  match n:
    case 0n: depth
    case 1n+k: depth.for(k, count, Bool.pick(U32, ((1 << U32.to_nat(depth)) < count : U32), (depth + 1 : U32), depth))

def count.floats(values: +List<F32>, +n: U32) -> U32:
  match values:
    case Nil{}: n
    case Con{_, +rest}: count.floats(rest, (n + 1 : U32))

# A row with the values in order from index 0, and 0.0 after them up to the
# next power of two.
def Row.from(+values: +List<F32>) -> Row:
  row.filled(values, 0, Row.new(depth.for(32n, count.floats(values, 0), 0), 0.0))

# The places of a row of words.
type Words is Data:
  WOne{value: U32}
  WTwo{low: Words, high: Words}

# A row of words, as Row.
type Index is Data:
  Index{top: U32, places: Words}

def words.doubled(+half: Words) -> Words:
  WTwo{half, half}

def words.new(depth: Nat, +value: U32) -> Words:
  match depth:
    case 0n: WOne{value}
    case 1n+k: words.doubled(words.new(k, value))

def words.get(places: Words, upper: Bool, +i: U32, +bit: U32) -> U32:
  match places upper:
    case WOne{+value} _: value
    case WTwo{+a, _} False{}: words.get(a, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32))
    case WTwo{_, +b} True{}: words.get(b, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32))

def words.set(places: Words, upper: Bool, +i: U32, +bit: U32, +value: U32) -> Words:
  match places upper:
    case WOne{_} _: WOne{value}
    case WTwo{+a, +b} False{}: WTwo{words.set(a, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32), value), b}
    case WTwo{+a, +b} True{}: WTwo{a, words.set(b, U32.is_ne((i .&. (bit >> 1n) : U32), 0), i, (bit >> 1n : U32), value)}

def words.listed(places: Words, acc: +List<U32>) -> +List<U32>:
  match places:
    case WOne{+value}: Con{value, acc}
    case WTwo{+a, +b}: words.listed(a, words.listed(b, acc))

def Index.new(+depth: U32, +value: U32) -> Index:
  Index{Bool.pick(U32, U32.is_eq(depth, 0), 0, (1 << U32.to_nat((U32.max(depth, 1) - 1 : U32)) : U32)), words.new(U32.to_nat(depth), value)}

def Index.get(row: Index, +i: U32) -> U32:
  Index{+top, places} = row
  words.get(places, U32.is_ne((i .&. top : U32), 0), i, top)

def Index.set(row: Index, +i: U32, +value: U32) -> Index:
  Index{+top, places} = row
  Index{top, words.set(places, U32.is_ne((i .&. top : U32), 0), i, top, value)}

def Index.list(row: Index) -> +List<U32>:
  Index{_, places} = row
  words.listed(places, Nil{})

def index.filled(values: +List<U32>, +i: U32, +row: Index) -> Index:
  match values:
    case Nil{}: row
    case Con{+v, +rest}: index.filled(rest, (i + 1 : U32), Index.set(row, i, v))

def count.words(values: +List<U32>, +n: U32) -> U32:
  match values:
    case Nil{}: n
    case Con{_, +rest}: count.words(rest, (n + 1 : U32))

# A row with the values in order from index 0, and `rest` after them up to
# the next power of two.
def Index.from(+values: +List<U32>, +rest: U32) -> Index:
  index.filled(values, 0, Index.new(depth.for(32n, count.words(values, 0), 0), rest))

# The row's first places, a power of two of them, replaced by `zeros` (a
# tree of as many places): `whole` is whether the places at hand are those.
def floats.cleared(places: Floats, whole: Bool, +size: U32, +count: U32, +zeros: Floats) -> Floats:
  match places whole:
    case _ True{}: zeros
    case FOne{_} False{}: zeros
    case FTwo{+a, +b} False{}: FTwo{floats.cleared(a, U32.is_eq((size >> 1n : U32), count), (size >> 1n : U32), count, zeros), b}

# The row with its first `count` places 0.0: `count` is a power of two, no
# more than the row has. As many steps as the row's depth.
def Row.cleared(row: Row, +count: U32) -> Row:
  Row{+top, places} = row
  Row{top, floats.cleared(places, U32.is_eq(U32.max((top * 2 : U32), 1), count), U32.max((top * 2 : U32), 1), count, floats.new(U32.to_nat(depth.for(32n, count, 0)), 0.0))}
