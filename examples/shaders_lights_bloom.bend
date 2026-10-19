# raylib [shaders] example - lights bloom, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_lights_bloom.c
# (zlib/libpng, Copyright (c) 2025 PanicTitan (@PanicTitan)); see
# LICENSES/raylib.txt.
#
# A cube (GenMeshCube) on a floor (GenMeshPlane) under an orbital camera,
# drawn into a render texture with eight point lights circling them, each
# marked by a sphere of its color; the render texture is then drawn
# (y-flipped DrawTextureRec) through a bloom and tone-mapping shader. On the
# software renderer shaders do not exist (docs/SHADERS.md): both shaders load
# with id 0, every location is -1 (the uniforms are skipped) and the models
# and the shader mode draw as with the default shader, which is what the
# reference draws too. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md); UpdateCamera, the bulbs and the lights' sinf/cosf
# of the clock follow its profile (docs/SINCOSF.md); a refused camera, clock
# or angle refuses the frame and every later one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: nothing refused so far; lights: lightPositions (MAX_LIGHTS 8); light, bloom: lightShader and
# bloomShader; box, ground: the cube and floor models.
type Scene is Data:
  Scene{valid: Bool, camera: J.Camera3D, lights: +List<M.Vector3>, light: J.Shader, bloom: J.Shader, box: J.Model, ground: J.Model}

type State is Type:
  State{scene: Scene, target: Maybe<J.RenderTexture>}

# The positions computed from the clock, and whether every sinf/cosf answered.
type Spots is Data:
  Spots{valid: Bool, list: +List<M.Vector3>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 5.0, 9.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# lightColors: red, green, blue, yellow, magenta, cyan, orange, purple.
def palette() -> +List<M.Vector3>:
  [M.Vector3{1.0, 0.2, 0.2}, M.Vector3{0.2, 1.0, 0.3}, M.Vector3{0.2, 0.5, 1.0}, M.Vector3{1.0, 0.8, 0.1},
   M.Vector3{1.0, 0.1, 0.8}, M.Vector3{0.1, 1.0, 1.0}, M.Vector3{1.0, 0.4, 0.1}, M.Vector3{0.7, 0.2, 1.0}]

# A vec3 array's words (x, y, z per element), as SetShaderValue(V) reads them.
def words.of(+v: M.Vector3, +rest: +List<U32>) -> +List<U32>:
  M.Vector3{+x, +y, +z} = v
  Con{F32.bits(x), Con{F32.bits(y), Con{F32.bits(z), rest}}}

def words(list: +List<M.Vector3>) -> +List<U32>:
  match list:
    case Nil{}: Nil{}
    case Con{+v, rest}: words.of(v, words(rest))

# lightPositions[i] = (sinf(angle)*radius, height, cosf(angle)*radius) with radius = 4.2f + sinf(time*1.2f + i)*0.4f
# and height = 1.0f + sinf(time*1.8f + i)*0.6f.
def spot(+rest: Spots, sa: Maybe<F32>, ca: Maybe<F32>, sr: Maybe<F32>, sh: Maybe<F32>) -> Spots:
  Spots{+valid, +list} = rest
  match sa ca sr sh:
    case Some{+s} Some{+c} Some{+r} Some{+h}: Spots{valid, Con{M.Vector3{(s * (4.2 + r * 0.4) : F32), (1.0 + h * 0.6 : F32), (c * (4.2 + r * 0.4) : F32)}, list}}
    case _ _ _ _: Spots{False{}, list}

# angle = (i/(float)MAX_LIGHTS)*2.0f*PI + time*0.6f.
def angle(+time: F32, +i: U32) -> F32:
  ((((U32.to_f32(i) / 8.0) * 2.0) * M.Math.PI()) + time * 0.6 : F32)

# The lights i, i + 1, ... (n of them), in the loop's order.
def orbits(n: Nat, +libm: M.Libm, +time: F32, +i: U32) -> Spots:
  match n:
    case 0n: Spots{True{}, Nil{}}
    case 1n+p: spot(orbits(p, libm, time, (i + 1 : U32)), M.Libm.sin(libm, angle(time, i)), M.Libm.cos(libm, angle(time, i)),
      M.Libm.sin(libm, (time * 1.2 + U32.to_f32(i) : F32)), M.Libm.sin(libm, (time * 1.8 + U32.to_f32(i) : F32)))

# SetShaderValueV(lightShader, lightPosLoc, lightPositions, SHADER_UNIFORM_VEC3, MAX_LIGHTS);
# SetShaderValue(lightShader, viewPosLoc, &camera.position, SHADER_UNIFORM_VEC3) (both locations are -1 here).
def placed.at(+valid: Bool, +camera: J.Camera3D, +light: J.Shader, +bloom: J.Shader, +box: J.Model, +ground: J.Model, +spots: Spots) -> Scene:
  J.Camera3D{+position, _, _, _, _} = camera
  Spots{+ok, +list} = spots
  Scene{valid && ok, camera, list, J.Shader.set_value(J.Shader.set_value_v(light, J.Shader.get_location(light, "lightPositions"), words(list), 2, 8),
    J.Shader.get_location(light, "viewPos"), words([position]), 2), bloom, box, ground}

# A refusal stays: once invalid, the camera and the lights no longer move.
def placed(+valid: Bool, +camera: J.Camera3D, +light: J.Shader, +bloom: J.Shader, +box: J.Model, +ground: J.Model, +lights: +List<M.Vector3>, +libm: M.Libm, moved: Maybe<J.Camera3D>, clock: Maybe<F32>) -> Scene:
  match moved clock:
    case Some{+c} Some{+t}: placed.at(valid, c, light, bloom, box, ground, orbits(8n, libm, t, 0))
    case _ _: Scene{False{}, camera, lights, light, bloom, box, ground}

# UpdateCamera(&camera, CAMERA_ORBITAL); time = (float)GetTime(); the light positions and the uniforms.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+scene, target} = state
  Scene{+valid, +camera, +lights, +light, +bloom, +box, +ground} = scene
  (core, State{placed(valid, camera, light, bloom, box, ground, lights, libm, J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_ORBITAL()),
    M.Float64.to_f32(J.Core.get_time(core))), target})

# bulbColor = ((unsigned char)(lightColors[i].x*255), ..y.., ..z.., 255).
def bulb(+c: M.Vector3) -> U32:
  M.Vector3{+x, +y, +z} = c
  J.Color.rgba(F32.to_u32((x * 255.0 : F32)), F32.to_u32((y * 255.0 : F32)), F32.to_u32((z * 255.0 : F32)), 255)

# DrawSphere(lightPositions[i], 0.15f, bulbColor) for each light.
def bulbs(+libm: M.Libm, list: +List<M.Vector3>, colors: +List<M.Vector3>, frame: J.Frame) -> J.Frame:
  match list colors:
    case Con{+p, ps} Con{+c, cs}: bulbs(libm, ps, cs, J.Draw.sphere_for(libm, frame, p, 0.15, bulb(c)))
    case _ _: frame

def modeled(+model: J.Model, +position: M.Vector3, +tint: U32, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  (frame, textures) = r
  J.Draw.model(frame, textures, model, position, 1.0, tint)

def modeled.frame(r: J.Frame & List<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# EndShaderMode(); DrawText("BALANCED MULTI-LIGHT + REINHARD TONE MAPPED BLOOM", 20, 20, 20, GREEN).
def draw.shown(+core: J.Core, +scene: Scene, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{scene, Some{J.RenderTexture{id, texture, depth}}},
    J.Draw.text(J.Frame.end_shader_mode(frame), "BALANCED MULTI-LIGHT + REINHARD TONE MAPPED BLOOM", 20.0, 20.0, 20.0, J.Color.GREEN())))

# ClearBackground(BLACK); BeginShaderMode(bloomShader); DrawTextureRec(target.texture,
# (0, 0, (float)width, (float)-height), (0, 0), WHITE).
def draw.screen(+core: J.Core, +scene: Scene, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  Scene{_, _, _, _, +bloom, _, _} = scene
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(core, scene, id, depth,
    J.Draw.texture_rec(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.BLACK()), bloom), J.Texture{tid, w, h, format, linear, alpha, texels},
      J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def draw.ended(+core: J.Core, +scene: Scene, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(core, scene, frame, t)

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# ClearBackground((12, 12, 18, 255)); BeginMode3D(camera); DrawModel(cube, (0, 1, 0), 1.0f, GRAY);
# DrawModel(floor, (0, 0, 0), 1.0f, DARKGRAY); DrawGrid(10, 1.0f); the bulbs; EndMode3D(); EndTextureMode().
def draw.scene(+libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  Scene{_, +camera, +lights, _, _, +box, +ground} = scene
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, target), J.Color.rgba(12, 12, 18, 255)), camera)
  f2 = J.Draw.grid(modeled.frame(modeled(ground, M.Vector3.zero(), J.Color.DARKGRAY(), J.Draw.model(f1, Nil{}, box, M.Vector3{0.0, 1.0, 0.0}, 1.0, J.Color.GRAY()))), 10.0, 1.0)
  draw.ended(core, scene, J.Frame.end_texture_mode(J.Frame.end_mode_3d(bulbs(libm, lights, palette(), f2))))

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid target:
    case True{} Some{t}: draw.scene(libm, core, scene, frame, t)
    case True{} None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))
    case False{} Some{t}: (core, (State{scene, Some{t}}, J.Frame.refuse(frame)))
    case False{} None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+scene, target} = state
  Scene{+valid, _, _, _, _, _, _} = scene
  draw.valid(valid, libm, core, scene, frame, target)

# The main loop's body; libm is the profile of UpdateCamera's, the bulbs' and the lights' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.done(+core: J.Core, +scene: Scene, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{scene, target}))

# cube = LoadModelFromMesh(GenMeshCube(2, 2, 2)); floor = LoadModelFromMesh(GenMeshPlane(14, 14, 1, 1));
# materials[0].shader = lightShader (the default shader's id, 0, here).
def setup.models(+light: J.Shader, +bloom: J.Shader, plane: Maybe<J.Mesh>) -> Scene:
  match plane:
    case Some{+g}: Scene{True{}, start(), Nil{}, light, bloom, J.Model.from_mesh(J.Mesh.gen_cube(2.0, 2.0, 2.0)), J.Model.from_mesh(g)}
    case None{}: Scene{False{}, start(), Nil{}, light, bloom, J.Model.from_mesh(J.Mesh.gen_cube(2.0, 2.0, 2.0)), J.Model.empty()}

# After SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_VSYNC_HINT) and InitWindow(800, 450): the camera,
# target = LoadRenderTexture(800, 450), LoadShader of lights_bloom.vs/.fs and of lights_bloom_post.fs
# (id 0 here, as on the software renderer), the models, SetShaderValueV(lightShader, lightColLoc,
# lightColors, SHADER_UNIFORM_VEC3, MAX_LIGHTS), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  +light = J.Shader.load(Some{"resources/shaders/glsl330/lights_bloom.vs"}, Some{"resources/shaders/glsl330/lights_bloom.fs"})
  +bloom = J.Shader.load(None{}, Some{"resources/shaders/glsl330/lights_bloom_post.fs"})
  +colored = J.Shader.set_value_v(light, J.Shader.get_location(light, "lightColors"), words(palette()), 2, 8)
  setup.done(core, setup.models(colored, bloom, J.Mesh.gen_plane(14.0, 14.0, 1, 1)), J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 96, "raylib [shaders] example - lights bloom", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
