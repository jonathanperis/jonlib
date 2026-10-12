# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_mp3 v0.7.4 (David Reid; public domain or MIT
# No Attribution; its decoder is minimp3, by lieff, CC0), as raylib 6.0
# vendors it in src/external/dr_mp3.h: a stream's samples
# (drmp3_decode_next_frame_ex__callbacks with its samples, drmp3_init's first
# frame, drmp3_read_pcm_frames_raw, drmp3_read_pcm_frames_s16,
# drmp3_read_pcm_frames_f32 with drmp3_s16_to_f32,
# drmp3_seek_to_start_of_stream with drmp3_reset, and drmp3_seek_to_pcm_frame
# without a seek table). See THIRD_PARTY_NOTICES.md and LICENSES/dr_mp3.txt.
#
# src/mp3.bend reads the file and counts its frames; src/mp3_layer3.bend
# decodes a frame. This is the two together: dr_mp3's drmp3 as raylib uses
# it, which decodes 16-bit samples a frame at a time and hands out as many
# as are asked for.
import Base
import ./mp3.bend as H
import ./mp3_layer3.bend as L

# drmp3: the file through its buffer (H.Stream, with the stream's channels,
# sample rate, delay, padding and tagged total), the decoder, the 2304
# samples of pcmFrames (a frame's are written over the start of what was
# there), pcmFramesConsumedInMP3Frame and pcmFramesRemainingInMP3Frame, the
# channels of the frame decoded last (mp3FrameChannels), currentPCMFrame,
# and `status`: 0, or why the stream stopped (L.Decoded's: 1 a frame dr_mp3
# decodes by leaving one of its arrays, 2 a Layer I or II frame, which this
# port does not decode yet).
type Player is Data:
  Player{stream: H.Stream, decoder: L.Decoder, pcm: +List<U32>, consumed: U32, remaining: U32, channels: U32, current: U32, status: U32}

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

# The decoder's header, free format size and reservoir, which the stream
# keeps too.
def Decoder.dec(decoder: L.Decoder) -> H.Dec:
  L.Decoder{dec, _, _, _, _, _, _, _, _} = decoder
  dec

# drmp3dec_init: the header's first byte cleared, so that the next frame is
# searched for in a zeroed decoder.
def Decoder.cleared(decoder: L.Decoder) -> L.Decoder:
  L.Decoder{H.Dec{+header, free, reserv}, main, scf, ist0, ist1, compress, overlap0, overlap1, qmf} = decoder
  L.Decoder{H.Dec{(header .&. 16777215 : U32), free, reserv}, main, scf, ist0, ist1, compress, overlap0, overlap1, qmf}

def Stream.have(stream: H.Stream) -> U32:
  H.Stream{_, _, _, _, _, have, _, _, _, _, _, _, _, _, _, _, _} = stream
  have

# The stream with the decoder's header, free format size and reservoir.
def Stream.with(stream: H.Stream, dec: H.Dec) -> H.Stream:
  H.Stream{data, size, length, start, at, have, pos, cursor, cap, end, _, delay, padding, known, total, channels, rate} = stream
  H.Stream{data, size, length, start, at, have, pos, cursor, cap, end, dec, delay, padding, known, total, channels, rate}

# The frame of the stream's buffer, with its samples.
def buffered(+stream: H.Stream, +decoder: L.Decoder) -> L.Decoded:
  L.decode(decoder, H.stream.at(stream), Stream.have(stream))

# What drmp3_decode_next_frame gives: the stream and the decoder after it,
# the frame's samples for a channel (0: none, the stream ended or stopped),
# why it stopped, the samples and the frame's channels.
type Next is Data:
  Next{stream: H.Stream, decoder: L.Decoder, samples: U32, status: U32, pcm: +List<U32>, channels: U32}

def next.frame(+stream: H.Stream, +decoder: L.Decoder, +samples: U32, +bytes: U32, +status: U32, +pcm: +List<U32>) -> Next:
  L.Decoder{H.Dec{+header, _, _}, _, _, _, _, _, _, _, _} = decoder
  Next{H.stream.used(stream, Decoder.dec(decoder), bytes), decoder, Bool.pick(U32, U32.is_eq(status, 0), samples, 0), status, pcm, Bool.pick(U32, H.hdr.mono(header), 1, 2)}

# The loop of drmp3_decode_next_frame_ex__callbacks with a buffer for the
# samples: a frame is decoded from the buffer and its bytes leave it; one
# with samples ends the loop, as does one this port refuses; anything else
# (bytes that are no frame, a frame that decodes nothing) is passed and the
# buffer filled again. `frame` is the frame of `stream`'s buffer and
# `before` the decoder it was decoded with.
def next.loop(n: Nat, ended: Bool, frame: L.Decoded, +stream: H.Stream, +before: L.Decoder) -> Next:
  match n:
    case 0n: Next{stream, before, 0, 0, Nil{}, 0}
    case 1n+rest:
      match ended frame:
        case True{} _: Next{stream, before, 0, 0, Nil{}, 0}
        case False{} L.Decoded{+decoder, 0, +bytes, 0, _, _}:
          +filled = H.stream.fill(H.stream.used(stream, Decoder.dec(decoder), bytes))
          next.loop(rest, H.stream.ended(filled), buffered(filled, decoder), filled, decoder)
        case False{} L.Decoded{+decoder, +samples, +bytes, +status, _, +pcm}: next.frame(stream, decoder, samples, bytes, status, pcm)

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# pcmFrames once a frame's samples are written at its start.
def pcm.written(+samples: +List<U32>, +array: +List<U32>) -> +List<U32>:
  List.append(&2, U32, samples, List.drop(&2, U32, array, U32.to_nat(count(samples, 0))))

# The player after drmp3_decode_next_frame. A frame with samples becomes the
# frame at hand, none consumed; without one nothing changes but the stream
# and the decoder (and `status` when the frame is one this port refuses).
def next.player(next: Next, +pcm: +List<U32>, +consumed: U32, +remaining: U32, +channels: U32, +current: U32, +status: U32) -> Player:
  match next:
    case Next{stream, decoder, 0, +stopped, _, _}: Player{stream, decoder, pcm, consumed, remaining, channels, current, U32.max(status, stopped)}
    case Next{stream, decoder, +samples, _, +written, +of}: Player{stream, decoder, pcm.written(written, pcm), 0, samples, of, current, status}

# drmp3_decode_next_frame: the next frame that decodes, its samples in
# pcmFrames. A player that stopped stays where it is.
def next.go(stopped: Bool, +player: Player) -> Player:
  match stopped:
    case True{}: player
    case False{}:
      Player{+stream, +decoder, +pcm, +consumed, +remaining, +channels, +current, +status} = player
      +filled = H.stream.fill(stream)
      next.player(next.loop(U32.to_nat(((H.stream.size(stream) / 4) + 16 : U32)), H.stream.ended(filled), buffered(filled, decoder), filled, decoder), pcm, consumed, remaining, channels, current, status)

def Player.status(player: Player) -> U32:
  Player{_, _, _, _, _, _, _, status} = player
  status

def Player.remaining(player: Player) -> U32:
  Player{_, _, _, _, remaining, _, _, _} = player
  remaining

def Player.current(player: Player) -> U32:
  Player{_, _, _, _, _, _, current, _} = player
  current

def Player.stream(player: Player) -> H.Stream:
  Player{stream, _, _, _, _, _, _, _} = player
  stream

# The stream's channels and sample rate: its first frame's.
def Player.channels(player: Player) -> U32:
  Player{H.Stream{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, channels, _}, _, _, _, _, _, _, _} = player
  channels

def Player.rate(player: Player) -> U32:
  Player{H.Stream{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rate}, _, _, _, _, _, _, _} = player
  rate

def advance(+player: Player) -> Player:
  next.go(U32.is_ne(Player.status(player), 0), player)

# -----------------------------------------------------------------------------
# drmp3_init

# The player once the first frame is decoded with its samples. An Xing/Info
# frame is not played: none of its samples remain, the decoder's header is
# cleared and the stream starts after it (H.open's stream); its samples stay
# in pcmFrames as dr_mp3 leaves them.
def open.first(tagged: Bool, first: Player, +opened: H.Stream) -> Player:
  match tagged:
    case False{}:
      Player{_, +decoder, pcm, consumed, remaining, channels, current, status} = first
      Player{Stream.with(opened, Decoder.dec(decoder)), decoder, pcm, consumed, remaining, channels, current, status}
    case True{}:
      Player{_, +decoder, pcm, _, _, channels, _, status} = first
      Player{Stream.with(opened, Decoder.dec(Decoder.cleared(decoder))), Decoder.cleared(decoder), pcm, 0, 0, channels, 0, status}

# The stream as drmp3_init has it before its first frame: the bytes before
# the tags at the file's end, from the byte after an ID3v2 tag.
def open.stream(+data: +List<U32>, +opened: H.Stream) -> H.Stream:
  H.Stream{_, +size, +length, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = opened
  +start = H.tags.id3v2(data)
  H.Stream{data, size, length, start, List.drop(&2, U32, data, U32.to_nat(U32.min(start, size))), 0, start, start, 0, False{}, H.Dec.zero(), 0, 0, False{}, 0, 0, 0}

def open.opened(opened: Maybe<H.Opened>, +data: +List<U32>) -> Maybe<Player>:
  match opened:
    case None{}: None{}
    case Some{H.Opened{+stream, +first}}:
      Some{open.first(Bool.not(first), advance(Player{open.stream(data, stream), L.Decoder.zero(), zeros(2304n, Nil{}), 0, 0, 0, 0, 0}), stream)}

# drmp3_init_file on the file's bytes: None where it fails (H.open).
def open(+data: +List<U32>) -> Maybe<Player>:
  open.opened(H.open(data), data)

# -----------------------------------------------------------------------------
# Reading (drmp3_read_pcm_frames_raw)

# `count` samples of pcmFrames from `from`.
def pcm.taken(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      match xs:
        case Nil{}: pcm.taken(k, Nil{}, Con{0, acc})
        case Con{+x, rest}: pcm.taken(k, rest, Con{x, acc})

def pcm.copied(keep: Bool, +pcm: +List<U32>, +from: U32, +count: U32) -> +List<U32>:
  match keep:
    case False{}: Nil{}
    case True{}: pcm.taken(U32.to_nat(count), List.drop(&2, U32, pcm, U32.to_nat(from)), Nil{})

# A read as it goes: the player, the frames still wanted, those read, the
# samples read (a list for each turn, the last first) and whether it is over.
type Step is Data:
  Step{player: Player, want: U32, got: U32, out: +List<+List<U32>>, stop: Bool}

# After a turn that did not end the read, the next frame is decoded; the
# read is over when there is none.
def turn.more(stop: Bool, +player: Player, +want: U32, +got: U32, +out: +List<+List<U32>>) -> Step:
  match stop:
    case True{}: Step{player, want, got, out, True{}}
    case False{}:
      +after = advance(player)
      Step{after, want, got, out, U32.is_eq(Player.remaining(after), 0) || U32.is_ne(Player.status(after), 0)}

# A turn of drmp3_read_pcm_frames_raw's loop. The frames of the delay are
# passed first (they count in currentPCMFrame and not in what is read); then
# as many frames as the frame at hand has and are wanted, no further than
# the padding when the stream's total is known (inside the padding the read
# is over before anything is copied); a frame is as many samples as the
# stream has channels, from where the frame's own channel count puts it.
def turn.taken(into: Bool, +player: Player, +want: U32, +got: U32, +out: +List<+List<U32>>, +keep: Bool, +take: U32, +limited: Bool, +edge: U32, +frames: U32) -> Step:
  match into:
    case True{}: Step{player, want, got, out, True{}}
    case False{}:
      Player{stream, decoder, +pcm, +consumed, +remaining, +channels, +current, status} = player
      turn.more(U32.is_eq(want, take) || (limited && ((current + take) >= edge : U32)),
        Player{stream, decoder, pcm, (consumed + take : U32), (remaining - take : U32), channels, (current + take : U32), status}, (want - take : U32), (got + take : U32),
        Con{pcm.copied(keep, pcm, (consumed * channels : U32), (take * frames : U32)), out})

# The frames of the delay passed at the start of a turn: what is left of the
# delay, no more than the frame at hand has.
def turn.skip(+current: U32, +delay: U32, +remaining: U32) -> U32:
  Bool.pick(U32, (current < delay : U32), U32.min(remaining, (delay - U32.min(current, delay) : U32)), 0)

# The frames a turn takes: those left of the frame at hand, no more than
# are wanted, and with a known total (`limited`) no further than `edge`,
# the total less the padding.
def turn.take(+left: U32, +want: U32, +limited: Bool, +edge: U32, +at: U32) -> U32:
  U32.min(U32.min(left, want), Bool.pick(U32, limited, (edge - U32.min(at, edge) : U32), 4294967295))

def turn(+player: Player, +want: U32, +got: U32, +out: +List<+List<U32>>, +keep: Bool) -> Step:
  Player{+stream, decoder, pcm, +consumed, +remaining, channels, +current, status} = player
  H.Stream{_, _, _, _, _, _, _, _, _, _, _, +delay, +padding, +known, +total, +frames, _} = stream
  +skip = turn.skip(current, delay, remaining)
  +limited = known && (total > padding : U32)
  +edge = (total - U32.min(padding, total) : U32)
  +at = (current + skip : U32)
  +left = (remaining - skip : U32)
  turn.taken(limited && (at >= edge : U32), Player{stream, decoder, pcm, (consumed + skip : U32), left, channels, at, status}, want, got, out, keep, turn.take(left, want, limited, edge, at), limited, edge,
    frames)

def read.loop(n: Nat, state: Step, +keep: Bool) -> Step:
  match n:
    case 0n: state
    case 1n+k:
      match state:
        case Step{player, want, got, out, True{}}: Step{player, want, got, out, True{}}
        case Step{+player, +want, +got, +out, False{}}: read.loop(k, turn(player, want, got, out, keep), keep)

def blocks.joined(blocks: +List<+List<U32>>, acc: +List<U32>) -> +List<U32>:
  match blocks:
    case Nil{}: acc
    case Con{+block, rest}: blocks.joined(rest, List.append(&2, U32, block, acc))

# What a read gives: the player after it, the frames read and their samples
# (an int16's 16 bits each, a frame a channel after a channel).
type Read is Data:
  Read{player: Player, frames: U32, samples: +List<U32>}

def read.done(state: Step) -> Read:
  Step{player, _, got, out, _} = state
  Read{player, got, blocks.joined(out, Nil{})}

# drmp3_read_pcm_frames_raw: `frames` frames from where the player is, or as
# many as there are; without `keep` they are passed and not returned (what
# a seek forward does). No frame is asked of a stream that stopped.
def read.raw(+player: Player, +frames: U32, +keep: Bool) -> Read:
  Player{+stream, _, _, _, _, _, _, +status} = player
  read.done(read.loop(U32.to_nat(((H.stream.size(stream) / 4) + 18 : U32)), Step{player, frames, 0, Nil{}, U32.is_eq(frames, 0) || U32.is_ne(status, 0)}, keep))

# drmp3_read_pcm_frames_s16.
def read.s16(+player: Player, +frames: U32) -> Read:
  read.raw(player, frames, True{})

# drmp3_s16_to_f32: a sample over 32768, as a float.
def sample.float(+bits: U32) -> F32:
  (Bool.pick(F32, (bits >= 32768 : U32), F32.neg(U32.to_f32((65536 - bits : U32))), U32.to_f32(bits)) * 0.000030517578125 : F32)

def pcm.floats(xs: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match xs:
    case Nil{}: List.reverse(&2, F32, acc)
    case Con{+x, rest}: pcm.floats(rest, Con{sample.float(x), acc})

# drmp3_read_pcm_frames_f32 as raylib's build has it: the 16-bit samples,
# each over 32768.
type Floats is Data:
  Floats{player: Player, frames: U32, samples: +List<F32>}

def read.floats(read: Read) -> Floats:
  Read{player, frames, samples} = read
  Floats{player, frames, pcm.floats(samples, Nil{})}

def read.f32(+player: Player, +frames: U32) -> Floats:
  read.floats(read.raw(player, frames, True{}))

# -----------------------------------------------------------------------------
# Seeking

# drmp3_seek_to_start_of_stream: the file at the stream's start, the buffer
# empty, no frame at hand, currentPCMFrame 0 and the decoder's header
# cleared. pcmFrames and the last frame's channels stay.
def rewind(player: Player) -> Player:
  Player{stream, decoder, pcm, _, _, channels, _, status} = player
  Player{H.stream.rewound(stream), Decoder.cleared(decoder), pcm, 0, 0, channels, 0, status}

# What a seek gives: the player, and whether dr_mp3 calls it done.
type Sought is Data:
  Sought{player: Player, done: Bool}

def seek.read(read: Read, +frames: U32) -> Sought:
  Read{player, +got, _} = read
  Sought{player, U32.is_eq(got, frames)}

# drmp3_seek_forward_by_pcm_frames__brute_force: the frames are read and
# dropped.
def seek.forward(+player: Player, +frames: U32) -> Sought:
  seek.read(read.raw(player, frames, False{}), frames)

# Which way a seek to `frame` goes from currentPCMFrame. 0: frame 0 is the
# start; 1: the frame the count stands at is where the player is; 2: a later
# one is read up to; 3: an earlier one is read up to from the start.
def seek.which(+frame: U32, +current: U32) -> U32:
  Bool.pick(U32, U32.is_eq(frame, 0), 0, Bool.pick(U32, U32.is_eq(frame, current), 1, Bool.pick(U32, (frame > current : U32), 2, 3)))

def seek.way(way: U32, +player: Player, +frame: U32) -> Sought:
  match way:
    case 0: Sought{rewind(player), True{}}
    case 1: Sought{player, True{}}
    case 2: seek.forward(player, (frame - Player.current(player) : U32))
    case _: seek.forward(rewind(player), frame)

# drmp3_seek_to_pcm_frame without a seek table. currentPCMFrame counts the
# delay's frames and a read does not, so the frame sought is `frame` reads
# from where the count stands, not the stream's frame of that index: a seek
# to a frame the count has passed goes back to the start first.
def seek(+player: Player, +frame: U32) -> Sought:
  seek.way(seek.which(frame, Player.current(player)), player, frame)

# What drmp3_get_pcm_frame_count gives, as an unsigned int (raylib's
# music.frameCount), and the player after it.
type Counted is Data:
  Counted{player: Player, frames: U32}

def total.sought(sought: Sought, +frames: U32) -> Counted:
  Sought{player, +done} = sought
  Counted{player, Bool.pick(U32, done, frames, 0)}

def total.known(known: Bool, +player: Player) -> Counted:
  match known:
    case True{}: Counted{player, H.total(Player.stream(player))}
    case False{}: total.sought(seek(rewind(player), Player.current(player)), H.scan.samples(H.scan(Player.stream(player))))

# drmp3_get_pcm_frame_count. With an Xing/Info frame's count the stream is
# left as it is. Without one every frame is counted from the start, and the
# player is put back by a seek from the start to the frame its count stood
# at: the frame at hand is decoded again, and a count that seek cannot reach
# makes the result 0.
def total(+player: Player) -> Counted:
  Player{H.Stream{_, _, _, _, _, _, _, _, _, _, _, _, _, +known, _, _, _}, _, _, _, _, _, _, _} = player
  total.known(known, player)
