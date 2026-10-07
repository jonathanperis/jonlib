# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of rl_load_ktx_from_memory, rl_load_pkm_from_memory,
# rl_load_pvr_from_memory and rl_load_astc_from_memory from raylib 6.0's
# rltexgpu.h (single-level files); notice retained in LICENSES/raylib.txt. See
# THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C

# A loaded level: dimensions, raylib PixelFormat and GetPixelDataSize bytes.
type Outcome is Type:
  Loaded{width: U32, height: U32, format: U32, data: +List<U32>}
  Unsupported{}
  Invalid{error: C.Error}

def at.head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, index: U32) -> U32:
  at.head(List.drop(&2, U32, bytes, U32.to_nat(index)))

def le32(+bytes: +List<U32>, +index: U32) -> U32:
  (at(bytes, index) .|. (at(bytes, (index + 1 : U32)) << 8n) .|. (at(bytes, (index + 2 : U32)) << 16n) .|. (at(bytes, (index + 3 : U32)) << 24n) : U32)

def le24(+bytes: +List<U32>, +index: U32) -> U32:
  (at(bytes, index) .|. (at(bytes, (index + 1 : U32)) << 8n) .|. (at(bytes, (index + 2 : U32)) << 16n) : U32)

def be16(+bytes: +List<U32>, +index: U32) -> U32:
  ((at(bytes, index) << 8n) .|. at(bytes, (index + 1 : U32)) : U32)

# get_pixel_data_size for the formats these files load.
def bits_per_pixel(format: U32) -> U32:
  match format:
    case 1: 8
    case 4: 24
    case 7: 32
    case 18: 4
    case 19: 4
    case 20: 8
    case 21: 4
    case 22: 4
    case 23: 8
    case 24: 2
    case _: 16

def level_size(+width: U32, +height: U32, +format: U32) -> U32:
  +small = ((width < 4) && (height < 4) : U32)
  Bool.pick(U32, small && ((format >= 14) && (format < 16) : U32), 8,
    Bool.pick(U32, small && ((format >= 16) && (format < 24) : U32), 16, (width * height * bits_per_pixel(format) / 8 : U32)))

# raylib copies `copied` bytes from `offset`; Jonlib keeps the level's
# GetPixelDataSize bytes, which must lie within that copy.
def level(+width: U32, +height: U32, +format: U32, +offset: U32, +copied: U32, +bytes: +List<U32>) -> Outcome:
  +size = level_size(width, height, format)
  +data = List.take(&2, U32, List.drop(&2, U32, bytes, U32.to_nat(offset)), U32.to_nat(copied))
  Bool.pick(Outcome, Bool.not(Nat.is_eq(C.byte_count(data, 0n), U32.to_nat(copied))), Invalid{C.Truncated{}},
    Bool.pick(Outcome, (copied < size : U32), Invalid{C.BadSize{}},
      Loaded{width, height, format, List.take(&2, U32, data, U32.to_nat(size))}))

# PKM: "PKM ", version, then big-endian format, width and height; ETC1 (0),
# ETC2 RGB (1) and ETC2 EAC RGBA (3) data of width*height*bpp/8 bytes.
def pkm.format(code: U32) -> U32:
  match code:
    case 0: 18
    case 1: 19
    case 3: 20
    case _: 0

def pkm(+bytes: +List<U32>) -> Outcome:
  +code = be16(bytes, 6)
  +width = be16(bytes, 8)
  +height = be16(bytes, 10)
  +format = pkm.format(code)
  Bool.pick(Outcome, U32.is_eq(format, 0), Invalid{C.BadHeader{}},
    level(width, height, format, 16, (width * height * Bool.pick(U32, U32.is_eq(code, 3), 8, 4) / 8 : U32), bytes))

# KTX 1.1: the 64-byte header, key/value data, then the first level's byte
# count and data. ETC1/ETC2/ETC2 EAC internal formats; one mipmap level (raylib
# keeps only the first level of a chain while reporting all of them).
def ktx.format(+internal: U32) -> U32:
  Bool.pick(U32, U32.is_eq(internal, 36196), 18, Bool.pick(U32, U32.is_eq(internal, 37492), 19, Bool.pick(U32, U32.is_eq(internal, 37496), 20, 0)))

def ktx(+bytes: +List<U32>) -> Outcome:
  +format = ktx.format(le32(bytes, 28))
  +skip = le32(bytes, 60)
  +offset = (68 + skip : U32)
  Bool.pick(Outcome, U32.is_eq(format, 0) || (skip > 2147483647 : U32), Invalid{C.BadHeader{}},
    Bool.pick(Outcome, U32.is_ne(le32(bytes, 56), 1), Unsupported{},
      level(le32(bytes, 36), le32(bytes, 40), format, offset, le32(bytes, (64 + skip : U32)), bytes)))

# PVR v3: the 52-byte header (channel names and depths select the format),
# metadata, then the first level of the first surface and face.
def pvr.rgb(+alpha: U32, +d0: U32, +d1: U32, +d2: U32, +d3: U32) -> U32:
  Bool.pick(U32, U32.is_eq(alpha, 97),
    Bool.pick(U32, U32.is_eq(d0, 5) && U32.is_eq(d1, 5) && U32.is_eq(d2, 5) && U32.is_eq(d3, 1), 5,
    Bool.pick(U32, U32.is_eq(d0, 4) && U32.is_eq(d1, 4) && U32.is_eq(d2, 4) && U32.is_eq(d3, 4), 6,
    Bool.pick(U32, U32.is_eq(d0, 8) && U32.is_eq(d1, 8) && U32.is_eq(d2, 8) && U32.is_eq(d3, 8), 7, 0))),
  Bool.pick(U32, U32.is_eq(alpha, 0),
    Bool.pick(U32, U32.is_eq(d0, 5) && U32.is_eq(d1, 6) && U32.is_eq(d2, 5), 3,
    Bool.pick(U32, U32.is_eq(d0, 8) && U32.is_eq(d1, 8) && U32.is_eq(d2, 8), 4, 0)), 0))

def pvr.format(+bytes: +List<U32>) -> U32:
  +c0 = at(bytes, 8)
  +c1 = at(bytes, 9)
  +d0 = at(bytes, 12)
  Bool.pick(U32, U32.is_eq(c0, 108) && U32.is_eq(c1, 0) && U32.is_eq(d0, 8), 1,
  Bool.pick(U32, U32.is_eq(c0, 108) && U32.is_eq(c1, 97) && U32.is_eq(d0, 8) && U32.is_eq(at(bytes, 13), 8), 2,
  Bool.pick(U32, U32.is_eq(c0, 114) && U32.is_eq(c1, 103) && U32.is_eq(at(bytes, 10), 98),
    pvr.rgb(at(bytes, 11), d0, at(bytes, 13), at(bytes, 14), at(bytes, 15)),
  Bool.pick(U32, U32.is_eq(c0, 2), 21, Bool.pick(U32, U32.is_eq(c0, 3), 22, 0)))))

def pvr(+bytes: +List<U32>) -> Outcome:
  +format = pvr.format(bytes)
  +width = le32(bytes, 28)
  +height = le32(bytes, 24)
  +skip = le32(bytes, 48)
  Bool.pick(Outcome, Bool.not(U32.is_eq(at(bytes, 0), 80) && U32.is_eq(at(bytes, 1), 86) && U32.is_eq(at(bytes, 2), 82) && U32.is_eq(at(bytes, 3), 3))
      || U32.is_eq(format, 0) || (skip > 2147483647 : U32), Invalid{C.BadHeader{}},
    Bool.pick(Outcome, U32.is_ne(le32(bytes, 44), 1), Unsupported{},
      level(width, height, format, (52 + skip : U32), (width * height * bits_per_pixel(format) / 8 : U32), bytes)))

# ASTC: the 16-byte header with block dimensions and 24-bit sizes; raylib takes
# 128/(blockX*blockY) bits per pixel, loading 8 as ASTC 4x4 and 2 as ASTC 8x8.
def astc(+bytes: +List<U32>) -> Outcome:
  +blocks = (at(bytes, 4) * at(bytes, 5) : U32)
  +bits = Bool.pick(U32, U32.is_eq(blocks, 0), 0, (128 / blocks : U32))
  +width = le24(bytes, 7)
  +height = le24(bytes, 10)
  Bool.pick(Outcome, U32.is_eq(blocks, 0), Invalid{C.BadHeader{}},
    Bool.pick(Outcome, Bool.not(U32.is_eq(bits, 8) || U32.is_eq(bits, 2)), Unsupported{},
      level(width, height, Bool.pick(U32, U32.is_eq(bits, 8), 23, 24), 16, (width * height * bits / 8 : U32), bytes)))

# Signatures as raylib checks them: PKM "PKM ", KTX "KTX 11" at bytes 1..6,
# PVR version byte 'P', ASTC 13 AB A1 5C. Shorter files are truncated.
def checked(enough: Bool, +valid: Bool, outcome: Outcome) -> Outcome:
  match enough:
    case False{}: Invalid{C.Truncated{}}
    case True{}: Bool.pick(Outcome, valid, outcome, Invalid{C.BadHeader{}})

def decode_pkm(+bytes: +List<U32>) -> Outcome:
  checked(Nat.is_le(16n, C.byte_count(bytes, 0n)),
    U32.is_eq(at(bytes, 0), 80) && U32.is_eq(at(bytes, 1), 75) && U32.is_eq(at(bytes, 2), 77) && U32.is_eq(at(bytes, 3), 32), pkm(bytes))

def decode_ktx(+bytes: +List<U32>) -> Outcome:
  checked(Nat.is_le(68n, C.byte_count(bytes, 0n)),
    U32.is_eq(at(bytes, 1), 75) && U32.is_eq(at(bytes, 2), 84) && U32.is_eq(at(bytes, 3), 88)
      && U32.is_eq(at(bytes, 4), 32) && U32.is_eq(at(bytes, 5), 49) && U32.is_eq(at(bytes, 6), 49), ktx(bytes))

def decode_pvr(+bytes: +List<U32>) -> Outcome:
  checked(Nat.is_le(52n, C.byte_count(bytes, 0n)), U32.is_eq(at(bytes, 0), 80), pvr(bytes))

def decode_astc(+bytes: +List<U32>) -> Outcome:
  checked(Nat.is_le(16n, C.byte_count(bytes, 0n)),
    U32.is_eq(at(bytes, 0), 19) && U32.is_eq(at(bytes, 1), 171) && U32.is_eq(at(bytes, 2), 161) && U32.is_eq(at(bytes, 3), 92), astc(bytes))
