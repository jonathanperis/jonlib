# Jonlights: rlights.h

`jonlights.bend` ports `rlights.h`, the lighting helper raylib 6.0's shader
and model examples ship (`examples/shaders/rlights.h`, the same file as
`examples/models/rlights.h`; notice in
[LICENSES/rlights.txt](../LICENSES/rlights.txt)):

```bend
import ./jonlib.bend as J
import ./jonlights.bend as L
```

| rlights.h | Jonlights |
|---|---|
| `MAX_LIGHTS` (4) | `L.Light.MAX_LIGHTS()` |
| `LightType` (`LIGHT_DIRECTIONAL`, `LIGHT_POINT`) | `L.LightType.LIGHT_DIRECTIONAL()`, `L.LightType.LIGHT_POINT()` |
| `Light` | `L.Light{kind, enabled, position, target, color, attenuation, enabled_loc, type_loc, position_loc, target_loc, color_loc, attenuation_loc}` (`type` is a Bend keyword: the field is `kind`; the color is a Color word) |
| `lightsCount` (static) | `L.Lights`, from `L.Lights.new()`; `L.Lights.count(lights)` |
| `CreateLight(type, position, target, color, shader)` | `L.Light.create(lights, kind, position, target, color, shader) -> (Lights & Light) & Shader` |
| `UpdateLightValues(shader, light)` | `L.Light.update_values(shader, light) -> Shader` |

- **The count is a value.** rlights keeps `lightsCount` in a static variable
  shared by every shader; Jonlights threads it as `Lights`, so a program
  passes the value `Light.create` returns to its next call.
- **Below `MAX_LIGHTS`** a light is enabled, takes its arguments and the
  shader's locations for `lights[i].enabled`, `type`, `position`, `target` and
  `color` (`GetShaderLocation`; -1 on the software renderer, which has no
  shaders, [SHADERS.md](SHADERS.md)), is sent with `UpdateLightValues`, and
  the count grows. From `MAX_LIGHTS` on, `CreateLight` returns a zero light
  (`Light light = { 0 }`: disabled, black, every location 0) and the count
  stays.
- **`attenuation` and `attenuationLoc`** are never set by rlights: 0.
- **`UpdateLightValues`** sends the enabled state and type as ints, the
  position and target as vec3 and the color as a vec4 of `(float)c/255`
  through `SetShaderValue`; the software renderer ignores every uniform, so
  the shader is returned unchanged. raylib reads the bool `enabled` through an
  `int*` (four bytes from a one-byte field); Jonlights sends 0 or 1.
- **C glue.** `RLIGHTS_H` and `RLIGHTS_IMPLEMENTATION` are the module import.

Coverage is tracked in `api/jonlights.json`. `tools/lights_probe.py` (gate
`lights`) links rlights.h with the gates' raylib build, creates six lights
(four created, two past `MAX_LIGHTS`) on the default shader and compares
every field and the shader's id.
