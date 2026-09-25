# Jonlib - original additions zlib, Copyright (c) 2026 Jonathan Peris.
# QOI decoding adapted from Dominic Szablewski's MIT-licensed qoi.h in raylib 6.0.
# Altered owned Bend implementation; see LICENSES/qoi.txt and THIRD_PARTY_NOTICES.md.
import Base

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}
  BadStream{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

type Header is Data:
  Header{width: U32, height: U32, channels: U32, data: +List<U32>}

type Word is Data:
  Word{value: U32, rest: +List<U32>}

def word(bytes: +List<U32>) -> Maybe<&2, Word>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      Some{Word{((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32), rest}}
    case _: None{}

def header.valid(valid: Bool, width: U32, height: U32, channels: U32, data: +List<U32>) -> Result<&2, &2, Error, Header>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: Done{Header{width, height, channels, data}}

def header.tail(width: U32, height: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Header>:
  match bytes:
    case Con{+channels, Con{space, rest}}:
      header.valid(((channels >= 3) && (channels <= 4) && (space <= 1) : U32), width, height, channels, rest)
    case _: Fail{BadHeader{}}

def header.height(width: U32, result: Maybe<&2, Word>) -> Result<&2, &2, Error, Header>:
  match result:
    case None{}: Fail{BadHeader{}}
    case Some{Word{height, rest}}: header.tail(width, height, rest)

def header.width(result: Maybe<&2, Word>) -> Result<&2, &2, Error, Header>:
  match result:
    case None{}: Fail{BadHeader{}}
    case Some{Word{width, rest}}: header.height(width, word(rest))

def header.magic(result: Maybe<&2, Word>) -> Result<&2, &2, Error, Header>:
  match result:
    case Some{Word{1903126886, rest}}: header.width(word(rest))
    case _: Fail{BadHeader{}}

def valid_bytes(bytes: +List<U32>, +valid: Bool) -> Bool:
  match bytes:
    case Nil{}: valid
    case Con{v, rest}: valid_bytes(rest, valid && (v <= 255 : U32))

def rgba(r: U32, g: U32, b: U32, a: U32) -> U32:
  (((r .&. 255) << 24n) .|. ((g .&. 255) << 16n) .|. ((b .&. 255) << 8n) .|. (a .&. 255) : U32)

def hash(+pixel: U32) -> U32:
  (((pixel >> 24n) * 3 + ((pixel >> 16n) .&. 255) * 5 + ((pixel >> 8n) .&. 255) * 7 + (pixel .&. 255) * 11) .&. 63 : U32)

type State is Type:
  State{data: +List<U32>, cache: Array<U32>, pixel: U32, repeat: U32, output: Array<U32>}

def parsed(data: +List<U32>, cache: Array<U32>, +pixel: U32, repeat: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  Done{State{data, Array.set(U32, cache, hash(pixel), pixel), pixel, repeat, output}}

def rgb(data: +List<U32>, cache: Array<U32>, previous: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match data:
    case Con{r, Con{g, Con{b, rest}}}: parsed(rest, cache, rgba(r, g, b, previous), 0, output)
    case _: Fail{Truncated{}}

def rgba_chunk(data: +List<U32>, cache: Array<U32>, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match data:
    case Con{r, Con{g, Con{b, Con{a, rest}}}}: parsed(rest, cache, rgba(r, g, b, a), 0, output)
    case _: Fail{Truncated{}}

def indexed(data: +List<U32>, output: Array<U32>, result: Array<U32> & U32) -> Result<&1, &1, Error, State>:
  (cache, pixel) = result
  parsed(data, cache, pixel, 0, output)

def diff(+byte: U32, +pixel: U32) -> U32:
  rgba(((pixel >> 24n) + ((byte >> 4n) .&. 3) - 2 : U32),
    (((pixel >> 16n) .&. 255) + ((byte >> 2n) .&. 3) - 2 : U32),
    (((pixel >> 8n) .&. 255) + (byte .&. 3) - 2 : U32), pixel)

def luma(data: +List<U32>, cache: Array<U32>, +pixel: U32, +green: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match data:
    case Con{+byte, rest}:
      parsed(rest, cache, rgba(((pixel >> 24n) + green - 8 + (byte >> 4n) : U32),
        (((pixel >> 16n) .&. 255) + green : U32),
        (((pixel >> 8n) .&. 255) + green - 8 + (byte .&. 15) : U32), pixel), 0, output)
    case _: Fail{Truncated{}}

def compact(tag: U32, +byte: U32, data: +List<U32>, cache: Array<U32>, pixel: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match tag:
    case 0: indexed(data, output, Array.get(U32, cache, (byte .&. 63 : U32)))
    case 1: parsed(data, cache, diff(byte, pixel), 0, output)
    case 2: luma(data, cache, pixel, ((byte .&. 63) - 32 : U32), output)
    case _: parsed(data, cache, pixel, (byte .&. 63 : U32), output)

def opcode(byte: U32, data: +List<U32>, cache: Array<U32>, pixel: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match byte:
    case 254: rgb(data, cache, pixel, output)
    case 255: rgba_chunk(data, cache, output)
    case +other: compact((other >> 6n : U32), other, data, cache, pixel, output)

def next(repeat: U32, data: +List<U32>, cache: Array<U32>, pixel: U32, output: Array<U32>) -> Result<&1, &1, Error, State>:
  match repeat:
    case 0:
      match data:
        case Nil{}: Fail{Truncated{}}
        case Con{byte, rest}: opcode(byte, rest, cache, pixel, output)
    case n: Done{State{data, cache, pixel, (n - 1 : U32), output}}

def write(i: U32, channels: U32, result: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{State{data, cache, +pixel, repeat, output}}:
      Done{State{data, cache, pixel, repeat, Array.set(U32, output, i,
        Bool.pick(U32, U32.is_eq(channels, 3), (pixel .|. 255 : U32), pixel))}}

def finish(state: State) -> Result<&1, &1, Error, Array<U32>>:
  match state:
    case State{Con{0, Con{0, Con{0, Con{0, Con{0, Con{0, Con{0, Con{1, Nil{}}}}}}}}}, _, _, 0, output}: Done{output}
    case _: Fail{BadStream{}}

def loop(n: Nat, +i: U32, +channels: U32, state: Result<&1, &1, Error, State>) -> Result<&1, &1, Error, Array<U32>>:
  match n state:
    case _ Fail{error}: Fail{error}
    case 0n Done{value}: finish(value)
    case 1n+k Done{State{data, cache, pixel, repeat, output}}:
      loop(k, (i + 1 : U32), channels, write(i, channels, next(repeat, data, cache, pixel, output)))

def image(width: U32, height: U32, result: Result<&1, &1, Error, Array<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{pixels}: Done{Image{width, height, pixels}}

def sized(valid: Bool, +width: U32, +height: U32, channels: U32, data: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, loop(U32.to_nat(count), 0, channels, Done{State{data, Array.new(U32, 6n, 0), 255, 0, Array.new(U32, depth, 0)}}))

def start(header: Result<&2, &2, Error, Header>) -> Result<&1, &1, Error, Image>:
  match header:
    case Fail{error}: Fail{error}
    case Done{Header{+w, +h, channels, data}}:
      sized(((w >= 1) && (h >= 1) && (w <= 4096) && (h <= 4096) : U32), w, h, channels, data)

def checked(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadByte{}}
    case True{}: start(header.magic(word(bytes)))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  checked(valid_bytes(bytes, True{}), bytes)

type Encoder is Type:
  Encoder{cache: Array<U32>, previous: U32, run: U32, reverse: +List<U32>}

def encode.flush(run: U32, reverse: +List<U32>) -> +List<U32>:
  match run:
    case 0: reverse
    case n: Con{(192 .|. (n - 1) : U32), reverse}

def encode.rgb(diff_ok: Bool, luma_ok: Bool, +pixel: U32, dr: U32, dg: U32, db: U32, green: U32, red_green: U32, blue_green: U32, reverse: +List<U32>) -> +List<U32>:
  match diff_ok luma_ok:
    case True{} _: Con{(64 .|. (dr << 4n) .|. (dg << 2n) .|. db : U32), reverse}
    case False{} True{}: Con{((red_green << 4n) .|. blue_green : U32), Con{(128 .|. green : U32), reverse}}
    case False{} False{}:
      Con{((pixel >> 8n) .&. 255 : U32), Con{((pixel >> 16n) .&. 255 : U32), Con{(pixel >> 24n : U32), Con{254, reverse}}}}

def encode.color(same_alpha: Bool, +pixel: U32, +previous: U32, reverse: +List<U32>) -> +List<U32>:
  match same_alpha:
    case False{}:
      Con{(pixel .&. 255 : U32), Con{((pixel >> 8n) .&. 255 : U32), Con{((pixel >> 16n) .&. 255 : U32), Con{(pixel >> 24n : U32), Con{255, reverse}}}}}
    case True{}:
      +r = (((pixel >> 24n) - (previous >> 24n)) .&. 255 : U32)
      +g = ((((pixel >> 16n) .&. 255) - ((previous >> 16n) .&. 255)) .&. 255 : U32)
      +b = ((((pixel >> 8n) .&. 255) - ((previous >> 8n) .&. 255)) .&. 255 : U32)
      +dr = ((r + 2) .&. 255 : U32)
      +dg = ((g + 2) .&. 255 : U32)
      +db = ((b + 2) .&. 255 : U32)
      +green = ((g + 32) .&. 255 : U32)
      +rg = ((r - g + 8) .&. 255 : U32)
      +bg = ((b - g + 8) .&. 255 : U32)
      encode.rgb(((dr < 4) && (dg < 4) && (db < 4) : U32), ((green < 64) && (rg < 16) && (bg < 16) : U32),
        pixel, dr, dg, db, green, rg, bg, reverse)

def encode.cache(hit: Bool, cache: Array<U32>, +pixel: U32, +previous: U32, reverse: +List<U32>) -> Encoder:
  match hit:
    case True{}: Encoder{cache, pixel, 0, Con{hash(pixel), reverse}}
    case False{}:
      Encoder{Array.set(U32, cache, hash(pixel), pixel), pixel, 0,
        encode.color(U32.is_eq((pixel .&. 255 : U32), (previous .&. 255 : U32)), pixel, previous, reverse)}

def encode.lookup(+pixel: U32, previous: U32, reverse: +List<U32>, got: Array<U32> & U32) -> Encoder:
  (cache, found) = got
  encode.cache(U32.is_eq(pixel, found), cache, pixel, previous, reverse)

def encode.repeat(full: Bool, cache: Array<U32>, pixel: U32, run: U32, reverse: +List<U32>) -> Encoder:
  match full:
    case True{}: Encoder{cache, pixel, 0, Con{253, reverse}}
    case False{}: Encoder{cache, pixel, run, reverse}

def encode.same(same: Bool, cache: Array<U32>, +pixel: U32, previous: U32, +run: U32, reverse: +List<U32>) -> Encoder:
  match same:
    case True{}: encode.repeat(U32.is_eq(run, 61), cache, pixel, (run + 1 : U32), reverse)
    case False{}: encode.lookup(pixel, previous, encode.flush(run, reverse), Array.get(U32, cache, hash(pixel)))

def encode.step(got: Array<U32> & U32, encoder: Encoder) -> Array<U32> & Encoder:
  match got encoder:
    case Tuple{pixels, +pixel} Encoder{cache, +previous, run, reverse}:
      (pixels, encode.same(U32.is_eq(pixel, previous), cache, pixel, previous, run, reverse))

def encode.loop(n: Nat, +i: U32, state: Array<U32> & Encoder) -> +List<U32>:
  match n state:
    case 0n Tuple{_, Encoder{_, _, run, reverse}}:
      List.reverse(&2, U32, Con{1, Con{0, Con{0, Con{0, Con{0, Con{0, Con{0, Con{0, encode.flush(run, reverse)}}}}}}}})
    case 1n+k Tuple{pixels, encoder}:
      encode.loop(k, (i + 1 : U32), encode.step(Array.get(U32, pixels, i), encoder))

def encode(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  prefix = {[0,4, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), ((height >> 16n) .&. 255 : U32), (height >> 24n : U32),
    (width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), ((width >> 16n) .&. 255 : U32), (width >> 24n : U32), 102,105,111,113] : +List<U32>}
  encode.loop(U32.to_nat((width * height : U32)), 0, (pixels, Encoder{Array.new(U32, 6n, 0), 255, 0, prefix}))
