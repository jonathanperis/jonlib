# Session handoff (2026-10-09)

Snapshot for continuing on another machine. Everything is committed and pushed;
nothing lives only on the old machine except throwaway caches (`.build/`).

## Goal in force

Jonathan's directive: **100% of raylib ported** (raylib.h, raymath.h, rlgl.h,
rcamera.h, rgestures.h), **validated by porting every upstream example** to
Bend and replaying it against the native example. Work autonomously; merge to
`main` only after a CI run concludes `success`.

## Where things are

| Branch | Content | State |
|---|---|---|
| `main` | e3afa23: Phase 1 work, CI timeout fix | CI green |
| `feature/audio-waves` | everything verified since: audio, math profiles, text, fonts (TTF/BDF/BMFont), camera, Phase 2 (frame, shapes, textures, rlgl, input, gestures, timing, desktop driver), meshes/3D shapes, window/core functions, QuaternionToEuler, the examples tracker | **merge to `main` once its CI concludes `success`** (the run for 9cf1748 had all 8 Linux shards green before this push restarted CI) |
| `wip/lgpl-tan-asinf` | 79aae7a, unfinished agent work: glibc 2.39 `tan` (LGPL, isolated) | see below |
| `wip/models-drawing-obj` | 10b25ad, unfinished agent work: materials, DrawMesh/DrawModel, OBJ loading | see below |

Coverage (`python3 tools/api_plan.py check`): raylib.h 484/600 partial
(95 not-started, 21 blocked); raymath.h 145/146; rlgl.h 93/163; rcamera.h
12/12; rgestures.h 10/10. Examples (`python3 tools/examples_plan.py check`,
[EXAMPLES.md](EXAMPLES.md)): 13/212 ported, 120 ready, 79 waiting. No API is
`complete` by design until Phase 7 targets (see MASTER-PLAN).

## Decisions and rules to keep (from Jonathan; also in project memory)

- AGENTS.md rules: pinned toolchains, never install/update them or modify
  the Bend compiler; never loosen expected results; refuse undefined native
  behavior; preserve notices.
- **LGPL (2026-10-09): allowed, isolated.** glibc's `tan` and `asinf` (LGPL-2.1+)
  may be ported into separate `src/lgpl/` modules with full notices
  (`LICENSES/lgpl-2.1.txt`, a THIRD_PARTY_NOTICES section, a MASTER-PLAN
  decision entry); the rest of Jonlib stays zlib. Apple's libm is unpublished:
  Apple profiles stay refused where they can't be reproduced.
- Merge discipline: merge to `main` only when CI `conclusion == success`;
  delete merged branches locally and remotely; never force-push or amend pushed
  commits without asking.
- Work before 2026-10-06 was GPT-generated: re-verify rather than trust.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Unfinished work

### `wip/lgpl-tan-asinf` (perspective cameras)
Done: unmodified glibc 2.39 sources in `tools/reference/glibc239/`; C models
in `tools/reference/glibc_tan/` (`model.c` with `FUSED=1` = the FMA variant
CI runners use, `FUSED=0` = SSE2/AVX); exhaustive check on all 4,278,190,080
MatrixPerspective arguments: native glibc 2.39 `tan` = FMA model (0
differences; results in `results/perspective-fma.json`); FMA vs SSE2 variants
differ on 27,258; glibc 2.41's tan sources are identical (map Glibc241Libm to
the same kernel). `src/binary64_scaled.bend` (zlib) and a **draft, never
compiled** `src/lgpl/tan.bend` + `tan_table.bend`.
Next: rerun the BeginMode3D exhaustive set (`tools/reference/glibc_tan/run_all.sh`
in an Ubuntu 24.04 amd64 container; it was interrupted), compile and test the
Bend kernel against the C model, add the LGPL license/notice/decision entries,
wire `M.Libm.tan` → `MatrixPerspective`, perspective `BeginMode3D`, the camera
projection/screen functions; port glibc 2.39 `e_asinf.c` (LGPL) to extend
`M.Libm.asin` for Glibc239Libm; probes + gates on both hosts; then the 3D
examples.

### `wip/models-drawing-obj`
76ac541, rebased on `feature/audio-waves` at 9cf1748. Adds Material/MaterialMap
and their functions, DrawMesh/DrawModel(Ex)/DrawModelWires(Ex)/DrawBillboard*
(rlsw vertex-array paths; DrawMeshInstanced is a GL3-only no-op), OBJ+MTL
loading via a tinyobj_loader_c port (`src/obj.bend`, binary64 number parsing
with a contraction profile), `tools/model_draw_probe.py` (27 scenes) and
`tools/obj_probe.py` (40 cases), gates `model-draw`, `obj`, `obj-uncontracted`.
Verified: type checks, PROOF, unit tests, check_project, and the JavaScript
lane of both probes (all match). **Not yet verified:** the full CPU-1/CPU-2
runs (compiles timed out under load; about 2.5 min on a quiet machine), the
`obj-uncontracted` gate, and the `mesh`/`models`/`frame`/`texture` probes
after `tools/mesh_probe.py` changed for the new `Model` constructor. Then merge
`feature/audio-waves` in, rebuild the plans and merge. Gaps: IQM/glTF/VOX/M3D
unsupported, OBJ faces of 6+ vertices refused (tinyobj asserts).

## Next steps, in order

1. When `feature/audio-waves` CI is green: merge to `main`, push.
2. Finish the two `wip/` branches above.
3. Port the 120 ready examples (docs/EXAMPLES.md), category by category
   (shapes 36, text 14, textures 25, core 41, models 4), each added to
   `tools/examples_probe.py`; split the `examples` gate per category.
4. Remaining milestones: rlgl-advanced (52) and shaders (12): implement what
   the GL1.1/rlsw software path does (mostly documented no-ops; framebuffers
   exist in rlsw); audio-device (20) and audio-stream (35) (Phase 4: miniaudio
   mixing; Base has `Audio.open/write/close`); animation (5), vr (4), the
   remaining models/materials; `files` (16 blocked: directories, timestamps,
   rename/remove need OS primitives Base lacks; that is Bend overlay runtime
   work).
5. Keep `docs/EXAMPLES.md` ranking ("APIs that unblock the most examples") as
   the work queue.

## Known pitfalls (save time)

- **Bend native miscompile:** a `Bool.pick(Bool, …)` result feeding `||` in the
  same def is wrong on native lanes (repro `tests/compiler/bool_pick_or.bend`,
  diagnostic gate `bend-defects`). Never write it.
- **Apple clang 21 crashes** compiling very large Bend defs: keep defs small and
  probes data-driven ("scenes as data through one interpreter def").
- **Memory:** probes' JavaScript lanes peak near 4.5 GB; run probes with
  `--jobs 1` or `2` when other work shares the machine; re-run on compile
  timeouts rather than raising budgets.
- **Host-dependent expectations:** Linux CI uses the glibc profiles and
  uncontracted x86-64; macOS uses Apple libm and fused arm64. Compute every
  probe expectation per host profile; never run natively anything undefined in
  C (x86 traps integer division by zero, arm64 returns 0). Verify Linux
  behavior locally in `docker run --platform linux/amd64 ubuntu:24.04`.
- **Reference build:** probekit's `CUSTOMIZE_BUILD=ON` raylib enables every
  `SUPPORT_*` flag `config.h` defines, including default-off ones
  (docs/VERIFICATION.md).
- **Compilers fold `powf(x, 2)` into `x*x`**; check compiled references before
  assuming a libm call.
- **Apple sinf/cosf** are not correctly rounded; the AppleLibm profile is
  verified only on whole degrees (and a few known exceptions).
- CI: 8 shards per OS, gate `minutes` = measured macOS durations (docs/CI.md).

## Toolchain on the new machine

Pinned in `toolchain.json`: Bend at `b7ebee9…` with the declared overlay
(`patches/`), raylib 6.0 at `dbc56a87…`, Bun 1.3.12. Local layout used so far:
Bend at `~/Projetos/bendlang/bend` (CLI `bun ~/Projetos/bendlang/bend/bend2/main.ts`),
raylib at `~/Projetos/raysan5/raylib`. Checks:

```sh
python3 -m unittest discover -s tests
python3 tools/check_project.py
bun ~/Projetos/bendlang/bend/bend2/main.ts PROOF.bend
python3 tools/run_gates.py --bend-source ~/Projetos/bendlang/bend --raylib-source ~/Projetos/raysan5/raylib --only <gate>
```
