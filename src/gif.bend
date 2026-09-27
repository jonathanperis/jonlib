# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image first-frame GIF reader.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./qoi.bend as Q
import ./gif_lzw.bend as Lzw

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}
  BadStream{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

def signature(bytes: +List<U32>) -> Bool:
  match bytes:
    case Con{71, Con{73, Con{70, Con{56, Con{+version, Con{97, _}}}}}}: U32.is_eq(version, 55) || U32.is_eq(version, 57)
    case _: False{}

def byte_count(data: +List<U32>, count: Nat) -> Nat:
  match data:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, 1n+count)

type Palette is Data:
  Palette{colors: +List<U32>, data: +List<U32>}

def palette(n: Nat, data: +List<U32>, colors: +List<U32>) -> Result<&2, &2, Error, Palette>:
  match n data:
    case 0n _: Done{Palette{List.reverse(&2, U32, colors), data}}
    case 1n+rest Con{r, Con{g, Con{b, tail}}}:
      palette(rest, tail, Con{((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. 255 : U32), colors})
    case _ _: Fail{Truncated{}}

def palette.load(present: Bool, flags: U32, data: +List<U32>) -> Result<&2, &2, Error, Palette>:
  match present:
    case False{}: Done{Palette{Nil{}, data}}
    case True{}: palette(U32.to_nat((2 << U32.to_nat((flags .&. 7 : U32)) : U32)), data, Nil{})

type Header is Data:
  Header{width: U32, height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>}

def header.palette(width: U32, height: U32, result: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Header>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Palette{colors, data}}: Done{Header{width, height, colors, None{}, data}}

def header.sized(valid: Bool, width: U32, height: U32, +flags: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: header.palette(width, height, palette.load(U32.is_ne((flags .&. 128 : U32), 0), flags, data))

def header.fields(data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match data:
    case Con{wl, Con{wh, Con{hl, Con{hh, Con{flags, Con{_, Con{_, rest}}}}}}}:
      +width = (wl .|. (wh << 8n) : U32)
      +height = (hl .|. (hh << 8n) : U32)
      header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, flags, rest)
    case _: Fail{BadHeader{}}

def header.valid(valid: Bool, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.fields(List.drop(&2, U32, data, 6n))

def header(+data: +List<U32>) -> Result<&2, &2, Error, Header>:
  header.valid(signature(data), data)

type Blocks is Data:
  Blocks{bytes: +List<U32>, data: +List<U32>}

def take(n: Nat, data: +List<U32>, values: +List<U32>) -> Maybe<&2, Blocks>:
  match n data:
    case 0n _: Some{Blocks{values, data}}
    case _ Nil{}: None{}
    case 1n+rest Con{value, tail}: take(rest, tail, Con{value, values})

type Collection is Data:
  Collection{ended: Bool, values: +List<U32>, data: +List<U32>}

def block.read(result: Maybe<&2, Blocks>) -> Maybe<&2, Collection>:
  match result:
    case None{}: None{}
    case Some{Blocks{values, data}}: Some{Collection{False{}, values, data}}

def block(values: +List<U32>, data: +List<U32>) -> Maybe<&2, Collection>:
  match data:
    case Nil{}: None{}
    case Con{0, rest}: Some{Collection{True{}, values, rest}}
    case Con{size, rest}: block.read(take(U32.to_nat(size), rest, values))

def blocks(n: Nat, state: Maybe<&2, Collection>) -> Maybe<&2, Blocks>:
  match n state:
    case _ None{}: None{}
    case _ Some{Collection{True{}, values, data}}: Some{Blocks{List.reverse(&2, U32, values), data}}
    case 0n _: None{}
    case 1n+rest Some{Collection{False{}, values, data}}: blocks(rest, block(values, data))

def collect(+data: +List<U32>) -> Maybe<&2, Blocks>:
  blocks(byte_count(data, 0n), Some{Collection{False{}, Nil{}, data}})

type Frame is Data:
  Frame{width: U32, height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, minimum: U32, data: +List<U32>}

type Search is Data:
  Seeking{header: Header}
  Found{frame: Frame}

def extension.data(width: U32, height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, result: Maybe<&2, Blocks>) -> Result<&2, &2, Error, Search>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Blocks{_, data}}: Done{Seeking{Header{width, height, palette, transparent, data}}}

def extension.control(width: U32, height: U32, palette: +List<U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match data:
    case Con{4, Con{flags, Con{_, Con{_, Con{index, rest}}}}}:
      transparent = Bool.pick(Maybe<&2, U32>, U32.is_ne((flags .&. 1 : U32), 0), Some{index}, None{})
      extension.data(width, height, palette, transparent, collect(rest))
    case _: Fail{BadHeader{}}

def extension(label: U32, width: U32, height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match label:
    case 249: extension.control(width, height, palette, data)
    case _: extension.data(width, height, palette, transparent, collect(data))

def frame.blocks(valid: Bool, width: U32, height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, minimum: U32, result: Maybe<&2, Blocks>) -> Result<&2, &2, Error, Search>:
  match valid result:
    case False{} _: Fail{BadHeader{}}
    case True{} None{}: Fail{Truncated{}}
    case True{} Some{Blocks{bytes, _}}: Done{Found{Frame{width, height, palette, transparent, minimum, bytes}}}

def frame.data(width: U32, height: U32, transparent: Maybe<&2, U32>, result: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Search>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Palette{Nil{}, _}}: Fail{BadHeader{}}
    case Done{Palette{colors, Con{+minimum, data}}}:
      frame.blocks(((minimum >= 2) && (minimum <= 8) : U32), width, height, colors, transparent, minimum, collect(data))
    case _: Fail{BadHeader{}}

def frame.palette(local: Bool, width: U32, height: U32, flags: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match local:
    case False{}: frame.data(width, height, transparent, Done{Palette{palette, data}})
    case True{}: frame.data(width, height, transparent, palette.load(True{}, flags, data))

def frame.valid(valid: Bool, width: U32, height: U32, +flags: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: frame.palette(U32.is_ne((flags .&. 128 : U32), 0), width, height, flags, palette, transparent, data)

def frame(+width: U32, +height: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match data:
    case Con{xl, Con{xh, Con{yl, Con{yh, Con{wl, Con{wh, Con{hl, Con{hh, Con{+flags, rest}}}}}}}}}:
      frame.valid(U32.is_eq((xl .|. xh .|. yl .|. yh : U32), 0) && U32.is_eq((wl .|. (wh << 8n) : U32), width)
        && U32.is_eq((hl .|. (hh << 8n) : U32), height) && U32.is_eq((flags .&. 64 : U32), 0),
        width, height, flags, palette, transparent, rest)
    case _: Fail{BadHeader{}}

def scan.step(header: Header) -> Result<&2, &2, Error, Search>:
  match header:
    case Header{width, height, palette, transparent, Con{33, Con{label, data}}}: extension(label, width, height, palette, transparent, data)
    case Header{width, height, palette, transparent, Con{44, data}}: frame(width, height, palette, transparent, data)
    case _: Fail{BadHeader{}}

def scan(n: Nat, state: Result<&2, &2, Error, Search>) -> Result<&2, &2, Error, Frame>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Found{frame}}: Done{frame}
    case 0n _: Fail{BadHeader{}}
    case 1n+rest Done{Seeking{header}}: scan(rest, scan.step(header))

def scanned(result: Result<&2, &2, Error, Header>) -> Result<&2, &2, Error, Frame>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{width, height, palette, transparent, +data}}:
      scan(byte_count(data, 0n), Done{Seeking{Header{width, height, palette, transparent, data}}})

def transparent(selected: Maybe<&2, U32>, index: U32) -> Bool:
  match selected:
    case None{}: False{}
    case Some{value}: U32.is_eq(value, index)

def color(clear: Bool, result: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match result:
    case None{}: None{}
    case Some{rgba}: Some{Bool.pick(U32, clear, 0, rgba)}

def render.write(index: U32, pixels: Array<U32>, result: Maybe<&2, U32>) -> Result<&1, &1, Error, Array<U32>>:
  match result:
    case None{}: Fail{BadStream{}}
    case Some{rgba}: Done{Array.set(U32, pixels, index, rgba)}

def render.read(index: U32, palette: +List<U32>, selected: Maybe<&2, U32>, result: Array<U32> & U32) -> Result<&1, &1, Error, Array<U32>>:
  (pixels, +value) = result
  render.write(index, pixels, color(transparent(selected, value), List.get(&2, U32, palette, U32.to_nat(value))))

def render(n: Nat, +index: U32, +palette: +List<U32>, +selected: Maybe<&2, U32>, result: Result<&1, &1, Error, Array<U32>>) -> Result<&1, &1, Error, Array<U32>>:
  match n result:
    case _ Fail{error}: Fail{error}
    case 0n _: result
    case 1n+rest Done{pixels}: render(rest, (index + 1 : U32), palette, selected, render.read(index, palette, selected, Array.get(U32, pixels, index)))

def image(width: U32, height: U32, result: Result<&1, &1, Error, Array<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{pixels}: Done{Image{width, height, pixels}}

def decoded(+width: U32, +height: U32, palette: +List<U32>, selected: Maybe<&2, U32>, result: Maybe<Array<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case None{}: Fail{BadStream{}}
    case Some{pixels}: image(width, height, render(U32.to_nat((width * height : U32)), 0, palette, selected, Done{pixels}))

def start(result: Result<&2, &2, Error, Frame>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Frame{+width, +height, palette, selected, minimum, data}}: decoded(width, height, palette, selected, Lzw.decode(minimum, (width * height : U32), data))

def checked(valid: Bool, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(scanned(header(data)))

def decode(+data: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(data, True{}), data)
