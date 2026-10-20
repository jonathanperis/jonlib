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
| `rtext.c` (+154 −95) | `LoadFontData` space codepoints, `LoadFontDataBDF` fixed, `ImageDrawTextPro` (an empty body, in `rtextures.c`), text functions; the rest (`LoadFontFromImage`'s leak, `snprintf` copies, an unused atlas width, a redundant cast in `DrawTextEx`, log lines, `LoadBMFont`'s page merge through `ImageDrawImagePro`, whose pages are still freed first: refused) changes nothing observable | fonts ported (gates `ttf`, `font`); the text functions ported (gate `text`): `TextSubtext`'s position and length checks, `TextRemoveSpaces`, `TextReplaceBetween`'s bound, `TextInsert(Alloc)`'s position, `TextJoin`'s delimiter in the fit, `TextSplit`'s bound, `TextToPascal`/`TextToCamel`/`TextToSnake`; no observable change in `LoadTextLines`, `GetTextBetween`, `TextReplace(Alloc)`, `TextIsEqual`, `TextFindIndex`, `TextToUpper` (`memcpy`/`snprintf` copies of the same bytes, casts, comments) |
| `rmodels.c` (+357 −221) | billboards, cylinders and capsules (signatures), loaders, CPU skinning | 3D shapes ported: `DrawSphereEx` (`180/rings`, `rings` bands), the rewritten `DrawSphereWires`, `DrawCapsule(Wires)` `(rings, slices)` with rings raised to 1; cylinders and billboards only renamed parameters (gate `models`); `UpdateModelAnimation(Ex)` split into `UpdateModelAnimationBones(Ex)` and `UpdateModelAnimationVertexBuffers`, which now skins every mesh with bone data on the CPU whatever the build (no software-renderer shader has a bone-ids location) and allocates `animVertices` itself: ported with the meshes' bone data from the glTF, IQM and M3D loaders ([MODELS.md](MODELS.md#poses); gates `model-pose`, `gltf`, `iqm`, `m3d`); `GetRayCollisionSphere`'s miss behind the ray (gate `ray`); `LoadOBJ`'s index range checks ported: an index outside its array leaves a zero vertex or texcoord and the (0, 1, 0) normal (gate `obj`). No observable change: `IsModelValid` (bone buffers checked under `SUPPORT_GPU_SKINNING`, which the reference enables in both releases), `UnloadModel` (frees), `ExportMeshAsCode`, `LoadOBJ`'s directory copy and `LoadModelAnimationsM3D`'s names (`snprintf` of the same bytes), `LoadIQM`/`LoadGLTF`/`LoadM3D`'s removed `animVertices` allocations (`!SUPPORT_GPU_SKINNING` only; CPU skinning allocates them, ported), `LoadImageFromCgltfImage` (`>>3` for `/8`), billboards (renamed parameter, dropped casts), `GenMeshCone` and `LoadMaterials` (comments) |
| `raudio.c` (+36 −27) | `LoadWaveFromMemory`/`WaveFormat` `RL_CALLOC`, `LoadSoundAlias`'s NULL check, `UnloadSoundAlias`, music unloads, `CloseAudioDevice`'s order, `snprintf` copies | ported: frames a WAV or OGG read does not reach are zeros (gates `wav`, `vorbis-wave`); an alias of the zero sound is the zero sound, now compared (gate `sound`). No observable change: `WaveFormat`'s zeroed buffer (its frame count becomes what `ma_convert_frames` wrote), `UnloadSoundAlias` freeing the converter residual, WAV/FLAC music unloads (frees; FLAC is not ported), `CloseAudioDevice` uninitializing the device before its mutex (thread order only), `ExportWaveAsCode`'s and `GetFileNameWithoutExt`'s `snprintf` (the same 255 bytes as `strncpy` into zeroed buffers), the dropped `stb_vorbis_stream_length_in_samples` casts (it returns an unsigned int), comments |
| `raymath.h` (+81 −24) | `QuaternionFromVector3ToVector3`'s opposite vectors, `MatrixDecompose`'s columns, `MatrixCompose` written out, `float * Vector*` C++ operators | ported in `jonmath.bend` (gates `operators`, `gltf-anim`): the opposite-vector axis and `MatrixDecompose`'s columns; `MatrixCompose` computes the same products in the same order; the C++ operators are tracked in the ledger (gate `operators`) |
| `rlgl.h` (+106 −95) | fixed shader names, `rlGetPixelDataSize`, ES2/GL33 paths | ported: `rlGetPixelDataSize`'s empty and negative sizes (`Pixel.data_size` in `jonlib.bend`, through `rlReadTexturePixels`); the fixed shader names keep 6.0's values (gate `macros`). No observable change: `rlPushMatrix`'s overflow return, `rlLoadTexture`'s power-of-two check, `rlReadTexturePixels`' format, shader precision and the framebuffer guard are GL33/ES2 code (the reference is `GRAPHICS_API_OPENGL_SOFTWARE`, whose 1.1 path is unchanged); `snprintf`, includes, comments; `RLGL_VERSION` is "6.0" in both |
| `rgestures.h` (+20 −18) | `bool` guard, `rgGetCurrentTime` locals | no observable change: build-time guard, comments, the Windows timer's `unsigned long long` (the same type) and the standalone clock (raylib's build uses `GetTime()`) |
| `rcamera.h` | none | unchanged between the two commits |
| `external/dr_wav.h` (0.14.6), `dr_mp3.h` | malformed-file checks, 64-bit totals | ported (`src/wav.bend`, `src/mp3.bend`; gates `wav`, `mp3`): Wave64 sizes below 24, `fmt` chunks below 16 bytes, ADPCM block headers that take the data, Xing/Info bounds and the 64-bit frame total. No observable change: `bext`/`smpl` metadata (not read by raylib), big-endian >32-bit samples (little-endian hosts), dr_mp3's smaller stack buffers |
| `external/qoa.h` | frame checks, rounded buffer | ported (`src/qoa.bend`; gate `qoa`): more than 8 channels, frames below their header or past 256 slices, decoding up to a short frame into a buffer of whole frames |
| `external/dr_flac.h` (0.13.4) | metadata bounds, seek ratio in double | no observable change: FLAC is not ported (raylib's default build leaves it out) |
| `external/miniaudio.h` (0.11.25) | WinRT `dlopen`, Emscripten macros, `ma_data_source` frame count, embedded dr_wav fixes | no observable change: no hunk touches the converter, resampler, filters, channel maps, PCM conversions or mixing Jonlib ports; raudio defines `MA_NO_WAV` and uses no `ma_data_source` |
| `external/tinyobj_loader_c.h` | asserts replaced by runtime returns | ported (`src/obj.bend`; gate `obj`): a line of 4095 bytes is parsed. Still refused: a longer line (`parseLine` returns before it sets the command's `malloc`'d type, which is then read) and faces of more than 5 vertices (the return leaves the command's counts unset; past 16 its array overflows first) |
| `external/vox_loader.h` | bounds checks | ported (`src/vox.bend`; gate `vox`): fewer bytes than a chunk header, a SIZE, a voxel count or a palette end the reading with what was read (a file that ends with its palette among them), a count is cut to the voxels the file holds, and a voxel outside the padded sizes (or before any SIZE) is not set; freeing the normals changes nothing observable |
| `external/jar_mod.h` | `jar_mod_load_file`'s `fread` result | no observable change: only a failed read of an opened file (an I/O error) differs, and Jonlib reads the file's bytes itself |
| `external/rprand.h` (1.1) | `rprand_get_value_raw` | no observable change: a new function raylib does not call; the generator is the same |
| other `external/` (`cgltf`, `m3d`, `jar_xm`, `stb_*`, `par_shapes`, `qoi`, `sdefl`/`sinfl`, `rltexgpu`, `msf_gif`) | none | unchanged between the two commits; `pep.h` is new (the PEP loader, not compared) and `RGFW`/`glfw` are platform code |
| examples | 11 new, 53 changed | the 11 new examples are ported (`shapes_drag_puzzle`, `shapes_ellipse_collision`, `shapes_outlines_testbed`, `shapes_outlines_thickness`, `shapes_polygon_lines`, `textures_portal_window`, `text_animations`, `models_mesh_uv_painting`, `models_procedural_decals`, `shaders_lights_bloom`, `audio_amp_envelope`); the 53 changed ports follow 6.2 (gates `examples-*`, to run): new keys and texts (`core_smooth_pixelperfect`'s S and O, `models_loading_iqm`'s animation and speed keys, `models_animation_blending`'s label, `textures_image_text`'s fitted atlas and 94 codepoints), changed control flow (`core_directory_files` goes into directories and filters with `"DIRS*;.png;.c"`, `shapes_ball_physics`' window shake, `shaders_shadowmap_rendering`'s camera before the view uniform), `sinf` for `sin` (`audio_raw_stream`, `audio_stream_callback`), `roundf` of the wheel (`shapes_rlgl_color_wheel`), renamed APIs (`ImageDrawImagePro`, `GetScreenToWorldRay`, `IsGestureDetected`); `text_codepoints_loading` and `audio_stream_callback` are no longer undefined natively and are compared whole; the rest change comments, casts or unloads only. |
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
