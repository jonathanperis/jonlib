# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_truetype.h v1.26's stbtt__solve_cubic and
# stbtt__cuberoot as pinned raylib 6.0 vendors it (src/external/stb_truetype.h,
# Sean Barrett, public domain / MIT; LICENSES/stb_truetype.txt): the roots of
# x^3 + a*x^2 + b*x + c = 0 that stbtt_GetGlyphSDF takes for the point of a
# curve nearest to a pixel. F32 arithmetic follows the C source order,
# uncontracted.
#
# The solver calls the C library's binary64 pow, acos and cos on floats and
# narrows them: here those are glibc 2.39's x86_64 functions (./power64.bend,
# ./lgpl/acos.bend and ./lgpl/sin.bend, docs/MATH.md), so the roots are the
# ones a glibc 2.39 host computes. Its float sqrt of a float is sqrtf (the
# double root narrowed is the same float), and the sqrt it does not narrow
# is the exact binary64 one.
import Base
import ./binary64_fma.bend as F
import ./binary64_scaled.bend as S
import ./binary64_ops.bend as O
import ./binary64_narrow.bend as N
import ./binary64_sqrt.bend as Q
import ./power64.bend as P
import ./lgpl/acos.bend as Acos
import ./lgpl/sin.bend as Sin

# What stbtt__solve_cubic leaves in r. state 1: one root, r0. 3: three
# roots. 4: three roots that are NaN in C, the argument of acos being above
# 1 by the rounding of what came before: none is used. 0: no answer here
# (a value that is not finite on the way, or a step the binary64 helpers
# do not take).
type Roots is Data:
  Roots{state: U32, r0: F32, r1: F32, r2: F32}

def refused() -> Roots:
  Roots{0, 0.0, 0.0, 0.0}

def flt(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def finite(+x: F32) -> Bool:
  U32.is_ne((F32.bits(x) .&. 2139095040 : U32), 2139095040)

def narrowed(words: Maybe<F.Words>) -> Maybe<U32>:
  match words:
    case None{}: None{}
    case Some{F.Words{high, low}}: N.checked(high, low)

# -----------------------------------------------------------------------------
# d >= 0: one root, s + cuberoot(u) + cuberoot(v)

def cuberoot.signed(negative: Bool, root: Maybe<U32>) -> Maybe<F32>:
  match root:
    case None{}: None{}
    case Some{+bits}: Some{Bool.pick(F32, negative, F32.neg(flt(bits)), flt(bits))}

# stbtt__cuberoot: -(float) pow(-x, 1.0f/3.0f) below 0, else
# (float) pow(x, 1.0f/3.0f).
def cuberoot(+x: F32) -> Maybe<F32>:
  cuberoot.signed((x < 0.0 : F32), P.third(Bool.pick(U32, (x < 0.0 : F32), (F32.bits(x) .^. 2147483648 : U32), F32.bits(x))))

def one.checked(+r0: F32) -> Roots:
  Bool.pick(Roots, finite(r0), Roots{1, r0, 0.0, 0.0}, refused())

def one.rooted(+s: F32, u: Maybe<F32>, v: Maybe<F32>) -> Roots:
  match u v:
    case Some{+x} Some{+y}: one.checked(((s + x : F32) + y : F32))
    case _ _: refused()

# z = (float) sqrt(d); u = (-q + z)/2; v = (-q - z)/2.
def one(+s: F32, +q: F32, +z: F32) -> Roots:
  one.rooted(s, cuberoot(((F32.neg(q) + z : F32) / 2.0 : F32)), cuberoot(((F32.neg(q) - z : F32) / 2.0 : F32)))

# -----------------------------------------------------------------------------
# d < 0: three roots by the angle v = acos(-sqrt(-27/p3)*q/2)/3

def three.checked(+r0: F32, +r1: F32, +r2: F32) -> Roots:
  Bool.pick(Roots, finite(r0) && finite(r1) && finite(r2), Roots{3, r0, r1, r2}, refused())

# r[0] = s + u*2*m; r[1] = s - u*(n + m); r[2] = s - u*(m - n).
def three.made(+s: F32, +u: F32, +m: F32, +n: F32) -> Roots:
  three.checked((s + ((u * 2.0 : F32) * m : F32) : F32), (s - (u * (n + m : F32) : F32) : F32), (s - (u * (m - n : F32) : F32) : F32))

# m = (float) cos(v); n = (float) cos(v - 3.141592/2)*1.732050808f.
def three.cosines(+s: F32, +u: F32, m: Maybe<U32>, n: Maybe<U32>) -> Roots:
  match m n:
    case Some{+mb} Some{+nb}: three.made(s, u, flt(mb), (flt(nb) * flt(1071494103) : F32))
    case _ _: refused()

def cos.narrowed(words: Maybe<F.Words>) -> Maybe<U32>:
  match words:
    case None{}: None{}
    case Some{F.Words{+high, +low}}: narrowed(Sin.cos(high, low))

# v as a double, and v - 3.141592/2.
def three.angle(+s: F32, +u: F32, v: Maybe<F.Words>) -> Roots:
  match v:
    case None{}: refused()
    case Some{F.Words{+high, +low}}: three.cosines(s, u, narrowed(Sin.cos(high, low)), cos.narrowed(S.subtract(high, low, 1073291770, 4236968058)))

# v = (float) acos(...)/3.
def three.third(+s: F32, +u: F32, angle: Maybe<U32>) -> Roots:
  match angle:
    case None{}: refused()
    case Some{+bits}: three.angle(s, u, O.checked_promote(F32.bits((flt(bits) / 3.0 : F32))))

# acos of an argument above 1 is a NaN: so are the three roots.
def three.inside(above: Bool, +s: F32, +u: F32, +high: U32, +low: U32) -> Roots:
  match above:
    case True{}: Roots{4, 0.0, 0.0, 0.0}
    case False{}: three.third(s, u, narrowed(Acos.acos(high, low)))

def three.argument(+s: F32, +u: F32, argument: Maybe<F.Words>) -> Roots:
  match argument:
    case None{}: refused()
    case Some{F.Words{+high, +low}}:
      three.inside(((high .&. 2147483647) > 1072693248 : U32) || (U32.is_eq((high .&. 2147483647 : U32), 1072693248) && U32.is_ne(low, 0)), s, u, high, low)

# (-root*q)/2, in binary64.
def three.halved(product: Maybe<F.Words>) -> Maybe<F.Words>:
  match product:
    case None{}: None{}
    case Some{F.Words{+high, +low}}: S.multiply(high, low, 1071644672, 0)

def three.times(+rh: U32, +rl: U32, q: Maybe<F.Words>) -> Maybe<F.Words>:
  match q:
    case None{}: None{}
    case Some{F.Words{+qh, +ql}}: three.halved(S.multiply((rh .^. 2147483648 : U32), rl, qh, ql))

def three.rooted(root: Maybe<F.Words>, +q: F32) -> Maybe<F.Words>:
  match root:
    case None{}: None{}
    case Some{F.Words{+rh, +rl}}: three.times(rh, rl, O.checked_promote(F32.bits(q)))

# sqrt(-27/p3) of the float quotient as a double.
def three.root(w: Maybe<F.Words>) -> Maybe<F.Words>:
  match w:
    case None{}: None{}
    case Some{F.Words{+high, +low}}: Q.checked(high, low)

# u = (float) sqrt(-p/3), and the argument of acos. p3 is negative here in
# C; where it is not, or something is not finite, there is no answer.
def three.at(fine: Bool, +s: F32, +p: F32, +q: F32, +p3: F32) -> Roots:
  match fine:
    case False{}: refused()
    case True{}: three.argument(s, F32.sqrt((F32.neg(p) / 3.0 : F32)), three.rooted(three.root(O.checked_promote(F32.bits((F32.neg(27.0) / p3 : F32)))), q))

def three(+s: F32, +p: F32, +q: F32, +p3: F32) -> Roots:
  three.at(finite(s) && finite(p) && finite(q) && finite(p3) && (p3 < 0.0 : F32), s, p, q, p3)

# -----------------------------------------------------------------------------

def solve.at(single: Bool, +s: F32, +p: F32, +q: F32, +p3: F32, +d: F32) -> Roots:
  match single:
    case True{}: one(s, q, F32.sqrt(d))
    case False{}: three(s, p, q, p3)

def solve.terms(+s: F32, +p: F32, +q: F32, +p3: F32) -> Roots:
  solve.at(((((q * q : F32) + ((4.0 * p3 : F32) / 27.0 : F32)) : F32) >= 0.0 : F32), s, p, q, p3, ((q * q : F32) + ((4.0 * p3 : F32) / 27.0 : F32) : F32))

def solve.reduced(+s: F32, +p: F32, +q: F32) -> Roots:
  solve.terms(s, p, q, ((p * p : F32) * p : F32))

# stbtt__solve_cubic(a, b, c, r): s = -a/3; p = b - a*a/3;
# q = a*(2*a*a - 9*b)/27 + c; p3 = p*p*p; d = q*q + 4*p3/27.
def solve(+a: F32, +b: F32, +c: F32) -> Roots:
  solve.reduced((F32.neg(a) / 3.0 : F32), (b - ((a * a : F32) / 3.0 : F32) : F32), (((a * ((((2.0 * a : F32) * a : F32) - (9.0 * b : F32)) : F32) : F32) / 27.0 : F32) + c : F32))
