# raylib [shaders] example - hybrid rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_hybrid_rendering.c
# (zlib/libpng, Copyright (c) 2022-2025 Buğra Alptekin Sarı
# (@BugraAlptekinSari)); see LICENSES/raylib.txt.
#
# A raymarched scene and a rasterized one sharing a depth buffer, in a render
# texture the example builds itself with rlgl (LoadRenderTextureDepthTex,
# docs/RLGL.md). Neither shader is compiled on the software renderer
# (docs/SHADERS.md): the raymarching pass is a white rectangle over the
# texture, drawn with the depth test on, and the cubes and the grid follow
# with their ordinary depths under an orbital camera. The camera position
# and direction are still sent to the raymarching shader (camDist is
# 1/tanf(fovy/2), the libm profile's tanf). The perspective needs its
# binary64 tan (docs/PERSPECTIVE.md) and UpdateCamera its sinf/cosf
# (docs/SINCOSF.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# shdrRaymarch, shdrRaster and camDist.
type Shaders is Data:
  Shaders{march: J.Shader, raster: J.Shader, distance: F32}

# valid: the render texture was built, tanf was answered and no refusal so
# far. depth is target.depth, the depth attachment as a texture.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, shader: Shaders}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.5, 1.0, 1.5}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def bits(v: M.Vector3) -> +List<U32>:
  M.Vector3{x, y, z} = v
  [F32.bits(x), F32.bits(y), F32.bits(z)]

# SetShaderValue(shdrRaymarch, marchLocs.camPos, &camera.position, VEC3) and camDir =
# Vector3Scale(Vector3Normalize(Vector3Subtract(camera.target, camera.position)), camDist).
def aimed(shaders: Shaders, camera: J.Camera3D) -> Shaders:
  Shaders{+march, raster, +distance} = shaders
  J.Camera3D{+position, +target, _, _, _} = camera
  Shaders{J.Shader.set_value(J.Shader.set_value(march, J.Shader.get_location(march, "camPos"), bits(position), 2), J.Shader.get_location(march, "camDir"),
    bits(M.Vector3.scale(M.Vector3.normalize(M.Vector3.subtract(target, position)), distance)), 2), raster, distance}

def update.moved(updated: Maybe<J.Camera3D>, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +shader: Shaders) -> State:
  match updated:
    case None{}: State{False{}, None{}, target, depth, shader}
    case Some{+c}: State{True{}, Some{c}, target, depth, aimed(shader, c)}

# UpdateCamera(&camera, CAMERA_ORBITAL).
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +shader: Shaders) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), target, depth, shader)
    case _ None{}: State{False{}, None{}, target, depth, shader}
    case False{} Some{+c}: State{False{}, Some{c}, target, depth, shader}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, target, depth, +shader} = state
  (core, update.live(valid, camera, libm, core, target, depth, shader))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.shown(+core: J.Core, +camera: J.Camera3D, depth: Maybe<J.Texture>, +shader: Shaders, +id: U32, +depth_id: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps.done(State{True{}, Some{camera}, Some{J.RenderTexture{id, texture, depth_id}}, depth, shader}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

# ClearBackground(RAYWHITE); DrawTextureRec(target.texture, (0, 0, screenWidth, -screenHeight), (0, 0), WHITE); DrawFPS(10, 10).
def draw.screen(+core: J.Core, +camera: J.Camera3D, depth: Maybe<J.Texture>, +shader: Shaders, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  J.RenderTexture{+id, texture, +depth_id} = target
  draw.shown(core, camera, depth, shader, id, depth_id,
    J.Draw.texture_rec(J.Frame.clear_background(frame, J.Color.RAYWHITE()), texture, J.Rectangle{0.0, 0.0, 800.0, F32.neg(450.0)}, M.Vector2.zero(), J.Color.WHITE()))

def draw.ended(+core: J.Core, +camera: J.Camera3D, depth: Maybe<J.Texture>, +shader: Shaders, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{False{}, Some{camera}, None{}, depth, shader}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(core, camera, depth, shader, frame, t)

def raster.of(shaders: Shaders) -> J.Shader:
  Shaders{_, raster, _} = shaders
  raster

def march.of(shaders: Shaders) -> J.Shader:
  Shaders{march, _, _} = shaders
  march

# rlEnableDepthTest(); BeginShaderMode(shdrRaymarch); DrawRectangleRec((0, 0, screenWidth, screenHeight), WHITE); EndShaderMode().
def marched(+shader: Shaders, frame: J.Frame) -> J.Frame:
  J.Frame.end_shader_mode(J.Draw.rectangle_rec(J.Frame.begin_shader_mode(J.Rlgl.enable_depth_test(frame), march.of(shader)), J.Rectangle{0.0, 0.0, 800.0, 450.0}, J.Color.WHITE()))

# The cubes with their wires and the grid, in shader mode.
def scene(+shader: Shaders, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.cube_wires_v(J.Frame.begin_shader_mode(frame, raster.of(shader)), M.Vector3{0.0, 0.5, 1.0}, M.Vector3{1.0, 1.0, 1.0}, J.Color.RED())
  f2 = J.Draw.cube_v(f1, M.Vector3{0.0, 0.5, 1.0}, M.Vector3{1.0, 1.0, 1.0}, J.Color.PURPLE())
  f3 = J.Draw.cube_wires_v(f2, M.Vector3{0.0, 0.5, F32.neg(1.0)}, M.Vector3{1.0, 1.0, 1.0}, J.Color.DARKGREEN())
  f4 = J.Draw.cube_v(f3, M.Vector3{0.0, 0.5, F32.neg(1.0)}, M.Vector3{1.0, 1.0, 1.0}, J.Color.YELLOW())
  J.Frame.end_shader_mode(J.Draw.grid(f4, 10.0, 1.0))

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# BeginTextureMode(target); ClearBackground(WHITE); the raymarching pass; BeginMode3D(camera); the scene; EndMode3D(); EndTextureMode().
def draw.at(valid: Bool, target: Maybe<J.RenderTexture>, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, depth: Maybe<J.Texture>, +shader: Shaders, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid target camera:
    case True{} Some{t} Some{+c}: draw.ended(core, c, depth, shader,
      J.Frame.end_texture_mode(J.Frame.end_mode_3d(scene(shader, J.Frame.begin_mode_3d_for(libm, marched(shader, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.WHITE())), c)))))
    case _ Some{t} _: (core, (State{False{}, None{}, Some{t}, depth, shader}, J.Frame.refuse(frame)))
    case _ None{} _: (core, (State{False{}, None{}, None{}, depth, shader}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, target, depth, +shader} = state
  draw.at(valid, target, camera, libm, core, depth, shader, frame)

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

# screenCenter = (screenWidth/2.0f, screenHeight/2.0f) to the raymarching shader.
def centered(+march: J.Shader) -> J.Shader:
  J.Shader.set_value(march, J.Shader.get_location(march, "screenCenter"), [F32.bits(400.0), F32.bits(225.0)], 1)

# camDist = 1.0f/(tanf(camera.fovy*0.5f*DEG2RAD)).
def setup.shaders(distance: Maybe<F32>, +core: J.Core, frame: J.Frame, target: Maybe<J.RenderTexture>, depth: Maybe<J.Texture>, +dir: String, +valid: Bool) -> J.Core & (J.Frame & State):
  match distance:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{False{}, Some{start()}, target, depth,
      Shaders{J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/hybrid_raymarch.fs"}), J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/hybrid_raster.fs"}), 0.0}}))
    case Some{+t}: (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, target, depth,
      Shaders{centered(J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/hybrid_raymarch.fs"})), J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/hybrid_raster.fs"}), (1.0 / t : F32)}}))

def setup.target(+libm: M.Libm, +core: J.Core, frame: J.Frame, depth: Maybe<J.Texture>, +dir: String, checked: Maybe<J.RenderTexture> & Bool) -> J.Core & (J.Frame & State):
  (target, +valid) = checked
  setup.shaders(M.Libm.tanf(libm, ((45.0 * 0.5 : F32) * M.Math.DEG2RAD() : F32)), core, frame, target, depth, dir, valid)

def setup.parts(+libm: M.Libm, +core: J.Core, +dir: String, frame: J.Frame, loaded: Loaded) -> J.Core & (J.Frame & State):
  Loaded{target, depth} = loaded
  setup.target(libm, core, frame, depth, dir, some(target))

def setup.loaded(+libm: M.Libm, +core: J.Core, +dir: String, r: J.Frame & Loaded) -> J.Core & (J.Frame & State):
  (frame, loaded) = r
  setup.parts(libm, core, dir, frame, loaded)

# After InitWindow(800, 450): the shaders, the render texture, camDist, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(libm, core, dir, loader(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - hybrid rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, "", core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
