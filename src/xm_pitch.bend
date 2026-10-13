# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_xm (Joshua Reisenauer's port of libxm by
# Romain "Artefact2" Dalmaso; WTFPL), as raylib 6.0 vendors it in
# src/external/jar_xm.h: a channel's periods and frequencies, linear and
# Amiga (jar_xm_linear_period, jar_xm_linear_frequency, jar_xm_amiga_period,
# jar_xm_amiga_frequency, jar_xm_period, jar_xm_frequency), the waveforms
# (jar_xm_waveform) and the envelopes (jar_xm_envelope_lerp,
# jar_xm_envelope_tick). See THIRD_PARTY_NOTICES.md and LICENSES/jar_xm.txt.
#
# C ints are U32 two's-complement words. None is what C leaves undefined (a
# float outside the int it is converted to, a shift by a count it has not, a
# read past an envelope's points) and what the libm profile does not give.
import Base
import ../jonmath.bend as M
import ./xm_module.bend as Xm

# -----------------------------------------------------------------------------
# Linear frequencies

# jar_xm_linear_period(note).
def linear.period(+note: F32) -> F32:
  (7680.0 - (note * 64.0) : F32)

def linear.scaled(power: Maybe<F32>) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{(8363.0 * p : F32)}

# jar_xm_linear_frequency(period): 8363*powf(2, (4608 - period)/768).
def linear.frequency(+libm: M.Libm, +period: F32) -> Maybe<F32>:
  linear.scaled(M.Libm.pow2(libm, ((4608.0 - period) / 768.0 : F32)))

# -----------------------------------------------------------------------------
# Amiga frequencies

# amiga_frequencies: the periods of C-2 to C-3.
def amiga.table() -> +List<U32>:
  [1712, 1616, 1525, 1440, 1357, 1281, 1209, 1141, 1077, 1017, 961, 907, 856]

def head(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, xs, U32.to_nat(i)))

def nan(+x: F32) -> Bool:
  ((F32.bits(x) .&. 2147483647) > 2139095040 : U32)

# An int as a float (an int8 or a difference of two uint16s here).
def float.of(+a: U32) -> F32:
  Bool.pick(F32, (a >= 2147483648 : U32), (0.0 - U32.to_f32((0 - a : U32)) : F32), U32.to_f32(a))

# A float of (-129, 128) as an int8, toward zero.
def int8.of(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32((0.0 - x : F32)) : U32), F32.to_u32(x))

# A period of the table an octave away, kept in 16 bits: shifted right for
# an octave above 0 and left for one below. `octave` is an int from -20 to
# 31.
def amiga.shifted(+p: U32, +octave: U32) -> U32:
  Bool.pick(U32, (octave >= 2147483648 : U32), ((p << U32.to_nat(U32.min((0 - octave : U32), 31))) .&. 65535 : U32), (p >> U32.to_nat(U32.min(octave, 31)) : U32))

def amiga.lerp(+p1: U32, +p2: U32, +t: F32) -> F32:
  (U32.to_f32(p1) + (t * float.of((p2 - p1 : U32))) : F32)

def amiga.noted(+note: F32, +whole: U32, +octave: U32) -> F32:
  amiga.lerp(amiga.shifted(nth(amiga.table(), (whole % 12 : U32)), octave), amiga.shifted(nth(amiga.table(), ((whole % 12) + 1 : U32)), octave), (note - U32.to_f32(whole) : F32))

def amiga.defined(fine: Bool, +note: F32) -> Maybe<F32>:
  match fine:
    case False{}: None{}
    case True{}: Some{amiga.noted(note, Bool.pick(U32, (note < 0.0 : F32), 0, F32.to_u32(note)), int8.of(((note / 12.0) - 2.0 : F32)))}

# jar_xm_amiga_period(note): the note's place between two periods of the
# table, an octave away. The note is converted to an unsigned int and its
# octave to an int8, which is then a shift's count: a NaN, a note of -1 or
# less and an octave past 31 are undefined.
def amiga.period(+note: F32) -> Maybe<F32>:
  amiga.defined(Bool.not(nan(note)) && (note > (0.0 - 1.0 : F32) : F32) && (((note / 12.0) - 2.0 : F32) < 32.0 : F32), note)

# jar_xm_amiga_frequency(period).
def amiga.frequency(+period: F32) -> F32:
  Bool.pick(F32, F32.is_eq(period, 0.0), 0.0, (7093789.2 / (period * 2.0) : F32))

# The octave of a period above the table's first: the first whose shifted
# period reaches it, from -1 down. One past -20 would shift an int out of
# its bits (0 here).
def octave.below(n: Nat, +period: F32, +octave: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+k: Bool.pick(U32, (period > U32.to_f32((1712 << U32.to_nat((0 - octave : U32)) : U32)) : F32), octave.below(k, period, (octave - 1 : U32)), octave)

# ... and of one below the table's last, from 1 up (a period of 0 ends at
# 10, where the shifted period is 0).
def octave.above(n: Nat, +period: F32, +octave: U32) -> U32:
  match n:
    case 0n: octave
    case 1n+k: Bool.pick(U32, (period < U32.to_f32((856 >> U32.to_nat(octave) : U32)) : F32), octave.above(k, period, (octave + 1 : U32)), octave)

def octave.of(+period: F32) -> U32:
  Bool.pick(U32, (period > 1712.0 : F32), octave.below(20n, period, 4294967295), Bool.pick(U32, (period < 856.0 : F32), octave.above(10n, period, 1), 0))

# The table's first pair of periods, an octave away, that the period lies
# between: its number, and the pair (the last pair and 0 if there is none).
type Found is Data:
  Found{a: U32, p1: U32, p2: U32}

def found.in(rest: +List<U32>, on: Bool, +first: U32, +i: U32, +period: F32, +octave: U32, +found: Found) -> Found:
  match rest on:
    case _ False{}: found
    case Nil{} True{}: found
    case Con{+second, +more} True{}:
      +p1 = amiga.shifted(first, octave)
      +p2 = amiga.shifted(second, octave)
      +inside = (U32.to_f32(p2) <= period : F32) && (period <= U32.to_f32(p1) : F32)
      found.in(more, Bool.not(inside), second, (i + 1 : U32), period, octave, Found{Bool.pick(U32, inside, i, 0), p1, p2})

def tail(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

def offset.noted(found: Found, +period: F32, +octave: U32, +offset: F32) -> Maybe<F32>:
  Found{+a, +p1, +p2} = found
  amiga.period(((((12.0 * float.of((octave + 2 : U32))) + U32.to_f32(a)) + ((period - U32.to_f32(p1)) / float.of((p2 - p1 : U32)))) + offset : F32))

def amiga.frequent(period: Maybe<F32>) -> Maybe<F32>:
  match period:
    case None{}: None{}
    case Some{+p}: Some{amiga.frequency(p)}

def amiga.offset(fine: Bool, +period: F32, +offset: F32) -> Maybe<F32>:
  match fine:
    case False{}: None{}
    case True{}: amiga.frequent(offset.noted(found.in(tail(amiga.table()), True{}, 1712, 0, period, octave.of(period), Found{0, 0, 0}), period, octave.of(period), offset))

# -----------------------------------------------------------------------------
# jar_xm_period and jar_xm_frequency

# jar_xm_period(ctx, note): `kind` is the module's frequency type (0
# linear, 1 Amiga).
def period.of(+kind: U32, +note: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, U32.is_eq(kind, 0), Some{linear.period(note)}, Bool.pick(Maybe<F32>, U32.is_eq(kind, 1), amiga.period(note), Some{0.0}))

# The frequency of an Amiga period a note's offset away: the period's note
# is found in the table (its octave by shifts: a period below 0, or past
# the table's first shifted 20 bits, is undefined), the offset added, and
# the note's period taken again.
def amiga.away(+period: F32, +offset: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(offset, 0.0), Some{amiga.frequency(period)}, amiga.offset(nan(period) || ((period >= 0.0 : F32) && (period <= 1795162112.0 : F32)), period, offset))

# jar_xm_frequency(ctx, period, note_offset).
def frequency.of(+libm: M.Libm, +kind: U32, +period: F32, +offset: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, U32.is_eq(kind, 0), linear.frequency(libm, (period - (64.0 * offset) : F32)), Bool.pick(Maybe<F32>, U32.is_eq(kind, 1), amiga.away(period, offset), Some{0.0}))

# -----------------------------------------------------------------------------
# jar_xm_waveform

# A waveform's value, whether the libm profile gives it, and the random
# waveform's state after it (jar_xm keeps one for every module it plays:
# 24492 at first).
type Wave is Data:
  Wave{value: F32, fine: Bool, random: U32}

# The sine negated: its sign changed, so that a sine of 0 is -0.
def wave.sine(sine: Maybe<F32>, +random: U32) -> Wave:
  match sine:
    case None{}: Wave{0.0, False{}, random}
    case Some{+s}: Wave{(s * (0.0 - 1.0 : F32) : F32), True{}, random}

# The random waveform's next state: the generator of POSIX.1-2001's example.
def random.next(+random: U32) -> U32:
  ((random * 1103515245) + 12345 : U32)

# jar_xm_waveform(waveform, step): the step is a byte, taken modulo 64.
# 0 a sine (-sinf of the step's 64th of a turn), 1 a ramp down, 2 a square,
# 3 random (the POSIX example generator), 4 a ramp up, anything else 0.
def waveform(kind: U32, +libm: M.Libm, +step: U32, +random: U32) -> Wave:
  match kind:
    case 0: wave.sine(M.Libm.sin(libm, ((6.283184 * U32.to_f32(((step .&. 255) % 64 : U32))) / 64.0 : F32)), random)
    case 1: Wave{(float.of((32 - ((step .&. 255) % 64) : U32)) / 32.0 : F32), True{}, random}
    case 2: Wave{Bool.pick(F32, (((step .&. 255) % 64 : U32) >= 32 : U32), 1.0, (0.0 - 1.0 : F32)), True{}, random}
    case 3: Wave{((U32.to_f32(((random.next(random) >> 16n) .&. 32767 : U32)) / 16384.0) - 1.0 : F32), True{}, random.next(random)}
    case 4: Wave{(float.of((((step .&. 255) % 64) - 32 : U32)) / 32.0 : F32), True{}, random}
    case _: Wave{0.0, True{}, random}

# -----------------------------------------------------------------------------
# Envelopes

def point.at(points: +List<Xm.Point>) -> Xm.Point:
  match points:
    case Nil{}: Xm.Point{0, 0}
    case Con{+p, _}: p

def point.nth(+points: +List<Xm.Point>, +i: U32) -> Xm.Point:
  point.at(List.drop(&2, Xm.Point, points, U32.to_nat(U32.min(i, 12))))

def Point.frame(point: Xm.Point) -> U32:
  Xm.Point{frame, _} = point
  frame

def Point.value(point: Xm.Point) -> U32:
  Xm.Point{_, value} = point
  value

# jar_xm_envelope_lerp(a, b, pos): the value between two points at a frame.
def envelope.lerp(a: Xm.Point, b: Xm.Point, +pos: U32) -> F32:
  Xm.Point{+from, +low} = a
  Xm.Point{+to, +high} = b
  Bool.pick(F32, (pos <= from : U32), U32.to_f32(low), Bool.pick(F32, (pos >= to : U32), U32.to_f32(high),
    ((U32.to_f32(low) * (1.0 - (float.of((pos - from : U32)) / float.of((to - from : U32))))) + (U32.to_f32(high) * (float.of((pos - from : U32)) / float.of((to - from : U32)))) : F32)))

# An envelope's counter and value after a tick, and whether the tick read
# only the envelope's 12 points.
type Ticked is Data:
  Ticked{counter: U32, value: F32, fine: Bool}

# The value at the counter: the first pair of points it lies between, over
# 64; the value stays where there is none.
def envelope.value(rest: +List<Xm.Point>, n: Nat, on: Bool, +first: Xm.Point, +counter: U32, +value: F32) -> F32:
  match rest n on:
    case Con{+second, +more} 1n+k True{}:
      envelope.value(more, k, Bool.not((Point.frame(first) <= counter : U32) && (Point.frame(second) >= counter : U32)), second, counter,
        Bool.pick(F32, (Point.frame(first) <= counter : U32) && (Point.frame(second) >= counter : U32), (envelope.lerp(first, second, counter) / 64.0 : F32), value))
    case _ _ _: value

def points.tail(points: +List<Xm.Point>) -> +List<Xm.Point>:
  match points:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

# The counter in the loop: one at the loop's end or past it goes back by
# the loop's length (16-bit ints).
def envelope.looped(+looped: Bool, +points: +List<Xm.Point>, +start: U32, +end: U32, +counter: U32) -> U32:
  Bool.pick(U32, looped && (counter >= Point.frame(point.nth(points, end)) : U32), ((counter - ((Point.frame(point.nth(points, end)) - Point.frame(point.nth(points, start))) .&. 65535)) .&. 65535 : U32), counter)

# With two points or more: the loop, the value, and the counter moved on
# unless the channel is sustained at the envelope's sustain point.
def envelope.many(envelope: Xm.Envelope, +sustained: Bool, +counter: U32, +value: F32) -> Ticked:
  Xm.Envelope{+points, +count, +sustain, +loop_start, +loop_end, _, +sustains, +looped} = envelope
  +at = envelope.looped(looped, points, loop_start, loop_end, counter)
  Ticked{Bool.pick(U32, sustained && sustains && U32.is_eq(at, Point.frame(point.nth(points, sustain))), at, ((at + 1) .&. 65535 : U32)), envelope.value(points.tail(points), U32.to_nat((count - 1 : U32)), True{}, point.at(points), at, value),
    Bool.not(looped && ((loop_start > 11 : U32) || (loop_end > 11 : U32))) && Bool.not(sustained && sustains && (sustain > 11 : U32))}

def envelope.one(envelope: Xm.Envelope, +counter: U32) -> Ticked:
  Xm.Envelope{+points, _, _, _, _, _, _, _} = envelope
  Ticked{counter, F32.min((U32.to_f32(Point.value(point.nth(points, 0))) / 64.0 : F32), 1.0), True{}}

# jar_xm_envelope_tick(ch, env, &counter, &outval): `kind` is 0 for an
# envelope without points (nothing changes), 1 for one point (its value
# over 64, 1 at most), 2 for more. The loop's and the sustain's points are
# numbered by bytes: one past the 12th is a read past the points.
def envelope.ticked(kind: U32, +envelope: Xm.Envelope, +sustained: Bool, +counter: U32, +value: F32) -> Ticked:
  match kind:
    case 0: Ticked{counter, value, True{}}
    case 1: envelope.one(envelope, counter)
    case _: envelope.many(envelope, sustained, counter, value)

def Envelope.count(envelope: Xm.Envelope) -> U32:
  Xm.Envelope{_, count, _, _, _, _, _, _} = envelope
  count

def envelope.tick(+envelope: Xm.Envelope, +sustained: Bool, +counter: U32, +value: F32) -> Ticked:
  envelope.ticked(U32.min(Envelope.count(envelope), 2), envelope, sustained, counter, value)
