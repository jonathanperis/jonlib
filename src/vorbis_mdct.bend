# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_vorbis v1.22 (Sean Barrett; MIT or public
# domain), as raylib 6.0 vendors it in src/external/stb_vorbis.c:
# inverse_mdct with its loops (imdct_step3_iter0_loop,
# imdct_step3_inner_r_loop, imdct_step3_inner_s_loop, iter_54,
# imdct_step3_inner_s_loop_ld654). See THIRD_PARTY_NOTICES.md and
# LICENSES/stb_vorbis.txt.
#
# Every float operation is one of the C code's, in its order, each rounded
# once: products are not fused with the sums that follow them (raylib's
# audio as this port compares it is built without contraction). The
# buffers are rows read and written by index (store.bend).
import Base
import ./store.bend as R
import ./vorbis_tables.bend as T
import ./vorbis_codebook.bend as C

# A block size's tables as rows.
type Factors is Data:
  Factors{a: R.Row, b: R.Row, c: R.Row, window: R.Row, reverse: R.Index}

def factors.of(tables: T.Tables) -> Factors:
  T.Tables{a, b, c, window, reverse} = tables
  Factors{R.Row.from(a), R.Row.from(b), R.Row.from(c), R.Row.from(window), R.Index.from(reverse, 0)}

def Factors.a(factors: Factors) -> R.Row:
  Factors{a, _, _, _, _} = factors
  a

def Factors.b(factors: Factors) -> R.Row:
  Factors{_, b, _, _, _} = factors
  b

def Factors.c(factors: Factors) -> R.Row:
  Factors{_, _, c, _, _} = factors
  c

def Factors.window(factors: Factors) -> R.Row:
  Factors{_, _, _, window, _} = factors
  window

def Factors.reverse(factors: Factors) -> R.Index:
  Factors{_, _, _, _, reverse} = factors
  reverse

# Two floats written.
def put2(+row: R.Row, +i: U32, +x: F32, +j: U32, +y: F32) -> R.Row:
  R.Row.set(R.Row.set(row, i, x), j, y)

# The first pass: the spectrum's even places with the factors A, into the
# second half of the temporary buffer, from its end down:
#   d[1] = e[0]*AA[0] - e[2]*AA[1];  d[0] = e[0]*AA[1] + e[2]*AA[0];
def first.half(n: Nat, +buffer: R.Row, +a: R.Row, +d: U32, +aa: U32, +e: U32, +other: R.Row) -> R.Row:
  match n:
    case 0n: other
    case 1n+k:
      first.half(k, buffer, a, (d - 2 : U32), (aa + 2 : U32), (e + 4 : U32),
        put2(other, (d + 1 : U32), (((R.Row.get(buffer, e) * R.Row.get(a, aa) : F32)) - ((R.Row.get(buffer, (e + 2 : U32)) * R.Row.get(a, (aa + 1 : U32)) : F32)) : F32),
          d, (((R.Row.get(buffer, e) * R.Row.get(a, (aa + 1 : U32)) : F32)) + ((R.Row.get(buffer, (e + 2 : U32)) * R.Row.get(a, aa) : F32)) : F32)))

# Then the odd places from the end, negated, into the first half:
#   d[1] = -e[2]*AA[0] - -e[0]*AA[1];  d[0] = -e[2]*AA[1] + -e[0]*AA[0];
def second.half(n: Nat, +buffer: R.Row, +a: R.Row, +d: U32, +aa: U32, +e: U32, +other: R.Row) -> R.Row:
  match n:
    case 0n: other
    case 1n+k:
      second.half(k, buffer, a, (d - 2 : U32), (aa + 2 : U32), (e - 4 : U32),
        put2(other, (d + 1 : U32), (((F32.neg(R.Row.get(buffer, (e + 2 : U32))) * R.Row.get(a, aa) : F32)) - ((F32.neg(R.Row.get(buffer, e)) * R.Row.get(a, (aa + 1 : U32)) : F32)) : F32),
          d, (((F32.neg(R.Row.get(buffer, (e + 2 : U32))) * R.Row.get(a, (aa + 1 : U32)) : F32)) + ((F32.neg(R.Row.get(buffer, e)) * R.Row.get(a, aa) : F32)) : F32)))

# Step 2, a pair of places: the sum to d0, the difference turned by two
# factors to d1.
#   v41 = e0[1] - e1[1];  v40 = e0[0] - e1[0];
#   d0[1] = e0[1] + e1[1];  d0[0] = e0[0] + e1[0];
#   d1[1] = v41*p - v40*q;  d1[0] = v40*p + v41*q;
def step2.pair(+other: R.Row, +e0: U32, +e1: U32, +d0: U32, +d1: U32, +p: F32, +q: F32, +buffer: R.Row) -> R.Row:
  +v41 = (R.Row.get(other, (e0 + 1 : U32)) - R.Row.get(other, (e1 + 1 : U32)) : F32)
  +v40 = (R.Row.get(other, e0) - R.Row.get(other, e1) : F32)
  put2(put2(buffer, (d0 + 1 : U32), (R.Row.get(other, (e0 + 1 : U32)) + R.Row.get(other, (e1 + 1 : U32)) : F32), d0, (R.Row.get(other, e0) + R.Row.get(other, e1) : F32)),
    (d1 + 1 : U32), (((v41 * p : F32)) - ((v40 * q : F32)) : F32), d1, (((v40 * p : F32)) + ((v41 * q : F32)) : F32))

def step2(n: Nat, +other: R.Row, +a: R.Row, +aa: U32, +at: U32, +quarter: U32, +buffer: R.Row) -> R.Row:
  match n:
    case 0n: buffer
    case 1n+k:
      step2(k, other, a, (aa - 8 : U32), (at + 4 : U32), quarter,
        step2.pair(other, ((quarter + at) + 2 : U32), (at + 2 : U32), ((quarter + at) + 2 : U32), (at + 2 : U32), R.Row.get(a, aa), R.Row.get(a, (aa + 1 : U32)),
          step2.pair(other, (quarter + at : U32), at, (quarter + at : U32), at, R.Row.get(a, (aa + 4 : U32)), R.Row.get(a, (aa + 5 : U32)), buffer)))

# A butterfly of step 3, on the places i and i - 1 and the places j and
# j - 1:
#   k0 = e[i] - e[j];  k1 = e[i-1] - e[j-1];
#   e[i] += e[j];  e[i-1] += e[j-1];
#   e[j] = k0*p - k1*q;  e[j-1] = k1*p + k0*q;
def fly(+row: R.Row, +i: U32, +j: U32, +p: F32, +q: F32) -> R.Row:
  +k0 = (R.Row.get(row, i) - R.Row.get(row, j) : F32)
  +k1 = (R.Row.get(row, (i - 1 : U32)) - R.Row.get(row, (j - 1 : U32)) : F32)
  put2(put2(row, i, (R.Row.get(row, i) + R.Row.get(row, j) : F32), (i - 1 : U32), (R.Row.get(row, (i - 1 : U32)) + R.Row.get(row, (j - 1 : U32)) : F32)),
    j, (((k0 * p : F32)) - ((k1 * q : F32)) : F32), (j - 1 : U32), (((k1 * p : F32)) + ((k0 * q : F32)) : F32))

# The butterflies a loop of `count >> 2` turns of four makes: the count
# without its two low bits (the block of 64 asks for 2, and gets none).
def fours(+count: U32) -> Nat:
  U32.to_nat(((count >> 2n) << 2n : U32))

# imdct_step3_iter0_loop and imdct_step3_inner_r_loop: butterflies down
# the buffer from i, each pair 2 places under the one before, against the
# places `off` under them, the factors `k1` further on each.
def r.loop(n: Nat, +a: R.Row, +i: U32, +off: U32, +aa: U32, +k1: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k: r.loop(k, a, (i - 2 : U32), off, (aa + k1 : U32), k1, fly(row, i, (i - off : U32), R.Row.get(a, aa), R.Row.get(a, (aa + 1 : U32))))

# imdct_step3_inner_s_loop: four butterflies with four pairs of factors
# that stay, at places `k0` under the ones before each turn.
def s.loop(n: Nat, +i: U32, +off: U32, +k0: U32, +a0: F32, +a1: F32, +a2: F32, +a3: F32, +a4: F32, +a5: F32, +a6: F32, +a7: F32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      s.loop(k, (i - k0 : U32), off, k0, a0, a1, a2, a3, a4, a5, a6, a7,
        fly(fly(fly(fly(row, i, (i - off : U32), a0, a1), (i - 2 : U32), ((i - 2) - off : U32), a2, a3), (i - 4 : U32), ((i - 4) - off : U32), a4, a5), (i - 6 : U32), ((i - 6) - off : U32), a6, a7))

# The turns of the s loop over the factors: `rlim` of them, the factors
# 4*k1 further and the places 8 under each time.
def s.turns(n: Nat, +a: R.Row, +lim: Nat, +i: U32, +off: U32, +k0: U32, +k1: U32, +aa: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      s.turns(k, a, lim, (i - 8 : U32), off, k0, k1, (aa + (k1 * 4) : U32),
        s.loop(lim, i, off, k0, R.Row.get(a, aa), R.Row.get(a, (aa + 1 : U32)), R.Row.get(a, (aa + k1 : U32)), R.Row.get(a, ((aa + k1) + 1 : U32)), R.Row.get(a, (aa + (k1 * 2) : U32)),
          R.Row.get(a, ((aa + (k1 * 2)) + 1 : U32)), R.Row.get(a, (aa + (k1 * 3) : U32)), R.Row.get(a, ((aa + (k1 * 3)) + 1 : U32)), row))

# The r loops of a level: `lim` of them, each `k0` places under the one
# before.
def r.turns(n: Nat, +a: R.Row, +count: Nat, +i: U32, +k0: U32, +off: U32, +k1: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k: r.turns(k, a, count, (i - k0 : U32), k0, off, k1, r.loop(count, a, i, off, 0, k1, row))

# iter_54 on the 8 places down from z.
def iter54(+row: R.Row, +z: U32) -> R.Row:
  +k00 = (R.Row.get(row, z) - R.Row.get(row, (z - 4 : U32)) : F32)
  +y0 = (R.Row.get(row, z) + R.Row.get(row, (z - 4 : U32)) : F32)
  +y2 = (R.Row.get(row, (z - 2 : U32)) + R.Row.get(row, (z - 6 : U32)) : F32)
  +k22 = (R.Row.get(row, (z - 2 : U32)) - R.Row.get(row, (z - 6 : U32)) : F32)
  +k33 = (R.Row.get(row, (z - 3 : U32)) - R.Row.get(row, (z - 7 : U32)) : F32)
  +k11 = (R.Row.get(row, (z - 1 : U32)) - R.Row.get(row, (z - 5 : U32)) : F32)
  +y1 = (R.Row.get(row, (z - 1 : U32)) + R.Row.get(row, (z - 5 : U32)) : F32)
  +y3 = (R.Row.get(row, (z - 3 : U32)) + R.Row.get(row, (z - 7 : U32)) : F32)
  put2(put2(put2(put2(row, z, (y0 + y2 : F32), (z - 2 : U32), (y0 - y2 : F32)), (z - 4 : U32), (k00 + k33 : F32), (z - 6 : U32), (k00 - k33 : F32)), (z - 1 : U32), (y1 + y3 : F32), (z - 3 : U32), (y1 - y3 : F32)),
    (z - 5 : U32), (k11 - k22 : F32), (z - 7 : U32), (k11 + k22 : F32))

# The first half of a turn of imdct_step3_inner_s_loop_ld654, on the
# places z to z - 3 and z - 8 to z - 11.
def ld654.upper(+row: R.Row, +z: U32, +a2: F32) -> R.Row:
  +k00 = (R.Row.get(row, z) - R.Row.get(row, (z - 8 : U32)) : F32)
  +k11 = (R.Row.get(row, (z - 1 : U32)) - R.Row.get(row, (z - 9 : U32)) : F32)
  +l00 = (R.Row.get(row, (z - 2 : U32)) - R.Row.get(row, (z - 10 : U32)) : F32)
  +l11 = (R.Row.get(row, (z - 3 : U32)) - R.Row.get(row, (z - 11 : U32)) : F32)
  put2(put2(put2(put2(row, z, (R.Row.get(row, z) + R.Row.get(row, (z - 8 : U32)) : F32), (z - 1 : U32), (R.Row.get(row, (z - 1 : U32)) + R.Row.get(row, (z - 9 : U32)) : F32)),
    (z - 2 : U32), (R.Row.get(row, (z - 2 : U32)) + R.Row.get(row, (z - 10 : U32)) : F32), (z - 3 : U32), (R.Row.get(row, (z - 3 : U32)) + R.Row.get(row, (z - 11 : U32)) : F32)),
    (z - 8 : U32), k00, (z - 9 : U32), k11), (z - 10 : U32), (((l00 + l11 : F32)) * a2 : F32), (z - 11 : U32), (((l11 - l00 : F32)) * a2 : F32))

# The second half, on the places z - 4 to z - 7 and z - 12 to z - 15.
def ld654.lower(+row: R.Row, +z: U32, +a2: F32) -> R.Row:
  +k00 = (R.Row.get(row, (z - 4 : U32)) - R.Row.get(row, (z - 12 : U32)) : F32)
  +k11 = (R.Row.get(row, (z - 5 : U32)) - R.Row.get(row, (z - 13 : U32)) : F32)
  +l00 = (R.Row.get(row, (z - 6 : U32)) - R.Row.get(row, (z - 14 : U32)) : F32)
  +l11 = (R.Row.get(row, (z - 7 : U32)) - R.Row.get(row, (z - 15 : U32)) : F32)
  put2(put2(put2(put2(row, (z - 4 : U32), (R.Row.get(row, (z - 4 : U32)) + R.Row.get(row, (z - 12 : U32)) : F32), (z - 5 : U32), (R.Row.get(row, (z - 5 : U32)) + R.Row.get(row, (z - 13 : U32)) : F32)),
    (z - 6 : U32), (R.Row.get(row, (z - 6 : U32)) + R.Row.get(row, (z - 14 : U32)) : F32), (z - 7 : U32), (R.Row.get(row, (z - 7 : U32)) + R.Row.get(row, (z - 15 : U32)) : F32)),
    (z - 12 : U32), k11, (z - 13 : U32), F32.neg(k00)), (z - 14 : U32), (((l11 - l00 : F32)) * a2 : F32), (z - 15 : U32), (((l00 + l11 : F32)) * F32.neg(a2) : F32))

# imdct_step3_inner_s_loop_ld654: the last three levels at once, 16 places
# a turn.
def ld654(n: Nat, +z: U32, +a2: F32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k: ld654(k, (z - 16 : U32), a2, iter54(iter54(ld654.lower(ld654.upper(row, z, a2), z, a2), z), (z - 8 : U32)))

# The levels of step 3 where the r loop is inside: l from 2, while l is
# under (ld - 3)/2.
def levels.r(n: Nat, +a: R.Row, +size: U32, +l: U32, +limit: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      levels.r(k, a, size, (l + 1 : U32), limit, Bool.pick(R.Row, (l < limit : U32),
        r.turns(U32.to_nat((1 << U32.to_nat((l + 1 : U32)) : U32)), a, fours((size >> U32.to_nat((l + 4 : U32)) : U32)), ((size >> 1n) - 1 : U32), (size >> U32.to_nat((l + 2 : U32)) : U32),
          ((size >> U32.to_nat((l + 2 : U32))) >> 1n : U32), (1 << U32.to_nat((l + 3 : U32)) : U32), row), row))

# And where the s loop is: l on to ld - 6.
def levels.s(n: Nat, +a: R.Row, +size: U32, +l: U32, +from: U32, +limit: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      levels.s(k, a, size, (l + 1 : U32), from, limit, Bool.pick(R.Row, (l >= from : U32) && (l < limit : U32),
        s.turns(U32.to_nat((size >> U32.to_nat((l + 6 : U32)) : U32)), a, U32.to_nat((1 << U32.to_nat((l + 1 : U32)) : U32)), ((size >> 1n) - 1 : U32), ((size >> U32.to_nat((l + 2 : U32))) >> 1n : U32),
          (size >> U32.to_nat((l + 2 : U32)) : U32), (1 << U32.to_nat((l + 3 : U32)) : U32), 0, row), row))

# Steps 4 to 6: the buffer's places in bit-reversed order, into the
# temporary buffer from its middle and its end down, 4 at a time:
#   d1[3] = u[k4];  d1[2] = u[k4+1];  d0[3] = u[k4+2];  d0[2] = u[k4+3];   (k4 = bitrev[0])
#   d1[1] = u[k4];  d1[0] = u[k4+1];  d0[1] = u[k4+2];  d0[0] = u[k4+3];   (k4 = bitrev[1])
def reversed(n: Nat, +buffer: R.Row, +reverse: R.Index, +at: U32, +d0: U32, +d1: U32, +other: R.Row) -> R.Row:
  match n:
    case 0n: other
    case 1n+k:
      reversed(k, buffer, reverse, (at + 2 : U32), (d0 - 4 : U32), (d1 - 4 : U32),
        put2(put2(put2(put2(other, (d1 + 3 : U32), R.Row.get(buffer, R.Index.get(reverse, at)), (d1 + 2 : U32), R.Row.get(buffer, (R.Index.get(reverse, at) + 1 : U32))),
          (d0 + 3 : U32), R.Row.get(buffer, (R.Index.get(reverse, at) + 2 : U32)), (d0 + 2 : U32), R.Row.get(buffer, (R.Index.get(reverse, at) + 3 : U32))),
          (d1 + 1 : U32), R.Row.get(buffer, R.Index.get(reverse, (at + 1 : U32))), d1, R.Row.get(buffer, (R.Index.get(reverse, (at + 1 : U32)) + 1 : U32))),
          (d0 + 1 : U32), R.Row.get(buffer, (R.Index.get(reverse, (at + 1 : U32)) + 2 : U32)), d0, R.Row.get(buffer, (R.Index.get(reverse, (at + 1 : U32)) + 3 : U32))))

# Step 7, a pair of places from each end of the temporary buffer:
#   a02 = d[0] - e[2];  a11 = d[1] + e[3];
#   b0 = c1*a02 + c0*a11;  b1 = c1*a11 - c0*a02;
#   b2 = d[0] + e[2];  b3 = d[1] - e[3];
#   d[0] = b2 + b0;  d[1] = b3 + b1;  e[2] = b2 - b0;  e[3] = b1 - b3;
def step7.pair(+row: R.Row, +d: U32, +e: U32, +c0: F32, +c1: F32) -> R.Row:
  +a02 = (R.Row.get(row, d) - R.Row.get(row, e) : F32)
  +a11 = (R.Row.get(row, (d + 1 : U32)) + R.Row.get(row, (e + 1 : U32)) : F32)
  +b0 = (((c1 * a02 : F32)) + ((c0 * a11 : F32)) : F32)
  +b1 = (((c1 * a11 : F32)) - ((c0 * a02 : F32)) : F32)
  +b2 = (R.Row.get(row, d) + R.Row.get(row, e) : F32)
  +b3 = (R.Row.get(row, (d + 1 : U32)) - R.Row.get(row, (e + 1 : U32)) : F32)
  put2(put2(row, d, (b2 + b0 : F32), (d + 1 : U32), (b3 + b1 : F32)), e, (b2 - b0 : F32), (e + 1 : U32), (b1 - b3 : F32))

def step7(n: Nat, +c: R.Row, +cc: U32, +d: U32, +e: U32, +row: R.Row) -> R.Row:
  match n:
    case 0n: row
    case 1n+k:
      step7(k, c, (cc + 4 : U32), (d + 4 : U32), (e - 4 : U32),
        step7.pair(step7.pair(row, d, (e + 2 : U32), R.Row.get(c, cc), R.Row.get(c, (cc + 1 : U32))), (d + 2 : U32), e, R.Row.get(c, (cc + 2 : U32)), R.Row.get(c, (cc + 3 : U32))))

# Step 8, a pair of the temporary buffer's places turned by two of the
# factors B into four places of the block:
#   p3 = e0*b1 - e1*b0;  p2 = -e0*b0 - e1*b1;
#   d0[i] = p3;  d1[j] = -p3;  d2[i] = p2;  d3[j] = p2;
def step8.pair(+buffer: R.Row, +e0: F32, +e1: F32, +b0: F32, +b1: F32, +d0: U32, +d1: U32, +d2: U32, +d3: U32) -> R.Row:
  +p3 = (((e0 * b1 : F32)) - ((e1 * b0 : F32)) : F32)
  +p2 = (((F32.neg(e0) * b0 : F32)) - ((e1 * b1 : F32)) : F32)
  put2(put2(buffer, d0, p3, d1, F32.neg(p3)), d2, p2, d3, p2)

def step8.at(+buffer: R.Row, +other: R.Row, +b: R.Row, +e: U32, +d0: U32, +d1: U32, +d2: U32, +d3: U32) -> R.Row:
  step8.pair(buffer, R.Row.get(other, e), R.Row.get(other, (e + 1 : U32)), R.Row.get(b, e), R.Row.get(b, (e + 1 : U32)), d0, d1, d2, d3)

def step8(n: Nat, +other: R.Row, +b: R.Row, +e: U32, +d0: U32, +d1: U32, +d2: U32, +d3: U32, +buffer: R.Row) -> R.Row:
  match n:
    case 0n: buffer
    case 1n+k:
      step8(k, other, b, (e - 8 : U32), (d0 + 4 : U32), (d1 - 4 : U32), (d2 + 4 : U32), (d3 - 4 : U32),
        step8.at(step8.at(step8.at(step8.at(buffer, other, b, (e + 6 : U32), d0, (d1 + 3 : U32), d2, (d3 + 3 : U32)), other, b, (e + 4 : U32), (d0 + 1 : U32), (d1 + 2 : U32), (d2 + 1 : U32), (d3 + 2 : U32)),
          other, b, (e + 2 : U32), (d0 + 2 : U32), (d1 + 1 : U32), (d2 + 2 : U32), (d3 + 1 : U32)), other, b, e, (d0 + 3 : U32), d1, (d2 + 3 : U32), d3))

# Step 3 on the buffer: the two halves and the four quarters, the levels
# between, and the last three.
def step3(+a: R.Row, +n: U32, +ld: U32, +row: R.Row) -> R.Row:
  ld654(U32.to_nat((n >> 5n : U32)), ((n >> 1n) - 1 : U32), R.Row.get(a, (n >> 3n : U32)),
    levels.s(16n, a, n, 2, U32.max(((ld - 3) >> 1n : U32), 2), (ld - 6 : U32),
      levels.r(16n, a, n, 2, ((ld - 3) >> 1n : U32),
        r.loop(fours((n >> 5n : U32)), a, (((n >> 1n) - 1) - ((n >> 3n) * 3) : U32), (n >> 4n : U32), 0, 16,
          r.loop(fours((n >> 5n : U32)), a, (((n >> 1n) - 1) - ((n >> 3n) * 2) : U32), (n >> 4n : U32), 0, 16,
            r.loop(fours((n >> 5n : U32)), a, (((n >> 1n) - 1) - (n >> 3n) : U32), (n >> 4n : U32), 0, 16,
              r.loop(fours((n >> 5n : U32)), a, ((n >> 1n) - 1 : U32), (n >> 4n : U32), 0, 16,
                r.loop(fours((n >> 4n : U32)), a, (((n >> 1n) - 1) - (n >> 2n) : U32), (n >> 3n : U32), 0, 8,
                  r.loop(fours((n >> 4n : U32)), a, ((n >> 1n) - 1 : U32), (n >> 3n : U32), 0, 8, row)))))))))

def transform.ended(+other: R.Row, +b: R.Row, +n: U32, +buffer: R.Row) -> R.Row:
  step8(U32.to_nat((n >> 4n : U32)), other, b, ((n >> 1n) - 8 : U32), 0, ((n >> 1n) - 4 : U32), (n >> 1n : U32), (n - 4 : U32), buffer)

def transform.turned(+buffer: R.Row, +factors: Factors, +n: U32, +other: R.Row) -> R.Row:
  transform.ended(step7(U32.to_nat((n >> 4n : U32)), Factors.c(factors), 0, 0, ((n >> 1n) - 4 : U32), reversed(U32.to_nat((n >> 4n : U32)), buffer, Factors.reverse(factors), 0, ((n >> 2n) - 4 : U32), ((n >> 1n) - 4 : U32), other)),
    Factors.b(factors), n, buffer)

def transform.stepped(+factors: Factors, +n: U32, +other: R.Row, +buffer: R.Row) -> R.Row:
  transform.turned(step3(Factors.a(factors), n, (C.ilog(n) - 1 : U32), step2(U32.to_nat((n >> 4n : U32)), other, Factors.a(factors), ((n >> 1n) - 8 : U32), 0, (n >> 2n : U32), buffer)), factors, n, other)

# inverse_mdct(buffer, n, f, blocktype): the n/2 spectral values at the
# start of the block's n floats become its n samples (unwindowed, and half
# as large as the transform would have them: stb_vorbis leaves a factor of
# 2 for the window's step).
def transform(+buffer: R.Row, +factors: Factors, +n: U32) -> R.Row:
  transform.stepped(factors, n,
    second.half(U32.to_nat((n >> 3n : U32)), buffer, Factors.a(factors), ((n >> 2n) - 2 : U32), (n >> 2n : U32), ((n >> 1n) - 3 : U32),
      first.half(U32.to_nat((n >> 3n : U32)), buffer, Factors.a(factors), ((n >> 1n) - 2 : U32), 0, 0, R.Row.new(C.ilog(((n >> 1n) - 1 : U32)), 0.0))), buffer)
