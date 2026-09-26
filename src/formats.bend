# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 ImageFormat/LoadImageDataNormalized;
# notice retained in LICENSES/raylib.txt. Byte/integer formats only.
import Base

type Normal is Data:
  Normal{r: F32, g: F32, b: F32, a: F32}

type Word is Data:
  Word{value: U32, rest: +List<U32>}

type Input is Type:
  Input{bytes: +List<U32>, pixels: Array<U32>}

def valid(bytes: +List<U32>, +remaining: U32, ok: Bool) -> Bool:
  match bytes ok:
    case _ False{}: False{}
    case Nil{} True{}: U32.is_eq(remaining, 0)
    case Con{byte, rest} True{}: valid(rest, (remaining - 1 : U32), ((remaining > 0) && (byte <= 255) : U32))

def read_word(n: Nat, +shift: Nat, value: U32, bytes: +List<U32>) -> Maybe<&2, Word>:
  match n bytes:
    case 0n _: Some{Word{value, bytes}}
    case _ Nil{}: None{}
    case 1n+rest Con{byte, tail}: read_word(rest, (shift + 8n : Nat), (value .|. (byte << shift) : U32), tail)

def read_pixel(index: U32, pixels: Array<U32>, word: Maybe<&2, Word>) -> Maybe<Input>:
  match word:
    case None{}: None{}
    case Some{Word{value, rest}}: Some{Input{rest, Array.set(U32, pixels, index, value)}}

def unpack(n: Nat, +index: U32, +bytes_per_pixel: Nat, input: Maybe<Input>) -> Maybe<Array<U32>>:
  match n input:
    case _ None{}: None{}
    case 0n Some{Input{_, pixels}}: Some{pixels}
    case 1n+rest Some{Input{bytes, pixels}}:
      unpack(rest, (index + 1 : U32), bytes_per_pixel, read_pixel(index, pixels, read_word(bytes_per_pixel, 0n, 0, bytes)))

def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})

def bytes(~q: Quant, pixels: List<U32>, +bytes_per_pixel: Nat, values: List<q, U32>) -> List<q, U32>:
  match pixels:
    case Nil{}: List.reverse(q, U32, values)
    case Con{word, rest}: bytes(~q, rest, bytes_per_pixel, word_bytes(~q, bytes_per_pixel, word, values))

def byte_norm(value: U32) -> F32:
  (U32.to_f32(value) / 255.0 : F32)

def packed_norm(value: U32, limit: F32) -> F32:
  (U32.to_f32(value) * (1.0 / limit) : F32)

def decode(format: U32, +word: U32) -> Normal:
  match format:
    case 1:
      +v = byte_norm((word .&. 255 : U32))
      Normal{v, v, v, 1.0}
    case 2:
      +v = byte_norm((word .&. 255 : U32))
      Normal{v, v, v, byte_norm(((word >> 8n) .&. 255 : U32))}
    case 3:
      Normal{packed_norm((word >> 11n : U32), 31.0), packed_norm(((word >> 5n) .&. 63 : U32), 63.0), packed_norm((word .&. 31 : U32), 31.0), 1.0}
    case 4:
      Normal{byte_norm((word .&. 255 : U32)), byte_norm(((word >> 8n) .&. 255 : U32)), byte_norm(((word >> 16n) .&. 255 : U32)), 1.0}
    case 5:
      Normal{packed_norm((word >> 11n : U32), 31.0), packed_norm(((word >> 6n) .&. 31 : U32), 31.0),
        packed_norm(((word >> 1n) .&. 31 : U32), 31.0), U32.to_f32((word .&. 1 : U32))}
    case 6:
      Normal{packed_norm((word >> 12n : U32), 15.0), packed_norm(((word >> 8n) .&. 15 : U32), 15.0),
        packed_norm(((word >> 4n) .&. 15 : U32), 15.0), packed_norm((word .&. 15 : U32), 15.0)}
    case _:
      Normal{byte_norm((word .&. 255 : U32)), byte_norm(((word >> 8n) .&. 255 : U32)),
        byte_norm(((word >> 16n) .&. 255 : U32)), byte_norm((word >> 24n : U32))}

def level(value: F32, limit: F32) -> U32:
  F32.to_u32(F32.floor((value * limit + 0.5 : F32)))

def luminance(r: F32, g: F32, b: F32) -> U32:
  F32.to_u32(((r * 0.299 + g * 0.587 + b * 0.114) * 255.0 : F32))

def encode(normal: Normal, format: U32) -> U32:
  Normal{r, g, b, a} = normal
  match format:
    case 1: luminance(r, g, b)
    case 2: (luminance(r, g, b) .|. (F32.to_u32((a * 255.0 : F32)) << 8n) : U32)
    case 3: ((level(r, 31.0) << 11n) .|. (level(g, 63.0) << 5n) .|. level(b, 31.0) : U32)
    case 4: (F32.to_u32((r * 255.0 : F32)) .|. (F32.to_u32((g * 255.0 : F32)) << 8n) .|. (F32.to_u32((b * 255.0 : F32)) << 16n) : U32)
    case 5: ((level(r, 31.0) << 11n) .|. (level(g, 31.0) << 6n) .|. (level(b, 31.0) << 1n) .|. Bool.to_u32((a > 50.0 / 255.0 : F32)) : U32)
    case 6: ((level(r, 15.0) << 12n) .|. (level(g, 15.0) << 8n) .|. (level(b, 15.0) << 4n) .|. level(a, 15.0) : U32)
    case _: (F32.to_u32((r * 255.0 : F32)) .|. (F32.to_u32((g * 255.0 : F32)) << 8n) .|. (F32.to_u32((b * 255.0 : F32)) << 16n) .|. (F32.to_u32((a * 255.0 : F32)) << 24n) : U32)

def converted(index: U32, from: U32, to: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, word) = read
  Array.set(U32, pixels, index, encode(decode(from, word), to))

def convert(n: Nat, +index: U32, +from: U32, +to: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: convert(rest, (index + 1 : U32), from, to, converted(index, from, to, Array.get(U32, pixels, index)))

def swap(+word: U32) -> U32:
  ((word >> 24n) .|. (((word >> 16n) .&. 255) << 8n) .|. (((word >> 8n) .&. 255) << 16n) .|. (word << 24n) : U32)

def swapped(index: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, word) = read
  Array.set(U32, pixels, index, swap(word))

def swap_pixels(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: swap_pixels(rest, (index + 1 : U32), swapped(index, Array.get(U32, pixels, index)))
