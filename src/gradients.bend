# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Gradient formulas adapted from the pinned raylib rtextures.c; see its notices.
import Base

type Paint is Data:
  Radial{cx: F32, cy: F32, radius: F32, density: F32, inner: U32, outer: U32}
  Linear{cosine: F32, sine: F32, start: F32, extent: F32, inner: U32, outer: U32}

def mix.channel(inner: U32, outer: U32, +factor: F32) -> U32:
  F32.to_u32((U32.to_f32(outer) * factor + U32.to_f32(inner) * (1.0 - factor) : F32))

def mix(+inner: U32, +outer: U32, factor: F32) -> U32:
  +f = F32.clamp(factor, 0.0, 1.0)
  r = mix.channel((inner >> 24n : U32), (outer >> 24n : U32), f)
  g = mix.channel(((inner >> 16n) .&. 255 : U32), ((outer >> 16n) .&. 255 : U32), f)
  b = mix.channel(((inner >> 8n) .&. 255 : U32), ((outer >> 8n) .&. 255 : U32), f)
  a = mix.channel((inner .&. 255 : U32), (outer .&. 255 : U32), f)
  ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32)

def radial.factor(full: Bool, distance: F32, +radius: F32, +density: F32) -> F32:
  match full:
    case True{}: Bool.pick(F32, (distance > radius : F32), 1.0, 0.0)
    case False{}: ((distance - radius * density) / (radius * (1.0 - density)) : F32)

def pixel(paint: Paint, +x: F32, +y: F32) -> U32:
  match paint:
    case Radial{cx, cy, radius, +density, inner, outer}:
      +dx = (x - cx : F32)
      +dy = (y - cy : F32)
      distance = F32.sqrt((dx * dx + dy * dy : F32))
      mix(inner, outer, radial.factor(F32.is_eq(density, 1.0), distance, radius, density))
    case Linear{cosine, sine, start, extent, inner, outer}:
      position = ((start + (x * cosine + y * sine)) / extent : F32)
      mix(inner, outer, (F32.clamp(position, F32.neg(1.0), 1.0) / 2.0 + 0.5 : F32))

def leaf(inside: Bool, paint: Paint, +at: U32, +width: U32) -> Array<U32>:
  match inside:
    case False{}: ALeaf{0}
    case True{}: ALeaf{pixel(paint, U32.to_f32((at % width : U32)), U32.to_f32((at / width : U32)))}

def serial(+depth: Nat, +at: U32, +width: U32, +count: U32, +paint: Paint) -> Array<U32>:
  match depth:
    case 0n: leaf((at < count : U32), paint, at, width)
    case 1n+k:
      ANode{serial(k, at, width, count, paint), serial(k, (at + U32.shln(1, k) : U32), width, count, paint)}

# Independent owned subarrays; at most 256 pixels of serial work per leaf task.
def build(+forks: Nat, +leaf_depth: Nat, +at: U32, +width: U32, +count: U32, +paint: Paint) -> Array<U32>:
  match forks:
    case 0n: serial(leaf_depth, at, width, count, paint)
    case 1n+k:
      +half = U32.shln(1, (k + leaf_depth : Nat))
      left right = build(k, leaf_depth, at, width, count, paint) build(k, leaf_depth, (at + half : U32), width, count, paint)
      ANode{left, right}

def generate(+depth: Nat, width: U32, count: U32, paint: Paint) -> Array<U32>:
  +leaf_depth = Nat.min(depth, 8n)
  build((depth - leaf_depth : Nat), leaf_depth, 0, width, count, paint)
