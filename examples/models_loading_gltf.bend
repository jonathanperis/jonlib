# raylib [models] example - loading gltf, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_loading_gltf.c (zlib/libpng,
# Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The robot model (LoadModel of a .glb: nineteen primitives under a skin of
# 43 joints, base color factors) under an orbital camera, its fourteen
# animations (LoadModelAnimations) switched with LEFT and RIGHT and
# advanced a keyframe a frame (UpdateModelAnimation). The reference library
# is built with GPU skinning and its software renderer runs no shader, so
# the model is drawn in its bind pose whatever the pose is: the update
# fills the pose and the bone matrices only, here the State's ModelPose
# (docs/MODELS.md). The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md), UpdateCamera its sinf/cosf (docs/SINCOSF.md) and
# the animations' QuaternionSlerp its acosf and sinf: under a profile
# without them the animations do not load and every frame is refused. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: everything loaded, an animation to play and no refusal so far.
# index is animIndex and current animCurrentFrame.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, pose: J.ModelPose, index: U32, current: U32}

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

# Every animation has a keyframe (the frame counter is taken modulo the count).
def playable(items: +List<J.ModelAnimation>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{item, rest}: (keyframes(item) > 0 : U32) && playable(rest)

def update.posed(posed: Maybe<J.ModelPose>, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +previous: J.ModelPose,
    +index: U32, +current: U32) -> State:
  match posed:
    case None{}: State{False{}, Some{camera}, model, textures, skeleton, animations, previous, index, current}
    case Some{+pose}: State{True{}, Some{camera}, model, textures, skeleton, animations, pose, index, current}

# UpdateModelAnimation(model, anims[animIndex], (float)animCurrentFrame).
def update.animated(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32,
    +current: U32) -> State:
  update.posed(J.Model.update_animation_for(libm, skeleton, pick(animations, index), U32.to_f32(current), pose), camera, model, textures, skeleton, animations, pose, index, current)

# RIGHT plays the next animation, else LEFT the one before.
def switched(+core: J.Core, +index: U32, +total: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 262), ((index + 1) % total : U32), Bool.pick(U32, J.Input.is_key_pressed(core, 263), ((index + total - 1) % total : U32), index))

# animCurrentFrame = (animCurrentFrame + 1)%anims[animIndex].keyframeCount.
def update.keyed(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32,
    +current: U32) -> State:
  update.animated(libm, camera, model, textures, skeleton, animations, pose, index, ((current + 1) % keyframes(pick(animations, index)) : U32))

def update.moved(updated: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose,
    +index: U32, +current: U32) -> State:
  match updated:
    case None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}
    case Some{+c}: update.keyed(libm, c, model, textures, skeleton, animations, pose, switched(core, index, count(animations, 0)), current)

# UpdateCamera(&camera, CAMERA_ORBITAL), the keys, the next keyframe.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +index: U32, +current: U32) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), libm, core, model, textures, skeleton, animations, pose, index, current)
    case _ None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, skeleton, animations, pose, index, current}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +index, +current} = state
  (core, update.live(valid, camera, libm, core, model, textures, skeleton, animations, pose, index, current))

# DrawGrid(10, 1.0f); EndMode3D(); the animation's name and the help.
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32, +current: U32,
    r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  f2 = J.Draw.text(f1, "Current animation: " ++ name(pick(animations, index)), 10.0, 40.0, 20.0, J.Color.MAROON())
  (core, (State{True{}, Some{camera}, model, textures, skeleton, animations, pose, index, current}, J.Draw.text(f2, "Use the LEFT/RIGHT keys to switch animation", 10.0, 10.0, 20.0, J.Color.GRAY())))

# DrawModel(model, (0, 0, 0), 1.0f, WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +index: U32, +current: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, model, skeleton, animations, pose, index, current,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, skeleton, animations, pose, index, current}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +index, +current} = state
  draw.at(valid, camera, libm, core, model, textures, skeleton, animations, pose, index, current, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def path(+dir: String) -> String:
  dir ++ "resources/models/gltf/robot.glb"

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, skeleton, animations, J.Model.pose(skeleton), 0, 0}))

def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, False{}, model, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, frame, (count(items, 0) > 0 : U32) && playable(items), model, textures, skeleton, items)

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
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - loading gltf", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
