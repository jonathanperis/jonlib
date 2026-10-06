# Jon* module names and imports

Port names follow **`ray<suffix>` → `jon<suffix>`**. The implemented entry points are:

| Upstream counterpart | Bend port | Ownership |
|---|---|---|
| raylib | `jonlib.bend` | Geometry, collision, images, codecs, random streams and IO. |
| raymath | `jonmath.bend` | Scalar/vector/matrix/quaternion operations and shared mathematical types. |

The same convention names a future raygui port **Jongui**. This repository's
implemented modules and coverage are recorded in [PROGRESS.md](PROGRESS.md).
Upstream headers, catalog IDs, source URLs and license notices identify the actual
reference implementation; the target mapping column names the Jon* counterpart.
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

Jonmath owns `Vector2`, `Vector3`, `Vector4`, `Matrix`, `Matrix.Decomposition`,
`Float64`, the shared `Gradient.Reference` numerical profile, and the separate
`Angle.Reference` checked-angle profile. Construct values
with `M.Vector2{...}`, `M.Matrix{...}`, `M.Float64{...}` and `M.Decomposed{...}`.
Profile constructors are `M.AccurateGradient{}` and `M.GnuGradient{}`. Jonlib owns
`J.Rectangle`, `J.BoundingBox`, `J.Surface` and its core-specific types; a bounding
box's corners and geometry APIs use Jonmath vectors.
`J.Image.Decode.Reference` and its `J.FusedDecode{}` / `J.UncontractedDecode{}`
constructors belong to Jonlib's codec interface; see [PSD.md](PSD.md).
`J.Image.FloatRGB` owns float image storage while its pixels use the canonical
`M.Vector3` type; see [HDR.md](HDR.md).

## Import migration

Earlier builds exposed math through `jonlib.bend`. Update those references:

- `J.Math.*`, `J.Vector2.*`, `J.Vector3.*`, `J.Vector4.*` → `M.*`.
- `J.Matrix.*`, `J.Quaternion.*`, `J.Float64.*` → `M.*`.
- Math type/constructor references and numerical profiles use `M` as above.

Jonlib image/geometry operations keep their `J` namespace. The math declarations
have a single implementation in `jonmath.bend`; the migration changes module/type
ownership and imports, not their arithmetic or reference profiles. Existing native
expected results and proof propositions remain the verification gates.

## Private arithmetic support

`src/binary64_narrow.bend` provides the isolated checked finite64-word to
nearest-even binary32-word prerequisite described in [BINARY64-NARROW.md](BINARY64-NARROW.md).
It is not re-exported by Jonmath/Jonlib; the modern scalar adapter consumes it.
Existing Float64/projection/resize conversion contracts are unchanged.

`src/binary64_fma.bend` and `src/binary64_add_sub.bend` are separate private
bounded arithmetic prerequisites. The latter reuses the former's internal
word/list primitives under its own 34-limb invariants; neither is exported by
Jonlib/Jonmath. The modern scalar adapter consumes them, while old image/math
consumers are unchanged. See [BINARY64-FMA.md](BINARY64-FMA.md)
and [BINARY64-ADD-SUB.md](BINARY64-ADD-SUB.md) for the checked domains and proof limits.


`src/modern_angle.bend` is a separate private finite-input scalar adapter for the
pinned glibc 2.41 RN-even algorithm. It consumes the checked arithmetic helpers
without re-exporting them or changing any existing API's profile. Its entry point
accepts raw F32 words and returns a checked F32 result word; diagnostic traces are
also private. See [MODERN-ANGLE.md](MODERN-ANGLE.md) for verification status,
source provenance and exact operation order. The new checked public angle
wrappers consume it through `src/checked_angle.bend`; see
[CHECKED-ANGLES.md](ANGLES.md). Device work remains separate.
