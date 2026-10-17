# Jonlights - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of rlights.h as raylib 6.0's examples ship it
# (examples/shaders/rlights.h and examples/models/rlights.h, the same file;
# zlib/libpng, Copyright (c) 2017-2024 Victor Fisac (@victorfisac) and Ramon
# Santamaria (@raysan5)); see LICENSES/rlights.txt. Jonlights is to rlights.h
# what Jonlib is to raylib.h: rlights' static lightsCount is a Lights value
# the program threads. See docs/LIGHTS.md.
import Base
import ./jonmath.bend as M
import ./jonlib.bend as J

# MAX_LIGHTS: the lights the shader takes.
def Light.MAX_LIGHTS() -> U32:
  4

# LightType.
def LightType.LIGHT_DIRECTIONAL() -> U32:
  0

def LightType.LIGHT_POINT() -> U32:
  1

# Light: its type, state, position, target, color (a Color word) and
# attenuation (never set by rlights: 0), and its shader locations.
type Light is Data:
  Light{kind: U32, enabled: Bool, position: M.Vector3, target: M.Vector3, color: U32, attenuation: F32, enabled_loc: U32, type_loc: U32, position_loc: U32, target_loc: U32, color_loc: U32, attenuation_loc: U32}

# rlights' lightsCount: the lights created so far.
type Lights is Data:
  Lights{count: U32}

def Lights.new() -> Lights:
  Lights{0}

def Lights.count(+lights: Lights) -> U32:
  Lights{+count} = lights
  count

# Light light = { 0 }.
def Light.zero() -> Light:
  Light{0, False{}, M.Vector3.zero(), M.Vector3.zero(), 0, 0.0, 0, 0, 0, 0, 0, 0}

# TextFormat("lights[%i].<field>", lightsCount).
def Light.uniform(+index: U32, field: String) -> String:
  "lights[" ++ U32.show(index) ++ "]." ++ field

# A float component of the color: (float)c/(float)255.
def Light.channel(+value: U32) -> U32:
  F32.bits((U32.to_f32(value) / 255.0 : F32))

# UpdateLightValues(shader, light): the enabled state and type as ints, the
# position and target as vec3 and the color as a vec4 of (float)c/255 go to
# their locations (SetShaderValue; -1 skips one, and the software renderer
# ignores the others).
def Light.update_values(+shader: J.Shader, +light: Light) -> J.Shader:
  Light{+kind, +enabled, +position, +target, +color, _, +enabled_loc, +type_loc, +position_loc, +target_loc, +color_loc, _} = light
  M.Vector3{+px, +py, +pz} = position
  M.Vector3{+tx, +ty, +tz} = target
  +s1 = J.Shader.set_value(shader, enabled_loc, [Bool.to_u32(enabled)], J.ShaderUniformDataType.SHADER_UNIFORM_INT())
  +s2 = J.Shader.set_value(s1, type_loc, [kind], J.ShaderUniformDataType.SHADER_UNIFORM_INT())
  +s3 = J.Shader.set_value(s2, position_loc, [F32.bits(px), F32.bits(py), F32.bits(pz)], J.ShaderUniformDataType.SHADER_UNIFORM_VEC3())
  +s4 = J.Shader.set_value(s3, target_loc, [F32.bits(tx), F32.bits(ty), F32.bits(tz)], J.ShaderUniformDataType.SHADER_UNIFORM_VEC3())
  J.Shader.set_value(s4, color_loc, [Light.channel((color >> 24n : U32)), Light.channel(((color >> 16n) .&. 255 : U32)), Light.channel(((color >> 8n) .&. 255 : U32)), Light.channel((color .&. 255 : U32))], J.ShaderUniformDataType.SHADER_UNIFORM_VEC4())

def Light.located(+index: U32, +kind: U32, +position: M.Vector3, +target: M.Vector3, +color: U32, +shader: J.Shader) -> Light:
  Light{kind, True{}, position, target, color, 0.0,
    J.Shader.get_location(shader, Light.uniform(index, "enabled")), J.Shader.get_location(shader, Light.uniform(index, "type")),
    J.Shader.get_location(shader, Light.uniform(index, "position")), J.Shader.get_location(shader, Light.uniform(index, "target")),
    J.Shader.get_location(shader, Light.uniform(index, "color")), 0}

def Light.create.made(+count: U32, +light: Light, +shader: J.Shader) -> (Lights & Light) & J.Shader:
  ((Lights{(count + 1 : U32)}, light), Light.update_values(shader, light))

def Light.create.at(below: Bool, +count: U32, +kind: U32, +position: M.Vector3, +target: M.Vector3, +color: U32, +shader: J.Shader) -> (Lights & Light) & J.Shader:
  match below:
    case False{}: ((Lights{count}, Light.zero()), shader)
    case True{}: Light.create.made(count, Light.located(count, kind, position, target, color, shader), shader)

# CreateLight(type, position, target, color, shader): below MAX_LIGHTS, an
# enabled light with the shader's locations for lights[lightsCount] (sent with
# UpdateLightValues) and lightsCount + 1; at MAX_LIGHTS, a zero light and the
# count unchanged. The color is a Color word (0xRRGGBBAA).
def Light.create(lights: Lights, +kind: U32, +position: M.Vector3, +target: M.Vector3, +color: U32, +shader: J.Shader) -> (Lights & Light) & J.Shader:
  Lights{+count} = lights
  Light.create.at((count < Light.MAX_LIGHTS() : U32), count, kind, position, target, color, shader)
