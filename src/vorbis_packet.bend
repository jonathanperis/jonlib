# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.2 vendors it in src/external/stb_vorbis.c: the
# decoding of an audio packet (vorbis_decode_packet: vorbis_decode_initial
# and vorbis_decode_packet_rest, with predict_point). See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# C ints are U32 two's-complement words. The reader's error 1001 is this
# port's refusal of what C leaves undefined: a packet that meets it is not
# decoded, and neither is anything after it.
import Base
import ../jonmath.bend as Mth
import ./vorbis_ogg.bend as O
import ./vorbis_codebook.bend as C
import ./vorbis_setup.bend as S
import ./vorbis_maps.bend as M
import ./vorbis_tables.bend as T
import ./vorbis_decode.bend as D
import ./vorbis_mdct.bend as X
import ./vorbis_residue.bend as Rs
import ./vorbis_floor.bend as F
import ./store.bend as R

# What the setup gives and no packet changes: the channels, the two block
# sizes, the codebooks ready to decode with, the floors, residues, mappings
# and modes, the transform's tables for each block size and
# inverse_db_table.
type Plan is Data:
  Plan{channels: U32, blocksize_0: U32, blocksize_1: U32, coders: +List<D.Coder>, floors: +List<M.Floor>, residues: +List<M.Residue>, mappings: +List<M.Mapping>, modes: +List<M.Mode>, short: X.Factors, long: X.Factors,
    table: R.Row}

def Plan.channels(plan: Plan) -> U32:
  Plan{channels, _, _, _, _, _, _, _, _, _, _} = plan
  channels

def Plan.blocksize_0(plan: Plan) -> U32:
  Plan{_, blocksize_0, _, _, _, _, _, _, _, _, _} = plan
  blocksize_0

def Plan.blocksize_1(plan: Plan) -> U32:
  Plan{_, _, blocksize_1, _, _, _, _, _, _, _, _} = plan
  blocksize_1

def Plan.coders(plan: Plan) -> +List<D.Coder>:
  Plan{_, _, _, coders, _, _, _, _, _, _, _} = plan
  coders

def Plan.floors(plan: Plan) -> +List<M.Floor>:
  Plan{_, _, _, _, floors, _, _, _, _, _, _} = plan
  floors

def Plan.residues(plan: Plan) -> +List<M.Residue>:
  Plan{_, _, _, _, _, residues, _, _, _, _, _} = plan
  residues

def Plan.mappings(plan: Plan) -> +List<M.Mapping>:
  Plan{_, _, _, _, _, _, mappings, _, _, _, _} = plan
  mappings

def Plan.modes(plan: Plan) -> +List<M.Mode>:
  Plan{_, _, _, _, _, _, _, modes, _, _, _} = plan
  modes

def Plan.short(plan: Plan) -> X.Factors:
  Plan{_, _, _, _, _, _, _, _, short, _, _} = plan
  short

def Plan.long(plan: Plan) -> X.Factors:
  Plan{_, _, _, _, _, _, _, _, _, long, _} = plan
  long

def Plan.table(plan: Plan) -> R.Row:
  Plan{_, _, _, _, _, _, _, _, _, _, table} = plan
  table

# What a packet changes: the reader, the channels' floats (channel_buffers,
# blocksize_1 each: what a packet leaves in them is there for the next),
# the sample position of the next block (current_loc), whether it is known
# (current_loc_valid) and how many samples are still to be dropped
# (discard_samples_deferred).
type State is Data:
  State{reader: O.Reader, rows: +List<R.Row>, loc: U32, known: Bool, discard: U32}

def State.reader(state: State) -> O.Reader:
  State{reader, _, _, _, _} = state
  reader

def State.rows(state: State) -> +List<R.Row>:
  State{_, rows, _, _, _} = state
  rows

# -----------------------------------------------------------------------------
# Small things

def head(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, _}: x

def nth(xs: +List<U32>, +i: U32) -> U32:
  head(List.drop(&2, U32, xs, U32.to_nat(i)))

def counted(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

# An int kept in an int16, as an int again.
def s16(+a: U32) -> U32:
  Bool.pick(U32, U32.is_ne((a .&. 32768 : U32), 0), ((a .&. 65535) .|. 4294901760 : U32), (a .&. 65535 : U32))

# a < b as ints.
def under(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

# a >> 1 of an int: the sign stays.
def halved(+a: U32) -> U32:
  ((a >> 1n) .|. (a .&. 2147483648) : U32)

# predict_point(x, x0, x1, y0, y1): the line from (x0, y0) to (x1, y1) at
# x, by integers: y0 and |dy|*(x - x0)/adx toward y1.
def predict(+x: U32, +x0: U32, +x1: U32, +y0: U32, +y1: U32) -> U32:
  Bool.pick(U32, F.negative((y1 - y0 : U32)), (y0 - ((F.magnitude((y1 - y0 : U32)) * (x - x0)) / U32.max((x1 - x0 : U32), 1)) : U32), (y0 + ((F.magnitude((y1 - y0 : U32)) * (x - x0)) / U32.max((x1 - x0 : U32), 1)) : U32))

# -----------------------------------------------------------------------------
# vorbis_decode_initial

# The packet's mode and its windows: where the block's left part begins and
# ends and where its right part does, in samples of the block. `fine` is the
# C answer.
type Initial is Data:
  Initial{reader: O.Reader, fine: Bool, mode: U32, left_start: U32, left_end: U32, right_start: U32, right_end: U32}

# A packet whose first bit is set is not audio: it is read to its end and
# the next one is looked at. The reader's answer: 0 looking, 1 an audio
# packet is begun, 2 there is none (the data ended, or a packet did not
# begin).
def audio.kind(audio: Bool, +reader: O.Reader) -> O.Reader:
  match audio:
    case True{}: O.Reader.answer(reader, 1)
    case False{}: O.Reader.answer(O.bits.dropped(O.flush.packet(reader)), 0)

def audio.bit(+reader: O.Reader) -> O.Reader:
  audio.kind(U32.is_eq(O.Reader.value(reader), 0), reader)

def audio.begun(began: Bool, +reader: O.Reader) -> O.Reader:
  match began:
    case False{}: O.Reader.answer(reader, 2)
    case True{}: audio.bit(O.bits.get(1, reader))

def audio.started(+reader: O.Reader) -> O.Reader:
  audio.begun(U32.is_eq(O.Reader.value(reader), 1), reader)

def audio.try(ended: Bool, +reader: O.Reader) -> O.Reader:
  match ended:
    case True{}: O.Reader.answer(reader, 2)
    case False{}: audio.started(O.packet.maybe(reader))

def audio.tail(n: Nat, on: Bool, +reader: O.Reader) -> O.Reader:
  match n on:
    case _ False{}: reader
    case 0n True{}: O.Reader.answer(reader, 2)
    case 1n+k True{}:
      +next = audio.try(O.Stream.eof(O.Reader.stream(reader)), reader)
      audio.tail(k, U32.is_eq(O.Reader.value(next), 0), next)

# A packet that is passed over takes a segment at least: the data's bytes
# outlast the packets.
def audio.loop(fuel: +List<U32>, on: Bool, +reader: O.Reader) -> O.Reader:
  match fuel on:
    case _ False{}: reader
    case Nil{} True{}: audio.tail(600n, True{}, reader)
    case Con{_, +more} True{}:
      +next = audio.try(O.Stream.eof(O.Reader.stream(reader)), reader)
      audio.loop(more, U32.is_eq(O.Reader.value(next), 0), next)

def mode.at(modes: +List<M.Mode>) -> M.Mode:
  match modes:
    case Nil{}: M.Mode{0, 0}
    case Con{+m, _}: m

def Mode.blockflag(mode: M.Mode) -> U32:
  M.Mode{blockflag, _} = mode
  blockflag

def Mode.mapping(mode: M.Mode) -> U32:
  M.Mode{_, mapping} = mode
  mapping

def count.modes(modes: +List<M.Mode>, +n: U32) -> U32:
  match modes:
    case Nil{}: n
    case Con{_, +rest}: count.modes(rest, (n + 1 : U32))

# The windows of a block of n samples: a long block next to a short one
# has the short block's slope in its middle; otherwise the slope is half
# the block.
def initial.windows(+reader: O.Reader, +mode: U32, +long: Bool, +n: U32, +small: U32, +prev: U32, +next: U32) -> Initial:
  Initial{reader, True{}, mode, Bool.pick(U32, long && U32.is_eq(prev, 0), ((n - small) >> 2n : U32), 0), Bool.pick(U32, long && U32.is_eq(prev, 0), ((n + small) >> 2n : U32), (n >> 1n : U32)),
    Bool.pick(U32, long && U32.is_eq(next, 0), (((n * 3) - small) >> 2n : U32), (n >> 1n : U32)), Bool.pick(U32, long && U32.is_eq(next, 0), (((n * 3) + small) >> 2n : U32), n)}

# A long block says in two bits whether the blocks before and after it are
# long too.
def initial.flags(long: Bool, +reader: O.Reader, +mode: U32, +plan: Plan) -> Initial:
  match long:
    case False{}: initial.windows(reader, mode, False{}, Plan.blocksize_0(plan), Plan.blocksize_0(plan), 0, 0)
    case True{}: initial.windows(O.bits.get(1, O.bits.get(1, reader)), mode, True{}, Plan.blocksize_1(plan), Plan.blocksize_0(plan), O.Reader.value(O.bits.get(1, reader)), O.Reader.value(O.bits.get(1, O.bits.get(1, reader))))

# The mode's number, in as many bits as the last mode's takes; a number
# that is no mode is the end.
def initial.mode(known: Bool, +reader: O.Reader, +plan: Plan) -> Initial:
  match known:
    case False{}: Initial{reader, False{}, 0, 0, 0, 0, 0}
    case True{}: initial.flags(U32.is_ne(Mode.blockflag(mode.at(List.drop(&2, M.Mode, Plan.modes(plan), U32.to_nat(O.Reader.value(reader))))), 0), reader, O.Reader.value(reader), plan)

def initial.moded(+reader: O.Reader, +plan: Plan) -> Initial:
  initial.mode((O.Reader.value(reader) < count.modes(Plan.modes(plan), 0) : U32), reader, plan)

def initial.audio(found: Bool, +reader: O.Reader, +plan: Plan) -> Initial:
  match found:
    case False{}: Initial{reader, False{}, 0, 0, 0, 0, 0}
    case True{}: initial.moded(O.bits.get(C.ilog((count.modes(Plan.modes(plan), 0) - 1 : U32)), reader), plan)

def initial.looked(+reader: O.Reader, +plan: Plan) -> Initial:
  initial.audio(U32.is_eq(O.Reader.value(reader), 1), reader, plan)

# vorbis_decode_initial: the next audio packet's mode and windows.
def initial.read(+reader: O.Reader, +plan: Plan) -> Initial:
  initial.looked(audio.loop(O.Stream.rest(O.Reader.stream(reader)), True{}, reader), plan)

# -----------------------------------------------------------------------------
# A channel's floor: its points' Y values

# The reader with the Y values read so far, the last first.
type Ys is Data:
  Ys{reader: O.Reader, values: +List<U32>}

def Ys.reader(ys: Ys) -> O.Reader:
  Ys{reader, _} = ys
  reader

def Ys.values(ys: Ys) -> +List<U32>:
  Ys{_, values} = ys
  values

def point.decoded(+reader: O.Reader, +values: +List<U32>) -> Ys:
  Ys{reader, Con{s16(O.Reader.value(reader)), values}}

# A point's value: a symbol of its subclass's codebook, kept in an int16,
# or 0 where the subclass has no codebook.
def point.booked(none: Bool, +book: U32, +coders: +List<D.Coder>, +reader: O.Reader, +values: +List<U32>) -> Ys:
  match none:
    case True{}: Ys{reader, Con{0, values}}
    case False{}: point.decoded(D.decode.symbol(D.coder.at(coders, book), reader), values)

def point.read(+book: U32, +coders: +List<D.Coder>, +ys: Ys) -> Ys:
  point.booked(U32.is_eq(book, 4294967295), book, coders, Ys.reader(ys), Ys.values(ys))

# cval >> cbits of an int that is a symbol's number or -1 (no symbol),
# which stays -1.
def shifted(+cval: U32, +cbits: U32) -> U32:
  Bool.pick(U32, U32.is_eq(cval, 4294967295), 4294967295, (cval >> U32.to_nat(U32.min(cbits, 31)) : U32))

# A partition's points: each one's subclass is the next `cbits` bits of the
# class value.
def points.read(n: Nat, +cval: U32, +cbits: U32, +books: +List<U32>, +coders: +List<D.Coder>, +ys: Ys) -> Ys:
  match n:
    case 0n: ys
    case 1n+k: points.read(k, shifted(cval, cbits), cbits, books, coders, point.read(nth(books, (cval .&. ((1 << U32.to_nat(U32.min(cbits, 31))) - 1) : U32)), coders, ys))

def class.valued(+reader: O.Reader, +dimensions: U32, +cbits: U32, +books: +List<U32>, +coders: +List<D.Coder>, +values: +List<U32>) -> Ys:
  points.read(U32.to_nat(dimensions), O.Reader.value(reader), cbits, books, coders, Ys{reader, values})

def class.value(plain: Bool, +masterbook: U32, +coders: +List<D.Coder>, +reader: O.Reader) -> O.Reader:
  match plain:
    case True{}: O.Reader.answer(reader, 0)
    case False{}: D.decode.symbol(D.coder.at(coders, masterbook), reader)

# A partition: its class's value (a symbol of the masterbook, where the
# class has subclasses; 0 otherwise), then its points.
def partition.read(class: M.Class, +coders: +List<D.Coder>, +ys: Ys) -> Ys:
  M.Class{+dimensions, +subclasses, +masterbook, +books} = class
  class.valued(class.value(U32.is_eq(subclasses, 0), masterbook, coders, Ys.reader(ys)), dimensions, subclasses, books, coders, Ys.values(ys))

def class.at(classes: +List<M.Class>) -> M.Class:
  match classes:
    case Nil{}: M.Class{1, 0, 0, Nil{}}
    case Con{+c, _}: c

def partitions.read(partitions: +List<U32>, +classes: +List<M.Class>, +coders: +List<D.Coder>, +ys: Ys) -> Ys:
  match partitions:
    case Nil{}: ys
    case Con{+number, +rest}: partitions.read(rest, classes, coders, partition.read(class.at(List.drop(&2, M.Class, classes, U32.to_nat(number))), coders, ys))

# The Y values as they are worked out, and which points have one of their
# own (step2_flag).
type Amp is Data:
  Amp{y: R.Index, used: R.Index}

def Amp.y(amp: Amp) -> R.Index:
  Amp{y, _} = amp
  y

def used.set(+used: R.Index, +low: U32, +high: U32, +j: U32) -> R.Index:
  R.Index.set(R.Index.set(R.Index.set(used, low, 1), high, 1), j, 1)

# A point from the third on: `pred` is where the line between its two
# neighbours passes; its value says how far from there it is, to one side
# or the other by turns while there is room on both, and to the roomier
# side past that. A value of 0 is the line's height, and the point is not
# one of its own.
def amp.valued(+amp: Amp, +j: U32, +low: U32, +high: U32, +range: U32, +pred: U32) -> Amp:
  Amp{+y, +used} = amp
  +val = R.Index.get(y, j)
  +highroom = (range - pred : U32)
  +room = (Bool.pick(U32, under(highroom, pred), highroom, pred) * 2 : U32)
  Amp{R.Index.set(y, j, s16(Bool.pick(U32, U32.is_eq(val, 0), pred,
      Bool.pick(U32, under(val, room), Bool.pick(U32, U32.is_ne((val .&. 1 : U32), 0), (pred - halved((val + 1 : U32)) : U32), (pred + halved(val) : U32)),
        Bool.pick(U32, under(pred, highroom), ((val - pred) + pred : U32), (((pred - val) + highroom) - 1 : U32)))))),
    Bool.pick(R.Index, U32.is_eq(val, 0), R.Index.set(used, j, 0), used.set(used, low, high, j))}

def amp.point(+amp: Amp, +j: U32, +low: U32, +high: U32, +range: U32, +xs: R.Index) -> Amp:
  amp.valued(amp, j, low, high, range, predict(R.Index.get(xs, j), R.Index.get(xs, low), R.Index.get(xs, high), R.Index.get(Amp.y(amp), low), R.Index.get(Amp.y(amp), high)))

def amp.each(lows: +List<U32>, highs: +List<U32>, +j: U32, +range: U32, +xs: R.Index, +amp: Amp) -> Amp:
  match lows highs:
    case Con{+low, +more} Con{+high, +rest}: amp.each(more, rest, (j + 1 : U32), range, xs, amp.point(amp, j, low, high, range, xs))
    case _ _: amp

# finalY: a point's value, or -1 for a point that is not one of its own.
def ys.listed(n: Nat, +j: U32, +y: R.Index, +used: R.Index, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: ys.listed(k, (j + 1 : U32), y, used, Con{Bool.pick(U32, U32.is_eq(R.Index.get(used, j), 0), 4294967295, R.Index.get(y, j)), acc})

def ys.final(amp: Amp, +count: U32) -> +List<U32>:
  Amp{y, used} = amp
  ys.listed(U32.to_nat(count), 0, y, used, Nil{})

# A channel's floor in a packet: its points' Y values (finalY), or `zero`
# where the packet has none for the channel: its bit for the floor is
# clear, or the packet ended in the values.
type Floored is Data:
  Floored{reader: O.Reader, ys: +List<U32>, zero: Bool}

# The values read (the last first, two of them before the partitions'),
# made the points' Y values.
def Floor.xs(floor: M.Floor) -> +List<U32>:
  M.Floor{_, _, _, _, xs, _, _, _} = floor
  xs

def Floor.lows(floor: M.Floor) -> +List<U32>:
  M.Floor{_, _, _, _, _, _, lows, _} = floor
  lows

def Floor.highs(floor: M.Floor) -> +List<U32>:
  M.Floor{_, _, _, _, _, _, _, highs} = floor
  highs

def floor.valued(ended: Bool, +ys: Ys, +floor: M.Floor, +range: U32, +old: +List<U32>) -> Floored:
  match ended:
    case True{}: Floored{Ys.reader(ys), old, True{}}
    case False{}: Floored{Ys.reader(ys), ys.final(amp.each(Floor.lows(floor), Floor.highs(floor), 2, range, R.Index.from(Floor.xs(floor), 0),
      Amp{R.Index.from(List.reverse(&2, U32, Ys.values(ys)), 0), R.Index.set(R.Index.set(R.Index.new(8, 0), 0, 1), 1, 1)}), counted(Floor.xs(floor), 0)), False{}}

def floor.parted(+ys: Ys, +floor: M.Floor, +range: U32, +old: +List<U32>) -> Floored:
  floor.valued(U32.is_eq(O.Packet.valid(O.Reader.packet(Ys.reader(ys))), 4294967295), ys, floor, range, old)

# The floor's range by its multiplier: 256, 128, 86 or 64.
def range.of(+multiplier: U32) -> U32:
  Bool.pick(U32, U32.is_eq(multiplier, 1), 256, Bool.pick(U32, U32.is_eq(multiplier, 2), 128, Bool.pick(U32, U32.is_eq(multiplier, 3), 86, 64)))

def Floor.multiplier(floor: M.Floor) -> U32:
  M.Floor{_, _, multiplier, _, _, _, _, _} = floor
  multiplier

def Floor.partitions(floor: M.Floor) -> +List<U32>:
  M.Floor{partitions, _, _, _, _, _, _, _} = floor
  partitions

def Floor.classes(floor: M.Floor) -> +List<M.Class>:
  M.Floor{_, classes, _, _, _, _, _, _} = floor
  classes

# The first two points' values, in the bits the range's last value takes,
# then the partitions'.
def floor.present(present: Bool, +reader: O.Reader, +floor: M.Floor, +coders: +List<D.Coder>, +old: +List<U32>) -> Floored:
  match present:
    case False{}: Floored{reader, old, True{}}
    case True{}:
      +first = O.bits.get((C.ilog(range.of(Floor.multiplier(floor))) - 1 : U32), reader)
      +second = O.bits.get((C.ilog(range.of(Floor.multiplier(floor))) - 1 : U32), first)
      floor.parted(partitions.read(Floor.partitions(floor), Floor.classes(floor), coders, Ys{second, [O.Reader.value(second), O.Reader.value(first)]}), floor, range.of(Floor.multiplier(floor)), old)

# A bit says whether the packet has the channel's floor.
def floor.read(+reader: O.Reader, +floor: M.Floor, +coders: +List<D.Coder>, +old: +List<U32>) -> Floored:
  floor.present(U32.is_eq(O.Reader.value(O.bits.get(1, reader)), 1), O.bits.get(1, reader), floor, coders, old)

# -----------------------------------------------------------------------------
# The channels of a packet

def Mapping.mux(mapping: M.Mapping) -> +List<U32>:
  M.Mapping{_, _, mux, _, _, _} = mapping
  mux

def Mapping.magnitudes(mapping: M.Mapping) -> +List<U32>:
  M.Mapping{magnitudes, _, _, _, _, _} = mapping
  magnitudes

def Mapping.angles(mapping: M.Mapping) -> +List<U32>:
  M.Mapping{_, angles, _, _, _, _} = mapping
  angles

def Mapping.submaps(mapping: M.Mapping) -> U32:
  M.Mapping{_, _, _, submaps, _, _} = mapping
  submaps

def Mapping.floors(mapping: M.Mapping) -> +List<U32>:
  M.Mapping{_, _, _, _, floors, _} = mapping
  floors

def Mapping.residues(mapping: M.Mapping) -> +List<U32>:
  M.Mapping{_, _, _, _, _, residues} = mapping
  residues

def floor.at(floors: +List<M.Floor>) -> M.Floor:
  match floors:
    case Nil{}: M.Floor{Nil{}, Nil{}, 1, 0, [0, 1], [0, 1], Nil{}, Nil{}}
    case Con{+f, _}: f

# The floors of a packet's channels: the reader after them, each channel's
# Y values (the last first) and a bit for each channel without a floor
# (zero_channel).
type Floors is Data:
  Floors{reader: O.Reader, ys: +List<+List<U32>>, zeros: U32}

def Floors.reader(state: Floors) -> O.Reader:
  Floors{reader, _, _} = state
  reader

def floors.put(read: Floored, +channel: U32, +ys: +List<+List<U32>>, +zeros: U32) -> Floors:
  Floored{reader, values, zero} = read
  Floors{reader, Con{values, ys}, Bool.pick(U32, zero, (zeros .|. (1 << U32.to_nat(U32.min(channel, 31))) : U32), zeros)}

def Floors.ys(state: Floors) -> +List<+List<U32>>:
  Floors{_, ys, _} = state
  ys

def Floors.zeros(state: Floors) -> U32:
  Floors{_, _, zeros} = state
  zeros

# Each channel's floor is its submap's.
def floors.each(mux: +List<U32>, +channel: U32, +mapping: M.Mapping, +plan: Plan, +state: Floors) -> Floors:
  match mux:
    case Nil{}: state
    case Con{+submap, +rest}: floors.each(rest, (channel + 1 : U32), mapping, plan,
      floors.put(floor.read(Floors.reader(state), floor.at(List.drop(&2, M.Floor, Plan.floors(plan), U32.to_nat(nth(Mapping.floors(mapping), submap)))), Plan.coders(plan), Nil{}), channel, Floors.ys(state), Floors.zeros(state)))

def bit(+mask: U32, +i: U32) -> Bool:
  U32.is_ne(((mask >> U32.to_nat(U32.min(i, 31))) .&. 1 : U32), 0)

def cleared(+mask: U32, +i: U32) -> U32:
  (mask .&. (4294967295 .^. (1 << U32.to_nat(U32.min(i, 31)))) : U32)

# A coupled pair with a floor for one of its channels has both decoded.
def coupled.zeros(magnitudes: +List<U32>, angles: +List<U32>, +zeros: U32) -> U32:
  match magnitudes angles:
    case Con{+m, +more} Con{+a, +rest}: coupled.zeros(more, rest, Bool.pick(U32, bit(zeros, m) && bit(zeros, a), zeros, cleared(cleared(zeros, m), a)))
    case _ _: zeros

# A submap's channels, in the channels' order: their floats (the last
# first), a bit for each that is decoded and how many they are.
type Sub is Data:
  Sub{rows: +List<R.Row>, mask: U32, count: U32}

def sub.with(sub: Sub, +row: R.Row, +decoded: Bool) -> Sub:
  Sub{+rows, +mask, +count} = sub
  Sub{Con{row, rows}, Bool.pick(U32, decoded, (mask .|. (1 << U32.to_nat(U32.min(count, 31))) : U32), mask), (count + 1 : U32)}

def sub.gather(mux: +List<U32>, rows: +List<R.Row>, +submap: U32, +channel: U32, +zeros: U32, +sub: Sub) -> Sub:
  match mux rows:
    case Con{+m, +more} Con{+row, +rest}: sub.gather(more, rest, submap, (channel + 1 : U32), zeros, Bool.pick(Sub, U32.is_eq(m, submap), sub.with(sub, row, Bool.not(bit(zeros, channel))), sub))
    case _ _: sub

def rows.head(rows: +List<R.Row>) -> R.Row:
  match rows:
    case Nil{}: R.Row.new(0, 0.0)
    case Con{+r, _}: r

def rows.tail(rows: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

# The submap's channels' floats put back among the others.
def sub.scatter(mux: +List<U32>, rows: +List<R.Row>, +submap: U32, +new: +List<R.Row>, acc: +List<R.Row>) -> +List<R.Row>:
  match mux rows:
    case Con{+m, +more} Con{+row, +rest}: sub.scatter(more, rest, submap, Bool.pick(+List<R.Row>, U32.is_eq(m, submap), rows.tail(new), new), Con{Bool.pick(R.Row, U32.is_eq(m, submap), rows.head(new), row), acc})
    case _ _: List.reverse(&2, R.Row, acc)

def residue.at(residues: +List<M.Residue>) -> M.Residue:
  match residues:
    case Nil{}: M.Residue{0, 0, 0, 1, 1, 0, Nil{}}
    case Con{+r, _}: r

def sub.decoded(sub: Sub, +reader: O.Reader, +plan: Plan, +residue: U32, +half: U32) -> Rs.Res:
  Sub{+rows, +mask, +count} = sub
  Rs.residue.decode(reader, List.reverse(&2, R.Row, rows), Plan.coders(plan), residue.at(List.drop(&2, M.Residue, Plan.residues(plan), U32.to_nat(residue))), count, half, mask)

def sub.put(res: Rs.Res, +mux: +List<U32>, +rows: +List<R.Row>, +submap: U32) -> Rs.Res:
  Rs.Res{reader, new, done} = res
  Rs.Res{reader, sub.scatter(mux, rows, submap, new, Nil{}), done}

# decode_residue for each submap's channels, with the submap's residue.
def residues.each(n: Nat, +submap: U32, +mapping: M.Mapping, +plan: Plan, +half: U32, +zeros: U32, +state: Rs.Res) -> Rs.Res:
  match n:
    case 0n: state
    case 1n+k:
      residues.each(k, (submap + 1 : U32), mapping, plan, half, zeros,
        sub.put(sub.decoded(sub.gather(Mapping.mux(mapping), Rs.Res.rows(state), submap, 0, zeros, Sub{Nil{}, 0, 0}), Rs.Res.reader(state), plan, nth(Mapping.residues(mapping), submap), half), Mapping.mux(mapping), Rs.Res.rows(state), submap))

# Two channels' floats.
type Two is Data:
  Two{magnitude: R.Row, angle: R.Row}

# The inverse coupling of a float of each: which of them is the sum or the
# difference goes by their signs.
def couple.float(+m: F32, +a: F32, +j: U32, +magnitude: R.Row, +angle: R.Row) -> Two:
  Two{R.Row.set(magnitude, j, Bool.pick(F32, (m > 0.0 : F32), Bool.pick(F32, (a > 0.0 : F32), m, (m + a : F32)), Bool.pick(F32, (a > 0.0 : F32), m, (m - a : F32)))),
    R.Row.set(angle, j, Bool.pick(F32, (m > 0.0 : F32), Bool.pick(F32, (a > 0.0 : F32), (m - a : F32), m), Bool.pick(F32, (a > 0.0 : F32), (m + a : F32), m)))}

def Two.magnitude(two: Two) -> R.Row:
  Two{magnitude, _} = two
  magnitude

def Two.angle(two: Two) -> R.Row:
  Two{_, angle} = two
  angle

def couple.each(n: Nat, +j: U32, +two: Two) -> Two:
  match n:
    case 0n: two
    case 1n+k: couple.each(k, (j + 1 : U32), couple.float(R.Row.get(Two.magnitude(two), j), R.Row.get(Two.angle(two), j), j, Two.magnitude(two), Two.angle(two)))

def rows.at(rows: +List<R.Row>, +i: U32) -> R.Row:
  rows.head(List.drop(&2, R.Row, rows, U32.to_nat(i)))

def rows.put(rows: +List<R.Row>, +i: U32, +row: R.Row, acc: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: List.reverse(&2, R.Row, acc)
    case Con{+r, +rest}: rows.put(rest, (i - 1 : U32), row, Con{Bool.pick(R.Row, U32.is_eq(i, 0), row, r), acc})

def couple.put(two: Two, +rows: +List<R.Row>, +m: U32, +a: U32) -> +List<R.Row>:
  Two{magnitude, angle} = two
  rows.put(rows.put(rows, m, magnitude, Nil{}), a, angle, Nil{})

# The coupled pairs undone, the last first.
def couples.each(magnitudes: +List<U32>, angles: +List<U32>, +half: U32, +rows: +List<R.Row>) -> +List<R.Row>:
  match magnitudes angles:
    case Con{+m, +more} Con{+a, +rest}: couples.each(more, rest, half, couple.put(couple.each(U32.to_nat(half), 0, Two{rows.at(rows, m), rows.at(rows, a)}), rows, m, a))
    case _ _: rows

# The channels' floats after the floors: a channel without a floor of its
# own has its half block cleared; the others are multiplied by their
# floor's curve. `fine` is whether no curve ended past the table.
type Curved is Data:
  Curved{rows: +List<R.Row>, fine: Bool}

def curved.put(curve: F.Curve, +rows: +List<R.Row>, +fine: Bool) -> Curved:
  F.Curve{row, inside} = curve
  Curved{Con{row, rows}, fine && inside}

def curve.one(zero: Bool, +row: R.Row, +floor: M.Floor, +ys: +List<U32>, +half: U32, +table: R.Row) -> F.Curve:
  match zero:
    case True{}: F.Curve{R.Row.cleared(row, half), True{}}
    case False{}: F.curve.of(row, floor, ys, half, table)

def ys.head(ys: +List<+List<U32>>) -> +List<U32>:
  match ys:
    case Nil{}: Nil{}
    case Con{+y, _}: y

def ys.tail(ys: +List<+List<U32>>) -> +List<+List<U32>>:
  match ys:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

def Curved.rows(state: Curved) -> +List<R.Row>:
  Curved{rows, _} = state
  rows

def Curved.fine(state: Curved) -> Bool:
  Curved{_, fine} = state
  fine

# The rows gathered are the last channel's first until the end.
def curves.each(rows: +List<R.Row>, mux: +List<U32>, +channel: U32, +zeros: U32, +ys: +List<+List<U32>>, +mapping: M.Mapping, +plan: Plan, +half: U32, +state: Curved) -> Curved:
  match rows mux:
    case Con{+row, +rest} Con{+submap, +more}: curves.each(rest, more, (channel + 1 : U32), zeros, ys.tail(ys), mapping, plan, half,
      curved.put(curve.one(bit(zeros, channel), row, floor.at(List.drop(&2, M.Floor, Plan.floors(plan), U32.to_nat(nth(Mapping.floors(mapping), submap)))), ys.head(ys), half, Plan.table(plan)), Curved.rows(state), Curved.fine(state)))
    case _ _: Curved{List.reverse(&2, R.Row, Curved.rows(state)), Curved.fine(state)}

def transformed(rows: +List<R.Row>, +factors: X.Factors, +n: U32, acc: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: List.reverse(&2, R.Row, acc)
    case Con{+row, +rest}: transformed(rest, factors, n, Con{X.transform(row, factors, n), acc})

# -----------------------------------------------------------------------------
# Where the block is

# After a packet: the sample position of the next block, whether it is
# known, the samples still to drop, how many of the block's samples count
# (len) and where its left part begins.
type Placed is Data:
  Placed{loc: U32, known: Bool, discard: U32, len: U32, left: U32}

# `ends` is whether the packet is the one its page's granule position is
# for. On the stream's last page that position can cut the block short:
# the block then counts up to it (and no more than the block has).
# Otherwise the position places the block, and the next block is a
# window's width further.
def placed.end(+ends: Bool, +last: Bool, +known_loc: U32, +loc: U32, +known: Bool, +discard: U32, +left: U32, +right_start: U32, +right_end: U32, +half: U32) -> Placed:
  +short = ends && known && last && (known_loc < (loc + (right_end - left)) : U32)
  +len = ((Bool.pick(U32, (known_loc < loc : U32), 0, (known_loc - loc : U32))) + left : U32)
  +near = Bool.pick(U32, ends, (known_loc - (half - left) : U32), loc)
  Bool.pick(Placed, short, Placed{(loc + Bool.pick(U32, under(right_end, len), right_end, len) : U32), known, discard, Bool.pick(U32, under(right_end, len), right_end, len), left},
    Placed{Bool.pick(U32, ends || known, (near + (right_start - left) : U32), near), ends || known, discard, right_end, left})

# The first packet decoded places the stream: its block's first half is to
# be dropped, and what a long first block has past its right window is
# dropped from the next. Samples still to drop move the block's left part
# up, as far as its right one.
def placed.of(+first: Bool, +ends: Bool, +last: Bool, +known_loc: U32, +loc: U32, +known: Bool, +discard: U32, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Placed:
  +width = (right_start - left : U32)
  +most = Bool.not(under(discard, width))
  placed.end(ends, last, known_loc, Bool.pick(U32, first, (0 - (n >> 1n) : U32), loc), first || known,
    Bool.pick(U32, first, (n - right_end : U32), Bool.pick(U32, U32.is_eq(discard, 0), 0, Bool.pick(U32, most, (discard - width : U32), 0))),
    Bool.pick(U32, first || U32.is_eq(discard, 0), left, Bool.pick(U32, most, right_start, (left + discard : U32))), right_start, right_end, (n >> 1n : U32))

# -----------------------------------------------------------------------------
# vorbis_decode_packet

# The state after a packet with the C answer, the count of the block's
# samples and where its left and right parts begin.
type Packet is Data:
  Packet{state: State, fine: Bool, len: U32, left: U32, right: U32}

def failed(+reader: O.Reader, state: State) -> Packet:
  State{_, rows, loc, known, discard} = state
  Packet{State{reader, rows, loc, known, discard}, False{}, 0, 0, 0}

def packet.placed(placed: Placed, +reader: O.Reader, +rows: +List<R.Row>, +right: U32) -> Packet:
  Placed{loc, known, discard, len, left} = placed
  Packet{State{O.first.decode(reader, False{}), rows, loc, known, discard}, True{}, len, left, right}

# The packet's rest is read and dropped, then the block is placed.
def packet.ended(+reader: O.Reader, +rows: +List<R.Row>, state: State, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  State{_, _, +loc, +known, +discard} = state
  packet.placed(placed.of(O.Reader.decoding(reader), U32.is_eq(O.Packet.which(O.Reader.packet(reader)), O.Page.known_seg(O.Reader.page(reader))), U32.is_ne((O.Page.flag(O.Reader.page(reader)) .&. 4 : U32), 0),
    O.Page.known_loc(O.Reader.page(reader)), loc, known, discard, n, left, right_start, right_end), reader, rows, right_start)

def factors.for(long: Bool, +plan: Plan) -> X.Factors:
  match long:
    case True{}: Plan.long(plan)
    case False{}: Plan.short(plan)

# The floors' curves, the transform, and the end. A curve that ends past
# the table is refused.
def packet.curved(fine: Bool, +curved: Curved, +reader: O.Reader, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  match fine:
    case False{}: failed(O.undefined(reader), state)
    case True{}: packet.ended(O.flush.packet(reader), transformed(Curved.rows(curved), factors.for(long, plan), n, Nil{}), state, n, left, right_start, right_end)

def packet.curves(+curved: Curved, +reader: O.Reader, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  packet.curved(Curved.fine(curved), curved, reader, plan, state, long, n, left, right_start, right_end)

# After the residues: the coupled pairs undone from the last to the first,
# then each channel's floor.
def packet.residued(refused: Bool, +res: Rs.Res, +floors: Floors, +mapping: M.Mapping, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  match refused:
    case True{}: failed(Rs.Res.reader(res), state)
    case False{}: packet.curves(curves.each(couples.each(List.reverse(&2, U32, Mapping.magnitudes(mapping)), List.reverse(&2, U32, Mapping.angles(mapping)), (n >> 1n : U32), Rs.Res.rows(res)), Mapping.mux(mapping), 0,
      Floors.zeros(floors), List.reverse(&2, +List<U32>, Floors.ys(floors)), mapping, plan, (n >> 1n : U32), Curved{Nil{}, True{}}), Rs.Res.reader(res), plan, state, long, n, left, right_start, right_end)

def packet.residues(+res: Rs.Res, +floors: Floors, +mapping: M.Mapping, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  packet.residued(O.refused(Rs.Res.reader(res)), res, floors, mapping, plan, state, long, n, left, right_start, right_end)

# After the floors: the residues of each submap's channels. A channel
# without a floor is not decoded, unless it is coupled with one that has
# one.
def packet.floored(refused: Bool, +floors: Floors, +mapping: M.Mapping, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  match refused:
    case True{}: failed(Floors.reader(floors), state)
    case False{}: packet.residues(residues.each(U32.to_nat(Mapping.submaps(mapping)), 0, mapping, plan, (n >> 1n : U32), coupled.zeros(Mapping.magnitudes(mapping), Mapping.angles(mapping), Floors.zeros(floors)),
      Rs.Res{Floors.reader(floors), State.rows(state), False{}}), floors, mapping, plan, state, long, n, left, right_start, right_end)

def packet.floors(+floors: Floors, +mapping: M.Mapping, +plan: Plan, +state: State, +long: Bool, +n: U32, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  packet.floored(O.refused(Floors.reader(floors)), floors, mapping, plan, state, long, n, left, right_start, right_end)

def mapping.at(mappings: +List<M.Mapping>) -> M.Mapping:
  match mappings:
    case Nil{}: M.Mapping{Nil{}, Nil{}, Nil{}, 1, [0], [0]}
    case Con{+m, _}: m

def packet.mapped(+mapping: M.Mapping, +reader: O.Reader, +plan: Plan, +state: State, +long: Bool, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  packet.floors(floors.each(Mapping.mux(mapping), 0, mapping, plan, Floors{reader, Nil{}, 0}), mapping, plan, state, long, Bool.pick(U32, long, Plan.blocksize_1(plan), Plan.blocksize_0(plan)), left, right_start, right_end)

def packet.moded(+mode: M.Mode, +reader: O.Reader, +plan: Plan, +state: State, +left: U32, +right_start: U32, +right_end: U32) -> Packet:
  packet.mapped(mapping.at(List.drop(&2, M.Mapping, Plan.mappings(plan), U32.to_nat(Mode.mapping(mode)))), reader, plan, state, U32.is_ne(Mode.blockflag(mode), 0), left, right_start, right_end)

# vorbis_decode_packet_rest.
def packet.rest(initial: Initial, +plan: Plan, +state: State) -> Packet:
  match initial:
    case Initial{+reader, False{}, _, _, _, _, _}: failed(reader, state)
    case Initial{+reader, True{}, +mode, +left_start, _, +right_start, +right_end}: packet.moded(mode.at(List.drop(&2, M.Mode, Plan.modes(plan), U32.to_nat(mode))), reader, plan, state, left_start, right_start, right_end)

# After a refusal no call decodes anything: the reader is left as it is.
def packet.gone(refused: Bool, +plan: Plan, +state: State) -> Packet:
  match refused:
    case True{}: failed(State.reader(state), state)
    case False{}: packet.rest(initial.read(State.reader(state), plan), plan, state)

# vorbis_decode_packet(f, &len, &left, &right): the next audio packet
# decoded into the channels' floats, a block of them, before the window.
def packet.decode(+plan: Plan, +state: State) -> Packet:
  packet.gone(O.refused(State.reader(state)), plan, state)

# -----------------------------------------------------------------------------
# A decoder

# stb_vorbis_open_memory's start: the setup read, with the tables its two
# block sizes need, or why there is no decoder: stb_vorbis's failure, or a
# refusal (5: the transform's tables are not given under the libm profile,
# see vorbis_tables.bend).
type Decoder is Data:
  Opened{plan: Plan, state: State}
  Closed{status: S.Status}

def rows.new(n: Nat, +depth: U32, acc: +List<R.Row>) -> +List<R.Row>:
  match n:
    case 0n: acc
    case 1n+k: rows.new(k, depth, Con{R.Row.new(depth, 0.0), acc})

def open.tabled(short: Maybe<T.Tables>, long: Maybe<T.Tables>, +setup: S.Setup, +maps: M.Maps) -> Decoder:
  match short long:
    case Some{+small} Some{+large}:
      Opened{Plan{S.Head.channels(S.Setup.head(setup)), S.Head.blocksize_0(S.Setup.head(setup)), S.Head.blocksize_1(S.Setup.head(setup)), D.coders.of(S.Setup.books(setup), Nil{}), M.Maps.floors(maps), M.Maps.residues(maps),
        M.Maps.mappings(maps), M.Maps.modes(maps), X.factors.of(small), X.factors.of(large), F.table.row()},
        State{M.Maps.reader(maps), rows.new(U32.to_nat(S.Head.channels(S.Setup.head(setup))), (C.ilog(S.Head.blocksize_1(S.Setup.head(setup))) - 1 : U32), Nil{}), 0, False{}, 0}}
    case _ _: Closed{S.Refused{5}}

def open.read(status: S.Status, +libm: Mth.Libm, +setup: S.Setup, +maps: M.Maps) -> Decoder:
  match status:
    case S.Going{}: open.tabled(T.tables.for(libm, S.Head.blocksize_0(S.Setup.head(setup))), T.tables.for(libm, S.Head.blocksize_1(S.Setup.head(setup))), setup, maps)
    case S.Failed{+code}: Closed{S.Failed{code}}
    case S.Refused{+why}: Closed{S.Refused{why}}

def open.mapped(+libm: Mth.Libm, +setup: S.Setup, +maps: M.Maps) -> Decoder:
  open.read(M.Maps.status(maps), libm, setup, maps)

def open.set(+libm: Mth.Libm, +setup: S.Setup) -> Decoder:
  open.mapped(libm, setup, M.maps.read(setup))

# The decoder of the data, as start_decoder leaves it: the channels' floats
# all 0, no position known.
def open(+libm: Mth.Libm, +bytes: +List<U32>) -> Decoder:
  open.set(libm, S.setup.codebooks(bytes))
