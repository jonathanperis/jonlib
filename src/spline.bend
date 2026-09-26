# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rshapes.c spline formulas; LICENSES/raylib.txt.
import Base
import ./fused.bend as F

type Weights is Data:
  Weights{a: F32, b: F32, c: F32, d: F32}

def mad(fused: Bool, a: F32, b: F32, c: F32) -> F32:
  match fused:
    case False{}: (a * b + c : F32)
    case True{}: F.multiply_add(a, b, c)

def linear(fused: Bool, a: F32, b: F32, +t: F32) -> F32:
  mad(fused, a, (1.0 - t : F32), (b * t : F32))

def basis(+fused: Bool, +a: F32, +b: F32, +c: F32, d: F32, +t: F32) -> F32:
  q0 = ((mad(fused, F32.neg(3.0), c, mad(fused, 3.0, b, F32.neg(a))) + d) / 6.0 : F32)
  q1 = (mad(fused, 3.0, c, mad(fused, 3.0, a, (F32.neg(6.0) * b : F32))) / 6.0 : F32)
  q2 = (mad(fused, F32.neg(3.0), a, (3.0 * c : F32)) / 6.0 : F32)
  q3 = ((mad(fused, 4.0, b, a) + c) / 6.0 : F32)
  mad(fused, t, mad(fused, t, mad(fused, t, q0, q1), q2), q3)

def catmull_weights(+fused: Bool, +t: F32) -> Weights:
  q0 = (mad(fused, (F32.neg(t) * t : F32), t, (2.0 * t * t : F32)) - t : F32)
  q1 = (mad(fused, (3.0 * t * t : F32), t, (F32.neg(5.0) * t * t : F32)) + 2.0 : F32)
  q2 = (mad(fused, (F32.neg(3.0) * t * t : F32), t, (4.0 * t * t : F32)) + t : F32)
  q3 = mad(fused, (t * t : F32), t, F32.neg((t * t : F32)))
  Weights{q0, q1, q2, q3}

def catmull(+fused: Bool, weights: Weights, a: F32, b: F32, c: F32, d: F32) -> F32:
  Weights{q0, q1, q2, q3} = weights
  (0.5 * mad(fused, d, q3, mad(fused, c, q2, mad(fused, a, q0, (b * q1 : F32)))) : F32)

def bezier_quad(+fused: Bool, a: F32, b: F32, c: F32, +t: F32) -> F32:
  +one = (1.0 - t : F32)
  qa = (one * one : F32)
  qb = (2.0 * one * t : F32)
  qc = (t * t : F32)
  mad(fused, qc, c, mad(fused, qa, a, (qb * b : F32)))
