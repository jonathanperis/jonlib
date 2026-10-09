# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of tinyobj_loader_c.h (Copyright (c) 2016 - 2019
# Syoyo Fujita and many contributors, MIT, LICENSES/tinyobj_loader_c.txt) as
# raylib 6.0 vendors it (src/external/tinyobj_loader_c.h), and of rmodels.c's
# LoadOBJ mesh assembly (zlib, LICENSES/raylib.txt). Text is a list of bytes
# (0..255) ending where C's string ends. The parser reproduces tinyobj's line
# splitting, commands, tryParseDouble (binary64 through the checked helpers of
# docs/BINARY64.md, its fraction digits fused under M.Fused{}), relative
# indices, triangulation, material table (djb2 hashes with quadratic probing)
# and shapes, then rmodels.c's split of the faces into meshes. What the C code
# leaves undefined (integer overflow, reads outside its arrays, asserts) and
# values outside the binary64 helpers' domains are reported, not guessed; see
# docs/MODELS.md.
import Base
import ./binary64_fma.bend as W64
import ./binary64_add_sub.bend as Add64
import ./binary64_ops.bend as Ops64
import ./binary64_narrow.bend as Narrow64

# -----------------------------------------------------------------------------
# Bytes

def head(+bs: +List<U32>) -> U32:
  match bs:
    case Nil{}: 0
    case Con{+c, _}: c

def tail(+bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def at(n: Nat, +bs: +List<U32>) -> U32:
  match n bs:
    case _ Nil{}: 0
    case 0n Con{+c, _}: c
    case 1n+k Con{_, rest}: at(k, rest)

def drop(n: Nat, +bs: +List<U32>) -> +List<U32>:
  match n bs:
    case 0n _: bs
    case _ Nil{}: Nil{}
    case 1n+k Con{_, rest}: drop(k, rest)

def length(bs: +List<U32>, +n: U32) -> U32:
  match bs:
    case Nil{}: n
    case Con{_, rest}: length(rest, (n + 1 : U32))

def reverse(bs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, bs)

def is_space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9)

def is_digit(+c: U32) -> Bool:
  (c >= 48 : U32) && (c <= 57 : U32)

def is_stop(+c: U32) -> Bool:
  is_space(c) || U32.is_eq(c, 13) || U32.is_eq(c, 0)

def skip_space.go(bs: +List<U32>, skip: Bool) -> +List<U32>:
  match bs skip:
    case Nil{} _: Nil{}
    case Con{_, +rest} True{}: skip_space.go(rest, is_space(head(rest)))
    case Con{+c, rest} False{}: Con{c, rest}

# skip_space: ' ' and '\t'
def skip_space(+bs: +List<U32>) -> +List<U32>:
  skip_space.go(bs, is_space(head(bs)))

def skip_space_cr.go(bs: +List<U32>, skip: Bool) -> +List<U32>:
  match bs skip:
    case Nil{} _: Nil{}
    case Con{_, +rest} True{}: skip_space_cr.go(rest, is_space(head(rest)) || U32.is_eq(head(rest), 13))
    case Con{+c, rest} False{}: Con{c, rest}

# skip_space_and_cr: ' ', '\t' and '\r'
def skip_space_cr(+bs: +List<U32>) -> +List<U32>:
  skip_space_cr.go(bs, is_space(head(bs)) || U32.is_eq(head(bs), 13))

def token.go(bs: +List<U32>, stop: Bool, +acc: +List<U32>) -> +List<U32> & +List<U32>:
  match bs stop:
    case Nil{} _: (reverse(acc), Nil{})
    case Con{+c, +rest} True{}: (reverse(acc), Con{c, rest})
    case Con{+c, +rest} False{}: token.go(rest, is_stop(head(rest)), Con{c, acc})

# until_space: the bytes before a NUL, ' ', '\t' or '\r', and the rest.
def token.split(+bs: +List<U32>) -> +List<U32> & +List<U32>:
  token.go(bs, is_stop(head(bs)), Nil{})

# -----------------------------------------------------------------------------
# tryParseDouble in binary64. A value is a canonical binary64 word pair with
# whether every operation stayed inside the checked helpers' domains.

type Num is Data:
  Num{ok: Bool, high: U32, low: U32}

def num(+high: U32, +low: U32) -> Num:
  Num{True{}, high, low}

def num.zero() -> Num:
  num(0, 0)

def num.one() -> Num:
  num(1072693248, 0)

def num.ten() -> Num:
  num(1076101120, 0)

def num.tenth() -> Num:
  num(1069128089, 2576980378)

def num.five() -> Num:
  num(1075052544, 0)

def num.two() -> Num:
  num(1073741824, 0)

# (double) of a decimal digit.
def num.digit(+d: U32) -> Num:
  match d:
    case 0: num(0, 0)
    case 1: num(1072693248, 0)
    case 2: num(1073741824, 0)
    case 3: num(1074266112, 0)
    case 4: num(1074790400, 0)
    case 5: num(1075052544, 0)
    case 6: num(1075314688, 0)
    case 7: num(1075576832, 0)
    case 8: num(1075838976, 0)
    case _: num(1075970048, 0)

def num.of(+ok: Bool, r: Maybe<W64.Words>) -> Num:
  match r:
    case None{}: Num{False{}, 0, 0}
    case Some{+w}: Num{ok, W64.Words.high(w), W64.Words.low(w)}

def num.mul(+a: Num, +b: Num) -> Num:
  Num{+ok, +ah, +al} = a
  Num{+bok, +bh, +bl} = b
  num.of(ok && bok, Ops64.checked_multiply(ah, al, bh, bl))

def num.add(+a: Num, +b: Num) -> Num:
  Num{+ok, +ah, +al} = a
  Num{+bok, +bh, +bl} = b
  num.of(ok && bok, Add64.checked_add(ah, al, bh, bl))

def num.fma(+a: Num, +b: Num, +c: Num) -> Num:
  Num{+ok, +ah, +al} = a
  Num{+bok, +bh, +bl} = b
  Num{+cok, +ch, +cl} = c
  num.of(ok && bok && cok, W64.checked(ah, al, bh, bl, ch, cl))

# 1.0/a
def num.inverse(+a: Num) -> Num:
  Num{+ok, +ah, +al} = a
  num.of(ok, Ops64.checked_divide(1072693248, 0, ah, al))

# mantissa += d*frac_value, one rounding when the reference contracts it.
def num.mad(+fused: Bool, +d: Num, +f: Num, +m: Num) -> Num:
  Bool.pick(Num, fused, num.fma(d, f, m), num.add(m, num.mul(d, f)))

# A parsed float: ub when the C code overflows an int; the value when every
# binary64 step was inside the helpers' domains.
type Parsed is Data:
  Parsed{ub: Bool, value: Maybe<&2, F32>}

def parsed.zero() -> Parsed:
  Parsed{False{}, Some{0.0}}

def f32.of(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def narrowed(+negative: Bool, r: Maybe<U32>) -> Maybe<&2, F32>:
  match r:
    case None{}: None{}
    case Some{+bits}: Some{f32.of((bits .^. Bool.pick(U32, negative, 2147483648, 0) : U32))}

# (float)((sign == '+' ? 1 : -1)*value)
def narrow(+ok: Bool, +negative: Bool, +n: Num) -> Maybe<&2, F32>:
  Num{+nok, +high, +low} = n
  Bool.pick(Maybe<&2, F32>, ok && nok, narrowed(negative, Narrow64.checked(high, low)), None{})

def power(n: Nat, +acc: Num, +base: Num) -> Num:
  match n:
    case 0n: acc
    case 1n+k: power(k, num.mul(acc, base), base)

# assemble: a = 5^e, b = 2^e (repeated products, inverted for a negative
# exponent), the value mantissa*a*b. Exponents above 64 leave the multiply
# domain (5^55 > 2^127) and are not evaluated.
def assemble(+negative: Bool, +m: Num, +minus: Bool, +e: U32) -> Parsed:
  +small = (e <= 64 : U32)
  +k = U32.to_nat(Bool.pick(U32, small, e, 0))
  +a = power(k, num.one(), num.five())
  +b = power(k, num.one(), num.two())
  Parsed{False{}, narrow(small, negative, num.mul(num.mul(m, Bool.pick(Num, minus, num.inverse(a), a)), Bool.pick(Num, minus, num.inverse(b), b)))}

type ExpOut is Data:
  ExpOut{value: U32, read: U32, overflow: Bool}

# exponent = exponent*10 + digit (an int: overflow is undefined).
def p.exp(bs: +List<U32>, digit: Bool, +value: U32, +read: U32, +overflow: Bool) -> ExpOut:
  match bs digit:
    case Con{+c, +rest} True{}:
      +d = (c - 48 : U32)
      p.exp(rest, is_digit(head(rest)), (value * 10 + d : U32), (read + 1 : U32), overflow || (value > ((2147483647 - d) / 10 : U32) : U32))
    case _ _: ExpOut{value, read, overflow}

def exponent.done(+negative: Bool, +m: Num, +minus: Bool, +o: ExpOut) -> Parsed:
  ExpOut{+value, +read, +overflow} = o
  Bool.pick(Parsed, overflow, Parsed{True{}, None{}}, Bool.pick(Parsed, U32.is_eq(read, 0), parsed.zero(), assemble(negative, m, minus, value)))

def exponent.route(route: U32, +negative: Bool, +m: Num, +minus: Bool, +t: +List<U32>) -> Parsed:
  match route:
    case 0: parsed.zero()
    case 1: exponent.done(negative, m, minus, p.exp(tail(t), is_digit(head(tail(t))), 0, 0, False{}))
    case _: exponent.done(negative, m, False{}, p.exp(t, is_digit(head(t)), 0, 0, False{}))

# After 'e' or 'E': an optional sign (only before the end), then digits; an
# empty exponent fails (the value stays 0).
def exponent(+negative: Bool, +m: Num, +t: +List<U32>) -> Parsed:
  +c = head(t)
  +signed = Bool.not(List.is_empty(&2, U32, t)) && (U32.is_eq(c, 43) || U32.is_eq(c, 45))
  exponent.route(Bool.pick(U32, signed, 1, Bool.pick(U32, is_digit(c), 2, 0)), negative, m, U32.is_eq(c, 45), t)

def is_e(+c: U32) -> Bool:
  U32.is_eq(c, 101) || U32.is_eq(c, 69)

type FracOut is Data:
  FracOut{m: Num, rest: +List<U32>}

# Fraction digits: frac_value = 0.1^read (the C loop's repeated products,
# kept from the previous digit), mantissa += digit*frac_value.
def p.frac(bs: +List<U32>, digit: Bool, +fused: Bool, +m: Num, +f: Num) -> FracOut:
  match bs digit:
    case Con{+c, +rest} True{}:
      +g = num.mul(f, num.tenth())
      p.frac(rest, is_digit(head(rest)), fused, num.mad(fused, num.digit((c - 48 : U32)), g, m), g)
    case _ _: FracOut{m, bs}

def fraction.done(+negative: Bool, +o: FracOut) -> Parsed:
  FracOut{+m, +rest} = o
  Bool.pick(Parsed, Bool.not(List.is_empty(&2, U32, rest)) && is_e(head(rest)), exponent(negative, m, tail(rest)), assemble(negative, m, False{}, 0))

type IntOut is Data:
  IntOut{m: Num, read: U32, rest: +List<U32>}

def p.int(bs: +List<U32>, digit: Bool, +m: Num, +read: U32) -> IntOut:
  match bs digit:
    case Con{+c, +rest} True{}: p.int(rest, is_digit(head(rest)), num.add(num.mul(m, num.ten()), num.digit((c - 48 : U32))), (read + 1 : U32))
    case _ _: IntOut{m, read, bs}

def integer.route(route: U32, +fused: Bool, +negative: Bool, +m: Num, +rest: +List<U32>) -> Parsed:
  match route:
    case 0: parsed.zero()
    case 1: assemble(negative, m, False{}, 0)
    case 2: fraction.done(negative, p.frac(tail(rest), is_digit(head(tail(rest))), fused, m, num.one()))
    case _: exponent(negative, m, tail(rest))

def integer.done(+fused: Bool, +negative: Bool, +o: IntOut) -> Parsed:
  IntOut{+m, +read, +rest} = o
  +c = head(rest)
  +next = Bool.pick(U32, U32.is_eq(c, 46), 2, Bool.pick(U32, is_e(c), 3, 1))
  integer.route(Bool.pick(U32, U32.is_eq(read, 0), 0, Bool.pick(U32, List.is_empty(&2, U32, rest), 1, next)), fused, negative, m, rest)

def parse.route(route: U32, +fused: Bool, +negative: Bool, +t: +List<U32>) -> Parsed:
  match route:
    case 0: parsed.zero()
    case 1: integer.done(fused, negative, p.int(tail(t), is_digit(head(tail(t))), num.zero(), 0))
    case _: integer.done(fused, negative, p.int(t, True{}, num.zero(), 0))

# tryParseDouble over one token: [sign] digits ['.' digits] [e [sign]
# digits], greedy, stopping at the first byte outside the grammar. A failed
# parse leaves 0.0.
def parse.double(+fused: Bool, +t: +List<U32>) -> Parsed:
  +c = head(t)
  +route = Bool.pick(U32, U32.is_eq(c, 43) || U32.is_eq(c, 45), 1, Bool.pick(U32, is_digit(c), 2, 0))
  parse.route(Bool.pick(U32, List.is_empty(&2, U32, t), 0, route), fused, U32.is_eq(c, 45), t)

type FloatOut is Data:
  FloatOut{value: Parsed, rest: +List<U32>}

def parse.float.with(+fused: Bool, split: +List<U32> & +List<U32>) -> FloatOut:
  (+t, +rest) = split
  FloatOut{parse.double(fused, t), rest}

# parseFloat: skip spaces, the token up to NUL/' '/'\t'/'\r', parsed.
def parse.float(+fused: Bool, +bs: +List<U32>) -> FloatOut:
  parse.float.with(fused, token.split(skip_space(bs)))

# -----------------------------------------------------------------------------
# my_atoi: [sign] digits; an int overflow is undefined.

type Atoi is Data:
  Atoi{negative: Bool, value: U32, overflow: Bool}

def atoi.digits(bs: +List<U32>, digit: Bool, +value: U32, +overflow: Bool) -> U32 & Bool:
  match bs digit:
    case Con{+c, +rest} True{}:
      +d = (c - 48 : U32)
      atoi.digits(rest, is_digit(head(rest)), (value * 10 + d : U32), overflow || (value > ((2147483647 - d) / 10 : U32) : U32))
    case _ _: (value, overflow)

def atoi.with(+negative: Bool, r: U32 & Bool) -> Atoi:
  (+value, +overflow) = r
  Atoi{negative, value, overflow}

def atoi(+bs: +List<U32>) -> Atoi:
  +c = head(bs)
  +signed = U32.is_eq(c, 43) || U32.is_eq(c, 45)
  +digits = Bool.pick(+List<U32>, signed, tail(bs), bs)
  atoi.with(U32.is_eq(c, 45), atoi.digits(digits, is_digit(head(digits)), 0, False{}))

# -----------------------------------------------------------------------------
# Lines: tinyobj splits at '\n' and at a '\r' followed by another byte than
# '\n' (not the last one); a line ending in '\r' before its terminator loses
# it, and an empty line after a lone '\r' would underflow its length
# (refused). The final line runs from the last terminator to the end, or
# misses the text's last byte when there is no terminator at all.

type Lines is Data:
  Lines{ok: Bool, lines: +List<+List<U32>>}

def lines.close(+line: +List<U32>, +previous: U32, +out: Lines) -> Lines:
  Lines{+ok, +ls} = out
  +cr = U32.is_eq(previous, 13)
  +empty = List.is_empty(&2, U32, line)
  Lines{ok && Bool.not(cr && empty), Con{reverse(Bool.pick(+List<U32>, cr && Bool.not(empty), tail(line), line)), ls}}

def lines.finish(+line: +List<U32>, +ended: Bool, +out: Lines) -> Lines:
  Lines{+ok, +ls} = out
  Lines{ok, List.reverse(&2, +List<U32>, Con{reverse(Bool.pick(+List<U32>, ended, line, tail(line))), ls})}

# is_line_ending at the head: '\n', or '\r' followed by a byte other than '\n'.
def lines.ends(+bs: +List<U32>) -> Bool:
  +c = head(bs)
  +rest = tail(bs)
  U32.is_eq(c, 10) || (U32.is_eq(c, 13) && Bool.not(List.is_empty(&2, U32, rest)) && Bool.not(U32.is_eq(head(rest), 10)))

# line: the current line reversed; previous: the byte before the head;
# ended: whether a terminator was seen.
def lines.go(bs: +List<U32>, ending: Bool, +line: +List<U32>, +previous: U32, +ended: Bool, +out: Lines) -> Lines:
  match bs ending:
    case Nil{} _: lines.finish(line, ended, out)
    case Con{+c, +rest} True{}: lines.go(rest, lines.ends(rest), Nil{}, c, True{}, lines.close(line, previous, out))
    case Con{+c, +rest} False{}: lines.go(rest, lines.ends(rest), Con{c, line}, c, ended, out)

def lines(+bs: +List<U32>) -> Lines:
  lines.go(bs, lines.ends(bs), Nil{}, 0, False{}, Lines{True{}, Nil{}})

# -----------------------------------------------------------------------------
# parseLine

type Raw is Data:
  Missing{}
  RawInt{negative: Bool, value: U32}

type Corner is Data:
  Corner{v: Raw, vt: Raw, vn: Raw}

# One line's command; CBad is a line the reference leaves undefined (an
# assert, a buffer overflow, a read before an empty name, an int overflow).
type Cmd is Data:
  CEmpty{}
  CV{x: Parsed, y: Parsed, z: Parsed}
  CVN{x: Parsed, y: Parsed, z: Parsed}
  CVT{x: Parsed, y: Parsed}
  CF{corners: +List<Corner>, count: U32}
  CUse{name: +List<U32>}
  CLib{name: +List<U32>}
  CShape{}
  CBad{}

def in_token(+c: U32) -> Bool:
  Bool.not(U32.is_eq(c, 0) || U32.is_eq(c, 47) || is_space(c) || U32.is_eq(c, 13))

def skip_token.go(bs: +List<U32>, skip: Bool) -> +List<U32>:
  match bs skip:
    case Nil{} _: Nil{}
    case Con{_, +rest} True{}: skip_token.go(rest, in_token(head(rest)))
    case Con{+c, rest} False{}: Con{c, rest}

# The walk parseRawTriple does after each number: up to NUL, '/', ' ', '\t' or '\r'.
def skip_token(+bs: +List<U32>) -> +List<U32>:
  skip_token.go(bs, in_token(head(bs)))

def raw.of(+a: Atoi) -> Raw:
  Atoi{+negative, +value, _} = a
  RawInt{negative, value}

def raw.over(+a: Atoi) -> Bool:
  Atoi{_, _, +overflow} = a
  overflow

type Triple is Data:
  Triple{corner: Corner, overflow: Bool, rest: +List<U32>}

def triple.third(slash: Bool, +v: Atoi, +t: Atoi, +c: +List<U32>) -> Triple:
  match slash:
    case False{}: Triple{Corner{raw.of(v), raw.of(t), Missing{}}, raw.over(v) || raw.over(t), c}
    case True{}:
      +n = atoi(tail(c))
      Triple{Corner{raw.of(v), raw.of(t), raw.of(n)}, raw.over(v) || raw.over(t) || raw.over(n), skip_token(tail(c))}

def triple.second(double: Bool, +v: Atoi, +b: +List<U32>) -> Triple:
  match double:
    case True{}:
      +n = atoi(tail(b))
      Triple{Corner{raw.of(v), Missing{}, raw.of(n)}, raw.over(v) || raw.over(n), skip_token(tail(b))}
    case False{}:
      +t = atoi(b)
      +c = skip_token(b)
      triple.third(U32.is_eq(head(c), 47), v, t, c)

def triple.slash(slash: Bool, +v: Atoi, +a: +List<U32>) -> Triple:
  match slash:
    case False{}: Triple{Corner{raw.of(v), Missing{}, Missing{}}, raw.over(v), a}
    case True{}: triple.second(U32.is_eq(head(tail(a)), 47), v, tail(a))

# parseRawTriple: i, i/j, i//k or i/j/k (missing indices invalid).
def triple(+bs: +List<U32>) -> Triple:
  +a = skip_token(bs)
  triple.slash(U32.is_eq(head(a), 47), atoi(bs), a)

def triple.corner(+t: Triple) -> Corner:
  Triple{+c, _, _} = t
  c

def triple.over(+t: Triple) -> Bool:
  Triple{_, +o, _} = t
  o

def triple.rest(+t: Triple) -> +List<U32>:
  Triple{_, _, +r} = t
  r

def is_new_line(+c: U32) -> Bool:
  U32.is_eq(c, 13) || U32.is_eq(c, 10) || U32.is_eq(c, 0)

type Face is Data:
  Face{corners: +List<Corner>, count: U32, overflow: Bool}

# The face's triples until a NUL, '\r' or '\n' (fuel: the line's length).
def face.go(fuel: Nat, done: Bool, +bs: +List<U32>, +acc: +List<Corner>, +count: U32, +overflow: Bool) -> Face:
  match fuel done:
    case _ True{}: Face{List.reverse(&2, Corner, acc), count, overflow}
    case 0n False{}: Face{List.reverse(&2, Corner, acc), count, True{}}
    case 1n+k False{}:
      +t = triple(bs)
      +rest = skip_space_cr(triple.rest(t))
      face.go(k, is_new_line(head(rest)), rest, Con{triple.corner(t), acc}, (count + 1 : U32), overflow || triple.over(t))

# More than 5 vertices fail tinyobj's assert(3*num_f < 16) (or, without
# asserts, overflow its arrays from 8): refused.
def cmd.f.done(+f: Face) -> Cmd:
  Face{+corners, +count, +overflow} = f
  Bool.pick(Cmd, overflow || (count > 5 : U32), CBad{}, CF{corners, count})

def cmd.f(+bs: +List<U32>) -> Cmd:
  +start = skip_space(bs)
  cmd.f.done(face.go(U32.to_nat((length(start, 0) + 1 : U32)), is_new_line(head(start)), start, Nil{}, 0, False{}))

def float.value(+f: FloatOut) -> Parsed:
  FloatOut{+v, _} = f
  v

def float.rest(+f: FloatOut) -> +List<U32>:
  FloatOut{_, +r} = f
  r

def cmd.v(+kind: U32, +fused: Bool, +bs: +List<U32>) -> Cmd:
  +a = parse.float(fused, bs)
  +b = parse.float(fused, float.rest(a))
  +c = parse.float(fused, float.rest(b))
  Bool.pick(Cmd, U32.is_eq(kind, 1), CV{float.value(a), float.value(b), float.value(c)}, CVN{float.value(a), float.value(b), float.value(c)})

def cmd.vt(+fused: Bool, +bs: +List<U32>) -> Cmd:
  +a = parse.float(fused, bs)
  CVT{float.value(a), float.value(parse.float(fused, float.rest(a)))}

# mtllib, g and o with nothing after the keyword and its space: tinyobj
# computes length_until_newline over p_len - offset - 1 (an unsigned
# underflow) and reads past the line.
def cmd.named(+lib: Bool, +bs: +List<U32>) -> Cmd:
  Bool.pick(Cmd, List.is_empty(&2, U32, bs), CBad{}, Bool.pick(Cmd, lib, CLib{bs}, CShape{}))

def line.cmd(route: U32, +fused: Bool, +t: +List<U32>) -> Cmd:
  match route:
    case 1: cmd.v(1, fused, drop(2n, t))
    case 2: cmd.v(2, fused, drop(3n, t))
    case 3: cmd.vt(fused, drop(3n, t))
    case 4: cmd.f(drop(2n, t))
    case 5: CUse{skip_space(drop(7n, t))}
    case 6: cmd.named(True{}, skip_space(drop(7n, t)))
    case 7: cmd.named(False{}, drop(2n, t))
    case _: CEmpty{}

def prefix(word: +List<U32>, +bs: +List<U32>) -> Bool:
  match word:
    case Nil{}: True{}
    case Con{+w, rest}: U32.is_eq(head(bs), w) && prefix(rest, tail(bs))

def line.kind(+t: +List<U32>) -> U32:
  +c0 = at(0n, t)
  +c1 = at(1n, t)
  +c2 = at(2n, t)
  +v = U32.is_eq(c0, 118)
  Bool.pick(U32, v && is_space(c1), 1, Bool.pick(U32, v && U32.is_eq(c1, 110) && is_space(c2), 2, Bool.pick(U32, v && U32.is_eq(c1, 116) && is_space(c2), 3,
    Bool.pick(U32, U32.is_eq(c0, 102) && is_space(c1), 4, Bool.pick(U32, prefix([117, 115, 101, 109, 116, 108], t) && is_space(at(6n, t)), 5,
    Bool.pick(U32, prefix([109, 116, 108, 108, 105, 98], t) && is_space(at(6n, t)), 6,
    Bool.pick(U32, (U32.is_eq(c0, 103) || U32.is_eq(c0, 111)) && is_space(c1), 7, 0)))))))

# parseLine: lines of 4095 bytes or more fail its assert(p_len < 4095).
def parse.line(+fused: Bool, +line: +List<U32>) -> Cmd:
  +t = skip_space(line)
  Bool.pick(Cmd, (length(line, 0) >= 4095 : U32), CBad{}, line.cmd(line.kind(t), fused, t))

def commands(ls: +List<+List<U32>>, +fused: Bool, +acc: +List<Cmd>) -> +List<Cmd>:
  match ls:
    case Nil{}: List.reverse(&2, Cmd, acc)
    case Con{+line, rest}: commands(rest, fused, Con{parse.line(fused, line), acc})

# The last mtllib's name (tinyobj loads only that one).
def mtllib(cmds: +List<Cmd>, +found: Maybe<&2, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match cmds:
    case Nil{}: found
    case Con{CLib{+name}, rest}: mtllib(rest, Some{name})
    case Con{_, rest}: mtllib(rest, found)

# -----------------------------------------------------------------------------
# The material table: djb2 hashes (64-bit unsigned long) in an open table of
# capacity 10 grown to 2*max(capacity, n + 1), quadratic probing from hash %
# capacity. An insertion that finds no slot loops forever (or, when growing,
# loses the entry and later dereferences NULL): refused.

type H64 is Data:
  H64{high: U32, low: U32}

def djb2.step(+h: H64, +c: U32) -> H64:
  H64{+hi, +lo} = h
  +t = (lo << 5n : U32)
  +s = (t + lo : U32)
  +u = (s + c : U32)
  H64{((hi << 5n) + hi + (lo >> 27n) + Bool.to_u32((s < t : U32)) + Bool.to_u32((u < s : U32)) : U32), u}

def djb2.go(bs: +List<U32>, +h: H64) -> H64:
  match bs:
    case Nil{}: h
    case Con{+c, rest}: djb2.go(rest, djb2.step(h, c))

def djb2(+bs: +List<U32>) -> H64:
  djb2.go(bs, H64{0, 5381})

def h64.eq(+a: H64, +b: H64) -> Bool:
  H64{+ah, +al} = a
  H64{+bh, +bl} = b
  U32.is_eq(ah, bh) && U32.is_eq(al, bl)

# hash % capacity (capacity below 2^16).
def h64.mod(+h: H64, +cap: U32) -> U32:
  H64{+hi, +lo} = h
  +r32 = (((4294967295 % cap) + 1) % cap : U32)
  ((((hi % cap) * r32) + (lo % cap)) % cap : U32)

def member(xs: +List<U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+y, rest}: U32.is_eq(x, y) || member(rest, x)

def probe(fuel: Nat, free: Bool, +slots: +List<U32>, +cap: U32, +start: U32, +index: U32, +i: U32) -> Maybe<&2, U32>:
  match fuel free:
    case _ True{}: Some{index}
    case 0n False{}: None{}
    case 1n+k False{}:
      +next = ((start + i * i) % cap : U32)
      probe(k, Bool.not(member(slots, next)), slots, cap, start, next, (i + 1 : U32))

# hash_table_insert_value: the slot, or None when the probe gives up.
def insert(+slots: +List<U32>, +cap: U32, +h: H64) -> Maybe<&2, U32>:
  +start = h64.mod(h, cap)
  probe(U32.to_nat((cap - 1 : U32)), Bool.not(member(slots, start)), slots, cap, start, start, 1)

type Placed is Data:
  Placed{ok: Bool, slots: +List<U32>}

def Placed.slots(+p: Placed) -> +List<U32>:
  Placed{_, +slots} = p
  slots

def placed.add(+slot: Maybe<&2, U32>, +p: Placed) -> Placed:
  Placed{+ok, +slots} = p
  Placed{ok && Maybe.is_some(&2, U32, slot), Con{Maybe.default(&2, U32, slot, 0), slots}}

def rehash(hashes: +List<H64>, +cap: U32, +p: Placed) -> Placed:
  match hashes:
    case Nil{}: p
    case Con{+h, rest}: rehash(rest, cap, placed.add(insert(Placed.slots(p), cap, h), p))

type Entry is Data:
  Entry{hash: H64, value: U32}

type Table is Data:
  Table{ok: Bool, cap: U32, n: U32, order: +List<H64>, slots: +List<U32>, entries: +List<Entry>}

def table.new() -> Table:
  Table{True{}, 10, 0, Nil{}, Nil{}, Nil{}}

def entries.find(entries: +List<Entry>, +h: H64) -> Maybe<&2, U32>:
  match entries:
    case Nil{}: None{}
    case Con{Entry{+eh, +v}, rest}: Bool.pick(Maybe<&2, U32>, h64.eq(eh, h), Some{v}, entries.find(rest, h))

def entries.update(entries: +List<Entry>, +h: H64, +value: U32) -> +List<Entry>:
  match entries:
    case Nil{}: Nil{}
    case Con{Entry{+eh, +v}, rest}: Con{Entry{eh, Bool.pick(U32, h64.eq(eh, h), value, v)}, entries.update(rest, h, value)}

def table.insert.at(+t: Table, +h: H64, +value: U32, +slot: Maybe<&2, U32>) -> Table:
  Table{+ok, +cap, +n, +order, +slots, +entries} = t
  Table{ok && Maybe.is_some(&2, U32, slot), cap, (n + 1 : U32), List.append(&2, H64, order, [h]), Con{Maybe.default(&2, U32, slot, 0), slots},
    Con{Entry{h, value}, entries}}

def table.grow.with(+t: Table, +cap: U32, +p: Placed) -> Table:
  Table{+ok, _, +n, +order, _, +entries} = t
  Placed{+pok, +slots} = p
  Table{ok && pok, cap, n, order, slots, entries}

# hash_table_maybe_grow(n + 1): a full table moves to the new capacity, its
# hashes reinserted in insertion order.
def table.grow(+t: Table) -> Table:
  Table{_, +cap, +n, +order, _, _} = t
  +wanted = (n + 1 : U32)
  +bigger = (2 * Bool.pick(U32, ((2 * cap : U32) > wanted : U32), cap, wanted) : U32)
  Bool.pick(Table, (wanted > cap : U32), table.grow.with(t, bigger, rehash(order, bigger, Placed{True{}, Nil{}})), t)

def table.slots(+t: Table) -> +List<U32>:
  Table{_, _, _, _, +slots, _} = t
  slots

def table.cap(+t: Table) -> U32:
  Table{_, +cap, _, _, _, _} = t
  cap

def table.entries(+t: Table) -> +List<Entry>:
  Table{_, _, _, _, _, +entries} = t
  entries

def table.update(+t: Table, +h: H64, +value: U32) -> Table:
  Table{+ok, +cap, +n, +order, +slots, +entries} = t
  Table{ok, cap, n, order, slots, entries.update(entries, h, value)}

def table.added(+g: Table, +h: H64, +value: U32) -> Table:
  table.insert.at(g, h, value, insert(table.slots(g), table.cap(g), h))

# hash_table_set: an existing hash takes the new value; otherwise grow if
# needed and insert (a failed insertion cannot recover).
def table.set(+t: Table, +h: H64, +value: U32) -> Table:
  Bool.pick(Table, Maybe.is_some(&2, U32, entries.find(table.entries(t), h)), table.update(t, h, value), table.added(table.grow(t), h, value))

def table.get(+t: Table, +h: H64) -> Maybe<&2, U32>:
  entries.find(table.entries(t), h)

def table.ok(+t: Table) -> Bool:
  Table{+ok, _, _, _, _, _} = t
  ok

# -----------------------------------------------------------------------------
# MTL files (tinyobj_parse_and_index_mtl_file). Lines come from
# dynamic_fgets: each ends with its '\n' (kept); a last line without one is
# never returned, so it is not parsed. A NUL byte makes strlen/strchr see
# other lines than the file's: refused.

type Mtl is Data:
  Mtl{diffuse: +List<Parsed>, specular: +List<Parsed>, emission: +List<Parsed>, shininess: Parsed, diffuse_tex: Maybe<&2, +List<U32>>,
    specular_tex: Maybe<&2, +List<U32>>, bump_tex: Maybe<&2, +List<U32>>, disp_tex: Maybe<&2, +List<U32>>}

def mtl.init() -> Mtl:
  Mtl{[parsed.zero(), parsed.zero(), parsed.zero()], [parsed.zero(), parsed.zero(), parsed.zero()], [parsed.zero(), parsed.zero(), parsed.zero()],
    Parsed{False{}, Some{1.0}}, None{}, None{}, None{}, None{}}

type MtlState is Data:
  MtlState{ok: Bool, named: Bool, current: Mtl, done: +List<Mtl>, count: U32, table: Table}

def mtl.lines(bs: +List<U32>, newline: Bool, +line: +List<U32>, +out: +List<+List<U32>>) -> +List<+List<U32>>:
  match bs newline:
    case Nil{} _: List.reverse(&2, +List<U32>, out)
    case Con{+c, +rest} True{}: mtl.lines(rest, U32.is_eq(head(rest), 10), Nil{}, Con{reverse(Con{c, line}), out})
    case Con{+c, +rest} False{}: mtl.lines(rest, U32.is_eq(head(rest), 10), Con{c, line}, out)

def is_c_space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || ((c >= 9 : U32) && (c <= 13 : U32))

def word.go(bs: +List<U32>, stop: Bool, +acc: +List<U32>) -> +List<U32>:
  match bs stop:
    case Con{+c, +rest} False{}: word.go(rest, is_c_space(head(rest)) || U32.is_eq(head(rest), 0), Con{c, acc})
    case _ _: reverse(acc)

def word.skip(bs: +List<U32>, skip: Bool) -> +List<U32>:
  match bs skip:
    case Con{_, +rest} True{}: word.skip(rest, is_c_space(head(rest)))
    case Nil{} _: Nil{}
    case Con{+c, rest} False{}: Con{c, rest}

# sscanf(token, "%s", namebuf): whitespace skipped, then the non-space run.
def scan.word(+bs: +List<U32>) -> +List<U32>:
  +start = word.skip(bs, is_c_space(head(bs)))
  word.go(start, is_c_space(head(start)) || U32.is_eq(head(start), 0), Nil{})

def lf.go(bs: +List<U32>, stop: Bool, +acc: +List<U32>) -> +List<U32>:
  match bs stop:
    case Con{+c, +rest} False{}: lf.go(rest, U32.is_eq(head(rest), 10) || U32.is_eq(head(rest), 13), Con{c, acc})
    case _ _: reverse(acc)

# my_strdup(token, line_end - token): the bytes before the first '\n' or '\r'.
def until_lf(+bs: +List<U32>) -> +List<U32>:
  lf.go(bs, U32.is_eq(head(bs), 10) || U32.is_eq(head(bs), 13), Nil{})

def parsed.ub(+p: Parsed) -> Bool:
  Parsed{+ub, _} = p
  ub

def three(+fused: Bool, +bs: +List<U32>) -> +List<Parsed>:
  +a = parse.float(fused, bs)
  +b = parse.float(fused, float.rest(a))
  [float.value(a), float.value(b), float.value(parse.float(fused, float.rest(b)))]

def parsed.list.ub(ps: +List<Parsed>) -> Bool:
  match ps:
    case Nil{}: False{}
    case Con{+p, rest}: parsed.ub(p) || parsed.list.ub(rest)

def mtl.with.color(+which: U32, +m: Mtl, +values: +List<Parsed>) -> Mtl:
  Mtl{+d, +s, +e, +ns, +dt, +st, +bt, +pt} = m
  Mtl{Bool.pick(+List<Parsed>, U32.is_eq(which, 3), values, d), Bool.pick(+List<Parsed>, U32.is_eq(which, 4), values, s),
    Bool.pick(+List<Parsed>, U32.is_eq(which, 7), values, e), ns, dt, st, bt, pt}

def mtl.with.shininess(+m: Mtl, +value: Parsed) -> Mtl:
  Mtl{+d, +s, +e, _, +dt, +st, +bt, +pt} = m
  Mtl{d, s, e, value, dt, st, bt, pt}

def mtl.with.tex(+which: U32, +m: Mtl, +name: +List<U32>) -> Mtl:
  Mtl{+d, +s, +e, +ns, +dt, +st, +bt, +pt} = m
  Mtl{d, s, e, ns, Bool.pick(Maybe<&2, +List<U32>>, U32.is_eq(which, 13), Some{name}, dt), Bool.pick(Maybe<&2, +List<U32>>, U32.is_eq(which, 14), Some{name}, st),
    Bool.pick(Maybe<&2, +List<U32>>, U32.is_eq(which, 16) || U32.is_eq(which, 18), Some{name}, bt), Bool.pick(Maybe<&2, +List<U32>>, U32.is_eq(which, 19), Some{name}, pt)}

def state.current(+s: MtlState, +m: Mtl, +ub: Bool) -> MtlState:
  MtlState{+ok, +named, _, +done, +count, +table} = s
  MtlState{ok && Bool.not(ub), named, m, done, count, table}

def state.mtl(+s: MtlState) -> Mtl:
  MtlState{_, _, +m, _, _, _} = s
  m

# newmtl: the previous material flushed (from the second on), a fresh one,
# and the table entry name -> index. A name that does not scan (namebuf left
# unset), one of 4096 bytes or more, or a line longer than namebuf (my_strdup
# scans namebuf for the line's length) is refused.
def state.newmtl(+s: MtlState, +rest: +List<U32>) -> MtlState:
  MtlState{+ok, +named, +current, +done, +count, +table} = s
  +name = scan.word(rest)
  +size = length(name, 0)
  +flushed = Bool.pick(U32, named, (count + 1 : U32), count)
  MtlState{ok && (size >= 1 : U32) && (size < 4096 : U32) && (length(rest, 0) <= 4096 : U32), True{}, mtl.init(),
    Bool.pick(+List<Mtl>, named, Con{current, done}, done), flushed, table.set(table, djb2(name), flushed)}

def illum.ub(+bs: +List<U32>) -> Bool:
  raw.over(atoi(skip_space(bs)))

def state.color(+which: U32, +s: MtlState, +values: +List<Parsed>) -> MtlState:
  state.current(s, mtl.with.color(which, state.mtl(s), values), parsed.list.ub(values))

def state.shine(+s: MtlState, +value: Parsed) -> MtlState:
  state.current(s, mtl.with.shininess(state.mtl(s), value), parsed.ub(value))

def state.tex(+which: U32, +s: MtlState, +name: +List<U32>) -> MtlState:
  state.current(s, mtl.with.tex(which, state.mtl(s), name), False{})

def mtl.route(route: U32, +fused: Bool, +t: +List<U32>, +s: MtlState) -> MtlState:
  match route:
    case 1: state.newmtl(s, drop(7n, t))
    case 2: state.color(0, s, three(fused, drop(2n, t)))
    case 3: state.color(3, s, three(fused, drop(2n, t)))
    case 4: state.color(4, s, three(fused, drop(2n, t)))
    case 5: state.color(0, s, three(fused, drop(2n, t)))
    case 6: state.current(s, state.mtl(s), parsed.ub(float.value(parse.float(fused, drop(2n, t)))))
    case 7: state.color(7, s, three(fused, drop(2n, t)))
    case 8: state.shine(s, float.value(parse.float(fused, drop(2n, t))))
    case 9: state.current(s, state.mtl(s), illum.ub(drop(6n, t)))
    case 10: state.current(s, state.mtl(s), parsed.ub(float.value(parse.float(fused, drop(1n, t)))))
    case 11: state.current(s, state.mtl(s), parsed.ub(float.value(parse.float(fused, drop(2n, t)))))
    case 13: state.tex(13, s, until_lf(drop(7n, t)))
    case 14: state.tex(14, s, until_lf(drop(7n, t)))
    case 16: state.tex(16, s, until_lf(drop(9n, t)))
    case 18: state.tex(18, s, until_lf(drop(5n, t)))
    case 19: state.tex(19, s, until_lf(drop(5n, t)))
    case _: s

def two.is(+t: +List<U32>, +a: U32, +b: U32) -> Bool:
  U32.is_eq(at(0n, t), a) && U32.is_eq(at(1n, t), b) && is_space(at(2n, t))

def word.is(+t: +List<U32>, +word: +List<U32>, n: Nat) -> Bool:
  prefix(word, t) && is_space(at(n, t))

# The keyword checks in tinyobj's order (12, 15 and 17 are the unused map_Ka,
# map_Ns and map_d).
def mtl.kind(+t: +List<U32>) -> U32:
  Bool.pick(U32, word.is(t, [110, 101, 119, 109, 116, 108], 6n), 1, Bool.pick(U32, two.is(t, 75, 97), 2, Bool.pick(U32, two.is(t, 75, 100), 3,
    Bool.pick(U32, two.is(t, 75, 115), 4, Bool.pick(U32, two.is(t, 75, 116), 5, Bool.pick(U32, two.is(t, 78, 105), 6, Bool.pick(U32, two.is(t, 75, 101), 7,
    Bool.pick(U32, two.is(t, 78, 115), 8, Bool.pick(U32, word.is(t, [105, 108, 108, 117, 109], 5n), 9,
    Bool.pick(U32, U32.is_eq(at(0n, t), 100) && is_space(at(1n, t)), 10, Bool.pick(U32, two.is(t, 84, 114), 11,
    Bool.pick(U32, word.is(t, [109, 97, 112, 95, 75, 97], 6n), 12, Bool.pick(U32, word.is(t, [109, 97, 112, 95, 75, 100], 6n), 13,
    Bool.pick(U32, word.is(t, [109, 97, 112, 95, 75, 115], 6n), 14, Bool.pick(U32, word.is(t, [109, 97, 112, 95, 78, 115], 6n), 15,
    Bool.pick(U32, word.is(t, [109, 97, 112, 95, 98, 117, 109, 112], 8n), 16, Bool.pick(U32, word.is(t, [109, 97, 112, 95, 100], 5n), 17,
    Bool.pick(U32, word.is(t, [98, 117, 109, 112], 4n), 18, Bool.pick(U32, word.is(t, [100, 105, 115, 112], 4n), 19, 0)))))))))))))))))))

def mtl.step(+fused: Bool, +line: +List<U32>, +s: MtlState) -> MtlState:
  +t = skip_space(line)
  mtl.route(Bool.pick(U32, U32.is_eq(at(0n, t), 35), 0, mtl.kind(t)), fused, t, s)

def mtl.go(ls: +List<+List<U32>>, +fused: Bool, +s: MtlState) -> MtlState:
  match ls:
    case Nil{}: s
    case Con{+line, rest}: mtl.go(rest, fused, mtl.step(fused, line, s))

type MtlOut is Data:
  MtlOut{ok: Bool, materials: +List<Mtl>, table: Table}

def mtl.finish(+s: MtlState) -> MtlOut:
  MtlState{+ok, +named, +current, +done, _, +table} = s
  MtlOut{ok, List.reverse(&2, Mtl, Bool.pick(+List<Mtl>, named, Con{current, done}, done)), table}

def MtlOut.ok(+o: MtlOut) -> Bool:
  MtlOut{+ok, _, _} = o
  ok

def MtlOut.materials(+o: MtlOut) -> +List<Mtl>:
  MtlOut{_, +m, _} = o
  m

def MtlOut.table(+o: MtlOut) -> Table:
  MtlOut{_, _, +t} = o
  t

# The materials of an MTL file in order and the name table.
def mtl.parse(+fused: Bool, +bs: +List<U32>) -> MtlOut:
  +s = mtl.finish(mtl.go(mtl.lines(bs, U32.is_eq(head(bs), 10), Nil{}, Nil{}), fused, MtlState{True{}, False{}, mtl.init(), Nil{}, 0, table.new()}))
  MtlOut{Bool.not(member(bs, 0)) && MtlOut.ok(s), MtlOut.materials(s), MtlOut.table(s)}

# No MTL file (or none opened): no materials, an empty table.
def mtl.none() -> MtlOut:
  MtlOut{True{}, Nil{}, table.new()}

# -----------------------------------------------------------------------------
# Attributes (tinyobj_parse_obj's construction pass): vertices, normals and
# texcoords in order, faces with indices made zero-based (negative ones
# relative to the counts so far; invalid stays negative) and the material
# of the last usemtl (-1 when unknown).

type Fix is Data:
  Fix{ok: Bool, index: U32}

type FC is Data:
  FC{v: Fix, vt: Fix, vn: Fix}

type Tri is Data:
  Tri{a: FC, b: FC, c: FC, material: U32}

def fix.int(+negative: Bool, +value: U32, +n: U32) -> Fix:
  Bool.pick(Fix, U32.is_eq(value, 0), Fix{True{}, 0}, Bool.pick(Fix, negative, Bool.pick(Fix, (value <= n : U32), Fix{True{}, (n - value : U32)}, Fix{False{}, 0}),
    Fix{True{}, (value - 1 : U32)}))

# fixIndex
def fix(+raw: Raw, +n: U32) -> Fix:
  match raw:
    case Missing{}: Fix{False{}, 0}
    case RawInt{+negative, +value}: fix.int(negative, value, n)

def fix.corner(+c: Corner, +nv: U32, +nt: U32, +nn: U32) -> FC:
  Corner{+v, +vt, +vn} = c
  FC{fix(v, nv), fix(vt, nt), fix(vn, nn)}

def fix.corners(cs: +List<Corner>, +nv: U32, +nt: U32, +nn: U32) -> +List<FC>:
  match cs:
    case Nil{}: Nil{}
    case Con{+c, rest}: Con{fix.corner(c, nv, nt, nn), fix.corners(rest, nv, nt, nn)}

def tris(rest: +List<FC>, +f0: FC, +prev: FC, +m: U32, +acc: +List<Tri>) -> +List<Tri>:
  match rest:
    case Nil{}: acc
    case Con{+c, more}: tris(more, f0, c, m, Con{Tri{f0, prev, c, m}, acc})

# Triangulation: (f0, f[k-1], f[k]) for k >= 2, pushed on the reversed faces.
def triangulate(fs: +List<FC>, +m: U32, +acc: +List<Tri>) -> +List<Tri>:
  match fs:
    case Con{+f0, Con{+f1, rest}}: tris(rest, f0, f1, m, acc)
    case _: acc

type Attrib is Data:
  Attrib{ok: Bool, vertices: +List<Parsed>, normals: +List<Parsed>, texcoords: +List<Parsed>, nv: U32, nn: U32, nt: U32, faces: +List<Tri>, material: U32}

def push3(+x: Parsed, +y: Parsed, +z: Parsed, +acc: +List<Parsed>) -> +List<Parsed>:
  Con{z, Con{y, Con{x, acc}}}

def attrib.v(+a: Attrib, +x: Parsed, +y: Parsed, +z: Parsed) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{ok && Bool.not(parsed.ub(x) || parsed.ub(y) || parsed.ub(z)), push3(x, y, z, vs), ns, ts, (nv + 1 : U32), nn, nt, fs, m}

def attrib.vn(+a: Attrib, +x: Parsed, +y: Parsed, +z: Parsed) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{ok && Bool.not(parsed.ub(x) || parsed.ub(y) || parsed.ub(z)), vs, push3(x, y, z, ns), ts, nv, (nn + 1 : U32), nt, fs, m}

def attrib.vt(+a: Attrib, +x: Parsed, +y: Parsed) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{ok && Bool.not(parsed.ub(x) || parsed.ub(y)), vs, ns, Con{y, Con{x, ts}}, nv, nn, (nt + 1 : U32), fs, m}

def attrib.f(+a: Attrib, +corners: +List<Corner>) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{ok, vs, ns, ts, nv, nn, nt, triangulate(fix.corners(corners, nv, nt, nn), m, fs), m}

def attrib.use(+a: Attrib, +id: U32) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, _} = a
  Attrib{ok, vs, ns, ts, nv, nn, nt, fs, id}

def attrib.bad(+a: Attrib) -> Attrib:
  Attrib{_, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{False{}, vs, ns, ts, nv, nn, nt, fs, m}

def attrib.material(+a: Attrib) -> U32:
  Attrib{_, _, _, _, _, _, _, _, +m} = a
  m

# usemtl: a known name's index, -1 for an unknown one; an empty name keeps
# the current material.
def attrib.name(+a: Attrib, +table: Table, +name: +List<U32>) -> Attrib:
  attrib.use(a, Bool.pick(U32, List.is_empty(&2, U32, name), attrib.material(a), Maybe.default(&2, U32, table.get(table, djb2(name)), 4294967295)))

def attrib.step(+cmd: Cmd, +table: Table, +a: Attrib) -> Attrib:
  match cmd:
    case CV{+x, +y, +z}: attrib.v(a, x, y, z)
    case CVN{+x, +y, +z}: attrib.vn(a, x, y, z)
    case CVT{+x, +y}: attrib.vt(a, x, y)
    case CF{+corners, _}: attrib.f(a, corners)
    case CUse{+name}: attrib.name(a, table, name)
    case CBad{}: attrib.bad(a)
    case _: a

def attrib.go(cmds: +List<Cmd>, +table: Table, +a: Attrib) -> Attrib:
  match cmds:
    case Nil{}: a
    case Con{+cmd, rest}: attrib.go(rest, table, attrib.step(cmd, table, a))

def attrib.finish(+a: Attrib) -> Attrib:
  Attrib{+ok, +vs, +ns, +ts, +nv, +nn, +nt, +fs, +m} = a
  Attrib{ok, List.reverse(&2, Parsed, vs), List.reverse(&2, Parsed, ns), List.reverse(&2, Parsed, ts), nv, nn, nt, List.reverse(&2, Tri, fs), m}

def attributes(+cmds: +List<Cmd>, +table: Table) -> Attrib:
  attrib.finish(attrib.go(cmds, table, Attrib{True{}, Nil{}, Nil{}, Nil{}, 0, 0, 0, Nil{}, 4294967295}))

# -----------------------------------------------------------------------------
# Shapes: the face offsets (in face lines, as tinyobj counts them) of the
# shapes its 'o'/'g' pass builds.

type Shapes is Data:
  Shapes{faces: U32, index: U32, shape_offset: U32, face_offset: U32, offsets: +List<U32>}

def shapes.named(+s: Shapes) -> Shapes:
  Shapes{+faces, +index, +shape_offset, +face_offset, +offsets} = s
  +grown = (faces > face_offset : U32)
  +first = U32.is_eq(index, 0)
  +append = first || grown
  Bool.pick(Shapes, U32.is_eq(faces, 0), Shapes{0, index, 0, 0, offsets},
    Shapes{faces, Bool.pick(U32, append, (index + 1 : U32), index), faces, Bool.pick(U32, append, faces, face_offset),
      Bool.pick(+List<U32>, append, Con{Bool.pick(U32, first, 0, face_offset), offsets}, offsets)})

def shapes.face(+s: Shapes) -> Shapes:
  Shapes{+faces, +index, +shape_offset, +face_offset, +offsets} = s
  Shapes{(faces + 1 : U32), index, shape_offset, face_offset, offsets}

def shapes.step(+cmd: Cmd, +s: Shapes) -> Shapes:
  match cmd:
    case CShape{}: shapes.named(s)
    case CF{_, _}: shapes.face(s)
    case _: s

def shapes.go(cmds: +List<Cmd>, +s: Shapes) -> Shapes:
  match cmds:
    case Nil{}: s
    case Con{+cmd, rest}: shapes.go(rest, shapes.step(cmd, s))

def shapes.finish(+s: Shapes) -> +List<U32>:
  Shapes{+faces, _, +shape_offset, +face_offset, +offsets} = s
  List.reverse(&2, U32, Bool.pick(+List<U32>, (faces > face_offset : U32) && (faces > shape_offset : U32), Con{face_offset, offsets}, offsets))

def shapes(+cmds: +List<Cmd>) -> +List<U32>:
  shapes.finish(shapes.go(cmds, Shapes{0, 0, 0, 0, Nil{}}))

# -----------------------------------------------------------------------------
# LoadOBJ (rmodels.c): the faces split into meshes at shape offsets (compared
# with face indices, as rmodels.c does) and at material changes after a known
# material; each mesh gets its corners' vertices, normals ((0, 1, 0) without
# a valid index) and texcoords (when the file has any; v flipped as 1 - v,
# zero without a valid index), and the material of its last face (0 when
# that is not an index of the MTL materials). A vertex index that is
# negative or beyond the vertices, or a valid texcoord or normal index beyond
# its array, makes rmodels.c read outside tinyobj's arrays: refused.

type Item is Data:
  Item{a: Parsed, b: Parsed, c: Parsed}

type ITree is Data:
  ITip{}
  ILeaf{value: Item}
  INode{left: ITree, right: ITree}

def items3(ps: +List<Parsed>, +acc: +List<Item>) -> +List<Item>:
  match ps:
    case Con{+x, Con{+y, Con{+z, rest}}}: items3(rest, Con{Item{x, y, z}, acc})
    case _: List.reverse(&2, Item, acc)

def items2(ps: +List<Parsed>, +acc: +List<Item>) -> +List<Item>:
  match ps:
    case Con{+x, Con{+y, rest}}: items2(rest, Con{Item{x, y, parsed.zero()}, acc})
    case _: List.reverse(&2, Item, acc)

def itrees.reverse(xs: +List<ITree>, +acc: +List<ITree>) -> +List<ITree>:
  match xs:
    case Nil{}: acc
    case Con{+t, rest}: itrees.reverse(rest, Con{t, acc})

def ileaves(xs: +List<Item>, +acc: +List<ITree>) -> +List<ITree>:
  match xs:
    case Nil{}: itrees.reverse(acc, Nil{})
    case Con{+x, rest}: ileaves(rest, Con{ILeaf{x}, acc})

def ipairs(xs: +List<ITree>, +acc: +List<ITree>) -> +List<ITree>:
  match xs:
    case Con{+a, Con{+b, rest}}: ipairs(rest, Con{INode{a, b}, acc})
    case Con{+a, Nil{}}: itrees.reverse(Con{INode{a, ITip{}}, acc}, Nil{})
    case _: itrees.reverse(acc, Nil{})

def ilevels(d: Nat, +xs: +List<ITree>) -> +List<ITree>:
  match d:
    case 0n: xs
    case 1n+k: ilevels(k, ipairs(xs, Nil{}))

def itree.first(xs: +List<ITree>) -> ITree:
  match xs:
    case Con{+t, _}: t
    case Nil{}: ITip{}

def depth(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def itree.of(+d: Nat, +xs: +List<Item>) -> ITree:
  itree.first(ilevels(d, ileaves(xs, Nil{})))

def itree.get(+d: Nat, t: ITree, +i: U32) -> Item:
  match d t:
    case 0n ILeaf{+x}: x
    case 1n+k INode{l, r}: itree.get(k, Bool.pick(ITree, U32.is_eq(((i >> k) .&. 1 : U32), 1), r, l), i)
    case _ _: Item{parsed.zero(), parsed.zero(), parsed.zero()}

type Arrays is Data:
  Arrays{dv: Nat, tv: ITree, nv: U32, dn: Nat, tn: ITree, nn: U32, dt: Nat, tt: ITree, nt: U32}

def arrays.of(+a: Attrib) -> Arrays:
  Attrib{_, +vs, +ns, +ts, +nv, +nn, +nt, _, _} = a
  +dv = depth(nv)
  +dn = depth(nn)
  +dt = depth(nt)
  Arrays{dv, itree.of(dv, items3(vs, Nil{})), nv, dn, itree.of(dn, items3(ns, Nil{})), nn, dt, itree.of(dt, items2(ts, Nil{})), nt}

type MeshAcc is Data:
  MeshAcc{ok: Bool, count: U32, vertices: +List<F32>, normals: +List<F32>, texcoords: +List<F32>, material: U32}

def meshacc.new() -> MeshAcc:
  MeshAcc{True{}, 0, Nil{}, Nil{}, Nil{}, 0}

def meshacc.material(+m: MeshAcc, +material: U32) -> MeshAcc:
  MeshAcc{+ok, +count, +vs, +ns, +ts, _} = m
  MeshAcc{ok, count, vs, ns, ts, material}

def fix.ok(+f: Fix) -> Bool:
  Fix{+ok, _} = f
  ok

def fix.index(+f: Fix) -> U32:
  Fix{_, +i} = f
  i

def parsed.value(+p: Parsed) -> Maybe<&2, F32>:
  Parsed{_, +v} = p
  v

def parsed.has(+p: Parsed) -> Bool:
  Maybe.is_some(&2, F32, parsed.value(p))

def parsed.f32(+p: Parsed) -> F32:
  Maybe.default(&2, F32, parsed.value(p), 0.0)

def item.has3(+x: Item) -> Bool:
  Item{+a, +b, +c} = x
  parsed.has(a) && parsed.has(b) && parsed.has(c)

def item.has2(+x: Item) -> Bool:
  Item{+a, +b, _} = x
  parsed.has(a) && parsed.has(b)

def item.push3(+x: Item, +acc: +List<F32>) -> +List<F32>:
  Item{+a, +b, +c} = x
  Con{parsed.f32(c), Con{parsed.f32(b), Con{parsed.f32(a), acc}}}

def item.uv(+x: Item, +acc: +List<F32>) -> +List<F32>:
  Item{+a, +b, _} = x
  Con{(1.0 - parsed.f32(b) : F32), Con{parsed.f32(a), acc}}

def arrays.vertex(+arr: Arrays, +i: U32) -> Item:
  Arrays{+dv, +tv, _, _, _, _, _, _, _} = arr
  itree.get(dv, tv, i)

def arrays.normal(+arr: Arrays, +i: U32) -> Item:
  Arrays{_, _, _, +dn, +tn, _, _, _, _} = arr
  itree.get(dn, tn, i)

def arrays.texcoord(+arr: Arrays, +i: U32) -> Item:
  Arrays{_, _, _, _, _, _, +dt, +tt, _} = arr
  itree.get(dt, tt, i)

def arrays.nv(+arr: Arrays) -> U32:
  Arrays{_, _, +nv, _, _, _, _, _, _} = arr
  nv

def arrays.nn(+arr: Arrays) -> U32:
  Arrays{_, _, _, _, _, +nn, _, _, _} = arr
  nn

def arrays.nt(+arr: Arrays) -> U32:
  Arrays{_, _, _, _, _, _, _, _, +nt} = arr
  nt

def corner.add.with(+arr: Arrays, +v: Fix, +vt: Fix, +vn: Fix, +m: MeshAcc) -> MeshAcc:
  MeshAcc{+ok, +count, +vs, +ns, +ts, +material} = m
  +nv = arrays.nv(arr)
  +nn = arrays.nn(arr)
  +nt = arrays.nt(arr)
  +vertex = arrays.vertex(arr, fix.index(v))
  +normal = arrays.normal(arr, fix.index(vn))
  +texcoord = arrays.texcoord(arr, fix.index(vt))
  +has_normal = fix.ok(vn)
  +has_texcoord = fix.ok(vt) && (nt > 0 : U32)
  +valid = fix.ok(v) && (fix.index(v) < nv : U32) && item.has3(vertex)
    && Bool.not(has_normal && Bool.not((fix.index(vn) < nn : U32) && item.has3(normal)))
    && Bool.not(has_texcoord && Bool.not((fix.index(vt) < nt : U32) && item.has2(texcoord)))
  MeshAcc{ok && valid, (count + 1 : U32), item.push3(vertex, vs),
    Bool.pick(+List<F32>, has_normal, item.push3(normal, ns), Con{0.0, Con{1.0, Con{0.0, ns}}}),
    Bool.pick(+List<F32>, (nt > 0 : U32), Bool.pick(+List<F32>, has_texcoord, item.uv(texcoord, ts), Con{0.0, Con{0.0, ts}}), ts), material}

def corner.add(+arr: Arrays, +fc: FC, +m: MeshAcc) -> MeshAcc:
  FC{+v, +vt, +vn} = fc
  corner.add.with(arr, v, vt, vn, m)

def nth(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, rest}: Bool.pick(U32, U32.is_eq(n, 0), x, nth(rest, (n - 1 : U32)))

type Asm is Data:
  Asm{face: U32, next_shape: U32, next_end: U32, last: U32, current: MeshAcc, done: +List<MeshAcc>}

type Plan is Data:
  Plan{arrays: Arrays, offsets: +List<U32>, shapes: U32, corners: U32, materials: U32}

def asm.tri(+plan: Plan, +s: Asm, +ta: FC, +tb: FC, +tc: FC, +tm: U32) -> Asm:
  Plan{+arr, +offsets, +shape_count, +corners, +mat_count} = plan
  Asm{+fid, +next_shape, +next_end, +last, +current, +done} = s
  +crossed = (fid >= next_end : U32)
  +sidx = Bool.pick(U32, crossed, (next_shape + 1 : U32), next_shape)
  +limit = Bool.pick(U32, crossed, Bool.pick(U32, (sidx < shape_count : U32), nth(offsets, sidx), corners), next_end)
  +fresh = crossed || (Bool.not(U32.is_eq(last, 4294967295)) && Bool.not(U32.is_eq(tm, last)))
  +id = Bool.pick(U32, (tm < 2147483648 : U32) && (tm < mat_count : U32), tm, 0)
  +mesh = meshacc.material(Bool.pick(MeshAcc, fresh, meshacc.new(), current), id)
  Asm{(fid + 1 : U32), sidx, limit, tm, corner.add(arr, tc, corner.add(arr, tb, corner.add(arr, ta, mesh))), Bool.pick(+List<MeshAcc>, fresh, Con{current, done}, done)}

def asm.face(+plan: Plan, +t3: Tri, +s: Asm) -> Asm:
  Tri{+ta, +tb, +tc, +tm} = t3
  asm.tri(plan, s, ta, tb, tc, tm)

def asm.go(tris: +List<Tri>, +plan: Plan, +s: Asm) -> Asm:
  match tris:
    case Nil{}: s
    case Con{+t, rest}: asm.go(rest, plan, asm.face(plan, t, s))

def asm.meshes(+s: Asm) -> +List<MeshAcc>:
  Asm{_, _, _, _, +current, +done} = s
  List.reverse(&2, MeshAcc, Con{current, done})

def count.u32(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count.u32(rest, (n + 1 : U32))

def count.tris(xs: +List<Tri>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count.tris(rest, (n + 1 : U32))

# The meshes of the faces (each as reversed attribute lists): see above.
def assemble.meshes(+a: Attrib, +offsets: +List<U32>, +mat_count: U32) -> +List<MeshAcc>:
  Attrib{_, _, _, _, _, _, _, +faces, _} = a
  +shape_count = count.u32(offsets, 0)
  +corners = (3 * count.tris(faces, 0) : U32)
  asm.meshes(asm.go(faces, Plan{arrays.of(a), offsets, shape_count, corners, mat_count},
    Asm{0, 1, Bool.pick(U32, (shape_count > 1 : U32), nth(offsets, 1), corners), 4294967295, meshacc.new(), Nil{}}))

def attrib.ok(+a: Attrib) -> Bool:
  Attrib{+ok, _, _, _, _, _, _, _, _} = a
  ok

def attrib.texcoords(+a: Attrib) -> U32:
  Attrib{_, _, _, _, _, _, +nt, _, _} = a
  nt

# -----------------------------------------------------------------------------
# Helpers for the loaders in jonlib.bend

def until_nul.go(bs: +List<U32>, stop: Bool, +acc: +List<U32>) -> +List<U32>:
  match bs stop:
    case Con{+c, +rest} False{}: until_nul.go(rest, U32.is_eq(head(rest), 0), Con{c, acc})
    case _ _: reverse(acc)

# strlen: the text before the first NUL byte.
def until_nul(+bs: +List<U32>) -> +List<U32>:
  until_nul.go(bs, U32.is_eq(head(bs), 0), Nil{})

# Bytes 32..126: names Jonlib passes to the file system unchanged.
def printable(bs: +List<U32>) -> Bool:
  match bs:
    case Nil{}: True{}
    case Con{+c, rest}: (c >= 32 : U32) && (c <= 126 : U32) && printable(rest)

# The texture names ProcessMaterialsOBJ loads, in order: per material the
# diffuse, specular, bump and displacement maps.
def requests(ms: +List<Mtl>) -> +List<Maybe<&2, +List<U32>>>:
  match ms:
    case Nil{}: Nil{}
    case Con{Mtl{_, _, _, _, +d, +s, +b, +p}, rest}: Con{d, Con{s, Con{b, Con{p, requests(rest)}}}}

def meshes.ok(ms: +List<MeshAcc>) -> Bool:
  match ms:
    case Nil{}: True{}
    case Con{MeshAcc{+ok, _, _, _, _, _}, rest}: ok && meshes.ok(rest)

def mtl.count(ms: +List<Mtl>, +n: U32) -> U32:
  match ms:
    case Nil{}: n
    case Con{_, rest}: mtl.count(rest, (n + 1 : U32))
