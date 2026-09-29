# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered raylib ComputeSHA1/ComputeSHA256 adaptation; see LICENSES/raylib.txt.
# Native SHA-256's four-byte padding-size rule is intentionally retained.
import Base
import ./checksum.bend as C

type Digest is Data:
  Digest{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

type State is Type:
  State{message: Array<U32>, schedule: Array<U32>, constants: Array<U32>, digest: Digest}

def constants(sha256: Bool) -> Array<U32>:
  match sha256:
    case False{}: Array.new(U32, 0n, 0)
    case True{}:
      C.table([
        1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
        3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
        3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
        2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
        666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
        2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
        430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
        1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298
      ], 0, Array.new(U32, 6n, 0))

def packed(a: U32, b: U32, c: U32, d: U32) -> U32:
  ((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32)

def message(bytes: +List<U32>, +index: U32, output: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: Array.set(U32, output, index, 2147483648)
    case Con{a, Nil{}}: Array.set(U32, output, index, packed(a, 128, 0, 0))
    case Con{a, Con{b, Nil{}}}: Array.set(U32, output, index, packed(a, b, 128, 0))
    case Con{a, Con{b, Con{c, Nil{}}}}: Array.set(U32, output, index, packed(a, b, c, 128))
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: message(rest, (index + 1 : U32), Array.set(U32, output, index, packed(a, b, c, d)))

def loaded_word(index: U32, schedule: Array<U32>, result: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (message, word) = result
  (message, Array.set(U32, schedule, index, word))

def load(n: Nat, +index: U32, +offset: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+rest Tuple{message, schedule}:
      load(rest, (index + 1 : U32), offset, loaded_word(index, schedule, Array.get(U32, message, (offset + index : U32))))

def right(+value: U32, +shift: Nat) -> U32:
  ((value >> shift) .|. (value << Nat.sub(32n, shift)) : U32)

def xored(sum: U32, result: Array<U32> & U32) -> Array<U32> & U32:
  (schedule, value) = result
  (schedule, (sum .^. value : U32))

def xor_at(index: U32, state: Array<U32> & U32) -> Array<U32> & U32:
  (schedule, sum) = state
  xored(sum, Array.get(U32, schedule, index))

def sigma(kind: U32, +value: U32) -> U32:
  match kind:
    case 0: value
    case 1: (right(value, 7n) .^. right(value, 18n) .^. (value >> 3n) : U32)
    case _: (right(value, 17n) .^. right(value, 19n) .^. (value >> 10n) : U32)

def summed(kind: U32, sum: U32, result: Array<U32> & U32) -> Array<U32> & U32:
  (schedule, value) = result
  (schedule, (sum + sigma(kind, value) : U32))

def sum_at(kind: U32, index: U32, state: Array<U32> & U32) -> Array<U32> & U32:
  (schedule, sum) = state
  summed(kind, sum, Array.get(U32, schedule, index))

def extended(rotate: Bool, index: U32, result: Array<U32> & U32) -> Array<U32>:
  (schedule, +value) = result
  Array.set(U32, schedule, index, Bool.pick(U32, rotate, C.rotate(value, 1n), value))

def expansion(sha256: Bool, +index: U32, schedule: Array<U32>) -> Array<U32>:
  match sha256:
    case False{}:
      a = xor_at((index - 3 : U32), (schedule, 0))
      b = xor_at((index - 8 : U32), a)
      c = xor_at((index - 14 : U32), b)
      extended(True{}, index, xor_at((index - 16 : U32), c))
    case True{}:
      a = sum_at(2, (index - 2 : U32), (schedule, 0))
      b = sum_at(0, (index - 7 : U32), a)
      c = sum_at(1, (index - 15 : U32), b)
      extended(False{}, index, sum_at(0, (index - 16 : U32), c))

def expand(n: Nat, +index: U32, +sha256: Bool, schedule: Array<U32>) -> Array<U32>:
  match n:
    case 0n: schedule
    case 1n+rest: expand(rest, (index + 1 : U32), sha256, expansion(sha256, index, schedule))

def one_mix(phase: U32, +b: U32, +c: U32, +d: U32) -> U32:
  match phase:
    case 0: ((b .&. c) .|. (U32.not(b) .&. d) : U32)
    case 2: ((b .&. c) .|. (b .&. d) .|. (c .&. d) : U32)
    case _: (b .^. c .^. d : U32)

def one_constant(phase: U32) -> U32:
  match phase:
    case 0: 1518500249
    case 1: 1859775393
    case 2: 2400959708
    case _: 3395469782

def one_word(index: U32, message: Array<U32>, constants: Array<U32>, digest: Digest, result: Array<U32> & U32) -> State:
  Digest{+a, +b, +c, +d, e, _, _, _} = digest
  (schedule, word) = result
  +phase = (index / 20 : U32)
  next = (C.rotate(a, 5n) + one_mix(phase, b, c, d) + e + one_constant(phase) + word : U32)
  State{message, schedule, constants, Digest{next, a, C.rotate(b, 30n), c, d, 0, 0, 0}}

def two_word(constant: U32, message: Array<U32>, constants: Array<U32>, digest: Digest, result: Array<U32> & U32) -> State:
  Digest{+a, +b, +c, d, +e, +f, +g, h} = digest
  (schedule, word) = result
  e1 = (right(e, 6n) .^. right(e, 11n) .^. right(e, 25n) : U32)
  ch = ((e .&. f) .^. (U32.not(e) .&. g) : U32)
  +t1 = (h + e1 + ch + constant + word : U32)
  e0 = (right(a, 2n) .^. right(a, 13n) .^. right(a, 22n) : U32)
  maj = ((a .&. b) .^. (a .&. c) .^. (b .&. c) : U32)
  t2 = (e0 + maj : U32)
  State{message, schedule, constants, Digest{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}}

def two_constant(index: U32, message: Array<U32>, schedule: Array<U32>, digest: Digest, result: Array<U32> & U32) -> State:
  (constants, value) = result
  two_word(value, message, constants, digest, Array.get(U32, schedule, index))

def round(sha256: Bool, +index: U32, state: State) -> State:
  match sha256 state:
    case False{} State{message, schedule, constants, digest}: one_word(index, message, constants, digest, Array.get(U32, schedule, index))
    case True{} State{message, schedule, constants, digest}: two_constant(index, message, schedule, digest, Array.get(U32, constants, index))

def rounds(n: Nat, +index: U32, +sha256: Bool, state: State) -> State:
  match n:
    case 0n: state
    case 1n+rest: rounds(rest, (index + 1 : U32), sha256, round(sha256, index, state))

def added(previous: Digest, state: State) -> State:
  Digest{a, b, c, d, e, f, g, h} = previous
  State{message, schedule, constants, Digest{x0, x1, x2, x3, x4, x5, x6, x7}} = state
  State{message, schedule, constants, Digest{(a + x0 : U32), (b + x1 : U32), (c + x2 : U32), (d + x3 : U32),
    (e + x4 : U32), (f + x5 : U32), (g + x6 : U32), (h + x7 : U32)}}

def loaded(+sha256: Bool, constants: Array<U32>, +digest: Digest, buffers: Array<U32> & Array<U32>) -> State:
  (message, schedule) = buffers
  words = expand(Bool.pick(Nat, sha256, 48n, 64n), 16, sha256, schedule)
  added(digest, rounds(Bool.pick(Nat, sha256, 64n, 80n), 0, sha256, State{message, words, constants, digest}))

def block(sha256: Bool, offset: U32, state: State) -> State:
  State{message, schedule, constants, digest} = state
  loaded(sha256, constants, digest, load(16n, 0, offset, (message, schedule)))

def words(sha256: Bool, digest: Digest) -> +List<U32>:
  match sha256 digest:
    case False{} Digest{a, b, c, d, e, _, _, _}: [a, b, c, d, e]
    case True{} Digest{a, b, c, d, e, f, g, h}: [a, b, c, d, e, f, g, h]

def blocks(n: Nat, +offset: U32, +sha256: Bool, state: State) -> +List<U32>:
  match n state:
    case 0n State{_, _, _, digest}: words(sha256, digest)
    case 1n+rest _: blocks(rest, (offset + 16 : U32), sha256, block(sha256, offset, state))

def initial(sha256: Bool) -> Digest:
  match sha256:
    case False{}: Digest{1732584193, 4023233417, 2562383102, 271733878, 3285377520, 0, 0, 0}
    case True{}: Digest{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def checked(size: Maybe<&2, U32>, +sha256: Bool, bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  match size:
    case None{}: None{}
    case Some{+length}:
      +count = ((((length + Bool.pick(U32, sha256, 4, 8)) / 64) + 1) * 16 : U32)
      depth = {1n+U32.log2((count - 1 : U32)) : Nat}
      input = message(bytes, 0, Array.new(U32, depth, 0))
      padded = Array.set(U32, Array.set(U32, input, (count - 2 : U32), 0), (count - 1 : U32), (length * 8 : U32))
      Some{blocks(U32.to_nat((count / 16 : U32)), 0, sha256, State{padded, Array.new(U32, 7n, 0), constants(sha256), initial(sha256)})}

def hash(sha256: Bool, +bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  checked(C.input_size(bytes, 0, True{}), sha256, bytes)
