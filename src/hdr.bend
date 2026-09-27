# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned stb_image Radiance RGBE loading.
# Upstream HDR reader by Nicolas Schulz; MIT notice in LICENSES/stb-image.txt.
import Base
import ./../jonmath.bend as M
import ./qoi.bend as Q

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}

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

def dimensions.sized(valid: Bool, width: U32, height: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: Done{Header{width, height, data}}

def dimensions.parsed(valid: Bool, width: Maybe<&2, U32>, height: Maybe<&2, U32>, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid width height:
    case True{} Some{+w} Some{+h}: dimensions.sized(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, data)
    case _ _ _: Fail{BadHeader{}}

def dimensions.tokens(tokens: +List<String>, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match tokens:
    case Con{y, Con{height, Con{x, Con{width, Nil{}}}}}:
      dimensions.parsed(String.eq(y, "-Y") && String.eq(x, "+X"), U32.read(width), U32.read(height), data)
    case _: Fail{BadHeader{}}

def nonempty(tokens: +List<String>, values: +List<String>) -> +List<String>:
  match tokens:
    case Nil{}: List.reverse(&2, String, values)
    case Con{SNil{}, rest}: nonempty(rest, values)
    case Con{text, rest}: nonempty(rest, Con{text, values})

def dimensions.valid(valid: Bool, text: String, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: dimensions.tokens(nonempty(String.split(text, ' '), Nil{}), data)

def dimensions(result: Maybe<&2, Line>) -> Result<&2, &2, Error, Header>:
  match result:
    case None{}: Fail{BadHeader{}}
    case Some{Line{+text, data}}: dimensions.valid(String.starts_with(text, "-Y "), text, data)

type Parsing is Data:
  Parsing{found: Bool, ended: Bool, data: +List<U32>}

def header.line(found: Bool, result: Maybe<&2, Line>) -> Maybe<&2, Parsing>:
  match result:
    case None{}: None{}
    case Some{Line{+text, data}}:
      Some{Parsing{found || String.eq(text, "FORMAT=32-bit_rle_rgbe"), String.eq(text, ""), data}}

def header.lines(n: Nat, state: Maybe<&2, Parsing>) -> Result<&2, &2, Error, Header>:
  match n state:
    case _ None{}: Fail{BadHeader{}}
    case _ Some{Parsing{True{}, True{}, data}}: dimensions(line(1023n, data, Nil{}))
    case _ Some{Parsing{False{}, True{}, _}}: Fail{BadHeader{}}
    case 0n _: Fail{BadHeader{}}
    case 1n+rest Some{Parsing{found, False{}, data}}: header.lines(rest, header.line(found, line(1023n, data, Nil{})))

def byte_count(data: +List<U32>, count: Nat) -> Nat:
  match data:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, 1n+count)

def header.signature(valid: Bool, +data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: header.lines(byte_count(data, 0n), Some{Parsing{False{}, False{}, data}})

def header(result: Maybe<&2, Line>) -> Result<&2, &2, Error, Header>:
  match result:
    case None{}: Fail{BadHeader{}}
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

def pixels(n: Nat, +index: U32, data: +List<U32>, output: Array<M.Vector3>) -> Result<&1, &1, Error, Array<M.Vector3>>:
  match n data:
    case 0n _: Done{output}
    case 1n+rest Con{r, Con{g, Con{b, Con{+e, tail}}}}:
      pixels(rest, (index + 1 : U32), tail, Array.set(M.Vector3, output, index, M.Vector3{sample(r, e), sample(g, e), sample(b, e)}))
    case _ _: Fail{Truncated{}}

def image(width: U32, height: U32, result: Result<&1, &1, Error, Array<M.Vector3>>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{pixels}: Done{Image{width, height, pixels}}

def start.valid(raw: Bool, complete: Bool, +width: U32, +height: U32, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match raw complete:
    case False{} _: Fail{BadHeader{}}
    case True{} False{}: Fail{Truncated{}}
    case True{} True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, pixels(U32.to_nat(count), 0, data, Array.new(M.Vector3, depth, M.Vector3{0.0, 0.0, 0.0})))

def start(result: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Header{+width, +height, +data}}:
      start.valid((width < 8 : U32) || Bool.not(rle_marker(data)), enough(U32.to_nat((width * height * 4 : U32)), data), width, height, data)

def checked(valid: Bool, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header(line(1023n, data, Nil{})))

def decode(+data: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(Q.valid_bytes(data, True{}), data)
