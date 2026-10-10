# raylib [textures] example - image kernel, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_kernel.c
# (zlib/libpng, Copyright (c) 2015-2025 Karim Salem (@kimo-s)); see
# LICENSES/raylib.txt.
#
# An image sharpened, edge-filtered (Sobel) and blurred (a Gaussian kernel
# six times) with ImageKernelConvolution, the four versions cropped to 200
# pixels and drawn side by side. NormalizeKernel divides a kernel by its sum
# unless that is zero (the Sobel kernel). LoadImage of a .png is the PNG
# loader (Surface.load_png).
#
# The native example is undefined behavior in C: ImageKernelConvolution
# converts each alpha sum times 255 with an (unsigned char) cast, and the
# sharpen kernel sums to 2 on the image's first and last rows (510.0f), the
# Sobel kernel to -2 on its first pixel. Surface.kernel_convolution refuses
# such kernels (InvalidKernel, docs/CONVOLUTION.md), so this port leaves
# those images without a texture and refuses every frame; nothing of it is
# compared with the native example. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: sharpened, Sobel, Gaussian, original (the drawing order).
type State is Type:
  State{textures: List<Maybe<J.Texture>>}

def total(kernel: +List<F32>, +sum: F32) -> F32:
  match kernel:
    case Nil{}: sum
    case Con{+k, rest}: total(rest, (sum + k : F32))

def divided(kernel: +List<F32>, +sum: F32) -> +List<F32>:
  match kernel:
    case Nil{}: Nil{}
    case Con{+k, rest}: Con{(k / sum : F32), divided(rest, sum)}

# NormalizeKernel: kernel[i] /= sum when sum != 0.
def normalized.by(+kernel: +List<F32>, +sum: F32) -> +List<F32>:
  Bool.pick(+List<F32>, F32.is_ne(sum, 0.0), divided(kernel, sum), kernel)

def normalized(+kernel: +List<F32>) -> +List<F32>:
  normalized.by(kernel, total(kernel, 0.0))

def gaussian() -> +List<F32>:
  normalized([1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0])

def sobel() -> +List<F32>:
  normalized([1.0, 0.0, F32.neg(1.0), 2.0, 0.0, F32.neg(2.0), 1.0, 0.0, F32.neg(1.0)])

def sharpen() -> +List<F32>:
  normalized([0.0, F32.neg(1.0), 0.0, F32.neg(1.0), 5.0, F32.neg(1.0), 0.0, F32.neg(1.0), 0.0])

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def show.pushed(done: List<Maybe<J.Texture>>, r: J.Frame & J.Texture) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, texture) = r
  (frame, Con{Some{texture}, done})

# DrawTexture(texture, 200*i, 0, WHITE).
def show(+i: U32, acc: J.Frame & List<Maybe<J.Texture>>, texture: Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, done) = acc
  match texture:
    case None{}: (J.Frame.refuse(frame), Con{None{}, done})
    case Some{t}: show.pushed(done, J.Draw.texture(frame, t, U32.to_f32((200 * i : U32)), 0.0, J.Color.WHITE()))

# The textures drawn in order; they come back newest first.
def shown(list: List<Maybe<J.Texture>>, +i: U32, acc: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  match list:
    case Nil{}: acc
    case Con{texture, rest}: shown(rest, (i + 1 : U32), show(i, acc, texture))

def draw.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (State & J.Frame):
  (frame, reversed) = r
  (core, (State{List.reverse(&1, Maybe<J.Texture>, reversed)}, frame))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{textures} = state
  match textures:
    case Nil{}: (core, (State{Nil{}}, J.Frame.refuse(frame)))
    case Con{first, rest}: draw.done(core, shown(Con{first, rest}, 0, (J.Frame.clear_background(frame, J.Color.RAYWHITE()), Nil{})))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def kept(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

# ImageKernelConvolution(&image, kernel, 9).
def convolved(image: Maybe<J.Surface>, +kernel: +List<F32>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: kept(J.Surface.kernel_convolution(i, kernel))

def repeated(n: Nat, image: Maybe<J.Surface>, +kernel: +List<F32>) -> Maybe<J.Surface>:
  match n:
    case 0n: image
    case 1n+p: repeated(p, convolved(image, kernel), kernel)

# ImageCrop(&image, (0, 0, 200, 450)).
def cropped(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: kept(J.Surface.crop(i, J.Rectangle{0.0, 0.0, 200.0, 450.0}))

# The images in the example's upload order: original, sharpened, Sobel, Gaussian.
def made.third(sharp: Maybe<J.Surface>, edges: Maybe<J.Surface>, pair: J.Surface & J.Surface) -> List<Maybe<J.Surface>>:
  (image, copy) = pair
  [cropped(Some{image}), cropped(sharp), cropped(edges), cropped(repeated(6n, Some{copy}, gaussian()))]

def made.second(sharp: Maybe<J.Surface>, pair: J.Surface & J.Surface) -> List<Maybe<J.Surface>>:
  (image, copy) = pair
  made.third(sharp, convolved(Some{copy}, sobel()), J.Surface.copy(image))

def made.first(pair: J.Surface & J.Surface) -> List<Maybe<J.Surface>>:
  (image, copy) = pair
  made.second(convolved(Some{copy}, sharpen()), J.Surface.copy(image))

def made(image: J.Surface) -> List<Maybe<J.Surface>>:
  made.first(J.Surface.copy(image))

def uploaded.pushed(acc: List<Maybe<J.Texture>>, r: J.Frame & Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, texture) = r
  (frame, Con{texture, acc})

def uploaded.push(r: J.Frame & List<Maybe<J.Texture>>, image: Maybe<J.Surface>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, acc) = r
  match image:
    case None{}: (frame, Con{None{}, acc})
    case Some{i}: uploaded.pushed(acc, J.Texture.load_from_image(frame, i))

def uploaded(images: List<Maybe<J.Surface>>, r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  match images:
    case Nil{}: r
    case Con{i, rest}: uploaded(rest, uploaded.push(r, i))

# From the upload order (newest first: Gaussian, Sobel, sharpened, original) to the drawing order.
def ordered(list: List<Maybe<J.Texture>>) -> List<Maybe<J.Texture>>:
  match list:
    case Con{blurred, Con{edges, Con{sharp, Con{image, Nil{}}}}}: [sharp, edges, blurred, image]
    case _: Nil{}

def setup.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (J.Frame & State):
  (frame, textures) = r
  (J.Core.set_target_fps(core, 60), (frame, State{ordered(textures)}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{Nil{}}))
    case Done{image}: setup.done(core, uploaded(made(image), (frame, Nil{})))

# After InitWindow(800, 450): LoadImage("resources/cat.png"), the three
# filtered copies, the four textures, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cat.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image kernel", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
