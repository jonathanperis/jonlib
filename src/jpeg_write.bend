# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the JPEG writer in pinned stb_image_write.h
# (stbi_write_jpg_core at quality 90: 4:2:0, scaled quality 20). That writer
# is Jon Olick's public-domain jo_jpeg. MIT notice: LICENSES/stb-image.txt.
# See THIRD_PARTY_NOTICES.md.
#
# Each add and multiply is its own F32 operation, so the CPU lane (fp-contract
# off) and JavaScript Math.fround see the same rounding. Quantization and
# Huffman tables are the quality-20 values from that writer, stored as bits.
import Base

def bits(+word: U32) -> F32:
  U32{b} = word
  F32{b}

def k299() -> F32:
  bits(1050220167)

def k587() -> F32:
  bits(1058424226)

def k114() -> F32:
  bits(1038710997)

def k128() -> F32:
  bits(1124073472)

def ku1() -> F32:
  bits(3190606382)

def ku2() -> F32:
  bits(3198786281)

def k05() -> F32:
  bits(1056964608)

def kv2() -> F32:
  bits(3201719945)

def kv3() -> F32:
  bits(3181807067)

def k25() -> F32:
  bits(1048576000)

def c4() -> F32:
  bits(1060439283)

def c6() -> F32:
  bits(1053028117)

def c26() -> F32:
  bits(1057655764)

def c2p() -> F32:
  bits(1067924853)

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def nth(+values: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, values, U32.to_nat(index)))

def clamp(+base: U32, +offset: U32, +limit: U32) -> U32:
  +sum = (base + offset : U32)
  Bool.pick(U32, (sum < limit : U32), sum, (limit - 1 : U32))

def y.of(+r: F32, +g: F32, +b: F32) -> F32:
  +pr = (k299() * r : F32)
  +pg = (k587() * g : F32)
  +pb = (k114() * b : F32)
  +sum = (pr + pg : F32)
  ((sum + pb : F32) - k128() : F32)

def u.of(+r: F32, +g: F32, +b: F32) -> F32:
  +pr = (ku1() * r : F32)
  +pg = (ku2() * g : F32)
  +pb = (k05() * b : F32)
  +sum = (pr + pg : F32)
  (sum + pb : F32)

def v.of(+r: F32, +g: F32, +b: F32) -> F32:
  +pr = (k05() * r : F32)
  +pg = (kv2() * g : F32)
  +pb = (kv3() * b : F32)
  +sum = (pr + pg : F32)
  (sum + pb : F32)

type Writer is Data:
  Writer{count: U32, buffer: U32, bytes: +List<U32>}

def emit.stuff(marker: Bool, +byte: U32, bytes: +List<U32>) -> +List<U32>:
  match marker:
    case True{}: Con{0, Con{byte, bytes}}
    case False{}: Con{byte, bytes}

def emit.byte(+buffer: U32, bytes: +List<U32>) -> +List<U32>:
  +byte = ((buffer >> 16n) .&. 255 : U32)
  emit.stuff(U32.is_eq(byte, 255), byte, bytes)

# stb's bit packer: codes enter at bit 24 and whole bytes leave high-first.
# A 0xFF data byte is followed by a stuffed 0x00.
def emit(n: Nat, go: Bool, +count: U32, +buffer: U32, bytes: +List<U32>) -> Writer:
  match n go:
    case 0n _: Writer{count, buffer, bytes}
    case _ False{}: Writer{count, buffer, bytes}
    case 1n+rest True{}:
      +next = (count - 8 : U32)
      emit(rest, (next >= 8 : U32), next, (buffer << 8n : U32), emit.byte(buffer, bytes))

def write.bits(writer: Writer, +code: U32, +len: U32) -> Writer:
  Writer{+count, +buffer, bytes} = writer
  +next = (count + len : U32)
  +amount = (24 - next : U32)
  +merged = (buffer .|. (code << U32.to_nat(amount) : U32) : U32)
  emit(5n, (next >= 8 : U32), next, merged, bytes)

def write.pair(writer: Writer, pair: U32 & U32) -> Writer:
  (+code, +len) = pair
  write.bits(writer, code, len)

def ht(+table: +List<U32>, +index: U32) -> U32 & U32:
  +at = (index * 2 : U32)
  (nth(table, at), nth(table, (at + 1 : U32)))

def write.ht(writer: Writer, +table: +List<U32>, +index: U32) -> Writer:
  write.pair(writer, ht(table, index))

def calc.length(n: Nat, go: Bool, +tmp: U32, +count: U32) -> U32:
  match n go:
    case 0n _: count
    case _ False{}: count
    case 1n+rest True{}:
      +next = (tmp >> 1n : U32)
      calc.length(rest, (next > 0 : U32), next, (count + 1 : U32))

# stb calcBits on a two's-complement word. Category 0 is not requested.
def calc.bits(+val: U32) -> U32 & U32:
  +neg = (val >= 2147483648 : U32)
  +tmp = Bool.pick(U32, neg, (0 - val : U32), val)
  +adjusted = Bool.pick(U32, neg, (val - 1 : U32), val)
  +shifted = (tmp >> 1n : U32)
  +len = calc.length(32n, (shifted > 0 : U32), shifted, 1)
  +mask = ((1 << U32.to_nat(len) : U32) - 1 : U32)
  ((adjusted .&. mask : U32), len)

# (int)(v < 0 ? v - 0.5 : v + 0.5), truncating toward zero.
def quantize(+v: F32) -> U32:
  +neg = (v < 0.0 : F32)
  +shifted = Bool.pick(F32, neg, (v - k05() : F32), (v + k05() : F32))
  +mag = F32.to_u32(F32.floor(F32.abs(shifted)))
  Bool.pick(U32, neg, (0 - mag : U32), mag)

type Oct is Data:
  Oct{a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, g: F32, h: F32}

def oct.zero() -> Oct:
  Oct{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

def oct.put.at(k: U32, +value: F32, a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, g: F32, h: F32) -> Oct:
  match k a b c d e f g h:
    case 0 _ b c d e f g h: Oct{value, b, c, d, e, f, g, h}
    case 1 a _ c d e f g h: Oct{a, value, c, d, e, f, g, h}
    case 2 a b _ d e f g h: Oct{a, b, value, d, e, f, g, h}
    case 3 a b c _ e f g h: Oct{a, b, c, value, e, f, g, h}
    case 4 a b c d _ f g h: Oct{a, b, c, d, value, f, g, h}
    case 5 a b c d e _ g h: Oct{a, b, c, d, e, value, g, h}
    case 6 a b c d e f _ h: Oct{a, b, c, d, e, f, value, h}
    case _ a b c d e f g _: Oct{a, b, c, d, e, f, g, value}

def oct.put(+k: U32, +value: F32, oct: Oct) -> Oct:
  Oct{a, b, c, d, e, f, g, h} = oct
  oct.put.at(k, value, a, b, c, d, e, f, g, h)

def oct.get.at(k: U32, a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, g: F32, h: F32) -> Oct & F32:
  match k a b c d e f g h:
    case 0 +a b c d e f g h: (Oct{a, b, c, d, e, f, g, h}, a)
    case 1 a +b c d e f g h: (Oct{a, b, c, d, e, f, g, h}, b)
    case 2 a b +c d e f g h: (Oct{a, b, c, d, e, f, g, h}, c)
    case 3 a b c +d e f g h: (Oct{a, b, c, d, e, f, g, h}, d)
    case 4 a b c d +e f g h: (Oct{a, b, c, d, e, f, g, h}, e)
    case 5 a b c d e +f g h: (Oct{a, b, c, d, e, f, g, h}, f)
    case 6 a b c d e f +g h: (Oct{a, b, c, d, e, f, g, h}, g)
    case _ a b c d e f g +h: (Oct{a, b, c, d, e, f, g, h}, h)

def oct.get(+k: U32, oct: Oct) -> Oct & F32:
  Oct{a, b, c, d, e, f, g, h} = oct
  oct.get.at(k, a, b, c, d, e, f, g, h)

def load.got(+k: U32, oct: Oct, read: Array<F32> & F32) -> Array<F32> & Oct:
  (plane, +value) = read
  (plane, oct.put(k, value, oct))

def load.one(+k: U32, +index: U32, plane: Array<F32>, oct: Oct) -> Array<F32> & Oct:
  load.got(k, oct, Array.get(F32, plane, index))

def load.step(n: Nat, +k: U32, +index: U32, +stride: U32, state: Array<F32> & Oct) -> Array<F32> & Oct:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{plane, oct}: load.step(rest, (k + 1 : U32), (index + stride : U32), stride, load.one(k, index, plane, oct))

def load.full(+index: U32, +stride: U32, plane: Array<F32>) -> Array<F32> & Oct:
  load.step(8n, 0, index, stride, (plane, oct.zero()))

def store.set(+index: U32, plane: Array<F32>, got: Oct & F32) -> Array<F32> & Oct:
  (oct, +value) = got
  (Array.set(F32, plane, index, value), oct)

def store.one(+k: U32, +index: U32, plane: Array<F32>, oct: Oct) -> Array<F32> & Oct:
  store.set(index, plane, oct.get(k, oct))

def store.step(n: Nat, +k: U32, +index: U32, +stride: U32, state: Array<F32> & Oct) -> Array<F32> & Oct:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{plane, oct}: store.step(rest, (k + 1 : U32), (index + stride : U32), stride, store.one(k, index, plane, oct))

def store.done(state: Array<F32> & Oct) -> Array<F32>:
  (plane, _) = state
  plane

# AAN DCT, one vector. The forward transform matches stb's in-place float kernel.
def dct(oct: Oct) -> Oct:
  Oct{+d0, +d1, +d2, +d3, +d4, +d5, +d6, +d7} = oct
  +t0 = (d0 + d7 : F32)
  +t7 = (d0 - d7 : F32)
  +t1 = (d1 + d6 : F32)
  +t6 = (d1 - d6 : F32)
  +t2 = (d2 + d5 : F32)
  +t5 = (d2 - d5 : F32)
  +t3 = (d3 + d4 : F32)
  +t4 = (d3 - d4 : F32)
  +e10 = (t0 + t3 : F32)
  +e13 = (t0 - t3 : F32)
  +e11 = (t1 + t2 : F32)
  +e12 = (t1 - t2 : F32)
  +o0 = (e10 + e11 : F32)
  +o4 = (e10 - e11 : F32)
  +z1 = ((e12 + e13 : F32) * c4() : F32)
  +o2 = (e13 + z1 : F32)
  +o6 = (e13 - z1 : F32)
  +o10 = (t4 + t5 : F32)
  +o11 = (t5 + t6 : F32)
  +o12 = (t6 + t7 : F32)
  +z5 = ((o10 - o12 : F32) * c6() : F32)
  +z2 = ((o10 * c26() : F32) + z5 : F32)
  +z4 = ((o12 * c2p() : F32) + z5 : F32)
  +z3 = (o11 * c4() : F32)
  +z11 = (t7 + z3 : F32)
  +z13 = (t7 - z3 : F32)
  Oct{o0, (z11 + z4 : F32), o2, (z13 - z2 : F32), o4, (z13 + z2 : F32), o6, (z11 - z4 : F32)}

def dct.run(state: Array<F32> & Oct) -> Array<F32> & Oct:
  (plane, oct) = state
  (plane, dct(oct))

def dct.apply(+index: U32, +stride: U32, plane: Array<F32>) -> Array<F32>:
  store.done(store.step(8n, 0, index, stride, dct.run(load.full(index, stride, plane))))

def dcts(n: Nat, +k: U32, +stride: U32, +step: U32, plane: Array<F32>) -> Array<F32>:
  match n:
    case 0n: plane
    case 1n+rest: dcts(rest, (k + 1 : U32), stride, step, dct.apply((k * step : U32), stride, plane))

def dct.all(plane: Array<F32>) -> Array<F32>:
  dcts(8n, 0, 8, 1, dcts(8n, 0, 1, 8, plane))

def blank64f() -> Array<F32>:
  Array.new(F32, 6n, 0.0)

def blank256f() -> Array<F32>:
  Array.new(F32, 8n, 0.0)

def blank64u() -> Array<U32>:
  Array.new(U32, 6n, 0)

def window.got(+j: U32, out: Array<F32>, read: Array<F32> & F32) -> Array<F32> & Array<F32>:
  (src, +value) = read
  (src, Array.set(F32, out, j, value))

def window.put(+j: U32, +origin: U32, +stride: U32, src: Array<F32>, out: Array<F32>) -> Array<F32> & Array<F32>:
  +row = (j / 8 : U32)
  +col = (j % 8 : U32)
  +at = ((origin + (row * stride : U32) : U32) + col : U32)
  window.got(j, out, Array.get(F32, src, at))

def window.fill(n: Nat, +j: U32, +origin: U32, +stride: U32, state: Array<F32> & Array<F32>) -> Array<F32> & Array<F32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{src, out}: window.fill(rest, (j + 1 : U32), origin, stride, window.put(j, origin, stride, src, out))

def window.of(+origin: U32, +stride: U32, plane: Array<F32>) -> Array<F32> & Array<F32>:
  window.fill(64n, 0, origin, stride, (plane, blank64f()))

def quant.got(+j: U32, +fdtbl: +List<U32>, +zig: +List<U32>, du: Array<U32>, read: Array<F32> & F32) -> Array<F32> & Array<U32>:
  (plane, +sample) = read
  +scale = bits(nth(fdtbl, j))
  +value = (sample * scale : F32)
  +at = nth(zig, j)
  (plane, Array.set(U32, du, at, quantize(value)))

def quant.one(+j: U32, plane: Array<F32>, du: Array<U32>, +fdtbl: +List<U32>, +zig: +List<U32>) -> Array<F32> & Array<U32>:
  quant.got(j, fdtbl, zig, du, Array.get(F32, plane, j))

def quant.run(n: Nat, +j: U32, state: Array<F32> & Array<U32>, +fdtbl: +List<U32>, +zig: +List<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, du}: du
    case 1n+rest Tuple{plane, du}: quant.run(rest, (j + 1 : U32), quant.one(j, plane, du, fdtbl, zig), fdtbl, zig)

type Scan is Type:
  Scan{du: Array<U32>, go: Bool, index: U32, end: U32}

def end.got(+index: U32, read: Array<U32> & U32) -> Scan:
  (du, +value) = read
  +zero = U32.is_eq(value, 0)
  Scan{du, zero, Bool.pick(U32, zero, (index - 1 : U32), index), 0}

def end.at(live: Bool, +index: U32, du: Array<U32>) -> Scan:
  match live:
    case False{}: Scan{du, False{}, index, 0}
    case True{}: end.got(index, Array.get(U32, du, index))

def end.read(scan: Scan) -> Scan:
  Scan{du, _, +index, _} = scan
  end.at((index > 0 : U32), index, du)

def end.scan(n: Nat, scan: Scan) -> Scan:
  match n scan:
    case 0n _: scan
    case _ Scan{du, False{}, index, end}: Scan{du, False{}, index, end}
    case 1n+rest Scan{du, True{}, index, end}: end.scan(rest, end.read(Scan{du, True{}, index, end}))

def skip.got(+index: U32, +end: U32, read: Array<U32> & U32) -> Scan:
  (du, +value) = read
  +zero = U32.is_eq(value, 0)
  Scan{du, zero, Bool.pick(U32, zero, (index + 1 : U32), index), end}

def skip.at(live: Bool, +index: U32, +end: U32, du: Array<U32>) -> Scan:
  match live:
    case False{}: Scan{du, False{}, index, end}
    case True{}: skip.got(index, end, Array.get(U32, du, index))

def skip.read(scan: Scan) -> Scan:
  Scan{du, _, +index, +end} = scan
  skip.at((index <= end : U32), index, end, du)

def skip.scan(n: Nat, scan: Scan) -> Scan:
  match n scan:
    case 0n _: scan
    case _ Scan{du, False{}, index, end}: Scan{du, False{}, index, end}
    case 1n+rest Scan{du, True{}, index, end}: skip.scan(rest, skip.read(Scan{du, True{}, index, end}))

def marks(n: Nat, writer: Writer, +code: U32, +len: U32) -> Writer:
  match n:
    case 0n: writer
    case 1n+rest: marks(rest, write.bits(writer, code, len), code, len)

def dc.mag(writer: Writer, +htdc: +List<U32>, bits: U32 & U32) -> Writer:
  (+mag, +cat) = bits
  write.pair(write.ht(writer, htdc, cat), (mag, cat))

def dc.which(zero: Bool, writer: Writer, +diff: U32, +htdc: +List<U32>) -> Writer:
  match zero:
    case True{}: write.ht(writer, htdc, 0)
    case False{}: dc.mag(writer, htdc, calc.bits(diff))

type Ac is Type:
  Ac{go: Bool, index: U32, end: U32, writer: Writer, du: Array<U32>}

def ac.encoded(+found: U32, +end: U32, +nr: U32, +htac: +List<U32>, writer: Writer, du: Array<U32>, bits: U32 & U32) -> Ac:
  (+mag, +cat) = bits
  +index = ((nr << 4n) + cat : U32)
  +next = (found + 1 : U32)
  Ac{(next <= end : U32), next, end, write.pair(write.ht(writer, htac, index), (mag, cat)), du}

def ac.coeff(+found: U32, +end: U32, +nr: U32, +htac: +List<U32>, writer: Writer, read: Array<U32> & U32) -> Ac:
  (du, +value) = read
  ac.encoded(found, end, nr, htac, writer, du, calc.bits(value))

def ac.value(+found: U32, +end: U32, +nr: U32, +htac: +List<U32>, writer: Writer, du: Array<U32>) -> Ac:
  ac.coeff(found, end, nr, htac, writer, Array.get(U32, du, found))

def ac.marked(+found: U32, +end: U32, +nr: U32, +htac: +List<U32>, writer: Writer, du: Array<U32>, pair: U32 & U32) -> Ac:
  (+code, +len) = pair
  +lng = (nr >> 4n : U32)
  ac.value(found, end, (nr .&. 15 : U32), htac, marks(U32.to_nat(lng), writer, code, len), du)

def ac.wide(wide: Bool, +found: U32, +end: U32, +nr: U32, +htac: +List<U32>, writer: Writer, du: Array<U32>) -> Ac:
  match wide:
    case False{}: ac.value(found, end, nr, htac, writer, du)
    case True{}: ac.marked(found, end, nr, htac, writer, du, ht(htac, 240))

def ac.found(+start: U32, +end: U32, +htac: +List<U32>, writer: Writer, scan: Scan) -> Ac:
  Scan{du, _, +found, _} = scan
  +nr = (found - start : U32)
  ac.wide((nr >= 16 : U32), found, end, nr, htac, writer, du)

def ac.one(+start: U32, +end: U32, writer: Writer, du: Array<U32>, +htac: +List<U32>) -> Ac:
  ac.found(start, end, htac, writer, skip.scan(64n, Scan{du, True{}, start, end}))

def ac.run(n: Nat, state: Ac, +htac: +List<U32>) -> Writer & Array<U32>:
  match n state:
    case 0n Ac{_, _, _, writer, du}: (writer, du)
    case _ Ac{False{}, _, _, writer, du}: (writer, du)
    case 1n+rest Ac{True{}, +index, +end, writer, du}: ac.run(rest, ac.one(index, end, writer, du, htac), htac)

def process.kept(+du0: U32, plane: Array<F32>, writer: Writer, read: Array<U32> & U32) -> Array<F32> & U32 & Writer:
  (_, _) = read
  (plane, du0, writer)

def process.keep(+du0: U32, plane: Array<F32>, writer: Writer, du: Array<U32>) -> Array<F32> & U32 & Writer:
  process.kept(du0, plane, writer, Array.get(U32, du, 0))

def process.eob(last: Bool, +du0: U32, +htac: +List<U32>, plane: Array<F32>, writer: Writer, du: Array<U32>) -> Array<F32> & U32 & Writer:
  match last:
    case True{}: process.keep(du0, plane, writer, du)
    case False{}: process.keep(du0, plane, write.ht(writer, htac, 0), du)

def process.ran(+du0: U32, +end: U32, +htac: +List<U32>, plane: Array<F32>, state: Writer & Array<U32>) -> Array<F32> & U32 & Writer:
  (writer, du) = state
  process.eob(U32.is_eq(end, 63), du0, htac, plane, writer, du)

def process.ac(none: Bool, +du0: U32, +end: U32, +htac: +List<U32>, plane: Array<F32>, du: Array<U32>, writer: Writer) -> Array<F32> & U32 & Writer:
  match none:
    case True{}: process.keep(du0, plane, write.ht(writer, htac, 0), du)
    case False{}: process.ran(du0, end, htac, plane, ac.run(64n, Ac{True{}, 1, end, writer, du}, htac))

def process.coded(+du0: U32, +htac: +List<U32>, plane: Array<F32>, scan: Scan, writer: Writer) -> Array<F32> & U32 & Writer:
  Scan{du, _, +end, _} = scan
  process.ac(U32.is_eq(end, 0), du0, end, htac, plane, du, writer)

def process.diff(+dc: U32, +htdc: +List<U32>, +htac: +List<U32>, plane: Array<F32>, writer: Writer, read: Array<U32> & U32) -> Array<F32> & U32 & Writer:
  (du, +du0) = read
  +diff = (du0 - dc : U32)
  process.coded(du0, htac, plane, end.scan(64n, Scan{du, True{}, 63, 0}), dc.which(U32.is_eq(diff, 0), writer, diff, htdc))

def process.du0(+dc: U32, +htdc: +List<U32>, +htac: +List<U32>, plane: Array<F32>, writer: Writer, du: Array<U32>) -> Array<F32> & U32 & Writer:
  process.diff(dc, htdc, htac, plane, writer, Array.get(U32, du, 0))

def process.quantized(+dc: U32, +htdc: +List<U32>, +htac: +List<U32>, plane: Array<F32>, writer: Writer, du: Array<U32>) -> Array<F32> & U32 & Writer:
  process.du0(dc, htdc, htac, plane, writer, du)

def process.split(+fdtbl: +List<U32>, +dc: U32, +htdc: +List<U32>, +htac: +List<U32>, +zig: +List<U32>, writer: Writer, both: Array<F32> & Array<F32>) -> Array<F32> & U32 & Writer:
  (plane, window) = both
  process.quantized(dc, htdc, htac, plane, writer, quant.run(64n, 0, (dct.all(window), blank64u()), fdtbl, zig))

def process.from(+origin: U32, +stride: U32, +fdtbl: +List<U32>, +dc: U32, +htdc: +List<U32>, +htac: +List<U32>, +zig: +List<U32>, writer: Writer, plane: Array<F32>) -> Array<F32> & U32 & Writer:
  process.split(fdtbl, dc, htdc, htac, zig, writer, window.of(origin, stride, plane))

type Pass is Type:
  Pass{plane: Array<F32>, dc: U32, writer: Writer}

def pass.of(state: Array<F32> & U32 & Writer) -> Pass:
  (plane, +dc, writer) = state
  Pass{plane, dc, writer}

def y.next(+origin: U32, pass: Pass, +fdtbl: +List<U32>, +htdc: +List<U32>, +htac: +List<U32>, +zig: +List<U32>) -> Pass:
  Pass{plane, +dc, writer} = pass
  pass.of(process.from(origin, 16, fdtbl, dc, htdc, htac, zig, writer, plane))

def y4(plane: Array<F32>, +dc: U32, writer: Writer, +fdy: +List<U32>, +ydc: +List<U32>, +yac: +List<U32>, +zig: +List<U32>) -> Pass:
  y.next(136, y.next(128, y.next(8, y.next(0, Pass{plane, dc, writer}, fdy, ydc, yac, zig), fdy, ydc, yac, zig), fdy, ydc, yac, zig), fdy, ydc, yac, zig)

def drop.got(keep: Array<F32>, read: Array<F32> & F32) -> Array<F32>:
  (_, _) = read
  keep

def drop.array(drop: Array<F32>, keep: Array<F32>) -> Array<F32>:
  drop.got(keep, Array.get(F32, drop, 0))

def sub.got(+pos: U32, out: Array<F32>, read: Array<F32> & F32) -> Array<F32> & Array<F32>:
  (src, +value) = read
  (src, Array.set(F32, out, pos, value))

def sub.d(+a: F32, +b: F32, +c: F32, read: Array<F32> & F32) -> Array<F32> & F32:
  (src, +d) = read
  +s0 = (a + b : F32)
  +s1 = (s0 + c : F32)
  +s2 = (s1 + d : F32)
  (src, (s2 * k25() : F32))

def sub.c(+j: U32, +a: F32, +b: F32, read: Array<F32> & F32) -> Array<F32> & F32:
  (src, +c) = read
  sub.d(a, b, c, Array.get(F32, src, (j + 17 : U32)))

def sub.b(+j: U32, +a: F32, read: Array<F32> & F32) -> Array<F32> & F32:
  (src, +b) = read
  sub.c(j, a, b, Array.get(F32, src, (j + 16 : U32)))

def sub.a(+j: U32, read: Array<F32> & F32) -> Array<F32> & F32:
  (src, +a) = read
  sub.b(j, a, Array.get(F32, src, (j + 1 : U32)))

def sub.avg(+j: U32, src: Array<F32>) -> Array<F32> & F32:
  sub.a(j, Array.get(F32, src, j))

def sub.one(+pos: U32, src: Array<F32>, out: Array<F32>) -> Array<F32> & Array<F32>:
  +row = (pos / 8 : U32)
  +col = (pos % 8 : U32)
  +j = ((row * 32 : U32) + (col * 2 : U32) : U32)
  sub.got(pos, out, sub.avg(j, src))

def sub.fill(n: Nat, +pos: U32, state: Array<F32> & Array<F32>) -> Array<F32> & Array<F32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{src, out}: sub.fill(rest, (pos + 1 : U32), sub.one(pos, src, out))

def sub.finish(state: Array<F32> & Array<F32>) -> Array<F32>:
  (src, out) = state
  drop.array(src, out)

def sub.run(src: Array<F32>) -> Array<F32>:
  sub.finish(sub.fill(64n, 0, (src, blank64f())))

type Planes is Type:
  Planes{y: Array<F32>, u: Array<F32>, v: Array<F32>}

def paint.store(+pos: U32, planes: Planes, +yy: F32, +uu: F32, +vv: F32) -> Planes:
  Planes{y, u, v} = planes
  Planes{Array.set(F32, y, pos, yy), Array.set(F32, u, pos, uu), Array.set(F32, v, pos, vv)}

def paint.one(+pos: U32, +y0: U32, +x0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, planes: Planes) -> Planes:
  +row = (pos / 16 : U32)
  +col = (pos % 16 : U32)
  +yy = clamp(y0, row, height)
  +xx = clamp(x0, col, width)
  +pix = ((yy * width : U32) + xx : U32)
  +p = (pix * comp : U32)
  +gs = Bool.pick(U32, (comp > 2 : U32), 1, 0)
  +bs = Bool.pick(U32, (comp > 2 : U32), 2, 0)
  +r = U32.to_f32(nth(bytes, p))
  +g = U32.to_f32(nth(bytes, (p + gs : U32)))
  +b = U32.to_f32(nth(bytes, (p + bs : U32)))
  paint.store(pos, planes, y.of(r, g, b), u.of(r, g, b), v.of(r, g, b))

def paint(n: Nat, +pos: U32, +y0: U32, +x0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, planes: Planes) -> Planes:
  match n:
    case 0n: planes
    case 1n+rest: paint(rest, (pos + 1 : U32), y0, x0, width, height, comp, bytes, paint.one(pos, y0, x0, width, height, comp, bytes, planes))

def paint.run(+y0: U32, +x0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>) -> Planes:
  paint(256n, 0, y0, x0, width, height, comp, bytes, Planes{blank256f(), blank256f(), blank256f()})

type Tables is Data:
  Tables{fdy: +List<U32>, fduv: +List<U32>, ydc: +List<U32>, yac: +List<U32>, uvdc: +List<U32>, uvac: +List<U32>, zig: +List<U32>}

type Codes is Data:
  Codes{dy: U32, du: U32, dv: U32, writer: Writer}

type Step is Data:
  Step{tables: Tables, codes: Codes}

def block.end(+dy: U32, +du: U32, +dv: U32, writer: Writer, tables: Tables, read: Array<F32> & F32) -> Step:
  (_, _) = read
  Step{tables, Codes{dy, du, dv, writer}}

def block.finish(+dy: U32, +du: U32, +dv: U32, writer: Writer, tables: Tables, plane: Array<F32>) -> Step:
  block.end(dy, du, dv, writer, tables, Array.get(F32, plane, 0))

def block.afterv(+dy: U32, +dcu: U32, tables: Tables, state: Array<F32> & U32 & Writer) -> Step:
  (plane, +dcv, writer) = state
  block.finish(dy, dcu, dcv, writer, tables, plane)

def block.afteru(+dy: U32, +dcv: U32, tables: Tables, +fduv: +List<U32>, +uvdc: +List<U32>, +uvac: +List<U32>, +zig: +List<U32>, v: Array<F32>, state: Array<F32> & U32 & Writer) -> Step:
  (plane, +dcu, writer) = state
  block.afterv(dy, dcu, tables, process.from(0, 8, fduv, dcv, uvdc, uvac, zig, writer, drop.array(plane, sub.run(v))))

def block.u(+dy: U32, +dcu: U32, +dcv: U32, tables: Tables, +fduv: +List<U32>, +uvdc: +List<U32>, +uvac: +List<U32>, +zig: +List<U32>, writer: Writer, v: Array<F32>, usub: Array<F32>) -> Step:
  block.afteru(dy, dcv, tables, fduv, uvdc, uvac, zig, v, process.from(0, 8, fduv, dcu, uvdc, uvac, zig, writer, usub))

def block.y.pass(+dcu: U32, +dcv: U32, +fdy: +List<U32>, +fduv: +List<U32>, +ydc: +List<U32>, +yac: +List<U32>, +uvdc: +List<U32>, +uvac: +List<U32>, +zig: +List<U32>, u: Array<F32>, v: Array<F32>, pass: Pass) -> Step:
  Pass{plane, +dy, writer} = pass
  block.u(dy, dcu, dcv, Tables{fdy, fduv, ydc, yac, uvdc, uvac, zig}, fduv, uvdc, uvac, zig, writer, v, drop.array(plane, sub.run(u)))

def block.y(+dcu: U32, +dcv: U32, tables: Tables, u: Array<F32>, v: Array<F32>, pass: Pass) -> Step:
  Tables{+fdy, +fduv, +ydc, +yac, +uvdc, +uvac, +zig} = tables
  block.y.pass(dcu, dcv, fdy, fduv, ydc, yac, uvdc, uvac, zig, u, v, pass)

def block.from(+dcu: U32, +dcv: U32, tables: Tables, +fdy: +List<U32>, +ydc: +List<U32>, +yac: +List<U32>, +zig: +List<U32>, +dy: U32, writer: Writer, planes: Planes) -> Step:
  Planes{y, u, v} = planes
  block.y(dcu, dcv, tables, u, v, y4(y, dy, writer, fdy, ydc, yac, zig))

def block.codes.open(+x: U32, +y0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, +fdy: +List<U32>, +fduv: +List<U32>, +ydc: +List<U32>, +yac: +List<U32>, +uvdc: +List<U32>, +uvac: +List<U32>, +zig: +List<U32>, codes: Codes) -> Step:
  Codes{+dy, +dcu, +dcv, writer} = codes
  block.from(dcu, dcv, Tables{fdy, fduv, ydc, yac, uvdc, uvac, zig}, fdy, ydc, yac, zig, dy, writer, paint.run(y0, x, width, height, comp, bytes))

def block.codes(+x: U32, +y0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, tables: Tables, codes: Codes) -> Step:
  Tables{+fdy, +fduv, +ydc, +yac, +uvdc, +uvac, +zig} = tables
  block.codes.open(x, y0, width, height, comp, bytes, fdy, fduv, ydc, yac, uvdc, uvac, zig, codes)

def block.open(+x: U32, +y0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, step: Step) -> Step:
  Step{tables, codes} = step
  block.codes(x, y0, width, height, comp, bytes, tables, codes)

def tiles(+span: U32) -> Nat:
  U32.to_nat(((span + 15) / 16 : U32))

def cols(n: Nat, +x: U32, +y0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, step: Step) -> Step:
  match n step:
    case 0n _: step
    case 1n+rest Step{tables, codes}: cols(rest, (x + 16 : U32), y0, width, height, comp, bytes, block.open(x, y0, width, height, comp, bytes, Step{tables, codes}))

def rows(n: Nat, +y0: U32, +width: U32, +height: U32, +comp: U32, +bytes: +List<U32>, step: Step) -> Step:
  match n step:
    case 0n _: step
    case 1n+rest Step{tables, codes}: rows(rest, (y0 + 16 : U32), width, height, comp, bytes, cols(tiles(width), 0, y0, width, height, comp, bytes, Step{tables, codes}))
def header.prefix() -> +List<U32>:
  [
    255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1,
    0, 1, 0, 0, 255, 219, 0, 132, 0, 3, 2, 2, 3, 2, 2, 3,
    3, 3, 3, 4, 3, 3, 4, 5, 8, 5, 5, 4, 4, 5, 10, 7,
    7, 6, 8, 12, 10, 12, 12, 11, 10, 11, 11, 13, 14, 18, 16, 13,
    14, 17, 14, 11, 11, 16, 22, 16, 17, 19, 20, 21, 21, 21, 12, 15,
    23, 24, 22, 20, 24, 18, 20, 21, 20, 1, 3, 4, 4, 5, 4, 5,
    9, 5, 5, 9, 20, 13, 11, 13, 20, 20, 20, 20, 20, 20, 20, 20,
    20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
    20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
    20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 255, 192, 0, 17, 8
  ]

def header.suffix() -> +List<U32>:
  [
    3, 1, 34, 0, 2, 17, 1, 3, 17, 1, 255, 196, 1, 162, 0, 0,
    1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 16, 0, 2, 1, 3,
    3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125, 1, 2, 3, 0,
    4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7, 34, 113, 20, 50,
    129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114,
    130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40, 41, 42, 52, 53,
    54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85,
    86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117,
    118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148,
    149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178,
    179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201,
    202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226, 227, 228, 229, 230,
    231, 232, 233, 234, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 1, 0,
    3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 17, 0, 2, 1, 2,
    4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119, 0, 1, 2, 3,
    17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50, 129,
    8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114, 209,
    10, 22, 36, 52, 225, 37, 241, 23, 24, 25, 26, 38, 39, 40, 41, 42,
    53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84,
    85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116,
    117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136, 137, 138, 146,
    147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169,
    170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199,
    200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 226, 227, 228, 229,
    230, 231, 232, 233, 234, 242, 243, 244, 245, 246, 247, 248, 249, 250, 255, 218,
    0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0
  ]

def ydc.table() -> +List<U32>:
  [
    0, 2, 2, 3, 3, 3, 4, 3, 5, 3, 6, 3, 14, 4, 30, 5,
    62, 6, 126, 7, 254, 8, 510, 9, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]

def uvdc.table() -> +List<U32>:
  [
    0, 2, 1, 2, 2, 2, 6, 3, 14, 4, 30, 5, 62, 6, 126, 7,
    254, 8, 510, 9, 1022, 10, 2046, 11, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]

def yac.table() -> +List<U32>:
  [
    10, 4, 0, 2, 1, 2, 4, 3, 11, 4, 26, 5, 120, 7, 248, 8,
    1014, 10, 65410, 16, 65411, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 12, 4, 27, 5, 121, 7, 502, 9, 2038, 11, 65412, 16, 65413, 16,
    65414, 16, 65415, 16, 65416, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 28, 5, 249, 8, 1015, 10, 4084, 12, 65417, 16, 65418, 16, 65419, 16,
    65420, 16, 65421, 16, 65422, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 58, 6, 503, 9, 4085, 12, 65423, 16, 65424, 16, 65425, 16, 65426, 16,
    65427, 16, 65428, 16, 65429, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 59, 6, 1016, 10, 65430, 16, 65431, 16, 65432, 16, 65433, 16, 65434, 16,
    65435, 16, 65436, 16, 65437, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 122, 7, 2039, 11, 65438, 16, 65439, 16, 65440, 16, 65441, 16, 65442, 16,
    65443, 16, 65444, 16, 65445, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 123, 7, 4086, 12, 65446, 16, 65447, 16, 65448, 16, 65449, 16, 65450, 16,
    65451, 16, 65452, 16, 65453, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 250, 8, 4087, 12, 65454, 16, 65455, 16, 65456, 16, 65457, 16, 65458, 16,
    65459, 16, 65460, 16, 65461, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 504, 9, 32704, 15, 65462, 16, 65463, 16, 65464, 16, 65465, 16, 65466, 16,
    65467, 16, 65468, 16, 65469, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 505, 9, 65470, 16, 65471, 16, 65472, 16, 65473, 16, 65474, 16, 65475, 16,
    65476, 16, 65477, 16, 65478, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 506, 9, 65479, 16, 65480, 16, 65481, 16, 65482, 16, 65483, 16, 65484, 16,
    65485, 16, 65486, 16, 65487, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 1017, 10, 65488, 16, 65489, 16, 65490, 16, 65491, 16, 65492, 16, 65493, 16,
    65494, 16, 65495, 16, 65496, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 1018, 10, 65497, 16, 65498, 16, 65499, 16, 65500, 16, 65501, 16, 65502, 16,
    65503, 16, 65504, 16, 65505, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 2040, 11, 65506, 16, 65507, 16, 65508, 16, 65509, 16, 65510, 16, 65511, 16,
    65512, 16, 65513, 16, 65514, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 65515, 16, 65516, 16, 65517, 16, 65518, 16, 65519, 16, 65520, 16, 65521, 16,
    65522, 16, 65523, 16, 65524, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    2041, 11, 65525, 16, 65526, 16, 65527, 16, 65528, 16, 65529, 16, 65530, 16, 65531, 16,
    65532, 16, 65533, 16, 65534, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]

def uvac.table() -> +List<U32>:
  [
    0, 2, 1, 2, 4, 3, 10, 4, 24, 5, 25, 5, 56, 6, 120, 7,
    500, 9, 1014, 10, 4084, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 11, 4, 57, 6, 246, 8, 501, 9, 2038, 11, 4085, 12, 65416, 16,
    65417, 16, 65418, 16, 65419, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 26, 5, 247, 8, 1015, 10, 4086, 12, 32706, 15, 65420, 16, 65421, 16,
    65422, 16, 65423, 16, 65424, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 27, 5, 248, 8, 1016, 10, 4087, 12, 65425, 16, 65426, 16, 65427, 16,
    65428, 16, 65429, 16, 65430, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 58, 6, 502, 9, 65431, 16, 65432, 16, 65433, 16, 65434, 16, 65435, 16,
    65436, 16, 65437, 16, 65438, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 59, 6, 1017, 10, 65439, 16, 65440, 16, 65441, 16, 65442, 16, 65443, 16,
    65444, 16, 65445, 16, 65446, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 121, 7, 2039, 11, 65447, 16, 65448, 16, 65449, 16, 65450, 16, 65451, 16,
    65452, 16, 65453, 16, 65454, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 122, 7, 2040, 11, 65455, 16, 65456, 16, 65457, 16, 65458, 16, 65459, 16,
    65460, 16, 65461, 16, 65462, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 249, 8, 65463, 16, 65464, 16, 65465, 16, 65466, 16, 65467, 16, 65468, 16,
    65469, 16, 65470, 16, 65471, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 503, 9, 65472, 16, 65473, 16, 65474, 16, 65475, 16, 65476, 16, 65477, 16,
    65478, 16, 65479, 16, 65480, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 504, 9, 65481, 16, 65482, 16, 65483, 16, 65484, 16, 65485, 16, 65486, 16,
    65487, 16, 65488, 16, 65489, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 505, 9, 65490, 16, 65491, 16, 65492, 16, 65493, 16, 65494, 16, 65495, 16,
    65496, 16, 65497, 16, 65498, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 506, 9, 65499, 16, 65500, 16, 65501, 16, 65502, 16, 65503, 16, 65504, 16,
    65505, 16, 65506, 16, 65507, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 2041, 11, 65508, 16, 65509, 16, 65510, 16, 65511, 16, 65512, 16, 65513, 16,
    65514, 16, 65515, 16, 65516, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 16352, 14, 65517, 16, 65518, 16, 65519, 16, 65520, 16, 65521, 16, 65522, 16,
    65523, 16, 65524, 16, 65525, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1018, 10, 32707, 15, 65526, 16, 65527, 16, 65528, 16, 65529, 16, 65530, 16, 65531, 16,
    65532, 16, 65533, 16, 65534, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]

def fdy.table() -> +List<U32>:
  [
    1026206380, 1027117266, 1027862293, 1024533469, 1020054733, 1017309633, 1019033061, 1025156432, 1027117266, 1023742080, 1018976489, 1016919507, 1016309519, 1008507621, 1013144309, 1022575133,
    1023582051, 1018976489, 1019736780, 1015369072, 1011085077, 1010130274, 1011802390, 1023483629, 1024533468, 1020348356, 1017553100, 1014422767, 1009658633, 1006790013, 1011426127, 1023640562,
    1023410177, 1018728658, 1012919466, 1008620971, 1007831333, 1005385449, 1010053972, 1022848742, 1023562907, 1015430048, 1010130274, 1009419447, 1008921025, 1008597743, 1011968121, 1023621058,
    1019033062, 1011998160, 1010107635, 1010650730, 1010053972, 1011396298, 1016179793, 1026257640, 1023708594, 1016375399, 1016431136, 1016975753, 1017689176, 1022112042, 1025722589, 1034430350
  ]

def fduv.table() -> +List<U32>:
  [
    1026206380, 1018728658, 1016905540, 1010926886, 1003277517, 1006785690, 1010644453, 1018794796, 1018728658, 1015353472, 1013056587, 1002516110, 999532303, 1002171667, 1007184327, 1015401155,
    1016905541, 1013056587, 1004150821, 998591856, 1000128325, 1002930259, 1007734979, 1015941227, 1010926886, 1002516110, 998591856, 999562793, 1001270025, 1004383368, 1008789772, 1016975753,
    1003277517, 999532303, 1000128324, 1001270025, 1003277517, 1006785690, 1010644453, 1018794796, 1006785691, 1002171667, 1002930259, 1004383368, 1006785691, 1009115413, 1014026687, 1022112042,
    1010644454, 1007184327, 1007734979, 1008789773, 1010644454, 1014026687, 1018089161, 1026257640, 1018794797, 1015401155, 1015941226, 1016975753, 1018794797, 1022112042, 1026257640, 1034430350
  ]

def zig.table() -> +List<U32>:
  [
    0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42,
    3, 8, 12, 17, 25, 30, 41, 43, 9, 11, 18, 24, 31, 40, 44, 53,
    10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60,
    21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63
  ]
def header.rest(+height: U32, +width: U32) -> +List<U32>:
  Con{(height >> 8n : U32), Con{(height .&. 255 : U32), Con{(width >> 8n : U32), Con{(width .&. 255 : U32), header.suffix()}}}}

def header(+height: U32, +width: U32) -> +List<U32>:
  List.append(&2, U32, header.prefix(), header.rest(height, width))

def finish.bytes(writer: Writer) -> +List<U32>:
  Writer{_, _, bytes} = writer
  List.reverse(&2, U32, bytes)

def finish(writer: Writer) -> +List<U32>:
  finish.bytes(write.bits(writer, 127, 7))

def package(+height: U32, +width: U32, entropy: +List<U32>) -> +List<U32>:
  List.append(&2, U32, header(height, width), List.append(&2, U32, entropy, [255, 217]))

def encode.writer(+height: U32, +width: U32, codes: Codes) -> +List<U32>:
  Codes{_, _, _, writer} = codes
  package(height, width, finish(writer))

def encode.ready(+height: U32, +width: U32, step: Step) -> +List<U32>:
  Step{_, codes} = step
  encode.writer(height, width, codes)

# Quality 90 only: subsampled 16x16 macroblocks, the stb scaled quality of 20.
def encode(+width: U32, +height: U32, +comp: U32, +bytes: +List<U32>) -> +List<U32>:
  encode.ready(height, width, rows(tiles(height), 0, width, height, comp, bytes, Step{Tables{fdy.table(), fduv.table(), ydc.table(), yac.table(), uvdc.table(), uvac.table(), zig.table()}, Codes{0, 0, 0, Writer{0, 0, Nil{}}}}))

def unpack.word(n: Nat, +value: U32, bytes: +List<U32>) -> +List<U32>:
  match n:
    case 0n: bytes
    case 1n+rest: unpack.word(rest, (value >> 8n : U32), Con{(value .&. 255 : U32), bytes})

def unpack.finished(bytes: +List<U32>, read: Array<U32> & U32) -> +List<U32>:
  (_, _) = read
  List.reverse(&2, U32, bytes)

def unpack.finish(pixels: Array<U32>, bytes: +List<U32>) -> +List<U32>:
  unpack.finished(bytes, Array.get(U32, pixels, 0))

def unpack.read(+channels: U32, bytes: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, +value) = read
  (pixels, unpack.word(U32.to_nat(channels), value, bytes))

def unpack.pixels(n: Nat, +index: U32, +channels: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{pixels, bytes}: unpack.finish(pixels, bytes)
    case 1n+rest Tuple{pixels, bytes}: unpack.pixels(rest, (index + 1 : U32), channels, unpack.read(channels, bytes, Array.get(U32, pixels, index)))

# Little-endian channel bytes of formats 1, 2 and 4: low byte is channel 0.
def packed(+width: U32, +height: U32, +channels: U32, pixels: Array<U32>) -> +List<U32>:
  encode(width, height, channels, unpack.pixels(U32.to_nat((width * height : U32)), 0, channels, (pixels, Nil{})))

def color.word(+value: U32, bytes: +List<U32>) -> +List<U32>:
  Con{(value .&. 255 : U32), Con{((value >> 8n) .&. 255 : U32), Con{((value >> 16n) .&. 255 : U32), Con{(value >> 24n : U32), bytes}}}}

def color.read(bytes: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, +value) = read
  (pixels, color.word(value, bytes))

def color.pixels(n: Nat, +index: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{pixels, bytes}: unpack.finish(pixels, bytes)
    case 1n+rest Tuple{pixels, bytes}: color.pixels(rest, (index + 1 : U32), color.read(bytes, Array.get(U32, pixels, index)))

# Canonical 0xRRGGBBAA words, four channel bytes, as LoadImageColors lays them out.
def colors(+width: U32, +height: U32, pixels: Array<U32>) -> +List<U32>:
  encode(width, height, 4, color.pixels(U32.to_nat((width * height : U32)), 0, (pixels, Nil{})))
