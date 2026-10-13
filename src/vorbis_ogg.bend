# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: how the
# decoder reads its data, as bytes (get8, get32, getn, skip), as Ogg pages
# (capture_pattern, start_page_no_capturepattern, start_page), as the
# packets laid over the pages' segments (start_packet, maybe_start_packet,
# next_segment, get8_packet_raw, get8_packet, get32_packet, flush_packet)
# and as bits (get_bits). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# The data is a memory stream (stb_vorbis_open_memory), which is what raylib
# opens. C ints are U32 two's-complement words: -1 is 4294967295 (a next
# segment that is on no page yet, the end of a packet, bits that ran out)
# and -2 is 4294967294 (no known sample position).
#
# Each function takes the reader and gives it back with its C answer in
# `value` (0 for FALSE).
import Base

# The data: every byte, the bytes from the position on, the position
# (stream - stream_start; a skip can leave it past the length, where every
# read answers 0), the length, and whether a read met the end.
type Stream is Data:
  Stream{bytes: +List<U32>, rest: +List<U32>, at: U32, length: U32, eof: Bool}

# The page the reader is on: page_flag, segment_count, the 255 places of
# segments (a page writes as many as it has: the others keep what an earlier
# page left), next_seg, the page's sequence number (last_page),
# end_seg_with_known_loc and known_loc_for_packet.
type Page is Data:
  Page{flag: U32, count: U32, segments: +List<U32>, next: U32, sequence: U32, known_seg: U32, known_loc: U32}

# first_decode, and what it makes each page note (p_first): where the page
# begins and ends and its granule position's low word.
type First is Data:
  First{decoding: Bool, start: U32, end: U32, sample: U32}

# The packet being read: bytes_in_seg, last_seg, last_seg_which,
# packet_bytes, and the bits at hand (acc, valid_bits).
type Packet is Data:
  Packet{in_seg: U32, last: Bool, which: U32, bytes: U32, acc: U32, valid: U32}

# `error` is stb_vorbis's (0 for none), `taken` the bytes the last getn that
# succeeded gave, `value` the last answer.
type Reader is Data:
  Reader{stream: Stream, page: Page, first: First, packet: Packet, error: U32, taken: +List<U32>, value: U32}

def Reader.value(reader: Reader) -> U32:
  Reader{_, _, _, _, _, _, value} = reader
  value

def Reader.error(reader: Reader) -> U32:
  Reader{_, _, _, _, error, _, _} = reader
  error

def Reader.taken(reader: Reader) -> +List<U32>:
  Reader{_, _, _, _, _, taken, _} = reader
  taken

def Reader.stream(reader: Reader) -> Stream:
  Reader{stream, _, _, _, _, _, _} = reader
  stream

def Reader.page(reader: Reader) -> Page:
  Reader{_, page, _, _, _, _, _} = reader
  page

def Reader.packet(reader: Reader) -> Packet:
  Reader{_, _, _, packet, _, _, _} = reader
  packet

def Stream.eof(stream: Stream) -> Bool:
  Stream{_, _, _, _, eof} = stream
  eof

def Stream.rest(stream: Stream) -> +List<U32>:
  Stream{_, rest, _, _, _} = stream
  rest

def Stream.at(stream: Stream) -> U32:
  Stream{_, _, at, _, _} = stream
  at

def Page.flag(page: Page) -> U32:
  Page{flag, _, _, _, _, _, _} = page
  flag

def Page.next(page: Page) -> U32:
  Page{_, _, _, next, _, _, _} = page
  next

def Packet.last(packet: Packet) -> Bool:
  Packet{_, last, _, _, _, _} = packet
  last

def Packet.in_seg(packet: Packet) -> U32:
  Packet{in_seg, _, _, _, _, _} = packet
  in_seg

def Packet.valid(packet: Packet) -> U32:
  Packet{_, _, _, _, _, valid} = packet
  valid

# The reader with another answer.
def Reader.answer(reader: Reader, +value: U32) -> Reader:
  Reader{stream, page, first, packet, error, taken, _} = reader
  Reader{stream, page, first, packet, error, taken, value}

# error(f, e): the error is kept and the answer is FALSE.
def failed(reader: Reader, +code: U32) -> Reader:
  Reader{stream, page, first, packet, _, taken, _} = reader
  Reader{stream, page, first, packet, code, taken, 0}

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

def counted(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

# A reader at the start of the data, as vorbis_init and
# stb_vorbis_open_memory leave it: everything 0.
def open(+bytes: +List<U32>) -> Reader:
  Reader{Stream{bytes, bytes, 0, counted(bytes, 0), False{}}, Page{0, 0, zeros(255n, Nil{}), 0, 0, 0, 0}, First{False{}, 0, 0, 0}, Packet{0, False{}, 0, 0, 0, 0}, 0, Nil{}, 0}

# first_decode = on.
def first.decode(reader: Reader, +on: Bool) -> Reader:
  match reader:
    case Reader{+stream, +page, First{_, +start, +end, +sample}, +packet, +error, +taken, +value}:
      Reader{stream, page, First{on, start, end, sample}, packet, error, taken, value}

# -----------------------------------------------------------------------------
# Bytes

# get8: the next byte, or 0 with eof at the end.
def get8(reader: Reader) -> Reader:
  match reader:
    case Reader{Stream{+bytes, rest, +at, +length, +eof}, +page, +first, +packet, +error, +taken, _}:
      match rest:
        case Nil{}: Reader{Stream{bytes, Nil{}, at, length, True{}}, page, first, packet, error, taken, 0}
        case Con{+b, +more}: Reader{Stream{bytes, more, (at + 1 : U32), length, eof}, page, first, packet, error, taken, b}

# get32: four bytes, the low one first.
def get32(+reader: Reader) -> Reader:
  +a = get8(reader)
  +b = get8(a)
  +c = get8(b)
  +d = get8(c)
  Reader.answer(d, (((Reader.value(a) + (Reader.value(b) << 8n)) + (Reader.value(c) << 16n)) + (Reader.value(d) << 24n) : U32))

def firsts(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      match xs:
        case Nil{}: List.reverse(&2, U32, acc)
        case Con{+x, +rest}: firsts(k, rest, Con{x, acc})

# getn(data, n) for n up to 255: the n bytes (`taken`) and 1, or 0 with eof
# where fewer are left, and nothing read.
def getn(reader: Reader, +n: U32) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, +first, +packet, +error, +taken, _}:
      Bool.pick(Reader, ((at + n) > length : U32), Reader{Stream{bytes, rest, at, length, True{}}, page, first, packet, error, taken, 0},
        Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(U32.min(n, 255))), (at + n : U32), length, eof}, page, first, packet, error, firsts(U32.to_nat(U32.min(n, 255)), rest, Nil{}), 1})

# skip(n) for n up to 255: the position moves n bytes, past the end if it
# comes to that (stb_vorbis moves its pointer and compares it), and eof is
# set from the end on.
def skip(reader: Reader, +n: U32) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, +first, +packet, +error, +taken, +value}:
      Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(U32.min(n, 255))), (at + n : U32), length, eof || ((at + n) >= length : U32)}, page, first, packet, error, taken, value}

# -----------------------------------------------------------------------------
# Pages

# capture_pattern: the bytes wanted, read up to the first that is another.
def capture.pattern(wanted: List<U32>, found: Bool, +reader: Reader) -> Reader:
  match wanted found:
    case _ False{}: Reader.answer(reader, 0)
    case Nil{} True{}: Reader.answer(reader, 1)
    case Con{+w, rest} True{}:
      +next = get8(reader)
      capture.pattern(rest, U32.is_eq(Reader.value(next), w), next)

# With first_decode a page notes where it begins: 4 bytes back, at its
# capture pattern.
def page.noted(reader: Reader) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, First{+decoding, +start, +end, +sample}, +packet, +error, +taken, +value}:
      Reader{Stream{bytes, rest, at, length, eof}, page, First{decoding, Bool.pick(U32, decoding, (at - 4 : U32), start), end, sample}, packet, error, taken, value}

# A page's segment table over the 255 places: `n` lengths from the data,
# then what the places held.
def table.read(n: Nat, data: +List<U32>, old: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.append(&2, U32, List.reverse(&2, U32, acc), old)
    case 1n+k:
      match data old:
        case Con{+x, +rest} Con{_, +kept}: table.read(k, rest, kept, Con{x, acc})
        case _ _: List.append(&2, U32, List.reverse(&2, U32, acc), old)

# The last of the first `n` segments that ends a packet (a length under
# 255), or -1.
def last.short(n: Nat, segments: +List<U32>, +at: U32, +found: U32) -> U32:
  match n:
    case 0n: found
    case 1n+k:
      match segments:
        case Nil{}: found
        case Con{+len, +rest}: last.short(k, rest, (at + 1 : U32), Bool.pick(U32, (len < 255 : U32), at, found))

def table.sum(n: Nat, segments: +List<U32>, +total: U32) -> U32:
  match n:
    case 0n: total
    case 1n+k:
      match segments:
        case Nil{}: total
        case Con{+len, +rest}: table.sum(k, rest, (total + len : U32))

# The end of a page's header: its segment table (getn), the segment whose
# packet's last sample the granule position gives, and with first_decode the
# page's end and position.
def page.tabled(reader: Reader, +flag: U32, +loc0: U32, +loc1: U32, +sequence: U32, +count: U32) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, Page{_, _, +segments, +next, _, +known_seg, +known_loc}, First{+decoding, +start, +end, +sample}, +packet, +error, +taken, _}:
      +lengths = table.read(U32.to_nat(count), rest, segments, Nil{})
      +short = last.short(U32.to_nat(count), lengths, 0, 4294967295)
      +known = (U32.is_ne(loc0, 4294967295) || U32.is_ne(loc1, 4294967295)) && U32.is_ne(short, 4294967295)
      Bool.pick(Reader, ((at + count) > length : U32),
        Reader{Stream{bytes, rest, at, length, True{}}, Page{flag, count, segments, next, sequence, known_seg, known_loc}, First{decoding, start, end, sample}, packet, 10, taken, 0},
        Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(count)), (at + count : U32), length, eof},
          Page{flag, count, lengths, 0, sequence, Bool.pick(U32, known, short, 4294967294), Bool.pick(U32, known, loc0, known_loc)},
          First{decoding, start, Bool.pick(U32, decoding, (((start + table.sum(U32.to_nat(count), lengths, 0)) + 27) + count : U32), end), Bool.pick(U32, decoding, loc0, sample)}, packet, error, taken, 1})

# A page's header after its version byte, which must be 0.
def page.body(fine: Bool, +reader: Reader) -> Reader:
  match fine:
    case False{}: failed(reader, 31)
    case True{}:
      +flag = get8(reader)
      +loc0 = get32(flag)
      +loc1 = get32(loc0)
      +serial = get32(loc1)
      +sequence = get32(serial)
      +crc = get32(sequence)
      +count = get8(crc)
      page.tabled(count, Reader.value(flag), Reader.value(loc0), Reader.value(loc1), Reader.value(sequence), Reader.value(count))

def page.versioned(+reader: Reader) -> Reader:
  page.body(U32.is_eq(Reader.value(reader), 0), reader)

# start_page_no_capturepattern: the page's header from its version byte on.
# Its flags, sequence number and segment count are kept as they are read; the
# serial number and the checksum are passed over. 1, or 0 with
# VORBIS_invalid_stream_structure_version (31) or VORBIS_unexpected_eof
# (10, the segment table is cut).
def page.begin(+reader: Reader) -> Reader:
  page.versioned(get8(page.noted(reader)))

def page.opened(found: Bool, +reader: Reader) -> Reader:
  match found:
    case False{}: failed(reader, 30)
    case True{}: page.begin(reader)

def page.captured(+reader: Reader) -> Reader:
  page.opened(U32.is_eq(Reader.value(reader), 1), reader)

# start_page: "OggS" and the page's header, or 0 with
# VORBIS_missing_capture_pattern (30).
def page.start(+reader: Reader) -> Reader:
  page.captured(capture.pattern([79, 103, 103, 83], True{}, reader))

# -----------------------------------------------------------------------------
# Packets

# A packet begins: no last segment yet, no bits, no bytes. 1.
def packet.reset(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{_, _, +which, _, +acc, _}, +error, +taken, _}:
      Reader{stream, page, first, Packet{0, False{}, which, 0, acc, 0}, error, taken, 1}

def packet.paged(fine: Bool, +reader: Reader) -> Reader:
  match fine:
    case False{}: reader
    case True{}: Bool.pick(Reader, U32.is_ne((Page.flag(Reader.page(reader)) .&. 1 : U32), 0), failed(reader, 32), packet.reset(reader))

def packet.started(+reader: Reader) -> Reader:
  packet.paged(U32.is_eq(Reader.value(reader), 1), reader)

def packet.start.at(fresh: Bool, +reader: Reader) -> Reader:
  match fresh:
    case False{}: packet.reset(reader)
    case True{}: packet.started(page.start(reader))

# start_packet: where the page's segments are used up (next_seg is -1) the
# next page is started, and it must not continue a packet
# (VORBIS_continued_packet_flag_invalid, 32). 1 or 0.
def packet.start(+reader: Reader) -> Reader:
  packet.start.at(U32.is_eq(Page.next(Reader.page(reader)), 4294967295), reader)

# The packet a continued page leaves readable: not on its last segment and
# with no byte of a segment left.
def packet.held(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{_, _, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      Reader{stream, page, first, Packet{0, False{}, which, bytes, acc, valid}, error, taken, value}

def packet.maybe.paged(fine: Bool, +reader: Reader) -> Reader:
  match fine:
    case False{}: reader
    case True{}: Bool.pick(Reader, U32.is_ne((Page.flag(Reader.page(reader)) .&. 1 : U32), 0), failed(packet.held(reader), 32), packet.reset(reader))

def packet.maybe.begun(+reader: Reader) -> Reader:
  packet.maybe.paged(U32.is_eq(Reader.value(reader), 1), reader)

def packet.maybe.captured(found: Bool, +reader: Reader) -> Reader:
  match found:
    case False{}: failed(reader, 30)
    case True{}: packet.maybe.begun(page.begin(reader))

def packet.maybe.rest(+reader: Reader) -> Reader:
  packet.maybe.captured(U32.is_eq(Reader.value(reader), 1), reader)

# kind: 0 the data ended, 1 the byte is not an "O", 2 it is.
def packet.maybe.first(kind: U32, +reader: Reader) -> Reader:
  match kind:
    case 0: Reader.answer(reader, 0)
    case 1: failed(reader, 30)
    case _: packet.maybe.rest(capture.pattern([103, 103, 83], True{}, reader))

def packet.maybe.read(+reader: Reader) -> Reader:
  packet.maybe.first(Bool.pick(U32, Stream.eof(Reader.stream(reader)), 0, Bool.pick(U32, U32.is_ne(Reader.value(reader), 79), 1, 2)), reader)

def packet.maybe.at(fresh: Bool, +reader: Reader) -> Reader:
  match fresh:
    case False{}: packet.reset(reader)
    case True{}: packet.maybe.read(get8(reader))

# maybe_start_packet: start_packet where the data may end instead of a page
# beginning, which is no error (0, and eof); eof set by an earlier read
# counts. A continued page is an error (32) that leaves its packet
# readable.
def packet.maybe(+reader: Reader) -> Reader:
  packet.maybe.at(U32.is_eq(Page.next(Reader.page(reader)), 4294967295), reader)

def entry(segments: +List<U32>) -> U32:
  match segments:
    case Nil{}: 0
    case Con{+len, _}: len

# len = segments[next_seg++]: a length under 255 is the packet's last
# segment; after the page's last one next_seg is -1.
def segment.taken(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, Page{+flag, +count, +segments, +next, +sequence, +known_seg, +known_loc}, +first, Packet{_, _, +which, +bytes, +acc, +valid}, +error, +taken, _}:
      +len = entry(List.drop(&2, U32, segments, U32.to_nat(U32.min(next, 254))))
      Reader{stream, Page{flag, count, segments, Bool.pick(U32, ((next + 1) >= count : U32), 4294967295, (next + 1 : U32)), sequence, known_seg, known_loc}, first,
        Packet{len, (len < 255 : U32), Bool.pick(U32, (len < 255 : U32), next, which), bytes, acc, valid}, error, taken, len}

# The packet ends where its next page does not begin.
def packet.ended(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, _, +which, +bytes, +acc, +valid}, +error, +taken, _}:
      Reader{stream, page, first, Packet{in_seg, True{}, which, bytes, acc, valid}, error, taken, 0}

def segment.paged(fine: Bool, +reader: Reader) -> Reader:
  match fine:
    case False{}: packet.ended(reader)
    case True{}: Bool.pick(Reader, U32.is_eq((Page.flag(Reader.page(reader)) .&. 1 : U32), 0), failed(reader, 32), segment.taken(reader))

def segment.turned(+reader: Reader) -> Reader:
  segment.paged(U32.is_eq(Reader.value(reader), 1), reader)

# last_seg_which = segment_count - 1, before the next page is started.
def segment.which(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, Page{+flag, +count, +segments, +next, +sequence, +known_seg, +known_loc}, +first, Packet{+in_seg, +last, _, +bytes, +acc, +valid}, +error, +taken, +value}:
      Reader{stream, Page{flag, count, segments, next, sequence, known_seg, known_loc}, first, Packet{in_seg, last, (count - 1 : U32), bytes, acc, valid}, error, taken, value}

# kind: 0 the packet is on its last segment, 1 the page's segments are used
# up, 2 the page has the next one.
def segment.at(kind: U32, +reader: Reader) -> Reader:
  match kind:
    case 0: Reader.answer(reader, 0)
    case 1: segment.turned(page.start(segment.which(reader)))
    case _: segment.taken(reader)

# next_segment: the packet's next segment and its length, or 0 where the
# packet has none (its last one is read, the next page does not begin, or
# it does not continue a packet: 32). A page that begins without the flag
# is left started. Called with no byte of a segment left, as stb_vorbis
# asserts.
def segment.next(+reader: Reader) -> Reader:
  segment.at(Bool.pick(U32, Packet.last(Reader.packet(reader)), 0, Bool.pick(U32, U32.is_eq(Page.next(Reader.page(reader)), 4294967295), 1, 2)), reader)

# skip(f, f->bytes_in_seg); f->bytes_in_seg = 0: what the setup does before
# it asks for the next segment itself.
def segment.dropped(reader: Reader) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, +first, Packet{+in_seg, +last, +which, +count, +acc, +valid}, +error, +taken, +value}:
      Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(U32.min(in_seg, 255))), (at + in_seg : U32), length, eof || ((at + in_seg) >= length : U32)}, page, first,
        Packet{0, last, which, count, acc, valid}, error, taken, value}

# --bytes_in_seg, ++packet_bytes.
def packet.counted(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      Reader{stream, page, first, Packet{(in_seg - 1 : U32), last, which, (bytes + 1 : U32), acc, valid}, error, taken, value}

def packet.get8.got(none: Bool, +reader: Reader) -> Reader:
  match none:
    case True{}: Reader.answer(reader, 4294967295)
    case False{}: get8(packet.counted(reader))

def packet.get8.next(+reader: Reader) -> Reader:
  packet.get8.got(U32.is_eq(Reader.value(reader), 0), reader)

# kind: 0 the segment has a byte, 1 it has none and is the packet's last, 2
# it has none and the packet may go on.
def packet.get8.at(kind: U32, +reader: Reader) -> Reader:
  match kind:
    case 0: get8(packet.counted(reader))
    case 1: Reader.answer(reader, 4294967295)
    case _: packet.get8.next(segment.next(reader))

# get8_packet_raw: the packet's next byte, or EOP (-1) at its end. A byte
# the data does not have is 0 (and eof), as get8 answers it.
def packet.get8.raw(+reader: Reader) -> Reader:
  packet.get8.at(Bool.pick(U32, U32.is_ne(Packet.in_seg(Reader.packet(reader)), 0), 0, Bool.pick(U32, Packet.last(Reader.packet(reader)), 1, 2)), reader)

def bits.dropped(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, +last, +which, +bytes, +acc, _}, +error, +taken, +value}:
      Reader{stream, page, first, Packet{in_seg, last, which, bytes, acc, 0}, error, taken, value}

# get8_packet: the packet's next byte, the bits at hand dropped.
def packet.get8(+reader: Reader) -> Reader:
  bits.dropped(packet.get8.raw(reader))

# get32_packet: four of them, the low one first. An EOP among them is the
# int -1 shifted to its place and added, as the C code adds it.
def packet.get32(+reader: Reader) -> Reader:
  +a = packet.get8(reader)
  +b = packet.get8(a)
  +c = packet.get8(b)
  +d = packet.get8(c)
  Reader.answer(d, (((Reader.value(a) + (Reader.value(b) << 8n)) + (Reader.value(c) << 16n)) + (Reader.value(d) << 24n) : U32))

# What is left of a segment read byte by byte: the position moves over the
# bytes the data has, and eof is set where it has fewer.
def segment.passed(reader: Reader) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, +first, Packet{+in_seg, +last, +which, +count, +acc, +valid}, +error, +taken, +value}:
      +left = (length - U32.min(at, length) : U32)
      Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(U32.min(in_seg, 255))), (at + U32.min(in_seg, left) : U32), length, eof || (in_seg > left : U32)}, page, first,
        Packet{0, last, which, (count + in_seg : U32), acc, valid}, error, taken, value}

def flush.next(+reader: Reader) -> Reader:
  Reader.answer(reader, Bool.pick(U32, U32.is_eq(Reader.value(reader), 0), 4294967295, 0))

def flush.turn(last: Bool, +reader: Reader) -> Reader:
  match last:
    case True{}: Reader.answer(reader, 4294967295)
    case False{}: flush.next(segment.next(reader))

# A segment's bytes and the step to the next one: EOP where there is none.
def flush.step(+reader: Reader) -> Reader:
  flush.turn(Packet.last(Reader.packet(reader)), reader)

def flush.tail(n: Nat, ended: Bool, +reader: Reader) -> Reader:
  match n ended:
    case _ True{}: reader
    case 0n False{}: reader
    case 1n+k False{}:
      +next = flush.step(segment.passed(reader))
      flush.tail(k, U32.is_eq(Reader.value(next), 4294967295), next)

# A packet takes a segment a turn. The segments of the pages to come are
# bytes of the data, so the data's bytes outlast them; the page being read
# has 255 at most.
def flush.loop(fuel: +List<U32>, ended: Bool, +reader: Reader) -> Reader:
  match fuel ended:
    case _ True{}: reader
    case Nil{} False{}: flush.tail(600n, False{}, reader)
    case Con{_, +more} False{}:
      +next = flush.step(segment.passed(reader))
      flush.loop(more, U32.is_eq(Reader.value(next), 4294967295), next)

# flush_packet: the rest of the packet is read and dropped, segment by
# segment.
def flush.packet(+reader: Reader) -> Reader:
  Reader.answer(flush.loop(Stream.rest(Reader.stream(reader)), False{}, reader), 0)

# -----------------------------------------------------------------------------
# Bits

# if (valid_bits == 0) acc = 0, before bits are added.
def bits.cleared(reader: Reader, +n: U32) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      Reader{stream, page, first, Packet{in_seg, last, which, bytes, Bool.pick(U32, U32.is_eq(valid, 0) && U32.is_ne(n, 0), 0, acc), valid}, error, taken, value}

# A byte of the packet above the bits at hand, or INVALID_BITS (-1) at the
# packet's end.
def bits.added(reader: Reader) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, +value}:
      Reader{stream, page, first, Bool.pick(Packet, U32.is_eq(value, 4294967295), Packet{in_seg, last, which, bytes, acc, 4294967295},
        Packet{in_seg, last, which, bytes, (acc + (value << U32.to_nat(U32.min(valid, 31))) : U32), (valid + 8 : U32)}), error, taken, value}

# Whether `n` bits are not at hand yet (bits that ran out are -1: no more
# are asked for).
def bits.wanting(+n: U32, +reader: Reader) -> Bool:
  (Packet.valid(Reader.packet(reader)) < n : U32)

def bits.fill(n: Nat, more: Bool, +want: U32, +reader: Reader) -> Reader:
  match n more:
    case _ False{}: reader
    case 0n True{}: reader
    case 1n+k True{}:
      +next = bits.added(packet.get8.raw(reader))
      bits.fill(k, bits.wanting(want, next), want, next)

# z = acc & ((1 << n) - 1); acc >>= n; valid_bits -= n: or 0 where the bits
# ran out.
def bits.taken(reader: Reader, +n: U32) -> Reader:
  match reader:
    case Reader{+stream, +page, +first, Packet{+in_seg, +last, +which, +bytes, +acc, +valid}, +error, +taken, _}:
      Bool.pick(Reader, U32.is_eq(valid, 4294967295), Reader{stream, page, first, Packet{in_seg, last, which, bytes, acc, valid}, error, taken, 0},
        Reader{stream, page, first, Packet{in_seg, last, which, bytes, (acc >> U32.to_nat(U32.min(n, 31)) : U32), (valid - n : U32)}, error, taken, (acc .&. ((1 << U32.to_nat(U32.min(n, 31))) - 1) : U32)})

# get_bits for up to 24 bits: bytes are added while fewer are at hand, three
# at most.
def bits.low(+n: U32, +reader: Reader) -> Reader:
  bits.taken(bits.fill(3n, bits.wanting(n, reader), n, bits.cleared(reader, n)), n)

def bits.wide(wide: Bool, +n: U32, +reader: Reader) -> Reader:
  match wide:
    case False{}: bits.low(n, reader)
    case True{}:
      +low = bits.low(24, reader)
      +high = bits.low((n - 24 : U32), low)
      Reader.answer(high, (Reader.value(low) + (Reader.value(high) << 24n) : U32))

# get_bits(n) for n up to 32: the packet's next n bits, the first one
# lowest. More than 24 that are not at hand are read as 24 and the rest.
# Past the packet's end the answer is 0 and so is every later one
# (valid_bits is INVALID_BITS), whatever was read of the bits asked for.
def bits.get(+n: U32, +reader: Reader) -> Reader:
  bits.wide((n > 24 : U32) && bits.wanting(n, reader), n, reader)

# -----------------------------------------------------------------------------
# What the setup does with its header packets

def Page.count(page: Page) -> U32:
  Page{_, count, _, _, _, _, _} = page
  count

def Page.segments(page: Page) -> +List<U32>:
  Page{_, _, segments, _, _, _, _} = page
  segments

# `n` bytes of the segment read byte by byte, n at most what it has left:
# zeros where the data ended.
def segment.read(reader: Reader, +n: U32) -> Reader:
  match reader:
    case Reader{Stream{+bytes, +rest, +at, +length, +eof}, +page, +first, Packet{+in_seg, +last, +which, +count, +acc, +valid}, +error, +taken, +value}:
      +left = (length - U32.min(at, length) : U32)
      Reader{Stream{bytes, List.drop(&2, U32, rest, U32.to_nat(U32.min(n, 255))), (at + U32.min(n, left) : U32), length, eof || (n > left : U32)}, page, first,
        Packet{(in_seg - n : U32), last, which, (count + n : U32), acc, valid}, error, taken, value}

# What the segment has of `n` bytes wanted: `value` is how many are still
# wanted.
def skip.read(+n: U32, +reader: Reader) -> Reader:
  Reader.answer(segment.read(reader, U32.min(n, Packet.in_seg(Reader.packet(reader)))), (n - U32.min(n, Packet.in_seg(Reader.packet(reader))) : U32))

def skip.taken(none: Bool, +n: U32, +reader: Reader) -> Reader:
  match none:
    case True{}: Reader.answer(reader, 0)
    case False{}: skip.read(n, reader)

def skip.entered(+n: U32, +reader: Reader) -> Reader:
  skip.taken(U32.is_eq(Reader.value(reader), 0), n, reader)

# kind: 0 the segment has a byte, 1 it has none and is the packet's last, 2
# it has none and the packet may go on.
def skip.turn(kind: U32, +n: U32, +reader: Reader) -> Reader:
  match kind:
    case 0: skip.read(n, reader)
    case 1: Reader.answer(reader, 0)
    case _: skip.entered(n, segment.next(reader))

def skip.step(+reader: Reader) -> Reader:
  skip.turn(Bool.pick(U32, U32.is_ne(Packet.in_seg(Reader.packet(reader)), 0), 0, Bool.pick(U32, Packet.last(Reader.packet(reader)), 1, 2)), Reader.value(reader), reader)

def skip.tail(n: Nat, done: Bool, +reader: Reader) -> Reader:
  match n done:
    case _ True{}: reader
    case 0n False{}: reader
    case 1n+k False{}:
      +next = skip.step(reader)
      skip.tail(k, U32.is_eq(Reader.value(next), 0), next)

def skip.loop(fuel: +List<U32>, done: Bool, +reader: Reader) -> Reader:
  match fuel done:
    case _ True{}: reader
    case Nil{} False{}: skip.tail(600n, False{}, reader)
    case Con{_, +more} False{}:
      +next = skip.step(reader)
      skip.loop(more, U32.is_eq(Reader.value(next), 0), next)

def skip.some(some: Bool, +n: U32, +reader: Reader) -> Reader:
  match some:
    case False{}: reader
    case True{}: bits.dropped(skip.loop(Stream.rest(Reader.stream(reader)), False{}, Reader.answer(reader, n)))

# get8_packet `n` times, the bytes dropped (a vendor string, a comment): a
# segment a turn. At the packet's end the calls that are left answer EOP and
# change nothing.
def packet.skipped(+reader: Reader, +n: U32) -> Reader:
  skip.some(U32.is_ne(n, 0), n, reader)

def left.tail(n: Nat, ended: Bool, +reader: Reader) -> Reader:
  match n ended:
    case _ True{}: reader
    case 0n False{}: reader
    case 1n+k False{}:
      +next = segment.dropped(segment.next(reader))
      left.tail(k, U32.is_eq(Reader.value(next), 0), next)

def left.loop(fuel: +List<U32>, ended: Bool, +reader: Reader) -> Reader:
  match fuel ended:
    case _ True{}: reader
    case Nil{} False{}: left.tail(600n, False{}, reader)
    case Con{_, +more} False{}:
      +next = segment.dropped(segment.next(reader))
      left.loop(more, U32.is_eq(Reader.value(next), 0), next)

# The rest of a header packet passed over, as start_decoder does it:
#   skip(f, f->bytes_in_seg); f->bytes_in_seg = 0;
#   do { len = next_segment(f); skip(f, len); f->bytes_in_seg = 0; } while (len);
# The bytes are skipped, not read: the position can pass the data's end.
def packet.left(+reader: Reader) -> Reader:
  left.loop(Stream.rest(Reader.stream(reader)), False{}, segment.dropped(reader))
