# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the pinned stb_image GIF LZW state machine.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./codec.bend as C

type Bits is Data:
  Bits{data: +List<U32>, word: U32, count: U32}

type Code is Data:
  Code{value: U32, bits: Bits}

def bits.byte(needed: Bool, bits: Bits) -> Maybe<&2, Bits>:
  match needed bits:
    case False{} _: Some{bits}
    case True{} Bits{Nil{}, _, _}: None{}
    case True{} Bits{Con{byte, data}, word, +count}: Some{Bits{data, (word .|. (byte << U32.to_nat(count)) : U32), (count + 8 : U32)}}

def bits.result(valid: Bool, +width: U32, bits: Bits) -> Maybe<&2, Code>:
  match valid bits:
    case False{} _: None{}
    case True{} Bits{data, +word, count}:
      Some{Code{(word .&. ((1 << U32.to_nat(width)) - 1) : U32), Bits{data, (word >> U32.to_nat(width) : U32), (count - width : U32)}}}

def bits.fill(n: Nat, +width: U32, state: Maybe<&2, Bits>) -> Maybe<&2, Code>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Bits{data, word, +count}}: bits.result((count >= width : U32), width, Bits{data, word, count})
    case 1n+rest Some{Bits{data, word, +count}}: bits.fill(rest, width, bits.byte((count < width : U32), Bits{data, word, count}))

type Sequence is Type:
  Sequence{dictionary: Array<U32>, values: List<U32>}

type Expansion is Type:
  Walking{code: U32, dictionary: Array<U32>, values: List<U32>}
  Expanded{dictionary: Array<U32>, values: List<U32>}

def expansion.read(values: List<U32>, result: Array<U32> & U32) -> Expansion:
  (dictionary, +entry) = result
  Walking{(entry >> 16n : U32), dictionary, Con{(entry .&. 255 : U32), values}}

def expansion.step(literal: Bool, code: U32, dictionary: Array<U32>, values: List<U32>) -> Expansion:
  match literal:
    case True{}: Expanded{dictionary, Con{code, values}}
    case False{}: expansion.read(values, Array.get(U32, dictionary, code))

def expand(n: Nat, +clear: U32, state: Expansion) -> Maybe<Sequence>:
  match n state:
    case _ Expanded{dictionary, values}: Some{Sequence{dictionary, values}}
    case 0n _: None{}
    case 1n+rest Walking{+code, dictionary, values}: expand(rest, clear, expansion.step((code < clear : U32), code, dictionary, values))

type Output is Type:
  Output{at: U32, pixels: Array<U32>}

def put(valid: Bool, +at: U32, value: U32, pixels: Array<U32>) -> Maybe<Output>:
  match valid:
    case False{}: None{}
    case True{}: Some{Output{(at + 1 : U32), Array.set(U32, pixels, at, value)}}

def write(values: List<U32>, +limit: U32, state: Maybe<Output>) -> Maybe<Output>:
  match values state:
    case _ None{}: None{}
    case Nil{} _: state
    case Con{value, rest} Some{Output{+at, pixels}}: write(rest, limit, put((at < limit : U32), at, value, pixels))

type Lookup is Type:
  Lookup{first: U32, dictionary: Array<U32>}

def lookup.read(result: Array<U32> & U32) -> Lookup:
  (dictionary, entry) = result
  Lookup{((entry >> 8n) .&. 255 : U32), dictionary}

def lookup(special: Bool, code: U32, previous_first: U32, dictionary: Array<U32>) -> Lookup:
  match special:
    case True{}: Lookup{previous_first, dictionary}
    case False{}: lookup.read(Array.get(U32, dictionary, code))

type State is Type:
  Running{bits: Bits, width: U32, next: U32, previous: Maybe<&2, U32>, first: U32, cleared: Bool, at: U32, dictionary: Array<U32>, pixels: Array<U32>}
  Finished{pixels: Array<U32>}

def accepted.output(bits: Bits, width: U32, next: U32, code: U32, first: U32, dictionary: Array<U32>, result: Maybe<Output>) -> Maybe<State>:
  match result:
    case None{}: None{}
    case Some{Output{at, pixels}}: Some{Running{bits, width, next, Some{code}, first, True{}, at, dictionary, pixels}}

def accepted.sequence(limit: U32, bits: Bits, width: U32, next: U32, code: U32, first: U32, at: U32, pixels: Array<U32>, sequence: Maybe<Sequence>) -> Maybe<State>:
  match sequence:
    case None{}: None{}
    case Some{Sequence{dictionary, values}}: accepted.output(bits, width, next, code, first, dictionary, write(values, limit, Some{Output{at, pixels}}))

def accepted(clear: U32, limit: U32, bits: Bits, +width: U32, +next: U32, +code: U32, first: U32, at: U32, dictionary: Array<U32>, pixels: Array<U32>) -> Maybe<State>:
  grow = U32.is_eq((next .&. ((1 << U32.to_nat(width)) - 1) : U32), 0) && (next <= 4095 : U32)
  accepted.sequence(limit, bits, (width + Bool.to_u32(grow) : U32), next, code, first, at, pixels,
    expand(8192n, clear, Walking{code, dictionary, Nil{}}))

def data.looked(clear: U32, limit: U32, bits: Bits, width: U32, +next: U32, previous: Maybe<&2, U32>, previous_first: U32, code: U32, at: U32, pixels: Array<U32>, looked: Lookup) -> Maybe<State>:
  match previous looked:
    case None{} Lookup{first, dictionary}: accepted(clear, limit, bits, width, next, code, first, at, dictionary, pixels)
    case Some{old} Lookup{+first, dictionary}:
      entry = ((old << 16n) .|. (previous_first << 8n) .|. first : U32)
      accepted(clear, limit, bits, width, (next + 1 : U32), code, first, at, Array.set(U32, dictionary, next, entry), pixels)

def data.valid(valid: Bool, clear: U32, limit: U32, bits: Bits, width: U32, +next: U32, previous: Maybe<&2, U32>, +previous_first: U32, +code: U32, at: U32, dictionary: Array<U32>, pixels: Array<U32>) -> Maybe<State>:
  match valid:
    case False{}: None{}
    case True{}: data.looked(clear, limit, bits, width, next, previous, previous_first, code, at, pixels,
      lookup(U32.is_eq(code, next), code, previous_first, dictionary))

def finish(valid: Bool, pixels: Array<U32>) -> Maybe<State>:
  match valid:
    case False{}: None{}
    case True{}: Some{Finished{pixels}}

def control(reset: Bool, end: Bool, minimum: U32, +clear: U32, +limit: U32, bits: Bits, width: U32, +next: U32, +previous: Maybe<&2, U32>, first: U32, cleared: Bool, +code: U32, +at: U32, dictionary: Array<U32>, pixels: Array<U32>) -> Maybe<State>:
  match reset end:
    case True{} _: Some{Running{bits, (minimum + 1 : U32), (clear + 2 : U32), None{}, 0, True{}, at, dictionary, pixels}}
    case False{} True{}: finish(U32.is_eq(at, limit), pixels)
    case False{} False{}:
      +has_old = Maybe.is_some(&2, U32, previous)
      data.valid(cleared && (code <= next : U32) && (has_old || (code < clear : U32)) && (Bool.not(has_old) || (next < 8192 : U32)),
        clear, limit, bits, width, next, previous, first, code, at, dictionary, pixels)

def decoded(minimum: U32, +clear: U32, limit: U32, width: U32, next: U32, previous: Maybe<&2, U32>, first: U32, cleared: Bool, at: U32, dictionary: Array<U32>, pixels: Array<U32>, result: Maybe<&2, Code>) -> Maybe<State>:
  match result:
    case None{}: None{}
    case Some{Code{+code, bits}}: control(U32.is_eq(code, clear), U32.is_eq(code, (clear + 1 : U32)), minimum, clear, limit, bits, width, next, previous, first, cleared, code, at, dictionary, pixels)

def run(n: Nat, +minimum: U32, +clear: U32, +limit: U32, state: Maybe<State>) -> Maybe<Array<U32>>:
  match n state:
    case _ None{}: None{}
    case _ Some{Finished{pixels}}: Some{pixels}
    case 0n _: None{}
    case 1n+rest Some{Running{bits, +width, next, previous, first, cleared, at, dictionary, pixels}}:
      run(rest, minimum, clear, limit, decoded(minimum, clear, limit, width, next, previous, first, cleared, at, dictionary, pixels, bits.fill(2n, width, Some{bits})))

def literals(n: Nat, +index: U32, dictionary: Array<U32>) -> Array<U32>:
  match n:
    case 0n: dictionary
    case 1n+rest: literals(rest, (index + 1 : U32), Array.set(U32, dictionary, index, ((index << 8n) .|. index : U32)))

def checked(valid: Bool, +minimum: U32, +limit: U32, +data: +List<U32>) -> Maybe<Array<U32>>:
  match valid:
    case False{}: None{}
    case True{}:
      +clear = (1 << U32.to_nat(minimum) : U32)
      depth = Bool.pick(Nat, U32.is_eq(limit, 1), 0n, 1n+U32.log2((limit - 1 : U32)))
      dictionary = literals(U32.to_nat(clear), 0, Array.new(U32, 13n, 0))
      run((C.byte_count(data, 0n) * 8n : Nat), minimum, clear, limit,
        Some{Running{Bits{data, 0, 0}, (minimum + 1 : U32), (clear + 2 : U32), None{}, 0, False{}, 0, dictionary, Array.new(U32, depth, 0)}})

def decode(+minimum: U32, +limit: U32, data: +List<U32>) -> Maybe<Array<U32>>:
  checked(((minimum >= 2) && (minimum <= 8) && (limit > 0) && (limit <= 16777216) : U32), minimum, limit, data)
