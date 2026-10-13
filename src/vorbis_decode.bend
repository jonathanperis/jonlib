# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: the
# decoding of a codebook's symbols from a packet's bits (the DECODE_RAW and
# DECODE macros of the inline build, codebook_decode_scalar_raw) and of its
# vectors of values (codebook_decode_start, codebook_decode,
# codebook_decode_step). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# A symbol that is not decoded is -1 (4294967295). The reader's error 1001
# is this port's refusal of what C leaves undefined (see vorbis_ogg.bend).
import Base
import ./vorbis_ogg.bend as O
import ./vorbis_codebook.bend as C
import ./vorbis_setup.bend as S
import ./store.bend as R

# A codebook made ready to decode with: its tables as rows read by index
# (the accelerated table, the lengths the codebook keeps, the sorted
# codewords and their symbols, the values), with the lengths and the
# codewords by symbol as lists too, for the search of a small codebook.
type Coder is Data:
  Coder{dimensions: U32, entries: U32, sparse: Bool, lookup: U32, sequence: Bool, minimum: F32, sorted: U32, fast: R.Index, kept: R.Index, lengths: +List<U32>, codewords: +List<U32>, sorted_codewords: R.Index,
    sorted_values: R.Index, values: R.Row}

def coder.booked(book: C.Book, +dimensions: U32, +entries: U32, +lookup: U32, +sequence: Bool, +minimum: F32, +values: +List<F32>) -> Coder:
  C.Book{+sparse, _, +lengths, +codewords, +sorted, +sorted_codewords, +sorted_values, +fast} = book
  Coder{dimensions, entries, sparse, lookup, sequence, minimum, sorted, R.Index.from(fast, 4294967295), R.Index.from(lengths, 255), lengths, codewords, R.Index.from(sorted_codewords, 4294967295), R.Index.from(sorted_values, 4294967295),
    R.Row.from(values)}

# The codebook as the setup read it, ready to decode with.
def coder.of(read: S.Codebook) -> Coder:
  S.Codebook{dimensions, entries, book, lookup, minimum, _, _, sequence, _, multiplicands} = read
  coder.booked(book, dimensions, entries, lookup, sequence, minimum, multiplicands)

# The codebooks of a setup, each ready to decode with.
def coders.of(books: +List<S.Codebook>, acc: +List<Coder>) -> +List<Coder>:
  match books:
    case Nil{}: List.reverse(&2, Coder, acc)
    case Con{+b, +rest}: coders.of(rest, Con{coder.of(b), acc})

# A codebook of no entry: what a number past the setup's codebooks gets
# (the setup does not let one be asked for).
def coder.none() -> Coder:
  Coder{0, 0, False{}, 0, False{}, 0.0, 0, R.Index.new(0, 4294967295), R.Index.new(0, 255), Nil{}, Nil{}, R.Index.new(0, 4294967295), R.Index.new(0, 4294967295), R.Row.new(0, 0.0)}

def coder.first(coders: +List<Coder>) -> Coder:
  match coders:
    case Nil{}: coder.none()
    case Con{+c, _}: c

# The codebook of a number.
def coder.at(+coders: +List<Coder>, +i: U32) -> Coder:
  coder.first(List.drop(&2, Coder, coders, U32.to_nat(i)))

def Coder.sparse(coder: Coder) -> Bool:
  Coder{_, _, sparse, _, _, _, _, _, _, _, _, _, _, _} = coder
  sparse

def Coder.sorted(coder: Coder) -> U32:
  Coder{_, _, _, _, _, _, sorted, _, _, _, _, _, _, _} = coder
  sorted

def Coder.sorted_values(coder: Coder) -> R.Index:
  Coder{_, _, _, _, _, _, _, _, _, _, _, _, sorted_values, _} = coder
  sorted_values

def Coder.lookup(coder: Coder) -> U32:
  Coder{_, _, _, lookup, _, _, _, _, _, _, _, _, _, _} = coder
  lookup

def Coder.dimensions(coder: Coder) -> U32:
  Coder{dimensions, _, _, _, _, _, _, _, _, _, _, _, _, _} = coder
  dimensions

def Coder.sequence(coder: Coder) -> Bool:
  Coder{_, _, _, _, sequence, _, _, _, _, _, _, _, _, _} = coder
  sequence

def Coder.minimum(coder: Coder) -> F32:
  Coder{_, _, _, _, _, minimum, _, _, _, _, _, _, _, _} = coder
  minimum

def Coder.kept(coder: Coder) -> R.Index:
  Coder{_, _, _, _, _, _, _, _, kept, _, _, _, _, _} = coder
  kept

def Coder.values(coder: Coder) -> R.Row:
  Coder{_, _, _, _, _, _, _, _, _, _, _, _, _, values} = coder
  values

def acc(reader: O.Reader) -> U32:
  O.Packet.acc(O.Reader.packet(reader))

def valid(reader: O.Reader) -> U32:
  O.Packet.valid(O.Reader.packet(reader))

# valid_bits as an int is under n.
def short(+valid: U32, +n: U32) -> Bool:
  U32.is_eq(valid, 4294967295) || (valid < n : U32)

# A code of `length` bits is the symbol's if the bits at hand are as many:
# they are used. Otherwise no bits are at hand any more and the symbol is
# -1.
def taken(enough: Bool, +reader: O.Reader, +length: U32, +symbol: U32) -> O.Reader:
  match enough:
    case True{}: O.Reader.answer(O.bits.used(reader, length), symbol)
    case False{}: O.Reader.answer(O.bits.dropped(reader), 4294967295)

# The binary search of the sorted codewords for the bits at hand read the
# other way: the last codeword that is not above them. It does not ask
# whether the code is one of the codebook's.
def search(n: Nat, +codes: R.Index, +code: U32, +x: U32, +count: U32) -> U32:
  match n:
    case 0n: x
    case 1n+k:
      +over = (count > 1 : U32) && (R.Index.get(codes, (x + (count >> 1n) : U32)) <= code : U32)
      search(k, codes, code, Bool.pick(U32, over, (x + (count >> 1n) : U32), x), Bool.pick(U32, (count > 1 : U32), Bool.pick(U32, over, (count - (count >> 1n) : U32), (count >> 1n : U32)), count))

def sorted.symbol(+coder: Coder, +x: U32) -> U32:
  Coder{_, _, +sparse, _, _, _, _, _, _, _, _, _, +sorted_values, _} = coder
  Bool.pick(U32, sparse, x, R.Index.get(sorted_values, x))

def sorted.found(+coder: Coder, +reader: O.Reader, +symbol: U32) -> O.Reader:
  Coder{_, _, _, _, _, _, _, _, +kept, _, _, _, _, _} = coder
  taken(Bool.not(short(valid(reader), R.Index.get(kept, symbol))), reader, R.Index.get(kept, symbol), symbol)

def sorted.decode(+coder: Coder, +reader: O.Reader) -> O.Reader:
  Coder{_, _, _, _, _, _, +sorted, _, _, _, _, +sorted_codewords, _, _} = coder
  sorted.found(coder, reader, sorted.symbol(coder, search(32n, sorted_codewords, C.bit.reverse(acc(reader)), 0, sorted)))

# What the search of a small codebook finds: state 0 nothing, 1 a symbol
# whose bits are at hand, 2 one whose bits are not.
type Hit is Data:
  Hit{state: U32, symbol: U32, length: U32}

# The search of a small codebook, symbol by symbol: the first whose code
# the bits at hand begin with.
def linear(lengths: +List<U32>, codewords: +List<U32>, +state: U32, +acc: U32, +valid: U32, +i: U32, +symbol: U32, +length: U32) -> Hit:
  match lengths codewords:
    case Con{+len, +more} Con{+code, +rest}:
      +hit = U32.is_eq(state, 0) && U32.is_ne(len, 255) && U32.is_eq(code, (acc .&. ((1 << U32.to_nat(U32.min(len, 31))) - 1) : U32))
      linear(more, rest, Bool.pick(U32, hit, Bool.pick(U32, short(valid, len), 2, 1), state), acc, valid, (i + 1 : U32), Bool.pick(U32, hit, i, symbol), Bool.pick(U32, hit, len, length))
    case _ _: Hit{state, symbol, length}

# No symbol's code is a VORBIS_invalid_stream (21).
def linear.found(found: Hit, +reader: O.Reader) -> O.Reader:
  match found:
    case Hit{0, _, _}: O.Reader.answer(O.bits.dropped(O.failed(reader, 21)), 4294967295)
    case Hit{1, +symbol, +length}: taken(True{}, reader, length, symbol)
    case Hit{_, +symbol, +length}: taken(False{}, reader, length, symbol)

def linear.decode(+coder: Coder, +reader: O.Reader) -> O.Reader:
  Coder{_, _, _, _, _, _, _, _, _, +lengths, +codewords, _, _, _} = coder
  linear.found(linear(lengths, codewords, 0, acc(reader), valid(reader), 0, 0, 0), reader)

# kind: 0 the codebook has no code (-1), 1 the sorted table is searched, 2
# the symbols are.
def raw.search(kind: U32, +coder: Coder, +reader: O.Reader) -> O.Reader:
  match kind:
    case 0: O.Reader.answer(reader, 4294967295)
    case 1: sorted.decode(coder, reader)
    case _: linear.decode(coder, reader)

def raw.kind(+coder: Coder) -> U32:
  Coder{_, +entries, +sparse, _, _, _, +sorted, _, _, _, _, _, _, _} = coder
  Bool.pick(U32, sparse && U32.is_eq(sorted, 0), 0, Bool.pick(U32, ((entries > 8 : U32) && U32.is_ne(sorted, 0)) || ((entries <= 8 : U32) && sparse), 1, 2))

# codebook_decode_scalar_raw: the bits are prepared, then the sorted table
# is searched where the codebook has more than 8 entries and a sorted
# table, or has no codewords by symbol (it is sparse); else the symbols are
# searched in turn.
def raw.decode(+coder: Coder, +reader: O.Reader) -> O.Reader:
  raw.search(raw.kind(coder), coder, O.huffman.prep(reader))

# The accelerated table's answer for the next 10 bits: a symbol whose code
# they begin with, whose bits are shifted out (then -1 and no bits at hand
# if they were more than there were), or the slower search.
def fast.used(+reader: O.Reader, +length: U32, +symbol: U32) -> O.Reader:
  Bool.pick(O.Reader, short(valid(reader), length), O.Reader.answer(O.bits.dropped(O.bits.used(reader, length)), 4294967295), O.Reader.answer(O.bits.used(reader, length), symbol))

def fast.found(none: Bool, +coder: Coder, +reader: O.Reader, +symbol: U32) -> O.Reader:
  match none:
    case True{}: raw.decode(coder, reader)
    case False{}: fast.used(reader, R.Index.get(Coder.kept(coder), symbol), symbol)

def fast.decode(+coder: Coder, +reader: O.Reader) -> O.Reader:
  Coder{_, _, _, _, _, _, _, +fast, _, _, _, _, _, _} = coder
  fast.found(U32.is_eq(R.Index.get(fast, (acc(reader) .&. 1023 : U32)), 4294967295), coder, reader, R.Index.get(fast, (acc(reader) .&. 1023 : U32)))

def prepared(few: Bool, +reader: O.Reader) -> O.Reader:
  match few:
    case False{}: reader
    case True{}: O.huffman.prep(reader)

# DECODE_RAW: a symbol of the codebook from the packet's bits, in `value`:
# its number, or its place in the sorted table for a sparse codebook; -1
# where there is none. The bits are prepared where fewer than 10 are at
# hand.
def decode.raw(+coder: Coder, +reader: O.Reader) -> O.Reader:
  fast.decode(coder, prepared(short(valid(reader), 10), reader))

# kind: 0 the codebook is not sparse, 1 it is sparse with a sorted table, 2
# it is sparse without one: stb_vorbis reads sorted_values[-1] of a table
# that is not there (refused).
def decode.mapped(kind: U32, +coder: Coder, +reader: O.Reader) -> O.Reader:
  match kind:
    case 0: reader
    case 1: O.Reader.answer(reader, Bool.pick(U32, U32.is_eq(O.Reader.value(reader), 4294967295), 4294967295, R.Index.get(Coder.sorted_values(coder), O.Reader.value(reader))))
    case _: O.undefined(reader)

# DECODE: the symbol's number: a sparse codebook's sorted place is turned
# into it (and -1 stays -1: the table has that before its first place).
def decode.symbol(+coder: Coder, +reader: O.Reader) -> O.Reader:
  decode.mapped(Bool.pick(U32, Coder.sparse(coder), Bool.pick(U32, U32.is_eq(Coder.sorted(coder), 0), 2, 1), 0), coder, decode.raw(coder, reader))

# -----------------------------------------------------------------------------
# Vectors of values

# codebook_decode_start: a symbol for a vector. A codebook without a lookup
# has no vector (VORBIS_invalid_stream, 21); no symbol is the packet's end
# where the packet is over, and an invalid stream otherwise. `value` is the
# symbol or -1.
def start.ended(reader: O.Reader) -> O.Reader:
  match reader:
    case O.Reader{+stream, +page, +first, O.Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      O.Reader{stream, page, first, O.Packet{in_seg, last, which, bytes, acc, valid}, Bool.pick(U32, U32.is_eq(value, 4294967295) && Bool.not(U32.is_eq(in_seg, 0) && last), 21, error), taken, value}

def start.looked(none: Bool, +coder: Coder, +reader: O.Reader) -> O.Reader:
  match none:
    case True{}: O.Reader.answer(O.failed(reader, 21), 4294967295)
    case False{}: start.ended(decode.raw(coder, reader))

def vector.start(+coder: Coder, +reader: O.Reader) -> O.Reader:
  start.looked(U32.is_eq(Coder.lookup(coder), 0), coder, reader)

# The reader and the floats after a vector: `fine` is the C answer.
type Vector is Data:
  Vector{reader: O.Reader, row: R.Row, fine: Bool}

# output[i] += values[z + i] + last, for i under n. In a sequence `last` is
# the value before, with the codebook's least value added unless `stepped`;
# otherwise 0.
def vector.added(n: Nat, +values: R.Row, +z: U32, +at: U32, +step: U32, +sequence: Bool, +stepped: Bool, +minimum: F32, +last: F32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      +value = ((R.Row.get(values, z) + last : F32))
      vector.added(k, values, (z + 1 : U32), (at + step : U32), step, sequence, stepped, minimum, Bool.pick(F32, sequence, Bool.pick(F32, stepped, value, (value + minimum : F32)), last),
        R.Row.set(row, at, (R.Row.get(row, at) + value : F32)))

def vector.put(fine: Bool, +coder: Coder, +reader: O.Reader, +row: R.Row, +at: U32, +length: U32, +step: U32, +stepped: Bool) -> Vector:
  match fine:
    case False{}: Vector{reader, row, False{}}
    case True{}: Vector{reader, vector.added(U32.to_nat(U32.min(length, Coder.dimensions(coder))), Coder.values(coder), (O.Reader.value(reader) * Coder.dimensions(coder) : U32), at, step, Coder.sequence(coder),
      stepped, Coder.minimum(coder), 0.0, row), True{}}

def vector.started(+coder: Coder, +reader: O.Reader, +row: R.Row, +at: U32, +length: U32, +step: U32, +stepped: Bool) -> Vector:
  vector.put(U32.is_ne(O.Reader.value(reader), 4294967295), coder, reader, row, at, length, step, stepped)

# codebook_decode(f, c, output, len): a vector's values added to the
# floats from `at`, as many as `length` and the codebook's dimensions
# allow.
def vector.decode(+coder: Coder, +reader: O.Reader, +row: R.Row, +at: U32, +length: U32) -> Vector:
  vector.started(coder, vector.start(coder, reader), row, at, length, 1, False{})

# codebook_decode_step(f, c, output, len, step): the same to every `step`th
# float. Here a sequence adds the value before as it is: the codebook's
# least value is not added again.
def vector.step(+coder: Coder, +reader: O.Reader, +row: R.Row, +at: U32, +length: U32, +step: U32) -> Vector:
  vector.started(coder, vector.start(coder, reader), row, at, length, step, True{})
