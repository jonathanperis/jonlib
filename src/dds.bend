# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of rl_load_dds_from_memory from raylib 6.0's
# rltexgpu.h (uncompressed, single-level files); notice retained in
# LICENSES/raylib.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C
import ./formats.bend as Formats

# Little-endian header words after the "DDS " magic: size, flags, height,
# width, pitch, depth, mipmap count, 11 reserved, then the pixel format
# (size, flags, fourcc, bit count, R/G/B/A masks) and the caps words.
type Header is Data:
  Header{width: U32, height: U32, mipmaps: U32, flags: U32, fourcc: U32, bits: U32, alpha: U32}

type Image is Type:
  Image{width: U32, height: U32, format: U32, data: +List<U32>}

# Decoded owners, files this profile does not hold (compressed blocks or mip
# chains, which raylib loads as multi-level/compressed images) and invalid data.
type Outcome is Type:
  Decoded{image: Image}
  Unsupported{}
  Invalid{error: C.Error}

def words.read(values: +List<U32>, word: Maybe<&2, Formats.Word>) -> Maybe<(+List<U32> & +List<U32>)>:
  match word:
    case None{}: None{}
    case Some{Formats.Word{value, rest}}: Some{(Con{value, values}, rest)}

def words(n: Nat, state: Maybe<(+List<U32> & +List<U32>)>) -> Maybe<(+List<U32> & +List<U32>)>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Tuple{values, rest}}: Some{(List.reverse(&2, U32, values), rest)}
    case 1n+k Some{Tuple{values, rest}}: words(k, words.read(values, Formats.read_word(4n, 0n, 0, rest)))

def head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

def field(index: Nat, +values: +List<U32>) -> U32:
  head(List.drop(&2, U32, values, index))

def header(+values: +List<U32>) -> Header:
  Header{field(3n, values), field(2n, values), field(6n, values), field(19n, values), field(20n, values), field(21n, values), field(25n, values)}

# A1R5G5B5 to R5G5B5A1 and A4R4G4B4 to R4G4B4A4: raylib rotates each 16-bit
# word left by the alpha width.
def rotate16(+shift: Nat, +back: Nat, data: +List<U32>, out: +List<U32>) -> +List<U32>:
  match data:
    case Con{low, Con{high, rest}}:
      +value = (low .|. (high << 8n) : U32)
      +turned = ((((value << shift) .&. 65535) + (value >> back)) .&. 65535 : U32)
      rotate16(shift, back, rest, Con{(turned >> 8n : U32), Con{(turned .&. 255 : U32), out}})
    case _: List.reverse(&2, U32, out)

# raylib swaps the first and third byte of every 32-bit pixel (BGRA to RGBA).
def swap_rb(data: +List<U32>, out: +List<U32>) -> +List<U32>:
  match data:
    case Con{b, Con{g, Con{r, Con{a, rest}}}}: swap_rb(rest, Con{a, Con{b, Con{g, Con{r, out}}}})
    case _: List.reverse(&2, U32, out)

def payload(+format: U32, +count: U32, data: +List<U32>) -> Outcome:
  +size = (count * Bool.pick(U32, U32.is_eq(format, 4), 3, Bool.pick(U32, U32.is_eq(format, 7), 4, 2)) : U32)
  +bytes = List.take(&2, U32, data, U32.to_nat(size))
  Bool.pick(Outcome, Nat.is_eq(C.byte_count(bytes, 0n), U32.to_nat(size)), Decoded{Image{0, 0, format, bytes}}, Invalid{C.Truncated{}})

def converted(+format: U32, +bits: U32, +flags: U32, +alpha: U32) -> U32:
  Bool.pick(U32, U32.is_eq(bits, 16) && U32.is_eq(flags, 64), 3,
  Bool.pick(U32, U32.is_eq(bits, 16) && U32.is_eq(flags, 65) && U32.is_eq(alpha, 32768), 5,
  Bool.pick(U32, U32.is_eq(bits, 16) && U32.is_eq(flags, 65) && U32.is_eq(alpha, 61440), 6,
  Bool.pick(U32, U32.is_eq(bits, 24) && U32.is_eq(flags, 64), 4,
  Bool.pick(U32, U32.is_eq(bits, 32) && U32.is_eq(flags, 65), 7, format)))))

def reorder(kind: U32, data: +List<U32>) -> +List<U32>:
  match kind:
    case 5: rotate16(1n, 15n, data, Nil{})
    case 6: rotate16(4n, 12n, data, Nil{})
    case 7: swap_rb(data, Nil{})
    case _: data

def finished(+width: U32, +height: U32, outcome: Outcome) -> Outcome:
  match outcome:
    case Decoded{Image{_, _, +format, data}}: Decoded{Image{width, height, format, reorder(format, data)}}
    case other: other

# Header checks in raylib's order: 16-bit modes, 24-bit RGB, 32-bit RGBA, then
# FourCC compression. Combinations it leaves without data are invalid.
def selected(head: Header, data: +List<U32>) -> Outcome:
  Header{+width, +height, +mipmaps, +flags, +fourcc, +bits, +alpha} = head
  +format = converted(0, bits, flags, alpha)
  +compressed = U32.is_ne(bits, 16) && (U32.is_eq(flags, 4) || U32.is_eq(flags, 5)) && (fourcc > 0 : U32)
  Bool.pick(Outcome, compressed || ((mipmaps > 1) && U32.is_ne(format, 0) : U32), Unsupported{},
    Bool.pick(Outcome, U32.is_eq(format, 0), Invalid{C.BadHeader{}}, finished(width, height, payload(format, (width * height : U32), data))))

def parsed(state: Maybe<(+List<U32> & +List<U32>)>) -> Outcome:
  match state:
    case None{}: Invalid{C.Truncated{}}
    case Some{Tuple{+values, data}}: selected(header(values), data)

def decode(bytes: +List<U32>) -> Outcome:
  match bytes:
    case Con{68, Con{68, Con{83, Con{32, rest}}}}: parsed(words(31n, Some{(Nil{}, rest)}))
    case _: Invalid{C.BadHeader{}}
