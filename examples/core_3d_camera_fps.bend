# raylib [core] example - 3d camera fps, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_camera_fps.c (zlib/libpng,
# Copyright (c) 2025 Agnis Aldiņš (@nezvers)); see LICENSES/raylib.txt.
#
# A first-person body with strafing physics (W, A, S, D, SPACE to jump,
# LEFT CTRL to crouch) and the example's own camera: mouse look clamped by
# Vector3Angle, a head bob, a lean and a field of view that narrows while
# walking. The body's and the head's sinf/cosf, Vector3RotateByAxisAngle
# and Vector3Angle's atan2f follow the libm profile (docs/SINCOSF.md,
# docs/ANGLES.md) and the perspective needs its binary64 tan
# (docs/PERSPECTIVE.md); a value outside the profile refuses that frame
# and every later one. See docs/CAMERA.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The player's Body.
type Body is Data:
  Body{position: M.Vector3, velocity: M.Vector3, dir: M.Vector3, grounded: Bool}

# lookRotation, headTimer, walkLerp, headLerp, lean and the camera; ok: no refusal so far.
type State is Data:
  State{body: Body, look: M.Vector2, head: F32, walk: F32, height: F32, lean: M.Vector2, camera: J.Camera3D, ok: Bool}

# UpdateCameraFPS's results: the camera and lookRotation.y.
type Aim is Data:
  Aim{camera: J.Camera3D, look: F32}

def up() -> M.Vector3:
  M.Vector3{0.0, 1.0, 0.0}

def pair(first: Maybe<F32>, second: Maybe<F32>) -> Maybe<M.Vector2>:
  match first second:
    case Some{+a} Some{+b}: Some{M.Vector2{a, b}}
    case _ _: None{}

# bobbing = right*(headSin*bobSide) with bobbing.y = fabsf(headCos*bobUp).
def aim.bob(sway: M.Vector3, +lift: F32) -> M.Vector3:
  M.Vector3{+x, _, +z} = sway
  M.Vector3{x, lift, z}

# The up direction rotated around the view by the head's sway and the lean, the bobbing scaled by walkLerp, the target.
def aim.built(+libm: M.Libm, +position: M.Vector3, +fovy: F32, +looky: F32, +leanx: F32, +walk: F32, +right: M.Vector3, +pitch: M.Vector3, head: M.Vector2) -> Aim:
  M.Vector2{+sine, +cosine} = head
  +sway = M.Vector3.scale(right, (sine * 0.1 : F32))
  +bobbed = M.Vector3.add(position, M.Vector3.scale(aim.bob(sway, F32.abs((cosine * 0.15 : F32))), walk))
  Aim{J.Camera3D{bobbed, M.Vector3.add(bobbed, pitch), M.Vector3.rotate_by_axis_angle_for(libm, up(), pitch, (sine * 0.01 + leanx : F32)), fovy, J.CameraProjection.CAMERA_PERSPECTIVE()}, looky}

def aim.head(+libm: M.Libm, +position: M.Vector3, +fovy: F32, +looky: F32, +leanx: F32, +walk: F32, +right: M.Vector3, +pitch: M.Vector3, head: Maybe<M.Vector2>) -> Maybe<Aim>:
  match head:
    case None{}: None{}
    case Some{+h}: Some{aim.built(libm, position, fovy, looky, leanx, walk, right, pitch, h)}

# The look clamped just inside straight up and down, the view pitched around the right axis.
def aim.clamped(+libm: M.Libm, +position: M.Vector3, +fovy: F32, +looky: F32, +lean: M.Vector2, +timer: F32, +walk: F32, +yaw: M.Vector3, angles: M.Vector2) -> Maybe<Aim>:
  M.Vector2{+leanx, +leany} = lean
  M.Vector2{+above, +below} = angles
  +top = (above - 0.001 : F32)
  +raised = Bool.pick(F32, (F32.neg(looky) > top : F32), F32.neg(top), looky)
  +bottom = (below * F32.neg(1.0) + 0.001 : F32)
  +lowered = Bool.pick(F32, (F32.neg(raised) < bottom : F32), F32.neg(bottom), raised)
  +right = M.Vector3.normalize(M.Vector3.cross_product(yaw, up()))
  +pitch = M.Vector3.rotate_by_axis_angle_for(libm, yaw, right, M.Math.clamp((F32.neg(lowered) - leany : F32), (F32.neg(M.Math.PI()) / 2.0 + 0.0001 : F32), (M.Math.PI() / 2.0 - 0.0001 : F32)))
  aim.head(libm, position, fovy, lowered, leanx, walk, right, pitch, pair(M.Libm.sin(libm, (timer * M.Math.PI() : F32)), M.Libm.cos(libm, (timer * M.Math.PI() : F32))))

def aim.angles(+libm: M.Libm, +position: M.Vector3, +fovy: F32, +looky: F32, +lean: M.Vector2, +timer: F32, +walk: F32, +yaw: M.Vector3, angles: Maybe<M.Vector2>) -> Maybe<Aim>:
  match angles:
    case None{}: None{}
    case Some{+a}: aim.clamped(libm, position, fovy, looky, lean, timer, walk, yaw, a)

def aim.yawed(+libm: M.Libm, +position: M.Vector3, +fovy: F32, +looky: F32, +lean: M.Vector2, +timer: F32, +walk: F32, +yaw: M.Vector3) -> Maybe<Aim>:
  aim.angles(libm, position, fovy, looky, lean, timer, walk, yaw, pair(M.Vector3.angle_for(libm, up(), yaw), M.Vector3.angle_for(libm, M.Vector3.negate(up()), yaw)))

# UpdateCameraFPS: the yaw of (0, 0, -1) around up, then the clamps, the pitch, the head animation and the bob.
def aim(+libm: M.Libm, +position: M.Vector3, +fovy: F32, look: M.Vector2, +lean: M.Vector2, +timer: F32, +walk: F32) -> Maybe<Aim>:
  M.Vector2{+lookx, +looky} = look
  aim.yawed(libm, position, fovy, looky, lean, timer, walk, M.Vector3.rotate_by_axis_angle_for(libm, M.Vector3{0.0, 0.0, F32.neg(1.0)}, up(), lookx))

# body->position += body->velocity*delta; at or below the floor the body stands on it.
def moved.landed(+px: F32, +py: F32, +pz: F32, +vy: F32, +floor: Bool, +dt: F32, +accel: F32, +dir: M.Vector3, hvel: M.Vector3) -> Body:
  M.Vector3{+dx, _, +dz} = dir
  M.Vector3{+hx, _, +hz} = hvel
  +vx = (hx + dx * accel : F32)
  +vz = (hz + dz * accel : F32)
  +y = (py + vy * dt : F32)
  +down = (y <= 0.0 : F32)
  Body{M.Vector3{(px + vx * dt : F32), Bool.pick(F32, down, 0.0, y), (pz + vz * dt : F32)}, M.Vector3{vx, Bool.pick(F32, down, 0.0, vy), vz}, dir, floor || down}

# The direction eased to the input, the horizontal velocity dragged, stopped below 1% of MAX_SPEED and accelerated
# along the direction up to the speed limit; the move, and the floor.
def moved.at(+input: M.Vector2, +jump: Bool, +crouch: Bool, +dt: F32, body: Body, front: M.Vector2, right: M.Vector2) -> Body:
  M.Vector2{+ix, +iy} = input
  Body{+position, +velocity, +dir, +grounded} = body
  M.Vector3{+px, +py, +pz} = position
  M.Vector3{+vx, +vy, +vz} = velocity
  M.Vector2{+fs, +fc} = front
  M.Vector2{+rc, +rs} = right
  +fall = Bool.pick(F32, grounded, vy, (vy - 32.0 * dt : F32))
  +leap = grounded && jump
  +vy1 = Bool.pick(F32, leap, 12.0, fall)
  +floor = grounded && Bool.not(leap)
  +turned = M.Vector3.lerp(dir, M.Vector3{(ix * rc + iy * fs : F32), 0.0, (ix * rs + iy * fc : F32)}, (15.0 * dt : F32))
  +decel = Bool.pick(F32, floor, 0.86, 0.98)
  +drag = {M.Vector3{(vx * decel : F32), 0.0, (vz * decel : F32)} : M.Vector3}
  +hvel = Bool.pick(M.Vector3, (M.Vector3.length(drag) < (20.0 * 0.01) : F32), M.Vector3.zero(), drag)
  +accel = M.Math.clamp((Bool.pick(F32, crouch, 5.0, 20.0) - M.Vector3.dot_product(hvel, turned) : F32), 0.0, (150.0 * dt : F32))
  moved.landed(px, py, pz, vy1, floor, dt, accel, turned, hvel)

def moved.trig(+input: M.Vector2, +jump: Bool, +crouch: Bool, +dt: F32, +body: Body, front: Maybe<M.Vector2>, right: Maybe<M.Vector2>) -> Maybe<Body>:
  match front right:
    case Some{+f} Some{+r}: Some{moved.at(input, jump, crouch, dt, body, f, r)}
    case _ _: None{}

# UpdateBody: front = (sinf(rot), 0, cosf(rot)), right = (cosf(-rot), 0, sinf(-rot)); a diagonal input is normalized.
def moved(+libm: M.Libm, +body: Body, +rot: F32, +side: F32, +forward: F32, +jump: Bool, +crouch: Bool, +dt: F32) -> Maybe<Body>:
  +input = {M.Vector2{side, (0.0 - forward : F32)} : M.Vector2}
  moved.trig(Bool.pick(M.Vector2, Bool.not(F32.is_eq(side, 0.0)) && Bool.not(F32.is_eq(forward, 0.0)), M.Vector2.normalize(input), input), jump, crouch, dt, body,
    pair(M.Libm.sin(libm, rot), M.Libm.cos(libm, rot)), pair(M.Libm.cos(libm, F32.neg(rot)), M.Libm.sin(libm, F32.neg(rot))))

def refused(+state: State) -> State:
  State{+body, +look, +head, +walk, +height, +lean, +camera, _} = state
  State{body, look, head, walk, height, lean, camera, False{}}

def update.kept(state: State, +body: Body, +lookx: F32, +looky: F32, +head: F32, +walk: F32, +height: F32, +lean: M.Vector2, +camera: J.Camera3D) -> State:
  State{_, _, _, _, _, _, _, +ok} = state
  State{body, M.Vector2{lookx, looky}, head, walk, height, lean, camera, ok}

def update.aimed(+state: State, +body: Body, +lookx: F32, +head: F32, +walk: F32, +height: F32, +lean: M.Vector2, aim: Maybe<Aim>) -> State:
  match aim:
    case None{}: refused(state)
    case Some{Aim{+camera, +looky}}: update.kept(state, body, lookx, looky, head, walk, height, lean, camera)

# headLerp to the crouch or stand height; walking on the floor advances the head timer and narrows the field of
# view; the lean follows the keys; then the camera from the body.
def update.body(+libm: M.Libm, +state: State, +look: M.Vector2, +side: F32, +forward: F32, +crouch: Bool, +dt: F32, +body: Body) -> State:
  State{_, _, +head, +walk, +height, +lean, +camera, _} = state
  M.Vector2{+leanx, +leany} = lean
  J.Camera3D{_, _, _, +fovy, _} = camera
  M.Vector2{+lookx, _} = look
  Body{+position, _, _, +grounded} = body
  M.Vector3{+px, +py, +pz} = position
  +tall = M.Math.lerp(height, Bool.pick(F32, crouch, 0.0, 1.0), (20.0 * dt : F32))
  +walking = grounded && (Bool.not(F32.is_eq(forward, 0.0)) || Bool.not(F32.is_eq(side, 0.0)))
  +timer = Bool.pick(F32, walking, (head + dt * 3.0 : F32), head)
  +pace = M.Math.lerp(walk, Bool.pick(F32, walking, 1.0, 0.0), (10.0 * dt : F32))
  +leaned = {M.Vector2{M.Math.lerp(leanx, (side * 0.02 : F32), (10.0 * dt : F32)), M.Math.lerp(leany, (forward * 0.015 : F32), (10.0 * dt : F32))} : M.Vector2}
  update.aimed(state, body, lookx, timer, pace, tall, leaned,
    aim(libm, M.Vector3{px, (py + (0.5 + tall) : F32), pz}, M.Math.lerp(fovy, Bool.pick(F32, walking, 55.0, 60.0), (5.0 * dt : F32)), look, leaned, timer, pace))

def update.moved(+libm: M.Libm, +state: State, +look: M.Vector2, +side: F32, +forward: F32, +crouch: Bool, +dt: F32, body: Maybe<Body>) -> State:
  match body:
    case None{}: refused(state)
    case Some{+b}: update.body(libm, state, look, side, forward, crouch, dt, b)

def axis(+positive: Bool, +negative: Bool) -> F32:
  (Bool.pick(F32, positive, 1.0, 0.0) - Bool.pick(F32, negative, 1.0, 0.0) : F32)

# lookRotation -= / += the mouse delta by the sensitivity (0.001); sideway = D - A, forward = W - S.
def update.at(+libm: M.Libm, +core: J.Core, +state: State, delta: M.Vector2) -> State:
  State{+body, +look, _, _, _, _, _, _} = state
  M.Vector2{+lookx, +looky} = look
  M.Vector2{+dx, +dy} = delta
  +turned = {M.Vector2{(lookx - dx * 0.001 : F32), (looky + dy * 0.001 : F32)} : M.Vector2}
  +side = axis(J.Input.is_key_down(core, J.KeyboardKey.KEY_D()), J.Input.is_key_down(core, J.KeyboardKey.KEY_A()))
  +forward = axis(J.Input.is_key_down(core, J.KeyboardKey.KEY_W()), J.Input.is_key_down(core, J.KeyboardKey.KEY_S()))
  +crouch = J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL())
  +dt = J.Core.get_frame_time(core)
  update.moved(libm, state, turned, side, forward, crouch, dt, moved(libm, body, (lookx - dx * 0.001 : F32), side, forward, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), crouch, dt))

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  (core, update.at(libm, core, state, J.Input.get_mouse_delta(core)))

def tile(drawn: Bool, +x: F32, +z: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match drawn:
    case False{}: frame
    case True{}: J.Draw.plane(frame, M.Vector3{x, 0.0, z}, M.Vector2{5.0, 5.0}, color)

# A row of the floor: x from -25 (odd) to 24; tileColor1 where y and x are odd, LIGHTGRAY where both are even.
def tiles.row(n: Nat, +ix: U32, +odd: Bool, +z: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: tiles.row(p, (ix + 1 : U32), odd, z, tile(Bool.pick(Bool, odd, U32.is_eq((ix % 2 : U32), 0), U32.is_eq((ix % 2 : U32), 1)), ((U32.to_f32(ix) - 25.0) * 5.0 : F32), z,
      Bool.pick(U32, odd, J.Color.rgba(150, 200, 200, 255), J.Color.LIGHTGRAY()), frame))

def tiles(n: Nat, +iy: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: tiles(p, (iy + 1 : U32), tiles.row(50n, 0, U32.is_eq((iy % 2 : U32), 0), ((U32.to_f32(iy) - 25.0) * 5.0 : F32), frame))

def tower(frame: J.Frame, +x: F32, +z: F32) -> J.Frame:
  J.Draw.cube_wires_v(J.Draw.cube_v(frame, M.Vector3{x, 16.0, z}, M.Vector3{16.0, 32.0, 16.0}, J.Color.rgba(150, 200, 200, 255)), M.Vector3{x, 16.0, z}, M.Vector3{16.0, 32.0, 16.0}, J.Color.DARKBLUE())

# DrawLevel: the floor tiles, the four towers and the red sun.
def level(+libm: M.Libm, frame: J.Frame) -> J.Frame:
  f1 = tower(tower(tower(tower(tiles(50n, 0, frame), 16.0, 16.0), F32.neg(16.0), 16.0), F32.neg(16.0), F32.neg(16.0)), 16.0, F32.neg(16.0))
  J.Draw.sphere_for(libm, f1, M.Vector3{300.0, 300.0, 0.0}, 100.0, J.Color.rgba(255, 0, 0, 255))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 15.0, 60.0, 10.0, J.Color.BLACK())

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def speed(body: Body) -> F32:
  Body{_, +velocity, _, _} = body
  M.Vector3{+vx, _, +vz} = velocity
  M.Vector2.length(M.Vector2{vx, vz})

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+body, _, _, _, _, _, +camera, +ok} = state
  f1 = J.Frame.end_mode_3d(level(libm, J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()), camera)))
  f2 = J.Draw.rectangle_lines(J.Draw.rectangle(f1, 5.0, 5.0, 330.0, 75.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 5.0, 5.0, 330.0, 75.0, J.Color.BLUE())
  f3 = J.Draw.text(J.Draw.text(f2, "Camera controls:", 15.0, 15.0, 10.0, J.Color.BLACK()), "- Move keys: W, A, S, D, Space, Left-Ctrl", 15.0, 30.0, 10.0, J.Color.BLACK())
  (core, (state, label(J.Text.format("- Velocity Len: (%06.3f)", [J.TextFloat{speed(body)}]), J.Draw.text(f3, "- Look around: arrow keys or mouse", 15.0, 45.0, 10.0, J.Color.BLACK()))))

# The main loop's body; libm is the profile of the body's and the head's sinf/cosf, the rotations, Vector3Angle and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, (0.0 + (0.5 + 1.0) : F32), 0.0}, M.Vector3.zero(), M.Vector3.zero(), 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def setup.aimed(aim: Maybe<Aim>) -> State:
  match aim:
    case None{}: State{Body{M.Vector3.zero(), M.Vector3.zero(), M.Vector3.zero(), False{}}, M.Vector2.zero(), 0.0, 0.0, 1.0, M.Vector2.zero(), start(), False{}}
    case Some{Aim{+camera, +looky}}: State{Body{M.Vector3.zero(), M.Vector3.zero(), M.Vector3.zero(), False{}}, M.Vector2{0.0, looky}, 0.0, 0.0, 1.0, M.Vector2.zero(), camera, True{}}

# After InitWindow(800, 450): the camera at the standing player (fovy 60) through UpdateCameraFPS, DisableCursor(), SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, setup.aimed(aim(libm, M.Vector3{0.0, (0.0 + (0.5 + 1.0) : F32), 0.0}, 60.0, M.Vector2.zero(), M.Vector2.zero(), 0.0, 0.0))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d camera fps", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
