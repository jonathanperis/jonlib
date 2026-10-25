# macOS validation

Every gate passes on Linux against the pinned raylib 6.2. macOS (arm64,
`macos-15`) has been off the merge path since 2026-10-10 ([CI.md](CI.md)).
Both CI hosts are part of every entry's verification
([API-TRACKING.md](API-TRACKING.md)), so this is the validation of the
second of Jonlib's two target platforms
([`api/milestones.json`](../api/milestones.json)). It is run by the maintainer
on a Mac. `macos-15` stays out of `MERGE_HOSTS` until a full shard of the
current `main` is green on this host.

## 1. Turn macOS back on in CI

Do this only after section 3 lists no open failure on the current `main`.

- Add `('macos', 'macos-15')` to `MERGE_HOSTS` in
  [`tools/ci_scope.py`](../tools/ci_scope.py) (and drop the deferral note in
  its module text).
- Make the `os:` line of `.github/workflows/checks.yml` include `macos-15`
  for every event, and update the comments of both workflows that say macOS
  is deferred.

Pushes and pull requests then run every scoped gate on both hosts.

## 2. Run every gate on the Mac

Set up the pinned toolchains of [`toolchain.json`](../toolchain.json) as
`.github/actions/setup-pinned` does: Bend at its base revision with the
declared overlay patches ([patches/README.md](../patches/README.md)), raylib
6.2 at `02566453`, Bun 1.3.12 first in `PATH`. Then:

```sh
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
python3 tools/run_gates.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --only <id>
```

On macOS the host libm selects `M.AppleLibm{}` and the linked raylib fuses
`a*b + c` (`M.Fused{}`); what those profiles refuse is in
[ANGLES.md](ANGLES.md), [PERSPECTIVE.md](PERSPECTIVE.md) and
[SINCOSF.md](SINCOSF.md). The reference library is built with
`INCLUDE_EVERYTHING=ON` ([VERIFICATION.md](VERIFICATION.md)). Forced-Metal
runs (`tools/conformance.py --gpu`, `tools/verify_bend.py --gpu` and the
probes' `--gpu`) are separate local evidence; hosted runners have no GPU.

## 3. Verified state

A full shard on 2026-10-24 (`fa0755b`, raylib 6.2, Apple clang 21.0.0,
arm64, `--jobs 1`, lanes cpu-1, cpu-2 and javascript) passed 191 of 206
gates. That run supersedes the raylib 6.0 nightly of 2026-10-16. Gates the
6.0 note had never run, or had failing, and that passed there include
`macros`, `easings`, `lights`, `facades`, `mod`, `mod-music`, `files-os`,
`gui-icon-files`, `examples-gui` and `examples-text`. `filter-precision`
recorded its float-normalization mismatches and exited 0.

Re-run green on this Mac after the contract fixes, same lanes and jobs:

- `spectrum`: `capture` refuses a frame whose Blackman weights or twiddle
  factors were not answered. Under AppleLibm every frame is that refusal
  (50 frames, nothing compared).
- `ttf`: a curve SDF under AppleLibm stays a refusal (`data-sdf-curves` of
  the generated curve font, and `data-sdf-example`). DotGothic16 is lines,
  so its SDF is compared. The AppleLibm run reported `refused_operations=18`
  and `cubic_compared=False`.
- `gltf-anim`: `greenman.glb` is compared (12 bones, 4 animations).
  `robot.glb`'s rotations leave the nlerp band, so that load stays a
  contract. 19 cases, 13 compared, 6 contracts.
- `examples-shaders`: 36 examples, 184 frames, on the same lanes. Apple
  clang 21's Darwin `-fstack-check` probe clobbers a register
  `preserve_none` still uses; the overlay's CPU line passes
  `-fno-stack-check` for that clang (`patches/bend-apple-clang.patch`).
- `easings`, `pow2`, `xm-pitch`, `xm-player`, `xm-mixer`, `xm-music`:
  AppleLibm answers the 25,980 measured `exp2f` words in
  `src/apple_exp2.bend`, including two linear exponents that appear only
  after `jar_xm_reset` following 9,000 samples of the linear module at
  48,000 Hz. The JavaScript lane shares one value for that table
  (`patches/bend-js-constant.patch`). easings 382 samples; pow2 25,980 host
  words; xm-pitch 524 frequencies; xm-player 11,460 ticks; xm-mixer 164,741
  frames; xm-music 15 cases, 10 compared, 278 steps, including `linear`
  and `apple-mini`.
- `sound`: the mixer keeps subnormals on Darwin arm64 (`flush` false). 126
  cases, 86 compared, 40 contracts, 1363 steps.
- `mp3-layer3`, `mp3-stream`, `mp3-wave`: the window's int16 conversion is
  NEON on arm64 (`Decoder.nearest` false: half added, truncated toward zero,
  one less when that sum is negative) and SSE elsewhere. layer3 179 files,
  1676 frames; stream 95 files, 224 streams; wave 95 files, 72 waves.
- `ogg-music`: the same subnormal flag. 6 cases, 181 steps.
- `examples-audio`: 11 examples, 208 frames, 135 compared, 73 refused.
  `audio_mixed_processor-powers` compares frame 0. AppleLibm has no `powf`,
  so the first update that owes a 10 ms period (frame 1) refuses that frame
  and every later one.

Still open from the `fa0755b` shard:

- `examples-textures`: `textures_sprite_stacking-spin` frame 1.

Each failure gets the same diagnosis as on Linux: raylib's semantics on
macOS, then Jonlib, the fixtures and the host differences. Never a looser
expectation ([AGENTS.md](../AGENTS.md)).

## 4. Record and close

- Keep the compact per-gate records of the complete run
  (`run_gates.py --record docs/evidence`) if evidence is to be committed: the
  earlier macOS records were from raylib 6.0 and were removed, so none is in
  the repository now.
- Record the macOS results in `api/progress.json` (gates, gaps and target
  results; then `python3 tools/api_plan.py build`), mark an entry `complete`
  only where the completion rule of [API-TRACKING.md](API-TRACKING.md) is
  met, and record what stays partial.
