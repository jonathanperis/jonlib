# raylib [models] example - first person maze, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_first_person_maze.c
# (zlib/libpng, Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A maze of cubes generated from a 32x16 image (GenMeshCubicmap) walked with
# a first-person camera: a move that would put the player (a circle of
# radius 0.1) into a wall cell (a red channel of 255 in the image) restores
# the camera's old position. The image and the player's cell are drawn in a
# corner. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf (docs/SINCOSF.md); a
# refused UpdateCamera refuses the frame and every later one. LoadImage and
# LoadTexture of a .png are the PNG loader (Surface.load_png). See
# docs/MODELS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: the atlas (the model's diffuse map); cubicmap: the image's
# texture; pixels: LoadImageColors of the image; cx, cy: the player's cell.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, pixels: +List<U32>, cx: U32, cy: U32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.2, 0.4, 0.2}, M.Vector3{0.185, 0.4, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# (int)(coordinate - mapPosition + 0.5f), kept inside 0..size - 1.
def cell(+coordinate: F32, +origin: F32, +size: U32) -> U32:
  Bool.pick(U32, ((coordinate - origin) + 0.5 < 1.0 : F32), 0, U32.min(F32.to_u32(((coordinate - origin) + 0.5 : F32)), (size - 1 : U32)))

def pixel.head(pixels: +List<U32>) -> U32:
  match pixels:
    case Con{+p, _}: p
    case Nil{}: 0

# mapPixels[y*32 + x].r == 255 and the player's circle touching the cell's square.
def wall(+pixels: +List<U32>, +x: U32, +y: U32, +player: M.Vector2) -> Bool:
  U32.is_eq(J.Color.red(pixel.head(List.drop(&2, U32, pixels, U32.to_nat((y * 32 + x : U32))))), 255)
    && J.Collision.circle_rec(player, 0.1, J.Rectangle{((F32.neg(16.0) - 0.5) + U32.to_f32(x) * 1.0 : F32), ((F32.neg(8.0) - 0.5) + U32.to_f32(y) * 1.0 : F32), 1.0, 1.0})

# for (x = playerCellX - 1; x <= playerCellX + 1; x++) inside the map: i is x + 1.
def row(n: Nat, +pixels: +List<U32>, +i: U32, +y: U32, +player: M.Vector2) -> Bool:
  match n:
    case 0n: False{}
    case 1n+p: (((i >= 1 : U32) && (i <= 32 : U32)) && wall(pixels, (i - 1 : U32), y, player)) || row(p, pixels, (i + 1 : U32), y, player)

# for (y = playerCellY - 1; y <= playerCellY + 1; y++) inside the map: j is y + 1.
def blocked(n: Nat, +pixels: +List<U32>, +cx: U32, +j: U32, +player: M.Vector2) -> Bool:
  match n:
    case 0n: False{}
    case 1n+p: (((j >= 1 : U32) && (j <= 16 : U32)) && row(3n, pixels, cx, (j - 1 : U32), player)) || blocked(p, pixels, cx, (j + 1 : U32), player)

# camera.position = oldCamPos when the new position touches a wall (the target keeps its move).
def collided(+old: M.Vector3, +pixels: +List<U32>, +camera: J.Camera3D) -> J.Camera3D:
  J.Camera3D{+position, +target, +up, +fovy, +projection} = camera
  M.Vector3{+x, _, +z} = position
  +cx = cell(x, F32.neg(16.0), 32)
  +cy = cell(z, F32.neg(8.0), 16)
  Bool.pick(J.Camera3D, blocked(3n, pixels, cx, cy, M.Vector2{x, z}), J.Camera3D{old, target, up, fovy, projection}, camera)

def moved.at(+pixels: +List<U32>, model: J.Model, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, +old: M.Vector3, +camera: J.Camera3D) -> State:
  J.Camera3D{+position, _, _, _, _} = camera
  M.Vector3{+x, _, +z} = position
  State{Some{collided(old, pixels, camera)}, model, textures, cubicmap, pixels, cell(x, F32.neg(16.0), 32), cell(z, F32.neg(8.0), 16)}

def moved(+pixels: +List<U32>, model: J.Model, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, +old: M.Vector3, updated: Maybe<J.Camera3D>) -> State:
  match updated:
    case None{}: State{None{}, model, textures, cubicmap, pixels, 0, 0}
    case Some{+c}: moved.at(pixels, model, textures, cubicmap, old, c)

def update.at(+libm: M.Libm, +core: J.Core, +pixels: +List<U32>, model: J.Model, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, +camera: J.Camera3D) -> State:
  J.Camera3D{+position, _, _, _, _} = camera
  moved(pixels, model, textures, cubicmap, position, J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_FIRST_PERSON()))

# oldCamPos = camera.position; UpdateCamera(CAMERA_FIRST_PERSON); the player's cell and the walls around it.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, model, textures, cubicmap, +pixels, +cx, +cy} = state
  match camera:
    case None{}: (core, State{None{}, model, textures, cubicmap, pixels, cx, cy})
    case Some{+c}: (core, update.at(libm, core, pixels, model, textures, cubicmap, c))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.outlined(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +pixels: +List<U32>, +cx: U32, +cy: U32, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, cubicmap) = r
  f1 = J.Draw.rectangle_lines(frame, (800.0 - w * 4.0 - 20.0 : F32), 20.0, (w * 4.0 : F32), (h * 4.0 : F32), J.Color.GREEN())
  f2 = J.Draw.rectangle(f1, (800.0 - w * 4.0 - 20.0 + U32.to_f32((cx * 4 : U32)) : F32), U32.to_f32((20 + cy * 4 : U32)), 4.0, 4.0, J.Color.RED())
  draw.fps.done(State{Some{camera}, model, textures, Some{cubicmap}, pixels, cx, cy}, f2, J.Core.get_fps(core, J.Core.get_time(core)), core)

# DrawTextureEx(cubicmap, (GetScreenWidth() - cubicmap.width*4.0f - 20, 20), 0, 4, WHITE), its outline and
# the player's cell: DrawRectangle(GetScreenWidth() - cubicmap.width*4 - 20 + playerCellX*4, 20 + playerCellY*4, 4, 4, RED).
def draw.corner(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +pixels: +List<U32>, +cx: U32, +cy: U32, frame: J.Frame, cubicmap: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = cubicmap
  draw.outlined(core, camera, model, textures, pixels, cx, cy, U32.to_f32(w), U32.to_f32(h),
    J.Draw.texture_ex_for(libm, frame, J.Texture{id, w, h, format, linear, alpha, texels}, M.Vector2{(800.0 - U32.to_f32(w) * 4.0 - 20.0 : F32), 20.0}, 0.0, 4.0, J.Color.WHITE()))

def draw.model(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +model: J.Model, +pixels: +List<U32>, +cx: U32, +cy: U32, r: J.Frame & List<J.Texture>, cubicmap: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  match cubicmap:
    case None{}: (core, (State{Some{camera}, model, textures, None{}, pixels, cx, cy}, J.Frame.refuse(frame)))
    case Some{t}: draw.corner(libm, core, camera, model, textures, pixels, cx, cy, J.Frame.end_mode_3d(frame), t)

# DrawModel(model, (-16, 0, -8), 1.0f, WHITE).
def draw.at(+libm: M.Libm, +core: J.Core, +model: J.Model, +pixels: +List<U32>, +cx: U32, +cy: U32, frame: J.Frame, textures: List<J.Texture>, cubicmap: Maybe<J.Texture>, camera: +Maybe<J.Camera3D>) -> J.Core & (State & J.Frame):
  match camera:
    case None{}: (core, (State{None{}, model, textures, cubicmap, pixels, cx, cy}, J.Frame.refuse(frame)))
    case Some{+c}: draw.model(libm, core, c, model, pixels, cx, cy,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model,
        M.Vector3{F32.neg(16.0), 0.0, F32.neg(8.0)}, 1.0, J.Color.WHITE()), cubicmap)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +model, textures, cubicmap, +pixels, +cx, +cy} = state
  draw.at(libm, core, model, pixels, cx, cy, frame, textures, cubicmap, camera)

# The main loop's body; libm is the profile of UpdateCamera's and DrawTextureEx's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

def setup.textured(+core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, +pixels: +List<U32>, +model: J.Model, r: J.Texture & J.TextureInfo) -> J.Core & (J.Frame & State):
  (texture, +info) = r
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, textured(model, info), [texture], cubicmap, pixels, 0, 0}))

def setup.atlas(+core: J.Core, cubicmap: Maybe<J.Texture>, +pixels: +List<U32>, +model: J.Model, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, atlas) = r
  match atlas:
    case None{}: (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, model, Nil{}, None{}, pixels, 0, 0}))
    case Some{t}: setup.textured(core, frame, cubicmap, pixels, model, J.Texture.info(t))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# texture = LoadTexture("resources/cubicmap_atlas.png").
def setup.model(+dir: String, +core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, +pixels: +List<U32>, +model: J.Model) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.atlas(core, cubicmap, pixels, model, upload(frame, result))))

# mesh = GenMeshCubicmap(image, (1, 1, 1)); model = LoadModelFromMesh(mesh).
def setup.mesh(+dir: String, +core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, +pixels: +List<U32>, mesh: Result<&1, &1, J.Surface & J.Surface.Error, J.Mesh>) -> IO(J.Core & (J.Frame & State)):
  match mesh:
    case Fail{_}: setup.model(dir, core, frame, None{}, pixels, J.Model.empty())
    case Done{+m}: setup.model(dir, core, frame, cubicmap, pixels, J.Model.from_mesh(m))

def shared(list: List<U32>) -> +List<U32>:
  match list:
    case Nil{}: Nil{}
    case Con{color, rest}: Con{color, shared(rest)}

def colors(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> +List<U32>:
  match result:
    case Fail{_}: Nil{}
    case Done{list}: shared(list)

# mapPixels = LoadImageColors(imMap), from a second copy (the mesh takes the image).
def setup.pixels(+dir: String, +core: J.Core, frame: J.Frame, cubicmap: Maybe<J.Texture>, pair: J.Surface & J.Surface) -> IO(J.Core & (J.Frame & State)):
  (image, copy) = pair
  setup.mesh(dir, core, frame, cubicmap, colors(J.Surface.colors(copy)), J.Mesh.gen_cubicmap(image, M.Vector3{1.0, 1.0, 1.0}))

def setup.uploaded(+dir: String, +core: J.Core, image: J.Surface, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, cubicmap) = r
  setup.pixels(dir, core, frame, cubicmap, J.Surface.copy(image))

# cubicmap = LoadTextureFromImage(image): the upload takes a copy, the mesh the image.
def setup.copied(+dir: String, +core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> IO(J.Core & (J.Frame & State)):
  (image, copy) = pair
  setup.uploaded(dir, core, image, J.Texture.load_from_image(frame, copy))

def setup.loaded(+dir: String, +core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: setup.model(dir, core, frame, None{}, Nil{}, J.Model.empty())
    case Done{image}: setup.copied(dir, core, frame, J.Surface.copy(image))

# After InitWindow(800, 450): LoadImage("resources/cubicmap.png"), its
# texture, colors, mesh and model, the atlas texture, DisableCursor(), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap.png"),
    result => setup.loaded(dir, core, frame, result))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - first person maze", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
