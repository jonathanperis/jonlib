# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c: the tables
# init_blocksize computes for a block size (compute_twiddle_factors,
# compute_window, compute_bitreverse). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# The twiddle factors and the window are the C library's binary64 cos and
# sin narrowed to float. Their arguments are exact IEEE products and
# quotients, the same on every host; the functions are the library's. Here
# they are glibc 2.39's (Jonmath's Libm.sin64 and Libm.cos64, the LGPL
# module src/lgpl/sin.bend, which is what M.Glibc239Libm stands for), and
# under that profile every value is the library's own. Under another
# profile a value is given only where it is sure: where the binary64 result
# is far enough from a float's rounding boundary (two units in its last
# place on each side) that any library within one unit of the true value,
# as glibc's is, narrows to the same float. A table with a value that is
# not sure is None.
import Base
import ../jonmath.bend as M
import ./vorbis_codebook.bend as C

# M_PI and 0.5*M_PI.
def pi() -> M.Float64:
  M.Float64{1074340347, 1413754136}

def half.pi() -> M.Float64:
  M.Float64{1073291771, 1413754136}

# An int from 0 to 2^20 as a double: its bits under the leading one are the
# top of the fraction.
def whole(+n: U32) -> M.Float64:
  Bool.pick(M.Float64, U32.is_eq(n, 0), M.Float64{0, 0}, M.Float64{((((1022 + C.ilog(n)) << 20n) .|. ((n << U32.to_nat((21 - U32.min(C.ilog(n), 21) : U32))) .&. 1048575)) : U32), 0})

# value / 2^power, exact (the values here stay normal).
def halved(value: M.Float64, +power: U32) -> M.Float64:
  M.Float64{high, low} = value
  M.Float64{(high - (power << 20n) : U32), low}

def times(a: Maybe<M.Float64>, +b: M.Float64) -> Maybe<M.Float64>:
  match a:
    case None{}: None{}
    case Some{+x}: M.Float64.internal.multiply(x, b)

def over(a: Maybe<M.Float64>, +b: M.Float64) -> Maybe<M.Float64>:
  match a:
    case None{}: None{}
    case Some{+x}: M.Float64.internal.divide(x, b)

# m*M_PI/n, as the C expressions with ints m and n compute it: a product,
# then a quotient.
def angle(+m: U32, +n: U32) -> Maybe<M.Float64>:
  over(M.Float64.internal.multiply(whole(m), pi()), whole(n))

# The value two units in its last place further from zero, and nearer.
def further(value: M.Float64) -> M.Float64:
  M.Float64{+high, +low} = value
  M.Float64{(high + Bool.pick(U32, (low >= 4294967294 : U32), 1, 0) : U32), (low + 2 : U32)}

def nearer(value: M.Float64) -> M.Float64:
  M.Float64{+high, +low} = value
  M.Float64{(high - Bool.pick(U32, (low < 2 : U32), 1, 0) : U32), (low - 2 : U32)}

# A zero is a zero in every library (the sine of 0).
def zero(value: M.Float64) -> Bool:
  M.Float64{+high, +low} = value
  U32.is_eq((high .&. 2147483647 : U32), 0) && U32.is_eq(low, 0)

def bits.same(a: Maybe<F32>, b: Maybe<F32>) -> Bool:
  match a b:
    case Some{+x} Some{+y}: U32.is_eq(F32.bits(x), F32.bits(y))
    case _ _: False{}

# (float)value where the library's own value is known (`exact`) or where the
# float is sure.
def narrowed.sure(sure: Bool, +value: M.Float64) -> Maybe<F32>:
  match sure:
    case False{}: None{}
    case True{}: M.Float64.to_f32(value)

def narrowed.value(+exact: Bool, +value: M.Float64) -> Maybe<F32>:
  narrowed.sure(exact || zero(value) || bits.same(M.Float64.to_f32(further(value)), M.Float64.to_f32(nearer(value))), value)

def narrowed(value: Maybe<M.Float64>, +exact: Bool, +negated: Bool) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+v}: narrowed.value(exact, Bool.pick(M.Float64, negated, M.Float64.internal.negate(v), v))

def sine(x: Maybe<M.Float64>) -> Maybe<M.Float64>:
  match x:
    case None{}: None{}
    case Some{+v}: M.Libm.sin64.words(v)

def cosine(x: Maybe<M.Float64>) -> Maybe<M.Float64>:
  match x:
    case None{}: None{}
    case Some{+v}: M.Libm.cos64.words(v)

# Floats gathered in turn, the last first: `fine` is whether every one was
# given.
type Floats is Data:
  Floats{fine: Bool, values: +List<F32>}

def Floats.fine(state: Floats) -> Bool:
  Floats{fine, _} = state
  fine

def Floats.values(state: Floats) -> +List<F32>:
  Floats{_, values} = state
  values

# A value put with the others, halved where the table has it so
# ((float)cos(x)*0.5f).
def put(value: Maybe<F32>, +half: Bool, +state: Floats) -> Floats:
  match value:
    case None{}: Floats{False{}, Floats.values(state)}
    case Some{+v}: Floats{Floats.fine(state), Con{Bool.pick(F32, half, (v * 0.5 : F32), v), Floats.values(state)}}

def given(state: Floats) -> Maybe<+List<F32>>:
  Floats{fine, values} = state
  Bool.pick(Maybe<+List<F32>>, fine, Some{List.reverse(&2, F32, values)}, None{})

# A[2k] = (float)cos(4*k*M_PI/n), A[2k+1] = (float)-sin(4*k*M_PI/n), for k
# under n/4.
def a.each(count: Nat, on: Bool, +exact: Bool, +n: U32, +k: U32, +state: Floats) -> Floats:
  match count on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+rest True{}:
      +next = put(narrowed(sine(angle((4 * k : U32), n)), exact, True{}), False{}, put(narrowed(cosine(angle((4 * k : U32), n)), exact, False{}), False{}, state))
      a.each(rest, Floats.fine(next), exact, n, (k + 1 : U32), next)

# B[2k] = (float)cos((2k+1)*M_PI/n/2)*0.5f, B[2k+1] = (float)sin(...)*0.5f,
# for k under n/4.
def b.each(count: Nat, on: Bool, +exact: Bool, +n: U32, +k: U32, +state: Floats) -> Floats:
  match count on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+rest True{}:
      +next = put(narrowed(sine(times(angle(((2 * k) + 1 : U32), n), M.Float64{1071644672, 0})), exact, False{}), True{},
        put(narrowed(cosine(times(angle(((2 * k) + 1 : U32), n), M.Float64{1071644672, 0})), exact, False{}), True{}, state))
      b.each(rest, Floats.fine(next), exact, n, (k + 1 : U32), next)

# C[2k] = (float)cos(2*(2k+1)*M_PI/n), C[2k+1] = (float)-sin(...), for k
# under n/8.
def c.each(count: Nat, on: Bool, +exact: Bool, +n: U32, +k: U32, +state: Floats) -> Floats:
  match count on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+rest True{}:
      +next = put(narrowed(sine(angle((2 * ((2 * k) + 1) : U32), n)), exact, True{}), False{}, put(narrowed(cosine(angle((2 * ((2 * k) + 1) : U32), n)), exact, False{}), False{}, state))
      c.each(rest, Floats.fine(next), exact, n, (k + 1 : U32), next)

# sin(0.5*M_PI*square(s)) for the float s, narrowed.
def window.outer(inner: Maybe<F32>, +exact: Bool) -> Maybe<F32>:
  match inner:
    case None{}: None{}
    case Some{+s}: narrowed(sine(M.Float64.internal.multiply(half.pi(), M.Float64.from_f32((s * s : F32)))), exact, False{})

# window[i] = (float)sin(0.5*M_PI*square((float)sin((i + 0.5)/n2*0.5*M_PI))),
# for i under n2 = n/2: (i + 0.5)/n2*0.5 is the exact (2i + 1)/(2n).
def window.each(count: Nat, on: Bool, +exact: Bool, +n: U32, +i: U32, +state: Floats) -> Floats:
  match count on:
    case _ False{}: state
    case 0n True{}: state
    case 1n+rest True{}:
      +next = put(window.outer(narrowed(sine(M.Float64.internal.multiply(halved(whole(((2 * i) + 1 : U32)), C.ilog(n)), pi())), exact, False{}), exact), False{}, state)
      window.each(rest, Floats.fine(next), exact, n, (i + 1 : U32), next)

# rev[i] = (bit_reverse(i) >> (32 - ld + 3)) << 2 for i under n/8, ld being
# ilog(n) - 1.
def reverse.each(count: Nat, +shift: U32, +i: U32, acc: +List<U32>) -> +List<U32>:
  match count:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+rest: reverse.each(rest, shift, (i + 1 : U32), Con{((C.bit.reverse(i) >> U32.to_nat(U32.min(shift, 31))) << 2n : U32), acc})

# compute_bitreverse(n) for a block size of 64 to 8192.
def bitreverse(+n: U32) -> +List<U32>:
  reverse.each(U32.to_nat((n >> 3n : U32)), (36 - C.ilog(n) : U32), 0, Nil{})

# A block size's tables: the twiddle factors A and B (n/2 floats each) and C
# (n/4), the window (n/2) and the bit reversal (n/8).
type Tables is Data:
  Tables{a: +List<F32>, b: +List<F32>, c: +List<F32>, window: +List<F32>, reverse: +List<U32>}

def tables.made(a: Maybe<+List<F32>>, b: Maybe<+List<F32>>, c: Maybe<+List<F32>>, window: Maybe<+List<F32>>, +reverse: +List<U32>) -> Maybe<Tables>:
  match a b c window:
    case Some{+x} Some{+y} Some{+z} Some{+w}: Some{Tables{x, y, z, w, reverse}}
    case _ _ _ _: None{}

def library.own(libm: M.Libm) -> Bool:
  match libm:
    case M.Glibc239Libm{}: True{}
    case _: False{}

# init_blocksize's tables for a block size n, a power of two from 64 to
# 8192. None where a value is not given (see the top of the file), which
# under M.Glibc239Libm does not happen.
def tables.for(+libm: M.Libm, +n: U32) -> Maybe<Tables>:
  tables.made(given(a.each(U32.to_nat((n >> 2n : U32)), True{}, library.own(libm), n, 0, Floats{True{}, Nil{}})), given(b.each(U32.to_nat((n >> 2n : U32)), True{}, library.own(libm), n, 0, Floats{True{}, Nil{}})),
    given(c.each(U32.to_nat((n >> 3n : U32)), True{}, library.own(libm), n, 0, Floats{True{}, Nil{}})), given(window.each(U32.to_nat((n >> 1n : U32)), True{}, library.own(libm), n, 0, Floats{True{}, Nil{}})), bitreverse(n))
