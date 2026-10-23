# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.2 vendors it in src/external/stb_vorbis.c: frames and
# samples (get_window, vorbis_finish_frame, vorbis_pump_first_frame,
# stb_vorbis_open_memory, stb_vorbis_get_frame_float, and
# stb_vorbis_get_samples_short_interleaved for as many channels as the
# stream has, with convert_channels_short_interleaved and
# FAST_SCALED_FLOAT_TO_INT). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# C ints are U32 two's-complement words; a short is a word of 16 bits. The
# reader's error 1001 is this port's refusal of what C leaves undefined or
# machines answer differently: nothing is read after it.
import Base
import ../jonmath.bend as Mth
import ./vorbis_ogg.bend as O
import ./vorbis_codebook.bend as C
import ./vorbis_setup.bend as S
import ./vorbis_mdct.bend as X
import ./vorbis_packet.bend as K
import ./store.bend as R

# A decoder between frames: the packets' state, the right part of the last
# block for each channel (previous_window) and how long it is
# (previous_length), where the samples not yet taken are in the channels'
# floats (channel_buffer_start and channel_buffer_end) and how many samples
# the frames have given (samples_output).
type Frames is Data:
  Frames{state: K.State, previous: +List<R.Row>, length: U32, start: U32, end: U32, output: U32}

def Frames.state(frames: Frames) -> K.State:
  Frames{state, _, _, _, _, _} = frames
  state

def Frames.previous(frames: Frames) -> +List<R.Row>:
  Frames{_, previous, _, _, _, _} = frames
  previous

def Frames.length(frames: Frames) -> U32:
  Frames{_, _, length, _, _, _} = frames
  length

def Frames.start(frames: Frames) -> U32:
  Frames{_, _, _, start, _, _} = frames
  start

def Frames.end(frames: Frames) -> U32:
  Frames{_, _, _, _, end, _} = frames
  end

def Frames.output(frames: Frames) -> U32:
  Frames{_, _, _, _, _, output} = frames
  output

def Frames.reader(frames: Frames) -> O.Reader:
  K.State.reader(Frames.state(frames))

# Whether the decoder met a refusal.
def Frames.refused(frames: Frames) -> Bool:
  O.refused(Frames.reader(frames))

# Frames and a C answer.
type Got is Data:
  Got{frames: Frames, value: U32}

def Got.frames(got: Got) -> Frames:
  Got{frames, _} = got
  frames

# -----------------------------------------------------------------------------
# vorbis_finish_frame

def window.chosen(which: U32, +plan: K.Plan) -> Maybe<R.Row>:
  match which:
    case 1: Some{X.Factors.window(K.Plan.short(plan))}
    case 2: Some{X.Factors.window(K.Plan.long(plan))}
    case _: None{}

# get_window(f, n): the window of the block that is twice n long, if a
# block size is. (A length below 0 is no block's half.)
def window.for(+plan: K.Plan, +n: U32) -> Maybe<R.Row>:
  window.chosen(Bool.pick(U32, K.under(n, 0), 0, Bool.pick(U32, U32.is_eq((n << 1n : U32), K.Plan.blocksize_0(plan)), 1, Bool.pick(U32, U32.is_eq((n << 1n : U32), K.Plan.blocksize_1(plan)), 2, 0))), plan)

# buffer[left + j] = buffer[left + j]*w[j] + previous[j]*w[n - 1 - j].
def mix.steps(n: Nat, +j: U32, +left: U32, +last: U32, +w: R.Row, +prev: R.Row, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k: mix.steps(k, (j + 1 : U32), left, last, w, prev, R.Row.set(row, (left + j : U32), ((R.Row.get(row, (left + j : U32)) * R.Row.get(w, j)) + (R.Row.get(prev, j) * R.Row.get(w, (last - j : U32))) : F32)))

def mix.each(rows: +List<R.Row>, previous: +List<R.Row>, +n: U32, +left: U32, +w: R.Row, acc: +List<R.Row>) -> +List<R.Row>:
  match rows previous:
    case Con{+row, +more} Con{+prev, +rest}: mix.each(more, rest, n, left, w, Con{mix.steps(U32.to_nat(n), 0, left, (n - 1 : U32), w, prev, row), acc})
    case _ _: List.reverse(&2, R.Row, acc)

# previous[j] = buffer[right + j].
def save.steps(n: Nat, +j: U32, +right: U32, +row: R.Row, +prev: R.Row) -> R.Row:
  match n:
    case 0n: prev
    case 1n+k: save.steps(k, (j + 1 : U32), right, row, R.Row.set(prev, j, R.Row.get(row, (right + j : U32))))

def save.each(rows: +List<R.Row>, previous: +List<R.Row>, +count: U32, +right: U32, acc: +List<R.Row>) -> +List<R.Row>:
  match rows previous:
    case Con{+row, +more} Con{+prev, +rest}: save.each(more, rest, count, right, Con{save.steps(U32.to_nat(count), 0, right, row, prev), acc})
    case _ _: List.reverse(&2, R.Row, acc)

# After the mixing: the block's right part is kept for the next frame, and
# the frame gives the samples from `left` to `right` (or to `len`, where a
# last block is cut short). A first frame, with nothing before it to mix
# with, gives none.
def finish.kept(frames: Frames, +rows: +List<R.Row>, +len: U32, +left: U32, +right: U32) -> Got:
  match frames:
    case Frames{K.State{+reader, _, +loc, +known, +discard}, +previous, +length, +start, +end, +output}:
      +given = Bool.pick(U32, U32.is_eq(length, 0), 0, (Bool.pick(U32, K.under(len, right), len, right) - left : U32))
      Got{Frames{K.State{reader, rows, loc, known, discard}, save.each(rows, previous, Bool.pick(U32, K.under(right, len), (len - right : U32), 0), right, Nil{}), (len - right : U32), start, end, (output + given : U32)}, given}

# A previous length that is no block's half has no window: the frame gives
# nothing and changes nothing.
def finish.mixed(window: Maybe<R.Row>, +frames: Frames, +len: U32, +left: U32, +right: U32) -> Got:
  match window:
    case None{}: Got{frames, 0}
    case Some{+w}: finish.kept(frames, mix.each(K.State.rows(Frames.state(frames)), Frames.previous(frames), Frames.length(frames), left, w, Nil{}), len, left, right)

def finish.any(mixing: Bool, +plan: K.Plan, +frames: Frames, +len: U32, +left: U32, +right: U32) -> Got:
  match mixing:
    case False{}: finish.kept(frames, K.State.rows(Frames.state(frames)), len, left, right)
    case True{}: finish.mixed(window.for(plan, Frames.length(frames)), frames, len, left, right)

# vorbis_finish_frame(f, len, left, right): the block's left part mixed
# with what the last block left, each under its half of the window.
def finish(+plan: K.Plan, +frames: Frames, +len: U32, +left: U32, +right: U32) -> Got:
  finish.any(U32.is_ne(Frames.length(frames), 0), plan, frames, len, left, right)

# -----------------------------------------------------------------------------
# Frames

def frame.with(frames: Frames, +state: K.State) -> Frames:
  Frames{_, previous, length, start, end, output} = frames
  Frames{state, previous, length, start, end, output}

def frame.placed(frames: Frames, +start: U32, +end: U32) -> Frames:
  Frames{state, previous, length, _, _, output} = frames
  Frames{state, previous, length, start, end, output}

def frame.given(got: Got, +left: U32) -> Got:
  Got{+frames, +value} = got
  Got{frame.placed(frames, left, (left + value : U32)), value}

def frame.decoded(packet: K.Packet, +plan: K.Plan, +frames: Frames) -> Got:
  match packet:
    case K.Packet{+state, False{}, _, _, _}: Got{frame.placed(frame.with(frames, state), 0, 0), 0}
    case K.Packet{+state, True{}, +len, +left, +right}: frame.given(finish(plan, frame.with(frames, state), len, left, right), left)

# stb_vorbis_get_frame_float(f, NULL, &output): the next packet decoded and
# finished. The answer is how many samples it gives, which are in the
# channels' floats from `start` to `end`; 0 where no packet is decoded, and
# for a frame that gives none.
def frame.float(+plan: K.Plan, +frames: Frames) -> Got:
  frame.decoded(K.packet.decode(plan, Frames.state(frames)), plan, frames)

def pump.decoded(packet: K.Packet, +plan: K.Plan, +frames: Frames) -> Frames:
  match packet:
    case K.Packet{+state, False{}, _, _, _}: frame.with(frames, state)
    case K.Packet{+state, True{}, +len, +left, +right}: Got.frames(finish(plan, frame.with(frames, state), len, left, right))

# vorbis_pump_first_frame: the first packet decoded and finished, its
# samples not given.
def pump(+plan: K.Plan, +frames: Frames) -> Frames:
  pump.decoded(K.packet.decode(plan, Frames.state(frames)), plan, frames)

# A decoder of the data, with the stream's sample rate and where its audio
# begins (first_audio_page_offset), or why there is none.
type Started is Data:
  Opened{plan: K.Plan, frames: Frames, rate: U32, first: U32}
  Unready{status: S.Status}

# first_audio_page_offset, of the reader as the setup leaves it: where the
# data is, if the setup's packet ended its page; 0 if audio packets share
# that page.
def first.audio(+reader: O.Reader) -> U32:
  Bool.pick(U32, U32.is_eq(O.Page.next(O.Reader.page(reader)), 4294967295), O.Stream.at(O.Reader.stream(reader)), 0)

def memory.opened(decoder: K.Decoder, +rate: U32) -> Started:
  match decoder:
    case K.Closed{+status}: Unready{status}
    case K.Opened{+plan, +state}: Opened{plan, pump(plan, Frames{state, K.rows.new(U32.to_nat(K.Plan.channels(plan)), (C.ilog(K.Plan.blocksize_1(plan)) - 2 : U32), Nil{}), 0, 0, 0, 0}), rate, first.audio(K.State.reader(state))}

def memory.set(+libm: Mth.Libm, +setup: S.Setup) -> Started:
  memory.opened(K.open.set(libm, setup), S.Head.rate(S.Setup.head(setup)))

# stb_vorbis_open_memory(data, len, &error, NULL): the setup read and the
# first frame pumped.
def memory.open(+libm: Mth.Libm, +bytes: +List<U32>) -> Started:
  memory.set(libm, S.setup.codebooks(bytes))

# -----------------------------------------------------------------------------
# Shorts

# Whether a float is a NaN, by its bits.
def nan(+bits: U32) -> Bool:
  ((bits .&. 2147483647) > 2139095040 : U32)

# FAST_SCALED_FLOAT_TO_INT(temp, x, 15) is temp.f = x + 384.0f (the macro's
# MAGIC(15), whose rounding term is lost in the float) and then the int
# temp.i - 0x43C00000, the bits of 384.0f: the sum's bits count the steps of
# 1/32768 from 384. `bits` are the sum's. For a sum below 0 and above -384
# the int subtraction overflows, which C leaves undefined.
def short.undefined(+bits: U32) -> Bool:
  (bits >= 2147483648 : U32) && (bits <= 3284140031 : U32)

# The int kept to a short's range, as convert_channels_short_interleaved
# does: a word of 16 bits.
def short.clamped(+bits: U32) -> U32:
  Bool.pick(U32, (((bits - 1136656384) + 32768 : U32) > 65535 : U32), Bool.pick(U32, ((bits - 1136656384 : U32) >= 2147483648 : U32), 32768, 32767), ((bits - 1136656384) .&. 65535 : U32))

# Refused: a float from -768 to -384 (both left out), whose conversion
# overflows an int, and a NaN, whose sign (which the conversion goes by) is
# the machine's.
def sample.refused(+x: F32) -> Bool:
  nan(F32.bits(x)) || short.undefined(F32.bits((x + 384.0 : F32)))

# A float as a short: x*32768 rounded to the nearest (to the even one of
# two as near), no further than -32768 and 32767.
def sample.short(+x: F32) -> U32:
  short.clamped(F32.bits((x + 384.0 : F32)))

# Shorts, the last first, and whether none was refused.
type Shorts is Data:
  Shorts{samples: +List<U32>, fine: Bool}

def Shorts.samples(shorts: Shorts) -> +List<U32>:
  Shorts{samples, _} = shorts
  samples

def Shorts.fine(shorts: Shorts) -> Bool:
  Shorts{_, fine} = shorts
  fine

# A sample of each channel.
def shorts.one(rows: +List<R.Row>, fine: Bool, +j: U32, +samples: +List<U32>) -> Shorts:
  match rows fine:
    case _ False{}: Shorts{samples, False{}}
    case Nil{} True{}: Shorts{samples, True{}}
    case Con{+row, +rest} True{}: shorts.one(rest, Bool.not(sample.refused(R.Row.get(row, j))), j, Con{sample.short(R.Row.get(row, j)), samples})

# convert_channels_short_interleaved for as many channels as the data has:
# n samples of each from j on.
def shorts.each(n: Nat, fine: Bool, +j: U32, +rows: +List<R.Row>, +samples: +List<U32>) -> Shorts:
  match n fine:
    case _ False{}: Shorts{samples, False{}}
    case 0n True{}: Shorts{samples, True{}}
    case 1n+k True{}:
      +next = shorts.one(rows, True{}, j, samples)
      shorts.each(k, Shorts.fine(next), (j + 1 : U32), rows, Shorts.samples(next))

# -----------------------------------------------------------------------------
# stb_vorbis_get_samples_short_interleaved

# The decoder after a read, how many samples of each channel were read and
# the shorts, interleaved. `on` is the loop's own.
type Read is Data:
  Read{frames: Frames, count: U32, samples: +List<U32>, on: Bool}

def Read.frames(read: Read) -> Frames:
  Read{frames, _, _, _} = read
  frames

def Read.count(read: Read) -> U32:
  Read{_, count, _, _} = read
  count

def Read.samples(read: Read) -> +List<U32>:
  Read{_, _, samples, _} = read
  samples

def Read.on(read: Read) -> Bool:
  Read{_, _, _, on} = read
  on

def frame.refused(frames: Frames) -> Frames:
  match frames:
    case Frames{K.State{+reader, +rows, +loc, +known, +discard}, +previous, +length, +start, +end, +output}: Frames{K.State{O.undefined(reader), rows, loc, known, discard}, previous, length, start, end, output}

def read.framed(got: Got, +n: U32, +samples: +List<U32>) -> Read:
  Got{+frames, +value} = got
  Read{frames, n, samples, U32.is_ne(value, 0)}

# With as many samples as were asked for the read is over; otherwise the
# next frame is decoded, and a frame that gives no sample ends the read.
def read.moved(done: Bool, +plan: K.Plan, +frames: Frames, +n: U32, +samples: +List<U32>) -> Read:
  match done:
    case True{}: Read{frames, n, samples, False{}}
    case False{}: read.framed(frame.float(plan, frames), n, samples)

def read.converted(shorts: Shorts, +plan: K.Plan, +frames: Frames, +n: U32, +len: U32, +k: U32) -> Read:
  match shorts:
    case Shorts{+samples, False{}}: Read{frame.refused(frames), n, samples, False{}}
    case Shorts{+samples, True{}}: read.moved(U32.is_eq((n + k : U32), len), plan, frame.placed(frames, (Frames.start(frames) + k : U32), Frames.end(frames)), (n + k : U32), samples)

def read.taken(+plan: K.Plan, +frames: Frames, +n: U32, +len: U32, +k: U32, +samples: +List<U32>) -> Read:
  read.converted(shorts.each(U32.to_nat(k), True{}, Frames.start(frames), K.State.rows(Frames.state(frames)), samples), plan, frames, n, len, k)

# A turn of the loop: the samples at hand, as many as are still asked for.
def read.turn(+plan: K.Plan, +frames: Frames, +n: U32, +len: U32, +samples: +List<U32>) -> Read:
  read.taken(plan, frames, n, len, Bool.pick(U32, ((n + (Frames.end(frames) - Frames.start(frames)) : U32) >= len : U32), (len - n : U32), (Frames.end(frames) - Frames.start(frames) : U32)), samples)

def read.tail(fuel: Nat, on: Bool, +plan: K.Plan, +frames: Frames, +n: U32, +len: U32, +samples: +List<U32>) -> Read:
  match fuel on:
    case _ False{}: Read{frames, n, samples, False{}}
    case 0n True{}: Read{frames, n, samples, False{}}
    case 1n+more True{}:
      +next = read.turn(plan, frames, n, len, samples)
      read.tail(more, Read.on(next), plan, Read.frames(next), Read.count(next), len, Read.samples(next))

# A turn that goes on decoded a packet: the data's bytes outlast them, but
# for those of the page at hand.
def read.loop(fuel: +List<U32>, on: Bool, +plan: K.Plan, +frames: Frames, +n: U32, +len: U32, +samples: +List<U32>) -> Read:
  match fuel on:
    case _ False{}: Read{frames, n, samples, False{}}
    case Nil{} True{}: read.tail(600n, True{}, plan, frames, n, len, samples)
    case Con{_, +more} True{}:
      +next = read.turn(plan, frames, n, len, samples)
      read.loop(more, Read.on(next), plan, Read.frames(next), Read.count(next), len, Read.samples(next))

def read.ended(read: Read) -> Read:
  Read{frames, count, samples, on} = read
  Read{frames, count, List.reverse(&2, U32, samples), on}

# stb_vorbis_get_samples_short_interleaved(f, f->channels, buffer, shorts):
# shorts/channels samples of each channel, or as many as the stream has
# before a frame that gives none. A float that is refused leaves the
# reader's error 1001 (see Frames.refused), and what was read is not to be
# used. `shorts` is an int above -1.
def samples.read(+plan: K.Plan, +frames: Frames, +shorts: U32) -> Read:
  read.ended(read.loop(O.Stream.rest(O.Reader.stream(Frames.reader(frames))), Bool.not(Frames.refused(frames)) && ((shorts / U32.max(K.Plan.channels(plan), 1) : U32) > 0 : U32), plan, frames, 0,
    (shorts / U32.max(K.Plan.channels(plan), 1) : U32), Nil{}))
