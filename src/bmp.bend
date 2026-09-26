# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_image/stb_image_write BMP paths in raylib 6.0.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./formats.bend as F
import ./qoi.bend as Q

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

type Words is Data:
  Words{values: +List<U32>, rest: +List<U32>}

type Header is Data:
  Header{width: U32, height: U32, top: Bool, wide: Bool, restore: Bool, gap: U32, data: +List<U32>}

def words.step(values: +List<U32>, next: Maybe<&2, F.Word>) -> Maybe<&2, Words>:
  match next:
    case None{}: None{}
    case Some{F.Word{value, rest}}: Some{Words{Con{value, values}, rest}}

def words(n: Nat, state: Maybe<&2, Words>) -> Maybe<&2, Words>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Words{values, rest}}: Some{Words{List.reverse(&2, U32, values), rest}}
    case 1n+tail Some{Words{values, bytes}}: words(tail, words.step(values, F.read_word(4n, 0n, 0, bytes)))

def header.valid(valid: Bool, header: Header) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: Done{header}

def header.masks(width: U32, height: U32, top: Bool, wide: Bool, +compression: U32, gap: U32, result: Maybe<&2, Words>) -> Result<&2, &2, Error, Header>:
  match result:
    case Some{Words{Con{r, Con{g, Con{b, Con{a, _}}}}, data}}:
      header.valid(U32.is_eq(compression, 0) || (U32.is_eq(r, 16711680) && U32.is_eq(g, 65280) && U32.is_eq(b, 255) && U32.is_eq(a, 4278190080)),
        Header{width, height, top, wide, U32.is_eq(compression, 0), gap, data})
    case _: Fail{BadHeader{}}

def header.extended(v4: Bool, width: U32, height: U32, top: Bool, wide: Bool, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match v4:
    case False{}: Done{Header{width, height, top, wide, True{}, gap, data}}
    case True{}: header.masks(width, height, top, wide, compression, gap, words(17n, Some{Words{Nil{}, data}}))

def header.sized(valid: Bool, width: U32, height: U32, top: Bool, v4: Bool, wide: Bool, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: header.extended(v4, width, height, top, wide, compression, gap, data)

def header.checked(valid: Bool, +width: U32, +height: U32, top: Bool, v4: Bool, wide: Bool, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, top, v4, wide, compression, gap, data)

def header.fields(result: Maybe<&2, Words>) -> Result<&2, &2, Error, Header>:
  match result:
    case Some{Words{Con{_, Con{_, Con{+offset, Con{+dib, Con{+width, Con{+signed_height, Con{+mode, Con{+compression, Con{_, Con{_, Con{_, Con{_, Con{_, Nil{}}}}}}}}}}}}}}, data}}:
      +top = (signed_height >= 2147483648 : U32)
      +height = Bool.pick(U32, top, (0 - signed_height : U32), signed_height)
      +v4 = U32.is_eq(dib, 108)
      +wide = U32.is_eq(mode, 2097153)
      +end = (14 + dib : U32)
      header.checked((U32.is_eq(dib, 40) || v4) && (wide || U32.is_eq(mode, 1572865))
        && (U32.is_eq(compression, 0) || (v4 && wide && U32.is_eq(compression, 3)))
        && ((offset >= end) && (offset - end <= 1024) : U32),
        width, height, top, v4, wide, compression, (offset - end : U32), data)
    case _: Fail{BadHeader{}}

def header(bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{66, Con{77, rest}}: header.fields(words(13n, Some{Words{Nil{}, rest}}))
    case _: Fail{BadHeader{}}

def enough(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

type State is Type:
  State{data: +List<U32>, pixels: Array<U32>, alpha: U32}

def pixel.read(index: U32, wide: Bool, padding: Nat, pixels: Array<U32>, alpha: U32, result: Maybe<&2, F.Word>) -> Result<&1, &1, Error, State>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{F.Word{+word, data}}:
      +a = Bool.pick(U32, wide, (word >> 24n : U32), 255)
      rgba = ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. a : U32)
      Done{State{List.drop(&2, U32, data, padding), Array.set(U32, pixels, index, rgba), (alpha .|. a : U32)}}

def pixels(n: Nat, +index: U32, +width: U32, +height: U32, +top: Bool, +wide: Bool, +padding: Nat, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{State{data, output, alpha}}:
      +x = (index % width : U32)
      +y = (index / width : U32)
      at = (Bool.pick(U32, top, y, (height - 1 - y : U32)) * width + x : U32)
      pad = Bool.pick(Nat, U32.is_eq((x + 1 : U32), width), padding, 0n)
      pixels(rest, (index + 1 : U32), width, height, top, wide, padding,
        pixel.read(at, wide, pad, output, alpha, F.read_word(Bool.pick(Nat, wide, 4n, 3n), 0n, 0, data)))

def opaque.write(index: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, value) = read
  Array.set(U32, pixels, index, (value .|. 255 : U32))

def opaque(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: opaque(rest, (index + 1 : U32), opaque.write(index, Array.get(U32, pixels, index)))

def finish.alpha(restore: Bool, +width: U32, +height: U32, pixels: Array<U32>) -> Image:
  match restore:
    case False{}: Image{width, height, pixels}
    case True{}: Image{width, height, opaque(U32.to_nat((width * height : U32)), 0, pixels)}

def finish(width: U32, height: U32, restore: Bool, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Image>:
  match state:
    case Fail{error}: Fail{error}
    case Done{State{_, pixels, alpha}}: Done{finish.alpha(restore && U32.is_eq(alpha, 0), width, height, pixels)}

def start.valid(valid: Bool, +width: U32, +height: U32, top: Bool, wide: Bool, restore: Bool, padding: U32, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      finish(width, height, restore, pixels(U32.to_nat(count), 0, width, height, top, wide, U32.to_nat(padding), Done{State{data, Array.new(U32, depth, 0), 0}}))

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, top, +wide, restore, gap, +data}}:
      +row = (width * Bool.pick(U32, wide, 4, 3) : U32)
      +padding = ((0 - row) .&. 3 : U32)
      # The pinned true-color reader skips the post-header gap twice.
      +skip = (2 * gap : U32)
      start.valid(enough(U32.to_nat((skip + (row + padding) * height : U32)), data), width, height, top, wide, restore, padding,
        List.drop(&2, U32, data, U32.to_nat(skip)))

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(bytes, True{}), bytes)

def encode.read(bytes: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, +rgba) = read
  (pixels, Con{(rgba .&. 255 : U32), Con{(rgba >> 24n : U32), Con{((rgba >> 16n) .&. 255 : U32), Con{((rgba >> 8n) .&. 255 : U32), bytes}}}})

def encode.pixels(n: Nat, +index: U32, +width: U32, +height: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: List.reverse(&2, U32, bytes)
    case 1n+rest Tuple{pixels, bytes}:
      at = ((height - 1 - index / width) * width + index % width : U32)
      encode.pixels(rest, (index + 1 : U32), width, height, encode.read(bytes, Array.get(U32, pixels, at)))

def encode(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  fields = F.bytes(~&2, [(122 + width * height * 4 : U32), 0, 122, 108, width, height, 2097153, 3, 0, 0, 0, 0, 0,
    16711680, 65280, 255, 4278190080, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4n, Nil{})
  Con{66, Con{77, List.append(&2, U32, fields, encode.pixels(U32.to_nat((width * height : U32)), 0, width, height, (pixels, Nil{})))}}
