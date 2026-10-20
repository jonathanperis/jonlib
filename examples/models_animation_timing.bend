# raylib [models] example - animation timing, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_animation_timing.c
# (zlib/libpng, Copyright (c) 2026 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The robot model under an orbital camera, one of its animations advanced by
# a fractional frame speed (UpdateModelAnimation between two keyframes), P
# pausing it. raygui controls (Jongui): a dropdown box with the animations'
# names, a slider for the speed, a label and a progress bar for the current
# frame, with a tick for every keyframe. raylib 6.2 skins the meshes on the
# CPU (no shader of the software renderer takes the bones) and DrawModel
# draws the skinned vertices; the pose is the Play's ModelPose
# (docs/MODELS.md). The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md), UpdateCamera its sinf/cosf (docs/SINCOSF.md) and
# QuaternionSlerp its acosf and sinf. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# index is animIndex, current animCurrentFrame, speed animFrameSpeed, paused
# animPause and edit dropdownEditMode; names is TextJoin(animNames, animCount, ";").
type Play is Data:
  Play{skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, names: String, pose: J.ModelPose, index: U32, current: F32, speed: F32, paused: Bool, edit: Bool}

# valid: everything loaded, the eleventh animation there and no refusal so far.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, gui: G.Gui, play: Play}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{6.0, 6.0, 6.0}, M.Vector3{0.0, 2.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def count(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def pick.first(items: +List<J.ModelAnimation>) -> J.ModelAnimation:
  match items:
    case Con{item, _}: item
    case Nil{}: J.ModelAnimation{"", 0, 0, Nil{}}

# anims[index].
def pick(items: +List<J.ModelAnimation>, +index: U32) -> J.ModelAnimation:
  pick.first(List.drop(&2, J.ModelAnimation, items, U32.to_nat(index)))

def keyframes(animation: J.ModelAnimation) -> U32:
  J.ModelAnimation{_, _, total, _} = animation
  total

def name(animation: J.ModelAnimation) -> String:
  J.ModelAnimation{text, _, _, _} = animation
  text

# The skinned model and the play after an update.
type Step is Data:
  Step{model: J.Model, play: Play}

def update.posed(posed: Maybe<J.AnimatedModel>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String, +index: U32, +current: F32, +speed: F32, +edit: Bool) -> Maybe<Step>:
  match posed:
    case None{}: None{}
    case Some{J.AnimatedModel{+model, +pose}}: Some{Step{model, Play{skeleton, animations, names, pose, index, current, speed, False{}, edit}}}

# animCurrentFrame += animFrameSpeed, back to 0 at the keyframe count; UpdateModelAnimation(model, anims[animIndex], animCurrentFrame).
def update.stepped(halted: Bool, +libm: M.Libm, +model: J.Model, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String, +pose: J.ModelPose, +index: U32, +current: F32, +speed: F32,
    +edit: Bool) -> Maybe<Step>:
  match halted:
    case True{}: Some{Step{model, Play{skeleton, animations, names, pose, index, current, speed, True{}, edit}}}
    case False{}:
      +next = (current + speed : F32)
      +frame = Bool.pick(F32, (next >= U32.to_f32(keyframes(pick(animations, index))) : F32), 0.0, next)
      update.posed(J.Model.update_animation_for(libm, model, skeleton, pick(animations, index), frame, pose), skeleton, animations, names, index, frame, speed, edit)

# P pauses; None when the pose is refused.
def update.play(+libm: M.Libm, +core: J.Core, +model: J.Model, play: Play) -> Maybe<Step>:
  Play{+skeleton, +animations, +names, +pose, +index, +current, +speed, +paused, +edit} = play
  update.stepped(Bool.pick(Bool, J.Input.is_key_pressed(core, 80), Bool.not(paused), paused), libm, model, skeleton, animations, names, pose, index, current, speed, edit)

def update.stepped.state(+camera: J.Camera3D, step: Step, textures: List<J.Texture>, +gui: G.Gui) -> State:
  Step{+model, +play} = step
  State{True{}, Some{camera}, model, textures, gui, play}

def update.moved(updated: Maybe<J.Camera3D>, played: Maybe<Step>, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +old: Play) -> State:
  match updated played:
    case Some{+c} Some{+s}: update.stepped.state(c, s, textures, gui)
    case Some{+c} None{}: State{False{}, Some{c}, model, textures, gui, old}
    case None{} _: State{False{}, None{}, model, textures, gui, old}

# UpdateCamera(&camera, CAMERA_ORBITAL), then the animation.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), update.play(libm, core, model, play), model, textures, gui, play)
    case _ None{}: State{False{}, None{}, model, textures, gui, play}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, gui, play}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +gui, +play} = state
  (core, update.live(valid, camera, libm, core, model, textures, gui, play))

# DrawRectangle(10 + (int)(((float)(GetScreenWidth() - 20)/(float)keyframeCount)*(float)i), GetScreenHeight() - 40, 1, 24, BLUE) for every keyframe.
def ticks(n: Nat, +i: U32, +total: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: ticks(p, (i + 1 : U32), total, J.Draw.rectangle(frame, (10.0 + F32.trunc(((780.0 / U32.to_f32(total)) * U32.to_f32(i) : F32)) : F32), 410.0, 1.0, 24.0, J.Color.BLUE()))

def draw.bar(r: J.Frame & F32, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play, +total: U32) -> J.Core & (State & J.Frame):
  (frame, _) = r
  (core, (State{True{}, Some{camera}, model, textures, gui, play}, ticks(U32.to_nat(total), 0, total, frame)))

def current.of(play: Play) -> F32:
  Play{_, _, _, _, _, current, _, _, _} = play
  current

# GuiLabel with the frame and the keyframe count, GuiProgressBar over them (its capped value is a copy natively), the ticks.
def draw.labeled(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play, +total: U32) -> J.Core & (State & J.Frame):
  match text:
    case None{}: (core, (State{False{}, Some{camera}, model, textures, gui, play}, J.Frame.refuse(frame)))
    case Some{t}: draw.bar(G.Gui.progress_bar(gui, G.Gui.label(gui, frame, J.Rectangle{10.0, 386.0, 780.0, 24.0}, t), J.Rectangle{10.0, 410.0, 780.0, 24.0}, None{}, None{}, current.of(play), 0.0,
      U32.to_f32(total)), core, camera, model, textures, gui, play, total)

# The slider's Gui (a drag is its state) and value.
type Slid is Data:
  Slid{gui: G.Gui, speed: F32}

def slid.value(pair: F32 & Bool) -> F32:
  (value, _) = pair
  value

def slid(rest: G.Gui & (F32 & Bool)) -> Slid:
  (gui, pair) = rest
  Slid{gui, slid.value(pair)}

def draw.sped(result: Slid, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String,
    +pose: J.ModelPose, +index: U32, +current: F32, +paused: Bool, +edit: Bool) -> J.Core & (State & J.Frame):
  Slid{+gui, +speed} = result
  draw.labeled(J.Text.format("CURRENT FRAME: %.2f / %i", [J.TextFloat{current}, J.TextInt{keyframes(pick(animations, index))}]), frame, core, camera, model, textures, gui,
    Play{skeleton, animations, names, pose, index, current, speed, paused, edit}, keyframes(pick(animations, index)))

def draw.rest(r: J.Frame & (G.Gui & (F32 & Bool)), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String,
    +pose: J.ModelPose, +index: U32, +current: F32, +paused: Bool, +edit: Bool) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.sped(slid(rest), frame, core, camera, model, textures, skeleton, animations, names, pose, index, current, paused, edit)

# GuiSlider((260, 10, 500, 24), "FRAME SPEED: ", TextFormat("x%.1f", animFrameSpeed), &animFrameSpeed, 0.1f, 2.0f).
def draw.slid(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +names: String, +pose: J.ModelPose, +index: U32, +current: F32, +speed: F32, +paused: Bool, +edit: Bool) -> J.Core & (State & J.Frame):
  match text:
    case None{}: (core, (State{False{}, Some{camera}, model, textures, gui, Play{skeleton, animations, names, pose, index, current, speed, paused, edit}}, J.Frame.refuse(frame)))
    case Some{t}: draw.rest(G.Gui.slider(gui, core, frame, J.Rectangle{260.0, 10.0, 500.0, 24.0}, Some{"FRAME SPEED: "}, Some{t}, speed, 0.1, 2.0), core, camera, model, textures, skeleton, animations, names,
      pose, index, current, paused, edit)

# The dropdown's result: the active animation, and the edit mode flipped when raygui answers true.
def draw.chosen(pair: U32 & Bool, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +names: String, +pose: J.ModelPose, +current: F32, +speed: F32, +paused: Bool, +edit: Bool) -> J.Core & (State & J.Frame):
  (+index, +toggled) = pair
  draw.slid(J.Text.format("x%.1f", [J.TextFloat{speed}]), frame, core, camera, model, textures, gui, skeleton, animations, names, pose, index, current, speed, paused, Bool.pick(Bool, toggled, Bool.not(edit), edit))

def draw.dropped(r: J.Frame & (U32 & Bool), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +names: String, +pose: J.ModelPose, +current: F32, +speed: F32, +paused: Bool, +edit: Bool) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  draw.chosen(pair, frame, core, camera, model, textures, gui, skeleton, animations, names, pose, current, speed, paused, edit)

# DrawGrid(10, 1.0f); EndMode3D(); GuiDropdownBox((10, 10, 140, 24), names, &animIndex, dropdownEditMode).
def draw.gui(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +gui: G.Gui, play: Play, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  Play{+skeleton, +animations, +names, +pose, +index, +current, +speed, +paused, +edit} = play
  (frame, textures) = r
  draw.dropped(G.Gui.dropdown_box(gui, core, J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)), J.Rectangle{10.0, 10.0, 140.0, 24.0}, names, index, edit), core, camera, model, textures, gui, skeleton,
    animations, names, pose, current, speed, paused, edit)

# DrawModel(model, (0, 0, 0), 1.0f, WHITE); GuiSetStyle(DROPDOWNBOX, DROPDOWN_ITEMS_SPACING, 1).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.gui(core, c, model, G.Gui.set_style(gui, 8, 17, 1), play,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, gui, play}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, gui, play}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +gui, +play} = state
  draw.at(valid, camera, libm, core, model, textures, gui, play, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def path(+dir: String) -> String:
  dir ++ "resources/models/gltf/robot.glb"

# TextJoin(animNames, animCount, ";").
def joined(items: +List<J.ModelAnimation>, +first: Bool) -> String:
  match items:
    case Nil{}: ""
    case Con{item, rest}: Bool.pick(String, first, "", ";") ++ name(item) ++ joined(rest, False{})

# Every animation has a keyframe.
def playable(items: +List<J.ModelAnimation>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{item, rest}: (keyframes(item) > 0 : U32) && playable(rest)

# animIndex = 10, animFrameSpeed = 0.5f; SetTargetFPS(60).
def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, G.Gui.new(), Play{skeleton, animations, joined(animations, True{}), J.Model.pose(skeleton), 10, 0.0, 0.5, False{}, False{}}}))

def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, False{}, model, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, frame, (count(items, 0) > 10 : U32) && playable(items), model, textures, skeleton, items)

# anims = LoadModelAnimations("resources/models/gltf/robot.glb", &animCount).
def setup.skeleton(result: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, model, textures, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, J.Core & (J.Frame & State), J.Model.load_animations_for(libm, path(dir)),
        a => IO.pure(J.Core & (J.Frame & State), setup.animations(a, core, frame, model, textures, skeleton)))

# The model's skeleton, which Jonlib loads beside the model.
def setup.model(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, J.Core & (J.Frame & State), J.Model.load_skeleton(path(dir)), s => setup.skeleton(s, libm, dir, core, frame, model, textures))

def setup.loaded(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{loaded}: setup.model(libm, dir, core, frame, loaded)

# After InitWindow(800, 450): LoadModel("resources/models/gltf/robot.glb"), its animations, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, path(dir)), r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - animation timing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
