# macOS validation

Every gate passes on Linux against the pinned raylib 6.2. macOS (arm64,
`macos-15`) has been off the merge path since 2026-10-10 ([CI.md](CI.md)), so
nothing on `main` is verified there yet. Both CI hosts are part of every
entry's verification ([API-TRACKING.md](API-TRACKING.md)), so this is the
validation of the second of Jonlib's two target platforms
([`api/milestones.json`](../api/milestones.json)). It is run by the maintainer
on a Mac.

## 1. Turn macOS back on in CI

- Add `('macos', 'macos-15')` to `MERGE_HOSTS` in
  [`tools/ci_scope.py`](../tools/ci_scope.py) (and drop the deferral note in
  its module text).
- Make the `os:` line of `.github/workflows/checks.yml` include `macos-15`
  for every event, and update the comments of both workflows that say macOS
  is deferred.

Pushes and pull requests then run every scoped gate on both hosts.

## 2. Run every gate on the Mac

Set up the pinned toolchains of [`toolchain.json`](../toolchain.json) as
`.github/actions/setup-pinned` does: Bend at its base revision with both
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

## 3. What is known to need diagnosis

**The pin moved since the last macOS run.** The last nightly that ran
macOS (2026-10-16, `main` at `b4f74f4`) was against raylib 6.0. Every gate
has changed reference since, so every gate must be run again on 6.2, not only
the ones below. These failed there on `macos-15` (first symptom each):

- `sound`: the model disagrees with raylib on `stream-play-mono` at step 8
  (`mix`, 480);
- `xm-pitch`, `xm-player`, `xm-mixer`, `xm-music`: jar_xm's linear
  frequencies and what follows from them (Apple's `exp2f`/`powf` and `sinf`
  against the glibc models);
- `mp3-layer3`, `mp3-wave`: frame 19 of a Layer III stream and a Layer I
  stream's samples (dr_mp3's float path on arm64);
- `ogg-music`: the first state;
- `spectrum`: raylib refuses where Jonlib answers on a silent input;
- `gltf-anim`: raylib's `greenman` is null where Jonlib loads it;
- `ttf`, `examples-text`, `examples-audio`: glyph and audio frames (likely
  consequences of the above);
- `examples-shaders`: a candidate failed to build with clang on macOS
  (`candidate-33`).

**Gates that have never run on macOS:** `macros`, `easings` (most sine,
exponential and elastic easings refuse under AppleLibm), `lights`,
`facades`, `mod`, `mod-music`, `files-os`, `gui-icon-files` and
`examples-gui`, plus the scenes added to existing gates since (for example
`texture`'s `params` and `rl-update`, `rlgl`'s `resize` and `client`,
`models`' clip planes, and everything raylib 6.2 changed).

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
