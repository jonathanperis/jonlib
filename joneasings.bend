# Joneasings - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of reasings.h as raylib 6.0's examples ship it
# (examples/shapes/reasings.h; zlib/libpng, Copyright (c) 2015-2024 Ramon
# Santamaria (@raysan5), after Robert Penner's easing equations, BSD,
# Copyright (c) 2001 Robert Penner); see LICENSES/reasings.txt. Joneasings is
# to reasings.h what Jonlib is to raylib.h.
#
# Each Ease* function is Ease.<family>_<kind>(t, b, c, d): t the current time,
# b the start value, c the change and d the duration, in reasings' F32
# operation order, uncontracted. The sine, exponential and elastic easings
# call sinf, cosf and powf(2, x): their `_for` forms take a Jonmath libm
# profile and answer None where the profile does not verify the argument
# (M.Libm.sin, M.Libm.cos and M.Libm.pow2, docs/MATH.md); their plain forms
# use M.AppleLibm{}, as Jonlib's profile-free forms do. See docs/EASINGS.md.
import Base
import ./jonmath.bend as M

# -----------------------------------------------------------------------------
# Helpers

# c*value + b for an optional value.
def Ease.scaled(+b: F32, +c: F32, value: Maybe<F32>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+v}: Some{(c * v + b : F32)}

def Ease.sine_in.at(+b: F32, +c: F32, cosine: Maybe<F32>) -> Maybe<F32>:
  match cosine:
    case None{}: None{}
    case Some{+v}: Some{(F32.neg(c) * v + c + b : F32)}

def Ease.sine_in_out.at(+b: F32, +c: F32, cosine: Maybe<F32>) -> Maybe<F32>:
  match cosine:
    case None{}: None{}
    case Some{+v}: Some{(F32.neg(c) / 2.0 * (v - 1.0) + b : F32)}

def Ease.expo_out.at(+b: F32, +c: F32, power: Maybe<F32>) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{(c * (F32.neg(p) + 1.0) + b : F32)}

def Ease.expo_in_out.late(+b: F32, +c: F32, power: Maybe<F32>) -> Maybe<F32>:
  match power:
    case None{}: None{}
    case Some{+p}: Some{(c / 2.0 * (F32.neg(p) + 2.0) + b : F32)}

def Ease.expo_in_out.half(early: Bool, +libm: M.Libm, +u: F32, +b: F32, +c: F32) -> Maybe<F32>:
  match early:
    case True{}: Ease.scaled(b, (c / 2.0 : F32), M.Libm.pow2(libm, (10.0 * (u - 1.0) : F32)))
    case False{}: Ease.expo_in_out.late(b, c, M.Libm.pow2(libm, (F32.neg(10.0) * (u - 1.0) : F32)))

def Ease.expo_in_out.at(edge: U32, +libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  match edge:
    case 0: Some{b}
    case 1: Some{(b + c : F32)}
    case _: Ease.expo_in_out.half(((t / (d / 2.0)) < 1.0 : F32), libm, (t / (d / 2.0) : F32), b, c)

# EaseBounceOut's later arcs: postFix = t -= offset; c*(7.5625f*postFix*t + rise) + b.
def Ease.bounce.arc(+t: F32, +b: F32, +c: F32, +offset: F32, +rise: F32) -> F32:
  (c * (7.5625 * (t - offset) * (t - offset) + rise) + b : F32)

# postFix*sinf(...) for the elastic easings, postFix being a*powf(2, exponent);
# kind 0: -(wave) + b (in), 1: wave + c + b (out), 2: -0.5f*wave + b (in out,
# first half), 3: wave*0.5f + c + b (second half).
def Ease.elastic.value(kind: U32, +b: F32, +c: F32, +wave: F32) -> F32:
  match kind:
    case 0: (F32.neg(wave) + b : F32)
    case 1: (wave + c + b : F32)
    case 2: (F32.neg(0.5) * wave + b : F32)
    case _: (wave * 0.5 + c + b : F32)

def Ease.elastic.at(+kind: U32, +b: F32, +c: F32, power: Maybe<F32>, sine: Maybe<F32>) -> Maybe<F32>:
  match power sine:
    case Some{+p} Some{+s}: Some{Ease.elastic.value(kind, b, c, (c * p * s : F32))}
    case _ _: None{}

# The wave sinf((t*d - s)*(2.0f*PI)/p) with s = p/4 under the power's exponent.
def Ease.elastic(+kind: U32, +libm: M.Libm, +exponent: F32, +t: F32, +b: F32, +c: F32, +d: F32, +p: F32) -> Maybe<F32>:
  Ease.elastic.at(kind, b, c, M.Libm.pow2(libm, exponent), M.Libm.sin(libm, ((t * d - p / 4.0) * (2.0 * M.Math.PI()) / p : F32)))

# -----------------------------------------------------------------------------
# Linear (EaseLinearNone, EaseLinearIn, EaseLinearOut, EaseLinearInOut): c*t/d + b.

def Ease.linear_none(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * t / d + b : F32)

def Ease.linear_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * t / d + b : F32)

def Ease.linear_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * t / d + b : F32)

def Ease.linear_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * t / d + b : F32)

# -----------------------------------------------------------------------------
# Sine

# EaseSineIn: -c*cosf(t/d*(PI/2.0f)) + c + b.
def Ease.sine_in_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.sine_in.at(b, c, M.Libm.cos(libm, (t / d * (M.Math.PI() / 2.0) : F32)))

def Ease.sine_in(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.sine_in_for(M.AppleLibm{}, t, b, c, d)

# EaseSineOut: c*sinf(t/d*(PI/2.0f)) + b.
def Ease.sine_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.scaled(b, c, M.Libm.sin(libm, (t / d * (M.Math.PI() / 2.0) : F32)))

def Ease.sine_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.sine_out_for(M.AppleLibm{}, t, b, c, d)

# EaseSineInOut: -c/2.0f*(cosf(PI*t/d) - 1.0f) + b.
def Ease.sine_in_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.sine_in_out.at(b, c, M.Libm.cos(libm, (M.Math.PI() * t / d : F32)))

def Ease.sine_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.sine_in_out_for(M.AppleLibm{}, t, b, c, d)

# -----------------------------------------------------------------------------
# Circular

# EaseCircIn: t /= d; -c*(sqrtf(1.0f - t*t) - 1.0f) + b.
def Ease.circ_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (F32.neg(c) * (F32.sqrt((1.0 - (t / d) * (t / d) : F32)) - 1.0) + b : F32)

# EaseCircOut: t = t/d - 1.0f; c*sqrtf(1.0f - t*t) + b.
def Ease.circ_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * F32.sqrt((1.0 - (t / d - 1.0) * (t / d - 1.0) : F32)) + b : F32)

def Ease.circ_in_out.at(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), (F32.neg(c) / 2.0 * (F32.sqrt((1.0 - u * u : F32)) - 1.0) + b : F32), (c / 2.0 * (F32.sqrt((1.0 - (u - 2.0) * (u - 2.0) : F32)) + 1.0) + b : F32))

# EaseCircInOut: by t/(d/2.0f) below 1 or not.
def Ease.circ_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Ease.circ_in_out.at((t / (d / 2.0) : F32), b, c)

# -----------------------------------------------------------------------------
# Cubic

# EaseCubicIn: t /= d; c*t*t*t + b.
def Ease.cubic_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * (t / d) * (t / d) * (t / d) + b : F32)

# EaseCubicOut: t = t/d - 1.0f; c*(t*t*t + 1.0f) + b.
def Ease.cubic_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * ((t / d - 1.0) * (t / d - 1.0) * (t / d - 1.0) + 1.0) + b : F32)

def Ease.cubic_in_out.at(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), (c / 2.0 * u * u * u + b : F32), (c / 2.0 * ((u - 2.0) * (u - 2.0) * (u - 2.0) + 2.0) + b : F32))

# EaseCubicInOut: by t/(d/2.0f) below 1 or not.
def Ease.cubic_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Ease.cubic_in_out.at((t / (d / 2.0) : F32), b, c)

# -----------------------------------------------------------------------------
# Quadratic

# EaseQuadIn: t /= d; c*t*t + b.
def Ease.quad_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * (t / d) * (t / d) + b : F32)

# EaseQuadOut: t /= d; -c*t*(t - 2.0f) + b.
def Ease.quad_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (F32.neg(c) * (t / d) * ((t / d) - 2.0) + b : F32)

def Ease.quad_in_out.at(+u: F32, +b: F32, +c: F32) -> F32:
  Bool.pick(F32, (u < 1.0 : F32), ((c / 2.0) * (u * u) + b : F32), (F32.neg(c) / 2.0 * (((u - 1.0) * (u - 3.0)) - 1.0) + b : F32))

# EaseQuadInOut: by t/(d/2) below 1 or not.
def Ease.quad_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Ease.quad_in_out.at((t / (d / 2.0) : F32), b, c)

# -----------------------------------------------------------------------------
# Exponential

# EaseExpoIn: b at t == 0, else c*powf(2.0f, 10.0f*(t/d - 1.0f)) + b.
def Ease.expo_in_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Ease.scaled(b, c, M.Libm.pow2(libm, (10.0 * (t / d - 1.0) : F32))))

def Ease.expo_in(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.expo_in_for(M.AppleLibm{}, t, b, c, d)

# EaseExpoOut: b + c at t == d, else c*(-powf(2.0f, -10.0f*t/d) + 1.0f) + b.
def Ease.expo_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, d), Some{(b + c : F32)}, Ease.expo_out.at(b, c, M.Libm.pow2(libm, (F32.neg(10.0) * t / d : F32))))

def Ease.expo_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.expo_out_for(M.AppleLibm{}, t, b, c, d)

# EaseExpoInOut: b at t == 0, b + c at t == d, else by t/(d/2.0f) below 1 or not.
def Ease.expo_in_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.expo_in_out.at(Bool.pick(U32, F32.is_eq(t, 0.0), 0, Bool.pick(U32, F32.is_eq(t, d), 1, 2)), libm, t, b, c, d)

def Ease.expo_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.expo_in_out_for(M.AppleLibm{}, t, b, c, d)

# -----------------------------------------------------------------------------
# Back (s = 1.70158f)

# EaseBackIn: postFix = t /= d; c*postFix*t*((s + 1.0f)*t - s) + b.
def Ease.back_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d : F32)
  (c * u * u * ((1.70158 + 1.0) * u - 1.70158) + b : F32)

# EaseBackOut: t = t/d - 1.0f; c*(t*t*((s + 1.0f)*t + s) + 1.0f) + b.
def Ease.back_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d - 1.0 : F32)
  (c * (u * u * ((1.70158 + 1.0) * u + 1.70158) + 1.0) + b : F32)

def Ease.back_in_out.at(+u: F32, +b: F32, +c: F32) -> F32:
  +s = (1.70158 * 1.525 : F32)
  Bool.pick(F32, (u < 1.0 : F32), (c / 2.0 * (u * u * ((s + 1.0) * u - s)) + b : F32), (c / 2.0 * ((u - 2.0) * (u - 2.0) * ((s + 1.0) * (u - 2.0) + s) + 2.0) + b : F32))

# EaseBackInOut: s *= 1.525f on either side of t/(d/2.0f) = 1.
def Ease.back_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Ease.back_in_out.at((t / (d / 2.0) : F32), b, c)

# -----------------------------------------------------------------------------
# Bounce

# EaseBounceOut. The third bound is the double 2.5/2.75; a float is below it
# exactly when it is below the float 2.5f/2.75f (the nearest float, which is
# above the double).
def Ease.bounce_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d : F32)
  Bool.pick(F32, (u < (1.0 / 2.75) : F32), (c * (7.5625 * u * u) + b : F32),
    Bool.pick(F32, (u < (2.0 / 2.75) : F32), Ease.bounce.arc(u, b, c, (1.5 / 2.75 : F32), 0.75),
      Bool.pick(F32, (u < (2.5 / 2.75) : F32), Ease.bounce.arc(u, b, c, (2.25 / 2.75 : F32), 0.9375), Ease.bounce.arc(u, b, c, (2.625 / 2.75 : F32), 0.984375))))

# EaseBounceIn: c - EaseBounceOut(d - t, 0.0f, c, d) + b.
def Ease.bounce_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c - Ease.bounce_out((d - t : F32), 0.0, c, d) + b : F32)

# EaseBounceInOut: the first half through EaseBounceIn(t*2.0f), the second
# through EaseBounceOut(t*2.0f - d).
def Ease.bounce_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  Bool.pick(F32, (t < (d / 2.0) : F32), (Ease.bounce_in((t * 2.0 : F32), 0.0, c, d) * 0.5 + b : F32), (Ease.bounce_out((t * 2.0 - d : F32), 0.0, c, d) * 0.5 + c * 0.5 + b : F32))

# -----------------------------------------------------------------------------
# Elastic

# EaseElasticIn: b at t == 0, b + c where t/d == 1; p = d*0.3f.
def Ease.elastic_in_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)},
    Ease.elastic(0, libm, (10.0 * (t / d - 1.0) : F32), (t / d - 1.0 : F32), b, c, d, (d * 0.3 : F32))))

def Ease.elastic_in(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.elastic_in_for(M.AppleLibm{}, t, b, c, d)

# EaseElasticOut: b at t == 0, b + c where t/d == 1; p = d*0.3f.
def Ease.elastic_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq((t / d : F32), 1.0), Some{(b + c : F32)},
    Ease.elastic(1, libm, (F32.neg(10.0) * (t / d) : F32), (t / d : F32), b, c, d, (d * 0.3 : F32))))

def Ease.elastic_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.elastic_out_for(M.AppleLibm{}, t, b, c, d)

# EaseElasticInOut: b at t == 0, b + c where t/(d/2.0f) == 2; p = d*(0.3f*1.5f);
# by t/(d/2.0f) below 1 or not.
def Ease.elastic_in_out_for(+libm: M.Libm, +t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  +u = (t / (d / 2.0) : F32)
  +p = (d * (0.3 * 1.5) : F32)
  Bool.pick(Maybe<F32>, F32.is_eq(t, 0.0), Some{b}, Bool.pick(Maybe<F32>, F32.is_eq(u, 2.0), Some{(b + c : F32)},
    Bool.pick(Maybe<F32>, (u < 1.0 : F32), Ease.elastic(2, libm, (10.0 * (u - 1.0) : F32), (u - 1.0 : F32), b, c, d, p), Ease.elastic(3, libm, (F32.neg(10.0) * (u - 1.0) : F32), (u - 1.0 : F32), b, c, d, p))))

def Ease.elastic_in_out(+t: F32, +b: F32, +c: F32, +d: F32) -> Maybe<F32>:
  Ease.elastic_in_out_for(M.AppleLibm{}, t, b, c, d)
