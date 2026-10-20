# raylib [shaders] example - basic lighting, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_basic_lighting.c
# (zlib/libpng, Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt. CreateLight and
# UpdateLightValues are Jonlights' (docs/LIGHTS.md).
#
# An orbital camera around a plane and a cube drawn with the lighting shader,
# and four point lights (Y/R/G/B toggle them: a solid sphere when on, a
# translucent wire sphere when off). On the software renderer shaders do not
# exist (docs/SHADERS.md): the shader loads with id 0, every uniform is
# ignored and the shader mode draws as the default one, which is what the
# reference draws too. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md), UpdateCamera and DrawSphereWires its sinf/cosf
# (docs/SINCOSF.md); a refused UpdateCamera refuses the frame and every later
# one. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jonlights.bend as L

# lights[MAX_LIGHTS], in creation order.
type State is Data:
  State{camera: +Maybe<J.Camera3D>, lights: +List<L.Light>, shader: J.Shader}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 4.0, 6.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# lights[i].enabled = !lights[i].enabled when its key is pressed.
def light.toggled(+flip: Bool, +one: L.Light) -> L.Light:
  L.Light{+kind, +enabled, +position, +target, +color, +attenuation, +el, +tl, +pl, +gl, +cl, +al} = one
  L.Light{kind, Bool.pick(Bool, flip, Bool.not(enabled), enabled), position, target, color, attenuation, el, tl, pl, gl, cl, al}

# KEY_Y, KEY_R, KEY_G and KEY_B, one per light.
def toggled(+core: J.Core, +keys: +List<U32>, +lights: +List<L.Light>) -> +List<L.Light>:
  match keys lights:
    case Con{+k, +ks} Con{+l, +ls}: Con{light.toggled(J.Input.is_key_pressed(core, k), l), toggled(core, ks, ls)}
    case _ _: Nil{}

# for (i < MAX_LIGHTS) UpdateLightValues(shader, lights[i]).
def updated(+lights: +List<L.Light>, +shader: J.Shader) -> J.Shader:
  match lights:
    case Nil{}: shader
    case Con{+l, +ls}: updated(ls, L.Light.update_values(shader, l))

def camera.updated(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def camera.update(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: camera.updated(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

# The camera position as a vec3 uniform (SetShaderValue(shader, locs[SHADER_LOC_VECTOR_VIEW], ...)).
def view.at(+shader: J.Shader, camera: J.Camera3D) -> J.Shader:
  J.Camera3D{position, _, _, _, _} = camera
  M.Vector3{+x, +y, +z} = position
  J.Shader.set_value(shader, 4294967295, [F32.bits(x), F32.bits(y), F32.bits(z)], 2)

def view(+shader: J.Shader, camera: +Maybe<J.Camera3D>) -> J.Shader:
  match camera:
    case None{}: shader
    case Some{+c}: view.at(shader, c)

# UpdateCamera(CAMERA_ORBITAL), the view uniform, the toggles and UpdateLightValues (no-ops here).
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +lights, +shader} = state
  +moved = camera.update(libm, core, camera)
  +switched = toggled(core, [89, 82, 71, 66], lights)
  (core, State{moved, switched, updated(switched, view(shader, moved))})

# DrawSphereEx(position, 0.2, 8, 8, color) when on, else DrawSphereWires with ColorAlpha(color, 0.3).
def light.drawn(+libm: M.Libm, on: Bool, position: M.Vector3, +color: U32, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: J.Draw.sphere_ex_for(libm, frame, position, 0.2, 8.0, 8.0, color)
    case False{}: J.Draw.sphere_wires_for(libm, frame, position, 0.2, 8.0, 8.0, J.Color.with_alpha(color, 0.3))

def light(+libm: M.Libm, +one: L.Light, frame: J.Frame) -> J.Frame:
  L.Light{_, +enabled, +position, _, +color, _, _, _, _, _, _, _} = one
  light.drawn(libm, enabled, position, color, frame)

def lights(+libm: M.Libm, +all: +List<L.Light>, frame: J.Frame) -> J.Frame:
  match all:
    case Nil{}: frame
    case Con{+l, +ls}: lights(libm, ls, light(libm, l, frame))

def scene.at(+libm: M.Libm, +camera: J.Camera3D, +shader: J.Shader, +on: +List<L.Light>, frame: J.Frame) -> J.Frame:
  f1 = J.Frame.begin_shader_mode(J.Frame.begin_mode_3d_for(libm, frame, camera), shader)
  f2 = J.Frame.end_shader_mode(J.Draw.cube(J.Draw.plane(f1, M.Vector3.zero(), M.Vector2{10.0, 10.0}, J.Color.WHITE()), M.Vector3.zero(), 2.0, 4.0, 2.0, J.Color.WHITE()))
  J.Frame.end_mode_3d(J.Draw.grid(lights(libm, on, f2), 10.0, 1.0))

def scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, +shader: J.Shader, +on: +List<L.Light>, frame: J.Frame) -> J.Frame:
  match camera:
    case None{}: J.Frame.refuse(frame)
    case Some{+c}: scene.at(libm, c, shader, on, frame)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.text(J.Draw.fps(frame, 10.0, 10.0, fps), "Use keys [Y][R][G][B] to toggle lights", 10.0, 40.0, 20.0, J.Color.DARKGRAY())))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +on, +shader} = state
  f1 = scene(libm, camera, shader, on, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  draw.fps.done(state, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of UpdateCamera's and the spheres' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def snoc(+xs: +List<L.Light>, +x: L.Light) -> +List<L.Light>:
  match xs:
    case Nil{}: [x]
    case Con{+h, +rest}: Con{h, snoc(rest, x)}

def created.add(+list: +List<L.Light>, +shader: J.Shader, made: L.Lights & L.Light) -> (L.Lights & +List<L.Light>) & J.Shader:
  (count, +light) = made
  ((count, snoc(list, light)), shader)

def created.made(+list: +List<L.Light>, made: (L.Lights & L.Light) & J.Shader) -> (L.Lights & +List<L.Light>) & J.Shader:
  (inner, +shader) = made
  created.add(list, shader, inner)

def created.inner(+shader: J.Shader, +position: M.Vector3, +color: U32, inner: L.Lights & +List<L.Light>) -> (L.Lights & +List<L.Light>) & J.Shader:
  (count, +list) = inner
  created.made(list, L.Light.create(count, L.LightType.LIGHT_POINT(), position, M.Vector3.zero(), color, shader))

# lights[i] = CreateLight(LIGHT_POINT, position, Vector3Zero(), color, shader).
def created(st: (L.Lights & +List<L.Light>) & J.Shader, +position: M.Vector3, +color: U32) -> (L.Lights & +List<L.Light>) & J.Shader:
  (inner, +shader) = st
  created.inner(shader, position, color, inner)

def started.with(+core: J.Core, frame: J.Frame, +shader: J.Shader, inner: L.Lights & +List<L.Light>) -> J.Core & (J.Frame & State):
  (_, +lights) = inner
  (J.Core.set_target_fps(core, 60), (frame, State{Some{start()}, lights, shader}))

def started(+core: J.Core, frame: J.Frame, made: (L.Lights & +List<L.Light>) & J.Shader) -> J.Core & (J.Frame & State):
  (inner, +shader) = made
  started.with(core, frame, shader, inner)

# LoadShader of the lighting shader (id 0 here, as on the software renderer),
# the ambient uniform and four point lights (CreateLight enables them);
# SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  +shader = J.Shader.load(Some{"resources/shaders/glsl330/lighting.vs"}, Some{"resources/shaders/glsl330/lighting.fs"})
  +ambient = J.Shader.set_value(shader, J.Shader.get_location(shader, "ambient"), [F32.bits(0.1), F32.bits(0.1), F32.bits(0.1), F32.bits(1.0)], 3)
  s1 = created(((L.Lights.new(), []), ambient), M.Vector3{F32.neg(2.0), 1.0, F32.neg(2.0)}, J.Color.YELLOW())
  s2 = created(s1, M.Vector3{2.0, 1.0, 2.0}, J.Color.RED())
  s3 = created(s2, M.Vector3{F32.neg(2.0), 1.0, 2.0}, J.Color.GREEN())
  started(core, frame, created(s3, M.Vector3{2.0, 1.0, F32.neg(2.0)}, J.Color.BLUE()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - basic lighting", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
