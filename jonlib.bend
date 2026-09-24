# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Rectangle/circle/alpha algorithms adapted from raylib 6.0 rtextures.c.
# Altered Bend implementations; see THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
import Base

# A color is packed RRGGBBAA. Channel conversion follows C unsigned-byte casts.
def Color.rgba(r: U32, g: U32, b: U32, a: U32) -> U32:
  (((r .&. 255) << 24n) .|. ((g .&. 255) << 16n) .|. ((b .&. 255) << 8n) .|. (a .&. 255) : U32)

def Color.red(c: U32) -> U32:
  (c >> 24n : U32)

def Color.green(c: U32) -> U32:
  ((c >> 16n) .&. 255 : U32)

def Color.blue(c: U32) -> U32:
  ((c >> 8n) .&. 255 : U32)

def Color.alpha(c: U32) -> U32:
  (c .&. 255 : U32)

def Color.tint(+source: U32, +tint: U32) -> U32:
  Color.rgba(((Color.red(source) * (Color.red(tint) + 1)) >> 8n : U32),
    ((Color.green(source) * (Color.green(tint) + 1)) >> 8n : U32),
    ((Color.blue(source) * (Color.blue(tint) + 1)) >> 8n : U32),
    ((Color.alpha(source) * (Color.alpha(tint) + 1)) >> 8n : U32))

def Color.blend.channel(dst: U32, src: U32, da: U32, +sa: U32, out: U32) -> U32:
  (((src * sa * 256 + dst * da * (256 - sa)) / out) >> 8n : U32)

def Color.blend.with_alpha(alpha: U32, +dst: U32, +src: U32) -> U32:
  match alpha:
    case 0:
      dst
    case 255:
      src
    case a:
      +sa = (a + 1 : U32)
      +da = Color.alpha(dst)
      +out = ((sa * 256 + da * (256 - sa)) >> 8n : U32)
      Color.rgba(Color.blend.channel(Color.red(dst), Color.red(src), da, sa, out),
        Color.blend.channel(Color.green(dst), Color.green(src), da, sa, out),
        Color.blend.channel(Color.blue(dst), Color.blue(src), da, sa, out), out)

def Color.blend.tinted(dst: U32, +src: U32) -> U32:
  Color.blend.with_alpha(Color.alpha(src), dst, src)

# raylib's integer ColorAlphaBlend, including its 256-based tint/alpha rounding.
def Color.alpha_blend(dst: U32, src: U32, tint: U32) -> U32:
  Color.blend.tinted(dst, Color.tint(src, tint))

# Construct through Surface.create; preserve its dimensions/storage invariant.
type Surface is Type:
  Surface{width: U32, height: U32, pixels: Array<U32>}

def Surface.dimensions(surface: Surface) -> U32 & U32:
  Surface{w, h, _} = surface
  (w, h)

def Surface.capacity(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

def Surface.create.checked(ok: Bool, +w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}}

# The initial profile supports 1..4096 pixels on each axis.
def Surface.create(+w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  Surface.create.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, color)

def Surface.clear(surface: Surface, color: U32) -> Surface:
  Surface{+w, +h, _} = surface
  Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}

def Surface.get.result(w: U32, h: U32, got: Array<U32> & U32) -> Surface & Maybe<&2, U32>:
  (pixels, color) = got
  (Surface{w, h, pixels}, Some{color})

def Surface.get.checked(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: U32, y: U32) -> Surface & Maybe<&2, U32>:
  match ok:
    case False{}:
      (Surface{w, h, pixels}, None{})
    case True{}:
      Surface.get.result(w, h, Array.get(U32, pixels, (y * w + x : U32)))

def Surface.get(surface: Surface, +x: U32, +y: U32) -> Surface & Maybe<&2, U32>:
  Surface{+w, +h, pixels} = surface
  Surface.get.checked(((x < w) && (y < h) : U32), w, h, pixels, x, y)

def Surface.pixel.checked(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: F32, y: F32, color: U32) -> Surface:
  match ok:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      Surface{w, h, Array.set(U32, pixels, (F32.to_u32(y) * w + F32.to_u32(x) : U32), color)}

# Drawing coordinates are finite integral F32 values in the initial profile.
# ImageDrawPixel replaces RGBA bytes; it does not alpha-blend them.
def Surface.draw_pixel(surface: Surface, +x: F32, +y: F32, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  Surface.pixel.checked(((x >= 0.0) && (y >= 0.0) && (x < U32.to_f32(w)) && (y < U32.to_f32(h)) : F32), w, h, pixels, x, y, color)

def Surface.span(n: Nat, +at: U32, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Surface.span(k, (at + 1 : U32), color, Array.set(U32, pixels, at, color))

def Surface.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Surface.rows(k, (at + stride : U32), stride, cols, color, Surface.span(cols, at, color, pixels))

def Surface.rectangle.fill(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: U32, y: U32, +cols: U32, rows: U32, color: U32) -> Surface:
  match ok:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      # raylib writes the first pixel even for an accepted zero-width rectangle;
      # subsequent rows copy zero bytes. Zero height still writes the first row.
      +nr = Bool.pick(U32, U32.is_eq(cols, 0), 1, U32.max(1, rows))
      Surface{w, h, Surface.rows(U32.to_nat(nr), (y * w + x : U32), w,
        U32.to_nat(U32.max(1, cols)), color, pixels)}

def Surface.draw_rectangle(surface: Surface, +x: F32, +y: F32, width: F32, height: F32, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.max(0.0, F32.min(F32.max(0.0, (width + F32.min(0.0, x) : F32)), (U32.to_f32(w) - sx : F32)))
  +ch = F32.max(0.0, F32.min(F32.max(0.0, (height + F32.min(0.0, y) : F32)), (U32.to_f32(h) - sy : F32)))
  Surface.rectangle.fill(((sx < U32.to_f32(w)) && (sy < U32.to_f32(h)) && (sx + cw > 0.0) && (sy + ch > 0.0) : F32),
    w, h, pixels, F32.to_u32(sx), F32.to_u32(sy), F32.to_u32(cw), F32.to_u32(ch), color)

def Surface.circle.loop(fuel: Nat, on: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +error: F32, +color: U32, surface: Surface) -> Surface:
  match fuel on:
    case 0n _:
      surface
    case 1n+k False{}:
      surface
    case 1n+k True{}:
      s0 = Surface.draw_rectangle(surface, (cx - x : F32), (cy + y : F32), (x * 2.0 : F32), 1.0, color)
      s1 = Surface.draw_rectangle(s0, (cx - x : F32), (cy - y : F32), (x * 2.0 : F32), 1.0, color)
      s2 = Surface.draw_rectangle(s1, (cx - y : F32), (cy + x : F32), (y * 2.0 : F32), 1.0, color)
      s3 = Surface.draw_rectangle(s2, (cx - y : F32), (cy - x : F32), (y * 2.0 : F32), 1.0, color)
      +nx = (x + 1.0 : F32)
      +down = (error > 0.0 : F32)
      +ny = Bool.pick(F32, down, (y - 1.0 : F32), y)
      ne = Bool.pick(F32, down, (error + 4.0 * (nx - ny) + 10.0 : F32), (error + 4.0 * nx + 6.0 : F32))
      Surface.circle.loop(k, (ny >= nx : F32), cx, cy, nx, ny, ne, color, s3)

# Midpoint scanlines match raylib ImageDrawCircle, including its edge coverage.
def Surface.draw_circle(surface: Surface, cx: F32, cy: F32, +radius: U32, color: U32) -> Surface:
  +r = U32.to_f32(radius)
  Surface.circle.loop(1n+U32.to_nat(radius), True{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

# Export consumes the surface and excludes power-of-two storage padding.
def Surface.colors(surface: Surface) -> List<U32>:
  Surface{w, h, pixels} = surface
  List.take(&1, U32, Array.to_list(~U32, pixels), U32.to_nat((w * h : U32)))

def Surface.copy.result(+w: U32, +h: U32, pair: Array<U32> & Array<U32>) -> Surface & Surface:
  (a, b) = pair
  (Surface{w, h, a}, Surface{w, h, b})

def Surface.copy(surface: Surface) -> Surface & Surface:
  Surface{w, h, pixels} = surface
  Surface.copy.result(w, h, Array.clone(U32, pixels))

def Surface.flip.index(horizontal: Bool, +i: U32, +w: U32, h: U32) -> U32:
  +x = (i % w : U32)
  +y = (i / w : U32)
  Bool.pick(U32, horizontal, (y * w + w - 1 - x : U32), ((h - 1 - y) * w + x : U32))

def Surface.flip.loop(more: Nat, +i: U32, +w: U32, +h: U32, +horizontal: Bool, output: Array<U32>, got: Array<U32> & U32) -> Array<U32>:
  match more got:
    case 0n Tuple{_, color}:
      Array.set(U32, output, i, color)
    case 1n+k Tuple{source, color}:
      +next = (i + 1 : U32)
      Surface.flip.loop(k, next, w, h, horizontal, Array.set(U32, output, i, color),
        Array.get(U32, source, Surface.flip.index(horizontal, next, w, h)))

def Surface.flip(surface: Surface, +horizontal: Bool) -> Surface:
  Surface{+w, +h, pixels} = surface
  +count = (w * h : U32)
  Surface{w, h, Surface.flip.loop(U32.to_nat((count - 1 : U32)), 0, w, h, horizontal,
    Array.new(U32, Surface.capacity(count), 0),
    Array.get(U32, pixels, Surface.flip.index(horizontal, 0, w, h)))}

def Surface.flip_horizontal(surface: Surface) -> Surface:
  Surface.flip(surface, True{})

def Surface.flip_vertical(surface: Surface) -> Surface:
  Surface.flip(surface, False{})

# Base.Image contains RGB colors. Alpha is discarded, not composited.
def Surface.tree.leaf(got: Array<U32> & U32) -> Array<U32> & Image:
  (pixels, color) = got
  (pixels, Pix{(color >> 8n : U32)})

def Surface.tree.pixel(inside: Bool, +w: U32, x: U32, y: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match inside:
    case False{}:
      (pixels, Pix{0})
    case True{}:
      Surface.tree.leaf(Array.get(U32, pixels, (y * w + x : U32)))

def Surface.tree.bind(got: Array<U32> & Image, next: Array<U32> -> Image -> (Array<U32> & Image)) -> Array<U32> & Image:
  (pixels, image) = got
  next(pixels, image)

def Surface.tree(+depth: Nat, +size: U32, +x: U32, +y: U32, +w: U32, +h: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match depth:
    case 0n:
      Surface.tree.pixel(((x < w) && (y < h) : U32), w, x, y, pixels)
    case 1n+k:
      +half = (size / 2 : U32)
      Surface.tree.bind(Surface.tree(k, half, x, y, w, h, pixels), p0 => tl =>
        Surface.tree.bind(Surface.tree(k, half, (x + half : U32), y, w, h, p0), p1 => tr =>
          Surface.tree.bind(Surface.tree(k, half, x, (y + half : U32), w, h, p1), p2 => bl =>
            Surface.tree.bind(Surface.tree(k, half, (x + half : U32), (y + half : U32), w, h, p2), p3 => br =>
              (p3, Qua{tl, tr, bl, br})))))

def Surface.to_image(surface: Surface) -> Image:
  Surface{+w, +h, pixels} = surface
  +depth = Surface.capacity(U32.max(w, h))
  Pair.snd(Array<U32>, Image, Surface.tree(depth, U32.shln(1, depth), 0, 0, w, h, pixels))

# Portable, inspectable P3 PPM output for headless programs. Alpha is discarded.
def Surface.ppm.colors(colors: List<U32>) -> String:
  match colors:
    case Nil{}:
      ""
    case Con{+color, rest}:
      U32.show(Color.red(color)) ++ " " ++ U32.show(Color.green(color)) ++ " "
        ++ U32.show(Color.blue(color)) ++ "\n" ++ Surface.ppm.colors(rest)

def Surface.to_ppm(surface: Surface) -> String:
  Surface{+w, +h, pixels} = surface
  "P3\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n"
    ++ Surface.ppm.colors(Surface.colors(Surface{w, h, pixels}))

def Surface.ppm.written(result: File & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, Unit>):
  (file, status) = result
  do IO<Result<&1, &1, U32 & String, Unit>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, U32 & String, Unit>, status)

def Surface.ppm.opened(text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write(file, text), Surface.ppm.written)

def Surface.write_ppm(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.ppm.opened(Surface.to_ppm(surface)))
