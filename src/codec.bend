# Jonlib - original additions zlib, Copyright (c) 2026 Jonathan Peris.
# Shared vocabulary for the image codec modules: one decode-error type, the
# native-channel image record decoders return, and byte/word readers.
import Base

type Error is Data:
  BadHeader{}
  BadByte{}
  BadSize{}
  Truncated{}
  BadStream{}

# Canonical RGBA words plus the native output channel count (1 gray, 2 gray
# and alpha, 3 RGB, 4 RGBA) that selects raylib's stored pixel format.
type Image is Type:
  Image{width: U32, height: U32, channels: U32, pixels: Array<U32>}

def valid_bytes(bytes: +List<U32>, +valid: Bool) -> Bool:
  match bytes:
    case Nil{}: valid
    case Con{v, rest}: valid_bytes(rest, valid && (v <= 255 : U32))

def byte_count(data: +List<U32>, count: Nat) -> Nat:
  match data:
    case Nil{}: count
    case Con{_, rest}: byte_count(rest, 1n+count)

type Word is Data:
  Word{value: U32, data: +List<U32>}

# Big-endian unsigned word of n bytes.
def read(n: Nat, value: U32, bytes: +List<U32>) -> Maybe<&2, Word>:
  match n bytes:
    case 0n _: Some{Word{value, bytes}}
    case _ Nil{}: None{}
    case 1n+rest Con{byte, tail}: read(rest, ((value << 8n) .|. byte : U32), tail)

def word(bytes: +List<U32>) -> Maybe<&2, Word>:
  read(4n, 0, bytes)

type Words is Data:
  Words{values: +List<U32>, data: +List<U32>}

def words.read(values: +List<U32>, word: Maybe<&2, Word>) -> Maybe<&2, Words>:
  match word:
    case None{}: None{}
    case Some{Word{value, data}}: Some{Words{Con{value, values}, data}}

# n big-endian 16-bit words.
def words(n: Nat, state: Maybe<&2, Words>) -> Maybe<&2, Words>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Words{values, data}}: Some{Words{List.reverse(&2, U32, values), data}}
    case 1n+rest Some{Words{values, data}}: words(rest, words.read(values, read(2n, 0, data)))
