# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: a
# stream's length (stb_vorbis_stream_length_in_samples, with
# vorbis_find_page, crc32_init and crc32_update). See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# C ints are U32 two's-complement words.
import Base
import ./vorbis_ogg.bend as O
import ./vorbis_packet.bend as K
import ./vorbis_frame.bend as Fr
import ./store.bend as R

# -----------------------------------------------------------------------------
# The pages' checksum

# A table entry: eight turns of the polynomial 0x04c11db7.
def crc.entry(n: Nat, +s: U32) -> U32:
  match n:
    case 0n: s
    case 1n+k: crc.entry(k, ((s << 1n) .^. Bool.pick(U32, (s >= 2147483648 : U32), 79764919, 0) : U32))

def crc.entries(n: Nat, +i: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: crc.entries(k, (i + 1 : U32), Con{crc.entry(8n, (i << 24n : U32)), acc})

# crc32_init: crc_table.
def crc.table() -> R.Index:
  R.Index.from(crc.entries(256n, 0, Nil{}), 0)

# crc32_update(crc, byte).
def crc.update(+table: R.Index, +crc: U32, +byte: U32) -> U32:
  ((crc << 8n) .^. R.Index.get(table, ((byte .&. 255) .^. (crc >> 24n) : U32)) : U32)

def crc.zeros(n: Nat, +table: R.Index, +crc: U32) -> U32:
  match n:
    case 0n: crc
    case 1n+k: crc.zeros(k, table, crc.update(table, crc, 0))

def crc.each(bytes: +List<U32>, +table: R.Index, +crc: U32) -> U32:
  match bytes:
    case Nil{}: crc
    case Con{+b, +rest}: crc.each(rest, table, crc.update(table, crc, b))

# The checksum over n bytes as get8 gives them (the data's while it lasts,
# zeros past its end), their sum, and whether the data ended in them.
type Walk is Data:
  Walk{crc: U32, sum: U32, short: Bool}

def Walk.crc(walk: Walk) -> U32:
  Walk{crc, _, _} = walk
  crc

def Walk.sum(walk: Walk) -> U32:
  Walk{_, sum, _} = walk
  sum

def Walk.short(walk: Walk) -> Bool:
  Walk{_, _, short} = walk
  short

def crc.walk(n: Nat, bytes: +List<U32>, +table: R.Index, +crc: U32, +sum: U32) -> Walk:
  match n bytes:
    case 0n _: Walk{crc, sum, False{}}
    case 1n+k Nil{}: Walk{crc.zeros(k, table, crc.update(table, crc, 0)), sum, True{}}
    case 1n+k Con{+b, +rest}: crc.walk(k, rest, table, crc.update(table, crc, b), (sum + b : U32))

# -----------------------------------------------------------------------------
# vorbis_find_page

# What an 'O' in the data is: 0 no page (the search goes on after it), 1 a
# page, which ends at `end` and is or is not flagged as the stream's last,
# 2 the search's end (the data ended in it).
type Tried is Data:
  Tried{verdict: U32, end: U32, last: Bool}

def Tried.verdict(tried: Tried) -> U32:
  Tried{verdict, _, _} = tried
  verdict

def Tried.end(tried: Tried) -> U32:
  Tried{_, end, _} = tried
  end

def Tried.last(tried: Tried) -> Bool:
  Tried{_, _, last} = tried
  last

# The bytes after the 'O' against "ggS": 0 they are there, 1 another byte,
# 2 the data's end.
def capture.kind(expected: +List<U32>, bytes: +List<U32>) -> U32:
  match expected bytes:
    case Nil{} _: 0
    case Con{_, _} Nil{}: 2
    case Con{+e, +more} Con{+b, +rest}: Bool.pick(U32, U32.is_eq(e, b), capture.kind(more, rest), 1)

def taken(n: Nat, bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n bytes:
    case 1n+k Con{+b, +rest}: taken(k, rest, Con{b, acc})
    case _ _: List.reverse(&2, U32, acc)

def counted(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

def head(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, xs, U32.to_nat(i)))

# The checksum the page states: bytes 22 to 25 of its header.
def goal.of(+header: +List<U32>) -> U32:
  (((nth(header, 18) .|. (nth(header, 19) << 8n)) .|. (nth(header, 20) << 16n)) .|. (nth(header, 21) << 24n) : U32)

# The checksum of the header's 27 bytes with those four as zeros. `header`
# is its 23 bytes after the capture pattern.
def crc.header(+header: +List<U32>, +table: R.Index) -> U32:
  crc.update(table, crc.zeros(4n, table, crc.each(taken(18n, header, Nil{}), table, crc.each([79, 103, 103, 83], table, 0))), nth(header, 22))

# A page whose checksum is the one it states ends where the reader is after
# its body: no further than the data's end.
def page.checked(body: Walk, +walk: Walk, +header: +List<U32>, +retry: U32, +length: U32) -> Tried:
  Walk{+crc, _, _} = body
  Bool.pick(Tried, U32.is_eq(crc, goal.of(header)), Tried{1, U32.min((((retry + 26) + nth(header, 22)) + Walk.sum(walk) : U32), length), U32.is_ne((nth(header, 1) .&. 4 : U32), 0)}, Tried{0, 0, False{}})

# The page's body: its checksum decides.
def page.bodied(sure: Bool, +walk: Walk, +body: +List<U32>, +header: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  match sure:
    case False{}: Tried{2, 0, False{}}
    case True{}: page.checked(crc.walk(U32.to_nat(Walk.sum(walk)), List.drop(&2, U32, body, U32.to_nat(nth(header, 22))), table, Walk.crc(walk), 0), walk, header, retry, length)

# The segment table: a body whose length is known only past the data's end
# ends the search.
def page.tabled(+walk: Walk, +body: +List<U32>, +header: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  page.bodied(Bool.not(U32.is_ne(Walk.sum(walk), 0) && Walk.short(walk)), walk, body, header, retry, length, table)

# The header's 23 bytes after the capture pattern, and what follows them. A
# stream structure version other than 0 is no page.
def page.headed(kind: U32, +header: +List<U32>, +body: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  match kind:
    case 0: page.tabled(crc.walk(U32.to_nat(nth(header, 22)), body, table, crc.header(header, table), 0), body, header, retry, length, table)
    case 1: Tried{0, 0, False{}}
    case _: Tried{2, 0, False{}}

def page.captured(kind: U32, +after: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  match kind:
    case 0: page.headed(Bool.pick(U32, (counted(taken(23n, after, Nil{}), 0) < 23 : U32), 2, Bool.pick(U32, U32.is_ne(head(after), 0), 1, 0)), taken(23n, after, Nil{}), List.drop(&2, U32, after, 23n), retry, length, table)
    case 1: Tried{0, 0, False{}}
    case _: Tried{2, 0, False{}}

# An 'O' further than the data is long (the offset after it, less 25, as an
# unsigned int: one in the data's first 24 bytes) ends the search.
def page.sized(off: Bool, +rest: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  match off:
    case True{}: Tried{2, 0, False{}}
    case False{}: page.captured(capture.kind([103, 103, 83], rest), List.drop(&2, U32, rest, 3n), retry, length, table)

# `rest` is the data after the byte, `retry` its offset.
def page.try(candidate: Bool, +rest: +List<U32>, +retry: U32, +length: U32, +table: R.Index) -> Tried:
  match candidate:
    case False{}: Tried{0, 0, False{}}
    case True{}: page.sized(((retry - 25 : U32) > length : U32), rest, retry, length, table)

# A page found: where it begins and ends and whether it is flagged as the
# last.
type Found is Data:
  Found{found: Bool, at: U32, end: U32, last: Bool}

def Found.found(found: Found) -> Bool:
  Found{found, _, _, _} = found
  found

def Found.at(found: Found) -> U32:
  Found{_, at, _, _} = found
  at

def Found.end(found: Found) -> U32:
  Found{_, _, end, _} = found
  end

def Found.last(found: Found) -> Bool:
  Found{_, _, _, last} = found
  last

# vorbis_find_page from the offset `at`, where `bytes` are: the first 'O'
# that begins a page whose checksum is the one it states.
def page.scan(bytes: +List<U32>, on: Bool, +result: Found, +at: U32, +length: U32, +table: R.Index) -> Found:
  match bytes on:
    case _ False{}: result
    case Nil{} True{}: Found{False{}, 0, 0, False{}}
    case Con{+b, +rest} True{}:
      +tried = page.try(U32.is_eq(b, 79), rest, (at + 1 : U32), length, table)
      page.scan(rest, U32.is_eq(Tried.verdict(tried), 0), Found{U32.is_eq(Tried.verdict(tried), 1), at, Tried.end(tried), Tried.last(tried)}, (at + 1 : U32), length, table)

# set_file_offset(f, at) and vorbis_find_page: an offset at the data's end
# or past it finds nothing.
def page.from(inside: Bool, +bytes: +List<U32>, +at: U32, +length: U32, +table: R.Index) -> Found:
  match inside:
    case False{}: Found{False{}, 0, 0, False{}}
    case True{}: page.scan(List.drop(&2, U32, bytes, U32.to_nat(at)), True{}, Found{False{}, 0, 0, False{}}, at, length, table)

def page.find(+bytes: +List<U32>, +at: U32, +length: U32, +table: R.Index) -> Found:
  page.from((at < length : U32), bytes, at, length, table)

# -----------------------------------------------------------------------------
# stb_vorbis_stream_length_in_samples

# The pages after one that is not flagged as the last, as long as there is
# one: the last of them found. A page is 27 bytes at least: the data's
# bytes outlast its pages.
def pages.follow(fuel: +List<U32>, on: Bool, +page: Found, +bytes: +List<U32>, +length: U32, +table: R.Index) -> Found:
  match fuel on:
    case _ False{}: page
    case Nil{} True{}: page
    case Con{_, +more} True{}:
      +next = page.find(bytes, Found.end(page), length, table)
      pages.follow(more, Found.found(next) && Bool.not(Found.last(next)), Bool.pick(Found, Found.found(next), next, page), bytes, length, table)

# A word of four bytes, the lowest first.
def word(+bytes: +List<U32>) -> U32:
  (((nth(bytes, 0) .|. (nth(bytes, 1) << 8n)) .|. (nth(bytes, 2) << 16n)) .|. (nth(bytes, 3) << 24n) : U32)

# The decoder's reader after the call, the length kept (total_samples: 0
# for none yet, all ones for one that is not known) and the C answer.
type Length is Data:
  Length{reader: O.Reader, total: U32, value: U32}

def Length.reader(found: Length) -> O.Reader:
  Length{reader, _, _} = found
  reader

def Length.total(found: Length) -> U32:
  Length{_, total, _} = found
  total

def Length.value(found: Length) -> U32:
  Length{_, _, value} = found
  value

# The reader back at its offset, as set_file_offset leaves it, with the
# error and the length kept.
def length.ended(+reader: O.Reader, +failed: Bool, +total: U32) -> Length:
  Length{O.offset.set(Bool.pick(O.Reader, failed, O.failed(reader, 36), reader), O.Stream.at(O.Reader.stream(reader))), total, Bool.pick(U32, U32.is_eq(total, 4294967295), 0, total)}

# The last page's granule position: all ones is no position
# (VORBIS_cant_find_last_page); one past 32 bits is 0xfffffffe.
def length.read(+reader: O.Reader, +lo: U32, +hi: U32) -> Length:
  length.ended(reader, U32.is_eq(lo, 4294967295) && U32.is_eq(hi, 4294967295), Bool.pick(U32, U32.is_eq(lo, 4294967295) && U32.is_eq(hi, 4294967295), 4294967295, Bool.pick(U32, U32.is_ne(hi, 0), 4294967294, lo)))

def length.paged(page: Found, +reader: O.Reader, +bytes: +List<U32>) -> Length:
  Found{_, +at, _, _} = page
  length.read(reader, word(List.drop(&2, U32, bytes, U32.to_nat((at + 6 : U32)))), word(List.drop(&2, U32, bytes, U32.to_nat((at + 10 : U32)))))

def length.found(found: Bool, +page: Found, +reader: O.Reader, +bytes: +List<U32>, +length: U32, +table: R.Index) -> Length:
  match found:
    case False{}: length.ended(reader, True{}, 4294967295)
    case True{}: length.paged(pages.follow(bytes, Bool.not(Found.last(page)), page, bytes, length, table), reader, bytes)

def length.searched(+page: Found, +reader: O.Reader, +bytes: +List<U32>, +length: U32, +table: R.Index) -> Length:
  length.found(Found.found(page), page, reader, bytes, length, table)

# The search begins 64 KiB before the data's end, or where the audio does
# if that is later.
def length.sought(+reader: O.Reader, +first: U32, +bytes: +List<U32>, +length: U32, +table: R.Index) -> Length:
  length.searched(page.find(bytes, Bool.pick(U32, (length >= 65536 : U32) && ((length - 65536 : U32) >= first : U32), (length - 65536 : U32), first), length, table), reader, bytes, length, table)

def length.kept(known: Bool, +reader: O.Reader, +first: U32, +total: U32) -> Length:
  match known:
    case True{}: Length{reader, total, Bool.pick(U32, U32.is_eq(total, 4294967295), 0, total)}
    case False{}: length.sought(reader, first, O.Stream.bytes(O.Reader.stream(reader)), O.Stream.length(O.Reader.stream(reader)), crc.table())

# stb_vorbis_stream_length_in_samples(f): the granule position of the last
# page, searched for once. `first` is first_audio_page_offset and `total`
# the length kept by the call before (0 at first).
def length.samples(+reader: O.Reader, +first: U32, +total: U32) -> Length:
  length.kept(U32.is_ne(total, 0), reader, first, total)

# A decoder after its stream's length is asked for, the length kept and the
# C answer.
type Measured is Data:
  Measured{frames: Fr.Frames, total: U32, value: U32}

def frames.with(frames: Fr.Frames, +reader: O.Reader) -> Fr.Frames:
  match frames:
    case Fr.Frames{K.State{_, +rows, +loc, +known, +discard}, +previous, +length, +start, +end, +output}: Fr.Frames{K.State{reader, rows, loc, known, discard}, previous, length, start, end, output}

def stream.measured(found: Length, +frames: Fr.Frames) -> Measured:
  Length{+reader, +total, +value} = found
  Measured{frames.with(frames, reader), total, value}

# stb_vorbis_stream_length_in_samples for a decoder: `first` is where its
# audio begins (Fr.Ready's) and `total` what the call before kept (0 at
# first). The answer is 0 for a length that is not known.
def stream.length(+frames: Fr.Frames, +first: U32, +total: U32) -> Measured:
  stream.measured(length.samples(Fr.Frames.reader(frames), first, total), frames)
