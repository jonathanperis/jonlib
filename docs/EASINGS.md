# Joneasings: reasings.h

`joneasings.bend` adapts `reasings.h`, the easing header raylib 6.2's examples
ship (`examples/shapes/reasings.h`, Robert Penner's equations; notice in
[LICENSES/reasings.txt](../LICENSES/reasings.txt)). It imports Jonmath only:

```bend
import ./jonmath.bend as M
import ./joneasings.bend as E
```

Every `Ease<Family><Kind>(t, b, c, d)` is `E.Ease.<family>_<kind>(t, b, c, d)`:
`t` the current time, `b` the start value, `c` the change and `d` the
duration, F32 throughout, in reasings' operation order and uncontracted (as
raylib's examples build it on Linux).

| reasings.h | Joneasings | Result |
|---|---|---|
| `EaseLinearNone`, `EaseLinearIn`, `EaseLinearOut`, `EaseLinearInOut` | `Ease.linear_none`, `linear_in`, `linear_out`, `linear_in_out` | F32: `c*t/d + b` |
| `EaseSineIn`, `EaseSineOut`, `EaseSineInOut` | `Ease.sine_in_for(libm, ...)`, `sine_out_for`, `sine_in_out_for` (and the plain forms) | `Maybe<F32>` |
| `EaseCircIn`, `EaseCircOut`, `EaseCircInOut` | `Ease.circ_in`, `circ_out`, `circ_in_out` | F32 |
| `EaseCubicIn`, `EaseCubicOut`, `EaseCubicInOut` | `Ease.cubic_in`, `cubic_out`, `cubic_in_out` | F32 |
| `EaseQuadIn`, `EaseQuadOut`, `EaseQuadInOut` | `Ease.quad_in`, `quad_out`, `quad_in_out` | F32 |
| `EaseExpoIn`, `EaseExpoOut`, `EaseExpoInOut` | `Ease.expo_in_for(libm, ...)`, `expo_out_for`, `expo_in_out_for` (and the plain forms) | `Maybe<F32>` |
| `EaseBackIn`, `EaseBackOut`, `EaseBackInOut` | `Ease.back_in`, `back_out`, `back_in_out` | F32 |
| `EaseBounceOut`, `EaseBounceIn`, `EaseBounceInOut` | `Ease.bounce_out`, `bounce_in`, `bounce_in_out` | F32 |
| `EaseElasticIn`, `EaseElasticOut`, `EaseElasticInOut` | `Ease.elastic_in_for(libm, ...)`, `elastic_out_for`, `elastic_in_out_for` (and the plain forms) | `Maybe<F32>` |

- **Libm.** The sine, exponential and elastic easings call `sinf`, `cosf` and
  `powf(2, x)`. Their `_for` forms take a Jonmath profile (`M.Glibc239Libm{}`,
  `M.Glibc241Libm{}`, `M.AppleLibm{}`) and answer None where it does not
  verify the argument: the glibc profiles take every finite normal or zero
  `sinf`/`cosf` argument and `powf(2, y)` for finite `|y| < 126`; AppleLibm
  takes the integral degrees of [FRAME.md](FRAME.md) for `sinf`/`cosf` and no
  `powf` ([MATH.md](MATH.md), [SINCOSF.md](SINCOSF.md)). The early returns
  (`t == 0`, `t == d`) need no libm. The plain forms are the `_for` forms
  under `M.AppleLibm{}`, as Jonlib's profile-free forms are.
- **EaseBounceOut's third bound** is the double `2.5/2.75`: a float is below
  it exactly when it is below the float `2.5f/2.75f`, which is the next float
  above it, so Joneasings compares in F32.
- **NaN.** Times outside `[0, d]` make the circular easings take `sqrtf` of a
  negative and a zero duration divides by zero: the NaN's sign and payload
  are the platform's.
- **Inline definitions.** `REASINGS_STATIC_INLINE` and `EASEDEF` select C
  linkage; every Bend definition is visible to importers.

The ported examples `shapes_easings_ball`, `shapes_easings_box`,
`shapes_easings_rectangles` and `shapes_easings_testbed` import Joneasings.

Coverage is tracked in `api/joneasings.json`: the 28 functions and the
header's four macros (`REASINGS_H`, `REASINGS_STATIC_INLINE` and `EASEDEF` are
C glue; `PI` is Jonmath's `M.Math.PI()`, the same float).

`tools/easings_probe.py` (gate `easings`) compiles reasings.h with
`-ffp-contract=off` against the host libm and compares all 28 functions on a
corpus of times at, inside and outside `[0, d]` (the edges, and the floats on
either side of EaseBounceOut's bounds) with durations from 0.001 to 1000,
under the host's profile: refused arguments must answer None, NaN results
must be NaN, every other value bit for bit.
