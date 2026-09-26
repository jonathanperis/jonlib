# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_image_write's default RGBA8 PNG export.
# MIT notice: LICENSES/stb-image.txt. Auto filter, quality 8, no vertical flip.
import Base
import ./png.bend as P
import ./deflate.bend as D

def capacity(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def input.read(+at: U32, output: Array<U32>, read: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (pixels, +value) = read
  r = Array.set(U32, output, at, (value >> 24n : U32))
  g = Array.set(U32, r, (at + 1 : U32), ((value >> 16n) .&. 255 : U32))
  b = Array.set(U32, g, (at + 2 : U32), ((value >> 8n) .&. 255 : U32))
  (pixels, Array.set(U32, b, (at + 3 : U32), (value .&. 255 : U32)))

def input(n: Nat, +index: U32, state: Array<U32> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{pixels, output}: input(rest, (index + 1 : U32), input.read((index * 4 : U32), output, Array.get(U32, pixels, index)))

def filter.corner(filter: U32, raw: U32, a: U32, b: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, c) = read
  (pixels, ((raw - P.predictor(filter, a, b, c)) .&. 255 : U32))

def filter.above(width: U32, index: U32, filter: U32, raw: U32, a: U32, corner: Bool, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, b) = read
  filter.corner(filter, raw, a, b, P.neighbor(corner, (index - width - 4 : U32), pixels))

def filter.left(+width: U32, +index: U32, filter: U32, raw: U32, left: Bool, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, a) = read
  +above = (index >= width : U32)
  filter.above(width, index, filter, raw, a, left && above, P.neighbor(above, (index - width : U32), pixels))

def filter.value(+width: U32, +index: U32, filter: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, raw) = read
  +left = (index % width >= 4 : U32)
  filter.left(width, index, filter, raw, left, P.neighbor(left, (index - 4 : U32), pixels))

def filter.byte(width: U32, +index: U32, filter: U32, pixels: Array<U32>) -> Array<U32> & U32:
  filter.value(width, index, filter, Array.get(U32, pixels, index))

def score.add(total: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, +value) = read
  (pixels, (total + Bool.pick(U32, (value < 128 : U32), value, (256 - value : U32)) : U32))

def score(n: Nat, +index: U32, +width: U32, +filter: U32, state: Array<U32> & U32) -> Array<U32> & U32:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{pixels, total}: score(rest, (index + 1 : U32), width, filter, score.add(total, filter.byte(width, index, filter, pixels)))

type Choice is Type:
  Choice{input: Array<U32>, score: U32, filter: U32}

def choose.updated(candidate: U32, +best_score: U32, best_filter: U32, result: Array<U32> & U32) -> Choice:
  (pixels, +value) = result
  +better = (value < best_score : U32)
  Choice{pixels, Bool.pick(U32, better, value, best_score), Bool.pick(U32, better, candidate, best_filter)}

def choose(n: Nat, +candidate: U32, +row: U32, +width: U32, state: Choice) -> Choice:
  match n state:
    case 0n _: state
    case 1n+rest Choice{pixels, best_score, best_filter}:
      choose(rest, (candidate + 1 : U32), row, width, choose.updated(candidate, best_score, best_filter, score(U32.to_nat(width), row, width, candidate, (pixels, 0))))

def row.write(at: U32, output: Array<U32>, read: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (pixels, value) = read
  (pixels, Array.set(U32, output, at, value))

def row(n: Nat, +index: U32, +at: U32, +width: U32, +filter: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{pixels, output}:
      row(rest, (index + 1 : U32), (at + 1 : U32), width, filter, row.write(at, output, filter.byte(width, index, filter, pixels)))

def row.filtered(+y: U32, +width: U32, output: Array<U32>, selected: Choice) -> Array<U32> & Array<U32>:
  Choice{pixels, _, +filter} = selected
  +at = (y * (width + 1) : U32)
  row(U32.to_nat(width), (y * width : U32), (at + 1 : U32), width, filter, (pixels, Array.set(U32, output, at, filter)))

def rows(n: Nat, +y: U32, +width: U32, state: Array<U32> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{pixels, output}:
      rows(rest, (y + 1 : U32), width, row.filtered(y, width, output, choose(5n, 0, (y * width : U32), width, Choice{pixels, 2147483647, 0})))

def crc.bits(n: Nat, +value: U32) -> U32:
  match n:
    case 0n: value
    case 1n+rest: crc.bits(rest, ((value >> 1n) .^. Bool.pick(U32, ((value .&. 1) > 0 : U32), 3988292384, 0) : U32))

def crc(bytes: +List<U32>, value: U32) -> U32:
  match bytes:
    case Nil{}: value
    case Con{byte, rest}: crc(rest, crc.bits(8n, (value .^. byte : U32)))

def word.bytes(+value: U32) -> +List<U32>:
  [(value >> 24n : U32), ((value >> 16n) .&. 255 : U32), ((value >> 8n) .&. 255 : U32), (value .&. 255 : U32)]

def word.prepend(+value: U32, bytes: +List<U32>) -> +List<U32>:
  Con{(value .&. 255 : U32), Con{((value >> 8n) .&. 255 : U32), Con{((value >> 16n) .&. 255 : U32), Con{(value >> 24n : U32), bytes}}}}

def chunk(kind: U32, size: U32, +payload: +List<U32>, bytes: +List<U32>) -> +List<U32>:
  +tag = word.bytes(kind)
  checksum = (crc(payload, crc(tag, 4294967295)) .^. 4294967295 : U32)
  word.prepend(checksum, P.reverse_into(payload, P.reverse_into(tag, word.prepend(size, bytes))))

def wrap(width: U32, height: U32, stream: D.Stream) -> +List<U32>:
  D.Stream{size, bytes} = stream
  header = List.append(&2, U32, word.bytes(width), List.append(&2, U32, word.bytes(height), [8,6,0,0,0]))
  ihdr = chunk(1229472850, 13, header, [10,26,10,13,71,78,80,137])
  List.reverse(&2, U32, chunk(1229278788, 0, Nil{}, chunk(1229209940, size, bytes, ihdr)))

def encode.raw(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  +size = ((width * 4 + 1) * height : U32)
  filtered = rows(U32.to_nat(height), 0, (width * 4 : U32), (pixels, Array.new(U32, capacity(size), 0)))
  wrap(width, height, D.compress(size, filtered))

def encode(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  encode.raw(width, height, input(U32.to_nat((width * height : U32)), 0, (pixels, Array.new(U32, capacity((width * height * 4 : U32)), 0))))
