# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib's rprand 1.0 (Ramon Santamaria, 2023).
# SplitMix64 / Xoshiro128** credits and notices are retained in LICENSES/rprand.txt.
import Base
import ./resize_numeric.bend as N

type State is Data:
  State{a: U32, b: U32, c: U32, d: U32}

def xor(a: N.Wide, b: N.Wide) -> N.Wide:
  N.Wide{ah, al} = a
  N.Wide{bh, bl} = b
  N.Wide{U32.xor(ah, bh), U32.xor(al, bl)}

def multiply(n: Nat, +bits: N.Wide, +value: N.Wide, +acc: N.Wide) -> N.Wide:
  match n:
    case 0n: acc
    case 1n+k:
      multiply(k, N.Wide.shr1(bits), N.Wide.shl1(value), Bool.pick(N.Wide, N.Wide.odd(bits), N.Wide.add(acc, value), acc))

def splitmix(+value: N.Wide) -> N.Wide:
  first = xor(value, N.Wide.shr(30n, value))
  +second = multiply(64n, N.Wide{3210233709, 484763065}, first, N.Wide.zero())
  third = xor(second, N.Wide.shr(27n, second))
  +fourth = multiply(64n, N.Wide{2496678331, 321982955}, third, N.Wide.zero())
  xor(fourth, N.Wide.shr(31n, fourth))

def seeded(first: N.Wide, second: N.Wide, third: N.Wide, fourth: N.Wide) -> State:
  N.Wide{_, a} = first
  N.Wide{b, _} = second
  N.Wide{_, c} = third
  N.Wide{d, _} = fourth
  State{a, b, c, d}

def seed(value: U32) -> State:
  +increment = {N.Wide{2654435769, 2135587861} : N.Wide}
  +first = N.Wide.add(N.Wide{0, value}, increment)
  +second = N.Wide.add(first, increment)
  +third = N.Wide.add(second, increment)
  fourth = N.Wide.add(third, increment)
  seeded(splitmix(first), splitmix(second), splitmix(third), splitmix(fourth))

def rotate(+value: U32, +shift: Nat) -> U32:
  (U32.shln(value, shift) .|. U32.shrn(value, (32n - shift : Nat)) : U32)

def next(state: State) -> State & U32:
  State{+a, +b, c, d} = state
  output = (rotate((b * 5 : U32), 7n) * 9 : U32)
  shift = (b << 9n : U32)
  +c1 = U32.xor(c, a)
  +d1 = U32.xor(d, b)
  (State{U32.xor(a, d1), U32.xor(b, c1), U32.xor(c1, shift), rotate(d1, 11n)}, output)
