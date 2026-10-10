# raylib [textures] example - gif player, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_gif_player.c
# (zlib/libpng, Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The frames of a GIF (LoadImageAnim) shown one after another by updating a
# texture every frameDelay frames (UpdateTexture with the frame's offset in
# the image data); RIGHT and LEFT change the delay inside 1..20. Here the
# decoded frames are a list of images and the texture takes a copy of the
# current one. A frame Jonlib cannot upload refuses the frames. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# frames: the decoded images; pixels: width*height; current, delay, counter:
# currentAnimFrame, frameDelay and frameCounter.
type State is Type:
  State{valid: Bool, frames: List<J.Surface>, texture: Maybe<J.Texture>, count: U32, pixels: U32, current: U32, delay: U32, counter: U32}

def copy.kept(first: J.Surface, r: List<J.Surface> & Maybe<J.Surface>) -> List<J.Surface> & Maybe<J.Surface>:
  (rest, copy) = r
  (Con{first, rest}, copy)

def copy.made(rest: List<J.Surface>, pair: J.Surface & J.Surface) -> List<J.Surface> & Maybe<J.Surface>:
  (original, copy) = pair
  (Con{original, rest}, Some{copy})

# A copy of frame n (the list keeps its images).
def copy(frames: List<J.Surface>, n: Nat) -> List<J.Surface> & Maybe<J.Surface>:
  match frames n:
    case Nil{} _: (Nil{}, None{})
    case Con{first, rest} 0n: copy.made(rest, J.Surface.copy(first))
    case Con{first, rest} 1n+p: copy.kept(first, copy(rest, p))

def updated(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> Maybe<J.Texture>:
  match result:
    case Fail{_}: None{}
    case Done{texture}: Some{texture}

# UpdateTexture(texScarfyAnim, imScarfyAnim.data + nextFrameDataOffset).
def upload(texture: Maybe<J.Texture>, pixels: Maybe<J.Surface>) -> Maybe<J.Texture>:
  match texture pixels:
    case Some{t} Some{p}: updated(J.Texture.update(t, p))
    case _ _: None{}

def switched.done(+count: U32, +pixels: U32, +current: U32, +delay: U32, frames: List<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match texture:
    case None{}: State{False{}, frames, None{}, count, pixels, current, delay, 0}
    case Some{t}: State{True{}, frames, Some{t}, count, pixels, current, delay, 0}

def switched.copied(+count: U32, +pixels: U32, +current: U32, +delay: U32, texture: Maybe<J.Texture>, r: List<J.Surface> & Maybe<J.Surface>) -> State:
  (frames, copy) = r
  switched.done(count, pixels, current, delay, frames, upload(texture, copy))

# frameCounter++; at frameDelay the next frame (after the last, the first) goes into the texture.
def switched(switch: Bool, +valid: Bool, +count: U32, +pixels: U32, +current: U32, +delay: U32, +counter: U32, frames: List<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match switch:
    case False{}: State{valid, frames, texture, count, pixels, current, delay, counter}
    case True{}: switched.copied(count, pixels, Bool.pick(U32, ((current + 1) >= count : U32), 0, (current + 1 : U32)), delay, texture,
      copy(frames, U32.to_nat(Bool.pick(U32, ((current + 1) >= count : U32), 0, (current + 1 : U32)))))

# RIGHT adds a frame of delay, otherwise LEFT removes one; the delay stays inside 1..20.
def paced(+core: J.Core, state: State) -> State:
  State{+valid, frames, texture, +count, +pixels, +current, +delay, +counter} = state
  +more = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +less = Bool.not(more) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  State{valid, frames, texture, count, pixels, current,
    Bool.pick(U32, more, U32.min((delay + 1 : U32), 20), Bool.pick(U32, less && (delay > 1 : U32), (delay - 1 : U32), delay)), counter}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, frames, texture, +count, +pixels, +current, +delay, +counter} = state
  (core, paced(core, switched(((counter + 1) >= delay : U32), valid, count, pixels, current, delay, (counter + 1 : U32), frames, texture)))

def label(text: Maybe<String>, +x: F32, +y: F32, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, size, color)

# if (i < frameDelay) DrawRectangle(190 + 21*i, 300, 20, 20, RED).
def box(filled: Bool, +i: U32, frame: J.Frame) -> J.Frame:
  match filled:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, U32.to_f32((190 + 21 * i : U32)), 300.0, 20.0, 20.0, J.Color.RED())

# The delay as twenty boxes, the first frameDelay of them filled.
def boxes(n: Nat, +i: U32, +delay: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: boxes(p, (i + 1 : U32), delay, J.Draw.rectangle_lines(box((i < delay : U32), i, frame), U32.to_f32((190 + 21 * i : U32)), 300.0, 20.0, 20.0, J.Color.MAROON()))

def draw.shown(+core: J.Core, frames: List<J.Surface>, +count: U32, +pixels: U32, +current: U32, +delay: U32, +counter: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{True{}, frames, Some{texture}, count, pixels, current, delay, counter},
    J.Draw.text(frame, "(c) Scarfy sprite by Eiden Marsal", (800.0 - 200.0 : F32), (450.0 - 20.0 : F32), 10.0, J.Color.GRAY())))

# DrawTexture(texScarfyAnim, GetScreenWidth()/2 - texScarfyAnim.width/2, 140, WHITE).
def draw.at(+core: J.Core, frames: List<J.Surface>, +count: U32, +pixels: U32, +current: U32, +delay: U32, +counter: U32, frame: J.Frame, texture: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(core, frames, count, pixels, current, delay, counter,
    J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (800.0 / 2.0 - U32.to_f32((w / 2 : U32)) : F32), 140.0, J.Color.WHITE()))

def texts(+count: U32, +pixels: U32, +current: U32, +delay: U32, frame: J.Frame) -> J.Frame:
  f1 = label(J.Text.format("TOTAL GIF FRAMES:  %02i", [J.TextInt{count}]), 50.0, 30.0, 20.0, J.Color.LIGHTGRAY(), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = label(J.Text.format("CURRENT FRAME: %02i", [J.TextInt{current}]), 50.0, 60.0, 20.0, J.Color.GRAY(), f1)
  f3 = label(J.Text.format("CURRENT FRAME IMAGE.DATA OFFSET: %02i", [J.TextInt{(pixels * 4 * current : U32)}]), 50.0, 90.0, 20.0, J.Color.GRAY(), f2)
  f4 = J.Draw.text(f3, "FRAMES DELAY: ", 100.0, 305.0, 10.0, J.Color.DARKGRAY())
  f5 = label(J.Text.format("%02i frames", [J.TextInt{delay}]), 620.0, 305.0, 10.0, J.Color.DARKGRAY(), f4)
  boxes(20n, 0, delay, J.Draw.text(f5, "PRESS RIGHT/LEFT KEYS to CHANGE SPEED!", 290.0, 350.0, 10.0, J.Color.DARKGRAY()))

def draw.valid(valid: Bool, +core: J.Core, frames: List<J.Surface>, +count: U32, +pixels: U32, +current: U32, +delay: U32, +counter: U32, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  match valid texture:
    case True{} Some{t}: draw.at(core, frames, count, pixels, current, delay, counter, texts(count, pixels, current, delay, frame), t)
    case False{} Some{t}: (core, (State{False{}, frames, Some{t}, count, pixels, current, delay, counter}, J.Frame.refuse(frame)))
    case _ None{}: (core, (State{False{}, frames, None{}, count, pixels, current, delay, counter}, J.Frame.refuse(frame)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, frames, texture, +count, +pixels, +current, +delay, +counter} = state
  draw.valid(valid, core, frames, count, pixels, current, delay, counter, frame, texture)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def none(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{False{}, Nil{}, None{}, 0, 0, 0, 8, 0}))

def setup.uploaded(+core: J.Core, frames: List<J.Surface>, +count: U32, +pixels: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, frames, texture, count, pixels, 0, 8, 0}))

# texScarfyAnim = LoadTextureFromImage(imScarfyAnim): the first frame.
def setup.first(+core: J.Core, frame: J.Frame, +count: U32, +pixels: U32, r: List<J.Surface> & Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (frames, first) = r
  match first:
    case None{}: none(core, frame)
    case Some{image}: setup.uploaded(core, frames, count, pixels, J.Texture.load_from_image(frame, image))

def setup.entries(+core: J.Core, frame: J.Frame, entries: U32 & U32 & U32 & List<J.Surface>) -> J.Core & (J.Frame & State):
  (+width, rest) = entries
  (+height, more) = rest
  (+count, frames) = more
  setup.first(core, frame, count, (width * height : U32), copy(frames, 0n))

def setup.decoded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: none(core, frame)
    case Done{animation}: setup.entries(core, frame, J.Image.Animation.entries(animation))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: none(core, frame)
    case Done{+bytes}: setup.decoded(core, frame, J.Image.Animation.decode_gif(bytes, 64, 1048576))

# After InitWindow(800, 450): LoadImageAnim("resources/scarfy_run.gif") (the
# file's bytes through the GIF decoder), its texture, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, J.Core & (J.Frame & State), J.Files.load_data(dir ++ "resources/scarfy_run.gif"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - gif player", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
