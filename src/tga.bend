# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned stb_image/stb_image_write TGA paths.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./formats.bend as F
import ./qoi.bend as Q

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}
  BadStream{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

type Header is Data:
  Header{width: U32, height: U32, top: Bool, rle: Bool, channels: U32, data: +List<U32>}

def header.sized(valid: Bool, width: U32, height: U32, top: Bool, rle: Bool, channels: U32, id: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: Done{Header{width, height, top, rle, channels, List.drop(&2, U32, bytes, U32.to_nat(id))}}

def header.checked(valid: Bool, +width: U32, +height: U32, top: Bool, rle: Bool, channels: U32, id: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, top, rle, channels, id, bytes)

def header(bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{id, Con{0, Con{+kind, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{wl, Con{wh, Con{hl, Con{hh, Con{+bits, Con{descriptor, data}}}}}}}}}}}}}}}}}}:
      +gray = U32.is_eq(kind, 3) || U32.is_eq(kind, 11)
      color = U32.is_eq(kind, 2) || U32.is_eq(kind, 10)
      header.checked((gray && (U32.is_eq(bits, 8) || U32.is_eq(bits, 16))) || (color && (U32.is_eq(bits, 24) || U32.is_eq(bits, 32))),
        (wl .|. (wh << 8n) : U32), (hl .|. (hh << 8n) : U32), ((descriptor .&. 32) > 0 : U32), (kind >= 8 : U32), (bits / 8 : U32), id, data)
    case _: Fail{BadHeader{}}

def rgba(channels: U32, +word: U32) -> U32:
  match channels:
    case 1: ((word << 24n) .|. (word << 16n) .|. (word << 8n) .|. 255 : U32)
    case 2:
      +gray = (word .&. 255 : U32)
      ((gray << 24n) .|. (gray << 16n) .|. (gray << 8n) .|. (word >> 8n) : U32)
    case 3: ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. 255 : U32)
    case _: ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. (word >> 24n) : U32)

type Cursor is Data:
  Cursor{data: +List<U32>, left: U32, repeat: Bool, pixel: U32}

def read(channels: U32, left: U32, repeat: Bool, word: Maybe<&2, F.Word>) -> Result<&2, &2, Error, Cursor>:
  match word:
    case None{}: Fail{Truncated{}}
    case Some{F.Word{value, rest}}: Done{Cursor{rest, left, repeat, rgba(channels, value)}}

def packet(valid: Bool, +channels: U32, +count: U32, repeat: Bool, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match valid:
    case False{}: Fail{BadStream{}}
    case True{}: read(channels, (count - 1 : U32), repeat, F.read_word(U32.to_nat(channels), 0n, 0, data))

def command(remaining: U32, channels: U32, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match data:
    case Nil{}: Fail{Truncated{}}
    case Con{+code, rest}:
      +count = ((code .&. 127) + 1 : U32)
      packet((count <= remaining : U32), channels, count, (code >= 128 : U32), rest)

def next(rle: Bool, fresh: Bool, repeat: Bool, remaining: U32, +channels: U32, left: U32, pixel: U32, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match rle fresh repeat:
    case False{} _ _: read(channels, 0, False{}, F.read_word(U32.to_nat(channels), 0n, 0, data))
    case True{} True{} _: command(remaining, channels, data)
    case True{} False{} True{}: Done{Cursor{data, (left - 1 : U32), True{}, pixel}}
    case True{} False{} False{}: read(channels, (left - 1 : U32), False{}, F.read_word(U32.to_nat(channels), 0n, 0, data))

type State is Type:
  State{cursor: Cursor, pixels: Array<U32>}

def write(index: U32, pixels: Array<U32>, result: Result<&2, &2, Error, Cursor>) -> Result<&1, &1, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Cursor{data, left, repeat, +pixel}}: Done{State{Cursor{data, left, repeat, pixel}, Array.set(U32, pixels, index, pixel)}}

def pixels(n: Nat, +index: U32, +width: U32, +height: U32, +top: Bool, +rle: Bool, +channels: U32, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Image>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{State{_, output}}: Done{Image{width, height, output}}
    case 1n+rest Done{State{Cursor{data, +left, repeat, pixel}, output}}:
      +y = (index / width : U32)
      at = (Bool.pick(U32, top, y, (height - 1 - y : U32)) * width + index % width : U32)
      pixels(rest, (index + 1 : U32), width, height, top, rle, channels,
        write(at, output, next(rle, U32.is_eq(left, 0), repeat, (width * height - index : U32), channels, left, pixel, data)))

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, top, rle, channels, data}}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      pixels(U32.to_nat(count), 0, width, height, top, rle, channels, Done{State{Cursor{data, 0, False{}, 0}, Array.new(U32, depth, 0)}})

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(bytes, True{}), bytes)

type Packet is Data:
  Packet{count: U32, repeat: Bool}

def encode.scan(n: Nat, +length: U32, +repeat: Bool, previous: +List<U32>, following: +List<U32>, stopped: Maybe<&2, U32>) -> U32:
  match n previous following stopped:
    case _ _ _ Some{count}: count
    case 0n _ _ None{}: length
    case _ Nil{} _ None{}: length
    case _ _ Nil{} None{}: length
    case 1n+rest Con{+old, +olds} Con{value, tail} None{}:
      stop = Bool.pick(Maybe<&2, U32>, Bool.xor(repeat, U32.is_eq(old, value)), Some{Bool.pick(U32, repeat, length, (length - 1 : U32))}, None{})
      encode.scan(rest, (length + 1 : U32), repeat, Bool.pick(+List<U32>, repeat, Con{old, olds}, olds), tail, stop)

def encode.packet(colors: +List<U32>) -> Packet:
  match colors:
    case Con{+first, Con{+second, +rest}}:
      +repeat = U32.is_eq(first, second)
      # Raw runs compare the new pixel with the one two positions earlier.
      Packet{encode.scan(126n, 2, repeat, Con{first, Con{second, rest}}, rest, None{}), repeat}
    case _: Packet{1, False{}}

def encode.color(+pixel: U32, bytes: +List<U32>) -> +List<U32>:
  Con{(pixel .&. 255 : U32), Con{(pixel >> 24n : U32), Con{((pixel >> 16n) .&. 255 : U32), Con{((pixel >> 8n) .&. 255 : U32), bytes}}}}

def encode.values(n: Nat, colors: +List<U32>, bytes: +List<U32>) -> +List<U32>:
  match n colors:
    case 0n _: bytes
    case _ Nil{}: bytes
    case 1n+rest Con{pixel, tail}: encode.values(rest, tail, encode.color(pixel, bytes))

def encode.step(+colors: +List<U32>, bytes: +List<U32>, packet: Packet) -> +List<U32> & +List<U32>:
  Packet{+count, +repeat} = packet
  code = Bool.pick(U32, repeat, (count + 127 : U32), (count - 1 : U32))
  (List.drop(&2, U32, colors, U32.to_nat(count)), encode.values(U32.to_nat(Bool.pick(U32, repeat, 1, count)), colors, Con{code, bytes}))

def encode.row(n: Nat, state: +List<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: bytes
    case _ Tuple{Nil{}, bytes}: bytes
    case 1n+rest Tuple{+colors, bytes}: encode.row(rest, encode.step(colors, bytes, encode.packet(colors)))

def encode.read(values: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, value) = read
  (pixels, Con{value, values})

def encode.collect(n: Nat, +index: U32, state: Array<U32> & +List<U32>) -> Array<U32> & +List<U32>:
  match n state:
    case 0n Tuple{pixels, values}: (pixels, List.reverse(&2, U32, values))
    case 1n+rest Tuple{pixels, values}: encode.collect(rest, (index + 1 : U32), encode.read(values, Array.get(U32, pixels, index)))

def encode.collected(width: U32, bytes: +List<U32>, result: Array<U32> & +List<U32>) -> Array<U32> & +List<U32>:
  (pixels, colors) = result
  (pixels, encode.row(U32.to_nat(width), (colors, bytes)))

def encode.rows(n: Nat, +y: U32, +width: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: List.reverse(&2, U32, bytes)
    case 1n+rest Tuple{pixels, bytes}:
      encode.rows(rest, (y - 1 : U32), width, encode.collected(width, bytes, encode.collect(U32.to_nat(width), (y * width : U32), (pixels, Nil{}))))

def encode(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  header = {[8,32,(height >> 8n : U32),(height .&. 255 : U32),(width >> 8n : U32),(width .&. 255 : U32),0,0,0,0,0,0,0,0,0,10,0,0] : +List<U32>}
  encode.rows(U32.to_nat(height), (height - 1 : U32), width, (pixels, header))
