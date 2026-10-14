# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_xm (Joshua Reisenauer's port of libxm by
# Romain "Artefact2" Dalmaso; WTFPL), as raylib 6.0 vendors it in
# src/external/jar_xm.h: the mixer (jar_xm_mixdown and
# jar_xm_generate_samples, with ramping on and no loop limit, as raylib
# plays a module). See THIRD_PARTY_NOTICES.md and LICENSES/jar_xm.txt.
import Base
import ./xm_sample.bend as Sm
import ./xm_player.bend as Pl

# The frame's two sums so far.
type Sums is Data:
  Sums{left: F32, right: F32}

# The channels after a frame, the sums, and whether every step was fine.
type Mixed is Data:
  Mixed{channels: +List<Pl.Channel>, left: F32, right: F32, fine: Bool}

def level.ramped(level: Pl.Level) -> Pl.Level:
  Pl.Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, +target_panning, +target_volume, +actual_panning, +actual_volume} = level
  Pl.Level{volume, panning, sustained, fadeout, envelope, spread, volume_frames, panning_frames, tremolo, tremor, target_panning, target_volume, Pl.slid(actual_panning, target_panning, 0.0078125), Pl.slid(actual_volume, target_volume, 0.0078125)}

def head.counted(head: Sm.Head) -> Sm.Head:
  Sm.Head{position, step, +frames, lefts, rights, left, right} = head
  Sm.Head{position, step, (frames + 1 : U32), lefts, rights, left, right}

def Level.actual_volume(level: Pl.Level) -> F32:
  Pl.Level{_, _, _, _, _, _, _, _, _, _, _, _, _, actual_volume} = level
  actual_volume

def Level.actual_panning(level: Pl.Level) -> F32:
  Pl.Level{_, _, _, _, _, _, _, _, _, _, _, _, actual_panning, _} = level
  actual_panning

def Head.left(head: Sm.Head) -> F32:
  Sm.Head{_, _, _, _, _, left, _} = head
  left

def Head.right(head: Sm.Head) -> F32:
  Sm.Head{_, _, _, _, _, _, right} = head
  right

def Stepped.head(stepped: Sm.Stepped) -> Sm.Head:
  Sm.Stepped{head, _} = stepped
  head

def Stepped.fine(stepped: Sm.Stepped) -> Bool:
  Sm.Stepped{_, fine} = stepped
  fine

# A channel that sounds: its next sample added to the sums by its volume
# and panning, its frame counted, and its volume and panning moved a 128th
# towards what the tick set.
def sounded(+stepped: Sm.Stepped, +channel: Pl.Channel, +left: F32, +right: F32, +rest: Mixed) -> Mixed:
  Mixed{+channels, _, _, +fine} = rest
  +level = Pl.Channel.level(channel)
  Mixed{Con{Pl.with.level(Pl.with.head(channel, head.counted(Stepped.head(stepped))), level.ramped(level)), channels},
    (left + ((Head.left(Stepped.head(stepped)) * Level.actual_volume(level)) * (1.0 - Level.actual_panning(level))) : F32), (right + ((Head.right(Stepped.head(stepped)) * Level.actual_volume(level)) * Level.actual_panning(level)) : F32),
    fine && Stepped.fine(stepped)}

def Head.position(head: Sm.Head) -> F32:
  Sm.Head{position, _, _, _, _, _, _} = head
  position

# Whether the mixer steps a channel: it has an instrument and a sample, and
# its position is not below 0.
def sounds(+channel: Pl.Channel) -> Bool:
  U32.is_ne(Pl.Channel.instrument(channel), 0) && U32.is_ne(Pl.Channel.owner(channel), 0) && (Head.position(Pl.Channel.head(channel)) >= 0.0 : F32)

def Mixed.fine(mixed: Mixed) -> Bool:
  Mixed{_, _, _, fine} = mixed
  fine

def Mixed.right(mixed: Mixed) -> F32:
  Mixed{_, _, right, _} = mixed
  right

def Mixed.left(mixed: Mixed) -> F32:
  Mixed{_, left, _, _} = mixed
  left

def channel.sounded(+stepped: Sm.Stepped, +channel: Pl.Channel, +state: Mixed) -> Mixed:
  sounded(stepped, channel, Mixed.left(state), Mixed.right(state), state)

def channel.kept(+channel: Pl.Channel, state: Mixed) -> Mixed:
  Mixed{channels, left, right, fine} = state
  Mixed{Con{channel, channels}, left, right, fine}

def channel.mix(sounding: Bool, +around: Pl.Around, +channel: Pl.Channel, +state: Mixed) -> Mixed:
  match sounding:
    case False{}: channel.kept(channel, state)
    case True{}: channel.sounded(Sm.sample.next(True{}, Pl.tone.of(around, channel), Pl.Channel.head(channel), 4294967295), channel, state)

# A frame of every channel in turn: the channels come out the last first.
def channels.mix(channels: +List<Pl.Channel>, on: Bool, +around: Pl.Around, +state: Mixed) -> Mixed:
  match channels on:
    case _ False{}: state
    case Nil{} True{}: state
    case Con{+channel, +rest} True{}:
      +next = channel.mix(sounds(channel), around, channel, state)
      channels.mix(rest, Mixed.fine(next), around, next)

def bounded(+x: F32) -> F32:
  Bool.pick(F32, (x < (0.0 - 1.0 : F32) : F32), (0.0 - 1.0 : F32), Bool.pick(F32, (x > 1.0 : F32), 1.0, x))

# A sum times the global volume (unless that is 1), kept from -1 to 1.
def out(+sum: F32, +global: F32) -> F32:
  bounded(Bool.pick(F32, F32.is_eq(global, 1.0), sum, (sum * global : F32)))

# The player after a frame, and the frame's two samples.
type Frame is Data:
  Frame{player: Pl.Player, left: F32, right: F32}

def player.mixed(mixed: Mixed, player: Pl.Player) -> Frame:
  Mixed{+channels, +left, +right, +fine} = mixed
  Pl.Player{libm, module, tones, rate, +song, index, row, tick, remaining, counts, loops, generated, _} = player
  Frame{Pl.Player{libm, module, tones, rate, Bool.pick(Pl.Song, fine, song, Pl.stopped(song, 1)), index, row, tick, remaining, counts, loops, generated, List.reverse(&2, Pl.Channel, channels)}, out(left, Pl.Song.global(song)),
    out(right, Pl.Song.global(song))}

def player.spent(player: Pl.Player) -> Pl.Player:
  Pl.Player{libm, module, tones, rate, song, index, row, tick, +remaining, counts, loops, generated, channels} = player
  Pl.Player{libm, module, tones, rate, song, index, row, tick, (remaining - 1.0 : F32), counts, loops, generated, channels}

# The frame of a player that plays: one sample less left in the tick, and
# the channels' frame.
def frame.played(going: Bool, +player: Pl.Player) -> Frame:
  match going:
    case False{}: Frame{player, 0.0, 0.0}
    case True{}: player.mixed(channels.mix(Pl.Player.channels(player), True{}, Pl.Player.around(player), Mixed{Nil{}, 0.0, 0.0, True{}}), player.spent(player))

def frame.ticked(+player: Pl.Player) -> Frame:
  frame.played(U32.is_eq(Pl.Player.why(player), 0), player)

def frame.due(due: Bool, +player: Pl.Player) -> Frame:
  match due:
    case True{}: frame.ticked(Pl.tick(player))
    case False{}: frame.ticked(player)

# jar_xm_mixdown(ctx, &left, &right): a tick where the tick's samples are
# spent, then a frame of every channel. A player that has stopped gives
# silence and stays as it is.
def mixdown(+player: Pl.Player) -> Frame:
  frame.due(U32.is_eq(Pl.Player.why(player), 0) && (Pl.Player.remaining(player) <= 0.0 : F32), player)

# The player after frames, and their samples, left and right in turn (the
# last first while they are made).
type Generated is Data:
  Generated{player: Pl.Player, samples: +List<F32>}

def Frame.right(frame: Frame) -> F32:
  Frame{_, _, right} = frame
  right

def Frame.left(frame: Frame) -> F32:
  Frame{_, left, _} = frame
  left

def Frame.player(frame: Frame) -> Pl.Player:
  Frame{player, _, _} = frame
  player

def frames(n: Nat, on: Bool, +player: Pl.Player, +samples: +List<F32>) -> Generated:
  match n on:
    case _ False{}: Generated{player, samples}
    case 0n True{}: Generated{player, samples}
    case 1n+k True{}:
      +frame = mixdown(player)
      frames(k, U32.is_eq(Pl.Player.why(Frame.player(frame)), 0), Frame.player(frame), Con{Frame.right(frame), Con{Frame.left(frame), samples}})

def player.generated(player: Pl.Player, +count: U32) -> Pl.Player:
  Pl.Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, loops, +generated, channels} = player
  Pl.Player{libm, module, tones, rate, song, index, row, tick, remaining, counts, loops, (generated + count : U32), channels}

def generated.ended(made: Generated) -> Generated:
  Generated{player, samples} = made
  Generated{player, List.reverse(&2, F32, samples)}

# The count of samples jar_xm_generate_samples has been asked for
# (generated_samples), which raylib's GetMusicTimePlayed reads.
def generated.of(player: Pl.Player) -> U32:
  Pl.Player{_, _, _, _, _, _, _, _, _, _, _, generated, _} = player
  generated

# Whether a count with `count` more is still one of 32 bits.
def generated.fits(+generated: U32, +count: U32) -> Bool:
  ((generated + count : U32) >= generated : U32)

def generate.fitting(fits: Bool, +player: Pl.Player, +count: U32) -> Generated:
  match fits:
    case False{}: Generated{Pl.player.stopped(player, 4), Nil{}}
    case True{}: generated.ended(frames(U32.to_nat(count), True{}, player.generated(player, count), Nil{}))

# jar_xm_generate_samples(ctx, output, count): `count` frames of two
# floats. A player that stops gives the frames before that, and its `why`
# says so. jar_xm counts the samples in 64 bits: a count past 32 is past
# this port's limits, and the player stops (4) without a frame.
def generate(+player: Pl.Player, +count: U32) -> Generated:
  generate.fitting(generated.fits(generated.of(player), count), player, count)
