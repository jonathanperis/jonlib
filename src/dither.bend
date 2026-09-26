# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 ImageDither; LICENSES/raylib.txt.
import Base

type Bits is Data:
  Bits{r: Nat, g: Nat, b: Nat, a: Nat}

def channel(value: U32, error: U32, weight: U32) -> U32:
  +total = (value + error * weight / 16 : U32)
  Bool.pick(U32, (total < 255 : U32), total, 255)

def spread.write(index: U32, +error: U32, +weight: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, +value) = read
  r = channel((value >> 24n : U32), (error >> 24n : U32), weight)
  g = channel(((value >> 16n) .&. 255 : U32), ((error >> 16n) .&. 255 : U32), weight)
  b = channel(((value >> 8n) .&. 255 : U32), ((error >> 8n) .&. 255 : U32), weight)
  Array.set(U32, pixels, index, ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. (value .&. 255) : U32))

def spread(valid: Bool, +index: U32, error: U32, weight: U32, pixels: Array<U32>) -> Array<U32>:
  match valid:
    case False{}: pixels
    case True{}: spread.write(index, error, weight, Array.get(U32, pixels, index))

def step(+index: U32, +width: U32, height: U32, bits: Bits, output: Array<U32>, read: Array<U32> & U32) -> Array<U32> & Array<U32>:
  Bits{r, +g, +b, +a} = bits
  (pixels, +value) = read
  +rs = (8n - r : Nat)
  +gs = (8n - g : Nat)
  +bs = (8n - b : Nat)
  +red = (value >> 24n : U32)
  +green = ((value >> 16n) .&. 255 : U32)
  +blue = ((value >> 8n) .&. 255 : U32)
  +qr = (red >> rs : U32)
  +qg = (green >> gs : U32)
  +qb = (blue >> bs : U32)
  qa = ((value .&. 255) >> (8n - a : Nat) : U32)
  +error = (((red - (qr << rs)) << 24n) .|. ((green - (qg << gs)) << 16n) .|. ((blue - (qb << bs)) << 8n) : U32)
  packed = ((qr << (g + b + a : Nat)) .|. (qg << (b + a : Nat)) .|. (qb << a) .|. qa : U32)
  +x = (index % width : U32)
  +right = (x + 1 < width : U32)
  +below = (index / width + 1 < height : U32)
  first = spread(right, (index + 1 : U32), error, 7, pixels)
  second = spread((x > 0 : U32) && below, (index + width - 1 : U32), error, 3, first)
  third = spread(below, (index + width : U32), error, 5, second)
  fourth = spread(right && below, (index + width + 1 : U32), error, 1, third)
  (fourth, Array.set(U32, output, index, packed))

def loop(n: Nat, +index: U32, +width: U32, +height: U32, +bits: Bits, buffers: Array<U32> & Array<U32>) -> Array<U32>:
  match n buffers:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{pixels, output}:
      loop(rest, (index + 1 : U32), width, height, bits, step(index, width, height, bits, output, Array.get(U32, pixels, index)))

def format(r: U32, g: U32, b: U32, a: U32) -> U32:
  match r g b a:
    case 5 6 5 0: 3
    case 5 5 5 1: 5
    case 4 4 4 4: 6
    case _ _ _ _: 0
