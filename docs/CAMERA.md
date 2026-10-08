# Cameras

Jonlib's camera queries are adapted from pinned raylib 6.0 `rcamera.h` and the
camera/screen-space part of `rcore.c` (altered Bend adaptations; zlib,
[LICENSES/raylib.txt](../LICENSES/raylib.txt)). They operate on
`J.Camera3D{position, target, up, fovy, projection}` (raylib's `Camera`) and
`J.Camera2D{offset, target, rotation, zoom}`. A C function that updates
`*camera` returns the updated camera instead; nothing is mutated.

## API

Every query has a `_for` variant taking the arithmetic profile
(`M.Uncontracted{}` or `M.Fused{}`, below) and, where `sinf`, `cosf` or
`atan2f` is involved, the `M.Libm` profile. The convenience forms use
`M.Uncontracted{}` and `M.AppleLibm{}`, like the collision queries.

| raylib | Jonlib | Result |
|---|---|---|
| `GetCameraForward` | `Camera.forward_for(arithmetic, camera)` | `M.Vector3`: normalized `target - position` |
| `GetCameraUp` | `Camera.up_for(arithmetic, camera)` | `M.Vector3`: normalized `up` (not made perpendicular) |
| `GetCameraRight` | `Camera.right_for(arithmetic, camera)` | `M.Vector3`: normalized `cross(forward, up)` |
| `CameraMoveForward` | `Camera.move_forward_for(arithmetic, camera, distance, in_world_plane)` | `Camera3D` |
| `CameraMoveUp` | `Camera.move_up_for(arithmetic, camera, distance)` | `Camera3D` |
| `CameraMoveRight` | `Camera.move_right_for(arithmetic, camera, distance, in_world_plane)` | `Camera3D` |
| `CameraMoveToTarget` | `Camera.move_to_target_for(arithmetic, camera, delta)` | `Camera3D` |
| `CameraYaw` | `Camera.yaw_for(arithmetic, libm, camera, angle, around_target)` | `Maybe<Camera3D>` |
| `CameraPitch` | `Camera.pitch_for(arithmetic, libm, camera, angle, lock_view, around_target, rotate_up)` | `Maybe<Camera3D>` |
| `CameraRoll` | `Camera.roll_for(arithmetic, libm, camera, angle)` | `Maybe<Camera3D>` |
| `GetCameraViewMatrix` | `Camera.view_matrix_for(arithmetic, camera)` | `M.Matrix` (`MatrixLookAt`) |
| `GetCameraProjectionMatrix` | `Camera.projection_matrix(camera, aspect)` | `Maybe<M.Matrix>` |
| `GetCameraMatrix` | `Camera.matrix_for(arithmetic, camera)` | `M.Matrix` (`MatrixLookAt`) |
| `GetCameraMatrix2D` | `Camera.matrix_2d_for(arithmetic, libm, camera2d)` | `Maybe<M.Matrix>` |
| `GetWorldToScreen2D` | `Camera.world_to_screen_2d_for(arithmetic, libm, position, camera2d)` | `Maybe<M.Vector2>` |
| `GetScreenToWorld2D` | `Camera.screen_to_world_2d_for(arithmetic, libm, position, camera2d)` | `Maybe<M.Vector2>` |
| `GetWorldToScreenEx` | `Camera.world_to_screen_ex_for(arithmetic, position, camera, width, height)` | `Maybe<M.Vector2>` |
| `GetScreenToWorldRayEx` | `Camera.screen_to_world_ray_ex_for(arithmetic, position, camera, width, height)` | `Maybe<J.Ray>` |
| `UpdateCameraPro` | `Camera.update_pro_for(arithmetic, libm, camera, movement, rotation, zoom)` | `Maybe<Camera3D>` |

The convenience names drop `_for` and the profile arguments
(`Camera.forward(camera)`, `Camera.pitch(camera, angle, lock_view,
around_target, rotate_up)`, `Camera.world_to_screen_ex(position, camera,
width, height)`, ...); `Camera.projection_matrix` has no profile argument.
Angles are radians, except `UpdateCameraPro`'s degrees and `Camera2D.rotation`.
Screen sizes are `U32` values standing for C `int`s.

The algorithms keep the reference order and edge behavior:

- Normalization leaves a zero vector unchanged; `MatrixLookAt` divides a zero
  length by one, which is the same. Degenerate cameras (target equal to the
  position, up parallel to the view or zero) therefore keep raylib's zero or
  NaN components rather than an invented basis.
- `in_world_plane` zeroes the z component when `|up.z| > 0.7071f`, else x when
  `|up.x| > 0.7071f`, else y (also for a NaN up vector), then renormalizes.
- `CameraMoveToTarget` replaces a non-positive new distance with `0.001f`; a NaN
  distance is kept.
- Rotations use `Vector3RotateByAxisAngle` (Euler-Rodrigues with two cross
  products and a renormalized axis whose zero length divides by one).
  `CameraYaw` and `CameraPitch` rotate the view vector and move the position
  (around the target) or the target (around the position); `rotate_up` and
  `CameraRoll` rotate the camera's own up vector.
- `lock_view` clamps the pitch to `Vector3Angle(up, view) - 0.001f` and then to
  `-Vector3Angle(-up, view) + 0.001f`, in that order, with the normalized up.
- `UpdateCameraPro` pitches by `-rotation.y` degrees with `lock_view`, yaws by
  `-rotation.x`, rolls by `rotation.z`, all around the position, then moves
  forward and right in the world plane, up, and toward the target. It reads no
  input state, unlike `UpdateCamera`.
- 2D cameras compose `translate(-target)`, `scale(zoom, zoom, 1)` times
  `MatrixRotate((0, 0, 1), rotation*DEG2RAD)`, and `translate(offset)` with
  raylib's multiplication order; `GetScreenToWorld2D` inverts that matrix with
  `MatrixInvert`, singular matrices included.
- `GetWorldToScreenEx` transforms `(x, y, z, 1)` by the view and projection
  matrices, divides by w and maps to `((x/w + 1)/2*width, (-y/w + 1)/2*height)`.
  `GetScreenToWorldRayEx` unprojects the normalized device position at depths
  0 and 1 for the (normalized) direction; an orthographic ray starts at the
  unprojected point at depth -1, and projections other than 0 and 1 (identity
  projection) keep raylib's zero origin.
- Orthographic projections are `MatrixOrtho(-right, right, -top, top, near,
  far)` with `top = fovy/2.0`. For `GetCameraProjectionMatrix` (a `float`
  aspect) `right = top*aspect` is exact in binary64, so the F32 span is
  `fovy*aspect` rounded once. The screen-space queries use
  `aspect = (double)width/(double)height`; that quotient and `top*aspect` are
  rounded in binary64 by Jonlib's checked binary64 helpers
  ([BINARY64.md](BINARY64.md)) before the F32 casts. The cull distances are
  rlgl's defaults, `0.05` and `4000.0` (raylib's `rlSetClipPlanes` state is not
  modelled).
- Projection values other than `CAMERA_PERSPECTIVE` (0) and
  `CAMERA_ORTHOGRAPHIC` (1) give the identity projection, as in raylib.

## Arithmetic and libm profiles

The raymath helpers are inlined into `rcore.c`, so their arithmetic follows the
reference build's contraction. Apple clang on macOS arm64 contracts each
`a*b + c` written in one expression into a fused multiply-add; the Linux
x86_64 build does not. Read from the source order (and confirmed in the
disassembled library), the fused shapes are: dot products and squared lengths
`fma(z, w, fma(x, u, y*v))`; cross-product components `fma(a, b, -(c*d))`;
matrix cells `fma(d, h, fma(c, g, fma(a, e, b*f)))`; `MatrixInvert` factors
`fma(a, b, -(c*d))`, its determinant and cofactors chained left to right with
the negations folded into the factors; `Vector3Transform` adds `m12` after the
fused three-term sum; `MatrixRotate` cells `fma(x*y, t, z*sin)`. Products in
separate statements or separate inline functions (scaling, `position +
direction*t`, `cos*2`) are never fused. One optimizer choice is part of the
profile too: where `GetCameraViewMatrix` and `GetCameraMatrix` store
`MatrixLookAt`'s translation `-(x*u + y*v + z*w)`, the arm64 build folds the
negation into `fnmadd`, `(-z)*w + (-fma(x, u, y*v))` rounded once, which can
differ from the negated dot product in the sign of an exact zero; inside the
screen-space queries the same row is only added and multiplied, and keeps the
plain negation. `M.Fused{}` uses the total binary32 FMA in `src/fma.bend`:
exact integer significands rounded once, for every input class (signed zeros,
subnormal operands and results, overflow, infinities and NaN). The harness
declares the profile per host (`conformance.contraction`: `M.Fused{}` on Darwin
arm64, `M.Uncontracted{}` on Linux x86_64).

`M.Libm` selects `sinf`/`cosf` (rotations, `GetCameraMatrix2D`) and `atan2f`
(`lock_view`), using Jonmath's kernels ([ANGLES.md](ANGLES.md),
[ROTATION.md](ROTATION.md)). The glibc profiles' sine/cosine is the Arm
optimized-routines polynomial that glibc ships; it equals the C model of
`tools/trig_probe.py` on every argument tried. Jonmath's `M.AppleLibm{}`
sine/cosine rounds the exact value, but macOS arm64 `sinf`/`cosf` do not
always do so: on 40001 random one-cycle half-angles about 2.6% differ by one
ulp (for example `cosf(-0.42634228)`, an almost exact tie). Camera queries
therefore accept only a zero `sinf`/`cosf` argument under `M.AppleLibm{}`,
where every libm returns the signed zero and one.

## None and refusals

Jonlib returns `None` where it has no verified implementation of the native
result:

- **Perspective projections.** `GetCameraProjectionMatrix`,
  `GetWorldToScreenEx` and `GetScreenToWorldRayEx` with `CAMERA_PERSPECTIVE`
  need `MatrixPerspective`'s binary64 `tan`, which is blocked
  ([PERSPECTIVE.md](PERSPECTIVE.md)); no F32 or F64 tangent is substituted.
  `GetCameraViewMatrix`/`GetCameraMatrix` (`MatrixLookAt`) do not depend on the
  projection and are defined for every camera.
- **Rotation angles.** The angle checked is the one actually rotated by: the
  yaw and roll angle, the pitch after `lock_view` clamping, each
  `UpdateCameraPro` step and `rotation*DEG2RAD` of a 2D camera; its `sinf`/`cosf`
  argument is half of it for `Vector3RotateByAxisAngle` and the angle itself for
  `MatrixRotate`. A zero argument is always reproduced. Under the glibc
  profiles a normal argument with `|angle| <= 6.283186f` (Jonmath's one-cycle
  rotation profile) also is; subnormal arguments are outside the kernel, and
  NaN and infinite angles outside the profile. Under `M.AppleLibm{}` every
  nonzero argument is `None` (see above), so a 2D camera with rotation 0 and
  rotations by zero work, others do not.
- **lock_view angles.** Each `Vector3Angle` needs the checked angle contract:
  a normal or zero cross length and dot product, a normal or zero `atan2f`
  result, and a zero result only for a zero cross length (this excludes the
  Apple subnormal-result case of [ANGLES.md](ANGLES.md#known-gap)).
- **Screen sizes and spans.** Widths and heights outside `1..2147483647`, and,
  for orthographic cameras, a non-finite `fovy` or `fovy/2.0 * aspect` outside
  the checked binary64 multiplier (exponent sum above 127, i.e. `fovy` beyond
  about `2^97`).

Within these limits every input is supported, including NaN, infinite,
signed-zero, subnormal and huge camera components; NaN results carry no sign or
payload contract.

## Not ported here

- `GetWorldToScreen`, `GetScreenToWorldRay` read the window size and
  `UpdateCamera` reads keyboard, mouse, gamepad and frame-time state; they
  belong to the window/input/frame work of Phase 2.
- `rlSetClipPlanes` cull distances other than rlgl's defaults.
- A verified kernel for macOS arm64 `sinf`/`cosf` (nonzero `M.AppleLibm{}`
  rotations).

## How it is verified

| Gate | Tool | Compares |
|---|---|---|
| `camera` | `tools/camera_probe.py` | every result bit of the 19 functions above against the linked raylib with the host contraction and libm profiles, the refusals selected by a C oracle repeating the contract, and the total FMA kernel against the host `fmaf` |
| `camera-uncontracted` | `tools/camera_probe.py --uncontracted-control` | the same cases against the pinned `rcamera.h`/`rcore.c` functions compiled without contraction, checking `M.Uncontracted{}` on any host |
| `camera-glibc239` | `--uncontracted-control --gnu-libm glibc239` | the pinned functions without contraction, with `sinf`/`cosf` from the Arm model and `atan2f` from the pinned glibc 2.39 (Sun) source: `M.Uncontracted{}` with `M.Glibc239Libm{}` on any host |
| `camera-fused-glibc241` | `--fused-control --gnu-libm glibc241` | the pinned functions compiled with arm64 clang contraction into FMA, the Arm model and the pinned glibc 2.41 `atan2f`: `M.Fused{}` with `M.Glibc241Libm{}` and nonzero rotations. macOS only: x86-64 FMA code (`-mfma`) negates zeros and produces negative default NaNs where arm64's `fnmadd` folding does not, so `M.Fused{}` names the arm64 code generation |

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only camera
```

The corpus has random cameras and degenerate ones (target equal to the
position, up parallel or antiparallel to the view, zero, signed-zero, tiny,
subnormal, huge and nonfinite components), the three world-plane branches and
their `0.7071f` thresholds, `lock_view` pitches near the vertical, every flag
combination, orthographic, perspective and other projections, aspect ratios
including zero, negative and infinite, 2D cameras with rotation, zoom and
offset (including zero zoom), and screen sizes from `1x1` to `INT_MAX`. CPU-1,
CPU-2 and JavaScript lanes; GPU, other targets and performance remain open.
