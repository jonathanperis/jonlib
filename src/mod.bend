# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of jar_mod.h v0.01 (Joshua Reisenauer's adaptation
# of Jean-Francois DEL NERO's HxCMOD; WTFPL), as raylib 6.2 vendors it in
# src/external/jar_mod.h: jar_mod_init's period table, jar_mod_load,
# getnote, worknote, workeffect, jar_mod_fillbuffer (no tracker state) and
# jar_mod_max_samples, at raylib's settings (48000 Hz, stereo, 16 bits, the
# filter and a stereo separation of 1). See THIRD_PARTY_NOTICES.md and
# LICENSES/jar_mod.txt.
#
# The module is the file's bytes, read where jar_mod reads them. C's
# unsigned chars, unsigned shorts and shorts are U32 words holding their
# value (a short sign-extended); ints are two's-complement words; `char`
# sample bytes are signed, as on x86 and Apple arm64. A player whose `why`
# is not 0 has met what C leaves undefined (1: a read outside the file or
# outside an array of the context) or a song longer than this port counts
# (2), and plays no further.
import Base
import ./store.bend as R

# -----------------------------------------------------------------------------
# C's integer types

def u8(+x: U32) -> U32:
  (x .&. 255 : U32)

def u16(+x: U32) -> U32:
  (x .&. 65535 : U32)

# (short)x: the low 16 bits, sign-extended.
def s16(+x: U32) -> U32:
  (((x .&. 65535) .^. 32768) - 32768 : U32)

# (signed char)x.
def s8(+x: U32) -> U32:
  (((x .&. 255) .^. 128) - 128 : U32)

# a < b as ints.
def lt(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

# x >> 1 for an int (arithmetic).
def sar1(+x: U32) -> U32:
  ((x >> 1n) .|. (x .&. 2147483648) : U32)

# -----------------------------------------------------------------------------
# Tables

# periodtable[]: twelve octaves of twelve notes.
def periods() -> +List<U32>:
  [27392, 25856, 24384, 23040, 21696, 20480, 19328, 18240, 17216, 16256, 15360, 14496,
   13696, 12928, 12192, 11520, 10848, 10240, 9664, 9120, 8606, 8128, 7680, 7248,
   6848, 6464, 6096, 5760, 5424, 5120, 4832, 4560, 4304, 4064, 3840, 3624,
   3424, 3232, 3048, 2880, 2712, 2560, 2416, 2280, 2152, 2032, 1920, 1812,
   1712, 1616, 1524, 1440, 1356, 1280, 1208, 1140, 1076, 1016, 960, 906,
   856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
   428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
   214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
   107, 101, 95, 90, 85, 80, 75, 71, 67, 63, 60, 56,
   53, 50, 47, 45, 42, 40, 37, 35, 33, 31, 30, 28,
   27, 25, 24, 22, 21, 20, 19, 18, 17, 16, 15, 14,
   13, 13, 12, 11, 11, 10, 9, 9, 8, 8, 7, 7]

# sintable[], the vibrato's half sine.
def sine.quarter(+i: U32) -> U32:
  match i:
    case 0: 0
    case 1: 24
    case 2: 49
    case 3: 74
    case 4: 97
    case 5: 120
    case 6: 141
    case 7: 161
    case 8: 180
    case 9: 197
    case 10: 212
    case 11: 224
    case 12: 235
    case 13: 244
    case 14: 250
    case 15: 253
    case _: 255

# The table rises to 255 at 16 and falls back symmetrically.
def sine(+i: U32) -> U32:
  sine.quarter(Bool.pick(U32, (i <= 16 : U32), i, (32 - i : U32)))

# The eight steps from one period to the next: p - ((p - q)/8)*j, j from 8 - n.
def full.group(n: Nat, +p: U32, +q: U32, +j: U32, rest: +List<U32>) -> +List<U32>:
  match n:
    case 0n: rest
    case 1n+k: Con{(p - ((p - q) / 8) * j : U32), full.group(k, p, q, (j + 1 : U32), rest)}

# Each period with the next one.
def full.of(+ps: +List<U32>, +qs: +List<U32>) -> +List<U32>:
  match ps qs:
    case Con{+p, +prest} Con{+q, +qrest}: full.group(8n, p, q, 0, full.of(prest, qrest))
    case _ _: Nil{}

def list.tail(+xs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

# fullperiod[MAXNOTES*8]: (144 - 1)*8 steps, then zeros (2048 places).
def fullperiods() -> R.Index:
  R.Index.from(full.of(periods(), list.tail(periods())), 0)

# getnote(period): the first index whose period is at most `period` (the
# table never rises, and its places from 1144 are 0), by halving [lo, hi).
def nt.search(n: Nat, +table: R.Index, +period: U32, +lo: U32, +hi: U32) -> U32:
  match n:
    case 0n: lo
    case 1n+k:
      +mid = ((lo + hi) >> 1n : U32)
      +below = (period >= R.Index.get(table, mid) : U32)
      +open = (lo < hi : U32)
      nt.search(k, table, period, Bool.pick(U32, open && Bool.not(below), (mid + 1 : U32), lo), Bool.pick(U32, open && below, mid, hi))

def getnote(+table: R.Index, +period: U32) -> U32:
  nt.search(12n, table, period, 0, 1152)

# -----------------------------------------------------------------------------
# The module

# The file's bytes and size, the channels, the song length and pattern table
# (as jar_mod_load leaves `song`), each sample's length, finetune, volume,
# repeat point, repeat length and data offset (0 for none; slot 8*i + field),
# each pattern's offset, and fullperiod[].
type Mod is Data:
  Mod{bytes: R.Index, size: U32, channels: U32, length: U32, table: R.Index, samples: R.Index, patterns: R.Index, periods: R.Index}

def Mod.byte(+m: Mod, +at: U32) -> U32:
  Mod{bytes, _, _, _, _, _, _, _} = m
  R.Index.get(bytes, at)

def Mod.size(+m: Mod) -> U32:
  Mod{_, +size, _, _, _, _, _, _} = m
  size

def Mod.channels(+m: Mod) -> U32:
  Mod{_, _, +channels, _, _, _, _, _} = m
  channels

def Mod.length(+m: Mod) -> U32:
  Mod{_, _, _, +length, _, _, _, _} = m
  length

def Mod.entry(+m: Mod, +at: U32) -> U32:
  Mod{_, _, _, _, table, _, _, _} = m
  R.Index.get(table, at)

def Mod.sample(+m: Mod, +number: U32, +field: U32) -> U32:
  Mod{_, _, _, _, _, samples, _, _} = m
  R.Index.get(samples, (number * 8 + field : U32))

def Mod.pattern(+m: Mod, +number: U32) -> U32:
  Mod{_, _, _, _, _, _, patterns, _} = m
  R.Index.get(patterns, number)

def Mod.period(+m: Mod, +at: U32) -> U32:
  Mod{_, _, _, _, _, _, _, periods} = m
  R.Index.get(periods, at)

def Mod.periods(+m: Mod) -> R.Index:
  Mod{_, _, _, _, _, _, _, +periods} = m
  periods

# The bytes' big-endian word at `at`.
def word.at(+bytes: R.Index, +at: U32) -> U32:
  ((R.Index.get(bytes, at) << 8n) .|. R.Index.get(bytes, (at + 1 : U32)) : U32)

# modlist[]: the signature's channels, 0 for none.
def signature.word(+word: U32) -> U32:
  match word:
    case 1294027553: 4
    case 1294879534: 4
    case 1179407412: 4
    case 1179407416: 8
    case 876824654: 4
    case 910379086: 6
    case 943933518: 8
    case 825246536: 10
    case 825377608: 12
    case 825508680: 14
    case 825639752: 16
    case 825770824: 18
    case 842023752: 20
    case 842154824: 22
    case 842285896: 24
    case 842416968: 26
    case 842548040: 28
    case 858800968: 30
    case 858932040: 32
    case _: 0

def signature.channels(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  signature.word(((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32))

# The loaded module, or why it is not one: 0, jar_mod_load returns 0 (a file
# that ends before its patterns or samples); 1, what C leaves undefined (a
# file shorter than the 1084 bytes jar_mod copies from it, a pattern table
# entry past patterndata[128]).
type Loaded is Data:
  Loaded{module: Mod}
  Failed{why: U32}

# The pattern offsets: pattern `max` and the ones after it up to the table's
# entry, each 256*channels bytes on; None when the file ends at or before one.
type Patterns is Data:
  Patterns{offsets: R.Index, max: U32, at: U32}

# The entry's patterns: one more while `max` is at most the entry; None when
# the file ends at or before one.
def patterns.entry(n: Nat, +size: U32, +step: U32, +entry: U32, +offsets: R.Index, +max: U32, +at: U32) -> Maybe<Patterns>:
  match n:
    case 0n: Some{Patterns{offsets, max, at}}
    case 1n+k: Bool.pick(Maybe<Patterns>, (max > entry : U32), Some{Patterns{offsets, max, at}},
      Bool.pick(Maybe<Patterns>, ((at + step) >= size : U32), None{},
        patterns.entry(k, size, step, entry, R.Index.set(offsets, max, at), (max + 1 : U32), (at + step : U32))))

def Patterns.offsets(+done: Patterns) -> R.Index:
  Patterns{+offsets, _, _} = done
  offsets

def Patterns.max(+done: Patterns) -> U32:
  Patterns{_, +max, _} = done
  max

def Patterns.at(+done: Patterns) -> U32:
  Patterns{_, _, +at} = done
  at

# Every table entry, i from 128 - n.
def patterns.all(n: Nat, +table: R.Index, +size: U32, +step: U32, +i: U32, found: Maybe<Patterns>) -> Maybe<Patterns>:
  match n found:
    case _ None{}: None{}
    case 0n Some{+done}: Some{done}
    case 1n+k Some{+done}: patterns.all(k, table, size, step, (i + 1 : U32),
      patterns.entry(257n, size, step, R.Index.get(table, i), Patterns.offsets(done), Patterns.max(done), Patterns.at(done)))

# The samples from `at`: (length & 0xFF00)>>8 | (length & 0xFF)<<8 doubled as
# a muint (the bytes as the file has them, big-endian), the same for the
# repeat point and length; a sample of length 0 has no data and keeps its
# repeat length; another's data is at `at`, its repeat length is cut to
# length - reppnt when they pass it, and the file must not end before it.
type Samples is Data:
  Samples{table: R.Index, at: U32}

def samples.one(+bytes: R.Index, +header: U32, +size: U32, +i: U32, +done: Samples) -> Maybe<Samples>:
  Samples{+table, +at} = done
  +length = u16((word.at(bytes, (header + 22 : U32)) * 2 : U32))
  +reppnt = u16((word.at(bytes, (header + 26 : U32)) * 2 : U32))
  +replen = u16((word.at(bytes, (header + 28 : U32)) * 2 : U32))
  +base = (i * 8 : U32)
  +t1 = R.Index.set(R.Index.set(R.Index.set(table, base, length), (base + 1 : U32), R.Index.get(bytes, (header + 24 : U32))), (base + 2 : U32), R.Index.get(bytes, (header + 25 : U32)))
  +t2 = R.Index.set(t1, (base + 3 : U32), reppnt)
  +cut = Bool.pick(U32, ((replen + reppnt) > length : U32), u16((length - reppnt : U32)), replen)
  Bool.pick(Maybe<Samples>, U32.is_eq(length, 0), Some{Samples{R.Index.set(t2, (base + 4 : U32), replen), at}},
    Bool.pick(Maybe<Samples>, ((at + length) > size : U32), None{},
      Some{Samples{R.Index.set(R.Index.set(t2, (base + 4 : U32), cut), (base + 5 : U32), at), (at + length : U32)}}))

# The 31 sample headers, from `headers` (the 15-sample modules' last 16 are
# zeros, read from a zeroed copy).
def samples.all(n: Nat, +bytes: R.Index, +size: U32, +i: U32, found: Maybe<Samples>) -> Maybe<Samples>:
  match n found:
    case _ None{}: None{}
    case 0n Some{+done}: Some{done}
    case 1n+k Some{+done}: samples.all(k, bytes, size, (i + 1 : U32), samples.one(bytes, (20 + i * 30 : U32), size, i, done))

def load.made(+bytes: R.Index, +size: U32, +channels: U32, +length: U32, +table: R.Index, +patterns: R.Index, +done: Samples) -> Loaded:
  Samples{+samples, _} = done
  Loaded{Mod{bytes, size, channels, length, table, samples, patterns, fullperiods()}}

def load.samples(+bytes: R.Index, +size: U32, +channels: U32, +length: U32, +table: R.Index, +patterns: R.Index, found: Maybe<Samples>) -> Loaded:
  match found:
    case None{}: Failed{0}
    case Some{+done}: load.made(bytes, size, channels, length, table, patterns, done)

def load.patterns.done(+bytes: R.Index, +header: R.Index, +size: U32, +channels: U32, +length: U32, +table: R.Index, +done: Patterns) -> Loaded:
  Patterns{+offsets, _, +at} = done
  load.samples(bytes, size, channels, length, table, offsets, samples.all(31n, header, size, 0, Some{Samples{R.Index.new(8, 0), at}}))

def load.patterns(+bytes: R.Index, +header: R.Index, +size: U32, +channels: U32, +length: U32, +table: R.Index, found: Maybe<Patterns>) -> Loaded:
  match found:
    case None{}: Failed{0}
    case Some{+done}: load.patterns.done(bytes, header, size, channels, length, table, done)

# The pattern table from `from` (128 bytes).
def tablebytes.read(n: Nat, +bytes: R.Index, +from: U32, +i: U32, +entries: R.Index) -> R.Index:
  match n:
    case 0n: entries
    case 1n+k: tablebytes.read(k, bytes, from, (i + 1 : U32), R.Index.set(entries, i, R.Index.get(bytes, (from + i : U32))))

# The 15-sample module's header: the file's first 470 bytes, then zeros.
def header.cleared(n: Nat, +bytes: R.Index, +i: U32, +kept: R.Index) -> R.Index:
  match n:
    case 0n: kept
    case 1n+k: header.cleared(k, bytes, (i + 1 : U32), R.Index.set(kept, i, R.Index.get(bytes, i)))

def load.with(+bytes: R.Index, +header: R.Index, +size: U32, +channels: U32, +start: U32, +length: U32, +table: R.Index) -> Loaded:
  Bool.pick(Loaded, (start >= size : U32), Failed{0},
    load.patterns(bytes, header, size, channels, length, table, patterns.all(128n, table, size, (256 * channels : U32), 0, Some{Patterns{R.Index.new(7, 0), 0, start}})))

# The table's largest entry (patterndata[] has 128 places).
def tablebytes.max(n: Nat, +entries: R.Index, +i: U32, +top: U32) -> U32:
  match n:
    case 0n: top
    case 1n+k: tablebytes.max(k, entries, (i + 1 : U32), U32.max(top, R.Index.get(entries, i)))

def load.checked(+bytes: R.Index, +header: R.Index, +size: U32, +channels: U32, +start: U32, +length: U32, +table: R.Index) -> Loaded:
  Bool.pick(Loaded, (tablebytes.max(128n, table, 0, 0) >= 128 : U32), Failed{1}, load.with(bytes, header, size, channels, start, length, table))

def load.signed(+bytes: R.Index, +size: U32, +channels: U32) -> Loaded:
  Bool.pick(Loaded, U32.is_eq(channels, 0),
    load.checked(bytes, header.cleared(470n, bytes, 0, R.Index.new(11, 0)), size, 4, 600, R.Index.get(bytes, 470), tablebytes.read(128n, bytes, 472, 0, R.Index.new(7, 0))),
    load.checked(bytes, bytes, size, channels, 1084, R.Index.get(bytes, 950), tablebytes.read(128n, bytes, 952, 0, R.Index.new(7, 0))))

# jar_mod_load(bytes): the signature's channels (none: a 15-sample module,
# four channels, its table at 470 and patterns at 600), the patterns up to
# the table's largest entry, then the samples; Failed{1} for a file shorter
# than the 1084 bytes jar_mod copies first.
def load(+bytes: +List<U32>) -> Loaded:
  +size = R.count.words(bytes, 0)
  +row = R.Index.from(bytes, 0)
  Bool.pick(Loaded, (size < 1084 : U32), Failed{1},
    load.signed(row, size, signature.channels(R.Index.get(row, 1080), R.Index.get(row, 1081), R.Index.get(row, 1082), R.Index.get(row, 1083))))

# -----------------------------------------------------------------------------
# A channel

# The sample played: its data offset (0 for none), number, length, repeat
# point and length, position (samppos, 22.10 fixed point) and finetune.
type Voice is Data:
  Voice{data: U32, number: U32, length: U32, reppnt: U32, replen: U32, position: U32, finetune: U32}

# period, decalperiod, portaspeed, portaperiod, vibraperiod, Arpperiods[3],
# ArpIndex, vibraparam and vibrapointeur.
type Tone is Data:
  Tone{period: U32, decal: U32, speed: U32, target: U32, vibrato: U32, arp0: U32, arp1: U32, arp2: U32, index: U32, param: U32, pointer: U32}

# effect, parameffect, effect_code, volume, volumeslide, cut_param,
# patternloopcnt and patternloopstartpoint.
type Act is Data:
  Act{effect: U32, param: U32, code: U32, volume: U32, slide: U32, cut: U32, loops: U32, start: U32}

type Channel is Data:
  Channel{voice: Voice, tone: Tone, act: Act}

def Channel.zero() -> Channel:
  Channel{Voice{0, 0, 0, 0, 0, 0, 0}, Tone{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, Act{0, 0, 0, 0, 0, 0, 0, 0}}

def channels.zero(n: Nat) -> +List<Channel>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{Channel.zero(), channels.zero(k)}

# The song's clock: tablepos, patternpos, patterndelay, jump_loop_effect,
# song.speed, bpm, patternticks, patterntickse, patternticksaim, samplenb
# and loopcount.
type Clock is Data:
  Clock{tablepos: U32, patternpos: U32, delay: U32, jump: U32, speed: U32, bpm: U32, ticks: U32, tickse: U32, aim: U32, samples: U32, loops: U32}

# speed * ((playrate*5)/(2*bpm)) at 48000 Hz.
def tempo.aim(+speed: U32, +bpm: U32) -> U32:
  (speed * (240000 / (2 * bpm)) : U32)

# jar_mod_load's states: speed 6, 125 beats a minute, the first row due.
def Clock.start() -> Clock:
  Clock{0, 0, 0, 0, 6, 125, (tempo.aim(6, 125) + 1 : U32), 0, tempo.aim(6, 125), 0, 0}

# -----------------------------------------------------------------------------
# worknote

# The fields worknote reads from a note's four bytes.
type Note is Data:
  Note{sample: U32, period: U32, effect: U32}

def Note.of(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> Note:
  Note{((b0 .&. 240) .|. (b2 >> 4n) : U32), (((b0 .&. 15) << 8n) .|. b1 : U32), (((b2 .&. 15) << 8n) .|. b3 : U32)}

# What a step of the player gives: the clock, the channel and why it stopped.
type Worked is Data:
  Worked{clock: Clock, channel: Channel, why: U32}

# fullperiod[getnote(period) + finetune] (finetune 1..7) or
# fullperiod[getnote(period) - (16 - finetune)] (8..15; None below index 0).
def tuned(+m: Mod, +period: U32, +finetune: U32) -> Maybe<U32>:
  +note = getnote(Mod.periods(m), period)
  Bool.pick(Maybe<U32>, (finetune <= 7 : U32), Some{Mod.period(m, (note + finetune : U32))},
    Bool.pick(Maybe<U32>, (note < (16 - finetune) : U32), None{}, Some{Mod.period(m, (note - (16 - finetune) : U32))}))

# The note's sample (number `number`) taken: data, lengths and finetune.
def taken.voice(+m: Mod, +number: U32, +position: U32) -> Voice:
  Voice{Mod.sample(m, number, 5), number, Mod.sample(m, number, 0), Mod.sample(m, number, 3), Mod.sample(m, number, 4), position, (Mod.sample(m, number, 1) .&. 15 : U32)}

# Arpperiods[1] or [2]: fullperiod[min(curnote + x*8, 1151)].
def arp.period(+m: Mod, +note: U32, +x: U32) -> U32:
  Mod.period(m, U32.min((note + x * 8 : U32), 1151))

# The channel with effect and parameffect 0 and effect_code the note's.
def same.of(+voice: Voice, +tone: Tone, +act: Act, +effect: U32) -> Channel:
  Act{_, _, _, +volume, +slide, +cut, +lcount, +lstart} = act
  Channel{voice, tone, Act{0, 0, effect, volume, slide, cut, lcount, lstart}}

def extended.kind(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +effect: U32, +lo: U32, +same: Channel, +sub: U32) -> Worked:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  Tone{+tp, +decal, +portaspeed, +portaperiod, +vibrato, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  Act{_, _, _, +volume, +slide, +cut, +lcount, +lstart} = act
  match sub:
    case 1: Worked{clock, Channel{voice, Tone{U32.max(u16((tp - lo : U32)), 113), decal, portaspeed, portaperiod, vibrato, arp0, arp1, arp2, index, vparam, pointer}, Act{0, 0, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 2: Worked{clock, Channel{voice, Tone{U32.min(u16((tp + lo : U32)), 856), decal, portaspeed, portaperiod, vibrato, arp0, arp1, arp2, index, vparam, pointer}, Act{0, 0, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 10: Worked{clock, Channel{voice, tone, Act{0, 0, effect, U32.min(u8((volume + lo : U32)), 64), slide, cut, lcount, lstart}}, 0}
    case 11: Worked{clock, Channel{voice, tone, Act{0, 0, effect, Bool.pick(U32, (u8((volume - lo : U32)) > 200 : U32), 0, u8((volume - lo : U32))), slide, cut, lcount, lstart}}, 0}
    case 6: Bool.pick(Worked, U32.is_eq(lo, 0),
      Worked{clock, Channel{voice, tone, Act{0, 0, effect, volume, slide, cut, lcount, patternpos}}, 0},
      Bool.pick(Worked, U32.is_eq(lcount, 0),
        Worked{Clock{tablepos, lstart, delay, 1, speed, bpm, ticks, tickse, aim, samples, loops}, Channel{voice, tone, Act{0, 0, effect, volume, slide, cut, lo, lstart}}, 0},
        Bool.pick(Worked, U32.is_ne(u16((lcount - 1 : U32)), 0),
          Worked{Clock{tablepos, lstart, delay, 1, speed, bpm, ticks, tickse, aim, samples, loops}, Channel{voice, tone, Act{0, 0, effect, volume, slide, cut, u16((lcount - 1 : U32)), lstart}}, 0},
          Worked{clock, Channel{voice, tone, Act{0, 0, effect, volume, slide, cut, 0, patternpos}}, 0})))
    case 14: Worked{Clock{tablepos, patternpos, lo, jump, speed, bpm, ticks, tickse, aim, samples, loops}, same, 0}
    case 12: Worked{clock, Channel{voice, tone, Act{12, 0, effect, Bool.pick(U32, U32.is_eq(lo, 0), 0, volume), slide, lo, lcount, lstart}}, 0}
    case _: Worked{clock, same, 0}

def extended.row(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +effect: U32) -> Worked:
  extended.kind(m, clock, voice, tone, act, effect, (effect .&. 15 : U32), same.of(voice, tone, act, effect), ((effect >> 4n) .&. 15 : U32))

# The effects' part of worknote on a channel whose note part is done (`period`
# is the note's period after finetune, `operiod` the channel's before).
def fx.kind(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +period: U32, +operiod: U32, +effect: U32, +x: U32, +hi: U32, +lo: U32, +same: Channel, +which: U32) -> Worked:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  Voice{+data, +number, +length, +reppnt, +replen, +position, +finetune} = voice
  Tone{+tp, +decal, +portaspeed, +portaperiod, +vibrato, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  Act{_, _, _, +volume, +slide, +cut, +lcount, +lstart} = act
  match which:
    case 0: Bool.pick(Worked, U32.is_eq(x, 0), Worked{clock, same, 0},
      Worked{clock, Channel{voice, Tone{tp, decal, portaspeed, portaperiod, vibrato, s16(tp), s16(arp.period(m, getnote(Mod.periods(m), tp), hi)), s16(arp.period(m, getnote(Mod.periods(m), tp), lo)), 0, vparam, pointer}, Act{0, x, effect, volume, slide, cut, lcount, lstart}}, 0})
    case 1: Worked{clock, Channel{voice, tone, Act{1, x, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 2: Worked{clock, Channel{voice, tone, Act{2, x, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 3: Worked{clock, Channel{voice,
      Tone{Bool.pick(U32, U32.is_ne(period, 0), operiod, tp), decal, Bool.pick(U32, U32.is_ne(x, 0), x, portaspeed), Bool.pick(U32, U32.is_ne(period, 0), s16(period), portaperiod), vibrato, arp0, arp1, arp2, index, vparam, pointer},
      Act{3, 0, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 4: Worked{clock, Channel{voice,
      Tone{tp, decal, portaspeed, portaperiod, vibrato, arp0, arp1, arp2, index,
        Bool.pick(U32, U32.is_ne((effect .&. 240 : U32), 0), ((Bool.pick(U32, U32.is_ne(lo, 0), ((vparam .&. 240) .|. lo : U32), vparam) .&. 15) .|. (effect .&. 240) : U32), Bool.pick(U32, U32.is_ne(lo, 0), ((vparam .&. 240) .|. lo : U32), vparam)), pointer},
      Act{4, 0, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 5: Worked{clock, Channel{voice,
      Tone{Bool.pick(U32, U32.is_ne(period, 0), operiod, tp), decal, portaspeed, Bool.pick(U32, U32.is_ne(period, 0), s16(period), portaperiod), vibrato, arp0, arp1, arp2, index, vparam, pointer},
      Act{5, 0, effect, volume, Bool.pick(U32, U32.is_ne(x, 0), x, slide), cut, lcount, lstart}}, 0}
    case 6: Worked{clock, Channel{voice, tone, Act{6, 0, effect, volume, Bool.pick(U32, U32.is_ne(x, 0), x, slide), cut, lcount, lstart}}, 0}
    case 9: Worked{clock, Channel{Voice{data, number, length, reppnt, replen, ((effect >> 4n) * 4096 + lo * 256 : U32), finetune}, tone, Act{0, 0, effect, volume, slide, cut, lcount, lstart}}, 0}
    case 10: Worked{clock, Channel{voice, tone, Act{10, 0, effect, volume, x, cut, lcount, lstart}}, 0}
    case 11: Worked{Clock{Bool.pick(U32, (x >= Mod.length(m) : U32), 0, x), 0, delay, 1, speed, bpm, ticks, tickse, aim, samples, loops}, same, 0}
    case 12: Worked{clock, Channel{voice, tone, Act{0, 0, effect, x, slide, cut, lcount, lstart}}, 0}
    case 13: Worked{Clock{Bool.pick(U32, (u16((tablepos + 1 : U32)) >= Mod.length(m) : U32), 0, u16((tablepos + 1 : U32))), u16(((hi * 10 + lo) * Mod.channels(m) : U32)), delay, 1, speed, bpm, ticks, tickse, aim, samples, loops}, same, 0}
    case 14: extended.row(m, clock, voice, tone, act, effect)
    case 15: Worked{Bool.pick(Clock, (x < 33 : U32),
        Bool.pick(Clock, U32.is_ne(x, 0), Clock{tablepos, patternpos, delay, jump, x, bpm, ticks, tickse, tempo.aim(x, bpm), samples, loops}, clock),
        Clock{tablepos, patternpos, delay, jump, speed, x, ticks, tickse, tempo.aim(speed, x), samples, loops}), same, 0}
    case _: Worked{clock, same, 0}

def fx.row(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +period: U32, +operiod: U32, +effect: U32) -> Worked:
  fx.kind(m, clock, voice, tone, act, period, operiod, effect, (effect .&. 255 : U32), ((effect >> 4n) .&. 15 : U32), (effect .&. 15 : U32), same.of(voice, tone, act, effect), (effect >> 8n : U32))

# cptr->period = period (when nonzero), then the effects.
def nt.period(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +period: U32, +operiod: U32, +effect: U32) -> Worked:
  Tone{+tp, +decal, +portaspeed, +portaperiod, +vibrato, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  fx.row(m, clock, voice, Tone{Bool.pick(U32, U32.is_ne(period, 0), period, tp), decal, portaspeed, portaperiod, vibrato, arp0, arp1, arp2, index, vparam, pointer}, act, period, operiod, effect)

# The note part with the period after finetune (None: an index below 0).
def nt.tuned(+m: Mod, +clock: Clock, +voice: Voice, +tone: Tone, +act: Act, +operiod: U32, +effect: U32, tuned: Maybe<U32>) -> Worked:
  match tuned:
    case None{}: Worked{clock, Channel{voice, tone, act}, 1}
    case Some{+period}: nt.period(m, clock, voice, tone, act, period, operiod, effect)

# The note part: a period or a sample takes the sample's data and lengths;
# the vibrato restarts but under effects 4 and 6; a sample sets the volume
# but under effect 5; a period restarts the sample but under effects 3 and 5;
# decalperiod is 0; the period is tuned by the finetune.
def nt.part(+m: Mod, +clock: Clock, +channel: Channel, +sample: U32, +period: U32, +effect: U32) -> Worked:
  Channel{+voice, +tone, +act} = channel
  Voice{_, +number, _, _, _, +position, _} = voice
  Tone{+tp, +decal, +portaspeed, +portaperiod, +vibrato, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  Act{+e, +p, +code, +volume, +slide, +cut, +lcount, +lstart} = act
  +kind = (effect >> 8n : U32)
  +num = Bool.pick(U32, U32.is_ne(sample, 0) && (sample < 32 : U32), (sample - 1 : U32), number)
  +restart = Bool.pick(U32, U32.is_ne(kind, 3) && U32.is_ne(kind, 5) && U32.is_ne(period, 0), 0, position)
  +fresh = U32.is_ne(kind, 4) && U32.is_ne(kind, 6)
  +sets = U32.is_ne(sample, 0) && U32.is_ne(kind, 5)
  +v = taken.voice(m, num, restart)
  +t = {Tone{tp, 0, portaspeed, portaperiod, Bool.pick(U32, fresh, 0, vibrato), arp0, arp1, arp2, index, vparam, Bool.pick(U32, fresh, 0, pointer)} : Tone}
  +a = {Act{e, p, code, Bool.pick(U32, sets, Mod.sample(m, num, 2), volume), Bool.pick(U32, sets, 0, slide), cut, lcount, lstart} : Act}
  +finetune = (Mod.sample(m, num, 1) .&. 15 : U32)
  Bool.pick(Worked, U32.is_ne(period, 0) && U32.is_ne(finetune, 0),
    nt.tuned(m, clock, v, t, a, tp, effect, tuned(m, period, finetune)),
    nt.period(m, clock, v, t, a, period, tp, effect))

# worknote(note, channel): the note part when the note has a period or a
# sample, then the effects.
def worknote(+m: Mod, +clock: Clock, +channel: Channel, +note: Note) -> Worked:
  Channel{+voice, +tone, +act} = channel
  Tone{+tp, _, _, _, _, _, _, _, _, _, _} = tone
  Note{+sample, +period, +effect} = note
  Bool.pick(Worked, U32.is_ne(period, 0) || U32.is_ne(sample, 0), nt.part(m, clock, channel, sample, period, effect),
    nt.period(m, clock, voice, tone, act, 0, tp, effect))

# -----------------------------------------------------------------------------
# workeffect

# The volume slides of effects 5 (bounded to 63), 6 and 10 (to 64).
def slid.up(+volume: U32, +slide: U32, +top: U32) -> U32:
  U32.min(u8((volume + (slide >> 4n) : U32)), top)

def slid.down(+volume: U32, +amount: U32, +top: U32) -> U32:
  Bool.pick(U32, (u8((volume - amount : U32)) > top : U32), 0, u8((volume - amount : U32)))

# Effects 3 and 5: the period toward portaperiod by portaspeed, portaperiod
# 0 when reached.
def porta(+tone: Tone) -> Tone:
  Tone{+tp, +decal, +speed, +target, +vibrato, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  +moving = U32.is_ne(tp, 0) && U32.is_ne(tp, target) && U32.is_ne(target, 0)
  +down = lt(target, tp)
  +next = Bool.pick(U32, down,
    Bool.pick(U32, lt((tp - target : U32), speed), target, u16((tp - speed : U32))),
    Bool.pick(U32, lt((target - tp : U32), speed), target, u16((tp + speed : U32))))
  Bool.pick(Tone, moving, Tone{next, decal, speed, Bool.pick(U32, U32.is_eq(next, target), 0, target), vibrato, arp0, arp1, arp2, index, vparam, pointer}, tone)

# Effects 4 and 6: vibraperiod from the sine, negated past pointer 31, and
# the pointer's step.
def vibrato.tick(+tone: Tone) -> Tone:
  Tone{+tp, +decal, +speed, +target, _, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  +amount = (((vparam .&. 15) * sine((pointer .&. 31 : U32))) >> 7n : U32)
  Tone{tp, decal, speed, target, s16(Bool.pick(U32, (pointer > 31 : U32), (0 - amount : U32), amount)), arp0, arp1, arp2, index, vparam, ((pointer + ((vparam >> 4n) .&. 15)) .&. 63 : U32)}

def arp.at(+index: U32, +arp0: U32, +arp1: U32, +arp2: U32) -> U32:
  match index:
    case 0: arp0
    case 1: arp1
    case _: arp2

def arp.of(+tone: Tone) -> U32:
  Tone{_, _, _, _, _, +arp0, +arp1, +arp2, +index, _, _} = tone
  arp.at(index, arp0, arp1, arp2)

def workeffect.kind(+channel: Channel, +effect: U32) -> Channel:
  Channel{+voice, +tone, +act} = channel
  Tone{+tp, +decal, +speed, +target, +vib, +arp0, +arp1, +arp2, +index, +vparam, +pointer} = tone
  Act{_, +param, +code, +volume, +slide, +cut, +lcount, +lstart} = act
  match effect:
    case 0: Bool.pick(Channel, U32.is_eq(param, 0), channel,
      Channel{voice, Tone{tp, s16((tp - arp.of(tone) : U32)), speed, target, vib, arp0, arp1, arp2, Bool.pick(U32, (index >= 2 : U32), 0, (index + 1 : U32)), vparam, pointer}, act})
    case 1: Bool.pick(Channel, U32.is_eq(tp, 0), channel,
      Channel{voice, Tone{Bool.pick(U32, (u16((tp - param : U32)) < 113 : U32) || (u16((tp - param : U32)) > 20000 : U32), 113, u16((tp - param : U32))), decal, speed, target, vib, arp0, arp1, arp2, index, vparam, pointer}, act})
    case 2: Bool.pick(Channel, U32.is_eq(tp, 0), channel,
      Channel{voice, Tone{U32.min(u16((tp + param : U32)), 20000), decal, speed, target, vib, arp0, arp1, arp2, index, vparam, pointer}, act})
    case 3: Channel{voice, porta(tone), act}
    case 5: Channel{voice, porta(tone), Act{effect, param, code, Bool.pick(U32, (slide > 15 : U32), slid.up(volume, slide, 63), slid.down(volume, slide, 63)), slide, cut, lcount, lstart}}
    case 4: Channel{voice, vibrato.tick(tone), act}
    case 6: Channel{voice, vibrato.tick(tone), Act{effect, param, code, Bool.pick(U32, (slide > 15 : U32), slid.up(volume, slide, 64), slid.down(volume, slide, 64)), slide, cut, lcount, lstart}}
    case 10: Channel{voice, tone, Act{effect, param, code, Bool.pick(U32, (slide > 15 : U32), slid.up(volume, slide, 64), slid.down(volume, (slide .&. 15 : U32), 64)), slide, cut, lcount, lstart}}
    case 12: Channel{voice, tone, Act{effect, param, code, Bool.pick(U32, U32.is_eq(Bool.pick(U32, U32.is_ne(cut, 0), (cut - 1 : U32), cut), 0), 0, volume), slide, Bool.pick(U32, U32.is_ne(cut, 0), (cut - 1 : U32), cut), lcount, lstart}}
    case _: channel

def workeffect(+channel: Channel) -> Channel:
  Channel{_, _, +act} = channel
  Act{+effect, _, _, _, _, _, _, _} = act
  workeffect.kind(channel, effect)

def workeffects(+channels: +List<Channel>) -> +List<Channel>:
  match channels:
    case Nil{}: Nil{}
    case Con{+c, +rest}: Con{workeffect(c), workeffects(rest)}

# -----------------------------------------------------------------------------
# The player

# The module, the clock, the channels, last_l_sample and last_r_sample, and
# why it stopped (0: it plays).
type Player is Data:
  Player{module: Mod, clock: Clock, channels: +List<Channel>, last_l: U32, last_r: U32, why: U32}

# A loaded module at its start (jar_mod_load's states; jar_mod_seek_start).
def Player.new(+m: Mod) -> Player:
  Player{m, Clock.start(), channels.zero(U32.to_nat(Mod.channels(m))), 0, 0, 0}

def Player.why(+player: Player) -> U32:
  Player{_, _, _, _, _, +why} = player
  why

def Player.samples(+player: Player) -> U32:
  Player{_, +clock, _, _, _, _} = player
  Clock{_, _, _, _, _, _, _, _, _, +samples, _} = clock
  samples

# The channels' notes, from the note at byte `at`, each four bytes on; why 1
# for a note past the file.
type Row is Data:
  RowDone{clock: Clock, channels: +List<Channel>, why: U32}

def Worked.clock(+w: Worked) -> Clock:
  Worked{+clock, _, _} = w
  clock

def Worked.channel(+w: Worked) -> Channel:
  Worked{_, +channel, _} = w
  channel

def Worked.why(+w: Worked) -> U32:
  Worked{_, _, +why} = w
  why

# Every channel's worknote, the done ones in `acc` (last first), and the
# first reason to stop (a note past the file, a worknote that stops): the
# player stops after such a row, so what the later channels did is moot.
def row.notes(+m: Mod, +channels: +List<Channel>, +clock: Clock, +at: U32, +acc: +List<Channel>, +why: U32) -> Row:
  match channels:
    case Nil{}: RowDone{clock, List.reverse(&2, Channel, acc), why}
    case Con{+c, +rest}:
      +w = worknote(m, clock, c, Note.of(Mod.byte(m, at), Mod.byte(m, (at + 1 : U32)), Mod.byte(m, (at + 2 : U32)), Mod.byte(m, (at + 3 : U32))))
      row.notes(m, rest, Worked.clock(w), (at + 4 : U32), Con{Worked.channel(w), acc},
        Bool.pick(U32, U32.is_ne(why, 0), why, Bool.pick(U32, ((at + 3) >= Mod.size(m) : U32), 1, Worked.why(w))))

# The row's end: patternpos advances (or the jump is taken), and after the
# pattern's last row the next table position, wrapping (and counting a loop)
# past the song's length.
def row.ended(+m: Mod, +clock: Clock) -> Clock:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  +pos = Bool.pick(U32, U32.is_eq(jump, 0), u16((patternpos + Mod.channels(m) : U32)), patternpos)
  +end = U32.is_eq(pos, (64 * Mod.channels(m) : U32))
  +next = u16((tablepos + 1 : U32))
  +wrap = (next >= Mod.length(m) : U32)
  Bool.pick(Clock, end,
    Clock{Bool.pick(U32, wrap, 0, next), 0, delay, 0, speed, bpm, ticks, tickse, aim, samples, Bool.pick(U32, wrap, (loops + 1 : U32), loops)},
    Clock{tablepos, pos, delay, 0, speed, bpm, ticks, tickse, aim, samples, loops})

def row.done(+m: Mod, +rows: Row) -> Row:
  RowDone{+clock, +channels, +why} = rows
  RowDone{row.ended(m, clock), channels, why}

# A new row (patterndelay 0): every channel's note from
# patterndata[patterntable[tablepos]] + patternpos; why 1 for a table position
# past patterntable[128].
def row.play(+m: Mod, +clock: Clock, +channels: +List<Channel>, +at: U32, outside: Bool) -> Row:
  match outside:
    case True{}: RowDone{clock, channels, 1}
    case False{}: row.done(m, row.notes(m, channels, clock, at, Nil{}, 0))

def row.start(+m: Mod, +clock: Clock, +channels: +List<Channel>) -> Row:
  Clock{+tablepos, +patternpos, _, _, _, _, _, _, _, _, _} = clock
  row.play(m, clock, channels, (Mod.pattern(m, Mod.entry(m, U32.min(tablepos, 127))) + patternpos * 4 : U32), (tablepos >= 128 : U32))

# if (patternticks++ > patternticksaim): a row, or a delayed one.
def tick.row.at(+m: Mod, +clock: Clock, +channels: +List<Channel>, +code: U32) -> Row:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  match code:
    case 0: row.start(m, Clock{tablepos, patternpos, delay, jump, speed, bpm, 0, 0, aim, samples, loops}, channels)
    case 1: RowDone{Clock{tablepos, patternpos, (delay - 1 : U32), jump, speed, bpm, 0, 0, aim, samples, loops}, channels, 0}
    case _: RowDone{Clock{tablepos, patternpos, delay, jump, speed, bpm, (ticks + 1 : U32), tickse, aim, samples, loops}, channels, 0}

def tick.row(+m: Mod, +clock: Clock, +channels: +List<Channel>) -> Row:
  Clock{_, _, +delay, _, _, _, +ticks, _, +aim, _, _} = clock
  tick.row.at(m, clock, channels, Bool.pick(U32, (ticks > aim : U32), Bool.pick(U32, U32.is_eq(delay, 0), 0, 1), 2))

# if (patterntickse++ > patternticksaim/speed): every channel's effect
# (jar_mod reads patterntable[tablepos] there too: why 1 past its 128).
def tick.effects(+rows: Row) -> Row:
  RowDone{+clock, +channels, +why} = rows
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  Bool.pick(Row, (tickse > (aim / speed) : U32),
    RowDone{Clock{tablepos, patternpos, delay, jump, speed, bpm, ticks, 0, aim, samples, loops}, workeffects(channels), Bool.pick(U32, U32.is_ne(why, 0), why, Bool.pick(U32, (tablepos >= 128 : U32), 1, 0))},
    RowDone{Clock{tablepos, patternpos, delay, jump, speed, bpm, ticks, (tickse + 1 : U32), aim, samples, loops}, channels, why})

# (sampleticksconst<<10)/finalperiod: 73<<10 at 48000 Hz over a positive
# finalperiod; nothing for 0, and 0 for a negative one (C converts it to a
# huge unsigned long).
def step.of(+final: U32, positive: Bool) -> U32:
  match positive:
    case True{}: (74752 / final : U32)
    case False{}: 0

# samppos past the repeat's end: (reppnt<<10) + samppos % ((replen + reppnt)<<10).
def wrap.of(+reppnt: U32, +moved: U32, +limit: U32, past: Bool) -> U32:
  match past:
    case True{}: ((reppnt << 10n) + (moved % (limit << 10n)) : U32)
    case False{}: moved

# A channel's sample position for one output sample: the step, then past the
# sample's end back to 0 (a repeat length of 2 or less: the length and
# repeat point become 0) or into the repeat.
def stepped.voice(+voice: Voice, +final: U32) -> Voice:
  Voice{+data, +number, +length, +reppnt, +replen, +position, +finetune} = voice
  +moved = (position + step.of(final, U32.is_ne(final, 0) && Bool.not(lt(final, 0))) : U32)
  +limit = (replen + reppnt : U32)
  Bool.pick(Voice, (replen <= 2 : U32),
    Bool.pick(Voice, ((moved >> 10n) >= length : U32), Voice{data, number, 0, 0, replen, 0, finetune}, Voice{data, number, length, reppnt, replen, moved, finetune}),
    Voice{data, number, length, reppnt, replen, wrap.of(reppnt, moved, limit, (replen > 2 : U32) && ((moved >> 10n) >= limit : U32)), finetune})

# The left and right sums, the channels after the step and why it stopped.
type Mixed is Data:
  Mixed{left: U32, right: U32, channels: +List<Channel>, why: U32}

# A channel after its step: the byte at sampdata[samppos>>10] times the
# volume goes left (channels 0 and 3 of each four) or right (1 and 2); why 1
# for a byte past the file.
def mix.voice(+m: Mod, +j: U32, +tone: Tone, +act: Act, +stepped: Voice, +volume: U32, +rest: Mixed) -> Mixed:
  Voice{+data, _, _, _, _, +position, _} = stepped
  Mixed{+l, +r, +channels, +why} = rest
  +at = (data + (position >> 10n) : U32)
  +inside = (U32.is_eq(data, 0) || (at < Mod.size(m) : U32))
  +value = Bool.pick(U32, U32.is_eq(data, 0) || Bool.not(inside), 0, (s8(Mod.byte(m, at)) * volume : U32))
  +right = U32.is_eq((j .&. 3 : U32), 1) || U32.is_eq((j .&. 3 : U32), 2)
  Mixed{Bool.pick(U32, right, l, (l + value : U32)), Bool.pick(U32, right, (r + value : U32), r), Con{Channel{stepped, tone, act}, channels}, Bool.pick(U32, inside, why, 1)}

def mix.kept(+channel: Channel, +rest: Mixed) -> Mixed:
  Mixed{+l, +r, +channels, +why} = rest
  Mixed{l, r, Con{channel, channels}, why}

def mix.channel(+m: Mod, +j: U32, +channel: Channel, +rest: Mixed) -> Mixed:
  Channel{+voice, +tone, +act} = channel
  Tone{+tp, +decal, _, _, +vib, _, _, _, _, _, _} = tone
  Act{_, _, _, +volume, _, _, _, _} = act
  Bool.pick(Mixed, U32.is_eq(tp, 0), mix.kept(channel, rest),
    mix.voice(m, j, tone, act, stepped.voice(voice, s16((tp - decal - vib : U32))), volume, rest))

def mix.ordered(+acc: Mixed) -> Mixed:
  Mixed{+l, +r, +channels, +why} = acc
  Mixed{l, r, List.reverse(&2, Channel, channels), why}

# Every channel with a period, the stepped ones in the result last first.
def mix.all(+m: Mod, +channels: +List<Channel>, +j: U32, +acc: Mixed) -> Mixed:
  match channels:
    case Nil{}: mix.ordered(acc)
    case Con{+c, +rest}: mix.all(m, rest, (j + 1 : U32), mix.channel(m, j, c, acc))

def clamp(+x: U32) -> U32:
  Bool.pick(U32, lt(32767, x), 32767, Bool.pick(U32, lt(x, (0 - 32768 : U32)), (0 - 32768 : U32), x))

# A step's result: the player and the sample's two words (shorts, sign-extended).
type Sampled is Data:
  Sampled{player: Player, left: U32, right: U32}

# The output sample from the sums: (short) of each kept for the next
# filter, the filter (l + ll)>>1, the stereo separation l += r>>1 then
# r += l>>1, and the bounds of a short.
def sample.out(+m: Mod, +clock: Clock, +ll: U32, +lr: U32, +mixed: Mixed) -> Sampled:
  Mixed{+l, +r, +channels, +why} = mixed
  +fl = sar1((l + ll : U32))
  +fr = sar1((r + lr : U32))
  +sl = (fl + sar1(fr) : U32)
  +sr = (fr + sar1(sl) : U32)
  Sampled{Player{m, clock, channels, s16(l), s16(r), why}, clamp(sl), clamp(sr)}

def sample.effects(+m: Mod, +ll: U32, +lr: U32, +rows: Row) -> Sampled:
  RowDone{+clock, +channels, +why} = rows
  Bool.pick(Sampled, U32.is_ne(why, 0), Sampled{Player{m, clock, channels, ll, lr, why}, 0, 0},
    sample.out(m, clock, ll, lr, mix.all(m, channels, 0, Mixed{0, 0, Nil{}, 0})))

# One output sample of jar_mod_fillbuffer: the row tick, the effect tick,
# then the channels' mix (a stopped player gives 0 and stays).
def Player.sample(+player: Player) -> Sampled:
  Player{+m, +clock, +channels, +ll, +lr, +why} = player
  Bool.pick(Sampled, U32.is_ne(why, 0), Sampled{player, 0, 0},
    sample.effects(m, ll, lr, tick.effects(tick.row(m, clock, channels))))

# samplenb += nbsample after a buffer.
def Player.counted(+player: Player, +count: U32) -> Player:
  Player{+m, +clock, +channels, +ll, +lr, +why} = player
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  Player{m, Clock{tablepos, patternpos, delay, jump, speed, bpm, ticks, tickse, aim, (samples + count : U32), loops}, channels, ll, lr, why}

# jar_mod_fillbuffer(count): `count` stereo samples, left then right, as
# 16-bit words; the player after them.
type Filled is Data:
  Filled{player: Player, words: +List<U32>}

def Sampled.player(+s: Sampled) -> Player:
  Sampled{+player, _, _} = s
  player

def Sampled.left(+s: Sampled) -> U32:
  Sampled{_, +l, _} = s
  l

def Sampled.right(+s: Sampled) -> U32:
  Sampled{_, _, +r} = s
  r

def fill.go(n: Nat, +player: Player, +acc: +List<U32>) -> Filled:
  match n:
    case 0n: Filled{player, List.reverse(&2, U32, acc)}
    case 1n+k:
      +s = Player.sample(player)
      fill.go(k, Sampled.player(s), Con{u16(Sampled.right(s)), Con{u16(Sampled.left(s)), acc}})

def fill.done(+count: U32, +filled: Filled) -> Filled:
  Filled{+player, +words} = filled
  Filled{Player.counted(player, count), words}

def Player.fill(+player: Player, +count: U32) -> Filled:
  fill.done(count, fill.go(U32.to_nat(count), player, Nil{}))

# jar_mod_max_samples, by rows: the first row is due at sample 0, and each
# row (or delayed row) the next one patternticksaim + 2 samples later, with
# patternticksaim as the row left it; the count ends with the sample whose
# row wraps the song past its length (loopcount grows): that row's time + 1.
# Only rows change the clock and the pattern loops, so the samples between
# them are not played. A song whose timing state (the clock and each
# channel's pattern loop) comes back without the song wrapping never ends in
# raylib (its count loops forever): why 2, found by Brent's cycle search, or
# past 2^20 rows. A row that reads past the file or the pattern table: why 1.
type Counted is Data:
  Counted{samples: U32, why: U32}

def timing.channel(+c: Channel, +acc: +List<U32>) -> +List<U32>:
  Channel{_, _, +act} = c
  Act{_, _, _, _, _, _, +loops, +start} = act
  Con{loops, Con{start, acc}}

# The timing state as words.
def timing.channels(+channels: +List<Channel>, +acc: +List<U32>) -> +List<U32>:
  match channels:
    case Nil{}: acc
    case Con{+c, +rest}: timing.channels(rest, timing.channel(c, acc))

def timing.of(+clock: Clock, +channels: +List<Channel>) -> +List<U32>:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, _, _, +aim, _, _} = clock
  Con{tablepos, Con{patternpos, Con{delay, Con{jump, Con{speed, Con{bpm, Con{aim, timing.channels(channels, Nil{})}}}}}}}

def words.same(+a: +List<U32>, +b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{+x, +xs} Con{+y, +ys}: U32.is_eq(x, y) && words.same(xs, ys)
    case _ _: False{}

def Clock.loops(+clock: Clock) -> U32:
  Clock{_, _, _, _, _, _, _, _, _, _, +loops} = clock
  loops

def Clock.aim(+clock: Clock) -> U32:
  Clock{_, _, _, _, _, _, _, _, +aim, _, _} = clock
  aim

def Clock.delay(+clock: Clock) -> U32:
  Clock{_, _, +delay, _, _, _, _, _, _, _, _} = clock
  delay

def Row.clock(+rows: Row) -> Clock:
  RowDone{+clock, _, _} = rows
  clock

def Row.channels(+rows: Row) -> +List<Channel>:
  RowDone{_, +channels, _} = rows
  channels

def Row.why(+rows: Row) -> U32:
  RowDone{_, _, +why} = rows
  why

def rows.delayed(+clock: Clock, +channels: +List<Channel>) -> Row:
  Clock{+tablepos, +patternpos, +delay, +jump, +speed, +bpm, +ticks, +tickse, +aim, +samples, +loops} = clock
  RowDone{Clock{tablepos, patternpos, (delay - 1 : U32), jump, speed, bpm, ticks, tickse, aim, samples, loops}, channels, 0}

# One trigger: a row when patterndelay is 0, else patterndelay - 1.
def rows.trigger(+m: Mod, +clock: Clock, +channels: +List<Channel>, delayed: Bool) -> Row:
  match delayed:
    case False{}: row.start(m, clock, channels)
    case True{}: rows.delayed(clock, channels)

# The count from the trigger at sample `time` (`at`: the last trigger's):
# `saved` is Brent's saved timing state, `power` and `length` its window and
# the steps since; code 0 goes on, 3 is the song wrapped at `at`, another is
# why it has no length.
def rows.count(n: Nat, +m: Mod, +clock: Clock, +channels: +List<Channel>, +time: U32, +at: U32, +saved: +List<U32>, +power: U32, +length: U32, +code: U32) -> Counted:
  match n code:
    case _ 3: Counted{(at + 1 : U32), 0}
    case 0n 0: Counted{0, 2}
    case 1n+k 0:
      +done = rows.trigger(m, clock, channels, U32.is_ne(Clock.delay(clock), 0))
      +state = timing.of(Row.clock(done), Row.channels(done))
      +restart = U32.is_eq(length, power)
      rows.count(k, m, Row.clock(done), Row.channels(done), (time + Clock.aim(Row.clock(done)) + 2 : U32), time,
        Bool.pick(+List<U32>, restart, state, saved), Bool.pick(U32, restart, (power * 2 : U32), power), Bool.pick(U32, restart, 1, (length + 1 : U32)),
        Bool.pick(U32, U32.is_ne(Row.why(done), 0), Row.why(done), Bool.pick(U32, U32.is_ne(Clock.loops(Row.clock(done)), 0), 3, Bool.pick(U32, words.same(state, saved), 2, 0))))
    case _ _: Counted{0, code}

def Player.max_samples(+m: Mod) -> Counted:
  rows.count(1048576n, m, Clock.start(), channels.zero(U32.to_nat(Mod.channels(m))), 0, 0, Nil{}, 1, 0, 0)

def Player.module(+player: Player) -> Mod:
  Player{+m, _, _, _, _, _} = player
  m

# The bytes' count (raudio loads 1 byte to 32 MiB).
def count.bytes(+bytes: +List<U32>) -> U32:
  R.count.words(bytes, 0)
