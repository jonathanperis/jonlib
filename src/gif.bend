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
  Header{width: U32, height: U32, palette: +List<U32>, background: U32, transparent: Maybe<&2, U32>, data: +List<U32>}

def header.palette(width: U32, height: U32, background: U32, result: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Header>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Palette{colors, data}}: Done{Header{width, height, colors, background, None{}, data}}

def header.sized(valid: Bool, width: U32, height: U32, +flags: U32, background: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: header.palette(width, height, background, palette.load(U32.is_ne((flags .&. 128 : U32), 0), flags, data))

def header.fields(data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match data:
    case Con{wl, Con{wh, Con{hl, Con{hh, Con{flags, Con{background, Con{_, rest}}}}}}}:
      +width = (wl .|. (wh << 8n) : U32)
      +height = (hl .|. (hh << 8n) : U32)
      header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, flags, background, rest)
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

type Region is Data:
  Region{x: U32, y: U32, width: U32, height: U32, interlaced: Bool}

type Frame is Data:
  Frame{width: U32, height: U32, region: Region, background: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, minimum: U32, data: +List<U32>}

type Search is Data:
  Seeking{header: Header}
  Found{frame: Frame}

def extension.data(width: U32, height: U32, palette: +List<U32>, background: U32, transparent: Maybe<&2, U32>, result: Maybe<&2, Blocks>) -> Result<&2, &2, Error, Search>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Blocks{_, data}}: Done{Seeking{Header{width, height, palette, background, transparent, data}}}

def extension.control(width: U32, height: U32, palette: +List<U32>, background: U32, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match data:
    case Con{4, Con{flags, Con{_, Con{_, Con{index, rest}}}}}:
      transparent = Bool.pick(Maybe<&2, U32>, U32.is_ne((flags .&. 1 : U32), 0), Some{index}, None{})
      extension.data(width, height, palette, background, transparent, collect(rest))
    case _: Fail{BadHeader{}}

def extension(label: U32, width: U32, height: U32, palette: +List<U32>, background: U32, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match label:
    case 249: extension.control(width, height, palette, background, data)
    case _: extension.data(width, height, palette, background, transparent, collect(data))

def frame.blocks(valid: Bool, width: U32, height: U32, region: Region, background: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, minimum: U32, result: Maybe<&2, Blocks>) -> Result<&2, &2, Error, Search>:
  match valid result:
    case False{} _: Fail{BadHeader{}}
    case True{} None{}: Fail{Truncated{}}
    case True{} Some{Blocks{bytes, _}}: Done{Found{Frame{width, height, region, background, palette, transparent, minimum, bytes}}}

def frame.data(width: U32, height: U32, region: Region, background: U32, transparent: Maybe<&2, U32>, result: Result<&2, &2, Error, Palette>) -> Result<&2, &2, Error, Search>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Palette{Nil{}, _}}: Fail{BadHeader{}}
    case Done{Palette{colors, Con{+minimum, data}}}:
      frame.blocks(((minimum >= 2) && (minimum <= 8) : U32), width, height, region, background, colors, transparent, minimum, collect(data))
    case _: Fail{BadHeader{}}

def frame.palette(local: Bool, width: U32, height: U32, region: Region, background: U32, flags: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match local:
    case False{}: frame.data(width, height, region, background, transparent, Done{Palette{palette, data}})
    case True{}: frame.data(width, height, region, background, transparent, palette.load(True{}, flags, data))

def background.color(result: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match result:
    case None{}: None{}
    case Some{+color}:
      # Native first-frame background memcpy retains the palette's BGR byte order.
      Some{(((color .&. 65280) << 16n) .|. (color .&. 16711680) .|. ((color >> 16n) .&. 65280) .|. 255 : U32)}

def background(used: Bool, index: U32, palette: +List<U32>) -> Maybe<&2, U32>:
  match used:
    case False{}: Some{0}
    case True{}: background.color(List.get(&2, U32, palette, U32.to_nat(index)))

def frame.valid(valid: Bool, width: U32, height: U32, region: Region, +flags: U32, palette: +List<U32>, transparent: Maybe<&2, U32>, data: +List<U32>, background: Maybe<&2, U32>) -> Result<&2, &2, Error, Search>:
  match valid background:
    case True{} Some{color}: frame.palette(U32.is_ne((flags .&. 128 : U32), 0), width, height, region, color, flags, palette, transparent, data)
    case _ _: Fail{BadHeader{}}

def frame(+width: U32, +height: U32, +palette: +List<U32>, +bgindex: U32, transparent: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Search>:
  match data:
    case Con{xl, Con{xh, Con{yl, Con{yh, Con{wl, Con{wh, Con{hl, Con{hh, Con{+flags, rest}}}}}}}}}:
      +x = (xl .|. (xh << 8n) : U32)
      +y = (yl .|. (yh << 8n) : U32)
      +w = (wl .|. (wh << 8n) : U32)
      +h = (hl .|. (hh << 8n) : U32)
      needed = U32.is_ne(bgindex, 0) && ((w * h < width * height) : U32)
      frame.valid(((w > 0) && (h > 0) && (x + w <= width) && (y + h <= height) : U32), width, height,
        Region{x, y, w, h, U32.is_ne((flags .&. 64 : U32), 0)}, flags, palette, transparent, rest, background(needed, bgindex, palette))
    case _: Fail{BadHeader{}}

def scan.step(header: Header) -> Result<&2, &2, Error, Search>:
  match header:
    case Header{width, height, palette, background, transparent, Con{33, Con{label, data}}}: extension(label, width, height, palette, background, transparent, data)
    case Header{width, height, palette, background, transparent, Con{44, data}}: frame(width, height, palette, background, transparent, data)
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
    case Done{Header{width, height, palette, background, transparent, +data}}:
      scan(byte_count(data, 0n), Done{Seeking{Header{width, height, palette, background, transparent, data}}})

def transparent(selected: Maybe<&2, U32>, index: U32) -> Bool:
  match selected:
    case None{}: False{}
    case Some{value}: U32.is_eq(value, index)

def color(clear: Bool, result: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match result:
    case None{}: None{}
    case Some{rgba}: Some{Bool.pick(U32, clear, 0, rgba)}

type Rendering is Type:
  Rendering{indices: Array<U32>, pixels: Array<U32>}

def row.selected(first: Bool, second: Bool, third: Bool, row: U32, one: U32, two: U32, three: U32) -> U32:
  match first second third:
    case True{} _ _: (row * 8 : U32)
    case False{} True{} _: (4 + (row - one) * 8 : U32)
    case False{} False{} True{}: (2 + (row - two) * 4 : U32)
    case False{} False{} False{}: (1 + (row - three) * 2 : U32)

def row.index(interlaced: Bool, +row: U32, +height: U32) -> U32:
  match interlaced:
    case False{}: row
    case True{}:
      +one = ((height + 7) / 8 : U32)
      +two = (one + (height + 3) / 8 : U32)
      +three = (two + (height + 1) / 4 : U32)
      row.selected((row < one : U32), (row < two : U32), (row < three : U32), row, one, two, three)

def position(+index: U32, canvas_width: U32, region: Region) -> U32:
  Region{x, y, +width, height, interlaced} = region
  ((y + row.index(interlaced, (index / width : U32), height)) * canvas_width + x + index % width : U32)

def render.write(index: U32, indices: Array<U32>, pixels: Array<U32>, result: Maybe<&2, U32>) -> Result<&1, &1, Error, Rendering>:
  match result:
    case None{}: Fail{BadStream{}}
    case Some{rgba}: Done{Rendering{indices, Array.set(U32, pixels, index, rgba)}}

def render.read(index: U32, palette: +List<U32>, selected: Maybe<&2, U32>, pixels: Array<U32>, result: Array<U32> & U32) -> Result<&1, &1, Error, Rendering>:
  (indices, +value) = result
  render.write(index, indices, pixels, color(transparent(selected, value), List.get(&2, U32, palette, U32.to_nat(value))))

def render(n: Nat, +index: U32, +width: U32, +region: Region, +palette: +List<U32>, +selected: Maybe<&2, U32>, result: Result<&1, &1, Error, Rendering>) -> Result<&1, &1, Error, Rendering>:
  match n result:
    case _ Fail{error}: Fail{error}
    case 0n _: result
    case 1n+rest Done{Rendering{indices, pixels}}:
      render(rest, (index + 1 : U32), width, region, palette, selected,
        render.read(position(index, width, region), palette, selected, pixels, Array.get(U32, indices, index)))

def image(width: U32, height: U32, result: Result<&1, &1, Error, Rendering>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Rendering{_, pixels}}: Done{Image{width, height, pixels}}

def decoded(+width: U32, +height: U32, region: Region, background: U32, palette: +List<U32>, selected: Maybe<&2, U32>, result: Maybe<Array<U32>>) -> Result<&1, &1, Error, Image>:
  match region result:
    case _ None{}: Fail{BadStream{}}
    case Region{x, y, +w, +h, interlaced} Some{indices}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, render(U32.to_nat((w * h : U32)), 0, width, Region{x, y, w, h, interlaced}, palette, selected,
        Done{Rendering{indices, Array.new(U32, depth, background)}}))

def start(result: Result<&2, &2, Error, Frame>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Frame{width, height, Region{x, y, +w, +h, interlaced}, background, palette, selected, minimum, data}}:
      decoded(width, height, Region{x, y, w, h, interlaced}, background, palette, selected, Lzw.decode(minimum, (w * h : U32), data))

def checked(valid: Bool, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(scanned(header(data)))

def decode(+data: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(data, True{}), data)
