# raylib [models] example - textured cube, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_textured_cube.c
# (zlib/libpng, Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Two cubes drawn as rlgl quads with a texture (rlSetTexture, rlBegin(RL_QUADS),
# rlNormal3f, rlTexCoord2f, rlVertex3f): one with the whole texture on each
# face (DrawCubeTexture), one with a region of it (DrawCubeTextureRec). The
# faces below keep the example's order of faces and corners; each corner
# holds its texture coordinate as a low (0) or high (1) end and the signs of
# its half extents. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md). LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>}

# u, v: 0 the low end of the texture coordinate, 1 the high end; sx, sy, sz: the signs of width/2, height/2 and length/2.
type Corner is Data:
  Corner{u: F32, v: F32, sx: F32, sy: F32, sz: F32}

type Face is Data:
  Face{normal: M.Vector3, corners: +List<Corner>}

# The cube's position, its half extents and the texture coordinates' low and high ends.
type Box is Data:
  Box{position: M.Vector3, half: M.Vector3, low: M.Vector2, high: M.Vector2}

# DrawCubeTexture's faces: front, back, top, bottom, right, left.
def plain() -> +List<Face>:
  [
    Face{M.Vector3{0.0, 0.0, 1.0}, [Corner{0.0, 0.0, F32.neg(1.0), F32.neg(1.0), 1.0}, Corner{1.0, 0.0, 1.0, F32.neg(1.0), 1.0}, Corner{1.0, 1.0, 1.0, 1.0, 1.0}, Corner{0.0, 1.0, F32.neg(1.0), 1.0, 1.0}]},
    Face{M.Vector3{0.0, 0.0, F32.neg(1.0)}, [Corner{1.0, 0.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 1.0, F32.neg(1.0), 1.0, F32.neg(1.0)}, Corner{0.0, 1.0, 1.0, 1.0, F32.neg(1.0)}, Corner{0.0, 0.0, 1.0, F32.neg(1.0), F32.neg(1.0)}]},
    Face{M.Vector3{0.0, 1.0, 0.0}, [Corner{0.0, 1.0, F32.neg(1.0), 1.0, F32.neg(1.0)}, Corner{0.0, 0.0, F32.neg(1.0), 1.0, 1.0}, Corner{1.0, 0.0, 1.0, 1.0, 1.0}, Corner{1.0, 1.0, 1.0, 1.0, F32.neg(1.0)}]},
    Face{M.Vector3{0.0, F32.neg(1.0), 0.0}, [Corner{1.0, 1.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{0.0, 1.0, 1.0, F32.neg(1.0), F32.neg(1.0)}, Corner{0.0, 0.0, 1.0, F32.neg(1.0), 1.0}, Corner{1.0, 0.0, F32.neg(1.0), F32.neg(1.0), 1.0}]},
    Face{M.Vector3{1.0, 0.0, 0.0}, [Corner{1.0, 0.0, 1.0, F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 1.0, 1.0, 1.0, F32.neg(1.0)}, Corner{0.0, 1.0, 1.0, 1.0, 1.0}, Corner{0.0, 0.0, 1.0, F32.neg(1.0), 1.0}]},
    Face{M.Vector3{F32.neg(1.0), 0.0, 0.0}, [Corner{0.0, 0.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 0.0, F32.neg(1.0), F32.neg(1.0), 1.0}, Corner{1.0, 1.0, F32.neg(1.0), 1.0, 1.0}, Corner{0.0, 1.0, F32.neg(1.0), 1.0, F32.neg(1.0)}]}]

# DrawCubeTextureRec's faces, in its order of corners.
def region() -> +List<Face>:
  [
    Face{M.Vector3{0.0, 0.0, 1.0}, [Corner{0.0, 1.0, F32.neg(1.0), F32.neg(1.0), 1.0}, Corner{1.0, 1.0, 1.0, F32.neg(1.0), 1.0}, Corner{1.0, 0.0, 1.0, 1.0, 1.0}, Corner{0.0, 0.0, F32.neg(1.0), 1.0, 1.0}]},
    Face{M.Vector3{0.0, 0.0, F32.neg(1.0)}, [Corner{1.0, 1.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 0.0, F32.neg(1.0), 1.0, F32.neg(1.0)}, Corner{0.0, 0.0, 1.0, 1.0, F32.neg(1.0)}, Corner{0.0, 1.0, 1.0, F32.neg(1.0), F32.neg(1.0)}]},
    Face{M.Vector3{0.0, 1.0, 0.0}, [Corner{0.0, 0.0, F32.neg(1.0), 1.0, F32.neg(1.0)}, Corner{0.0, 1.0, F32.neg(1.0), 1.0, 1.0}, Corner{1.0, 1.0, 1.0, 1.0, 1.0}, Corner{1.0, 0.0, 1.0, 1.0, F32.neg(1.0)}]},
    Face{M.Vector3{0.0, F32.neg(1.0), 0.0}, [Corner{1.0, 0.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{0.0, 0.0, 1.0, F32.neg(1.0), F32.neg(1.0)}, Corner{0.0, 1.0, 1.0, F32.neg(1.0), 1.0}, Corner{1.0, 1.0, F32.neg(1.0), F32.neg(1.0), 1.0}]},
    Face{M.Vector3{1.0, 0.0, 0.0}, [Corner{1.0, 1.0, 1.0, F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 0.0, 1.0, 1.0, F32.neg(1.0)}, Corner{0.0, 0.0, 1.0, 1.0, 1.0}, Corner{0.0, 1.0, 1.0, F32.neg(1.0), 1.0}]},
    Face{M.Vector3{F32.neg(1.0), 0.0, 0.0}, [Corner{0.0, 1.0, F32.neg(1.0), F32.neg(1.0), F32.neg(1.0)}, Corner{1.0, 1.0, F32.neg(1.0), F32.neg(1.0), 1.0}, Corner{1.0, 0.0, F32.neg(1.0), 1.0, 1.0}, Corner{0.0, 0.0, F32.neg(1.0), 1.0, F32.neg(1.0)}]}]

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

# rlTexCoord2f(u, v); rlVertex3f(x -/+ width/2, y -/+ height/2, z -/+ length/2).
def corner(+box: Box, +c: Corner, frame: J.Frame) -> J.Frame:
  Box{+position, +half, +low, +high} = box
  M.Vector3{+x, +y, +z} = position
  M.Vector3{+hw, +hh, +hl} = half
  M.Vector2{+u0, +v0} = low
  M.Vector2{+u1, +v1} = high
  Corner{+u, +v, +sx, +sy, +sz} = c
  J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(frame, Bool.pick(F32, F32.is_eq(u, 0.0), u0, u1), Bool.pick(F32, F32.is_eq(v, 0.0), v0, v1)),
    (x + sx * hw : F32), (y + sy * hh : F32), (z + sz * hl : F32))

def corners(list: +List<Corner>, +box: Box, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+c, rest}: corners(rest, box, corner(box, c, frame))

def faces(list: +List<Face>, +box: Box, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+face, rest}:
      Face{+normal, +cs} = face
      M.Vector3{+nx, +ny, +nz} = normal
      faces(rest, box, corners(cs, box, J.Rlgl.normal3f(frame, nx, ny, nz)))

def bound(r: J.Frame & Maybe<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# rlSetTexture(texture.id); rlBegin(RL_QUADS); rlColor4ub(WHITE); the faces; rlEnd(); rlSetTexture(0).
def cube(+list: +List<Face>, +box: Box, frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Rlgl.set_texture(J.Rlgl.end(faces(list, box, J.Rlgl.color4ub(J.Rlgl.begin(bound(J.Rlgl.set_texture(frame, Some{texture})), 7), 255, 255, 255, 255))), None{})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps.done(State{texture}, J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)), J.Core.get_fps(core, J.Core.get_time(core)), core)

# source = (0, height/2, width/2, height/2): the coordinates source.x/texWidth to (source.x + source.width)/texWidth
# and source.y/texHeight to (source.y + source.height)/texHeight.
def draw.region(+core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.done(core, cube(region(), Box{M.Vector3{2.0, 1.0, 0.0}, M.Vector3{(2.0 / 2.0 : F32), (2.0 / 2.0 : F32), (2.0 / 2.0 : F32)},
    M.Vector2{(0.0 / U32.to_f32(w) : F32), ((U32.to_f32(h) / 2.0) / U32.to_f32(h) : F32)},
    M.Vector2{((0.0 + U32.to_f32(w) / 2.0) / U32.to_f32(w) : F32), ((U32.to_f32(h) / 2.0 + U32.to_f32(h) / 2.0) / U32.to_f32(h) : F32)}},
    frame, J.Texture{id, w, h, format, linear, alpha, texels}))

# DrawCubeTextureRec(texture, (0, height/2, width/2, height/2), (2, 1, 0), 2, 2, 2, WHITE).
def draw.second(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  match texture:
    case None{}: (core, (State{None{}}, J.Frame.refuse(frame)))
    case Some{t}: draw.region(core, frame, t)

def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# DrawCubeTexture(texture, (-2, 2, 0), 2, 4, 2, WHITE).
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture} = state
  match texture:
    case None{}: (core, (State{None{}}, J.Frame.refuse(frame)))
    case Some{t}: draw.second(core, cube(plain(), Box{M.Vector3{F32.neg(2.0), 2.0, 0.0}, M.Vector3{(2.0 / 2.0 : F32), (4.0 / 2.0 : F32), (2.0 / 2.0 : F32)}, M.Vector2{0.0, 0.0}, M.Vector2{1.0, 1.0}},
      J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera()), t))

# The main loop's body; libm is the profile of the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/cubicmap_atlas.png"), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - textured cube", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
