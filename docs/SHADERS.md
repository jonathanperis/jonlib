# Shaders

raylib's shader API is delivered as the software renderer runs it. Jonlib's
reference is raylib on `PLATFORM=Memory`, whose `rlgl.h` takes the OpenGL 1.1
path into `rlsw`; `rlgl.h` compiles shader programs, uniforms and program
binding only for OpenGL 3.3 and ES2. On this path:

- `rlLoadShaderProgram` and `rlGetShaderIdDefault` return 0, and
  `rlGetLocationUniform` / `rlGetLocationAttrib` return -1;
- `rlSetShader`, `rlEnableShader` and every `rlSetUniform*` do nothing.

So `LoadShaderFromMemory` always takes its failure branch: id 0 and
`RL_MAX_SHADER_LOCATIONS` (32) locations of -1. Shader code is never compiled
and drawing inside `BeginShaderMode`/`EndShaderMode` is drawing with the fixed
pipeline, as the probe checks pixel by pixel.

| raylib | Jonlib | Result |
|---|---|---|
| `LoadShader(vs, fs)` | `Shader.load(vs, fs)` (`Maybe<String>` paths, `None` for NULL) | `Shader{0, 32 x -1}` |
| `LoadShaderFromMemory(vs, fs)` | `Shader.load_from_memory(vs, fs)` | the same |
| `IsShaderValid` | `Shader.is_valid(shader)` | `id > 0`: `False` |
| `UnloadShader` | `Shader.unload(shader)` | nothing to free |
| `GetShaderLocation` / `GetShaderLocationAttrib` | `Shader.get_location(shader, name)` / `get_location_attrib` | -1 (`4294967295`) |
| `SetShaderValue` / `V` / `Matrix` / `Texture` | `Shader.set_value(shader, loc, words, type)`, `set_value_v(..., count)`, `set_value_matrix(shader, loc, matrix)`, `set_value_texture(shader, loc, info)` | the shader unchanged |
| `BeginShaderMode` / `EndShaderMode` | `Frame.begin_shader_mode(frame, shader)` / `Frame.end_shader_mode(frame)` | the frame unchanged |

C ints are `U32` two's complement. `LoadShader` reads its files with
`LoadFileText` before discarding the text; Jonlib's form takes the paths only.
Assigning a shader to a material (`model.materials[0].shader = shader`) has no
Jonlib field: the software renderer's `DrawMesh` never binds one.

## Gaps

- An OpenGL 3.3/ES2 (or GPU) rendering path, where shaders run, is not a
  Jonlib target.
- `LoadShader`'s trace-log warnings for missing files are not reproduced.

## Verification

`tools/shader_probe.py` (gate `shader`) prints, natively and in Jonlib, the id,
the 32 locations, `IsShaderValid` and two lookups of shaders loaded from
missing files, from code and from NULLs, and draws the same scene natively
with and without `BeginShaderMode` (every `SetShaderValue*` form included),
requiring equal color buffers.

The `examples-shaders` gate replays the ported shader examples frame by frame
against the unmodified native examples ([DRIVER.md](DRIVER.md)):
`shaders_basic_lighting`, `shaders_eratosthenes_sieve`, `shaders_julia_set`,
`shaders_mandelbrot_set`, `shaders_multi_sample2d`, `shaders_palette_switch`,
`shaders_raymarching_rendering`, `shaders_rounded_rectangle`,
`shaders_shapes_textures`, `shaders_texture_outline`,
`shaders_texture_rendering`, `shaders_texture_tiling` and
`shaders_texture_waves`. State that only reaches a shader's uniforms (zoom,
offsets, palettes, run time, a camera used only as a uniform) changes no
pixel there, so the ports that do not track it say so.
