# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Default RGBA8 resampling adapted from stb_image_resize2.h in raylib 6.0.
# Altered Bend implementation; see THIRD_PARTY_NOTICES.md and LICENSES/stb_image_resize2.txt.
import Base
import ./resize_numeric.bend as N

type Kernel is Data:
  Kernel{first: F32, weights: +List<F32>}

def branch(-T: Type, condition: Bool, yes: Unit -> T, no: Unit -> T) -> T:
  Bool.pick(Unit -> T, condition, yes, no)(Unit{})

def capacity(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

def tiny() -> F32:
  (1.0 / 1048576.0 / 1048576.0 / 1048576.0 / 1048576.0 / 1048576.0 / 1048576.0 : F32)

def catmull.route(inner: Bool, outer: Bool, +x: F32) -> F32:
  match inner outer:
    case True{} _: (1.0 - x * x * (2.5 - 1.5 * x) : F32)
    case False{} True{}: (2.0 - x * (4.0 + x * (0.5 * x - 2.5)) : F32)
    case False{} False{}: 0.0

def mitchell.route(inner: Bool, outer: Bool, +x: F32) -> F32:
  match inner outer:
    case True{} _: ((16.0 + x * x * (21.0 * x - 36.0)) / 18.0 : F32)
    case False{} True{}: ((32.0 + x * (0.0 - 60.0 + x * (36.0 - 7.0 * x))) / 18.0 : F32)
    case False{} False{}: 0.0

def filter(up: Bool, +x: F32) -> F32:
  match up:
    case True{}: catmull.route((F32.abs(x) < 1.0 : F32), (F32.abs(x) < 2.0 : F32), F32.abs(x))
    case False{}: mitchell.route((F32.abs(x) < 1.0 : F32), (F32.abs(x) < 2.0 : F32), F32.abs(x))

def gcd(n: Nat, +a: U32, b: U32) -> U32:
  match n b:
    case 0n _: a
    case 1n+k 0: a
    case 1n+k +b: gcd(k, b, (a % b : U32))

def Kernel.push(first: F32, weights: +List<F32>, at: F32, value: F32) -> Kernel:
  match weights:
    case Nil{}: Kernel{at, [value]}
    case Con{head, tail}: Kernel{first, Con{value, Con{head, tail}}}

def Kernel.add(take: Bool, row: Kernel, at: F32, +value: F32) -> Kernel:
  match take:
    case False{}: row
    case True{}:
      Kernel{first, weights} = row
      Kernel.push(first, weights, at, Bool.pick(F32, (F32.abs(value) < tiny() : F32), 0.0, value))

def Kernel.raw(n: Nat, +at: F32, +out: F32, +up: Bool, +scale: F32, +inv: F32, +radius: F32, row: Kernel) -> Kernel:
  match n:
    case 0n: row
    case 1n+k:
      +center = (at + 0.5 : F32)
      +first = F32.floor(((center - radius) * scale + 0.5 : F32))
      +last = F32.floor(((center + radius) * scale - 0.5 : F32))
      +take = up || ((out >= first) && (out <= last) : F32)
      +x = Bool.pick(F32, up, ((out + 0.5) * inv - center : F32), (out + 0.5 - center * scale : F32))
      weight = (filter(up, x) * Bool.pick(F32, up, 1.0, scale) : F32)
      Kernel.raw(k, (at + 1.0 : F32), out, up, scale, inv, radius, Kernel.add(take, row, at, weight))

def drop_zeros(values: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, +rest}:
      branch(+List<F32>, F32.is_eq(value, 0.0), _ => drop_zeros(rest), _ => Con{value, rest})

def Kernel.trim(values: +List<F32>, +first: F32) -> Kernel:
  match values:
    case Nil{}: Kernel{first, Nil{}}
    case Con{+value, +rest}:
      branch(Kernel, F32.is_eq(value, 0.0), _ => Kernel.trim(rest, (first + 1.0 : F32)),
        _ => Kernel{first, N.normalize(Con{value, rest})})

def Kernel.normalize(row: Kernel, shift: F32) -> Kernel:
  Kernel{first, reverse} = row
  Kernel.trim(List.reverse(&2, F32, drop_zeros(reverse)), (first + shift : F32))

def sum(values: +List<F32>, acc: F32) -> F32:
  match values:
    case Nil{}: acc
    case Con{v, rest}: sum(rest, (acc + v : F32))

def fold_right.loop(n: Nat, values: +List<F32>, acc: +List<F32>) -> +List<F32>:
  match n values:
    case _ Nil{}: List.reverse(&2, F32, acc)
    case 0n Con{v, rest}: List.reverse(&2, F32, Con{sum(rest, v), acc})
    case 1n+k Con{v, rest}: fold_right.loop(k, rest, Con{v, acc})

def fold_right(values: +List<F32>, at: F32, last: F32) -> +List<F32>:
  fold_right.loop(F32.to_nat((last - at : F32)), values, Nil{})

def fold_head(values: +List<F32>, left: +List<F32>) -> +List<F32>:
  match values:
    case Nil{}: Nil{}
    case Con{v, rest}: Con{sum(left, v), rest}

def fold_left(n: Nat, values: +List<F32>, +at: F32, +last: F32, left: +List<F32>) -> Kernel:
  match n values:
    case _ Nil{}: Kernel{at, Nil{}}
    case 0n Con{v, rest}: Kernel{at, fold_head(fold_right(Con{v, rest}, at, last), left)}
    case 1n+k Con{v, rest}: fold_left(k, rest, (at + 1.0 : F32), last, Con{v, left})

def Kernel.fold(row: Kernel, size: U32) -> Kernel:
  Kernel{+first, weights} = row
  fold_left(F32.to_nat(F32.max(0.0, F32.neg(first))), weights, first, U32.to_f32((size - 1 : U32)), Nil{})

def Kernel.finish(row: Kernel) -> Kernel:
  Kernel{first, weights} = row
  Kernel{first, List.reverse(&2, F32, drop_zeros(List.reverse(&2, F32, weights)))}

def Kernel.build(equal: Bool, up: Bool, +size: U32, +output: U32, +position: U32) -> Kernel:
  match equal up:
    case True{} _: Kernel{U32.to_f32(position), [1.0]}
    case False{} +up:
      +scale = (U32.to_f32(output) / U32.to_f32(size) : F32)
      +inv = (U32.to_f32(size) / U32.to_f32(output) : F32)
      +divisor = gcd(32n, size, output)
      +numerator = (output / divisor : U32)
      +phase = U32.to_f32((position % numerator : U32))
      shift = U32.to_f32(((position / numerator) * (size / divisor) : U32))
      +radius = (2.0 / scale : F32)
      +margin = F32.floor((F32.ceil((4.0 / scale : F32)) / 2.0 : F32))
      +up_first = F32.floor(((phase + 0.5 - 2.0 * scale) * inv + 0.5 : F32))
      +up_last = F32.floor(((phase + 0.5 + 2.0 * scale) * inv - 0.5 : F32))
      first = Bool.pick(F32, up, up_first, F32.neg(margin))
      count = Bool.pick(F32, up, F32.min(4.0, (F32.max(up_first, up_last) - up_first + 1.0 : F32)), (U32.to_f32(size) + 2.0 * margin : F32))
      Kernel.finish(Kernel.fold(Kernel.normalize(Kernel.raw(F32.to_nat(count), first, phase, up, scale, inv, radius, Kernel{0.0, Nil{}}), shift), size))

def Kernel.make(+size: U32, +output: U32, position: U32) -> Kernel:
  Kernel.build(U32.is_eq(size, output), (output > size : U32), size, output, position)

def prepend_zeros(n: Nat, values: +List<F32>) -> +List<F32>:
  match n:
    case 0n: values
    case 1n+k: prepend_zeros(k, Con{0.0, values})

def weight_count(weights: +List<F32>, +count: U32) -> U32:
  match weights:
    case Nil{}: count
    case Con{_, rest}: weight_count(rest, (count + 1 : U32))

def Kernel.pack(+widest: U32, size: U32, row: Kernel) -> Kernel:
  Kernel{+first, +weights} = row
  +length = U32.to_f32(weight_count(weights, 0))
  +mod = U32.to_f32((widest .&. 3 : U32))
  +stop = Bool.pick(F32, (widest <= 12 : U32), U32.to_f32(widest),
    F32.max((8.0 + mod : F32), (F32.ceil(((length - mod) / 4.0 : F32)) * 4.0 + mod : F32)))
  +start = F32.min(first, (U32.to_f32(size) - stop : F32))
  Kernel{start, prepend_zeros(F32.to_nat((first - start : F32)), weights)}

type Plan is Type:
  Plan{widest: U32, kernels: Array<Kernel>}

def Plan.insert(at: U32, row: Kernel, plan: Plan) -> Plan:
  Kernel{+first, +weights} = row
  Plan{widest, kernels} = plan
  Plan{U32.max(widest, weight_count(weights, 0)), Array.set(Kernel, kernels, at, Kernel{first, weights})}

def Plan.loop(n: Nat, +i: U32, +size: U32, +output: U32, plan: Plan) -> Plan:
  match n:
    case 0n: plan
    case 1n+k: Plan.loop(k, (i + 1 : U32), size, output, Plan.insert(i, Kernel.make(size, output, i), plan))

def Plan.make(size: U32, +output: U32) -> Plan:
  Plan.loop(U32.to_nat(output), 0, size, output, Plan{0, Array.new(Kernel, capacity(output), Kernel{0.0, Nil{}})})

type Sample is Data:
  Sample{r: F32, g: F32, b: F32, a: F32, pr: F32, pg: F32, pb: F32}

def Sample.zero() -> Sample:
  Sample{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

def Sample.decode(+pixel: U32) -> Sample:
  +unit = (1.0 / 255.0 : F32)
  +r = (U32.to_f32((pixel >> 24n : U32)) * unit : F32)
  +g = (U32.to_f32(((pixel >> 16n) .&. 255 : U32)) * unit : F32)
  +b = (U32.to_f32(((pixel >> 8n) .&. 255 : U32)) * unit : F32)
  +a = (U32.to_f32((pixel .&. 255 : U32)) * unit : F32)
  Sample{r, g, b, a, (r * a : F32), (g * a : F32), (b * a : F32)}

def Sample.mul(sample: Sample, +weight: F32) -> Sample:
  Sample{r, g, b, a, pr, pg, pb} = sample
  Sample{(r * weight : F32), (g * weight : F32), (b * weight : F32), (a * weight : F32),
    (pr * weight : F32), (pg * weight : F32), (pb * weight : F32)}

def Sample.add(left: Sample, right: Sample) -> Sample:
  Sample{r, g, b, a, pr, pg, pb} = left
  Sample{r2, g2, b2, a2, pr2, pg2, pb2} = right
  Sample{(r + r2 : F32), (g + g2 : F32), (b + b2 : F32), (a + a2 : F32),
    (pr + pr2 : F32), (pg + pg2 : F32), (pb + pb2 : F32)}

def byte(value: F32) -> U32:
  F32.to_u32(F32.clamp((value * 255.0 + 0.5 : F32), 0.0, 255.0))

def Sample.encode(sample: Sample) -> U32:
  Sample{r, g, b, +a, pr, pg, pb} = sample
  +hidden = (a < tiny() : F32)
  +inv = (1.0 / a : F32)
  +rr = byte(Bool.pick(F32, hidden, r, (pr * inv : F32)))
  +gg = byte(Bool.pick(F32, hidden, g, (pg * inv : F32)))
  +bb = byte(Bool.pick(F32, hidden, b, (pb * inv : F32)))
  ((rr << 24n) .|. (gg << 16n) .|. (bb << 8n) .|. byte(a) : U32)

def decode.step(i: U32, output: Array<Sample>, got: Array<U32> & U32) -> Array<U32> & Array<Sample>:
  (source, pixel) = got
  (source, Array.set(Sample, output, i, Sample.decode(pixel)))

def decode.loop(n: Nat, +i: U32, state: Array<U32> & Array<Sample>) -> Array<Sample>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+k Tuple{source, output}:
      decode.loop(k, (i + 1 : U32), decode.step(i, output, Array.get(U32, source, i)))

def decode(+count: U32, pixels: Array<U32>) -> Array<Sample>:
  decode.loop(U32.to_nat(count), 0, (pixels, Array.new(Sample, capacity(count), Sample.zero())))

def encode.step(i: U32, output: Array<U32>, got: Array<Sample> & Sample) -> Array<Sample> & Array<U32>:
  (source, sample) = got
  (source, Array.set(U32, output, i, Sample.encode(sample)))

def encode.loop(n: Nat, +i: U32, state: Array<Sample> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+k Tuple{source, output}:
      encode.loop(k, (i + 1 : U32), encode.step(i, output, Array.get(Sample, source, i)))

def encode(+count: U32, pixels: Array<Sample>) -> Array<U32>:
  encode.loop(U32.to_nat(count), 0, (pixels, Array.new(U32, capacity(count), 0)))

def gather.step(+odd: Bool, +even_acc: Sample, +odd_acc: Sample, weight: F32, got: Array<Sample> & Sample) -> Array<Sample> & (Sample & Sample):
  (pixels, sample) = got
  +weighted = Sample.mul(sample, weight)
  (pixels, (Bool.pick(Sample, odd, even_acc, Sample.add(even_acc, weighted)),
    Bool.pick(Sample, odd, Sample.add(odd_acc, weighted), odd_acc)))

def gather(weights: +List<F32>, +at: U32, +stride: U32, +alternate: Bool, +odd: Bool, state: Array<Sample> & (Sample & Sample)) -> Array<Sample> & Sample:
  match weights state:
    case Nil{} Tuple{pixels, Tuple{even_acc, odd_acc}}: (pixels, Sample.add(even_acc, odd_acc))
    case Con{weight, rest} Tuple{pixels, Tuple{even_acc, odd_acc}}:
      gather(rest, (at + stride : U32), stride, alternate, Bool.not(odd),
        gather.step(alternate && odd, even_acc, odd_acc, weight, Array.get(Sample, pixels, at)))

def vertical.weights(weights: +List<F32>) -> +List<F32>:
  match weights:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      match rest:
        case Nil{}: [Bool.pick(F32, ((value >= 0.999999) && (value <= 1.000001) : F32), 1.0, value)]
        case Con{v2, more}: Con{value, Con{v2, more}}

type Pass is Type:
  Pass{kernels: Array<Kernel>, source: Array<Sample>, output: Array<Sample>}

def pass.kernel(+vertical: Bool, +i: U32, +width: U32, +stride: U32, +widest: U32, pixels: Array<Sample>, got: Array<Kernel> & Kernel) -> Array<Kernel> & (Array<Sample> & Sample):
  match got:
    case Tuple{kernels, Kernel{+first, +weights}}:
      index = Bool.pick(U32, vertical, (F32.to_u32(first) * stride + i % width : U32), ((i / width) * stride + F32.to_u32(first) : U32))
      (kernels, gather(Bool.pick(+List<F32>, vertical, vertical.weights(weights), weights), index,
        Bool.pick(U32, vertical, stride, 1), Bool.not(vertical) && (widest >= 4 : U32), False{}, (pixels, (Sample.zero(), Sample.zero()))))

def pass.pack(vertical: Bool, widest: U32, stride: U32, got: Array<Kernel> & Kernel) -> Array<Kernel> & Kernel:
  (kernels, +row) = got
  (kernels, Bool.pick(Kernel, vertical, row, Kernel.pack(widest, stride, row)))

def pass.write(i: U32, output: Array<Sample>, result: Array<Kernel> & (Array<Sample> & Sample)) -> Pass:
  match result:
    case Tuple{kernels, Tuple{pixels, sample}}: Pass{kernels, pixels, Array.set(Sample, output, i, sample)}

def pass.loop(n: Nat, +i: U32, +vertical: Bool, +width: U32, +stride: U32, +widest: U32, state: Pass) -> Array<Sample>:
  match n state:
    case 0n Pass{_, _, output}: output
    case 1n+k Pass{kernels, source, output}:
      axis = Bool.pick(U32, vertical, (i / width : U32), (i % width : U32))
      pass.loop(k, (i + 1 : U32), vertical, width, stride, widest,
        pass.write(i, output, pass.kernel(vertical, i, width, stride, widest, source,
          pass.pack(vertical, widest, stride, Array.get(Kernel, kernels, axis)))))

def pass(vertical: Bool, +width: U32, height: U32, stride: U32, plan: Plan, pixels: Array<Sample>) -> Array<Sample>:
  Plan{widest, kernels} = plan
  +count = (width * height : U32)
  pass.loop(U32.to_nat(count), 0, vertical, width, stride, widest,
    Pass{kernels, pixels, Array.new(Sample, capacity(count), Sample.zero())})

type Cost is Data:
  Cost{h0: F32, h1: F32, v0: F32, v1: F32}

def filter_width(+size: U32, +output: U32) -> F32:
  Bool.pick(F32, U32.is_eq(size, output), 1.0,
    Bool.pick(F32, (output > size : U32), 4.0, F32.ceil((4.0 / (U32.to_f32(output) / U32.to_f32(size)) : F32))))

def cost(+nw: U32, +nh: U32, +vertical_scale: F32, +gather: Bool) -> Cost:
  +scatter = {Cost{0.0, 0.59375, 0.0, 0.96875} : Cost}
  regular = Bool.pick(Cost, (vertical_scale <= 1.0 : F32),
    Bool.pick(Cost, gather, Cost{0.0625, 0.8125, 0.0625, 0.59375}, scatter),
    Bool.pick(Cost, (vertical_scale <= 2.0 : F32), Cost{0.75, 0.4375, 0.125, 0.96875},
      Bool.pick(Cost, (vertical_scale <= 3.0 : F32), Cost{0.875, 0.0625, 0.1875, 0.4375}, Cost{0.15625, 0.125, 1.0, 1.0})))
  small = Bool.pick(Cost, Bool.not(gather) && ((nw <= 16) || (nh <= 16) : U32), scatter, regular)
  Bool.pick(Cost, ((nw <= 4) || (nh <= 4) : U32),
    Bool.pick(Cost, (nh < nw : U32), Cost{1.0, 1.0, 0.0625, 1.0}, Cost{0.0, 1.0, 0.03125, 0.34375}), small)

def vertical_first.cost(hs: F32, vs: F32, +hw: F32, +vw: F32, weights: Cost) -> Bool:
  Cost{h0, h1, v0, v1} = weights
  ((vw * v0 + vs * hw * v1) <= (hw * h0 + hs * vw * h1) : F32)

def vertical_first(+sw: U32, +sh: U32, +nw: U32, +nh: U32) -> Bool:
  hs = (U32.to_f32(nw) / U32.to_f32(sw) : F32)
  +vs = (U32.to_f32(nh) / U32.to_f32(sh) : F32)
  hw = filter_width(sw, nw)
  +vw = filter_width(sh, nh)
  vertical_first.cost(hs, vs, hw, vw, cost(nw, nh, vs, (vw <= 32.0 : F32)))

def resize.route(vertical: Bool, +sw: U32, +sh: U32, +nw: U32, +nh: U32, pixels: Array<U32>) -> Array<U32>:
  match vertical:
    case True{}:
      intermediate = pass(True{}, sw, nh, sw, Plan.make(sh, nh), decode((sw * sh : U32), pixels))
      encode((nw * nh : U32), pass(False{}, nw, nh, sw, Plan.make(sw, nw), intermediate))
    case False{}:
      intermediate = pass(False{}, nw, sh, sw, Plan.make(sw, nw), decode((sw * sh : U32), pixels))
      encode((nw * nh : U32), pass(True{}, nw, nh, nw, Plan.make(sh, nh), intermediate))

def resize(+sw: U32, +sh: U32, +nw: U32, +nh: U32, pixels: Array<U32>) -> Array<U32>:
  resize.route(vertical_first(sw, sh, nw, nh), sw, sh, nw, nh, pixels)
