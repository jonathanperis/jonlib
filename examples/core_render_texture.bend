# raylib [core] example - render texture, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_render_texture.c (zlib/libpng,
# Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A ball bounces inside a 300x300 render texture drawn rotating on the
# screen. raylib draws into the texture before BeginDrawing; here the draw
# does that first, in texture mode (the same pixels). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{target: Maybe<J.RenderTexture>, ball: M.Vector2, speed: M.Vector2, rotation: F32}

# Bounces off 20..280 (renderTexture size minus ballRadius); rotation += 0.5.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{target, +ball, +speed, +rotation} = state
  M.Vector2{+x, +y} = ball
  M.Vector2{+sx, +sy} = speed
  +nx = (x + sx : F32)
  +ny = (y + sy : F32)
  +tx = Bool.pick(F32, (nx >= 280.0 : F32) || (nx <= 20.0 : F32), (sx * F32.neg(1.0) : F32), sx)
  +ty = Bool.pick(F32, (ny >= 280.0 : F32) || (ny <= 20.0 : F32), (sy * F32.neg(1.0) : F32), sy)
  (core, State{target, M.Vector2{nx, ny}, M.Vector2{tx, ty}, (rotation + 0.5 : F32)})

def ball.drawn(+libm: M.Libm, +ball: M.Vector2, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle(J.Frame.clear_background(frame, J.Color.SKYBLUE()), 0.0, 0.0, 20.0, 20.0, J.Color.RED())
  J.Draw.circle_v_for(libm, f1, ball, 20.0, J.Color.MAROON())

def target.drawn(+libm: M.Libm, +ball: M.Vector2, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: J.Frame.end_texture_mode(ball.drawn(libm, ball, J.Frame.begin_texture_mode(frame, t)))

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTexturePro(target.texture, (0, 0, w, -h), (400, 225, w, h), (w/2, h/2), rotation, WHITE).
def target.show.at(+libm: M.Libm, +rotation: F32, frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  +fw = U32.to_f32(w)
  +fh = U32.to_f32(h)
  shown(id, depth, J.Draw.texture_pro_for(libm, frame, J.Texture{tid, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, fw, F32.neg(fh)},
    J.Rectangle{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32), fw, fh}, M.Vector2{(fw / 2.0 : F32), (fh / 2.0 : F32)}, rotation, J.Color.WHITE()))

def target.show(+libm: M.Libm, +rotation: F32, r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, target) = r
  match target:
    case None{}: (frame, None{})
    case Some{t}: target.show.at(libm, rotation, frame, t)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+libm: M.Libm, +core: J.Core, +ball: M.Vector2, +speed: M.Vector2, +rotation: F32, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  f1 = J.Draw.text(frame, "DRAWING BOUNCING BALL INSIDE RENDER TEXTURE!", 10.0, 410.0, 20.0, J.Color.BLACK())
  draw.fps.done(State{target, ball, speed, rotation}, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.screen(+rotation: F32, +libm: M.Libm, r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, target) = r
  target.show(libm, rotation, (J.Frame.clear_background(frame, J.Color.RAYWHITE()), target))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +ball, +speed, +rotation} = state
  draw.done(libm, core, ball, speed, rotation, draw.screen(rotation, libm, target.drawn(libm, ball, frame, target)))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV and DrawTexturePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{target, M.Vector2{(300.0 / 2.0 : F32), (300.0 / 2.0 : F32)}, M.Vector2{5.0, 4.0}, 0.0}))

# After InitWindow(800, 450): the 300x300 render texture, the ball at its
# center moving (5, 4), rotation 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 300, 300))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - render texture", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
