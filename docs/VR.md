# VR stereo

Jonlib adapts raylib 6.2's VR simulator functions of `rcore.c` as `Vr.*` and
two `Frame` functions in `jonlib.bend`.

| Function | raylib | Contract |
|---|---|---|
| `Vr.load_stereo_config_for(libm, device)` | `LoadVrStereoConfig` | The configuration for a `VrDeviceInfo`, below. |
| `Vr.unload_stereo_config(config)` | `UnloadVrStereoConfig` | Nothing to unload. |
| `Frame.begin_vr_stereo_mode(frame, config)` | `BeginVrStereoMode` | The frame as it is: the software renderer does not draw in stereo. |
| `Frame.end_vr_stereo_mode(frame)` | `EndVrStereoMode` | The frame as it is. |

A `VrDeviceInfo{h_resolution, v_resolution, h_screen_size, v_screen_size,
eye_to_screen_distance, lens_separation_distance, interpupillary_distance,
lens_distortion_values, chroma_ab_correction}` holds raylib's fields: the
resolutions are C ints as U32 words, the two arrays of four floats are
`M.Vector4` values. A `VrStereoConfig` holds each eye's projection and view
offset matrix (`left_projection`, `right_projection`, `left_view_offset`,
`right_view_offset`) and the six pairs the distortion shader takes
(`left_lens_center`, `right_lens_center`, `left_screen_center`,
`right_screen_center`, `scale`, `scale_in`) as `M.Vector2` values.

## The configuration

The reference is raylib's software renderer, whose `rlGetVersion()` is
`RL_OPENGL_SOFTWARE`, not `RL_OPENGL_11`: `LoadVrStereoConfig` computes the
whole configuration there (on OpenGL 1.1 it returns zeros). In binary32, in
C's order of operations and uncontracted:

- `aspect = ((float)hResolution*0.5f)/(float)vResolution`;
- `lensShift = (hScreenSize*0.25f - lensSeparationDistance*0.5f)/hScreenSize`,
  the lens centers `(0.25 + lensShift, 0.5)` and `(0.75 - lensShift, 0.5)`,
  the screen centers `(0.25, 0.5)` and `(0.75, 0.5)`;
- `distortionScale`, the polynomial of the four lens distortion values in
  `lensRadius^2` with `lensRadius = fabsf(-1 - 4*lensShift)`;
- `scaleIn = (4, 2/aspect)` and `scale = (0.25/distortionScale,
  0.5*aspect/distortionScale)`;
- `fovy = 2*atan2f(vScreenSize*0.5f*distortionScale, eyeToScreenDistance)`
  with the libm profile's `atan2f` ([ANGLES.md](ANGLES.md));
- the projections `MatrixPerspective(fovy, aspect, 0.05, 4000.0)` (the
  profile's binary64 `tan`, [PERSPECTIVE.md](PERSPECTIVE.md)) times a
  translation by `4*lensShift` to the left eye's side and the right's;
- the view offsets, translations by half the interpupillary distance each
  way, and `(0.075, 0.045)` up and back.

The chromatic aberration values are not read. `None` where a result is not
finite (a resolution or a screen width of 0, a distortion scale of 0, NaN
and infinite fields: the bits of a NaN are the host's), where the profile's
`atan2f` or `tan` is refused or the perspective has no height (a screen
height of 0), and for `M.AppleLibm`, whose binary64 `tan` is not reproduced.

## Stereo mode

`BeginVrStereoMode` enables rlgl's stereo rendering and sets its two
projection and view offset matrices; rlgl has them on OpenGL 3.3 and ES 2
only. On the software renderer those calls do nothing, the scene between
`BeginVrStereoMode` and `EndVrStereoMode` is drawn once with the camera's
own matrices, and the distortion shader an example then draws the render
texture through changes nothing ([SHADERS.md](SHADERS.md)).

## How it is verified

`tools/vr_probe.py` (gate `vr`) runs native `LoadVrStereoConfig` on the
uncontracted memory-platform raylib and `Vr.load_stereo_config_for` on 40
devices and compares all 76 words of each configuration: the device of
`core_vr_simulator`, other resolutions (portrait, one pixel, odd and
negative C ints), screens from a millimetre to ten metres, lenses further
apart than half the screen, on its edge and together, eyes from a millimetre
to a metre away and behind the screen, distortion polynomials with zero,
negative and large coefficients, interpupillary distances of 0, negative and
3e30, and twelve seeded devices. Ten devices whose results are not finite or
whose perspective has no height are refused on Jonlib alone. On a host whose
libm is `M.AppleLibm` every device must be refused (`--apple-contract`
checks that on any host). CPU-1, CPU-2 and JavaScript.

`core_vr_simulator` (its 2160x1200 render texture drawn to the window through
the shader) replays frame by frame against the native example in the
`examples-core` gate.

Gaps: no stereo rendering (no renderer Jonlib reproduces has it); only the
uncontracted profile; `M.AppleLibm` is refused; no GPU evidence.
