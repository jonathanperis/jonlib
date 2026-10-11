# raylib [models] example - animation blending, ported to Jonlib.
# Adapted from raylib 6.0 examples/models/models_animation_blending.c
# (zlib/libpng, Copyright (c) 2024-2026 Kirandeep (@Kirandeep-Singh-Khehra)
# and Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The robot model under an orbital camera playing one of two animations;
# SPACE blends into the other one over two seconds (UpdateModelAnimationEx)
# and P pauses. raygui controls (Jongui): a dropdown box and a speed slider
# for each animation, a progress bar for the blend (filled from the right
# on the way back) and one with a tick a keyframe for each animation. The
# reference library is built with GPU skinning and its software renderer
# runs no shader, so the model is drawn in its bind pose; the updates fill
# the State's ModelPose (docs/MODELS.md). The skinning shader the native
# example loads is never compiled; the port does not read it. The
# perspective needs the libm profile's binary64 tan (docs/PERSPECTIVE.md),
# UpdateCamera its sinf/cosf (docs/SINCOSF.md) and QuaternionSlerp its acosf
# and sinf. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# An animation's index, current frame, frame speed and dropdown edit mode.
type Track is Data:
  Track{index: U32, frame: F32, speed: F32, edit: Bool}

# currentAnimPlaying, nextAnimToPlay, animTransition, animBlendFactor,
# animBlendTimeCounter and animBlendProgress.
type Blend is Data:
  Blend{playing: U32, next: U32, transition: Bool, factor: F32, counter: F32, progress: F32}

type Mix is Data:
  Mix{first: Track, second: Track, blend: Blend}

# names is TextJoin(animNames, animCount, ";").
type Play is Data:
  Play{skeleton: J.ModelSkeleton, animations: +List<J.ModelAnimation>, names: String, pose: J.ModelPose, mix: Mix, paused: Bool}

# valid: everything loaded, both animations there and no refusal so far.
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

def track.index(track: Track) -> U32:
  Track{index, _, _, _} = track
  index

def track.frame(track: Track) -> F32:
  Track{_, frame, _, _} = track
  frame

def track.speed(track: Track) -> F32:
  Track{_, _, speed, _} = track
  speed

def track.edit(track: Track) -> Bool:
  Track{_, _, _, edit} = track
  edit

# animCurrentFrame += animFrameSpeed, back to 0 at the keyframe count.
def stepped(track: Track, +animations: +List<J.ModelAnimation>) -> Track:
  Track{+index, +frame, +speed, +edit} = track
  Track{index, Bool.pick(F32, ((frame + speed : F32) >= U32.to_f32(keyframes(pick(animations, index))) : F32), 0.0, (frame + speed : F32)), speed, edit}

def rewound(track: Track) -> Track:
  Track{index, _, speed, edit} = track
  Track{index, 0.0, speed, edit}

# SPACE outside a transition: the other animation starts from its first keyframe and the blend from 0.
def mix.started(go: Bool, +mix: Mix) -> Mix:
  match go:
    case False{}: mix
    case True{}:
      Mix{+first, +second, blend} = mix
      Blend{+playing, _, _, _, _, +progress} = blend
      Mix{Bool.pick(Track, U32.is_eq(playing, 0), first, rewound(first)), Bool.pick(Track, U32.is_eq(playing, 0), rewound(second), second),
        Blend{playing, Bool.pick(U32, U32.is_eq(playing, 0), 1, 0), True{}, 0.0, 0.0, progress}}

type Advance is Data:
  Advance{mix: Mix, pose: J.ModelPose}

def mix.posed(posed: Maybe<J.ModelPose>, +mix: Mix) -> Maybe<Advance>:
  match posed:
    case None{}: None{}
    case Some{+pose}: Some{Advance{mix, pose}}

# UpdateModelAnimationEx(model, anims[from], its frame, anims[to], its frame, animBlendFactor).
def blended(+libm: M.Libm, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +from: Track, +to: Track, +factor: F32, +pose: J.ModelPose) -> Maybe<J.ModelPose>:
  J.Model.update_animation_ex_for(libm, skeleton, pick(animations, track.index(from)), track.frame(from), pick(animations, track.index(to)), track.frame(to), factor, pose)

# UpdateModelAnimation(model, anims[index], its frame).
def played(+libm: M.Libm, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +track: Track, +pose: J.ModelPose) -> Maybe<J.ModelPose>:
  J.Model.update_animation_for(libm, skeleton, pick(animations, track.index(track)), track.frame(track), pose)

# In a transition both animations advance and blend by animBlendTimeCounter/animBlendTime (2 seconds), the
# counter grows by GetFrameTime(), and past a factor of 1 the next animation becomes the one playing.
# Otherwise the one playing advances alone.
def mix.moved(transition: Bool, +libm: M.Libm, +dt: F32, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, +first: Track, +second: Track, +playing: U32, +next: U32,
    +factor: F32, +counter: F32, +progress: F32) -> Maybe<Advance>:
  match transition:
    case True{}:
      +a = stepped(first, animations)
      +b = stepped(second, animations)
      +now = (counter / 2.0 : F32)
      +done = (now > 1.0 : F32)
      mix.posed(Bool.pick(Maybe<J.ModelPose>, U32.is_eq(next, 1), blended(libm, skeleton, animations, a, b, now, pose), blended(libm, skeleton, animations, b, a, now, pose)),
        Mix{Bool.pick(Track, done && U32.is_eq(playing, 0), rewound(a), a), Bool.pick(Track, done && U32.is_eq(playing, 1), rewound(b), b),
          Blend{Bool.pick(U32, done, next, playing), next, Bool.not(done), Bool.pick(F32, done, 0.0, now), Bool.pick(F32, done, 0.0, (counter + dt : F32)), now}})
    case False{}:
      +a = stepped(first, animations)
      +b = stepped(second, animations)
      mix.posed(Bool.pick(Maybe<J.ModelPose>, U32.is_eq(playing, 0), played(libm, skeleton, animations, a, pose), Bool.pick(Maybe<J.ModelPose>, U32.is_eq(playing, 1), played(libm, skeleton, animations, b, pose), Some{pose})),
        Mix{Bool.pick(Track, U32.is_eq(playing, 0), a, first), Bool.pick(Track, U32.is_eq(playing, 1), b, second), Blend{playing, next, False{}, factor, counter, progress}})

def mix.advanced(+libm: M.Libm, +dt: F32, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +pose: J.ModelPose, mix: Mix) -> Maybe<Advance>:
  Mix{+first, +second, blend} = mix
  Blend{+playing, +next, +transition, +factor, +counter, +progress} = blend
  mix.moved(transition, libm, dt, skeleton, animations, pose, first, second, playing, next, factor, counter, progress)

def blend.transition(blend: Blend) -> Bool:
  Blend{_, _, transition, _, _, _} = blend
  transition

def mix.transition(mix: Mix) -> Bool:
  Mix{_, _, blend} = mix
  blend.transition(blend)

def update.stepped(step: Maybe<Advance>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String) -> Maybe<Play>:
  match step:
    case None{}: None{}
    case Some{Advance{+mix, +pose}}: Some{Play{skeleton, animations, names, pose, mix, False{}}}

def update.run(halted: Bool, +libm: M.Libm, +core: J.Core, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>, +names: String, +pose: J.ModelPose, +mix: Mix) -> Maybe<Play>:
  match halted:
    case True{}: Some{Play{skeleton, animations, names, pose, mix, True{}}}
    case False{}: update.stepped(mix.advanced(libm, J.Core.get_frame_time(core), skeleton, animations, pose, mix.started(J.Input.is_key_pressed(core, 32) && Bool.not(mix.transition(mix)), mix)),
      skeleton, animations, names)

# P pauses; None when a pose is refused.
def update.play(+libm: M.Libm, +core: J.Core, play: Play) -> Maybe<Play>:
  Play{+skeleton, +animations, +names, +pose, +mix, +paused} = play
  update.run(Bool.pick(Bool, J.Input.is_key_pressed(core, 80), Bool.not(paused), paused), libm, core, skeleton, animations, names, pose, mix)

def update.moved(updated: Maybe<J.Camera3D>, played: Maybe<Play>, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +old: Play) -> State:
  match updated played:
    case Some{+c} Some{+p}: State{True{}, Some{c}, model, textures, gui, p}
    case Some{+c} None{}: State{False{}, Some{c}, model, textures, gui, old}
    case None{} _: State{False{}, None{}, model, textures, gui, old}

# UpdateCamera(&camera, CAMERA_ORBITAL), then the animations.
def update.live(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> State:
  match valid camera:
    case True{} Some{+c}: update.moved(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()), update.play(libm, core, play), model, textures, gui, play)
    case _ None{}: State{False{}, None{}, model, textures, gui, play}
    case False{} Some{+c}: State{False{}, Some{c}, model, textures, gui, play}

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, +model, textures, +gui, +play} = state
  (core, update.live(valid, camera, libm, core, model, textures, gui, play))

def play.mix(play: Play) -> Mix:
  Play{_, _, _, _, mix, _} = play
  mix

def mix.first(mix: Mix) -> Track:
  Mix{first, _, _} = mix
  first

def mix.second(mix: Mix) -> Track:
  Mix{_, second, _} = mix
  second

def mix.blend(mix: Mix) -> Blend:
  Mix{_, _, blend} = mix
  blend

def play.first(play: Play) -> Track:
  mix.first(play.mix(play))

def play.second(play: Play) -> Track:
  mix.second(play.mix(play))

def play.blend(play: Play) -> Blend:
  mix.blend(play.mix(play))

def play.names(play: Play) -> String:
  Play{_, _, names, _, _, _} = play
  names

def play.animations(play: Play) -> +List<J.ModelAnimation>:
  Play{_, +animations, _, _, _, _} = play
  animations

def blend.next(blend: Blend) -> U32:
  Blend{_, next, _, _, _, _} = blend
  next

def blend.progress(blend: Blend) -> F32:
  Blend{_, _, _, _, _, progress} = blend
  progress

def with.mix(play: Play, +mix: Mix) -> Play:
  Play{skeleton, animations, names, pose, _, paused} = play
  Play{skeleton, animations, names, pose, mix, paused}

def with.speed(track: Track, +speed: F32) -> Track:
  Track{index, frame, _, edit} = track
  Track{index, frame, speed, edit}

# The dropdown's result: the active animation, and the edit mode flipped when raygui answers true.
def with.picked(track: Track, +index: U32, +toggled: Bool) -> Track:
  Track{_, frame, speed, +edit} = track
  Track{index, frame, speed, Bool.pick(Bool, toggled, Bool.not(edit), edit)}

def with.first(+play: Play, +first: Track) -> Play:
  with.mix(play, Mix{first, play.second(play), play.blend(play)})

def with.second(+play: Play, +second: Track) -> Play:
  with.mix(play, Mix{play.first(play), second, play.blend(play)})

def blend.shown(blend: Blend, +progress: F32) -> Blend:
  Blend{playing, next, transition, factor, counter, _} = blend
  Blend{playing, next, transition, factor, counter, progress}

def with.progress(+play: Play, +progress: F32) -> Play:
  with.mix(play, Mix{play.first(play), play.second(play), blend.shown(play.blend(play), progress)})

# The keyframe count of a track's animation.
def total(+play: Play, track: Track) -> U32:
  keyframes(pick(play.animations(play), track.index(track)))

# The slider's Gui (a drag is its state) and value.
type Slid is Data:
  Slid{gui: G.Gui, speed: F32}

def slid.value(pair: F32 & Bool) -> F32:
  (value, _) = pair
  value

def slid(rest: G.Gui & (F32 & Bool)) -> Slid:
  (gui, pair) = rest
  Slid{gui, slid.value(pair)}

# DrawRectangle(60 + (int)(((float)(GetScreenWidth() - 180)/(float)keyframeCount)*(float)i), y, 1, 20, BLUE) for every keyframe.
def ticks(n: Nat, +i: U32, +total: U32, +y: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: ticks(p, (i + 1 : U32), total, y, J.Draw.rectangle(frame, (60.0 + F32.trunc(((620.0 / U32.to_f32(total)) * U32.to_f32(i) : F32)) : F32), y, 1.0, 20.0, J.Color.BLUE()))

def refused(+core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (State{False{}, Some{camera}, model, textures, gui, play}, J.Frame.refuse(frame)))

def draw.second.bar(r: J.Frame & F32, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (frame, _) = r
  (core, (State{True{}, Some{camera}, model, textures, gui, play}, ticks(U32.to_nat(total(play, play.second(play))), 0, total(play, play.second(play)), 420.0, frame)))

# GuiProgressBar((60, GetScreenHeight() - 30, GetScreenWidth() - 180, 20), "ANIM 1", the frame text, &animFrameProgress1, 0, keyframeCount).
def draw.second(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  match text:
    case None{}: refused(core, camera, model, textures, gui, play, frame)
    case Some{t}: draw.second.bar(G.Gui.progress_bar(gui, frame, J.Rectangle{60.0, 420.0, 620.0, 20.0}, Some{"ANIM 1"}, Some{t}, track.frame(play.second(play)), 0.0,
      U32.to_f32(total(play, play.second(play)))), core, camera, model, textures, gui, play)

def progress.text(+play: Play, +track: Track) -> Maybe<String>:
  J.Text.format("FRAME: %.2f / %i", [J.TextFloat{track.frame(track)}, J.TextInt{total(play, track)}])

def draw.first.bar(r: J.Frame & F32, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (frame, _) = r
  draw.second(progress.text(play, play.second(play)), ticks(U32.to_nat(total(play, play.first(play))), 0, total(play, play.first(play)), 390.0, frame), core, camera, model, textures, gui, play)

# GuiProgressBar((60, GetScreenHeight() - 60, GetScreenWidth() - 180, 20), "ANIM 0", the frame text, &animFrameProgress0, 0, keyframeCount).
def draw.first(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  match text:
    case None{}: refused(core, camera, model, textures, gui, play, frame)
    case Some{t}: draw.first.bar(G.Gui.progress_bar(gui, frame, J.Rectangle{60.0, 390.0, 620.0, 20.0}, Some{"ANIM 0"}, Some{t}, track.frame(play.first(play)), 0.0,
      U32.to_f32(total(play, play.first(play)))), core, camera, model, textures, gui, play)

def draw.picked1(pair: U32 & Bool, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (+index, +toggled) = pair
  draw.first(progress.text(with.second(play, with.picked(play.second(play), index, toggled)), play.first(play)), frame, core, camera, model, textures, gui,
    with.second(play, with.picked(play.second(play), index, toggled)))

def draw.dropped1(r: J.Frame & (U32 & Bool), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  draw.picked1(pair, frame, core, camera, model, textures, gui, play)

# The blend bar's value comes back capped at 1 (the native bar writes animBlendProgress);
# GuiDropdownBox((GetScreenWidth() - 170, 10, 160, 24), names, &animIndex1, dropdownEditMode1).
def draw.blend(r: J.Frame & F32, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (frame, +progress) = r
  draw.dropped1(G.Gui.dropdown_box(gui, core, frame, J.Rectangle{630.0, 10.0, 160.0, 24.0}, play.names(play), track.index(play.second(play)), track.edit(play.second(play))), core, camera, model, textures, gui,
    with.progress(play, progress))

# GuiSetStyle(PROGRESSBAR, PROGRESS_SIDE, 0 towards animation 1, else 1); GuiProgressBar((180, 14, 440, 16), NULL, NULL, &animBlendProgress, 0, 1); the side back to 0.
def draw.picked0(pair: U32 & Bool, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (+index, +toggled) = pair
  draw.blend(G.Gui.progress_bar(G.Gui.set_style(gui, 5, 17, Bool.pick(U32, U32.is_eq(blend.next(play.blend(play)), 1), 0, 1)), frame, J.Rectangle{180.0, 14.0, 440.0, 16.0}, None{}, None{},
    blend.progress(play.blend(play)), 0.0, 1.0), core, camera, model, textures, gui, with.first(play, with.picked(play.first(play), index, toggled)))

def draw.dropped0(r: J.Frame & (U32 & Bool), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  draw.picked0(pair, frame, core, camera, model, textures, gui, play)

# GuiEnable(); GuiSetStyle(DROPDOWNBOX, DROPDOWN_ITEMS_SPACING, 1); GuiDropdownBox((10, 10, 160, 24), names, &animIndex0, dropdownEditMode0).
def draw.sped1(result: Slid, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +play: Play) -> J.Core & (State & J.Frame):
  Slid{+gui, +speed} = result
  draw.dropped0(G.Gui.dropdown_box(G.Gui.set_style(G.Gui.enable(gui), 8, 17, 1), core, frame, J.Rectangle{10.0, 10.0, 160.0, 24.0}, play.names(play), track.index(play.first(play)), track.edit(play.first(play))),
    core, camera, model, textures, G.Gui.set_style(G.Gui.enable(gui), 8, 17, 1), with.second(play, with.speed(play.second(play), speed)))

def draw.slid1(r: J.Frame & (G.Gui & (F32 & Bool)), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +play: Play) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.sped1(slid(rest), frame, core, camera, model, textures, play)

def dimmed(off: Bool, gui: G.Gui) -> G.Gui:
  match off:
    case False{}: gui
    case True{}: G.Gui.disable(gui)

# if (dropdownEditMode1) GuiDisable(); GuiSlider((GetScreenWidth() - 170, 38, 160, 12), TextFormat("%.1fx", animFrameSpeed1), NULL, &animFrameSpeed1, 0.1f, 2.0f).
def draw.text1(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  match text:
    case None{}: refused(core, camera, model, textures, gui, play, frame)
    case Some{t}: draw.slid1(G.Gui.slider(dimmed(track.edit(play.second(play)), gui), core, frame, J.Rectangle{630.0, 38.0, 160.0, 12.0}, Some{t}, None{}, track.speed(play.second(play)), 0.1, 2.0),
      core, camera, model, textures, play)

# GuiEnable() after the first slider.
def draw.sped0(result: Slid, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +play: Play) -> J.Core & (State & J.Frame):
  Slid{gui, +speed} = result
  draw.text1(J.Text.format("%.1fx", [J.TextFloat{track.speed(play.second(play))}]), frame, core, camera, model, textures, G.Gui.enable(gui), with.first(play, with.speed(play.first(play), speed)))

def draw.slid0(r: J.Frame & (G.Gui & (F32 & Bool)), +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +play: Play) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.sped0(slid(rest), frame, core, camera, model, textures, play)

# if (dropdownEditMode0) GuiDisable(); GuiSlider((10, 38, 160, 12), NULL, TextFormat("x%.1f", animFrameSpeed0), &animFrameSpeed0, 0.1f, 2.0f).
def draw.text0(text: Maybe<String>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play) -> J.Core & (State & J.Frame):
  match text:
    case None{}: refused(core, camera, model, textures, gui, play, frame)
    case Some{t}: draw.slid0(G.Gui.slider(dimmed(track.edit(play.first(play)), gui), core, frame, J.Rectangle{10.0, 38.0, 160.0, 12.0}, None{}, Some{t}, track.speed(play.first(play)), 0.1, 2.0),
      core, camera, model, textures, play)

# if (animTransition) DrawText("ANIM TRANSITION BLENDING!", 170, 50, 30, BLUE).
def banner(transition: Bool, frame: J.Frame) -> J.Frame:
  match transition:
    case False{}: frame
    case True{}: J.Draw.text(frame, "ANIM TRANSITION BLENDING!", 170.0, 50.0, 30.0, J.Color.BLUE())

# DrawGrid(10, 1.0f); EndMode3D(); the banner and the controls.
def draw.gui(+core: J.Core, +camera: J.Camera3D, +model: J.Model, +gui: G.Gui, +play: Play, r: J.Frame & List<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.text0(J.Text.format("x%.1f", [J.TextFloat{track.speed(play.first(play))}]), banner(blend.transition(play.blend(play)), J.Frame.end_mode_3d(J.Draw.grid(frame, 10.0, 1.0))), core, camera, model, textures, gui,
    play)

# DrawModel(model, (0, 0, 0), 1.0f, WHITE).
def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +model: J.Model, textures: List<J.Texture>, +gui: G.Gui, +play: Play, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.gui(core, c, model, gui, play,
      J.Draw.model(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), c), textures, model, M.Vector3.zero(), 1.0, J.Color.WHITE()))
    case _ None{}: (core, (State{False{}, None{}, model, textures, gui, play}, J.Frame.refuse(frame)))
    case False{} Some{+c}: (core, (State{False{}, Some{c}, model, textures, gui, play}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, +model, textures, +gui, +play} = state
  draw.at(valid, camera, libm, core, model, textures, gui, play, frame)

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf, the perspective tan and the poses' QuaternionSlerp.
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

# animIndex0 = 10 (walking) playing, animIndex1 = 6 (running) next, both at half a keyframe a frame; SetTargetFPS(60).
def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, +model: J.Model, textures: List<J.Texture>, +skeleton: J.ModelSkeleton, +animations: +List<J.ModelAnimation>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{valid, Some{start()}, model, textures, G.Gui.new(),
    Play{skeleton, animations, joined(animations, True{}), J.Model.pose(skeleton), Mix{Track{10, 0.0, 0.5, False{}}, Track{6, 0.0, 0.5, False{}}, Blend{0, 1, False{}, 0.0, 0.0, 0.0}}, False{}}}))

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
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [models] example - animation blending", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(M.Glibc239Libm{}, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
