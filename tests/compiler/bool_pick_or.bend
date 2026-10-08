# Pinned-toolchain defect repro: a Bool.pick(Bool, ...) result feeding || in
# the same def. Every call should print 2; the native lanes print 1 from the
# sixth call (JavaScript is correct). See docs/VERIFICATION.md.
import Base

def head(rest: +List<U32>) -> U32:
  match rest:
    case Con{value, _}: value
    case Nil{}: 0

def at(+bytes: +List<U32>, +index: U32) -> U32:
  head(List.drop(&2, U32, bytes, U32.to_nat(index)))

def tag(+bytes: +List<U32>, +index: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> Bool:
  U32.is_eq(at(bytes, index), a) && U32.is_eq(at(bytes, (index + 1 : U32)), b)
    && U32.is_eq(at(bytes, (index + 2 : U32)), c) && U32.is_eq(at(bytes, (index + 3 : U32)), d)

def kind(+here: +List<U32>, +i: U32) -> U32:
  Bool.pick(U32, tag(here, i, 78, 79, 78, 69), 1,
  Bool.pick(U32, tag(here, i, 114, 97, 119, 32), 2,
  Bool.pick(U32, tag(here, i, 115, 111, 119, 116), 4,
  Bool.pick(U32, tag(here, i, 102, 108, 51, 50) || tag(here, i, 102, 108, 54, 52) || tag(here, i, 70, 76, 51, 50) || tag(here, i, 70, 76, 54, 52), 3,
  Bool.pick(U32, tag(here, i, 97, 108, 97, 119) || tag(here, i, 65, 76, 65, 87), 6,
  Bool.pick(U32, tag(here, i, 117, 108, 97, 119) || tag(here, i, 85, 76, 65, 87), 7, 0))))))

def f(+here: +List<U32>, +flag: Bool, +n: U32) -> U32:
  +bad = Bool.pick(Bool, flag, False{}, U32.is_ne(n, 18))
  +k = Bool.pick(U32, flag, kind(here, 18), 1)
  Bool.pick(U32, bad || False{}, 2, k)

def bytes() -> +List<U32>:
  [0, 1, 0, 0, 0, 4, 0, 16, 64, 11, 250, 0, 0, 0, 0, 0, 0, 0, 83, 83, 78, 68, 0, 0, 0, 16]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
    IO.print(U32.show(f(bytes(), False{}, 17)))
