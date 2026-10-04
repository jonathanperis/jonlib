# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image Softimage PIC reader.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./qoi.bend as Q

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}
  BadStream{}

type Image is Type:
  Image{width: U32, height: U32, native_channels: U32, pixels: Array<U32>}

type Word is Data:
  Word{value: U32, data: +List<U32>}

def read(n: Nat, value: U32, bytes: +List<U32>) -> Maybe<&2, Word>:
  match n bytes:
    case 0n _: Some{Word{value, bytes}}
    case _ Nil{}: None{}
    case 1n+rest Con{byte, tail}: read(rest, ((value << 8n) .|. byte : U32), tail)

type Words is Data:
  Words{values: +List<U32>, data: +List<U32>}

def words.read(values: +List<U32>, word: Maybe<&2, Word>) -> Maybe<&2, Words>:
  match word:
    case None{}: None{}
    case Some{Word{value, data}}: Some{Words{Con{value, values}, data}}

def words(n: Nat, state: Maybe<&2, Words>) -> Maybe<&2, Words>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Words{values, data}}: Some{Words{List.reverse(&2, U32, values), data}}
    case 1n+rest Some{Words{values, data}}: words(rest, words.read(values, read(2n, 0, data)))

def signature.marker(bytes: +List<U32>) -> Bool:
  match bytes:
    case Con{80, Con{73, Con{67, Con{84, _}}}}: True{}
    case _: False{}

def signature(bytes: +List<U32>) -> Bool:
  match bytes:
    case Con{83, Con{128, Con{246, Con{52, rest}}}}: signature.marker(List.drop(&2, U32, rest, 84n))
    case _: False{}

type Packet is Data:
  Packet{kind: U32, channels: U32, mask: U32}

type Packets is Data:
  Packets{more: Bool, values: +List<Packet>, size: U32, data: +List<U32>}

def packet.valid(valid: Bool, chain: U32, kind: U32, +channels: U32, values: +List<Packet>, size: U32, data: +List<U32>) -> Result<&2, &2, Error, Packets>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}:
      +red = U32.is_ne((channels .&. 128 : U32), 0)
      +green = U32.is_ne((channels .&. 64 : U32), 0)
      +blue = U32.is_ne((channels .&. 32 : U32), 0)
      +alpha = U32.is_ne((channels .&. 16 : U32), 0)
      mask = (Bool.pick(U32, red, 4278190080, 0) .|. Bool.pick(U32, green, 16711680, 0)
        .|. Bool.pick(U32, blue, 65280, 0) .|. Bool.pick(U32, alpha, 255, 0) : U32)
      Done{Packets{U32.is_ne(chain, 0), Con{Packet{kind, channels, mask}, values},
        (size + Bool.to_u32(red) + Bool.to_u32(green) + Bool.to_u32(blue) + Bool.to_u32(alpha) : U32), data}}

def packet(values: +List<Packet>, size: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Packets>:
  match bytes:
    case Con{chain, Con{8, Con{+kind, Con{channels, Con{first, rest}}}}}:
      packet.valid((kind <= 2 : U32), chain, kind, channels, values, size, Con{first, rest})
    case _: Fail{BadHeader{}}

def packets(n: Nat, state: Result<&2, &2, Error, Packets>) -> Result<&2, &2, Error, Packets>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Packets{False{}, values, size, data}}: Done{Packets{False{}, List.reverse(&2, Packet, values), size, data}}
    case 0n _: Fail{BadHeader{}}
    case 1n+rest Done{Packets{True{}, values, size, data}}: packets(rest, packet(values, size, data))

type Header is Data:
  Header{width: U32, height: U32, packets: +List<Packet>, size: U32, data: +List<U32>}

def header.packets(width: U32, height: U32, result: Result<&2, &2, Error, Packets>) -> Result<&2, &2, Error, Header>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Packets{_, values, size, data}}: Done{Header{width, height, values, size, data}}

def header.sized(valid: Bool, width: U32, height: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: header.packets(width, height, packets(10n, Done{Packets{True{}, Nil{}, 0, data}}))

def header.fields(result: Maybe<&2, Words>) -> Result<&2, &2, Error, Header>:
  match result:
    case Some{Words{Con{+width, Con{+height, Con{_, Con{_, Con{_, Con{_, Nil{}}}}}}}, data}}:
      header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, data)
    case _: Fail{BadHeader{}}

def header.valid(valid: Bool, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.fields(words(6n, Some{Words{Nil{}, List.drop(&2, U32, bytes, 92n)}}))

def header(+bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  header.valid(signature(bytes), bytes)

def enough(n: Nat, data: +List<U32>) -> Bool:
  match n data:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

def sample.byte(selected: Bool, shift: Nat, value: U32, data: +List<U32>) -> Maybe<&2, Word>:
  match selected data:
    case False{} _: Some{Word{value, data}}
    case True{} Nil{}: None{}
    case True{} Con{byte, rest}: Some{Word{(value .|. (byte << shift) : U32), rest}}

def sample(n: Nat, +bit: U32, +shift: Nat, +channels: U32, state: Maybe<&2, Word>) -> Maybe<&2, Word>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Word{value, data}}:
      sample(rest, (bit >> 1n : U32), Nat.sub(shift, 8n), channels, sample.byte(U32.is_ne((channels .&. bit : U32), 0), shift, value, data))

type State is Type:
  State{data: +List<U32>, pixels: Array<U32>}

def pixel.merge(index: U32, mask: U32, value: U32, data: +List<U32>, read: Array<U32> & U32) -> State:
  (pixels, old) = read
  State{data, Array.set(U32, pixels, index, ((old .&. (4294967295 - mask)) .|. value : U32))}

def pixel.read(+index: U32, mask: U32, pixels: Array<U32>, result: Maybe<&2, Word>) -> Result<&1, &1, Error, State>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Word{value, data}}: Done{pixel.merge(index, mask, value, data, Array.get(U32, pixels, index))}

def pixels(n: Nat, +index: U32, +channels: U32, +mask: U32, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{State{data, output}}:
      pixels(rest, (index + 1 : U32), channels, mask, pixel.read(index, mask, output, sample(4n, 128, 24n, channels, Some{Word{0, data}})))

type Rle is Type:
  Rle{left: U32, index: U32, data: +List<U32>, pixels: Array<U32>}

def rle.written(left: U32, index: U32, result: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Rle>:
  match result:
    case Fail{error}: Fail{error}
    case Done{State{data, output}}: Done{Rle{left, index, data, output}}

def rle.repeat(n: Nat, +index: U32, +mask: U32, +value: U32, state: State) -> State:
  match n state:
    case 0n _: state
    case 1n+rest State{data, output}:
      rle.repeat(rest, (index + 1 : U32), mask, value, pixel.merge(index, mask, value, data, Array.get(U32, output, index)))

def rle.repeated(+count: U32, left: U32, +index: U32, mask: U32, pixels: Array<U32>, result: Maybe<&2, Word>) -> Result<&1, &1, Error, Rle>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Word{value, data}}:
      rle.written((left - count : U32), (index + count : U32), Done{rle.repeat(U32.to_nat(count), index, mask, value, State{data, pixels})})

def rle.packet(valid: Bool, literal: Bool, +count: U32, left: U32, +index: U32, channels: U32, mask: U32, data: +List<U32>, output: Array<U32>) -> Result<&1, &1, Error, Rle>:
  match valid literal:
    case False{} _: Fail{BadStream{}}
    case True{} True{}: rle.written((left - count : U32), (index + count : U32), pixels(U32.to_nat(count), index, channels, mask, Done{State{data, output}}))
    case True{} False{}: rle.repeated(count, left, index, mask, output, sample(4n, 128, 24n, channels, Some{Word{0, data}}))

def rle.extended(+left: U32, index: U32, channels: U32, mask: U32, output: Array<U32>, result: Maybe<&2, Word>) -> Result<&1, &1, Error, Rle>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Word{+count, data}}: rle.packet((count <= left : U32), False{}, count, left, index, channels, mask, data, output)

def rle.mixed(extended: Bool, +literal: Bool, +code: U32, +left: U32, index: U32, channels: U32, mask: U32, data: +List<U32>, output: Array<U32>) -> Result<&1, &1, Error, Rle>:
  match extended:
    case True{}: rle.extended(left, index, channels, mask, output, read(2n, 0, data))
    case False{}:
      +count = Bool.pick(U32, literal, (code + 1 : U32), (code - 127 : U32))
      rle.packet((count <= left : U32), literal, count, left, index, channels, mask, data, output)

def rle.control(pure: Bool, +code: U32, +left: U32, index: U32, channels: U32, mask: U32, data: +List<U32>, output: Array<U32>) -> Result<&1, &1, Error, Rle>:
  match pure:
    case True{}: rle.packet(True{}, False{}, U32.min(code, left), left, index, channels, mask, data, output)
    case False{}: rle.mixed(U32.is_eq(code, 128), (code < 128 : U32), code, left, index, channels, mask, data, output)

def rle.step(kind: U32, channels: U32, mask: U32, state: Rle) -> Result<&1, &1, Error, Rle>:
  match state:
    case Rle{left, index, Con{code, Con{first, rest}}, output}:
      # Native PIC requires data after the control, including for empty masks.
      rle.control(U32.is_eq(kind, 1), code, left, index, channels, mask, Con{first, rest}, output)
    case _: Fail{Truncated{}}

def rle.run(n: Nat, +kind: U32, +channels: U32, +mask: U32, state: Result<&1, &1, Error, Rle>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Rle{0, _, data, output}}: Done{State{data, output}}
    case 0n _: Fail{Truncated{}}
    case 1n+rest Done{cursor}: rle.run(rest, kind, channels, mask, rle.step(kind, channels, mask, cursor))

def packet.run(+kind: U32, width: U32, index: U32, channels: U32, mask: U32, fuel: Nat, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match kind state:
    case _ Fail{error}: Fail{error}
    case 0 _: pixels(U32.to_nat(width), index, channels, mask, state)
    case _ Done{State{data, output}}: rle.run(fuel, kind, channels, mask, Done{Rle{width, index, data, output}})

def row(packets: +List<Packet>, +index: U32, +width: U32, +fuel: Nat, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match packets state:
    case _ Fail{error}: Fail{error}
    case Nil{} _: state
    case Con{Packet{kind, channels, mask}, rest} _: row(rest, index, width, fuel, packet.run(kind, width, index, channels, mask, fuel, state))

def rows(n: Nat, +y: U32, +width: U32, +packets: +List<Packet>, +fuel: Nat, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest _: rows(rest, (y + 1 : U32), width, packets, fuel, row(packets, (y * width : U32), width, fuel, state))

def image(width: U32, height: U32, native_channels: U32, result: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{State{_, output}}: Done{Image{width, height, native_channels, output}}

def start.valid(valid: Bool, +width: U32, +height: U32, native_channels: U32, packets: +List<Packet>, fuel: Nat, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, native_channels, rows(U32.to_nat(height), 0, width, packets, fuel, Done{State{data, Array.new(U32, depth, 4294967295)}}))

def byte_count(data: +List<U32>, count: Nat) -> Nat:
  match data:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, 1n+count)

def raw(packets: +List<Packet>) -> Bool:
  match packets:
    case Nil{}: True{}
    case Con{Packet{kind, _, _}, rest}: U32.is_eq(kind, 0) && raw(rest)

def start.kind(plain: Bool, +width: U32, +height: U32, native_channels: U32, packets: +List<Packet>, size: U32, +data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match plain:
    case True{}: start.valid(enough(U32.to_nat((width * height * size : U32)), data), width, height, native_channels, packets, 0n, data)
    case False{}: start.valid(True{}, width, height, native_channels, packets, byte_count(data, 0n), data)

# Native output components are structural: alpha in ANY validated descriptor
# selects RGBA, even when later RGB packets overwrite colors or alpha is opaque.
# The separate size accumulator remains a selected-input-sample count.
def native.mask(packets: +List<Packet>, mask: U32) -> U32:
  match packets:
    case Nil{}: mask
    case Con{Packet{_, channels, _}, rest}: native.mask(rest, (mask .|. channels : U32))

def native.channels(packets: +List<Packet>) -> U32:
  Bool.pick(U32, U32.is_ne((native.mask(packets, 0) .&. 16 : U32), 0), 4, 3)

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{width, height, +packets, size, data}}:
      start.kind(raw(packets), width, height, native.channels(packets), packets, size, data)

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(bytes, True{}), bytes)
