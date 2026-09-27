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
`Float64` and the shared `Gradient.Reference` numerical profile. Construct values
with `M.Vector2{...}`, `M.Matrix{...}`, `M.Float64{...}` and `M.Decomposed{...}`.
Profile constructors are `M.AccurateGradient{}` and `M.GnuGradient{}`. Jonlib owns
`J.Rectangle`, `J.BoundingBox`, `J.Surface` and its core-specific types; a bounding
box's corners and geometry APIs use Jonmath vectors.

## Import migration

Earlier builds exposed math through `jonlib.bend`. Update those references:

- `J.Math.*`, `J.Vector2.*`, `J.Vector3.*`, `J.Vector4.*` → `M.*`.
- `J.Matrix.*`, `J.Quaternion.*`, `J.Float64.*` → `M.*`.
- Math type/constructor references and numerical profiles use `M` as above.

Jonlib image/geometry operations keep their `J` namespace. The math declarations
have a single implementation in `jonmath.bend`; the migration changes module/type
ownership and imports, not their arithmetic or reference profiles. Existing native
expected results and proof propositions remain the verification gates.
