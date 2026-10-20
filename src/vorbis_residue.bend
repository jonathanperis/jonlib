# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.2 vendors it in src/external/stb_vorbis.c: the
# residues of a packet (decode_residue, residue_decode) and the vectors
# laid over the channels (codebook_decode_deinterleave_repeat). See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# C ints are U32 two's-complement words. The channels' floats are rows
# (store.bend); a channel that is not decoded has a row all the same and a
# bit of the mask clear, where stb_vorbis has a null pointer.
import Base
import ./vorbis_ogg.bend as O
import ./vorbis_decode.bend as D
import ./vorbis_maps.bend as M
import ./store.bend as R

# a > b as ints.
def above(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) > (b .^. 2147483648) : U32)

# The channels' floats and where the next value goes: channel c_inter,
# place p_inter.
type Weave is Data:
  Weave{rows: +List<R.Row>, c_inter: U32, p_inter: U32}

def row.added(live: Bool, +row: R.Row, +p: U32, +value: F32) -> R.Row:
  match live:
    case False{}: row
    case True{}: R.Row.set(row, p, (R.Row.get(row, p) + value : F32))

def rows.added(rows: +List<R.Row>, +c: U32, +p: U32, +value: F32, acc: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: List.reverse(&2, R.Row, acc)
    case Con{+row, +rest}: rows.added(rest, (c - 1 : U32), p, value, Con{row.added(U32.is_eq(c, 0), row, p, value), acc})

def weave.live(live: Bool, +rows: +List<R.Row>, +c: U32, +p: U32, +value: F32) -> +List<R.Row>:
  match live:
    case False{}: rows
    case True{}: rows.added(rows, c, p, value, Nil{})

# outputs[c_inter][p_inter] += value where the channel has floats, then the
# next channel, and the next place after the last one.
def weave.put(state: Weave, +value: F32, +mask: U32, +channels: U32) -> Weave:
  Weave{+rows, +c_inter, +p_inter} = state
  Weave{weave.live(U32.is_ne(((mask >> U32.to_nat(U32.min(c_inter, 31))) .&. 1 : U32), 0), rows, c_inter, p_inter, value), Bool.pick(U32, U32.is_eq((c_inter + 1 : U32), channels), 0, (c_inter + 1 : U32)),
    Bool.pick(U32, U32.is_eq((c_inter + 1 : U32), channels), (p_inter + 1 : U32), p_inter)}

# A vector's values in turn: values[z + i] + last, `last` being the value
# before in a sequence and 0 otherwise.
def weave.values(n: Nat, +values: R.Row, +z: U32, +sequence: Bool, +mask: U32, +channels: U32, +last: F32, +state: Weave) -> Weave:
  match n:
    case 0n: state
    case 1n+k:
      +value = ((R.Row.get(values, z) + last : F32))
      weave.values(k, values, (z + 1 : U32), sequence, mask, channels, Bool.pick(F32, sequence, value, last), weave.put(state, value, mask, channels))

# The vectors so far. state: 0 another is due, 1 they are all there, 2 one
# was not decoded.
type Turn is Data:
  Turn{state: U32, reader: O.Reader, weave: Weave, effective: U32, total: U32}

def Turn.state(turn: Turn) -> U32:
  Turn{state, _, _, _, _} = turn
  state

def Weave.c(weave: Weave) -> U32:
  Weave{_, c_inter, _} = weave
  c_inter

def Weave.p(weave: Weave) -> U32:
  Weave{_, _, p_inter} = weave
  p_inter

# How many values of a vector are used: all its dimensions, unless they
# would pass the end of the channels' floats, `len` each. stb_vorbis then
# takes len*ch - (p_inter*ch - c_inter), which is the room left with
# c_inter added instead of taken away, and keeps that for the vectors
# after it.
def weave.room(+effective: U32, +c: U32, +p: U32, +channels: U32, +len: U32) -> U32:
  Bool.pick(U32, above(((c + (p * channels)) + effective : U32), (len * channels : U32)), ((len * channels) - ((p * channels) - c) : U32), effective)

# A vector's `room` values from its symbol's place in the codebook's values.
# stb_vorbis's room can be more than the codebook's dimensions (above): the
# values read are then the next symbol's, and past the last symbol's they
# are not the codebook's at all: refused.
def weave.vector(+coder: D.Coder, +mask: U32, +channels: U32, +reader: O.Reader, +weave: Weave, +room: U32, +total: U32) -> Turn:
  Bool.pick(Turn, above(room, 0) && (((O.Reader.value(reader) * D.Coder.dimensions(coder)) + room) > D.Coder.count(coder) : U32), Turn{2, O.undefined(reader), weave, room, total},
    Turn{Bool.pick(U32, above((total - room : U32), 0), 0, 1), reader,
      weave.values(U32.to_nat(Bool.pick(U32, above(room, 0) && (room <= 65536 : U32), room, 0)), D.Coder.values(coder), (O.Reader.value(reader) * D.Coder.dimensions(coder) : U32), D.Coder.sequence(coder), mask, channels, 0.0, weave),
      room, (total - room : U32)})

def weave.decoded(none: Bool, +coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +reader: O.Reader, +weave: Weave, +effective: U32, +total: U32) -> Turn:
  match none:
    case True{}: Turn{2, reader, weave, effective, total}
    case False{}: weave.vector(coder, mask, channels, reader, weave, weave.room(effective, Weave.c(weave), Weave.p(weave), channels, len), total)

def weave.symbol(+coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +reader: O.Reader, +weave: Weave, +effective: U32, +total: U32) -> Turn:
  weave.decoded(U32.is_eq(O.Reader.value(reader), 4294967295), coder, mask, channels, len, reader, weave, effective, total)

# A vector: its symbol (no symbol at the packet's end is the end of the
# vectors without an error, and a VORBIS_invalid_stream elsewhere), then
# its values.
def weave.turn(+coder: D.Coder, +mask: U32, +channels: U32, +len: U32, turn: Turn) -> Turn:
  Turn{_, +reader, +weave, +effective, +total} = turn
  weave.symbol(coder, mask, channels, len, D.start.ended(D.decode.raw(coder, reader)), weave, effective, total)

# Up to 8 vectors: a byte of the packet has bits for no more (a symbol
# takes a bit at least).
def weave.eight(n: Nat, on: Bool, +coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +turn: Turn) -> Turn:
  match n on:
    case _ False{}: turn
    case 0n True{}: turn
    case 1n+k True{}:
      +next = weave.turn(coder, mask, channels, len, turn)
      weave.eight(k, U32.is_eq(Turn.state(next), 0), coder, mask, channels, len, next)

def weave.tail(n: Nat, on: Bool, +coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +turn: Turn) -> Turn:
  match n on:
    case _ False{}: turn
    case 0n True{}: turn
    case 1n+k True{}:
      +next = weave.eight(8n, True{}, coder, mask, channels, len, turn)
      weave.tail(k, U32.is_eq(Turn.state(next), 0), coder, mask, channels, len, next)

def weave.tails(n: Nat, on: Bool, +coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +turn: Turn) -> Turn:
  match n on:
    case _ False{}: turn
    case 0n True{}: turn
    case 1n+k True{}:
      +next = weave.tail(256n, True{}, coder, mask, channels, len, turn)
      weave.tails(k, U32.is_eq(Turn.state(next), 0), coder, mask, channels, len, next)

# The vectors go on until they are all there or one is not decoded. A
# vector that uses no value (its room is 0 or less) takes nothing from what
# is left to decode: the loop then only ends with the packet. The packet's
# bytes outlast the vectors, 8 to a byte; a packet past the data's end has
# its segments' zeros, 255 segments of 255 bytes at most.
def weave.loop(fuel: +List<U32>, on: Bool, +coder: D.Coder, +mask: U32, +channels: U32, +len: U32, +turn: Turn) -> Turn:
  match fuel on:
    case _ False{}: turn
    case Nil{} True{}: weave.tails(256n, True{}, coder, mask, channels, len, turn)
    case Con{_, +more} True{}:
      +next = weave.eight(8n, True{}, coder, mask, channels, len, turn)
      weave.loop(more, U32.is_eq(Turn.state(next), 0), coder, mask, channels, len, next)

# The reader, the channels' floats, where the next value would go and the C
# answer after the vectors.
type Woven is Data:
  Woven{reader: O.Reader, rows: +List<R.Row>, c_inter: U32, p_inter: U32, fine: Bool}

def Woven.reader(woven: Woven) -> O.Reader:
  Woven{reader, _, _, _, _} = woven
  reader

def Woven.fine(woven: Woven) -> Bool:
  Woven{_, _, _, _, fine} = woven
  fine

def weave.ended(turn: Turn) -> Woven:
  match turn:
    case Turn{+state, +reader, Weave{+rows, +c_inter, +p_inter}, _, _}: Woven{reader, rows, c_inter, p_inter, U32.is_eq(state, 1)}

# kind: 0 the codebook has no lookup (VORBIS_invalid_stream), 1 nothing is
# left to decode, 2 vectors are due.
def weave.kind(kind: U32, +coder: D.Coder, +reader: O.Reader, +rows: +List<R.Row>, +mask: U32, +channels: U32, +c_inter: U32, +p_inter: U32, +len: U32, +total: U32) -> Woven:
  match kind:
    case 0: Woven{O.failed(reader, 21), rows, c_inter, p_inter, False{}}
    case 1: Woven{reader, rows, c_inter, p_inter, True{}}
    case _: weave.ended(weave.loop(O.Stream.rest(O.Reader.stream(reader)), True{}, coder, mask, channels, len, Turn{0, reader, Weave{rows, c_inter, p_inter}, D.Coder.dimensions(coder), total}))

# codebook_decode_deinterleave_repeat(f, c, outputs, ch, &c_inter, &p_inter,
# len, total_decode): vectors of the codebook until `total` values are
# decoded, each value added to the next channel's floats in turn. Where the
# answer is FALSE c_inter and p_inter are not what the caller is given back
# in C: they are not used then.
def weave.decode(+coder: D.Coder, +reader: O.Reader, +rows: +List<R.Row>, +mask: U32, +channels: U32, +c_inter: U32, +p_inter: U32, +len: U32, +total: U32) -> Woven:
  weave.kind(Bool.pick(U32, U32.is_eq(D.Coder.lookup(coder), 0), 0, Bool.pick(U32, above(total, 0), 2, 1)), coder, reader, rows, mask, channels, c_inter, p_inter, len, total)

# -----------------------------------------------------------------------------
# Residues

def shrunk(n: Nat, +q: U32, +base: U32) -> U32:
  match n:
    case 0n: q
    case 1n+k: shrunk(k, (q / U32.max(base, 1) : U32), base)

# classdata[q][i]: the i-th of the `count` digits of q in the base of the
# residue's classifications, the highest first (stb_vorbis keeps them all in
# tables; a number under 2^19 has no digit past its 32nd from the lowest).
def digit(+q: U32, +base: U32, +count: U32, +i: U32) -> U32:
  (shrunk(U32.to_nat(U32.min(((count - 1) - i : U32), 32)), q, base) % U32.max(base, 1) : U32)

def nth(xs: +List<U32>, +i: U32) -> U32:
  O.entry(List.drop(&2, U32, xs, U32.to_nat(i)))

def row.first(rows: +List<+List<U32>>) -> +List<U32>:
  match rows:
    case Nil{}: Nil{}
    case Con{+r, _}: r

# residue_books[c][pass]: a codebook's number, or -1.
def book.of(+books: +List<+List<U32>>, +c: U32, +pass: U32) -> U32:
  nth(row.first(List.drop(&2, +List<U32>, books, U32.to_nat(c))), pass)

# What a residue needs that does not change while it is decoded: its type,
# where it begins, the size of a partition, the classifications, the digits
# of a class (the classbook's dimensions), its codebooks, how many
# partitions are read, the channels and which of them are decoded, the
# vectors' length (half the block) and the setup's codebooks.
type Plan is Data:
  Plan{kind: U32, begin: U32, part_size: U32, classifications: U32, classwords: U32, books: +List<+List<U32>>, part_read: U32, channels: U32, mask: U32, n: U32, classbook: D.Coder, coders: +List<D.Coder>}

# The reader, the channels' floats and whether the residue is over (the
# packet ended, or a vector was not decoded).
type Res is Data:
  Res{reader: O.Reader, rows: +List<R.Row>, done: Bool}

def Res.done(res: Res) -> Bool:
  Res{_, _, done} = res
  done

def Res.reader(res: Res) -> O.Reader:
  Res{reader, _, _} = res
  reader

def Res.rows(res: Res) -> +List<R.Row>:
  Res{_, rows, _} = res
  rows

def rows.first(rows: +List<R.Row>) -> R.Row:
  match rows:
    case Nil{}: R.Row.new(0, 0.0)
    case Con{+r, _}: r

def rows.set(rows: +List<R.Row>, +j: U32, +row: R.Row, acc: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: List.reverse(&2, R.Row, acc)
    case Con{+r, +rest}: rows.set(rest, (j - 1 : U32), row, Con{Bool.pick(R.Row, U32.is_eq(j, 0), row, r), acc})

# The reader and a channel's floats after the vectors of a partition:
# `fine` is the C answer.
type Part is Data:
  Part{reader: O.Reader, row: R.Row, fine: Bool}

def part.of(vector: D.Vector) -> Part:
  D.Vector{reader, row, fine} = vector
  Part{reader, row, fine}

def Part.reader(part: Part) -> O.Reader:
  Part{reader, _, _} = part
  reader

def Part.row(part: Part) -> R.Row:
  Part{_, row, _} = part
  row

def Part.fine(part: Part) -> Bool:
  Part{_, _, fine} = part
  fine

# residue_decode for a residue of type 0: codebook_decode_step from each of
# the first n/dimensions floats of the partition, every (n/dimensions)th
# float after it, with a length of n - offset - k, which is the partition's
# size less where the partition is: under 1 past the first partitions, and
# then nothing is added.
def part.stepped(n: Nat, on: Bool, +coder: D.Coder, +offset: U32, +size: U32, +step: U32, +k: U32, +part: Part) -> Part:
  match n on:
    case _ False{}: part
    case 0n True{}: part
    case 1n+rest True{}:
      +next = part.of(D.vector.step(coder, Part.reader(part), Part.row(part), (offset + k : U32), Bool.pick(U32, above(((size - offset) - k : U32), 0), ((size - offset) - k : U32), 0), step))
      part.stepped(rest, Part.fine(next), coder, offset, size, step, (k + 1 : U32), next)

# And for the other types: codebook_decode at the partition's floats, the
# codebook's dimensions further each time, while they are inside it.
def part.plain(n: Nat, on: Bool, +coder: D.Coder, +offset: U32, +size: U32, +k: U32, +part: Part) -> Part:
  match n on:
    case _ False{}: part
    case 0n True{}: part
    case 1n+rest True{}:
      +next = part.of(D.vector.decode(coder, Part.reader(part), Part.row(part), offset, (size - k : U32)))
      part.plain(rest, Part.fine(next) && ((k + D.Coder.dimensions(coder)) < size : U32), coder, (offset + D.Coder.dimensions(coder) : U32), size, (k + D.Coder.dimensions(coder) : U32), next)

def Plan.kind(plan: Plan) -> U32:
  Plan{kind, _, _, _, _, _, _, _, _, _, _, _} = plan
  kind

def Plan.begin(plan: Plan) -> U32:
  Plan{_, begin, _, _, _, _, _, _, _, _, _, _} = plan
  begin

def Plan.part_size(plan: Plan) -> U32:
  Plan{_, _, part_size, _, _, _, _, _, _, _, _, _} = plan
  part_size

def Plan.classifications(plan: Plan) -> U32:
  Plan{_, _, _, classifications, _, _, _, _, _, _, _, _} = plan
  classifications

def Plan.classwords(plan: Plan) -> U32:
  Plan{_, _, _, _, classwords, _, _, _, _, _, _, _} = plan
  classwords

def Plan.books(plan: Plan) -> +List<+List<U32>>:
  Plan{_, _, _, _, _, books, _, _, _, _, _, _} = plan
  books

def Plan.part_read(plan: Plan) -> U32:
  Plan{_, _, _, _, _, _, part_read, _, _, _, _, _} = plan
  part_read

def Plan.channels(plan: Plan) -> U32:
  Plan{_, _, _, _, _, _, _, channels, _, _, _, _} = plan
  channels

def Plan.mask(plan: Plan) -> U32:
  Plan{_, _, _, _, _, _, _, _, mask, _, _, _} = plan
  mask

def Plan.n(plan: Plan) -> U32:
  Plan{_, _, _, _, _, _, _, _, _, n, _, _} = plan
  n

def Plan.classbook(plan: Plan) -> D.Coder:
  Plan{_, _, _, _, _, _, _, _, _, _, classbook, _} = plan
  classbook

def Plan.coders(plan: Plan) -> +List<D.Coder>:
  Plan{_, _, _, _, _, _, _, _, _, _, _, coders} = plan
  coders

# Whether channel j is decoded.
def live(+mask: U32, +j: U32) -> Bool:
  U32.is_ne(((mask >> U32.to_nat(U32.min(j, 31))) .&. 1 : U32), 0)

# A partition of a channel in a pass: the vectors of its class's codebook
# for the pass, if the class has one. kind: 0 none, 1 a residue of type 0,
# 2 another.
def part.vectors(kind: U32, +coder: D.Coder, +offset: U32, +size: U32, +reader: O.Reader, +row: R.Row) -> Part:
  match kind:
    case 0: Part{reader, row, True{}}
    case 1: part.stepped(U32.to_nat((size / U32.max(D.Coder.dimensions(coder), 1) : U32)), True{}, coder, offset, size, (size / U32.max(D.Coder.dimensions(coder), 1) : U32), 0, Part{reader, row, True{}})
    case _: part.plain(U32.to_nat(size), True{}, coder, offset, size, 0, Part{reader, row, True{}})

# The codebook of a number, the first for none (-1), which is not used then.
def coder.for(+coders: +List<D.Coder>, +book: U32) -> D.Coder:
  D.coder.at(coders, Bool.pick(U32, U32.is_eq(book, 4294967295), 0, book))

def part.booked(+book: U32, +plan: Plan, +pcount: U32, +reader: O.Reader, +row: R.Row) -> Part:
  part.vectors(Bool.pick(U32, U32.is_eq(book, 4294967295), 0, Bool.pick(U32, U32.is_eq(Plan.kind(plan), 0), 1, 2)), coder.for(Plan.coders(plan), book), (Plan.begin(plan) + (pcount * Plan.part_size(plan)) : U32), Plan.part_size(plan), reader, row)

def res.parted(part: Part, +rows: +List<R.Row>, +j: U32) -> Res:
  Part{reader, row, fine} = part
  Res{reader, rows.set(rows, j, row, Nil{}), Bool.not(fine)}

# A channel's partition, if the channel is decoded.
def channel.one(decoded: Bool, +q: U32, +j: U32, +i: U32, +pass: U32, +pcount: U32, +plan: Plan, +res: Res) -> Res:
  match decoded:
    case False{}: res
    case True{}: res.parted(part.booked(book.of(Plan.books(plan), digit(q, Plan.classifications(plan), Plan.classwords(plan), i), pass), plan, pcount, Res.reader(res), rows.first(List.drop(&2, R.Row, Res.rows(res), U32.to_nat(j)))), Res.rows(res), j)

# A partition's channels in turn: `qs` are the channels' classes.
def channels.each(qs: +List<U32>, on: Bool, +j: U32, +i: U32, +pass: U32, +pcount: U32, +plan: Plan, +res: Res) -> Res:
  match qs on:
    case _ False{}: res
    case Nil{} True{}: res
    case Con{+q, +rest} True{}:
      +next = channel.one(live(Plan.mask(plan), j), q, j, i, pass, pcount, plan, res)
      channels.each(rest, Bool.not(Res.done(next)), (j + 1 : U32), i, pass, pcount, plan, next)

# The partitions of a class set: as many as the class has digits, or as are
# left.
def group.parts(n: Nat, on: Bool, +qs: +List<U32>, +i: U32, +pass: U32, +pcount: U32, +plan: Plan, +res: Res) -> Res:
  match n on:
    case _ False{}: res
    case 0n True{}: res
    case 1n+k True{}:
      +next = channels.each(qs, True{}, 0, i, pass, pcount, plan, res)
      group.parts(k, Bool.not(Res.done(next)), qs, (i + 1 : U32), pass, (pcount + 1 : U32), plan, next)

# The classes of a class set, read in the first pass: a symbol of the
# classbook for each channel that is decoded (0 stands for the others). No
# symbol ends the residue.
type Classed is Data:
  Classed{reader: O.Reader, done: Bool, qs: +List<U32>}

def class.read(decoded: Bool, +classbook: D.Coder, +reader: O.Reader) -> O.Reader:
  match decoded:
    case False{}: O.Reader.answer(reader, 0)
    case True{}: D.decode.symbol(classbook, reader)

def classes.read(n: Nat, on: Bool, +j: U32, +mask: U32, +classbook: D.Coder, +reader: O.Reader, +acc: +List<U32>) -> Classed:
  match n on:
    case _ False{}: Classed{reader, True{}, List.reverse(&2, U32, acc)}
    case 0n True{}: Classed{reader, False{}, List.reverse(&2, U32, acc)}
    case 1n+k True{}:
      +next = class.read(live(mask, j), classbook, reader)
      classes.read(k, U32.is_ne(O.Reader.value(next), 4294967295), (j + 1 : U32), mask, classbook, next, Con{O.Reader.value(next), acc})

# The class sets of a pass. In the first pass their classes are read and
# kept (`kept`, the last first); in the others they are the ones kept
# (`sets`).
type Sets is Data:
  Sets{res: Res, kept: +List<+List<U32>>}

def Sets.res(sets: Sets) -> Res:
  Sets{res, _} = sets
  res

def Sets.kept(sets: Sets) -> +List<+List<U32>>:
  Sets{_, kept} = sets
  kept

def sets.first(sets: +List<+List<U32>>) -> +List<U32>:
  match sets:
    case Nil{}: Nil{}
    case Con{+qs, _}: qs

def sets.rest(sets: +List<+List<U32>>) -> +List<+List<U32>>:
  match sets:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

def res.read(res: Res, +reader: O.Reader, +done: Bool) -> Res:
  Res{_, rows, _} = res
  Res{reader, rows, done}

# A class set of the first pass: its classes, then its partitions.
def set.read(classed: Classed, +pass: U32, +pcount: U32, +plan: Plan, +res: Res, +kept: +List<+List<U32>>) -> Sets:
  Classed{+reader, +done, +qs} = classed
  Sets{group.parts(U32.to_nat(U32.min(Plan.classwords(plan), (Plan.part_read(plan) - pcount : U32))), Bool.not(done), qs, 0, pass, pcount, plan, res.read(res, reader, done)), Con{qs, kept}}

# A class set: read in the first pass, kept in the others.
def set.one(first: Bool, +pass: U32, +pcount: U32, +plan: Plan, +qs: +List<U32>, +state: Sets) -> Sets:
  match first:
    case True{}: set.read(classes.read(U32.to_nat(Plan.channels(plan)), True{}, 0, Plan.mask(plan), Plan.classbook(plan), Res.reader(Sets.res(state)), Nil{}), pass, pcount, plan, Sets.res(state), Sets.kept(state))
    case False{}: Sets{group.parts(U32.to_nat(U32.min(Plan.classwords(plan), (Plan.part_read(plan) - pcount : U32))), True{}, qs, 0, pass, pcount, plan, Sets.res(state)), Sets.kept(state)}

def sets.each(n: Nat, on: Bool, +first: Bool, +pass: U32, +pcount: U32, +plan: Plan, +sets: +List<+List<U32>>, +state: Sets) -> Sets:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = set.one(first, pass, pcount, plan, sets.first(sets), state)
      sets.each(k, Bool.not(Res.done(Sets.res(next))) && ((pcount + Plan.classwords(plan)) < Plan.part_read(plan) : U32), first, pass, (pcount + Plan.classwords(plan) : U32), plan, sets.rest(sets), next)

# -----------------------------------------------------------------------------
# A residue of type 2 over several channels: one class for all of them, and
# the vectors woven over them.

# The residue so far, with where the next value goes.
type Lace is Data:
  Lace{res: Res, c_inter: U32, p_inter: U32}

def Lace.res(lace: Lace) -> Res:
  Lace{res, _, _} = lace
  res

def Lace.c(lace: Lace) -> U32:
  Lace{_, c_inter, _} = lace
  c_inter

def Lace.p(lace: Lace) -> U32:
  Lace{_, _, p_inter} = lace
  p_inter

def lace.woven(woven: Woven) -> Lace:
  Woven{reader, rows, c_inter, p_inter, fine} = woven
  Lace{Res{reader, rows, Bool.not(fine)}, c_inter, p_inter}

# A partition without a codebook in the pass is passed over: the next value
# goes where the partition after it begins.
def lace.part(none: Bool, +coder: D.Coder, +plan: Plan, +pcount: U32, +lace: Lace) -> Lace:
  match none:
    case True{}: Lace{Lace.res(lace), (((Plan.begin(plan) + (pcount * Plan.part_size(plan))) + Plan.part_size(plan)) % U32.max(Plan.channels(plan), 1) : U32),
      (((Plan.begin(plan) + (pcount * Plan.part_size(plan))) + Plan.part_size(plan)) / U32.max(Plan.channels(plan), 1) : U32)}
    case False{}: lace.woven(weave.decode(coder, Res.reader(Lace.res(lace)), Res.rows(Lace.res(lace)), Plan.mask(plan), Plan.channels(plan), Lace.c(lace), Lace.p(lace), Plan.n(plan), Plan.part_size(plan)))

def lace.booked(+book: U32, +plan: Plan, +pcount: U32, +lace: Lace) -> Lace:
  lace.part(U32.is_eq(book, 4294967295), coder.for(Plan.coders(plan), book), plan, pcount, lace)

def lace.parts(n: Nat, on: Bool, +q: U32, +i: U32, +pass: U32, +pcount: U32, +plan: Plan, +lace: Lace) -> Lace:
  match n on:
    case _ False{}: lace
    case 0n True{}: lace
    case 1n+k True{}:
      +next = lace.booked(book.of(Plan.books(plan), digit(q, Plan.classifications(plan), Plan.classwords(plan), i), pass), plan, pcount, lace)
      lace.parts(k, Bool.not(Res.done(Lace.res(next))), q, (i + 1 : U32), pass, (pcount + 1 : U32), plan, next)

# A class set's partitions, the first value at the first partition's place.
def lace.set(on: Bool, +q: U32, +pass: U32, +pcount: U32, +plan: Plan, +res: Res) -> Res:
  Lace.res(lace.parts(U32.to_nat(U32.min(Plan.classwords(plan), (Plan.part_read(plan) - pcount : U32))), on, q, 0, pass, pcount, plan,
    Lace{res, ((Plan.begin(plan) + (pcount * Plan.part_size(plan))) % U32.max(Plan.channels(plan), 1) : U32), ((Plan.begin(plan) + (pcount * Plan.part_size(plan))) / U32.max(Plan.channels(plan), 1) : U32)}))

def lace.read(+classed: O.Reader, +pass: U32, +pcount: U32, +plan: Plan, +res: Res, +kept: +List<+List<U32>>) -> Sets:
  Sets{lace.set(U32.is_ne(O.Reader.value(classed), 4294967295), O.Reader.value(classed), pass, pcount, plan, res.read(res, classed, U32.is_eq(O.Reader.value(classed), 4294967295))), Con{[O.Reader.value(classed)], kept}}

def lace.one(first: Bool, +pass: U32, +pcount: U32, +plan: Plan, +qs: +List<U32>, +state: Sets) -> Sets:
  match first:
    case True{}: lace.read(D.decode.symbol(Plan.classbook(plan), Res.reader(Sets.res(state))), pass, pcount, plan, Sets.res(state), Sets.kept(state))
    case False{}: Sets{lace.set(True{}, O.entry(qs), pass, pcount, plan, Sets.res(state)), Sets.kept(state)}

def laces.each(n: Nat, on: Bool, +first: Bool, +pass: U32, +pcount: U32, +plan: Plan, +sets: +List<+List<U32>>, +state: Sets) -> Sets:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = lace.one(first, pass, pcount, plan, sets.first(sets), state)
      laces.each(k, Bool.not(Res.done(Sets.res(next))) && ((pcount + Plan.classwords(plan)) < Plan.part_read(plan) : U32), first, pass, (pcount + Plan.classwords(plan) : U32), plan, sets.rest(sets), next)

# -----------------------------------------------------------------------------
# The eight passes

def pass.sets(woven: Bool, +pass: U32, +plan: Plan, +kept: +List<+List<U32>>, +res: Res) -> Sets:
  match woven:
    case True{}: laces.each(U32.to_nat(Plan.part_read(plan)), U32.is_ne(Plan.part_read(plan), 0), U32.is_eq(pass, 0), pass, 0, plan, kept, Sets{res, Nil{}})
    case False{}: sets.each(U32.to_nat(Plan.part_read(plan)), U32.is_ne(Plan.part_read(plan), 0), U32.is_eq(pass, 0), pass, 0, plan, kept, Sets{res, Nil{}})

# A pass over the partitions for each of a class's eight codebooks. The
# classes are read in the first.
def passes(n: Nat, on: Bool, +woven: Bool, +pass: U32, +plan: Plan, +kept: +List<+List<U32>>, +res: Res) -> Res:
  match n on:
    case _ False{}: res
    case 0n True{}: res
    case 1n+k True{}:
      +next = pass.sets(woven, pass, plan, kept, res)
      passes(k, Bool.not(Res.done(Sets.res(next))), woven, (pass + 1 : U32), plan, Bool.pick(+List<+List<U32>>, U32.is_eq(pass, 0), List.reverse(&2, +List<U32>, Sets.kept(next)), kept), Sets.res(next))

def rows.cleared(rows: +List<R.Row>, +mask: U32, +j: U32, +n: U32, acc: +List<R.Row>) -> +List<R.Row>:
  match rows:
    case Nil{}: List.reverse(&2, R.Row, acc)
    case Con{+row, +rest}: rows.cleared(rest, mask, (j + 1 : U32), n, Con{Bool.pick(R.Row, live(mask, j), R.Row.cleared(row, n), row), acc})

# kind: 0 no channel is decoded, 1 the vectors are woven over the channels
# (a residue of type 2 and more channels than one), 2 each channel has its
# own.
def residue.passes(kind: U32, +plan: Plan, +res: Res) -> Res:
  match kind:
    case 0: res
    case 1: passes(8n, True{}, True{}, 0, plan, Nil{}, res)
    case _: passes(8n, True{}, False{}, 0, plan, Nil{}, res)

# decode_residue(f, residue_buffers, ch, n, rn, do_not_decode): the
# residue's vectors added to the channels' floats, whose first n are
# cleared first for the channels that are decoded (`mask` has their bits).
# n is half the block. A residue of type 2 reads up to twice n: over two
# channels or more that is n floats of each; over one it is floats the
# clearing did not reach, which hold what the block before left there.
def residue.decode(+reader: O.Reader, +rows: +List<R.Row>, +coders: +List<D.Coder>, residue: M.Residue, +channels: U32, +n: U32, +mask: U32) -> Res:
  M.Residue{+kind, +begin, +end, +part_size, +classifications, +classbook, +books} = residue
  +actual = Bool.pick(U32, U32.is_eq(kind, 2), (n * 2 : U32), n)
  residue.passes(Bool.pick(U32, U32.is_eq(kind, 2) && U32.is_ne(channels, 1), Bool.pick(U32, U32.is_eq(mask, 0), 0, 1), 2),
    Plan{kind, begin, part_size, classifications, D.Coder.dimensions(D.coder.at(coders, classbook)), books, ((U32.min(end, actual) - U32.min(begin, actual)) / U32.max(part_size, 1) : U32), channels, mask, n,
      D.coder.at(coders, classbook), coders},
    Res{reader, rows.cleared(rows, mask, 0, n, Nil{}), False{}})
