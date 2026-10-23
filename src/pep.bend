# Jonlib - original additions zlib, Copyright (c) 2026 Jonathan Peris.
# Prediction-Encoded Pixels adapted from ENDESGA's CC0 pep.h in raylib 6.2.
# Altered owned Bend implementation. A color's first byte is its low 8 bits,
# the little-endian layout of the pinned Linux comparison. The context slab is
# sized to the pixel count, so images above 4096 pixels are refused.
# The pixel list is owned by the caller. raylib's loader frees that buffer
# after publishing it; this port keeps the pixels.
import Base

type Enc is Type:
  Enc{idx: Array<U32>, freq: Array<U32>, map: Array<U32>, reg: Array<U32>, out: +List<U32>}

type Best is Type:
  Best{bytes: +List<U32>, count: U32, model: U32}

type Plan is Data:
  Plan{stop: Bool, low: U32, range: U32}

type Mark is Data:
  Mark{stop: Bool, at: U32}

type Palette is Type:
  Palette{pal: Array<U32>, pix: Array<U32>, count: U32}

type Indexed is Type:
  Indexed{idx: Array<U32>, pal: Array<U32>, pix: Array<U32>}

type Packed is Type:
  Packed{pal: Array<U32>, buffer: U32, held: U32, acc: +List<U32>}

type Pressed is Type:
  Pressed{best: Best, pal: Array<U32>, count: U32}

type Seen is Data:
  Seen{stop: Bool, symbol: U32, low: U32, high: U32}

type Hit is Data:
  Hit{decoded: Bool, symbol: U32}

type Got is Data:
  Got{ok: Bool, i: U32, byte: U32}

type Vint is Data:
  Vint{ok: Bool, i: U32, size: U32, shift: U32, more: Bool}

type Dec is Type:
  Dec{enc: Enc, src: Array<U32>, pix: Array<U32>, pal: Array<U32>}

type Pal8 is Type:
  Pal8{src: Array<U32>, pal: Array<U32>, i: U32, n: U32, ok: Bool}

type Bits is Type:
  Bits{src: Array<U32>, pal: Array<U32>, i: U32, n: U32, buf: U32, held: U32, ok: Bool}

type Loaded is Type:
  Loaded{ok: Bool, src: Array<U32>, pal: Array<U32>, width: U32, height: U32, format: U32, model: U32, pcount: U32, pay: U32, size: U32}

def pep.depth(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, (1n + U32.log2((count - 1 : U32)) : Nat))

def pep.block(+slot: U32) -> U32:
  ((slot - 1 : U32) << 9n : U32)

def pep.burn(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{_, rest}: pep.burn(rest)

def pep.get.go(read: Array<U32> & U32, idx: Array<U32>, freq: Array<U32>, map: Array<U32>, out: +List<U32>) -> Enc & U32:
  (reg, value) = read
  (Enc{idx, freq, map, reg, out}, value)

def pep.get(+i: U32, enc: Enc) -> Enc & U32:
  Enc{idx, freq, map, reg, out} = enc
  pep.get.go(Array.get(U32, reg, i), idx, freq, map, out)

def pep.set(+i: U32, +value: U32, enc: Enc) -> Enc:
  Enc{idx, freq, map, reg, out} = enc
  Enc{idx, freq, map, Array.set(U32, reg, i, value), out}

def pep.push.go(+byte: U32, read: Array<U32> & U32, idx: Array<U32>, freq: Array<U32>, map: Array<U32>, out: +List<U32>) -> Enc:
  (reg, count) = read
  Enc{idx, freq, map, Array.set(U32, reg, 3, (count + 1 : U32)), Con{byte, out}}

def pep.push(+byte: U32, enc: Enc) -> Enc:
  Enc{idx, freq, map, reg, out} = enc
  pep.push.go(byte, Array.get(U32, reg, 3), idx, freq, map, out)

def pep.cell.go(+slot: U32, read: Array<U32> & U32, idx: Array<U32>, map: Array<U32>, reg: Array<U32>, out: +List<U32>) -> Enc & U32:
  (freq, value) = read
  (Enc{idx, freq, map, reg, out}, value)

def pep.cell(+slot: U32, +symbol: U32, enc: Enc) -> Enc & U32:
  Enc{idx, freq, map, reg, out} = enc
  pep.cell.go(slot, Array.get(U32, freq, (pep.block(slot) + symbol : U32)), idx, map, reg, out)

def pep.cell.set(+slot: U32, +symbol: U32, +value: U32, enc: Enc) -> Enc:
  Enc{idx, freq, map, reg, out} = enc
  Enc{idx, Array.set(U32, freq, (pep.block(slot) + symbol : U32), value), map, reg, out}

def pep.map.go(read: Array<U32> & U32, idx: Array<U32>, freq: Array<U32>, reg: Array<U32>, out: +List<U32>) -> Enc & U32:
  (map, value) = read
  (Enc{idx, freq, map, reg, out}, value)

def pep.map.get(+index: U32, enc: Enc) -> Enc & U32:
  Enc{idx, freq, map, reg, out} = enc
  pep.map.go(Array.get(U32, map, index), idx, freq, reg, out)

def pep.map.set(+index: U32, +slot: U32, enc: Enc) -> Enc:
  Enc{idx, freq, map, reg, out} = enc
  Enc{idx, freq, Array.set(U32, map, index, slot), reg, out}

def pep.idx.go(read: Array<U32> & U32, freq: Array<U32>, map: Array<U32>, reg: Array<U32>, out: +List<U32>) -> Enc & U32:
  (idx, value) = read
  (Enc{idx, freq, map, reg, out}, value)

def pep.idx.get(+at: U32, enc: Enc) -> Enc & U32:
  Enc{idx, freq, map, reg, out} = enc
  pep.idx.go(Array.get(U32, idx, at), freq, map, reg, out)

def pep.idx.set(+at: U32, +value: U32, enc: Enc) -> Enc:
  Enc{idx, freq, map, reg, out} = enc
  Enc{Array.set(U32, idx, at, value), freq, map, reg, out}

def pep.idx.pick(ok: Bool, +at: U32, +sent: U32, enc: Enc) -> Enc & U32:
  match ok:
    case False{}: (enc, sent)
    case True{}: pep.idx.get(at, enc)

def pep.hash(+nv: U32, +wv: U32, +nwv: U32, +nev: U32, +nnv: U32, +wwv: U32, +nnwv: U32, +nnev: U32, +nwwv: U32) -> U32:
  +h = (((((((((nv * 1540483477) + (wv * 3332679571)) + (nwv * 3432918353)) + (nev * 2246822507)) + (nnv * 2146121005)) + (wwv * 2890668881)) + (nnwv * 830770091)) + (nnev * 1935289751)) + (nwwv * 2943497623) : U32)
  (h .^. (h >> 15n) : U32)

def pep.level.kind(kind: U32, +nv: U32, +wv: U32, +nwv: U32, +nev: U32, +nnv: U32, +wwv: U32, +nnwv: U32, +nnev: U32, +nwwv: U32, +index_end: U32, enc: Enc) -> Enc & U32:
  match kind:
    case 0: (enc, (1 + (pep.hash(nv, wv, nwv, nev, nnv, wwv, nnwv, nnev, nwwv) .&. 65535) : U32))
    case 1: (enc, (1 + ((nv * index_end) + wv : U32) : U32))
    case _: (enc, (1 + wv : U32))

def pep.level.nwwv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, +nnv: U32, +wwv: U32, +nev: U32, +nnwv: U32, +nnev: U32, read: Enc & U32) -> Enc & U32:
  (enc, nwwv) = read
  pep.level.kind(kind, nv, wv, nwv, nev, nnv, wwv, nnwv, nnev, nwwv, index_end, enc)

def pep.level.nnev(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, +nnv: U32, +wwv: U32, +nev: U32, +nnwv: U32, read: Enc & U32) -> Enc & U32:
  (enc, nnev) = read
  pep.level.nwwv(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, nnv, wwv, nev, nnwv, nnev, pep.idx.pick((x > 1 : U32) && (y > 0 : U32), (pos - width - 2 : U32), sent, enc))

def pep.level.nnwv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, +nnv: U32, +wwv: U32, +nev: U32, read: Enc & U32) -> Enc & U32:
  (enc, nnwv) = read
  pep.level.nnev(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, nnv, wwv, nev, nnwv, pep.idx.pick((y > 1 : U32) && ((x + 1) < width : U32), ((pos - (width << 1n) : U32) + 1 : U32), sent, enc))

def pep.level.nev(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, +nnv: U32, +wwv: U32, read: Enc & U32) -> Enc & U32:
  (enc, nev) = read
  pep.level.nnwv(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, nnv, wwv, nev, pep.idx.pick((y > 1 : U32) && (x > 0 : U32), ((pos - (width << 1n) : U32) - 1 : U32), sent, enc))

def pep.level.wwv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, +nnv: U32, read: Enc & U32) -> Enc & U32:
  (enc, wwv) = read
  pep.level.nev(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, nnv, wwv, pep.idx.pick(((x + 1) < width : U32) && (y > 0 : U32), (pos - width + 1 : U32), sent, enc))

def pep.level.nnv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, +nwv: U32, read: Enc & U32) -> Enc & U32:
  (enc, nnv) = read
  pep.level.wwv(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, nnv, pep.idx.pick((x > 1 : U32), (pos - 2 : U32), sent, enc))

def pep.level.nwv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, +nv: U32, read: Enc & U32) -> Enc & U32:
  (enc, nwv) = read
  pep.level.nnv(kind, x, y, pos, width, sent, index_end, wv, nv, nwv, pep.idx.pick((y > 1 : U32), (pos - (width << 1n) : U32), sent, enc))

def pep.level.nv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, +wv: U32, read: Enc & U32) -> Enc & U32:
  (enc, nv) = read
  pep.level.nwv(kind, x, y, pos, width, sent, index_end, wv, nv, pep.idx.pick((x > 0 : U32) && (y > 0 : U32), (pos - width - 1 : U32), sent, enc))

def pep.level.wv(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, +index_end: U32, read: Enc & U32) -> Enc & U32:
  (enc, wv) = read
  pep.level.nv(kind, x, y, pos, width, sent, index_end, wv, pep.idx.pick((y > 0 : U32), (pos - width : U32), sent, enc))

def pep.level.end(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, +sent: U32, read: Enc & U32) -> Enc & U32:
  (enc, index_end) = read
  pep.level.wv(kind, x, y, pos, width, sent, index_end, pep.idx.pick((x > 0 : U32), (pos - 1 : U32), sent, enc))

def pep.level.sent(+kind: U32, +x: U32, +y: U32, +pos: U32, +width: U32, read: Enc & U32) -> Enc & U32:
  (enc, sent) = read
  pep.level.end(kind, x, y, pos, width, sent, pep.get(7, enc))

def pep.level.width(+kind: U32, +x: U32, +y: U32, +pos: U32, read: Enc & U32) -> Enc & U32:
  (enc, width) = read
  pep.level.sent(kind, x, y, pos, width, pep.get(6, enc))

def pep.level.pos(+kind: U32, +x: U32, +y: U32, read: Enc & U32) -> Enc & U32:
  (enc, pos) = read
  pep.level.width(kind, x, y, pos, pep.get(9, enc))

def pep.level.y(+kind: U32, +x: U32, read: Enc & U32) -> Enc & U32:
  (enc, y) = read
  pep.level.pos(kind, x, y, pep.get(13, enc))

def pep.level.x(+kind: U32, read: Enc & U32) -> Enc & U32:
  (enc, x) = read
  pep.level.y(kind, x, pep.get(12, enc))

def pep.level.kindreg(read: Enc & U32) -> Enc & U32:
  (enc, kind) = read
  pep.level.x(kind, pep.get(11, enc))

def pep.level(enc: Enc) -> Enc & U32:
  pep.level.kindreg(pep.get(8, enc))

def pep.slot.store(+index: U32, read: Enc & U32) -> Enc & U32:
  (enc, +slots) = read
  (pep.map.set(index, slots, pep.set(2, (slots + 1 : U32), enc)), slots)

def pep.slot.new(fresh: Bool, +index: U32, +slot: U32, enc: Enc) -> Enc & U32:
  match fresh:
    case False{}: (enc, slot)
    case True{}: pep.slot.store(index, pep.get(2, enc))

def pep.slot.open(+index: U32, read: Enc & U32) -> Enc & U32:
  (enc, +slot) = read
  pep.slot.new(U32.is_eq(slot, 0), index, slot, enc)

def pep.slot(+index: U32, enc: Enc) -> Enc & U32:
  pep.slot.open(index, pep.map.get(index, enc))

def pep.prob.add(+acc: U32, read: Enc & U32) -> Enc & U32:
  (enc, value) = read
  (enc, (acc + value : U32))

def pep.prob(left: Nat, +i: U32, +slot: U32, cursor: Enc & U32) -> Enc & U32:
  match left cursor:
    case 0n Tuple{enc, acc}: (enc, acc)
    case 1n+k Tuple{enc, acc}: pep.prob(k, (i + 1 : U32), slot, pep.prob.add(acc, pep.cell(slot, i, enc)))

def pep.arith.range(+lowp: U32, +high: U32, +scale: U32, +low: U32, read: Enc & U32) -> Enc:
  (enc, range) = read
  +next = (range / scale : U32)
  pep.set(1, (next * (high - lowp) : U32), pep.set(0, (low + (lowp * next) : U32), enc))

def pep.arith.low(+lowp: U32, +high: U32, +scale: U32, read: Enc & U32) -> Enc:
  (enc, low) = read
  pep.arith.range(lowp, high, scale, low, pep.get(1, enc))

def pep.arith(+lowp: U32, +high: U32, +scale: U32, enc: Enc) -> Enc:
  pep.arith.low(lowp, high, scale, pep.get(0, enc))

def pep.norm.plan.stop(stop: Bool, +low: U32, +range: U32) -> Plan:
  match stop:
    case True{}: Plan{True{}, low, range}
    case False{}: Plan{False{}, low, (16384 - (low .&. 16383) : U32)}

def pep.norm.plan.wide(wide: Bool, +low: U32, +range: U32) -> Plan:
  match wide:
    case False{}: Plan{False{}, low, range}
    case True{}: pep.norm.plan.stop((range >= 16384 : U32), low, range)

def pep.norm.plan(+low: U32, +range: U32) -> Plan:
  pep.norm.plan.wide((((low .^. (low + range : U32)) >= 16777215) : U32), low, range)

def pep.norm(fuel: Nat, plan: Plan, enc: Enc) -> Enc:
  match fuel plan:
    case 0n _: enc
    case _ Plan{True{}, _, _}: enc
    case 1n+k Plan{False{}, +low, +range}:
      +nlow = (low << 8n : U32)
      +nrange = (range << 8n : U32)
      pep.norm(k, pep.norm.plan(nlow, nrange), pep.set(1, nrange, pep.set(0, nlow, pep.push((low >> 24n : U32), enc))))

def pep.normalize.range(+low: U32, read: Enc & U32) -> Enc:
  (enc, range) = read
  pep.norm(16n, pep.norm.plan(low, range), enc)

def pep.normalize.low(read: Enc & U32) -> Enc:
  (enc, low) = read
  pep.normalize.range(low, pep.get(1, enc))

def pep.normalize(enc: Enc) -> Enc:
  pep.normalize.low(pep.get(0, enc))

def pep.scale.step(zero: Bool, +i: U32, +slot: U32, +sum: U32, +value: U32, enc: Enc) -> Enc & U32:
  match zero:
    case True{}: (enc, sum)
    case False{}:
      +scaled = ((value + 1) >> 1n : U32)
      (pep.cell.set(slot, i, scaled, enc), (sum + scaled : U32))

def pep.scale.apply(+i: U32, +slot: U32, +sum: U32, read: Enc & U32) -> Enc & U32:
  (enc, +value) = read
  pep.scale.step(U32.is_eq(value, 0), i, slot, sum, value, enc)

def pep.scale(left: Nat, +i: U32, +slot: U32, cursor: Enc & U32) -> Enc:
  match left cursor:
    case 0n Tuple{enc, sum}: pep.cell.set(slot, 257, sum, enc)
    case 1n+k Tuple{enc, sum}: pep.scale(k, (i + 1 : U32), slot, pep.scale.apply(i, slot, sum, pep.cell(slot, i, enc)))

def pep.update.go(rescale: Bool, +slot: U32, +limit: U32, enc: Enc) -> Enc:
  match rescale:
    case False{}: enc
    case True{}: pep.scale(257n, 0, slot, (pep.cell.set(slot, 257, 0, pep.set(4, limit, enc)), 0))

def pep.update.pcount(+slot: U32, +symbol: U32, +freq2: U32, +sum2: U32, +freq_max: U32, read: Enc & U32) -> Enc:
  (enc, pcount) = read
  +limit = (((freq_max + ((256 - pcount) >> 1n : U32)) .&. 65535) : U32)
  pep.update.go(((freq2 >= freq_max : U32) || (sum2 >= 16384 : U32)), slot, limit, pep.cell.set(slot, 257, sum2, pep.cell.set(slot, symbol, freq2, enc)))

def pep.update.max(+slot: U32, +symbol: U32, +freq2: U32, +sum2: U32, read: Enc & U32) -> Enc:
  (enc, freq_max) = read
  pep.update.pcount(slot, symbol, freq2, sum2, freq_max, pep.get(5, enc))

def pep.update.sum(+slot: U32, +symbol: U32, +freq: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.update.max(slot, symbol, ((freq + 2) .&. 65535 : U32), (sum + 2 : U32), pep.get(4, enc))

def pep.update.freq(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, freq) = read
  pep.update.sum(slot, symbol, freq, pep.cell(slot, 257, enc))

def pep.update(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.update.freq(slot, symbol, pep.cell(slot, symbol, enc))

def pep.learn.sum(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.cell.set(slot, 257, (sum + 1 : U32), pep.cell.set(slot, symbol, 1, enc))

def pep.learn(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.learn.sum(slot, symbol, pep.cell(slot, 257, enc))

def pep.seed.empty(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, escape) = read
  pep.learn(slot, symbol, pep.cell.set(slot, 257, 1, pep.cell.set(slot, escape, 1, enc)))

def pep.seed(empty: Bool, +slot: U32, +symbol: U32, enc: Enc) -> Enc:
  match empty:
    case False{}: pep.learn(slot, symbol, enc)
    case True{}: pep.seed.empty(slot, symbol, pep.get(6, enc))

def pep.order.scale(+slot: U32, +symbol: U32, empty: Bool, +lowp: U32, +span: U32, read: Enc & U32) -> Enc:
  (enc, scale) = read
  pep.seed(empty, slot, symbol, pep.update(1, symbol, pep.normalize(pep.arith(lowp, (lowp + span : U32), scale, enc))))

def pep.order.span(+slot: U32, +symbol: U32, empty: Bool, +lowp: U32, read: Enc & U32) -> Enc:
  (enc, span) = read
  pep.order.scale(slot, symbol, empty, lowp, span, pep.cell(1, 257, enc))

def pep.order.low(+slot: U32, +symbol: U32, empty: Bool, read: Enc & U32) -> Enc:
  (enc, lowp) = read
  pep.order.span(slot, symbol, empty, lowp, pep.cell(1, symbol, enc))

def pep.order(+slot: U32, +symbol: U32, empty: Bool, enc: Enc) -> Enc:
  pep.order.low(slot, symbol, empty, pep.prob(U32.to_nat(symbol), 0, 1, (enc, 0)))

def pep.escape.sum(+slot: U32, +symbol: U32, +escape: U32, +freq: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.order(slot, symbol, False{}, pep.cell.set(slot, 257, (sum + 1 : U32), pep.cell.set(slot, escape, ((freq + 1) .&. 65535 : U32), enc)))

def pep.escape.freq(+slot: U32, +symbol: U32, +escape: U32, read: Enc & U32) -> Enc:
  (enc, freq) = read
  pep.escape.sum(slot, symbol, escape, freq, pep.cell(slot, 257, enc))

def pep.escape.coded(+slot: U32, +symbol: U32, +escape: U32, enc: Enc) -> Enc:
  pep.escape.freq(slot, symbol, escape, pep.cell(slot, escape, enc))

def pep.escape.scale(+slot: U32, +symbol: U32, +escape: U32, +lowp: U32, +span: U32, read: Enc & U32) -> Enc:
  (enc, scale) = read
  pep.escape.coded(slot, symbol, escape, pep.normalize(pep.arith(lowp, (lowp + span : U32), scale, enc)))

def pep.escape.span(+slot: U32, +symbol: U32, +escape: U32, +lowp: U32, read: Enc & U32) -> Enc:
  (enc, span) = read
  pep.escape.scale(slot, symbol, escape, lowp, span, pep.cell(slot, 257, enc))

def pep.escape.low(+slot: U32, +symbol: U32, +escape: U32, read: Enc & U32) -> Enc:
  (enc, lowp) = read
  pep.escape.span(slot, symbol, escape, lowp, pep.cell(slot, escape, enc))

def pep.escape.esc(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, +escape) = read
  pep.escape.low(slot, symbol, escape, pep.prob(U32.to_nat(escape), 0, slot, (enc, 0)))

def pep.escape(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.escape.esc(slot, symbol, pep.get(6, enc))

def pep.known.scale(+slot: U32, +symbol: U32, +lowp: U32, +span: U32, read: Enc & U32) -> Enc:
  (enc, scale) = read
  pep.update(slot, symbol, pep.normalize(pep.arith(lowp, (lowp + span : U32), scale, enc)))

def pep.known.span(+slot: U32, +symbol: U32, +lowp: U32, read: Enc & U32) -> Enc:
  (enc, span) = read
  pep.known.scale(slot, symbol, lowp, span, pep.cell(slot, 257, enc))

def pep.known.low(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, lowp) = read
  pep.known.span(slot, symbol, lowp, pep.cell(slot, symbol, enc))

def pep.known(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.known.low(slot, symbol, pep.prob(U32.to_nat(symbol), 0, slot, (enc, 0)))

def pep.hit.have(present: Bool, +slot: U32, +symbol: U32, enc: Enc) -> Enc:
  match present:
    case True{}: pep.known(slot, symbol, enc)
    case False{}: pep.escape(slot, symbol, enc)

def pep.hit.freq(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, freq) = read
  pep.hit.have((freq > 0 : U32), slot, symbol, enc)

def pep.hit(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.hit.freq(slot, symbol, pep.cell(slot, symbol, enc))

def pep.on(live: Bool, +slot: U32, +symbol: U32, enc: Enc) -> Enc:
  match live:
    case False{}: pep.order(slot, symbol, True{}, enc)
    case True{}: pep.hit(slot, symbol, enc)

def pep.use.sum(+symbol: U32, +slot: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.on((sum > 0 : U32), slot, symbol, enc)

def pep.use.slot(+symbol: U32, read: Enc & U32) -> Enc:
  (enc, +slot) = read
  pep.use.sum(symbol, slot, pep.cell(slot, 257, enc))

def pep.use.index(+symbol: U32, read: Enc & U32) -> Enc:
  (enc, index) = read
  pep.use.slot(symbol, pep.slot(index, enc))

def pep.use(+symbol: U32, enc: Enc) -> Enc:
  pep.use.index(symbol, pep.level(enc))

def pep.flush.go(n: Nat, cursor: Enc & U32) -> Enc:
  match n cursor:
    case 0n Tuple{enc, +low}: enc
    case 1n+k Tuple{enc, +low}: pep.flush.go(k, pep.get(0, pep.set(0, (low << 8n : U32), pep.push((low >> 24n : U32), enc))))

def pep.flush(n: Nat, enc: Enc) -> Enc:
  pep.flush.go(n, pep.get(0, enc))

def pep.step.use(+pos: U32, +x: U32, +y: U32, +width: U32, +symbol: U32, enc: Enc) -> Enc:
  +x2 = (x + 1 : U32)
  +wrap = U32.is_eq(x2, width)
  pep.set(13, (pos + 1 : U32), pep.set(12, Bool.pick(U32, wrap, (y + 1 : U32), y), pep.set(11, Bool.pick(U32, wrap, 0, x2), pep.use(symbol, enc))))

def pep.step.width(+pos: U32, +symbol: U32, +x: U32, +y: U32, read: Enc & U32) -> Enc:
  (enc, width) = read
  pep.step.use(pos, x, y, width, symbol, enc)

def pep.step.y(+pos: U32, +symbol: U32, +x: U32, read: Enc & U32) -> Enc:
  (enc, y) = read
  pep.step.width(pos, symbol, x, y, pep.get(9, enc))

def pep.step.x(+pos: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, x) = read
  pep.step.y(pos, symbol, x, pep.get(12, enc))

def pep.step.sym(+pos: U32, read: Enc & U32) -> Enc:
  (enc, symbol) = read
  pep.step.x(pos, symbol, pep.get(11, enc))

def pep.step.pos(read: Enc & U32) -> Enc:
  (enc, +pos) = read
  pep.step.sym(pos, pep.idx.get(pos, enc))

def pep.step(left: Nat, enc: Enc) -> Enc:
  match left:
    case 0n: pep.flush(4n, enc)
    case 1n+k: pep.step(k, pep.step.pos(pep.get(13, enc)))

def pep.order0(left: Nat, +i: U32, freq: Array<U32>) -> Array<U32>:
  match left:
    case 0n: freq
    case 1n+k: pep.order0(k, (i + 1 : U32), Array.set(U32, freq, i, 1))

def pep.reg(+kind: U32, +pcount: U32, +width: U32, +height: U32, +area: U32) -> Array<U32>:
  a0 = Array.new(U32, 5n, 0)
  a1 = Array.set(U32, a0, 1, 4294967295)
  a2 = Array.set(U32, a1, 2, 2)
  a3 = Array.set(U32, a2, 4, 128)
  a4 = Array.set(U32, a3, 5, pcount)
  a5 = Array.set(U32, a4, 6, pcount)
  a6 = Array.set(U32, a5, 7, (pcount + 1 : U32))
  a7 = Array.set(U32, a6, 8, kind)
  a8 = Array.set(U32, a7, 9, width)
  a9 = Array.set(U32, a8, 10, height)
  a10 = Array.set(U32, a9, 11, 0)
  a11 = Array.set(U32, a10, 12, 0)
  a12 = Array.set(U32, a11, 13, 0)
  Array.set(U32, a12, 14, area)

def pep.fresh(+kind: U32, +pcount: U32, +width: U32, +height: U32, +area: U32, idx: Array<U32>) -> Enc:
  reg = pep.reg(kind, pcount, width, height, area)
  freq = Array.set(U32, pep.order0(U32.to_nat(pcount), 0, Array.new(U32, pep.depth(((area + 1) * 512 : U32)), 0)), 257, pcount)
  Enc{idx, freq, Array.set(U32, Array.new(U32, 17n, 0), 0, 1), reg, Nil{}}

def pep.done.model(+count: U32, out: +List<U32>, read: Array<U32> & U32) -> Best:
  (reg, model) = read
  Best{List.reverse(&2, U32, out), count, model}

def pep.done.count(out: +List<U32>, read: Array<U32> & U32) -> Best:
  (reg, count) = read
  pep.done.model(count, out, Array.get(U32, reg, 8))

def pep.done.map(reg: Array<U32>, out: +List<U32>, read: Array<U32> & U32) -> Best:
  (map, _) = read
  pep.done.count(out, Array.get(U32, reg, 3))

def pep.done.freq(map: Array<U32>, reg: Array<U32>, out: +List<U32>, read: Array<U32> & U32) -> Best:
  (freq, _) = read
  pep.done.map(reg, out, Array.get(U32, map, 0))

def pep.done.idx(freq: Array<U32>, map: Array<U32>, reg: Array<U32>, out: +List<U32>, read: Array<U32> & U32) -> Best:
  (idx, _) = read
  pep.done.freq(map, reg, out, Array.get(U32, freq, 0))

def pep.done(enc: Enc) -> Best:
  Enc{idx, freq, map, reg, out} = enc
  pep.done.idx(freq, map, reg, out, Array.get(U32, idx, 0))

def pep.choose.at(better: Bool, gbytes: +List<U32>, +gcount: U32, +gmodel: U32, bbytes: +List<U32>, +bcount: U32, +bmodel: U32) -> Best:
  match better:
    case True{}: Best{gbytes, (gcount + pep.burn(bbytes) : U32), gmodel}
    case False{}: Best{bbytes, (bcount + pep.burn(gbytes) : U32), bmodel}

def pep.choose(got: Best, best: Best) -> Best:
  Best{gbytes, +gcount, gmodel} = got
  Best{bbytes, +bcount, bmodel} = best
  pep.choose.at((gcount < bcount : U32), gbytes, gcount, gmodel, bbytes, bcount, bmodel)

def pep.models.burn(best: Best, read: Array<U32> & U32) -> Best:
  (idx, _) = read
  best

def pep.models.advance(+kind: U32, best: Best, +pcount: U32, +width: U32, +height: U32, +area: U32, read: Array<U32> & Array<U32>) -> Best & Array<U32>:
  (copy, rest) = read
  (pep.choose(pep.done(pep.step(U32.to_nat(area), pep.fresh(kind, pcount, width, height, area, copy))), best), rest)

def pep.models(n: Nat, +kind: U32, cursor: Best & Array<U32>, +pcount: U32, +width: U32, +height: U32, +area: U32) -> Best:
  match n cursor:
    case 0n Tuple{best, idx}: pep.models.burn(best, Array.get(U32, idx, 0))
    case 1n+k Tuple{best, idx}: pep.models(k, (kind + 1 : U32), pep.models.advance(kind, best, pcount, width, height, area, Array.clone(U32, idx)), pcount, width, height, area)

def pep.find.step(+i: U32, +color: U32, read: Array<U32> & U32) -> Array<U32> & Mark:
  (pal, value) = read
  +eq = U32.is_eq(value, color)
  (pal, Mark{eq, Bool.pick(U32, eq, i, (i + 1 : U32))})

def pep.find(left: Nat, cursor: Array<U32> & Mark, +color: U32) -> Array<U32> & U32:
  match left cursor:
    case _ Tuple{pal, Mark{True{}, +at}}: (pal, at)
    case 0n Tuple{pal, Mark{False{}, _}}: (pal, 256)
    case 1n+k Tuple{pal, Mark{False{}, +i}}: pep.find(k, pep.find.step(i, color, Array.get(U32, pal, i)), color)

def pep.store(add: Bool, +count: U32, +color: U32, pal: Array<U32>) -> Array<U32>:
  match add:
    case True{}: Array.set(U32, pal, count, color)
    case False{}: pal

def pep.colors.found(+count: U32, +color: U32, pix: Array<U32>, read: Array<U32> & U32) -> Palette:
  (pal, at) = read
  +add = ((at >= count : U32) && (count < 256 : U32))
  Palette{pep.store(add, count, color, pal), pix, Bool.pick(U32, add, (count + 1 : U32), count)}

def pep.colors.pix(+count: U32, pal: Array<U32>, read: Array<U32> & U32) -> Palette:
  (pix, +color) = read
  pep.colors.found(count, color, pix, pep.find(U32.to_nat(count), (pal, Mark{False{}, 0}), color))

def pep.colors(left: Nat, +i: U32, cursor: Palette) -> Palette:
  match left cursor:
    case 0n Palette{pal, pix, count}: Palette{pal, pix, count}
    case 1n+k Palette{pal, pix, count}: pep.colors(k, (i + 1 : U32), pep.colors.pix(count, pal, Array.get(U32, pix, i)))

def pep.indexes.found(+i: U32, +count: U32, pix: Array<U32>, idx: Array<U32>, read: Array<U32> & U32) -> Indexed:
  (pal, +at) = read
  Indexed{Array.set(U32, idx, i, Bool.pick(U32, (at < count : U32), at, 0)), pal, pix}

def pep.indexes.pix(+i: U32, +count: U32, pal: Array<U32>, idx: Array<U32>, read: Array<U32> & U32) -> Indexed:
  (pix, color) = read
  pep.indexes.found(i, count, pix, idx, pep.find(U32.to_nat(count), (pal, Mark{False{}, 0}), color))

def pep.indexes(left: Nat, +i: U32, +count: U32, cursor: Indexed) -> Indexed:
  match left cursor:
    case 0n Indexed{idx, pal, pix}: Indexed{idx, pal, pix}
    case 1n+k Indexed{idx, pal, pix}: pep.indexes(k, (i + 1 : U32), count, pep.indexes.pix(i, count, pal, idx, Array.get(U32, pix, i)))

def pep.compress.pix(+width: U32, +height: U32, +area: U32, +count: U32, pal: Array<U32>, idx: Array<U32>, read: Array<U32> & U32) -> Pressed:
  (pix, _) = read
  +pcount = Bool.pick(U32, U32.is_eq(count, 0), 256, count)
  Pressed{pep.models(3n, 0, (Best{Nil{}, 4294967295, 0}, idx), pcount, width, height, area), pal, count}

def pep.compress.idx(+width: U32, +height: U32, +area: U32, +count: U32, read: Indexed) -> Pressed:
  Indexed{idx, pal, pix} = read
  pep.compress.pix(width, height, area, count, pal, idx, Array.get(U32, pix, 0))

def pep.compress.colors(+width: U32, +height: U32, +area: U32, read: Palette) -> Pressed:
  Palette{pal, pix, +count} = read
  pep.compress.idx(width, height, area, count, pep.indexes(U32.to_nat(area), 0, count, Indexed{Array.new(U32, pep.depth(area), 0), pal, pix}))

def pep.compress(+width: U32, +height: U32, pix: Array<U32>) -> Pressed:
  +area = (width * height : U32)
  pep.compress.colors(width, height, area, pep.colors(U32.to_nat(area), 0, Palette{Array.new(U32, 8n, 0), pix, 0}))

def pep.byte(+color: U32, n: Nat) -> U32:
  ((color >> n) .&. 255 : U32)

def pep.black(+color: U32, rgba: Bool) -> Bool:
  Bool.pick(Bool, rgba, U32.is_eq(color, 4278190080), U32.is_eq(color, 255))

def pep.pair(+rgba: Bool, +a: U32, +b: U32) -> Bool:
  (U32.is_eq(a, 4294967295) && pep.black(b, rgba)) || (pep.black(a, rgba) && U32.is_eq(b, 4294967295))

def pep.bitmap.second(rgba: Bool, +first: U32, read: Array<U32> & U32) -> Array<U32> & Bool:
  (pal, second) = read
  (pal, pep.pair(rgba, first, second))

def pep.bitmap.first(rgba: Bool, read: Array<U32> & U32) -> Array<U32> & Bool:
  (pal, first) = read
  pep.bitmap.second(rgba, first, Array.get(U32, pal, 1))

def pep.bitmap(count: U32, rgba: Bool, pal: Array<U32>) -> Array<U32> & Bool:
  match count:
    case 2: pep.bitmap.first(rgba, Array.get(U32, pal, 0))
    case _: (pal, False{})

def pep.opaque.step(+i: U32, read: Array<U32> & U32) -> Array<U32> & Mark:
  (pal, color) = read
  (pal, Mark{Bool.not(U32.is_eq(pep.byte(color, 24n), 255)), (i + 1 : U32)})

def pep.opaque(left: Nat, cursor: Array<U32> & Mark) -> Array<U32> & Bool:
  match left cursor:
    case _ Tuple{pal, Mark{True{}, at}}: (pal, False{})
    case 0n Tuple{pal, Mark{False{}, at}}: (pal, True{})
    case 1n+k Tuple{pal, Mark{False{}, +i}}: pep.opaque(k, pep.opaque.step(i, Array.get(U32, pal, i)))

def pep.rgb(bitmap: Bool, +count: U32, pal: Array<U32>) -> Array<U32> & Bool:
  match bitmap:
    case True{}: (pal, True{})
    case False{}: pep.opaque(U32.to_nat(count), (pal, Mark{False{}, 0}))

def pep.emit(bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: acc
    case Con{head, rest}: pep.emit(rest, Con{head, acc})

def pep.varint(fuel: Nat, more: Bool, +n: U32, acc: +List<U32>) -> +List<U32>:
  match fuel more:
    case 0n _: Con{(n .&. 255 : U32), acc}
    case _ False{}: Con{(n .&. 255 : U32), acc}
    case 1n+k True{}: pep.varint(k, (((n >> 7n) >= 128) : U32), (n >> 7n : U32), Con{((n .|. 128) .&. 255 : U32), acc})

def pep.color8(rgb: Bool, +color: U32, acc: +List<U32>) -> +List<U32>:
  match rgb:
    case True{}: Con{pep.byte(color, 16n), Con{pep.byte(color, 8n), Con{pep.byte(color, 0n), acc}}}
    case False{}: Con{pep.byte(color, 24n), Con{pep.byte(color, 16n), Con{pep.byte(color, 8n), Con{pep.byte(color, 0n), acc}}}}

def pep.palette8.step(rgb: Bool, acc: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pal, color) = read
  (pal, pep.color8(rgb, color, acc))

def pep.palette8(left: Nat, +i: U32, +rgb: Bool, cursor: Array<U32> & +List<U32>) -> Array<U32> & +List<U32>:
  match left cursor:
    case 0n Tuple{pal, acc}: (pal, acc)
    case 1n+k Tuple{pal, acc}: pep.palette8(k, (i + 1 : U32), rgb, pep.palette8.step(rgb, acc, Array.get(U32, pal, i)))

def pep.drain(fuel: Nat, more: Bool, +buffer: U32, +held: U32, acc: +List<U32>) -> U32 & (U32 & +List<U32>):
  match fuel more:
    case 0n _: (buffer, (held, acc))
    case _ False{}: (buffer, (held, acc))
    case 1n+k True{}:
      +left = (buffer - 8 : U32)
      pep.drain(k, (left >= 8 : U32), left, held, Con{((held >> U32.to_nat(left)) .&. 255 : U32), acc})

def pep.bits(+value: U32, +channel: U32, +buffer: U32, +held: U32, acc: +List<U32>) -> U32 & (U32 & +List<U32>):
  +next = (buffer + channel : U32)
  pep.drain(4n, (next >= 8 : U32), next, ((held << U32.to_nat(channel)) .|. value : U32), acc)

def pep.alpha(rgb: Bool, +color: U32, +channel: U32, +mask: U32, +shift: U32, +buffer: U32, +held: U32, acc: +List<U32>) -> U32 & (U32 & +List<U32>):
  match rgb:
    case True{}: (buffer, (held, acc))
    case False{}: pep.bits(((pep.byte(color, 24n) >> U32.to_nat(shift)) .&. mask : U32), channel, buffer, held, acc)

def pep.pack.one.a(+color: U32, +channel: U32, +mask: U32, +shift: U32, rgb: Bool, read: U32 & (U32 & +List<U32>)) -> U32 & (U32 & +List<U32>):
  (buffer, (held, acc)) = read
  pep.alpha(rgb, color, channel, mask, shift, buffer, held, acc)

def pep.pack.one.b(+color: U32, +channel: U32, +mask: U32, +shift: U32, rgb: Bool, read: U32 & (U32 & +List<U32>)) -> U32 & (U32 & +List<U32>):
  (buffer, (held, acc)) = read
  pep.pack.one.a(color, channel, mask, shift, rgb, pep.bits(((pep.byte(color, 16n) >> U32.to_nat(shift)) .&. mask : U32), channel, buffer, held, acc))

def pep.pack.one.g(+color: U32, +channel: U32, +mask: U32, +shift: U32, rgb: Bool, read: U32 & (U32 & +List<U32>)) -> U32 & (U32 & +List<U32>):
  (buffer, (held, acc)) = read
  pep.pack.one.b(color, channel, mask, shift, rgb, pep.bits(((pep.byte(color, 8n) >> U32.to_nat(shift)) .&. mask : U32), channel, buffer, held, acc))

def pep.pack.one(+color: U32, +channel: U32, +mask: U32, +shift: U32, rgb: Bool, +buffer: U32, +held: U32, acc: +List<U32>) -> U32 & (U32 & +List<U32>):
  pep.pack.one.g(color, channel, mask, shift, rgb, pep.bits(((pep.byte(color, 0n) >> U32.to_nat(shift)) .&. mask : U32), channel, buffer, held, acc))

def pep.pack.end(rest: Bool, +buffer: U32, +held: U32, pal: Array<U32>, acc: +List<U32>) -> Array<U32> & +List<U32>:
  match rest:
    case False{}: (pal, acc)
    case True{}: (pal, Con{((held << U32.to_nat((8 - buffer : U32))) .&. 255 : U32), acc})

def pep.pack.wrap(pal: Array<U32>, read: U32 & (U32 & +List<U32>)) -> Packed:
  (buffer, (held, acc)) = read
  Packed{pal, buffer, held, acc}

def pep.pack.apply(+channel: U32, +mask: U32, +shift: U32, rgb: Bool, +buffer: U32, +held: U32, acc: +List<U32>, read: Array<U32> & U32) -> Packed:
  (pal, color) = read
  pep.pack.wrap(pal, pep.pack.one(color, channel, mask, shift, rgb, buffer, held, acc))

def pep.pack(left: Nat, +i: U32, +channel: U32, +mask: U32, +shift: U32, +rgb: Bool, cursor: Packed) -> Array<U32> & +List<U32>:
  match left cursor:
    case 0n Packed{pal, +buffer, held, acc}: pep.pack.end((buffer > 0 : U32), buffer, held, pal, acc)
    case 1n+k Packed{pal, +buffer, held, acc}: pep.pack(k, (i + 1 : U32), channel, mask, shift, rgb, pep.pack.apply(channel, mask, shift, rgb, buffer, held, acc, Array.get(U32, pal, i)))

def pep.colors.of(wide: Bool, +count: U32, +channel: U32, rgb: Bool, pal: Array<U32>, acc: +List<U32>) -> Array<U32> & +List<U32>:
  match wide:
    case True{}: pep.palette8(U32.to_nat(count), 0, rgb, (pal, acc))
    case False{}: pep.pack(U32.to_nat(count), 0, channel, ((1 << U32.to_nat(channel)) - 1 : U32), (8 - channel : U32), rgb, Packed{pal, 0, 0, acc})

def pep.dims(small: Bool, +w: U32, +h: U32, acc: +List<U32>) -> +List<U32>:
  match small:
    case True{}: Con{(h .&. 255 : U32), Con{(w .&. 255 : U32), acc}}
    case False{}:
      +packed = (((w .&. 4095) << 12n) .|. (h .&. 4095) : U32)
      Con{(packed .&. 255 : U32), Con{((packed >> 8n) .&. 255 : U32), Con{((packed >> 16n) .&. 255 : U32), acc}}}

def pep.header(+small: Bool, +width: U32, +height: U32, +format: U32, +bits: U32, +model: U32, rgb: Bool, bitmap: Bool, acc: +List<U32>) -> +List<U32>:
  +flags = ((format .&. 3) .|. ((bits .&. 3) << 2n) .|. (Bool.pick(U32, small, 1, 0) << 4n) .|. (Bool.pick(U32, rgb, 1, 0) << 5n) .|. (Bool.pick(U32, bitmap, 1, 0) << 6n) : U32)
  pep.dims(small, (width - 1 : U32), (height - 1 : U32), Con{(model .&. 255 : U32), Con{flags, acc}})

def pep.body.burn(bytes: +List<U32>, colors: +List<U32>, read: Array<U32> & U32) -> +List<U32>:
  (pal, _) = read
  List.reverse(&2, U32, pep.emit(bytes, colors))

def pep.body.colors(bytes: +List<U32>, read: Array<U32> & +List<U32>) -> +List<U32>:
  (pal, colors) = read
  pep.body.burn(bytes, colors, Array.get(U32, pal, 0))

def pep.body.go(bitmap: Bool, rgb: Bool, +count: U32, +bits: U32, pal: Array<U32>, bytes: +List<U32>, sized: +List<U32>) -> +List<U32>:
  match bitmap:
    case True{}: List.reverse(&2, U32, pep.emit(bytes, sized))
    case False{}:
      +channel = (1 << U32.to_nat(bits) : U32)
      pep.body.colors(bytes, pep.colors.of(U32.is_eq(channel, 8), count, channel, rgb, pal, Con{(count .&. 255 : U32), sized}))

def pep.body(bitmap: Bool, rgb: Bool, +count: U32, +bits: U32, +payload: U32, pal: Array<U32>, bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  pep.body.go(bitmap, rgb, count, bits, pal, bytes, pep.varint(6n, (payload >= 128 : U32), payload, acc))

def pep.serialize.rgb(+width: U32, +height: U32, +format: U32, +bits: U32, bytes: +List<U32>, +count: U32, +model: U32, +bitmap: Bool, +colors: U32, read: Array<U32> & Bool) -> +List<U32>:
  (pal, +rgb) = read
  pep.body(bitmap, rgb, colors, bits, count, pal, bytes, pep.header(((width - 1) <= 255 : U32) && ((height - 1) <= 255 : U32), width, height, format, bits, model, rgb, bitmap, Nil{}))

def pep.serialize.bitmap(+width: U32, +height: U32, +format: U32, +bits: U32, bytes: +List<U32>, +count: U32, +model: U32, +colors: U32, read: Array<U32> & Bool) -> +List<U32>:
  (pal, +bitmap) = read
  pep.serialize.rgb(width, height, format, bits, bytes, count, model, bitmap, colors, pep.rgb(bitmap, colors, pal))

def pep.serialize(+width: U32, +height: U32, +format: U32, +bits: U32, result: Pressed) -> +List<U32>:
  Pressed{Best{bytes, +count, model}, pal, +colors} = result
  pep.serialize.bitmap(width, height, format, bits, bytes, count, model, colors, pep.bitmap(colors, (format <= 1 : U32), pal))

# Serialized file bytes for an in-range image, or the empty list when refused.
def pep.bytes.drop(read: Array<U32> & U32) -> +List<U32>:
  (pix, _) = read
  Nil{}

def pep.bytes(ok: Bool, +width: U32, +height: U32, +format: U32, +bits: U32, pix: Array<U32>) -> +List<U32>:
  match ok:
    case False{}: pep.bytes.drop(Array.get(U32, pix, 0))
    case True{}: pep.serialize(width, height, format, bits, pep.compress(width, height, pix))

def bytes(+width: U32, +height: U32, +format: U32, +bits: U32, pix: Array<U32>) -> +List<U32>:
  +area = (width * height : U32)
  pep.bytes((width > 0 : U32) && (height > 0 : U32) && (width <= 65535 : U32) && (height <= 65535 : U32) && (area > 0 : U32) && (area <= 4096 : U32) && (bits <= 3 : U32) && (format <= 3 : U32), width, height, format, bits, pix)


def pep.list.nil.go(ok: Bool) -> +List<U32>:
  match ok:
    case True{}: Nil{}
    case False{}: Nil{}

def pep.list.nil(+n: U32) -> +List<U32>:
  pep.list.nil.go((n >= 0 : U32))

def pep.span(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{_, rest}: (1 + pep.span(rest) : U32)

def pep.fill(xs: +List<U32>, +i: U32, src: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}: src
    case Con{+head, rest}: pep.fill(rest, (i + 1 : U32), Array.set(U32, src, i, head))

def pep.arr.drop.open(read: Array<U32> & U32) -> U32:
  (rest, _) = read
  0

def pep.arr.drop(arr: Array<U32>) -> U32:
  pep.arr.drop.open(Array.get(U32, arr, 0))

def pep.arr.touch.open(read: Array<U32> & U32) -> U32:
  (rest, value) = read
  (value + pep.arr.drop(rest) : U32)

def pep.arr.touch(arr: Array<U32>) -> U32:
  pep.arr.touch.open(Array.get(U32, arr, 0))

def pep.best.drop(best: Best) -> U32:
  Best{bytes, +count, +model} = best
  (count .|. model .|. pep.burn(bytes) : U32)

def pep.bump.sum(+slot: U32, +escape: U32, +freq: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.cell.set(slot, 257, (sum + 1 : U32), pep.cell.set(slot, escape, ((freq + 1) .&. 65535 : U32), enc))

def pep.bump.freq(+slot: U32, +escape: U32, read: Enc & U32) -> Enc:
  (enc, freq) = read
  pep.bump.sum(slot, escape, freq, pep.cell(slot, 257, enc))

def pep.bump.esc(+slot: U32, read: Enc & U32) -> Enc:
  (enc, +escape) = read
  pep.bump.freq(slot, escape, pep.cell(slot, escape, enc))

def pep.bump(+slot: U32, enc: Enc) -> Enc:
  pep.bump.esc(slot, pep.get(6, enc))

def pep.took.order(+slot: U32, +symbol: U32, empty: Bool, enc: Enc) -> Enc:
  pep.seed(empty, slot, symbol, pep.update(1, symbol, enc))

def pep.took.sum(+slot: U32, +symbol: U32, read: Enc & U32) -> Enc:
  (enc, sum) = read
  pep.took.order(slot, symbol, U32.is_eq(sum, 0), enc)

def pep.took(+slot: U32, +symbol: U32, enc: Enc) -> Enc:
  pep.took.sum(slot, symbol, pep.cell(slot, 257, enc))

def pep.sym.add(+target: U32, +i: U32, +total: U32, read: Enc & U32) -> Enc & Seen:
  (enc, value) = read
  +high = (total + value : U32)
  +hit = (high > target : U32)
  (enc, Seen{hit, Bool.pick(U32, hit, i, (i + 1 : U32)), Bool.pick(U32, hit, total, high), high})

def pep.sym.clamp(+high: U32, read: Enc & U32) -> Enc & Seen:
  (enc, freq) = read
  (enc, Seen{True{}, 256, (high - freq : U32), high})

def pep.sym(left: Nat, +target: U32, +slot: U32, cursor: Enc & Seen) -> Enc & Seen:
  match left cursor:
    case _ Tuple{enc, Seen{True{}, +symbol, +low, +high}}: (enc, Seen{True{}, symbol, low, high})
    case 0n Tuple{enc, Seen{False{}, +at, +low, +high}}: pep.sym.clamp((high .|. ((at .|. low) .&. 0) : U32), pep.cell(slot, 256, enc))
    case 1n+k Tuple{enc, Seen{False{}, +i, +low, +high}}: pep.sym(k, target, slot, pep.sym.add(target, i, (high .|. (low .&. 0) : U32), pep.cell(slot, i, enc)))

def pep.reform.swap16(+color: U32) -> U32:
  ((color .&. 4278255360) .|. ((color .&. 255) << 16n) .|. ((color .&. 16711680) >> 16n) : U32)

def pep.reform.swap32(+color: U32) -> U32:
  ((color .&. 16711935) .|. ((color .&. 65280) << 16n) .|. ((color .&. 4278190080) >> 16n) : U32)

def pep.reform.flip(+color: U32) -> U32:
  (((color .&. 255) << 24n) .|. ((color .&. 65280) << 8n) .|. ((color .&. 16711680) >> 8n) .|. ((color .&. 4278190080) >> 24n) : U32)

def pep.reform.up(+color: U32) -> U32:
  (((color .&. 4278190080) >> 24n) .|. ((color .&. 16777215) << 8n) : U32)

def pep.reform.down(+color: U32) -> U32:
  (((color .&. 255) << 24n) .|. ((color .&. 4294967040) >> 8n) : U32)

def pep.reform(+src: U32, +dst: U32, +color: U32) -> U32:
  Bool.pick(U32, U32.is_eq(src, dst), color,
    Bool.pick(U32, (src <= 1 : U32) && (dst <= 1 : U32), pep.reform.swap16(color),
      Bool.pick(U32, (src >= 2 : U32) && (dst >= 2 : U32), pep.reform.swap32(color),
        Bool.pick(U32, U32.is_eq((src .^. dst : U32), 2), pep.reform.flip(color),
          Bool.pick(U32, (src < dst : U32), pep.reform.up(color), pep.reform.down(color))))))

def pep.mix(+channel: U32, +scaled: U32) -> U32:
  (((channel * scaled + 32896) >> 16n) .&. 255 : U32)

def pep.pre.rgba(+color: U32) -> U32:
  +a = pep.byte(color, 24n)
  +scaled = (a * 257 : U32)
  (pep.byte(color, 0n) .|. (pep.mix(pep.byte(color, 8n), scaled) << 8n) .|. (pep.mix(pep.byte(color, 16n), scaled) << 16n) .|. (pep.mix(a, scaled) << 24n) : U32)

def pep.pre.argb(+color: U32) -> U32:
  +a = pep.byte(color, 0n)
  +scaled = (a * 257 : U32)
  (pep.mix(a, scaled) .|. (pep.mix(pep.byte(color, 8n), scaled) << 8n) .|. (pep.mix(pep.byte(color, 16n), scaled) << 16n) .|. (pep.byte(color, 24n) << 24n) : U32)

def pep.pre(+format: U32, +color: U32) -> U32:
  Bool.pick(U32, (format <= 1 : U32), pep.pre.rgba(color), pep.pre.argb(color))

def pep.shade.no(+symbol: U32, +src: U32, +dst: U32, +pre: U32, +raw: U32, pal: Array<U32>) -> Array<U32> & U32:
  (pal, (((symbol .|. src .|. dst .|. pre .|. raw) .&. 0) : U32))

def pep.shade.yes(+symbol: U32, +src: U32, +dst: U32, +pre: U32, +raw: U32, pal: Array<U32>) -> Array<U32> & U32:
  +pixel = pep.reform(src, dst, raw)
  (pal, (Bool.pick(U32, (pre > 0 : U32), pep.pre(dst, pixel), pixel) .|. (symbol .&. 0) : U32))

def pep.shade.yes.open(+symbol: U32, +src: U32, +dst: U32, +pre: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pal, raw) = read
  pep.shade.yes(symbol, src, dst, pre, raw, pal)

def pep.shade.no.open(+symbol: U32, +src: U32, +dst: U32, +pre: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (pal, raw) = read
  pep.shade.no(symbol, src, dst, pre, raw, pal)

def pep.shade.pick(have: Bool, +symbol: U32, +src: U32, +dst: U32, +pre: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  match have:
    case True{}: pep.shade.yes.open(symbol, src, dst, pre, read)
    case False{}: pep.shade.no.open(symbol, src, dst, pre, read)

def pep.shade(+symbol: U32, +pcount: U32, +src: U32, +dst: U32, +pre: U32, pal: Array<U32>) -> Array<U32> & U32:
  +have = (symbol < pcount : U32)
  pep.shade.pick(have, symbol, src, dst, pre, Array.get(U32, pal, Bool.pick(U32, have, symbol, 0)))

def pep.dadvance(+pos: U32, +x: U32, +y: U32, +width: U32, enc: Enc) -> Enc:
  +x2 = (x + 1 : U32)
  +wrap = U32.is_eq(x2, width)
  pep.set(13, (pos + 1 : U32), pep.set(12, Bool.pick(U32, wrap, (y + 1 : U32), y), pep.set(11, Bool.pick(U32, wrap, 0, x2), enc)))

def pep.one.store(+pos: U32, +symbol: U32, +pixel: U32, +x: U32, +y: U32, +width: U32, dec: Dec) -> Dec:
  Dec{enc, src, pix, pal} = dec
  Dec{pep.dadvance(pos, x, y, width, pep.idx.set(pos, symbol, enc)), src, Array.set(U32, pix, pos, pixel), pal}

def pep.one.shaded(+pos: U32, +symbol: U32, +x: U32, +y: U32, +width: U32, enc: Enc, src: Array<U32>, pix: Array<U32>, read: Array<U32> & U32) -> Dec:
  (pal, pixel) = read
  pep.one.store(pos, symbol, pixel, x, y, width, Dec{enc, src, pix, pal})

def pep.one.pre(+pos: U32, +symbol: U32, +x: U32, +y: U32, +width: U32, +pcount: U32, +srcfmt: U32, +dst: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, pre) = read
  pep.one.shaded(pos, symbol, x, y, width, enc, src, pix, pep.shade(symbol, pcount, srcfmt, dst, pre, pal))

def pep.one.dst(+pos: U32, +symbol: U32, +x: U32, +y: U32, +width: U32, +pcount: U32, +srcfmt: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, dst) = read
  pep.one.pre(pos, symbol, x, y, width, pcount, srcfmt, dst, src, pix, pal, pep.get(19, enc))

def pep.one.srcfmt(+pos: U32, +symbol: U32, +x: U32, +y: U32, +width: U32, +pcount: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, srcfmt) = read
  pep.one.dst(pos, symbol, x, y, width, pcount, srcfmt, src, pix, pal, pep.get(18, enc))

def pep.one.pcount(+pos: U32, +symbol: U32, +x: U32, +y: U32, +width: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, pcount) = read
  pep.one.srcfmt(pos, symbol, x, y, width, pcount, src, pix, pal, pep.get(20, enc))

def pep.one.width(+pos: U32, +symbol: U32, +x: U32, +y: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, width) = read
  pep.one.pcount(pos, symbol, x, y, width, src, pix, pal, pep.get(5, enc))

def pep.one.y(+pos: U32, +symbol: U32, +x: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, y) = read
  pep.one.width(pos, symbol, x, y, src, pix, pal, pep.get(9, enc))

def pep.one.x(+pos: U32, +symbol: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, x) = read
  pep.one.y(pos, symbol, x, src, pix, pal, pep.get(12, enc))

def pep.one.pos(+symbol: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, pos) = read
  pep.one.x(pos, symbol, src, pix, pal, pep.get(11, enc))

def pep.one.after(+symbol: U32, dec: Dec) -> Dec:
  Dec{enc, src, pix, pal} = dec
  pep.one.pos(symbol, src, pix, pal, pep.get(13, enc))

def pep.pull.got(+pos: U32, enc: Enc, pix: Array<U32>, pal: Array<U32>, read: Array<U32> & U32) -> Dec & U32:
  (src, byte) = read
  (Dec{pep.set(16, (pos + 1 : U32), enc), src, pix, pal}, byte)

def pep.pull.read(+pos: U32, dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.pull.got(pos, enc, pix, pal, Array.get(U32, src, pos))

def pep.pull.live(live: Bool, +pos: U32, dec: Dec) -> Dec & U32:
  match live:
    case False{}: (dec, (pos .&. 0 : U32))
    case True{}: pep.pull.read(pos, dec)

def pep.pull.pos(+end: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, +pos) = read
  pep.pull.live(Bool.not(U32.is_eq(pos, end)), pos, Dec{enc, src, pix, pal})

def pep.pull.end(src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, end) = read
  pep.pull.pos(end, src, pix, pal, pep.get(16, enc))

def pep.pull(dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.pull.end(src, pix, pal, pep.get(17, enc))

def pep.prime.store(+byte: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, code) = read
  Dec{pep.set(15, ((code << 8n) .|. byte : U32), enc), src, pix, pal}

def pep.prime.apply(read: Dec & U32) -> Dec:
  (dec, byte) = read
  Dec{enc, src, pix, pal} = dec
  pep.prime.store(byte, src, pix, pal, pep.get(15, enc))

def pep.prime(n: Nat, dec: Dec) -> Dec:
  match n:
    case 0n: dec
    case 1n+k: pep.prime(k, pep.prime.apply(pep.pull(dec)))

def pep.curr.quot(+scale: U32, +low: U32, +code: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, range) = read
  +next = (range / scale : U32)
  (Dec{pep.set(1, next, enc), src, pix, pal}, ((code - low) / next : U32))

def pep.curr.code(+scale: U32, +low: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, code) = read
  pep.curr.quot(scale, low, code, src, pix, pal, pep.get(1, enc))

def pep.curr.low(+scale: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, low) = read
  pep.curr.code(scale, low, src, pix, pal, pep.get(15, enc))

def pep.curr(+scale: U32, dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.curr.low(scale, src, pix, pal, pep.get(0, enc))

def pep.dshift.store(+byte: U32, +low: U32, +range: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, code) = read
  +nlow = (low << 8n : U32)
  +nrange = (range << 8n : U32)
  Dec{pep.set(15, ((code << 8n) .|. byte : U32), pep.set(1, nrange, pep.set(0, nlow, enc))), src, pix, pal}

def pep.dshift.pull(+low: U32, +range: U32, read: Dec & U32) -> Dec:
  (dec, byte) = read
  Dec{enc, src, pix, pal} = dec
  pep.dshift.store(byte, low, range, src, pix, pal, pep.get(15, enc))

def pep.dshift(fuel: Nat, plan: Plan, dec: Dec) -> Dec:
  match fuel plan:
    case 0n _: dec
    case _ Plan{True{}, _, _}: dec
    case 1n+k Plan{False{}, +low, +range}: pep.dshift(k, pep.norm.plan((low << 8n : U32), (range << 8n : U32)), pep.dshift.pull(low, range, pep.pull(dec)))

def pep.dupdate.range(+lowp: U32, +span: U32, +low: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, +range) = read
  +nlow = (low + (range * lowp) : U32)
  +nrange = (range * span : U32)
  pep.dshift(16n, pep.norm.plan(nlow, nrange), Dec{pep.set(1, nrange, pep.set(0, nlow, enc)), src, pix, pal})

def pep.dupdate.low(+lowp: U32, +span: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec:
  (enc, low) = read
  pep.dupdate.range(lowp, span, low, src, pix, pal, pep.get(1, enc))

def pep.dupdate(+lowp: U32, +high: U32, dec: Dec) -> Dec:
  Dec{enc, src, pix, pal} = dec
  pep.dupdate.low(lowp, (high - lowp : U32), src, pix, pal, pep.get(0, enc))

def pep.dsym.seen(src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & Seen) -> Dec & Seen:
  (enc, seen) = read
  (Dec{enc, src, pix, pal}, seen)

def pep.dsym.open(+slot: U32, +target: U32, dec: Dec) -> Dec & Seen:
  Dec{enc, src, pix, pal} = dec
  pep.dsym.seen(src, pix, pal, pep.sym(257n, target, slot, (enc, Seen{False{}, 0, 0, 0})))

def pep.dsym.target(+slot: U32, read: Dec & U32) -> Dec & Seen:
  (dec, target) = read
  pep.dsym.open(slot, target, dec)

def pep.dsym(+slot: U32, +scale: U32, dec: Dec) -> Dec & Seen:
  pep.dsym.target(slot, pep.curr(scale, dec))

def pep.try.branch(miss: Bool, +slot: U32, +symbol: U32, dec: Dec) -> Dec & Hit:
  match miss:
    case False{}:
      Dec{enc, src, pix, pal} = dec
      (Dec{pep.update(slot, symbol, enc), src, pix, pal}, Hit{True{}, symbol})
    case True{}:
      Dec{enc, src, pix, pal} = dec
      (Dec{pep.bump(slot, enc), src, pix, pal}, Hit{False{}, symbol})

def pep.try.escape(+slot: U32, +symbol: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & Hit:
  (enc, escape) = read
  pep.try.branch(U32.is_eq(symbol, escape), slot, symbol, Dec{enc, src, pix, pal})

def pep.try.updated(+slot: U32, +symbol: U32, dec: Dec) -> Dec & Hit:
  Dec{enc, src, pix, pal} = dec
  pep.try.escape(slot, symbol, src, pix, pal, pep.get(6, enc))

def pep.try.finish(+slot: U32, seen: Seen, dec: Dec) -> Dec & Hit:
  match seen:
    case Seen{_, +symbol, +low, +high}: pep.try.updated(slot, symbol, pep.dupdate(low, high, dec))

def pep.try.seen(+slot: U32, read: Dec & Seen) -> Dec & Hit:
  (dec, seen) = read
  pep.try.finish(slot, seen, dec)

def pep.try.decode(+slot: U32, +scale: U32, dec: Dec) -> Dec & Hit:
  pep.try.seen(slot, pep.dsym(slot, scale, dec))

def pep.try.live(live: Bool, +slot: U32, +scale: U32, dec: Dec) -> Dec & Hit:
  match live:
    case False{}: (dec, Hit{False{}, (((scale .|. slot) .&. 0) : U32)})
    case True{}: pep.try.decode(slot, scale, dec)

def pep.try.open(+slot: U32, +sum: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, enc: Enc) -> Dec & Hit:
  pep.try.live((sum > 0 : U32), slot, sum, Dec{enc, src, pix, pal})

def pep.try.cell(+slot: U32, src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & Hit:
  (enc, sum) = read
  pep.try.open(slot, sum, src, pix, pal, enc)

def pep.try.ctx(+slot: U32, dec: Dec) -> Dec & Hit:
  Dec{enc, src, pix, pal} = dec
  pep.try.cell(slot, src, pix, pal, pep.cell(slot, 257, enc))

def pep.ord.apply(+slot: U32, +symbol: U32, dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  (Dec{pep.took(slot, symbol, enc), src, pix, pal}, symbol)

def pep.ord.finish(+slot: U32, seen: Seen, dec: Dec) -> Dec & U32:
  match seen:
    case Seen{_, +symbol, +low, +high}: pep.ord.apply(slot, symbol, pep.dupdate(low, high, dec))

def pep.ord.seen(+slot: U32, read: Dec & Seen) -> Dec & U32:
  (dec, seen) = read
  pep.ord.finish(slot, seen, dec)

def pep.ord.scale(+slot: U32, read: Dec & U32) -> Dec & U32:
  (dec, scale) = read
  pep.ord.seen(slot, pep.dsym(1, scale, dec))

def pep.osum.open(src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, sum) = read
  (Dec{enc, src, pix, pal}, sum)

def pep.osum(dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.osum.open(src, pix, pal, pep.cell(1, 257, enc))

def pep.one.ordered(+symbol: U32, dec: Dec) -> Dec:
  pep.one.after(symbol, dec)

def pep.one.order.go(+slot: U32, read: Dec & U32) -> Dec:
  (dec, symbol) = read
  pep.one.ordered(symbol, dec)

def pep.one.order(+slot: U32, dec: Dec) -> Dec:
  pep.one.order.go(slot, pep.ord.scale(slot, pep.osum(dec)))

def pep.one.hit.go(hit: Hit, +slot: U32, dec: Dec) -> Dec:
  match hit:
    case Hit{True{}, +symbol}: pep.one.after(symbol, dec)
    case Hit{False{}, _}: pep.one.order(slot, dec)

def pep.one.hit(+slot: U32, read: Dec & Hit) -> Dec:
  (dec, hit) = read
  pep.one.hit.go(hit, slot, dec)

def pep.one.slot(read: Dec & U32) -> Dec:
  (dec, +slot) = read
  pep.one.hit(slot, pep.try.ctx(slot, dec))

def pep.dslot.open(src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, slot) = read
  (Dec{enc, src, pix, pal}, slot)

def pep.dslot.use(+index: U32, dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.dslot.open(src, pix, pal, pep.slot(index, enc))

def pep.dslot(read: Dec & U32) -> Dec & U32:
  (dec, index) = read
  pep.dslot.use(index, dec)

def pep.dlevel.open(src: Array<U32>, pix: Array<U32>, pal: Array<U32>, read: Enc & U32) -> Dec & U32:
  (enc, index) = read
  (Dec{enc, src, pix, pal}, index)

def pep.dlevel(dec: Dec) -> Dec & U32:
  Dec{enc, src, pix, pal} = dec
  pep.dlevel.open(src, pix, pal, pep.level(enc))

def pep.one(dec: Dec) -> Dec:
  pep.one.slot(pep.dslot(pep.dlevel(dec)))

def pep.dpix(left: Nat, dec: Dec) -> Dec:
  match left:
    case 0n: dec
    case 1n+k: pep.dpix(k, pep.one(dec))

def pep.dreg(+pay: U32, +end: U32, +dst: U32, +pre: U32, +srcfmt: U32, enc: Enc) -> Enc:
  pep.set(20, srcfmt, pep.set(19, pre, pep.set(18, dst, pep.set(17, end, pep.set(16, pay, pep.set(15, 0, enc))))))

def pep.fade(+format: U32, read: Array<U32> & U32) -> Array<U32>:
  (pal, color) = read
  +mask = Bool.pick(U32, (format <= 1 : U32), 16777215, 4294967040)
  Array.set(U32, pal, 0, (color .&. mask : U32))

def pep.fade.keep.open(read: Array<U32> & U32) -> Array<U32>:
  (rest, _) = read
  rest

def pep.fade.keep(pal: Array<U32>) -> Array<U32>:
  pep.fade.keep.open(Array.get(U32, pal, 0))

def pep.fade.if(on: Bool, +format: U32, pal: Array<U32>) -> Array<U32>:
  match on:
    case False{}: pep.fade.keep(pal)
    case True{}: pep.fade(format, Array.get(U32, pal, 0))

def pep.unlist.done.open(acc: +List<U32>, read: Array<U32> & U32) -> +List<U32>:
  (rest, _) = read
  List.reverse(&2, U32, acc)

def pep.unlist.done(pix: Array<U32>, acc: +List<U32>) -> +List<U32>:
  pep.unlist.done.open(acc, Array.get(U32, pix, 0))

def pep.unlist.step(+i: U32, acc: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pix, value) = read
  (pix, Con{value, acc})

def pep.unlist(left: Nat, +i: U32, cursor: Array<U32> & +List<U32>) -> +List<U32>:
  match left cursor:
    case 0n Tuple{pix, acc}: pep.unlist.done(pix, acc)
    case 1n+k Tuple{pix, acc}: pep.unlist(k, (i + 1 : U32), pep.unlist.step(i, acc, Array.get(U32, pix, i)))

def pep.finish.go(+area: U32, +dropped: U32, pix: Array<U32>) -> +List<U32>:
  pep.unlist(U32.to_nat((area + (dropped .&. 0) : U32)), 0, (pix, Nil{}))

def pep.finish.open(+area: U32, enc: Enc, src: Array<U32>, pal: Array<U32>, pix: Array<U32>) -> +List<U32>:
  pep.finish.go(area, (pep.best.drop(pep.done(enc)) .|. pep.arr.touch(src) .|. pep.arr.touch(pal) : U32), pix)

def pep.finish.area(src: Array<U32>, pal: Array<U32>, pix: Array<U32>, read: Enc & U32) -> +List<U32>:
  (enc, area) = read
  pep.finish.open(area, enc, src, pal, pix)

def pep.finish(dec: Dec) -> +List<U32>:
  Dec{enc, src, pix, pal} = dec
  pep.finish.area(src, pal, pix, pep.get(14, enc))

def pep.decode(+dst: U32, +transparent: U32, +pre: U32, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32, src: Array<U32>, pal: Array<U32>) -> +List<U32>:
  +area = (width * height : U32)
  +kind = Bool.pick(U32, (model < 3 : U32), model, 0)
  enc = pep.dreg(pay, (pay + size : U32), dst, pre, format, pep.fresh(kind, pcount, width, height, area, Array.new(U32, pep.depth(area), 0)))
  primed = pep.prime(4n, Dec{enc, src, Array.new(U32, pep.depth(area), 0), pep.fade.if((transparent > 0 : U32), format, pal)})
  pep.finish(pep.dpix(U32.to_nat(area), primed))


def pep.rd.ok(+i: U32, read: Array<U32> & U32) -> Array<U32> & Got:
  (src, byte) = read
  (src, Got{True{}, (i + 1 : U32), byte})

def pep.rd.bad.open(+i: U32, read: Array<U32> & U32) -> Array<U32> & Got:
  (src, _) = read
  (src, Got{False{}, i, 0})

def pep.rd.bad(src: Array<U32>, +i: U32) -> Array<U32> & Got:
  pep.rd.bad.open(i, Array.get(U32, src, 0))

def pep.rd(inside: Bool, +i: U32, src: Array<U32>) -> Array<U32> & Got:
  match inside:
    case True{}: pep.rd.ok(i, Array.get(U32, src, i))
    case False{}: pep.rd.bad(src, i)

def pep.bad.open(+sink: U32, read: Array<U32> & U32) -> Loaded:
  (src, value) = read
  Loaded{False{}, src, Array.new(U32, 0n, 0), 0, 0, 0, 0, 0, 0, ((value .|. sink) .&. 0 : U32)}

def pep.bad(src: Array<U32>, +sink: U32) -> Loaded:
  pep.bad.open(sink, Array.get(U32, src, 0))

def pep.accept.no.open(src: Array<U32>, +sink: U32, read: Array<U32> & U32) -> Loaded:
  (rest, _) = read
  pep.bad(src, (sink .|. pep.arr.drop(rest) : U32))

def pep.accept.no(src: Array<U32>, pal: Array<U32>, +sink: U32) -> Loaded:
  pep.accept.no.open(src, sink, Array.get(U32, pal, 0))

def pep.accept.go(good: Bool, src: Array<U32>, pal: Array<U32>, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32) -> Loaded:
  match good:
    case False{}: pep.accept.no(src, pal, (width .|. height .|. format .|. model .|. pcount .|. pay .|. size : U32))
    case True{}: Loaded{True{}, src, pal, width, height, format, model, pcount, pay, size}

def pep.accept(ok: Bool, src: Array<U32>, pal: Array<U32>, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32) -> Loaded:
  +area = (width * height : U32)
  pep.accept.go(ok && (area > 0 : U32) && (area <= 4096 : U32) && (width > 0 : U32) && (height > 0 : U32) && (width <= 65535 : U32) && (height <= 65535 : U32) && (size <= 65536 : U32) && (pcount > 0 : U32) && (pcount <= 256 : U32), src, pal, width, height, format, model, pcount, pay, size)

def pep.vint.step(+size: U32, +shift: U32, got: Got) -> Vint:
  match got:
    case Got{False{}, +i, +byte}: Vint{False{}, i, (size .|. (byte .&. 0) : U32), shift, False{}}
    case Got{True{}, +i, +byte}:
      +nshift = (shift + 7 : U32)
      +add = Bool.pick(U32, (shift < 32 : U32), ((byte .&. 127) << U32.to_nat(shift) : U32), 0)
      Vint{True{}, i, (size .|. add : U32), nshift, (((byte .&. 128) > 0 : U32) && (nshift < 35 : U32))}

def pep.vint.next(+size: U32, +shift: U32, read: Array<U32> & Got) -> Array<U32> & Vint:
  (src, got) = read
  (src, pep.vint.step(size, shift, got))

def pep.vint(fuel: Nat, +n: U32, cursor: Array<U32> & Vint) -> Array<U32> & Vint:
  match fuel cursor:
    case _ Tuple{src, Vint{False{}, +i, +size, +shift, more}}: (src, Vint{False{}, i, size, shift, more})
    case _ Tuple{src, Vint{True{}, +i, +size, +shift, False{}}}: (src, Vint{True{}, i, size, shift, False{}})
    case 0n Tuple{src, Vint{True{}, +i, +size, +shift, True{}}}: (src, Vint{False{}, i, size, shift, False{}})
    case 1n+k Tuple{src, Vint{True{}, +i, +size, +shift, True{}}}: pep.vint(k, n, pep.vint.next(size, shift, pep.rd((i < n : U32), i, src)))

def pep.p8.take.byte(pal: Array<U32>, +n: U32, ok: Bool, src: Array<U32>, got: Got) -> Pal8 & U32:
  match got:
    case Got{good, +i, +byte}: (Pal8{src, pal, i, n, ok && good}, byte)

def pep.p8.take.open(pal: Array<U32>, +n: U32, ok: Bool, read: Array<U32> & Got) -> Pal8 & U32:
  (src, got) = read
  pep.p8.take.byte(pal, n, ok, src, got)

def pep.p8.take(state: Pal8) -> Pal8 & U32:
  Pal8{src, pal, +i, +n, +ok} = state
  pep.p8.take.open(pal, n, ok, pep.rd(ok && (i < n : U32), i, src))

def pep.p8.put(+at: U32, +r: U32, +g: U32, +b: U32, +a: U32, state: Pal8) -> Pal8:
  Pal8{src, pal, i, n, ok} = state
  Pal8{src, Array.set(U32, pal, at, (r .|. (g << 8n) .|. (b << 16n) .|. ((a .&. 255) << 24n) : U32)), i, n, ok}

def pep.p8.a.read(+at: U32, +r: U32, +g: U32, +b: U32, read: Pal8 & U32) -> Pal8:
  (state, a) = read
  pep.p8.put(at, r, g, b, a, state)

def pep.p8.a(rgb: Bool, +at: U32, +r: U32, +g: U32, +b: U32, state: Pal8) -> Pal8:
  match rgb:
    case True{}: pep.p8.put(at, r, g, b, 255, state)
    case False{}: pep.p8.a.read(at, r, g, b, pep.p8.take(state))

def pep.p8.b(+at: U32, +r: U32, +g: U32, rgb: Bool, read: Pal8 & U32) -> Pal8:
  (state, b) = read
  pep.p8.a(rgb, at, r, g, b, state)

def pep.p8.g(+at: U32, +r: U32, rgb: Bool, read: Pal8 & U32) -> Pal8:
  (state, g) = read
  pep.p8.b(at, r, g, rgb, pep.p8.take(state))

def pep.p8.r(+at: U32, rgb: Bool, read: Pal8 & U32) -> Pal8:
  (state, r) = read
  pep.p8.g(at, r, rgb, pep.p8.take(state))

def pep.p8.one(+rgb: Bool, +at: U32, state: Pal8) -> Pal8:
  pep.p8.r(at, rgb, pep.p8.take(state))

def pep.p8(left: Nat, +at: U32, +rgb: Bool, state: Pal8) -> Pal8:
  match left:
    case 0n: state
    case 1n+k: pep.p8(k, (at + 1 : U32), rgb, pep.p8.one(rgb, at, state))

def pep.widen(+channel: U32, +value: U32) -> U32:
  +scaled = (value << U32.to_nat((8 - channel : U32)) : U32)
  +once = (scaled .|. (scaled >> U32.to_nat(channel)) : U32)
  Bool.pick(U32, (channel < 4 : U32), (once .|. (once >> U32.to_nat((channel << 1n : U32))) : U32), once)

def pep.need.store(+buf: U32, +held: U32, pal: Array<U32>, +n: U32, ok: Bool, src: Array<U32>, got: Got) -> Bits:
  match got:
    case Got{good, +i, +byte}: Bits{src, pal, i, n, ((buf << 8n) .|. byte : U32), (held + 8 : U32), ok && good}

def pep.need.got(+buf: U32, +held: U32, pal: Array<U32>, +n: U32, ok: Bool, read: Array<U32> & Got) -> Bits:
  (src, got) = read
  pep.need.store(buf, held, pal, n, ok, src, got)

def pep.need.read(state: Bits) -> Bits:
  Bits{src, pal, +i, +n, +buf, +held, +ok} = state
  pep.need.got(buf, held, pal, n, ok, pep.rd(ok && (i < n : U32), i, src))

def pep.need.keep(+channel: U32, state: Bits) -> Bits:
  Bits{src, pal, i, n, buf, held, ok} = state
  Bits{src, pal, i, n, buf, (held .|. (channel .&. 0) : U32), ok}

def pep.need.byte(short: Bool, +channel: U32, state: Bits) -> Bits:
  match short:
    case False{}: pep.need.keep(channel, state)
    case True{}: pep.need.read(state)

def pep.need.more(+channel: U32, state: Bits) -> Bits:
  Bits{src, pal, i, n, buf, +held, +ok} = state
  pep.need.byte(ok && (held < channel : U32), channel, Bits{src, pal, i, n, buf, held, ok})

def pep.need(fuel: Nat, +channel: U32, state: Bits) -> Bits:
  match fuel:
    case 0n: pep.need.keep(channel, state)
    case 1n+k: pep.need(k, channel, pep.need.more(channel, state))

def pep.ch.open(+channel: U32, +mask: U32, state: Bits) -> Bits & U32:
  Bits{src, pal, i, n, +buf, +held, ok} = state
  +fit = (ok && (held >= channel : U32))
  +left = Bool.pick(U32, fit, (held - channel : U32), held)
  +raw = ((buf >> U32.to_nat(left)) .&. mask : U32)
  (Bits{src, pal, i, n, buf, left, fit}, Bool.pick(U32, fit, pep.widen(channel, raw), (raw .&. 0 : U32)))

def pep.ch(+channel: U32, +mask: U32, state: Bits) -> Bits & U32:
  pep.ch.open(channel, mask, pep.need(2n, channel, state))

def pep.bstore(+color: U32, +at: U32, state: Bits) -> Bits:
  Bits{src, pal, i, n, buf, held, ok} = state
  Bits{src, Array.set(U32, pal, at, color), i, n, buf, held, ok}

def pep.balpha.keep(+channel: U32, +mask: U32, state: Bits) -> Bits:
  Bits{src, pal, i, n, buf, held, ok} = state
  Bits{src, pal, i, n, buf, (held .|. ((channel .|. mask) .&. 0) : U32), ok}

def pep.balpha.got(+at: U32, +r: U32, +g: U32, +b: U32, read: Bits & U32) -> Bits:
  (state, a) = read
  pep.bstore((r .|. (g << 8n) .|. (b << 16n) .|. (a << 24n) : U32), at, state)

def pep.balpha(rgb: Bool, +channel: U32, +mask: U32, +at: U32, +r: U32, +g: U32, +b: U32, state: Bits) -> Bits:
  match rgb:
    case True{}: pep.bstore((r .|. (g << 8n) .|. (b << 16n) .|. 4278190080 : U32), at, pep.balpha.keep(channel, mask, state))
    case False{}: pep.balpha.got(at, r, g, b, pep.ch(channel, mask, state))

def pep.bb.got(+channel: U32, +mask: U32, rgb: Bool, +at: U32, +r: U32, +g: U32, read: Bits & U32) -> Bits:
  (state, b) = read
  pep.balpha(rgb, channel, mask, at, r, g, b, state)

def pep.bb(+channel: U32, +mask: U32, rgb: Bool, +at: U32, +r: U32, +g: U32, state: Bits) -> Bits:
  pep.bb.got(channel, mask, rgb, at, r, g, pep.ch(channel, mask, state))

def pep.bg.got(+channel: U32, +mask: U32, rgb: Bool, +at: U32, +r: U32, read: Bits & U32) -> Bits:
  (state, g) = read
  pep.bb(channel, mask, rgb, at, r, g, state)

def pep.bg(+channel: U32, +mask: U32, rgb: Bool, +at: U32, +r: U32, state: Bits) -> Bits:
  pep.bg.got(channel, mask, rgb, at, r, pep.ch(channel, mask, state))

def pep.br.got(+channel: U32, +mask: U32, rgb: Bool, +at: U32, read: Bits & U32) -> Bits:
  (state, r) = read
  pep.bg(channel, mask, rgb, at, r, state)

def pep.br(+channel: U32, +mask: U32, rgb: Bool, +at: U32, state: Bits) -> Bits:
  pep.br.got(channel, mask, rgb, at, pep.ch(channel, mask, state))

def pep.bone(+channel: U32, +mask: U32, rgb: Bool, +at: U32, state: Bits) -> Bits:
  pep.br(channel, mask, rgb, at, state)

def pep.bpal(left: Nat, +at: U32, +channel: U32, +mask: U32, +rgb: Bool, state: Bits) -> Bits:
  match left:
    case 0n: state
    case 1n+k: pep.bpal(k, (at + 1 : U32), channel, mask, rgb, pep.bone(channel, mask, rgb, at, state))

def pep.hd.pay(ok: Bool, src: Array<U32>, pal: Array<U32>, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32, +n: U32) -> Loaded:
  +end = (pay + size : U32)
  +kind = Bool.pick(U32, (model < 3 : U32), model, 0)
  pep.accept(ok && (pay <= n : U32) && (end <= n : U32) && (end >= pay : U32), src, pal, width, height, (format .&. 3 : U32), kind, pcount, pay, size)

def pep.hd.p8.done(+width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +size: U32, +n: U32, state: Pal8) -> Loaded:
  Pal8{src, pal, +pay, +kept, ok} = state
  pep.hd.pay(ok, src, pal, width, height, format, model, pcount, pay, size, (n .|. (kept .&. 0) : U32))

def pep.hd.p8(+count: U32, rgb: Bool, +width: U32, +height: U32, +format: U32, +model: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  pep.hd.p8.done(width, height, format, model, count, size, n, pep.p8(U32.to_nat(count), 0, rgb, Pal8{src, Array.new(U32, pep.depth(count), 0), i, n, True{}}))

def pep.hd.narrow.done(+width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +size: U32, +n: U32, state: Bits) -> Loaded:
  Bits{src, pal, +pay, +kept, buf, held, ok} = state
  pep.hd.pay(ok, src, pal, width, height, format, model, pcount, pay, size, (n .|. buf .|. held .|. (kept .&. 0) : U32))

def pep.hd.narrow(+channel: U32, +count: U32, rgb: Bool, +width: U32, +height: U32, +format: U32, +model: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  +mask = ((1 << U32.to_nat(channel)) - 1 : U32)
  pep.hd.narrow.done(width, height, format, model, count, size, n, pep.bpal(U32.to_nat(count), 0, channel, mask, rgb, Bits{src, Array.new(U32, pep.depth(count), 0), i, n, 0, 0, True{}}))

def pep.hd.keep.open(+channel: U32, read: Array<U32> & U32) -> Array<U32>:
  (src, value) = read
  Array.set(U32, src, 0, (value .|. (channel .&. 0) : U32))

def pep.hd.keep(+channel: U32, src: Array<U32>) -> Array<U32>:
  pep.hd.keep.open(channel, Array.get(U32, src, 0))

def pep.hd.parse(wide: Bool, rgb: Bool, +channel: U32, +count: U32, +width: U32, +height: U32, +format: U32, +model: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  match wide:
    case True{}: pep.hd.p8(count, rgb, width, height, format, model, size, n, i, pep.hd.keep(channel, src))
    case False{}: pep.hd.narrow(channel, count, rgb, width, height, format, model, size, n, i, src)

def pep.hd.fit(fit: Bool, wide: Bool, rgb: Bool, +channel: U32, +count: U32, +width: U32, +height: U32, +format: U32, +model: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  match fit:
    case False{}: pep.bad(src, (channel .|. count .|. width .|. height .|. format .|. model .|. size .|. n .|. i .|. Bool.pick(U32, wide, 1, 0) .|. Bool.pick(U32, rgb, 1, 0) : U32))
    case True{}: pep.hd.parse(wide, rgb, channel, count, width, height, format, model, size, n, i, src)

def pep.hd.ready(+psize: U32, +flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  +format = (flags .&. 3 : U32)
  +bits = ((flags >> 2n) .&. 3 : U32)
  +rgb = (((flags >> 5n) .&. 1) > 0 : U32)
  +count = Bool.pick(U32, U32.is_eq(psize, 0), 256, psize)
  +channel = (1 << U32.to_nat(bits) : U32)
  +wide = U32.is_eq(channel, 8)
  +channels = Bool.pick(U32, rgb, 3, 4)
  +pbytes = Bool.pick(U32, wide, (count * channels : U32), ((((channel * channels) * count) + 7) >> 3n : U32))
  +remain = (n - i : U32)
  pep.hd.fit((i <= n : U32) && (remain >= pbytes : U32) && ((remain - pbytes) >= size : U32), wide, rgb, channel, count, width, height, format, model, size, n, i, src)

def pep.hd.ps.byte(+flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. width .|. height .|. size .|. n .|. i .|. byte : U32))
    case Got{True{}, +i, +psize}: pep.hd.ready(psize, flags, model, width, height, size, n, i, src)

def pep.hd.ps.got(+flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.ps.byte(flags, model, width, height, size, n, src, got)

def pep.hd.ps(+flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  pep.hd.ps.got(flags, model, width, height, size, n, pep.rd((i < n : U32), i, src))

def pep.hd.bit.go(fit: Bool, +format: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  match fit:
    case False{}: pep.bad(src, (format .|. model .|. width .|. height .|. size .|. n .|. i : U32))
    case True{}:
      +c0 = Bool.pick(U32, (format <= 1 : U32), 4278190080, 255)
      pep.hd.pay(True{}, src, Array.set(U32, Array.set(U32, Array.new(U32, 1n, 0), 0, c0), 1, 4294967295), width, height, format, model, 2, i, size, n)

def pep.hd.bit(+flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  +format = (flags .&. 3 : U32)
  pep.hd.bit.go((i <= n : U32) && ((n - i) >= size : U32), format, model, width, height, size, n, i, src)

def pep.hd.branch(bitmap: Bool, +flags: U32, +model: U32, +width: U32, +height: U32, +size: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  match bitmap:
    case True{}: pep.hd.bit(flags, model, width, height, size, n, i, src)
    case False{}: pep.hd.ps(flags, model, width, height, size, n, i, src)

def pep.hd.vint(+flags: U32, +model: U32, +width: U32, +height: U32, +n: U32, src: Array<U32>, vint: Vint) -> Loaded:
  match vint:
    case Vint{False{}, +i, +size, +shift, more}: pep.bad(src, (flags .|. model .|. width .|. height .|. n .|. i .|. size .|. shift .|. Bool.pick(U32, more, 1, 0) : U32))
    case Vint{True{}, +i, +size, +shift, more}: pep.hd.branch((((flags >> 6n) .&. 1) > 0 : U32), flags, model, width, height, (size .|. (shift .&. 0) .|. Bool.pick(U32, more, 0, 0) : U32), n, i, src)

def pep.hd.sized(+flags: U32, +model: U32, +width: U32, +height: U32, +n: U32, read: Array<U32> & Vint) -> Loaded:
  (src, vint) = read
  pep.hd.vint(flags, model, width, height, n, src, vint)

def pep.hd.after(+flags: U32, +model: U32, +width: U32, +height: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  pep.hd.sized(flags, model, width, height, n, pep.vint(6n, n, (src, Vint{True{}, i, 0, 0, True{}})))

def pep.hd.h.go(+flags: U32, +model: U32, +n: U32, +w: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. n .|. w .|. i .|. byte : U32))
    case Got{True{}, +i, +h}: pep.hd.after(flags, model, (w + 1 : U32), (h + 1 : U32), n, i, src)

def pep.hd.h(+flags: U32, +model: U32, +n: U32, +w: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.h.go(flags, model, n, w, src, got)

def pep.hd.w.go(+flags: U32, +model: U32, +n: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. n .|. i .|. byte : U32))
    case Got{True{}, +i, +w}: pep.hd.h(flags, model, n, w, pep.rd((i < n : U32), i, src))

def pep.hd.w(+flags: U32, +model: U32, +n: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.w.go(flags, model, n, src, got)

def pep.hd.b2.pack(+flags: U32, +model: U32, +n: U32, +b0: U32, +b1: U32, +b2: U32, +i: U32, src: Array<U32>) -> Loaded:
  +packed = ((b0 << 16n) .|. (b1 << 8n) .|. b2 : U32)
  pep.hd.after(flags, model, ((((packed >> 12n) .&. 4095) + 1) : U32), (((packed .&. 4095) + 1) : U32), n, i, src)

def pep.hd.b2.go(+flags: U32, +model: U32, +n: U32, +b0: U32, +b1: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. n .|. b0 .|. b1 .|. i .|. byte : U32))
    case Got{True{}, +i, +b2}: pep.hd.b2.pack(flags, model, n, b0, b1, b2, i, src)

def pep.hd.b2(+flags: U32, +model: U32, +n: U32, +b0: U32, +b1: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.b2.go(flags, model, n, b0, b1, src, got)

def pep.hd.b1.go(+flags: U32, +model: U32, +n: U32, +b0: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. n .|. b0 .|. i .|. byte : U32))
    case Got{True{}, +i, +b1}: pep.hd.b2(flags, model, n, b0, b1, pep.rd((i < n : U32), i, src))

def pep.hd.b1(+flags: U32, +model: U32, +n: U32, +b0: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.b1.go(flags, model, n, b0, src, got)

def pep.hd.b0.go(+flags: U32, +model: U32, +n: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. model .|. n .|. i .|. byte : U32))
    case Got{True{}, +i, +b0}: pep.hd.b1(flags, model, n, b0, pep.rd((i < n : U32), i, src))

def pep.hd.b0(+flags: U32, +model: U32, +n: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.b0.go(flags, model, n, src, got)

def pep.hd.small(small: Bool, +flags: U32, +model: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  match small:
    case True{}: pep.hd.w(flags, model, n, pep.rd((i < n : U32), i, src))
    case False{}: pep.hd.b0(flags, model, n, pep.rd((i < n : U32), i, src))

def pep.hd.dims(+flags: U32, +model: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  pep.hd.small((((flags >> 4n) .&. 1) > 0 : U32), flags, model, n, i, src)

def pep.hd.model.byte(+flags: U32, +n: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (flags .|. n .|. i .|. byte : U32))
    case Got{True{}, +i, +model}: pep.hd.dims(flags, model, n, i, src)

def pep.hd.model.read(+flags: U32, +n: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.model.byte(flags, n, src, got)

def pep.hd.model(+flags: U32, +n: U32, +i: U32, src: Array<U32>) -> Loaded:
  pep.hd.model.read(flags, n, pep.rd((i < n : U32), i, src))

def pep.hd.flags.byte(+n: U32, src: Array<U32>, got: Got) -> Loaded:
  match got:
    case Got{False{}, +i, +byte}: pep.bad(src, (n .|. i .|. byte : U32))
    case Got{True{}, +i, +flags}: pep.hd.model(flags, n, i, src)

def pep.hd.flags(+n: U32, read: Array<U32> & Got) -> Loaded:
  (src, got) = read
  pep.hd.flags.byte(n, src, got)

def pep.hd(src: Array<U32>, +n: U32) -> Loaded:
  pep.hd.flags(n, pep.rd((0 < n : U32), 0, src))

def pep.nil.parts(+a: U32, +b: U32, +c: U32) -> +List<U32>:
  pep.list.nil((a .|. b .|. c : U32))

def pep.nil.loaded(src: Array<U32>, pal: Array<U32>, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32) -> +List<U32>:
  pep.nil.parts(pep.arr.touch(src), pep.arr.touch(pal), (width .|. height .|. format .|. model .|. pcount .|. pay .|. size : U32))

def pep.use.ok(ok: Bool, +dst: U32, +transparent: U32, +pre: U32, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32, src: Array<U32>, pal: Array<U32>) -> +List<U32>:
  match ok:
    case False{}: pep.nil.loaded(src, pal, width, height, format, model, pcount, pay, size)
    case True{}: pep.decode(dst, transparent, pre, width, height, format, model, pcount, pay, size, src, pal)

def pep.use.loaded(+dst: U32, +transparent: U32, +pre: U32, loaded: Loaded) -> +List<U32>:
  Loaded{ok, src, pal, +width, +height, +format, +model, +pcount, +pay, +size} = loaded
  pep.use.ok(ok, dst, transparent, pre, width, height, format, model, pcount, pay, size, src, pal)

def pep.rev(xs: +List<U32>, +n: U32, acc: +List<U32>) -> U32 & +List<U32>:
  match xs:
    case Nil{}: (n, acc)
    case Con{+head, rest}: pep.rev(rest, (n + 1 : U32), Con{head, acc})

def pep.fill.rev(xs: +List<U32>, +i: U32, src: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}: src
    case Con{+head, rest}: pep.fill.rev(rest, (i - 1 : U32), Array.set(U32, src, i, head))

def pep.pixels.drop(file: +List<U32>) -> +List<U32>:
  pep.list.nil(pep.span(file))

def pep.pixels.run(+dst: U32, +transparent: U32, +pre: U32, +n: U32, file: +List<U32>) -> +List<U32>:
  pep.use.loaded(dst, transparent, pre, pep.hd(pep.fill.rev(file, (n - 1 : U32), Array.new(U32, pep.depth(n), 0)), n))

def pep.pixels.go(ok: Bool, +dst: U32, +transparent: U32, +pre: U32, +n: U32, file: +List<U32>) -> +List<U32>:
  match ok:
    case False{}: pep.pixels.drop(file)
    case True{}: pep.pixels.run(dst, transparent, pre, n, file)

def pep.pixels.open(+dst: U32, +transparent: U32, +pre: U32, read: U32 & +List<U32>) -> +List<U32>:
  (+n, file) = read
  pep.pixels.go((n > 0 : U32) && (n <= 65536 : U32), dst, transparent, pre, n, file)

# Decompressed pixels, or the empty list when the file is refused.
# out format, first-color transparency and premultiplication follow pep_decompress.
def pixels(+dst: U32, +transparent: U32, +premultiply: U32, file: +List<U32>) -> +List<U32>:
  pep.pixels.open(dst, transparent, premultiply, pep.rev(file, 0, Nil{}))

# Width, height and pixels. A refused file is 0 by 0 and an empty pixel list.
type Shot is Type:
  Shot{width: U32, height: U32, pixels: +List<U32>}

def pep.shot.none(src: Array<U32>, pal: Array<U32>, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32) -> Shot:
  Shot{0, 0, pep.nil.loaded(src, pal, width, height, format, model, pcount, pay, size)}

def pep.shot.some(+width: U32, +height: U32, +dst: U32, +transparent: U32, +pre: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32, src: Array<U32>, pal: Array<U32>) -> Shot:
  Shot{width, height, pep.decode(dst, transparent, pre, width, height, format, model, pcount, pay, size, src, pal)}

def pep.shot.ok(ok: Bool, +dst: U32, +transparent: U32, +pre: U32, +width: U32, +height: U32, +format: U32, +model: U32, +pcount: U32, +pay: U32, +size: U32, src: Array<U32>, pal: Array<U32>) -> Shot:
  match ok:
    case False{}: pep.shot.none(src, pal, width, height, format, model, pcount, pay, size)
    case True{}: pep.shot.some(width, height, dst, transparent, pre, format, model, pcount, pay, size, src, pal)

def pep.use.shot(+dst: U32, +transparent: U32, +pre: U32, loaded: Loaded) -> Shot:
  Loaded{ok, src, pal, width, height, format, model, pcount, pay, size} = loaded
  pep.shot.ok(ok, dst, transparent, pre, width, height, format, model, pcount, pay, size, src, pal)

def pep.shot.run(+dst: U32, +transparent: U32, +pre: U32, +n: U32, file: +List<U32>) -> Shot:
  pep.use.shot(dst, transparent, pre, pep.hd(pep.fill.rev(file, (n - 1 : U32), Array.new(U32, pep.depth(n), 0)), n))

def pep.shot.drop(file: +List<U32>) -> Shot:
  Shot{0, 0, pep.pixels.drop(file)}

def pep.shot.go(ok: Bool, +dst: U32, +transparent: U32, +pre: U32, +n: U32, file: +List<U32>) -> Shot:
  match ok:
    case False{}: pep.shot.drop(file)
    case True{}: pep.shot.run(dst, transparent, pre, n, file)

def pep.shot.open(+dst: U32, +transparent: U32, +pre: U32, read: U32 & +List<U32>) -> Shot:
  (+n, file) = read
  pep.shot.go((n > 0 : U32) && (n <= 65536 : U32), dst, transparent, pre, n, file)

def picture(+dst: U32, +transparent: U32, +premultiply: U32, file: +List<U32>) -> Shot:
  pep.shot.open(dst, transparent, premultiply, pep.rev(file, 0, Nil{}))
