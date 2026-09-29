# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered adaptation of raylib ImageKernelConvolution; see LICENSES/raylib.txt.
import Base
import ./../jonmath.bend as M

type Kernel is Data:
  Kernel{width: U32, values: +List<F32>}

type State is Type:
  Ready{source: Array<U32>, output: Array<U32>}
  Rejected{source: Array<U32>}

def coefficient(+value: F32) -> Bool:
  +magnitude = F32.abs(value)
  F32.is_eq(value, 0.0) || ((magnitude >= 0.0000152587890625) && (magnitude <= 16.0) : F32)

def inspect(n: Nat, values: +List<F32>, +count: U32, valid: Bool) -> Maybe<&2, U32>:
  match n values valid:
    case _ _ False{}: None{}
    case _ Nil{} True{}: Some{count}
    case 0n _ True{}: None{}
    case 1n+rest Con{value, tail} True{}: inspect(rest, tail, (count + 1 : U32), coefficient(value))

def squared(valid: Bool, width: U32, values: +List<F32>) -> Maybe<&2, Kernel>:
  match valid:
    case False{}: None{}
    case True{}: Some{Kernel{width, values}}

def shape(values: +List<F32>, count: Maybe<&2, U32>) -> Maybe<&2, Kernel>:
  match count:
    case None{}: None{}
    case Some{+length}:
      +width = F32.to_u32(F32.sqrt(U32.to_f32(length)))
      squared(U32.is_eq((width * width : U32), length), width, values)

def normalized(+word: U32) -> M.Vector4:
  M.Vector4{(U32.to_f32((word >> 24n : U32)) / 255.0 : F32),
    (U32.to_f32(((word >> 16n) .&. 255 : U32)) / 255.0 : F32),
    (U32.to_f32(((word >> 8n) .&. 255 : U32)) / 255.0 : F32),
    (U32.to_f32((word .&. 255 : U32)) / 255.0 : F32)}

def received(weight: F32, sum: M.Vector4, result: Array<U32> & U32) -> Array<U32> & M.Vector4:
  (source, word) = result
  (source, M.Vector4.add(sum, M.Vector4.scale(normalized(word), weight)))

def sample(valid: Bool, index: U32, weight: F32, state: Array<U32> & M.Vector4) -> Array<U32> & M.Vector4:
  match valid state:
    case False{} Tuple{source, sum}: (source, M.Vector4.add(sum, M.Vector4.zero()))
    case True{} Tuple{source, sum}: received(weight, sum, Array.get(U32, source, index))

def terms(values: +List<F32>, +index: U32, +size: U32, +width: U32, +count: U32, +at: U32, state: Array<U32> & M.Vector4) -> Array<U32> & M.Vector4:
  match values:
    case Nil{}: state
    case Con{weight, rest}:
      +half = (size / 2 : U32)
      +source_at = (at + (index / size) * width + (index % size) - half * width - half : U32)
      terms(rest, (index + 1 : U32), size, width, count, at, sample((source_at < count : U32), source_at, weight, state))

def packed(r: F32, g: F32, b: F32, alpha: F32) -> U32:
  ((F32.to_u32((F32.clamp(r, 0.0, 1.0) * 255.0 : F32)) << 24n)
    .|. (F32.to_u32((F32.clamp(g, 0.0, 1.0) * 255.0 : F32)) << 16n)
    .|. (F32.to_u32((F32.clamp(b, 0.0, 1.0) * 255.0 : F32)) << 8n)
    .|. F32.to_u32(alpha) : U32)

def stored(valid: Bool, at: U32, output: Array<U32>, source: Array<U32>, r: F32, g: F32, b: F32, alpha: F32) -> State:
  match valid:
    case False{}: Rejected{source}
    case True{}: Ready{source, Array.set(U32, output, at, packed(r, g, b, alpha))}

def pixel(at: U32, output: Array<U32>, result: Array<U32> & M.Vector4) -> State:
  (source, M.Vector4{r, g, b, a}) = result
  +alpha = (a * 255.0 : F32)
  stored(((alpha > (0.0 - 1.0)) && (alpha < 256.0) : F32), at, output, source, r, g, b, alpha)

def pixels(n: Nat, +at: U32, +size: U32, +values: +List<F32>, +width: U32, +count: U32, state: State) -> Result<&1, &1, Array<U32>, Array<U32>>:
  match n state:
    case _ Rejected{source}: Fail{source}
    case 0n Ready{_, output}: Done{output}
    case 1n+rest Ready{source, output}:
      pixels(rest, (at + 1 : U32), size, values, width, count, pixel(at, output, terms(values, 0, size, width, count, at, (source, M.Vector4.zero()))))

def checked(kernel: Maybe<&2, Kernel>, +width: U32, height: U32, source: Array<U32>) -> Result<&1, &1, Array<U32>, Array<U32>>:
  match kernel:
    case None{}: Fail{source}
    case Some{Kernel{size, values}}:
      +count = (width * height : U32)
      depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      pixels(U32.to_nat(count), 0, size, values, width, count, Ready{source, Array.new(U32, depth, 0)})

def apply(width: U32, height: U32, +kernel: +List<F32>, source: Array<U32>) -> Result<&1, &1, Array<U32>, Array<U32>>:
  checked(shape(kernel, inspect(225n, kernel, 0, True{})), width, height, source)
