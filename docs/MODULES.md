# Jon* module names and imports

Port names follow **`ray<suffix>` → `jon<suffix>`**. The implemented entry points are:

| Upstream counterpart | Bend port | Ownership |
|---|---|---|
| raylib | `jonlib.bend` | Geometry, collision, images, codecs, random streams and IO. |
| raymath | `jonmath.bend` | Scalar/vector/matrix/quaternion operations and shared mathematical types. |

The same convention names a future raygui port **Jongui**. Implemented modules
and coverage are recorded in [PROGRESS.md](PROGRESS.md). Upstream headers,
catalog IDs, source URLs and license notices identify the actual reference
implementation; the target mapping column names the Jon* counterpart.
Project-side branded configuration names follow the same rule, such as
`JONLIB_VERSION` and `JONMATH_IMPLEMENTATION` in proposed mappings.

## Importing

```bend
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
```

Math-only programs import Jonmath directly. See [examples/math.bend](../examples/math.bend).
Jonmath depends on Base and the numerical support modules; Jonlib imports Jonmath.
Both modules use the same vector/matrix values.

## Type ownership

Jonmath owns `Vector2`, `Vector3`, `Vector4`, `Matrix`, `Matrix.Decomposition`,
`Float64` and the two numerical profiles shared by both modules: `M.Libm`
(`M.AppleLibm{}`, `M.Glibc239Libm{}`, `M.Glibc241Libm{}`; which C math library
a result follows, see [ANGLES.md](ANGLES.md)) and `M.Contraction`
(`M.Uncontracted{}`, `M.Fused{}`; whether the reference build fuses `a*b + c`,
see [COLLISION.md](COLLISION.md)). Construct values with `M.Vector2{...}`,
`M.Matrix{...}`, `M.Float64{...}` and `M.Decomposed{...}`.

Jonlib owns `J.Rectangle`, `J.BoundingBox`, `J.Surface` and its core-specific
types; a bounding box's corners and geometry APIs use Jonmath vectors.
`J.Image.FloatRGB` owns float image storage while its pixels use the canonical
`M.Vector3` type; see [HDR.md](HDR.md).

## Namespace migration

Math was previously exposed through `jonlib.bend`. Update those references:

- `J.Math.*`, `J.Vector2.*`, `J.Vector3.*`, `J.Vector4.*` → `M.*`.
- `J.Matrix.*`, `J.Quaternion.*`, `J.Float64.*` → `M.*`.
- Math type/constructor references and numerical profiles use `M` as above.

Jonlib image/geometry operations keep their `J` namespace. The math declarations
have a single implementation in `jonmath.bend`; the move changes module/type
ownership and imports, not arithmetic or reference profiles.

## Private arithmetic support

These modules are not re-exported by Jonlib or Jonmath and do not change any
public API's profile. Their checked domains and proof limits are in
[BINARY64.md](BINARY64.md).

- `src/binary64_narrow.bend`: checked finite binary64-word to nearest-even
  binary32-word narrowing with gradual underflow.
- `src/binary64_fma.bend` and `src/binary64_add_sub.bend`: bounded FMA and
  add/subtract; the latter reuses the former's internal word/list primitives
  under its own 34-limb invariants.
- `src/binary64_ops.bend` and `src/binary64_gradual_multiply.bend`: checked
  normal multiply/divide with word adapters, and the gradual-output product.

`src/modern_angle.bend` is a private finite-input scalar adapter for the pinned
glibc 2.41 round-to-nearest-even `atan2f` algorithm. It consumes the helpers above,
accepts raw F32 words and returns a checked F32 result word; diagnostic traces
are also private. See [MODERN-ANGLE.md](MODERN-ANGLE.md) for source provenance
and exact operation order. The public checked angle wrappers consume it through
`src/checked_angle.bend`; see [ANGLES.md](ANGLES.md).
