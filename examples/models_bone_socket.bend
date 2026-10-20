# raylib [models] example - bone socket, ported to Jonlib.
# Adapted from raylib 6.2 examples/models/models_bone_socket.c (zlib/libpng,
# Copyright (c) 2024-2025 iP (@ipzaur)); see LICENSES/raylib.txt.
#
# The greenman model with a hat, a sword and a shield (four .glb files with
# embedded textures) drawn with DrawMesh: each piece of equipment follows
# its socket bone through the playing animation's keyframe pose
# (anim.keyframePoses[frame][bone] against skeleton.bindPose[bone]), under a
# third person camera. T/G switch the animation, F/H turn the character
# and 1, 2, 3 hide a piece. UpdateModelAnimation (called twice a frame
# natively, with the same arguments: the second call computes the same)
# fills the pose kept in the State and, raylib 6.2 skinning on the CPU (no
# shader of the software renderer takes the bones), the character's
# meshes' animVertices, which DrawMesh of meshes[0] draws. Only meshes[0]
# is kept, so it is skinned alone, in a model of its own (a mesh's
# animVertices depend on nothing else). The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md),
# UpdateCamera and QuaternionFromAxisAngle its sinf/cosf (docs/SINCOSF.md)
# and the animations' QuaternionSlerp its acosf and sinf. See docs/MODELS.md
# and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# model.meshes[0] and model.materials[1].
type Part is Data:
  Part{mesh: J.Mesh, material: J.Material}

# A piece of equipment, the bone it follows and that bone's bind rotation.
type Equip is Data:
  Equip{part: Part, bone: U32, bind: M.Vector4}

type Scene is Data:
  Scene{body: Part, hat: Equip, sword: Equip, shield: Equip}

# index is animIndex and current animCurrentFrame.
type Play is Data:
  Play{skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, pose: J.ModelPose, index: U32, current: U32}

type Shown is Data:
  Shown{hat: Bool, sword: Bool, shield: Bool}

# scene is None when a file did not load as the example needs it or a pose
# was refused; camera when UpdateCamera was.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, textures: List<J.Texture>, scene: +Maybe<Scene>, play: Play, shown: Shown, angle: U32}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{5.0, 5.0, 5.0}, M.Vector3{0.0, 2.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def count(items: +List<J.ModelAnimation>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def pick.first(items: +List<J.ModelAnimation>) -> J.ModelAnimation:
  match items:
    case Con{item, _}: item
    case Nil{}: J.ModelAnimation{"", 0, 0, Nil{}}

# modelAnimations[index].
def pick(items: +List<J.ModelAnimation>, +index: U32) -> J.ModelAnimation:
  pick.first(List.drop(&2, J.ModelAnimation, items, U32.to_nat(index)))

def keyframes(animation: J.ModelAnimation) -> U32:
  J.ModelAnimation{_, _, total, _} = animation
  total

def pose.first(poses: +List<+List<J.Transform>>) -> +List<J.Transform>:
  match poses:
    case Con{pose, _}: pose
    case Nil{}: Nil{}

# anim.keyframePoses[current].
def keyframe(animation: J.ModelAnimation, +current: U32) -> +List<J.Transform>:
  J.ModelAnimation{_, _, _, +poses} = animation
  pose.first(List.drop(&2, +List<J.Transform>, poses, U32.to_nat(current)))

def blank() -> J.Transform:
  J.Transform{M.Vector3{0.0, 0.0, 0.0}, M.Vector4{0.0, 0.0, 0.0, 1.0}, M.Vector3{1.0, 1.0, 1.0}}

def transform.first(items: +List<J.Transform>) -> J.Transform:
  match items:
    case Con{item, _}: item
    case Nil{}: blank()

# pose[bone] (setup checks every animation has the skeleton's bones).
def bone.at(pose: +List<J.Transform>, +bone: U32) -> J.Transform:
  transform.first(List.drop(&2, J.Transform, pose, U32.to_nat(bone)))

# Every animation has a keyframe and the skeleton's bone count.
def playable(items: +List<J.ModelAnimation>, +skeleton: J.ModelSkeleton) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: (keyframes(item) > 0 : U32) && J.Model.is_animation_valid(skeleton, item) && playable(rest, skeleton)

# angle = (angle + 1)%360 while F is down, else (360 + angle - 1)%360 while H is.
def turned(+core: J.Core, +angle: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_down(core, 70), ((angle + 1) % 360 : U32), Bool.pick(U32, J.Input.is_key_down(core, 72), ((360 + angle - 1) % 360 : U32), angle))

# T plays the next animation, else G the one before (total is above 0).
def switched(+core: J.Core, +index: U32, +total: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 84), ((index + 1) % total : U32), Bool.pick(U32, J.Input.is_key_pressed(core, 71), ((index + total - 1) % total : U32), index))

def flipped(pressed: Bool, +value: Bool) -> Bool:
  match pressed:
    case False{}: value
    case True{}: Bool.not(value)

# 1, 2 and 3 toggle the hat, the sword and the shield.
def toggled(+core: J.Core, shown: Shown) -> Shown:
  Shown{+hat, +sword, +shield} = shown
  Shown{flipped(J.Input.is_key_pressed(core, 49), hat), flipped(J.Input.is_key_pressed(core, 50), sword), flipped(J.Input.is_key_pressed(core, 51), shield)}

def body.mesh(meshes: +List<J.Mesh>, +fallback: J.Mesh) -> J.Mesh:
  match meshes:
    case Con{+mesh, _}: mesh
    case Nil{}: fallback

# The scene with the character's skinned meshes[0].
def skinned(+scene: Scene, +model: J.Model) -> Scene:
  Scene{+body, +hat, +sword, +shield} = scene
  Part{+mesh, +material} = body
  J.Model{_, +meshes, _, _} = model
  Scene{Part{body.mesh(meshes, mesh), material}, hat, sword, shield}

def update.posed(posed: Maybe<J.AnimatedModel>, +camera: J.Camera3D, textures: List<J.Texture>, +scene: Scene, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +previous: J.ModelPose, +index: U32,
    +current: U32, +shown: Shown, +angle: U32) -> State:
  match posed:
    case None{}: State{Some{camera}, textures, None{}, Play{skeleton, animations, previous, index, current}, shown, angle}
    case Some{J.AnimatedModel{+model, +pose}}: State{Some{camera}, textures, Some{skinned(scene, model)}, Play{skeleton, animations, pose, index, current}, shown, angle}

# The character's meshes[0] as a model.
def body.model(+scene: Scene) -> J.Model:
  Scene{+body, _, _, _} = scene
  Part{+mesh, _} = body
  J.Model.from_mesh(mesh)

# animCurrentFrame = (animCurrentFrame + 1)%anim.keyframeCount; UpdateModelAnimation(characterModel, anim, (float)animCurrentFrame).
def update.animated(+libm: M.Libm, +camera: J.Camera3D, textures: List<J.Texture>, +scene: Scene, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +index: U32, +current: U32,
    +shown: Shown, +angle: U32) -> State:
  update.posed(J.Model.update_animation_for(libm, body.model(scene), skeleton, pick(animations, index), U32.to_f32(current), pose), camera, textures, scene, skeleton, animations, pose, index, current, shown, angle)

def update.keyed(+libm: M.Libm, +core: J.Core, +camera: J.Camera3D, textures: List<J.Texture>, +scene: Scene, play: Play, +shown: Shown, +angle: U32, +index: U32) -> State:
  Play{+skeleton, +animations, +pose, _, +current} = play
  update.animated(libm, camera, textures, scene, skeleton, animations, pose, index, ((current + 1) % keyframes(pick(animations, index)) : U32), toggled(core, shown), turned(core, angle))

def animations.of(play: Play) -> +List<J.ModelAnimation>:
  Play{_, +animations, _, _, _} = play
  animations

def index.of(play: Play) -> U32:
  Play{_, _, _, index, _} = play
  index

def update.moved(updated: Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, textures: List<J.Texture>, +scene: Scene, +play: Play, +shown: Shown, +angle: U32) -> State:
  match updated:
    case None{}: State{None{}, textures, Some{scene}, play, shown, angle}
    case Some{+c}: update.keyed(libm, core, c, textures, scene, play, shown, angle, switched(core, index.of(play), count(animations.of(play), 0)))

# UpdateCamera(&camera, CAMERA_THIRD_PERSON), then the keys and the next keyframe.
def update.live(camera: +Maybe<J.Camera3D>, scene: +Maybe<Scene>, +libm: M.Libm, +core: J.Core, textures: List<J.Texture>, +play: Play, +shown: Shown, +angle: U32) -> State:
  match camera scene:
    case Some{+c} Some{+s}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_THIRD_PERSON()), libm, core, textures, s, play, shown, angle)
    case None{} Some{+s}: State{None{}, textures, Some{s}, play, shown, angle}
    case Some{+c} None{}: State{Some{c}, textures, None{}, play, shown, angle}
    case None{} None{}: State{None{}, textures, None{}, play, shown, angle}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, textures, +scene, +play, +shown, +angle} = state
  (core, update.live(camera, scene, libm, core, textures, play, shown, angle))

# DrawMesh(equipModel[i].meshes[0], equipModel[i].materials[1], matrixTransform) with
# rotate = QuaternionMultiply(transform->rotation, QuaternionInvert(bind rotation)) and
# matrixTransform = QuaternionToMatrix(rotate)*MatrixTranslate(transform->translation)*characterModel.transform.
def equip.drawn(bone: J.Transform, part: Part, +bind: M.Vector4, +transform: M.Matrix, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  J.Transform{translation, rotation, _} = bone
  M.Vector3{x, y, z} = translation
  Part{+mesh, +material} = part
  (frame, textures) = r
  J.Draw.mesh(frame, textures, mesh, material,
    M.Matrix.multiply(M.Matrix.multiply(M.Quaternion.to_matrix(M.Quaternion.multiply(rotation, M.Quaternion.invert(bind))), M.Matrix.translate(x, y, z)), transform))

# if (!showEquip[i]) continue.
def equip(shown: Bool, +item: Equip, +pose: +List<J.Transform>, +transform: M.Matrix, r: J.Frame & List<J.Texture>) -> J.Frame & List<J.Texture>:
  match shown:
    case False{}: r
    case True{}:
      Equip{+part, +bone, +bind} = item
      equip.drawn(bone.at(pose, bone), part, bind, transform, r)

def texts(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(frame, "Use the T/G to switch animation", 10.0, 10.0, 20.0, J.Color.GRAY())
  f2 = J.Draw.text(f1, "Use the F/H to rotate character left/right", 10.0, 35.0, 20.0, J.Color.GRAY())
  J.Draw.text(f2, "Use the 1,2,3 to toggle shown of hat, sword and shield", 10.0, 60.0, 20.0, J.Color.GRAY())

def draw.done(+core: J.Core, +camera: J.Camera3D, +scene: Scene, +play: Play, +shown: Shown, +angle: U32, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  (core, (State{Some{camera}, textures, Some{scene}, play, shown, angle}, texts(J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0)))))

def play.keyframe(play: Play) -> +List<J.Transform>:
  Play{_, +animations, _, +index, +current} = play
  keyframe(pick(animations, index), current)

# The character's mesh under characterModel.transform, then the equipment shown.
def draw.scene(+core: J.Core, +camera: J.Camera3D, +scene: Scene, +play: Play, +shown: Shown, +angle: U32, +transform: M.Matrix, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (State & J.Frame):
  Scene{+body, +hat, +sword, +shield} = scene
  Part{+mesh, +material} = body
  Shown{+show_hat, +show_sword, +show_shield} = shown
  +pose = play.keyframe(play)
  draw.done(core, camera, scene, play, shown, angle,
    equip(show_shield, shield, pose, transform, equip(show_sword, sword, pose, transform, equip(show_hat, hat, pose, transform, J.Draw.mesh(frame, textures, mesh, material, transform)))))

# characterModel.transform = QuaternionToMatrix(QuaternionFromAxisAngle((0, 1, 0), angle*DEG2RAD))*MatrixTranslate(0, 0, 0).
def turn(+libm: M.Libm, +angle: U32) -> M.Matrix:
  M.Matrix.multiply(M.Quaternion.to_matrix(M.Quaternion.from_axis_angle_for(libm, M.Vector3{0.0, 1.0, 0.0}, (U32.to_f32(angle) * M.Math.DEG2RAD() : F32))), M.Matrix.translate(0.0, 0.0, 0.0))

def draw.at(camera: +Maybe<J.Camera3D>, scene: +Maybe<Scene>, +libm: M.Libm, +core: J.Core, textures: List<J.Texture>, +play: Play, +shown: Shown, +angle: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match camera scene:
    case Some{+c} Some{+s}: draw.scene(core, c, s, play, shown, angle, turn(libm, angle), J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures)
    case None{} Some{+s}: (core, (State{None{}, textures, Some{s}, play, shown, angle}, J.Frame.refuse(frame)))
    case Some{+c} None{}: (core, (State{Some{c}, textures, None{}, play, shown, angle}, J.Frame.refuse(frame)))
    case None{} None{}: (core, (State{None{}, textures, None{}, play, shown, angle}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, textures, +scene, +play, +shown, +angle} = state
  draw.at(camera, scene, libm, core, textures, play, shown, angle, frame)

# The main loop's body; libm is the profile of UpdateCamera's and the turn's sinf/cosf, the perspective tan and the pose's QuaternionSlerp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# The models loaded so far, the last one first, and their textures.
type Loaded is Type:
  Loaded{valid: Bool, parts: +List<Part>, textures: List<J.Texture>}

def part.of(meshes: +List<J.Mesh>, materials: +List<J.Material>) -> Maybe<Part>:
  match meshes materials:
    case Con{+mesh, _} Con{_, Con{+material, _}}: Some{Part{mesh, material}}
    case _ _: None{}

def load.part(part: Maybe<Part>, +valid: Bool, +parts: +List<Part>, textures: List<J.Texture>) -> Loaded:
  match part:
    case None{}: Loaded{False{}, parts, textures}
    case Some{+p}: Loaded{valid, Con{p, parts}, textures}

def load.added(loaded: J.LoadedModel, acc: Loaded) -> Loaded:
  J.LoadedModel{+model, own} = loaded
  J.Model{_, +meshes, +materials, _} = model
  Loaded{+valid, +parts, textures} = acc
  load.part(part.of(meshes, materials), valid, parts, List.append(&1, J.Texture, textures, own))

def load.failed(acc: Loaded) -> Loaded:
  Loaded{_, +parts, textures} = acc
  Loaded{False{}, parts, textures}

def load.took(r: J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, acc: Loaded) -> J.Frame & Loaded:
  (frame, result) = r
  match result:
    case Fail{_}: (frame, load.failed(acc))
    case Done{loaded}: (frame, load.added(loaded, acc))

# LoadModel(path).
def load.one(+path: String, state: J.Frame & Loaded) -> IO(J.Frame & Loaded):
  (frame, acc) = state
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, J.LoadedModel>, J.Frame & Loaded, J.Model.load(frame, path), r => IO.pure(J.Frame & Loaded, load.took(r, acc)))

def same(a: String, b: String) -> Bool:
  match a b:
    case SNil{} SNil{}: True{}
    case SCon{x, xs} SCon{y, ys}: U32.is_eq(Char.to_u32(x), Char.to_u32(y)) && same(xs, ys)
    case _ _: False{}

# The last bone with that name (the native loop keeps the last match): 4294967295 for none.
def socket(bones: +List<J.BoneInfo>, +wanted: String, +index: U32, +found: U32) -> U32:
  match bones:
    case Nil{}: found
    case Con{J.BoneInfo{name, _}, rest}: socket(rest, wanted, (index + 1 : U32), Bool.pick(U32, same(name, wanted), index, found))

def rotation.of(transform: J.Transform) -> M.Vector4:
  J.Transform{_, rotation, _} = transform
  rotation

def equipped(+part: Part, +bone: U32, +binds: +List<J.Transform>) -> Equip:
  Equip{part, bone, rotation.of(bone.at(binds, bone))}

def paused(+skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> Play:
  Play{skeleton, animations, J.Model.pose(skeleton), 0, 0}

def all.shown() -> Shown:
  Shown{True{}, True{}, True{}}

def setup.failed(+core: J.Core, frame: J.Frame, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (core, (frame, State{None{}, textures, None{}, paused(J.ModelSkeleton{Nil{}, Nil{}}, Nil{}), all.shown(), 0}))

# The socket bones by name; DisableCursor(); SetTargetFPS(60).
def setup.scene(valid: Bool, +core: J.Core, frame: J.Frame, textures: List<J.Texture>, +body: Part, +hat: Part, +sword: Part, +shield: Part, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>,
    +bone_hat: U32, +bone_sword: U32, +bone_shield: U32) -> J.Core & (J.Frame & State):
  match valid:
    case False{}: setup.failed(core, frame, textures)
    case True{}:
      J.ModelSkeleton{_, +binds} = skeleton
      (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Some{start()}, textures,
        Some{Scene{body, equipped(hat, bone_hat, binds), equipped(sword, bone_sword, binds), equipped(shield, bone_shield, binds)}}, paused(skeleton, animations), all.shown(), 0}))

def bones.of(skeleton: J.ModelSkeleton) -> +List<J.BoneInfo>:
  J.ModelSkeleton{+bones, _} = skeleton
  bones

def setup.parts(parts: +List<Part>, +valid: Bool, +core: J.Core, frame: J.Frame, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  match parts:
    case Con{+shield, Con{+sword, Con{+hat, Con{+body, Nil{}}}}}:
      +bone_hat = socket(bones.of(skeleton), "socket_hat", 0, 4294967295)
      +bone_sword = socket(bones.of(skeleton), "socket_hand_R", 0, 4294967295)
      +bone_shield = socket(bones.of(skeleton), "socket_hand_L", 0, 4294967295)
      setup.scene(valid && (count(animations, 0) > 0 : U32) && playable(animations, skeleton) && U32.is_ne(bone_hat, 4294967295) && U32.is_ne(bone_sword, 4294967295) && U32.is_ne(bone_shield, 4294967295),
        core, frame, textures, body, hat, sword, shield, skeleton, animations, bone_hat, bone_sword, bone_shield)
    case _: setup.failed(core, frame, textures)

def textures.of(loaded: Loaded) -> List<J.Texture>:
  Loaded{_, _, textures} = loaded
  textures

def setup.loaded(loaded: Loaded, +core: J.Core, frame: J.Frame, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  Loaded{+valid, +parts, textures} = loaded
  setup.parts(parts, valid, core, frame, textures, skeleton, animations)

def setup.animations(result: Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, +core: J.Core, frame: J.Frame, loaded: Loaded, +skeleton: J.ModelSkeleton) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.failed(core, frame, textures.of(loaded))
    case Done{+items}: setup.loaded(loaded, core, frame, skeleton, items)

# modelAnimations = LoadModelAnimations("resources/models/gltf/greenman.glb", &animsCount).
def setup.skeleton(result: Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, +libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame, loaded: Loaded) -> IO(J.Core & (J.Frame & State)):
  match result:
    case Fail{_}: IO.pure(J.Core & (J.Frame & State), setup.failed(core, frame, textures.of(loaded)))
    case Done{+skeleton}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<J.ModelAnimation>>, J.Core & (J.Frame & State), J.Model.load_animations_for(libm, dir ++ "resources/models/gltf/greenman.glb"),
        a => IO.pure(J.Core & (J.Frame & State), setup.animations(a, core, frame, loaded, skeleton)))

# The character's skeleton, which Jonlib loads beside the model.
def setup.models(+libm: M.Libm, +dir: String, +core: J.Core, state: J.Frame & Loaded) -> IO(J.Core & (J.Frame & State)):
  (frame, loaded) = state
  IO.bind(Result<&1, &1, J.Surface.IOError, J.ModelSkeleton>, J.Core & (J.Frame & State), J.Model.load_skeleton(dir ++ "resources/models/gltf/greenman.glb"),
    s => setup.skeleton(s, libm, dir, core, frame, loaded))

def setup.shield(+libm: M.Libm, +dir: String, +core: J.Core, state: J.Frame & Loaded) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Loaded, J.Core & (J.Frame & State), load.one(dir ++ "resources/models/gltf/greenman_shield.glb", state), s => setup.models(libm, dir, core, s))

def setup.sword(+libm: M.Libm, +dir: String, +core: J.Core, state: J.Frame & Loaded) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Loaded, J.Core & (J.Frame & State), load.one(dir ++ "resources/models/gltf/greenman_sword.glb", state), s => setup.shield(libm, dir, core, s))

def setup.hat(+libm: M.Libm, +dir: String, +core: J.Core, state: J.Frame & Loaded) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Loaded, J.Core & (J.Frame & State), load.one(dir ++ "resources/models/gltf/greenman_hat.glb", state), s => setup.sword(libm, dir, core, s))

# After InitWindow(800, 450): the character, the hat, the sword and the shield, then the character's animations.
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Loaded, J.Core & (J.Frame & State), load.one(dir ++ "resources/models/gltf/greenman.glb", (frame, Loaded{True{}, Nil{}, Nil{}})), s => setup.hat(libm, dir, core, s))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - bone socket", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
