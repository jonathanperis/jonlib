# raylib [models] example - loading iqm, ported to Jonlib.
# Adapted from raylib 6.2 examples/models/models_loading_iqm.c (zlib/libpng,
# Copyright (c) 2019-2025 Culacant (@culacant) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# The guy model (LoadModel of an .iqm file: one mesh of 224 vertices in
# raylib 6.2's resources, 240 in 6.0's, and a skeleton of 14 joints) with
# its texture set as the material's diffuse map (the file's own material
# names no file, so LoadIQM leaves a texture of zeros there first), under an
# orbital camera, and an animation of guyanim.iqm (LoadModelAnimations:
# "jump" and "dance", 61 keyframes each) advanced animSpeed keyframes a frame
# (UpdateModelAnimation), back to keyframe 0 after the last. raylib 6.2's
# keys: RIGHT and LEFT choose the animation (from keyframe 0), UP and DOWN
# change the speed by 0.1 within fminf(5, ..) and fmaxf(0, ..). The frame
# counter is a float and reaches the keyframe count before it is reset, as
# in the example. raylib 6.2 skins the mesh on the CPU (no shader of the
# software renderer takes the bones) and DrawModelEx draws the skinned
# vertices; the pose is the State's ModelPose beside the model
# (docs/MODELS.md). The perspective needs
# the libm profile's binary64 tan (docs/PERSPECTIVE.md), UpdateCamera and
# DrawModelEx's rotation its sinf/cosf (docs/SINCOSF.md) and the pose's
# QuaternionSlerp its acosf and sinf. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: everything loaded, an animation to play and no refusal so far.
# current is animCurrentFrame, index animIndex and speed animSpeed.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, model: J.Model, textures: List<J.Texture>, skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, pose: J.ModelPose, current: F32,
    index: U32, speed: F32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{10.0, 10.0, 10.0}, M.Vector3{0.0, 4.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def count(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def first(items: +List<J.ModelAnimation>) -> J.ModelAnimation:
  match items:
    case Con{item, _}: item
    case Nil{}: J.ModelAnimation{"", 0, 0, Nil{}}

# anims[animIndex].
def chosen(items: +List<J.ModelAnimation>, +index: U32) -> J.ModelAnimation:
  first(List.drop(&2, J.ModelAnimation, items, U32.to_nat(index)))

def keyframes(animation: J.ModelAnimation) -> U32:
  J.ModelAnimation{_, _, total, _} = animation
  total

def name(animation: J.ModelAnimation) -> String:
  J.ModelAnimation{text, _, _, _} = animation
  text

# if (animCurrentFrame >= anims[animIndex].keyframeCount) animCurrentFrame = 0.
def wrapped(+frame: F32, +total: U32) -> F32:
  Bool.pick(F32, (frame >= U32.to_f32(total) : F32), 0.0, frame)

def update.posed(posed: Maybe<J.AnimatedModel>, +camera: J.Camera3D, +previous_model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +previous: J.ModelPose,
    +frame: F32, +index: U32, +speed: F32) -> State:
  match posed:
    case None{}: State{False{}, Some{camera}, previous_model, textures, skeleton, animations, previous, frame, index, speed}
    case Some{J.AnimatedModel{+model, +pose}}: State{True{}, Some{camera}, model, textures, skeleton, animations, pose, wrapped(frame, keyframes(chosen(animations, index))), index, speed}

# animCurrentFrame += animSpeed; UpdateModelAnimation(model, anims[animIndex], animCurrentFrame).
def update.moved(updated: Maybe<J.Camera3D>, +libm: M.Libm, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +current: F32,
    +index: U32, +speed: F32) -> State:
  match updated:
    case None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, current, index, speed}
    case Some{+c}: update.posed(J.Model.update_animation_for(libm, model, skeleton, chosen(animations, index), (current + speed : F32), pose), c, model, textures, skeleton, animations, pose,
      (current + speed : F32), index, speed)

# RIGHT: the next animation (after the last, the first), LEFT the previous
# (before the first, the last), either from frame 0; UP and DOWN change the
# speed by 0.1 within 0..5.
def update.keyed(updated: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +current: F32, +index: U32, +speed: F32) -> State:
  +last = (count(animations, 0) - 1 : U32)
  +right = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +left = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  +i1 = Bool.pick(U32, right, Bool.pick(U32, U32.is_eq(index, last), 0, (index + 1 : U32)), index)
  +i2 = Bool.pick(U32, left, Bool.pick(U32, U32.is_eq(i1, 0), last, (i1 - 1 : U32)), i1)
  +s1 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()), F32.min(5.0, (speed + 0.1 : F32)), speed)
  +s2 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()), F32.max(0.0, (s1 - 0.1 : F32)), s1)
  update.moved(updated, libm, model, textures, skeleton, animations, pose, Bool.pick(F32, right || left, 0.0, current), i2, s2)

# UpdateCamera(&camera, CAMERA_ORBITAL), the keys, then the next frame.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +current: F32, +index: U32, +speed: F32) -> State:
  match valid camera:
    case True{} Some{+c}: update.keyed(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), libm, core, model, textures, skeleton, animations, pose, current, index, speed)
    case _ None{}: State{False{}, None{}, model, textures, skeleton, animations, pose, current, index, speed}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, skeleton, animations, pose, current, index, speed}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +current, +index, +speed} = state
  (core, update.live(valid, camera, libm, core, model, textures, skeleton, animations, pose, current, index, speed))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.MAROON())

# DrawGrid(10, 1.0f); EndMode3D(); the animation's name, the speed, the help lines and the credit.
def draw.model(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +current: F32, +index: U32, +speed: F32,
    r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))
  f2 = label(J.Text.format("Current animation: %s", [J.TextString{name(chosen(animations, index))}]), 10.0, f1)
  f3 = label(J.Text.format("Animation speed: %.2f", [J.TextFloat{speed}]), 40.0, f2)
  f4 = J.Draw.text(f3, "Use left and right arrow keys to change current animation", 10.0, (450.0 - 34.0 : F32), 10.0, J.Color.BLACK())
  f5 = J.Draw.text(f4, "Use up and down arrow keys to change animation speed", 10.0, (450.0 - 20.0 : F32), 10.0, J.Color.BLACK())
  (core, (State{True{}, Some{camera}, model, textures, skeleton, animations, pose, current, index, speed}, J.Draw.text(f5, "(c) Guy IQM 3D model by @culacant", 600.0, 430.0, 10.0, J.Color.GRAY())))

# DrawModelEx(model, (0, 0, 0), (1, 0, 0), -90.0f, (1, 1, 1), WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +pose: J.ModelPose, +current: F32, +index: U32, +speed: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.model(core, c, model, skeleton, animations, pose, current, index, speed,
      J.Draw.model_ex_for(libm, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), M.Vector3{1.0, 0.0, 0.0}, F32.neg(90.0), M.Vector3{1.0, 1.0, 1.0},
        J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, skeleton, animations, pose, current, index, speed}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, skeleton, animations, pose, current, index, speed}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +skeleton, +animations, +pose, +current, +index, +speed} = state
  draw.at(valid, camera, libm, core, model, textures, skeleton, animations, pose, current, index, speed, frame)

# The main loop's body; libm is the profile of UpdateCamera's and DrawModelEx's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, skeleton, animations, J.Model.pose(skeleton), 0.0, 0, 1.0}))

# An animation to play: anims[0] with a keyframe.
def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.done(core, frame, False{}, model, textures, skeleton, Nil{})
    case Done{+items}: setup.done(core, frame, valid && (count(items, 0) > 0 : U32) && (keyframes(first(items)) > 0 : U32), model, textures, skeleton, items)

# anims = LoadModelAnimations("resources/models/iqm/guyanim.iqm", &animCount).
def setup.skeleton(result: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, model, textures, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, J.Core & (J.Frame & State), J.Model.load_animations_for(libm, dir ++ "resources/models/iqm/guyanim.iqm"),
        a => IO.pure(J.Core & (J.Frame & State), setup.animations(a, core, frame, valid, model, textures, skeleton)))

# model.materials[0].maps[MATERIAL_MAP_DIFFUSE].texture = texture.
def textured.material(+info: J.TextureInfo, materials: +List<J.Material>) -> +List<J.Material>:
  match materials:
    case Con{+m, rest}: Con{Maybe.default(&1, J.Material, J.Material.set_texture(m, 0, info), m), rest}
    case Nil{}: Nil{}

def textured(+model: J.Model, +info: J.TextureInfo) -> J.Model:
  J.Model{+transform, +meshes, +materials, +ids} = model
  J.Model{transform, meshes, textured.material(info, materials), ids}

def setup.textured.info(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, +model: J.Model, textures: List<J.Texture>, r: J.Texture & J.TextureInfo) -> IO(J.Core & (J.Frame & State)):
  (texture, +info) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, J.Core & (J.Frame & State), J.Model.load_skeleton(dir ++ "resources/models/iqm/guy.iqm"),
    s => setup.skeleton(s, libm, dir, core, frame, True{}, textured(model, info), Con{texture, textures}))

# SetMaterialTexture(&model.materials[0], MATERIAL_MAP_DIFFUSE, texture); the model's skeleton, which Jonlib loads beside the model.
def setup.texture(r: J.Frame & Maybe<J.Texture>, +libm: M.Libm, +dir: String, +core: J.Core, +model: J.Model, textures: List<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  match r:
    case Tuple{frame, None{}}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, model, textures, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Tuple{frame, Some{t}}: setup.textured.info(libm, dir, core, frame, model, textures, J.Texture.info(t))

# texture = LoadTexture("resources/models/iqm/guytex.png").
def setup.model(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: J.LoadedModel) -> IO(J.Core & (J.Frame & State)):
  J.LoadedModel{+model, textures} = loaded
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/models/iqm/guytex.png"), r => setup.texture(r, libm, dir, core, model, textures))

def setup.loaded(+libm: M.Libm, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, False{}, J.Model.empty(), Nil{}, J.ModelSkeleton{Nil{}, Nil{}}, Nil{}))
    case Done{loaded}: setup.model(libm, dir, core, frame, loaded)

# After InitWindow(800, 450): LoadModel("resources/models/iqm/guy.iqm"), its texture, the animations, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Core & (J.Frame & State), J.Model.load(frame, dir ++ "resources/models/iqm/guy.iqm"), r => setup.loaded(libm, dir, core, r))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - loading iqm", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
