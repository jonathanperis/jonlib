# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image opaque raw PSD reader.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./qoi.bend as Q

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

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

type Header is Data:
  Header{width: U32, height: U32, channels: U32, wide: Bool, data: +List<U32>}

def header.sized(valid: Bool, width: U32, height: U32, channels: U32, wide: Bool, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: Done{Header{width, height, channels, wide, data}}

def header.checked(valid: Bool, +width: U32, +height: U32, channels: U32, wide: Bool, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, channels, wide, data)

def header.fields(result: Maybe<&2, Words>) -> Result<&2, &2, Error, Header>:
  match result:
    case Some{Words{Con{+channels, Con{hh, Con{hl, Con{wh, Con{wl, Con{+bits, Con{color, Nil{}}}}}}}}, data}}:
      header.checked((channels <= 3 : U32) && (U32.is_eq(bits, 8) || U32.is_eq(bits, 16)) && U32.is_eq(color, 3),
        ((wh << 16n) .|. wl : U32), ((hh << 16n) .|. hl : U32), channels, U32.is_eq(bits, 16), data)
    case _: Fail{BadHeader{}}

def header(bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{56, Con{66, Con{80, Con{83, Con{0, Con{1, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, rest}}}}}}}}}}}}:
      header.fields(words(7n, Some{Words{Nil{}, rest}}))
    case _: Fail{BadHeader{}}

def skip(n: Nat, bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  match n bytes:
    case 0n _: Some{bytes}
    case _ Nil{}: None{}
    case 1n+rest Con{_, tail}: skip(rest, tail)

def section.data(result: Maybe<&2, +List<U32>>) -> Result<&2, &2, Error, +List<U32>>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{data}: Done{data}

def section(word: Maybe<&2, Word>) -> Result<&2, &2, Error, +List<U32>>:
  match word:
    case None{}: Fail{BadHeader{}}
    case Some{Word{size, data}}: section.data(skip(U32.to_nat(size), data))

def sections(n: Nat, state: Result<&2, &2, Error, +List<U32>>) -> Result<&2, &2, Error, +List<U32>>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{data}: sections(rest, section(read(4n, 0, data)))

def enough(n: Nat, data: +List<U32>) -> Bool:
  match n data:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

type State is Type:
  State{data: +List<U32>, pixels: Array<U32>}

def pixel.merge(index: U32, shift: Nat, value: U32, data: +List<U32>, result: Array<U32> & U32) -> State:
  (pixels, old) = result
  State{data, Array.set(U32, pixels, index, (old .|. (value << shift) : U32))}

def pixel.read(+index: U32, shift: Nat, wide: Bool, pixels: Array<U32>, result: Maybe<&2, Word>) -> Result<&1, &1, Error, State>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{Word{+value, data}}:
      Done{pixel.merge(index, shift, Bool.pick(U32, wide, (value >> 8n : U32), value), data, Array.get(U32, pixels, index))}

def pixels(n: Nat, +index: U32, +shift: Nat, +wide: Bool, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest Done{State{data, output}}:
      pixels(rest, (index + 1 : U32), shift, wide, pixel.read(index, shift, wide, output, read(Bool.pick(Nat, wide, 2n, 1n), 0, data)))

def channels(n: Nat, +shift: Nat, +count: Nat, +wide: Bool, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n _: state
    case 1n+rest _: channels(rest, Nat.sub(shift, 8n), count, wide, pixels(count, 0, shift, wide, state))

def image(width: U32, height: U32, result: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{State{_, output}}: Done{Image{width, height, output}}

def start.valid(valid: Bool, +width: U32, +height: U32, amount: U32, wide: Bool, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, channels(U32.to_nat(amount), 24n, U32.to_nat(count), wide, Done{State{data, Array.new(U32, depth, 255)}}))

def compression.valid(valid: Bool, +width: U32, +height: U32, +amount: U32, +wide: Bool, +data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: start.valid(enough(U32.to_nat((width * height * amount * Bool.pick(U32, wide, 2, 1) : U32)), data), width, height, amount, wide, data)

def compression(width: U32, height: U32, amount: U32, wide: Bool, word: Maybe<&2, Word>) -> Result<&1, &1, Error, Image>:
  match word:
    case None{}: Fail{BadHeader{}}
    case Some{Word{code, data}}: compression.valid(U32.is_eq(code, 0), width, height, amount, wide, data)

def prepared(width: U32, height: U32, amount: U32, wide: Bool, result: Result<&2, &2, Error, +List<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{data}: compression(width, height, amount, wide, read(2n, 0, data))

def prepare(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{width, height, amount, wide, data}}: prepared(width, height, amount, wide, sections(3n, Done{data}))

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: prepare(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(bytes, True{}), bytes)
