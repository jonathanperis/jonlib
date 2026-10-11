# Session handoff (2026-10-11)

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
**macOS is off the merge path until the port is complete** (2026-10-10):
pushes and pull requests run on Linux only; then macOS is turned back on and
everything merged is validated against it ([CI.md](CI.md)). That validation
is owed: the port is not done before it passes.

## Where things are

| Branch | Content | State |
|---|---|---|
| `main` | everything through 157 example ports, and each piece of `stack/final` as its run goes green: Jongui's controls ([GUI.md](GUI.md)), the change-scoped Linux-only Conformance workflow ([CI.md](CI.md)), the libm/libc kernels (`pow2`, `exp`/`log`, `rand`, `hypot_within`, `tanf`, the decimal parser), `J.Until`, the rlgl uniform setters, `UploadMesh`, `ColorFromHSV` for any finite hue, binary glTF | green on Linux for every commit |
| `stack/final` | the commits not yet on `main`, in landing order. The name starts no CI run: it is the backup | each piece goes to `main` through a `feature/**` branch |

On `stack/final` now, in landing order (`git log origin/main..origin/stack/final`
lists what is left; `python3 tools/ci_scope.py --base origin/main --head <commit>`
prints a commit's scope). One complete run verifies the whole list (branch
`feature/piece-38`, pushed 2026-10-11 04:13 UTC): the pieces edit
`jongui.bend`'s header comment, which the scope tool counts as a changed
definition, and `GuiSetIconScale` adds a field to Jongui's state.

1. `GuiValueBox`/`GuiSpinner`, the port `shapes_hilbert_curve`,
   `GuiDropdownBox`/`GuiPanel`/`GuiStatusBar`, the port
   `shapes_splines_drawing`, `GuiTextBox`, the port `core_compute_hash`.
2. `GuiSetIconScale` and the port `core_clipboard_text`.
3. `GuiScrollPanel`/`GuiScrollBar` and the port `shapes_pie_chart`.
4. Thirty-one rlgl buffer, shader object, compute and storage buffer
   functions (empty on the software path) and the port
   `shaders_rlgl_compute`.
5. After that branch: the port `shaders_lightmap_rendering` (a scoped run
   once the rest is on `main`) and this document.

`main` may move under a branch in CI: another session pushed a CI commit on
2026-10-11 while two branches were running. A green branch that `main` is no
longer an ancestor of is merged with a merge commit after the unit tests and
`tools/check_project.py` pass on the merged tree; the rest of the stack is
then rebased onto `main`.

How the last stack went (2026-10-10/11): thirteen independent pieces were
pushed as thirteen `feature/piece-NN` branches and landed one by one within
33 minutes; everything stacked on changed definitions shared one complete
run at the stack's tip (about 100 minutes) and `main` was fast-forwarded to
it. A branch is classified against its merge base with `main`, so a piece is
pushed only once the pieces under it are on `main`, or with them, verified
at the branch's head.

`feature/examples-gui`, `feature/audio-waves`, `wip/models-drawing-obj`, `wip/lgpl-tan-asinf`,
`integrate/models-lgpl`, `feature/scoped-ci`, `feature/examples-batch-4` and the stack's branches are merged into `main` and deleted
(`feature/examples-batch-5` was re-landed as pieces and deleted).

Coverage (`python3 tools/api_plan.py check`): raylib.h 515/600 partial
(20 blocked, 65 not started); raymath.h 146/146; rlgl.h 98/163; rcamera.h
12/12; rgestures.h 10/10 (rlgl.h gains 31 functions with the stack). Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): **163/212 ported** with the stack, 18 ready, 31 waiting (one port, `textures_image_kernel`, is a documented refusal: the native example is undefined behavior, [CONVOLUTION.md](CONVOLUTION.md)). No API
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

## What changed last (2026-10-09/11)

- **Jongui grew to the controls the examples use** ([GUI.md](GUI.md)):
  raygui's icons in control texts (`src/gui_icons.bend`, generated from the
  pinned raygui.h and checked by the `gui-icons` gate) with
  `GuiSetIconScale`, `GuiLine`, `GuiGroupBox`, `GuiValueBox` and `GuiSpinner`
  (outside edit mode), `GuiStatusBar`, `GuiPanel`, `GuiDropdownBox` and
  `GuiTextBox` (raygui's two text box globals are a `G.Gui.Editing` value),
  `GuiScrollPanel` and `GuiScrollBar`. Left: `GuiProgressBar`,
  `GuiListViewEx`, `GuiGetFont`.
- **rlgl's empty functions** ([RLGL.md](RLGL.md)): the vertex array, buffer,
  shader object, compute and storage buffer functions as the software path
  leaves them (ids 0, locations -1, nothing else), compared natively by the
  `rlgl` gate.
- **`M.Libm.tanf`** ([MATH.md](MATH.md)): glibc 2.39's `tanf` on every
  finite argument (an LGPL module; glibc 2.41's is a different, correctly
  rounded function and stays refused, as does Apple's).
- **Scoped CI jobs of 50 minutes** ([CI.md](CI.md)): the corpus and the core
  examples of an additive library change run side by side (about 50
  minutes instead of 90), up to six jobs a host.

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
- **Small unlocks**: the rlgl uniform setters and `rlSetShader` (no effect on
  the software renderer), `UploadMesh` (`Mesh.upload`, the mesh given), and
  `ColorFromHSV` for any finite hue (an exact `fmodf` by 6; it was limited
  to one turn).
- **Binary glTF** ([MODELS.md](MODELS.md)): `LoadModel` of `.glb` files for
  float attributes, indices, node transforms and base color factors
  (`src/gltf.bend`), on an original JSON reader (`src/json.bend`) and a
  correctly rounded decimal parser (`M.Float64.from_decimal`,
  `src/strtod.bend`, [MATH.md](MATH.md)). Gates `strtod`, `gltf`.
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
   Push each branch in its own `git push` (a push of many refs at once
   started only part of the workflows) and never push to a branch whose run
   you wait for (the push cancels it). A complete run takes fifteen Linux
   runners for about an hour and a half; the account runs about twenty
   jobs at a time.
2. Grow the glTF loader, the largest unlock left in the models family
   (`models_loading_gltf`, `models_animation_gpu_skinning`,
   `models_bone_socket`, `models_animation_blend_custom`,
   `models_animation_blending` and `_timing` with `GuiProgressBar`,
   `shaders_shadowmap_rendering` with the framebuffer functions). What the
   reference does (found 2026-10-11, read `rmodels.c` before designing):
   - The reference library is built with `SUPPORT_GPU_SKINNING` on
     ([VERIFICATION.md](VERIFICATION.md)), so `animVertices` is never
     allocated and `UpdateModelAnimationVertexBuffers` skips every mesh: on
     the software renderer **an animated model is drawn in its bind pose**.
     `UpdateModelAnimation` only fills `model.currentPose` and
     `model.boneMatrices`. No CPU skinning is needed.
   - What reaches the screen is the data the examples read themselves:
     animation names and `keyframeCount`, `skeleton.bones[i].name`,
     `skeleton.bindPose[i]` and `anim.keyframePoses[frame][bone]`
     (`models_bone_socket` places the hat, sword and shield with them).
   - `greenman.glb` (164 KB; three examples) has one skin of 12 joints, four
     LINEAR animations, `JOINTS_0` as u8 and `WEIGHTS_0` as float, and its
     base color texture as an embedded PNG (`images[0].bufferView`); its
     hat, sword and shield files have a texture each. `robot.glb` (1.6 MB;
     three examples) has 43 joints, 14 animations, base color factors and no
     texture. The loader refuses both today (`static` in `src/gltf.bend`:
     no skins, textures or images).
   - `LoadModelAnimationsGLTF`: `keyframeCount = (int)(duration*60) + 1`,
     frame `j` at `j/60` s; each bone starts from its node's TRS and takes
     `GetPoseAtTimeGLTF` per channel (the keyframe search leaves keyframe 0
     with `t` clamped to 1 at or after the last key; `Vector3Lerp`,
     `QuaternionSlerp` under the libm profile); the root pose is composed
     with the world transform of joint 0's parent (`MatrixDecompose`), then
     `BuildPoseFromParentJoints`. Jonmath has every raymath function used.
   - Jonlib's `Model` and `Mesh` have no skeleton, pose or bone data. The
     additive route: new types (`Transform`, `BoneInfo`, `ModelSkeleton`,
     `ModelAnimation`) and functions beside the model (the skeleton of a
     file, its animations, the pose and bone matrices of a frame), in a new
     module that reuses `src/gltf.bend`'s JSON, accessor and node helpers.
     Accepting skins and embedded textures changes the loader's existing
     definitions (a complete run).
   Also:
   textures and images (embedded and external; `shaders_basic_pbr` also needs
   PNG files above Jonlib's 1 MiB input limit), skins and
   `LoadModelAnimations`/`UpdateModelAnimation` (`models_loading_gltf` and
   eight animation examples), glTF as text with external buffers.
3. The remaining raygui controls, each a small additive piece of
   `jongui.bend` verified by the example that uses it: `GuiProgressBar` (two
   animation examples), `GuiListViewEx` and `GuiGetFont`
   (`core_directory_files`, with the directory functions). Append whole
   definitions only and leave the file's header comment alone, or the piece
   runs in full. The probe's replayed events never reach `GetCharPressed`
   (typing into a text box cannot be compared natively) and no example's
   content overflows its scroll panel (the scroll bars are unverified).
4. Other pieces that each unblock examples:
   - an IO step in `J.Program`'s update (`core_storage_values`);
   - binary64 `sin`/`cos` (`models_waving_cubes`,
     `shaders_spotlight_rendering`, `GenMeshCylinder`);
   - the wall clock (`shapes_digital_clock`, `shapes_clock_of_clocks`,
     `core_custom_logging`): Base's `IO.now` is a monotonic clock, so the
     desktop driver has no source for `time()` without a new effect in the
     Bend overlay (the replay can inject one);
   - the rlgl framebuffer functions (6 examples). On the reference they
     run on rlsw: `rlLoadTextureDepth` makes a D32 renderbuffer whatever
     `useRenderBuffer` says, so the examples' `LoadRenderTextureDepthTex` is
     `LoadRenderTexture` with other calls, and their shaders are no-ops
     (`shaders_depth_rendering` draws its depth texture as a white quad).
     Jonlib's canvas has no framebuffer objects apart from
     `RenderTexture.load`: the functions need an attachment table by
     framebuffer id in `src/frame.bend`;
   - `shaders_game_of_life` is ready but steps a 2048x2048 world through a
     shader each frame: too heavy for the JavaScript lane as written;
   - images beyond 4096 pixels on an axis (`textures_sprite_stacking`,
     parked in `.build/pending/`, not in the repository);
   - `GetFileModTime` (`shaders_hot_reloading`), `GetApplicationDirectory`
     (`core_screen_recording`); `models_decals` is ready since `UploadMesh`;
     `text_codepoints_loading` reads out of bounds natively (an
     `UNDEFINED_NATIVE` port);
   - IQM, M3D and VOX model loading;
   - the audio device and streams (12+ examples; the reference build has
     `SUPPORT_MODULE_RAUDIO=OFF`), VR.
5. **Owed before the port is called done:** turn macOS back on
   (`MERGE_HOSTS` in `tools/ci_scope.py`, the `os:` line of
   `.github/workflows/checks.yml`), run both workflows manually on `main`
   and fix everything macOS finds. Until then the nightly runs (06:17 UTC,
   every host) show what macOS thinks of `main`: note a red one here.

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
