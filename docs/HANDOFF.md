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
| `main` | everything through 169 example ports, and each piece of `stack/final` as its run goes green: Jongui's controls ([GUI.md](GUI.md)), the change-scoped Linux-only Conformance workflow ([CI.md](CI.md)), the libm/libc kernels (`pow2`, `exp`/`log`, `rand`, `hypot_within`, `tanf`, the decimal parser), `J.Until`, the rlgl uniform setters, `UploadMesh`, `ColorFromHSV` for any finite hue, binary glTF with skins and embedded textures, the rlgl buffer and shader object functions | green on Linux for every commit |
| `stack/final` | the commits not yet on `main`, in landing order. The name starts no CI run: it is the backup | each piece goes to `main` through a `feature/**` branch |

On `stack/final` now, in landing order (`git log origin/main..origin/stack/final`
lists what is left; `python3 tools/ci_scope.py --base origin/main --head <commit>`
prints a commit's scope). Every piece is scoped (new definitions, a new
module, new gates, ports); they were pushed as `feature/piece-41` to
`-47` on 2026-10-11 08:06 UTC, each at its commit, and land in order:

1. `src/gltf_anim.bend` with `Model.load_skeleton` and
   `Model.load_animations` (gate `gltf-anim`), `Model.update_animation`,
   `Model.update_animation_ex` and `Model.is_animation_valid` over a
   `ModelPose` (gate `model-pose`), the port
   `models_animation_gpu_skinning`, and the loader reading each joint's node
   once (four commits in one branch: the gate took sixteen minutes before
   the last one, four after).
2. The ports `models_bone_socket` and `models_loading_gltf`.
3. `GuiProgressBar` and the ports `models_animation_timing`,
   `models_animation_blending` and `models_animation_blend_custom`.
4. This document's previous version.
5. In CI since 09:20 UTC as `feature/piece-48` to `-51` (pieces 41 to 47
   are on `main`): the binary64 `sin`/`cos` kernel (`M.Libm.sin64`/`cos64`,
   `src/lgpl/sin.bend`, gate `glibc-sin`: 23 gates in its scoped run because
   it adds pinned glibc sources), `M.Float64.internal.add`/`subtract`/
   `divide`, `GenMeshCylinder`/`GenMeshCone`/`GenMeshKnot` (gate
   `mesh-tube`) and the ports `models_waving_cubes`,
   `shaders_spotlight_rendering` and `models_mesh_generation`.

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

Coverage (`python3 tools/api_plan.py check`): raylib.h 520/600 partial
with the stack; raymath.h 146/146; rlgl.h 98/163; rcamera.h
12/12; rgestures.h 10/10. Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): **172/212 ported** with the stack, 18 ready, 22 waiting (one port, `textures_image_kernel`, is a documented refusal: the native example is undefined behavior, [CONVOLUTION.md](CONVOLUTION.md)). No API
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
  `GuiScrollPanel` and `GuiScrollBar`, `GuiProgressBar`. Left:
  `GuiListViewEx`, `GuiGetFont`.
- **Binary64 sin and cos** ([MATH.md](MATH.md)): `M.Libm.sin64`/`cos64`
  reproduce glibc 2.39's x86_64 FMA variants operation by operation (LGPL
  module `src/lgpl/sin.bend`; the contraction positions were read from the
  disassembly of the Ubuntu 24.04 `libm.so.6`, and the C model equals the
  host on sixteen million arguments a function). How it was done, for the
  next kernel: find the ifunc resolver with `readelf --dyn-syms`, disassemble
  the `lea`-referenced variant with `objdump -d --start-address`, map each
  `vfmadd`/`vfnmadd` to the source expression, write
  `tools/reference/<name>/model.c` with `MADD`/`NMADD`, compare with the host
  on random words per exponent range (and check the unfused model differs).
- **Skeletons, animations and poses** ([MODELS.md](MODELS.md)): a `.glb`
  file's bones and bind pose (`Model.load_skeleton`), its animations as
  `LoadModelAnimationsGLTF` samples them (`Model.load_animations`), and
  `UpdateModelAnimation`/`UpdateModelAnimationEx`/`IsModelAnimationValid`
  over a `ModelPose` value beside the skeleton (Jonlib's `Model` holds no
  bones). The loader also takes skins and embedded PNG textures. Gates
  `gltf-anim` and `model-pose`. Six examples ported with them:
  `models_animation_gpu_skinning`, `models_bone_socket` (the one whose
  frames show the keyframe poses), `models_loading_gltf`,
  `models_animation_timing`, `models_animation_blending`,
  `models_animation_blend_custom`.
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
2. What is left of glTF and animations ([MODELS.md](MODELS.md)): glTF as
   text with external buffers, external image files, PNG files above
   Jonlib's 1 MiB input limit (`shaders_basic_pbr`), CUBICSPLINE samplers,
   IQM and M3D animations (`models_loading_iqm`, `models_loading_m3d`), and
   `shaders_shadowmap_rendering` (the robot with the framebuffer functions).
   Facts to keep:
   - The reference library is built with `SUPPORT_GPU_SKINNING` on, so an
     animated model is drawn in its bind pose on the software renderer;
     `UpdateModelAnimation` only fills `model.currentPose` and
     `model.boneMatrices` (the `ModelPose`). What reaches the screen is what
     an example reads itself (`models_bone_socket`).
   - `QuaternionSlerp` needs `acosf` and `sinf` for rotations more than
     about 36 degrees apart: the animation examples compare under
     `M.Glibc239Libm` only. They draw through a perspective camera, so on
     macOS every frame is a contract already; an Apple `acosf` would be
     needed to compare poses there.
   - `src/strtod.bend` is slow (about 0.1 ms a number natively, ten times
     that in JavaScript): convert a JSON number once and keep the value.
     Reading a joint's node for every keyframe made `robot.glb` take
     sixteen minutes in the gate.
   - `Bool.pick` is strict: a `%` by a count that may be 0 traps in the C
     lanes even in the branch not taken; guard with a `match`.
3. The remaining raygui controls, each a small additive piece of
   `jongui.bend` verified by the example that uses it: `GuiListViewEx` and
   `GuiGetFont` (`core_directory_files`, with the directory functions). Append whole
   definitions only and leave the file's header comment alone, or the piece
   runs in full. The probe's replayed events never reach `GetCharPressed`
   (typing into a text box cannot be compared natively) and no example's
   content overflows its scroll panel (the scroll bars are unverified).
4. Other pieces that each unblock examples:
   - IO in the loop is done (`J.Effects`, `Program.replay_io`, gate
     `driver-effects`; `core_storage_values`, `core_automation_events` and
     `shaders_shadowmap_rendering` use it). An example that writes files
     goes in the probe's `SCRATCH` (a directory a script, compared with the
     reference's afterwards); a script that would run undefined C from some
     frame goes in `UNDEFINED_FROM` and the reference stops before it.
     raylib ignores `PlayAutomationEvent` while it records, and that is the
     probe's input: `core_automation_events` can start a recording under
     the probe (the count it draws is compared) but not stop, export or
     play one. Those branches are ported and unverified; a driver that sets
     the input another way would be needed to compare them;
   - `core_custom_frame_control` is ported: its second `PollInputEvents`
     is `Core.poll_input_events` in the update (on the default build it
     makes every press an old one) and its timing after EndDrawing is the
     program's `after`, with `Core.wait_time`. The probe's scripted clocks
     follow the example's own wait (`OWN_WAIT`, `own_wait`) and the header
     wraps its `WaitTime` so that the sleep ends at raylib's destination;
   - the wall clock is done for the examples that read it
     (`shapes_digital_clock`, `shapes_clock_of_clocks`): Base has none, and
     they call the C library's `time()` and `localtime()`, so a port's setup
     takes the seconds of the day at InitWindow (the script's seed in the
     probe, whose header redirects `time()` in the example) and adds
     `Core.get_time`'s whole seconds. On the desktop their `run` passes 0:
     a `--time` argument read like `--frames` is still to be added.
     `core_custom_logging` is ported as its text: its callback only ever
     receives raylib's own log lines, which Jonlib does not emit;
   - the rlgl framebuffer functions are done for one color and one depth
     attachment (`Rlgl.Framebuffer`, docs/RLGL.md): `shaders_depth_writing`,
     `shaders_hybrid_rendering`, `shaders_depth_rendering` and
     `shaders_shadowmap_rendering` are ported. What rlsw does decides the
     model: a renderbuffer is a texture, a texture of a depth format is
     bound with texturing off (drawn in its tint), and a framebuffer
     without a color attachment is incomplete, so `swBegin`, `swClear` and
     `swDrawArrays` are refused while it is bound (`Canvas.blind`: the
     shadow pass draws nothing). A deferred renderer's G-buffer is
     incomplete too (float textures have no storage under OpenGL 1.1,
     channels 1 and 2 never attach) and is bound to draw with
     `Rlgl.enable_framebuffer_incomplete`: `shaders_deferred_rendering` is
     ported (the screen shows the lights alone; a zero albedo texture left
     bound makes the lit spheres invisible, as natively).
     `models_skybox_rendering` is ported too: `useHDR` is false, so its
     `GenTextureCubemap` (six framebuffers) never runs, and
     `LoadTextureCubemap` keeps id 0 on the software renderer: the cube is
     drawn white. No framebuffer example is left;
   - what the ten "ready" examples left need (triaged 2026-10-11;
     `text_unicode_emojis` is ported: a BMFont's baseSize is its
     lineHeight, and `DrawTextBoxed` there is byte-indexed, unlike the
     ASCII one of `examples/text_rectangle_bounds.bend`):
     `text_font_sdf` the C library's functions of `stbtt__solve_cubic` for
     SDF glyphs with curves (docs/FONTS.md, Gaps); `text_unicode_ranges` a
     7 MiB TTF and `shaders_basic_pbr` a 1.7 MiB PNG (the 1 MiB input
     limit); `textures_sprite_stacking` a 112x11468 image (the 4096 limit);
     `text_3d_drawing` is a long pure port and `models_decals` is ported
     (its `GenMeshDecal` as lists of triangles; the indexed-mesh branch is
     not taken by `LoadOBJ` meshes and is left out; its first button is
     drawn above the screen, as upstream); the IQM, VOX and M3D loaders are
     not written.
     (off the screen: a typo upstream, to keep). `core_screen_recording`
     needs a GIF encoder (msf_gif) besides `GetApplicationDirectory`, and
     `shaders_game_of_life` draws 2048x2048 worlds each frame;
   - `shaders_game_of_life` is ready but steps a 2048x2048 world through a
     shader each frame: too heavy for the JavaScript lane as written;
   - images beyond 4096 pixels on an axis (`textures_sprite_stacking`,
     parked in `.build/pending/`, not in the repository);
   - `GetFileModTime` (`shaders_hot_reloading`), `GetApplicationDirectory`
     (`core_screen_recording`); `models_decals` is ready since `UploadMesh`;
     `text_codepoints_loading` reads out of bounds natively and is ported
     as a refusal (`UNDEFINED_NATIVE`, docs/TEXT.md);
   - IQM, M3D and VOX model loading;
   - the audio device and streams (12+ examples; the reference build has
     `SUPPORT_MODULE_RAUDIO=OFF`), VR.
5. **Owed before the port is called done:** turn macOS back on
   (`MERGE_HOSTS` in `tools/ci_scope.py`, the `os:` line of
   `.github/workflows/checks.yml`), run both workflows manually on `main`
   and fix everything macOS finds. Until then the nightly runs (06:17 UTC,
   every host) show what macOS thinks of `main`: note a red one here.

## Known pitfalls (save time)

- **A background lander lives two hours at most**: a complete run that
  queues behind another one can outlast it (2026-10-11: the run finished
  green as the lander was stopped). Check the run and land by hand.
- **A compile can be killed for memory** when another session compiles at
  the same time in the 8 GiB container (exit -9 from the probe's `bun`):
  run it again.

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
