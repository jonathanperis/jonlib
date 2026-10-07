# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# ImageRotate sampling adapted from pinned raylib rtextures.c; retained notices
# are in THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
# ImageRotate interpolates every stored byte on its own, so a pixel is any
# value whose bytes `mix` blends: a word's four byte lanes, or each word of a
# wider sample. Unused high bytes of narrow formats stay zero.
import Base

type Mapping is Data:
  Mapping{source_width: U32, source_height: U32, width: U32, height: U32, cosine: F32, sine: F32}

def channel(a: U32, b: U32, c: U32, d: U32, +x: F32, +y: F32) -> U32:
  F32.to_u32((U32.to_f32(a) * (1.0 - x) * (1.0 - y)
    + U32.to_f32(b) * x * (1.0 - y)
    + U32.to_f32(c) * (1.0 - x) * y
    + U32.to_f32(d) * x * y : F32))

def mix(+a: U32, +b: U32, +c: U32, +d: U32, +x: F32, +y: F32) -> U32:
  r = channel((a >> 24n : U32), (b >> 24n : U32), (c >> 24n : U32), (d >> 24n : U32), x, y)
  g = channel(((a >> 16n) .&. 255 : U32), ((b >> 16n) .&. 255 : U32), ((c >> 16n) .&. 255 : U32), ((d >> 16n) .&. 255 : U32), x, y)
  blue = channel(((a >> 8n) .&. 255 : U32), ((b >> 8n) .&. 255 : U32), ((c >> 8n) .&. 255 : U32), ((d >> 8n) .&. 255 : U32), x, y)
  alpha = channel((a .&. 255 : U32), (b .&. 255 : U32), (c .&. 255 : U32), (d .&. 255 : U32), x, y)
  ((r << 24n) .|. (g << 16n) .|. (blue << 8n) .|. alpha : U32)

def mix.word(a: U32, b: U32, c: U32, d: U32, x: F32, y: F32) -> U32:
  mix(a, b, c, d, x, y)

def fourth(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, got: Array<T> & T, a: T, b: T, c: T, x: F32, y: F32) -> Array<T> & T:
  (pixels, d) = got
  (pixels, blend(a, b, c, d, x, y))

def third(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, got: Array<T> & T, last: U32, a: T, b: T, x: F32, y: F32) -> Array<T> & T:
  (pixels, c) = got
  fourth(~T, ~blend, Array.get(T, pixels, last), a, b, c, x, y)

def second(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, got: Array<T> & T, next: U32, last: U32, a: T, x: F32, y: F32) -> Array<T> & T:
  (pixels, b) = got
  third(~T, ~blend, Array.get(T, pixels, next), last, a, b, x, y)

def first(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, got: Array<T> & T, next: U32, third: U32, last: U32, x: F32, y: F32) -> Array<T> & T:
  (pixels, a) = got
  second(~T, ~blend, Array.get(T, pixels, next), third, last, a, x, y)

def sample(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, inside: Bool, +empty: T, +width: U32, height: U32, +x: F32, +y: F32, pixels: Array<T>) -> Array<T> & T:
  match inside:
    case False{}: (pixels, empty)
    case True{}:
      +x1 = F32.to_u32(F32.floor(x))
      +y1 = F32.to_u32(F32.floor(y))
      +x2 = U32.min((x1 + 1 : U32), (width - 1 : U32))
      +y2 = U32.min((y1 + 1 : U32), (height - 1 : U32))
      first(~T, ~blend, Array.get(T, pixels, (y1 * width + x1 : U32)), (y1 * width + x2 : U32),
        (y2 * width + x1 : U32), (y2 * width + x2 : U32), (x - U32.to_f32(x1) : F32), (y - U32.to_f32(y1) : F32))

def pixel(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, mapping: Mapping, +empty: T, +index: U32, pixels: Array<T>) -> Array<T> & T:
  Mapping{+sw, +sh, +width, height, +cosine, +sine} = mapping
  +x = (U32.to_f32((index % width : U32)) - U32.to_f32(width) / 2.0 : F32)
  +y = (U32.to_f32((index / width : U32)) - U32.to_f32(height) / 2.0 : F32)
  +old_x = ((x * cosine + y * sine) + U32.to_f32(sw) / 2.0 : F32)
  +old_y = ((y * cosine - x * sine) + U32.to_f32(sh) / 2.0 : F32)
  sample(~T, ~blend, ((old_x >= 0.0) && (old_x < U32.to_f32(sw)) && (old_y >= 0.0) && (old_y < U32.to_f32(sh)) : F32),
    empty, sw, sh, old_x, old_y, pixels)

def write(~T: Data, index: U32, output: Array<T>, sampled: Array<T> & T) -> Array<T> & Array<T>:
  (source, value) = sampled
  (source, Array.set(T, output, index, value))

def loop(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, n: Nat, +index: U32, +mapping: Mapping, +empty: T, buffers: Array<T> & Array<T>) -> Array<T>:
  match n buffers:
    case 0n Tuple{_, output}: output
    case 1n+k Tuple{source, output}:
      loop(~T, ~blend, k, (index + 1 : U32), mapping, empty, write(~T, index, output, pixel(~T, ~blend, mapping, empty, index, source)))

# Pixels outside the rotated source stay `empty` (zero bytes, raylib's calloc).
def render.with(~T: Data, ~blend: T -> T -> T -> T -> F32 -> F32 -> T, +empty: T, +sw: U32, +sh: U32, +width: U32, +height: U32, cosine: F32, sine: F32, pixels: Array<T>) -> Array<T>:
  +count = (width * height : U32)
  depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
  loop(~T, ~blend, U32.to_nat(count), 0, Mapping{sw, sh, width, height, cosine, sine}, empty, (pixels, Array.new(T, depth, empty)))

def render(+sw: U32, +sh: U32, +width: U32, +height: U32, cosine: F32, sine: F32, pixels: Array<U32>) -> Array<U32>:
  render.with(~U32, ~mix.word, 0, sw, sh, width, height, cosine, sine, pixels)
