# raylib [models] example - rotating cube, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_rotating_cube.c (zlib/libpng,
# Copyright (c) 2025 Jopestpe (@jopestpe)); see LICENSES/raylib.txt.
#
# A cube model textured with a quarter of the cubicmap atlas, turning one
# degree a frame about (0.5, 1, 0). The perspective needs the libm profile's
# binary64 tan (docs/PERSPECTIVE.md). See docs/DRIVER.md.
# LoadImage of a .png file is raylib's PNG loader (LoadImage selects it by the
# extension), Surface.load_png here: the generic J.Surface.load_image would
# compile every image decoder into the program (about 1.5 GB more compiler
# memory).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{model: J.Model, textures: List<J.Texture>, rotation: F32}

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 3.0, 3.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+model, textures, +rotation} = state
  (core, State{model, textures, (rotation + 1.0 : F32)})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+core: J.Core, +model: J.Model, +rotation: F32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  draw.fps.done(State{model, textures, rotation}, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawModelEx(model, (0, 0, 0), (0.5, 1, 0), rotation, (1, 1, 1), WHITE).
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+model, textures, +rotation} = state
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera())
  draw.done(core, model, rotation, J.Draw.model_ex_for(libm, f1, textures, model, M.Vector3.zero(), M.Vector3{0.5, 1.0, 0.0}, rotation, M.Vector3.one(), J.Color.WHITE()))

# The main loop's body; libm is the profile of DrawModelEx's rotation and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

def setup.texture(+core: J.Core, frame: J.Frame, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  (J.Core.set_target_fps(core, 60), (frame, State{textured(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), info), [texture], 0.0}))

def setup.untextured(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), Nil{}, 0.0}))

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: setup.untextured(core, frame)
    case Some{t}: setup.texture(core, frame, J.Texture.info(t))

def setup.cropped(+core: J.Core, frame: J.Frame, crop: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> J.Core & (J.Frame & State):
  match crop:
    case Fail{_}: setup.untextured(core, frame)
    case Done{region}: setup.uploaded(core, J.Texture.load_from_image(frame, region))

# ImageFromImage(img, (0, height/2.0, width/2.0, height/2.0)).
def setup.image(+core: J.Core, frame: J.Frame, image: J.Surface) -> J.Core & (J.Frame & State):
  J.Surface{+w, +h, format, pixels} = image
  +fw = U32.to_f32(w)
  +fh = U32.to_f32(h)
  setup.cropped(core, frame, J.Surface.crop(J.Surface{w, h, format, pixels}, J.Rectangle{0.0, (fh / 2.0 : F32), (fw / 2.0 : F32), (fh / 2.0 : F32)}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.untextured(core, frame)
    case Done{image}: setup.image(core, frame, image)

# After InitWindow(800, 450): the cube model with the atlas crop as its
# diffuse texture, rotation 0, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - rotating cube", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
