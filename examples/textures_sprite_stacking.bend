# raylib [textures] example - sprite stacking, ported to Jonlib.
# Adapted from raylib 6.2 examples/textures/textures_sprite_stacking.c
# (zlib/libpng, Copyright (c) 2025 Robin (@RobinsAviary)); see
# LICENSES/raylib.txt.
#
# The 122 slices of the booth sprite drawn bottom to top with DrawTexturePro,
# each turned by the same rotation, which advances with the frame time; A/D
# change the speed and the wheel the slice spacing. DrawTexturePro's
# sinf/cosf follow the libm profile: under M.AppleLibm{} (whole degrees) the
# first frame with a nonzero rotation is refused (docs/SINCOSF.md).
# booth.png is 112 pixels by 11468: a texture's PNG may be that long
# (J.Texture.load, docs/TEXTURES.md), which an image may not. Loads
# resources/booth.png from raylib's examples/textures directory: run from
# that directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{booth: Maybe<J.Texture>, spacing: F32, speed: F32, rotation: F32}

# Clamp(value, 0, 5).
def clamp(+v: F32) -> F32:
  +low = Bool.pick(F32, (v < 0.0 : F32), 0.0, v)
  Bool.pick(F32, (low > 5.0 : F32), 5.0, low)

def key(+core: J.Core, +a: U32, +b: U32) -> Bool:
  J.Input.is_key_down(core, a) || J.Input.is_key_down(core, b)

def update(+core: J.Core, state: State) -> J.Core & State:
  State{booth, +spacing, +speed, +rotation} = state
  +spaced = clamp((spacing + J.Input.get_mouse_wheel_move(core) * 0.1 : F32))
  +slower = Bool.pick(F32, key(core, J.KeyboardKey.KEY_LEFT(), J.KeyboardKey.KEY_A()), (speed - 0.25 : F32), speed)
  +faster = Bool.pick(F32, key(core, J.KeyboardKey.KEY_RIGHT(), J.KeyboardKey.KEY_D()), (slower + 0.25 : F32), slower)
  (core, State{booth, spaced, faster, (rotation + faster * J.Core.get_frame_time(core) : F32)})

# Slice i: source (0, i*frameHeight, width, frameHeight), dest centered at
# (400, 225 + i*spacing - spacing*122/2) and three times the size, origin at its middle.
def slice(+libm: M.Libm, +i: U32, +spacing: F32, +rotation: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, texture) = r
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  +fw = U32.to_f32(w)
  +fh = (U32.to_f32(h) / 122.0 : F32)
  +sw = (fw * 3.0 : F32)
  +sh = (fh * 3.0 : F32)
  J.Draw.texture_pro_for(libm, frame, J.Texture{id, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, (U32.to_f32(i) * fh : F32), fw, fh},
    J.Rectangle{(800.0 / 2.0 : F32), ((450.0 / 2.0) + (U32.to_f32(i) * spacing) - (spacing * 122.0 / 2.0) : F32), sw, sh},
    M.Vector2{(sw / 2.0 : F32), (sh / 2.0 : F32)}, rotation, J.Color.WHITE())

# i from stackCount - 1 down to 0.
def slices(n: Nat, +libm: M.Libm, +i: U32, +spacing: F32, +rotation: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match n:
    case 0n: r
    case 1n+p: slices(p, libm, (i - 1 : U32), spacing, rotation, slice(libm, i, spacing, rotation, r))

def stacked.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def stacked(+libm: M.Libm, +spacing: F32, +rotation: F32, frame: J.Frame, booth: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match booth:
    case None{}: (frame, None{})
    case Some{t}: stacked.kept(slices(122n, libm, 121, spacing, rotation, (frame, t)))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.DARKGRAY())

def draw.done(+core: J.Core, +spacing: F32, +speed: F32, +rotation: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, booth) = r
  f1 = J.Draw.text(frame, "A/D to spin\nmouse wheel to change separation (aka 'angle')", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f2 = label(J.Text.format("current spacing: %.01f", [J.TextFloat{spacing}]), 50.0, f1)
  f3 = label(J.Text.format("current speed: %.02f", [J.TextFloat{speed}]), 70.0, f2)
  (core, (State{booth, spacing, speed, rotation}, J.Draw.text(f3, "redbooth model (c) kluchek under cc 4.0", 10.0, 420.0, 20.0, J.Color.DARKGRAY())))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{booth, +spacing, +speed, +rotation} = state
  draw.done(core, spacing, speed, rotation, stacked(libm, spacing, rotation, J.Frame.clear_background(frame, J.Color.RAYWHITE()), booth))

# The main loop's body; libm is the sinf/cosf profile of DrawTexturePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, booth) = r
  (J.Core.set_target_fps(core, 60), (frame, State{booth, 2.0, 30.0, 0.0}))

# After InitWindow(800, 450): LoadTexture("resources/booth.png"), spacing 2,
# speed 30 degrees a second, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/booth.png"),
    r => IO.pure(J.Core & (J.Frame & State), setup.uploaded(core, r)))

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
  (+dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - sprite stacking", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
