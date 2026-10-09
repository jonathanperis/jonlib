# raylib [textures] example - srcrec dstrec, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_srcrec_dstrec.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Loads resources/scarfy.png from raylib's examples/textures (not copied into
# this repository): run it from that directory, or pass `--resources <dir/>`.
# DrawTexturePro rotates by one more degree every frame; its sinf/cosf follow
# the M.Libm profile (the Apple profile refuses 13, 19, 22, 103 and 188
# degrees; the interactive run uses glibc 2.39's). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The texture (None when it did not load: raylib's id 0 draws nothing), its
# frame size (width/6, height) and the rotation in degrees (a C int).
type State is Type:
  State{scarfy: Maybe<J.Texture>, fw: U32, fh: U32, rotation: U32}

# rotation++ (the C int overflows after 2^31 - 1 frames: refused there).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{scarfy, +fw, +fh, +rotation} = state
  (core, State{scarfy, fw, fh, (rotation + 1 : U32)})

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexturePro(scarfy, (0, 0, fw, fh), (400, 225, fw*2, fh*2), (fw, fh),
# (float)rotation, WHITE).
def draw.texture(+libm: M.Libm, frame: J.Frame, texture: Maybe<J.Texture>, +w: F32, +h: F32, +rotation: U32) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: drawn(J.Draw.texture_pro_for(libm, frame, t, J.Rectangle{0.0, 0.0, w, h}, J.Rectangle{400.0, 225.0, (w * 2.0 : F32), (h * 2.0 : F32)},
      M.Vector2{w, h}, U32.to_f32(rotation), J.Color.WHITE()))

def checked(overflow: Bool, frame: J.Frame) -> J.Frame:
  match overflow:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

def draw.rest(+core: J.Core, +fw: U32, +fh: U32, +rotation: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.line(frame, 400.0, 0.0, 400.0, 450.0, J.Color.GRAY())
  f2 = J.Draw.line(f1, 0.0, 225.0, 800.0, 225.0, J.Color.GRAY())
  f3 = J.Draw.text(f2, "(c) Scarfy sprite by Eiden Marsal", 600.0, 430.0, 10.0, J.Color.GRAY())
  (core, (State{texture, fw, fh, rotation}, checked((rotation >= 2147483648 : U32), f3)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{scarfy, +fw, +fh, +rotation} = state
  draw.rest(core, fw, fh, rotation,
    draw.texture(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), scarfy, U32.to_f32(fw), U32.to_f32(fh), rotation))

# The main loop's body; libm is the sinf/cosf profile of DrawTexturePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.sized(+core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, (w / 6 : U32), h, 0}))

def setup.texture(+core: J.Core, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  match texture:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0, 0, 0}))
    case Some{t}: setup.sized(core, frame, t)

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.texture(core, frame, texture)

# After InitWindow(800, 450): LoadTexture(dir ++ "resources/scarfy.png"),
# SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/scarfy.png"),
    r => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, r)))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - srcrec dstrec", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
