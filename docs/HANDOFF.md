# Session handoff (2026-10-10)

Snapshot for continuing on another machine or in a new session. Everything
described here is committed and pushed to `feature/examples-batch-4`; nothing
lives only on one machine except throwaway caches (`.build/`).

## Goal in force

Jonathan's directive: **100% of raylib ported** (raylib.h, raymath.h, rlgl.h,
rcamera.h, rgestures.h), **validated by porting every upstream example** to
Bend and replaying it against the native example. Work autonomously; merge to
`main` only after a CI run concludes `success`; delete merged branches.

## Where things are

| Branch | Content | State |
|---|---|---|
| `main` | c3e2e6b: everything through Jongui (raygui's first controls), `M.Libm.pow2` and 79 example ports | CI green (run 38030650917 on this commit, merged 2026-10-10) |
| `feature/examples-batch-3` | a1e88b6, on top of `main`: 29 more example ports, `Font.texture_size`/`Draw.font_texture`, `Surface.colors_image`, `M.Float64.to_f32`/`to_int`, the examples probe's 30-minute lane limit and `UNDEFINED_NATIVE` | CI run 38054490652; **merge to `main` once it concludes `success`** |
| `feature/examples-batch-4` | on top of `feature/examples-batch-3`: 27 more example ports, render-texture depth buffers and the compiler's memory hint in containers | its own CI run; **merge to `main` after batch 3, once it concludes `success`** |

`feature/examples-gui`, `feature/audio-waves`, `wip/models-drawing-obj`, `wip/lgpl-tan-asinf` and
`integrate/models-lgpl` are merged into `main` and deleted.

Coverage (`python3 tools/api_plan.py check`): raylib.h 514/600 partial
(20 blocked, 66 not started); raymath.h 146/146; rlgl.h 93/163; rcamera.h
12/12; rgestures.h 10/10. Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): **135/212 ported**, 35 ready, 42 waiting (one port, `textures_image_kernel`, is a documented refusal: the native example is undefined behavior, [CONVOLUTION.md](CONVOLUTION.md)). No API
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
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## What changed last (2026-10-09/10)

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
- **Examples**: 135 ported; gates `examples-core`, `-shapes`, `-text`,
  `-textures`, `-models`, `-shaders`.
- **Compile memory**: per-output compiler processes and a cgroup-aware job
  budget in probekit; `LoadImage` of a `.png` in ports is `Surface.load_png`
  (the generic loader compiles every decoder, about 1.5 GB more). In a
  container with a memory limit below the host's memory, probekit passes
  half the limit to Bun's engine (`BUN_JSC_forceRAMSize`): the engine paces
  its collections by physical memory, and an OBJ example's compile passed an
  8 GiB limit without it (5 GB with it, the same output, 1.5x the time).

## Next steps, in order

1. Land work on `main` in steps: when the CI run of `feature/examples-batch-3`
   is green, merge it, push and delete the branch; the same for
   `feature/examples-batch-4`. New work goes to a new branch (a push to a
   branch cancels that branch's running CI), so a verified batch is never
   held back by later commits.
2. Keep porting the ready examples ([EXAMPLES.md](EXAMPLES.md)), smallest
   first. `textures_sprite_stacking` is written and parked
   (`.build/pending/`, not in the repository): its `booth.png` is 112x11468
   and Jonlib's images stop at 4096 pixels per axis (PNG also at 1 MiB of
   input), so the texture does not load.
3. Small library pieces that each unblock examples:
   - an IO step in `J.Program`'s update (`core_storage_values`,
     `core_text_file_loading` style file access inside the loop);
   - a loop-exit condition in `J.Program` (`core_window_should_close`);
   - glibc's `rand()` (`shapes_simple_particles`, `models_point_rendering`);
   - general `powf`, `expf`/`logf`, `hypot`, binary64 `sin`/`cos`
     (`shapes_easings_*`, `core_2d_camera_mouse_zoom`, `shapes_ball_physics`,
     `GenMeshCylinder`);
   - the rlgl framebuffer functions (6 examples);
   - images beyond 4096 pixels on an axis (`textures_sprite_stacking`);
   - glTF/IQM/M3D/VOX model loading and model animations (about 15 examples).
4. Large milestones: the remaining raygui controls (toggle, toggle group,
   spinner, text box, dropdown box, progress bar, group box, line, scroll
   panel, list view; about 11 more examples), the audio device and streams
   (12+ examples; the reference build has `SUPPORT_MODULE_RAUDIO=OFF`), VR.

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
  OOM killer); probes' JavaScript lanes peak near 4.5 GB.
- **Host-dependent expectations:** Linux CI uses the glibc profiles and
  uncontracted x86-64; macOS uses Apple libm and fused arm64. Compute every
  probe expectation per host profile; never run natively anything undefined in
  C. `--assume-libm AppleLibm` on the examples and models probes runs Jonlib
  and the refusal oracle under the Apple profile on Linux: use it before
  pushing, a CI round takes about 3.5 hours.
- **A port that calls sinf/cosf itself** must refuse where `M.Libm.sin/cos`
  return `None` (keep a `valid` flag in its state), and its refusal predictor
  in `tools/examples_probe.py` must name the same frame.
- **Target FPS below 60** hangs the native busy-wait under the scripted clock.
- **Reference build:** probekit's `CUSTOMIZE_BUILD=ON` raylib enables every
  `SUPPORT_*` flag `config.h` defines, including default-off ones
  (docs/VERIFICATION.md).
- **Compilers fold `powf(x, 2)` into `x*x`**; check compiled references before
  assuming a libm call.
- CI: 10 shards per OS, gate `minutes` = measured macOS durations (docs/CI.md).

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
