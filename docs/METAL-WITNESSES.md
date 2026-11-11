# Forced-Metal witnesses

Hosted runners have no GPU, so the Metal lane is local evidence
([API-TRACKING.md](API-TRACKING.md#phase-1-exit-measure)). This page records
the forced-Metal runs on the current Bend pin and the entries they witness.
A witness line names an entry only when every probe the entry lists as
evidence compared a `gpu` lane and passed; a probe that leaves the GPU lane
out of its comparison is not a witness.

## Run of 2026-11-11

- Tree `71b4d70` (the library of `f8bee06` plus a longer GPU compile budget
  in `tools/conformance.py`), Bend `a3efe8a3801f423827424227172eed9802c5e6cb`
  with the declared overlay, raylib 6.2 `02566453`, Bun 1.3.12.
- Host: Apple M1 (arm64, 8 cores, 16 GiB), macOS 27.2, Apple clang 21.0.0.
- `tools/conformance.py --gpu`: lanes cpu-1, cpu-2, javascript and
  gpu-forced each matched 281 scenarios and 40963 pixels exactly; the
  transform and decode contracts passed on forced GPU.
- Each gate of `tools/gates.json` below ran with `--gpu` appended:

| Gate | Lanes compared | Result |
|---|---|---|
| `lifecycle` | cpu-1, cpu-2, javascript, gpu | pass (16 lines, 22 calls) |
| `color-words` | cpu-1, cpu-2, javascript, gpu | pass (339 lines) |
| `float-rgb-transform` | cpu-1, cpu-2, javascript, gpu | pass (43 cases, 14953 pixels) |
| `mesh` | cpu-1, cpu-2, javascript, gpu | pass (263 cases, 213 compared, `Fused`, `AppleLibm`) |
| `font` | cpu-1, cpu-2, javascript, gpu | pass (69 scenes, 64 compared) |
| `surface-format` | cpu-1, cpu-2, javascript, gpu | pass (2605 cases, 13 formats) |
| `log` | cpu-1, cpu-2, javascript | pass; trace output is a host effect, no GPU lane |
| `files` | cpu-1, cpu-2, javascript | pass; host file effects, no GPU lane |
| `loaders` | cpu-1, cpu-2, javascript | pass; host file effects, no GPU lane |
| `stored` | cpu-1, cpu-2, javascript | pass; no GPU lane |
| `window` | cpu-1, cpu-2, javascript | pass; no GPU lane |

Entries whose evidence includes `files`, `loaders`, `log`, `stored` or
`window` probes (the file, trace-log and callback functions, `ImageCopy`,
`IsImageValid`, the dropped-file calls) have no witness here.

## Witnesses

Metal witness: raylib:function:UnloadRandomSequence a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:UnloadImagePalette a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:MemFree a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:UnloadImage a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:UnloadImageColors a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangleGradientEx a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawCircleGradient a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTextPro a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetModelBoundingBox a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetMeshBoundingBox a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetRayCollisionMesh a3efe8a3801f423827424227172eed9802c5e6cb pass

## Collision ownership batch, 2026-11-11

`collision-domain` with `--gpu` on the same host and pins, after its queries
were routed through ownership defs: cpu-1, cpu-2, javascript and gpu each
matched 1572 cases.

Metal witness: raylib:function:CheckCollisionPointRec a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionRecs a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionBoxes a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetCollisionRec a3efe8a3801f423827424227172eed9802c5e6cb pass

`collision-finite` (1096 cases) and `collision-exceptional` (2594 cases) with
`--gpu`, after the finite probe routed its queries through ownership defs:
every lane, gpu included, matched.

Metal witness: raylib:function:CheckCollisionCircles a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionCircleRec a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionCircleLine a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionPointCircle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionPointTriangle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionPointLine a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionSpheres a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionBoxSphere a3efe8a3801f423827424227172eed9802c5e6cb pass

`collision-poly` (1145 cases), `collision-lines` (363 cases) and `fused`
(2056 samples) with `--gpu`: every lane, gpu included, matched. `ray`,
`ray-uncontracted` and `ray-exceptional` also passed with `--gpu`, but `ray`
compares no GPU lane, so the ray queries have no witness.

Metal witness: raylib:function:CheckCollisionPointPoly a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:CheckCollisionLines a3efe8a3801f423827424227172eed9802c5e6cb pass

## Color ownership batch, 2026-11-11

`color-words` (339 lines), `color-normalized` (156 cases) and `color-hsv`
(664 cases) with `--gpu`, after their calls were routed through ownership
defs: every lane, gpu included, matched.

Metal witness: raylib:function:ColorIsEqual a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:Fade a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorAlpha a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorToInt a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetColor a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorNormalize a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorToHSV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorTint a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorBrightness a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorContrast a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorAlphaBlend a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorLerp a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorFromNormalized a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ColorFromHSV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GenImageColor a3efe8a3801f423827424227172eed9802c5e6cb pass

## Vector, quaternion and scalar ownership batch, 2026-11-11

`vector2` (27993 cases), `vector3` (32412), `vector4` (32466) and `scalars`
(8260) passed with `--gpu` after their calls were routed through ownership
defs, but these probes compare no GPU lane, so the 40 raymath functions they
cover have no witness here.
