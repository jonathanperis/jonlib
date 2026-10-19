# raylib [shaders] example - rlgl compute, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_rlgl_compute.c (zlib/libpng,
# Copyright (c) 2021-2025 Teddy Astie (@tsnake41)); see LICENSES/raylib.txt.
#
# Conway's game of life in compute shaders and shader storage buffers. rlgl
# compiles those for OpenGL 4.3 only: on the software renderer the shaders
# and buffers are id 0 and every compute call does nothing (docs/RLGL.md,
# docs/SHADERS.md), so the example shows its white 768x768 texture, the
# brush's outline and the frame rate. The shader sources the native example
# reads are never compiled; the port does not read them. SetTargetFPS(0)
# (raylib 6.2; 6.0 set none): frames do not wait. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# brush is brushSize and count transfertBuffer.count (unsigned ints); the ids
# are the two compute programs and the three storage buffers. valid: the
# wheel's and the pointer's int conversions were defined.
type State is Type:
  State{texture: Maybe<J.Texture>, shader: J.Shader, brush: U32, count: U32, logic: U32, transfer: U32, a: U32, b: U32, buffer: U32, valid: Bool}

# The ids loaded so far, the last one first.
type Ids is Type:
  Ids{frame: J.Frame, ids: +List<U32>}

def took(ids: +List<U32>, r: J.Frame & U32) -> Ids:
  (frame, id) = r
  Ids{frame, Con{id, ids}}

# rlLoadShader(code, RL_COMPUTE_SHADER) and rlLoadShaderProgramCompute of it.
def program.linked(ids: +List<U32>, r: J.Frame & U32) -> Ids:
  (frame, +shader) = r
  took(ids, J.Rlgl.load_shader_program_compute(frame, shader))

def program.loaded(loaded: Ids) -> Ids:
  Ids{frame, ids} = loaded
  program.linked(ids, J.Rlgl.load_shader(frame, "", 37305))

# rlLoadShaderBuffer(size, NULL, RL_DYNAMIC_COPY).
def buffer.loaded(loaded: Ids, +size: U32) -> Ids:
  Ids{frame, ids} = loaded
  took(ids, J.Rlgl.load_shader_buffer(frame, size, 35050))

# (float) of a C int held as a two's-complement word.
def int.f32(+x: U32) -> F32:
  Bool.pick(F32, (x >= 2147483648 : U32), F32.neg(U32.to_f32((0 - x : U32))), U32.to_f32(x))

# (int) of a float as a word (the caller checks the range).
def int.of(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.trunc(F32.neg(x))) : U32), F32.to_u32(F32.trunc(x)))

# brushSize += (int)GetMouseWheelMove(); a command is buffered while a button
# is down and fewer than 48 are; otherwise the buffer is sent (count 0) or the
# logic runs and the two buffers swap.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, +shader, +brush, +count, +logic, +transfer, +a, +b, +buffer, +valid} = state
  +wheel = J.Input.get_mouse_wheel_move(core)
  +down = J.Input.is_mouse_button_down(core, 0) || J.Input.is_mouse_button_down(core, 1)
  +adding = down && (count < 48 : U32)
  +swap = Bool.not(adding) && U32.is_eq(count, 0)
  (core, State{texture, shader, (brush + int.of(wheel) : U32), Bool.pick(U32, adding, (count + 1 : U32), 0), logic, transfer, Bool.pick(U32, swap, b, a), Bool.pick(U32, swap, a, b), buffer,
    valid && (wheel > F32.neg(2147483648.0) : F32) && (wheel < 2147483648.0 : F32)})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 668.0, 10.0, fps)))

def draw.fps(result: Maybe<(J.Core & U32)>, state: State, frame: J.Frame, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawRectangleLines(GetMouseX() - brushSize/2, GetMouseY() - brushSize/2, brushSize, brushSize, RED) in unsigned arithmetic.
def brush.at(x: Maybe<U32>, y: Maybe<U32>, +brush: U32, frame: J.Frame) -> J.Frame:
  match x y:
    case Some{+mx} Some{+my}: J.Draw.rectangle_lines(frame, int.f32((mx - brush / 2 : U32)), int.f32((my - brush / 2 : U32)), int.f32(brush), int.f32(brush), J.Color.RED())
    case _ _: J.Frame.refuse(frame)

def refused(valid: Bool, frame: J.Frame) -> J.Frame:
  match valid:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def drawn(r: J.Frame & J.Texture, +core: J.Core, +shader: J.Shader, +brush: U32, +count: U32, +logic: U32, +transfer: U32, +a: U32, +b: U32, +buffer: U32, +valid: Bool) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = brush.at(J.Input.get_mouse_x(core), J.Input.get_mouse_y(core), brush, J.Frame.end_shader_mode(frame))
  f2 = J.Draw.text(f1, "Use Mouse wheel to increase/decrease brush size", 10.0, 10.0, 20.0, J.Color.WHITE())
  draw.fps(J.Core.get_fps(core, J.Core.get_time(core)), State{Some{texture}, shader, brush, count, logic, transfer, a, b, buffer, valid}, refused(valid, f2), core)

# The frame's storage buffer and compute calls (none has a body on the
# software path), rlBindShaderBuffer(ssboA, 1), then the white texture under
# the render shader.
def painted(texture: Maybe<J.Texture>, +core: J.Core, +shader: J.Shader, +brush: U32, +count: U32, +logic: U32, +transfer: U32, +a: U32, +b: U32, +buffer: U32, +valid: Bool, frame: J.Frame) -> J.Core & (State & J.Frame):
  match texture:
    case None{}: (core, (State{None{}, shader, brush, count, logic, transfer, a, b, buffer, valid}, J.Frame.refuse(frame)))
    case Some{t}:
      f1 = J.Rlgl.update_shader_buffer(frame, buffer, 772, 0)
      f2 = J.Rlgl.bind_shader_buffer(J.Rlgl.bind_shader_buffer(J.Rlgl.enable_shader(f1, logic), a, 1), b, 2)
      f3 = J.Rlgl.disable_shader(J.Rlgl.compute_shader_dispatch(f2, 48, 48, 1))
      f4 = J.Frame.clear_background(J.Rlgl.bind_shader_buffer(f3, a, 1), J.Color.BLANK())
      drawn(J.Draw.texture(J.Frame.begin_shader_mode(f4, shader), t, 0.0, 0.0, J.Color.WHITE()), core, shader, brush, count, logic, transfer, a, b, buffer, valid)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +shader, +brush, +count, +logic, +transfer, +a, +b, +buffer, +valid} = state
  painted(texture, core, J.Shader.set_value(shader, J.Shader.get_location(shader, "resolution"), [F32.bits(768.0), F32.bits(768.0)], 1), brush, count, logic, transfer, a, b, buffer, valid, frame)

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.state(texture: Maybe<J.Texture>, +ids: +List<U32>) -> State:
  match ids:
    case Con{+buffer, Con{+b, Con{+a, Con{+transfer, Con{+logic, _}}}}}:
      State{texture, J.Shader.load(None{}, Some{"resources/shaders/glsl430/gol_render.glsl"}), 8, 0, logic, transfer, a, b, buffer, True{}}
    case _: State{texture, J.Shader.load(None{}, Some{"resources/shaders/glsl430/gol_render.glsl"}), 8, 0, 0, 0, 0, 0, 0, False{}}

def setup.uploaded(+core: J.Core, +ids: +List<U32>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 0), (frame, setup.state(texture, ids)))

def setup.image(image: Maybe<J.Surface>, +core: J.Core, +ids: +List<U32>, frame: J.Frame) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 0), (frame, setup.state(None{}, ids)))
    case Some{i}: setup.uploaded(core, ids, J.Texture.load_from_image(frame, i))

def setup.loaded(loaded: Ids, +core: J.Core) -> J.Core & (J.Frame & State):
  Ids{frame, +ids} = loaded
  setup.image(J.Surface.create(768, 768, J.Color.WHITE()), core, ids, frame)

# After InitWindow(768, 768): the logic and transfer compute programs, the
# render shader, three storage buffers (768*768 unsigned ints twice, and the
# 772-byte command buffer), a white texture from GenImageColor and
# SetTargetFPS(0).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(buffer.loaded(buffer.loaded(buffer.loaded(program.loaded(program.loaded(Ids{frame, Nil{}})), 2359296), 2359296), 772), core)

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - rlgl compute", 768, 768, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
