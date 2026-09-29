# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered sdefl adaptation, Copyright (c) 2020-2023 Micha Mettke (MIT).
# Required license: LICENSES/sdefl.txt. Private bounded compressor dependency.
import Base
import ./deflate.bend as D

type Codes is Type:
  Codes{lengths: Array<U32>, words: Array<U32>}

type Collected is Type:
  Collected{frequencies: Array<U32>, values: +List<U32>}

def collect.read(+index: U32, +values: +List<U32>, result: Array<U32> & U32) -> Collected:
  (frequencies, +value) = result
  Collected{frequencies, Bool.pick(+List<U32>, U32.is_eq(value, 0), values, Con{(index .|. (value << 10n) : U32), values})}

def collect(n: Nat, +index: U32, state: Collected) -> Collected:
  match n state:
    case 0n _: state
    case 1n+rest Collected{frequencies, values}:
      collect(rest, (index + 1 : U32), collect.read(index, values, Array.get(U32, frequencies, index)))

def depth(count: U32) -> Nat:
  1n+U32.log2((count - 1 : U32))

def fill(values: +List<U32>, +index: U32, output: Array<U32>) -> Array<U32>:
  match values:
    case Nil{}: output
    case Con{value, rest}: fill(rest, (index + 1 : U32), Array.set(U32, output, index, value))

type Picked is Type:
  Picked{words: Array<U32>, leaf: U32, inner: U32, index: U32}

type Tree is Type:
  Tree{words: Array<U32>, leaf: U32, inner: U32}

def pick.compared(use_leaf: Bool, +leaf: U32, +inner: U32, words: Array<U32>) -> Picked:
  match use_leaf:
    case True{}: Picked{words, (leaf + 1 : U32), inner, leaf}
    case False{}: Picked{words, leaf, (inner + 1 : U32), inner}

def pick.inner(leaf: U32, inner: U32, first: U32, result: Array<U32> & U32) -> Picked:
  (words, second) = result
  pick.compared(((first >> 10n) <= (second >> 10n) : U32), leaf, inner, words)

def pick.leaf(leaf: U32, +inner: U32, result: Array<U32> & U32) -> Picked:
  (words, value) = result
  pick.inner(leaf, inner, value, Array.get(U32, words, inner))

def pick.route(exhausted: Bool, empty: Bool, +leaf: U32, +inner: U32, words: Array<U32>) -> Picked:
  match exhausted empty:
    case True{} _: pick.compared(False{}, leaf, inner, words)
    case False{} True{}: pick.compared(True{}, leaf, inner, words)
    case False{} False{}: pick.leaf(leaf, inner, Array.get(U32, words, leaf))

def pick(used: U32, end: U32, +leaf: U32, +inner: U32, words: Array<U32>) -> Picked:
  pick.route(U32.is_eq(leaf, used), U32.is_eq(inner, end), leaf, inner, words)

def tree.parent(index: U32, leaf: U32, inner: U32, frequency: U32, result: Array<U32> & U32) -> Tree:
  (words, value) = result
  Tree{Array.set(U32, words, index, ((value .&. 1023) .|. frequency : U32)), leaf, inner}

def tree.joined(+end: U32, first: U32, second: U32, leaf: U32, inner: U32, +first_word: U32, result: Array<U32> & U32) -> Tree:
  (words, +second_word) = result
  frequency = ((first_word .&. 4294966272) + (second_word .&. 4294966272) : U32)
  a = Array.set(U32, words, first, ((first_word .&. 1023) .|. (end << 10n) : U32))
  b = Array.set(U32, a, second, ((second_word .&. 1023) .|. (end << 10n) : U32))
  tree.parent(end, leaf, inner, frequency, Array.get(U32, b, end))

def tree.first(end: U32, first: U32, +second: U32, leaf: U32, inner: U32, result: Array<U32> & U32) -> Tree:
  (words, value) = result
  tree.joined(end, first, second, leaf, inner, value, Array.get(U32, words, second))

def tree.second(end: U32, +first: U32, result: Picked) -> Tree:
  Picked{words, leaf, inner, second} = result
  tree.first(end, first, second, leaf, inner, Array.get(U32, words, first))

def tree.pick_second(+end: U32, used: U32, result: Picked) -> Tree:
  Picked{words, leaf, inner, first} = result
  tree.second(end, first, pick(used, end, leaf, inner, words))

def tree.step(+end: U32, +used: U32, state: Tree) -> Tree:
  Tree{words, leaf, inner} = state
  tree.pick_second(end, used, pick(used, end, leaf, inner, words))

def tree(n: Nat, +end: U32, +used: U32, state: Tree) -> Array<U32>:
  match n state:
    case 0n Tree{words, _, _}: words
    case 1n+rest _: tree(rest, (end + 1 : U32), used, tree.step(end, used, state))

type Lengths is Type:
  Lengths{words: Array<U32>, counts: Array<U32>}

def highest.read(index: U32, previous: U32, result: Array<U32> & U32) -> Array<U32> & U32:
  (counts, value) = result
  (counts, Bool.pick(U32, (value > 0 : U32), index, previous))

def highest(n: Nat, +index: U32, state: Array<U32> & U32) -> Array<U32> & U32:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{counts, previous}: highest(rest, (index + 1 : U32), highest.read(index, previous, Array.get(U32, counts, index)))

def lengths.give(index: U32, words: Array<U32>, result: Array<U32> & U32) -> Lengths:
  (counts, value) = result
  Lengths{words, Array.set(U32, counts, index, (value + 2 : U32))}

def lengths.take(+length: U32, words: Array<U32>, result: Array<U32> & U32) -> Lengths:
  (counts, value) = result
  lengths.give((length + 1 : U32), words, Array.get(U32, Array.set(U32, counts, length, (value - 1 : U32)), (length + 1 : U32)))

def lengths.selected(words: Array<U32>, result: Array<U32> & U32) -> Lengths:
  (counts, +length) = result
  lengths.take(length, words, Array.get(U32, counts, length))

def lengths.route(limited: Bool, maximum: U32, level: U32, words: Array<U32>, counts: Array<U32>) -> Lengths:
  match limited:
    case False{}: lengths.selected(words, (counts, level))
    case True{}: lengths.selected(words, highest(U32.to_nat(maximum), 0, (counts, 0)))

def lengths.parent(index: U32, original: U32, +maximum: U32, counts: Array<U32>, result: Array<U32> & U32) -> Lengths:
  (words, parent) = result
  +level = ((parent >> 10n) + 1 : U32)
  changed = Array.set(U32, words, index, ((original .&. 1023) .|. (level << 10n) : U32))
  lengths.route((level >= maximum : U32), maximum, level, changed, counts)

def lengths.child(index: U32, maximum: U32, counts: Array<U32>, result: Array<U32> & U32) -> Lengths:
  (words, +value) = result
  lengths.parent(index, value, maximum, counts, Array.get(U32, words, (value >> 10n : U32)))

def lengths.step(+index: U32, maximum: U32, state: Lengths) -> Lengths:
  Lengths{words, counts} = state
  lengths.child(index, maximum, counts, Array.get(U32, words, index))

def lengths(n: Nat, +index: U32, +maximum: U32, state: Lengths) -> Lengths:
  match n:
    case 0n: state
    case 1n+rest: lengths(rest, (index - 1 : U32), maximum, lengths.step(index, maximum, state))

type Assignment is Type:
  Assignment{words: Array<U32>, counts: Array<U32>, lengths: Array<U32>, cursor: U32}

def assigned(length: U32, counts: Array<U32>, lengths: Array<U32>, cursor: U32, result: Array<U32> & U32) -> Assignment:
  (words, value) = result
  Assignment{words, counts, Array.set(U32, lengths, (value .&. 1023 : U32), length), (cursor + 1 : U32)}

def assign_one(length: U32, state: Assignment) -> Assignment:
  Assignment{words, counts, lengths, +cursor} = state
  assigned(length, counts, lengths, cursor, Array.get(U32, words, cursor))

def assign_many(n: Nat, +length: U32, state: Assignment) -> Assignment:
  match n:
    case 0n: state
    case 1n+rest: assign_many(rest, length, assign_one(length, state))

def assign_count(length: U32, words: Array<U32>, lengths: Array<U32>, cursor: U32, result: Array<U32> & U32) -> Assignment:
  (counts, count) = result
  assign_many(U32.to_nat(count), length, Assignment{words, counts, lengths, cursor})

def assign_length(+length: U32, state: Assignment) -> Assignment:
  Assignment{words, counts, lengths, cursor} = state
  assign_count(length, words, lengths, cursor, Array.get(U32, counts, length))

def assign_lengths(+n: Nat, state: Assignment) -> Assignment:
  match n:
    case 0n: state
    case 1n+rest: assign_lengths(rest, assign_length(U32.from_nat(n), state))

def next.count(index: U32, previous: U32, next: Array<U32>, result: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (counts, value) = result
  (counts, Array.set(U32, next, index, ((previous + value) << 1n : U32)))

def next.previous(+index: U32, counts: Array<U32>, result: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (next, value) = result
  next.count(index, value, next, Array.get(U32, counts, (index - 1 : U32)))

def next.step(+index: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  (counts, next) = state
  next.previous(index, counts, Array.get(U32, next, (index - 1 : U32)))

def nexts(n: Nat, +index: U32, state: Array<U32> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, next}: next
    case 1n+rest _: nexts(rest, (index + 1 : U32), next.step(index, state))

type Coding is Type:
  Coding{words: Array<U32>, lengths: Array<U32>, next: Array<U32>}

def coded(index: U32, +bits: U32, words: Array<U32>, lengths: Array<U32>, result: Array<U32> & U32) -> Coding:
  (next, +value) = result
  Coding{Array.set(U32, words, index, D.reverse(U32.to_nat(bits), value, 0)), lengths, Array.set(U32, next, bits, (value + 1 : U32))}

def coding.length(index: U32, words: Array<U32>, next: Array<U32>, result: Array<U32> & U32) -> Coding:
  (lengths, +bits) = result
  coded(index, bits, words, lengths, Array.get(U32, next, bits))

def coding.step(+index: U32, state: Coding) -> Coding:
  Coding{words, lengths, next} = state
  coding.length(index, words, next, Array.get(U32, lengths, index))

def coding(n: Nat, +index: U32, state: Coding) -> Codes:
  match n state:
    case 0n Coding{words, lengths, _}: Codes{lengths, words}
    case 1n+rest _: coding(rest, (index + 1 : U32), coding.step(index, state))

def canonical(count: U32, maximum: U32, state: Assignment) -> Codes:
  Assignment{words, counts, lengths, _} = state
  next = nexts(U32.to_nat((maximum - 1 : U32)), 2, (counts, Array.new(U32, 4n, 0)))
  coding(U32.to_nat(count), 0, Coding{words, lengths, next})

def generated(+count: U32, +maximum: U32, state: Lengths) -> Codes:
  Lengths{words, counts} = state
  canonical(count, maximum, assign_lengths(U32.to_nat(maximum), Assignment{words, counts, Array.new(U32, depth(count), 0), 0}))

def rooted(count: U32, +maximum: U32, +root: U32, result: Array<U32> & U32) -> Codes:
  (words, value) = result
  cleared = Array.set(U32, words, root, (value .&. 1023 : U32))
  generated(count, maximum, lengths(U32.to_nat(root), (root - 1 : U32), maximum, Lengths{cleared, Array.set(U32, Array.new(U32, 4n, 0), 1, 2)}))

def built_tree(count: U32, maximum: U32, +root: U32, words: Array<U32>) -> Codes:
  rooted(count, maximum, root, Array.get(U32, words, root))

def single(count: U32, result: Array<U32> & U32) -> Codes:
  (words, +value) = result
  +symbol = (value .&. 1023 : U32)
  +other = Bool.pick(U32, U32.is_eq(symbol, 0), 1, symbol)
  Codes{Array.set(U32, Array.set(U32, Array.new(U32, depth(count), 0), 0, 1), other, 1),
    Array.set(U32, Array.set(U32, words, 0, 0), other, 1)}

def sorted(+used: U32, +count: U32, maximum: U32, words: Array<U32>) -> Codes:
  match used:
    case 0: Codes{Array.new(U32, depth(count), 0), words}
    case 1: single(count, Array.get(U32, words, 0))
    case _:
      built_tree(count, maximum, (used - 2 : U32), tree(U32.to_nat((used - 1 : U32)), 0, used, Tree{words, 0, 0}))

def collected(+count: U32, maximum: U32, state: Collected) -> Array<U32> & Codes:
  Collected{frequencies, +values} = state
  used = U32.from_nat(List.length(&2, U32, values))
  words = fill(List.sort(~U32, ~U32.is_le, values), 0, Array.new(U32, depth(count), 0))
  (frequencies, sorted(used, count, maximum, words))

def build(+count: U32, maximum: U32, frequencies: Array<U32>) -> Array<U32> & Codes:
  collected(count, maximum, collect(U32.to_nat(count), 0, Collected{frequencies, Nil{}}))
