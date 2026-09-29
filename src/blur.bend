# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered adaptation of raylib ImageBlurGaussian; see LICENSES/raylib.txt.
import Base
import ./../jonmath.bend as M

type Row is Type:
  Row{source: Array<M.Vector4>, output: Array<M.Vector4>, sum: M.Vector4, count: U32}

def unpack(color: U32) -> M.Vector4:
  +value = color
  M.Vector4{U32.to_f32((value >> 24n : U32)), U32.to_f32(((value >> 16n) .&. 255 : U32)),
    U32.to_f32(((value >> 8n) .&. 255 : U32)), U32.to_f32((value .&. 255 : U32))}

def average(sum: M.Vector4, count: U32) -> M.Vector4:
  +divisor = U32.to_f32(count)
  M.Vector4.divide(sum, M.Vector4{divisor, divisor, divisor, divisor})

def quantize(value: M.Vector4) -> M.Vector4:
  M.Vector4{r, g, b, a} = value
  M.Vector4{U32.to_f32(F32.to_u32(r)), U32.to_f32(F32.to_u32(g)), U32.to_f32(F32.to_u32(b)), U32.to_f32(F32.to_u32(a))}

def divided(vertical: Bool, sum: M.Vector4, count: U32) -> M.Vector4:
  match vertical:
    case False{}: average(sum, count)
    case True{}: quantize(average(sum, count))

def received(add: Bool, output: Array<M.Vector4>, sum: M.Vector4, count: U32, read: Array<M.Vector4> & M.Vector4) -> Row:
  match add read:
    case True{} Tuple{source, value}: Row{source, output, M.Vector4.add(sum, value), (count + 1 : U32)}
    case False{} Tuple{source, value}: Row{source, output, M.Vector4.subtract(sum, value), (count - 1 : U32)}

def read(add: Bool, index: U32, state: Row) -> Row:
  Row{source, output, sum, count} = state
  received(add, output, sum, count, Array.get(M.Vector4, source, index))

def read_checked(valid: Bool, add: Bool, index: U32, state: Row) -> Row:
  match valid:
    case False{}: state
    case True{}: read(add, index, state)

def initial(n: Nat, +index: U32, +stride: U32, state: Row) -> Row:
  match n:
    case 0n: state
    case 1n+rest: initial(rest, (index + stride : U32), stride, read(True{}, index, state))

def write(vertical: Bool, index: U32, state: Row) -> Row:
  Row{source, output, +sum, +count} = state
  Row{source, Array.set(M.Vector4, output, index, divided(vertical, sum, count)), sum, count}

def step(+vertical: Bool, +position: U32, +length: U32, +size: U32, +start: U32, +stride: U32, state: Row) -> Row:
  removed = read_checked((position > size : U32), False{}, (start + (position - size - 1) * stride : U32), state)
  added = read_checked((position + size < length : U32), True{}, (start + (position + size) * stride : U32), removed)
  write(vertical, (start + position * stride : U32), added)

def positions(n: Nat, +position: U32, +vertical: Bool, +length: U32, +size: U32, +start: U32, +stride: U32, state: Row) -> Row:
  match n:
    case 0n: state
    case 1n+rest: positions(rest, (position + 1 : U32), vertical, length, size, start, stride, step(vertical, position, length, size, start, stride, state))

def finished(state: Row) -> Array<M.Vector4> & Array<M.Vector4>:
  Row{source, output, _, _} = state
  (source, output)

def line(vertical: Bool, +length: U32, +size: U32, +start: U32, +stride: U32, buffers: Array<M.Vector4> & Array<M.Vector4>) -> Array<M.Vector4> & Array<M.Vector4>:
  (source, output) = buffers
  finished(positions(U32.to_nat(length), 0, vertical, length, size, start, stride,
    initial(U32.to_nat(size), start, stride, Row{source, output, M.Vector4.zero(), 0})))

def lines(n: Nat, +start: U32, +line_stride: U32, +vertical: Bool, +length: U32, +size: U32, +stride: U32, buffers: Array<M.Vector4> & Array<M.Vector4>) -> Array<M.Vector4> & Array<M.Vector4>:
  match n buffers:
    case 0n Tuple{source, output}: (output, source)
    case 1n+rest _: lines(rest, (start + line_stride : U32), line_stride, vertical, length, size, stride, line(vertical, length, size, start, stride, buffers))

def iterations(n: Nat, +width: U32, +height: U32, +size: U32, buffers: Array<M.Vector4> & Array<M.Vector4>) -> Array<M.Vector4>:
  match n buffers:
    case 0n Tuple{source, _}: source
    case 1n+rest _:
      horizontal = lines(U32.to_nat(height), 0, width, False{}, width, size, 1, buffers)
      iterations(rest, width, height, size, lines(U32.to_nat(width), 0, 1, True{}, height, size, width, horizontal))

def pack(transparent: Bool, r: F32, g: F32, b: F32, +a: F32) -> U32:
  match transparent:
    case True{}: 0
    case False{}:
      +alpha = (a / 255.0 : F32)
      (F32.to_u32(F32.min((r / alpha : F32), 255.0)) << 24n
        .|. (F32.to_u32(F32.min((g / alpha : F32), 255.0)) << 16n)
        .|. (F32.to_u32(F32.min((b / alpha : F32), 255.0)) << 8n)
        .|. F32.to_u32(a) : U32)

def color(value: M.Vector4) -> U32:
  M.Vector4{r, g, b, +a} = value
  pack(F32.is_eq(a, 0.0), r, g, b, a)

def blur(+width: U32, +height: U32, size: U32, premultiplied: Array<U32>) -> Array<U32>:
  +count = (width * height : U32)
  depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
  source = Array.map(~U32, ~M.Vector4, ~unpack, premultiplied)
  Array.map(~M.Vector4, ~U32, ~color, iterations(4n, width, height, size, (source, Array.new(M.Vector4, depth, M.Vector4.zero()))))
