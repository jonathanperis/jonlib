# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered sdefl quality-8 adaptation, Copyright (c) 2020-2023 Micha Mettke (MIT).
# Required license: LICENSES/sdefl.txt. Bounded little-endian raw compression.
import Base
import ./checksum.bend as C
import ./deflate.bend as D
import ./sdeflate_huffman.bend as H
import ./sdeflate_lz.bend as L

type Books is Type:
  Books{literal: H.Codes, distance: H.Codes}

type Prelude is Type:
  Prelude{books: Books, pre: H.Codes, items: +List<U32>, literals: U32, distances: U32, precodes: U32, cost: U32}

type Items is Type:
  Items{frequencies: Array<U32>, values: +List<U32>}

def item(+symbol: U32, extra: U32, state: Items) -> Items:
  Items{frequencies, values} = state
  Items{L.increment(symbol, Array.get(U32, frequencies, symbol)), Con{(symbol .|. (extra << 5n) : U32), values}}

type Run is Type:
  Run{remaining: U32, items: Items}

def run.zero(long: Bool, medium: Bool, +count: U32, items: Items) -> Run:
  match long medium:
    case True{} _:
      +extra = U32.min((count - 11 : U32), 127)
      Run{(count - 11 - extra : U32), item(18, extra, items)}
    case False{} True{}:
      +extra = U32.min((count - 3 : U32), 7)
      Run{(count - 3 - extra : U32), item(17, extra, items)}
    case False{} False{}: Run{(count - 1 : U32), item(0, 0, items)}

def run.nonzero(repeat: Bool, length: U32, +count: U32, items: Items) -> Run:
  match repeat:
    case True{}:
      +extra = U32.min((count - 3 : U32), 3)
      Run{(count - 3 - extra : U32), item(16, extra, items)}
    case False{}: Run{(count - 1 : U32), item(length, 0, items)}

def run.step(zero: Bool, +length: U32, +count: U32, repeating: Bool, items: Items) -> Run:
  match zero:
    case True{}: run.zero((count >= 11 : U32), (count >= 3 : U32), count, items)
    case False{}: run.nonzero(repeating && (count >= 3 : U32), length, count, items)

def runs(n: Nat, +length: U32, +repeating: Bool, state: Run) -> Items:
  match n state:
    case _ Run{0, items}: items
    case 0n Run{_, items}: items
    case 1n+rest Run{+count, items}:
      runs(rest, length, repeating, run.step(U32.is_eq(length, 0), length, count, repeating, items))

def run.start(repeating: Bool, +length: U32, +count: U32, items: Items) -> Items:
  match repeating:
    case False{}: runs(U32.to_nat(count), length, False{}, Run{count, items})
    case True{}: runs(U32.to_nat(count), length, True{}, Run{(count - 1 : U32), item(length, 0, items)})

def precode.run(+length: U32, +count: U32, items: Items) -> Items:
  run.start(((length > 0) && (count >= 4) : U32), length, count, items)

type Group is Type:
  Group{length: U32, count: U32, items: Items}

def group(same: Bool, next: U32, length: U32, count: U32, items: Items) -> Group:
  match same:
    case True{}: Group{length, (count + 1 : U32), items}
    case False{}: Group{next, 1, precode.run(length, count, items)}

def grouped(values: +List<U32>, state: Group) -> Items:
  match values state:
    case Nil{} Group{length, count, items}: precode.run(length, count, items)
    case Con{+value, rest} Group{+length, count, items}:
      grouped(rest, group(U32.is_eq(value, length), value, length, count, items))

def precode(values: +List<U32>) -> Items:
  match values:
    case Nil{}: Items{Array.new(U32, 5n, 0), Nil{}}
    case Con{value, rest}: grouped(rest, Group{value, 1, Items{Array.new(U32, 5n, 0), Nil{}}})

type Collected is Type:
  Collected{lengths: Array<U32>, values: +List<U32>, used: U32}

def collect.read(+index: U32, values: +List<U32>, used: U32, result: Array<U32> & U32) -> Collected:
  (lengths, +value) = result
  Collected{lengths, Con{value, values}, Bool.pick(U32, (value > 0 : U32), (index + 1 : U32), used)}

def collect(n: Nat, +index: U32, state: Collected) -> Collected:
  match n state:
    case 0n _: state
    case 1n+rest Collected{lengths, values, used}:
      collect(rest, (index + 1 : U32), collect.read(index, values, used, Array.get(U32, lengths, index)))

def length_extra(last: Bool, +symbol: U32) -> U32:
  match last:
    case True{}: 0
    case False{}: U32.from_nat((U32.to_nat(((symbol - 257) / 4 : U32)) - 1n : Nat))

def literal_extra(valid: Bool, +symbol: U32) -> U32:
  match valid:
    case False{}: 0
    case True{}: length_extra(U32.is_eq(symbol, 285), symbol)

def x_literal(+symbol: U32) -> U32:
  literal_extra((symbol >= 257 : U32), symbol)

def x_distance(symbol: U32) -> U32:
  U32.from_nat((U32.to_nat((symbol / 2 : U32)) - 1n : Nat))

def x_precode(symbol: U32) -> U32:
  match symbol:
    case 16: 2
    case 17: 3
    case 18: 7
    case _: 0

type Cost is Type:
  Cost{frequencies: Array<U32>, lengths: Array<U32>, total: U32}

def cost.length(frequency: U32, extra: U32, total: U32, frequencies: Array<U32>, result: Array<U32> & U32) -> Cost:
  (lengths, length) = result
  Cost{frequencies, lengths, (total + frequency * (length + extra) : U32)}

def cost.frequency(index: U32, extra: U32, lengths: Array<U32>, total: U32, result: Array<U32> & U32) -> Cost:
  (frequencies, frequency) = result
  cost.length(frequency, extra, total, frequencies, Array.get(U32, lengths, index))

def cost(~extra: U32 -> U32, n: Nat, +index: U32, state: Cost) -> Cost:
  match n state:
    case 0n _: state
    case 1n+rest Cost{frequencies, lengths, total}:
      cost(~extra, rest, (index + 1 : U32), cost.frequency(index, extra(index), lengths, total, Array.get(U32, frequencies, index)))

def permutation(index: U32) -> U32:
  match index:
    case 0: 16
    case 1: 17
    case 2: 18
    case 3: 0
    case 4: 8
    case 5: 7
    case 6: 9
    case 7: 6
    case 8: 10
    case 9: 5
    case 10: 11
    case 11: 4
    case 12: 12
    case 13: 3
    case 14: 13
    case 15: 2
    case 16: 14
    case 17: 1
    case _: 15

def pre_count.read(+index: U32, +used: U32, result: Array<U32> & U32) -> Array<U32> & U32:
  (lengths, value) = result
  (lengths, Bool.pick(U32, (value > 0 : U32), U32.max((index + 1 : U32), used), used))

def pre_count(n: Nat, +index: U32, state: Array<U32> & U32) -> Array<U32> & U32:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{lengths, used}:
      pre_count(rest, (index + 1 : U32), pre_count.read(index, used, Array.get(U32, lengths, permutation(index))))

def prepared(books: Books, items: +List<U32>, literals: U32, distances: U32, precodes: U32, words: Array<U32>, state: Cost) -> Prelude:
  Cost{_, lengths, total} = state
  Prelude{books, H.Codes{lengths, words}, items, literals, distances, precodes, total}

def pre_counted(books: Books, items: +List<U32>, literals: U32, distances: U32, total: U32, frequencies: Array<U32>, words: Array<U32>, result: Array<U32> & U32) -> Prelude:
  (lengths, +used) = result
  prepared(books, items, literals, distances, used, words,
    cost(~x_precode, 19n, 0, Cost{frequencies, lengths, (total + 14 + 3 * used : U32)}))

def pre_built(books: Books, items: +List<U32>, literals: U32, distances: U32, total: U32, result: Array<U32> & H.Codes) -> Prelude:
  (frequencies, H.Codes{lengths, words}) = result
  pre_counted(books, items, literals, distances, total, frequencies, words, pre_count(19n, 0, (lengths, 4)))

def items_built(books: Books, literals: U32, distances: U32, total: U32, state: Items) -> Prelude:
  Items{frequencies, values} = state
  pre_built(books, List.reverse(&2, U32, values), literals, distances, total, H.build(19, 7, frequencies))

def lengths.collected(lit_words: Array<U32>, dist_words: Array<U32>, total: U32, literal: Collected, distance: Collected) -> Prelude:
  Collected{lit_lengths, lit_values, +lit_used} = literal
  Collected{dist_lengths, dist_values, +dist_used} = distance
  +nl = U32.max(lit_used, 257)
  +nd = U32.max(dist_used, 1)
  values = List.append(&2, U32, List.take(&2, U32, List.reverse(&2, U32, lit_values), U32.to_nat(nl)),
    List.take(&2, U32, List.reverse(&2, U32, dist_values), U32.to_nat(nd)))
  items_built(Books{H.Codes{lit_lengths, lit_words}, H.Codes{dist_lengths, dist_words}}, nl, nd, total, precode(values))

def distance.costed(lit_words: Array<U32>, lit_lengths: Array<U32>, dist_words: Array<U32>, state: Cost) -> Prelude:
  Cost{_, dist_lengths, total} = state
  lengths.collected(lit_words, dist_words, total,
    collect(288n, 0, Collected{lit_lengths, Nil{}, 0}), collect(32n, 0, Collected{dist_lengths, Nil{}, 0}))

def literal.costed(distance_frequencies: Array<U32>, dist_codes: H.Codes, lit_words: Array<U32>, state: Cost) -> Prelude:
  H.Codes{dist_lengths, dist_words} = dist_codes
  Cost{_, lit_lengths, total} = state
  distance.costed(lit_words, lit_lengths, dist_words, cost(~x_distance, 32n, 0, Cost{distance_frequencies, dist_lengths, total}))

def distance.built(lit_frequencies: Array<U32>, lit_codes: H.Codes, result: Array<U32> & H.Codes) -> Prelude:
  H.Codes{lengths, words} = lit_codes
  (frequencies, codes) = result
  literal.costed(frequencies, codes, words, cost(~(x => x_literal(x)), 288n, 0, Cost{lit_frequencies, lengths, 0}))

def literal.built(distances: Array<U32>, result: Array<U32> & H.Codes) -> Prelude:
  (frequencies, codes) = result
  distance.built(frequencies, codes, H.build(32, 15, distances))

def prepare(literals: Array<U32>, distances: Array<U32>) -> Prelude:
  literal.built(distances, H.build(288, 14, L.increment(256, Array.get(U32, literals, 256))))

type Coded is Type:
  Coded{codes: H.Codes, writer: D.Writer}

def symbol.word(bits: U32, lengths: Array<U32>, writer: D.Writer, result: Array<U32> & U32) -> Coded:
  (words, value) = result
  Coded{H.Codes{lengths, words}, D.put(value, bits, writer)}

def symbol.length(index: U32, words: Array<U32>, writer: D.Writer, result: Array<U32> & U32) -> Coded:
  (lengths, bits) = result
  symbol.word(bits, lengths, writer, Array.get(U32, words, index))

def symbol(+index: U32, state: Coded) -> Coded:
  Coded{H.Codes{lengths, words}, writer} = state
  symbol.length(index, words, writer, Array.get(U32, lengths, index))

def pre_length.read(words: Array<U32>, writer: D.Writer, result: Array<U32> & U32) -> Coded:
  (lengths, value) = result
  Coded{H.Codes{lengths, words}, D.put(value, 3, writer)}

def pre_lengths(n: Nat, +index: U32, state: Coded) -> Coded:
  match n state:
    case 0n _: state
    case 1n+rest Coded{H.Codes{lengths, words}, writer}:
      pre_lengths(rest, (index + 1 : U32), pre_length.read(words, writer, Array.get(U32, lengths, permutation(index))))

def pre_item.extra(extra: U32, bits: U32, state: Coded) -> Coded:
  Coded{codes, writer} = state
  Coded{codes, D.put(extra, bits, writer)}

def pre_items(items: +List<U32>, state: Coded) -> D.Writer:
  match items state:
    case Nil{} Coded{_, writer}: writer
    case Con{+value, rest} _:
      +code = (value .&. 31 : U32)
      pre_items(rest, pre_item.extra((value >> 5n : U32), x_precode(code), symbol(code, state)))

type Emitting is Type:
  Emitting{input: Array<U32>, books: Books, writer: D.Writer}

def literal.emitted(input: Array<U32>, distance: H.Codes, state: Coded) -> Emitting:
  Coded{literal, writer} = state
  Emitting{input, Books{literal, distance}, writer}

def literal.read(books: Books, writer: D.Writer, result: Array<U32> & U32) -> Emitting:
  Books{literal, distance} = books
  (input, byte) = result
  literal.emitted(input, distance, symbol(byte, Coded{literal, writer}))

def literals(n: Nat, +index: U32, state: Emitting) -> Emitting:
  match n state:
    case 0n _: state
    case 1n+rest Emitting{input, books, writer}:
      literals(rest, (index + 1 : U32), literal.read(books, writer, Array.get(U32, input, index)))

def length_base(last: Bool, +length: U32) -> U32:
  match last:
    case True{}: 258
    case False{}:
      +extra = (U32.log2((length - 3 : U32)) - 2n : Nat)
      ((((length - 3) >> extra) << extra) + 3 : U32)

def match.distance(input: Array<U32>, literal: H.Codes, extra: U32, bits: U32, state: Coded) -> Emitting:
  Coded{distance, writer} = state
  Emitting{input, Books{literal, distance}, D.put(extra, bits, writer)}

def match.length(input: Array<U32>, distance_codes: H.Codes, +distance: U32, length_extra: U32, length_bits: U32, state: Coded) -> Emitting:
  Coded{literal, writer} = state
  +dx = (U32.log2((distance - 1 : U32)) - 1n : Nat)
  +base = ((((distance - 1) >> dx) << dx) + 1 : U32)
  match.distance(input, literal, (distance - base : U32), U32.from_nat(dx),
    symbol(L.distance_code(distance), Coded{distance_codes, D.put(length_extra, length_bits, writer)}))

def match.emit(+distance: U32, +length: U32, state: Emitting) -> Emitting:
  Emitting{input, Books{literal, distance_codes}, writer} = state
  +code = L.length_code(U32.is_eq(length, 258), length)
  match.length(input, distance_codes, distance, (length - length_base(U32.is_eq(length, 258), length) : U32), x_literal(code),
    symbol(code, Coded{literal, writer}))

def sequences(values: +List<L.Sequence>, state: Emitting) -> Emitting:
  match values:
    case Nil{}: state
    case Con{L.Literals{offset, length}, rest}: sequences(rest, literals(U32.to_nat(length), offset, state))
    case Con{L.Match{distance, length}, rest}: sequences(rest, match.emit(distance, length, state))

def dynamic.finished(input: Array<U32>, state: Coded) -> Array<U32> & D.Writer:
  Coded{_, writer} = state
  (input, writer)

def dynamic.sequences(state: Emitting) -> Array<U32> & D.Writer:
  Emitting{input, Books{literal, _}, writer} = state
  dynamic.finished(input, symbol(256, Coded{literal, writer}))

def dynamic(last: Bool, input: Array<U32>, values: +List<L.Sequence>, writer: D.Writer, state: Prelude) -> Array<U32> & D.Writer:
  Prelude{books, pre, items, nl, nd, +np, _} = state
  header = D.put((np - 4 : U32), 4, D.put((nd - 1 : U32), 5, D.put((nl - 257 : U32), 5, D.put(2, 2, D.put(Bool.to_u32(last), 1, writer)))))
  dynamic.sequences(sequences(values, Emitting{input, books, pre_items(items, pre_lengths(U32.to_nat(np), 0, Coded{pre, header}))}))

def stored.read(writer: D.Writer, result: Array<U32> & U32) -> Array<U32> & D.Writer:
  (input, byte) = result
  (input, D.byte(byte, writer))

def stored.bytes(n: Nat, +index: U32, state: Array<U32> & D.Writer) -> Array<U32> & D.Writer:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{input, writer}:
      stored.bytes(rest, (index + 1 : U32), stored.read(writer, Array.get(U32, input, index)))

def stored(n: Nat, +last: Bool, +begin: U32, +end: U32, state: Array<U32> & D.Writer) -> Array<U32> & D.Writer:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{input, writer}:
      +amount = U32.min((end - begin : U32), 65535)
      final = last && U32.is_eq((begin + amount : U32), end)
      header = D.put((amount .^. 65535 : U32), 16, D.put(amount, 16, D.pad(D.put(0, 2, D.put(Bool.to_u32(final), 1, writer)))))
      stored(rest, last, (begin + amount : U32), end, stored.bytes(U32.to_nat(amount), begin, (input, header)))

def choose(use_dynamic: Bool, last: Bool, +begin: U32, +end: U32, input: Array<U32>, values: +List<L.Sequence>, writer: D.Writer, state: Prelude) -> Array<U32> & D.Writer:
  match use_dynamic:
    case True{}: dynamic(last, input, values, writer, state)
    case False{}: stored(U32.to_nat(((end - begin + 65534) / 65535 : U32)), last, begin, end, (input, writer))

def prepared.block(last: Bool, +begin: U32, +end: U32, input: Array<U32>, values: +List<L.Sequence>, writer: D.Writer, state: Prelude) -> Array<U32> & D.Writer:
  Prelude{books, pre, items, nl, nd, np, +cost} = state
  stored_cost = (8 * (5 * ((end - begin + 65534) / 65535) + end - begin + 3) : U32)
  choose((cost < stored_cost : U32), last, begin, end, input, values, writer, Prelude{books, pre, items, nl, nd, np, cost})

def emitted(table: Array<U32>, previous: Array<U32>, result: Array<U32> & D.Writer) -> L.Core & D.Writer:
  (input, writer) = result
  (L.Core{input, table, previous}, writer)

def encoded(last: Bool, writer: D.Writer, result: Maybe<&1, (L.Core & L.Block)>) -> Maybe<&1, (L.Core & D.Writer)>:
  match result:
    case None{}: None{}
    case Some{Tuple{L.Core{input, table, previous}, L.Block{begin, end, values, literals, distances}}}:
      Some{emitted(table, previous, prepared.block(last, begin, end, input, values, writer, prepare(literals, distances)))}

def finished(writer: D.Writer) -> +List<U32>:
  D.Writer{_, _, bytes, _} = writer
  List.reverse(&2, U32, bytes)

def blocks(n: Nat, +size: U32, +begin: U32, state: Maybe<&1, (L.Core & D.Writer)>) -> Maybe<&2, +List<U32>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Tuple{_, writer}}: Some{finished(D.pad(writer))}
    case 1n+rest Some{Tuple{core, writer}}:
      +end = U32.min(size, (begin + 262144 : U32))
      blocks(rest, size, end, encoded(U32.is_eq(end, size), writer, L.block(size, begin, end, core)))

def fill(bytes: +List<U32>, +index: U32, input: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: input
    case Con{byte, rest}: fill(rest, (index + 1 : U32), Array.set(U32, input, index, byte))

def sized(bytes: +List<U32>, size: Maybe<&2, U32>) -> Maybe<&2, +List<U32>>:
  match size:
    case None{}: None{}
    case Some{0}: Some{Nil{}}
    case Some{+size}:
      input = fill(bytes, 0, Array.new(U32, 1n+U32.log2((size - 1 : U32)), 0))
      blocks(U32.to_nat(((size + 262143) / 262144 : U32)), size, 0,
        Some{(L.Core{input, Array.new(U32, 15n, 4294967295), Array.new(U32, 15n, 4294967295)}, D.Writer{0, 0, Nil{}, 0})})

def compress(+bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  sized(bytes, C.input_size(bytes, 0, True{}))
