# Jonlib - original additions zlib, Copyright (c) 2026 Jonathan Peris.
# Prediction-Encoded Pixels adapted from ENDESGA's CC0 pep.h in raylib 6.2.
# Altered owned Bend implementation. A color's first byte is its low 8 bits,
# the little-endian layout of the pinned Linux comparison. The context slab is
# sized to the pixel count, so images above 4096 pixels are refused.
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
