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

Coverage (`python3 tools/api_plan.py check`): raylib.h 582/600 partial
with the stack; raymath.h 146/146; rlgl.h 142/163; rcamera.h
12/12; rgestures.h 10/10. Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): **209/212 ported** with the stack (`audio_music_stream`, `audio_stream_effects` and `audio_mixed_processor` play `country.mp3` through the MP3 decoder and `audio_spectrum_visualizer` loads it whole; `core_screen_recording` writes its GIF with the msf_gif port; `core_directory_files` is handed its directory listings; `text_unicode_ranges` loads a 7 MiB font; `textures_sprite_stacking` a 112x11468 texture), 3 ready (two of them wait for a decoder, which the plan does not count: `mini1111.xm`, `target.ogg`), 0 waiting (three ports are documented refusals, their native examples being undefined behavior: `textures_image_kernel`, [CONVOLUTION.md](CONVOLUTION.md); `text_codepoints_loading`, [TEXT.md](TEXT.md); `audio_stream_callback`, [AUDIO.md](AUDIO.md)). No API
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
2. What is left of the model formats ([MODELS.md](MODELS.md)): glTF as
   text with external buffers, external image files and CUBICSPLINE
   samplers; M3D textures (inlined or looked up), generated normals, voxels
   and shapes. OBJ, binary glTF, VOX, IQM and M3D load, and every models
   example is ported.
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
     `Core.get_time`'s whole seconds. On the desktop their `run` reads a
     `--time` argument (`Desktop.clock_args`).
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
     7 MiB TTF (no limit was in its way: it is ported, below) and `shaders_basic_pbr` a 1.7 MiB PNG (the 1 MiB input
     limit of images); `textures_sprite_stacking` a 112x11468 image (the 4096 limit: ported since, below);
     `text_3d_drawing` is ported (the font texture held once around the
     3D texts through `Rlgl.set_texture`, the glyph metrics as a table by
     byte; no script types characters, so that branch is unverified) and
     `models_decals` is ported (its `GenMeshDecal` as lists of triangles; the indexed-mesh branch is
     not taken by `LoadOBJ` meshes and is left out; its first button is
     drawn above the screen, as upstream); `models_loading_vox` is ported
     over the VOX loader (`src/vox.bend`, gate `vox`: vox_loader reads a
     chunk header in the last four bytes of a file that ends with its
     palette, so such files are refused); `models_loading_iqm` is ported
     over the IQM loader (`src/iqm.bend`, gate `iqm`: model, skeleton and
     animations); the M3D loader is not written (`m3d.h` is its own decoder,
     6574 lines, with a compressed container). `shaders_hot_reloading` is ported with its file's
     modification time as a setup argument (`GetFileModTime` stays blocked
     on Base, like the directory functions `core_directory_files` needs).
     `core_screen_recording` is ported (below), and
     `shaders_game_of_life` draws 2048x2048 worlds each frame;
   - how the four "ready" examples left are blocked (surveyed 2026-10-11):
     `shaders_basic_pbr` is ported: its PNGs of up to 1.68 MiB needed the
     PNG cap raised to 2 MiB (a `PngFile` kind in `Image.file.limit`, the
     decoder's two caps in `src/png.bend`, and `Inflate.decompress.within`
     so that the public `Compression.decompress` keeps 1 MiB; gates
     `png-format` at 55 minutes and `png-file` carry the cap cases).
     `textures_sprite_stacking` needed a 112x11468 image; the 4096 limit is
     in about sixty places of `jonlib.bend` and every codec, and stays
     (the example is ported through `LoadTexture`'s strips, below). `text_unicode_ranges` is ported (below). `text_font_sdf`
     needs binary64 acos and pow for `stbtt__solve_cubic` (cos exists:
     `src/lgpl/sin.bend`). `models_loading_m3d` is ported over the M3D loader
     (`src/m3d.bend`, gate `m3d`: the binary variant's container, chunks,
     meshes, materials, skeleton and `m3d_pose` animations; textures,
     generated normals, voxels, shapes and procedural chunks are refusals,
     so `seagull.m3d`, which inlines its texture, is refused). Things the
     port found: no error code the binary importer sets is fatal; the
     ASCII variant is not built into raylib; a map property without a name
     is dropped without a file lookup (cesium_man's case); `m3d_pose`'s
     interpolation factor is changed by each orientation it interpolates
     and carries to the next bone; the importer's bone matrices read
     values it never wrote for a parent that comes later (unobserved by
     raylib).
     `shaders_game_of_life`: below;
   - `shaders_game_of_life` is ported (2026-10-12). Its frames cost the
     JavaScript lane about a minute each whatever they do (two 2048x2048
     render textures are in play; where the time goes is not measured:
     `Draw.texture_pro` from a 2048x2048 texture each frame is the first
     suspect), so its CI script has nine frames; scripts of 22 and 18
     frames (zoom buttons, Slower, a run every second frame) passed
     locally. Its Random preset (4.2 million `GetRandomValue` draws) is
     ported and not scripted;
   - images beyond 4096 pixels on an axis (as images; a texture's PNG may
     be a strip of up to 16384, see `textures_sprite_stacking` below);
   - `GetFileModTime` (`shaders_hot_reloading`), `GetApplicationDirectory`
     (`core_screen_recording`); `models_decals` is ready since `UploadMesh`;
     `text_codepoints_loading` reads out of bounds natively and is ported
     as a refusal (`UNDEFINED_NATIVE`, docs/TEXT.md);
   - the audio device and streams (12+ examples; the reference build has
     `SUPPORT_MODULE_RAUDIO=OFF`), VR. What the audio examples load
     (surveyed 2026-10-11): `textures_sprite_button`,
     `textures_sprite_explosion`, `audio_sound_multi` and
     `audio_sound_positioning` only .wav files (decoded already,
     docs/AUDIO.md), and only the last shows audio state on screen
     (`IsSoundPlaying`); `audio_raw_stream`, `audio_stream_callback` and
     `audio_amp_envelope` no file (`IsAudioStreamProcessed`); the others an
     .mp3 (dr_mp3), an .ogg (stb_vorbis) or an .xm (jar_xm): decoders not
     ported. **The device and sounds are in** (`AudioDevice.*`, `Sound.*`;
     Base already has an `Audio` type, so the state could not take that name;
     docs/AUDIO.md, gate `sound`), and so is the mixer at the device rate
     (`AudioDevice.mix`, one data callback: the reference asks the stopped
     device for it with `ma_device_handle_backend_data_callback`); there is
     no clock. The
     reference of `tools/sound_probe.py` is `#include "raudio.c"` in the
     reference program (the library keeps `SUPPORT_MODULE_RAUDIO=OFF`)
     with `-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS -DMA_ENABLE_NULL`: the null
     backend opens on every host at 48000 Hz, and the program reads
     `AUDIO` and the buffers and calls `ma_device_stop` after
     `InitAudioDevice`. Found on the way: `Wave.format` overflowed the
     JavaScript stack on a wave of 13619 frames (its loops over samples
     were not tail calls; they are now, `src/convert.bend`); a device
     opened over a playing buffer mixes it before the program can stop it
     (no probe case does that). The examples whose frames do not depend
     on audio are ported with raudio.c compiled beside the native example
     the same way (`AUDIO` in `tools/examples_probe.py`):
     `textures_sprite_button`, `textures_sprite_explosion`,
     `audio_sound_multi` (the first of the new `examples-audio` gate) and
     `audio_sound_positioning` (it asks `IsSoundPlaying` every frame, but
     draws nothing from it: the port plays the sound once) are in. `audio_sound_loading`
     is listed ready but also loads an .ogg. Pitched buffers are mixed too
     (`src/mixer.bend`: raudio's read loop with its input estimate and its
     8-frame residual over the resampler as a stream). **A buffer's
     converter has the first-order filter** (`ma_lpf1`, coefficient
     `(float)exp(-pi*min/max)`: `ma_data_converter_config_init` leaves
     `lpfOrder` at 1; only `ma_convert_frames`, so `WaveFormat` and
     `LoadSoundFromWave`, raises it to 4). `Lowpass.coefficient1` brackets
     `exp` the way the biquads' `sin` is. **The clock is in** (`AudioClock`, docs/AUDIO.md): for
     the examples in `AUDIO_CLOCK` (`tools/examples_probe.py`) the
     reference compiles `tools/reference/audio_clock.c` (raudio.c plus two
     probe functions) instead of raudio.c alone; the example's
     `InitAudioDevice` (a shim macro under `-DJONLIB_EXAMPLE_AUDIO_CLOCK`)
     stops the device's thread and notes the scripted clock, and the
     `WindowShouldClose` hook (the start of each loop pass, before the
     example reads `IsSoundPlaying` or `IsAudioStreamProcessed`) asks for
     every whole period (480 frames, 10 ms) since. A ported example keeps a
     `J.AudioClock` beside its device and calls `AudioClock.advance` with
     `Core.get_time(core)` first in its update (`audio_raw_stream`; halving
     the clock's rate in Jonlib makes its replay fail at frame 4, so the
     frames do depend on it). The examples that never show audio state
     still let the native device thread run free. **Audio streams play**
     (`AudioStream.*`; a head's `Mixer.Feed` says what a buffer plays):
     `Mixer.turn` has raudio's stream branch of
     `ReadAudioBufferFramesInInternalFormat` (the halves, looping, the
     zero fill that counts as frames read) and `ma_data_converter`'s
     pipeline as a stream (format first, then the resampler on
     min(channels, 2) channels before or after `ma_channel_converter`,
     in passes through 4096-byte temporaries). Three things cost time
     there: raudio reads at most the frames its 4096-byte input buffer
     holds, so 512 only for a sound (2048 of a 16-bit mono stream: the
     residual differs by a frame otherwise); with one channel or more
     than two a pass takes no more input than
     `ma_linear_resampler_get_required_input_frame_count`; and the
     callback runs with **denormals disabled** (DAZ/FTZ on x86-64, the
     reference): `Mixer.fadd/fsub/fmul/fdiv` flush operands and results,
     and every operation of the callback goes through them (a filter's
     tail reaches exact zeros natively). AArch64 keeps subnormals there:
     a profile for the macOS validation to settle. `audio_raw_stream` is ported. **Stream callbacks are in**
     (`AudioStream.set_callback`, docs/AUDIO.md): raudio calls the
     function with its guess of the converter's input each time the
     stream is read, and those counts depend on rates and converter
     state only, never on a sample. So no function is kept and the mixer
     stays first-order: `AudioDevice.asks` runs the turn on zeros to
     learn the counts (`Mixer.Turn.asked`), the program answers, and
     `AudioDevice.mix_answered` runs it again on the answers
     (`AudioClock.advance_answering` does that for each period with a
     Bend function of the program's state). The sound probe gives raylib
     a C callback per slot and compares the asks too. **Processors are
     in** the same way (`AudioProcessors`, `AudioDevice.mix_processed`,
     `AudioClock.advance_processing`): raudio calls a stream's processors
     on each run of at most 512 mixed-format frames before
     `MixAudioFrames`, and the mixed ones on the whole output, so the
     program's function is called from the glue in `jonlib.bend`, not from
     `src/mixer.bend` (a buffer's runs are its frames split by 512). The
     examples that use them, `audio_stream_effects` and
     `audio_mixed_processor`, also play `country.mp3` (both ported, see
     below). Templates (`~answer`, `~process`) must be closed terms:
     everything a callback needs goes in the program state it takes and
     returns. **Music streams are in over WAV** (`Music.*`,
     docs/AUDIO.md): the stream, raudio's `UpdateMusicStream` over the
     two halves with `framesProcessed`, stop, seek and the time played;
     the decoder is a `Music.Context` constructor (`MusicWav{samples,
     at}`: the whole file decoded at load, by `Wav.decode` for 16/24-bit
     files and `Wav.decode.wide` for 32-bit ones). A new format is a new
     constructor with its read (`Music.read`), rewind and seek, and a
     `case` in `Music.load_from_memory`: QOA went in that way
     (`MusicQoa`; `qoaplay.c` reads like dr_wav once the file is decoded
     whole, and seeks to QOA frames of 5120 samples). MP3 is next and is
     not small: `dr_mp3.h` (minimp3) in float, whose frames must be
     decoded as the music asks for them (`country.mp3` is 1.4 MiB, about
     a minute and a half: too long to decode whole in the JavaScript
     lane, so `LoadWave` of it, which `audio_spectrum_visualizer` does,
     needs more than the decoder). **A plan for it, in pieces that each
     have their own reference dump** (surveyed 2026-10-12; piece (a) is
     in: `src/mp3.bend`, gate `mp3`, docs/AUDIO.md): `country.mp3` is MPEG-1 Layer III, 128 kbit/s, 44100
     Hz, joint stereo, and starts with an Info/LAME frame, so
     `drmp3_init_internal`'s tag handling matters (ID3v1/APE at the end,
     ID3v2 at the start, the Xing/Info frame skipped, LAME's delay and
     padding trimmed; lines 2943-3297). (a) headers and sync:
     `drmp3_hdr_*`, `drmp3d_match_frame`, `drmp3d_find_frame`, and the
     scan that gives `drmp3_get_pcm_frame_count` (what
     `music.frameCount` is); integers only. (b) Layer III side info, the
     bit reservoir, scalefactors and Huffman: `drmp3_L3_read_side_info`
     to `drmp3_L3_huffman`, which already writes floats (`pow_43`,
     `ldexp_q2`). (c) stereo, reorder, antialias and the IMDCT
     (`drmp3_L3_midside_stereo` to `drmp3_L3_imdct_gr`). (d) the
     polyphase synthesis (`drmp3d_DCT_II`, `drmp3d_synth`), then
     `drmp3_read_pcm_frames_f32` and seeking. raylib does not define
     `DR_MP3_NO_SIMD`: the reference runs the SSE paths, so each float
     stage has to be compared with the reference as built, not with the
     scalar C. Layers I and II decode in dr_mp3 too and can be refused
     at first. The tables (Huffman, scalefactor bands,
     windows, `g_win`, `g_sec`) are float and integer literals to carry
     over as bit patterns. There is no MP3 encoder here: test files are
     `country.mp3`, slices of its frames and mutations of them. Measured
     with a small C program over dr_mp3 (2026-10-12): `country.mp3` is
     4125934 frames (3583 MP3 frames of 1152, less LAME's delay of 1105
     and padding of 577, both from the Info frame: with a Xing/Info
     `FRAMES` field the count is that product and no scan is made;
     without one `drmp3_get_pcm_frame_count` decodes every header); and
     the float samples of the SSE build and of `-DDR_MP3_NO_SIMD`
     **differ** (the reference is the SSE build; `-ffp-contract` changes
     nothing there), so the port follows the SSE branches' operation
     order. `drmp3_init` decodes the first frame whole, and the file path
     reads through a 64 KiB window refilled below 16 KiB
     (`drmp3_decode_next_frame_ex__callbacks`), which only matters for
     how far `drmp3d_match_frame` can look on a damaged stream. The
     bitstream is read forward only, so lists do (no `Array`). **What
     the next pieces need, found while writing (a):** the tables can be
     taken from `dr_mp3.h` by a script that copies each
     `static const ... = {...};` initializer into a C program and prints
     ints as they are and floats as their bits (so each literal is
     converted as the compiler converts it): 25 tables, among them
     `tabs` (2164 Huffman entries), `g_drmp3_pow43` (145), `g_win` (240),
     `g_sec` (24), `g_mdct_window` (36), `g_twid9`, `g_twid3`, `g_aa`,
     `g_pan`, `g_expfrac`; a generated `src/mp3_tables.bend` with a
     staleness check, as the enumerations have, would fit. `tabs` is
     indexed per codebook (`tabindex`), so each region can carry its
     codebook's own sublist. In the SSE build `drmp3d_DCT_II` works on
     four time columns at once but each column alone, so it ports as one
     function of a column's 32 values in the SSE branch's order. A
     granule switches windows with `region_count[2]` left as the slot
     had it; its second region is 255 bands, every band there is, so the
     third is never read (`side.gr` gives 255). In (a) the probe caught
     two things worth remembering: a helper that indexes with
     `Bool.pick` over its own recursion walks to the end of the list (the
     whole file), and the test corpus needs the real file read through
     `Files.load_data`, because 1.5 MB of literals does not compile.
     **Piece (b) is in** (`src/mp3_layer3.bend`, `src/mp3_tables.bend`,
     `tools/mp3_tables.py`, gate `mp3-layer3`, docs/AUDIO.md): a frame
     decodes as far as its granules' 576 values per channel, bit for bit.
     What it taught: (1) a nullary def that is a list literal builds the
     list at every call, so a table read in a loop is named once outside
     it and passed down (`pow`, `book`); a codebook is rebuilt only when
     a region begins. (2) the decoder's scratch is state: the main data
     array keeps earlier frames' bytes past the current frame's (Huffman
     reads them on damaged granules), the 40 scales keep entries a
     granule does not write, and `drmp3_L3_intensity_stereo` writes the
     right channel's last intensity positions; all three are in
     `Mp3L3.Decoder` and in the gate's state hash. For (c):
     `drmp3_L3_intensity_stereo` is called whenever the header's bit
     0x10 is set, in mono frames too, where it processes the mono
     channel against 576 zeros and reads `gr[1].scalefac_compress` of
     the next slot of `gr_info[4]`, which is also scratch that persists
     (a mono MPEG-1 frame's second granule reads slot 2: an earlier
     stereo frame's, or zeros): the stale granule information has to be
     carried. (3) raylib does not define `DR_MP3_FLOAT_OUTPUT`: the
     synthesis writes 16-bit samples (`drmp3d_scale_pcm`, SSE
     `_mm_cvtps_epi32` and saturating packs) and
     `drmp3_read_pcm_frames_f32` converts them to floats, so (d)'s
     output is int16 and the float read is a division by 32768. (4) the
     gate's synthetic frames (random side information and main data, no
     encoder) reach every MPEG version, block type and table; later
     stages can reuse `mp3_layer3_probe.synthetic`, though random
     values will be large, so watch for infinities and NaNs (whose bits
     differ between JavaScript and C) before comparing floats there.
     (5) dr_mp3 has a bug the synthetic frames found: a mixed block at
     8000 Hz is reordered from value 72 (`n_long_bands` 4) with a band
     table whose long part is 48 values, so `drmp3_L3_reorder` writes 24
     floats past `grbuf[ch]` (over the right channel for the left, over
     `scf` for the right). Refused in both the port and the gate's
     reference (`reorder.inside`); (c) must keep that refusal where the
     reorder is ported. **The stereo step is in too** (same module and
     gate; the gate's hash is taken after it): what was listed for (c)
     above about mono frames and the stale slot is done
     (`Decoder.compress`, `stereo.mode`). **And (c) is complete**: the
     reorder, the alias reduction, the IMDCT with its overlap (two more
     arrays of decoder state, 288 floats a channel) and the sign change
     (`Mp3L3.filter`); `Mp3L3.decode` gives 32 subbands of 18 samples a
     channel a granule, and the gate hashes them. Their SSE paths
     compute each element with the scalar formula, so nothing in (c)
     depended on the vector order; that begins in (d): `drmp3d_DCT_II`
     (the SSE branch works on four time columns, each alone), then
     `drmp3d_synth_pair` and `drmp3d_synth` with `g_win`, 16-bit output
     through `drmp3d_scale_pcm` or the SSE `_mm_cvtps_epi32` and packs
     (rounding to nearest even, saturating), and `qmf_state` (960
     floats) as the last decoder state. For (d) the per-frame output to
     compare is the int16 PCM itself. Negation must turn the sign bit
     (`neg` in the module): `0 - x` loses a zero's sign and the hashes
     are of bits. **(d)'s decoder is in**: `Mp3L3.decode` gives the
     frame's 16-bit PCM (`synth.granule`), equal to dr_mp3's on every
     frame of `country.mp3` and on the synthetic corpus. Left of the
     plan: the `Wave`/`Sound` loaders (`LoadWave` is
     `drmp3_open_memory_and_read_pcm_frames_f32`), the last example
     that plays `country.mp3`, and Layers I and II (refused now).
     `audio_music_stream` and `audio_stream_effects` are ported, with
     the device's clock and their frames compared with the native
     examples' (the effects are stream processors computing with
     `src/mixer.bend`'s flush-to-zero operations, which the example
     imports: there is no public name for them yet).
     **`audio_mixed_processor` is ported** too: its processor on the
     device's mix is `powf(fabsf(x), exponent)` of every sample, times
     its sign, with the exponent moved by keys from 0.5 to 3 in steps
     of 0.05, and it keeps the average of each of its last 400 calls,
     which the frame draws as bars. The power is `M.Libm.powf`
     (`Power.powf`, gate `powf`, docs/MATH.md): glibc 2.39's `powf` for
     a non-negative finite base and a finite exponent, computed as both
     of glibc's builds (the FMA one fuses nine `a*b + c`; read from the
     library's code) and answered where they agree. The builds differ
     on about 7 pairs in ten billion (measured: 30 billion pairs, the
     models equal to their builds on all of them); `powf` is `None`
     there and the example refuses that frame and every later one,
     since the port cannot know which build the reference host runs.
     The base is `fabsf` of a mixed sample: 0 or a normal float (the
     callback flushes subnormals), never negative, and a subnormal
     power is 0 there. Each `powf` is two software binary64
     evaluations, 960 a callback: slow on the JavaScript lane, so the
     script is twelve frames.
     **`Music` plays MP3** (`MusicMp3{player}` in `jonlib.bend`, cases
     `music-mp3` and `music-mp3-counted` of the sound gate, whose model
     takes the stream's readable frames from the reference and keeps
     dr_mp3's count for the seeks). **The stream is in** (`src/mp3_stream.bend`, gate
     `mp3-stream`, docs/AUDIO.md): `Mp3S.open`, `read.s16`/`read.f32`,
     `rewind`, `seek`, `total`, each returning the player after it. For
     the music: `LoadMusicStream` is `drmp3_init_file`, a stream of
     (sample rate, 32, channels) and `frameCount` from
     `drmp3_get_pcm_frame_count` (which moves an untagged stream:
     `Mp3S.total` returns the player); `UpdateMusicStream` reads
     `drmp3_read_pcm_frames_f32` and at the end of a looping music
     calls `drmp3_seek_to_start_of_stream`; `StopMusicStream` the same;
     `SeekMusicStream` is `drmp3_seek_to_pcm_frame(positionInFrames)`,
     whose frame is counted with the delay (docs/AUDIO.md). `LoadWave`
     is `drmp3_open_memory_and_read_pcm_frames_f32`: the whole file,
     about six minutes for `country.mp3` on the JavaScript target at 95
     ms a frame, so `audio_spectrum_visualizer` needs the faster
     floats first.
     **Speed on the JavaScript target.** The module keeps floats in
     lists as U32 bits and converts at each use with `float(bits)`.
     Written `U32{word} = value; F32{word}` that compiles there to a
     32-node bit list and two typed arrays per call: about 50000 a
     frame, 185 ms a frame, 11 minutes for `country.mp3` (the C lanes
     are much faster). `float` now builds a finite float by exact
     arithmetic (`float.scaled`: significand times a power of two) and
     a frame takes about 95 ms. The rest is `F32.bits` (two typed
     arrays a call there) and list walking. The larger fix is lists of
     `F32` (`+List<F32>`) for the values, the scales, the overlap and
     the rows, with the tables converted once a frame and `F32.bits`
     only where integers are needed (the sample conversion, the
     probe's hashes); `F32.neg` is a true negation on both targets and
     would replace `neg`. Then the gate can take the whole file
     again (it has two 200-frame slices now), and music examples
     become practical in the JavaScript lane. `List.drop(xs, 1n)` in a
     loop is also slow there (a big-integer count): the module has
     `tail`.
     Measured: scalefactors and Huffman take about 12 ms a frame in the
     JavaScript lane (list steps through the trampoline). `audio_stream_callback` itself reads
     `buffer[SAMPLE_RATE]`, one float past its array, for the last
     column of its wave in every frame (AddressSanitizer agrees): its
     port is a refusal (`UNDEFINED_NATIVE`, docs/AUDIO.md). `audio_spectrum_visualizer` is listed ready but loads
     `country.mp3` with `LoadWave`: it waits for the MP3 decoder;
     (3) music (`LoadMusicStream`) and its decoders:
     dr_mp3, stb_vorbis, jar_xm, jar_mod, dr_flac.
   - **`core_screen_recording` is ported** over `src/msf_gif.bend`
     (`begin`, `frame`, `finish`; gate `msf-gif`; docs/GIF-ENCODER.md):
     Ctrl+R starts and ends a recording, every sixth frame the screen
     goes to the encoder with a delay of 0 and a depth of 16, and the end
     saves `screenrecording.gif`, which the probe compares byte for byte
     with the reference's. Three things are settled in the probe's shim
     (`tools/reference/example_driver.h`), as `GetFileModTime` was: the
     memory platform's `LoadImageFromScreen` gives the rows bottom-up
     with red and blue swapped (docs/FRAME.md), so the hook hands the
     example the desktop's image, which `Frame.load_image_from_screen`
     follows; `GetApplicationDirectory` is not in Base, so the port
     takes the directory as a setup argument and the hook answers the
     script's directory. The example reads the screen before
     `BeginDrawing`: it records the frame drawn before (an effects
     program's update takes the frame). Its 18-frame script takes the
     JavaScript lane about ten minutes (the C lanes take seconds). Where
     the time goes is not measured: each frame draws 255 lines and 256
     circles of 36 segments, and two frames go through the encoder. The
     circle's return to the left side after 180 frames is not scripted.
   - **`core_directory_files` is ported** over `Gui.list_view_ex`
     (raygui's `GuiListViewEx`, docs/GUI.md). Base has no directory
     listing, so the port is handed the listings (docs/FILES.md) and the
     probe reads them where the reference does (`LISTED`, `WORKING` in
     `tools/examples_probe.py`; a script's files may now be in
     directories). Two things the port found: raylib's `IsFileExtension`
     copies up to 16 bytes of the extension into a `char[16]` and reads
     it as a string, so a file without an extension below a directory
     with a dot in its name is undefined (a script covers the refusal);
     and on the memory platform a mouse button's previous state is never
     registered, so `IsMouseButtonReleased` never fires for it and
     `IsMouseButtonPressed` fires every frame it is held: a script
     presses a `GuiButton` with a touch point (`TOUCH_DOWN`, `TOUCH_UP`),
     whose previous state is registered. Scripts of earlier raygui
     examples that click buttons with the mouse button do not press
     them: worth a pass (`core_clipboard_text`'s `buttons` script says
     its buttons act).
   - **`Wave` and `Sound` load MP3 files** (`Wave.decode(".mp3")`, gate
     `mp3-wave`, docs/AUDIO.md). dr_mp3 reads a memory stream
     (`LoadWave`, `LoadMusicStreamFromMemory`) with another function than
     a file's (`LoadMusicStream`), and the two end a stream with an
     ID3v1 tag differently: `Mp3S.open.memory` beside `Mp3S.open`, and
     `Music.load_from_memory` now opens the memory way (it shared the
     file's before). The `mp3-stream` gate opens every file both ways.
     What `audio_spectrum_visualizer` still needs: its FFT (`cosf`,
     `sinf`, `logf`, `sqrtf`), and time: `LoadWave` of the whole
     `country.mp3` is about six minutes in the JavaScript lane.
   - **`text_unicode_ranges` is ported.** There was no input limit in
     its way (earlier notes here said 1 MiB; `Files.load_data` takes any
     file and `FontData.load` any font): Noto Sans TC's 7 MiB and its
     format 12 character map load as they are. The script takes the
     first of the four choices (three loads of the file, 212 glyphs);
     the whole replay is about nine minutes on this machine, most of it
     the JavaScript lane. The other choices are not scripted.
   - **`textures_sprite_stacking` is ported.** Its `booth.png` is
     112x11468, past an image's 4096 on a side. The limit was not lifted
     in its sixty places: only `LoadTexture` takes a longer PNG (up to
     16384 on a side, no more than 4096x4096 pixels; `Png.decode.wide`,
     docs/TEXTURES.md), and the decoded image goes nowhere but into the
     texture, which had no size rule of its own. The PNG decoder takes
     its side limit as a parameter of the parse, so that an image is
     refused at the same point as before. The `window` gate has the
     strips. The example's three frames take the JavaScript lane about
     ten minutes (122 textured quads of 336x282 pixels a frame; four
     frames took fourteen, too near the gate's 30-minute lane limit for a
     slower runner).
   - **`audio_spectrum_visualizer` is ported.** The whole `country.mp3`
     is loaded as a wave (7.5 minutes in the JavaScript lane, 27 seconds
     natively: 4125934 frames) and its spectrum computed every frame. No
     frame shows the spectrum (the software renderer runs no shader), so
     the example's replay is six plain frames and the transform has a
     gate of its own, `spectrum`, whose reference includes the example's
     source with `main` renamed and runs its own `CaptureFrame` and
     `RenderFrame` (docs/AUDIO.md). That way of reaching an example's
     static functions is there for any other example whose work no frame
     shows.
     Its JavaScript lane held 6.9 GB at its peak here (the wave's 8.2
     million samples as lists, twice): fine on a 16 GB runner, a risk on
     a smaller one, macOS included when it comes back. A wave kept as an
     array, or decoded as it is consumed, would bring it down.
   - **The three examples left**, with what each was found to need:
     - `text_font_sdf`. `LoadFontData(FONT_SDF)` is
       `stbtt_GetCodepointSDF`, whose `stbtt__solve_cubic` calls the C
       library's binary64 `pow`, `acos` and `cos` and narrows them to
       float. `cos` is in (`src/lgpl/sin.bend`). `pow` is the same Arm
       routine family as `powf` (two builds, with and without fused
       products); `acos` is IBM's accurate one (LGPL, tables). Then
       `stbtt_GetGlyphSDF` itself, and `GenImageFontAtlas`'s pack
       method 1.
     - `audio_sound_loading`. `LoadSound("target.ogg")`: stb_vorbis
       (`src/external/stb_vorbis.c`, 5584 lines; `target.ogg` is 13 KB).
       No frame depends on the sound. A plan in pieces, each with a gate
       whose reference includes stb_vorbis.c and reads its structures:
       (1) the Ogg pages and the three header packets (`start_decoder`:
       identification, comments, then the setup's codebooks, floors,
       residues, mappings and modes, with `compute_codewords`, the sorted
       and accelerated Huffman tables and the pre-expanded
       multiplicands); (2) a packet's decode up to the residue
       (`vorbis_decode_packet_rest`, `do_floor`, `decode_residue` and the
       `codebook_decode*` family); (3) `inverse_mdct` and the window and
       overlap, in float, in stb's order; (4)
       `stb_vorbis_decode_memory` and
       `stb_vorbis_get_samples_short_interleaved` as `Wave.decode(".ogg")`,
       then the music stream. Things already seen in the setup: the
       C library's binary64 functions are called there (`float32_unpack`
       is `ldexp`; `lookup1_values` is `floor(exp(log(entries)/dim))`
       corrected with `pow` on small integers, whose answer is the
       integer root: exact integer arithmetic gives it wherever the
       library's error is below one unit, which its documentation says);
       `setup_malloc` sizes come from the file (`len + 1` for a vendor
       string of `len` up to 2^32 - 1); the corpus is one file and edits
       of it, as with MP3 (there is no encoder here).
       Read since (2026-10-13), for whoever starts it:
       - **Done: the codebook builders** (`src/vorbis_codebook.bend`,
         gate `vorbis-codebook`, docs/AUDIO.md "Ogg Vorbis"):
         `compute_codewords`, `compute_sorted_huffman`,
         `compute_accelerated_huffman`, `float32_unpack`, `bit_reverse`,
         `ilog`, compared by a reference that includes stb_vorbis.c and
         calls its static functions on a `Codebook` filled as
         `start_decoder` fills it. `V.book.of(lengths, sparse)` is what the
         setup parser will call per codebook; a length of 32 never reaches
         it (`start_decoder` refuses it as it reads).
       - **Done: `lookup1_values`** (`V.lookup1.values`, same gate). It
         is not the integer root: it estimates
         `floor(exp((float)log((float)entries)/dim))` and corrects it by
         one upward only. The port answers the root where the estimate
         is surely within the correction (every codebook of up to 2^19
         entries; larger ones of 2 dimensions or more away from a perfect
         power) and `None` elsewhere, and where the C code converts a
         power of 2^31 or more to int (31 dimensions or more; a root of
         2 in 20 to 23 dimensions), which is undefined. Checked for all
         24 bits of entries by
         `tools/reference/stb_vorbis_lookup1` (about two minutes, by
         hand: `run_exhaustive.sh <raylib> <work>`). The setup must turn
         `None` into a refusal of its own, not into
         `VORBIS_invalid_setup`. Modelling the C library's binary64
         `log` and `exp` would answer the unsure pairs (the same
         functions `text_font_sdf`'s `pow` is made of).
       - **Done: the Ogg pages, packets and bits**
         (`src/vorbis_ogg.bend`, gate `vorbis-ogg`, docs/AUDIO.md "The
         data"): a `Reader` with stb_vorbis's state and its functions one
         for one, each answering in `Reader.value`. The gate drives
         stb_vorbis's static functions by scripts and compares all the
         state after each call; the same harness (a script of calls, a
         digest of the struct) will do for whatever is added to the
         reader (`prep_huffman`, the codebook decodes, the seeks).
         A judgment made there, to keep or to overturn: a pointer moved
         past the data's end and only compared (`skip`), and the int -1
         of an `EOP` shifted left (`get32_packet`), are followed as every
         compiler does them, not refused; reads outside memory and
         results that differ between machines are refused.
       - **Done: `start_decoder` as far as the codebooks**
         (`src/vorbis_setup.bend`, gate `vorbis-setup`, docs/AUDIO.md
         "The setup"): `S.setup.codebooks(bytes)` gives a status
         (`Going`, `Failed{stb's code}`, `Refused{why}`), the
         identification's fields and the codebooks with their expanded
         lookups. The gate's reference is `start_decoder` itself; the
         stage it failed in is told by `floor_config` being allocated or
         not. The probe has its own reading of the headers in Python
         (`model`), which says which files the port refuses and is
         checked against stb_vorbis on the others: extend both as the
         setup grows (`residue_config`, `mapping` tell the next stages).
         Learned there: a function that keeps many `Reader`s alive at
         once does not compile ("an arity over 255": records are
         flattened into words, a `Reader` is 25) though it type-checks;
         take each reader's values as soon as it is read.
       - **Done: the rest of the setup header**
         (`src/vorbis_maps.bend`, same gate): floors (type 1, with
         `sorted_order` and `neighbors`), residues, mappings, modes,
         `first_audio_page_offset`, and the stage a setup fails in.
         `M.maps.read(S.setup.codebooks(bytes))` is `start_decoder`
         without its tables. Two more refusals: a sixteenth submap
         (stb_vorbis's arrays hold 15) and a classbook of more than 2^24
         entries times dimensions.
       - **Done: `init_blocksize`'s tables** (`src/vorbis_tables.bend`,
         gate `vorbis-tables`, docs/AUDIO.md "The transform's tables"):
         `T.tables.for(libm, n)`. Found there: stb_vorbis defines a
         *float* `M_PI` where `<math.h>` has none, so a reference must be
         compiled as raylib is (`-D_DEFAULT_SOURCE`), or its tables are
         others; a variable named `C`, `L` or `R` after including
         stb_vorbis.c is one of its macros. Under profiles other than
         `Glibc239Libm` the port gives the floats that are sure whatever
         the library (a two-unit margin from the rounding boundary): on
         Linux every one is. **On macOS this gate is the test of that
         rule against Apple's library; if a value differs there, the rule
         is wrong for that library and Vorbis must be refused under
         `AppleLibm` instead.**
       - **Done: the store and the codebook decodes** (`src/store.bend`:
         `Row` of floats and `Index` of words, binary trees that are
         values; `src/vorbis_decode.bend`, gate `vorbis-decode`,
         docs/AUDIO.md "Symbols and vectors"): `huffman.prep`,
         `decode.raw`, `decode.symbol`, `raw.decode`, `vector.decode`,
         `vector.step` on `Coder`s made by `coder.of`. The gate is the
         Ogg gate's script harness after `start_decoder`, with a float
         buffer in the digest. Port refusals are the reader's error 1001
         (`O.refused`): the decoder above must stop on it.
       - **Done: `inverse_mdct`** (`src/vorbis_mdct.bend`, gate
         `vorbis-mdct`): `X.transform(row, X.factors.of(tables), n)`,
         bit for bit on every block size. A reference that calls it
         needs only `vorbis_init` and `init_blocksize`, no stream.
       - **Done: the residues** (`src/vorbis_residue.bend`, gate
         `vorbis-residue`): `Rs.residue.decode` and `Rs.weave.decode`,
         with `store`'s `Row.cleared` and a `count` of values in
         `D.Coder`. One more refusal (1001): woven vectors cut at the
         end of the floats can take values past the codebook's.
       - Next, in order:
         (a) `vorbis_decode_packet` (`vorbis_decode_initial`, the floors'
         Y values, `do_floor` with `inverse_db_table`, the residues, the
         coupling, the transform), compared by the channel buffers
         after a call of the static function on a started decoder.
         Seen already: `do_floor` ends with `inverse_db_table[ly]`
         unmasked, `ly` being the last point's Y times the multiplier,
         which passes 255 when a floor's subclass codebook has more
         entries than the floor's range (256, 128, 86 or 64 by
         multiplier): a read past the table, to refuse. raylib's
         target.ogg has no such codebook, so its packets can be damaged
         freely for a corpus (its residues end with the block and their
         codebooks' dimensions divide the partitions: no cut either);
         (b)
         `vorbis_finish_frame`, the samples and
         `stb_vorbis_stream_length_in_samples` (which seeks:
         `vorbis_find_page`, the page CRC); (c) `Wave.decode(".ogg")`,
         the sound, the music stream, `audio_sound_loading`.
       - `float32_unpack` is exact arithmetic (a 21-bit mantissa scaled
         by a power of two and narrowed once).
       - The transform's tables are binary64: `compute_twiddle_factors`
         is `cos` and `sin` of `4*k*M_PI/n` and the like narrowed to
         float, `compute_window` is
         `sin(0.5*M_PI*square((float)sin((i + 0.5)/n2*0.5*M_PI)))`. The
         glibc 2.39 binary64 `sin` and `cos` are in
         (`src/lgpl/sin.bend`); up to about 14000 of them for a pair of
         block sizes.
       - `get_bits` answers 0 from a packet's end on, and the setup goes
         on reading zeros until one of its own checks fails or it ends:
         `f->error` set by the page reader meanwhile is overwritten or
         kept as it is, and a setup can succeed with it set.
       - The memory reader moves its pointer past the data's end (`skip`)
         before it notes the end: a truncated header is undefined there.
     - `audio_module_playing`. `LoadMusicStream("mini1111.xm")`: jar_xm
       (its float mixer and its tables); the frame draws the time
       played.
5. **Owed before the port is called done:** turn macOS back on
   (`MERGE_HOSTS` in `tools/ci_scope.py`, the `os:` line of
   `.github/workflows/checks.yml`), run both workflows manually on `main`
   and fix everything macOS finds. Until then the nightly runs (06:17 UTC,
   every host) show what macOS thinks of `main`: note a red one here.

## Known pitfalls (save time)

- **`jonlib.bend` ends with the generated enumerations** ("Header
  enumerations", `tools/enums_probe.py --write`): a section appended after
  them fails the `enums` gate ("the generated jonlib.bend section is
  stale") and nothing else (2026-10-12: the VR section passed the proof,
  its probe and `conformance` locally and failed CI shard 4). New sections
  go above that rule; run `--only enums` after adding one.
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
  diagnostic gate `bend-defects`). Never write it: choose Bools with a def of
  your own (`either` in `src/wav.bend` and `src/mixer.bend`). The JavaScript
  lane is right, so a probe whose first lane passes and whose native lane
  differs in one flag is this (it cost the stream reads an hour).
- **Long files on the JavaScript lane:** a decoder whose gate only saw short
  files can still overflow there on a real one. `Qoa.decode` did on
  raylib's `target.qoa` (44100 stereo frames): `List.append` onto the
  samples so far and `List.take` of a frame's 10240 samples both recurse to
  the list's length. Base's `List.take` and `List.append` are not tail
  calls: use `Mixer.take.rev` / an accumulator for anything a file sizes.
- **Long list literals** in a generated program overflow the JavaScript
  parser's stack around 2000 elements: pass them in chunks of 64
  (`words.joined` in `tools/sound_probe.py`, `input_bytes` in
  `tools/bmp_probe.py`).
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
