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
defs. At that point these probes dropped their GPU lane.

The four probes then compared their GPU lane, which they had computed and
dropped: `vector2` (27993 cases), `vector3` (32412), `vector4` (32466) and
`scalars` (8260) matched on cpu-1, cpu-2, javascript and gpu.

Metal witness: raymath:function:Vector2Add a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2AddValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Subtract a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2SubtractValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Scale a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Multiply a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Negate a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Divide a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Invert a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Equals a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Add a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3AddValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Subtract a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3SubtractValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Scale a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Multiply a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Negate a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Divide a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Invert a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Equals a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Add a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4AddValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Subtract a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4SubtractValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Scale a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Multiply a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Negate a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Divide a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Invert a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Equals a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionAdd a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionAddValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionSubtract a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionSubtractValue a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionScale a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionDivide a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionEquals a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Clamp a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Normalize a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:FloatEquals a3efe8a3801f423827424227172eed9802c5e6cb pass

## Ray and stored-image GPU lanes, 2026-11-11

`ray` and `ray-uncontracted` (442 queries each) and `stored` (57 cases) had
dropped their GPU lane; they now compare it, and with `--gpu` every lane
matched. `ray-exceptional` (833 cases, no quiet-NaN sign rows on any lane)
passed with `--gpu` on the same tree. `ImageCopy` and `IsImageValid` were
missing only the `stored` GPU lane.

Metal witness: raylib:function:GetRayCollisionBox a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetRayCollisionTriangle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetRayCollisionQuad a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageCopy a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:IsImageValid a3efe8a3801f423827424227172eed9802c5e6cb pass

## Image ownership batch, 2026-11-11

`surface-format` (2605 cases, 13 formats) with `--gpu`, after 45 Surface
operations were routed through ownership defs: every lane, gpu included,
matched. Entries whose evidence also cites `tools/conformance.py` rely on its
forced-GPU run above (281 scenarios). Entries that cite a probe not yet run
with `--gpu` have no witness here.

Metal witness: raylib:function:ImageAlphaCrop a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageAlphaClear a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageAlphaMask a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageAlphaPremultiply a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageFlipVertical a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageFlipHorizontal a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageRotateCW a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageRotateCCW a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:LoadImagePalette a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetImageAlphaBorder a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageClearBackground a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawPixel a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawPixelV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawLine a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawLineV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawLineEx a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawLineStrip a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTriangle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTriangleLines a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTriangleFan a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTriangleStrip a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangleV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangleRec a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangleLines a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawRectangleLinesEx a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawCircle a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawCircleV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawCircleLines a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawCircleLinesV a3efe8a3801f423827424227172eed9802c5e6cb pass

The other probes those image entries cite ran with `--gpu` on the same tree
and every lane, gpu included, matched: `triangle-gradient` (241 cases),
`pixel`, `image-format`, `r32-image` (whose GPU lane has its own expected
rows), `float-rgb-crop`, `float-rgb-resize`, `float-rgb-resize-filtered`,
`float-rgb-canvas`, `float-rgb-color` and `image-colors`.

Metal witness: raylib:function:ImageToPOT a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageCrop a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageResizeNN a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageResizeCanvas a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDither a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageColorTint a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageColorInvert a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageColorContrast a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageColorBrightness a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageColorReplace a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:LoadImageColors a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetImageColor a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ImageDrawTriangleGradient a3efe8a3801f423827424227172eed9802c5e6cb pass

## Checksum, pixel, generator and constant batch, 2026-11-11

`checksum`, `sha`, `raw-pixel`, `pixel`, `gradient-checked`, `random` and
`math-values` (which had dropped its GPU lane and now compares it) passed
with `--gpu` after their calls were routed through ownership defs: every
lane, gpu included, matched.

Metal witness: raylib:function:ComputeCRC32 a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ComputeMD5 a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ComputeSHA1 a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:ComputeSHA256 a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetPixelColor a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:SetPixelColor a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GetPixelDataSize a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GenImageGradientRadial a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GenImageGradientSquare a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:GenImageChecked a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raylib:function:SetRandomSeed a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2Zero a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector2One a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3Zero a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3One a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4Zero a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector4One a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:Vector3ToFloatV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:MatrixTranspose a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:MatrixIdentity a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:MatrixToFloatV a3efe8a3801f423827424227172eed9802c5e6cb pass
Metal witness: raymath:function:QuaternionIdentity a3efe8a3801f423827424227172eed9802c5e6cb pass
