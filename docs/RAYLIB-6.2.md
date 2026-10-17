# The move to raylib 6.2

raylib 6.2 (tag `6.2`, `02566453`, 2026-10-15) is 530 commits after the 6.0
release Jonlib ported (`dbc56a87`). Jonathan's decision (2026-10-17): move
the port to 6.2 before the macOS validation. The move happens on the
`work/raylib-6.2` line (pieces pushed as `feature/raylib62-*`, the stack as
`raylib-6.2/stack`); `main` stays on 6.0, green, until every gate passes on
6.2, then the line merges.

## The pin and the catalog (done)

`toolchain.json` pins 6.2; `api/reference.json` is 6.2's headers (1906
entries; raylib.h 619 functions). The ledger follows the renames
(`GetSplinePointBezierQuad` → `GetSplinePointBezierQuadratic`,
`ImageDrawTriangleEx` → `ImageDrawTriangleGradient`) and drops what 6.2
removed (`ImageDraw`, now `ImageDrawImage*`; the `GetMouseRay` alias; the
`RL_BOOL_TYPE` switches). The examples plan lists 6.2's 223 examples.

## The reference build

6.2's CMake reads `#define SUPPORT_X 0` in `config.h` as `OFF` (6.0 read every
define as `ON`), so the probes' default reference library lost the TGA, JPG,
PSD, HDR, PIC, PNM, KTX, ASTC, PKM, PVR and BDF loaders and the image
references exited early. The probes and the conformance build now pass
`INCLUDE_EVERYTHING=ON`, which restores 6.0's effective configuration (and
enables the new PEP loader, which Jonlib does not compare: its
`LoadImageFromMemory` branch frees the pixels it returns). A changed option set
also drops the stale `CMakeCache.txt`, whose cached options would otherwise
outlive it.

## What changed upstream, and where Jonlib stands

| Upstream | Change | Jonlib |
|---|---|---|
| `rcore.c` (+264 −185) | files and paths: `IsPathDirectory`, `IsPathAbsolute`, `IsFileHidden` (new), `ChangeDirectory` returns `chdir`'s int, `GetPrevDirectoryPath` rewritten (it asks `IsPathFile`), `FileCopy`/`FileMove`/`FileTextReplace` results, `IsFileExtension` (15 bytes, 32 entries), path buffers of 4096 bytes; gamepad index checks; automation events | files and paths ported (gates `files`, `files-os`, `loaders`); the rest to check |
| `external/rlsw.h` (+1120 −1064) | dispatch refactor, span and quad fixes, scissor Y fix, blend state fix, NPOT textures, texture format coercion | to port (`src/frame.bend`) |
| `rshapes.c` (+2997 −924) | `*LinesEx` outlines (new and fixed), circle sectors, rounded rectangles, `DrawTriangleGradient` | to port |
| `rtextures.c` (+727 −354) | `ImageDrawImage*`, `ImageDraw*` new forms, `LoadRenderTextureEx`, `ImageColorContrast`, `GetPixelColor` | to port |
| `rtext.c` (+154 −95) | `ImageDrawTextPro`, text functions | to check |
| `rmodels.c` (+357 −221) | billboards, cylinders and capsules (signatures), loaders | to check |
| `raudio.c` (+36 −27), `rlgl.h`, `raymath.h`, `rgestures.h` | small changes, raymath operators | to check |
| vendored: jar_mod, qoa, miniaudio, rprand, tinyobj, vox_loader | small changes | to check |
| examples | 11 new, 53 changed | to port |

Each row is checked by its gates against 6.2 (the CI run of the pin lists
what moved), diagnosed, ported in Jonlib's own pieces with laws, docs and
ledger updates, and the gates are re-run.

## Gates against 6.2

The pin's first full Linux run (2026-10-17) failed 57 gates. By cluster:

- **The renderer** (rlsw): `frame`, `rlgl`, `texture`, `font`, `ttf`,
  `models`, `models-gnu`, `model-draw`, every `examples-*` gate.
- **Image files**: the references of `pnm`, `psd`, `psd-matte`, `pic`,
  `tga`, `tga-export`, `hdr`, `hdr-file`, `image-export`, `gif-animation`,
  `float-rgb`, `float-rgb-raster-export`, `formatted-tga-export` exit early;
  `image-file`, `image-memory`, `animation-file` accept differently.
- **Pixels**: `pixel`, `raw-pixel`, `float-rgb-color`, `convolution`.
- **Collision**: `ray`, `ray-uncontracted`; cameras: `camera-*`.
- **Models**: `gltf-anim`, `model-pose`, `iqm`.
- **Audio**: `wav`, `mp3-wave`.
- **Core**: `input`, `sha`, `text`; raymath `operators`; raygui
  `gui-icons`, `gui-icon-files`, `examples-gui`.
- **The API changes themselves** (fixed in the first pieces): `files`,
  `files-os`, `loaders`, `macros`, `spline`, `surface-format`, `conformance`.
