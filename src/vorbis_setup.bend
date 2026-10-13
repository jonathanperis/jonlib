# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: the
# beginning of start_decoder, from the identification header to the
# codebooks of the setup header and its time domain transfers. See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# The setup either goes on, fails as stb_vorbis fails (with its error code,
# which can be 0: start_decoder also answers FALSE without setting one), or
# is refused here, where stb_vorbis's answer is not one this port can give:
#   1  lookup1_values hangs on the C library's last bits, or is undefined
#      (see lookup1.values in vorbis_codebook.bend);
#   2  entries * dimensions passes the ints (undefined in C);
#   3  an allocation of more than 16 MiB, whose success depends on the host
#      (a vendor string, a comment, the comment list, a lookup's values);
#   4  a codebook of more than 2^19 entries, the port's budget.
import Base
import ./vorbis_ogg.bend as O
import ./vorbis_codebook.bend as C

type Status is Data:
  Going{}
  Failed{code: U32}
  Refused{why: U32}

def going(status: Status) -> Bool:
  match status:
    case Going{}: True{}
    case _: False{}

# A test of the setup and what it comes to where it fails.
type Check is Data:
  Check{failed: Bool, status: Status}

# The first check that failed, in order, or `found` where none does.
def checked(checks: +List<Check>, +found: Status, +open: Bool) -> Status:
  match checks:
    case Nil{}: found
    case Con{Check{+failed, +status}, +rest}: checked(rest, Bool.pick(Status, open && failed, status, found), open && Bool.not(failed))

def same(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{+x, +ra} Con{+y, +rb}: U32.is_eq(x, y) && same(ra, rb)
    case _ _: False{}

# "vorbis"
def named(bytes: +List<U32>) -> Bool:
  same(bytes, [118, 111, 114, 98, 105, 115])

# Whether the reader's last answer is TRUE.
def fine(reader: O.Reader) -> Bool:
  U32.is_eq(O.Reader.value(reader), 1)

# What the identification header says: the channels, the sample rate and
# the two block sizes.
type Head is Data:
  Head{channels: U32, rate: U32, blocksize_0: U32, blocksize_1: U32}

def Head.channels(head: Head) -> U32:
  Head{channels, _, _, _} = head
  channels

def Head.rate(head: Head) -> U32:
  Head{_, rate, _, _} = head
  rate

def Head.blocksize_0(head: Head) -> U32:
  Head{_, _, blocksize_0, _} = head
  blocksize_0

def Head.blocksize_1(head: Head) -> U32:
  Head{_, _, _, blocksize_1} = head
  blocksize_1

# The reader and how the setup stands.
type Step is Data:
  Step{reader: O.Reader, status: Status}

def Step.reader(step: Step) -> O.Reader:
  Step{reader, _} = step
  reader

def Step.status(step: Step) -> Status:
  Step{_, status} = step
  status

# The identification header read.
type Start is Data:
  Start{reader: O.Reader, status: Status, head: Head}

def Start.reader(start: Start) -> O.Reader:
  Start{reader, _, _} = start
  reader

def Start.status(start: Start) -> Status:
  Start{_, status, _} = start
  status

def Start.head(start: Start) -> Head:
  Start{_, _, head} = start
  head

# -----------------------------------------------------------------------------
# The identification header

# Whether the six bytes just taken are "fishea" and the two after them "d"
# and 0: the head of an Ogg skeleton.
def fishead(+taken: O.Reader) -> Bool:
  +d = O.get8(taken)
  fine(taken) && same(O.Reader.taken(taken), [102, 105, 115, 104, 101, 97]) && U32.is_eq(O.Reader.value(d), 100) && U32.is_eq(O.Reader.value(O.get8(d)), 0)

# The first page must be the stream's first, not its last, not continued,
# with one segment of 30 bytes; a first segment of 64 bytes that begins
# "fishead\0" is an Ogg skeleton (38), anything else an invalid first page
# (34). The header is read as bytes of the data, not as a packet: the packet
# type 1, "vorbis", version 0, the channels (1 to 16: 5 past that), the
# sample rate (not 0), three bitrates passed over, the two block sizes as
# exponents in a byte (6 to 13, the first not above the second: 20) and the
# framing bit.
def identification(+reader: O.Reader) -> Start:
  +paged = O.page.start(O.first.decode(reader, True{}))
  +begun = fine(paged)
  +error = O.Reader.error(paged)
  +flags = O.Page.flag(O.Reader.page(paged))
  +count = O.Page.count(O.Reader.page(paged))
  +first = O.entry(O.Page.segments(O.Reader.page(paged)))
  +skeleton = fishead(O.getn(paged, 6)) && U32.is_eq(first, 64)
  +kind = O.get8(paged)
  +header = O.Reader.value(kind)
  +name = O.getn(kind, 6)
  +whole = fine(name)
  +vorbis = named(O.Reader.taken(name))
  +version = O.get32(name)
  +zero = O.Reader.value(version)
  +channels = O.get8(version)
  +voices = O.Reader.value(channels)
  +rate = O.get32(channels)
  +hertz = O.Reader.value(rate)
  +sizes = O.get8(O.get32(O.get32(O.get32(rate))))
  +log0 = (O.Reader.value(sizes) .&. 15 : U32)
  +log1 = (O.Reader.value(sizes) >> 4n : U32)
  +framing = O.get8(sizes)
  +framed = O.Reader.value(framing)
  Start{framing, checked([Check{Bool.not(begun), Failed{error}}, Check{U32.is_eq((flags .&. 2 : U32), 0), Failed{34}}, Check{U32.is_ne((flags .&. 4 : U32), 0), Failed{34}},
      Check{U32.is_ne((flags .&. 1 : U32), 0), Failed{34}}, Check{U32.is_ne(count, 1), Failed{34}}, Check{U32.is_ne(first, 30) && skeleton, Failed{38}},
      Check{U32.is_ne(first, 30), Failed{34}}, Check{U32.is_ne(header, 1), Failed{34}}, Check{Bool.not(whole), Failed{10}}, Check{Bool.not(vorbis), Failed{34}},
      Check{U32.is_ne(zero, 0), Failed{34}}, Check{U32.is_eq(voices, 0), Failed{34}}, Check{(voices > 16 : U32), Failed{5}},
      Check{U32.is_eq(hertz, 0), Failed{34}}, Check{(log0 < 6 : U32) || (log0 > 13 : U32), Failed{20}}, Check{(log1 < 6 : U32) || (log1 > 13 : U32), Failed{20}}, Check{(log0 > log1 : U32), Failed{20}},
      Check{U32.is_eq((framed .&. 1 : U32), 0), Failed{34}}], Going{}, True{}),
    Head{voices, hertz, (1 << U32.to_nat(log0) : U32), (1 << U32.to_nat(log1) : U32)}}

# -----------------------------------------------------------------------------
# The comment header

# A length that sizes an allocation of length + 1 bytes: a negative int is
# VORBIS_outofmem (3: no bytes are asked for, or more than there can be),
# one over 16 MiB is refused.
def sized(+length: U32) -> Status:
  Bool.pick(Status, (length >= 2147483648 : U32), Failed{3}, Bool.pick(Status, (length > 16777216 : U32), Refused{3}, Going{}))

# The comments in turn: each a length and as many bytes, which are dropped
# (nothing of raylib reads them).
def comments(n: Nat, on: Bool, +status: Status, +reader: O.Reader) -> Step:
  match n on:
    case _ False{}: Step{reader, status}
    case 0n True{}: Step{reader, status}
    case 1n+k True{}:
      +length = O.packet.get32(reader)
      +next = sized(O.Reader.value(length))
      comments(k, going(next), next, O.packet.skipped(length, Bool.pick(U32, going(next), O.Reader.value(length), 0)))

# How many comments the list is sized for: none for a count that is not
# positive; 8 bytes each, which a count from 2^28 to 2^29 makes a negative
# size (3) and any other over 2^21 an allocation over 16 MiB, or one smaller
# than its list (refused).
def listed(+count: U32) -> Status:
  Bool.pick(Status, (count >= 2147483648 : U32) || (count <= 2097152 : U32), Going{}, Bool.pick(Status, (count >= 268435456 : U32) && (count < 536870912 : U32), Failed{3}, Refused{3}))

def comment.count(+count: U32) -> U32:
  Bool.pick(U32, (count >= 2147483648 : U32), 0, U32.min(count, 2097152))

# `reader` has just answered the count.
def comment.list(on: Bool, +status: Status, +reader: O.Reader) -> Step:
  match on:
    case False{}: Step{reader, status}
    case True{}: comments(U32.to_nat(comment.count(O.Reader.value(reader))), going(listed(O.Reader.value(reader))), listed(O.Reader.value(reader)), reader)

# After the comments: the framing bit (an EOP there is -1, whose bit is
# set), and the rest of the packet passed over.
def comment.end(on: Bool, +step: Step) -> Step:
  match on:
    case False{}: step
    case True{}:
      +framing = O.packet.get8(Step.reader(step))
      Step{O.packet.left(framing), Bool.pick(Status, U32.is_eq((O.Reader.value(framing) .&. 1 : U32), 0), Failed{20}, Going{})}

def comment.listed(+step: Step) -> Step:
  comment.end(going(Step.status(step)), step)

# The six bytes of a header packet's name: the reader after them, with
# whether they are "vorbis" as its answer.
def packet.named(+reader: O.Reader) -> O.Reader:
  +a = O.packet.get8(reader)
  +b = O.packet.get8(a)
  +c = O.packet.get8(b)
  +d = O.packet.get8(c)
  +e = O.packet.get8(d)
  +f = O.packet.get8(e)
  O.Reader.answer(f, Bool.pick(U32, named([O.Reader.value(a), O.Reader.value(b), O.Reader.value(c), O.Reader.value(d), O.Reader.value(e), O.Reader.value(f)]), 1, 0))

# The second page and its packet: the type 3, "vorbis", the vendor string
# (dropped) and the comments. start_decoder answers FALSE where the page or
# the packet does not start or the packet has no first segment, with
# whatever error that left (none for an empty packet).
def comment.header(+reader: O.Reader) -> Step:
  +paged = O.page.start(reader)
  +page_fine = fine(paged)
  +page_error = O.Reader.error(paged)
  +opened = O.packet.start(paged)
  +packet_fine = fine(opened)
  +packet_error = O.Reader.error(opened)
  +segment = O.segment.next(opened)
  +segment_length = O.Reader.value(segment)
  +segment_error = O.Reader.error(segment)
  +kind = O.packet.get8(segment)
  +header = O.Reader.value(kind)
  +name = packet.named(kind)
  +vorbis = fine(name)
  +length = O.packet.get32(name)
  +vendor = O.Reader.value(length)
  +status = checked([Check{Bool.not(page_fine), Failed{page_error}}, Check{Bool.not(packet_fine), Failed{packet_error}}, Check{U32.is_eq(segment_length, 0), Failed{segment_error}},
    Check{U32.is_ne(header, 3), Failed{20}}, Check{Bool.not(vorbis), Failed{20}}, Check{Bool.not(going(sized(vendor))), sized(vendor)}], Going{}, True{})
  comment.listed(comment.list(going(status), status, O.packet.get32(O.packet.skipped(length, Bool.pick(U32, going(status), vendor, 0)))))

# -----------------------------------------------------------------------------
# The setup header: codebooks

# A codebook as the setup leaves it: its tables (C.Book) and its lookup.
# `lookup` is 0 without one and 2 with one: a type 1 lookup is expanded to
# every entry's values as it is read (and stays 1, with no values, in a
# sparse codebook without a code).
type Codebook is Data:
  Codebook{dimensions: U32, entries: U32, book: C.Book, lookup: U32, minimum: F32, delta: F32, value_bits: U32, sequence: Bool, lookup_values: U32, multiplicands: +List<F32>}

# The codebooks read so far, the last first.
type Books is Data:
  Books{reader: O.Reader, status: Status, books: +List<Codebook>}

def Books.reader(state: Books) -> O.Reader:
  Books{reader, _, _} = state
  reader

def Books.status(state: Books) -> Status:
  Books{_, status, _} = state
  status

def Books.books(state: Books) -> +List<Codebook>:
  Books{_, _, books} = state
  books

# A codebook's first fields: the sync pattern "BCV", 16 bits of dimensions,
# 24 of entries, whether the lengths are ordered and, if not, whether the
# codebook is sparse.
type Lead is Data:
  Lead{reader: O.Reader, status: Status, dimensions: U32, entries: U32, ordered: Bool, sparse: Bool}

def Lead.reader(lead: Lead) -> O.Reader:
  Lead{reader, _, _, _, _, _} = lead
  reader

def Lead.status(lead: Lead) -> Status:
  Lead{_, status, _, _, _, _} = lead
  status

def Lead.dimensions(lead: Lead) -> U32:
  Lead{_, _, dimensions, _, _, _} = lead
  dimensions

def Lead.entries(lead: Lead) -> U32:
  Lead{_, _, _, entries, _, _} = lead
  entries

def Lead.sparse(lead: Lead) -> Bool:
  Lead{_, _, _, _, _, sparse} = lead
  sparse

# No dimension with entries is an invalid setup. No entry is
# VORBIS_outofmem: the lengths are an allocation of no byte, which
# setup_malloc answers with NULL (a sparse codebook's are a malloc(0), and
# its conversion to one that is not sparse the same NULL). More than 2^19
# entries are refused.
def book.lead(+reader: O.Reader) -> Lead:
  +b = O.bits.get(8, reader)
  +sync0 = O.Reader.value(b)
  +c = O.bits.get(8, b)
  +sync1 = O.Reader.value(c)
  +v = O.bits.get(8, c)
  +sync2 = O.Reader.value(v)
  +d0 = O.bits.get(8, v)
  +low = O.Reader.value(d0)
  +d1 = O.bits.get(8, d0)
  +dimensions = ((O.Reader.value(d1) << 8n) + low : U32)
  +e0 = O.bits.get(8, d1)
  +few = O.Reader.value(e0)
  +e1 = O.bits.get(8, e0)
  +some = O.Reader.value(e1)
  +e2 = O.bits.get(8, e1)
  +entries = (((O.Reader.value(e2) << 16n) + (some << 8n)) + few : U32)
  +order = O.bits.get(1, e2)
  +ordered = U32.is_eq(O.Reader.value(order), 1)
  +spare = Bool.pick(O.Reader, ordered, O.Reader.answer(order, 0), O.bits.get(1, order))
  +sparse = U32.is_eq(O.Reader.value(spare), 1)
  Lead{spare, checked([Check{U32.is_ne(sync0, 66), Failed{20}}, Check{U32.is_ne(sync1, 67), Failed{20}}, Check{U32.is_ne(sync2, 86), Failed{20}},
    Check{U32.is_eq(dimensions, 0) && U32.is_ne(entries, 0), Failed{20}}, Check{U32.is_eq(entries, 0), Failed{3}}, Check{(entries > 524288 : U32), Refused{4}}], Going{}, True{}),
    dimensions, entries, ordered, sparse}

# The lengths read: in the symbols' order, with how many have a code.
type Lengths is Data:
  Lengths{reader: O.Reader, status: Status, lengths: +List<U32>, total: U32}

def Lengths.status(read: Lengths) -> Status:
  Lengths{_, status, _, _} = read
  status

def Lengths.lengths(read: Lengths) -> +List<U32>:
  Lengths{_, _, lengths, _} = read
  lengths

def length.plus(+reader: O.Reader) -> O.Reader:
  O.Reader.answer(reader, (O.Reader.value(reader) + 1 : U32))

# A symbol's length: 5 bits and 1, or NO_CODE (255), nothing read, for one
# without a code.
def length.read(present: Bool, +reader: O.Reader) -> O.Reader:
  match present:
    case False{}: O.Reader.answer(reader, 255)
    case True{}: length.plus(O.bits.get(5, reader))

def length.present(+reader: O.Reader) -> O.Reader:
  length.read(U32.is_eq(O.Reader.value(reader), 1), reader)

# A sparse codebook says first, in a bit, whether the symbol has a code.
def length.flagged(sparse: Bool, +reader: O.Reader) -> O.Reader:
  match sparse:
    case False{}: length.read(True{}, reader)
    case True{}: length.present(O.bits.get(1, reader))

# The lengths one by one. A length of 32 is an invalid setup.
def lengths.each(n: Nat, on: Bool, +sparse: Bool, +reader: O.Reader, +total: U32, +acc: +List<U32>) -> Lengths:
  match n on:
    case _ False{}: Lengths{reader, Failed{20}, Nil{}, total}
    case 0n True{}: Lengths{reader, Going{}, List.reverse(&2, U32, acc), total}
    case 1n+k True{}:
      +next = length.flagged(sparse, reader)
      lengths.each(k, U32.is_ne(O.Reader.value(next), 32), sparse, next, (total + Bool.pick(U32, U32.is_eq(O.Reader.value(next), 255), 0, 1) : U32), Con{O.Reader.value(next), acc})

def repeated(n: Nat, +x: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: repeated(k, x, Con{x, acc})

# Ordered lengths: runs of symbols of one length, each run a length more
# than the one before, its count in as many bits as what is left to give
# takes. A run past the entries, or a length of 32, is an invalid setup.
# state: 0 a run is due, 1 the entries are all given, 2 invalid.
def ordered.runs(n: Nat, +state: U32, +entries: U32, +current: U32, +length: U32, +reader: O.Reader, +acc: +List<U32>) -> Lengths:
  match n:
    case 0n: Lengths{reader, Bool.pick(Status, U32.is_eq(state, 1), Going{}, Failed{20}), List.reverse(&2, U32, acc), 0}
    case 1n+k:
      +run = Bool.pick(O.Reader, U32.is_eq(state, 0), O.bits.get(C.ilog((entries - U32.min(current, entries) : U32)), reader), O.Reader.answer(reader, 0))
      +count = O.Reader.value(run)
      +bad = (length >= 32 : U32) || ((current + count) > entries : U32)
      ordered.runs(k, Bool.pick(U32, U32.is_ne(state, 0), state, Bool.pick(U32, bad, 2, Bool.pick(U32, U32.is_eq((current + count : U32), entries), 1, 0))), entries,
        Bool.pick(U32, U32.is_eq(state, 0) && Bool.not(bad), (current + count : U32), current), (length + 1 : U32), run,
        repeated(U32.to_nat(Bool.pick(U32, U32.is_eq(state, 0) && Bool.not(bad), count, 0)), length, acc))

def lengths.ordered(+entries: U32, +reader: O.Reader) -> Lengths:
  ordered.runs(33n, 0, entries, 0, (O.Reader.value(reader) + 1 : U32), reader, Nil{})

def lengths.read(ordered: Bool, +sparse: Bool, +entries: U32, +reader: O.Reader) -> Lengths:
  match ordered:
    case True{}: lengths.ordered(entries, O.bits.get(5, reader))
    case False{}: lengths.each(U32.to_nat(entries), True{}, sparse, reader, 0, Nil{})

def lengths.of(lead: Lead) -> Lengths:
  Lead{reader, _, _, entries, ordered, sparse} = lead
  lengths.read(ordered, sparse, entries, reader)

# entries * dimensions as an int, None where it passes the ints.
def product(+entries: U32, +dimensions: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, U32.is_ne(dimensions, 0) && (entries > (2147483647 / U32.max(dimensions, 1)) : U32), None{}, Some{(entries * dimensions : U32)})

# The reader with a lookup's values as they are read, value_bits each.
type Words is Data:
  Words{reader: O.Reader, values: +List<U32>}

def Words.reader(words: Words) -> O.Reader:
  Words{reader, _} = words
  reader

def Words.values(words: Words) -> +List<U32>:
  Words{_, values} = words
  values

def words.read(n: Nat, +bits: U32, +reader: O.Reader, +acc: +List<U32>) -> Words:
  match n:
    case 0n: Words{reader, List.reverse(&2, U32, acc)}
    case 1n+k:
      +next = O.bits.get(bits, reader)
      words.read(k, bits, next, Con{O.Reader.value(next), acc})

def latest(values: +List<F32>) -> F32:
  match values:
    case Nil{}: 0.0
    case Con{+x, _}: x

# val = mults[off]*delta + minimum + last, where last is the value before
# it in a sequence and 0 otherwise.
def scaled(+word: U32, +delta: F32, +minimum: F32, +sequence: Bool, +before: +List<F32>) -> F32:
  ((((U32.to_f32(word) * delta : F32) + minimum : F32) + Bool.pick(F32, sequence, latest(before), 0.0)) : F32)

# A type 2 lookup: a value for each of its entries' dimensions, in the
# order read.
def values.plain(words: +List<U32>, +delta: F32, +minimum: F32, +sequence: Bool, +acc: +List<F32>) -> +List<F32>:
  match words:
    case Nil{}: List.reverse(&2, F32, acc)
    case Con{+w, +rest}: values.plain(rest, delta, minimum, sequence, Con{scaled(w, delta, minimum, sequence, acc), acc})

def table.filled(words: +List<U32>, +i: U32, table: Array<U32>) -> Array<U32>:
  match words:
    case Nil{}: table
    case Con{+w, +rest}: table.filled(rest, (i + 1 : U32), Array.set(U32, table, i, w))

def expand.put(got: Array<U32> & U32, +delta: F32, +minimum: F32, +sequence: Bool, +acc: +List<F32>) -> Array<U32> & +List<F32>:
  (table, word) = got
  (table, Con{scaled(word, delta, minimum, sequence, acc), acc})

# An entry's values: one for each dimension, the entry's number read as
# digits in the base of the lookup's values, the lowest first.
def expand.entry(n: Nat, +z: U32, +base: U32, +delta: F32, +minimum: F32, +sequence: Bool, state: Array<U32> & +List<F32>) -> Array<U32> & +List<F32>:
  match n state:
    case 0n Tuple{table, +acc}: (table, acc)
    case 1n+k Tuple{table, +acc}: expand.entry(k, (z / base : U32), base, delta, minimum, sequence, expand.put(Array.get(U32, table, (z % base : U32)), delta, minimum, sequence, acc))

# A type 1 lookup expanded: every entry's values, one entry after another.
# In a sequence each value adds the one before it, and stb_vorbis does not
# start again at 0 with a new entry.
def expand.all(symbols: +List<U32>, +dimensions: U32, +base: U32, +delta: F32, +minimum: F32, +sequence: Bool, state: Array<U32> & +List<F32>) -> +List<F32>:
  match symbols state:
    case Nil{} Tuple{_, +acc}: List.reverse(&2, F32, acc)
    case Con{+z, +rest} Tuple{table, +acc}: expand.all(rest, dimensions, base, delta, minimum, sequence, expand.entry(U32.to_nat(dimensions), z, base, delta, minimum, sequence, (table, acc)))

def range(n: Nat, +from: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: range(k, (from + 1 : U32), Con{from, acc})

# Whether `div *= lookup_values` between an entry's dimensions passes the
# unsigned ints (`div > UINT_MAX / lookup_values` before it): an invalid
# setup. It is the same for every entry.
def div.over(n: Nat, +base: U32, +div: U32, +over: Bool) -> Bool:
  match n:
    case 0n: over
    case 1n+k: div.over(k, base, Bool.pick(U32, (div > (4294967295 / U32.max(base, 1)) : U32), div, (div * base : U32)), over || (div > (4294967295 / U32.max(base, 1)) : U32))

# The entries a type 1 lookup is expanded for: every one in the symbols'
# order, or a sparse codebook's in its sorted table's.
def rows(+book: C.Book, +entries: U32) -> +List<U32>:
  Bool.pick(+List<U32>, C.Book.sparse(book), C.Book.sorted_values(book), range(U32.to_nat(entries), 0, Nil{}))

def rows.count(+book: C.Book, +entries: U32) -> U32:
  Bool.pick(U32, C.Book.sparse(book), C.Book.count(book), entries)

# kind: 0 a type 2 lookup, 1 a type 1 lookup of a codebook without rows (it
# stays type 1, without values), 2 one whose divisor passes the ints, 3 a
# type 1 lookup to expand.
def lookup.made(kind: U32, +words: Words, +minimum: F32, +delta: F32, +value_bits: U32, +sequence: Bool, +count: U32, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match kind:
    case 0: Books{Words.reader(words), Going{}, Con{Codebook{dimensions, entries, book, 2, minimum, delta, value_bits, sequence, count, values.plain(Words.values(words), delta, minimum, sequence, Nil{})}, acc}}
    case 1: Books{Words.reader(words), Going{}, Con{Codebook{dimensions, entries, book, 1, minimum, delta, value_bits, sequence, count, Nil{}}, acc}}
    case 2: Books{Words.reader(words), Failed{20}, acc}
    case _: Books{Words.reader(words), Going{}, Con{Codebook{dimensions, entries, book, 2, minimum, delta, value_bits, sequence, count,
      expand.all(rows(book, entries), dimensions, count, delta, minimum, sequence, (table.filled(Words.values(words), 0, Array.new(U32, U32.to_nat(C.ilog((count - 1 : U32))), 0)), Nil{}))}, acc}}

# The lookup's values are read (as many as it has, value_bits each) and
# made into the codebook's.
def lookup.values(on: Bool, +status: Status, +lookup: U32, +count: U32, +reader: O.Reader, +minimum: F32, +delta: F32, +value_bits: U32, +sequence: Bool, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match on:
    case False{}: Books{reader, status, acc}
    case True{}:
      lookup.made(Bool.pick(U32, U32.is_eq(lookup, 2), 0, Bool.pick(U32, U32.is_eq(rows.count(book, entries), 0), 1, Bool.pick(U32, div.over(U32.to_nat(U32.min((dimensions - 1 : U32), 64)), count, 1, False{}), 2, 3))),
        words.read(U32.to_nat(count), value_bits, reader, Nil{}), minimum, delta, value_bits, sequence, count, book, dimensions, entries, acc)

# How many values the lookup has: None where the port does not answer
# (lookup1_values for type 1, entries * dimensions past the ints for type
# 2). -1 and 0 are invalid setups; more than 2^22 floats for the codebook
# are an allocation over 16 MiB.
def lookup.sized(count: Maybe<U32>, +lookup: U32, +reader: O.Reader, +minimum: F32, +delta: F32, +value_bits: U32, +sequence: Bool, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match count:
    case None{}: Books{reader, Refused{lookup}, acc}
    case Some{+n}:
      +status = checked([Check{(n >= 2147483648 : U32) || U32.is_eq(n, 0), Failed{20}}, Check{U32.is_eq(lookup, 2) && (n > 4194304 : U32), Refused{3}},
        Check{U32.is_eq(lookup, 1) && (dimensions > (4194304 / U32.max(rows.count(book, entries), 1)) : U32), Refused{3}}], Going{}, True{})
      lookup.values(going(status), status, lookup, n, reader, minimum, delta, value_bits, sequence, book, dimensions, entries, acc)

# A lookup of type 1 or 2: two packed floats (the least value and the step
# between values), the bits of a value less 1, whether the values are a
# sequence, and the values.
def lookup.read(+lookup: U32, +reader: O.Reader, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  +low = O.bits.get(32, reader)
  +least = O.Reader.value(low)
  +step = O.bits.get(32, low)
  +delta = O.Reader.value(step)
  +width = O.bits.get(4, step)
  +value_bits = (O.Reader.value(width) + 1 : U32)
  +sequence = O.bits.get(1, width)
  lookup.sized(Bool.pick(Maybe<U32>, U32.is_eq(lookup, 1), C.lookup1.values(entries, dimensions), product(entries, dimensions)), lookup, sequence, C.float32.unpack(least), C.float32.unpack(delta),
    value_bits, U32.is_eq(O.Reader.value(sequence), 1), book, dimensions, entries, acc)

# kind: the lookup type, 4 bits. Over 2 is an invalid setup.
def lookup.kind(kind: U32, +reader: O.Reader, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match kind:
    case 0: Books{reader, Going{}, Con{Codebook{dimensions, entries, book, 0, 0.0, 0.0, 0, False{}, 0, Nil{}}, acc}}
    case 1: lookup.read(1, reader, book, dimensions, entries, acc)
    case 2: lookup.read(2, reader, book, dimensions, entries, acc)
    case _: Books{reader, Failed{20}, acc}

def book.looked(+reader: O.Reader, +book: C.Book, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  lookup.kind(O.Reader.value(reader), reader, book, dimensions, entries, acc)

# Lengths that are no tree are an invalid setup.
def book.tabled(book: Maybe<C.Book>, +reader: O.Reader, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match book:
    case None{}: Books{reader, Failed{20}, acc}
    case Some{+b}: book.looked(O.bits.get(4, reader), b, dimensions, entries, acc)

def book.built(on: Bool, +status: Status, +reader: O.Reader, +lengths: +List<U32>, +sparse: Bool, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  match on:
    case False{}: Books{reader, status, acc}
    case True{}: book.tabled(C.book.of(lengths, sparse), reader, dimensions, entries, acc)

# A sparse codebook with a code for a quarter of its symbols or more is
# kept as one that is not sparse.
def book.coded(read: Lengths, +sparse: Bool, +dimensions: U32, +entries: U32, +acc: +List<Codebook>) -> Books:
  Lengths{+reader, +status, +lengths, +total} = read
  book.built(going(status), status, reader, lengths, sparse && (total < (entries >> 2n) : U32), dimensions, entries, acc)

def book.led(on: Bool, +lead: Lead, +acc: +List<Codebook>) -> Books:
  match on:
    case False{}: Books{Lead.reader(lead), Lead.status(lead), acc}
    case True{}: book.coded(lengths.of(lead), Lead.sparse(lead), Lead.dimensions(lead), Lead.entries(lead), acc)

def book.leading(+lead: Lead, +acc: +List<Codebook>) -> Books:
  book.led(going(Lead.status(lead)), lead, acc)

# A codebook read from the setup header and put before the others.
def book.read(+reader: O.Reader, +acc: +List<Codebook>) -> Books:
  book.leading(book.lead(reader), acc)

def books.each(n: Nat, on: Bool, +state: Books) -> Books:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = book.read(Books.reader(state), Books.books(state))
      books.each(k, going(Books.status(next)), next)

# -----------------------------------------------------------------------------
# The setup header, up to the floors

# The time domain transfers: a count of 6 bits and 1, and 16 bits each that
# must be 0.
def transfers(n: Nat, +reader: O.Reader, +bad: Bool) -> Step:
  match n:
    case 0n: Step{reader, Bool.pick(Status, bad, Failed{20}, Going{})}
    case 1n+k:
      +next = O.bits.get(16, reader)
      transfers(k, Bool.pick(O.Reader, bad, reader, next), bad || U32.is_ne(O.Reader.value(next), 0))

def transfers.read(+reader: O.Reader) -> Step:
  transfers(U32.to_nat((O.Reader.value(reader) + 1 : U32)), reader, False{})

# What this part of the setup gives: the reader after the time domain
# transfers, the identification header's fields and the codebooks, in
# their order.
type Setup is Data:
  Setup{reader: O.Reader, status: Status, head: Head, books: +List<Codebook>}

def Setup.reader(setup: Setup) -> O.Reader:
  Setup{reader, _, _, _} = setup
  reader

def Setup.status(setup: Setup) -> Status:
  Setup{_, status, _, _} = setup
  status

def Setup.head(setup: Setup) -> Head:
  Setup{_, _, head, _} = setup
  head

def Setup.books(setup: Setup) -> +List<Codebook>:
  Setup{_, _, _, books} = setup
  books

def setup.ended(step: Step, +head: Head, +books: +List<Codebook>) -> Setup:
  Step{reader, status} = step
  Setup{reader, status, head, books}

def setup.booked(on: Bool, +state: Books, +head: Head) -> Setup:
  match on:
    case False{}: Setup{Books.reader(state), Books.status(state), head, List.reverse(&2, Codebook, Books.books(state))}
    case True{}: setup.ended(transfers.read(O.bits.get(6, Books.reader(state))), head, List.reverse(&2, Codebook, Books.books(state)))

def setup.booking(+state: Books, +head: Head) -> Setup:
  setup.booked(going(Books.status(state)), state, head)

# The third packet: the type 5, "vorbis", a count of codebooks of 8 bits
# and 1, the codebooks, the time domain transfers.
def setup.header(on: Bool, +step: Step, +head: Head) -> Setup:
  match on:
    case False{}: Setup{Step.reader(step), Step.status(step), head, Nil{}}
    case True{}:
      +opened = O.packet.start(Step.reader(step))
      +started = fine(opened)
      +error = O.Reader.error(opened)
      +kind = O.packet.get8(opened)
      +header = O.Reader.value(kind)
      +name = packet.named(kind)
      +vorbis = fine(name)
      +count = O.bits.get(8, name)
      +status = checked([Check{Bool.not(started), Failed{error}}, Check{U32.is_ne(header, 5), Failed{20}}, Check{Bool.not(vorbis), Failed{20}}], Going{}, True{})
      setup.booking(books.each(U32.to_nat((O.Reader.value(count) + 1 : U32)), going(status), Books{count, status, Nil{}}), head)

def setup.commented(+step: Step, +head: Head) -> Setup:
  setup.header(going(Step.status(step)), step, head)

def setup.identified(on: Bool, +start: Start) -> Setup:
  match on:
    case False{}: Setup{Start.reader(start), Start.status(start), Start.head(start), Nil{}}
    case True{}: setup.commented(comment.header(Start.reader(start)), Start.head(start))

def setup.started(+start: Start) -> Setup:
  setup.identified(going(Start.status(start)), start)

# start_decoder over the data, as far as this part goes: the three headers
# up to the floors.
def setup.codebooks(+bytes: +List<U32>) -> Setup:
  setup.started(identification(O.open(bytes)))
