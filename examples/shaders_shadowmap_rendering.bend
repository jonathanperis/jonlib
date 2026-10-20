# raylib [shaders] example - shadowmap rendering, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_shadowmap_rendering.c
# (zlib/libpng, Copyright (c) 2023-2025 TheManTheMythTheGameDev
# (@TheManTheMythTheGameDev)); see LICENSES/raylib.txt.
#
# A floor, a cube and the animated robot under an orbital camera, drawn
# twice a frame: from the light into a shadow map, then on the screen with
# a shader that would read it. The shadow map is a framebuffer the example
# builds with rlgl with a depth attachment alone (LoadShadowmapRenderTexture,
# docs/RLGL.md): rlsw finds it incomplete, so the first pass draws and
# clears nothing, and no shader runs on the software renderer
# (docs/SHADERS.md): the screen shows the scene in its tints, unshadowed,
# whatever the arrow keys do to the light. UpdateModelAnimation skins the
# robot's meshes on the CPU (raylib 6.2; no shader of the software renderer
# takes the bones), so it is drawn in the animation's pose; the pose is the
# State's ModelPose (docs/MODELS.md). Jonlib's materials have no shader to
# assign. F after a frame takes a
# screenshot, an IO step of the loop (J.Effects, docs/DRIVER.md). The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md),
# UpdateCamera its sinf/cosf (docs/SINCOSF.md) and the animations'
# QuaternionSlerp its acosf and sinf: under a profile without them the
# animations do not load and every frame is refused.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The cube, the robot with its skeleton and animations, and shadowShader.
type Assets is Data:
  Assets{cube: J.Model, robot: J.Model, skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, shader: J.Shader}

# shadowMap: the framebuffer, target.depth and the RenderTexture2D the
# example fills by hand, without a color texture.
type Shadow is Type:
  Shadow{fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, target: Maybe<J.RenderTexture>}

# valid: everything loaded and no refusal so far. counter is frameCounter
# and light is lightDir.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, assets: Assets, textures: List<J.Texture>, pose: J.ModelPose, counter: U32, light: M.Vector3, shadow: Shadow}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# lightCamera: orthographic, 15 units against the light's direction.
def sun.camera(+light: M.Vector3) -> J.Camera3D:
  J.Camera3D{M.Vector3.scale(light, F32.neg(15.0)), M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 20.0, J.CameraProjection.CAMERA_ORTHOGRAPHIC()}

# One component of lightDir: raised while it is below 0.6, then lowered
# while it is above -0.6.
def sun.axis(+value: F32, +up: Bool, +down: Bool, +step: F32) -> F32:
  +raised = Bool.pick(F32, up && (value < 0.6 : F32), (value + step : F32), value)
  Bool.pick(F32, down && (raised > F32.neg(0.6) : F32), (raised - step : F32), raised)

# The arrow keys turn the light by cameraSpeed*60.0f*deltaTime a frame, then
# lightDir = Vector3Normalize(lightDir).
def sun.moved(+core: J.Core, +light: M.Vector3) -> M.Vector3:
  M.Vector3{+x, +y, +z} = light
  +step = ((0.05 * 60.0 : F32) * J.Core.get_frame_time(core) : F32)
  M.Vector3.normalize(M.Vector3{sun.axis(x, J.Input.is_key_down(core, 263), J.Input.is_key_down(core, 262), step), y,
    sun.axis(z, J.Input.is_key_down(core, 265), J.Input.is_key_down(core, 264), step)})

def count(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# anims[0].
def pick.first(items: +List<J.ModelAnimation>) -> J.ModelAnimation:
  match items:
    case Con{item, _}: item
    case Nil{}: J.ModelAnimation{"", 0, 0, Nil{}}

def keyframes(animation: J.ModelAnimation) -> U32:
  J.ModelAnimation{_, _, total, _} = animation
  total

# A vec3 uniform: SetShaderValue(shadowShader, location, &value, SHADER_UNIFORM_VEC3).
def uniform.vec3(+shader: J.Shader, name: String, +value: M.Vector3) -> J.Shader:
  M.Vector3{+x, +y, +z} = value
  J.Shader.set_value(shader, J.Shader.get_location(shader, name), [F32.bits(x), F32.bits(y), F32.bits(z)], 2)

# The Assets with the shader's uniforms of a frame's update: viewPos (the
# camera's position after UpdateCamera since raylib 6.2; 6.0 sent it before)
# and lightDir.
def uniforms(+assets: Assets, +position: M.Vector3, +light: M.Vector3) -> Assets:
  Assets{+cube, +robot, +skeleton, +animations, +shader} = assets
  Assets{cube, robot, skeleton, animations, uniform.vec3(uniform.vec3(shader, "viewPos", position), "lightDir", light)}

# camera.position.
def eye(camera: J.Camera3D) -> M.Vector3:
  J.Camera3D{at, _, _, _, _} = camera
  at

# The assets with the skinned robot.
def with_robot(+assets: Assets, +robot: J.Model) -> Assets:
  Assets{+cube, _, +skeleton, +animations, +shader} = assets
  Assets{cube, robot, skeleton, animations, shader}

def update.posed(posed: Maybe<J.AnimatedModel>, +camera: J.Camera3D, +assets: Assets, textures: List<J.Texture>, +previous: J.ModelPose, +counter: U32, +light: M.Vector3, shadow: Shadow) -> State:
  match posed:
    case None{}: State{False{}, Some{camera}, assets, textures, previous, counter, light, shadow}
    case Some{J.AnimatedModel{+robot, +pose}}: State{True{}, Some{camera}, with_robot(assets, robot), textures, pose, counter, light, shadow}

# UpdateModelAnimation(robot, anims[0], (float)frameCounter).
def update.animated(+libm: M.Libm, +camera: J.Camera3D, +assets: Assets, textures: List<J.Texture>, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, shadow: Shadow) -> State:
  Assets{_, +robot, +skeleton, +animations, _} = assets
  update.posed(J.Model.update_animation_for(libm, robot, skeleton, pick.first(animations), U32.to_f32(counter), pose), camera, assets, textures, pose, counter, light, shadow)

# frameCounter++; frameCounter %= anims[0].keyframeCount.
def advanced(+assets: Assets, +counter: U32) -> U32:
  Assets{_, _, _, +animations, _} = assets
  ((counter + 1) % keyframes(pick.first(animations)) : U32)

def update.moved(moved: Maybe<J.Camera3D>, +libm: M.Libm, +assets: Assets, textures: List<J.Texture>, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +turned: M.Vector3, shadow: Shadow) -> State:
  match moved:
    case None{}: State{False{}, None{}, assets, textures, pose, counter, light, shadow}
    case Some{+c}: update.animated(libm, c, uniforms(assets, eye(c), turned), textures, pose, advanced(assets, counter), turned, shadow)

# UpdateCamera(&camera, CAMERA_ORBITAL), the next keyframe, the light.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +assets: Assets, textures: List<J.Texture>, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, shadow: Shadow) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), libm,
      assets, textures, pose, counter, light, sun.moved(core, light), shadow)
    case _ None{}: State{False{}, None{}, assets, textures, pose, counter, light, shadow}
    case False{} Some{+c}: State{False{}, Some{c}, assets, textures, pose, counter, light, shadow}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +assets, textures, +pose, +counter, +light, shadow} = state
  (core, update.live(valid, camera, libm, core, assets, textures, pose, counter, light, shadow))

def unused(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# DrawScene(cube, robot): the floor (the cube scaled), the cube and the robot.
def scene(+libm: M.Libm, +assets: Assets, frame: J.Frame, textures: List<J.Texture>) -> J.Frame & List<J.Texture>:
  Assets{+cube, +robot, _, _, _} = assets
  f1 = unused(J.Draw.model_ex_for(libm, frame, Nil{}, cube, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{10.0, 1.0, 10.0}, J.Color.BLUE()))
  f2 = unused(J.Draw.model_ex_for(libm, f1, Nil{}, cube, M.Vector3{1.5, 1.0, F32.neg(1.5)}, M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3.one(), J.Color.WHITE()))
  J.Draw.model_ex_for(libm, f2, textures, robot, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.RED())

def texts(frame: J.Frame) -> J.Frame:
  J.Draw.text(J.Draw.text(frame, "Use the arrow keys to rotate the light!", 10.0, 10.0, 30.0, J.Color.RED()),
    "Shadows in raylib using the shadowmapping algorithm!", 520.0, 430.0, 10.0, J.Color.GRAY())

def draw.done(+core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, target: J.RenderTexture, textures: List<J.Texture>,
    r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, depth) = r
  (core, (State{True{}, Some{camera}, assets, textures, pose, counter, light, Shadow{fb, depth, Some{target}}}, texts(frame)))

# EndMode3D(); rlActiveTextureSlot(textureActiveSlot); rlDisableTexture()
# (raylib 6.2): the frame hands shadowMap.depth back (the slot is an OpenGL
# 3.3 call, nothing on the software renderer); the texts.
def draw.lit(+core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, target: J.RenderTexture,
    r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.done(core, camera, assets, pose, counter, light, fb, target, textures, J.Rlgl.disable_texture(J.Rlgl.active_texture_slot(J.Frame.end_mode_3d(frame), 10)))

# rlSetUniform(shadowMapLoc, &textureActiveSlot, SHADER_UNIFORM_INT, 1); BeginMode3D(camera); DrawScene(cube, robot).
def draw.bound(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, +location: U32, target: J.RenderTexture,
    textures: List<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, _) = r
  draw.lit(core, camera, assets, pose, counter, light, fb, target, scene(libm, assets, J.Frame.begin_mode_3d_for(libm, J.Rlgl.set_uniform(frame, location, [10], 4), camera), textures))

def shader.id(+assets: Assets) -> U32:
  Assets{_, _, _, _, shader} = assets
  J.Shader{id, _} = shader
  id

def shader.location(+assets: Assets, name: String) -> U32:
  Assets{_, _, _, _, +shader} = assets
  J.Shader.get_location(shader, name)

# SetShaderValueMatrix(shadowShader, lightVPLoc, lightViewProj).
def lit(+assets: Assets, +view_proj: M.Matrix) -> Assets:
  Assets{+cube, +robot, +skeleton, +animations, +shader} = assets
  Assets{cube, robot, skeleton, animations, J.Shader.set_value_matrix(shader, J.Shader.get_location(shader, "lightVP"), view_proj)}

# PASS 02: ClearBackground(RAYWHITE); the light's matrix; rlEnableShader(shadowShader.id); rlActiveTextureSlot(10); rlEnableTexture(shadowMap.depth.id).
def draw.screen(depth: Maybe<J.Texture>, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer,
    target: J.RenderTexture, textures: List<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match depth:
    case None{}: (core, (State{False{}, Some{camera}, assets, textures, pose, counter, light, Shadow{fb, None{}, Some{target}}}, J.Frame.refuse(frame)))
    case Some{d}: draw.bound(libm, core, camera, assets, pose, counter, light, fb, shader.location(assets, "shadowMap"), target, textures,
      J.Rlgl.enable_texture(J.Rlgl.active_texture_slot(J.Rlgl.enable_shader(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader.id(assets)), 10), d))

# EndTextureMode(); lightViewProj = MatrixMultiply(lightView, lightProj).
def draw.shadowed(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, +view: M.Matrix, +proj: M.Matrix,
    depth: Maybe<J.Texture>, textures: List<J.Texture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{False{}, Some{camera}, assets, textures, pose, counter, light, Shadow{fb, depth, None{}}}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(depth, libm, core, camera, lit(assets, M.Matrix.multiply(view, proj)), pose, counter, light, fb, t, textures, frame)

# EndMode3D(); EndTextureMode().
def draw.cast(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, +view: M.Matrix, +proj: M.Matrix,
    depth: Maybe<J.Texture>, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.shadowed(libm, core, camera, assets, pose, counter, light, fb, view, proj, depth, textures, J.Frame.end_texture_mode(J.Frame.end_mode_3d(frame)))

# lightProj = rlGetMatrixProjection(); DrawScene(cube, robot) from the light.
def draw.projected(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, +view: M.Matrix,
    depth: Maybe<J.Texture>, textures: List<J.Texture>, r: J.Frame & M.Matrix) -> J.Core & (State & J.Frame):
  (frame, +proj) = r
  draw.cast(libm, core, camera, assets, pose, counter, light, fb, view, proj, depth, scene(libm, assets, frame, textures))

# lightView = rlGetMatrixModelview().
def draw.viewed(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>,
    textures: List<J.Texture>, r: J.Frame & M.Matrix) -> J.Core & (State & J.Frame):
  (frame, +view) = r
  draw.projected(libm, core, camera, assets, pose, counter, light, fb, view, depth, textures, J.Rlgl.get_matrix_projection(frame))

# PASS 01 (raylib draws it before BeginDrawing; here the draw does that
# first, the same pixels): BeginTextureMode(shadowMap); ClearBackground(WHITE);
# BeginMode3D(lightCamera). Nothing of it reaches a buffer.
def draw.pass(target: Maybe<J.RenderTexture>, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, +fb: J.Rlgl.Framebuffer,
    depth: Maybe<J.Texture>, textures: List<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match target:
    case None{}: (core, (State{False{}, Some{camera}, assets, textures, pose, counter, light, Shadow{fb, depth, None{}}}, J.Frame.refuse(frame)))
    case Some{t}: draw.viewed(libm, core, camera, assets, pose, counter, light, fb, depth, textures,
      J.Rlgl.get_matrix_modelview(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.WHITE()), sun.camera(light))))

def draw.shadow(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +assets: Assets, textures: List<J.Texture>, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, shadow: Shadow,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  Shadow{+fb, depth, target} = shadow
  draw.pass(target, libm, core, camera, assets, pose, counter, light, fb, depth, textures, frame)

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +assets: Assets, textures: List<J.Texture>, +pose: J.ModelPose, +counter: U32, +light: M.Vector3, shadow: Shadow,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.shadow(libm, core, c, assets, textures, pose, counter, light, shadow, frame)
    case _ None{}: (core, (State{False{}, None{}, assets, textures, pose, counter, light, shadow}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, assets, textures, pose, counter, light, shadow}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +assets, textures, +pose, +counter, +light, shadow} = state
  draw.at(valid, camera, libm, core, assets, textures, pose, counter, light, shadow, frame)

def after.taken(+core: J.Core, state: State, r: J.Frame & Maybe<Bool>) -> J.Core & (State & J.Frame):
  (frame, _) = r
  (core, (state, frame))

def after.key(pressed: Bool, +core: J.Core, state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match pressed:
    case False{}: IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))
    case True{}: IO.bind(J.Frame & Maybe<Bool>, J.Core & (State & J.Frame), J.Frame.take_screenshot(frame, "shaders_shadowmap.png"),
      r => IO.pure(J.Core & (State & J.Frame), after.taken(core, state, r)))

# After EndDrawing: if (IsKeyPressed(KEY_F)) TakeScreenshot("shaders_shadowmap.png").
def after(+core: J.Core, state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  after.key(J.Input.is_key_pressed(core, 70), core, state, frame)

def stepped(r: J.Core & State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, state) = r
  (core, (state, frame))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => IO.pure(J.Core & (State & J.Frame), stepped(update(libm, core, state), frame)), core => state => frame => draw(libm, core, state, frame),
    core => state => frame => after(core, state, frame)}

def path(+dir: String) -> String:
  dir ++ "resources/models/robot.glb"

# A vec4 uniform: SetShaderValue(shadowShader, location, value, SHADER_UNIFORM_VEC4).
def uniform.vec4(+shader: J.Shader, name: String, +x: F32, +y: F32, +z: F32, +w: F32) -> J.Shader:
  J.Shader.set_value(shader, J.Shader.get_location(shader, name), [F32.bits(x), F32.bits(y), F32.bits(z), F32.bits(w)], 3)

# shadowShader = LoadShader(shadowmap.vs, shadowmap.fs) with lightDir, lightColor (WHITE normalized), ambient and shadowMapResolution.
def shader(+dir: String, +light: M.Vector3) -> J.Shader:
  s1 = uniform.vec3(J.Shader.load(Some{dir ++ "resources/shaders/glsl330/shadowmap.vs"}, Some{dir ++ "resources/shaders/glsl330/shadowmap.fs"}), "lightDir", light)
  +s2 = uniform.vec4(uniform.vec4(s1, "lightColor", 1.0, 1.0, 1.0, 1.0), "ambient", 0.1, 0.1, 0.1, 1.0)
  J.Shader.set_value(s2, J.Shader.get_location(s2, "shadowMapResolution"), [1024], 4)

def info.id(info: J.TextureInfo) -> U32:
  J.TextureInfo{id, _, _, _, _} = info
  id

def shadow.target(+fb: J.Rlgl.Framebuffer, +width: U32, +height: U32, r: J.Texture & J.TextureInfo) -> Shadow:
  (depth, +info) = r
  Shadow{fb, Some{depth}, J.Rlgl.render_texture_depth(fb, width, height, info.id(info))}

# if (rlFramebufferComplete(target.id)) TRACELOG(...); rlDisableFramebuffer().
def shadow.completed(r: J.Frame & Bool, +fb: J.Rlgl.Framebuffer, +width: U32, +height: U32, depth: J.Texture) -> J.Frame & Shadow:
  (frame, _) = r
  (J.Rlgl.disable_framebuffer(frame), shadow.target(fb, width, height, J.Texture.info(depth)))

def shadow.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, +width: U32, +height: U32) -> J.Frame & Shadow:
  (+fb, depth) = parts
  shadow.completed(J.Rlgl.framebuffer_complete(frame, fb), fb, width, height, depth)

# rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0).
def shadow.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), +width: U32, +height: U32) -> J.Frame & Shadow:
  (frame, parts) = r
  shadow.parts(frame, parts, width, height)

# target.depth.id = rlLoadTextureDepth(width, height, false).
def shadow.depth(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Shadow:
  (bound, depth) = r
  match depth:
    case None{}: (J.Rlgl.Bound.disable(bound), Shadow{fb, None{}, None{}})
    case Some{d}: shadow.attached(J.Rlgl.Bound.attach(bound, fb, d, 100, 100, 0), width, height)

# if (target.id > 0) rlEnableFramebuffer(target.id) and the rest.
def shadow.started(none: Bool, frame: J.Frame, +fb: J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Shadow:
  match none:
    case True{}: (frame, Shadow{fb, None{}, None{}})
    case False{}: shadow.depth(J.Rlgl.Bound.load_texture_depth(J.Rlgl.enable_framebuffer(frame, fb), width, height, False{}), fb, width, height)

def shadow.framebuffer(r: J.Frame & J.Rlgl.Framebuffer, +width: U32, +height: U32) -> J.Frame & Shadow:
  (frame, +fb) = r
  shadow.started(U32.is_eq(J.Rlgl.Framebuffer.id(fb), 0), frame, fb, width, height)

# LoadShadowmapRenderTexture(width, height): target.id = rlLoadFramebuffer() and its depth attachment; no color texture.
def shadow.load(frame: J.Frame, +width: U32, +height: U32) -> J.Frame & Shadow:
  shadow.framebuffer(J.Rlgl.load_framebuffer(frame), width, height)

# lightDir = Vector3Normalize((0.35, -1, -0.35)).
def sun.start() -> M.Vector3:
  M.Vector3.normalize(M.Vector3{0.35, F32.neg(1.0), F32.neg(0.35)})

# cube = LoadModelFromMesh(GenMeshCube(1, 1, 1)); shadowMap = LoadShadowmapRenderTexture(1024, 1024); SetTargetFPS(60).
def setup.shadowed(+core: J.Core, +dir: String, +valid: Bool, +robot: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, r: J.Frame & Shadow) -> J.Core & (J.Frame & State):
  (frame, shadow) = r
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, Assets{J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0)), robot, skeleton, animations, shader(dir, sun.start())}, textures,
    J.Model.pose(skeleton), 0, sun.start(), shadow}))

def setup.done(+core: J.Core, +dir: String, frame: J.Frame, +valid: Bool, +robot: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  setup.shadowed(core, dir, valid, robot, textures, skeleton, animations, shadow.load(frame, 1024, 1024))

# An animation to play, with a keyframe (the frame counter is taken modulo its count).
def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, +dir: String, frame: J.Frame, +robot: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, dir, frame, False{}, robot, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, dir, frame, (count(items, 0) > 0 : U32) && (keyframes(pick.first(items)) > 0 : U32), robot, textures, skeleton, items)

# anims = LoadModelAnimations("resources/models/robot.glb", &animCount).
def setup.skeleton(result: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, +robot: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, dir, frame, False{}, robot, textures, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, J.Core & (J.Frame & State), J.Model.load_animations_for(libm, path(dir)),
        a => IO.pure(J.Core & (J.Frame & State), setup.animations(a, core, dir, frame, robot, textures, skeleton)))

# The model's skeleton, which Jonlib loads beside the model.
def setup.model(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, J.Core & (J.Frame & State), J.Model.load_skeleton(path(dir)), s => setup.skeleton(s, libm, dir, core, frame, model, textures))

def setup.loaded(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, dir, frame, False{}, J.Model.empty(), Nil{}, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{loaded}: setup.model(libm, dir, core, frame, loaded)

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): the shader, the models, the animations, the shadow map, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, path(dir)), r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 32, "raylib [shaders] example - shadowmap rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
