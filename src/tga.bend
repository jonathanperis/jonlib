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
  Header{width: U32, height: U32, top: Bool, rle: Bool, channels: U32, packed: Bool, palette: +List<U32>, data: +List<U32>}

def rgba.bytes(channels: U32, +word: U32) -> U32:
  match channels:
    case 1: ((word << 24n) .|. (word << 16n) .|. (word << 8n) .|. 255 : U32)
    case 2:
      +gray = (word .&. 255 : U32)
      ((gray << 24n) .|. (gray << 16n) .|. (gray << 8n) .|. (word >> 8n) : U32)
    case 3: ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. 255 : U32)
    case _: ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. (word >> 24n) : U32)

def rgba(packed: Bool, channels: U32, +word: U32) -> U32:
  match packed:
    case False{}: rgba.bytes(channels, word)
    case True{}:
      # Native RGB555 expands by integer division and ignores the high alpha bit.
      r = (((word >> 10n) .&. 31) * 255 / 31 : U32)
      g = (((word >> 5n) .&. 31) * 255 / 31 : U32)
      b = ((word .&. 31) * 255 / 31 : U32)
      ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. 255 : U32)

type ColorMap is Data:
  NoColorMap{}
  ColorMap{skip: U32, count: U32, channels: U32, packed: Bool}

type Palette is Data:
  Palette{colors: +List<U32>, data: +List<U32>}

def palette.color(channels: U32, packed: Bool, colors: +List<U32>, word: Maybe<&2, F.Word>) -> Result<&2, &2, Error, Palette>:
  match word:
    case None{}: Fail{Truncated{}}
    case Some{F.Word{value, data}}: Done{Palette{Con{rgba(packed, channels, value), colors}, data}}

def palette.read(n: Nat, +channels: U32, +packed: Bool, state: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Palette>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{Palette{colors, data}}: Done{Palette{List.reverse(&2, U32, colors), data}}
    case 1n+rest Done{Palette{colors, data}}:
      palette.read(rest, channels, packed, palette.color(channels, packed, colors, F.read_word(U32.to_nat(channels), 0n, 0, data)))

def palette.load(map: ColorMap, data: +List<U32>) -> Result<&2, &2, Error, Palette>:
  match map:
    case NoColorMap{}: Done{Palette{Nil{}, data}}
    case ColorMap{skip, count, channels, packed}:
      # The native palette-start field skips bytes, not logical color indices.
      palette.read(U32.to_nat(count), channels, packed, Done{Palette{Nil{}, List.drop(&2, U32, data, U32.to_nat(skip))}})

def palette.spec(indexed: Bool, skip: U32, count: U32, +bits: U32) -> ColorMap:
  match indexed:
    case False{}: NoColorMap{}
    case True{}: ColorMap{skip, count, ((bits + 7) / 8 : U32), U32.is_eq(bits, 15) || U32.is_eq(bits, 16)}

def header.palette(width: U32, height: U32, top: Bool, rle: Bool, channels: U32, packed: Bool, result: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Header>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Palette{colors, data}}: Done{Header{width, height, top, rle, channels, packed, colors, data}}

def header.sized(valid: Bool, width: U32, height: U32, top: Bool, rle: Bool, channels: U32, packed: Bool, map: ColorMap, id: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: header.palette(width, height, top, rle, channels, packed, palette.load(map, List.drop(&2, U32, bytes, U32.to_nat(id))))

def header.checked(valid: Bool, +width: U32, +height: U32, top: Bool, rle: Bool, channels: U32, packed: Bool, map: ColorMap, id: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, top, rle, channels, packed, map, id, bytes)

def header(bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{id, Con{+map, Con{+kind, Con{sl, Con{sh, Con{cl, Con{ch, Con{+entry_bits, Con{_, Con{_, Con{_, Con{_, Con{wl, Con{wh, Con{hl, Con{hh, Con{+bits, Con{descriptor, data}}}}}}}}}}}}}}}}}}:
      +gray = U32.is_eq(kind, 3) || U32.is_eq(kind, 11)
      color = U32.is_eq(kind, 2) || U32.is_eq(kind, 10)
      packed = U32.is_eq(bits, 15) || (U32.is_eq(bits, 16) && Bool.not(gray))
      direct = U32.is_eq(map, 0) && (gray || color)
        && (U32.is_eq(bits, 8) || U32.is_eq(bits, 15) || U32.is_eq(bits, 16) || U32.is_eq(bits, 24) || U32.is_eq(bits, 32))
      +indexed = U32.is_eq(map, 1)
      +count = (cl .|. (ch << 8n) : U32)
      mapped = indexed && (count > 0 : U32) && (U32.is_eq(kind, 1) || U32.is_eq(kind, 9)) && (U32.is_eq(bits, 8) || U32.is_eq(bits, 16))
        && (U32.is_eq(entry_bits, 8) || U32.is_eq(entry_bits, 15) || U32.is_eq(entry_bits, 16) || U32.is_eq(entry_bits, 24) || U32.is_eq(entry_bits, 32))
      header.checked(direct || mapped, (wl .|. (wh << 8n) : U32), (hl .|. (hh << 8n) : U32),
        ((descriptor .&. 32) > 0 : U32), (kind >= 8 : U32), ((bits + 7) / 8 : U32), packed,
        palette.spec(indexed, (sl .|. (sh << 8n) : U32), count, entry_bits), id, data)
    case _: Fail{BadHeader{}}

def rgba.selected(palette: +List<U32>, packed: Bool, channels: U32, word: U32) -> U32:
  match palette:
    case Nil{}: rgba(packed, channels, word)
    case Con{+first, rest}:
      # Native out-of-range indices select entry zero.
      Maybe.default(&2, U32, List.get(&2, U32, Con{first, rest}, U32.to_nat(word)), first)

type Cursor is Data:
  Cursor{data: +List<U32>, left: U32, repeat: Bool, pixel: U32}

def read(channels: U32, packed: Bool, palette: +List<U32>, left: U32, repeat: Bool, word: Maybe<&2, F.Word>) -> Result<&2, &2, Error, Cursor>:
  match word:
    case None{}: Fail{Truncated{}}
    case Some{F.Word{value, rest}}: Done{Cursor{rest, left, repeat, rgba.selected(palette, packed, channels, value)}}

def packet(valid: Bool, +channels: U32, packed: Bool, palette: +List<U32>, +count: U32, repeat: Bool, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match valid:
    case False{}: Fail{BadStream{}}
    case True{}: read(channels, packed, palette, (count - 1 : U32), repeat, F.read_word(U32.to_nat(channels), 0n, 0, data))

def command(remaining: U32, channels: U32, packed: Bool, palette: +List<U32>, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match data:
    case Nil{}: Fail{Truncated{}}
    case Con{+code, rest}:
      +count = ((code .&. 127) + 1 : U32)
      packet((count <= remaining : U32), channels, packed, palette, count, (code >= 128 : U32), rest)

def next(rle: Bool, fresh: Bool, repeat: Bool, remaining: U32, +channels: U32, packed: Bool, palette: +List<U32>, left: U32, pixel: U32, data: +List<U32>) -> Result<&2, &2, Error, Cursor>:
  match rle fresh repeat:
    case False{} _ _: read(channels, packed, palette, 0, False{}, F.read_word(U32.to_nat(channels), 0n, 0, data))
    case True{} True{} _: command(remaining, channels, packed, palette, data)
    case True{} False{} True{}: Done{Cursor{data, (left - 1 : U32), True{}, pixel}}
    case True{} False{} False{}: read(channels, packed, palette, (left - 1 : U32), False{}, F.read_word(U32.to_nat(channels), 0n, 0, data))

type State is Type:
  State{cursor: Cursor, pixels: Array<U32>}

def write(index: U32, pixels: Array<U32>, result: Result<&2, &2, Error, Cursor>) -> Result<&1, &1, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Cursor{data, left, repeat, +pixel}}: Done{State{Cursor{data, left, repeat, pixel}, Array.set(U32, pixels, index, pixel)}}

def pixels(n: Nat, +index: U32, +width: U32, +height: U32, +top: Bool, +rle: Bool, +channels: U32, +packed: Bool, +palette: +List<U32>, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Image>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{State{_, output}}: Done{Image{width, height, output}}
    case 1n+rest Done{State{Cursor{data, +left, repeat, pixel}, output}}:
      +y = (index / width : U32)
      at = (Bool.pick(U32, top, y, (height - 1 - y : U32)) * width + index % width : U32)
      pixels(rest, (index + 1 : U32), width, height, top, rle, channels, packed, palette,
        write(at, output, next(rle, U32.is_eq(left, 0), repeat, (width * height - index : U32), channels, packed, palette, left, pixel, data)))

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, top, rle, channels, packed, palette, data}}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      pixels(U32.to_nat(count), 0, width, height, top, rle, channels, packed, palette, Done{State{Cursor{data, 0, False{}, 0}, Array.new(U32, depth, 0)}})

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

# Canonical pixels use 0xRRGGBBAA. Output is accumulated in reverse.
def encode.color(channels: U32, +pixel: U32, bytes: +List<U32>) -> +List<U32>:
  match channels:
    case 1: Con{(pixel >> 24n : U32), bytes}
    case 2: Con{(pixel .&. 255 : U32), Con{(pixel >> 24n : U32), bytes}}
    case 3: Con{(pixel >> 24n : U32), Con{((pixel >> 16n) .&. 255 : U32), Con{((pixel >> 8n) .&. 255 : U32), bytes}}}
    case _: Con{(pixel .&. 255 : U32), Con{(pixel >> 24n : U32), Con{((pixel >> 16n) .&. 255 : U32), Con{((pixel >> 8n) .&. 255 : U32), bytes}}}}

def encode.values(n: Nat, +channels: U32, colors: +List<U32>, bytes: +List<U32>) -> +List<U32>:
  match n colors:
    case 0n _: bytes
    case _ Nil{}: bytes
    case 1n+rest Con{pixel, tail}: encode.values(rest, channels, tail, encode.color(channels, pixel, bytes))

def encode.step(+channels: U32, +colors: +List<U32>, bytes: +List<U32>, packet: Packet) -> +List<U32> & +List<U32>:
  Packet{+count, +repeat} = packet
  code = Bool.pick(U32, repeat, (count + 127 : U32), (count - 1 : U32))
  (List.drop(&2, U32, colors, U32.to_nat(count)), encode.values(U32.to_nat(Bool.pick(U32, repeat, 1, count)), channels, colors, Con{code, bytes}))

def encode.row(n: Nat, +channels: U32, state: +List<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: bytes
    case _ Tuple{Nil{}, bytes}: bytes
    case 1n+rest Tuple{+colors, bytes}: encode.row(rest, channels, encode.step(channels, colors, bytes, encode.packet(colors)))

def encode.read(values: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, value) = read
  (pixels, Con{value, values})

def encode.collect(n: Nat, +index: U32, state: Array<U32> & +List<U32>) -> Array<U32> & +List<U32>:
  match n state:
    case 0n Tuple{pixels, values}: (pixels, List.reverse(&2, U32, values))
    case 1n+rest Tuple{pixels, values}: encode.collect(rest, (index + 1 : U32), encode.read(values, Array.get(U32, pixels, index)))

def encode.collected(channels: U32, width: U32, bytes: +List<U32>, result: Array<U32> & +List<U32>) -> Array<U32> & +List<U32>:
  (pixels, colors) = result
  (pixels, encode.row(U32.to_nat(width), channels, (colors, bytes)))

def encode.rows(n: Nat, +channels: U32, +y: U32, +width: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: List.reverse(&2, U32, bytes)
    case 1n+rest Tuple{pixels, bytes}:
      encode.rows(rest, channels, (y - 1 : U32), width, encode.collected(channels, width, bytes, encode.collect(U32.to_nat(width), (y * width : U32), (pixels, Nil{}))))

# Internal caller supplies checked channels 1..4 and formatted-normalized pixels
# (unused channels determined by emitted ones), matching native equality.
# Per-row packet selection is unchanged from pinned stb_image_write RLE.
def encode.channels(+width: U32, +height: U32, +channels: U32, pixels: Array<U32>) -> +List<U32>:
  alpha = Bool.pick(U32, U32.is_eq(channels, 2) || U32.is_eq(channels, 4), 8, 0)
  kind = Bool.pick(U32, U32.is_lt(channels, 3), 11, 10)
  header = {[alpha,(channels * 8 : U32),(height >> 8n : U32),(height .&. 255 : U32),(width >> 8n : U32),(width .&. 255 : U32),0,0,0,0,0,0,0,0,0,kind,0,0] : +List<U32>}
  encode.rows(U32.to_nat(height), channels, (height - 1 : U32), width, (pixels, header))

# Preserve the existing Surface/FloatRGB four-channel encoding exactly.
def encode(width: U32, height: U32, pixels: Array<U32>) -> +List<U32>:
  encode.channels(width, height, 4, pixels)
