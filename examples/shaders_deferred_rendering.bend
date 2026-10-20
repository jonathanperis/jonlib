# raylib [shaders] example - deferred rendering, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_deferred_rendering.c and
# the CreateLight/UpdateLightValues of examples/shaders/rlights.h (zlib/libpng,
# Copyright (c) 2023-2025 Justin Andreas Lacoste (@27justin), 2017-2025
# Victor Fisac (@victorfisac) and Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A plane, a cube and thirty small cubes are drawn into a G-buffer the
# example builds with rlgl (position, normal and albedo textures and a depth
# renderbuffer), which a shader then lights on the screen; keys 1 to 4 show
# a G-buffer texture or the result and Y, R, G and B toggle the four lights.
# On the software renderer (docs/RLGL.md, docs/SHADERS.md) the position and
# normal textures have a float format OpenGL 1.1 does not support (ids of
# textures without storage), channels 1 and 2 never attach, the G-buffer is
# incomplete and its pass draws nothing; no shader runs and rlLoadDrawQuad
# and rlBlitFramebuffer do nothing. The screen is cleared with the clear
# color the pass set (0, 0, 0, 0); the albedo texture, all zero, stays bound
# for the lights: the spheres of the lights that are on come out with alpha
# 0 and the wires of those that are off keep their color. The position and
# normal textures draw as a RAYWHITE rectangle, the albedo one as nothing.
# The cubes take the C library's rand() (M.Libc, the glibc generator from
# its default seed; the x, y, z initializers in clang's and gcc's order):
# under a profile without it, or without the perspective's binary64 tan
# (docs/PERSPECTIVE.md), every frame is refused. UpdateCamera's and the
# cubes' sinf/cosf follow the libm profile (docs/SINCOSF.md). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# lights[i].enabled of the yellow, red, green and blue point lights.
type Lights is Data:
  Lights{yellow: Bool, red: Bool, green: Bool, blue: Bool}

# cubePositions[i] and cubeRotations[i].
type Cube is Data:
  Cube{position: M.Vector3, rotation: F32}

# The plane, the cube, the small cubes and the two shaders.
type Scene is Data:
  Scene{plane: J.Model, cube: J.Model, cubes: +List<Cube>, gbuffer: J.Shader, deferred: J.Shader}

# gBuffer: the framebuffer and its textures (the depth renderbuffer too).
type Buffer is Type:
  Buffer{fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>, depth: Maybe<J.Texture>}

# valid: everything was made and no refusal so far. mode is DEFERRED_POSITION
# (0), DEFERRED_NORMAL, DEFERRED_ALBEDO or DEFERRED_SHADING (3).
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, scene: Scene, lights: Lights, mode: U32, buffer: Buffer}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{5.0, 4.0, 5.0}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def pressed(+core: J.Core, +code: U32, +on: Bool) -> Bool:
  Bool.pick(Bool, J.Input.is_key_pressed(core, code), Bool.not(on), on)

# Y, R, G and B toggle a light; UpdateLightValues only sets uniforms (nothing here).
def toggled(+core: J.Core, +lights: Lights) -> Lights:
  Lights{+y, +r, +g, +b} = lights
  Lights{pressed(core, 89, y), pressed(core, 82, r), pressed(core, 71, g), pressed(core, 66, b)}

# ONE to FOUR choose the mode (a later key of the same frame wins).
def switched(+core: J.Core, +mode: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 52), 3, Bool.pick(U32, J.Input.is_key_pressed(core, 51), 2, Bool.pick(U32, J.Input.is_key_pressed(core, 50), 1,
    Bool.pick(U32, J.Input.is_key_pressed(core, 49), 0, mode))))

# SetShaderValue(deferredShader, deferredShader.locs[SHADER_LOC_VECTOR_VIEW], cameraPos, SHADER_UNIFORM_VEC3).
def viewed(+scene: Scene, camera: J.Camera3D) -> Scene:
  Scene{+plane, +cube, +cubes, +gbuffer, +deferred} = scene
  J.Camera3D{position, _, _, _, _} = camera
  M.Vector3{+x, +y, +z} = position
  Scene{plane, cube, cubes, gbuffer, J.Shader.set_value(deferred, J.Shader.get_location(deferred, "viewPosition"), [F32.bits(x), F32.bits(y), F32.bits(z)], 2)}

def update.moved(moved: Maybe<J.Camera3D>, +core: J.Core, +scene: Scene, +lights: Lights, +mode: U32, buffer: Buffer) -> State:
  match moved:
    case None{}: State{False{}, None{}, scene, lights, mode, buffer}
    case Some{+c}: State{True{}, Some{c}, viewed(scene, c), toggled(core, lights), switched(core, mode), buffer}

# UpdateCamera(&camera, CAMERA_ORBITAL), the view uniform, the keys.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +scene: Scene, +lights: Lights, +mode: U32, buffer: Buffer) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), core, scene, lights, mode, buffer)
    case _ None{}: State{False{}, None{}, scene, lights, mode, buffer}
    case False{} Some{+c}: State{False{}, Some{c}, scene, lights, mode, buffer}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +scene, +lights, +mode, buffer} = state
  (core, update.live(valid, camera, libm, core, scene, lights, mode, buffer))

def unused(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# shader.id.
def sid(shader: J.Shader) -> U32:
  J.Shader{id, _} = shader
  id

# DrawModelEx(cube, position, (1, 1, 1), cubeRotations[i], (CUBE_SCALE, CUBE_SCALE, CUBE_SCALE), WHITE) for every small cube.
def small(list: +List<Cube>, +libm: M.Libm, +cube: J.Model, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+item, rest}:
      Cube{+position, +rotation} = item
      small(rest, libm, cube, unused(J.Draw.model_ex_for(libm, frame, Nil{}, cube, position, M.Vector3{1.0, 1.0, 1.0}, rotation, M.Vector3{0.25, 0.25, 0.25}, J.Color.WHITE())))

# Draw to the geometry buffer: rlEnableFramebuffer(gBuffer.framebufferId); rlClearColor(0, 0, 0, 0);
# rlClearScreenBuffers(); rlDisableColorBlend(); BeginMode3D(camera); rlEnableShader(gbufferShader.id); the
# models; rlDisableShader(); EndMode3D(); rlEnableColorBlend(). Then the default framebuffer:
# rlDisableFramebuffer(); rlClearScreenBuffers(). Only that last clear reaches a buffer.
def geometry(+libm: M.Libm, +camera: J.Camera3D, +scene: Scene, +fb: J.Rlgl.Framebuffer, frame: J.Frame) -> J.Frame:
  Scene{+plane, +cube, +cubes, +gbuffer, _} = scene
  f1 = J.Rlgl.disable_color_blend(J.Rlgl.clear_screen_buffers(J.Rlgl.clear_color(J.Rlgl.enable_framebuffer_incomplete(frame, fb), 0, 0, 0, 0)))
  f2 = J.Rlgl.enable_shader(J.Frame.begin_mode_3d_for(libm, f1, camera), sid(gbuffer))
  f3 = unused(J.Draw.model_ex_for(libm, f2, Nil{}, plane, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.WHITE()))
  f4 = unused(J.Draw.model_ex_for(libm, f3, Nil{}, cube, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 0.0, M.Vector3{1.0, 1.0, 1.0}, J.Color.WHITE()))
  f5 = J.Rlgl.enable_color_blend(J.Frame.end_mode_3d(J.Rlgl.disable_shader(small(cubes, libm, cube, f4))))
  J.Rlgl.clear_screen_buffers(J.Rlgl.disable_framebuffer(f5))

# A light's sphere: DrawSphereEx when it is on, else DrawSphereWires in ColorAlpha(color, 0.3f).
def light(on: Bool, +libm: M.Libm, frame: J.Frame, +x: F32, +z: F32, +color: U32) -> J.Frame:
  match on:
    case True{}: J.Draw.sphere_ex_for(libm, frame, M.Vector3{x, 1.0, z}, 0.2, 8.0, 8.0, color)
    case False{}: J.Draw.sphere_wires_for(libm, frame, M.Vector3{x, 1.0, z}, 0.2, 8.0, 8.0, J.Color.with_alpha(color, 0.3))

# BeginMode3D(camera); rlEnableShader(rlGetShaderIdDefault()); the four lights; rlDisableShader(); EndMode3D().
def spheres(+libm: M.Libm, +camera: J.Camera3D, +lights: Lights, frame: J.Frame) -> J.Frame:
  Lights{+y, +r, +g, +b} = lights
  f1 = J.Rlgl.enable_shader(J.Frame.begin_mode_3d_for(libm, frame, camera), J.Rlgl.get_shader_id_default())
  f2 = light(y, libm, f1, F32.neg(2.0), F32.neg(2.0), J.Color.YELLOW())
  f3 = light(r, libm, f2, 2.0, 2.0, J.Color.RED())
  f4 = light(g, libm, f3, F32.neg(2.0), 2.0, J.Color.GREEN())
  J.Frame.end_mode_3d(J.Rlgl.disable_shader(light(b, libm, f4, 2.0, F32.neg(2.0), J.Color.BLUE())))

def texts(frame: J.Frame) -> J.Frame:
  J.Draw.text(J.Draw.text(frame, "Toggle lights keys: [Y][R][G][B]", 10.0, 40.0, 20.0, J.Color.DARKGRAY()), "Switch G-buffer textures: [1][2][3][4]", 10.0, 70.0, 20.0, J.Color.DARKGRAY())

# The frame hands the albedo texture back (rlSetTexture(0), which DrawText's own ends with); "FINAL RESULT".
def shading.done(r: J.Frame & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, normal: Maybe<J.Texture>, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, albedo) = r
  (J.Draw.text(frame, "FINAL RESULT", 10.0, 420.0, 20.0, J.Color.DARKGREEN()), Buffer{fb, position, normal, albedo, depth})

# rlLoadDrawQuad(); rlDisableShader(); rlEnableColorBlend(); EndMode3D(); the depth buffer's copy
# (rlBindFramebuffer for reading and drawing, rlBlitFramebuffer, rlDisableFramebuffer()); the lights.
def shading.albedo(r: J.Frame & Maybe<J.Texture>, +libm: M.Libm, +camera: J.Camera3D, +lights: Lights, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, normal) = r
  f1 = J.Frame.end_mode_3d(J.Rlgl.enable_color_blend(J.Rlgl.disable_shader(J.Rlgl.load_draw_quad(frame))))
  f2 = J.Rlgl.bind_framebuffer(J.Rlgl.bind_framebuffer(f1, 36008, fb), 36009, J.Rlgl.Framebuffer.none())
  f3 = J.Rlgl.disable_framebuffer(J.Rlgl.blit_framebuffer(f2, 0.0, 0.0, 800.0, 450.0, 0.0, 0.0, 800.0, 450.0, 256))
  shading.done(J.Rlgl.disable_texture(spheres(libm, camera, lights, f3)), fb, position, normal, depth)

# rlActiveTextureSlot(texUnitAlbedoSpec); rlEnableTexture(gBuffer.albedoSpecTextureId).
def shading.normal(r: J.Frame & Maybe<J.Texture>, +libm: M.Libm, +camera: J.Camera3D, +lights: Lights, +fb: J.Rlgl.Framebuffer, albedo: J.Texture, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, position) = r
  shading.albedo(J.Rlgl.enable_texture(J.Rlgl.active_texture_slot(frame, 2), albedo), libm, camera, lights, fb, position, depth)

# rlActiveTextureSlot(texUnitNormal); rlEnableTexture(gBuffer.normalTextureId).
def shading.position(r: J.Frame & Maybe<J.Texture>, +libm: M.Libm, +camera: J.Camera3D, +lights: Lights, +fb: J.Rlgl.Framebuffer, normal: J.Texture, albedo: J.Texture, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, _) = r
  shading.normal(J.Rlgl.enable_texture(J.Rlgl.active_texture_slot(frame, 1), normal), libm, camera, lights, fb, albedo, depth)

# DEFERRED_SHADING: BeginMode3D(camera); rlDisableColorBlend(); rlEnableShader(deferredShader.id);
# rlActiveTextureSlot(texUnitPosition); rlEnableTexture(gBuffer.positionTextureId) and the rest.
def shading(+libm: M.Libm, +camera: J.Camera3D, +scene: Scene, +lights: Lights, +fb: J.Rlgl.Framebuffer, frame: J.Frame, position: J.Texture, normal: J.Texture, albedo: J.Texture,
    depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  Scene{_, _, _, _, +deferred} = scene
  f1 = J.Rlgl.enable_shader(J.Rlgl.disable_color_blend(J.Frame.begin_mode_3d_for(libm, frame, camera)), sid(deferred))
  shading.position(J.Rlgl.enable_texture(J.Rlgl.active_texture_slot(f1, 0), position), libm, camera, lights, fb, normal, albedo, depth)

def shown.position(r: J.Frame & J.Texture, +fb: J.Rlgl.Framebuffer, normal: J.Texture, albedo: J.Texture, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, position) = r
  (J.Draw.text(frame, "POSITION TEXTURE", 10.0, 420.0, 20.0, J.Color.DARKGREEN()), Buffer{fb, Some{position}, Some{normal}, Some{albedo}, depth})

def shown.normal(r: J.Frame & J.Texture, +fb: J.Rlgl.Framebuffer, position: J.Texture, albedo: J.Texture, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, normal) = r
  (J.Draw.text(frame, "NORMAL TEXTURE", 10.0, 420.0, 20.0, J.Color.DARKGREEN()), Buffer{fb, Some{position}, Some{normal}, Some{albedo}, depth})

def shown.albedo(r: J.Frame & J.Texture, +fb: J.Rlgl.Framebuffer, position: J.Texture, normal: J.Texture, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, albedo) = r
  (J.Draw.text(frame, "ALBEDO TEXTURE", 10.0, 420.0, 20.0, J.Color.DARKGREEN()), Buffer{fb, Some{position}, Some{normal}, Some{albedo}, depth})

# DrawTextureRec(the texture, (0, 0, screenWidth, -screenHeight), Vector2Zero(), RAYWHITE).
def whole(frame: J.Frame, texture: J.Texture) -> J.Frame & J.Texture:
  J.Draw.texture_rec(frame, texture, J.Rectangle{0.0, 0.0, 800.0, F32.neg(450.0)}, M.Vector2{0.0, 0.0}, J.Color.RAYWHITE())

# switch (mode).
def mode.drawn(mode: U32, +libm: M.Libm, +camera: J.Camera3D, +scene: Scene, +lights: Lights, +fb: J.Rlgl.Framebuffer, frame: J.Frame, position: J.Texture, normal: J.Texture, albedo: J.Texture,
    depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  match mode:
    case 0: shown.position(whole(frame, position), fb, normal, albedo, depth)
    case 1: shown.normal(whole(frame, normal), fb, position, albedo, depth)
    case 2: shown.albedo(whole(frame, albedo), fb, position, normal, depth)
    case _: shading(libm, camera, scene, lights, fb, frame, position, normal, albedo, depth)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# The texts; DrawFPS(10, 10).
def draw.done(+core: J.Core, +camera: J.Camera3D, +scene: Scene, +lights: Lights, +mode: U32, r: J.Frame & Buffer) -> J.Core & (State & J.Frame):
  (frame, buffer) = r
  draw.fps(State{True{}, Some{camera}, scene, lights, mode, buffer}, texts(frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.textures(position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>, +libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +scene: Scene, +lights: Lights, +mode: U32,
    +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match position normal albedo:
    case Some{p} Some{n} Some{a}: draw.done(core, camera, scene, lights, mode, mode.drawn(mode, libm, camera, scene, lights, fb, geometry(libm, camera, scene, fb, frame), p, n, a, depth))
    case _ _ _: (core, (State{False{}, Some{camera}, scene, lights, mode, Buffer{fb, None{}, None{}, None{}, depth}}, J.Frame.refuse(frame)))

def draw.buffer(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +scene: Scene, +lights: Lights, +mode: U32, buffer: Buffer, frame: J.Frame) -> J.Core & (State & J.Frame):
  Buffer{+fb, position, normal, albedo, depth} = buffer
  draw.textures(position, normal, albedo, libm, core, camera, scene, lights, mode, fb, depth, frame)

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +scene: Scene, +lights: Lights, +mode: U32, buffer: Buffer, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.buffer(libm, core, c, scene, lights, mode, buffer, frame)
    case _ None{}: (core, (State{False{}, None{}, scene, lights, mode, buffer}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, scene, lights, mode, buffer}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +scene, +lights, +mode, buffer} = state
  draw.at(valid, camera, libm, core, scene, lights, mode, buffer, frame)

# The main loop's body; libm is the profile of UpdateCamera's and the cubes' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# The next n values of rand(), the first being the one given.
def rolls(n: Nat, r: M.Libc.Rand & U32) -> +List<U32>:
  match n r:
    case 0n _: Nil{}
    case 1n+k Tuple{rand, +value}: Con{value, rolls(k, M.Libc.rand(rand))}

def nth.first(values: +List<U32>) -> U32:
  match values:
    case Nil{}: 0
    case Con{+value, _}: value

def nth(+values: +List<U32>, +index: U32) -> U32:
  nth.first(List.drop(&2, U32, values, U32.to_nat(index)))

# cubePositions[i] = ((float)(rand()%10) - 5, (float)(rand()%5), (float)(rand()%10) - 5); cubeRotations[i] = (float)(rand()%360).
def cube.of(+values: +List<U32>) -> Cube:
  Cube{M.Vector3{(U32.to_f32((nth(values, 0) % 10 : U32)) - 5.0 : F32), U32.to_f32((nth(values, 1) % 5 : U32)), (U32.to_f32((nth(values, 2) % 10 : U32)) - 5.0 : F32)},
    U32.to_f32((nth(values, 3) % 360 : U32))}

def cubes.go(n: Nat, +values: +List<U32>) -> +List<Cube>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{cube.of(values), cubes.go(k, List.drop(&2, U32, values, 4n))}

# The MAX_CUBES (30) small cubes, from a program that never called srand (none without the C library's rand()).
def cubes.made(rand: Maybe<M.Libc.Rand>) -> +List<Cube>:
  match rand:
    case None{}: Nil{}
    case Some{r}: cubes.go(30n, rolls(120n, M.Libc.rand(r)))

def any(list: +List<Cube>) -> Bool:
  match list:
    case Nil{}: False{}
    case Con{_, _}: True{}

# The sampler uniforms of the deferred shader (rlEnableShader, three SetShaderValue, rlDisableShader: nothing here).
def sampled(+shader: J.Shader) -> J.Shader:
  +s1 = J.Shader.set_value(shader, J.Rlgl.get_location_uniform(sid(shader), "gPosition"), [0], 12)
  J.Shader.set_value(J.Shader.set_value(s1, J.Rlgl.get_location_uniform(sid(s1), "gNormal"), [1], 12), J.Rlgl.get_location_uniform(sid(s1), "gAlbedoSpec"), [2], 12)

# The models, the shaders, the lights (all on), the cubes, mode DEFERRED_SHADING; rlEnableDepthTest(); SetTargetFPS(60).
def setup.made(plane: Maybe<J.Mesh>, +list: +List<Cube>, +core: J.Core, +dir: String, frame: J.Frame, buffer: Buffer) -> J.Core & (J.Frame & State):
  match plane:
    case Some{+mesh}: (J.Core.set_target_fps(core, 60), (J.Rlgl.enable_depth_test(frame), State{any(list), Some{start()}, Scene{J.Model.from_mesh(mesh),
      J.Model.from_mesh(J.Mesh.gen_cube(2.0, 2.0, 2.0)), list, J.Shader.load(Some{dir ++ "resources/shaders/glsl330/gbuffer.vs"}, Some{dir ++ "resources/shaders/glsl330/gbuffer.fs"}),
      sampled(J.Shader.load(Some{dir ++ "resources/shaders/glsl330/deferred_shading.vs"}, Some{dir ++ "resources/shaders/glsl330/deferred_shading.fs"}))},
      Lights{True{}, True{}, True{}, True{}}, 3, buffer}))
    case None{}: (J.Core.set_target_fps(core, 60), (J.Rlgl.enable_depth_test(frame), State{False{}, Some{start()}, Scene{J.Model.empty(), J.Model.empty(), list, J.Shader.load(None{}, None{}),
      J.Shader.load(None{}, None{})}, Lights{True{}, True{}, True{}, True{}}, 3, buffer}))

# if (!rlFramebufferComplete(gBuffer.framebufferId)) TraceLog(...): it is not.
def buffer.checked(r: J.Frame & Bool, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>, depth: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, _) = r
  (frame, Buffer{fb, position, normal, albedo, depth})

def buffer.depth.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>) -> J.Frame & Buffer:
  (+fb, depth) = parts
  buffer.checked(J.Rlgl.framebuffer_complete(frame, fb), fb, position, normal, albedo, Some{depth})

def buffer.depth.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, parts) = r
  buffer.depth.parts(frame, parts, position, normal, albedo)

# gBuffer.depthRenderbufferId = rlLoadTextureDepth(screenWidth, screenHeight, true), attached as a renderbuffer.
def buffer.depth(r: J.Frame & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, depth) = r
  match depth:
    case None{}: (frame, Buffer{fb, position, normal, albedo, None{}})
    case Some{d}: buffer.depth.attached(J.Rlgl.framebuffer_attach(frame, fb, d, 100, 200, 0), position, normal, albedo)

def buffer.albedo.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, position: Maybe<J.Texture>, normal: Maybe<J.Texture>) -> J.Frame & Buffer:
  (+fb, albedo) = parts
  buffer.depth(J.Rlgl.load_texture_depth(frame, 800, 450, True{}), fb, position, normal, Some{albedo})

def buffer.albedo.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), position: Maybe<J.Texture>, normal: Maybe<J.Texture>) -> J.Frame & Buffer:
  (frame, parts) = r
  buffer.albedo.parts(frame, parts, position, normal)

# rlFramebufferAttach(..., gBuffer.albedoSpecTextureId, RL_ATTACHMENT_COLOR_CHANNEL2, RL_ATTACHMENT_TEXTURE2D, 0).
def buffer.normal.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, position: Maybe<J.Texture>, albedo: J.Texture) -> J.Frame & Buffer:
  (+fb, normal) = parts
  buffer.albedo.attached(J.Rlgl.framebuffer_attach(frame, fb, albedo, 2, 100, 0), position, Some{normal})

def buffer.normal.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), position: Maybe<J.Texture>, albedo: J.Texture) -> J.Frame & Buffer:
  (frame, parts) = r
  buffer.normal.parts(frame, parts, position, albedo)

# rlFramebufferAttach(..., gBuffer.normalTextureId, RL_ATTACHMENT_COLOR_CHANNEL1, RL_ATTACHMENT_TEXTURE2D, 0).
def buffer.position.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, normal: J.Texture, albedo: J.Texture) -> J.Frame & Buffer:
  (+fb, position) = parts
  buffer.normal.attached(J.Rlgl.framebuffer_attach(frame, fb, normal, 1, 100, 0), Some{position}, albedo)

def buffer.position.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), normal: J.Texture, albedo: J.Texture) -> J.Frame & Buffer:
  (frame, parts) = r
  buffer.position.parts(frame, parts, normal, albedo)

# rlActiveDrawBuffers(3); rlFramebufferAttach(..., gBuffer.positionTextureId, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0).
def buffer.textures(position: Maybe<J.Texture>, normal: Maybe<J.Texture>, albedo: Maybe<J.Texture>, bound: J.Rlgl.Bound, +fb: J.Rlgl.Framebuffer) -> J.Frame & Buffer:
  match position normal albedo:
    case Some{p} Some{n} Some{a}: buffer.position.attached(J.Rlgl.Bound.attach(J.Rlgl.Bound.active_draw_buffers(bound, 3.0), fb, p, 0, 100, 0), n, a)
    case _ _ _: (J.Rlgl.Bound.disable(bound), Buffer{fb, None{}, None{}, None{}, None{}})

# gBuffer.albedoSpecTextureId = rlLoadTexture(NULL, screenWidth, screenHeight, RL_PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1).
def buffer.albedo(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>, normal: Maybe<J.Texture>) -> J.Frame & Buffer:
  (bound, albedo) = r
  buffer.textures(position, normal, albedo, bound, fb)

# gBuffer.normalTextureId = rlLoadTexture(NULL, screenWidth, screenHeight, RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16, 1).
def buffer.normal(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, position: Maybe<J.Texture>) -> J.Frame & Buffer:
  (bound, normal) = r
  buffer.albedo(J.Rlgl.Bound.load_texture(bound, 800, 450, 7, 1), fb, position, normal)

# gBuffer.positionTextureId = rlLoadTexture(NULL, screenWidth, screenHeight, RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16, 1).
def buffer.position(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer) -> J.Frame & Buffer:
  (bound, position) = r
  buffer.normal(J.Rlgl.Bound.load_texture(bound, 800, 450, 12, 1), fb, position)

# gBuffer.framebufferId = rlLoadFramebuffer(); rlEnableFramebuffer(gBuffer.framebufferId).
def buffer.framebuffer(r: J.Frame & J.Rlgl.Framebuffer) -> J.Frame & Buffer:
  (frame, +fb) = r
  buffer.position(J.Rlgl.Bound.load_texture(J.Rlgl.enable_framebuffer(frame, fb), 800, 450, 12, 1), fb)

def setup.buffer(+libm: M.Libm, +core: J.Core, +dir: String, r: J.Frame & Buffer) -> J.Core & (J.Frame & State):
  (frame, buffer) = r
  setup.made(J.Mesh.gen_plane(10.0, 10.0, 3, 3), cubes.made(M.Libc.srand(libm, 1)), core, dir, frame, buffer)

# After InitWindow(800, 450): the models, the shaders, the G-buffer, the lights, the cubes, rlEnableDepthTest(), SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.buffer(libm, core, dir, buffer.framebuffer(J.Rlgl.load_framebuffer(frame)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - deferred rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, "", core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
