# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered sdefl quality-8 adaptation, Copyright (c) 2020-2023 Micha Mettke (MIT).
# Required license: LICENSES/sdefl.txt. Private bounded raw compressor parsing.
import Base
import ./deflate.bend as D

type Sequence is Data:
  Literals{offset: U32, length: U32}
  Match{distance: U32, length: U32}

type Block is Type:
  Block{begin: U32, end: U32, sequences: +List<Sequence>, literals: Array<U32>, distances: Array<U32>}

type Core is Type:
  Core{input: Array<U32>, table: Array<U32>, previous: Array<U32>}

type Accum is Type:
  Accum{count: U32, sequences: +List<Sequence>, literals: Array<U32>, distances: Array<U32>}

type Parsing is Type:
  Parsing{core: Core, accum: Accum, position: U32, pending: U32}
  Parsed{core: Core, accum: Accum, pending: U32}
  Rejected{}

type Best is Data:
  Best{length: U32, distance: U32}

type Search is Type:
  Search{core: Core, best: Best, candidate: U32}

def hash(value: U32) -> U32:
  ((value * 2654435209) >> 17n : U32)

def length_code(last: Bool, +length: U32) -> U32:
  match last:
    case True{}: 285
    case False{}:
      +extra = (U32.log2((length - 3 : U32)) - 2n : Nat)
      (257 + 4 * U32.from_nat(extra) + ((length - 3) >> extra) : U32)

def distance_code(+distance: U32) -> U32:
  +extra = (U32.log2((distance - 1 : U32)) - 1n : Nat)
  (2 * U32.from_nat(extra) + ((distance - 1) >> extra) : U32)

def increment(+index: U32, result: Array<U32> & U32) -> Array<U32>:
  (values, value) = result
  Array.set(U32, values, index, (value + 1 : U32))

def append(valid: Bool, sequence: Sequence, accum: Accum) -> Maybe<Accum>:
  match valid accum:
    case False{} _: None{}
    case True{} Accum{count, sequences, literals, distances}:
      Some{Accum{(count + 1 : U32), Con{sequence, sequences}, literals, distances}}

def add(sequence: Sequence, accum: Accum) -> Maybe<Accum>:
  Accum{+count, sequences, literals, distances} = accum
  append((count < 87380 : U32), sequence, Accum{count, sequences, literals, distances})

def search.next(best: Best, input: Array<U32>, table: Array<U32>, result: Array<U32> & U32) -> Search:
  (previous, candidate) = result
  Search{Core{input, table, previous}, best, candidate}

def search.follow(done: Bool, +candidate: U32, best: Best, core: Core) -> Search:
  match done core:
    case True{} _: Search{core, best, 4294967295}
    case False{} Core{input, table, previous}:
      search.next(best, input, table, Array.get(U32, previous, (candidate .&. 32767 : U32)))

def search.counted(+position: U32, +candidate: U32, maximum: U32, +best: Best, table: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Search:
  Best{old, _} = best
  (input, +length) = result
  search.follow(U32.is_eq(length, maximum), candidate,
    Bool.pick(Best, (length > old : U32), Best{length, (position - candidate : U32)}, best), Core{input, table, previous})

def search.words(same: Bool, +position: U32, +candidate: U32, +maximum: U32, best: Best, core: Core) -> Search:
  match same core:
    case False{} _: search.follow(False{}, candidate, best, core)
    case True{} Core{input, table, previous}:
      search.counted(position, candidate, maximum, best, table, previous,
        D.count(U32.to_nat((maximum - 4 : U32)), (candidate + 4 : U32), (position + 4 : U32), D.Counting{input, 4, True{}}))

def search.other(position: U32, candidate: U32, maximum: U32, best: Best, word: U32, table: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Search:
  (input, other) = result
  search.words(U32.is_eq(word, other), position, candidate, maximum, best, Core{input, table, previous})

def search.word(+position: U32, candidate: U32, maximum: U32, best: Best, table: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Search:
  (input, word) = result
  search.other(position, candidate, maximum, best, word, table, previous, D.word(4n, position, 0n, (input, 0)))

def search.equal(same: Bool, position: U32, +candidate: U32, maximum: U32, best: Best, core: Core) -> Search:
  match same core:
    case False{} _: search.follow(False{}, candidate, best, core)
    case True{} Core{input, table, previous}:
      search.word(position, candidate, maximum, best, table, previous, D.word(4n, candidate, 0n, (input, 0)))

def search.checked(position: U32, candidate: U32, maximum: U32, best: Best, table: Array<U32>, previous: Array<U32>, result: Array<U32> & Bool) -> Search:
  (input, same) = result
  search.equal(same, position, candidate, maximum, best, Core{input, table, previous})

def search.step(+position: U32, maximum: U32, state: Search) -> Search:
  Search{Core{input, table, previous}, +best, +candidate} = state
  Best{length, _} = best
  search.checked(position, candidate, maximum, best, table, previous,
    D.equal.left((position + length : U32), Array.get(U32, input, (candidate + length : U32))))

def searching.step(valid: Bool, position: U32, maximum: U32, state: Search) -> Search:
  match valid state:
    case False{} Search{core, best, _}: Search{core, best, 4294967295}
    case True{} _: search.step(position, maximum, state)

def searching(n: Nat, +position: U32, +maximum: U32, state: Search) -> Search:
  match n state:
    case 0n _: state
    case _ Search{core, best, 4294967295}: Search{core, best, 4294967295}
    case 1n+rest Search{core, best, +candidate}:
      searching(rest, position, maximum, searching.step((position - candidate < 32768 : U32), position, maximum, Search{core, best, candidate}))

def search.bucket(position: U32, maximum: U32, input: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Search:
  (table, candidate) = result
  searching(8192n, position, maximum, Search{Core{input, table, previous}, Best{0, 0}, candidate})

def search.hashed(position: U32, maximum: U32, table: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Search:
  (input, value) = result
  search.bucket(position, maximum, input, previous, Array.get(U32, table, hash(value)))

def find(+position: U32, maximum: U32, core: Core) -> Search:
  Core{input, table, previous} = core
  search.hashed(position, maximum, table, previous, D.word(4n, position, 0n, (input, 0)))

def insert.bucket(+position: U32, +key: U32, input: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Core:
  (table, candidate) = result
  Core{input, Array.set(U32, table, key, position), Array.set(U32, previous, (position .&. 32767 : U32), candidate)}

def insert.word(position: U32, table: Array<U32>, previous: Array<U32>, result: Array<U32> & U32) -> Core:
  (input, value) = result
  +key = hash(value)
  insert.bucket(position, key, input, previous, Array.get(U32, table, key))

def insert(n: Nat, +position: U32, core: Core) -> Core:
  match n core:
    case 0n _: core
    case 1n+rest Core{input, table, previous}:
      insert(rest, (position + 1 : U32), insert.word(position, table, previous, D.word(4n, position, 0n, (input, 0))))

def advance(remember: Bool, +position: U32, +run: U32, pending: U32, core: Core, accum: Accum) -> Parsing:
  match remember:
    case False{}: Parsing{core, accum, (position + run : U32), pending}
    case True{}: Parsing{insert(U32.to_nat(run), position, core), accum, (position + run : U32), pending}

def matched(+position: U32, +size: U32, +distance: U32, +length: U32, core: Core, result: Maybe<Accum>) -> Parsing:
  match result:
    case None{}: Rejected{}
    case Some{Accum{count, sequences, literals, distances}}:
      +lc = length_code(U32.is_eq(length, 258), length)
      +dc = distance_code(distance)
      advance((size - position - length > 4 : U32), position, length, 0, core,
        Accum{count, sequences, increment(lc, Array.get(U32, literals, lc)), increment(dc, Array.get(U32, distances, dc))})

def match.pending(position: U32, size: U32, +distance: U32, +length: U32, core: Core, result: Maybe<Accum>) -> Parsing:
  match result:
    case None{}: Rejected{}
    case Some{accum}: matched(position, size, distance, length, core, add(Match{distance, length}, accum))

def match.start(has_pending: Bool, +position: U32, size: U32, +pending: U32, distance: U32, length: U32, core: Core, accum: Accum) -> Parsing:
  match has_pending:
    case False{}: match.pending(position, size, distance, length, core, Some{accum})
    case True{}: match.pending(position, size, distance, length, core, add(Literals{(position - pending : U32), pending}, accum))

def literal(+position: U32, +size: U32, pending: U32, table: Array<U32>, previous: Array<U32>, accum: Accum, result: Array<U32> & U32) -> Parsing:
  Accum{count, sequences, literals, distances} = accum
  (input, +byte) = result
  advance((size - position - 1 > 4 : U32), position, 1, (pending + 1 : U32), Core{input, table, previous},
    Accum{count, sequences, increment(byte, Array.get(U32, literals, byte)), distances})

def selected(use_match: Bool, +position: U32, size: U32, +pending: U32, best: Best, core: Core, accum: Accum) -> Parsing:
  match use_match best core:
    case True{} Best{length, distance} _: match.start((pending > 0 : U32), position, size, pending, distance, length, core, accum)
    case False{} _ Core{input, table, previous}: literal(position, size, pending, table, previous, accum, Array.get(U32, input, position))

def lazy.compared(position: U32, size: U32, pending: U32, +best: Best, accum: Accum, result: Search) -> Parsing:
  Best{old, _} = best
  Search{core, Best{new, _}, _} = result
  selected((new <= old : U32), position, size, pending, best, core, accum)

def lazy(valid: Bool, +position: U32, size: U32, pending: U32, +best: Best, core: Core, accum: Accum) -> Parsing:
  match valid best:
    case False{} Best{length, distance}: selected((length >= 4 : U32), position, size, pending, Best{length, distance}, core, accum)
    case True{} Best{length, _}: lazy.compared(position, size, pending, best, accum, find((position + 1 : U32), (length + 1 : U32), core))

def found(position: U32, size: U32, +maximum: U32, pending: U32, accum: Accum, result: Search) -> Parsing:
  Search{core, +best, _} = result
  Best{+length, _} = best
  lazy(((length >= 4) && (length + 1 < Bool.pick(U32, (maximum < 130 : U32), maximum, 130)) : U32),
    position, size, pending, best, core, accum)

def step(can_search: Bool, +position: U32, size: U32, +maximum: U32, pending: U32, core: Core, accum: Accum) -> Parsing:
  match can_search:
    case False{}: selected(False{}, position, size, pending, Best{0, 0}, core, accum)
    case True{}: found(position, size, maximum, pending, accum, find(position, maximum, core))

def parse.step(size: U32, +end: U32, active: Bool, core: Core, accum: Accum, +position: U32, pending: U32) -> Parsing:
  match active:
    case False{}: Parsed{core, accum, pending}
    case True{}:
      +left = (end - position : U32)
      +maximum = Bool.pick(U32, (left < 258 : U32), left, 258)
      step((maximum > 4 : U32), position, size, maximum, pending, core, accum)

def parse(n: Nat, +size: U32, +end: U32, state: Parsing) -> Parsing:
  match n state:
    case _ Rejected{}: Rejected{}
    case _ Parsed{core, accum, pending}: Parsed{core, accum, pending}
    case 0n _: state
    case 1n+rest Parsing{core, accum, +position, pending}:
      parse(rest, size, end, parse.step(size, end, (position < end : U32), core, accum, position, pending))

def finish.block(begin: U32, end: U32, core: Core, result: Maybe<Accum>) -> Maybe<&1, (Core & Block)>:
  match result:
    case None{}: None{}
    case Some{Accum{_, sequences, literals, distances}}:
      Some{(core, Block{begin, end, List.reverse(&2, Sequence, sequences), literals, distances})}

def finish.pending(has_pending: Bool, +begin: U32, +end: U32, +pending: U32, core: Core, accum: Accum) -> Maybe<&1, (Core & Block)>:
  match has_pending:
    case False{}: finish.block(begin, end, core, Some{accum})
    case True{}: finish.block(begin, end, core, add(Literals{(end - pending : U32), pending}, accum))

def finish(begin: U32, +end: U32, state: Parsing) -> Maybe<&1, (Core & Block)>:
  match state:
    case Rejected{}: None{}
    case Parsing{core, accum, _, +pending}: finish.pending((pending > 0 : U32), begin, end, pending, core, accum)
    case Parsed{core, accum, +pending}: finish.pending((pending > 0 : U32), begin, end, pending, core, accum)

def block(+size: U32, +begin: U32, +end: U32, core: Core) -> Maybe<&1, (Core & Block)>:
  finish(begin, end, parse(U32.to_nat((end - begin : U32)), size, end,
    Parsing{core, Accum{0, Nil{}, Array.new(U32, 9n, 0), Array.new(U32, 5n, 0)}, begin, 0}))
