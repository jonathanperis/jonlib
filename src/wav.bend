# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of dr_wav (David Reid; public domain or MIT-0, as
# pinned raylib 6.0 vendors it in src/external/dr_wav.h): drwav_init_memory's
# RIFF chunk walk and drwav_read_pcm_frames_s16 for PCM, IEEE float 32-bit,
# a-law and mu-law data. See THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C

# Samples are signed 16-bit values stored as their 16-bit pattern.
type Outcome is Type:
  Decoded{rate: U32, channels: U32, frames: U32, samples: +List<U32>}
  Unsupported{}
  Invalid{error: C.Error}

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, bytes, U32.to_nat(index)))

def u16(+bytes: +List<U32>, +index: U32) -> U32:
  (at(bytes, index) .|. (at(bytes, (index + 1 : U32)) << 8n) : U32)

def u32(+bytes: +List<U32>, +index: U32) -> U32:
  (u16(bytes, index) .|. (u16(bytes, (index + 2 : U32)) << 16n) : U32)

def tag(+bytes: +List<U32>, +index: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> Bool:
  U32.is_eq(at(bytes, index), a) && U32.is_eq(at(bytes, (index + 1 : U32)), b)
    && U32.is_eq(at(bytes, (index + 2 : U32)), c) && U32.is_eq(at(bytes, (index + 3 : U32)), d)

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# -----------------------------------------------------------------------------
# Chunk walk (drwav_init__internal for RIFF). `cursor` is the stream position;
# a seek before the start or past the end fails like dr_wav's memory stream.

type Fmt is Data:
  Fmt{tag: U32, channels: U32, rate: U32, align: U32, bits: U32, sub: U32}

type Scan is Data:
  Scan{cursor: U32, has_fmt: Bool, fmt: Fmt, has_data: Bool, pos: U32, size: U32, failed: Bool, done: Bool}

def Fmt.empty() -> Fmt:
  Fmt{0, 0, 0, 0, 0, 0}

# The "fmt " chunk at `c` (after its header): 16 bytes, then for larger chunks
# the extension size, a WAVE_FORMAT_EXTENSIBLE extension (exactly 22 bytes) or
# skipped extension bytes, then a relative seek to the chunk's declared end.
def fmt.chunk(+bytes: +List<U32>, +len: U32, +c: U32, +size: U32, +pad: U32, +has_data: Bool, +pos: U32, +dsize: U32) -> Scan:
  +ftag = u16(bytes, c)
  +c2 = (c + 16 : U32)
  +longer = (size > 16 : U32)
  +ext = u16(bytes, c2)
  +c3 = (c2 + 2 : U32)
  +extensible = U32.is_eq(ftag, 65534)
  +ext_ok = U32.is_eq(ext, 0) || Bool.not(extensible) || U32.is_eq(ext, 22)
  +ext_fits = Bool.pick(Bool, extensible, ((len - c3) >= 22 : U32), (ext <= (len - c3) : U32))
  +c4 = (c3 + ext : U32)
  +offset = (size - (18 + ext) : U32)
  +target = (c4 + offset : U32)
  +seek_ok = Bool.pick(Bool, negative(offset), ((0 - offset) <= c4 : U32), (offset <= (len - c4) : U32))
  +sub = Bool.pick(U32, extensible && U32.is_eq(ext, 22), u16(bytes, (c3 + 6 : U32)), 0)
  +final = Bool.pick(U32, longer, target, c2)
  +failed = ((len - c) < 16 : U32) || (longer && (((len - c2) < 2 : U32) || Bool.not(ext_ok) || (U32.is_ne(ext, 0) && Bool.not(ext_fits)) || Bool.not(seek_ok)))
  +padded_ok = ((final + pad) <= len : U32)
  Scan{Bool.pick(U32, padded_ok, (final + pad : U32), final), True{}, Fmt{ftag, u16(bytes, (c + 2 : U32)), u32(bytes, (c + 4 : U32)), u16(bytes, (c + 12 : U32)), u16(bytes, (c + 14 : U32)), sub}, has_data, pos, dsize, failed,
    Bool.not(padded_ok)}

def chunk(+bytes: +List<U32>, +len: U32, +cursor: U32, +has_fmt: Bool, +fmt: Fmt, +has_data: Bool, +pos: U32, +dsize: U32) -> Scan:
  +rem = (len - cursor : U32)
  +c = (cursor + 8 : U32)
  +size = u32(bytes, (cursor + 4 : U32))
  +pad = (size .&. 1 : U32)
  +after = (len - c : U32)
  +is_fmt = tag(bytes, cursor, 102, 109, 116, 32)
  +is_data = tag(bytes, cursor, 100, 97, 116, 97)
  +is_fact = tag(bytes, cursor, 102, 97, 99, 116)
  +skip_beyond = (size > after : U32) || ((size + pad) > after : U32)
  +fact_beyond = (size < 4 : U32) || ((size - 4 + pad) > (after - 4) : U32)
  Bool.pick(Scan, (rem < 8 : U32), Scan{cursor, has_fmt, fmt, has_data, pos, dsize, False{}, True{}},
  Bool.pick(Scan, is_fmt, fmt.chunk(bytes, len, c, size, pad, has_data, pos, dsize),
  Bool.pick(Scan, is_data, Scan{c, has_fmt, fmt, True{}, c, size, False{}, True{}},
  Bool.pick(Scan, is_fact, Scan{(c + size + pad : U32), has_fmt, fmt, has_data, pos, dsize, (after < 4 : U32), fact_beyond},
    Scan{(c + size + pad : U32), has_fmt, fmt, has_data, pos, dsize, False{}, skip_beyond}))))

def chunks(n: Nat, +bytes: +List<U32>, +len: U32, scan: Scan) -> Scan:
  match n scan:
    case 1n+k Scan{cursor, has_fmt, fmt, has_data, pos, size, False{}, False{}}: chunks(k, bytes, len, chunk(bytes, len, cursor, has_fmt, fmt, has_data, pos, size))
    case _ other: other

# -----------------------------------------------------------------------------
# Samples (drwav_read_pcm_frames_s16)

def alaw() -> +List<U32>:
  [60032, 60288, 59520, 59776, 61056, 61312, 60544, 60800, 57984, 58240, 57472, 57728, 59008, 59264, 58496, 58752,
   62784, 62912, 62528, 62656, 63296, 63424, 63040, 63168, 61760, 61888, 61504, 61632, 62272, 62400, 62016, 62144,
   43520, 44544, 41472, 42496, 47616, 48640, 45568, 46592, 35328, 36352, 33280, 34304, 39424, 40448, 37376, 38400,
   54528, 55040, 53504, 54016, 56576, 57088, 55552, 56064, 50432, 50944, 49408, 49920, 52480, 52992, 51456, 51968,
   65192, 65208, 65160, 65176, 65256, 65272, 65224, 65240, 65064, 65080, 65032, 65048, 65128, 65144, 65096, 65112,
   65448, 65464, 65416, 65432, 65512, 65528, 65480, 65496, 65320, 65336, 65288, 65304, 65384, 65400, 65352, 65368,
   64160, 64224, 64032, 64096, 64416, 64480, 64288, 64352, 63648, 63712, 63520, 63584, 63904, 63968, 63776, 63840,
   64848, 64880, 64784, 64816, 64976, 65008, 64912, 64944, 64592, 64624, 64528, 64560, 64720, 64752, 64656, 64688,
   5504, 5248, 6016, 5760, 4480, 4224, 4992, 4736, 7552, 7296, 8064, 7808, 6528, 6272, 7040, 6784,
   2752, 2624, 3008, 2880, 2240, 2112, 2496, 2368, 3776, 3648, 4032, 3904, 3264, 3136, 3520, 3392,
   22016, 20992, 24064, 23040, 17920, 16896, 19968, 18944, 30208, 29184, 32256, 31232, 26112, 25088, 28160, 27136,
   11008, 10496, 12032, 11520, 8960, 8448, 9984, 9472, 15104, 14592, 16128, 15616, 13056, 12544, 14080, 13568,
   344, 328, 376, 360, 280, 264, 312, 296, 472, 456, 504, 488, 408, 392, 440, 424,
   88, 72, 120, 104, 24, 8, 56, 40, 216, 200, 248, 232, 152, 136, 184, 168,
   1376, 1312, 1504, 1440, 1120, 1056, 1248, 1184, 1888, 1824, 2016, 1952, 1632, 1568, 1760, 1696,
   688, 656, 752, 720, 560, 528, 624, 592, 944, 912, 1008, 976, 816, 784, 880, 848]

def mulaw() -> +List<U32>:
  [33412, 34436, 35460, 36484, 37508, 38532, 39556, 40580, 41604, 42628, 43652, 44676, 45700, 46724, 47748, 48772,
   49540, 50052, 50564, 51076, 51588, 52100, 52612, 53124, 53636, 54148, 54660, 55172, 55684, 56196, 56708, 57220,
   57604, 57860, 58116, 58372, 58628, 58884, 59140, 59396, 59652, 59908, 60164, 60420, 60676, 60932, 61188, 61444,
   61636, 61764, 61892, 62020, 62148, 62276, 62404, 62532, 62660, 62788, 62916, 63044, 63172, 63300, 63428, 63556,
   63652, 63716, 63780, 63844, 63908, 63972, 64036, 64100, 64164, 64228, 64292, 64356, 64420, 64484, 64548, 64612,
   64660, 64692, 64724, 64756, 64788, 64820, 64852, 64884, 64916, 64948, 64980, 65012, 65044, 65076, 65108, 65140,
   65164, 65180, 65196, 65212, 65228, 65244, 65260, 65276, 65292, 65308, 65324, 65340, 65356, 65372, 65388, 65404,
   65416, 65424, 65432, 65440, 65448, 65456, 65464, 65472, 65480, 65488, 65496, 65504, 65512, 65520, 65528, 0,
   32124, 31100, 30076, 29052, 28028, 27004, 25980, 24956, 23932, 22908, 21884, 20860, 19836, 18812, 17788, 16764,
   15996, 15484, 14972, 14460, 13948, 13436, 12924, 12412, 11900, 11388, 10876, 10364, 9852, 9340, 8828, 8316,
   7932, 7676, 7420, 7164, 6908, 6652, 6396, 6140, 5884, 5628, 5372, 5116, 4860, 4604, 4348, 4092,
   3900, 3772, 3644, 3516, 3388, 3260, 3132, 3004, 2876, 2748, 2620, 2492, 2364, 2236, 2108, 1980,
   1884, 1820, 1756, 1692, 1628, 1564, 1500, 1436, 1372, 1308, 1244, 1180, 1116, 1052, 988, 924,
   876, 844, 812, 780, 748, 716, 684, 652, 620, 588, 556, 524, 492, 460, 428, 396,
   372, 356, 340, 324, 308, 292, 276, 260, 244, 228, 212, 196, 180, 164, 148, 132,
   120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 0]

def float_bits(value: U32) -> F32:
  U32{word} = value
  F32{word}

# drwav_f32_to_s16: clamp to [-1, 1], add 1, scale by 32767.5 and truncate.
def f32.sample(+bits: U32) -> U32:
  +x = float_bits(bits)
  +c = Bool.pick(F32, (x < F32.neg(1.0) : F32), F32.neg(1.0), Bool.pick(F32, (x > 1.0 : F32), 1.0, x))
  ((F32.to_u32(F32.mul(F32.add(c, 1.0), 32767.5)) - 32768) .&. 65535 : U32)

def nan(+bits: U32) -> Bool:
  ((bits .&. 2147483647) > 2139095040 : U32)

# One sample of `width` bytes: u8 recentred, the top two bytes of 2..8-byte
# samples, zero above 8 bytes; float 32-bit; a-law and mu-law tables.
def sample(+kind: U32, +width: U32, +data: +List<U32>) -> U32:
  +top = (at(data, (width - 2 : U32)) .|. (at(data, (width - 1 : U32)) << 8n) : U32)
  Bool.pick(U32, U32.is_eq(kind, 6), at(alaw(), head(data)),
  Bool.pick(U32, U32.is_eq(kind, 7), at(mulaw(), head(data)),
  Bool.pick(U32, U32.is_eq(kind, 3), Bool.pick(U32, U32.is_eq(width, 4), f32.sample(u32(data, 0)), 0),
  Bool.pick(U32, U32.is_eq(width, 1), (((head(data) .^. 128) << 8n) .&. 65535 : U32),
  Bool.pick(U32, (width > 8 : U32), 0, top)))))

type Samples is Data:
  Samples{values: +List<U32>, nan: Bool}

def samples(n: Nat, +kind: U32, +width: U32, +data: +List<U32>, +acc: +List<U32>, +seen: Bool) -> Samples:
  match n:
    case 0n: Samples{List.reverse(&2, U32, acc), seen}
    case 1n+k:
      +here = List.take(&2, U32, data, U32.to_nat(width))
      samples(k, kind, width, List.drop(&2, U32, data, U32.to_nat(width)), Con{sample(kind, width, here), acc},
        seen || (U32.is_eq(kind, 3) && U32.is_eq(width, 4) && nan(u32(here, 0))))

# -----------------------------------------------------------------------------
# Validation after the walk, then the s16 read.

def decoded(+rate: U32, +channels: U32, +frames: U32, converted: Samples) -> Outcome:
  match converted:
    case Samples{_, True{}}: Invalid{C.BadByte{}}
    case Samples{values, False{}}: Decoded{rate, channels, frames, values}

def finished(+bytes: +List<U32>, +len: U32, +scan: Scan) -> Outcome:
  Scan{_, has_fmt, Fmt{ftag, +channels, +rate, +align, +bits, +sub}, has_data, +pos, +declared, failed, _} = scan
  +kind = Bool.pick(U32, U32.is_eq(ftag, 65534), sub, ftag)
  +size = Bool.pick(U32, (declared > (len - pos) : U32), (len - pos : U32), declared)
  +companded = U32.is_eq(kind, 6) || U32.is_eq(kind, 7)
  +raw_frame = Bool.pick(U32, U32.is_eq((bits .&. 7 : U32), 0), ((bits * channels) >> 3n : U32), align)
  +frame = Bool.pick(U32, companded && U32.is_ne(raw_frame, channels), 0, raw_frame)
  +usable = Bool.pick(U32, U32.is_eq(frame, 0), size, (size - size % frame : U32))
  +frames = Bool.pick(U32, U32.is_eq(frame, 0), 0, (usable / frame : U32))
  +width = Bool.pick(U32, U32.is_eq(channels, 0), 0, (frame / channels : U32))
  +header = failed || Bool.not(has_fmt && has_data) || U32.is_eq(rate, 0) || (rate > 384000 : U32) || U32.is_eq(channels, 0) || (channels > 256 : U32)
    || U32.is_eq(bits, 0) || (bits > 64 : U32) || U32.is_eq(align, 0) || U32.is_eq(frame, 0)
  # dr_wav reads no frames for these, leaving raylib's buffer uninitialized.
  +unread = Bool.not(U32.is_eq(kind, 1) || U32.is_eq(kind, 3) || companded) || U32.is_eq(width, 0) || U32.is_ne((frame % channels : U32), 0)
  +data = List.drop(&2, U32, bytes, U32.to_nat(pos))
  +converted = samples(U32.to_nat((frames * channels : U32)), kind, Bool.pick(U32, U32.is_eq(kind, 1) && U32.is_eq(bits, 16), 2, width), data, Nil{}, False{})
  Bool.pick(Outcome, header, Invalid{C.BadHeader{}},
  Bool.pick(Outcome, U32.is_eq(kind, 2) || U32.is_eq(kind, 17) || (U32.is_eq(kind, 3) && U32.is_eq(width, 8)), Unsupported{},
  Bool.pick(Outcome, U32.is_eq(frames, 0), Decoded{rate, channels, 0, []},
  Bool.pick(Outcome, unread, Invalid{C.BadStream{}}, decoded(rate, channels, frames, converted)))))

# LoadWaveFromMemory(".wav"): RIFF files; RIFX, Wave64, RF64 and AIFF
# containers are Unsupported (dr_wav reads them too).
def decode(+bytes: +List<U32>) -> Outcome:
  +len = U32.from_nat(C.byte_count(bytes, 0n))
  +riff = tag(bytes, 0, 82, 73, 70, 70)
  +other = tag(bytes, 0, 82, 73, 70, 88) || tag(bytes, 0, 114, 105, 102, 102) || tag(bytes, 0, 82, 70, 54, 52) || tag(bytes, 0, 70, 79, 82, 77)
  Bool.pick(Outcome, (len >= 4 : U32) && other, Unsupported{},
  Bool.pick(Outcome, Bool.not(riff) || (len < 12 : U32) || Bool.not(tag(bytes, 8, 87, 65, 86, 69)), Invalid{C.BadHeader{}},
    finished(bytes, len, chunks(U32.to_nat(((len >> 3n) + 2 : U32)), bytes, len, Scan{12, False{}, Fmt.empty(), False{}, 0, 0, False{}, False{}}))))
