# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# When an operand is a NaN, clang returns that operand's bits (the left one
# when both are). The sign of a NaN that an invalid operation produces is not
# fixed by IEEE 754 and is left to the F32 operation.
import Base

def magnitude(value: F32) -> U32:
  (F32.bits(value) .&. 2147483647 : U32)

def nan(value: F32) -> Bool:
  (magnitude(value) > 2139095040 : U32)

def bits(word: U32) -> F32:
  U32{stored} = word
  F32{stored}

def first(left_nan: Bool, +left: F32, +right: F32) -> F32:
  match left_nan:
    case True{}: left
    case False{}: right

def either(present: Bool, +left: F32, +right: F32, value: F32) -> F32:
  match present:
    case True{}: first(nan(left), left, right)
    case False{}: value

def add(+left: F32, +right: F32) -> F32:
  either(nan(left) || nan(right), left, right, (left + right : F32))

def sub(+left: F32, +right: F32) -> F32:
  either(nan(left) || nan(right), left, right, (left - right : F32))

def mul(+left: F32, +right: F32) -> F32:
  either(nan(left) || nan(right), left, right, (left * right : F32))

def div(+left: F32, +right: F32) -> F32:
  either(nan(left) || nan(right), left, right, (left / right : F32))
