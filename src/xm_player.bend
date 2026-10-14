# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_xm (Joshua Reisenauer's port of libxm by
# Romain "Artefact2" Dalmaso; WTFPL), as raylib 6.0 vendors it in
# src/external/jar_xm.h: the player's rows and ticks (jar_xm_row,
# jar_xm_tick, jar_xm_handle_note_and_instrument, jar_xm_trigger_note, the
# effects and the envelopes of a channel), jar_xm_reset and
# jar_xm_get_remaining_samples. See THIRD_PARTY_NOTICES.md and
# LICENSES/jar_xm.txt.
#
# C ints are U32 two's-complement words. A player whose `why` is not 0 has
# met what C leaves undefined (1: a read or a write outside an array or
# jar_xm's block of memory, a null pointer, a float that is no int) or what
# the libm profile does not give (5), a song that does not come to a row
# again (2) or a count past this port's limits (4), and plays no further.
import Base
import ../jonmath.bend as M
import ./xm_module.bend as Xm
import ./xm_pitch.bend as P
import ./xm_sample.bend as Sm
import ./store.bend as R

# -----------------------------------------------------------------------------
# A channel

# The note as played and as read, the period and frequency, and the period
# a tone portamento slides to.
type Pitch is Data:
  Pitch{note: F32, orig: F32, period: F32, frequency: F32, target: F32}

# The volume and panning, whether the note is held, the fadeout and the two
# envelopes' values and frame counts, the tremolo's volume, the tremor, and
# the volume and panning the mixer ramps to and is at.
type Level is Data:
  Level{volume: F32, panning: F32, sustained: Bool, fadeout: F32, envelope: F32, spread: F32, volume_frames: U32, panning_frames: U32, tremolo: F32, tremor: Bool, target_panning: F32, target_volume: F32,
    actual_panning: F32, actual_volume: F32}

# The instrument's vibrato, the arpeggio, and the vibrato and tremolo
# effects: ticks, note offsets, waveforms and parameters.
type Wobble is Data:
  Wobble{auto_ticks: U32, auto_offset: F32, arp: Bool, arp_offset: U32, vibrating: Bool, vibrato_wave: U32, vibrato_again: Bool, vibrato_param: U32, vibrato_ticks: U32, vibrato_offset: F32, tremolo_wave: U32,
    tremolo_again: Bool, tremolo_param: U32, tremolo_ticks: U32}

# The effects' parameters a channel remembers.
type Memo is Data:
  Memo{volume_slide: U32, fine_volume_slide: U32, global_slide: U32, panning_slide: U32, porta_up: U32, porta_down: U32, fine_up: U32, fine_down: U32, extra_up: U32, extra_down: U32, tone: U32, retrig: U32,
    delay: U32, loop_origin: U32, loop_count: U32, tremor: U32}

# A channel: its instrument (0 for none, else its number), its sample (the
# number of the instrument that has it, 0 for none, and its place there),
# the slot it plays, and its parts.
type Channel is Data:
  Channel{instrument: U32, owner: U32, sample: U32, slot: Xm.Slot, head: Sm.Head, pitch: Pitch, level: Level, wobble: Wobble, memo: Memo}

def Channel.instrument(channel: Channel) -> U32:
  Channel{instrument, _, _, _, _, _, _, _, _} = channel
  instrument

def Channel.owner(channel: Channel) -> U32:
  Channel{_, owner, _, _, _, _, _, _, _} = channel
  owner

def Channel.sample(channel: Channel) -> U32:
  Channel{_, _, sample, _, _, _, _, _, _} = channel
  sample

def Channel.slot(channel: Channel) -> Xm.Slot:
  Channel{_, _, _, slot, _, _, _, _, _} = channel
  slot

def Channel.head(channel: Channel) -> Sm.Head:
  Channel{_, _, _, _, head, _, _, _, _} = channel
  head

def Channel.pitch(channel: Channel) -> Pitch:
  Channel{_, _, _, _, _, pitch, _, _, _} = channel
  pitch

def Channel.level(channel: Channel) -> Level:
  Channel{_, _, _, _, _, _, level, _, _} = channel
  level

def Channel.wobble(channel: Channel) -> Wobble:
  Channel{_, _, _, _, _, _, _, wobble, _} = channel
  wobble

def Channel.memo(channel: Channel) -> Memo:
  Channel{_, _, _, _, _, _, _, _, memo} = channel
  memo

def with.slot(channel: Channel, +slot: Xm.Slot) -> Channel:
  Channel{instrument, owner, sample, _, head, pitch, level, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.head(channel: Channel, +head: Sm.Head) -> Channel:
  Channel{instrument, owner, sample, slot, _, pitch, level, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.pitch(channel: Channel, +pitch: Pitch) -> Channel:
  Channel{instrument, owner, sample, slot, head, _, level, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.level(channel: Channel, +level: Level) -> Channel:
  Channel{instrument, owner, sample, slot, head, pitch, _, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.wobble(channel: Channel, +wobble: Wobble) -> Channel:
  Channel{instrument, owner, sample, slot, head, pitch, level, _, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.memo(channel: Channel, +memo: Memo) -> Channel:
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, _} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.instrument(channel: Channel, +instrument: U32) -> Channel:
  Channel{_, owner, sample, slot, head, pitch, level, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def with.sample(channel: Channel, +owner: U32, +sample: U32) -> Channel:
  Channel{instrument, _, _, slot, head, pitch, level, wobble, memo} = channel
  Channel{instrument, owner, sample, slot, head, pitch, level, wobble, memo}

def Slot.note(slot: Xm.Slot) -> U32:
  Xm.Slot{note, _, _, _, _} = slot
  note

def Slot.instrument(slot: Xm.Slot) -> U32:
  Xm.Slot{_, instrument, _, _, _} = slot
  instrument

def Slot.volume(slot: Xm.Slot) -> U32:
  Xm.Slot{_, _, volume, _, _} = slot
  volume

def Slot.effect(slot: Xm.Slot) -> U32:
  Xm.Slot{_, _, _, effect, _} = slot
  effect

def Slot.param(slot: Xm.Slot) -> U32:
  Xm.Slot{_, _, _, _, param} = slot
  param

# A channel as jar_xm_create_context_safe leaves it.
def channel.new() -> Channel:
  Channel{0, 0, 0, Xm.Slot{0, 0, 0, 0, 0}, Sm.Head{0.0, 0.0, 0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, 0.0}, Pitch{0.0, 0.0, 0.0, 0.0, 0.0},
    Level{1.0, 0.5, False{}, 1.0, 1.0, 0.5, 0, 0, 0.0, False{}, 0.0, 0.0, 0.5, 0.0}, Wobble{0, 0.0, False{}, 0, False{}, 0, True{}, 0, 0, 0.0, 0, True{}, 0, 0}, Memo{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}}

# -----------------------------------------------------------------------------
# The song around a channel

# What a row's or a tick's channels read of the player and do not change:
# the libm profile, the module, the device's rate, where the player is (the
# order's entry, the row and the tick), and each instrument's samples as
# the per-sample step reads them.
type Around is Data:
  Around{libm: M.Libm, module: Xm.Module, rate: U32, index: U32, row: U32, tick: U32, tones: +List<+List<Sm.Tone>>}

# ... and what they can change: the tempo and the BPM, the global volume,
# the position jump and the pattern break with their destinations, the
# extra ticks of a pattern delay, the random waveform's state, and why the
# player stops (0: it does not).
type Song is Data:
  Song{tempo: U32, bpm: U32, global: F32, jumping: Bool, breaking: Bool, jump_dest: U32, jump_row: U32, extra: U32, random: U32, why: U32}

# A channel and the song after something is done to the channel.
type Turn is Data:
  Turn{channel: Channel, song: Song}

def Turn.channel(turn: Turn) -> Channel:
  Turn{channel, _} = turn
  channel

def Turn.song(turn: Turn) -> Song:
  Turn{_, song} = turn
  song

def Song.why(song: Song) -> U32:
  Song{_, _, _, _, _, _, _, _, _, why} = song
  why

def Song.random(song: Song) -> U32:
  Song{_, _, _, _, _, _, _, _, random, _} = song
  random

def Song.tempo(song: Song) -> U32:
  Song{tempo, _, _, _, _, _, _, _, _, _} = song
  tempo

# The song stopped for a reason, unless it already is for another.
def stopped(song: Song, +reason: U32) -> Song:
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, +why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, Bool.pick(U32, U32.is_eq(why, 0), reason, why)}

def with.random(song: Song, +random: U32) -> Song:
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, _, why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, why}

def Around.libm(around: Around) -> M.Libm:
  Around{libm, _, _, _, _, _, _} = around
  libm

def Around.module(around: Around) -> Xm.Module:
  Around{_, module, _, _, _, _, _} = around
  module

def Around.rate(around: Around) -> U32:
  Around{_, _, rate, _, _, _, _} = around
  rate

def Around.index(around: Around) -> U32:
  Around{_, _, _, index, _, _, _} = around
  index

def Around.row(around: Around) -> U32:
  Around{_, _, _, _, row, _, _} = around
  row

def Around.tick(around: Around) -> U32:
  Around{_, _, _, _, _, tick, _} = around
  tick

def Around.tones(around: Around) -> +List<+List<Sm.Tone>>:
  Around{_, _, _, _, _, _, tones} = around
  tones

def Module.frequency(module: Xm.Module) -> U32:
  Xm.Module{_, _, _, frequency, _, _, _, _, _, _} = module
  frequency

def Module.instruments(module: Xm.Module) -> +List<Xm.Instrument>:
  Xm.Module{_, _, _, _, _, _, _, _, instruments, _} = module
  instruments

def Module.length(module: Xm.Module) -> U32:
  Xm.Module{length, _, _, _, _, _, _, _, _, _} = module
  length

# The module's frequency type: 0 linear, 1 Amiga.
def kind.of(+around: Around) -> U32:
  Module.frequency(Around.module(around))

def instrument.first(instruments: +List<Xm.Instrument>) -> Xm.Instrument:
  match instruments:
    case Nil{}: Xm.instrument.none()
    case Con{+instrument, _}: instrument

# The instrument of a number from 1 on.
def instrument.at(+module: Xm.Module, +number: U32) -> Xm.Instrument:
  instrument.first(List.drop(&2, Xm.Instrument, Module.instruments(module), U32.to_nat((number - 1 : U32))))

def Instrument.samples(instrument: Xm.Instrument) -> +List<Xm.Sample>:
  Xm.Instrument{_, _, _, _, _, _, _, _, samples} = instrument
  samples

def Instrument.notes(instrument: Xm.Instrument) -> +List<U32>:
  Xm.Instrument{notes, _, _, _, _, _, _, _, _} = instrument
  notes

def Instrument.volume(instrument: Xm.Instrument) -> Xm.Envelope:
  Xm.Instrument{_, volume, _, _, _, _, _, _, _} = instrument
  volume

def Instrument.panning(instrument: Xm.Instrument) -> Xm.Envelope:
  Xm.Instrument{_, _, panning, _, _, _, _, _, _} = instrument
  panning

def Instrument.fadeout(instrument: Xm.Instrument) -> U32:
  Xm.Instrument{_, _, _, _, _, _, _, fadeout, _} = instrument
  fadeout

def Envelope.enabled(envelope: Xm.Envelope) -> Bool:
  Xm.Envelope{_, _, _, _, _, enabled, _, _} = envelope
  enabled

def sample.first(samples: +List<Xm.Sample>) -> Xm.Sample:
  match samples:
    case Nil{}: Xm.Sample{8, 0, 0, 0, 0, 0, 0.0, 0, 0, 0.0, 0, Nil{}}
    case Con{+sample, _}: sample

def counted.samples(samples: +List<Xm.Sample>, +n: U32) -> U32:
  match samples:
    case Nil{}: n
    case Con{_, +rest}: counted.samples(rest, (n + 1 : U32))

# A channel's sample: the one at its place in the instrument that has it.
def sample.of(+module: Xm.Module, +channel: Channel) -> Xm.Sample:
  sample.first(List.drop(&2, Xm.Sample, Instrument.samples(instrument.at(module, Channel.owner(channel))), U32.to_nat(Channel.sample(channel))))

def Sample.volume(sample: Xm.Sample) -> F32:
  Xm.Sample{_, _, _, _, _, _, volume, _, _, _, _, _} = sample
  volume

def Sample.panning(sample: Xm.Sample) -> F32:
  Xm.Sample{_, _, _, _, _, _, _, _, _, panning, _, _} = sample
  panning

def Sample.finetune(sample: Xm.Sample) -> U32:
  Xm.Sample{_, _, _, _, _, _, _, finetune, _, _, _, _} = sample
  finetune

def Sample.relative(sample: Xm.Sample) -> U32:
  Xm.Sample{_, _, _, _, _, _, _, _, _, _, relative, _} = sample
  relative

# jar_xm_CLAMP_DOWN: a value below 0 is 0 (one that is not a number stays).
def floored(+x: F32) -> F32:
  Bool.pick(F32, (x < 0.0 : F32), 0.0, x)

# jar_xm_CLAMP_UP: a value above 1 is 1.
def capped(+x: F32) -> F32:
  Bool.pick(F32, (x > 1.0 : F32), 1.0, x)

# An int of a small range as a float.
def float.of(+a: U32) -> F32:
  Bool.pick(F32, (a >= 2147483648 : U32), (U32.to_f32((0 - a : U32)) * (0.0 - 1.0 : F32) : F32), U32.to_f32(a))

# -----------------------------------------------------------------------------
# The frequency

def Pitch.period(pitch: Pitch) -> F32:
  Pitch{_, _, period, _, _} = pitch
  period

def Pitch.note(pitch: Pitch) -> F32:
  Pitch{note, _, _, _, _} = pitch
  note

def Wobble.arp_offset(wobble: Wobble) -> U32:
  Wobble{_, _, _, arp_offset, _, _, _, _, _, _, _, _, _, _} = wobble
  arp_offset

def Wobble.offsets(wobble: Wobble) -> F32:
  Wobble{_, +auto_offset, _, _, _, _, _, _, _, +vibrato_offset, _, _, _, _} = wobble
  (vibrato_offset + auto_offset : F32)

def head.stepped(head: Sm.Head, +step: F32) -> Sm.Head:
  Sm.Head{position, _, frames, lefts, rights, left, right} = head
  Sm.Head{position, step, frames, lefts, rights, left, right}

def pitch.frequent(pitch: Pitch, +frequency: F32) -> Pitch:
  Pitch{note, orig, period, _, target} = pitch
  Pitch{note, orig, period, frequency, target}

def frequency.set(frequency: Maybe<F32>, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match frequency:
    case None{}: Turn{channel, stopped(song, Bool.pick(U32, U32.is_eq(kind.of(around), 0), 5, 1))}
    case Some{+f}: Turn{with.head(with.pitch(channel, pitch.frequent(Channel.pitch(channel), f)), head.stepped(Channel.head(channel), (f / U32.to_f32(Around.rate(around)) : F32))), song}

# jar_xm_update_frequency: the frequency of the channel's period, an
# arpeggio's note offset or the vibratos' away, and the sample's step a
# frame at the device's rate.
def frequency.update(+around: Around, +channel: Channel, +song: Song) -> Turn:
  frequency.set(P.frequency.of(Around.libm(around), kind.of(around), Pitch.period(Channel.pitch(channel)),
    Bool.pick(F32, (Wobble.arp_offset(Channel.wobble(channel)) > 0 : U32), U32.to_f32(Wobble.arp_offset(Channel.wobble(channel))), Wobble.offsets(Channel.wobble(channel)))), around, channel, song)

def turn.updated(+around: Around, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  frequency.update(around, channel, song)

# -----------------------------------------------------------------------------
# Notes

def level.cut(level: Level) -> Level:
  Level{_, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{0.0, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

# jar_xm_cut_note: the volume is 0.
def note.cut(+channel: Channel) -> Channel:
  with.level(channel, level.cut(Channel.level(channel)))

def level.released(level: Level, +cut: Bool) -> Level:
  Level{+volume, panning, _, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{Bool.pick(F32, cut, 0.0, volume), panning, False{}, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

# jar_xm_key_off: the note is no longer held, and is cut where there is no
# volume envelope to let it fade.
def note.released(+around: Around, +channel: Channel) -> Channel:
  with.level(channel, level.released(Channel.level(channel), U32.is_eq(Channel.instrument(channel), 0) || Bool.not(Envelope.enabled(Instrument.volume(instrument.at(Around.module(around), Channel.instrument(channel)))))))

# The flags of jar_xm_trigger_note: 1 keep the volume, 2 keep the period,
# 4 keep the sample's position.
def level.triggered(level: Level, +volume: F32, +panning: F32) -> Level:
  Level{_, _, _, _, _, _, _, _, _, _, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, True{}, 1.0, 1.0, 0.5, 0, 0, 0.0, False{}, target_panning, target_volume, actual_panning, actual_volume}

def Level.volume(level: Level) -> F32:
  Level{volume, _, _, _, _, _, _, _, _, _, _, _, _, _} = level
  volume

def wobble.triggered(wobble: Wobble) -> Wobble:
  Wobble{_, auto_offset, arp, arp_offset, vibrating, vibrato_wave, +vibrato_again, vibrato_param, +vibrato_ticks, _, tremolo_wave, +tremolo_again, tremolo_param, +tremolo_ticks} = wobble
  Wobble{0, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, Bool.pick(U32, vibrato_again, 0, vibrato_ticks), 0.0, tremolo_wave, tremolo_again, tremolo_param,
    Bool.pick(U32, tremolo_again, 0, tremolo_ticks)}

def head.rewound(head: Sm.Head) -> Sm.Head:
  Sm.Head{_, step, frames, lefts, rights, left, right} = head
  Sm.Head{0.0, step, frames, lefts, rights, left, right}

def pitch.perioded(pitch: Pitch, +period: F32) -> Pitch:
  Pitch{note, orig, _, frequency, target} = pitch
  Pitch{note, orig, period, frequency, target}

def period.set(period: Maybe<F32>, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match period:
    case None{}: Turn{channel, stopped(song, 1)}
    case Some{+p}: frequency.update(around, with.pitch(channel, pitch.perioded(Channel.pitch(channel), p)), song)

# The channel's period from its note, and its frequency.
def period.update(+around: Around, +channel: Channel, +song: Song) -> Turn:
  period.set(P.period.of(kind.of(around), Pitch.note(Channel.pitch(channel))), around, channel, song)

def trigger.pitched(keep: Bool, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match keep:
    case True{}: Turn{channel, song}
    case False{}: period.update(around, channel, song)

# With a sample: the position at 0 unless kept, the sample's volume unless
# the volume is kept, the sample's panning, the envelopes and the vibrato
# and tremolo begun again, and the period of the note unless kept.
def trigger.sampled(+around: Around, +channel: Channel, +song: Song, +flags: U32, +sample: Xm.Sample) -> Turn:
  trigger.pitched(U32.is_ne((flags .&. 2 : U32), 0), around,
    with.wobble(with.level(with.head(channel, Bool.pick(Sm.Head, U32.is_ne((flags .&. 4 : U32), 0), Channel.head(channel), head.rewound(Channel.head(channel)))),
      level.triggered(Channel.level(channel), Bool.pick(F32, U32.is_ne((flags .&. 1 : U32), 0), Level.volume(Channel.level(channel)), Sample.volume(sample)), Sample.panning(sample))), wobble.triggered(Channel.wobble(channel))), song)

# jar_xm_trigger_note(ctx, ch, flags). jar_xm reads the sample's panning
# whether the channel has a sample or not: without one it reads through a
# null pointer.
def note.triggered(sampled: Bool, +around: Around, +channel: Channel, +song: Song, +flags: U32) -> Turn:
  match sampled:
    case False{}: Turn{channel, stopped(song, 1)}
    case True{}: trigger.sampled(around, channel, song, flags, sample.of(Around.module(around), channel))

def note.trigger(+around: Around, +channel: Channel, +song: Song, +flags: U32) -> Turn:
  note.triggered(U32.is_ne(Channel.owner(channel), 0), around, channel, song, flags)

# -----------------------------------------------------------------------------
# Envelopes

def level.faded(level: Level, +fadeout: U32) -> Level:
  Level{volume, panning, +sustained, +faded, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, sustained, Bool.pick(F32, sustained, faded, floored((faded - (U32.to_f32(fadeout) / 65536.0) : F32))), envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume,
    actual_panning, actual_volume}

def Level.sustained(level: Level) -> Bool:
  Level{_, _, sustained, _, _, _, _, _, _, _, _, _, _, _} = level
  sustained

def Level.envelope(level: Level) -> F32:
  Level{_, _, _, _, envelope, _, _, _, _, _, _, _, _, _} = level
  envelope

def Level.spread(level: Level) -> F32:
  Level{_, _, _, _, _, spread, _, _, _, _, _, _, _, _} = level
  spread

def Level.volume_frames(level: Level) -> U32:
  Level{_, _, _, _, _, _, volume_frames, _, _, _, _, _, _, _} = level
  volume_frames

def Level.panning_frames(level: Level) -> U32:
  Level{_, _, _, _, _, _, _, panning_frames, _, _, _, _, _, _} = level
  panning_frames

def level.volumed(level: Level, ticked: P.Ticked) -> Level:
  Level{volume, panning, sustained, fadeout, _, spread, _, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  P.Ticked{counter, value, _} = ticked
  Level{volume, panning, sustained, fadeout, value, spread, counter, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

def level.panned(level: Level, ticked: P.Ticked) -> Level:
  Level{volume, panning, sustained, fadeout, envelope, _, volume_frames, _, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  P.Ticked{counter, value, _} = ticked
  Level{volume, panning, sustained, fadeout, envelope, value, volume_frames, counter, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

def Ticked.fine(ticked: P.Ticked) -> Bool:
  P.Ticked{_, _, fine} = ticked
  fine

# The volume envelope's tick, where it is enabled: a note no longer held
# fades by the instrument's fadeout first.
def envelope.volume(enabled: Bool, +instrument: Xm.Instrument, +level: Level) -> Level:
  match enabled:
    case False{}: level
    case True{}: level.volumed(level.faded(level, Instrument.fadeout(instrument)), P.envelope.tick(Instrument.volume(instrument), Level.sustained(level), Level.volume_frames(level), Level.envelope(level)))

def envelope.panning(enabled: Bool, +instrument: Xm.Instrument, +level: Level) -> Level:
  match enabled:
    case False{}: level
    case True{}: level.panned(level, P.envelope.tick(Instrument.panning(instrument), Level.sustained(level), Level.panning_frames(level), Level.spread(level)))

# Whether both envelopes' ticks read only their own points.
def envelope.fine(+instrument: Xm.Instrument, +level: Level) -> Bool:
  (Bool.not(Envelope.enabled(Instrument.volume(instrument))) || Ticked.fine(P.envelope.tick(Instrument.volume(instrument), Level.sustained(level), Level.volume_frames(level), Level.envelope(level))))
    && (Bool.not(Envelope.enabled(Instrument.panning(instrument))) || Ticked.fine(P.envelope.tick(Instrument.panning(instrument), Level.sustained(level), Level.panning_frames(level), Level.spread(level))))

def envelopes.of(some: Bool, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match some:
    case False{}: Turn{channel, song}
    case True{}:
      +instrument = instrument.at(Around.module(around), Channel.instrument(channel))
      Turn{with.level(channel, envelope.panning(Envelope.enabled(Instrument.panning(instrument)), instrument, envelope.volume(Envelope.enabled(Instrument.volume(instrument)), instrument, Channel.level(channel)))),
        Bool.pick(Song, envelope.fine(instrument, Channel.level(channel)), song, stopped(song, 1))}

# jar_xm_envelopes: the two envelopes of the channel's instrument.
def envelopes(+around: Around, +channel: Channel, +song: Song) -> Turn:
  envelopes.of(U32.is_ne(Channel.instrument(channel), 0), around, channel, song)

# -----------------------------------------------------------------------------
# Vibratos, tremolo, arpeggio and slides

def Wave.value(wave: P.Wave) -> F32:
  P.Wave{value, _, _} = wave
  value

def Wave.fine(wave: P.Wave) -> Bool:
  P.Wave{_, fine, _} = wave
  fine

def Wave.random(wave: P.Wave) -> U32:
  P.Wave{_, _, random} = wave
  random

# The song after a waveform is asked for: the random state moved on, and
# stopped where the libm profile does not give the sine.
def song.waved(+song: Song, wave: P.Wave) -> Song:
  P.Wave{_, +fine, +random} = wave
  Bool.pick(Song, fine, with.random(song, random), stopped(with.random(song, random), 5))

def Instrument.vibrato(instrument: Xm.Instrument) -> U32:
  Xm.Instrument{_, _, _, vibrato_type, _, _, _, _, _} = instrument
  vibrato_type

def Instrument.sweep(instrument: Xm.Instrument) -> U32:
  Xm.Instrument{_, _, _, _, vibrato_sweep, _, _, _, _} = instrument
  vibrato_sweep

def Instrument.depth(instrument: Xm.Instrument) -> U32:
  Xm.Instrument{_, _, _, _, _, vibrato_depth, _, _, _} = instrument
  vibrato_depth

def Instrument.speed(instrument: Xm.Instrument) -> U32:
  Xm.Instrument{_, _, _, _, _, _, vibrato_rate, _, _} = instrument
  vibrato_rate

def Wobble.auto_ticks(wobble: Wobble) -> U32:
  Wobble{auto_ticks, _, _, _, _, _, _, _, _, _, _, _, _, _} = wobble
  auto_ticks

def wobble.auto(wobble: Wobble, +offset: F32) -> Wobble:
  Wobble{+auto_ticks, _, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{((auto_ticks + 1) .&. 65535 : U32), offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks}

# The instrument's vibrato, swept in over its first ticks.
def autovibrato.waved(+wave: P.Wave, +around: Around, +channel: Channel, +song: Song, +instrument: Xm.Instrument) -> Turn:
  +ticks = Wobble.auto_ticks(Channel.wobble(channel))
  +sweep = Bool.pick(F32, (ticks < Instrument.sweep(instrument) : U32), (U32.to_f32(ticks) / U32.to_f32(Instrument.sweep(instrument)) : F32), 1.0)
  frequency.update(around, with.wobble(channel, wobble.auto(Channel.wobble(channel), ((((0.25 * Wave.value(wave)) * U32.to_f32(Instrument.depth(instrument))) / 15.0) * sweep : F32))), song.waved(song, wave))

def autovibrato.of(some: Bool, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match some:
    case False{}: Turn{channel, song}
    case True{}:
      +instrument = instrument.at(Around.module(around), Channel.instrument(channel))
      autovibrato.waved(P.waveform(Instrument.vibrato(instrument), Around.libm(around), ((Wobble.auto_ticks(Channel.wobble(channel)) * Instrument.speed(instrument)) >> 2n : U32), Song.random(song)), around, channel, song, instrument)

# jar_xm_autovibrato.
def autovibrato(+around: Around, +channel: Channel, +song: Song) -> Turn:
  autovibrato.of(U32.is_ne(Channel.instrument(channel), 0) && U32.is_ne(Instrument.depth(instrument.at(Around.module(around), Channel.instrument(channel))), 0), around, channel, song)

def Wobble.vibrato_wave(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, vibrato_wave, _, _, _, _, _, _, _, _} = wobble
  vibrato_wave

def Wobble.vibrato_param(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, vibrato_param, _, _, _, _, _, _} = wobble
  vibrato_param

def Wobble.vibrato_ticks(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, _, vibrato_ticks, _, _, _, _, _} = wobble
  vibrato_ticks

# The vibrato's offset set, its ticks moved on, and whether it is the
# effect's (`vibrating`) or the volume column's.
def wobble.vibrated(wobble: Wobble, +offset: F32, +vibrating: Bool) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, _, vibrato_wave, vibrato_again, vibrato_param, +vibrato_ticks, _, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, ((vibrato_ticks + 1) .&. 65535 : U32), offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks}

def vibrato.waved(+wave: P.Wave, +around: Around, +channel: Channel, +song: Song, +vibrating: Bool) -> Turn:
  frequency.update(around, with.wobble(channel, wobble.vibrated(Channel.wobble(channel), (((2.0 * Wave.value(wave)) * U32.to_f32((Wobble.vibrato_param(Channel.wobble(channel)) .&. 15 : U32))) / 15.0 : F32), vibrating)), song.waved(song, wave))

# jar_xm_vibrato(ctx, ch, ch->vibrato_param, ch->vibrato_ticks++).
def vibrato(+around: Around, +channel: Channel, +song: Song, +vibrating: Bool) -> Turn:
  vibrato.waved(P.waveform(Wobble.vibrato_wave(Channel.wobble(channel)), Around.libm(around), (Wobble.vibrato_ticks(Channel.wobble(channel)) * (Wobble.vibrato_param(Channel.wobble(channel)) >> 4n) : U32), Song.random(song)), around, channel, song,
    vibrating)

def wobble.tremoloed(wobble: Wobble) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, +tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, ((tremolo_ticks + 1) .&. 255 : U32)}

def level.tremolo(level: Level, +tremolo: F32) -> Level:
  Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, _, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

def Wobble.tremolo_wave(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, _, _, _, tremolo_wave, _, _, _} = wobble
  tremolo_wave

def Wobble.tremolo_ticks(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, _, _, _, _, _, _, tremolo_ticks} = wobble
  tremolo_ticks

def Wobble.tremolo_speed(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, _, _, _, _, _, tremolo_param, _} = wobble
  tremolo_param

def tremolo.waved(+wave: P.Wave, +channel: Channel, +song: Song, +param: U32) -> Turn:
  Turn{with.wobble(with.level(channel, level.tremolo(Channel.level(channel), ((((0.0 - 1.0 : F32) * Wave.value(wave)) * U32.to_f32((param .&. 15 : U32))) / 15.0 : F32))), wobble.tremoloed(Channel.wobble(channel))), song.waved(song, wave)}

# jar_xm_tremolo(ctx, ch, ch->tremolo_param, ch->tremolo_ticks++).
def tremolo(+around: Around, +channel: Channel, +song: Song) -> Turn:
  tremolo.waved(P.waveform(Wobble.tremolo_wave(Channel.wobble(channel)), Around.libm(around), (Wobble.tremolo_ticks(Channel.wobble(channel)) * (Wobble.tremolo_speed(Channel.wobble(channel)) >> 4n) : U32), Song.random(song)), channel, song,
    Wobble.tremolo_speed(Channel.wobble(channel)))

def wobble.arped(wobble: Wobble, +arp: Bool, +offset: U32) -> Wobble:
  Wobble{auto_ticks, auto_offset, _, _, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, offset, vibrating, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks}

# The arpeggio's note offset set (or the arpeggio ended), and the frequency.
def arpeggio.set(+around: Around, +channel: Channel, +song: Song, +arp: Bool, +offset: U32) -> Turn:
  frequency.update(around, with.wobble(channel, wobble.arped(Channel.wobble(channel), arp, offset)), song)

# jar_xm_arpeggio(ctx, ch, param, tick): `tick` is a 16-bit int.
def arpeggio(+around: Around, +channel: Channel, +song: Song, +param: U32, +tick: U32) -> Turn:
  arpeggio.set(around, channel, song, U32.is_ne(((tick .&. 65535) % 3 : U32), 0), Bool.pick(U32, U32.is_eq(((tick .&. 65535) % 3 : U32), 0), 0, Bool.pick(U32, U32.is_eq(((tick .&. 65535) % 3 : U32), 2), (param >> 4n : U32), (param .&. 15 : U32))))

# jar_xm_SLIDE_TOWARDS(val, goal, incr).
def slid(+value: F32, +goal: F32, +by: F32) -> F32:
  Bool.pick(F32, (value > goal : F32), Bool.pick(F32, ((value - by : F32) < goal : F32), goal, (value - by : F32)), Bool.pick(F32, (value < goal : F32), Bool.pick(F32, ((value + by : F32) > goal : F32), goal, (value + by : F32)), value))

def Pitch.target(pitch: Pitch) -> F32:
  Pitch{_, _, _, _, target} = pitch
  target

def Memo.tone(memo: Memo) -> U32:
  Memo{_, _, _, _, _, _, _, _, _, _, tone, _, _, _, _, _} = memo
  tone

def portamento.slid(sliding: Bool, +around: Around, +channel: Channel, +song: Song) -> Turn:
  match sliding:
    case False{}: Turn{channel, song}
    case True{}: frequency.update(around, with.pitch(channel, pitch.perioded(Channel.pitch(channel), slid(Pitch.period(Channel.pitch(channel)), Pitch.target(Channel.pitch(channel)),
      (Bool.pick(F32, U32.is_eq(kind.of(around), 0), 4.0, 1.0) * U32.to_f32(Memo.tone(Channel.memo(channel))) : F32)))), song)

# jar_xm_tone_portamento: the period slides to the target's, where there is
# one and it is not there yet.
def portamento(+around: Around, +channel: Channel, +song: Song) -> Turn:
  portamento.slid(Bool.not(F32.is_eq(Pitch.target(Channel.pitch(channel)), 0.0)) && Bool.not(F32.is_eq(Pitch.period(Channel.pitch(channel)), Pitch.target(Channel.pitch(channel)))), around, channel, song)

# jar_xm_pitch_slide(ctx, ch, offset): four times the offset with linear
# frequencies; the period does not go below 0.
def pitch.slide(+around: Around, +channel: Channel, +song: Song, +offset: F32) -> Turn:
  frequency.update(around, with.pitch(channel, pitch.perioded(Channel.pitch(channel), floored((Pitch.period(Channel.pitch(channel)) + Bool.pick(F32, U32.is_eq(kind.of(around), 0), (offset * 4.0 : F32), offset) : F32)))), song)

def level.slid(level: Level, +volume: F32, +panning: F32) -> Level:
  Level{_, _, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

def Level.panning(level: Level) -> F32:
  Level{_, panning, _, _, _, _, _, _, _, _, _, _, _, _} = level
  panning

# A slide's value: up by the raw byte's high four bits over `scale`, then
# down by its low four.
def sliding(+value: F32, +raw: U32, +scale: F32) -> F32:
  +up = Bool.pick(F32, U32.is_ne((raw .&. 240 : U32), 0), (value + (U32.to_f32(((raw .&. 240) >> 4n : U32)) / scale) : F32), value)
  Bool.pick(F32, U32.is_ne((raw .&. 15 : U32), 0), (up - (U32.to_f32((raw .&. 15 : U32)) / scale) : F32), up)

# jar_xm_volume_slide(ch, rawval) and jar_xm_panning_slide(ch, rawval):
# `raw` is a byte.
def volume.slide(+channel: Channel, +raw: U32) -> Channel:
  with.level(channel, level.slid(Channel.level(channel), sliding(Level.volume(Channel.level(channel)), (raw .&. 255 : U32), 64.0), Level.panning(Channel.level(channel))))

def panning.slide(+channel: Channel, +raw: U32) -> Channel:
  with.level(channel, level.slid(Channel.level(channel), Level.volume(Channel.level(channel)), sliding(Level.panning(Channel.level(channel)), (raw .&. 255 : U32), 255.0)))

# -----------------------------------------------------------------------------
# A slot's note and instrument

def tones.first(tones: +List<+List<Sm.Tone>>) -> +List<Sm.Tone>:
  match tones:
    case Nil{}: Nil{}
    case Con{+first, _}: first

def tone.first(tones: +List<Sm.Tone>) -> Sm.Tone:
  match tones:
    case Nil{}: Sm.Tone{0, 0, 0, 0, False{}, False{}, R.Row.new(0, 0.0), 0}
    case Con{+tone, _}: tone

# A channel's sample as the per-sample step reads it.
def tone.of(+around: Around, +channel: Channel) -> Sm.Tone:
  tone.first(List.drop(&2, Sm.Tone, tones.first(List.drop(&2, +List<Sm.Tone>, Around.tones(around), U32.to_nat((Channel.owner(channel) - 1 : U32)))), U32.to_nat(Channel.sample(channel))))

# HAS_TONE_PORTAMENTO: the effect 3 or 5, or F in the volume column.
def portamento.has(+slot: Xm.Slot) -> Bool:
  U32.is_eq(Slot.effect(slot), 3) || U32.is_eq(Slot.effect(slot), 5) || U32.is_eq((Slot.volume(slot) >> 4n : U32), 15)

def counted.instruments(instruments: +List<Xm.Instrument>, +n: U32) -> U32:
  match instruments:
    case Nil{}: n
    case Con{_, +rest}: counted.instruments(rest, (n + 1 : U32))

def Module.count(module: Xm.Module) -> U32:
  counted.instruments(Module.instruments(module), 0)

# The slot's instrument: with a tone portamento on a channel that has an
# instrument and a sample the note begins again (its period and position
# kept); a number past the module's instruments cuts the note and leaves
# the channel without instrument and sample; otherwise it is the channel's
# instrument, and without a note the sample's envelopes begin again.
def instrument.slot(kind: U32, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match kind:
    case 0: Turn{channel, song}
    case 1: note.trigger(around, channel, song, 6)
    case 2: Turn{with.sample(with.instrument(note.cut(channel), 0), 0, 0), song}
    case 3: note.trigger(around, with.instrument(channel, Slot.instrument(slot)), song, 4)
    case _: Turn{with.instrument(channel, Slot.instrument(slot)), song}

def slot.instrumented(+around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  instrument.slot(Bool.pick(U32, U32.is_eq(Slot.instrument(slot), 0), 0,
    Bool.pick(U32, portamento.has(Channel.slot(channel)) && U32.is_ne(Channel.instrument(channel), 0) && U32.is_ne(Channel.owner(channel), 0), 1,
      Bool.pick(U32, (Slot.instrument(slot) > Module.count(Around.module(around)) : U32), 2, Bool.pick(U32, U32.is_eq(Slot.note(slot), 0) && U32.is_ne(Channel.owner(channel), 0), 3, 4)))), around, channel, song, slot)

# The note of a slot's note on the channel's sample: the note, the sample's
# relative note and its finetune over 128, less 1.
def note.of(+note: U32, +sample: Xm.Sample) -> F32:
  ((float.of((note + Sample.relative(sample) : U32)) + (float.of(Sample.finetune(sample)) / 128.0)) - 1.0 : F32)

def pitch.noted(pitch: Pitch, +note: F32, +both: Bool) -> Pitch:
  Pitch{_, +orig, period, frequency, target} = pitch
  Pitch{note, Bool.pick(F32, both, note, orig), period, frequency, target}

def pitch.targeted(pitch: Pitch, +target: F32) -> Pitch:
  Pitch{note, orig, period, frequency, _} = pitch
  Pitch{note, orig, period, frequency, target}

def target.set(period: Maybe<F32>, +channel: Channel, +song: Song) -> Turn:
  match period:
    case None{}: Turn{channel, stopped(song, 1)}
    case Some{+p}: Turn{with.pitch(channel, pitch.targeted(Channel.pitch(channel), p)), song}

# A note under a tone portamento: the note and the period to slide to.
def note.target(+around: Around, +channel: Channel, +song: Song, +note: F32) -> Turn:
  target.set(P.period.of(kind.of(around), note), with.pitch(channel, pitch.noted(Channel.pitch(channel), note, False{})), song)

def head.framed(head: Sm.Head) -> Sm.Head:
  Sm.Head{position, step, _, lefts, rights, left, right} = head
  Sm.Head{position, step, 0, lefts, rights, left, right}

def Stepped.head(stepped: Sm.Stepped) -> Sm.Head:
  Sm.Stepped{head, _} = stepped
  head

def Stepped.fine(stepped: Sm.Stepped) -> Bool:
  Sm.Stepped{_, fine} = stepped
  fine

# The eight last values of the sample the channel plays, for the new note's
# ramp (jar_xm_next_of_sample with 0 to 7), and the frame count at 0.
def ramp.kept(n: Nat, on: Bool, +i: U32, +sampled: Bool, +tone: Sm.Tone, +head: Sm.Head) -> Sm.Stepped:
  match n on:
    case _ False{}: Sm.Stepped{head, False{}}
    case 0n True{}: Sm.Stepped{head.framed(head), True{}}
    case 1n+k True{}:
      +next = Sm.sample.next(sampled, tone, head, i)
      ramp.kept(k, Stepped.fine(next), (i + 1 : U32), sampled, tone, Stepped.head(next))

def note.begun(+channel: Channel, +around: Around, +song: Song, +slot: Xm.Slot) -> Turn:
  note.trigger(around, with.pitch(channel, pitch.noted(Channel.pitch(channel), note.of(Slot.note(slot), sample.of(Around.module(around), channel)), True{})), song, Bool.pick(U32, (Slot.instrument(slot) > 0 : U32), 0, 1))

# A new note on a sample of the channel's instrument: the ramp's values,
# the sample, the note, and the note begun (with the sample's volume if the
# slot has an instrument, the channel's own otherwise).
def note.sampled(ramp: Sm.Stepped, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot, +place: U32) -> Turn:
  Sm.Stepped{+head, +fine} = ramp
  note.begun(with.sample(with.head(channel, head), Channel.instrument(channel), place), around, Bool.pick(Song, fine, song, stopped(song, 1)), slot)

def word.first(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  word.first(List.drop(&2, U32, xs, U32.to_nat(i)))

# kind: 0 no note; 1 a note under a tone portamento; 2 a note the channel
# cannot play (no instrument, an instrument without samples, a note whose
# sample the instrument has not): cut; 3 a new note; 4 a key off.
def note.slot(kind: U32, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match kind:
    case 0: Turn{channel, song}
    case 1: note.target(around, channel, song, note.of(Slot.note(slot), sample.of(Around.module(around), channel)))
    case 2: Turn{note.cut(channel), song}
    case 3: note.sampled(ramp.kept(8n, True{}, 0, U32.is_ne(Channel.owner(channel), 0), tone.of(around, channel), Channel.head(channel)), around, channel, song, slot,
      nth(Instrument.notes(instrument.at(Around.module(around), Channel.instrument(channel))), (Slot.note(slot) - 1 : U32)))
    case _: Turn{note.released(around, channel), song}

def note.kind(+around: Around, +channel: Channel, +slot: Xm.Slot) -> U32:
  Bool.pick(U32, U32.is_eq(Slot.note(slot), 97), 4, Bool.pick(U32, U32.is_eq(Slot.note(slot), 0) || (Slot.note(slot) > 96 : U32), 0,
    Bool.pick(U32, portamento.has(Channel.slot(channel)) && U32.is_ne(Channel.instrument(channel), 0) && U32.is_ne(Channel.owner(channel), 0), 1,
      Bool.pick(U32, U32.is_eq(Channel.instrument(channel), 0), 2,
        Bool.pick(U32, (nth(Instrument.notes(instrument.at(Around.module(around), Channel.instrument(channel))), (Slot.note(slot) - 1 : U32)) < counted.samples(Instrument.samples(instrument.at(Around.module(around), Channel.instrument(channel))), 0) : U32), 3, 2)))))

def slot.noted(+around: Around, +slot: Xm.Slot, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  note.slot(note.kind(around, channel, slot), around, channel, song, slot)

# -----------------------------------------------------------------------------
# A slot's effect, as the row begins

# A remembered parameter set: `which` is its place in Memo.
def memo.set(memo: Memo, +which: U32, +value: U32) -> Memo:
  Memo{+a, +b, +c, +d, +e, +f, +g, +h, +i, +j, +k, +l, +m, +n, +o, +p} = memo
  Memo{Bool.pick(U32, U32.is_eq(which, 0), value, a), Bool.pick(U32, U32.is_eq(which, 1), value, b), Bool.pick(U32, U32.is_eq(which, 2), value, c), Bool.pick(U32, U32.is_eq(which, 3), value, d),
    Bool.pick(U32, U32.is_eq(which, 4), value, e), Bool.pick(U32, U32.is_eq(which, 5), value, f), Bool.pick(U32, U32.is_eq(which, 6), value, g), Bool.pick(U32, U32.is_eq(which, 7), value, h),
    Bool.pick(U32, U32.is_eq(which, 8), value, i), Bool.pick(U32, U32.is_eq(which, 9), value, j), Bool.pick(U32, U32.is_eq(which, 10), value, k), Bool.pick(U32, U32.is_eq(which, 11), value, l),
    Bool.pick(U32, U32.is_eq(which, 12), value, m), Bool.pick(U32, U32.is_eq(which, 13), value, n), Bool.pick(U32, U32.is_eq(which, 14), value, o), Bool.pick(U32, U32.is_eq(which, 15), value, p)}

def memo.get(memo: Memo, +which: U32) -> U32:
  Memo{+a, +b, +c, +d, +e, +f, +g, +h, +i, +j, +k, +l, +m, +n, +o, +p} = memo
  nth([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p], which)

# A parameter above 0 remembered.
def remembered(+channel: Channel, +which: U32, +param: U32) -> Channel:
  Bool.pick(Channel, (param > 0 : U32), with.memo(channel, memo.set(Channel.memo(channel), which, param)), channel)

# A speed and a depth in a byte, each replaced by the parameter's if that
# is not 0.
def nibbles(+old: U32, +param: U32) -> U32:
  ((Bool.pick(U32, U32.is_ne((param >> 4n : U32), 0), (param .&. 240 : U32), (old .&. 240 : U32))) .|. (Bool.pick(U32, U32.is_ne((param .&. 15 : U32), 0), (param .&. 15 : U32), (old .&. 15 : U32))) : U32)

def wobble.params(wobble: Wobble, +vibrato: U32, +tremolo: U32) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, _, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, _, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, vibrato, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo, tremolo_ticks}

def Wobble.tremolo_param(wobble: Wobble) -> U32:
  Wobble{_, _, _, _, _, _, _, _, _, _, _, _, tremolo_param, _} = wobble
  tremolo_param

def wobble.waves(wobble: Wobble, +vibrato: Bool, +wave: U32, +again: Bool) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, +vibrato_wave, +vibrato_again, vibrato_param, vibrato_ticks, vibrato_offset, +tremolo_wave, +tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, Bool.pick(U32, vibrato, wave, vibrato_wave), Bool.pick(Bool, vibrato, again, vibrato_again), vibrato_param, vibrato_ticks, vibrato_offset,
    Bool.pick(U32, vibrato, tremolo_wave, wave), Bool.pick(Bool, vibrato, tremolo_again, again), tremolo_param, tremolo_ticks}

def level.frames(level: Level, +frames: U32) -> Level:
  Level{volume, panning, sustained, fadeout, envelope, spread, _, _, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, sustained, fadeout, envelope, spread, frames, frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

def head.at(head: Sm.Head, +position: F32) -> Sm.Head:
  Sm.Head{_, step, frames, lefts, rights, left, right} = head
  Sm.Head{position, step, frames, lefts, rights, left, right}

def Head.position(head: Sm.Head) -> F32:
  Sm.Head{position, _, _, _, _, _, _} = head
  position

# 9xx: the sample's position at 256 times the parameter (128 times for a
# 16-bit sample). Past a sample that does not loop the sample has ended;
# past a loop's end the position goes back by the loop's length, and from
# the sample's length on it is the loop's start.
def offset.position(sample: Xm.Sample, +param: U32, +position: F32) -> F32:
  Xm.Sample{+bits, _, +length, +loop_start, +loop_length, +loop_end, _, _, +loop_type, _, _, _} = sample
  +final = (param << U32.to_nat(Bool.pick(U32, U32.is_eq(bits, 16), 7, 8)) : U32)
  Bool.pick(F32, U32.is_eq(loop_type, 0), Bool.pick(F32, (final >= length : U32), (0.0 - 1.0 : F32), U32.to_f32(final)),
    Bool.pick(F32, (final >= loop_end : U32), (position - U32.to_f32(loop_length) : F32), Bool.pick(F32, (final >= length : U32), U32.to_f32(loop_start), U32.to_f32(final))))

def offset.set(sampled: Bool, +around: Around, +channel: Channel, +param: U32) -> Channel:
  match sampled:
    case False{}: channel
    case True{}: with.head(channel, head.at(Channel.head(channel), offset.position(sample.of(Around.module(around), channel), param, Head.position(Channel.head(channel)))))

def song.jump(song: Song, +jumping: Bool, +dest: U32, +row: U32, +rowed: Bool) -> Song:
  Song{tempo, bpm, global, _, breaking, _, +jump_row, extra, random, why} = song
  Song{tempo, bpm, global, jumping, breaking, dest, Bool.pick(U32, rowed, row, jump_row), extra, random, why}

def Song.jump_dest(song: Song) -> U32:
  Song{_, _, _, _, _, jump_dest, _, _, _, _} = song
  jump_dest

def song.unjumped(song: Song) -> Song:
  Song{tempo, bpm, global, _, breaking, jump_dest, jump_row, extra, random, why} = song
  Song{tempo, bpm, global, False{}, breaking, jump_dest, jump_row, extra, random, why}

def song.broken(song: Song, +row: U32) -> Song:
  Song{tempo, bpm, global, jumping, _, jump_dest, _, extra, random, why} = song
  Song{tempo, bpm, global, jumping, True{}, jump_dest, row, extra, random, why}

def song.rowed(song: Song, +row: U32) -> Song:
  Song{tempo, bpm, global, jumping, breaking, jump_dest, _, extra, random, why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, row, extra, random, why}

def song.paced(song: Song, +param: U32) -> Song:
  Song{+tempo, +bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, why} = song
  Song{Bool.pick(U32, (param > 0 : U32) && (param <= 31 : U32), param, tempo), Bool.pick(U32, (param > 31 : U32), param, bpm), global, jumping, breaking, jump_dest, jump_row, extra, random, why}

def song.globaled(song: Song, +global: F32) -> Song:
  Song{tempo, bpm, _, jumping, breaking, jump_dest, jump_row, extra, random, why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, why}

def Song.global(song: Song) -> F32:
  Song{_, _, global, _, _, _, _, _, _, _} = song
  global

def song.delayed(song: Song, +extra: U32) -> Song:
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, _, random, why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, extra, random, why}

# E6y: with a count, the loop's passes: after as many as the count the loop
# is over, otherwise the row jumps back to the loop's origin; without one
# the row is the loop's origin.
def loop.effect(+around: Around, +channel: Channel, +song: Song, +count: U32) -> Turn:
  +passes = memo.get(Channel.memo(channel), 14)
  +origin = memo.get(Channel.memo(channel), 13)
  Bool.pick(Turn, U32.is_eq(count, 0), Turn{with.memo(channel, memo.set(Channel.memo(channel), 13, Around.row(around))), song.rowed(song, Around.row(around))},
    Bool.pick(Turn, U32.is_eq(count, passes), Turn{with.memo(channel, memo.set(Channel.memo(channel), 14, 0)), song.unjumped(song)},
      Turn{with.memo(channel, memo.set(Channel.memo(channel), 14, ((passes + 1) .&. 255 : U32))), song.jump(song, True{}, Around.index(around), origin, True{})}))

def Pitch.orig(pitch: Pitch) -> F32:
  Pitch{_, orig, _, _, _} = pitch
  orig

# E5y: the note's finetune set. jar_xm shifts the parameter less 8 left by
# four bits, which C leaves undefined for a parameter below 8.
def finetune.effect(kind: U32, +around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  match kind:
    case 0: Turn{channel, song}
    case 1: Turn{channel, stopped(song, 1)}
    case _: period.update(around, with.pitch(channel, pitch.noted(Channel.pitch(channel),
      ((float.of((Slot.note(Channel.slot(channel)) + Sample.relative(sample.of(Around.module(around), channel)) : U32)) + (U32.to_f32((((param .&. 15) - 8) << 4n : U32)) / 128.0)) - 1.0 : F32), False{})), song)

# EDy (on the tick it is delayed to): with neither note nor instrument in
# the slot, the note begins again, from its original note for a delay that
# is not 0 and as it is otherwise.
def delay.effect(bare: Bool, +around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  match bare:
    case False{}: Turn{channel, song}
    case True{}: Bool.pick(Turn, U32.is_ne((param .&. 15 : U32), 0), note.trigger(around, with.pitch(channel, pitch.noted(Channel.pitch(channel), Pitch.orig(Channel.pitch(channel)), False{})), song, 1), note.trigger(around, channel, song, 7))

# Exy.
def extended(sub: U32, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match sub:
    case 1: pitch.slide(around, remembered(channel, 6, (Slot.param(slot) .&. 15 : U32)), song, float.of((0 - memo.get(Channel.memo(remembered(channel, 6, (Slot.param(slot) .&. 15 : U32))), 6) : U32)))
    case 2: pitch.slide(around, remembered(channel, 7, (Slot.param(slot) .&. 15 : U32)), song, U32.to_f32(memo.get(Channel.memo(remembered(channel, 7, (Slot.param(slot) .&. 15 : U32))), 7)))
    case 4: Turn{with.wobble(channel, wobble.waves(Channel.wobble(channel), True{}, (Slot.param(slot) .&. 3 : U32), U32.is_eq(((Slot.param(slot) >> 2n) .&. 1 : U32), 0))), song}
    case 5: finetune.effect(Bool.pick(U32, Bool.not((Slot.note(Channel.slot(channel)) > 0 : U32) && (Slot.note(Channel.slot(channel)) < 97 : U32)) || U32.is_eq(Channel.owner(channel), 0), 0, Bool.pick(U32, ((Slot.param(slot) .&. 15 : U32) < 8 : U32), 1, 2)),
      around, channel, song, Slot.param(slot))
    case 6: loop.effect(around, channel, song, (Slot.param(slot) .&. 15 : U32))
    case 7: Turn{with.wobble(channel, wobble.waves(Channel.wobble(channel), False{}, (Slot.param(slot) .&. 3 : U32), U32.is_eq(((Slot.param(slot) >> 2n) .&. 1 : U32), 0))), song}
    case 10: Turn{volume.slide(remembered(channel, 1, (Slot.param(slot) .&. 15 : U32)), (memo.get(Channel.memo(remembered(channel, 1, (Slot.param(slot) .&. 15 : U32))), 1) << 4n : U32)), song}
    case 11: Turn{volume.slide(remembered(channel, 1, (Slot.param(slot) .&. 15 : U32)), memo.get(Channel.memo(remembered(channel, 1, (Slot.param(slot) .&. 15 : U32))), 1)), song}
    case 13: delay.effect(U32.is_eq(Slot.note(slot), 0) && U32.is_eq(Slot.instrument(slot), 0), around, channel, song, Slot.param(Channel.slot(channel)))
    case 14: Turn{channel, song.delayed(song, (((Slot.param(Channel.slot(channel)) .&. 15) * Song.tempo(song)) .&. 65535 : U32))}
    case _: Turn{channel, song}

# Xxy: the extra fine portamentos.
def extra(sub: U32, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match sub:
    case 1: pitch.slide(around, remembered(channel, 8, (Slot.param(slot) .&. 15 : U32)), song, ((0.0 - 1.0 : F32) * U32.to_f32(memo.get(Channel.memo(remembered(channel, 8, (Slot.param(slot) .&. 15 : U32))), 8)) : F32))
    case 2: pitch.slide(around, remembered(channel, 9, (Slot.param(slot) .&. 15 : U32)), song, U32.to_f32(memo.get(Channel.memo(remembered(channel, 9, (Slot.param(slot) .&. 15 : U32))), 9)))
    case _: Turn{channel, song}

def level.set(level: Level, +volume: F32, +panning: F32) -> Level:
  level.slid(level, volume, panning)

# The effect column of a slot, as jar_xm_handle_note_and_instrument reads
# it.
def effect.row(effect: U32, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match effect:
    case 1: Turn{remembered(channel, 4, Slot.param(slot)), song}
    case 2: Turn{remembered(channel, 5, Slot.param(slot)), song}
    case 3: Turn{remembered(channel, 10, Slot.param(slot)), song}
    case 4: Turn{with.wobble(channel, wobble.params(Channel.wobble(channel), nibbles(Wobble.vibrato_param(Channel.wobble(channel)), Slot.param(slot)), Wobble.tremolo_param(Channel.wobble(channel)))), song}
    case 5: Turn{remembered(channel, 0, Slot.param(slot)), song}
    case 6: Turn{remembered(channel, 0, Slot.param(slot)), song}
    case 7: Turn{with.wobble(channel, wobble.params(Channel.wobble(channel), Wobble.vibrato_param(Channel.wobble(channel)), nibbles(Wobble.tremolo_param(Channel.wobble(channel)), Slot.param(slot)))), song}
    case 8: Turn{with.level(channel, level.set(Channel.level(channel), Level.volume(Channel.level(channel)), (U32.to_f32(Slot.param(slot)) / 255.0 : F32))), song}
    case 9: Turn{offset.set(U32.is_ne(Channel.owner(channel), 0), around, channel, Slot.param(slot)), song}
    case 10: Turn{remembered(channel, 0, Slot.param(slot)), song}
    case 11: Turn{channel, Bool.pick(Song, (Slot.param(slot) < Module.length(Around.module(around)) : U32), song.jump(song, True{}, Slot.param(slot), 0, False{}), song)}
    case 12: Turn{with.level(channel, level.set(Channel.level(channel), (U32.to_f32(U32.min(Slot.param(slot), 64)) / 64.0 : F32), Level.panning(Channel.level(channel)))), song}
    case 13: Turn{channel, song.broken(song, (((Slot.param(slot) >> 4n) * 10) + (Slot.param(slot) .&. 15) : U32))}
    case 14: extended((Slot.param(slot) >> 4n : U32), around, channel, song, slot)
    case 15: Turn{channel, song.paced(song, Slot.param(slot))}
    case 16: Turn{channel, song.globaled(song, (U32.to_f32(U32.min(Slot.param(slot), 64)) / 64.0 : F32))}
    case 17: Turn{remembered(channel, 2, Slot.param(slot)), song}
    case 21: Turn{with.level(channel, level.frames(Channel.level(channel), Slot.param(slot))), song}
    case 25: Turn{remembered(channel, 3, Slot.param(slot)), song}
    case 27: Turn{Bool.pick(Channel, (Slot.param(slot) > 0 : U32), with.memo(channel, memo.set(Channel.memo(channel), 11, Bool.pick(U32, U32.is_eq((Slot.param(slot) >> 4n : U32), 0),
      ((memo.get(Channel.memo(channel), 11) .&. 240) .|. (Slot.param(slot) .&. 15) : U32), Slot.param(slot)))), channel), song}
    case 29: Turn{remembered(channel, 15, Slot.param(slot)), song}
    case 33: extra((Slot.param(slot) >> 4n : U32), around, channel, song, slot)
    case _: Turn{channel, song}

def slot.effected(+around: Around, +slot: Xm.Slot, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  effect.row(Slot.effect(slot), around, channel, song, slot)

# jar_xm_handle_note_and_instrument(ctx, ch, s).
def slot.handle(+around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  slot.effected(around, slot, slot.noted(around, slot, slot.instrumented(around, channel, song, slot)))

# -----------------------------------------------------------------------------
# A tick of a channel

def Wobble.arp(wobble: Wobble) -> Bool:
  Wobble{_, _, arp, _, _, _, _, _, _, _, _, _, _, _} = wobble
  arp

def Wobble.vibrating(wobble: Wobble) -> Bool:
  Wobble{_, _, _, _, vibrating, _, _, _, _, _, _, _, _, _} = wobble
  vibrating

def wobble.still(wobble: Wobble) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, _, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, _, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, False{}, vibrato_wave, vibrato_again, vibrato_param, vibrato_ticks, 0.0, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks}

# An arpeggio that the slot no longer has ends.
def arpeggio.ended(ended: Bool, +around: Around, +turn: Turn) -> Turn:
  match ended:
    case False{}: turn
    case True{}: arpeggio.set(around, Turn.channel(turn), Turn.song(turn), False{}, 0)

# HAS_VIBRATO: the effect 4, a parameter of 6 (jar_xm's test, where the
# effect 6 is meant), or B in the volume column.
def vibrato.has(+slot: Xm.Slot) -> Bool:
  U32.is_eq(Slot.effect(slot), 4) || U32.is_eq(Slot.param(slot), 6) || U32.is_eq((Slot.volume(slot) >> 4n : U32), 11)

# ... and so does the effect's vibrato.
def vibrato.ended(ended: Bool, +around: Around, +turn: Turn) -> Turn:
  match ended:
    case False{}: turn
    case True{}: frequency.update(around, with.wobble(Turn.channel(turn), wobble.still(Channel.wobble(Turn.channel(turn)))), Turn.song(turn))

def wobble.speed(wobble: Wobble, +speed: U32) -> Wobble:
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, +vibrato_param, vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks} = wobble
  Wobble{auto_ticks, auto_offset, arp, arp_offset, vibrating, vibrato_wave, vibrato_again, ((vibrato_param .&. 15) .|. (speed << 4n) : U32), vibrato_ticks, vibrato_offset, tremolo_wave, tremolo_again, tremolo_param, tremolo_ticks}

# The volume column on a tick: `column` is its byte.
def column.tick(kind: U32, +around: Around, +channel: Channel, +song: Song, +column: U32) -> Turn:
  match kind:
    case 1: Turn{with.level(channel, level.set(Channel.level(channel), (float.of((column - 16 : U32)) / 64.0 : F32), Level.panning(Channel.level(channel)))), song}
    case 6: Turn{volume.slide(channel, (column .&. 15 : U32)), song}
    case 7: Turn{volume.slide(channel, (column << 4n : U32)), song}
    case 8: Turn{volume.slide(channel, (column .&. 15 : U32)), song}
    case 9: Turn{volume.slide(channel, (column << 4n : U32)), song}
    case 10: Turn{with.wobble(channel, wobble.speed(Channel.wobble(channel), (column .&. 15 : U32))), song}
    case 11: vibrato(around, channel, song, False{})
    case 12: Turn{Bool.pick(Channel, U32.is_eq(Around.tick(around), 0), with.level(channel, level.set(Channel.level(channel), Level.volume(Channel.level(channel)), (U32.to_f32((column .&. 15 : U32)) / 15.0 : F32))), channel), song}
    case 13: Turn{panning.slide(channel, (column .&. 15 : U32)), song}
    case 14: Turn{panning.slide(channel, (column << 4n : U32)), song}
    case 15: portamento(around, Bool.pick(Channel, U32.is_eq(Around.tick(around), 0) && U32.is_ne((column .&. 15 : U32), 0), with.memo(channel, memo.set(Channel.memo(channel), 10, (((column .&. 15) << 4n) .|. (column .&. 15) : U32))), channel), song)
    case _: Turn{channel, song}

# 0x10 to 0x4F set the volume, and so does 0x50 alone of its sixteen.
def column.kind(+column: U32) -> U32:
  Bool.pick(U32, ((column >> 4n : U32) >= 1 : U32) && ((column >> 4n : U32) <= 4 : U32), 1, Bool.pick(U32, U32.is_eq((column >> 4n : U32), 5), Bool.pick(U32, U32.is_eq(column, 80), 1, 0), (column >> 4n : U32)))

def column.ticked(+around: Around, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  column.tick(column.kind(Slot.volume(Channel.slot(channel))), around, channel, song, Slot.volume(Channel.slot(channel)))

# 0xy on a tick, by the tempo modulo 3: the first ticks of a row without
# the arpeggio (one for 1, two for 2, where the second has the first
# note), then its three notes in turn.
def arpeggio.tick(+around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  +offset = (Song.tempo(song) % 3 : U32)
  Bool.pick(Turn, U32.is_eq(offset, 2) && U32.is_eq(Around.tick(around), 1), arpeggio.set(around, channel, song, True{}, (param >> 4n : U32)),
    Bool.pick(Turn, (U32.is_eq(offset, 2) || U32.is_eq(offset, 1)) && U32.is_eq(Around.tick(around), 0), arpeggio.set(around, channel, song, False{}, 0), arpeggio(around, channel, song, param, (Around.tick(around) - offset : U32))))

def retriggered(+around: Around, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  envelopes(around, channel, song)

def level.volumed.to(+level: Level, +volume: F32) -> Level:
  level.slid(level, volume, Level.panning(level))

def retrig.volume(+around: Around, +volume: F32, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  Turn{with.level(channel, level.volumed.to(Channel.level(channel), volume)), song}

# multi_retrig_add and multi_retrig_multiply, as bits.
def retrig.add() -> +List<F32>:
  [0.0, (0.0 - 1.0 : F32), (0.0 - 2.0 : F32), (0.0 - 4.0 : F32), (0.0 - 8.0 : F32), (0.0 - 16.0 : F32), 0.0, 0.0, 0.0, 1.0, 2.0, 4.0, 8.0, 16.0, 0.0, 0.0]

def retrig.multiply() -> +List<F32>:
  [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.6666667, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0]

def float.first(xs: +List<F32>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{+x, _}: x

def float.nth(xs: +List<F32>, +i: U32) -> F32:
  float.first(List.drop(&2, F32, xs, U32.to_nat(i)))

# jar_xm_CLAMP: a value kept from 0 to 1.
def unit(+x: F32) -> F32:
  Bool.pick(F32, (x > 1.0 : F32), 1.0, Bool.pick(F32, (x < 0.0 : F32), 0.0, x))

# Hxy on a tick: the global volume up by x or down by y over 64, kept from
# 0 to 1; with both it is left.
def global.slide(+song: Song, +param: U32) -> Song:
  Bool.pick(Song, U32.is_ne((param .&. 240 : U32), 0) && U32.is_ne((param .&. 15 : U32), 0), song,
    Bool.pick(Song, U32.is_ne((param .&. 240 : U32), 0), song.globaled(song, capped((Song.global(song) + (U32.to_f32((param >> 4n : U32)) / 64.0) : F32))), song.globaled(song, floored((Song.global(song) - (U32.to_f32((param .&. 15 : U32)) / 64.0) : F32)))))

def level.tremor(level: Level, +tremor: Bool) -> Level:
  Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, _, target_panning, target_volume, actual_panning, actual_volume} = level
  Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, actual_panning, actual_volume}

# Exy on a tick: E9y begins the note again every y ticks, ECy cuts it at
# tick y, EDy plays the slot at the tick it is delayed to.
def extended.tick(sub: U32, +around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  match sub:
    case 9: Bool.pick(Turn, U32.is_ne(Around.tick(around), 0) && U32.is_ne((param .&. 15 : U32), 0) && U32.is_eq((Around.tick(around) % U32.max((param .&. 15 : U32), 1) : U32), 0), retriggered(around, note.trigger(around, channel, song, 0)), Turn{channel, song})
    case 12: Turn{Bool.pick(Channel, U32.is_eq((param .&. 15 : U32), Around.tick(around)), note.cut(channel), channel), song}
    case 13: Bool.pick(Turn, U32.is_eq(memo.get(Channel.memo(channel), 12), Around.tick(around)), retriggered(around, slot.handle(around, channel, song, Channel.slot(channel))), Turn{channel, song})
    case _: Turn{channel, song}

# Rxy on a tick: every y ticks the note begins again at the volume the x
# makes of it.
def retrig.tick(+around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  Bool.pick(Turn, U32.is_ne((param .&. 15 : U32), 0) && U32.is_eq((Around.tick(around) % U32.max((param .&. 15 : U32), 1) : U32), 0),
    retrig.volume(around, unit(((Level.volume(Channel.level(channel)) * float.nth(retrig.multiply(), (param >> 4n : U32))) + float.nth(retrig.add(), (param >> 4n : U32)) : F32)), note.trigger(around, channel, song, 0)), Turn{channel, song})

def slid.volume(turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  Turn{volume.slide(channel, memo.get(Channel.memo(channel), 0)), song}

# The effects that go on after a row's first tick. `later` is whether the
# tick is not the first.
def effect.later(effect: U32, +around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  match effect:
    case 1: pitch.slide(around, channel, song, float.of((0 - memo.get(Channel.memo(channel), 4) : U32)))
    case 2: pitch.slide(around, channel, song, U32.to_f32(memo.get(Channel.memo(channel), 5)))
    case 3: portamento(around, channel, song)
    case 4: vibrato(around, channel, song, True{})
    case 5: slid.volume(portamento(around, channel, song))
    case 6: slid.volume(vibrato(around, channel, song, True{}))
    case 7: tremolo(around, channel, song)
    case 10: Turn{volume.slide(channel, memo.get(Channel.memo(channel), 0)), song}
    case 17: Turn{channel, global.slide(song, memo.get(Channel.memo(channel), 2))}
    case 25: Turn{panning.slide(channel, memo.get(Channel.memo(channel), 3)), song}
    case 27: retrig.tick(around, channel, song, memo.get(Channel.memo(channel), 11))
    case 29: Turn{with.level(channel, level.tremor(Channel.level(channel), (((Around.tick(around) - 1) % (((memo.get(Channel.memo(channel), 15) >> 4n) + (memo.get(Channel.memo(channel), 15) .&. 15)) + 2) : U32) > (memo.get(Channel.memo(channel), 15) >> 4n) : U32))), song}
    case _: Turn{channel, song}

# The effect column on a tick.
def effect.tick(effect: U32, +code: U32, +around: Around, +channel: Channel, +song: Song, +param: U32) -> Turn:
  match effect:
    case 0: Bool.pick(Turn, (param > 0 : U32), arpeggio.tick(around, channel, song, param), Turn{channel, song})
    case 14: extended.tick((param >> 4n : U32), around, channel, song, param)
    case 20: Turn{Bool.pick(Channel, U32.is_eq(Around.tick(around), param), note.released(around, channel), channel), song}
    case _: Bool.pick(Turn, U32.is_eq(Around.tick(around), 0), Turn{channel, song}, effect.later(code, around, channel, song, param))

def effect.ticked(+around: Around, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  effect.tick(Slot.effect(Channel.slot(channel)), Slot.effect(Channel.slot(channel)), around, channel, song, Slot.param(Channel.slot(channel)))

# -----------------------------------------------------------------------------
# The volume and panning the mixer ramps to

def panned.sum(sum: Maybe<M.Float64>) -> Maybe<F32>:
  match sum:
    case None{}: None{}
    case Some{value}: M.Float64.to_f32(value)

def panned.doubled(product: Maybe<M.Float64>, +panning: F32) -> Maybe<F32>:
  match product:
    case None{}: None{}
    case Some{value}: panned.sum(M.Float64.internal.add(M.Float64.from_f32(panning), value))

def panned.product(product: Maybe<M.Float64>, +panning: F32) -> Maybe<F32>:
  match product:
    case None{}: None{}
    case Some{value}: panned.doubled(M.Float64.internal.multiply(value, M.Float64.from_f32(2.0)), panning)

def panned.room(room: Maybe<M.Float64>, +panning: F32, +spread: F32) -> Maybe<F32>:
  match room:
    case None{}: None{}
    case Some{value}: panned.product(M.Float64.internal.multiply(M.Float64.from_f32((spread - 0.5 : F32)), value), panning)

# panning + (envelope - .5f)*(.5f - fabs(panning - .5f))*2.0f: fabs makes
# the product and the sum binary64 ones, narrowed to a float at the end.
def panned(+panning: F32, +spread: F32) -> Maybe<F32>:
  panned.room(M.Float64.internal.subtract(M.Float64.from_f32(0.5), M.Float64.from_f32(Bool.pick(F32, ((panning - 0.5 : F32) < 0.0 : F32), ((panning - 0.5) * (0.0 - 1.0 : F32) : F32), (panning - 0.5 : F32)))), panning, spread)

def level.aimed(level: Level, +panning: F32) -> Level:
  Level{+volume, +pan, sustained, +fadeout, +envelope, spread, volume_frames, panning_frames, +tremolo, +tremor, _, _, actual_panning, actual_volume} = level
  Level{volume, pan, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, panning, Bool.pick(F32, tremor, 0.0, (unit((volume + tremolo : F32)) * (fadeout * envelope) : F32)), actual_panning, actual_volume}

def aim.set(panning: Maybe<F32>, +channel: Channel, +song: Song) -> Turn:
  match panning:
    case None{}: Turn{channel, stopped(song, 5)}
    case Some{+p}: Turn{with.level(channel, level.aimed(Channel.level(channel), p)), song}

# The tick's end for a channel: the panning and the volume its sound is to
# reach.
def aimed(turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  aim.set(panned(Level.panning(Channel.level(channel)), Level.spread(Channel.level(channel))), channel, song)

def channel.unvibrated(+around: Around, +turn: Turn) -> Turn:
  vibrato.ended(Wobble.vibrating(Channel.wobble(Turn.channel(turn))) && Bool.not(vibrato.has(Channel.slot(Turn.channel(turn)))), around, turn)

def channel.settled(+around: Around, +turn: Turn) -> Turn:
  channel.unvibrated(around, arpeggio.ended(Wobble.arp(Channel.wobble(Turn.channel(turn))) && Bool.not(U32.is_eq(Slot.effect(Channel.slot(Turn.channel(turn))), 0) && U32.is_ne(Slot.param(Channel.slot(Turn.channel(turn))), 0)), around, turn))

def autovibrated(+around: Around, turn: Turn) -> Turn:
  Turn{+channel, +song} = turn
  autovibrato(around, channel, song)

# A channel's tick: the envelopes, the instrument's vibrato, an arpeggio or
# a vibrato the slot no longer has ended, the volume column, the effect,
# and the volume and panning to reach.
def channel.tick(+around: Around, +channel: Channel, +song: Song) -> Turn:
  aimed(effect.ticked(around, column.ticked(around, channel.settled(around, autovibrated(around, envelopes(around, channel, song))))))

# -----------------------------------------------------------------------------
# The player

# jar_xm's context as it plays: the module and its samples as the
# per-sample step reads them, the device's rate, the song (tempo, BPM,
# global volume, jumps, the random waveform's state, why it stopped), where
# it is (the order's entry, the row, the tick), the samples left in the
# tick, the count of each row's passes (256 an entry of the order), the
# loop count, the samples generated, and the channels.
type Player is Data:
  Player{libm: M.Libm, module: Xm.Module, tones: +List<+List<Sm.Tone>>, rate: U32, song: Song, index: U32, row: U32, tick: U32, remaining: F32, counts: R.Index, loops: U32, generated: U32, channels: +List<Channel>}

def Player.song(player: Player) -> Song:
  Player{_, _, _, _, song, _, _, _, _, _, _, _, _} = player
  song

def Player.channels(player: Player) -> +List<Channel>:
  Player{_, _, _, _, _, _, _, _, _, _, _, _, channels} = player
  channels

def Player.why(player: Player) -> U32:
  Song.why(Player.song(player))

def Player.around(player: Player) -> Around:
  Player{libm, module, tones, rate, _, index, row, tick, _, _, _, _, _} = player
  Around{libm, module, rate, index, row, tick, tones}

# The channels after something is done to each in turn, and the song.
type Round is Data:
  Round{channels: +List<Channel>, song: Song, looping: Bool}

# A tick of every channel.
def channels.tick(channels: +List<Channel>, +around: Around, +song: Song, acc: +List<Channel>) -> Round:
  match channels:
    case Nil{}: Round{List.reverse(&2, Channel, acc), song, False{}}
    case Con{+channel, +rest}:
      +turn = channel.tick(around, channel, song)
      channels.tick(rest, around, Turn.song(turn), Con{Turn.channel(turn), acc})

# -----------------------------------------------------------------------------
# jar_xm_row

def Module.restart(module: Xm.Module) -> U32:
  Xm.Module{_, restart, _, _, _, _, _, _, _, _} = module
  restart

def Module.tempo(module: Xm.Module) -> U32:
  Xm.Module{_, _, _, _, tempo, _, _, _, _, _} = module
  tempo

def Module.bpm(module: Xm.Module) -> U32:
  Xm.Module{_, _, _, _, _, bpm, _, _, _, _} = module
  bpm

def Module.order(module: Xm.Module) -> +List<U32>:
  Xm.Module{_, _, _, _, _, _, order, _, _, _} = module
  order

def Module.patterns(module: Xm.Module) -> +List<Xm.Pattern>:
  Xm.Module{_, _, _, _, _, _, _, patterns, _, _} = module
  patterns

def Module.channels(module: Xm.Module) -> U32:
  Xm.Module{_, _, channels, _, _, _, _, _, _, _} = module
  channels

def Module.room(module: Xm.Module) -> U32:
  Xm.Module{_, _, _, _, _, _, _, _, _, room} = module
  room

# Where a row is: the order's entry and the row, with the song.
type Place is Data:
  Place{index: U32, row: U32, song: Song}

def song.reset(song: Song, +module: Xm.Module) -> Song:
  Song{_, _, _, jumping, breaking, jump_dest, jump_row, extra, random, why} = song
  Song{Module.tempo(module), Module.bpm(module), 1.0, jumping, breaking, jump_dest, jump_row, extra, random, why}

# jar_xm_post_pattern_change: past the order's end the song begins again at
# its restart position (kept in a byte), with the module's tempo, BPM and
# global volume.
def place.changed(+module: Xm.Module, +index: U32, +row: U32, +song: Song) -> Place:
  Bool.pick(Place, (index >= Module.length(module) : U32), Place{(Module.restart(module) .&. 255 : U32), row, song.reset(song, module)}, Place{index, row, song})

def song.landed(song: Song) -> Song:
  Song{tempo, bpm, global, _, _, jump_dest, _, extra, random, why} = song
  Song{tempo, bpm, global, False{}, False{}, jump_dest, 0, extra, random, why}

def Song.jumping(song: Song) -> Bool:
  Song{_, _, _, jumping, _, _, _, _, _, _} = song
  jumping

def Song.breaking(song: Song) -> Bool:
  Song{_, _, _, _, breaking, _, _, _, _, _} = song
  breaking

def Song.jump_row(song: Song) -> U32:
  Song{_, _, _, _, _, _, jump_row, _, _, _} = song
  jump_row

# A row's place: a position jump goes to its entry and row, a pattern break
# to the next entry and its row.
def place.of(+module: Xm.Module, +index: U32, +row: U32, +song: Song) -> Place:
  Bool.pick(Place, Song.jumping(song), place.changed(module, Song.jump_dest(song), Song.jump_row(song), song.landed(song)),
    Bool.pick(Place, Song.breaking(song), place.changed(module, ((index + 1) .&. 255 : U32), Song.jump_row(song), song.landed(song)), Place{index, row, song}))

def pattern.first(patterns: +List<Xm.Pattern>) -> Xm.Pattern:
  match patterns:
    case Nil{}: Xm.Pattern{0, Nil{}}
    case Con{+pattern, _}: pattern

def counted.patterns(patterns: +List<Xm.Pattern>, +n: U32) -> U32:
  match patterns:
    case Nil{}: n
    case Con{_, +rest}: counted.patterns(rest, (n + 1 : U32))

def Pattern.rows(pattern: Xm.Pattern) -> U32:
  Xm.Pattern{rows, _} = pattern
  rows

def Pattern.slots(pattern: Xm.Pattern) -> +List<Xm.Slot>:
  Xm.Pattern{_, slots} = pattern
  slots

# A slot on a channel as the row begins: a note delay (EDy) is only
# remembered, anything else is played.
def slot.rowed(delayed: Bool, +around: Around, +channel: Channel, +song: Song, +slot: Xm.Slot) -> Turn:
  match delayed:
    case True{}: Turn{with.memo(channel, memo.set(Channel.memo(channel), 12, (Slot.param(slot) .&. 15 : U32))), song}
    case False{}: slot.handle(around, channel, song, slot)

# The row's slots given to the channels in turn; `looping` is whether a
# channel is in a pattern loop after it.
def channels.row(channels: +List<Channel>, slots: +List<Xm.Slot>, +around: Around, +song: Song, +looping: Bool, acc: +List<Channel>) -> Round:
  match channels slots:
    case Con{+channel, +rest} Con{+slot, +more}:
      +turn = slot.rowed(U32.is_eq(Slot.effect(slot), 14) && U32.is_eq((Slot.param(slot) >> 4n : U32), 13), around, with.slot(channel, slot), song, slot)
      channels.row(rest, more, around, Turn.song(turn), looping || (memo.get(Channel.memo(Turn.channel(turn)), 14) > 0 : U32), Con{Turn.channel(turn), acc})
    case _ _: Round{List.reverse(&2, Channel, acc), song, looping}

def Song.extra(song: Song) -> U32:
  Song{_, _, _, _, _, _, _, extra, _, _} = song
  extra

# The row after this one: the next, or the next entry's (at the row an E60
# left, 0 otherwise) past the pattern's rows and past row 255.
def place.next(+module: Xm.Module, +index: U32, +row: U32, +rows: U32, +song: Song) -> Place:
  Bool.pick(Place, Bool.not(Song.jumping(song)) && Bool.not(Song.breaking(song)) && ((((row + 1) .&. 255 : U32) >= rows : U32) || U32.is_eq(((row + 1) .&. 255 : U32), 0)),
    place.changed(module, ((index + 1) .&. 255 : U32), Song.jump_row(song), song.rowed(song, 0)), Place{index, ((row + 1) .&. 255 : U32), song})

def player.placed(player: Player, place: Place, +channels: +List<Channel>, +counts: R.Index, +loops: U32) -> Player:
  Player{libm, module, tones, rate, _, _, _, tick, remaining, _, _, generated, _} = player
  Place{index, row, song} = place
  Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, loops, generated, channels}

# After the channels: the row's passes counted unless a pattern loop is on
# (a count past jar_xm's block of memory is a write outside it), and the
# next row.
def row.counted(round: Round, +player: Player, +index: U32, +row: U32, +rows: U32) -> Player:
  Round{+channels, +song, +looping} = round
  Player{_, +module, _, _, _, _, _, _, _, +counts, +loops, _, _} = player
  +at = ((256 * index) + row : U32)
  +outside = Bool.not(looping) && (at >= Module.room(module) : U32)
  player.placed(player, place.next(module, index, row, rows, Bool.pick(Song, outside, stopped(song, 1), song)), channels, Bool.pick(R.Index, looping || outside, counts, R.Index.set(counts, at, ((R.Index.get(counts, at) + 1) .&. 255 : U32))),
    Bool.pick(U32, looping || outside, loops, R.Index.get(counts, at)))

def player.stopped(player: Player, +reason: U32) -> Player:
  Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, loops, generated, channels} = player
  Player{libm, module, tones, rate, stopped(song, reason), index, row, tick, remaining, counts, loops, generated, channels}

def around.at(+player: Player, +index: U32, +row: U32) -> Around:
  Player{libm, module, tones, rate, _, _, _, tick, _, _, _, _, _} = player
  Around{libm, module, rate, index, row, tick, tones}

def Player.module(player: Player) -> Xm.Module:
  Player{_, module, _, _, _, _, _, _, _, _, _, _, _} = player
  module

def row.slots(+player: Player, place: Place, +pattern: Xm.Pattern) -> Player:
  Place{+index, +row, +song} = place
  row.counted(channels.row(Player.channels(player), List.drop(&2, Xm.Slot, Pattern.slots(pattern), U32.to_nat((row * Module.channels(Player.module(player)) : U32))), around.at(player, index, row), song, False{}, Nil{}), player, index, row,
    Pattern.rows(pattern))

# The row's pattern must be one of the module's and have the row: jar_xm
# reads the slots where they would be.
def row.played(fine: Bool, +player: Player, +place: Place, +pattern: Xm.Pattern) -> Player:
  match fine:
    case False{}: player.stopped(player, 1)
    case True{}: row.slots(player, place, pattern)

def Place.index(place: Place) -> U32:
  Place{index, _, _} = place
  index

def Place.row(place: Place) -> U32:
  Place{_, row, _} = place
  row

def row.placed(+player: Player, +place: Place) -> Player:
  +number = nth(Module.order(Player.module(player)), Place.index(place))
  +pattern = pattern.first(List.drop(&2, Xm.Pattern, Module.patterns(Player.module(player)), U32.to_nat(U32.min(number, 65536))))
  row.played((number < counted.patterns(Module.patterns(Player.module(player)), 0) : U32) && (Place.row(place) < Pattern.rows(pattern) : U32), player, place, pattern)

# jar_xm_row.
def row(+player: Player) -> Player:
  Player{_, +module, _, _, +song, +index, +row, _, _, _, _, _, _} = player
  row.placed(player, place.of(module, index, row, song))

# -----------------------------------------------------------------------------
# jar_xm_tick

def song.ticked(song: Song, +over: Bool) -> Song:
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, +extra, random, why} = song
  Song{tempo, bpm, global, jumping, breaking, jump_dest, jump_row, Bool.pick(U32, over, 0, extra), random, why}

def Song.bpm(song: Song) -> U32:
  Song{_, bpm, _, _, _, _, _, _, _, _} = song
  bpm

# After the channels: the tick moved on (to 0 after the row's last, which
# ends a pattern delay), and the tick's samples: the rate over 0.4 times
# the BPM.
def tick.ended(round: Round, +player: Player) -> Player:
  Round{+channels, +song, _} = round
  Player{libm, module, tones, +rate, _, index, row, +tick, +remaining, counts, loops, generated, _} = player
  +over = ((((tick + 1) .&. 65535 : U32)) >= (Song.tempo(song) + Song.extra(song) : U32) : U32)
  Player{libm, module, tones, rate, song.ticked(song, over), index, row, Bool.pick(U32, over, 0, ((tick + 1) .&. 65535 : U32)), (remaining + (U32.to_f32(rate) / (U32.to_f32(Song.bpm(song)) * 0.4)) : F32), counts, loops, generated, channels}

def tick.channels(fine: Bool, +player: Player) -> Player:
  match fine:
    case False{}: player
    case True{}: tick.ended(channels.tick(Player.channels(player), Player.around(player), Player.song(player), Nil{}), player)

def tick.rowed(+player: Player) -> Player:
  tick.channels(U32.is_eq(Player.why(player), 0), player)

def Player.tick(player: Player) -> U32:
  Player{_, _, _, _, _, _, _, tick, _, _, _, _, _} = player
  tick

def tick.begun(first: Bool, +player: Player) -> Player:
  match first:
    case True{}: tick.rowed(row(player))
    case False{}: tick.rowed(player)

def tick.going(going: Bool, +player: Player) -> Player:
  match going:
    case False{}: player
    case True{}: tick.begun(U32.is_eq(Player.tick(player), 0), player)

# jar_xm_tick: a row's first tick plays the row; then every channel's tick.
# A player that has stopped stays as it is.
def tick(+player: Player) -> Player:
  tick.going(U32.is_eq(Player.why(player), 0), player)

# -----------------------------------------------------------------------------
# A player of a module

def Sample.tone(sample: Xm.Sample) -> Sm.Tone:
  Xm.Sample{_, +stereo, +length, +loop_start, +loop_length, +loop_end, _, _, +loop_type, _, _, +data} = sample
  Sm.Tone{length, loop_start, loop_length, loop_end, U32.is_eq(loop_type, 1), U32.is_ne(stereo, 0), R.Row.from(data), R.count.floats(data, 0)}

def tones.sampled(samples: +List<Xm.Sample>, acc: +List<Sm.Tone>) -> +List<Sm.Tone>:
  match samples:
    case Nil{}: List.reverse(&2, Sm.Tone, acc)
    case Con{+sample, +rest}: tones.sampled(rest, Con{Sample.tone(sample), acc})

def tones.of(instruments: +List<Xm.Instrument>, acc: +List<+List<Sm.Tone>>) -> +List<+List<Sm.Tone>>:
  match instruments:
    case Nil{}: List.reverse(&2, +List<Sm.Tone>, acc)
    case Con{+instrument, +rest}: tones.of(rest, Con{tones.sampled(Instrument.samples(instrument), Nil{}), acc})

def channels.new(n: Nat, acc: +List<Channel>) -> +List<Channel>:
  match n:
    case 0n: acc
    case 1n+k: channels.new(k, Con{channel.new(), acc})

# The player of a module as jar_xm_create_context_safe leaves its context,
# for a device of a rate. `random` is the random waveform's state, which
# jar_xm keeps for all its modules together: 24492 for the first.
def player.new(+libm: M.Libm, +module: Xm.Module, +rate: U32, +random: U32) -> Player:
  Player{libm, module, tones.of(Module.instruments(module), Nil{}), rate, Song{Module.tempo(module), Module.bpm(module), 1.0, False{}, False{}, 0, 0, 0, random, 0}, 0, 0, 0, 0.0, R.Index.new(16, 0), 0, 0,
    channels.new(U32.to_nat(Module.channels(module)), Nil{})}

def channels.cut(channels: +List<Channel>, acc: +List<Channel>) -> +List<Channel>:
  match channels:
    case Nil{}: List.reverse(&2, Channel, acc)
    case Con{+channel, +rest}: channels.cut(rest, Con{note.cut(channel), acc})

# jar_xm_reset: every note cut, the player at the song's start with the
# module's tempo, BPM and global volume, and no samples generated. What the
# channels and the song otherwise are stays.
def reset(player: Player) -> Player:
  Player{libm, +module, tones, rate, song, _, _, _, remaining, counts, loops, _, channels} = player
  Player{libm, module, tones, rate, song.reset(song, module), 0, 0, 0, remaining, counts, loops, 0, channels.cut(channels, Nil{})}

# -----------------------------------------------------------------------------
# jar_xm_get_remaining_samples

# The player, the samples counted, and whether the count goes on.
type Count is Data:
  Count{player: Player, total: U32, on: Bool}

def Player.loops(player: Player) -> U32:
  Player{_, _, _, _, _, _, _, _, _, _, loops, _, _} = player
  loops

def Player.remaining(player: Player) -> F32:
  Player{_, _, _, _, _, _, _, _, remaining, _, _, _, _} = player
  remaining

def player.emptied(player: Player) -> Player:
  Player{libm, module, tones, rate, song, index, row, tick, _, counts, loops, generated, channels} = player
  Player{libm, module, tones, rate, song, index, row, tick, 0.0, counts, loops, generated, channels}

# A tick's samples added to the count, which jar_xm keeps in a 64-bit int
# and adds to as a float: a sum that is no int of 32 bits here is not
# counted (5).
def count.step(+player: Player, +total: U32, +loops: U32) -> Count:
  +sum = (U32.to_f32(total) + Player.remaining(player) : F32)
  +fine = (sum >= 0.0 : F32) && (sum < 4294967296.0 : F32)
  +next = tick(player.emptied(player))
  Bool.pick(Count, fine, Count{next, F32.to_u32(sum), U32.is_eq(Player.loops(next), loops) && U32.is_eq(Player.why(next), 0)}, Count{player.stopped(player, 5), total, False{}})

def Count.total(count: Count) -> U32:
  Count{_, total, _} = count
  total

def Count.player(count: Count) -> Player:
  Count{player, _, _} = count
  player

def Count.on(count: Count) -> Bool:
  Count{_, _, on} = count
  on

def count.inner(n: Nat, on: Bool, +player: Player, +total: U32, +loops: U32) -> Count:
  match n on:
    case _ False{}: Count{player, total, False{}}
    case 0n True{}: Count{player, total, True{}}
    case 1n+k True{}:
      +next = count.step(player, total, loops)
      count.inner(k, Count.on(next), Count.player(next), Count.total(next), loops)

# Ticks until the loop count changes: 4096 times 4096 at most, past which
# the song is taken not to end (2).
def count.outer(n: Nat, on: Bool, +player: Player, +total: U32, +loops: U32) -> Count:
  match n on:
    case _ False{}: Count{player, total, False{}}
    case 0n True{}: Count{player.stopped(player, 2), total, False{}}
    case 1n+k True{}:
      +next = count.inner(4096n, True{}, player, total, loops)
      count.outer(k, Count.on(next), Count.player(next), Count.total(next), loops)

def player.looped(player: Player, +loops: U32) -> Player:
  Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, _, generated, channels} = player
  Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, loops, generated, channels}

# The player after the count, and the samples.
type Counted is Data:
  Counted{player: Player, samples: U32}

def counted.of(count: Count, +loops: U32) -> Counted:
  Count{+player, +total, _} = count
  Counted{player.looped(player, loops), total}

# jar_xm_get_remaining_samples: the song's ticks played, without sound,
# until a row comes again, and their samples; the loop count is put back.
def remaining.samples(+player: Player) -> Counted:
  counted.of(count.outer(4096n, True{}, player, 0, Player.loops(player)), Player.loops(player))
