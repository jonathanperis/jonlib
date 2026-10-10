# raylib [textures] example - image channel, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_channel.c
# (zlib/libpng, Copyright (c) 2024-2025 Bruno Cabral (@brccabral) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The red, green, blue and alpha channels of an image, each extracted with
# ImageFromChannel and masked with the alpha channel (ImageAlphaMask; the
# alpha image is first masked with itself), drawn tinted beside the image
# over a checked background. LoadImage of a .png is the PNG loader
# (Surface.load_png). An image operation Jonlib refuses leaves no textures
# and refuses the frames. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: background, image, red, green, blue, alpha (the drawing order).
type State is Type:
  State{textures: List<Maybe<J.Texture>>}

# image: fudesumiImage; alpha: imageAlpha; parts: the masked channels, newest first.
type Acc is Type:
  Acc{image: Maybe<J.Surface>, alpha: Maybe<J.Surface>, parts: List<Maybe<J.Surface>>}

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def show.pushed(done: List<Maybe<J.Texture>>, r: J.Frame & J.Texture) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, texture) = r
  (frame, Con{Some{texture}, done})

# DrawTexture(backgroundTexture, 0, 0, WHITE); the image at (50, 10) scaled
# 0.8; the channels at half that size, tinted RED, GREEN, BLUE and WHITE.
def show.draw(+libm: M.Libm, frame: J.Frame, texture: J.Texture, +source: J.Rectangle, +fw: F32, +fh: F32, index: U32) -> J.Frame & J.Texture:
  match index:
    case 0: J.Draw.texture(frame, texture, 0.0, 0.0, J.Color.WHITE())
    case 1: J.Draw.texture_pro_for(libm, frame, texture, source, J.Rectangle{50.0, 10.0, fw, fh}, M.Vector2.zero(), 0.0, J.Color.WHITE())
    case 2: J.Draw.texture_pro_for(libm, frame, texture, source, J.Rectangle{410.0, 10.0, (fw / 2.0 : F32), (fh / 2.0 : F32)}, M.Vector2.zero(), 0.0, J.Color.RED())
    case 3: J.Draw.texture_pro_for(libm, frame, texture, source, J.Rectangle{600.0, 10.0, (fw / 2.0 : F32), (fh / 2.0 : F32)}, M.Vector2.zero(), 0.0, J.Color.GREEN())
    case 4: J.Draw.texture_pro_for(libm, frame, texture, source, J.Rectangle{410.0, 230.0, (fw / 2.0 : F32), (fh / 2.0 : F32)}, M.Vector2.zero(), 0.0, J.Color.BLUE())
    case _: J.Draw.texture_pro_for(libm, frame, texture, source, J.Rectangle{600.0, 230.0, (fw / 2.0 : F32), (fh / 2.0 : F32)}, M.Vector2.zero(), 0.0, J.Color.WHITE())

# fudesumiRec = (0, 0, width, height); fudesumiPos is width*0.8f by height*0.8f.
def show.at(+libm: M.Libm, frame: J.Frame, texture: J.Texture, +index: U32) -> J.Frame & J.Texture:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  show.draw(libm, frame, J.Texture{id, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)},
    (U32.to_f32(w) * 0.8 : F32), (U32.to_f32(h) * 0.8 : F32), index)

def show(+libm: M.Libm, +i: U32, acc: J.Frame & List<Maybe<J.Texture>>, texture: Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, done) = acc
  match texture:
    case None{}: (J.Frame.refuse(frame), Con{None{}, done})
    case Some{t}: show.pushed(done, show.at(libm, frame, t, i))

# The textures drawn in order; they come back newest first.
def shown(list: List<Maybe<J.Texture>>, +libm: M.Libm, +i: U32, acc: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  match list:
    case Nil{}: acc
    case Con{texture, rest}: shown(rest, libm, (i + 1 : U32), show(libm, i, acc, texture))

def draw.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (State & J.Frame):
  (frame, reversed) = r
  (core, (State{List.reverse(&1, Maybe<J.Texture>, reversed)}, frame))

# The example does not clear: the background texture covers the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{textures} = state
  match textures:
    case Nil{}: (core, (State{Nil{}}, J.Frame.refuse(frame)))
    case Con{first, rest}: draw.done(core, shown(Con{first, rest}, libm, 0, (frame, Nil{})))

# The main loop's body; libm is the profile of DrawTexturePro's sinf/cosf (rotation 0).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def mask.swapped(pair: J.Surface & J.Surface) -> Maybe<J.Surface> & Maybe<J.Surface>:
  (masked, alpha) = pair
  (Some{alpha}, Some{masked})

def mask.kept(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Maybe<J.Surface> & Maybe<J.Surface>:
  match result:
    case Fail{_}: (None{}, None{})
    case Done{pair}: mask.swapped(pair)

# ImageAlphaMask(&channel, imageAlpha): the alpha image and the masked channel.
def mask(alpha: J.Surface, part: Maybe<J.Surface>) -> Maybe<J.Surface> & Maybe<J.Surface>:
  match part:
    case None{}: (Some{alpha}, None{})
    case Some{p}: mask.kept(J.Surface.alpha_mask(p, alpha))

def step.masked(parts: List<Maybe<J.Surface>>, image: J.Surface, r: Maybe<J.Surface> & Maybe<J.Surface>) -> Acc:
  (alpha, masked) = r
  Acc{Some{image}, alpha, Con{masked, parts}}

def step.made(parts: List<Maybe<J.Surface>>, alpha: J.Surface, r: J.Surface & Maybe<J.Surface>) -> Acc:
  (image, part) = r
  step.masked(parts, image, mask(alpha, part))

# ImageFromChannel(fudesumiImage, selected), masked.
def step(+selected: F32, acc: Acc) -> Acc:
  Acc{image, alpha, parts} = acc
  match image alpha:
    case Some{i} Some{a}: step.made(parts, a, J.Surface.from_channel(i, selected))
    case _ _: Acc{None{}, None{}, Con{None{}, parts}}

def self.first(pair: J.Surface & J.Surface) -> Maybe<J.Surface>:
  (masked, _) = pair
  Some{masked}

def self.kept(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{pair}: self.first(pair)

def self.masked(pair: J.Surface & J.Surface) -> Maybe<J.Surface>:
  (image, copy) = pair
  self.kept(J.Surface.alpha_mask(image, copy))

# ImageAlphaMask(&imageAlpha, imageAlpha): raylib masks with a copy taken first.
def self(part: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match part:
    case None{}: None{}
    case Some{p}: self.masked(J.Surface.copy(p))

def start.made(r: J.Surface & Maybe<J.Surface>) -> Acc:
  (image, part) = r
  Acc{Some{image}, self(part), Nil{}}

# imageAlpha = ImageFromChannel(fudesumiImage, 3), then red, green and blue.
def channels(image: J.Surface) -> Acc:
  step(2.0, step(1.0, step(0.0, start.made(J.Surface.from_channel(image, 3.0)))))

# The images in the example's upload order: image, alpha, red, green, blue and
# GenImageChecked(800, 450, 800/20, 450/20, ORANGE, YELLOW).
def images(acc: Acc) -> List<Maybe<J.Surface>>:
  Acc{image, alpha, parts} = acc
  Con{image, Con{alpha, List.append(&1, Maybe<J.Surface>, List.reverse(&1, Maybe<J.Surface>, parts),
    [J.Surface.create_checked(800, 450, (800 / 20 : U32), (450 / 20 : U32), J.Color.ORANGE(), J.Color.YELLOW())])}}

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

# From the upload order (newest first: background, blue, green, red, alpha,
# image) to the drawing order.
def ordered(list: List<Maybe<J.Texture>>) -> List<Maybe<J.Texture>>:
  match list:
    case Con{background, Con{blue, Con{green, Con{red, Con{alpha, Con{image, Nil{}}}}}}}: [background, image, red, green, blue, alpha]
    case _: Nil{}

def setup.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (J.Frame & State):
  (frame, textures) = r
  (J.Core.set_target_fps(core, 60), (frame, State{ordered(textures)}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{Nil{}}))
    case Done{image}: setup.done(core, uploaded(images(channels(image)), (frame, Nil{})))

# After InitWindow(800, 450): LoadImage("resources/fudesumi.png"), its
# channels, the six textures, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/fudesumi.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image channel", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
