# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: the rest
# of start_decoder's reading of the setup header, after the codebooks: the
# floors (type 1, with the order of their points and each point's
# neighbours), the residues, the mappings and the modes. See
# THIRD_PARTY_NOTICES.md and LICENSES/stb_vorbis.txt.
#
# The statuses are vorbis_setup.bend's. Two more things are refused here:
# a mapping of 16 submaps (stb_vorbis keeps 15 and writes the sixteenth's
# floor over the first's residue: refusal 2, undefined in C), and a residue
# whose classbook has more than 2^24 entries times dimensions (as many
# bytes in allocations: refusal 3).
import Base
import ./vorbis_ogg.bend as O
import ./vorbis_codebook.bend as C
import ./vorbis_setup.bend as S

def nth(xs: +List<U32>, +i: U32) -> U32:
  O.entry(List.drop(&2, U32, xs, U32.to_nat(i)))

def count.of(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count.of(rest, (n + 1 : U32))

# -----------------------------------------------------------------------------
# Floors

# A class of a floor's partitions: how many points a partition of the class
# has, the bits of its subclass number, the codebook that codes the
# subclasses (0 where there are none: stb_vorbis leaves it unset and does
# not read it) and each subclass's codebook, -1 (4294967295) for none.
type Class is Data:
  Class{dimensions: U32, subclasses: U32, masterbook: U32, books: +List<U32>}

def Class.dimensions(it: Class) -> U32:
  Class{dimensions, _, _, _} = it
  dimensions

# The classes read so far, the last first.
type Classes is Data:
  Classes{reader: O.Reader, status: S.Status, classes: +List<Class>}

def Classes.reader(state: Classes) -> O.Reader:
  Classes{reader, _, _} = state
  reader

def Classes.status(state: Classes) -> S.Status:
  Classes{_, status, _} = state
  status

def Classes.classes(state: Classes) -> +List<Class>:
  Classes{_, _, classes} = state
  classes

# Whether a subclass's codebook, read as its number and 1, is past the
# codebooks.
def books.over(values: +List<U32>, +books: U32, +over: Bool) -> Bool:
  match values:
    case Nil{}: over
    case Con{+v, +rest}: books.over(rest, books, over || (v > books : U32))

def less.one(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+v, +rest}: less.one(rest, Con{(v - 1 : U32), acc})

# A class: its dimensions (3 bits and 1), the bits of a subclass (2), the
# masterbook where there are subclasses, and a codebook for each of the
# 1 << bits subclasses.
def class.read(+reader: O.Reader, +books: U32, +acc: +List<Class>) -> Classes:
  +wide = O.bits.get(3, reader)
  +dimensions = (O.Reader.value(wide) + 1 : U32)
  +split = O.bits.get(2, wide)
  +subclasses = O.Reader.value(split)
  +master = Bool.pick(O.Reader, U32.is_eq(subclasses, 0), O.Reader.answer(split, 0), O.bits.get(8, split))
  +masterbook = O.Reader.value(master)
  +read = S.words.read(U32.to_nat((1 << U32.to_nat(subclasses) : U32)), 8, master, Nil{})
  Classes{S.Words.reader(read), Bool.pick(S.Status, (U32.is_ne(subclasses, 0) && (masterbook >= books : U32)) || books.over(S.Words.values(read), books, False{}), S.Failed{20}, S.Going{}),
    Con{Class{dimensions, subclasses, masterbook, less.one(S.Words.values(read), Nil{})}, acc}}

def classes.each(n: Nat, on: Bool, +books: U32, +state: Classes) -> Classes:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = class.read(Classes.reader(state), books, Classes.classes(state))
      classes.each(k, S.going(Classes.status(next)), books, next)

# The largest of a floor's partition classes and 1: how many classes it
# has. None without partitions.
def classes.count(partitions: +List<U32>, +most: U32) -> U32:
  match partitions:
    case Nil{}: most
    case Con{+c, +rest}: classes.count(rest, U32.max(most, (c + 1 : U32)))

def dimensions.of(classes: +List<Class>, +i: U32) -> U32:
  match classes:
    case Nil{}: 0
    case Con{+c, +rest}: Bool.pick(U32, U32.is_eq(i, 0), Class.dimensions(c), dimensions.of(rest, (i - 1 : U32)))

# How many points the partitions add: each its class's dimensions.
def points.count(partitions: +List<U32>, +classes: +List<Class>, +total: U32) -> U32:
  match partitions:
    case Nil{}: total
    case Con{+c, +rest}: points.count(rest, classes, (total + dimensions.of(classes, c) : U32))

# A point of a floor: where it is and which it is.
type Point is Data:
  Point{x: U32, id: U32}

def Point.x(point: Point) -> U32:
  Point{x, _} = point
  x

def Point.id(point: Point) -> U32:
  Point{_, id} = point
  id

def point.insert(+p: Point, sorted: +List<Point>) -> +List<Point>:
  match sorted:
    case Nil{}: [p]
    case Con{+q, +rest}: Bool.pick(+List<Point>, (Point.x(p) < Point.x(q) : U32), Con{p, Con{q, rest}}, Con{q, point.insert(p, rest)})

# The points sorted by where they are (qsort, on places that are all
# different where the floor is valid).
def points.sorted(xs: +List<U32>, +id: U32, +sorted: +List<Point>) -> +List<Point>:
  match xs:
    case Nil{}: sorted
    case Con{+x, +rest}: points.sorted(rest, (id + 1 : U32), point.insert(Point{x, id}, sorted))

# Whether two points are at one place: an invalid setup.
def points.doubled(sorted: +List<Point>, +before: U32, +first: Bool, +doubled: Bool) -> Bool:
  match sorted:
    case Nil{}: doubled
    case Con{+p, +rest}: points.doubled(rest, Point.x(p), False{}, doubled || (Bool.not(first) && U32.is_eq(Point.x(p), before)))

def points.ids(sorted: +List<Point>, acc: +List<U32>) -> +List<U32>:
  match sorted:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+p, +rest}: points.ids(rest, Con{Point.id(p), acc})

# neighbors(): among the points before one, the nearest below it (the one
# with the largest place under its own) and, with `above`, the nearest above
# it; 0 where there is none. `best` is the place found so far and 1 for
# below (0: none yet), the place itself for above (65536: none yet).
def neighbor(before: +List<U32>, +x: U32, +above: Bool, +at: U32, +best: U32, +found: U32) -> U32:
  match before:
    case Nil{}: found
    case Con{+v, +rest}:
      +nearer = (above && (v < best : U32) && (v > x : U32)) || (Bool.not(above) && ((v + 1) > best : U32) && (v < x : U32))
      neighbor(rest, x, above, (at + 1 : U32), Bool.pick(U32, nearer, Bool.pick(U32, above, v, (v + 1 : U32)), best), Bool.pick(U32, nearer, at, found))

# The neighbours of every point from the third on.
def neighbors(n: Nat, +xs: +List<U32>, +j: U32, +above: Bool, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: neighbors(k, xs, (j + 1 : U32), above, Con{neighbor(O.firsts(U32.to_nat(j), xs, Nil{}), nth(xs, j), above, 0, Bool.pick(U32, above, 65536, 0), 0), acc})

# A floor of type 1. Its points' places begin with 0 and 1 << rangebits;
# `order` is the points from the lowest place to the highest, `lows` and
# `highs` each point's neighbours among the points before it, from the
# third point on.
type Floor is Data:
  Floor{partitions: +List<U32>, classes: +List<Class>, multiplier: U32, rangebits: U32, xs: +List<U32>, order: +List<U32>, lows: +List<U32>, highs: +List<U32>}

# The floors read so far, the last first.
type Floors is Data:
  Floors{reader: O.Reader, status: S.Status, floors: +List<Floor>}

def Floors.reader(state: Floors) -> O.Reader:
  Floors{reader, _, _} = state
  reader

def Floors.status(state: Floors) -> S.Status:
  Floors{_, status, _} = state
  status

def Floors.floors(state: Floors) -> +List<Floor>:
  Floors{_, _, floors} = state
  floors

def floor.made(+reader: O.Reader, +partitions: +List<U32>, +classes: +List<Class>, +multiplier: U32, +rangebits: U32, +xs: +List<U32>, +sorted: +List<Point>, +acc: +List<Floor>) -> Floors:
  Floors{reader, Bool.pick(S.Status, points.doubled(sorted, 0, True{}, False{}), S.Failed{20}, S.Going{}),
    Con{Floor{partitions, classes, multiplier, rangebits, xs, points.ids(sorted, Nil{}), neighbors(U32.to_nat((count.of(xs, 0) - 2 : U32)), xs, 2, False{}, Nil{}), neighbors(U32.to_nat((count.of(xs, 0) - 2 : U32)), xs, 2, True{}, Nil{})}, acc}}

def floor.pointed(+read: S.Words, +partitions: +List<U32>, +classes: +List<Class>, +multiplier: U32, +rangebits: U32, +acc: +List<Floor>) -> Floors:
  floor.made(S.Words.reader(read), partitions, classes, multiplier, rangebits, Con{0, Con{(1 << U32.to_nat(rangebits) : U32), S.Words.values(read)}},
    points.sorted(Con{0, Con{(1 << U32.to_nat(rangebits) : U32), S.Words.values(read)}}, 0, Nil{}), acc)

# After the classes: the multiplier (2 bits and 1), the bits of a place
# (4), and a place for each point the partitions add.
def floor.classed(on: Bool, +state: Classes, +partitions: +List<U32>, +acc: +List<Floor>) -> Floors:
  match on:
    case False{}: Floors{Classes.reader(state), Classes.status(state), acc}
    case True{}:
      +times = O.bits.get(2, Classes.reader(state))
      +multiplier = (O.Reader.value(times) + 1 : U32)
      +range = O.bits.get(4, times)
      +rangebits = O.Reader.value(range)
      floor.pointed(S.words.read(U32.to_nat(points.count(partitions, List.reverse(&2, Class, Classes.classes(state)), 0)), rangebits, range, Nil{}), partitions,
        List.reverse(&2, Class, Classes.classes(state)), multiplier, rangebits, acc)

def floor.classes(+state: Classes, +partitions: +List<U32>, +acc: +List<Floor>) -> Floors:
  floor.classed(S.going(Classes.status(state)), state, partitions, acc)

# The partitions' classes (4 bits each), then the classes.
def floor.partitioned(+read: S.Words, +books: U32, +acc: +List<Floor>) -> Floors:
  floor.classes(classes.each(U32.to_nat(classes.count(S.Words.values(read), 0)), True{}, books, Classes{S.Words.reader(read), S.Going{}, Nil{}}), S.Words.values(read), acc)

def floor.partitions(+reader: O.Reader, +books: U32, +acc: +List<Floor>) -> Floors:
  floor.partitioned(S.words.read(U32.to_nat(O.Reader.value(reader)), 4, reader, Nil{}), books, acc)

# kind: the floor's type, 16 bits. 0 is a floor stb_vorbis does not decode
# (VORBIS_feature_not_supported, 4); over 1 is an invalid setup.
def floor.kind(kind: U32, +reader: O.Reader, +books: U32, +acc: +List<Floor>) -> Floors:
  match kind:
    case 0: Floors{reader, S.Failed{4}, acc}
    case 1: floor.partitions(O.bits.get(5, reader), books, acc)
    case _: Floors{reader, S.Failed{20}, acc}

def floor.read(+reader: O.Reader, +books: U32, +acc: +List<Floor>) -> Floors:
  floor.kind(O.Reader.value(reader), reader, books, acc)

def floors.each(n: Nat, on: Bool, +books: U32, +state: Floors) -> Floors:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = floor.read(O.bits.get(16, Floors.reader(state)), books, Floors.floors(state))
      floors.each(k, S.going(Floors.status(next)), books, next)

# -----------------------------------------------------------------------------
# Residues

# A residue: its type (0 to 2), where it begins and ends, the size of a
# partition, how many classifications a partition can have, the codebook
# that codes them, and for each classification its eight codebooks, -1
# (4294967295) where it has none.
type Residue is Data:
  Residue{kind: U32, begin: U32, end: U32, part_size: U32, classifications: U32, classbook: U32, books: +List<+List<U32>>}

# The residues read so far, the last first.
type Residues is Data:
  Residues{reader: O.Reader, status: S.Status, residues: +List<Residue>}

def Residues.reader(state: Residues) -> O.Reader:
  Residues{reader, _, _} = state
  reader

def Residues.status(state: Residues) -> S.Status:
  Residues{_, status, _} = state
  status

def Residues.residues(state: Residues) -> +List<Residue>:
  Residues{_, _, residues} = state
  residues

# A classification's cascade: 3 low bits, and 5 high ones where a bit says
# so: which of its eight codebooks it has.
def cascades(n: Nat, +reader: O.Reader, +acc: +List<U32>) -> S.Words:
  match n:
    case 0n: S.Words{reader, List.reverse(&2, U32, acc)}
    case 1n+k:
      +low = O.bits.get(3, reader)
      +few = O.Reader.value(low)
      +more = O.bits.get(1, low)
      +high = Bool.pick(O.Reader, U32.is_eq(O.Reader.value(more), 1), O.bits.get(5, more), O.Reader.answer(more, 0))
      cascades(k, high, Con{((O.Reader.value(high) * 8) + few : U32), acc})

# A classification's eight codebooks, with whether one is past the
# codebooks.
type Row is Data:
  Row{reader: O.Reader, over: Bool, books: +List<U32>}

def row.read(n: Nat, +bit: U32, +cascade: U32, +count: U32, +reader: O.Reader, +over: Bool, +acc: +List<U32>) -> Row:
  match n:
    case 0n: Row{reader, over, List.reverse(&2, U32, acc)}
    case 1n+k:
      +next = Bool.pick(O.Reader, U32.is_ne((cascade .&. bit : U32), 0), O.bits.get(8, reader), O.Reader.answer(reader, 4294967295))
      row.read(k, (bit << 1n : U32), cascade, count, next, over || (U32.is_ne((cascade .&. bit : U32), 0) && (O.Reader.value(next) >= count : U32)), Con{O.Reader.value(next), acc})

# The rows read so far, the last first.
type Rows is Data:
  Rows{reader: O.Reader, over: Bool, rows: +List<+List<U32>>}

def rows.put(row: Row, +acc: +List<+List<U32>>) -> Rows:
  Row{reader, over, books} = row
  Rows{reader, over, Con{books, acc}}

def Rows.reader(state: Rows) -> O.Reader:
  Rows{reader, _, _} = state
  reader

def Rows.over(state: Rows) -> Bool:
  Rows{_, over, _} = state
  over

def Rows.rows(state: Rows) -> +List<+List<U32>>:
  Rows{_, _, rows} = state
  rows

def rows.each(list: +List<U32>, on: Bool, +count: U32, +state: Rows) -> Rows:
  match list on:
    case _ False{}: state
    case Nil{} True{}: state
    case Con{+cascade, +rest} True{}:
      +next = rows.put(row.read(8n, 1, cascade, count, Rows.reader(state), False{}, Nil{}), Rows.rows(state))
      rows.each(rest, Bool.not(Rows.over(next)), count, next)

# The classbook's entries times its dimensions: stb_vorbis allocates as
# many bytes, a classification for each dimension of each entry.
def classdata(books: +List<S.Codebook>, +i: U32) -> U32:
  match books:
    case Nil{}: 0
    case Con{S.Codebook{+dimensions, +entries, _, _, _, _, _, _, _, _}, +rest}: Bool.pick(U32, U32.is_eq(i, 0), Bool.pick(U32, (dimensions > (16777216 / U32.max(entries, 1)) : U32), 16777217, (entries * dimensions : U32)), classdata(rest, (i - 1 : U32)))

def residue.made(+rows: Rows, +status: S.Status, +kind: U32, +begin: U32, +end: U32, +part_size: U32, +classifications: U32, +classbook: U32, +data: U32, +acc: +List<Residue>) -> Residues:
  Residues{Rows.reader(rows), S.checked([S.Check{Bool.not(S.going(status)), status}, S.Check{Rows.over(rows), S.Failed{20}}, S.Check{(data > 16777216 : U32), S.Refused{3}}], S.Going{}, True{}),
    Con{Residue{kind, begin, end, part_size, classifications, classbook, List.reverse(&2, +List<U32>, Rows.rows(rows))}, acc}}

def residue.rows(+read: S.Words, +status: S.Status, +count: U32, +kind: U32, +begin: U32, +end: U32, +part_size: U32, +classifications: U32, +classbook: U32, +data: U32, +acc: +List<Residue>) -> Residues:
  residue.made(rows.each(S.Words.values(read), S.going(status), count, Rows{S.Words.reader(read), False{}, Nil{}}), status, kind, begin, end, part_size, classifications, classbook, data, acc)

# A residue: 16 bits of type (over 2 is an invalid setup), 24 of begin, 24
# of end (not under begin), 24 of partition size and 1, 6 of
# classifications and 1, 8 of classbook (a codebook), the cascades and the
# codebooks.
def residue.read(+reader: O.Reader, +books: +List<S.Codebook>, +count: U32, +acc: +List<Residue>) -> Residues:
  +typed = O.bits.get(16, reader)
  +kind = O.Reader.value(typed)
  +start = O.bits.get(24, typed)
  +begin = O.Reader.value(start)
  +stop = O.bits.get(24, start)
  +end = O.Reader.value(stop)
  +size = O.bits.get(24, stop)
  +part_size = (O.Reader.value(size) + 1 : U32)
  +classes = O.bits.get(6, size)
  +classifications = (O.Reader.value(classes) + 1 : U32)
  +book = O.bits.get(8, classes)
  +classbook = O.Reader.value(book)
  +status = S.checked([S.Check{(kind > 2 : U32), S.Failed{20}}, S.Check{(end < begin : U32), S.Failed{20}}, S.Check{(classbook >= count : U32), S.Failed{20}}], S.Going{}, True{})
  residue.rows(cascades(U32.to_nat(Bool.pick(U32, S.going(status), classifications, 0)), book, Nil{}), status, count, kind, begin, end, part_size, classifications, classbook, classdata(books, classbook), acc)

def residues.each(n: Nat, on: Bool, +books: +List<S.Codebook>, +count: U32, +state: Residues) -> Residues:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = residue.read(Residues.reader(state), books, count, Residues.residues(state))
      residues.each(k, S.going(Residues.status(next)), books, count, next)

# -----------------------------------------------------------------------------
# Mappings

# A mapping: the channel pairs it couples (a magnitude and an angle
# channel each), each channel's submap, and each submap's floor and
# residue.
type Mapping is Data:
  Mapping{magnitudes: +List<U32>, angles: +List<U32>, mux: +List<U32>, submaps: U32, floors: +List<U32>, residues: +List<U32>}

# The mappings read so far, the last first.
type Mappings is Data:
  Mappings{reader: O.Reader, status: S.Status, mappings: +List<Mapping>}

def Mappings.reader(state: Mappings) -> O.Reader:
  Mappings{reader, _, _} = state
  reader

def Mappings.status(state: Mappings) -> S.Status:
  Mappings{_, status, _} = state
  status

def Mappings.mappings(state: Mappings) -> +List<Mapping>:
  Mappings{_, _, mappings} = state
  mappings

# Lists read side by side, with whether a test on them failed.
type Pairs is Data:
  Pairs{reader: O.Reader, bad: Bool, firsts: +List<U32>, seconds: +List<U32>}

def Pairs.reader(pairs: Pairs) -> O.Reader:
  Pairs{reader, _, _, _} = pairs
  reader

def Pairs.bad(pairs: Pairs) -> Bool:
  Pairs{_, bad, _, _} = pairs
  bad

def Pairs.firsts(pairs: Pairs) -> +List<U32>:
  Pairs{_, _, firsts, _} = pairs
  firsts

def Pairs.seconds(pairs: Pairs) -> +List<U32>:
  Pairs{_, _, _, seconds} = pairs
  seconds

# The coupling steps: a magnitude and an angle channel in as many bits as
# the last channel's number takes, two channels of the stream that are not
# one.
def couplings(n: Nat, +bits: U32, +channels: U32, +reader: O.Reader, +bad: Bool, +magnitudes: +List<U32>, +angles: +List<U32>) -> Pairs:
  match n:
    case 0n: Pairs{reader, bad, List.reverse(&2, U32, magnitudes), List.reverse(&2, U32, angles)}
    case 1n+k:
      +first = O.bits.get(bits, reader)
      +magnitude = O.Reader.value(first)
      +second = O.bits.get(bits, first)
      +angle = O.Reader.value(second)
      couplings(k, bits, channels, second, bad || (magnitude >= channels : U32) || (angle >= channels : U32) || U32.is_eq(magnitude, angle), Con{magnitude, magnitudes}, Con{angle, angles})

# The submaps: 8 bits that are dropped, a floor and a residue.
def submaps(n: Nat, +floors: U32, +residues: U32, +reader: O.Reader, +bad: Bool, +first: +List<U32>, +second: +List<U32>) -> Pairs:
  match n:
    case 0n: Pairs{reader, bad, List.reverse(&2, U32, first), List.reverse(&2, U32, second)}
    case 1n+k:
      +floor = O.bits.get(8, O.bits.get(8, reader))
      +under = O.Reader.value(floor)
      +residue = O.bits.get(8, floor)
      +over = O.Reader.value(residue)
      submaps(k, floors, residues, residue, bad || (under >= floors : U32) || (over >= residues : U32), Con{under, first}, Con{over, second})

# Whether a channel's submap is not one of the mapping's.
def mux.over(values: +List<U32>, +submaps: U32, +over: Bool) -> Bool:
  match values:
    case Nil{}: over
    case Con{+v, +rest}: mux.over(rest, submaps, over || (v >= submaps : U32))

def mapping.made(+subs: Pairs, +status: S.Status, +coupled: Pairs, +mux: +List<U32>, +count: U32, +acc: +List<Mapping>) -> Mappings:
  Mappings{Pairs.reader(subs), S.checked([S.Check{Bool.not(S.going(status)), status}, S.Check{Pairs.bad(subs), S.Failed{20}}, S.Check{U32.is_eq(count, 16), S.Refused{2}}], S.Going{}, True{}),
    Con{Mapping{Pairs.firsts(coupled), Pairs.seconds(coupled), mux, count, Pairs.firsts(subs), Pairs.seconds(subs)}, acc}}

# After the coupling: 2 reserved bits that must be 0, a submap for each
# channel where the mapping has more than one (4 bits), and the submaps. A
# sixteenth submap is refused, once the fifteen before it have passed their
# tests: stb_vorbis has room for 15.
def mapping.muxed(+read: S.Words, +status: S.Status, +coupled: Pairs, +count: U32, +floors: U32, +residues: U32, +acc: +List<Mapping>) -> Mappings:
  +fine = S.checked([S.Check{Bool.not(S.going(status)), status}, S.Check{mux.over(S.Words.values(read), count, False{}), S.Failed{20}}], S.Going{}, True{})
  mapping.made(submaps(U32.to_nat(Bool.pick(U32, S.going(fine), U32.min(count, 15), 0)), floors, residues, S.Words.reader(read), False{}, Nil{}, Nil{}), fine, coupled, S.Words.values(read), count, acc)

def mapping.coupled(+coupled: Pairs, +status: S.Status, +count: U32, +channels: U32, +floors: U32, +residues: U32, +acc: +List<Mapping>) -> Mappings:
  +reserved = O.bits.get(2, Pairs.reader(coupled))
  +fine = S.checked([S.Check{Bool.not(S.going(status)), status}, S.Check{Pairs.bad(coupled), S.Failed{20}}, S.Check{U32.is_ne(O.Reader.value(reserved), 0), S.Failed{20}}], S.Going{}, True{})
  mapping.muxed(S.words.read(U32.to_nat(Bool.pick(U32, S.going(fine), channels, 0)), Bool.pick(U32, (count > 1 : U32), 4, 0), reserved, Nil{}), fine, coupled, count, floors, residues, acc)

# A mapping: 16 bits of type (0), the submaps (4 bits and 1 where a bit
# says so, else 1), the coupling steps (8 bits and 1 where a bit says so,
# no more than the channels).
def mapping.read(+reader: O.Reader, +channels: U32, +floors: U32, +residues: U32, +acc: +List<Mapping>) -> Mappings:
  +typed = O.bits.get(16, reader)
  +kind = O.Reader.value(typed)
  +several = O.bits.get(1, typed)
  +many = Bool.pick(O.Reader, U32.is_eq(O.Reader.value(several), 1), O.bits.get(4, several), O.Reader.answer(several, 0))
  +count = (O.Reader.value(many) + 1 : U32)
  +couples = O.bits.get(1, many)
  +stepped = Bool.pick(O.Reader, U32.is_eq(O.Reader.value(couples), 1), O.bits.get(8, couples), O.Reader.answer(couples, 4294967295))
  +steps = (O.Reader.value(stepped) + 1 : U32)
  +status = S.checked([S.Check{U32.is_ne(kind, 0), S.Failed{20}}, S.Check{(steps > channels : U32), S.Failed{20}}], S.Going{}, True{})
  mapping.coupled(couplings(U32.to_nat(Bool.pick(U32, S.going(status), steps, 0)), C.ilog((channels - 1 : U32)), channels, stepped, False{}, Nil{}, Nil{}), status, count, channels, floors, residues, acc)

def mappings.each(n: Nat, on: Bool, +channels: U32, +floors: U32, +residues: U32, +state: Mappings) -> Mappings:
  match n on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+k True{}:
      +next = mapping.read(Mappings.reader(state), channels, floors, residues, Mappings.mappings(state))
      mappings.each(k, S.going(Mappings.status(next)), channels, floors, residues, next)

# -----------------------------------------------------------------------------
# Modes

# A mode: which of the two block sizes its packets have, and their mapping.
type Mode is Data:
  Mode{blockflag: U32, mapping: U32}

# The modes read so far, the last first.
type Modes is Data:
  Modes{reader: O.Reader, status: S.Status, modes: +List<Mode>}

# A bit of block size, 16 of window type and 16 of transform type that
# must be 0, 8 of mapping (one of the mappings).
def modes.each(n: Nat, on: Bool, +mappings: U32, +reader: O.Reader, +acc: +List<Mode>) -> Modes:
  match n on:
    case _ False{}: Modes{reader, S.Failed{20}, List.reverse(&2, Mode, acc)}
    case 0n True{}: Modes{reader, S.Going{}, List.reverse(&2, Mode, acc)}
    case 1n+k True{}:
      +flag = O.bits.get(1, reader)
      +blockflag = O.Reader.value(flag)
      +window = O.bits.get(16, flag)
      +windowtype = O.Reader.value(window)
      +transform = O.bits.get(16, window)
      +transformtype = O.Reader.value(transform)
      +mapped = O.bits.get(8, transform)
      modes.each(k, U32.is_eq(windowtype, 0) && U32.is_eq(transformtype, 0) && (O.Reader.value(mapped) < mappings : U32), mappings, mapped, Con{Mode{blockflag, O.Reader.value(mapped)}, acc})

# -----------------------------------------------------------------------------
# The setup header after the codebooks

def count.floors(xs: +List<Floor>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count.floors(rest, (n + 1 : U32))

def count.residues(xs: +List<Residue>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count.residues(rest, (n + 1 : U32))

def count.mappings(xs: +List<Mapping>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count.mappings(rest, (n + 1 : U32))

def count.books(xs: +List<S.Codebook>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: count.books(rest, (n + 1 : U32))

# What the rest of the setup header gives: the reader after the header (its
# packet flushed), how far the setup came (`stage`: 0 not to the floors, 1
# to 4 into the floors, the residues, the mappings, the modes, 5 to the
# end), the floors, residues, mappings and modes in their order (those of
# a stage that failed are not whole), and first_audio_page_offset: where
# the data is if the header's page is used up, else 0.
type Maps is Data:
  Maps{reader: O.Reader, status: S.Status, stage: U32, floors: +List<Floor>, residues: +List<Residue>, mappings: +List<Mapping>, modes: +List<Mode>, audio: U32}

def Maps.status(setup: Maps) -> S.Status:
  Maps{_, status, _, _, _, _, _, _} = setup
  status

def Maps.reader(setup: Maps) -> O.Reader:
  Maps{reader, _, _, _, _, _, _, _} = setup
  reader

def Maps.stage(setup: Maps) -> U32:
  Maps{_, _, stage, _, _, _, _, _} = setup
  stage

def Maps.floors(setup: Maps) -> +List<Floor>:
  Maps{_, _, _, floors, _, _, _, _} = setup
  floors

def Maps.residues(setup: Maps) -> +List<Residue>:
  Maps{_, _, _, _, residues, _, _, _} = setup
  residues

def Maps.mappings(setup: Maps) -> +List<Mapping>:
  Maps{_, _, _, _, _, mappings, _, _} = setup
  mappings

def Maps.modes(setup: Maps) -> +List<Mode>:
  Maps{_, _, _, _, _, _, modes, _} = setup
  modes

def Maps.audio(setup: Maps) -> U32:
  Maps{_, _, _, _, _, _, _, audio} = setup
  audio

def maps.ended(+reader: O.Reader, +floors: +List<Floor>, +residues: +List<Residue>, +mappings: +List<Mapping>, +modes: +List<Mode>) -> Maps:
  Maps{reader, S.Going{}, 5, floors, residues, mappings, modes, Bool.pick(U32, U32.is_eq(O.Page.next(O.Reader.page(reader)), 4294967295), O.Stream.at(O.Reader.stream(reader)), 0)}

def maps.moded(modes: Modes, +floors: +List<Floor>, +residues: +List<Residue>, +mappings: +List<Mapping>) -> Maps:
  match modes:
    case Modes{+reader, S.Going{}, +list}: maps.ended(O.flush.packet(reader), floors, residues, mappings, list)
    case Modes{+reader, +status, +list}: Maps{reader, status, 4, floors, residues, mappings, list, 0}

# `reader` has just answered the count of modes less 1 (6 bits).
def maps.modes.read(+reader: O.Reader, +floors: +List<Floor>, +residues: +List<Residue>, +mappings: +List<Mapping>) -> Maps:
  maps.moded(modes.each(U32.to_nat((O.Reader.value(reader) + 1 : U32)), True{}, count.mappings(mappings, 0), reader, Nil{}), floors, residues, mappings)

def maps.mapped(on: Bool, +state: Mappings, +floors: +List<Floor>, +residues: +List<Residue>) -> Maps:
  match on:
    case False{}: Maps{Mappings.reader(state), Mappings.status(state), 3, floors, residues, List.reverse(&2, Mapping, Mappings.mappings(state)), Nil{}, 0}
    case True{}: maps.modes.read(O.bits.get(6, Mappings.reader(state)), floors, residues, List.reverse(&2, Mapping, Mappings.mappings(state)))

def maps.mappings.read(+state: Mappings, +floors: +List<Floor>, +residues: +List<Residue>) -> Maps:
  maps.mapped(S.going(Mappings.status(state)), state, floors, residues)

def maps.residued(on: Bool, +state: Residues, +channels: U32, +floors: +List<Floor>) -> Maps:
  match on:
    case False{}: Maps{Residues.reader(state), Residues.status(state), 2, floors, List.reverse(&2, Residue, Residues.residues(state)), Nil{}, Nil{}, 0}
    case True{}:
      +count = O.bits.get(6, Residues.reader(state))
      maps.mappings.read(mappings.each(U32.to_nat((O.Reader.value(count) + 1 : U32)), True{}, channels, count.floors(floors, 0), count.residues(Residues.residues(state), 0), Mappings{count, S.Going{}, Nil{}}), floors,
        List.reverse(&2, Residue, Residues.residues(state)))

def maps.residues.read(+state: Residues, +channels: U32, +floors: +List<Floor>) -> Maps:
  maps.residued(S.going(Residues.status(state)), state, channels, floors)

def maps.floored(on: Bool, +state: Floors, +channels: U32, +books: +List<S.Codebook>) -> Maps:
  match on:
    case False{}: Maps{Floors.reader(state), Floors.status(state), 1, List.reverse(&2, Floor, Floors.floors(state)), Nil{}, Nil{}, Nil{}, 0}
    case True{}:
      +count = O.bits.get(6, Floors.reader(state))
      maps.residues.read(residues.each(U32.to_nat((O.Reader.value(count) + 1 : U32)), True{}, books, count.books(books, 0), Residues{count, S.Going{}, Nil{}}), channels, List.reverse(&2, Floor, Floors.floors(state)))

def maps.floors.read(+state: Floors, +channels: U32, +books: +List<S.Codebook>) -> Maps:
  maps.floored(S.going(Floors.status(state)), state, channels, books)

def maps.begun(on: Bool, +setup: S.Setup) -> Maps:
  match on:
    case False{}: Maps{S.Setup.reader(setup), S.Setup.status(setup), 0, Nil{}, Nil{}, Nil{}, Nil{}, 0}
    case True{}:
      +count = O.bits.get(6, S.Setup.reader(setup))
      maps.floors.read(floors.each(U32.to_nat((O.Reader.value(count) + 1 : U32)), True{}, count.books(S.Setup.books(setup), 0), Floors{count, S.Going{}, Nil{}}), S.Head.channels(S.Setup.head(setup)), S.Setup.books(setup))

# The setup header from its floors on, where the codebooks were read: each
# section a count of 6 bits and 1. The packet is flushed at the end.
def maps.read(+setup: S.Setup) -> Maps:
  maps.begun(S.going(S.Setup.status(setup)), setup)
