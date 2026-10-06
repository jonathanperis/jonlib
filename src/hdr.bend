# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned stb_image Radiance RGBE loading.
# Upstream HDR reader by Nicolas Schulz; MIT notice in LICENSES/stb-image.txt.
import Base
import ./codec.bend as C
import ./../jonmath.bend as M

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<M.Vector3>}

def float_bits(value: U32) -> F32:
  U32{word} = value
  F32{word}

def sample.scaled(normal: Bool, +channel: U32, +exponent: U32, +top: U32) -> F32:
  match normal:
    case False{}: float_bits((channel << U32.to_nat((exponent + 13 : U32)) : U32))
    case True{}:
      bits = (((exponent + top - 9) << 23n) .|. ((channel - (1 << U32.to_nat(top))) << U32.to_nat((23 - top : U32))) : U32)
      float_bits(bits)

def sample(+channel: U32, +exponent: U32) -> F32:
  match channel exponent:
    case 0 _: 0.0
    case _ 0: 0.0
    case _ _:
      # RGBE multiplication is exact; construct bits to retain GPU subnormals.
      +top = U32.from_nat(U32.log2(channel))
      sample.scaled((exponent + top > 9 : U32), channel, exponent, top)

type Line is Data:
  Line{text: String, data: +List<U32>}

def line(n: Nat, data: +List<U32>, values: +List<Char>) -> Maybe<&2, Line>:
  match n data:
    case _ Con{10, rest}: Some{Line{String.from_list(List.reverse(&2, Char, values)), rest}}
    case 0n _: None{}
    case _ Nil{}: None{}
    case _ Con{0, _}: None{}
    case 1n+rest Con{byte, tail}: line(rest, tail, Con{Char.from_u32(byte), values})

type Header is Data:
  Header{width: U32, height: U32, data: +List<U32>}

def dimensions.sized(valid: Bool, width: U32, height: U32, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid:
    case False{}: Fail{C.BadSize{}}
    case True{}: Done{Header{width, height, data}}

def dimensions.parsed(valid: Bool, width: Maybe<&2, U32>, height: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid width height:
    case True{} Some{+w} Some{+h}: dimensions.sized(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, data)
    case _ _ _: Fail{C.BadHeader{}}

def dimensions.tokens(tokens: +List<String>, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match tokens:
    case Con{y, Con{height, Con{x, Con{width, Nil{}}}}}:
      dimensions.parsed(String.eq(y, "-Y") && String.eq(x, "+X"), U32.read(width), U32.read(height), data)
    case _: Fail{C.BadHeader{}}

def nonempty(tokens: +List<String>, values: +List<String>) -> +List<String>:
  match tokens:
    case Nil{}: List.reverse(&2, String, values)
    case Con{SNil{}, rest}: nonempty(rest, values)
    case Con{text, rest}: nonempty(rest, Con{text, values})

def dimensions.valid(valid: Bool, text: String, data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid:
    case False{}: Fail{C.BadHeader{}}
    case True{}: dimensions.tokens(nonempty(String.split(text, ' '), Nil{}), data)

def dimensions(result: Maybe<&2, Line>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case None{}: Fail{C.BadHeader{}}
    case Some{Line{+text, data}}: dimensions.valid(String.starts_with(text, "-Y "), text, data)

type Parsing is Data:
  Parsing{found: Bool, ended: Bool, data: +List<U32>}

def header.line(found: Bool, result: Maybe<&2, Line>) -> Maybe<&2, Parsing>:
  match result:
    case None{}: None{}
    case Some{Line{+text, data}}:
      Some{Parsing{found || String.eq(text, "FORMAT=32-bit_rle_rgbe"), String.eq(text, ""), data}}

def header.lines(n: Nat, state: Maybe<&2, Parsing>) -> Result<&2, &2, C.Error, Header>:
  match n state:
    case _ None{}: Fail{C.BadHeader{}}
    case _ Some{Parsing{True{}, True{}, data}}: dimensions(line(1023n, data, Nil{}))
    case _ Some{Parsing{False{}, True{}, _}}: Fail{C.BadHeader{}}
    case 0n _: Fail{C.BadHeader{}}
    case 1n+rest Some{Parsing{found, False{}, data}}: header.lines(rest, header.line(found, line(1023n, data, Nil{})))

def header.signature(valid: Bool, +data: +List<U32>) -> Result<&2, &2, C.Error, Header>:
  match valid:
    case False{}: Fail{C.BadHeader{}}
    case True{}: header.lines(C.byte_count(data, 0n), Some{Parsing{False{}, False{}, data}})

def header(result: Maybe<&2, Line>) -> Result<&2, &2, C.Error, Header>:
  match result:
    case None{}: Fail{C.BadHeader{}}
    case Some{Line{+text, data}}: header.signature(String.eq(text, "#?RADIANCE") || String.eq(text, "#?RGBE"), data)

def rle_marker(data: +List<U32>) -> Bool:
  match data:
    case Con{2, Con{2, Con{high, _}}}: (high < 128 : U32)
    case _: False{}

def enough(n: Nat, data: +List<U32>) -> Bool:
  match n data:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

def pixels(n: Nat, +index: U32, data: +List<U32>, output: Array<M.Vector3>) -> Result<&1, &1, C.Error, Array<M.Vector3>>:
  match n data:
    case 0n _: Done{output}
    case 1n+rest Con{r, Con{g, Con{b, Con{+e, tail}}}}:
      pixels(rest, (index + 1 : U32), tail, Array.set(M.Vector3, output, index, M.Vector3{sample(r, e), sample(g, e), sample(b, e)}))
    case _ _: Fail{C.Truncated{}}

def image(width: U32, height: U32, result: Result<&1, &1, C.Error, Array<M.Vector3>>) -> Result<&1, &1, C.Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{pixels}: Done{Image{width, height, pixels}}

def start.raw(complete: Bool, +width: U32, +height: U32, data: +List<U32>) -> Result<&1, &1, C.Error, Image>:
  match complete:
    case False{}: Fail{C.Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, pixels(U32.to_nat(count), 0, data, Array.new(M.Vector3, depth, M.Vector3{0.0, 0.0, 0.0})))

type Row is Type:
  Row{data: +List<U32>, packed: Array<U32>}

def plane.write(index: U32, +shift: Nat, value: U32, data: +List<U32>, read: Array<U32> & U32) -> Row:
  (packed, old) = read
  pixel = ((old .&. (4294967295 - (255 << shift))) .|. (value << shift) : U32)
  Row{data, Array.set(U32, packed, index, pixel)}

def plane.copy(n: Nat, +index: U32, +shift: Nat, state: Result<&1, &1, C.Error, Row>) -> Result<&1, &1, C.Error, Row>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{Row{Con{value, tail}, packed}}:
      plane.copy(rest, (index + 1 : U32), shift, Done{plane.write(index, shift, value, tail, Array.get(U32, packed, index))})
    case _ _: Fail{C.Truncated{}}

def plane.repeat(n: Nat, +index: U32, +shift: Nat, +value: U32, row: Row) -> Row:
  match n row:
    case 0n _: row
    case 1n+rest Row{data, packed}:
      plane.repeat(rest, (index + 1 : U32), shift, value, plane.write(index, shift, value, data, Array.get(U32, packed, index)))

type Cursor is Type:
  Cursor{left: U32, index: U32, row: Row}

def plane.written(left: U32, index: U32, result: Result<&1, &1, C.Error, Row>) -> Result<&1, &1, C.Error, Cursor>:
  match result:
    case Fail{error}: Fail{error}
    case Done{row}: Done{Cursor{left, index, row}}

def plane.repeated(+count: U32, left: U32, +index: U32, shift: Nat, data: +List<U32>, packed: Array<U32>) -> Result<&1, &1, C.Error, Cursor>:
  match data:
    case Nil{}: Fail{C.Truncated{}}
    case Con{value, rest}:
      plane.written((left - count : U32), (index + count : U32), Done{plane.repeat(U32.to_nat(count), index, shift, value, Row{rest, packed})})

def plane.packet(valid: Bool, repeat: Bool, +count: U32, left: U32, +index: U32, shift: Nat, data: +List<U32>, packed: Array<U32>) -> Result<&1, &1, C.Error, Cursor>:
  match valid repeat:
    case False{} _: Fail{C.BadStream{}}
    case True{} True{}: plane.repeated(count, left, index, shift, data, packed)
    case True{} False{}:
      plane.written((left - count : U32), (index + count : U32), plane.copy(U32.to_nat(count), index, shift, Done{Row{data, packed}}))

def plane.step(shift: Nat, cursor: Cursor) -> Result<&1, &1, C.Error, Cursor>:
  match cursor:
    case Cursor{_, _, Row{Nil{}, _}}: Fail{C.Truncated{}}
    case Cursor{+left, index, Row{Con{+code, rest}, packed}}:
      +repeat = (code > 128 : U32)
      +count = Bool.pick(U32, repeat, (code - 128 : U32), code)
      plane.packet(((count > 0) && (count <= left) : U32), repeat, count, left, index, shift, rest, packed)

def plane.run(n: Nat, +shift: Nat, state: Result<&1, &1, C.Error, Cursor>) -> Result<&1, &1, C.Error, Row>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Cursor{0, _, row}}: Done{row}
    case 0n _: Fail{C.BadStream{}}
    case 1n+rest Done{cursor}: plane.run(rest, shift, plane.step(shift, cursor))

def planes(n: Nat, +width: U32, +shift: Nat, state: Result<&1, &1, C.Error, Row>) -> Result<&1, &1, C.Error, Row>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{row}: planes(rest, width, Nat.sub(shift, 8n), plane.run(U32.to_nat(width), shift, Done{Cursor{width, 0, row}}))

def scanline.valid(valid: Bool, width: U32, data: +List<U32>, packed: Array<U32>) -> Result<&1, &1, C.Error, Row>:
  match valid:
    case False{}: Fail{C.BadStream{}}
    case True{}: planes(4n, width, 24n, Done{Row{data, packed}})

def scanline(+width: U32, data: +List<U32>, packed: Array<U32>) -> Result<&1, &1, C.Error, Row>:
  match data:
    case Con{2, Con{2, Con{high, Con{low, rest}}}}:
      scanline.valid(U32.is_eq(((high << 8n) .|. low : U32), width), width, rest, packed)
    case _: Fail{C.Truncated{}}

type Converting is Type:
  Converting{packed: Array<U32>, pixels: Array<M.Vector3>}

def convert.read(at: U32, pixels: Array<M.Vector3>, result: Array<U32> & U32) -> Converting:
  (packed, +word) = result
  +exponent = (word .&. 255 : U32)
  color = {M.Vector3{sample((word >> 24n : U32), exponent), sample(((word >> 16n) .&. 255 : U32), exponent), sample(((word >> 8n) .&. 255 : U32), exponent)} : M.Vector3}
  Converting{packed, Array.set(M.Vector3, pixels, at, color)}

def convert(n: Nat, +index: U32, +at: U32, state: Converting) -> Converting:
  match n state:
    case 0n _: state
    case 1n+rest Converting{packed, pixels}: convert(rest, (index + 1 : U32), (at + 1 : U32), convert.read(at, pixels, Array.get(U32, packed, index)))

type Raster is Type:
  Raster{data: +List<U32>, packed: Array<U32>, pixels: Array<M.Vector3>}
  Replaced{pixels: Array<M.Vector3>}

def row.converted(data: +List<U32>, result: Converting) -> Raster:
  Converting{packed, pixels} = result
  Raster{data, packed, pixels}

def row.decoded(+width: U32, y: U32, pixels: Array<M.Vector3>, result: Result<&1, &1, C.Error, Row>) -> Result<&1, &1, C.Error, Raster>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Row{data, packed}}: Done{row.converted(data, convert(U32.to_nat(width), 0, (y * width : U32), Converting{packed, pixels}))}

def row.replaced(result: Result<&1, &1, C.Error, Array<M.Vector3>>) -> Result<&1, &1, C.Error, Raster>:
  match result:
    case Fail{error}: Fail{error}
    case Done{output}: Done{Replaced{output}}

def row.raw(complete: Bool, width: U32, height: U32, data: +List<U32>, output: Array<M.Vector3>) -> Result<&1, &1, C.Error, Raster>:
  match complete:
    case False{}: Fail{C.Truncated{}}
    case True{}:
      # Native later-row fallback resets i/j and rewrites the entire canvas.
      row.replaced(pixels(U32.to_nat((width * height : U32)), 0, data, output))

def row.selected(encoded: Bool, +width: U32, +height: U32, y: U32, +data: +List<U32>, packed: Array<U32>, output: Array<M.Vector3>) -> Result<&1, &1, C.Error, Raster>:
  match encoded:
    case True{}: row.decoded(width, y, output, scanline(width, data, packed))
    case False{}: row.raw(enough(U32.to_nat((width * height * 4 : U32)), data), width, height, data, output)

def rows(n: Nat, +y: U32, +width: U32, +height: U32, state: Result<&1, &1, C.Error, Raster>) -> Result<&1, &1, C.Error, Array<M.Vector3>>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Replaced{pixels}}: Done{pixels}
    case 0n Done{Raster{_, _, pixels}}: Done{pixels}
    case 1n+rest Done{Raster{+data, packed, output}}:
      rows(rest, (y + 1 : U32), width, height, row.selected(rle_marker(data), width, height, y, data, packed, output))

def start.kind(raw: Bool, +width: U32, +height: U32, +data: +List<U32>) -> Result<&1, &1, C.Error, Image>:
  match raw:
    case True{}: start.raw(enough(U32.to_nat((width * height * 4 : U32)), data), width, height, data)
    case False{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      row_depth = {1n+U32.log2((width - 1 : U32)) : Nat}
      image(width, height, rows(U32.to_nat(height), 0, width, height,
        Done{Raster{data, Array.new(U32, row_depth, 0), Array.new(M.Vector3, depth, M.Vector3{0.0, 0.0, 0.0})}}))

def start(result: Result<&2, &2, C.Error, Header>) -> Result<&1, &1, C.Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, +data}}:
      start.kind((width < 8 : U32) || Bool.not(rle_marker(data)), width, height, data)

def checked(valid: Bool, data: +List<U32>) -> Result<&1, &1, C.Error, Image>:
  match valid:
    case False{}: Fail{C.BadByte{}}
    case True{}: start(header(line(1023n, data, Nil{})))

def decode(+data: +List<U32>) -> Result<&1, &1, C.Error, Image>:
  checked(C.valid_bytes(data, True{}), data)
