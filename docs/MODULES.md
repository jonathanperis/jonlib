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

Jonlib owns `J.Rectangle`, `J.BoundingBox`, `J.Surface` (the one image type,
for every pixel format; R32G32B32 samples use the canonical `M.Vector3`) and its
core-specific types; a bounding box's corners and geometry APIs use Jonmath vectors.

## Namespace migration

Math was previously exposed through `jonlib.bend`. Update those references:

- `J.Math.*`, `J.Vector2.*`, `J.Vector3.*`, `J.Vector4.*` → `M.*`.
- `J.Matrix.*`, `J.Quaternion.*`, `J.Float64.*` → `M.*`.
- Math type/constructor references and numerical profiles use `M` as above.

Jonlib image/geometry operations keep their `J` namespace. The math declarations
have a single implementation in `jonmath.bend`; the move changes module/type
ownership and imports, not arithmetic or reference profiles.

## Image API migration

Jonlib previously had four image owners. They are now one format-tagged
`J.Surface{width, height, format, pixels}` (see [API.md](API.md)):

- `J.Surface{w, h, pixels}` (RGBA8) → `J.Surface{w, h, 7, J.Words{pixels}}`.
  Format-7 words stay canonical `0xRRGGBBAA` Colors.
- `J.Image.Formatted` / `FormattedImage{w, h, f, p}` → `J.Surface{w, h, f, J.Words{p}}`.
  Format-7 words are now canonical rather than byte-swapped.
- `J.Image.FloatRGB` / `FloatRGB{w, h, p}` → `J.Surface{w, h, 9, J.Vectors{p}}`.
- `J.Surface` (dither output) → a Surface in format 3, 5 or 6.
- Conversions (`Formatted.convert`, `to_formatted`, `to_surface`, `to_float_rgb`,
  `FloatRGB.to_formatted`) → `J.Surface.format(surface, target)`.
  `from_bytes`/`to_bytes`/`export` → `J.Surface.from_bytes(w, h, format, bytes)` /
  `J.Surface.export(surface)`; `FloatRGB.entries` → the export bytes.
- Per-type operations (`Surface.flip`, `.color_tint`, `.resize`,
  `Surface.colors`, `.get`, `.from_channel`, ...) → the `J.Surface`
  operation of the same name, which now covers every format.
- Decoders and loaders (`Surface.decode_*`, `load_image`, `Surface.decode_*`,
  `Surface.load_*`, `Surface.decode_hdr/load_hdr/load_raw`) →
  `J.Surface.decode_*`, `load_*`, `load_raw`, returning the file's native format
  (previously `Surface.decode_*` returned RGBA8: add `J.Surface.format(s, 7)` or
  read `J.Surface.colors`).
- Exports: `Surface.export_to_memory` / `Surface.export_to_memory` (memory) →
  `J.Surface.export_to_memory(surface, ".png")`; file bytes and writers →
  `J.Surface.to_png/to_bmp/to_tga/to_qoi`, `write_*`, `to_code`, `write_code`.

Result shapes are uniform: every consuming operation that can fail returns
`Result<&1, &1, J.Surface & J.Surface.Error, R>`, so color operations, `colors`,
`alpha_clear`, `alpha_premultiply`, `draw_image`, `mipmaps`, `to_ppm` and
`to_image` (previously total on RGBA8) now return `Result`.
`J.Surface.Error` and `J.Surface.Error` merge into `J.Surface.Error`
(`UnsupportedFormat` → `UnsupportedFormat`). `J.Surface.IOError`,
`RawLoadError`, `ExportError`, `Surface.IOError`,
`Surface.IOError` and both `CodeWriteError` types merge into
`J.Surface.IOError` (`FileError{code, message}`, `DataError{error}`,
`SourceError{surface, error}`); writers that returned `U32 & String` errors use
it too.

Contract changes made with the merge: contrast/brightness amounts outside their
C parameter domain are `InvalidRequest` in every format, and R32G32B32 brightness
truncates fractional amounts like the other formats; `dither` accepts only the
bit counts that name a 16-bit format. `resize` on GRAYSCALE, GRAY_ALPHA and
R8G8B8 was `UnsupportedFormat` at the merge; it now runs their 1..3-channel
filters.

Phase 1 parity changes: `draw_image*`, `alpha_mask`, `alpha_clear`,
`rotate_degrees` and `mipmaps` accept formats 1..9 instead of returning
`UnsupportedFormat`. `alpha_mask` on a GRAYSCALE destination returns GRAY_ALPHA,
and on other non-RGBA8 formats R8G8B8A8, as raylib does. `alpha_clear` rejects
thresholds outside finite 0..1, and R5G5B5A1/R4G4B4A4 colors whose native byte
casts are undefined, with `InvalidRequest` (previously unchecked).
`Surface.mipmaps` returns `Image.Mipmaps` directly, since it cannot fail.

Pixel formats 10..13 are supported everywhere formats 1..9 are. Float samples
are stored as bits: the `Vectors{Array<M.Vector3>}` storage of R32G32B32 became
`Quads{Array<Surface.Quad>}` (`J.Quad{a, b, c, d}` sample words, `d` zero for
format 9); build `J.Quad{F32.bits(r), F32.bits(g), F32.bits(b), 0}` where code
built `M.Vector3{r, g, b}`.

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
- `src/binary64_sqrt.bend`: checked square root of a signed zero or positive
  normal, rounded once (exact restoring integer square root).

`src/modern_angle.bend` is a private finite-input scalar adapter for the pinned
glibc 2.41 round-to-nearest-even `atan2f` algorithm. It consumes the helpers above,
accepts raw F32 words and returns a checked F32 result word; diagnostic traces
are also private. See [MODERN-ANGLE.md](MODERN-ANGLE.md) for source provenance
and exact operation order. The public checked angle wrappers consume it through
`src/checked_angle.bend`; see [ANGLES.md](ANGLES.md).
`src/asin.bend` is the private adaptation of glibc 2.41's correctly rounded
`asinf` on those helpers, consumed by `M.Libm.asin`; see
[INVERSE-TRIG.md](INVERSE-TRIG.md).
