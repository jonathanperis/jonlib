# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_image/stb_image_write BMP paths in raylib 6.0.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C
import ./formats.bend as F


type Words is Data:
  Words{values: +List<U32>, rest: +List<U32>}

type Channel is Data:
  ChannelValue{value: U32}
  ChannelField{mask: U32, shift: Nat, multiplier: U32, shrink: Nat}

type Layout is Data:
  Layout{red: Channel, green: Channel, blue: Channel, alpha: Channel}

# Effective alpha layout determines native components before pixel decoding or
# BI_RGB repair. A present field above the input word still contributes alpha.
def native.alpha(channel: Channel) -> U32:
  match channel:
    case ChannelValue{_}: 3
    case ChannelField{_, _, _, _}: 4

def native.channels(layout: Layout) -> U32:
  Layout{_, _, _, alpha} = layout
  native.alpha(alpha)

type Mode is Data:
  IndexedMode{bits: U32, entry_bytes: U32, bias: U32}
  ColorMode{bytes: U32, layout: Layout, repair: Bool}

type Header is Data:
  Header{width: U32, height: U32, top: Bool, mode: Mode, gap: U32, data: +List<U32>}

def words.step(values: +List<U32>, next: Maybe<&2, F.Word>) -> Maybe<&2, Words>:
  match next:
    case None{}: None{}
    case Some{F.Word{value, rest}}: Some{Words{Con{value, values}, rest}}

def words(n: Nat, +size: Nat, state: Maybe<&2, Words>) -> Maybe<&2, Words>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Words{values, rest}}: Some{Words{List.reverse(&2, U32, values), rest}}
    case 1n+tail Some{Words{values, bytes}}: words(tail, size, words.step(values, F.read_word(size, 0n, 0, bytes)))

def channel.count(+mask: U32) -> U32:
  +pairs = (mask - ((mask >> 1n) .&. 1431655765) : U32)
  +groups = ((pairs .&. 858993459) + ((pairs >> 2n) .&. 858993459) : U32)
  +bytes = ((groups + (groups >> 4n)) .&. 252645135 : U32)
  +halves = (bytes + (bytes >> 8n) : U32)
  ((halves + (halves >> 16n)) .&. 255 : U32)

def channel.scaled(count: U32, mask: U32, shift: Nat) -> Maybe<&2, Channel>:
  match count:
    case 1: Some{ChannelField{mask, shift, 255, 0n}}
    case 2: Some{ChannelField{mask, shift, 85, 0n}}
    case 3: Some{ChannelField{mask, shift, 73, 1n}}
    case 4: Some{ChannelField{mask, shift, 17, 0n}}
    case 5: Some{ChannelField{mask, shift, 33, 2n}}
    case 6: Some{ChannelField{mask, shift, 65, 4n}}
    case 7: Some{ChannelField{mask, shift, 129, 6n}}
    case 8: Some{ChannelField{mask, shift, 1, 0n}}
    case _: None{}

def channel.counted(+mask: U32, +count: U32) -> Maybe<&2, Channel>:
  # Native extraction aligns by highest bit and population; holes are not packed.
  channel.scaled(count, mask, Nat.sub(1n+U32.log2(mask), U32.to_nat(count)))

def channel(+mask: U32, optional: Bool) -> Maybe<&2, Channel>:
  match mask optional:
    case 0 True{}: Some{ChannelValue{255}}
    case 0 False{}: None{}
    case _ _: channel.counted(mask, channel.count(mask))

def mode.color(bytes: U32, repair: Bool, red: Maybe<&2, Channel>, green: Maybe<&2, Channel>, blue: Maybe<&2, Channel>, alpha: Maybe<&2, Channel>) -> Maybe<&2, Mode>:
  match red green blue alpha:
    case Some{r} Some{g} Some{b} Some{a}: Some{ColorMode{bytes, Layout{r, g, b, a}, repair}}
    case _ _ _ _: None{}

def mode.masks(bits: U32, repair: Bool, red: U32, green: U32, blue: U32, alpha: U32) -> Maybe<&2, Mode>:
  mode.color((bits / 8 : U32), repair, channel(red, False{}), channel(green, False{}), channel(blue, False{}), channel(alpha, True{}))

def mode.default(+bits: U32, alpha: U32) -> Maybe<&2, Mode>:
  match bits:
    case 16: mode.masks(16, False{}, 31744, 992, 31, alpha)
    case 24: mode.masks(24, False{}, 16711680, 65280, 255, 0)
    case 32: mode.masks(32, True{}, 16711680, 65280, 255, 4278190080)
    case _: Some{IndexedMode{bits, 4, 0}}

def mode.core(+bits: U32) -> Maybe<&2, Mode>:
  match bits:
    case 24: mode.default(24, 0)
    case _: Some{IndexedMode{bits, 3, 12}}

def mode.selected(explicit: Bool, bits: U32, red: U32, green: U32, blue: U32, alpha: U32) -> Maybe<&2, Mode>:
  match explicit:
    case False{}: mode.default(bits, alpha)
    case True{}: mode.masks(bits, False{}, red, green, blue, alpha)

def header.build(valid: Bool, width: U32, height: U32, top: Bool, gap: U32, data: +List<U32>, mode: Maybe<&2, Mode>) -> Result<&2, &2, C.Error, Header>:
  match valid mode:
    case True{} Some{format}: Done{Header{width, height, top, format, gap, data}}
    case _ _: Fail{C.BadHeader{}}

def header.masks(width: U32, height: U32, top: Bool, bits: U32, compression: U32, gap: U32, result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case Some{Words{Con{r, Con{g, Con{b, Con{a, _}}}}, data}}:
      header.build(True{}, width, height, top, gap, data, mode.selected(U32.is_eq(compression, 3), bits, r, g, b, a))
    case _: Fail{C.BadHeader{}}

def header.info.masks(width: U32, height: U32, top: Bool, bits: U32, gap: U32, result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case Some{Words{Con{+r, Con{+g, Con{+b, Nil{}}}}, data}}:
      header.build(Bool.not(U32.is_eq(r, g) && U32.is_eq(g, b)), width, height, top, gap, data, mode.masks(bits, False{}, r, g, b, 0))
    case _: Fail{C.BadHeader{}}

def header.info(explicit: Bool, width: U32, height: U32, top: Bool, bits: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match explicit:
    case False{}: header.build(True{}, width, height, top, gap, data, mode.default(bits, 0))
    case True{}: header.info.masks(width, height, top, bits, gap, words(3n, 4n, Some{Words{Nil{}, data}}))

def header.info.prefix(width: U32, height: U32, top: Bool, bits: U32, compression: U32, gap: U32, result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case None{}: Fail{C.BadHeader{}}
    # The native 56-byte path discards embedded masks before reading INFO masks.
    case Some{Words{_, data}}: header.info(U32.is_eq(compression, 3), width, height, top, bits, gap, data)

def header.extended(dib: U32, width: U32, height: U32, top: Bool, bits: U32, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match dib:
    case 12: header.build(True{}, width, height, top, gap, data, mode.core(bits))
    case 40: header.info(U32.is_eq(compression, 3), width, height, top, bits, gap, data)
    case 56: header.info.prefix(width, height, top, bits, compression, gap, words(4n, 4n, Some{Words{Nil{}, data}}))
    case 108: header.masks(width, height, top, bits, compression, gap, words(17n, 4n, Some{Words{Nil{}, data}}))
    case _: header.masks(width, height, top, bits, compression, gap, words(21n, 4n, Some{Words{Nil{}, data}}))

def header.sized(valid: Bool, width: U32, height: U32, top: Bool, dib: U32, bits: U32, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid:
    case False{}: Fail{C.BadSize{}}
    case True{}: header.extended(dib, width, height, top, bits, compression, gap, data)

def header.checked(valid: Bool, +width: U32, +height: U32, top: Bool, dib: U32, bits: U32, compression: U32, gap: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid:
    case False{}: Fail{C.BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, top, dib, bits, compression, gap, data)

def header.fields(+offset: U32, +dib: U32, result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case Some{Words{Con{+width, Con{+signed_height, Con{+mode, Con{+compression, Con{_, Con{_, Con{_, Con{_, Con{_, Nil{}}}}}}}}}}, data}}:
      +top = (signed_height >= 2147483648 : U32)
      +height = Bool.pick(U32, top, (0 - signed_height : U32), signed_height)
      +info = U32.is_eq(dib, 40) || U32.is_eq(dib, 56)
      +bits = (mode >> 16n : U32)
      +indexed = U32.is_eq(bits, 1) || U32.is_eq(bits, 4) || U32.is_eq(bits, 8)
      +bitfields = U32.is_eq(compression, 3)
      extra = Bool.pick(U32, info && bitfields, 12, 0)
      +end = (14 + dib + extra : U32)
      +gap = (offset - end : U32)
      header.checked((info || U32.is_eq(dib, 108) || U32.is_eq(dib, 124)) && U32.is_eq((mode .&. 65535 : U32), 1)
        && (indexed || U32.is_eq(bits, 16) || U32.is_eq(bits, 24) || U32.is_eq(bits, 32))
        && (U32.is_eq(compression, 0) || (bitfields && (U32.is_eq(bits, 16) || U32.is_eq(bits, 32))))
        && ((offset >= end) && (gap <= Bool.pick(U32, indexed, 1027, 1024)) : U32)
        && (Bool.not(indexed) || (gap >= 4 : U32)),
        width, height, top, dib, bits, compression, gap, data)
    case _: Fail{C.BadHeader{}}

def header.core(+offset: U32, result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case Some{Words{Con{+dimensions, Con{+mode, Nil{}}}, data}}:
      +gap = (offset - 26 : U32)
      +bits = (mode >> 16n : U32)
      indexed = U32.is_eq(bits, 1) || U32.is_eq(bits, 4) || U32.is_eq(bits, 8)
      header.checked(U32.is_eq((mode .&. 65535 : U32), 1)
        && ((indexed && ((offset >= 41) && (offset <= 808) : U32))
          || (U32.is_eq(bits, 24) && ((offset >= 26) && (gap <= 1024) : U32))),
        (dimensions .&. 65535 : U32), (dimensions >> 16n : U32), False{}, 12, bits, 0, gap, data)
    case _: Fail{C.BadHeader{}}

def header.kind(offset: U32, +dib: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match dib:
    case 12: header.core(offset, words(2n, 4n, Some{Words{Nil{}, data}}))
    case _: header.fields(offset, dib, words(9n, 4n, Some{Words{Nil{}, data}}))

def header.prefix(result: Maybe<&2, Words>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case Some{Words{Con{_, Con{_, Con{offset, Con{dib, Nil{}}}}}, data}}: header.kind(offset, dib, data)
    case _: Fail{C.BadHeader{}}

def header(bytes: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match bytes:
    case Con{66, Con{77, rest}}: header.prefix(words(4n, 4n, Some{Words{Nil{}, rest}}))
    case _: Fail{C.BadHeader{}}

def enough(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

type State is Type:
  State{data: +List<U32>, pixels: Array<U32>, alpha: U32}

def channel.value(channel: Channel, word: U32) -> U32:
  match channel:
    case ChannelValue{value}: value
    case ChannelField{mask, shift, multiplier, shrink}: ((((word .&. mask) >> shift) * multiplier) >> shrink : U32)

def pixel.rgba(layout: Layout, +word: U32) -> U32:
  Layout{red, green, blue, alpha} = layout
  ((channel.value(red, word) << 24n) .|. (channel.value(green, word) << 16n)
    .|. (channel.value(blue, word) << 8n) .|. channel.value(alpha, word) : U32)

def pixel.read(index: U32, layout: Layout, padding: Nat, pixels: Array<U32>, alpha: U32, result: Maybe<&2, F.Word>) -> Result<&1, &1, C.Error, State>:
  match result:
    case None{}: Fail{C.Truncated{}}
    case Some{F.Word{word, data}}:
      +rgba = pixel.rgba(layout, word)
      Done{State{List.drop(&2, U32, data, padding), Array.set(U32, pixels, index, rgba), (alpha .|. (rgba .&. 255) : U32)}}

def pixels(n: Nat, +index: U32, +width: U32, +height: U32, +top: Bool, +bytes: U32, +layout: Layout, +padding: Nat, state: Result<&1, &1, C.Error, State>) -> Result<&1, &1, C.Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{State{data, output, alpha}}:
      +x = (index % width : U32)
      +y = (index / width : U32)
      at = (Bool.pick(U32, top, y, (height - 1 - y : U32)) * width + x : U32)
      pad = Bool.pick(Nat, U32.is_eq((x + 1 : U32), width), padding, 0n)
      pixels(rest, (index + 1 : U32), width, height, top, bytes, layout, padding,
        pixel.read(at, layout, pad, output, alpha, F.read_word(U32.to_nat(bytes), 0n, 0, data)))

def opaque.write(index: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, value) = read
  Array.set(U32, pixels, index, (value .|. 255 : U32))

def opaque(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: opaque(rest, (index + 1 : U32), opaque.write(index, Array.get(U32, pixels, index)))

def finish.alpha(restore: Bool, +width: U32, +height: U32, channels: U32, pixels: Array<U32>) -> C.Image:
  match restore:
    case False{}: C.Image{width, height, channels, pixels}
    case True{}: C.Image{width, height, channels, opaque(U32.to_nat((width * height : U32)), 0, pixels)}

def finish(width: U32, height: U32, channels: U32, restore: Bool, state: Result<&1, &1, C.Error, State>) -> Result<&1, &1, C.Error, C.Image>:
  match state:
    case Fail{error}: Fail{error}
    case Done{State{_, pixels, alpha}}: Done{finish.alpha(restore && U32.is_eq(alpha, 0), width, height, channels, pixels)}

def start.valid(valid: Bool, +width: U32, +height: U32, top: Bool, bytes: U32, +layout: Layout, restore: Bool, padding: U32, data: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  match valid:
    case False{}: Fail{C.Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      finish(width, height, native.channels(layout), restore, pixels(U32.to_nat(count), 0, width, height, top, bytes, layout, U32.to_nat(padding), Done{State{data, Array.new(U32, depth, 0), 0}}))

def start.color(+width: U32, +height: U32, top: Bool, +bytes: U32, layout: Layout, restore: Bool, gap: U32, +data: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  +row = (width * bytes : U32)
  +padding = ((0 - row) .&. 3 : U32)
  # The pinned true-color reader skips the post-header gap twice.
  +skip = (2 * gap : U32)
  start.valid(enough(U32.to_nat((skip + (row + padding) * height : U32)), data), width, height, top, bytes, layout, restore, padding,
    List.drop(&2, U32, data, U32.to_nat(skip)))

type Indexed is Type:
  Indexed{data: +List<U32>, byte: U32, pixels: Array<U32>}

def indexed.byte(fresh: Bool, byte: U32, data: +List<U32>) -> Maybe<&2, F.Word>:
  match fresh:
    case False{}: Some{F.Word{byte, data}}
    case True{}: F.read_word(1n, 0n, 0, data)

def indexed.write(index: U32, byte: U32, padding: Nat, data: +List<U32>, pixels: Array<U32>, color: Maybe<&2, U32>) -> Result<&1, &1, C.Error, Indexed>:
  match color:
    case None{}: Fail{C.BadStream{}}
    case Some{+word}:
      rgba = ((((word >> 16n) .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word .&. 255) << 8n) .|. 255 : U32)
      Done{Indexed{List.drop(&2, U32, data, padding), byte, Array.set(U32, pixels, index, rgba)}}

def indexed.read(index: U32, bits: U32, shift: Nat, palette: +List<U32>, padding: Nat, pixels: Array<U32>, result: Maybe<&2, F.Word>) -> Result<&1, &1, C.Error, Indexed>:
  match result:
    case None{}: Fail{C.Truncated{}}
    case Some{F.Word{+byte, data}}:
      color = ((byte >> shift) .&. ((1 << U32.to_nat(bits)) - 1) : U32)
      indexed.write(index, byte, padding, data, pixels, List.get(&2, U32, palette, U32.to_nat(color)))

def indexed.pixels(n: Nat, +index: U32, +width: U32, +height: U32, +top: Bool, +bits: U32, +palette: +List<U32>, +padding: Nat, state: Result<&1, &1, C.Error, Indexed>) -> Result<&1, &1, C.Error, C.Image>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{Indexed{_, _, output}}: Done{C.Image{width, height, 3, output}}
    case 1n+rest Done{Indexed{data, byte, output}}:
      +x = (index % width : U32)
      +y = (index / width : U32)
      +part = (x % (8 / bits) : U32)
      at = (Bool.pick(U32, top, y, (height - 1 - y : U32)) * width + x : U32)
      pad = Bool.pick(Nat, U32.is_eq((x + 1 : U32), width), padding, 0n)
      indexed.pixels(rest, (index + 1 : U32), width, height, top, bits, palette, padding,
        indexed.read(at, bits, U32.to_nat((8 - bits - part * bits : U32)), palette, pad, output,
          indexed.byte(U32.is_eq(part, 0), byte, data)))

def indexed.start(valid: Bool, +width: U32, +height: U32, top: Bool, bits: U32, palette: +List<U32>, padding: U32, data: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  match valid:
    case False{}: Fail{C.Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      indexed.pixels(U32.to_nat(count), 0, width, height, top, bits, palette, U32.to_nat(padding), Done{Indexed{data, 0, Array.new(U32, depth, 0)}})

def indexed.palette(+width: U32, +height: U32, top: Bool, +bits: U32, +skip: U32, result: Maybe<&2, Words>) -> Result<&1, &1, C.Error, C.Image>:
  match result:
    case None{}: Fail{C.Truncated{}}
    case Some{Words{palette, +data}}:
      +row = ((width * bits + 7) / 8 : U32)
      +padding = ((0 - row) .&. 3 : U32)
      indexed.start(enough(U32.to_nat((skip + (row + padding) * height : U32)), data), width, height, top, bits, palette, padding,
        List.drop(&2, U32, data, U32.to_nat(skip)))

def start.indexed(width: U32, height: U32, top: Bool, bits: U32, +entry_bytes: U32, bias: U32, +gap: U32, data: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  # Native CORE palette sizing subtracts twelve extra bytes before counting triples.
  +count = ((gap - bias) / entry_bytes : U32)
  indexed.palette(width, height, top, bits, (gap - count * entry_bytes : U32),
    words(U32.to_nat(count), U32.to_nat(entry_bytes), Some{Words{Nil{}, data}}))

def start.mode(width: U32, height: U32, top: Bool, mode: Mode, gap: U32, data: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  match mode:
    case IndexedMode{bits, entry_bytes, bias}: start.indexed(width, height, top, bits, entry_bytes, bias, gap, data)
    case ColorMode{bytes, layout, repair}: start.color(width, height, top, bytes, layout, repair, gap, data)

def start(result: Result<&2, &2, C.Error, Header>) -> Result<&1, &1, C.Error, C.Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{width, height, top, mode, gap, data}}: start.mode(width, height, top, mode, gap, data)

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  match valid:
    case False{}: Fail{C.BadByte{}}
    case True{}: start(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, C.Error, C.Image>:
  checked(C.valid_bytes(bytes, True{}), bytes)

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

# Altered stb_image_write comp=1/2/3 BMP path. Gray-alpha discards alpha;
# grayscale expands to BGR, and each bottom-up row ends in zero padding.
def encode24.padding(n: Nat, bytes: +List<U32>) -> +List<U32>:
  match n:
    case 0n: bytes
    case 1n+rest: encode24.padding(rest, Con{0, bytes})

def encode24.row(end: Bool, padding: Nat, bytes: +List<U32>) -> +List<U32>:
  match end:
    case False{}: bytes
    case True{}: encode24.padding(padding, bytes)

def encode24.read(end: Bool, padding: Nat, format: U32, bytes: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, word) = read
  +rgba = F.image_color(format, word)
  (pixels, encode24.row(end, padding, Con{(rgba >> 24n : U32), Con{((rgba >> 16n) .&. 255 : U32), Con{((rgba >> 8n) .&. 255 : U32), bytes}}}))

def encode24.pixels(n: Nat, +index: U32, +width: U32, +height: U32, +format: U32, +padding: Nat, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: List.reverse(&2, U32, bytes)
    case 1n+rest Tuple{pixels, bytes}:
      at = ((height - 1 - index / width) * width + index % width : U32)
      encode24.pixels(rest, (index + 1 : U32), width, height, format, padding,
        encode24.read(U32.is_eq((index % width : U32), (width - 1 : U32)), padding, format, bytes, Array.get(U32, pixels, at)))

def encode24(+width: U32, +height: U32, format: U32, pixels: Array<U32>) -> +List<U32>:
  # Checked owners bound each axis to 1..4096: the largest file is 50,331,702
  # bytes and width*height <= 16,777,216, so every U32 size/index stays in range.
  +padding = ((0 - width * 3) .&. 3 : U32)
  fields = F.bytes(~&2, [(54 + (width * 3 + padding) * height : U32), 0, 54, 40, width, height, 1572865, 0, 0, 0, 0, 0, 0], 4n, Nil{})
  Con{66, Con{77, List.append(&2, U32, fields, encode24.pixels(U32.to_nat((width * height : U32)), 0, width, height, format, U32.to_nat(padding), (pixels, Nil{})))}}
