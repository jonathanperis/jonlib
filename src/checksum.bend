# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered adaptation of raylib ComputeMD5 in rcore.c; see LICENSES/raylib.txt.
import Base

def input_size(bytes: +List<U32>, +count: U32, valid: Bool) -> Maybe<&2, U32>:
  match bytes valid:
    case _ False{}: None{}
    case Nil{} True{}: Some{count}
    case Con{byte, rest} True{}: input_size(rest, (count + 1 : U32), ((byte <= 255) && (count < 1048576) : U32))

type MD5 is Data:
  MD5{a: U32, b: U32, c: U32, d: U32}

type State is Type:
  State{message: Array<U32>, constants: Array<U32>, digest: MD5}

def table(values: +List<U32>, +index: U32, output: Array<U32>) -> Array<U32>:
  match values:
    case Nil{}: output
    case Con{value, rest}: table(rest, (index + 1 : U32), Array.set(U32, output, index, value))

def constants() -> Array<U32>:
  table([
    3614090360, 3905402710, 606105819, 3250441966, 4118548399, 1200080426, 2821735955, 4249261313,
    1770035416, 2336552879, 4294925233, 2304563134, 1804603682, 4254626195, 2792965006, 1236535329,
    4129170786, 3225465664, 643717713, 3921069994, 3593408605, 38016083, 3634488961, 3889429448,
    568446438, 3275163606, 4107603335, 1163531501, 2850285829, 4243563512, 1735328473, 2368359562,
    4294588738, 2272392833, 1839030562, 4259657740, 2763975236, 1272893353, 4139469664, 3200236656,
    681279174, 3936430074, 3572445317, 76029189, 3654602809, 3873151461, 530742520, 3299628645,
    4096336452, 1126891415, 2878612391, 4237533241, 1700485571, 2399980690, 4293915773, 2240044497,
    1873313359, 4264355552, 2734768916, 1309151649, 4149444226, 3174756917, 718787259, 3951481745
  ], 0, Array.new(U32, 6n, 0))

def packed(a: U32, b: U32, c: U32, d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

def message(bytes: +List<U32>, +index: U32, output: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: Array.set(U32, output, index, 128)
    case Con{a, Nil{}}: Array.set(U32, output, index, packed(a, 128, 0, 0))
    case Con{a, Con{b, Nil{}}}: Array.set(U32, output, index, packed(a, b, 128, 0))
    case Con{a, Con{b, Con{c, Nil{}}}}: Array.set(U32, output, index, packed(a, b, c, 128))
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: message(rest, (index + 1 : U32), Array.set(U32, output, index, packed(a, b, c, d)))

def rotate(+value: U32, +shift: Nat) -> U32:
  ((value << shift) .|. (value >> Nat.sub(32n, shift)) : U32)

def shifts(phase: U32) -> U32:
  match phase:
    case 0: 370215943
    case 1: 336464133
    case 2: 386927364
    case _: 353307142

def slot(phase: U32, index: U32) -> U32:
  match phase:
    case 0: index
    case 1: ((5 * index + 1) % 16 : U32)
    case 2: ((3 * index + 5) % 16 : U32)
    case _: ((7 * index) % 16 : U32)

def mix(phase: U32, +b: U32, +c: U32, +d: U32) -> U32:
  match phase:
    case 0: ((b .&. c) .|. (U32.not(b) .&. d) : U32)
    case 1: ((d .&. b) .|. (U32.not(d) .&. c) : U32)
    case 2: (b .^. c .^. d : U32)
    case _: (c .^. (b .|. U32.not(d)) : U32)

def word(+index: U32, constant: U32, constants: Array<U32>, digest: MD5, result: Array<U32> & U32) -> State:
  MD5{a, +b, +c, +d} = digest
  (message, value) = result
  +phase = (index / 16 : U32)
  shift = U32.to_nat(((shifts(phase) >> U32.to_nat((8 * (index % 4) : U32))) .&. 255 : U32))
  next = (b + rotate((a + mix(phase, b, c, d) + constant + value : U32), shift) : U32)
  State{message, constants, MD5{d, next, b, c}}

def constant(+index: U32, offset: U32, message: Array<U32>, digest: MD5, result: Array<U32> & U32) -> State:
  (constants, value) = result
  word(index, value, constants, digest, Array.get(U32, message, (offset + slot((index / 16 : U32), index) : U32)))

def round(+index: U32, offset: U32, state: State) -> State:
  State{message, constants, digest} = state
  constant(index, offset, message, digest, Array.get(U32, constants, index))

def rounds(n: Nat, +index: U32, +offset: U32, state: State) -> State:
  match n:
    case 0n: state
    case 1n+rest: rounds(rest, (index + 1 : U32), offset, round(index, offset, state))

def added(previous: MD5, state: State) -> State:
  MD5{a, b, c, d} = previous
  State{message, constants, MD5{w, x, y, z}} = state
  State{message, constants, MD5{(a + w : U32), (b + x : U32), (c + y : U32), (d + z : U32)}}

def block(offset: U32, state: State) -> State:
  State{message, constants, +digest} = state
  added(digest, rounds(64n, 0, offset, State{message, constants, digest}))

def blocks(n: Nat, +offset: U32, state: State) -> +List<U32>:
  match n state:
    case 0n State{_, _, MD5{a, b, c, d}}: [a, b, c, d]
    case 1n+rest _: blocks(rest, (offset + 16 : U32), block(offset, state))

def checked(size: Maybe<&2, U32>, bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  match size:
    case None{}: None{}
    case Some{+length}:
      +words = ((((length + 8) / 64) + 1) * 16 : U32)
      depth = {1n+U32.log2((words - 1 : U32)) : Nat}
      padded = Array.set(U32, message(bytes, 0, Array.new(U32, depth, 0)), (words - 2 : U32), (length * 8 : U32))
      Some{blocks(U32.to_nat((words / 16 : U32)), 0, State{padded, constants(), MD5{1732584193, 4023233417, 2562383102, 271733878}})}

def md5(+bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  checked(input_size(bytes, 0, True{}), bytes)

# Reflected CRC-32 (polynomial 0xEDB88320) register update, one bit at a time.
def crc.bits(n: Nat, +value: U32) -> U32:
  match n:
    case 0n: value
    case 1n+rest: crc.bits(rest, ((value >> 1n) .^. Bool.pick(U32, ((value .&. 1) > 0 : U32), 3988292384, 0) : U32))

def crc(bytes: +List<U32>, value: U32) -> U32:
  match bytes:
    case Nil{}: value
    case Con{byte, rest}: crc(rest, crc.bits(8n, (value .^. byte : U32)))
