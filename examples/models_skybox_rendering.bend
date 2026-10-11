# raylib [models] example - skybox rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_skybox_rendering.c
# (zlib/libpng, Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A unit cube carries a cubemap that a shader would turn into the sky around
# a first person camera. On the software renderer LoadTextureCubemap keeps
# id 0 (rlLoadTextureCubemap has no OpenGL 1.1 body), DrawMesh binds the
# material's diffuse map alone and no shader runs (docs/SHADERS.md): the
# cube is drawn white, without back-face culling and without writing depth,
# under the grid; Jonlib's materials have no shader, so the two shaders the
# example loads and their uniforms have no counterpart. useHDR is false in
# the example, so GenTextureCubemap (the panorama rendered into six
# framebuffers) never runs and is not ported. No
# platform Jonlib runs on delivers dropped files, so the branch that loads a
# dropped image as the cubemap never runs; it is ported as written, which
# makes the loop one that does IO (J.Effects, docs/DRIVER.md). The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md)
# and UpdateCamera its sinf/cosf (docs/SINCOSF.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: the cube was made and no refusal so far. name is skyboxFileName.
type State is Data:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, skybox: J.Model, name: String}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{1.0, 1.0, 1.0}, M.Vector3{4.0, 1.0, 4.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def first(materials: +List<J.Material>) -> J.Material:
  match materials:
    case Nil{}: J.Material.load_default()
    case Con{+material, _}: material

def mapped(material: Maybe<J.Material>, +transform: M.Matrix, +meshes: +List<J.Mesh>, +materials: +List<J.Material>, +mesh_material: +List<U32>) -> J.Model:
  match material:
    case None{}: J.Model{transform, meshes, materials, mesh_material}
    case Some{+m}: J.Model{transform, meshes, Con{m, List.drop(&2, J.Material, materials, 1n)}, mesh_material}

# skybox.materials[0].maps[MATERIAL_MAP_CUBEMAP].texture = cubemap.
def textured(+skybox: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +mesh_material} = skybox
  mapped(J.Material.set_texture(first(materials), J.MaterialMapIndex.MATERIAL_MAP_CUBEMAP(), info), transform, meshes, materials, mesh_material)

def cubemap.info(parts: J.Surface & J.TextureInfo) -> J.TextureInfo:
  (_, info) = parts
  info

def cubemap.of(r: J.Frame & (J.Surface & J.TextureInfo)) -> J.Frame & J.TextureInfo:
  (frame, parts) = r
  (frame, cubemap.info(parts))

# LoadTextureCubemap(image, CUBEMAP_LAYOUT_AUTO_DETECT); UnloadImage(image). An image that did not load has no size: no cubemap.
def cubemap(frame: J.Frame, image: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & J.TextureInfo:
  match image:
    case Fail{_}: (frame, J.TextureInfo{0, 0, 0, 0, 0})
    case Done{surface}: cubemap.of(J.Texture.load_cubemap(frame, surface, J.CubemapLayout.CUBEMAP_LAYOUT_AUTO_DETECT()))

def done(+core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))

# The cubemap of the dropped image on the skybox; TextCopy(skyboxFileName, droppedFiles.paths[0]).
def dropped.loaded(r: J.Frame & J.TextureInfo, +core: J.Core, +state: State, +path: String) -> IO(J.Core & (State & J.Frame)):
  (frame, +info) = r
  State{+valid, +camera, +skybox, _} = state
  done(core, State{valid, camera, textured(skybox, info), path}, frame)

# IsFileExtension(droppedFiles.paths[0], ".png;.jpg;.hdr;.bmp;.tga"): UnloadTexture of the cubemap (id 0: nothing);
# image = LoadImage(droppedFiles.paths[0]).
def dropped.matched(matches: Bool, +path: String, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match matches:
    case False{}: done(core, state, frame)
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (State & J.Frame), J.Surface.load_image(path), image => dropped.loaded(cubemap(frame, image), core, state, path))

def dropped.extension(matches: Maybe<Bool>, +path: String, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match matches:
    case None{}: done(core, state, J.Frame.refuse(frame))
    case Some{+m}: dropped.matched(m, path, core, state, frame)

def dropped.first(paths: +List<String>, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match paths:
    case Nil{}: done(core, state, frame)
    case Con{+path, _}: dropped.extension(J.Files.has_extension(path, ".png;.jpg;.hdr;.bmp;.tga"), path, core, state, frame)

# if (droppedFiles.count == 1): only one dropped file is supported.
def dropped.one(one: Bool, +paths: +List<String>, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match one:
    case False{}: done(core, state, frame)
    case True{}: dropped.first(paths, core, state, frame)

# droppedFiles = LoadDroppedFiles(); UnloadDroppedFiles(droppedFiles).
def dropped.files(+files: J.FilePathList, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  J.FilePathList{+count, +paths} = files
  dropped.one(U32.is_eq(count, 1), paths, J.Core.unload_dropped_files(core, files), state, frame)

# if (IsFileDropped()): a new cubemap texture on drag and drop.
def dropped(drop: Bool, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match drop:
    case False{}: done(core, state, frame)
    case True{}: dropped.files(J.Core.load_dropped_files(core), core, state, frame)

def moved.to(moved: Maybe<J.Camera3D>, +skybox: J.Model, +name: String) -> State:
  match moved:
    case None{}: State{False{}, None{}, skybox, name}
    case Some{+c}: State{True{}, Some{c}, skybox, name}

# UpdateCamera(&camera, CAMERA_FIRST_PERSON).
def moved(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +skybox: J.Model, +name: String) -> State:
  match valid camera:
    case True{} Some{+c}: moved.to(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FIRST_PERSON()), skybox, name)
    case _ None{}: State{False{}, None{}, skybox, name}
    case False{} Some{+c}: State{False{}, Some{c}, skybox, name}

def update(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  State{+valid, +camera, +skybox, +name} = state
  dropped(J.Core.is_file_dropped(core), core, moved(valid, camera, libm, core, skybox, name), frame)

def unused(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 430.0, 10.0, J.Color.BLACK())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# We are inside the cube: rlDisableBackfaceCulling(); rlDisableDepthMask(); DrawModel(skybox, (0, 0, 0), 1.0f, WHITE);
# rlEnableBackfaceCulling(); rlEnableDepthMask(); DrawGrid(10, 1.0f); EndMode3D(); the file name; DrawFPS(10, 10).
def draw.scene(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, _, +skybox, +name} = state
  f1 = J.Rlgl.disable_depth_mask(J.Rlgl.disable_backface_culling(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera)))
  f2 = unused(J.Draw.model_ex_for(libm, f1, Nil{}, skybox, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.WHITE()))
  f3 = J.Frame.end_mode_3d(J.Draw.grid(J.Rlgl.enable_depth_mask(J.Rlgl.enable_backface_culling(f2)), 10.0, 1.0))
  draw.fps(state, label(J.Text.format(": %s", [J.TextString{J.Files.name(name)}]), f3), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.scene(libm, core, c, state, frame)
    case _ _: (core, (state, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, _, _} = state
  draw.at(valid, camera, libm, core, state, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan. Nothing follows EndDrawing in the loop.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(libm, core, state, frame), core => state => frame => draw(libm, core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))}

# skybox = LoadModelFromMesh(GenMeshCube(1, 1, 1)) with the cubemap; DisableCursor(); SetTargetFPS(60).
def setup.made(r: J.Frame & J.TextureInfo, +core: J.Core) -> J.Core & (J.Frame & State):
  (frame, +info) = r
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{True{}, Some{start()}, textured(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), info), ""}))

# After InitWindow(800, 450): image = LoadImage("resources/skybox.png") and the rest.
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/skybox.png"),
    image => IO.pure(J.Core & (J.Frame & State), setup.made(cubemap(frame, image), core)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - skybox rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
