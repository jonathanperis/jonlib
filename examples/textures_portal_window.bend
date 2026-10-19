# raylib [textures] example - portal window, ported to Jonlib.
# Adapted from raylib 6.2 examples/textures/textures_portal_window.c
# (zlib/libpng, Copyright (c) 2025 PanicTitan (@PanicTitan)); see
# LICENSES/raylib.txt.
#
# A golden archway whose opening is an rlgl quad textured with a 480x640
# render texture (rlSetTexture, rlBegin(RL_QUADS)), into which a second
# scene, sixty units away, is drawn each frame through BeginPortalMode3D: an
# off-axis frustum built from the eye and the archway's corners
# (rlMatrixMode(RL_PROJECTION), rlPushMatrix, rlSetMatrixProjection of
# MatrixFrustum) and a view fixed to the archway's plane (rlLoadIdentity,
# rlMultMatrixf of MatrixLookAt). On the software renderer
# rlSetMatrixProjection changes nothing (it only sets the OpenGL 3.3/ES2
# projection): the second scene keeps BeginTextureMode's orthographic
# projection, whose depth range clips it, there and here, so the archway
# shows the render texture's clear color. The free camera follows the mouse
# and W/A/S/D (DisableCursor only sets the flag). The perspective needs the
# libm profile's binary64 tan (docs/PERSPECTIVE.md); UpdateCamera, the
# spheres and the orbiting cubes' sinf/cosf of the clock follow its profile
# (docs/SINCOSF.md); a refused camera, clock or angle refuses the frame and
# every later one. See docs/RLGL.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: nothing refused so far; time: (float)GetTime() read in the update.
type Scene is Data:
  Scene{valid: Bool, camera: J.Camera3D, time: F32}

# view: portalView, held by the frame while it is drawn into or bound.
type State is Type:
  State{scene: Scene, view: Maybe<J.RenderTexture>}

# The positions computed from the clock, and whether every sinf/cosf answered.
type Spots is Data:
  Spots{valid: Bool, list: +List<M.Vector3>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 2.5, 7.0}, M.Vector3{0.0, 1.8, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# archBottomLeft, archBottomRight and archTopLeft.
def arch.bottom_left() -> M.Vector3:
  M.Vector3{F32.neg(1.5), 0.0, 0.0}

def arch.bottom_right() -> M.Vector3:
  M.Vector3{1.5, 0.0, 0.0}

def arch.top_left() -> M.Vector3:
  M.Vector3{F32.neg(1.5), 4.0, 0.0}

# portalA and portalB.
def portal.a() -> M.Vector3:
  M.Vector3{0.0, 0.0, 0.0}

def portal.b() -> M.Vector3:
  M.Vector3{0.0, 0.0, F32.neg(60.0)}

# A refusal stays: once invalid, the camera and the clock no longer move.
def kept(+valid: Bool, +camera: J.Camera3D, +time: F32, moved: Maybe<J.Camera3D>, clock: Maybe<F32>) -> Scene:
  match moved clock:
    case Some{+c} Some{+t}: Scene{valid, c, t}
    case _ _: Scene{False{}, camera, time}

# UpdateCamera(&camera, CAMERA_FREE); float time = (float)GetTime().
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+scene, view} = state
  Scene{+valid, +camera, +time} = scene
  (core, State{kept(valid, camera, time, J.Camera.update_for(M.Uncontracted{}, libm, core, camera, J.CameraMode.CAMERA_FREE()),
    M.Float64.to_f32(J.Core.get_time(core))), view})

# BeginPortalMode3D(eye, bottomLeft, bottomRight, topLeft, nearPlane, farPlane):
# the window's right, up and normal; dist = -dot(toBL, normal), at least 0.01f;
# rlSetMatrixProjection(MatrixFrustum(dot(right, toBL)*scale, dot(right, toBR)*scale,
# dot(up, toBL)*scale, dot(up, toTL)*scale, near, far)) with scale = near/dist (the
# products are floats, promoted to double); then the modelview
# MatrixLookAt(eye, eye - normal, up) and the depth test.
def portal.begin(+eye: M.Vector3, +bl: M.Vector3, +br: M.Vector3, +tl: M.Vector3, +near: F32, +far: F32, frame: J.Frame) -> J.Frame:
  +right = M.Vector3.normalize(M.Vector3.subtract(br, bl))
  +up = M.Vector3.normalize(M.Vector3.subtract(tl, bl))
  +normal = M.Vector3.normalize(M.Vector3.cross_product(right, up))
  +to_bl = M.Vector3.subtract(bl, eye)
  +to_br = M.Vector3.subtract(br, eye)
  +to_tl = M.Vector3.subtract(tl, eye)
  +d = F32.neg(M.Vector3.dot_product(to_bl, normal))
  +dist = Bool.pick(F32, (d < 0.01 : F32), 0.01, d)
  +scale = (near / dist : F32)
  +projection = M.Matrix.frustum(M.Float64.from_f32((M.Vector3.dot_product(right, to_bl) * scale : F32)), M.Float64.from_f32((M.Vector3.dot_product(right, to_br) * scale : F32)),
    M.Float64.from_f32((M.Vector3.dot_product(up, to_bl) * scale : F32)), M.Float64.from_f32((M.Vector3.dot_product(up, to_tl) * scale : F32)),
    M.Float64.from_f32(near), M.Float64.from_f32(far))
  f1 = J.Rlgl.set_matrix_projection(J.Rlgl.push_matrix(J.Rlgl.matrix_mode(J.Rlgl.draw_render_batch_active(frame), 5889)), projection)
  J.Rlgl.enable_depth_test(J.Rlgl.mult_matrixf(J.Rlgl.load_identity(J.Rlgl.matrix_mode(f1, 5888)), M.Matrix.look_at(eye, M.Vector3.subtract(eye, normal), up)))

# EndPortalMode3D: the projection popped, an identity modelview, no depth test.
def portal.end(frame: J.Frame) -> J.Frame:
  J.Rlgl.disable_depth_test(J.Rlgl.load_identity(J.Rlgl.matrix_mode(J.Rlgl.pop_matrix(J.Rlgl.matrix_mode(J.Rlgl.draw_render_batch_active(frame), 5889)), 5888)))

# angle = time*1.5f + i*(PI/2.0f).
def angle(+time: F32, +i: U32) -> F32:
  (time * 1.5 + U32.to_f32(i) * (M.Math.PI() / 2.0) : F32)

# pos = Vector3Add(portalB, (sinf(angle)*2.5f, 2.0f + cosf(time*3.0f + i)*0.5f, -4.0f + cosf(angle)*2.5f)).
def spot(+rest: Spots, sine: Maybe<F32>, bob: Maybe<F32>, cosine: Maybe<F32>) -> Spots:
  Spots{+valid, +list} = rest
  match sine bob cosine:
    case Some{+s} Some{+b} Some{+c}: Spots{valid, Con{M.Vector3.add(portal.b(), M.Vector3{(s * 2.5 : F32), (2.0 + b * 0.5 : F32), (F32.neg(4.0) + c * 2.5 : F32)}), list}}
    case _ _ _: Spots{False{}, list}

# The orbiting cubes i, i + 1, ... (n of them), in the loop's order.
def cubes(n: Nat, +libm: M.Libm, +time: F32, +i: U32) -> Spots:
  match n:
    case 0n: Spots{True{}, Nil{}}
    case 1n+p: spot(cubes(p, libm, time, (i + 1 : U32)), M.Libm.sin(libm, angle(time, i)), M.Libm.cos(libm, (time * 3.0 + U32.to_f32(i) : F32)),
      M.Libm.cos(libm, angle(time, i)))

# corePos = Vector3Add(portalB, (0, 2.0f + sinf(time*2.5f)*0.4f, -4.0f)).
def orb(sine: Maybe<F32>) -> Maybe<M.Vector3>:
  match sine:
    case None{}: None{}
    case Some{+s}: Some{M.Vector3.add(portal.b(), M.Vector3{0.0, (2.0 + s * 0.4 : F32), F32.neg(4.0)})}

# DrawCube(pos, 0.5f, 0.5f, 0.5f, LIME); DrawCubeWires(pos, 0.52f, 0.52f, 0.52f, DARKGREEN).
def cubes.drawn(list: +List<M.Vector3>, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+pos, rest}: cubes.drawn(rest, J.Draw.cube_wires(J.Draw.cube(frame, pos, 0.5, 0.5, 0.5, J.Color.LIME()), pos, 0.52, 0.52, 0.52, J.Color.DARKGREEN()))

# DrawSphere(corePos, 1.2f, PURPLE); DrawSphereWires(corePos, 1.25f, 16, 16, MAGENTA); the cubes.
def dimension.at(valid: Bool, +libm: M.Libm, +list: +List<M.Vector3>, center: Maybe<M.Vector3>, frame: J.Frame) -> J.Frame:
  match valid center:
    case True{} Some{+o}: cubes.drawn(list, J.Draw.sphere_wires_for(libm, J.Draw.sphere_for(libm, frame, o, 1.2, J.Color.PURPLE()), o, 1.25, 16.0, 16.0, J.Color.MAGENTA()))
    case _ _: J.Frame.refuse(frame)

# Dimension B after its DrawGrid(30, 0.8f).
def dimension(+libm: M.Libm, +time: F32, +spots: Spots, frame: J.Frame) -> J.Frame:
  Spots{+valid, +list} = spots
  dimension.at(valid, libm, list, orb(M.Libm.sin(libm, (time * 2.5 : F32))), frame)

# The opening: rlBegin(RL_QUADS); rlColor4ub(255, 255, 255, 255); rlNormal3f(0, 0, 1); the corners
# archBottomLeft (0, 0), archBottomRight (1, 0), (archBottomRight.x, 4.0f, archBottomRight.z) (1, 1),
# archTopLeft (0, 1); rlEnd().
def opening(frame: J.Frame) -> J.Frame:
  f1 = J.Rlgl.normal3f(J.Rlgl.color4ub(J.Rlgl.begin(frame, 7), 255, 255, 255, 255), 0.0, 0.0, 1.0)
  f2 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(f1, 0.0, 0.0), F32.neg(1.5), 0.0, 0.0), 1.0, 0.0), 1.5, 0.0, 0.0)
  J.Rlgl.end(J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(f2, 1.0, 1.0), 1.5, 4.0, 0.0), 0.0, 1.0), F32.neg(1.5), 4.0, 0.0))

# The side pillars, the archway frame, its base and the backing wall.
def archway(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.cube_wires(J.Draw.cube(frame, M.Vector3{F32.neg(3.5), 2.0, 0.0}, 0.8, 4.0, 0.8, J.Color.DARKGRAY()), M.Vector3{F32.neg(3.5), 2.0, 0.0}, 0.8, 4.0, 0.8, J.Color.ORANGE())
  f2 = J.Draw.cube_wires(J.Draw.cube(f1, M.Vector3{3.5, 2.0, 0.0}, 0.8, 4.0, 0.8, J.Color.DARKGRAY()), M.Vector3{3.5, 2.0, 0.0}, 0.8, 4.0, 0.8, J.Color.ORANGE())
  f3 = J.Draw.cube(J.Draw.cube_wires(f2, M.Vector3{0.0, 2.0, 0.0}, 3.2, 4.2, 0.2, J.Color.GOLD()), M.Vector3{0.0, 0.05, 0.0}, 3.4, 0.1, 0.6, J.Color.MAROON())
  J.Draw.cube(f3, M.Vector3{0.0, 2.0, F32.neg(0.05)}, 3.1, 4.1, 0.05, J.Color.MAROON())

def bound(r: J.Frame & Maybe<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

# portalView again, from the texture rlSetTexture(0) hands back.
def reattached(+id: U32, +depth: U32, held: Maybe<J.Texture>) -> Maybe<J.RenderTexture>:
  match held:
    case None{}: None{}
    case Some{t}: Some{J.RenderTexture{id, t, depth}}

# EndMode3D(); the HUD overlay.
def draw.shown(+core: J.Core, +scene: Scene, +id: U32, +depth: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, held) = r
  f1 = J.Draw.rectangle_lines(J.Draw.rectangle(J.Frame.end_mode_3d(frame), 15.0, 15.0, 520.0, 100.0, J.Color.with_alpha(J.Color.BLACK(), 0.75)), 15.0, 15.0, 520.0, 100.0, J.Color.GOLD())
  f2 = J.Draw.text(J.Draw.text(f1, "PORTAL WINDOW", 28.0, 25.0, 20.0, J.Color.GOLD()), "Look through the golden arch into Dimension B", 28.0, 52.0, 20.0, J.Color.RAYWHITE())
  (core, (State{scene, reattached(id, depth, held)}, J.Draw.text(f2, "Controls: Mouse to look | WASD to move", 28.0, 80.0, 20.0, J.Color.GRAY())))

# ClearBackground(RAYWHITE); BeginMode3D(camera); DrawGrid(20, 1.0f); the archway;
# rlSetTexture(portalView.texture.id); the opening; rlSetTexture(0).
def draw.world(+libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  Scene{_, +camera, _} = scene
  J.RenderTexture{+id, texture, +depth} = target
  f1 = archway(J.Draw.grid(J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera), 20.0, 1.0))
  draw.shown(core, scene, id, depth, J.Rlgl.set_texture(opening(bound(J.Rlgl.set_texture(f1, Some{texture}))), None{}))

def draw.screen(+libm: M.Libm, +core: J.Core, +scene: Scene, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, view) = r
  match view:
    case None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))
    case Some{v}: draw.world(libm, core, scene, frame, v)

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# BeginTextureMode(portalView); ClearBackground((10, 5, 20, 255)); BeginPortalMode3D(eyeInB, blInB, brInB,
# tlInB, 0.05f, 100.0f) with the eye and corners shifted by portalB - portalA; DrawGrid(30, 0.8f);
# Dimension B; EndPortalMode3D(); EndTextureMode().
def draw.portal(+libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  Scene{_, +camera, +time} = scene
  J.Camera3D{+position, _, _, _, _} = camera
  +offset = M.Vector3.subtract(portal.b(), portal.a())
  f1 = J.Frame.clear_background(J.Frame.begin_texture_mode(frame, target), J.Color.rgba(10, 5, 20, 255))
  f2 = J.Draw.grid(portal.begin(M.Vector3.add(position, offset), M.Vector3.add(arch.bottom_left(), offset), M.Vector3.add(arch.bottom_right(), offset),
    M.Vector3.add(arch.top_left(), offset), 0.05, 100.0, f1), 30.0, 0.8)
  draw.screen(libm, core, scene, J.Frame.end_texture_mode(portal.end(dimension(libm, time, cubes(4n, libm, time, 0), f2))))

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, frame: J.Frame, view: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid view:
    case True{} Some{v}: draw.portal(libm, core, scene, frame, v)
    case True{} None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))
    case False{} Some{v}: (core, (State{scene, Some{v}}, J.Frame.refuse(frame)))
    case False{} None{}: (core, (State{scene, None{}}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+scene, view} = state
  Scene{+valid, _, _} = scene
  draw.valid(valid, libm, core, scene, frame, view)

# The main loop's body; libm is the profile of UpdateCamera's, the spheres' and the clock angles' sinf/cosf and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.made(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, view) = r
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{Scene{True{}, start(), 0.0}, view}))

# After InitWindow(800, 450): the camera, portalView = LoadRenderTexture(480, 640), DisableCursor(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.made(core, J.RenderTexture.load(frame, 480, 640))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - portal window", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
