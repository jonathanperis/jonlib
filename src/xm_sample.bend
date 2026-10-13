# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_xm (Joshua Reisenauer's port of libxm by
# Romain "Artefact2" Dalmaso; WTFPL), as raylib 6.0 vendors it in
# src/external/jar_xm.h: a channel's next sample (jar_xm_next_of_sample,
# with linear interpolation and ramping on, as jar_xm loads every module).
# See THIRD_PARTY_NOTICES.md and LICENSES/jar_xm.txt.
#
# C ints are U32 two's-complement words. A step that C leaves undefined (a
# position that is no unsigned int, a read past the sample's data) is not
# fine.
import Base
import ./store.bend as R

# A sample as the step reads it: its length, its loop (start, length, end),
# whether it loops forward (jar_xm loads no other loop), whether it is
# stereo, its data and how many floats that is.
type Tone is Data:
  Tone{length: U32, loop_start: U32, loop_length: U32, loop_end: U32, looped: Bool, stereo: Bool, data: R.Row, count: U32}

# What the step keeps of a channel: where in the sample it is
# (sample_position; below 0 for a sample that has ended) and how far a
# frame moves it (step), how many frames the channel has played since its
# note (frame_count), the eight last values of the sample before it, left
# and right (end_of_previous_sample), and the channel's value now.
type Head is Data:
  Head{position: F32, step: F32, frames: U32, lefts: +List<F32>, rights: +List<F32>, left: F32, right: F32}

# The channel after a step, and whether C defines it.
type Stepped is Data:
  Stepped{head: Head, fine: Bool}

def float.at(xs: +List<F32>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{+x, _}: x

def nth(+xs: +List<F32>, +i: U32) -> F32:
  float.at(List.drop(&2, F32, xs, U32.to_nat(U32.min(i, 8))))

def put(xs: +List<F32>, +i: U32, +value: F32) -> +List<F32>:
  match xs:
    case Nil{}: Nil{}
    case Con{+x, +rest}: Bool.pick(+List<F32>, U32.is_eq(i, 0), Con{value, rest}, Con{x, put(rest, (i - 1 : U32), value)})

# jar_xm_LERP(u, v, t).
def lerp(+u: F32, +v: F32, +t: F32) -> F32:
  (u + (t * (v - u)) : F32)

# A value given to the channel: kept as one of the eight before a new note
# (`previous` from 0 to 7), or as the channel's own (-1).
def given(head: Head, +previous: U32, +left: F32, +right: F32) -> Head:
  Head{+position, +step, +frames, +lefts, +rights, +now_left, +now_right} = head
  Bool.pick(Head, (previous < 8 : U32), Head{position, step, frames, put(lefts, previous, left), put(rights, previous, right), now_left, now_right}, Head{position, step, frames, lefts, rights, left, right})

# A channel without a sample to play: silence, reached over its first
# eight frames from the values kept.
def silent(+head: Head, +previous: U32) -> Head:
  Head{+position, +step, +frames, +lefts, +rights, _, _} = head
  Bool.pick(Head, (frames < 8 : U32), given(Head{position, step, frames, lefts, rights, 0.0, 0.0}, previous, lerp(nth(lefts, frames), 0.0, (U32.to_f32(frames) / 8.0 : F32)), lerp(nth(rights, frames), 0.0, (U32.to_f32(frames) / 8.0 : F32))),
    Head{position, step, frames, lefts, rights, 0.0, 0.0})

# The position after a frame. A sample that does not loop ends at its
# length (-1); a loop goes back by its length at its end, and to its start
# from the sample's length on.
def moved(+tone: Tone, +position: F32) -> F32:
  Tone{+length, +loop_start, +loop_length, +loop_end, +looped, _, _, _} = tone
  +back = Bool.pick(F32, (position >= U32.to_f32(loop_end) : F32), (position - U32.to_f32(loop_length) : F32), position)
  Bool.pick(F32, looped, Bool.pick(F32, (back >= U32.to_f32(length) : F32), U32.to_f32(loop_start), back), Bool.pick(F32, (position >= U32.to_f32(length) : F32), (0.0 - 1.0 : F32), position))

# Which float follows the one at `at`: the next (`b`), the loop's start at
# the loop's end, and none (0) past a sample that does not loop.
def after(+tone: Tone, +b: U32, +shift: U32) -> U32:
  Tone{_, +loop_start, _, +loop_end, +looped, _, _, _} = tone
  Bool.pick(U32, looped && U32.is_eq(b, loop_end), (loop_start + shift : U32), (b + shift : U32))

def Tone.length(tone: Tone) -> U32:
  Tone{length, _, _, _, _, _, _, _} = tone
  length

def Tone.looped(tone: Tone) -> Bool:
  Tone{_, _, _, _, looped, _, _, _} = tone
  looped

def Tone.stereo(tone: Tone) -> Bool:
  Tone{_, _, _, _, _, stereo, _, _} = tone
  stereo

def Tone.data(tone: Tone) -> R.Row:
  Tone{_, _, _, _, _, _, data, _} = tone
  data

def Tone.count(tone: Tone) -> U32:
  Tone{_, _, _, _, _, _, _, count} = tone
  count

# The float after: read unless the sample does not loop and `b` is at its
# length or past it.
def follows(+tone: Tone, +b: U32) -> Bool:
  Tone.looped(tone) || (b < Tone.length(tone) : U32)

# The step of a sample that plays, its position `at` whole floats in and
# `b` the next: the value between the two floats there, for each side (a
# stereo sample's right side is its data's second half), and the position
# moved on.
def played(+tone: Tone, +head: Head, +previous: U32, +at: U32, +b: U32, +t: F32) -> Stepped:
  Head{+position, +step, +frames, +lefts, +rights, +left, +right} = head
  +far = Bool.pick(U32, Tone.stereo(tone), Tone.length(tone), 0)
  +u_left = R.Row.get(Tone.data(tone), at)
  +u_right = R.Row.get(Tone.data(tone), (at + far : U32))
  +v_left = Bool.pick(F32, follows(tone, b), R.Row.get(Tone.data(tone), after(tone, b, 0)), 0.0)
  +v_right = Bool.pick(F32, follows(tone, b), R.Row.get(Tone.data(tone), after(tone, b, far)), 0.0)
  Stepped{given(Head{moved(tone, (position + step : F32)), step, frames, lefts, rights, left, right}, previous, lerp(u_left, v_left, t), lerp(u_right, v_right, t)),
    ((at + far : U32) < Tone.count(tone) : U32) && (Bool.not(follows(tone, b)) || ((after(tone, b, far) < Tone.count(tone) : U32) && (after(tone, b, 0) < Tone.count(tone) : U32)))}

def Head.position(head: Head) -> F32:
  Head{position, _, _, _, _, _, _} = head
  position

# A position that is an unsigned int, and whose next is one too.
def whole(+position: F32) -> Bool:
  (position >= 0.0 : F32) && ((position + 1.0 : F32) < 4294967296.0 : F32)

def playing(fine: Bool, +tone: Tone, +head: Head, +previous: U32) -> Stepped:
  match fine:
    case False{}: Stepped{head, False{}}
    case True{}: played(tone, head, previous, F32.to_u32(Head.position(head)), F32.to_u32((Head.position(head) + 1.0 : F32)), (Head.position(head) - U32.to_f32(F32.to_u32(Head.position(head))) : F32))

# kind: 0 no sample to play (the channel has none, or its position is
# below 0), 1 a sample without floats (nothing changes), 2 a sample.
def sample.stepped(kind: U32, +tone: Tone, +head: Head, +previous: U32) -> Stepped:
  match kind:
    case 0: Stepped{silent(head, previous), True{}}
    case 1: Stepped{head, True{}}
    case _: playing(whole(Head.position(head)), tone, head, previous)

# jar_xm_next_of_sample(ctx, ch, previous): `sampled` is whether the
# channel has an instrument and a sample.
def sample.next(+sampled: Bool, +tone: Tone, +head: Head, +previous: U32) -> Stepped:
  sample.stepped(Bool.pick(U32, Bool.not(sampled) || (Head.position(head) < 0.0 : F32), 0, Bool.pick(U32, U32.is_eq(Tone.length(tone), 0), 1, 2)), tone, head, previous)
