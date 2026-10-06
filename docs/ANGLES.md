# Angle profiles and checked angle APIs

raymath's `Vector2Angle`, `Vector2LineAngle` and `Vector3Angle` reduce to
`atan2f`, whose last-bit behavior depends on the C library. Jonmath therefore
makes the `atan2f` implementation an explicit, versioned **profile** instead of
pretending one result is universal.

## Profiles

`M.Angle.Reference` names three source contracts:

| Profile | Source | Where it is the native behavior |
|---|---|---|
| `Apple2007AngleRn{}` | Apple Libm Intel assembly (Eric Postpischil, July 2007), commit `17a5f9da` | macOS |
| `Sun239AngleRn{}` | Sun float `atan`/`atan2` as shipped in glibc 2.39 (`tools/reference/angle_sources/`) | glibc ≤ 2.40 hosts (e.g. Ubuntu 24.04) |
| `Glibc241AngleRn{}` | glibc 2.41 `e_atan2f.c` (MIT, `tools/reference/modern_atan2f_glibc241.c`) | glibc ≥ 2.41 hosts |

A profile is a numerical contract, not host detection. The legacy
`*_for(Gradient.Reference, …)` angle functions keep their signatures and
meaning: `AccurateGradient` selects the Apple algorithm and `GnuGradient` the Sun
algorithm. (These two parallel families are scheduled to be unified.)

## Checked entry points

```bend
M.Vector2.angle_with_reference(reference, left, right) -> Maybe<F32>
M.Vector2.line_angle_with_reference(reference, start, end) -> Maybe<F32>
M.Vector3.angle_with_reference(reference, left, right) -> Maybe<F32>
```

`Some` carries exact F32 bits. `None` rejects inputs outside the contract:
every original component must be finite, and every source-order intermediate
(dot and determinant products and sums, the Vector3 cross product, squares,
length and square root) and the scalar result must be signed zero or a normal
binary32. Finite nonzero subnormal intermediates or outputs are rejected;
correct underflow to signed zero is allowed. Products with zero are kept, and
there is no reassociation or fused multiply-add in the wrapper. The rejection is
a Bend adaptation, not a claim that raymath rejects these inputs. Errno, floating
point exception flags, NaN payloads, other rounding modes and contracted
variants are outside the contract.

## How it is verified

- **Host profile selection** (`tools/native_profiles.py`, used by
  `tools/conformance.py`): a small C program built with the reference flags
  prints native `atan2f` bits for the frozen controls in
  [`angle_qualification_v1.json`](../tools/reference/angle_qualification_v1.json)
  and raylib's three wrappers for the wrapper controls. The single profile whose
  expected bits match every control is used for the main corpus's angle
  fixtures; zero or several matches fail. The same module selects the
  `fminf`/`fmaxf` signed-zero profile used by Vector min/max/clamp.
- **Kernels and wrappers** (`tools/angle_kernel_probe.py`, gate `angle-kernels`):
  the glibc 2.41 and Sun 2.39 kernels are compiled from their pinned sources and
  compared with Jonmath's kernels over the frozen corpora (exact words; for
  glibc 2.41 also branches and trace values). The checked wrappers of every
  profile are compared with raymath compiled with `atan2f` routed to that pinned
  kernel, plus the exact-rational rejection stages. This runs on every host.
  Apple2007 has no portable source, so it is compared with native libm on
  Darwin only.
- **Legacy profiles** (`tools/angle_probe.py`, gate `angle-legacy`) and
  **coefficient bounds** (`tools/modern_angle_bounds.py`, see
  [MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md)).

## Known gap

On macOS arm64, native `atan2f` and Jonmath's Apple2007 kernel differ on 13
inputs whose results are subnormal, outside the kernel's zero-or-normal scope;
they are listed as `apple_outside_contract_differences` in the gate's results.
One of them reaches the checked wrapper: `y = 0x25af786c, x = 0x70ae788d`
gives native `0x00000001` (so native raymath would be rejected by the checked
contract) but Jonmath `+0`, which the checked Apple wrapper accepts. It is far
outside the ±32767 fixture domain. Whether the arm64 libm or the port departs
from the Intel-assembly original is unresolved.
