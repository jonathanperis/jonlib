# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the canonical DEFLATE rules in pinned stb_image.
# MIT notice: LICENSES/stb-image.txt. Owned bounded output; raw streams only.
import Base

type Bits is Data:
  Bits{bytes: +List<U32>, word: U32, count: U32}

type Read is Data:
  Read{bits: Bits, value: U32}

def bit.loaded(bits: Maybe<&2, Bits>) -> Maybe<&2, Read>:
  match bits:
    case None{}: None{}
    case Some{Bits{bytes, +word, count}}: Some{Read{Bits{bytes, (word >> 1n : U32), (count - 1 : U32)}, (word .&. 1 : U32)}}

def bit.fill(empty: Bool, bits: Bits) -> Maybe<&2, Bits>:
  match empty bits:
    case False{} _: Some{bits}
    case True{} Bits{Nil{}, _, _}: None{}
    case True{} Bits{Con{byte, rest}, _, _}: Some{Bits{rest, byte, 8}}

def bit(bits: Bits) -> Maybe<&2, Read>:
  Bits{bytes, word, +count} = bits
  bit.loaded(bit.fill(U32.is_eq(count, 0), Bits{bytes, word, count}))

def read.step(value: U32, shift: Nat, result: Maybe<&2, Read>) -> Maybe<&2, Read>:
  match result:
    case None{}: None{}
    case Some{Read{bits, digit}}: Some{Read{bits, (value .|. (digit << shift) : U32)}}

def read.loop(n: Nat, +shift: Nat, result: Maybe<&2, Read>) -> Maybe<&2, Read>:
  match n result:
    case _ None{}: None{}
    case 0n _: result
    case 1n+rest Some{Read{bits, value}}: read.loop(rest, (shift + 1n : Nat), read.step(value, shift, bit(bits)))

def read(n: Nat, bits: Bits) -> Maybe<&2, Read>:
  read.loop(n, 0n, Some{Read{bits, 0}})

type Level is Data:
  Level{first: U32, count: U32, symbols: +List<U32>}

type Symbols is Data:
  Symbols{count: U32, values: +List<U32>}

def collect(lengths: +List<U32>, +wanted: U32, +index: U32, count: U32, +values: +List<U32>) -> Symbols:
  match lengths:
    case Nil{}: Symbols{count, List.reverse(&2, U32, values)}
    case Con{size, rest}:
      +hit = U32.is_eq(size, wanted)
      collect(rest, wanted, (index + 1 : U32), (count + Bool.to_u32(hit) : U32), Bool.pick(+List<U32>, hit, Con{index, values}, values))

type Building is Data:
  Building{code: U32, levels: +List<Level>}

def level.valid(valid: Bool, +code: U32, +count: U32, symbols: +List<U32>, levels: +List<Level>) -> Maybe<&2, Building>:
  match valid:
    case False{}: None{}
    case True{}: Some{Building{((code + count) << 1n : U32), Con{Level{code, count, symbols}, levels}}}

def level(+code: U32, bits: U32, levels: +List<Level>, symbols: Symbols) -> Maybe<&2, Building>:
  Symbols{+count, values} = symbols
  level.valid((code + count <= (1 << U32.to_nat(bits)) : U32), code, count, values, levels)

def build.loop(n: Nat, +bits: U32, +lengths: +List<U32>, state: Maybe<&2, Building>) -> Maybe<&2, +List<Level>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Building{_, levels}}: Some{List.reverse(&2, Level, levels)}
    case 1n+rest Some{Building{code, levels}}: build.loop(rest, (bits + 1 : U32), lengths, level(code, bits, levels, collect(lengths, bits, 0, 0, Nil{})))

def build(lengths: +List<U32>) -> Maybe<&2, +List<Level>>:
  build.loop(15n, 1, lengths, Some{Building{0, Nil{}}})

type Search is Data:
  Search{bits: Bits, code: U32, found: Maybe<&2, U32>}

def search.hit(valid: Bool, symbols: +List<U32>, index: U32) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}: List.get(&2, U32, symbols, U32.to_nat(index))

def search.step(level: Level, code: U32, next: Maybe<&2, Read>) -> Maybe<&2, Search>:
  Level{+first, count, symbols} = level
  match next:
    case None{}: None{}
    case Some{Read{bits, digit}}:
      +value = ((code << 1n) .|. digit : U32)
      Some{Search{bits, value, search.hit(((value >= first) && (value - first < count) : U32), symbols, (value - first : U32))}}

def search(levels: +List<Level>, state: Maybe<&2, Search>) -> Maybe<&2, Read>:
  match levels state:
    case _ None{}: None{}
    case _ Some{Search{bits, _, Some{value}}}: Some{Read{bits, value}}
    case Nil{} Some{Search{_, _, None{}}}: None{}
    case Con{level, rest} Some{Search{bits, code, None{}}}: search(rest, search.step(level, code, bit(bits)))

def symbol(levels: +List<Level>, bits: Bits) -> Maybe<&2, Read>:
  search(levels, Some{Search{bits, 0, None{}}})

type Trees is Data:
  Trees{bits: Bits, literal: +List<Level>, distance: +List<Level>}

def trees(bits: Bits, literal: Maybe<&2, +List<Level>>, distance: Maybe<&2, +List<Level>>) -> Maybe<&2, Trees>:
  match literal distance:
    case Some{l} Some{d}: Some{Trees{bits, l, d}}
    case _ _: None{}

def fixed.lengths(n: Nat, +index: U32, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, values)
    case 1n+rest:
      size = Bool.pick(U32, (index < 144 : U32), 8, Bool.pick(U32, (index < 256 : U32), 9, Bool.pick(U32, (index < 280 : U32), 7, 8)))
      fixed.lengths(rest, (index + 1 : U32), Con{size, values})

def fixed(bits: Bits) -> Maybe<&2, Trees>:
  trees(bits, build(fixed.lengths(288n, 0, Nil{})), build(List.replicate(U32, 32n, 5)))

type Codes is Data:
  Codes{bits: Bits, lengths: +List<U32>}

def codes.read(index: U32, values: +List<U32>, result: Maybe<&2, Read>) -> Maybe<&2, Codes>:
  match result:
    case None{}: None{}
    case Some{Read{bits, value}}: Some{Codes{bits, List.set(&2, U32, values, U32.to_nat(index), value)}}

def codes(n: Nat, order: +List<U32>, state: Maybe<&2, Codes>) -> Maybe<&2, Codes>:
  match n order state:
    case _ _ None{}: None{}
    case 0n _ _: state
    case _ Nil{} _: None{}
    case 1n+rest Con{index, tail} Some{Codes{bits, values}}: codes(rest, tail, codes.read(index, values, read(3n, bits)))

def repeated(n: Nat, +value: U32, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: values
    case 1n+rest: repeated(rest, value, Con{value, values})

type Lengths is Data:
  Lengths{bits: Bits, left: U32, values: +List<U32>}

def lengths.put(valid: Bool, bits: Bits, left: U32, +count: U32, value: U32, values: +List<U32>) -> Maybe<&2, Lengths>:
  match valid:
    case False{}: None{}
    case True{}: Some{Lengths{bits, (left - count : U32), repeated(U32.to_nat(count), value, values)}}

def lengths.extra(+left: U32, base: U32, value: U32, values: +List<U32>, result: Maybe<&2, Read>) -> Maybe<&2, Lengths>:
  match result:
    case None{}: None{}
    case Some{Read{bits, extra}}:
      +count = (base + extra : U32)
      lengths.put((count <= left : U32), bits, left, count, value, values)

def lengths.command(small: Bool, +code: U32, bits: Bits, left: U32, values: +List<U32>) -> Maybe<&2, Lengths>:
  match small code values:
    case True{} _ _: lengths.put(True{}, bits, left, 1, code, values)
    case False{} 16 Con{+value, rest}: lengths.extra(left, 3, value, Con{value, rest}, read(2n, bits))
    case False{} 17 _: lengths.extra(left, 3, 0, values, read(3n, bits))
    case False{} 18 _: lengths.extra(left, 11, 0, values, read(7n, bits))
    case _ _ _: None{}

def lengths.read(left: U32, values: +List<U32>, result: Maybe<&2, Read>) -> Maybe<&2, Lengths>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +code}}: lengths.command((code < 16 : U32), code, bits, left, values)

def lengths.loop(n: Nat, +tree: +List<Level>, state: Maybe<&2, Lengths>) -> Maybe<&2, Codes>:
  match n state:
    case _ None{}: None{}
    case _ Some{Lengths{bits, 0, values}}: Some{Codes{bits, List.reverse(&2, U32, values)}}
    case 0n _: None{}
    case 1n+rest Some{Lengths{bits, left, values}}: lengths.loop(rest, tree, lengths.read(left, values, symbol(tree, bits)))

def dynamic.end(valid: Bool, bits: Bits, literal: +List<U32>, distance: +List<U32>) -> Maybe<&2, Trees>:
  match valid:
    case False{}: None{}
    case True{}: trees(bits, build(literal), build(distance))

def dynamic.eob(bits: Bits, +literal: +List<U32>, distance: +List<U32>, end: Maybe<&2, U32>) -> Maybe<&2, Trees>:
  match end:
    case None{}: None{}
    case Some{value}: dynamic.end((value > 0 : U32), bits, literal, distance)

def dynamic.finished(+hlit: U32, result: Maybe<&2, Codes>) -> Maybe<&2, Trees>:
  match result:
    case None{}: None{}
    case Some{Codes{bits, +values}}:
      +literal = List.take(&2, U32, values, U32.to_nat(hlit))
      dynamic.eob(bits, literal, List.drop(&2, U32, values, U32.to_nat(hlit)), List.get(&2, U32, literal, 256n))

def dynamic.tree(hlit: U32, +count: U32, bits: Bits, result: Maybe<&2, +List<Level>>) -> Maybe<&2, Trees>:
  match result:
    case None{}: None{}
    case Some{tree}: dynamic.finished(hlit, lengths.loop(U32.to_nat(count), tree, Some{Lengths{bits, count, Nil{}}}))

def dynamic.codes(hlit: U32, count: U32, result: Maybe<&2, Codes>) -> Maybe<&2, Trees>:
  match result:
    case None{}: None{}
    case Some{Codes{bits, values}}: dynamic.tree(hlit, count, bits, build(values))

def dynamic.valid(valid: Bool, +hlit: U32, hdist: U32, hclen: U32, bits: Bits) -> Maybe<&2, Trees>:
  match valid:
    case False{}: None{}
    case True{}:
      dynamic.codes(hlit, (hlit + hdist : U32), codes(U32.to_nat(hclen), [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15], Some{Codes{bits, List.replicate(U32, 19n, 0)}}))

def dynamic(result: Maybe<&2, Read>) -> Maybe<&2, Trees>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +value}}:
      +hlit = ((value .&. 31) + 257 : U32)
      dynamic.valid((hlit <= 286 : U32), hlit, (((value >> 5n) .&. 31) + 1 : U32), ((value >> 10n) + 4 : U32), bits)

type Mode is Data:
  Header{}
  Huffman{final: Bool, literal: +List<Level>, distance: +List<Level>}
  Finished{}

type Output is Type:
  Output{bits: Bits, position: U32, pixels: Array<U32>, mode: Mode}

def output.literal(valid: Bool, +position: U32, pixels: Array<U32>, mode: Mode, result: Maybe<&2, Read>) -> Maybe<Output>:
  match valid result:
    case True{} Some{Read{bits, value}}: Some{Output{bits, (position + 1 : U32), Array.set(U32, pixels, position, value), mode}}
    case _ _: None{}

def stored.copy(n: Nat, state: Maybe<Output>) -> Maybe<Output>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Output{bits, position, pixels, mode}}: stored.copy(rest, output.literal(True{}, position, pixels, mode, read(8n, bits)))

def stored.valid(valid: Bool, +count: U32, bits: Bits, position: U32, pixels: Array<U32>, final: Bool, stop_empty: Bool) -> Maybe<Output>:
  match valid:
    case False{}: None{}
    case True{}: stored.copy(U32.to_nat(count), Some{Output{bits, position, pixels, Bool.pick(Mode, final || (stop_empty && U32.is_eq(count, 0)), Finished{}, Header{})}})

def stored(maximum: U32, +position: U32, pixels: Array<U32>, final: Bool, stop_empty: Bool, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +value}}:
      +count = (value .&. 65535 : U32)
      stored.valid(U32.is_eq((value >> 16n : U32), (count .^. 65535 : U32)) && (count <= maximum - position : U32), count, bits, position, pixels, final, stop_empty)

def output.trees(position: U32, pixels: Array<U32>, final: Bool, result: Maybe<&2, Trees>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Trees{bits, literal, distance}}: Some{Output{bits, position, pixels, Huffman{final, literal, distance}}}

def block(kind: U32, final: Bool, stop_empty: Bool, maximum: U32, position: U32, pixels: Array<U32>, bits: Bits) -> Maybe<Output>:
  match kind bits:
    case 0 Bits{bytes, _, _}: stored(maximum, position, pixels, final, stop_empty, read(32n, Bits{bytes, 0, 0}))
    case 1 _: output.trees(position, pixels, final, fixed(bits))
    case 2 _: output.trees(position, pixels, final, dynamic(read(14n, bits)))
    case _ _: None{}

def header(stop_empty: Bool, maximum: U32, position: U32, pixels: Array<U32>, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +value}}: block((value >> 1n : U32), ((value .&. 1) > 0 : U32), stop_empty, maximum, position, pixels, bits)

def copy.write(index: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, byte) = read
  Array.set(U32, pixels, index, byte)

def copy(n: Nat, +position: U32, +distance: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: copy(rest, (position + 1 : U32), distance, copy.write(position, Array.get(U32, pixels, (position - distance : U32))))

def match.valid(valid: Bool, bits: Bits, +position: U32, +length: U32, distance: U32, pixels: Array<U32>, mode: Mode) -> Maybe<Output>:
  match valid:
    case False{}: None{}
    case True{}: Some{Output{bits, (position + length : U32), copy(U32.to_nat(length), position, distance, pixels), mode}}

def match.extra(maximum: U32, +position: U32, +length: U32, base: U32, pixels: Array<U32>, mode: Mode, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, extra}}:
      +distance = (base + extra : U32)
      match.valid(((distance > 0) && (distance <= position) && (length <= maximum - position) : U32), bits, position, length, distance, pixels, mode)

def distance.valid(valid: Bool, +code: U32, bits: Bits, maximum: U32, position: U32, length: U32, pixels: Array<U32>, mode: Mode) -> Maybe<Output>:
  match valid:
    case False{}: None{}
    case True{}:
      +small = (code < 4 : U32)
      +extra = Bool.pick(U32, small, 0, (code / 2 - 1 : U32))
      base = Bool.pick(U32, small, (code + 1 : U32), (((2 + (code .&. 1)) << U32.to_nat(extra)) + 1 : U32))
      match.extra(maximum, position, length, base, pixels, mode, read(U32.to_nat(extra), bits))

def distance(maximum: U32, position: U32, length: U32, pixels: Array<U32>, mode: Mode, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +code}}: distance.valid((code < 30 : U32), code, bits, maximum, position, length, pixels, mode)

def length.extra(maximum: U32, position: U32, base: U32, pixels: Array<U32>, mode: Mode, tree: +List<Level>, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, extra}}: distance(maximum, position, (base + extra : U32), pixels, mode, symbol(tree, bits))

def length.valid(valid: Bool, +index: U32, bits: Bits, maximum: U32, position: U32, pixels: Array<U32>, mode: Mode, tree: +List<Level>) -> Maybe<Output>:
  match valid:
    case False{}: None{}
    case True{}:
      +short = (index < 8 : U32)
      +last = U32.is_eq(index, 28)
      +extra = Bool.pick(U32, short || last, 0, ((index - 4) / 4 : U32))
      base = Bool.pick(U32, short, (index + 3 : U32), Bool.pick(U32, last, 258, (((4 + index % 4) << U32.to_nat(extra)) + 3 : U32)))
      length.extra(maximum, position, base, pixels, mode, tree, read(U32.to_nat(extra), bits))

def decoded(literal_byte: Bool, end: Bool, +value: U32, bits: Bits, maximum: U32, +position: U32, pixels: Array<U32>, +final: Bool, literals: +List<Level>, +distances: +List<Level>) -> Maybe<Output>:
  match literal_byte end:
    case True{} _: output.literal((position < maximum : U32), position, pixels, Huffman{final, literals, distances}, Some{Read{bits, value}})
    case False{} True{}: Some{Output{bits, position, pixels, Bool.pick(Mode, final, Finished{}, Header{})}}
    case False{} False{}: length.valid((value < 286 : U32), (value - 257 : U32), bits, maximum, position, pixels, Huffman{final, literals, distances}, distances)

def huffman(maximum: U32, position: U32, pixels: Array<U32>, final: Bool, literals: +List<Level>, distances: +List<Level>, result: Maybe<&2, Read>) -> Maybe<Output>:
  match result:
    case None{}: None{}
    case Some{Read{bits, +value}}: decoded((value < 256 : U32), U32.is_eq(value, 256), value, bits, maximum, position, pixels, final, literals, distances)

def step(stop_empty: Bool, maximum: U32, bits: Bits, position: U32, pixels: Array<U32>, mode: Mode) -> Maybe<Output>:
  match mode:
    case Header{}: header(stop_empty, maximum, position, pixels, read(3n, bits))
    case Huffman{final, +literal, distance}: huffman(maximum, position, pixels, final, literal, distance, symbol(literal, bits))
    case Finished{}: Some{Output{bits, position, pixels, Finished{}}}

def output.read(values: List<U32>, read: Array<U32> & U32) -> Array<U32> & List<U32>:
  (pixels, value) = read
  (pixels, Con{value, values})

def output.bytes(n: Nat, +index: U32, state: Array<U32> & List<U32>) -> List<U32>:
  match n state:
    case 0n Tuple{_, values}: List.reverse(&1, U32, values)
    case 1n+rest Tuple{pixels, values}: output.bytes(rest, (index + 1 : U32), output.read(values, Array.get(U32, pixels, index)))

def loop(n: Nat, +stop_empty: Bool, +maximum: U32, state: Maybe<Output>) -> Maybe<List<U32>>:
  match n state:
    case _ None{}: None{}
    case _ Some{Output{_, position, pixels, Finished{}}}: Some{output.bytes(U32.to_nat(position), 0, (pixels, Nil{}))}
    case 0n _: None{}
    case 1n+rest Some{Output{bits, position, pixels, mode}}: loop(rest, stop_empty, maximum, step(stop_empty, maximum, bits, position, pixels, mode))

def bytes.count(bytes: +List<U32>, +count: U32, valid: Bool) -> Maybe<&2, U32>:
  match bytes valid:
    case _ False{}: None{}
    case Nil{} True{}: Some{count}
    case Con{byte, rest} True{}: bytes.count(rest, (count + 1 : U32), ((count < 1048576) && (byte <= 255) : U32))

def start(stop_empty: Bool, +maximum: U32, bytes: +List<U32>, count: Maybe<&2, U32>) -> Maybe<List<U32>>:
  match count:
    case None{}: None{}
    case Some{size}:
      depth = Bool.pick(Nat, (maximum <= 1 : U32), 0n, 1n+U32.log2((maximum - 1 : U32)))
      loop(U32.to_nat((size * 8 + 1 : U32)), stop_empty, maximum, Some{Output{Bits{bytes, 0, 0}, 0, Array.new(U32, depth, 0), Header{}}})

def checked(valid: Bool, stop_empty: Bool, maximum: U32, +bytes: +List<U32>) -> Maybe<List<U32>>:
  match valid:
    case False{}: None{}
    case True{}: start(stop_empty, maximum, bytes, bytes.count(bytes, 0, True{}))

def decompress(stop_empty: Bool, bytes: +List<U32>, +maximum: U32) -> Maybe<List<U32>>:
  checked((maximum <= 67108864 : U32), stop_empty, maximum, bytes)
