# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image binary PNM reader.
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

def space(+byte: U32) -> Bool:
  U32.is_eq(byte, 32) || ((byte >= 9) && (byte <= 13) : U32)

def skip(bytes: +List<U32>, +comment: Bool, stopped: Maybe<&2, U32>) -> +List<U32>:
  match bytes stopped:
    case _ Some{byte}: Con{byte, bytes}
    case Nil{} None{}: Nil{}
    case Con{+byte, rest} None{}:
      +mark = U32.is_eq(byte, 35)
      next_comment = (comment || mark) && Bool.not(U32.is_eq(byte, 10) || U32.is_eq(byte, 13))
      stop = Bool.pick(Maybe<&2, U32>, Bool.not(comment || mark || space(byte)), Some{byte}, None{})
      skip(rest, next_comment, stop)

type Token is Data:
  Token{value: U32, delimiter: U32, rest: +List<U32>}

def digits(bytes: +List<U32>, +value: U32, seen: Bool, valid: Bool, stopped: Maybe<&2, U32>) -> Result<&2, &2, Error, Token>:
  match bytes valid stopped:
    case _ False{} _: Fail{BadHeader{}}
    case _ True{} Some{delimiter}: Done{Token{value, delimiter, bytes}}
    case Nil{} True{} None{}: Fail{BadHeader{}}
    case Con{+byte, rest} True{} None{}:
      +digit = ((byte >= 48) && (byte <= 57) : U32)
      bound = (value < 214748364 : U32) || (U32.is_eq(value, 214748364) && (byte <= 55 : U32))
      digits(rest, Bool.pick(U32, digit, (value * 10 + byte - 48 : U32), value), True{},
        Bool.pick(Bool, digit, bound, seen), Bool.pick(Maybe<&2, U32>, digit, None{}, Some{byte}))

def number(bytes: +List<U32>) -> Result<&2, &2, Error, Token>:
  digits(skip(bytes, False{}, None{}), 0, False{}, True{}, None{})

type Header is Data:
  Header{width: U32, height: U32, channels: U32, data: +List<U32>}

def header.sized(valid: Bool, width: U32, height: U32, channels: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: Done{Header{width, height, channels, data}}

def header.valid(valid: Bool, +width: U32, +height: U32, channels: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, channels, data)

def header.maximum(width: U32, height: U32, channels: U32, token: Result<&2, &2, Error, Token>) -> Result<&2, &2, Error, Header>:
  match token:
    case Fail{error}: Fail{error}
    case Done{Token{+value, delimiter, rest}}:
      # The native reader has already consumed exactly one byte after maxval.
      header.valid(((value > 0) && (value <= 255) : U32) && space(delimiter), width, height, channels, rest)

def header.height(width: U32, channels: U32, token: Result<&2, &2, Error, Token>) -> Result<&2, &2, Error, Header>:
  match token:
    case Fail{error}: Fail{error}
    case Done{Token{height, delimiter, rest}}: header.maximum(width, height, channels, number(Con{delimiter, rest}))

def header.width(channels: U32, token: Result<&2, &2, Error, Token>) -> Result<&2, &2, Error, Header>:
  match token:
    case Fail{error}: Fail{error}
    case Done{Token{width, delimiter, rest}}: header.height(width, channels, number(Con{delimiter, rest}))

def header(bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{80, Con{53, rest}}: header.width(1, number(rest))
    case Con{80, Con{54, rest}}: header.width(3, number(rest))
    case _: Fail{BadHeader{}}

def enough(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: enough(rest, tail)

type State is Type:
  State{data: +List<U32>, pixels: Array<U32>}

def rgba(gray: Bool, +word: U32) -> U32:
  match gray:
    case True{}: ((word << 24n) .|. (word << 16n) .|. (word << 8n) .|. 255 : U32)
    case False{}: (((word .&. 255) << 24n) .|. (((word >> 8n) .&. 255) << 16n) .|. ((word >> 16n) << 8n) .|. 255 : U32)

def write(index: U32, gray: Bool, pixels: Array<U32>, result: Maybe<&2, F.Word>) -> Result<&1, &1, Error, State>:
  match result:
    case None{}: Fail{Truncated{}}
    case Some{F.Word{value, rest}}: Done{State{rest, Array.set(U32, pixels, index, rgba(gray, value))}}

def pixels(n: Nat, +index: U32, +channels: U32, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Array<U32>>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{State{_, output}}: Done{output}
    case 1n+rest Done{State{data, output}}:
      pixels(rest, (index + 1 : U32), channels, write(index, U32.is_eq(channels, 1), output, F.read_word(U32.to_nat(channels), 0n, 0, data)))

def image(width: U32, height: U32, result: Result<&1, &1, Error, Array<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{output}: Done{Image{width, height, output}}

def start.valid(valid: Bool, +width: U32, +height: U32, channels: U32, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{Truncated{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, pixels(U32.to_nat(count), 0, channels, Done{State{data, Array.new(U32, depth, 0)}}))

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, +channels, +data}}:
      start.valid(enough(U32.to_nat((width * height * channels : U32)), data), width, height, channels, data)

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header(bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(bytes, True{}), bytes)
