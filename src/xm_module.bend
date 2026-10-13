# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_xm (Joshua Reisenauer's port of libxm by
# Romain "Artefact2" Dalmaso; WTFPL), as raylib 6.0 vendors it in
# src/external/jar_xm.h: a module read from its file
# (jar_xm_create_context_safe: jar_xm_check_sanity_preload,
# jar_xm_get_memory_needed_for_context, jar_xm_load_module and
# jar_xm_check_sanity_postload). See THIRD_PARTY_NOTICES.md and
# LICENSES/jar_xm.txt.
#
# C ints are U32 two's-complement words. jar_xm reads its data safely (a
# byte past the data is 0) and writes into one block of memory whose size it
# works out beforehand; what it would write outside an array, or loop on
# without end, is refused here.
import Base
import ./store.bend as R

# -----------------------------------------------------------------------------
# The data

# READ_U8(offset): a byte of the data, 0 past its end.
def u8(+data: R.Index, +length: U32, +at: U32) -> U32:
  Bool.pick(U32, (at < length : U32), R.Index.get(data, at), 0)

def u16(+data: R.Index, +length: U32, +at: U32) -> U32:
  (u8(data, length, at) .|. (u8(data, length, (at + 1 : U32)) << 8n) : U32)

def u32(+data: R.Index, +length: U32, +at: U32) -> U32:
  (u16(data, length, at) .|. (u16(data, length, (at + 2 : U32)) << 16n) : U32)

# An offset moved on. jar_xm's offsets are size_t: one moved past any data
# stays past it (0xF0000000 here), whatever is added to it.
def moved(+at: U32, +by: U32) -> U32:
  Bool.pick(U32, (at >= 4026531840 : U32) || ((at + by : U32) < at : U32) || ((at + by : U32) >= 4026531840 : U32), 4026531840, (at + by : U32))

# A byte as an int8, and 16 bits as an int16.
def s8(+a: U32) -> U32:
  Bool.pick(U32, U32.is_ne((a .&. 128 : U32), 0), ((a .&. 255) .|. 4294967040 : U32), (a .&. 255 : U32))

def s16(+a: U32) -> U32:
  Bool.pick(U32, U32.is_ne((a .&. 32768 : U32), 0), ((a .&. 65535) .|. 4294901760 : U32), (a .&. 65535 : U32))

# An int of an int16's range as a float.
def float.of(+a: U32) -> F32:
  Bool.pick(F32, (a >= 2147483648 : U32), (0.0 - U32.to_f32((0 - a : U32)) : F32), U32.to_f32(a))

# The next multiple of 16.
def aligned(+a: U32) -> U32:
  ((a + 15) .&. 4294967280 : U32)

# Sizes in jar_xm's block of memory, kept under 2^30: more than 16 MiB is
# past this port's limit, however much more.
def most(+a: U32) -> U32:
  U32.min(a, 1073741824)

def times(+a: U32, +size: U32) -> U32:
  Bool.pick(U32, (a > (1073741824 / size) : U32), 1073741824, (a * size : U32))

def plus(+a: U32, +b: U32) -> U32:
  most((most(a) + most(b) : U32))

# -----------------------------------------------------------------------------
# What a module is

# A pattern's slot: the note (1 to 96, 97 a key off), the instrument, the
# volume column, the effect and its parameter.
type Slot is Data:
  Slot{note: U32, instrument: U32, volume: U32, effect: U32, param: U32}

# A pattern: its rows, and a slot a channel for each row.
type Pattern is Data:
  Pattern{rows: U32, slots: +List<Slot>}

type Point is Data:
  Point{frame: U32, value: U32}

# An envelope: its 12 points, how many are used, the sustain point, the
# loop's two points and its three flags.
type Envelope is Data:
  Envelope{points: +List<Point>, count: U32, sustain: U32, loop_start: U32, loop_end: U32, enabled: Bool, sustained: Bool, looped: Bool}

# A sample: 8 or 16 bits, whether it is stereo, its length and loop in
# samples, its volume, its finetune and relative note (int8s), the loop's
# type (0 none, 1 forward: jar_xm's ping-pong falls through to forward),
# its panning, and its data as floats.
type Sample is Data:
  Sample{bits: U32, stereo: U32, length: U32, loop_start: U32, loop_length: U32, loop_end: U32, volume: F32, finetune: U32, loop_type: U32, panning: F32, relative: U32, data: +List<F32>}

# An instrument: the sample of each of the 96 notes, the two envelopes, the
# vibrato (type, sweep, depth, rate), the fadeout and the samples.
type Instrument is Data:
  Instrument{notes: +List<U32>, volume: Envelope, panning: Envelope, vibrato_type: U32, vibrato_sweep: U32, vibrato_depth: U32, vibrato_rate: U32, fadeout: U32, samples: +List<Sample>}

# A module: the pattern order's length and restart position, the channels,
# the frequency type (0 linear, 1 Amiga), the default tempo and BPM, the 256
# entries of the pattern order, the patterns and the instruments. `room` is
# how many bytes of the player's row counts (256 an entry of the order) are
# inside jar_xm's block of memory: its estimate is some bytes short of what
# the module is laid out in.
type Module is Data:
  Module{length: U32, restart: U32, channels: U32, frequency: U32, tempo: U32, bpm: U32, order: +List<U32>, patterns: +List<Pattern>, instruments: +List<Instrument>, room: U32}

# jar_xm_create_context_safe's module, or why there is none: jar_xm's own
# failure (1: the data is not a module of version 1.04, or its pattern order
# names a pattern it does not have), or a refusal: 1 a write outside an
# array or the block of memory, 2 a loop that does not end, 4 past this
# port's limits (more than 16 MiB, or a pattern whose 16-bit counters wrap).
type Loaded is Data:
  Loaded{module: Module}
  Failed{code: U32}
  Refused{why: U32}

# -----------------------------------------------------------------------------
# jar_xm_check_sanity_preload

def magic.is(expected: +List<U32>, +data: R.Index, +length: U32, +at: U32) -> Bool:
  match expected:
    case Nil{}: True{}
    case Con{+e, +rest}: U32.is_eq(u8(data, length, at), e) && magic.is(rest, data, length, (at + 1 : U32))

# 60 bytes at least, "Extended Module: ", 0x1A at 37 and the version 1.04.
def sane(+data: R.Index, +length: U32) -> Bool:
  (length >= 60 : U32) && magic.is([69, 120, 116, 101, 110, 100, 101, 100, 32, 77, 111, 100, 117, 108, 101, 58, 32], data, length, 0) && U32.is_eq(u8(data, length, 37), 26)
    && U32.is_eq(u8(data, length, 59), 1) && U32.is_eq(u8(data, length, 58), 4)

# -----------------------------------------------------------------------------
# jar_xm_get_memory_needed_for_context

# The estimate so far, and the offset.
type Need is Data:
  Need{memory: U32, at: U32}

def Need.memory(need: Need) -> U32:
  Need{memory, _} = need
  memory

def Need.at(need: Need) -> U32:
  Need{_, at} = need
  at

# The patterns' slots. The two sizes that move the offset are added as
# 32-bit ints first.
def need.patterns(n: Nat, +data: R.Index, +length: U32, +channels: U32, +memory: U32, +at: U32) -> Need:
  match n:
    case 0n: Need{memory, at}
    case 1n+k: need.patterns(k, data, length, channels, plus(memory, times((u16(data, length, (at + 5 : U32)) * channels : U32), 5)), moved(at, (u32(data, length, at) + u16(data, length, (at + 7 : U32)) : U32)))

# An instrument's samples: their structures and their data (four bytes a
# byte of an 8-bit sample, two a byte of a 16-bit one). `sum` is the data's
# size, a 32-bit int.
def need.samples(n: Nat, on: Bool, +data: R.Index, +length: U32, +step: U32, +memory: U32, +at: U32, +sum: U32) -> Need:
  match n on:
    case _ False{}: Need{memory, at}
    case 0n True{}: Need{memory, moved(at, sum)}
    case 1n+k True{}:
      +size = u32(data, length, at)
      +next = plus(memory, times(size, Bool.pick(U32, U32.is_ne((u8(data, length, (at + 14 : U32)) .&. 16 : U32), 0), 2, 4)))
      need.samples(k, (next <= 16777216 : U32), data, length, step, next, moved(at, step), (sum + size : U32))

def need.instrument(+data: R.Index, +length: U32, +memory: U32, +at: U32, +count: U32) -> Need:
  need.samples(U32.to_nat(Bool.pick(U32, (plus(memory, times(count, 80)) <= 16777216 : U32), count, 0)), (plus(memory, times(count, 80)) <= 16777216 : U32), data, length,
    Bool.pick(U32, (count > 0 : U32), u32(data, length, (at + 29 : U32)), 0), plus(memory, times(count, 80)), moved(at, u32(data, length, at)), 0)

def need.instruments(n: Nat, on: Bool, +data: R.Index, +length: U32, +memory: U32, +at: U32) -> Need:
  match n on:
    case _ False{}: Need{memory, at}
    case 0n True{}: Need{memory, at}
    case 1n+k True{}:
      +next = need.instrument(data, length, memory, at, u16(data, length, (at + 27 : U32)))
      need.instruments(k, (Need.memory(next) <= 16777216 : U32), data, length, Need.memory(next), Need.at(next))

def need.ended(need: Need, +channels: U32) -> U32:
  Need{+memory, _} = need
  plus(memory, plus(times(channels, 256), 424))

def need.rest(need: Need, +data: R.Index, +length: U32, +channels: U32) -> U32:
  Need{+memory, +at} = need
  need.ended(need.instruments(U32.to_nat(u16(data, length, 72)), (memory <= 16777216 : U32), data, length, aligned(memory), at), channels)

# jar_xm_get_memory_needed_for_context: the block's size, with jar_xm's
# structures as the LP64 machines lay them out (a pattern 16 bytes, an
# instrument 272, a sample 80, a slot 5, a channel 256, the context 424).
def needed(+data: R.Index, +length: U32) -> U32:
  need.rest(need.patterns(U32.to_nat(u16(data, length, 70)), data, length, u16(data, length, 68),
    plus(aligned((aligned((u16(data, length, 70) * 16 : U32)) + (u16(data, length, 72) * 272) : U32)), (256 * u16(data, length, 64) : U32)), moved(60, u32(data, length, 60))), data, length, u16(data, length, 68))

# -----------------------------------------------------------------------------
# The patterns

# A pattern's slots (the last first) and why they are refused (0: not).
type Unpacked is Data:
  Unpacked{slots: +List<Slot>, why: U32}

def flagged(+note: U32, +bit: U32) -> U32:
  Bool.pick(U32, U32.is_ne((note .&. bit : U32), 0), 1, 0)

# A packed slot: a first byte with its high bit set says which of the five
# bytes follow; any other is the note, and the four others follow.
def slot.packed(+data: R.Index, +length: U32, +at: U32, +note: U32) -> Slot:
  +a = (at + 1 : U32)
  +b = (a + flagged(note, 1) : U32)
  +c = (b + flagged(note, 2) : U32)
  +d = (c + flagged(note, 4) : U32)
  +e = (d + flagged(note, 8) : U32)
  Slot{(u8(data, length, a) * flagged(note, 1) : U32), (u8(data, length, b) * flagged(note, 2) : U32), (u8(data, length, c) * flagged(note, 4) : U32), (u8(data, length, d) * flagged(note, 8) : U32),
    (u8(data, length, e) * flagged(note, 16) : U32)}

def slot.plain(+data: R.Index, +length: U32, +at: U32, +note: U32) -> Slot:
  Slot{note, u8(data, length, (at + 1 : U32)), u8(data, length, (at + 2 : U32)), u8(data, length, (at + 3 : U32)), u8(data, length, (at + 4 : U32))}

# How many bytes a slot takes.
def slot.size(+note: U32) -> U32:
  Bool.pick(U32, U32.is_ne((note .&. 128 : U32), 0), (((((1 + flagged(note, 1)) + flagged(note, 2)) + flagged(note, 4)) + flagged(note, 8)) + flagged(note, 16) : U32), 5)

def slot.read(+data: R.Index, +length: U32, +at: U32, +note: U32) -> Slot:
  Bool.pick(Slot, U32.is_ne((note .&. 128 : U32), 0), slot.packed(data, length, at, note), slot.plain(data, length, at, note))

# The slots of `packed` bytes at `base`: slot k is written while the bytes
# last. A slot past the pattern's is a write outside its array (1); bytes
# counted past 65535 wrap jar_xm's 16-bit counter (4).
def unpack.loop(fuel: Nat, on: Bool, +why: U32, +data: R.Index, +length: U32, +base: U32, +packed: U32, +count: U32, +j: U32, +k: U32, +slots: +List<Slot>) -> Unpacked:
  match fuel on:
    case _ False{}: Unpacked{slots, why}
    case 0n True{}: Unpacked{slots, 4}
    case 1n+more True{}:
      +note = u8(data, length, (base + j : U32))
      +next = (j + slot.size(note) : U32)
      +kind = Bool.pick(U32, (next > 65535 : U32), 4, Bool.pick(U32, (next >= packed : U32), 3, Bool.pick(U32, ((k + 1 : U32) >= count : U32), 1, 0)))
      unpack.loop(more, U32.is_eq(kind, 0), Bool.pick(U32, U32.is_eq(kind, 3), 0, kind), data, length, base, packed, count, next, (k + 1 : U32), Con{slot.read(data, length, (base + j : U32), note), slots})

# No bytes: every slot is zeros. Bytes for a pattern without slots are a
# write outside its array.
def unpack(+data: R.Index, +length: U32, +base: U32, +packed: U32, +count: U32) -> Unpacked:
  unpack.loop(U32.to_nat(packed), U32.is_ne(packed, 0) && U32.is_ne(count, 0), Bool.pick(U32, U32.is_ne(packed, 0) && U32.is_eq(count, 0), 1, 0), data, length, base, packed, count, 0, 0, Nil{})

def zeros.slots(n: Nat, acc: +List<Slot>) -> +List<Slot>:
  match n:
    case 0n: acc
    case 1n+k: zeros.slots(k, Con{Slot{0, 0, 0, 0, 0}, acc})

def counted.slots(slots: +List<Slot>, +n: U32) -> U32:
  match slots:
    case Nil{}: n
    case Con{_, +rest}: counted.slots(rest, (n + 1 : U32))

# The slots read, in their order, and zeros for the rest of the pattern's.
def slots.whole(+slots: +List<Slot>, +count: U32) -> +List<Slot>:
  List.reverse(&2, Slot, zeros.slots(U32.to_nat((count - U32.min(counted.slots(slots, 0), count) : U32)), slots))

# The patterns (the last first), the offset after them, where the block of
# memory is filled to, and why they are refused (0: not).
type Patterns is Data:
  Patterns{patterns: +List<Pattern>, at: U32, pool: U32, why: U32}

def pattern.made(unpacked: Unpacked, +rows: U32, +count: U32, +patterns: +List<Pattern>, +at: U32, +pool: U32) -> Patterns:
  Unpacked{+slots, +why} = unpacked
  Patterns{Con{Pattern{rows, slots.whole(slots, count)}, patterns}, at, pool, why}

def Patterns.why(state: Patterns) -> U32:
  Patterns{_, _, _, why} = state
  why

def Patterns.patterns(state: Patterns) -> +List<Pattern>:
  Patterns{patterns, _, _, _} = state
  patterns

def Patterns.at(state: Patterns) -> U32:
  Patterns{_, at, _, _} = state
  at

def Patterns.pool(state: Patterns) -> U32:
  Patterns{_, _, pool, _} = state
  pool

# A pattern: its header (the rows at 5, the packed size at 7), then its
# packed slots. Slots that do not fit the block of memory are a write
# outside it (a pattern without slots writes none).
def pattern.read(fits: Bool, +data: R.Index, +length: U32, +channels: U32, +patterns: +List<Pattern>, +at: U32, +pool: U32) -> Patterns:
  match fits:
    case False{}: Patterns{patterns, at, pool, 1}
    case True{}: pattern.made(unpack(data, length, moved(at, u32(data, length, at)), u16(data, length, (at + 7 : U32)), (channels * u16(data, length, (at + 5 : U32)) : U32)), u16(data, length, (at + 5 : U32)),
      (channels * u16(data, length, (at + 5 : U32)) : U32), patterns, moved(moved(at, u32(data, length, at)), u16(data, length, (at + 7 : U32))), plus(pool, times((channels * u16(data, length, (at + 5 : U32)) : U32), 5)))

def patterns.read(n: Nat, on: Bool, +data: R.Index, +length: U32, +channels: U32, +memory: U32, +state: Patterns) -> Patterns:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = pattern.read(U32.is_eq((channels * u16(data, length, (Patterns.at(state) + 5 : U32)) : U32), 0) || (plus(Patterns.pool(state), times((channels * u16(data, length, (Patterns.at(state) + 5 : U32)) : U32), 5)) <= memory : U32),
        data, length, channels, Patterns.patterns(state), Patterns.at(state), Patterns.pool(state))
      patterns.read(k, U32.is_eq(Patterns.why(next), 0), data, length, channels, memory, next)

# -----------------------------------------------------------------------------
# The instruments

def points.read(n: Nat, +data: R.Index, +length: U32, +at: U32, acc: +List<Point>) -> +List<Point>:
  match n:
    case 0n: acc
    case 1n+k: points.read(k, data, length, (at + 4 : U32), Con{Point{u16(data, length, at), u16(data, length, (at + 2 : U32))}, acc})

def zeros.points(n: Nat, acc: +List<Point>) -> +List<Point>:
  match n:
    case 0n: acc
    case 1n+k: zeros.points(k, Con{Point{0, 0}, acc})

# An envelope's points from `at` (as many as it says, 12 at most here, and
# zeros up to 12), with its three point numbers and its flags.
def envelope.read(+data: R.Index, +length: U32, +at: U32, +count: U32, +sustain: U32, +loop_start: U32, +loop_end: U32, +flags: U32) -> Envelope:
  Envelope{List.reverse(&2, Point, zeros.points(U32.to_nat((12 - U32.min(count, 12) : U32)), points.read(U32.to_nat(U32.min(count, 12)), data, length, at, Nil{}))), count, sustain, loop_start, loop_end,
    U32.is_ne((flags .&. 1 : U32), 0), U32.is_ne((flags .&. 2 : U32), 0), U32.is_ne((flags .&. 4 : U32), 0)}

def envelope.none() -> Envelope:
  Envelope{zeros.points(12n, Nil{}), 0, 0, 0, 0, False{}, False{}, False{}}

def bytes.read(n: Nat, +data: R.Index, +length: U32, +at: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: bytes.read(k, data, length, (at + 1 : U32), Con{u8(data, length, at), acc})

def zeros.words(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros.words(k, Con{0, acc})

# The vibrato's waveform: jar_xm swaps 1 and 2.
def waveform(+kind: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, 2), 1, Bool.pick(U32, U32.is_eq(kind, 1), 2, kind))

# A sample's data: `count` values, each the last plus an int8 or an int16
# of the data (kept to that type), over 128 or 32768. A stereo sample's
# running value begins again at its half.
def data.read(n: Nat, +data: R.Index, +length: U32, +at: U32, +wide: Bool, +half: U32, +k: U32, +v: U32, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+more:
      +from = Bool.pick(U32, U32.is_eq(k, half), 0, v)
      +next = Bool.pick(U32, wide, s16((from + s16(u16(data, length, (at + (k << 1n) : U32))) : U32)), s8((from + s8(u8(data, length, (at + k : U32))) : U32)))
      data.read(more, data, length, at, wide, half, (k + 1 : U32), next, Con{(float.of(next) / Bool.pick(F32, wide, 32768.0, 128.0) : F32), acc})

# An int halved as div does: toward zero.
def halved(+a: U32) -> U32:
  Bool.pick(U32, (a >= 2147483648 : U32), (0 - ((0 - a) / 2) : U32), (a / 2 : U32))

# The loop of a sample: its start, its length and its end. A 16-bit
# sample's are halved (the end is the halved sum); a stereo sample that
# loops has them halved from the header's, as ints, whatever its bits.
def loop.start(+wide: Bool, +paired: Bool, +start: U32) -> U32:
  Bool.pick(U32, paired, halved(start), Bool.pick(U32, wide, (start >> 1n : U32), start))

def loop.end(+wide: Bool, +paired: Bool, +start: U32, +span: U32) -> U32:
  Bool.pick(U32, paired, (halved(start) + halved(span) : U32), Bool.pick(U32, wide, ((start + span) >> 1n : U32), (start + span : U32)))

# A sample's header at `at`, its data to come: a 16-bit sample's length is
# halved.
def sample.header(+data: R.Index, +length: U32, +at: U32) -> Sample:
  +flags = u8(data, length, (at + 14 : U32))
  +wide = U32.is_ne((flags .&. 16 : U32), 0)
  +paired = U32.is_ne((flags .&. 32 : U32), 0) && U32.is_ne((flags .&. 3 : U32), 0)
  Sample{Bool.pick(U32, wide, 16, 8), Bool.pick(U32, U32.is_ne((flags .&. 32 : U32), 0), 1, 0), Bool.pick(U32, wide, (u32(data, length, at) >> 1n : U32), u32(data, length, at)),
    loop.start(wide, paired, u32(data, length, (at + 4 : U32))), loop.start(wide, paired, u32(data, length, (at + 8 : U32))), loop.end(wide, paired, u32(data, length, (at + 4 : U32)), u32(data, length, (at + 8 : U32))),
    F32.min((U32.to_f32((u8(data, length, (at + 12 : U32)) << 2n : U32)) / 256.0 : F32), 1.0), s8(u8(data, length, (at + 13 : U32))), Bool.pick(U32, U32.is_ne((flags .&. 3 : U32), 0), 1, 0),
    (U32.to_f32(u8(data, length, (at + 15 : U32))) / 255.0 : F32), s8(u8(data, length, (at + 16 : U32))), Nil{}}

# An instrument's sample headers (the last first), the offset after them
# and where the block of memory is filled to with their structures' data to
# come: two bytes a byte of a 16-bit sample, four a byte of an 8-bit one.
type Headers is Data:
  Headers{samples: +List<Sample>, at: U32, pool: U32}

def Headers.samples(headers: Headers) -> +List<Sample>:
  Headers{samples, _, _} = headers
  samples

def Headers.at(headers: Headers) -> U32:
  Headers{_, at, _} = headers
  at

def Headers.pool(headers: Headers) -> U32:
  Headers{_, _, pool} = headers
  pool

def headers.read(n: Nat, +data: R.Index, +length: U32, +step: U32, +samples: +List<Sample>, +at: U32, +pool: U32) -> Headers:
  match n:
    case 0n: Headers{samples, at, pool}
    case 1n+k: headers.read(k, data, length, step, Con{sample.header(data, length, at), samples}, moved(at, step),
      plus(pool, times(u32(data, length, at), Bool.pick(U32, U32.is_ne((u8(data, length, (at + 14 : U32)) .&. 16 : U32), 0), 2, 4))))

# The samples with their data (the last first) and the offset after it.
type Filled is Data:
  Filled{samples: +List<Sample>, at: U32}

# A sample's data read: a stereo sample keeps its first half as its length.
def sample.filled(sample: Sample, +data: R.Index, +length: U32, +at: U32) -> Sample:
  Sample{+bits, +stereo, +count, +loop_start, +loop_length, +loop_end, +volume, +finetune, +loop_type, +panning, +relative, _} = sample
  Sample{bits, stereo, Bool.pick(U32, U32.is_eq(stereo, 1), (count / 2 : U32), count), loop_start, loop_length, loop_end, volume, finetune, loop_type, panning, relative,
    data.read(U32.to_nat(count), data, length, at, U32.is_eq(bits, 16), Bool.pick(U32, U32.is_eq(stereo, 1), (count / 2 : U32), 4294967295), 0, 0, Nil{})}

# How far a sample's data moves the offset: its length, twice for 16 bits.
def sample.span(sample: Sample) -> U32:
  Sample{+bits, _, +count, _, _, _, _, _, _, _, _, _} = sample
  Bool.pick(U32, U32.is_eq(bits, 16), (count << 1n : U32), count)

def samples.fill(headers: +List<Sample>, +data: R.Index, +length: U32, +at: U32, +acc: +List<Sample>) -> Filled:
  match headers:
    case Nil{}: Filled{acc, at}
    case Con{+sample, +rest}: samples.fill(rest, data, length, moved(at, sample.span(sample)), Con{sample.filled(sample, data, length, at), acc})

# The instruments (the last first), the offset, where the block of memory
# is filled to, and why they are refused (0: not).
type Instruments is Data:
  Instruments{instruments: +List<Instrument>, at: U32, pool: U32, why: U32}

def Instruments.instruments(state: Instruments) -> +List<Instrument>:
  Instruments{instruments, _, _, _} = state
  instruments

def Instruments.at(state: Instruments) -> U32:
  Instruments{_, at, _, _} = state
  at

def Instruments.pool(state: Instruments) -> U32:
  Instruments{_, _, pool, _} = state
  pool

def Instruments.why(state: Instruments) -> U32:
  Instruments{_, _, _, why} = state
  why

# An instrument without samples is zeros.
def instrument.none() -> Instrument:
  Instrument{zeros.words(96n, Nil{}), envelope.none(), envelope.none(), 0, 0, 0, 0, 0, Nil{}}

# An instrument's own header at `at`, with its samples.
def instrument.made(+data: R.Index, +length: U32, +at: U32, +samples: +List<Sample>) -> Instrument:
  Instrument{bytes.read(96n, data, length, (at + 33 : U32), Nil{}),
    envelope.read(data, length, (at + 129 : U32), u8(data, length, (at + 225 : U32)), u8(data, length, (at + 227 : U32)), u8(data, length, (at + 228 : U32)), u8(data, length, (at + 229 : U32)), u8(data, length, (at + 233 : U32))),
    envelope.read(data, length, (at + 177 : U32), u8(data, length, (at + 226 : U32)), u8(data, length, (at + 230 : U32)), u8(data, length, (at + 231 : U32)), u8(data, length, (at + 232 : U32)), u8(data, length, (at + 234 : U32))),
    waveform(u8(data, length, (at + 235 : U32))), u8(data, length, (at + 236 : U32)), u8(data, length, (at + 237 : U32)), u8(data, length, (at + 238 : U32)), u16(data, length, (at + 239 : U32)), samples}

def instrument.filled(filled: Filled, +data: R.Index, +length: U32, +at: U32, +instruments: +List<Instrument>, +pool: U32) -> Instruments:
  Filled{+samples, +end} = filled
  Instruments{Con{instrument.made(data, length, at, List.reverse(&2, Sample, samples)), instruments}, end, pool, 0}

# The samples' data, where their structures and data fit the block.
def instrument.headed(fits: Bool, +headers: Headers, +data: R.Index, +length: U32, +at: U32, +instruments: +List<Instrument>) -> Instruments:
  match fits:
    case False{}: Instruments{instruments, at, 0, 1}
    case True{}: instrument.filled(samples.fill(List.reverse(&2, Sample, Headers.samples(headers)), data, length, Headers.at(headers), Nil{}), data, length, at, instruments, Headers.pool(headers))

def instrument.fitted(+headers: Headers, +data: R.Index, +length: U32, +at: U32, +memory: U32, +instruments: +List<Instrument>) -> Instruments:
  instrument.headed((Headers.pool(headers) <= memory : U32), headers, data, length, at, instruments)

# What an instrument is: 0 without samples; 1 an envelope of more than 12
# points, or sample structures past the block (writes outside); 2 one to
# read.
def instrument.kind(+data: R.Index, +length: U32, +at: U32, +memory: U32, +pool: U32) -> U32:
  Bool.pick(U32, U32.is_eq(u16(data, length, (at + 27 : U32)), 0), 0,
    Bool.pick(U32, (u8(data, length, (at + 225 : U32)) > 12 : U32) || (u8(data, length, (at + 226 : U32)) > 12 : U32) || (plus(pool, times(u16(data, length, (at + 27 : U32)), 80)) > memory : U32), 1, 2))

def instrument.read(kind: U32, +data: R.Index, +length: U32, +memory: U32, +instruments: +List<Instrument>, +at: U32, +pool: U32) -> Instruments:
  match kind:
    case 0: Instruments{Con{instrument.none(), instruments}, moved(at, u32(data, length, at)), pool, 0}
    case 2: instrument.fitted(headers.read(U32.to_nat(u16(data, length, (at + 27 : U32))), data, length, u32(data, length, (at + 29 : U32)), Nil{}, moved(at, u32(data, length, at)),
      plus(pool, times(u16(data, length, (at + 27 : U32)), 80))), data, length, at, memory, instruments)
    case _: Instruments{instruments, at, pool, 1}

def instruments.read(n: Nat, on: Bool, +data: R.Index, +length: U32, +memory: U32, +state: Instruments) -> Instruments:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = instrument.read(instrument.kind(data, length, Instruments.at(state), memory, Instruments.pool(state)), data, length, memory, Instruments.instruments(state), Instruments.at(state), Instruments.pool(state))
      instruments.read(k, U32.is_eq(Instruments.why(next), 0), data, length, memory, next)

# -----------------------------------------------------------------------------
# jar_xm_check_sanity_postload

# The pattern order checked: 0 fine (with the order's length, which loses
# its last entry if that one names no pattern), 1 an entry that names no
# pattern, 2 a check that does not end.
type Checked is Data:
  Checked{kind: U32, length: U32}

# jar_xm counts the order's entries in a byte: an order of 256 entries or
# more whose first 256 all name patterns is checked without end. A last
# entry that names no pattern is dropped from an order of more than one.
def order.check(order: +List<U32>, on: Bool, +kind: U32, +i: U32, +length: U32, +patterns: U32) -> Checked:
  match order on:
    case _ False{}: Checked{kind, length}
    case Nil{} True{}: Checked{Bool.pick(U32, (length <= 255 : U32), 0, 2), length}
    case Con{+entry, +rest} True{}:
      +ended = (i >= length : U32)
      +trim = (entry >= patterns : U32) && U32.is_eq((i + 1 : U32), length) && (length > 1 : U32)
      order.check(rest, Bool.not(ended || ((entry >= patterns : U32) && Bool.not(trim))), Bool.pick(U32, ended, 0, 1), (i + 1 : U32), Bool.pick(U32, trim && Bool.not(ended), (length - 1 : U32), length), patterns)

def Checked.kind(checked: Checked) -> U32:
  Checked{kind, _} = checked
  kind

def Checked.length(checked: Checked) -> U32:
  Checked{_, length} = checked
  length

# -----------------------------------------------------------------------------
# jar_xm_create_context_safe

def load.made(kind: U32, +entries: U32, +data: R.Index, +length: U32, +patterns: +List<Pattern>, +instruments: +List<Instrument>, +room: U32) -> Loaded:
  match kind:
    case 0: Loaded{Module{entries, u16(data, length, 66), u16(data, length, 68), Bool.pick(U32, U32.is_ne((u32(data, length, 74) .&. 1 : U32), 0), 0, 1), u16(data, length, 76), u16(data, length, 78),
      bytes.read(256n, data, length, 80, Nil{}), patterns, instruments, room}}
    case 1: Failed{1}
    case _: Refused{2}

def load.checked(+checked: Checked, +data: R.Index, +length: U32, +patterns: +List<Pattern>, +instruments: +List<Instrument>, +room: U32) -> Loaded:
  load.made(Checked.kind(checked), Checked.length(checked), data, length, patterns, instruments, room)

# The channels after the instruments: 256 of them or more are set up by a
# loop that does not end, and channels past the block are writes outside it
# (a module without an order has no room for any).
def load.channels(kind: U32, +data: R.Index, +length: U32, +memory: U32, +patterns: +List<Pattern>, +instruments: +List<Instrument>, +pool: U32) -> Loaded:
  match kind:
    case 0: load.checked(order.check(bytes.read(256n, data, length, 80, Nil{}), True{}, 0, 0, u16(data, length, 64), u16(data, length, 70)), data, length, patterns, instruments, (memory - U32.min(pool, memory) : U32))
    case _: Refused{kind}

def load.instrumented(fine: Bool, +state: Instruments, +data: R.Index, +length: U32, +memory: U32, +patterns: +List<Pattern>) -> Loaded:
  match fine:
    case False{}: Refused{Instruments.why(state)}
    case True{}:
      load.channels(Bool.pick(U32, (u16(data, length, 68) >= 256 : U32), 2, Bool.pick(U32, (u16(data, length, 68) > 0 : U32) && (plus(aligned(Instruments.pool(state)), times(u16(data, length, 68), 256)) > memory : U32), 1, 0)),
        data, length, memory, patterns,
        List.reverse(&2, Instrument, Instruments.instruments(state)), plus(aligned(Instruments.pool(state)), times(u16(data, length, 68), 256)))

def load.instruments(+state: Instruments, +data: R.Index, +length: U32, +memory: U32, +patterns: +List<Pattern>) -> Loaded:
  load.instrumented(U32.is_eq(Instruments.why(state), 0), state, data, length, memory, patterns)

def load.patterned(fine: Bool, +state: Patterns, +data: R.Index, +length: U32, +memory: U32) -> Loaded:
  match fine:
    case False{}: Refused{Patterns.why(state)}
    case True{}:
      load.instruments(instruments.read(U32.to_nat(u16(data, length, 72)), True{}, data, length, memory, Instruments{Nil{}, Patterns.at(state), aligned(Patterns.pool(state)), 0}), data, length, memory,
        List.reverse(&2, Pattern, Patterns.patterns(state)))

def load.patterns(+state: Patterns, +data: R.Index, +length: U32, +memory: U32) -> Loaded:
  load.patterned(U32.is_eq(Patterns.why(state), 0), state, data, length, memory)

# The module's header is at 60: its size, the order's length and restart,
# the channels, patterns and instruments, the flags, the tempo and BPM, and
# the order's 256 bytes at 80. The patterns follow the header.
def load.sized(small: Bool, +data: R.Index, +length: U32, +memory: U32) -> Loaded:
  match small:
    case False{}: Refused{4}
    case True{}: load.patterns(patterns.read(U32.to_nat(u16(data, length, 70)), True{}, data, length, u16(data, length, 68), memory,
      Patterns{Nil{}, moved(60, u32(data, length, 60)), aligned((aligned((424 + (u16(data, length, 70) * 16) : U32)) + (u16(data, length, 72) * 272) : U32)), 0}), data, length, memory)

def load.sane(fine: Bool, +data: R.Index, +length: U32) -> Loaded:
  match fine:
    case False{}: Failed{1}
    case True{}: load.sized((needed(data, length) <= 16777216 : U32), data, length, needed(data, length))

def counted(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

def load.indexed(+data: R.Index, +length: U32) -> Loaded:
  load.sane(sane(data, length), data, length)

# jar_xm_create_context_safe(&ctx, data, length, rate): the module of the
# data. (The module's and its parts' names are not kept.)
def load(+bytes: +List<U32>) -> Loaded:
  load.indexed(R.Index.from(bytes, 0), counted(bytes, 0))
