# Session handoff (2026-10-10)

Snapshot for continuing on another machine or in a new session. Everything
described here is committed and pushed (`main`, and the pieces still on their
way to it on `stack/final`); nothing lives only on one machine except
throwaway caches (`.build/`).

## Goal in force

Jonathan's directive: **100% of raylib ported** (raylib.h, raymath.h, rlgl.h,
rcamera.h, rgestures.h), **validated by porting every upstream example** to
Bend and replaying it against the native example. Work autonomously; merge to
`main` only after a CI run concludes `success`; delete merged branches.
**Land work in small pieces** (2026-10-10): one example port or one library
change per commit, each on `main` as soon as its own CI run is green, instead
of batches of many commits behind one long run.

## Where things are

| Branch | Content | State |
|---|---|---|
| `main` | everything through Jongui's first controls, the change-scoped Conformance workflow ([CI.md](CI.md)) and, once its run is green, `feature/examples-batch-4` (142 example ports, render-texture depth buffers, `Font.texture_size`, `Surface.colors_image`, `M.Float64.to_f32`/`to_int`) | CI green on every commit merged |
| `stack/final` | 28 single-purpose commits on top of that, in landing order (below). The name starts no CI run: it is the backup of work not yet on `main` | each piece goes to `main` through its own `feature/**` branch |

Landing order of `stack/final` (`python3 tools/ci_scope.py --base <parent> --head <commit>` prints each one's scope):

1. Eleven example ports that need nothing new (`models_mesh_picking`,
   `text_rectangle_bounds`, `shapes_rlgl_color_wheel`, `text_inline_styling`,
   `core_keyboard_testbed`, `shapes_rectangle_advanced`,
   `core_input_gestures_testbed`, `textures_clipboard_image`,
   `core_3d_camera_fps`, `text_strings_management`, `core_input_gamepad`),
   the laws for the last library changes and the example-table generators:
   scoped runs, minutes each.
2. One group that needs a complete run, verified together at its head: the
   compiler's memory hint in containers (`tools/probekit.py`), `M.Libm.pow2`
   for every exponent, `M.Libm.exp`/`log`, `M.Libc.srand`/`rand`, `J.Until`
   (a program whose loop has its own exit condition) and
   `M.Libm.hypot_within`.
3. Nine ports on top of those (`shapes_easings_ball`, `_box`, `_testbed`,
   `core_2d_camera_mouse_zoom`, `shapes_simple_particles`,
   `textures_textured_curve`, `shapes_top_down_lights`,
   `core_window_should_close`, `shapes_ball_physics`): scoped runs.

A branch is classified against its merge base with `main`, so a piece is
pushed (as `feature/<name>`, at its commit of the stack) once the pieces under
it are on `main`; pieces of the same kind may share one branch and are then
verified at its head. `feature/examples-batch-5` held items 1 and 2 as one
branch; its run was cancelled in favour of the pieces and the branch can be
deleted when they are on `main`.

`feature/examples-gui`, `feature/audio-waves`, `wip/models-drawing-obj`, `wip/lgpl-tan-asinf`,
`integrate/models-lgpl` and `feature/scoped-ci` are merged into `main` and deleted.

Coverage (`python3 tools/api_plan.py check`): raylib.h 514/600 partial
(20 blocked, 66 not started); raymath.h 146/146; rlgl.h 93/163; rcamera.h
12/12; rgestures.h 10/10. Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): **151/212 ported** with the whole stack, 19 ready, 42 waiting (one port, `textures_image_kernel`, is a documented refusal: the native example is undefined behavior, [CONVOLUTION.md](CONVOLUTION.md)). No API
is `complete` by design until Phase 7 targets (see MASTER-PLAN).

## Decisions and rules to keep (from Jonathan; also in project memory)

- AGENTS.md rules: pinned toolchains, never install/update them or modify
  the Bend compiler; never loosen expected results; refuse undefined native
  behavior; preserve notices.
- **LGPL (2026-10-09): allowed, isolated.** glibc's `tan` and `asinf`
  (LGPL-2.1+) live in `src/lgpl/` with full notices; the rest of Jonlib stays
  zlib. Arm optimized-routines code (MIT alternative: `powf`, `sinf`/`cosf`)
  stays on the zlib side with its notice. Apple's libm is unpublished: Apple
  profiles stay refused where they can't be reproduced.
- Merge discipline: merge to `main` only when CI `conclusion == success`;
  delete merged branches locally and remotely; never force-push or amend pushed
  commits without asking.
- Work before 2026-10-06 was GPT-generated: re-verify rather than trust.
- Laws with every library change (2026-10-10): a change to `jonlib.bend`,
  `jonmath.bend`, `jongui.bend` or `src/` adds its durable properties to
  `LAWS.bend` with their proofs in `PROOF.bend` in the same commit.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## What changed last (2026-10-09/10)

- **Change-scoped CI** ([CI.md](CI.md)): `tools/ci_scope.py` classifies a
  push. Example ports replay only themselves and three canaries (minutes,
  one job per host); a library file that only gained definitions, the
  proofs, a probe or a gate entry run only the gates they can reach (about
  an hour); a changed definition or a shared tool runs everything; a merge
  to `main` is compared with the nearest commit that already passed, and a
  nightly complete run on `main` is the safety net.
- **libm and libc kernels** ([MATH.md](MATH.md), [RANDOM.md](RANDOM.md)):
  under the glibc profiles `M.Libm.pow2` (`powf(2, y)`/`exp2f` for
  `|y| < 126`), `M.Libm.exp` and `log` (`expf` below 87 in magnitude except
  two arguments where glibc's CPU variants differ; `logf` for positive
  normal values), each exhaustively equal to glibc 2.39 and 2.41 in both
  variants, and `M.Libc.srand`/`rand` (glibc's `rand()`).
  `M.Libm.hypot_within(x, y, r)` is the comparison `hypot(x, y) <= r` for
  every faithful `hypot`, on any profile, refusing the band where two could
  disagree. Gates `pow2`, `explog`, `rand`, `hypot`.
- **`J.Until`** ([DRIVER.md](DRIVER.md)): a program whose loop ends on its
  own condition (`while (!exitWindow)`), for the replay and the desktop
  driver.
- **Perspective** ([PERSPECTIVE.md](PERSPECTIVE.md)): glibc's x86_64 `tan`
  (FMA ifunc variant) as an LGPL module, exhaustively equal to native glibc
  2.39/2.41 on every argument raylib can pass; `MatrixPerspective`,
  perspective `BeginMode3D` and the camera queries under the glibc profiles.
- **sinf/cosf** ([SINCOSF.md](SINCOSF.md)): glibc's own functions on every
  finite binary32 argument (model equal to native on all 2^32 inputs, both
  variants, glibc 2.39 and 2.41). `M.Libm.sin/cos`; the one-turn bound is
  gone under the glibc profiles, so `DrawSphereWires` and every rotation
  beyond one turn work there. Under `AppleLibm`, `Libm.sin/cos` answer only
  on the verified whole degrees.
- **Shaders** ([SHADERS.md](SHADERS.md)): the API as the software renderer
  runs it (no-ops), which makes most `shaders_*` examples portable.
- **Jongui** ([GUI.md](GUI.md)): raygui's style table, global state, label,
  button, check box, toggle, toggle group, slider and slider bar as
  `jongui.bend`; the examples plan tracks raygui per function
  (`api/jongui.json`). Spinner, dropdown box and text box need raygui's
  icons first.
- **Render-texture depth** ([RLGL.md](RLGL.md)): each render texture has its
  own depth buffer (zeroed at creation, kept between texture modes, as in
  rlsw), which unblocked `core_3d_camera_split_screen`,
  `textures_framebuffer_rendering`, `shaders_postprocessing` and
  `shaders_custom_uniform`.
- **Examples**: 151 ported with the stack; gates `examples-core`, `-shapes`, `-text`,
  `-textures`, `-models`, `-shaders`.
- **Compile memory**: per-output compiler processes and a cgroup-aware job
  budget in probekit; `LoadImage` of a `.png` in ports is `Surface.load_png`
  (the generic loader compiles every decoder, about 1.5 GB more). In a
  container with a memory limit below the host's memory, probekit passes
  half the limit to Bun's engine (`BUN_JSC_forceRAMSize`): the engine paces
  its collections by physical memory, and an OBJ example's compile passed an
  8 GiB limit without it (5 GB with it, the same output, 1.5x the time).

## Next steps, in order

1. Land `stack/final` piece by piece, in its order: push a piece as
   `feature/<name>` once what is under it is on `main`, merge it
   (fast-forward) when both workflows conclude `success`, delete the branch.
   Hosted macOS runs five jobs at a time across every run: keep one complete
   run in flight at most, and never push to a branch whose run you wait for
   (the push cancels it).
2. Keep porting the ready examples ([EXAMPLES.md](EXAMPLES.md)), one port a
   commit. `textures_sprite_stacking` is written and parked
   (`.build/pending/`, not in the repository): its `booth.png` is 112x11468
   and Jonlib's images stop at 4096 pixels per axis (PNG also at 1 MiB of
   input), so the texture does not load. `text_codepoints_loading` reads out
   of bounds natively (an `UNDEFINED_NATIVE` port).
3. Small library pieces that each unblock examples (a new definition is a
   scoped run; changing one is a complete run):
   - an IO step in `J.Program`'s update (`core_storage_values`);
   - `tanf`, `GuiGroupBox`/`GuiLine` and `DrawSplineLinear`
     (`shapes_math_sine_cosine`);
   - binary64 `sin`/`cos` (`models_waving_cubes`,
     `shaders_spotlight_rendering`, `GenMeshCylinder`);
   - the wall clock (`shapes_digital_clock`, `shapes_clock_of_clocks`,
     `core_custom_logging`);
   - the rlgl framebuffer functions (6 examples);
   - images beyond 4096 pixels on an axis (`textures_sprite_stacking`);
   - glTF/IQM/M3D/VOX model loading and model animations (about 15 examples).
4. Large milestones: the remaining raygui controls (spinner, text box,
   dropdown box, progress bar, group box, line, scroll panel, list view;
   about 11 more examples), the audio device and streams (12+ examples; the
   reference build has `SUPPORT_MODULE_RAUDIO=OFF`), VR.
5. Possible further CI savings, not decided: hosted macOS is the ceiling of
   a complete run (about 20 runner-hours through five slots). Running the
   byte-level codec gates on macOS only nightly would cut a complete run to
   about 1.5 hours, at the cost of "both hosts green before merge" for those
   gates.

## Known pitfalls (save time)

- **Bend rules that bite**: a `match` must scrutinize a parameter or a
  pattern-bound name, and no `let` may precede a destructuring of a parameter;
  no mutual recursion; a def must be above its callers; `Bool.pick` evaluates
  both branches and needs a Data type (pairs are Type: use a `match` helper);
  constructors in lets need `{... : T}`; `+` only on Data. Parameters must be
  destructured in declaration order (a field binder before the next
  parameter; a matched scalar parameter last), and the binders of a
  two-scrutinee `match` cannot be destructured in the case (use a helper def).
- **Example scripts cost JavaScript-lane time**: a frame of hundreds of
  primitives or a full-screen filtered texture takes seconds there
  (`textures_fog_of_war`, `textures_tiled_drawing`); keep such scripts short
  (the probe stops a lane after 600 s).
- **Strings are C byte strings**: a Bend literal holds code points, so write
  non-ASCII text as UTF-8 bytes (`"I\u{c3}\u{b1}igo"`).
- **Bend native miscompile:** a `Bool.pick(Bool, …)` result feeding `||` in the
  same def is wrong on native lanes (repro `tests/compiler/bool_pick_or.bend`,
  diagnostic gate `bend-defects`). Never write it.
- **Apple clang 21 crashes** compiling very large Bend defs: keep defs small and
  probes data-driven ("scenes as data through one interpreter def").
- **Memory:** one Bend compile at a time on an 8 GiB machine (exit -9 is the
  OOM killer); probes' JavaScript lanes peak near 4.5 GB. The JavaScript
  lane keeps every frame's text until its end: about 800 text-heavy frames
  reached 6.6 GB, so keep such scripts near 250 frames. For a manual compile
  in a container prefix `BUN_JSC_forceRAMSize=4294967296`; `--check-only`
  type-checks a file in about 15 seconds.
- **A running probe compiles from the working tree** when it reaches each
  candidate: do not edit `jonlib.bend`, `jonmath.bend`, `src/` or the
  examples it will compile until it ends (Python tools are safe to edit).
- **Check exit statuses, not piped tails:** `check | tail && git commit`
  commits whatever the check said; run the check, read its status, then
  commit.
- **Laws close by evaluation, and F32 primitives do not evaluate** in the
  checker (nor does a binary32 promotion): state the refused cases, the
  word-level results and the decision tables instead.
- **Host-dependent expectations:** Linux CI uses the glibc profiles and
  uncontracted x86-64; macOS uses Apple libm and fused arm64. Compute every
  probe expectation per host profile; never run natively anything undefined in
  C. `--assume-libm AppleLibm` on the examples and models probes runs Jonlib
  and the refusal oracle under the Apple profile on Linux: use it before
  pushing, a complete CI round takes about 3.5 hours.
- **A port that calls sinf/cosf itself** must refuse where `M.Libm.sin/cos`
  return `None` (keep a `valid` flag in its state), and its refusal predictor
  in `tools/examples_probe.py` must name the same frame.
- **Target FPS below 60** hangs the native busy-wait under the scripted clock.
- **Reference build:** probekit's `CUSTOMIZE_BUILD=ON` raylib enables every
  `SUPPORT_*` flag `config.h` defines, including default-off ones
  (docs/VERIFICATION.md).
- **Compilers fold `powf(x, 2)` into `x*x`**; check compiled references before
  assuming a libm call.
- CI: a complete run is 10 shards per OS, gate `minutes` = measured macOS durations; most changes run a scoped subset (docs/CI.md).

## Toolchain

Pinned in `toolchain.json`: Bend at `b7ebee9…` with the declared overlay
(`patches/`), raylib 6.0 at `dbc56a87…`, Bun 1.3.12 (probes refuse another
version: put the pinned one first in `PATH`). Local layout used so far: Bend
at `~/Projetos/bendlang/bend` (CLI `bun ~/Projetos/bendlang/bend/bend2/main.ts`),
raylib at `~/Projetos/raysan5/raylib`. Checks:

```sh
python3 -m unittest discover -s tests
python3 tools/check_project.py
bun ~/Projetos/bendlang/bend/bend2/main.ts PROOF.bend
python3 tools/run_gates.py --bend-source ~/Projetos/bendlang/bend --raylib-source ~/Projetos/raysan5/raylib --only <gate>
python3 tools/examples_probe.py --bend-source ~/Projetos/bendlang/bend --raylib-source ~/Projetos/raysan5/raylib --example <name> [--assume-libm AppleLibm]
```
