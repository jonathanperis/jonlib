# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# ImageRotate sampling adapted from pinned raylib rtextures.c; retained notices
# are in THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
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

def fourth(got: Array<U32> & U32, a: U32, b: U32, c: U32, x: F32, y: F32) -> Array<U32> & U32:
  (pixels, d) = got
  (pixels, mix(a, b, c, d, x, y))

def third(got: Array<U32> & U32, last: U32, a: U32, b: U32, x: F32, y: F32) -> Array<U32> & U32:
  (pixels, c) = got
  fourth(Array.get(U32, pixels, last), a, b, c, x, y)

def second(got: Array<U32> & U32, next: U32, last: U32, a: U32, x: F32, y: F32) -> Array<U32> & U32:
  (pixels, b) = got
  third(Array.get(U32, pixels, next), last, a, b, x, y)

def first(got: Array<U32> & U32, next: U32, third: U32, last: U32, x: F32, y: F32) -> Array<U32> & U32:
  (pixels, a) = got
  second(Array.get(U32, pixels, next), third, last, a, x, y)

def sample(inside: Bool, +width: U32, height: U32, +x: F32, +y: F32, pixels: Array<U32>) -> Array<U32> & U32:
  match inside:
    case False{}: (pixels, 0)
    case True{}:
      +x1 = F32.to_u32(F32.floor(x))
      +y1 = F32.to_u32(F32.floor(y))
      +x2 = U32.min((x1 + 1 : U32), (width - 1 : U32))
      +y2 = U32.min((y1 + 1 : U32), (height - 1 : U32))
      first(Array.get(U32, pixels, (y1 * width + x1 : U32)), (y1 * width + x2 : U32),
        (y2 * width + x1 : U32), (y2 * width + x2 : U32), (x - U32.to_f32(x1) : F32), (y - U32.to_f32(y1) : F32))

def pixel(mapping: Mapping, +index: U32, pixels: Array<U32>) -> Array<U32> & U32:
  Mapping{+sw, +sh, +width, height, +cosine, +sine} = mapping
  +x = (U32.to_f32((index % width : U32)) - U32.to_f32(width) / 2.0 : F32)
  +y = (U32.to_f32((index / width : U32)) - U32.to_f32(height) / 2.0 : F32)
  +old_x = ((x * cosine + y * sine) + U32.to_f32(sw) / 2.0 : F32)
  +old_y = ((y * cosine - x * sine) + U32.to_f32(sh) / 2.0 : F32)
  sample(((old_x >= 0.0) && (old_x < U32.to_f32(sw)) && (old_y >= 0.0) && (old_y < U32.to_f32(sh)) : F32), sw, sh, old_x, old_y, pixels)

def write(index: U32, output: Array<U32>, sampled: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (source, value) = sampled
  (source, Array.set(U32, output, index, value))

def loop(n: Nat, +index: U32, +mapping: Mapping, buffers: Array<U32> & Array<U32>) -> Array<U32>:
  match n buffers:
    case 0n Tuple{_, output}: output
    case 1n+k Tuple{source, output}:
      loop(k, (index + 1 : U32), mapping, write(index, output, pixel(mapping, index, source)))

def render(+sw: U32, +sh: U32, +width: U32, +height: U32, cosine: F32, sine: F32, pixels: Array<U32>) -> Array<U32>:
  +count = (width * height : U32)
  depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
  loop(U32.to_nat(count), 0, Mapping{sw, sh, width, height, cosine, sine}, (pixels, Array.new(U32, depth, 0)))
