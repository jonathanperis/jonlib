# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned stb_image PNG chunk/filter/color rules.
# MIT notice: LICENSES/stb-image.txt. Bounded non-interlaced byte/packed profile.
import Base
import ./qoi.bend as Q
import ./inflate.bend as Z

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  BadStream{}

type Image is Type:
  Image{width: U32, height: U32, pixels: Array<U32>}

type Config is Data:
  Config{width: U32, height: U32, color: U32, channels: U32, bits: U32}

def channels(color: U32) -> U32:
  match color:
    case 0: 1
    case 2: 3
    case 3: 1
    case 4: 2
    case 6: 4
    case _: 0

def config.sized(valid: Bool, width: U32, height: U32, color: U32, channels: U32, bits: U32) -> Result<&2, &2, Error, Config>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: Done{Config{width, height, color, channels, bits}}

def config.valid(valid: Bool, +width: U32, +height: U32, color: U32, channels: U32, bits: U32) -> Result<&2, &2, Error, Config>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: config.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, color, channels, bits)

def config.tail(width: U32, height: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Config>:
  match bytes:
    case Con{+bits, Con{+color, Con{0, Con{0, Con{0, Nil{}}}}}}:
      +count = channels(color)
      valid = (U32.is_eq(bits, 8) && (count > 0 : U32)) || ((U32.is_eq(color, 0) || U32.is_eq(color, 3))
        && (U32.is_eq(bits, 1) || U32.is_eq(bits, 2) || U32.is_eq(bits, 4)))
      config.valid(valid, width, height, color, count, bits)
    case _: Fail{BadHeader{}}

def config.height(width: U32, word: Maybe<&2, Q.Word>) -> Result<&2, &2, Error, Config>:
  match word:
    case None{}: Fail{BadHeader{}}
    case Some{Q.Word{height, rest}}: config.tail(width, height, rest)

def config(word: Maybe<&2, Q.Word>) -> Result<&2, &2, Error, Config>:
  match word:
    case None{}: Fail{BadHeader{}}
    case Some{Q.Word{width, rest}}: config.height(width, Q.word(rest))

def reverse_into(bytes: +List<U32>, values: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: values
    case Con{head, rest}: reverse_into(rest, Con{head, values})

def palette(bytes: +List<U32>, values: +List<U32>) -> Maybe<&2, +List<U32>>:
  match bytes:
    case Nil{}: Some{List.reverse(&2, U32, values)}
    case Con{r, Con{g, Con{b, rest}}}: palette(rest, Con{((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. 255 : U32), values})
    case _: None{}

def palette.alpha(colors: +List<U32>, alpha: +List<U32>, values: +List<U32>) -> Maybe<&2, +List<U32>>:
  match colors alpha:
    case _ Nil{}: Some{List.append(&2, U32, List.reverse(&2, U32, values), colors)}
    case Nil{} _: None{}
    case Con{color, rest} Con{a, tail}: palette.alpha(rest, tail, Con{((color .&. 4294967040) .|. a : U32), values})

type Parts is Data:
  Parts{config: Maybe<&2, Config>, palette: +List<U32>, key: Maybe<&2, U32>, compressed: +List<U32>, seen: Bool}

type Parsing is Data:
  More{bytes: +List<U32>, parts: Parts}
  Complete{parts: Parts}

type Chunk is Data:
  Chunk{kind: U32, size: U32, payload: +List<U32>, rest: +List<U32>}

def chunk.crc(kind: U32, size: U32, values: +List<U32>, crc: Maybe<&2, Q.Word>) -> Maybe<&2, Chunk>:
  match crc:
    case None{}: None{}
    case Some{Q.Word{_, rest}}: Some{Chunk{kind, size, List.reverse(&2, U32, values), rest}}

type Payload is Data:
  Payload{values: +List<U32>, rest: +List<U32>}

def chunk.take(n: Nat, bytes: +List<U32>, values: +List<U32>) -> Maybe<&2, Payload>:
  match n bytes:
    case 0n _: Some{Payload{values, bytes}}
    case _ Nil{}: None{}
    case 1n+rest Con{byte, tail}: chunk.take(rest, tail, Con{byte, values})

def chunk.loaded(kind: U32, size: U32, result: Maybe<&2, Payload>) -> Maybe<&2, Chunk>:
  match result:
    case None{}: None{}
    case Some{Payload{values, rest}}: chunk.crc(kind, size, values, Q.word(rest))

def chunk.valid(valid: Bool, +size: U32, word: Maybe<&2, Q.Word>) -> Maybe<&2, Chunk>:
  match valid word:
    case True{} Some{Q.Word{kind, rest}}: chunk.loaded(kind, size, chunk.take(U32.to_nat(size), rest, Nil{}))
    case _ _: None{}

def chunk(word: Maybe<&2, Q.Word>) -> Maybe<&2, Chunk>:
  match word:
    case None{}: None{}
    case Some{Q.Word{+size, rest}}: chunk.valid((size <= 1048576 : U32), size, Q.word(rest))

def more.valid(valid: Bool, bytes: +List<U32>, parts: Parts) -> Result<&2, &2, Error, Parsing>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: Done{More{bytes, parts}}

def more.config(bytes: +List<U32>, result: Result<&2, &2, Error, Config>) -> Result<&2, &2, Error, Parsing>:
  match result:
    case Fail{error}: Fail{error}
    case Done{cfg}: Done{More{bytes, Parts{Some{cfg}, Nil{}, None{}, Nil{}, False{}}}}

def more.palette(cfg: Config, key: Maybe<&2, U32>, compressed: +List<U32>, seen: Bool, bytes: +List<U32>, colors: Maybe<&2, +List<U32>>) -> Result<&2, &2, Error, Parsing>:
  match colors:
    case None{}: Fail{BadHeader{}}
    case Some{values}: Done{More{bytes, Parts{Some{cfg}, values, key, compressed, seen}}}

def more.plte(valid: Bool, cfg: Config, key: Maybe<&2, U32>, compressed: +List<U32>, seen: Bool, payload: +List<U32>, bytes: +List<U32>) -> Result<&2, &2, Error, Parsing>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: more.palette(cfg, key, compressed, seen, bytes, palette(payload, Nil{}))

def more.transparency(color: U32, scale: U32, cfg: Config, colors: +List<U32>, compressed: +List<U32>, payload: +List<U32>, bytes: +List<U32>) -> Result<&2, &2, Error, Parsing>:
  match color payload:
    case 0 Con{_, Con{value, Nil{}}}:
      +gray = ((value * scale) .&. 255 : U32)
      Done{More{bytes, Parts{Some{cfg}, colors, Some{((gray << 24n) .|. (gray << 16n) .|. (gray << 8n) : U32)}, compressed, False{}}}}
    case 2 Con{_, Con{r, Con{_, Con{g, Con{_, Con{b, Nil{}}}}}}}: Done{More{bytes, Parts{Some{cfg}, colors, Some{((r << 24n) .|. (g << 16n) .|. (b << 8n) : U32)}, compressed, False{}}}}
    case 3 _: more.palette(cfg, None{}, compressed, False{}, bytes, palette.alpha(colors, payload, Nil{}))
    case _ _: Fail{BadHeader{}}

def more.trns(valid: Bool, color: U32, scale: U32, cfg: Config, colors: +List<U32>, compressed: +List<U32>, payload: +List<U32>, bytes: +List<U32>) -> Result<&2, &2, Error, Parsing>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: more.transparency(color, scale, cfg, colors, compressed, payload, bytes)

def complete(valid: Bool, parts: Parts) -> Result<&2, &2, Error, Parsing>:
  match valid:
    case False{}: Fail{BadHeader{}}
    case True{}: Done{Complete{parts}}

def dispatch.kind(+kind: U32, +size: U32, cfg: Config, colors: +List<U32>, key: Maybe<&2, U32>, compressed: +List<U32>, +seen: Bool, payload: +List<U32>, bytes: +List<U32>, color: U32, scale: U32, indexed: Bool, has_palette: Bool) -> Result<&2, &2, Error, Parsing>:
  match kind:
    case 1229472850: Fail{BadHeader{}}
    case 1347179589: more.plte(((size > 0) && (size <= 768) : U32) && U32.is_eq((size % 3 : U32), 0) && Bool.not(seen), cfg, key, compressed, seen, payload, bytes)
    case 1951551059: more.trns(Bool.not(seen) && (Bool.not(indexed) || has_palette), color, scale, cfg, colors, compressed, payload, bytes)
    case 1229209940: more.valid(Bool.not(indexed) || has_palette, bytes, Parts{Some{cfg}, colors, key, reverse_into(payload, compressed), True{}})
    case 1229278788: complete(U32.is_eq(size, 0) && seen, Parts{Some{cfg}, colors, key, compressed, seen})
    case _: more.valid(((kind .&. 536870912) > 0 : U32), bytes, Parts{Some{cfg}, colors, key, compressed, seen})

def dispatch(+cfg: Config, kind: U32, size: U32, +colors: +List<U32>, key: Maybe<&2, U32>, compressed: +List<U32>, seen: Bool, payload: +List<U32>, bytes: +List<U32>) -> Result<&2, &2, Error, Parsing>:
  Config{_, _, +color, _, bits} = cfg
  dispatch.kind(kind, size, cfg, colors, key, compressed, seen, payload, bytes, color, (255 / ((1 << U32.to_nat(bits)) - 1) : U32), U32.is_eq(color, 3), Bool.not(List.is_empty(&2, U32, colors)))

def parsed(parts: Parts, result: Maybe<&2, Chunk>) -> Result<&2, &2, Error, Parsing>:
  match parts result:
    case _ None{}: Fail{BadHeader{}}
    case Parts{None{}, _, _, _, _} Some{Chunk{1229472850, 13, payload, rest}}: more.config(rest, config(Q.word(payload)))
    case Parts{None{}, _, _, _, _} _: Fail{BadHeader{}}
    case Parts{Some{cfg}, colors, key, compressed, seen} Some{Chunk{kind, size, payload, rest}}: dispatch(cfg, kind, size, colors, key, compressed, seen, payload, rest)

def parse(n: Nat, state: Result<&2, &2, Error, Parsing>) -> Result<&2, &2, Error, Parts>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{parts}}: Done{parts}
    case 0n _: Fail{BadHeader{}}
    case 1n+rest Done{More{bytes, parts}}: parse(rest, parsed(parts, chunk(Q.word(bytes))))

def signature(size: U32, bytes: +List<U32>) -> Result<&2, &2, Error, Parts>:
  match bytes:
    case Con{137, Con{80, Con{78, Con{71, Con{13, Con{10, Con{26, Con{10, rest}}}}}}}}:
      parse(U32.to_nat(size), Done{More{rest, Parts{None{}, Nil{}, None{}, Nil{}, False{}}}})
    case _: Fail{BadHeader{}}

def difference(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a >= b : U32), (a - b : U32), (b - a : U32))

def paeth(+a: U32, +b: U32, +c: U32) -> U32:
  +pa = difference(b, c)
  +pb = difference(a, c)
  +pc = difference((a + b : U32), (2 * c : U32))
  Bool.pick(U32, ((pa <= pb) && (pa <= pc) : U32), a, Bool.pick(U32, (pb <= pc : U32), b, c))

def predictor(filter: U32, a: U32, b: U32, c: U32) -> U32:
  match filter:
    case 0: 0
    case 1: a
    case 2: b
    case 3: ((a + b) / 2 : U32)
    case _: paeth(a, b, c)

def neighbor(valid: Bool, index: U32, pixels: Array<U32>) -> Array<U32> & U32:
  match valid:
    case False{}: (pixels, 0)
    case True{}: Array.get(U32, pixels, index)

type Scan is Type:
  Scan{data: List<U32>, pixels: Array<U32>, filter: U32}

def scan.write(+index: U32, raw: U32, +filter: U32, data: List<U32>, a: U32, b: U32, read: Array<U32> & U32) -> Scan:
  (pixels, c) = read
  Scan{data, Array.set(U32, pixels, index, ((raw + predictor(filter, a, b, c)) .&. 255 : U32)), filter}

def scan.above(+index: U32, width: U32, channels: U32, valid: Bool, raw: U32, filter: U32, data: List<U32>, a: U32, read: Array<U32> & U32) -> Scan:
  (pixels, b) = read
  scan.write(index, raw, filter, data, a, b, neighbor(valid, (index - width - channels : U32), pixels))

def scan.left(+index: U32, +width: U32, channels: U32, left: Bool, raw: U32, filter: U32, data: List<U32>, read: Array<U32> & U32) -> Scan:
  (pixels, a) = read
  +above = (index >= width : U32)
  scan.above(index, width, channels, left && above, raw, filter, data, a, neighbor(above, (index - width : U32), pixels))

def scan.byte(+index: U32, +width: U32, +channels: U32, state: Maybe<Scan>) -> Maybe<Scan>:
  match state:
    case Some{Scan{Con{raw, rest}, pixels, filter}}:
      +left = (index % width >= channels : U32)
      Some{scan.left(index, width, channels, left, raw, filter, rest, neighbor(left, (index - channels : U32), pixels))}
    case _: None{}

def scan.filter(valid: Bool, filter: U32, data: List<U32>, pixels: Array<U32>) -> Maybe<Scan>:
  match valid:
    case False{}: None{}
    case True{}: Some{Scan{data, pixels, filter}}

def scan.row(start: Bool, state: Scan) -> Maybe<Scan>:
  match start state:
    case False{} _: Some{state}
    case True{} Scan{Con{+filter, rest}, pixels, _}: scan.filter((filter <= 4 : U32), filter, rest, pixels)
    case _ _: None{}

def scan(n: Nat, +index: U32, +width: U32, +channels: U32, state: Maybe<Scan>) -> Maybe<Array<U32>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Scan{Nil{}, pixels, _}}: Some{pixels}
    case 0n _: None{}
    case 1n+rest Some{value}: scan(rest, (index + 1 : U32), width, channels, scan.byte(index, width, channels, scan.row(U32.is_eq((index % width : U32), 0), value)))

def word.read(shift: Nat, value: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pixels, byte) = read
  (pixels, (value .|. (byte << shift) : U32))

def word(n: Nat, +index: U32, +shift: Nat, state: Array<U32> & U32) -> Array<U32> & U32:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{pixels, value}: word(rest, (index + 1 : U32), (shift + 8n : Nat), word.read(shift, value, Array.get(U32, pixels, index)))

def rgba(color: U32, +value: U32, palette: +List<U32>) -> Maybe<&2, U32>:
  match color:
    case 0: Some{((value << 24n) .|. (value << 16n) .|. (value << 8n) .|. 255 : U32)}
    case 2: Some{(((value .&. 255) << 24n) .|. (((value >> 8n) .&. 255) << 16n) .|. ((value >> 16n) << 8n) .|. 255 : U32)}
    case 3: List.get(&2, U32, palette, U32.to_nat(value))
    case 4:
      +gray = (value .&. 255 : U32)
      Some{((gray << 24n) .|. (gray << 16n) .|. (gray << 8n) .|. (value >> 8n) : U32)}
    case _: Some{(((value .&. 255) << 24n) .|. (((value >> 8n) .&. 255) << 16n) .|. (((value >> 16n) .&. 255) << 8n) .|. (value >> 24n) : U32)}

def transparency(key: Maybe<&2, U32>, pixel: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match key pixel:
    case _ None{}: None{}
    case None{} _: pixel
    case Some{key} Some{+value}: Some{Bool.pick(U32, U32.is_eq((value .&. 4294967040 : U32), key), (value .&. 4294967040 : U32), value)}

type Pixels is Type:
  Pixels{samples: Array<U32>, output: Array<U32>}

def pixels.write(index: U32, samples: Array<U32>, output: Array<U32>, result: Maybe<&2, U32>) -> Maybe<Pixels>:
  match result:
    case None{}: None{}
    case Some{value}: Some{Pixels{samples, Array.set(U32, output, index, value)}}

def packed.sample(packed: Bool, bits: U32, shift: U32, color: U32, word: U32) -> U32:
  match packed:
    case False{}: word
    case True{}:
      +mask = ((1 << U32.to_nat(bits)) - 1 : U32)
      +value = ((word >> U32.to_nat(shift)) .&. mask : U32)
      Bool.pick(U32, U32.is_eq(color, 0), (value * (255 / mask) : U32), value)

def pixels.read(index: U32, +color: U32, +bits: U32, shift: U32, palette: +List<U32>, key: Maybe<&2, U32>, output: Array<U32>, read: Array<U32> & U32) -> Maybe<Pixels>:
  (samples, value) = read
  pixels.write(index, samples, output, transparency(key, rgba(color, packed.sample((bits < 8 : U32), bits, shift, color, value), palette)))

def pixels(n: Nat, +index: U32, +width: U32, +row: U32, +color: U32, +channels: U32, +bits: U32, +palette: +List<U32>, +key: Maybe<&2, U32>, state: Maybe<Pixels>) -> Maybe<Array<U32>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Pixels{_, output}}: Some{output}
    case 1n+rest Some{Pixels{samples, output}}:
      +x = (index % width : U32)
      at = (index / width * row + x * channels * bits / 8 : U32)
      shift = (8 - bits - (x * bits % 8) : U32)
      count = Bool.pick(U32, (bits < 8 : U32), 1, channels)
      pixels(rest, (index + 1 : U32), width, row, color, channels, bits, palette, key,
        pixels.read(index, color, bits, shift, palette, key, output, word(U32.to_nat(count), at, 0n, (samples, 0))))

def image(width: U32, height: U32, result: Maybe<Array<U32>>) -> Result<&1, &1, Error, Image>:
  match result:
    case None{}: Fail{BadStream{}}
    case Some{output}: Done{Image{width, height, output}}

def converted(+width: U32, +height: U32, color: U32, channels: U32, bits: U32, row: U32, palette: +List<U32>, key: Maybe<&2, U32>, samples: Maybe<Array<U32>>) -> Result<&1, &1, Error, Image>:
  match samples:
    case None{}: Fail{BadStream{}}
    case Some{values}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      image(width, height, pixels(U32.to_nat(count), 0, width, row, color, channels, bits, palette, key, Some{Pixels{values, Array.new(U32, depth, 0)}}))

def inflated(+width: U32, +height: U32, color: U32, +channels: U32, +bits: U32, palette: +List<U32>, key: Maybe<&2, U32>, data: Maybe<List<U32>>) -> Result<&1, &1, Error, Image>:
  match data:
    case None{}: Fail{BadStream{}}
    case Some{bytes}:
      +row = ((width * channels * bits + 7) / 8 : U32)
      +count = (row * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      converted(width, height, color, channels, bits, row, palette, key, scan(U32.to_nat(count), 0, row, ((channels * bits + 7) / 8 : U32), Some{Scan{bytes, Array.new(U32, depth, 0), 0}}))

def zlib.valid(valid: Bool, bytes: +List<U32>, limit: U32) -> Maybe<List<U32>>:
  match valid:
    case False{}: None{}
    case True{}: Z.decompress(False{}, bytes, limit)

def zlib(bytes: +List<U32>, limit: U32) -> Maybe<List<U32>>:
  match bytes:
    case Con{+cmf, Con{+flag, rest}}:
      zlib.valid(U32.is_eq((cmf .&. 15 : U32), 8) && U32.is_eq(((cmf * 256 + flag) % 31 : U32), 0) && U32.is_eq((flag .&. 32 : U32), 0), rest, limit)
    case _: None{}

def decode.bounded(valid: Bool, width: U32, height: U32, color: U32, channels: U32, bits: U32, palette: +List<U32>, key: Maybe<&2, U32>, compressed: +List<U32>, limit: U32) -> Result<&1, &1, Error, Image>:
  match valid:
    case False{}: Fail{BadSize{}}
    case True{}: inflated(width, height, color, channels, bits, palette, key, zlib(List.reverse(&2, U32, compressed), limit))

def decode.parts(result: Result<&2, &2, Error, Parts>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Parts{Some{Config{+width, +height, color, +channels, +bits}}, palette, key, compressed, _}}:
      +limit = (((width * channels * bits + 7) / 8 + 1) * height : U32)
      decode.bounded((limit <= 67108864 : U32), width, height, color, channels, bits, palette, key, compressed, limit)
    case _: Fail{BadHeader{}}

def input.error(valid_byte: Bool, valid_size: Bool) -> Maybe<&2, Error>:
  match valid_byte valid_size:
    case False{} _: Some{BadByte{}}
    case True{} False{}: Some{BadSize{}}
    case True{} True{}: None{}

def input.count(bytes: +List<U32>, +count: U32, error: Maybe<&2, Error>) -> Result<&2, &2, Error, U32>:
  match bytes error:
    case _ Some{error}: Fail{error}
    case Nil{} None{}: Done{count}
    case Con{byte, rest} None{}: input.count(rest, (count + 1 : U32), input.error((byte <= 255 : U32), (count < 1048576 : U32)))

def decode.checked(bytes: +List<U32>, result: Result<&2, &2, Error, U32>) -> Result<&1, &1, Error, Image>:
  match result:
    case Fail{error}: Fail{error}
    case Done{size}: decode.parts(signature(size, bytes))

def decode(+bytes: +List<U32>) -> Result<&1, &1, Error, Image>:
  decode.checked(bytes, input.count(bytes, 0, None{}))
