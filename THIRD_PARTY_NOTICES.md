# Third-party notices

Jonlib is an independent library written in Bend 2, inspired by raylib's design.
It is not affiliated with or endorsed by raylib or Bend's maintainers.
Jonmath is its separately importable mathematical module, porting `raymath.h`.
Project-owned port names use the `ray*` → `jon*` convention; upstream names here
identify the original sources and their required attribution.

## raylib

- Author: Ramon Santamaria (@raysan5) and contributors.
- Version: 6.0, commit `dbc56a87da87d973a9c5baa4e7438a9d20121d28`.
- Source: <https://github.com/raysan5/raylib>.
- License: zlib; retained verbatim in [LICENSES/raylib.txt](LICENSES/raylib.txt).
- Adaptations: the rectangle clipping/degenerate behavior, midpoint-circle,
  fixed-point line and edge-stepped triangle rasterization, and image
  compositing/integer alpha-blending, crop/extraction and fixed-point nearest
  resize algorithms in `jonlib.bend` are
  translated/adapted from `src/rtextures.c`, with Bend ownership and bounded
  recursion. These are modified implementations, not original raylib source.
- Subsequent adaptations include scaled/fractional image composition, vector
  drawing wrappers, outlines, thick lines, fan/strip and vertex-colored triangles,
  color/alpha transforms, checkerboards and quarter-turn rotations from
  `rtextures.c`. The scalar/vector/matrix/quaternion adaptations from `raymath.h`
  are implemented in `jonmath.bend` and shared with Jonlib through imports.
  Their scoped contracts and reference evidence are recorded in `docs/`.
- Pure collision queries in `jonlib.bend` and spline formulas in `src/spline.bend`
  adapt the same release's `rshapes.c`.
  Sphere/box predicates adapt `rmodels.c`; vector/matrix/quaternion operations adapt `raymath.h`.
  The `Camera.*` queries in `jonlib.bend` and `src/camera_span.bend` adapt
  `rcamera.h` and the camera/screen-space functions of `rcore.c`
  (copyright Christoph Wagner and Ramon Santamaria; zlib).
  General bilinear rotation, power-of-two canvases and channel extraction adapt
  `rtextures.c`; these remain modified Bend implementations with explicit profiles.
  `src/image_code.bend` adapts `ExportImageAsCode`, retaining the generated
  upstream banner and credits for exact text parity.
  `Surface.write_image` adapts `ExportImage` suffix selection from `rtextures.c`
  and `IsFileExtension`/`GetFileExtension` from `rcore.c`, using Bend-owned
  error results and the existing closed-handle file writers.
  `Image.Formatted.to_qoi` / `write_qoi` additionally adapt the QOI-specific
  original-format RGB888/RGBA8888 export gate from `rtextures.c`, with integer
  channel packing, retained unsupported owners and typed closed-handle IO.
  `Files.*` in `jonlib.bend` adapts the `rcore.c` path and file-data utilities;
  `src/image_code.bend` also retains the `ExportDataAsCode` banner/credits.
  `src/text.bend` (with `Text.*`, `Codepoint.*` and `UTF8.*` in `jonlib.bend`)
  adapts the text strings management and UTF-8 codepoint functions of
  `rtext.c`, keeping its static-buffer limits and returning owned values.
  `tools/text_probe.py` compiles those pinned rtext.c functions unaltered as a
  reference control.
  `src/fonts.bend` (with `Font.*`, `Draw.text*` and `Draw.fps` in
  `jonlib.bend`) adapts `rtext.c`'s `LoadFontDefault` glyph table (its
  `charsWidth` values unchanged), `LoadFontFromImage`, `GetGlyphIndex`, the
  text measurement and drawing functions and `DrawFPS`, and `rtextures.c`'s
  `ImageText*`/`ImageDrawText*`; `tools/font_probe.py` compiles `DrawFPS`'s
  pinned body unaltered (with `GetFPS()` replaced by a parameter) as a
  reference control.
  `src/input.bend`, `src/gestures.bend`, `src/automation.bend` and
  `src/core_state.bend` (with `Core.*`, `Input.*`, `Gestures.*` and
  `AutomationEventList.*` in `jonlib.bend`) adapt `CORE.Input`, automation
  events, frame timing and `GetFPS` from `rcore.c`, `PollInputEvents` and the
  cursor functions from `src/platforms/rcore_memory.c`, the key/char callbacks
  from `src/platforms/rcore_desktop_glfw.c`, and the gesture state machine of
  `src/rgestures.h` (copyright Ramon Santamaria and contributors; zlib), with
  explicit state and clock arguments. The desktop driver (`Desktop.*`,
  `Core.end_drawing_desktop` in `jonlib.bend`, the desktop polling of
  `src/input.bend` and `src/core_state.bend`) adapts `PollInputEvents` and the
  key, mouse button and cursor position callbacks of
  `src/platforms/rcore_desktop_glfw.c` (same author and license); the programs
  under `examples/` (`core_basic_window`, `core_input_keys`,
  `core_input_mouse`, `core_2d_camera`, `shapes_logo_raylib`,
  `textures_logo_raylib`, `shapes_basic_shapes`) are altered Bend ports of the
  raylib examples of the same names (copyright Ramon Santamaria; zlib/libpng).
  `src/dds.bend` adapts `rl_load_dds_from_memory` and `get_pixel_data_size`
  from `src/external/rltexgpu.h` (same author and zlib license) for DDS files,
  including DXT blocks and mipmap chains; `src/gputex.bend` adapts the same
  file's `rl_load_ktx_from_memory`, `rl_load_pkm_from_memory`,
  `rl_load_pvr_from_memory` and `rl_load_astc_from_memory` for single-level
  files.
  `Image.Formatted.decode_pnm` adapts `LoadImageFromMemory`'s PNM component-to-format
  selection from `rtextures.c`, preserving grayscale/RGB888 in owned Bend storage.
  `Image.Formatted.decode_png` adapts the same source's lines 461–471 for native
  component-to-format 1/2/4/7 selection and implicit single-mip owned storage.
  Owned mipmap-chain generation in `jonlib.bend` adapts `ImageMipmaps` from
  `rtextures.c`, preserving sequential default resampling and dimension order.
  `src/blur.bend` adapts `ImageBlurGaussian` from the same source, retaining its
  sliding-window order, default iteration count and per-pass byte quantization.
  `src/convolution.bend` adapts `ImageKernelConvolution`, preserving flattened
  indexing and accumulation order while rejecting undefined alpha casts.
  `src/base64.bend` adapts the Base64 utilities in `rcore.c`, retaining native
  alphabet/padding and size conventions within the declared input profile.
  `src/checksum.bend` adapts `ComputeMD5` from `rcore.c`, retaining its constants,
  round order, padding and little-endian word layout. The CRC32 utility reuses
  the existing PNG recurrence with the reference initial/final complements.
  `src/sha.bend` adapts the same source's `ComputeSHA1` and `ComputeSHA256`,
  including the pinned SHA-256 padding-size behavior.
  `src/cellular.bend` also adapts `GenImageCellular`, retaining seed order and
  quantization while selecting capped integer squared distances before square root.
  `src/dither.bend` adapts the same source's Floyd-Steinberg dithering and raw
  16-bit packing; pixel-data sizing retains the pinned format table and edge rules.
  `src/formats.bend` adapts byte/integer `ImageFormat` and normalized pixel loading
  from the same pinned source, with owned logical-word storage and explicit byte export.
  `src/mesh.bend`, `src/shapes3d.bend` and the "Models" section of
  `jonlib.bend` adapt `rmodels.c`'s mesh generators (GenMeshPoly, Plane,
  Cube, Heightmap, Cubicmap), GenMeshTangents, GetMeshBoundingBox, the
  ExportMesh/ExportMeshAsCode text (retaining the generated upstream banners
  and credits for exact text parity), GetRayCollisionMesh,
  GetModelBoundingBox, the 3D shape drawing functions and `rcore.c`'s
  BeginMode3D/EndMode3D; `src/par_shapes.bend` adapts par_shapes (below).
  `src/mesh_draw.bend` and the same section adapt DrawMesh (its OpenGL 1.1
  branch), DrawModel(Ex), DrawModelWires(Ex), DrawBillboard(Rec, Pro), the
  material functions (LoadMaterialDefault, IsMaterialValid, UnloadMaterial,
  SetMaterialTexture, SetModelMeshMaterial, IsModelValid) and LoadModel,
  LoadOBJ, ProcessMaterialsOBJ and LoadMaterials; `src/obj.bend` adapts
  tinyobj_loader_c (below).
- Reference testing: `tools/conformance.py` builds a separate raylib executable
  from a locally supplied checkout. Raylib is not linked into the Jonlib runner.
- API documentation: `api/reference.json`, generated `api/ledger.json` and
  `docs/api/` contain extracted/adapted declarations, fields and constant values
  from the pinned `raylib.h`, `raymath.h`, `rlgl.h`, `rcamera.h`, `rgestures.h`
  and `config.h`. These are Jonlib planning documents, not original upstream
  headers. Upstream authorship and the zlib notice above apply to those excerpts.

## stb_image_resize2

- Version 2.18, as vendored by the pinned raylib commit above; header authors
  Jeff Roberts (v2) and Jorge L Rodriguez; MIT notice copyright Sean Barrett.
- Source: <https://github.com/nothings/stb> and raylib's
  `src/external/stb_image_resize2.h` at the pinned revision.
- Jonlib selects the MIT alternative. The complete upstream dual-license notice
  is retained in [LICENSES/stb_image_resize2.txt](LICENSES/stb_image_resize2.txt).
- `src/resample.bend` adapts the default filters, rational phases, coefficient
  normalization/folding/packing, alpha pipeline, operation order and pass-cost
  table to owned Bend values. These are altered implementations. Original
  Jonlib code, including `src/resize_numeric.bend`, remains under zlib.
- `tools/resize_conformance.py` inserts observation-only logging into a local
  diagnostic copy of the pinned header. Kernel and whole-image reference probes
  additionally execute the unmodified upstream header and raylib library.

## stb_truetype and stb_rect_pack

- stb_truetype.h v1.26 and stb_rect_pack.h v1.01 by Sean Barrett and
  contributors, as vendored by the pinned raylib commit above in
  `src/external/`. Source: <https://github.com/nothings/stb>.
- Jonlib selects the MIT alternative; the complete dual-license notice is
  retained in [LICENSES/stb_truetype.txt](LICENSES/stb_truetype.txt).
- `src/truetype.bend` is an altered Bend adaptation of stb_truetype's font
  initialization, cmap lookup (formats 0, 4, 6, 12, 13), TrueType glyph
  shapes (simple and composite), metrics, curve flattening, edge sort,
  version-2 antialiasing rasterizer and line-only signed distance fields,
  with every read bounds-checked and undefined behavior refused.
  `src/font_data.bend` adapts stb_rect_pack's skyline bottom-left packer
  together with raylib's `LoadFontData`, `GenImageFontAtlas`,
  `LoadFontDataBDF` and `LoadBMFont` from `rtext.c` (zlib, above).
- `tools/ttf_probe.py` links the unmodified headers only through the pinned
  raylib reference library; no stb code is linked into the Bend candidate.

## FreeBSD qsort and heapsort (Apple Libc)

`src/font_data.bend` reproduces the order Apple's C library `qsort` gives
stb_rect_pack's rectangles by adapting the FreeBSD `qsort.c` and
`heapsort.c` algorithms as Apple's Libc ships them
(<https://github.com/apple-oss-distributions/Libc>, `stdlib/FreeBSD/`):
the introsort depth limit, pseudomedian selection, three-way partition,
bounded insertion sort and heapsort fallback. These are altered Bend
implementations; the BSD notices (copyright The Regents of the University of
California) are retained in [LICENSES/freebsd-sort.txt](LICENSES/freebsd-sort.txt).

## Test fonts

`tools/ttf_fonts.py` generates every TrueType font the `ttf` gate builds; the
gate also reads `anonymous_pro_bold.ttf` (Mark Simonson) and
`DotGothic16-Regular.ttf` (The DotGothic16 Project Authors), both under the
SIL Open Font License, in place from the pinned raylib checkout's
`examples/text/resources/` (see its `LICENSE.md`). No font file is
redistributed by Jonlib.

## Example assets

`examples/textures_logo_raylib.bend` and the `examples` gate read
`raylib_logo.png` in place from the pinned raylib checkout's
`examples/textures/resources/` (the raylib logo, by Ramon Santamaria; its
`LICENSE.md` does not list it). No image file is redistributed by Jonlib.

## sdefl

- Author: Micha Mettke, copyright 2020-2023.
- Source: `src/external/sdefl.h` at the pinned raylib revision.
- Jonlib selects the MIT alternative, retained in [LICENSES/sdefl.txt](LICENSES/sdefl.txt).
- `src/sdeflate_huffman.bend` is an altered Bend adaptation of the native
  canonical-Huffman construction, with owned arrays and equivalent packed-key
  sorting. `src/sdeflate_lz.bend` adapts quality-8 hash-chain parsing, lazy matches,
  sequences and frequencies; `src/sdeflate.bend` adapts precode generation,
  dynamic/stored selection and raw block emission to owned Bend values.
- `tools/sdeflate_probe.py` adds observation-only hooks to a task-local header
  copy. Its complete compressed output must match actual linked `CompressData`
  before sequence/frequency observations are used as parity evidence.

## QOI

`src/qoi.bend` is an altered Bend adaptation of the codec in raylib's pinned
`src/external/qoi.h`, by Dominic Szablewski. It uses owned arrays and immutable
input bytes, bounds allocations to the checked image profile, normalizes RGB
to RGBA8 for Surface callers and preserves RGB888/RGBA8888 for formatted callers.
Its channel-aware encoder preserves native RGB/RGBA headers and opcode rules;
Surface encoding retains a four-channel header. The formatted adapter rejects
unsupported original formats, canonicalizes RGB alpha to opaque and emits
colorspace zero. Malformed streams are reported explicitly. QOI's MIT notice and license
are retained in [LICENSES/qoi.txt](LICENSES/qoi.txt). The standalone C implementation
is used only by reference tooling; it is not linked into Jonlib's implementation.

## stb_image and stb_image_write

`src/bmp.bend`, `src/tga.bend`, `src/pnm.bend`, `src/png.bend`, `src/psd.bend`,
`src/pic.bend`, `src/gif.bend`, `src/gif_lzw.bend`, `src/gif_animation.bend`,
`src/hdr.bend` and `src/jpeg.bend` are altered, bounded Bend
adaptations of the BMP/TGA readers and writers and PNM/PNG/PSD/PIC/GIF/HDR/JPEG readers
in pinned raylib's `src/external/stb_image.h` and `stb_image_write.h`, by Sean
Barrett and contributors. Jonlib selects their MIT alternative, retained in
[LICENSES/stb-image.txt](LICENSES/stb-image.txt). It uses owned arrays and explicit
byte validation, preserves the exercised native pixel/export rules, and rejects
unsupported or truncated inputs. The native headers are used only by reference
tooling; no stb implementation is linked into the Bend candidate.
The formatted TGA channel-aware writer adapts `stb_image_write.h` lines 532–603
and the raylib `ExportImage`/`LoadImageColors` routing, retaining its row-bounded
RLE scan and component ordering in owned Bend arrays.
The formatted TGA memory adapter preserves the altered reader's checked rules,
adapting `stb_image.h` lines 5739–5753 and 5905–5922 for native output channels.
Indexed output uses palette depth independently of input index width; integer
packing retains native gray/gray-alpha/expanded RGB/RGBA output.
The formatted BMP memory adapter preserves the altered reader's checked rules,
adapting `stb_image.h` lines 5422–5443, 5482–5515, 5584–5591, 5707–5710 and
5728–5730 with raylib `rtextures.c` lines 461–471. Effective alpha-mask layout
retains native RGB/RGBA metadata independently of source bit depth or alpha
repair; integer packing preserves exact component bytes in owned Bend arrays.
The PNM formatted-memory adapter retains the altered `src/pnm.bend` reader's
checked header/byte/size rules and little-endian 16-to-8-bit reduction, adapting
`stb_image.h`'s `stbi__pnm_load` and `stbi__convert_16_to_8` behavior with integer
packing. It preserves native grayscale/RGB888 output rather than source depth.
The PNG formatted-memory adapter retains the altered `src/png.bend` reader's
checked domain, adapting `stb_image.h` lines 5119–5234 and 5284–5286 for native
component metadata, structural tRNS promotion and sticky palette channels across
later PLTE. Lines 1190–1203 and 1260–1273 supply final 16-to-8-bit high-byte
reduction after full-width transparency comparison; lines 4993–4994 and
5222–5223 retain the disabled CgBI conversion defaults. Integer packing exposes
exact grayscale/gray-alpha/RGB/RGBA bytes in owned Bend storage.
`tools/png_format_probe.py` executes the pinned unmodified reader only as an
independent native reference; its admission checks and observation protocol do
not link native PNG code into the Bend implementation.
The PIC formatted-memory adapter retains the altered `src/pic.bend` reader's
checked domain, adapting `stb_image.h` lines 6390–6416 and 6500–6538 with raylib
`rtextures.c` lines 461–471. The union of every validated packet channel mask
retains native RGB/RGBA metadata independently of output opacity or selected
input-sample totals. Integer repacking reuses owned Bend storage. The unmodified
native reader is only a reference; independently admitted complete inputs avoid
its failed-decode null-source conversion path.
The dedicated PIC file adapter reuses that unchanged checked decoder through
the existing bounded Base IO reader. Its file reference tooling additionally
anchors unmodified raylib `rtextures.c` file dispatch and `rcore.c` reads/token
selection; no native code is linked into the Bend implementation.
The upstream Softimage PIC reader credits Tom Seddon.
The upstream GIF reader credits Jean-Marc Lienher, with simplification by stb.
The upstream Radiance RGBE HDR reader credits Nicolas Schulz.

`src/inflate.bend` adapts the canonical DEFLATE decoding rules from the same
stb header to bounded owned output and tail-recursive extraction. Its raw API
also retains the observed empty-stored-block completion rule of raylib's
`DecompressData`. Native sinfl, stb and zlib are reference tooling only.

`src/png_encode.bend` and `src/deflate.bend` adapt the default PNG filter heuristic,
quality-8 zlib compressor, stored fallback and checksums from the same pinned
`stb_image_write.h`, with owned Bend input/dictionary arrays and byte lists.
The retained stb MIT notice applies to these altered implementations too.

## dr_wav

`src/wav.bend` and `src/wav_adpcm.bend` are altered Bend adaptations of
`drwav_init_memory` (container detection and the RIFF, RIFX, Wave64, RF64 and
AIFF/AIFC chunk walks, including `drwav_aiff_extented_to_s64`) and
`drwav_read_pcm_frames_s16` (PCM, 32- and 64-bit float, a-law, mu-law, MS
ADPCM and IMA ADPCM, including dr_wav's conversion, coefficient, adaptation,
index and step tables) from pinned raylib's `src/external/dr_wav.h` by David
Reid, and `Wave.to_wav` reproduces its RIFF writer's header. dr_wav is
public domain or MIT No Attribution; Jonlib uses the MIT-0 alternative,
retained in [LICENSES/dr_wav.txt](LICENSES/dr_wav.txt).
`Wave.*` in `jonlib.bend` adapts the Wave functions of raylib's `raudio.c`.

## miniaudio

`src/convert.bend`, `src/resampler.bend` and `src/lowpass.bend` are altered
Bend adaptations of the paths raylib's `WaveFormat` reaches through
`ma_convert_frames` in pinned raylib's `src/external/miniaudio.h` (miniaudio
v0.11.24 by David Reid): `ma_data_converter` path selection, the u8/s16/f32
`ma_pcm_*` conversions, `ma_channel_converter` with the default channel maps
and rectangular weights, and `ma_linear_resampler` with its order-4
`ma_lpf`/`ma_biquad` low-pass filter. The filter coefficients use Jonlib's own
fixed-point sine bracket instead of libm `sin`. miniaudio is public domain or
MIT No Attribution; Jonlib uses the MIT-0 alternative, retained in
[LICENSES/miniaudio.txt](LICENSES/miniaudio.txt).

## QOA

`src/qoa.bend` is an altered Bend adaptation of `qoa_decode` and `qoa_encode`
(its LMS filter, scalefactor search and tables) from pinned raylib's
`src/external/qoa.h`, by Dominic Szablewski. It uses U32 two's-complement
words for C ints and refuses files qoa.h would decode past its buffers. QOA's
MIT notice and license are retained in [LICENSES/qoa.txt](LICENSES/qoa.txt).

## rlsw

`src/frame.bend` is an altered Bend adaptation of pinned raylib's
`src/external/rlsw.h` 1.5, the OpenGL 1.1-style software renderer by Le Juez
Victor (reviewed by Ramon Santamaria): its matrix stacks and products, vertex
transform, face culling, polygon and line clipping (with the scissor),
projection, axis-aligned quad, triangle and line rasterizers, texel readers,
nearest and bilinear texture sampling, SRC_ALPHA/ONE_MINUS_SRC_ALPHA
blending, scissored clears, framebuffer objects and object pools, scalar and
uncontracted, refusing its undefined float-to-int and uint8 conversions and
out-of-bounds reads. It also adapts the rlgl.h OpenGL 1.1 immediate path and
texture/framebuffer calls that drive rlsw; `src/shapes.bend` adapts the
`rshapes.c` shape functions and `src/textures.bend` the `rtextures.c` texture
drawing and rlsw's translate/rotate/scale matrices (raylib, zlib notice
above). `src/frame_font.bend` holds `rtext.c`'s
`defaultFontData` bitmap unchanged (raylib, zlib). rlsw's MIT notice and
license are retained in [LICENSES/rlsw.txt](LICENSES/rlsw.txt).

## par_shapes

- Author: Philip Rideout. Source: <https://github.com/prideout/par>, as
  vendored by the pinned raylib commit in `src/external/par_shapes.h`.
- License: MIT; the notice is retained in [LICENSES/par_shapes.txt](LICENSES/par_shapes.txt).
- `src/par_shapes.bend` is an altered Bend adaptation of its parametric
  sphere, hemisphere and torus generators, `par_shapes_weld` (grid sort, point
  welding and condensing), `par_shapes_compute_normals` and
  `par_shapes_remove_degenerate`, used by `GenMeshSphere`,
  `GenMeshHemiSphere` and `GenMeshTorus`. The qsort it calls is modeled as
  glibc's stable merge sort.

## tinyobj_loader_c

- Author: Syoyo Fujita and many contributors. Source:
  <https://github.com/syoyo/tinyobjloader-c>, as vendored by the pinned raylib
  commit in `src/external/tinyobj_loader_c.h` (with raylib's local changes).
- License: MIT; the notice is retained in
  [LICENSES/tinyobj_loader_c.txt](LICENSES/tinyobj_loader_c.txt).
- `src/obj.bend` is an altered Bend adaptation of its OBJ line splitting,
  `parseLine`, `tryParseDouble` (evaluated with Jonlib's checked binary64
  helpers), `my_atoi`, `fixIndex`, triangulation, the djb2 material hash table,
  the MTL parser (`tinyobj_parse_and_index_mtl_file`, `dynamic_fgets` line
  semantics) and the shape construction, used by `Model.load_for` and
  `Material.load_materials_for`.

## Arm numerical routines

The GNU-reference polynomial in `src/trig.bend` and its independent C control
in `tools/trig_probe.py` adapt `math/sincosf.h` and `math/sincosf_data.c` from
[Arm optimized-routines at 47597821aaa52e9c055caf1ecf8f3aecfd751cd9](https://github.com/ARM-software/optimized-routines/tree/47597821aaa52e9c055caf1ecf8f3aecfd751cd9).
`src/power.bend` and the C model in `tools/spline_cubic_probe.py` adapt
`math/powf.c`, `math/powf_log2_data.c` and `math/exp2f_data.c` (as glibc 2.39
ships them on x86_64) at the same revision, for `powf(x, 2)` and `powf(x, 3)`
on [-0, 1].
These are altered Bend/tooling implementations, limited to the documented
gradient/rotation and power profiles. Jonlib selects the upstream MIT alternative; source copyright
notices and the selected license are retained in [LICENSES/arm-math.txt](LICENSES/arm-math.txt).

## Arctangent numerical references

- The Apple-profile mathematical polynomial, coefficient values and numerical
  boundary rules are documented by Eric Postpischil (July 2007) in
  [Apple Libm atan2f.s at 17a5f9daa3f5679f7536b26f133b40cc078753c3](https://github.com/apple-oss-distributions/Libm/blob/17a5f9daa3f5679f7536b26f133b40cc078753c3/Source/Intel/atan2f.s).
  `src/angle.bend` independently evaluates that mathematical specification using
  original Bend argument reduction and integer-limb arithmetic. No assembly
  implementation is copied or included.
- The GNU float atan/atan2 profile and independent C control adapt the Sun
  algorithms in glibc 2.39, revision `ef321e23c20eebc6d6fb4044425c00e6df27b05f`,
  `sysdeps/ieee754/flt-32/s_atanf.c` and `e_atan2f.c`. Their explicit permissive
  grant is retained in [LICENSES/sun-math.txt](LICENSES/sun-math.txt). These are
  altered implementations; floating-point exception-state behavior is outside
  the current numeric profile.

## Modern finite arctangent kernel

`src/modern_angle.bend` is an altered private Bend adaptation of the complete
finite-input RN-even scalar algorithm in
[glibc 2.41 e_atan2f.c](https://github.com/bminor/glibc/blob/74f59e9271cbb4071671e5a474e7d4f1622b186f/sysdeps/ieee754/flt-32/e_atan2f.c),
Copyright (c) 2022–2024 Alexei Sibidanov and Paul Zimmermann. The original file
identifies CORE-MATH revision `7835c5d`; this abbreviation is not an independently
verified full commit ID. The verified glibc release pin is
`74f59e9271cbb4071671e5a474e7d4f1622b186f`, Git blob
`82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4`, SHA-256
`96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38`.

The complete MIT notice is retained in the Bend file, the tooling original and
adaptation, and [LICENSES/core-math-atan2f.txt](LICENSES/core-math-atan2f.txt).
`tools/reference/modern_atan2f_glibc241.c` is the unmodified pinned source;
`modern_atan2f_adapted.c` adds observation-only branch/intermediate traces and a
finite-input boundary for reference tooling; both are compiled only by
`tools/angle_kernel_probe.py` as the native oracle. Neither C
implementation is linked into the Bend candidate. No glibc LGPL testcase table
is copied; controls are independently generated. See [the private contract](docs/MODERN-ANGLE.md).

## stb_perlin

`src/perlin.bend` is an altered Bend adaptation of stb_perlin.h v0.5 from pinned
raylib, Copyright (c) 2017 Sean Barrett, with fractal/seed contributions by Jack
Mott and Jordan Peck. Jonlib selects the MIT alternative retained in
[LICENSES/stb-perlin.txt](LICENSES/stb-perlin.txt). The original lookup tables
are packed into U32 words; arithmetic uses explicit reference profiles.

## rprand

`src/random.bend` is an altered Bend adaptation of pinned raylib's
`src/external/rprand.h` (rprand 1.0), Copyright (c) 2023 Ramon Santamaria.
Its SplitMix64 initialization and Xoshiro128** stepping preserve the reference
sequence. The zlib/libpng notice and David Blackman/Sebastiano Vigna algorithm
dedications are retained in [LICENSES/rprand.txt](LICENSES/rprand.txt).

## Bend

Jonlib uses the Bend language and Base library, provided by HigherOrderCO and
contributors under Apache-2.0. No Bend3D implementation or demo assets are vendored.

The compiler overlay in `patches/bend-metal-dispatch.patch` adapts Bend's
`bend2/comp.ts` and includes an original regression test and local-spec ignore
entry. It is based on `b7ebee9217c8813067e200b0c0c9153a3be31c5e` and is distributed
under **Apache-2.0**, including its modifications. The original copyright is
2026 HigherOrderCO; the modifications were authored for Jonathan Peris's Jonlib
project in 2026. The modified compiler carries a change notice.

The upstream license is retained verbatim in [LICENSES/bend.txt](LICENSES/bend.txt).
No upstream NOTICE file was present at the base revision. This overlay is not
an upstream-approved Bend release. See [patches/README.md](patches/README.md) for
provenance and application instructions. Distributions containing Bend runtime
artifacts must also retain their applicable Apache-2.0 notices.

## Sun float acosf

`src/inverse_trig.bend` is an altered Bend adaptation of the Sun float `acosf`
as shipped in glibc 2.39 (`sysdeps/ieee754/flt-32/e_acosf.c`, commit
`ef321e23c20eebc6d6fb4044425c00e6df27b05f`), keeping its constants, branches
and operation order. `tools/reference/acos_sources/sun_e_acosf.c` is the exact
original (SHA-256 `60a8c9b2d14409971adc930bfa386014230e3c7e21a8cd1fdc8178128800d8ba`),
compiled only by reference tooling. Its Sun notice is retained there and in
[LICENSES/sun-math.txt](LICENSES/sun-math.txt). glibc 2.39's `e_asinf.c` is not
adapted: its single-precision modifications are LGPL-2.1+.

## Native angle qualification source controls

`tools/reference/angle_sources/sun_e_atan2f.c` and `sun_s_atanf.c` are exact
Sun-permission originals from glibc 2.39 commit
`ef321e23c20eebc6d6fb4044425c00e6df27b05f`. Their original notices and the existing
[Sun notice](LICENSES/sun-math.txt) are retained. The modern reference remains the
unchanged MIT file identified above. Qualification metadata and rational audit
helpers are original tooling; none is linked into the Bend library.

The independently derived Apple control facts cite the pinned July 2007 source,
its author and SHA-256 in the manifest. This slice does not redistribute that
source or the local assembly adaptation because a covering license was not
verified. See [qualification provenance](docs/ANGLES.md).
