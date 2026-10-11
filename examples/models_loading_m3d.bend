# raylib [models] example - loading m3d, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_loading_m3d.c (zlib/libpng,
# Copyright (c) 2022-2025 bzt (@bztsrc)); see LICENSES/raylib.txt.
#
# The CesiumMan model (LoadModel of an .m3d file: 4672 faces, a material
# color, nineteen bones) under an orbital camera, its animation
# (LoadModelAnimations: 112 keyframes) advanced a keyframe a frame
# (UpdateModelAnimation) and switched with LEFT and RIGHT. While SPACE is
# held the example draws the animated skeleton instead of the model: a cube
# a bone at the keyframe's pose and a line to its parent (its
# DrawModelSkeleton). The reference library is built with GPU skinning and
# its software renderer runs no shader, so the model itself is drawn in its
# bind pose whatever the pose is (docs/MODELS.md). The perspective needs
# the libm profile's binary64 tan (docs/PERSPECTIVE.md), UpdateCamera its
# sinf/cosf (docs/SINCOSF.md) and the pose's QuaternionSlerp its acosf and
# sinf. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: everything loaded, an animation to play and no refusal so far.
# index is animIndex and current animCurrentFrame.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, pose: J.ModelPose, index: U32, current: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{1.5, 1.5, 1.5}, M.Vector3{0.0, 0.4, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

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

def poses(animation: J.ModelAnimation) -> +List<+List<J.Transform>>:
  J.ModelAnimation{_, _, _, frames} = animation
  frames

# Every animation has a keyframe (the frame counter is compared with the count).
def playable(items: +List<J.ModelAnimation>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{item, rest}: (keyframes(item) > 0 : U32) && playable(rest)

def update.posed(posed: Maybe<J.ModelPose>, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +previous: J.ModelPose,
    +index: U32, +current: F32) -> State:
  match posed:
    case None{}: State{False{}, Some{camera}, model, textures, skeleton, animations, previous, index, current}
    case Some{+pose}: State{True{}, Some{camera}, model, textures, skeleton, animations, pose, index, current}

# UpdateModelAnimation(model, anims[animIndex], animCurrentFrame).
def update.animated(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32,
    +current: F32) -> State:
  update.posed(J.Model.update_animation_for(libm, skeleton, pick(animations, index), current, pose), camera, model, textures, skeleton, animations, pose, index, current)

# RIGHT plays the next animation, else LEFT the one before.
def switched(+core: J.Core, +index: U32, +total: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 262), ((index + 1) % total : U32), Bool.pick(U32, J.Input.is_key_pressed(core, 263), ((index + total - 1) % total : U32), index))

# animCurrentFrame += 1.0f; if (animCurrentFrame >= anims[animIndex].keyframeCount) animCurrentFrame = 0.0f.
def advanced(+current: F32, +total: U32) -> F32:
  Bool.pick(F32, ((current + 1.0) >= U32.to_f32(total) : F32), 0.0, (current + 1.0 : F32))

def update.keyed(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32,
    +current: F32) -> State:
  update.animated(libm, camera, model, textures, skeleton, animations, pose, index, advanced(current, keyframes(pick(animations, index))))

def update.moved(updated: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose,
    +index: U32, +current: F32) -> State:
  match updated:
    case None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}
    case Some{+c}: update.keyed(libm, c, model, textures, skeleton, animations, pose, switched(core, index, count(animations, 0)), current)

# UpdateCamera(&camera, CAMERA_ORBITAL), the keys, the next keyframe.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +index: U32, +current: F32) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), libm, core, model, textures, skeleton, animations, pose, index, current)
    case _ None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, skeleton, animations, pose, index, current}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +index, +current} = state
  (core, update.live(valid, camera, libm, core, model, textures, skeleton, animations, pose, index, current))

def place(+t: J.Transform) -> M.Vector3:
  J.Transform{+translation, _, _} = t
  translation

def pose.first(items: +List<J.Transform>) -> M.Vector3:
  match items:
    case Con{+item, _}: place(item)
    case Nil{}: M.Vector3.zero()

# pose[index].translation.
def pose.at(+items: +List<J.Transform>, +index: U32) -> M.Vector3:
  pose.first(List.drop(&2, J.Transform, items, U32.to_nat(U32.min(index, 65536))))

# if (skeleton.bones[i].parent >= 0) DrawLine3D(pose[i].translation, pose[parent].translation, color).
def bone.line(parented: Bool, frame: J.Frame, +from: M.Vector3, +to: M.Vector3) -> J.Frame:
  match parented:
    case False{}: frame
    case True{}: J.Draw.line_3d(frame, from, to, J.Color.RED())

# DrawModelSkeleton(skeleton, pose, 1.0f, RED): a cube of 0.05 a bone but the last (the no-bone one), and a line to its parent.
def skeleton.drawn(n: Nat, bones: +List<J.BoneInfo>, poses: +List<J.Transform>, +all: +List<J.Transform>, frame: J.Frame) -> J.Frame:
  match n bones poses:
    case 1n+k Con{J.BoneInfo{_, +parent}, rest} Con{+t, more}:
      skeleton.drawn(k, rest, more, all, bone.line((parent < 2147483648 : U32), J.Draw.cube(frame, place(t), 0.05, 0.05, 0.05, J.Color.RED()), place(t), pose.at(all, parent)))
    case _ _ _: frame

def frame.first(items: +List<+List<J.Transform>>) -> +List<J.Transform>:
  match items:
    case Con{+item, _}: item
    case Nil{}: Nil{}

# anims[animIndex].keyframePoses[(int)animCurrentFrame].
def keyframe(+animation: J.ModelAnimation, +current: F32) -> +List<J.Transform>:
  frame.first(List.drop(&2, +List<J.Transform>, poses(animation), U32.to_nat(F32.to_u32(current))))

def bones.count(bones: +List<J.BoneInfo>, +n: U32) -> U32:
  match bones:
    case Nil{}: n
    case Con{_, rest}: bones.count(rest, (n + 1 : U32))

def skeleton.shown(+skeleton: J.ModelSkeleton, +pose: +List<J.Transform>, frame: J.Frame) -> J.Frame:
  J.ModelSkeleton{+bones, _} = skeleton
  skeleton.drawn(U32.to_nat((bones.count(bones, 0) - Bool.pick(U32, U32.is_eq(bones.count(bones, 0), 0), 0, 1) : U32)), bones, pose, pose, frame)

# if (!IsKeyDown(KEY_SPACE)) DrawModel(model, position, 1.0f, WHITE); else DrawModelSkeleton(...).
def draw.shown(skeletal: Bool, +skeleton: J.ModelSkeleton, +animation: J.ModelAnimation, +current: F32, +model: J.Model, frame: J.Frame, textures: List<J.Texture>) -> J.Frame & List<J.Texture>:
  match skeletal:
    case False{}: J.Draw.model(frame, textures, model, M.Vector3.zero(), 1.0, J.Color.WHITE())
    case True{}: (skeleton.shown(skeleton, keyframe(animation, current), frame), textures)

# DrawGrid(10, 1.0f); EndMode3D(); the animation's name and the texts.
def draw.done(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32, +current: F32,
    r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  f2 = J.Draw.text(f1, "Current animation: " ++ name(pick(animations, index)), 10.0, 10.0, 20.0, J.Color.LIGHTGRAY())
  f3 = J.Draw.text(f2, "Press SPACE to draw skeleton", 10.0, 40.0, 20.0, J.Color.MAROON())
  (core, (State{True{}, Some{camera}, model, textures, skeleton, animations, pose, index, current}, J.Draw.text(f3, "(c) CesiumMan model by KhronosGroup", 590.0, 430.0, 10.0, J.Color.GRAY())))

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +index: U32, +current: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.done(core, c, model, skeleton, animations, pose, index, current,
      draw.shown(J.Input.is_key_down(core, 32), skeleton, pick(animations, index), current, model, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures))
    case _ None{}: (core, (State{False{}, None{}, model, textures, skeleton, animations, pose, index, current}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, skeleton, animations, pose, index, current}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +index, +current} = state
  draw.at(valid, camera, libm, core, model, textures, skeleton, animations, pose, index, current, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def path(+dir: String) -> String:
  dir ++ "resources/models/m3d/cesium_man.m3d"

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, skeleton, animations, J.Model.pose(skeleton), 0, 0.0}))

def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, False{}, model, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, frame, (count(items, 0) > 0 : U32) && playable(items), model, textures, skeleton, items)

# anims = LoadModelAnimations("resources/models/m3d/cesium_man.m3d", &animCount).
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

# After InitWindow(800, 450): LoadModel("resources/models/m3d/cesium_man.m3d"), its animations, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, path(dir)), r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - loading m3d", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
