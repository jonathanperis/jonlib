# raylib [models] example - animation blend custom, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_animation_blend_custom.c
# (zlib/libpng, Copyright (c) 2026 dmitrii-brand (@dmitrii-brand)); see
# LICENSES/raylib.txt.
#
# The greenman model under an orbital camera with two of its animations
# blended bone by bone by the example's own UpdateModelAnimationBones: the
# upper body takes the attack and the lower body the walk, or (SPACE) every
# bone half of each. The function writes model.boneMatrices only; the
# reference library is built with GPU skinning (mesh.animVertices is never
# allocated, so the function's CPU skinning loop skips every mesh) and its
# software renderer runs no shader: the model is drawn in its bind pose and
# the matrices are kept in the State's ModelPose (docs/MODELS.md). The
# skinning shader the native example loads is never compiled; the port does
# not read it. The perspective needs the libm profile's binary64 tan
# (docs/PERSPECTIVE.md), UpdateCamera its sinf/cosf (docs/SINCOSF.md) and
# QuaternionSlerp its acosf and sinf. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# first and second are animIndex0 and animIndex1 with their current frames;
# upper is upperBodyBlend.
type Play is Data:
  Play{skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, pose: J.ModelPose, first: U32, second: U32, frame_first: U32, frame_second: U32, upper: Bool}

# valid: everything loaded, an animation to play and no refusal so far.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, play: Play}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 4.0, 4.0}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

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

def bone.count(animation: J.ModelAnimation) -> U32:
  J.ModelAnimation{_, total, _, _} = animation
  total

def name(animation: J.ModelAnimation) -> String:
  J.ModelAnimation{text, _, _, _} = animation
  text

def pose.first(poses: +List<+List<J.Transform>>) -> +List<J.Transform>:
  match poses:
    case Con{pose, _}: pose
    case Nil{}: Nil{}

# anim.keyframePoses[frame].
def keyframe(animation: J.ModelAnimation, +frame: U32) -> +List<J.Transform>:
  J.ModelAnimation{_, _, _, +poses} = animation
  pose.first(List.drop(&2, +List<J.Transform>, poses, U32.to_nat(frame)))

def same(a: String, b: String) -> Bool:
  match a b:
    case SNil{} SNil{}: True{}
    case SCon{x, xs} SCon{y, ys}: U32.is_eq(Char.to_u32(x), Char.to_u32(y)) && same(xs, ys)
    case _ _: False{}

def starts(text: String, needle: String) -> Bool:
  match text needle:
    case _ SNil{}: True{}
    case SCon{t, ts} SCon{n, ns}: U32.is_eq(Char.to_u32(t), Char.to_u32(n)) && starts(ts, ns)
    case SNil{} SCon{_, _}: False{}

# strstr(text, needle) != NULL.
def contains(text: String, +needle: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+c, +rest}: starts(SCon{c, rest}, needle) || contains(rest, needle)

def any.same(names: List<String>, +text: String) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{item, rest}: same(text, item) || any.same(rest, text)

def any.inside(needles: List<String>, +text: String) -> Bool:
  match needles:
    case Nil{}: False{}
    case Con{item, rest}: contains(text, item) || any.inside(rest, text)

# IsUpperBodyBone: one of the listed names, or a name containing one of the listed parts.
def upper.bone(+text: String) -> Bool:
  any.same(["spine", "spine1", "spine2", "chest", "upperChest", "neck", "head", "shoulder", "shoulder_L", "shoulder_R", "upperArm", "upperArm_L", "upperArm_R", "lowerArm", "lowerArm_L", "lowerArm_R",
    "hand", "hand_L", "hand_R", "clavicle", "clavicle_L", "clavicle_R"], text) || any.inside(["spine", "chest", "neck", "head", "shoulder", "arm", "hand", "clavicle"], text)

# MatrixMultiply(MatrixMultiply(MatrixScale(scale), QuaternionToMatrix(rotation)), MatrixTranslate(translation)).
def matrix.of(translation: M.Vector3, rotation: M.Vector4, scale: M.Vector3) -> M.Matrix:
  M.Vector3{tx, ty, tz} = translation
  M.Vector3{sx, sy, sz} = scale
  M.Matrix.multiply(M.Matrix.multiply(M.Matrix.scale(sx, sy, sz), M.Quaternion.to_matrix(rotation)), M.Matrix.translate(tx, ty, tz))

def matrix(transform: J.Transform) -> M.Matrix:
  J.Transform{translation, rotation, scale} = transform
  matrix.of(translation, rotation, scale)

# model->boneMatrices[boneIndex] = MatrixMultiply(MatrixInvert(bindMatrix), blendedMatrix).
def bone.rotated(rotation: Maybe<M.Vector4>, +bind: J.Transform, +translation: M.Vector3, +scale: M.Vector3) -> Maybe<M.Matrix>:
  match rotation:
    case None{}: None{}
    case Some{r}: Some{M.Matrix.multiply(M.Matrix.invert(matrix(bind)), matrix.of(translation, r, scale))}

# The two animations' transforms blended: Vector3Lerp, QuaternionSlerp (the libm profile's), Vector3Lerp.
def bone.mixed(first: J.Transform, second: J.Transform, +bind: J.Transform, +factor: F32, +libm: M.Libm) -> Maybe<M.Matrix>:
  J.Transform{t1, +r1, s1} = first
  J.Transform{t2, +r2, s2} = second
  bone.rotated(M.Quaternion.slerp_for(libm, r1, r2, factor), bind, M.Vector3.lerp(t1, t2, factor), M.Vector3.lerp(s1, s2, factor))

# With upperBodyBlend an upper body bone takes the blend and the others 1 - blend.
def bone.matrix(bone: J.BoneInfo, +bind: J.Transform, +first: J.Transform, +second: J.Transform, +blend: F32, +upper: Bool, +libm: M.Libm) -> Maybe<M.Matrix>:
  J.BoneInfo{text, _} = bone
  bone.mixed(first, second, bind, Bool.pick(F32, upper, Bool.pick(F32, upper.bone(text), blend, (1.0 - blend : F32)), blend), libm)

def bones.joined(first: Maybe<M.Matrix>, rest: Maybe<+List<M.Matrix>>) -> Maybe<+List<M.Matrix>>:
  match first rest:
    case Some{a} Some{b}: Some{Con{a, b}}
    case _ _: None{}

# The bones the skeleton and both keyframe poses have.
def bones.blended(bones: +List<J.BoneInfo>, binds: +List<J.Transform>, first: +List<J.Transform>, second: +List<J.Transform>, +blend: F32, +upper: Bool, +libm: M.Libm) -> Maybe<+List<M.Matrix>>:
  match bones binds first second:
    case Con{+bone, rest} Con{+bind, more} Con{+a, others} Con{+b, last}: bones.joined(bone.matrix(bone, bind, a, b, blend, upper, libm), bones.blended(rest, more, others, last, blend, upper, libm))
    case _ _ _ _: Some{Nil{}}

# The new matrices, then the old ones of the bones past them.
def merged(fresh: +List<M.Matrix>, old: +List<M.Matrix>) -> +List<M.Matrix>:
  match fresh old:
    case Con{+m, rest} Con{_, more}: Con{m, merged(rest, more)}
    case Con{+m, rest} Nil{}: Con{m, merged(rest, Nil{})}
    case Nil{} Con{+m, more}: Con{m, more}
    case Nil{} Nil{}: Nil{}

def pose.merged(pose: J.ModelPose, +fresh: +List<M.Matrix>) -> Maybe<J.ModelPose>:
  J.ModelPose{+current, +matrices} = pose
  Some{J.ModelPose{current, merged(fresh, matrices)}}

def pose.with(fresh: Maybe<+List<M.Matrix>>, pose: J.ModelPose) -> Maybe<J.ModelPose>:
  match fresh:
    case None{}: None{}
    case Some{+matrices}: pose.merged(pose, matrices)

def skeleton.empty(bones: +List<J.BoneInfo>) -> Bool:
  match bones:
    case Nil{}: True{}
    case Con{_, _}: False{}

# UpdateModelAnimationBones(&model, &anim0, frame0, &anim1, frame1, blend, upperBodyBlend): nothing for an
# animation or a skeleton without bones. The frames come in range from the main loop.
def blended(+libm: M.Libm, skeleton: J.ModelSkeleton, +first: J.ModelAnimation, +frame_first: U32, +second: J.ModelAnimation, +frame_second: U32, +blend: F32, +upper: Bool, +pose: J.ModelPose) -> Maybe<J.ModelPose>:
  J.ModelSkeleton{+bones, +binds} = skeleton
  Bool.pick(Maybe<J.ModelPose>, U32.is_eq(bone.count(first), 0) || U32.is_eq(bone.count(second), 0) || skeleton.empty(bones), Some{pose},
    pose.with(bones.blended(bones, binds, keyframe(first, frame_first), keyframe(second, frame_second), blend, upper, libm), pose))

def update.posed(posed: Maybe<J.ModelPose>, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +previous: J.ModelPose,
    +first: U32, +second: U32, +frame_first: U32, +frame_second: U32, +upper: Bool) -> State:
  match posed:
    case None{}: State{False{}, Some{camera}, model, textures, Play{skeleton, animations, previous, first, second, frame_first, frame_second, upper}}
    case Some{+pose}: State{True{}, Some{camera}, model, textures, Play{skeleton, animations, pose, first, second, frame_first, frame_second, upper}}

# The frames advance by one, each modulo its keyframe count; the blend is 1 with upperBodyBlend, else 0.5
# (fminf and fmaxf leave both as they are).
def update.frames(+libm: M.Libm, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +first: U32,
    +second: U32, +frame_first: U32, +frame_second: U32, +upper: Bool) -> State:
  update.posed(blended(libm, skeleton, pick(animations, first), frame_first, pick(animations, second), frame_second, Bool.pick(F32, upper, 1.0, 0.5), upper, pose), camera, model, textures, skeleton,
    animations, pose, first, second, frame_first, frame_second, upper)

def update.keyed(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, play: Play) -> State:
  Play{+skeleton, +animations, +pose, +first, +second, +frame_first, +frame_second, +upper} = play
  update.frames(libm, camera, model, textures, skeleton, animations, pose, first, second, ((frame_first + 1) % keyframes(pick(animations, first)) : U32),
    ((frame_second + 1) % keyframes(pick(animations, second)) : U32), Bool.pick(Bool, J.Input.is_key_pressed(core, 32), Bool.not(upper), upper))

def update.moved(updated: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +play: Play) -> State:
  match updated:
    case None{}: State{False{}, None{}, model, textures, play}
    case Some{+c}: update.keyed(libm, core, c, model, textures, play)

# UpdateCamera(&camera, CAMERA_ORBITAL); SPACE toggles the mode; the next keyframes.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +play: Play) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), libm, core, model, textures, play)
    case _ None{}: State{False{}, None{}, model, textures, play}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, play}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +play} = state
  (core, update.live(valid, camera, libm, core, model, textures, play))

def texts(play: Play, frame: J.Frame) -> J.Frame:
  Play{_, +animations, _, +first, +second, _, _, +upper} = play
  f1 = J.Draw.text(frame, "ANIM 0: " ++ name(pick(animations, first)), 10.0, 10.0, 20.0, J.Color.GRAY())
  f2 = J.Draw.text(f1, "ANIM 1: " ++ name(pick(animations, second)), 10.0, 40.0, 20.0, J.Color.GRAY())
  J.Draw.text(f2, "[SPACE] Toggle blending mode: " ++ Bool.pick(String, upper, "Upper/Lower Body Blending", "Uniform Blending"), 10.0, 420.0, 20.0, J.Color.DARKGRAY())

# DrawGrid(10, 1.0f); EndMode3D(); the texts.
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +play: Play, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  (core, (State{True{}, Some{camera}, model, textures, play}, texts(play, J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)))))

# DrawModel(model, (0, 0, 0), 1.0f, WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +play: Play, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, model, play,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, play}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, play}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +play} = state
  draw.at(valid, camera, libm, core, model, textures, play, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the blend's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def path(+dir: String) -> String:
  dir ++ "resources/models/gltf/greenman.glb"

# Every animation has a keyframe (the frame counters are taken modulo the count).
def playable(items: +List<J.ModelAnimation>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{item, rest}: (keyframes(item) > 0 : U32) && playable(rest)

# animIndex0 = 2 (walk) and animIndex1 = 3 (attack), or 0 and 1 (0 with one animation) when the file has fewer; SetTargetFPS(60).
def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  +total = count(animations, 0)
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures,
    Play{skeleton, animations, J.Model.pose(skeleton), Bool.pick(U32, (total > 2 : U32), 2, 0), Bool.pick(U32, (total > 3 : U32), 3, Bool.pick(U32, (total > 1 : U32), 1, 0)), 0, 0, True{}}}))

def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, False{}, model, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, frame, (count(items, 0) > 0 : U32) && playable(items), model, textures, skeleton, items)

# anims = LoadModelAnimations("resources/models/gltf/greenman.glb", &animCount).
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

# After InitWindow(800, 450): LoadModel("resources/models/gltf/greenman.glb"), its animations, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, path(dir)), r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - animation blend custom", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
