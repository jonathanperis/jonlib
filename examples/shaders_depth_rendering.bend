# raylib [shaders] example - depth rendering, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_depth_rendering.c
# (zlib/libpng, Copyright (c) 2025 Luís Almeida (@luis605)); see
# LICENSES/raylib.txt.
#
# A cube and a floor drawn into a render texture the example builds itself
# with rlgl (LoadRenderTextureDepthTex, docs/RLGL.md), whose depth attachment
# is then drawn to the screen through a shader that would show the depths.
# No shader runs on the software renderer (docs/SHADERS.md), and rlsw draws
# a texture of a depth format untextured: the screen shows a white rectangle
# of the attachment's size under the help box, whatever the free camera
# does. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf (docs/SINCOSF.md). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The cube and the floor.
type Models is Data:
  Models{cube: J.Model, floor: J.Model}

# valid: the render texture and the models were made and no refusal so far.
# depth is target.depth, the depth attachment as a texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, shader: J.Shader, models: Models}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 1.0, 5.0}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def update.moved(updated: Maybe<J.Camera3D>, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +shader: J.Shader, +models: Models) -> State:
  match updated:
    case None{}: State{False{}, None{}, target, depth, shader, models}
    case Some{+c}: State{True{}, Some{c}, target, depth, shader, models}

# UpdateCamera(&camera, CAMERA_FREE).
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +shader: J.Shader, +models: Models) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()), target, depth, shader, models)
    case _ None{}: State{False{}, None{}, target, depth, shader, models}
    case False{} Some{+c}: State{False{}, Some{c}, target, depth, shader, models}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, target, depth, +shader, +models} = state
  (core, update.live(valid, camera, libm, core, target, depth, shader, models))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def texts(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 10.0, 10.0, 320.0, 93.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 10.0, 10.0, 320.0, 93.0, J.Color.BLUE())
  f2 = J.Draw.text(f1, "Camera Controls:", 20.0, 20.0, 10.0, J.Color.BLACK())
  f3 = J.Draw.text(f2, "- WASD to move", 40.0, 40.0, 10.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "- Mouse Wheel Pressed to Pan", 40.0, 60.0, 10.0, J.Color.DARKGRAY())
  J.Draw.text(f4, "- Z to zoom to (0, 0, 0)", 40.0, 80.0, 10.0, J.Color.DARKGRAY())

# EndShaderMode(); the help box and its texts.
def draw.shown(+core: J.Core, +camera: J.Camera3D, target: J.RenderTexture, +shader: J.Shader, +models: Models, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, depth) = r
  (core, (State{True{}, Some{camera}, Some{target}, Some{depth}, shader, models}, texts(J.Frame.end_shader_mode(frame))))

# SetShaderValueTexture(depthShader, depthLoc, target.depth); DrawTexture(target.depth, 0, 0, WHITE).
def draw.depth(r: J.Texture & J.TextureInfo, +core: J.Core, +camera: J.Camera3D, +shader: J.Shader, +models: Models, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  (depth, +info) = r
  draw.shown(core, camera, target, J.Shader.set_value_texture(shader, J.Shader.get_location(shader, "depthTexture"), info), models,
    J.Draw.texture(frame, depth, 0.0, 0.0, J.Color.WHITE()))

# ClearBackground(RAYWHITE); BeginShaderMode(depthShader); the depth attachment as a texture.
def draw.screen(depth: Maybe<J.Texture>, +core: J.Core, +camera: J.Camera3D, +shader: J.Shader, +models: Models, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  match depth:
    case None{}: (core, (State{False{}, Some{camera}, Some{target}, None{}, shader, models}, J.Frame.refuse(frame)))
    case Some{d}: draw.depth(J.Texture.info(d), core, camera, shader, models, J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), target)

def draw.ended(+core: J.Core, +camera: J.Camera3D, depth: Maybe<J.Texture>, +shader: J.Shader, +models: Models, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{False{}, Some{camera}, None{}, depth, shader, models}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(depth, core, camera, shader, models, frame, t)

def unused(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# DrawModel(cube, (0, 0, 0), 3.0f, YELLOW); DrawModel(floor, (10, 0, 2), 2.0f, RED).
def scene(models: Models, frame: J.Frame) -> J.Frame:
  Models{+cube, +floor} = models
  unused(J.Draw.model(unused(J.Draw.model(frame, Nil{}, cube, M.Vector3{0.0, 0.0, 0.0}, 3.0, J.Color.YELLOW())), Nil{}, floor, M.Vector3{10.0, 0.0, 2.0}, 2.0, J.Color.RED()))

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# BeginTextureMode(target); ClearBackground(WHITE); BeginMode3D(camera); the models; EndMode3D(); EndTextureMode().
def draw.at(valid: Bool, target: Maybe<J.RenderTexture>, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, depth: Maybe<J.Texture>, +shader: J.Shader, +models: Models, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid target camera:
    case True{} Some{t} Some{+c}: draw.ended(core, c, depth, shader, models,
      J.Frame.end_texture_mode(J.Frame.end_mode_3d(scene(models, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.WHITE()), c)))))
    case _ Some{t} _: (core, (State{False{}, None{}, Some{t}, depth, shader, models}, J.Frame.refuse(frame)))
    case _ None{} _: (core, (State{False{}, None{}, None{}, depth, shader, models}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, target, depth, +shader, +models} = state
  draw.at(valid, target, camera, libm, core, depth, shader, models, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# The target as the example fills it, and target.depth.
type Loaded is Type:
  Loaded{target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>}

def info.id(info: J.TextureInfo) -> U32:
  J.TextureInfo{id, _, _, _, _} = info
  id

def load.target(+fb: J.Rlgl.Framebuffer, color: J.Texture, r: J.Texture & J.TextureInfo) -> Loaded:
  (depth, +info) = r
  Loaded{J.Rlgl.render_texture(fb, color, info.id(info)), Some{depth}}

# if (rlFramebufferComplete(target.id)) TRACELOG(...); rlDisableFramebuffer().
def load.completed(r: J.Frame & Bool, +fb: J.Rlgl.Framebuffer, color: J.Texture, depth: J.Texture) -> J.Frame & Loaded:
  (frame, _) = r
  (J.Rlgl.disable_framebuffer(frame), load.target(fb, color, J.Texture.info(depth)))

def load.depth.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, color: J.Texture) -> J.Frame & Loaded:
  (+fb, depth) = parts
  load.completed(J.Rlgl.framebuffer_complete(frame, fb), fb, color, depth)

def load.depth.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), color: J.Texture) -> J.Frame & Loaded:
  (frame, parts) = r
  load.depth.parts(frame, parts, color)

# rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0).
def load.color.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, depth: J.Texture) -> J.Frame & Loaded:
  (+fb, color) = parts
  load.depth.attached(J.Rlgl.framebuffer_attach(frame, fb, depth, 100, 100, 0), color)

def load.color.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), depth: J.Texture) -> J.Frame & Loaded:
  (frame, parts) = r
  load.color.parts(frame, parts, depth)

# rlFramebufferAttach(target.id, target.texture.id, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
# without both textures nothing is attached and there is no target.
def load.textures(color: Maybe<J.Texture>, depth: Maybe<J.Texture>, bound: J.Rlgl.Bound, +fb: J.Rlgl.Framebuffer) -> J.Frame & Loaded:
  match color depth:
    case Some{c} Some{d}: load.color.attached(J.Rlgl.Bound.attach(bound, fb, c, 0, 100, 0), d)
    case _ Some{d}: (J.Rlgl.Bound.disable(bound), Loaded{None{}, Some{d}})
    case _ None{}: (J.Rlgl.Bound.disable(bound), Loaded{None{}, None{}})

# target.depth.id = rlLoadTextureDepth(width, height, false).
def load.depth(r: J.Rlgl.Bound & Maybe<J.Texture>, color: Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer) -> J.Frame & Loaded:
  (bound, depth) = r
  load.textures(color, depth, bound, fb)

# target.texture.id = rlLoadTexture(0, width, height, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1).
def load.color(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Loaded:
  (bound, color) = r
  load.depth(J.Rlgl.Bound.load_texture_depth(bound, width, height, False{}), color, fb)

# if (target.id > 0) rlEnableFramebuffer(target.id) and the rest.
def load.started(none: Bool, frame: J.Frame, +fb: J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Loaded:
  match none:
    case True{}: (frame, Loaded{None{}, None{}})
    case False{}: load.color(J.Rlgl.Bound.load_texture(J.Rlgl.enable_framebuffer(frame, fb), width, height, 7, 1), fb, width, height)

def load.framebuffer(r: J.Frame & J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Loaded:
  (frame, +fb) = r
  load.started(U32.is_eq(J.Rlgl.Framebuffer.id(fb), 0), frame, fb, width, height)

# LoadRenderTextureDepthTex(width, height): target.id = rlLoadFramebuffer(), its color texture and its depth attachment.
def loader(frame: J.Frame, +width: U32, +height: U32) -> J.Frame & Loaded:
  load.framebuffer(J.Rlgl.load_framebuffer(frame), width, height)

def some(target: Maybe<J.RenderTexture>) -> Maybe<J.RenderTexture> & Bool:
  match target:
    case None{}: (None{}, False{})
    case Some{t}: (Some{t}, True{})

# SetShaderValue(depthShader, flipTextureLoc, (int[]){ 1 }, SHADER_UNIFORM_INT).
def flipped(+shader: J.Shader) -> J.Shader:
  J.Shader.set_value(shader, J.Shader.get_location(shader, "flipY"), [1], 4)

# cube = LoadModelFromMesh(GenMeshCube(1, 1, 1)); floor = LoadModelFromMesh(GenMeshPlane(20, 20, 1, 1)); DisableCursor(); SetTargetFPS(60).
def setup.floor(floor: Maybe<J.Mesh>, +core: J.Core, frame: J.Frame, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +dir: String, +valid: Bool) -> J.Core & (J.Frame & State):
  match floor:
    case None{}: (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{False{}, Some{start()}, target, depth,
      flipped(J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/depth_render.fs"})), Models{J.Model.empty(), J.Model.empty()}}))
    case Some{+mesh}: (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{valid, Some{start()}, target, depth,
      flipped(J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/depth_render.fs"})), Models{J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), J.Model.from_mesh(mesh)}}))

def setup.target(+core: J.Core, frame: J.Frame, depth: Maybe<J.Texture>, +dir: String, checked: Maybe<J.RenderTexture> & Bool) -> J.Core & (J.Frame & State):
  (target, +valid) = checked
  setup.floor(J.Mesh.gen_plane(20.0, 20.0, 1, 1), core, frame, target, depth, dir, valid)

def setup.parts(+core: J.Core, +dir: String, frame: J.Frame, loaded: Loaded) -> J.Core & (J.Frame & State):
  Loaded{target, depth} = loaded
  setup.target(core, frame, depth, dir, some(target))

def setup.loaded(+core: J.Core, +dir: String, r: J.Frame & Loaded) -> J.Core & (J.Frame & State):
  (frame, loaded) = r
  setup.parts(core, dir, frame, loaded)

# After InitWindow(800, 450): the render texture, the shader, the models, DisableCursor(), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, dir, loader(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - depth rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup("", core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
