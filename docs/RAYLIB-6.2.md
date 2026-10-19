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
| `rcore.c` (+264 −185) | files and paths: `IsPathDirectory`, `IsPathAbsolute`, `IsFileHidden` (new), `ChangeDirectory` returns `chdir`'s int, `GetPrevDirectoryPath` rewritten (it asks `IsPathFile`), `FileCopy`/`FileMove`/`FileTextReplace` results, `IsFileExtension` (15 bytes, 32 entries), path buffers of 4096 bytes; gamepad index checks (`gamepad >= 0`, a bounded `GetGamepadName`/`GetGamepadAxisCount`); `GetFPS` counts its samples; `LoadAutomationEventList` reads `%63[^\n]` and skips lines past the capacity; `TakeScreenshot` writes absolute names as given; SHA-256 padding; `rcore_memory.c`: `SetMousePosition` keeps the previous position | files and paths ported (gates `files`, `files-os`, `loaders`); gamepad checks, `GetFPS`, the event-file reader, SHA-256 and `SetMousePosition` ported (gates `input`, `sha`); `TakeScreenshot`'s absolute names documented, not compared. The rest of the diff (comments, `strncpy` to `memcpy`/`snprintf`, `TraceLog` prefixes, `const` parameters, `FileRename`/`FileRemove` results) is not observable |
| `external/rlsw.h` (+1120 −1064) | dispatch refactor, span and quad fixes, scissor Y fix, blend state fix, NPOT textures, texture format coercion | ported in `src/frame.bend`: spans and boxes clamped to the color buffer, flat or interpolated colors, plane derivatives and one texture filter per triangle, the scissor's y, per-vertex alpha, the line step, bilinear clamping; NPOT support, the depth-format coercion and the dispatch refactor change no pixel ([FRAME.md](FRAME.md)) |
| `rshapes.c` (+2997 −924) | `*LinesEx` outlines (new and fixed), circle sectors, rounded rectangles, `DrawTriangleGradient` | ported in `src/shapes.bend` ([FRAME.md](FRAME.md#state-and-api), [RLGL.md](RLGL.md)): radius `<= 0` and one-turn arcs, the new estimates, `DrawRectangleLinesEx`, `DrawPolyLinesEx`, the rounded outlines, `DrawTriangleGradient`, `DrawTriangleLinesEx`, `DrawCircleLinesEx`, `DrawEllipseLinesEx`, `DrawCircleSectorLinesEx`, `DrawRingLinesEx` (gates `frame`, `rlgl`; to run) |
| `rtextures.c` (+727 −354) | `ImageDrawImage*`, `ImageDraw*` new forms, `LoadRenderTextureEx`, `ImageColorContrast`, `GetPixelColor` | ported: `ImageDrawImage`/`Rec`/`Pro` (`Pro` is 6.0's `ImageDraw`, origin and rotation ignored as upstream), the new `ImageDrawImageEx`, `ImageDrawRectanglePro`, `ImageDrawRectangleGradientEx`, `ImageDrawCircleGradient`, `ImageDrawLineStrip`, `ImageDrawRectangleLines` (int) and `LinesEx`, `ImageDrawTriangleGradient`, the empty `ImageDrawTextPro`, `ImageFromImage`'s validation, `LoadRenderTextureEx` (gates `surface-format`, `float-rgb-crop`, `texture`); pixels, contrast and lines in the first piece |
| `rtext.c` (+154 −95) | `LoadFontData` space codepoints, `LoadFontDataBDF` fixed, `ImageDrawTextPro` (an empty body, in `rtextures.c`), text functions; the rest (`LoadFontFromImage`'s leak, `snprintf` copies, an unused atlas width, a redundant cast in `DrawTextEx`, log lines, `LoadBMFont`'s page merge through `ImageDrawImagePro`, whose pages are still freed first: refused) changes nothing observable | fonts ported (gates `ttf`, `font`); text functions to port |
| `rmodels.c` (+357 −221) | billboards, cylinders and capsules (signatures), loaders | 3D shapes ported: `DrawSphereEx` (`180/rings`, `rings` bands), the rewritten `DrawSphereWires`, `DrawCapsule(Wires)` `(rings, slices)` with rings raised to 1; cylinders and billboards only renamed parameters (gate `models`); loaders to check |
| `raudio.c` (+36 −27), `rlgl.h`, `raymath.h`, `rgestures.h` | small changes, raymath operators | to check |
| vendored: jar_mod, qoa, miniaudio, rprand, tinyobj, vox_loader | small changes | to check |
| examples | 11 new, 53 changed | the 11 new examples are ported (`shapes_drag_puzzle`, `shapes_ellipse_collision`, `shapes_outlines_testbed`, `shapes_outlines_thickness`, `shapes_polygon_lines`, `textures_portal_window`, `text_animations`, `models_mesh_uv_painting`, `models_procedural_decals`, `shaders_lights_bloom`, `audio_amp_envelope`); the 53 changed ports follow 6.2 (gates `examples-*`, to run): new keys and texts (`core_smooth_pixelperfect`'s S and O, `models_loading_iqm`'s animation and speed keys, `models_animation_blending`'s label, `textures_image_text`'s fitted atlas and 94 codepoints), changed control flow (`core_directory_files` goes into directories and filters with `"DIRS*;.png;.c"`, `shapes_ball_physics`' window shake, `shaders_shadowmap_rendering`'s camera before the view uniform), `sinf` for `sin` (`audio_raw_stream`, `audio_stream_callback`), `roundf` of the wheel (`shapes_rlgl_color_wheel`), renamed APIs (`ImageDrawImagePro`, `GetScreenToWorldRay`, `IsGestureDetected`); `text_codepoints_loading` and `audio_stream_callback` are no longer undefined natively and are compared whole; the rest change comments, casts or unloads only. The 11 new ones: to port |
| `examples/*/raygui.h` (5.0-dev → 5.1-dev) | 512 icons, `GuiLoadIconsFromMemory` replacing the table, `GuiTabBar`/`GuiTabBarEx` (TABBAR style row), `GuiMessageBox`/`GuiTextInputBox` with `btnActive`, `GuiGetTextWidth`/`GetLineWidth`, `TEXT_LINE_SPACING` 12, tooltips by `GuiMeasureText`, `GuiToggleGroup` parsing, hue bar gradients, scroll panel header, `GuiLoadStyle` `v` lines and version 600, results | ported in `jongui.bend` ([GUI.md](GUI.md); gates `gui-icons`, `gui-icon-files`, `examples-gui`) |

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
