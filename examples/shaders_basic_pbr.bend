# raylib [shaders] example - basic pbr, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_basic_pbr.c (zlib/libpng,
# Copyright (c) 2023-2025 Afan OLOVCIC (@_DevDad)); see LICENSES/raylib.txt.
#
# An old car and a floor (LoadModel of two .glb files) under four point
# lights, with a PBR shader and its albedo, metalness, normal and emission
# maps (seven 1024x1024 PNG textures). The reference's software renderer
# runs no shader (docs/SHADERS.md): the models are drawn with their
# material's diffuse map alone, the albedo texture, and the lights are the
# spheres that mark them (solid when enabled, wires when a key 1 to 4 turned
# them off). The car's body and the floor have no material in their files,
# so they take materials[0], the one the example dresses; the other maps and
# the values the shader would read are set on the material all the same.
# A light's color is its Color divided by 255 and multiplied back for the
# sphere, as the example does ((unsigned char)(color[i]*255)). The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md),
# UpdateCamera and the spheres its sinf/cosf (docs/SINCOSF.md). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: everything loaded and no refusal so far. lights has bit i set while lights[i] is enabled.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, car: J.Model, floor: J.Model, textures: List<J.Texture>, lights: U32}

# The textures loaded so far: ok (each one loaded), the textures and their infos, the last one first.
type Got is Type:
  Got{frame: J.Frame, ok: Bool, textures: List<J.Texture>, infos: +List<J.TextureInfo>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 2.0, 6.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# if (IsKeyPressed(key)) lights[i].enabled = !lights[i].enabled.
def toggled(+core: J.Core, +key: U32, +bit: U32, +lights: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, key), U32.xor(lights, bit), lights)

# KEY_ONE toggles lights[2], KEY_TWO lights[1], KEY_THREE lights[3] and KEY_FOUR lights[0].
def switched(+core: J.Core, +lights: U32) -> U32:
  toggled(core, 52, 1, toggled(core, 51, 8, toggled(core, 50, 2, toggled(core, 49, 4, lights))))

def update.moved(moved: Maybe<J.Camera3D>, +core: J.Core, +car: J.Model, +floor: J.Model, textures: List<J.Texture>, +lights: U32) -> State:
  match moved:
    case None{}: State{False{}, None{}, car, floor, textures, lights}
    case Some{+c}: State{True{}, Some{c}, car, floor, textures, switched(core, lights)}

# UpdateCamera(&camera, CAMERA_ORBITAL), then the keys.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +car: J.Model, +floor: J.Model, textures: List<J.Texture>, +lights: U32) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), core, car, floor, textures, lights)
    case _ _: State{False{}, None{}, car, floor, textures, lights}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +car, +floor, textures, +lights} = state
  (core, update.live(valid, camera, libm, core, car, floor, textures, lights))

# (unsigned char)(((float)channel/255.0f)*255).
def channel(+value: U32) -> U32:
  F32.to_u32(((U32.to_f32(value) / 255.0) * 255.0 : F32))

# lightColor: the light's normalized color back as bytes.
def shade(+color: U32) -> U32:
  ((channel((color >> 24n : U32)) << 24n) .|. (channel(((color >> 16n) .&. 255 : U32)) << 16n) .|. (channel(((color >> 8n) .&. 255 : U32)) << 8n) .|. channel((color .&. 255 : U32)) : U32)

# if (lights[i].enabled) DrawSphereEx(position, 0.2f, 8, 8, lightColor); else DrawSphereWires(position, 0.2f, 8, 8, ColorAlpha(lightColor, 0.3f)).
def light(on: Bool, +libm: M.Libm, frame: J.Frame, +x: F32, +y: F32, +z: F32, +color: U32) -> J.Frame:
  match on:
    case True{}: J.Draw.sphere_ex_for(libm, frame, M.Vector3{x, y, z}, 0.2, 8.0, 8.0, shade(color))
    case False{}: J.Draw.sphere_wires_for(libm, frame, M.Vector3{x, y, z}, 0.2, 8.0, 8.0, J.Color.with_alpha(shade(color), 0.3))

def lit(+lights: U32, +bit: U32) -> Bool:
  U32.is_ne((lights .&. bit : U32), 0)

# The four lights: yellow at (-1, 1, -2), green at (2, 1, 1), red at (-2, 1, 1) and blue at (1, 1, -2).
def draw.lights(+libm: M.Libm, +lights: U32, frame: J.Frame) -> J.Frame:
  f1 = light(lit(lights, 1), libm, frame, F32.neg(1.0), 1.0, F32.neg(2.0), J.Color.YELLOW())
  f2 = light(lit(lights, 2), libm, f1, 2.0, 1.0, 1.0, J.Color.GREEN())
  f3 = light(lit(lights, 4), libm, f2, F32.neg(2.0), 1.0, 1.0, J.Color.RED())
  light(lit(lights, 8), libm, f3, 1.0, 1.0, F32.neg(2.0), J.Color.BLUE())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# The lights' spheres, EndMode3D() and the texts.
def draw.car(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +car: J.Model, +floor: J.Model, +lights: U32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Draw.text(J.Frame.end_mode_3d(draw.lights(libm, lights, frame)), "Toggle lights: [1][2][3][4]", 10.0, 40.0, 20.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.text(f1, "(c) Old Rusty Car model by Renafox (https://skfb.ly/LxRy)", 480.0, 430.0, 10.0, J.Color.LIGHTGRAY())
  draw.fps.done(State{True{}, Some{camera}, car, floor, textures, lights}, f2, J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawModel(car, (0, 0, 0), 0.25f, WHITE).
def draw.floor(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +car: J.Model, +floor: J.Model, +lights: U32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.car(libm, core, camera, car, floor, lights, J.Draw.model(frame, textures, car, M.Vector3.zero(), 0.25, J.Color.WHITE()))

# ClearBackground(BLACK); BeginMode3D(camera); DrawModel(floor, (0, 0, 0), 5.0f, WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +car: J.Model, +floor: J.Model, textures: List<J.Texture>, +lights: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}:
      draw.floor(libm, core, c, car, floor, lights, J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.BLACK()), c), textures, floor, M.Vector3.zero(), 5.0, J.Color.WHITE()))
    case _ _: (core, (State{False{}, None{}, car, floor, textures, lights}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +car, +floor, textures, +lights} = state
  draw.at(valid, camera, libm, core, car, floor, textures, lights, frame)

# The main loop's body; libm is the profile of UpdateCamera's and the spheres' sinf/cosf and of the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# materials[0].maps[index] as the example sets it: the albedo color WHITE and its texture; the metalness value
# and texture; the normal texture; the roughness value; the occlusion value 1; the emission color and texture.
def map.set(index: U32, +texture: J.TextureInfo, +color: U32, +value: F32, +albedo: J.TextureInfo, +metalness: J.TextureInfo, +normal: J.TextureInfo, +emission: J.TextureInfo, +metal: F32, +rough: F32,
    +glow: U32) -> J.MaterialMap:
  match index:
    case 0: J.MaterialMap{albedo, J.Color.WHITE(), value}
    case 1: J.MaterialMap{metalness, color, metal}
    case 2: J.MaterialMap{normal, color, value}
    case 3: J.MaterialMap{texture, color, rough}
    case 4: J.MaterialMap{texture, color, 1.0}
    case 5: J.MaterialMap{emission, glow, value}
    case _: J.MaterialMap{texture, color, value}

def maps.set(maps: +List<J.MaterialMap>, +index: U32, +albedo: J.TextureInfo, +metalness: J.TextureInfo, +normal: J.TextureInfo, +emission: J.TextureInfo, +metal: F32, +rough: F32, +glow: U32) -> +List<J.MaterialMap>:
  match maps:
    case Nil{}: Nil{}
    case Con{J.MaterialMap{+texture, +color, +value}, rest}:
      Con{map.set(index, texture, color, value, albedo, metalness, normal, emission, metal, rough, glow), maps.set(rest, (index + 1 : U32), albedo, metalness, normal, emission, metal, rough, glow)}

def material.set(materials: +List<J.Material>, +albedo: J.TextureInfo, +metalness: J.TextureInfo, +normal: J.TextureInfo, +emission: J.TextureInfo, +metal: F32, +rough: F32, +glow: U32) -> +List<J.Material>:
  match materials:
    case Nil{}: Nil{}
    case Con{J.Material{+maps, +params}, +rest}: Con{J.Material{maps.set(maps, 0, albedo, metalness, normal, emission, metal, rough, glow), params}, rest}

# The model with materials[0] dressed.
def dressed(+model: J.Model, +albedo: J.TextureInfo, +metalness: J.TextureInfo, +normal: J.TextureInfo, +emission: J.TextureInfo, +metal: F32, +rough: F32, +glow: U32) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, material.set(materials, albedo, metalness, normal, emission, metal, rough, glow), ids}

def info.first(infos: +List<J.TextureInfo>) -> J.TextureInfo:
  match infos:
    case Con{+info, _}: info
    case Nil{}: J.TextureInfo.none()

# The texture loaded `back` textures before the last.
def info(+infos: +List<J.TextureInfo>, +back: U32) -> J.TextureInfo:
  info.first(List.drop(&2, J.TextureInfo, infos, U32.to_nat(back)))

def got.info(frame: J.Frame, +ok: Bool, textures: List<J.Texture>, +infos: +List<J.TextureInfo>, r: J.Texture & J.TextureInfo) -> Got:
  (texture, +found) = r
  Got{frame, ok, Con{texture, textures}, Con{found, infos}}

def got.loaded(r: J.Frame & Maybe<J.Texture>, +ok: Bool, textures: List<J.Texture>, +infos: +List<J.TextureInfo>) -> Got:
  match r:
    case Tuple{frame, None{}}: Got{frame, False{}, textures, Con{J.TextureInfo.none(), infos}}
    case Tuple{frame, Some{t}}: got.info(frame, ok, textures, infos, J.Texture.info(t))

# LoadTexture(path).
def load.one(got: Got, +path: String) -> IO(Got):
  Got{frame, +ok, textures, +infos} = got
  IO.bind(J.Frame & Maybe<J.Texture>, Got, J.Texture.load(frame, path), r => IO.pure(Got, got.loaded(r, ok, textures, infos)))

def loads(names: +List<String>, got: Got, +dir: String) -> IO(Got):
  match names:
    case Nil{}: IO.pure(Got, got)
    case Con{+name, rest}: IO.bind(Got, Got, load.one(got, dir ++ name), next => loads(rest, next, dir))

# The floor's maps: road_a, road_mra and road_n; metalness 0.8, roughness 0.1, a black emission color. The lights
# are enabled; SetTargetFPS(60).
def setup.done(+core: J.Core, +valid: Bool, +car: J.Model, +floor: J.Model, got: Got) -> J.Core & (J.Frame & State):
  Got{frame, +ok, textures, +infos} = got
  (J.Core.set_target_fps(core, 60), (frame, State{valid && ok, Some{start()}, car, dressed(floor, info(infos, 2), info(infos, 1), info(infos, 0), J.TextureInfo.none(), 0.8, 0.1, J.Color.BLACK()), textures, 15}))

def setup.floor(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, +dir: String, +core: J.Core, +ok: Bool, +car: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, Fail{_}}: IO.pure(J.Core & (J.Frame & State), setup.done(core, False{}, car, J.Model.empty(), Got{frame, False{}, textures, Nil{}}))
    case Tuple{frame, Done{J.LoadedModel{+floor, _}}}:
      IO.bind(Got, J.Core & (J.Frame & State), loads(["resources/road_a.png", "resources/road_mra.png", "resources/road_n.png"], Got{frame, ok, textures, Nil{}}, dir),
        got => IO.pure(J.Core & (J.Frame & State), setup.done(core, True{}, car, floor, got)))

# The car's maps: old_car_d, old_car_mra, old_car_n and old_car_e; metalness 1, roughness 0, the emission color
# (255, 162, 0, 255). Then floor = LoadModel("resources/models/plane.glb").
def setup.car(got: Got, +dir: String, +core: J.Core, +car: J.Model) -> IO(J.Core & (J.Frame & State)):
  Got{frame, +ok, textures, +infos} = got
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/plane.glb"),
    r => setup.floor(r, dir, core, ok, dressed(car, info(infos, 3), info(infos, 2), info(infos, 1), info(infos, 0), 1.0, 0.0, 4288807167), textures))

def setup.loaded(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, +dir: String, +core: J.Core) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, Fail{_}}: IO.pure(J.Core & (J.Frame & State), setup.done(core, False{}, J.Model.empty(), J.Model.empty(), Got{frame, False{}, Nil{}, Nil{}}))
    case Tuple{frame, Done{J.LoadedModel{+car, textures}}}:
      IO.bind(Got, J.Core & (J.Frame & State), loads(["resources/old_car_d.png", "resources/old_car_mra.png", "resources/old_car_n.png", "resources/old_car_e.png"], Got{frame, True{}, textures, Nil{}}, dir),
        got => setup.car(got, dir, core, car))

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): the PBR shader (nothing here), car =
# LoadModel("resources/models/old_car_new.glb") and its maps, the floor and its maps, the four lights.
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/old_car_new.glb"), r => setup.loaded(r, dir, core))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - basic pbr", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
