# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Image/color algorithms adapted from raylib 6.0 rtextures.c; shared math in Jonmath.
# Collision queries adapted from the same release's rshapes.c.
# 3D collision queries adapted from rmodels.c.
# Altered Bend implementations; see THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
import Base
import ./jonmath.bend as M
import ./src/resample.bend as Resample
import ./src/qoi.bend as Qoi
import ./src/gradients.bend as Gradients
import ./src/trig.bend as Trig
import ./src/rotation.bend as Rotation
import ./src/fused.bend as Fused
import ./src/random.bend as Rng
import ./src/cellular.bend as Cellular
import ./src/perlin.bend as Perlin
import ./src/spline.bend as SplineNumeric
import ./src/dither.bend as Dither
import ./src/formats.bend as Formats
import ./src/bmp.bend as Bmp
import ./src/tga.bend as Tga
import ./src/pnm.bend as Pnm
import ./src/psd.bend as Psd
import ./src/pic.bend as Pic
import ./src/gif.bend as Gif
import ./src/gif_animation.bend as GifAnimation
import ./src/hdr.bend as Hdr
import ./src/image_code.bend as ImageCode
import ./src/blur.bend as Blur
import ./src/convolution.bend as Convolution
import ./src/base64.bend as Base64Codec
import ./src/checksum.bend as Checksums
import ./src/sha.bend as Sha
import ./src/inflate.bend as Inflate
import ./src/sdeflate.bend as Sdeflate
import ./src/png.bend as Png
import ./src/png_encode.bend as PngEncode

def Compression.decompress(bytes: +List<U32>, maximum: U32) -> Maybe<List<U32>>:
  Inflate.decompress(True{}, bytes, maximum)

def Compression.compress(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Sdeflate.compress(bytes)

type Base64.Encoded is Data:
  Base64Encoded{size: U32, text: String}

def Base64.encoded(result: Maybe<&2, Base64Codec.Encoded>) -> Maybe<&2, Base64.Encoded>:
  match result:
    case None{}: None{}
    case Some{Base64Codec.Encoded{size, text}}: Some{Base64Encoded{size, text}}

def Base64.encode(bytes: +List<U32>) -> Maybe<&2, Base64.Encoded>:
  Base64.encoded(Base64Codec.encode(bytes))

def Base64.decode(text: String) -> Maybe<&2, +List<U32>>:
  Base64Codec.decode(text)

def Checksum.crc32.checked(size: Maybe<&2, U32>, bytes: +List<U32>) -> Maybe<&2, U32>:
  match size:
    case None{}: None{}
    case Some{_}: Some{(PngEncode.crc(bytes, 4294967295) .^. 4294967295 : U32)}

def Checksum.crc32(+bytes: +List<U32>) -> Maybe<&2, U32>:
  Checksum.crc32.checked(Checksums.input_size(bytes, 0, True{}), bytes)

def Checksum.md5(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Checksums.md5(bytes)

def Checksum.sha1(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Sha.hash(False{}, bytes)

def Checksum.sha256(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Sha.hash(True{}, bytes)

type Spline.Reference is Data:
  UncontractedSpline{}
  FusedSpline{}

def Spline.fused(reference: Spline.Reference) -> Bool:
  match reference:
    case UncontractedSpline{}: False{}
    case FusedSpline{}: True{}

def Spline.linear_for(reference: Spline.Reference, start: M.Vector2, end: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{x, y} = start
  M.Vector2{u, v} = end
  +fused = Spline.fused(reference)
  M.Vector2{SplineNumeric.linear(fused, x, u, t), SplineNumeric.linear(fused, y, v, t)}

def Spline.linear(start: M.Vector2, end: M.Vector2, t: F32) -> M.Vector2:
  Spline.linear_for(UncontractedSpline{}, start, end, t)

def Spline.basis_for(reference: Spline.Reference, first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = first
  M.Vector2{bx, by} = second
  M.Vector2{cx, cy} = third
  M.Vector2{dx, dy} = fourth
  +fused = Spline.fused(reference)
  M.Vector2{SplineNumeric.basis(fused, ax, bx, cx, dx, t), SplineNumeric.basis(fused, ay, by, cy, dy, t)}

def Spline.basis(first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  Spline.basis_for(UncontractedSpline{}, first, second, third, fourth, t)

def Spline.catmull_rom_for(reference: Spline.Reference, first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = first
  M.Vector2{bx, by} = second
  M.Vector2{cx, cy} = third
  M.Vector2{dx, dy} = fourth
  +fused = Spline.fused(reference)
  +weights = SplineNumeric.catmull_weights(fused, t)
  M.Vector2{SplineNumeric.catmull(fused, weights, ax, bx, cx, dx), SplineNumeric.catmull(fused, weights, ay, by, cy, dy)}

def Spline.catmull_rom(first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  Spline.catmull_rom_for(UncontractedSpline{}, first, second, third, fourth, t)

def Spline.bezier_quad_for(reference: Spline.Reference, start: M.Vector2, control: M.Vector2, end: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = start
  M.Vector2{bx, by} = control
  M.Vector2{cx, cy} = end
  +fused = Spline.fused(reference)
  M.Vector2{SplineNumeric.bezier_quad(fused, ax, bx, cx, t), SplineNumeric.bezier_quad(fused, ay, by, cy, t)}

def Spline.bezier_quad(start: M.Vector2, control: M.Vector2, end: M.Vector2, t: F32) -> M.Vector2:
  Spline.bezier_quad_for(UncontractedSpline{}, start, control, end, t)

type BoundingBox is Data:
  BoundingBox{min: M.Vector3, max: M.Vector3}

type Rectangle is Data:
  Rectangle{x: F32, y: F32, width: F32, height: F32}

type Collision.Arithmetic is Data:
  UncontractedCollision{}
  FusedCollision{}

def Collision.multiply_add(arithmetic: Collision.Arithmetic, a: F32, b: F32, c: F32) -> F32:
  match arithmetic:
    case UncontractedCollision{}: (a * b + c : F32)
    case FusedCollision{}: Fused.multiply_add(a, b, c)

def Collision.spheres(left: M.Vector3, radius: F32, right: M.Vector3, other_radius: F32) -> Bool:
  +sum = (radius + other_radius : F32)
  (M.Vector3.distance_sqr(left, right) <= sum * sum : F32)

def Collision.boxes(left: BoundingBox, right: BoundingBox) -> Bool:
  BoundingBox{M.Vector3{ax, ay, az}, M.Vector3{bx, by, bz}} = left
  BoundingBox{M.Vector3{cx, cy, cz}, M.Vector3{dx, dy, dz}} = right
  ((bx >= cx) && (ax <= dx) && (by >= cy) && (ay <= dy) && (bz >= cz) && (az <= dz) : F32)

def Collision.box_sphere(box: BoundingBox, center: M.Vector3, +radius: F32) -> Bool:
  BoundingBox{M.Vector3{lx, ly, lz}, M.Vector3{ux, uy, uz}} = box
  M.Vector3{+x, +y, +z} = center
  closest = {M.Vector3{M.Math.clamp(x, lx, ux), M.Math.clamp(y, ly, uy), M.Math.clamp(z, lz, uz)} : M.Vector3}
  (M.Vector3.distance_sqr(M.Vector3{x, y, z}, closest) <= radius * radius : F32)

def Collision.recs(left: Rectangle, right: Rectangle) -> Bool:
  Rectangle{+x, +y, w, h} = left
  Rectangle{+u, +v, rw, rh} = right
  ((x < u + rw) && (x + w > u) && (y < v + rh) && (y + h > v) : F32)

def Collision.circles(left: M.Vector2, radius: F32, right: M.Vector2, other_radius: F32) -> Bool:
  M.Vector2{x, y} = left
  M.Vector2{u, v} = right
  +dx = (u - x : F32)
  +dy = (v - y : F32)
  +sum = (radius + other_radius : F32)
  (dx * dx + dy * dy <= sum * sum : F32)

def Collision.rectangle.result(overlap: Bool, +x: F32, +y: F32, right: F32, bottom: F32) -> Rectangle:
  match overlap:
    case False{}: Rectangle{0.0, 0.0, 0.0, 0.0}
    case True{}: Rectangle{x, y, (right - x : F32), (bottom - y : F32)}

def Collision.rectangle(left: Rectangle, right: Rectangle) -> Rectangle:
  Rectangle{+x, +y, w, h} = left
  Rectangle{+u, +v, rw, rh} = right
  +start_x = Bool.pick(F32, (x > u : F32), x, u)
  +end1 = (x + w : F32)
  +end2 = (u + rw : F32)
  +end_x = Bool.pick(F32, (end1 < end2 : F32), end1, end2)
  +start_y = Bool.pick(F32, (y > v : F32), y, v)
  +bottom1 = (y + h : F32)
  +bottom2 = (v + rh : F32)
  +end_y = Bool.pick(F32, (bottom1 < bottom2 : F32), bottom1, bottom2)
  Collision.rectangle.result(((start_x < end_x) && (start_y < end_y) : F32), start_x, start_y, end_x, end_y)

def Collision.point_rec(point: M.Vector2, rectangle: Rectangle) -> Bool:
  M.Vector2{+x, +y} = point
  Rectangle{+rx, +ry, w, h} = rectangle
  ((x >= rx) && (x < rx + w) && (y >= ry) && (y < ry + h) : F32)

def Collision.point_circle(point: M.Vector2, center: M.Vector2, +radius: F32) -> Bool:
  M.Vector2{x, y} = point
  M.Vector2{cx, cy} = center
  +dx = (x - cx : F32)
  +dy = (y - cy : F32)
  (dx * dx + dy * dy <= radius * radius : F32)

def Collision.circle_rec(center: M.Vector2, +radius: F32, rectangle: Rectangle) -> Bool:
  M.Vector2{x, y} = center
  Rectangle{rx, ry, w, h} = rectangle
  +half_w = (w / 2.0 : F32)
  +half_h = (h / 2.0 : F32)
  +dx = F32.abs((x - (rx + half_w) : F32))
  +dy = F32.abs((y - (ry + half_h) : F32))
  +corner_x = (dx - half_w : F32)
  +corner_y = (dy - half_h : F32)
  (((dx <= half_w + radius) && (dy <= half_h + radius))
    && ((dx <= half_w) || (dy <= half_h) || (corner_x * corner_x + corner_y * corner_y <= radius * radius)) : F32)

def Collision.lines.hit(inside: Bool, +arithmetic: Collision.Arithmetic, x: F32, y: F32, rx: F32, ry: F32, +t: F32) -> Maybe<&2, M.Vector2>:
  match inside:
    case False{}: None{}
    case True{}: Some{M.Vector2{Collision.multiply_add(arithmetic, t, rx, x), Collision.multiply_add(arithmetic, t, ry, y)}}

def Collision.lines.divided(nonparallel: Bool, +arithmetic: Collision.Arithmetic, +x: F32, +y: F32, +rx: F32, +ry: F32, +sx: F32, +sy: F32, u: F32, v: F32, +divisor: F32) -> Maybe<&2, M.Vector2>:
  match nonparallel:
    case False{}: None{}
    case True{}:
      +dx = (u - x : F32)
      +dy = (v - y : F32)
      +t = (Collision.multiply_add(arithmetic, dx, sy, F32.neg((dy * sx : F32))) / divisor : F32)
      +s = (Collision.multiply_add(arithmetic, dx, ry, F32.neg((dy * rx : F32))) / divisor : F32)
      Collision.lines.hit(((0.0 <= t) && (t <= 1.0) && (0.0 <= s) && (s <= 1.0) : F32), arithmetic, x, y, rx, ry, t)

def Collision.lines_for(+arithmetic: Collision.Arithmetic, start: M.Vector2, end: M.Vector2, other_start: M.Vector2, other_end: M.Vector2) -> Maybe<&2, M.Vector2>:
  M.Vector2{+x, +y} = start
  M.Vector2{ex, ey} = end
  M.Vector2{+u, +v} = other_start
  M.Vector2{eu, ev} = other_end
  +rx = (ex - x : F32)
  +ry = (ey - y : F32)
  +sx = (eu - u : F32)
  +sy = (ev - v : F32)
  +divisor = Collision.multiply_add(arithmetic, rx, sy, F32.neg((ry * sx : F32)))
  Collision.lines.divided((F32.abs(divisor) >= 0.00000011920928955078125 : F32), arithmetic, x, y, rx, ry, sx, sy, u, v, divisor)

def Collision.lines(start: M.Vector2, end: M.Vector2, other_start: M.Vector2, other_end: M.Vector2) -> Maybe<&2, M.Vector2>:
  Collision.lines_for(UncontractedCollision{}, start, end, other_start, other_end)

def Collision.point_triangle(point: M.Vector2, first: M.Vector2, second: M.Vector2, third: M.Vector2) -> Bool:
  M.Vector2{+x, +y} = point
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  M.Vector2{+cx, +cy} = third
  +denominator = ((by - cy) * (ax - cx) + (cx - bx) * (ay - cy) : F32)
  +alpha = (((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / denominator : F32)
  +beta = (((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / denominator : F32)
  gamma = (1.0 - alpha - beta : F32)
  ((alpha > 0.0) && (beta > 0.0) && (gamma > 0.0) : F32)

def Collision.point_line(point: M.Vector2, first: M.Vector2, second: M.Vector2, threshold: F32) -> Bool:
  M.Vector2{+x, +y} = point
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  cross = ((x - ax) * dy - (y - ay) * dx : F32)
  along_x = Bool.pick(Bool, (dx > 0.0 : F32), ((ax <= x) && (x <= bx) : F32), ((bx <= x) && (x <= ax) : F32))
  along_y = Bool.pick(Bool, (dy > 0.0 : F32), ((ay <= y) && (y <= by) : F32), ((by <= y) && (y <= ay) : F32))
  (F32.abs(cross) < threshold * F32.max(F32.abs(dx), F32.abs(dy)) : F32)
    && Bool.pick(Bool, (F32.abs(dx) >= F32.abs(dy) : F32), along_x, along_y)

def Collision.circle_line.route(degenerate: Bool, +x: F32, +y: F32, +radius: F32, +ax: F32, +ay: F32, bx: F32, by: F32, +dx: F32, +dy: F32) -> Bool:
  match degenerate:
    case True{}: Collision.circles(M.Vector2{ax, ay}, 0.0, M.Vector2{x, y}, radius)
    case False{}:
      length_squared = (dx * dx + dy * dy : F32)
      +projection = M.Math.clamp((((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / length_squared : F32), 0.0, 1.0)
      +distance_x = ((ax - projection * dx) - x : F32)
      +distance_y = ((ay - projection * dy) - y : F32)
      (distance_x * distance_x + distance_y * distance_y <= radius * radius : F32)

def Collision.circle_line(center: M.Vector2, radius: F32, first: M.Vector2, second: M.Vector2) -> Bool:
  M.Vector2{x, y} = center
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  +dx = (ax - bx : F32)
  +dy = (ay - by : F32)
  Collision.circle_line.route((F32.abs(dx) + F32.abs(dy) <= 0.00000011920928955078125 : F32), x, y, radius, ax, ay, bx, by, dx, dy)

def Collision.polygon.last(points: +List<M.Vector2>, previous: M.Vector2) -> M.Vector2:
  match points:
    case Nil{}: previous
    case Con{point, rest}: Collision.polygon.last(rest, point)

def Collision.polygon.crossing(straddles: Bool, x: F32, y: F32, +ax: F32, +ay: F32, bx: F32, by: F32) -> Bool:
  match straddles:
    case False{}: False{}
    case True{}: (x < (bx - ax) * (y - ay) / (by - ay) + ax : F32)

def Collision.polygon.edge(point: M.Vector2, current: M.Vector2, previous: M.Vector2) -> Bool:
  M.Vector2{x, +y} = point
  M.Vector2{ax, +ay} = current
  M.Vector2{bx, +by} = previous
  Collision.polygon.crossing(Bool.xor((ay > y : F32), (by > y : F32)), x, y, ax, ay, bx, by)

def Collision.polygon.loop(points: +List<M.Vector2>, +point: M.Vector2, previous: M.Vector2, inside: Bool) -> Bool:
  match points:
    case Nil{}: inside
    case Con{+current, rest}:
      Collision.polygon.loop(rest, point, current, Bool.xor(inside, Collision.polygon.edge(point, current, previous)))

def Collision.point_poly(point: M.Vector2, +points: +List<M.Vector2>) -> Bool:
  (List.length(&2, M.Vector2, points) > 2n : Nat)
    && Collision.polygon.loop(points, point, Collision.polygon.last(points, M.Vector2.zero()), False{})

# Internal signed-word operations for raylib's integer raster stepping.
def Signed.word(+x: F32) -> U32:
  +magnitude = F32.to_u32(F32.abs(x))
  Bool.pick(U32, (x < 0.0 : F32), (0 - magnitude : U32), magnitude)

def Signed.high16(+word: U32) -> F32:
  (U32.to_f32((word >> 16n : U32))
    - Bool.pick(F32, (word >= 2147483648 : U32), 65536.0, 0.0) : F32)

def Signed.trunc(+x: F32) -> F32:
  +magnitude = F32.floor(F32.abs(x))
  Bool.pick(F32, (x < 0.0 : F32), (0.0 - magnitude : F32), magnitude)

def Signed.to_f32(+word: U32) -> F32:
  Bool.pick(F32, (word >= 2147483648 : U32), F32.neg(U32.to_f32((0 - word : U32))), U32.to_f32(word))

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

def Color.normalize(+color: U32) -> M.Vector4:
  M.Vector4{(U32.to_f32(Color.red(color)) / 255.0 : F32), (U32.to_f32(Color.green(color)) / 255.0 : F32),
    (U32.to_f32(Color.blue(color)) / 255.0 : F32), (U32.to_f32(Color.alpha(color)) / 255.0 : F32)}

def Color.from_normalized(value: M.Vector4) -> U32:
  M.Vector4{r, g, b, a} = value
  Color.rgba(F32.to_u32((r * 255.0 : F32)), F32.to_u32((g * 255.0 : F32)),
    F32.to_u32((b * 255.0 : F32)), F32.to_u32((a * 255.0 : F32)))

def Color.hsv.components(achromatic: Bool, +r: F32, +g: F32, +b: F32, +maximum: F32, +delta: F32) -> M.Vector3:
  match achromatic:
    case True{}: M.Vector3{0.0, 0.0, maximum}
    case False{}:
      sector = Bool.pick(F32, (r >= maximum : F32), ((g - b) / delta : F32),
        Bool.pick(F32, (g >= maximum : F32), (2.0 + (b - r) / delta : F32), (4.0 + (r - g) / delta : F32)))
      +hue = (sector * 60.0 : F32)
      M.Vector3{Bool.pick(F32, (hue < 0.0 : F32), (hue + 360.0 : F32), hue), (delta / maximum : F32), maximum}

def Color.to_hsv(+color: U32) -> M.Vector3:
  +r = (U32.to_f32(Color.red(color)) / 255.0 : F32)
  +g = (U32.to_f32(Color.green(color)) / 255.0 : F32)
  +b = (U32.to_f32(Color.blue(color)) / 255.0 : F32)
  minimum = F32.min(F32.min(r, g), b)
  +maximum = F32.max(F32.max(r, g), b)
  +delta = (maximum - minimum : F32)
  Color.hsv.components((delta < 0.00001 : F32), r, g, b, maximum, delta)

def Color.hsv.channel(offset: F32, hue: F32, saturation: F32, +value: F32) -> U32:
  # Hue 0..360 makes the shifted phase 1..11, requiring at most one remainder subtraction.
  +phase = (offset + hue / 60.0 : F32)
  +k = Bool.pick(F32, (phase >= 6.0 : F32), (phase - 6.0 : F32), phase)
  gain = F32.clamp(F32.min((4.0 - k : F32), k), 0.0, 1.0)
  F32.to_u32(((value - value * saturation * gain) * 255.0 : F32))

def Color.from_hsv(+hue: F32, +saturation: F32, +value: F32) -> U32:
  Color.rgba(Color.hsv.channel(5.0, hue, saturation, value), Color.hsv.channel(3.0, hue, saturation, value),
    Color.hsv.channel(1.0, hue, saturation, value), 255)

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

def Color.grayscale(+pixel: U32) -> U32:
  F32.to_u32(((U32.to_f32(Color.red(pixel)) / 255.0 * 0.299
    + U32.to_f32(Color.green(pixel)) / 255.0 * 0.587
    + U32.to_f32(Color.blue(pixel)) / 255.0 * 0.114) * 255.0 : F32))

type Color.Transform is Data:
  ImageTint{color: U32}
  ImageInvert{}
  ImageContrast{factor: F32}
  ImageBrightness{amount: F32}
  ImageReplace{original: U32, replacement: U32}
  AlphaClear{threshold: U32, color: U32}
  AlphaPremultiply{}
  ImageChannel{shift: Nat}
  ImageGrayscale{}

def Color.image_contrast(channel: U32, factor: F32) -> U32:
  F32.to_u32(F32.clamp((((U32.to_f32(channel) / 255.0 - 0.5) * factor + 0.5) * 255.0 : F32), 0.0, 255.0))

def Color.image_brightness(channel: U32, amount: F32) -> U32:
  +value = (U32.to_f32(channel) + amount : F32)
  F32.to_u32(Bool.pick(F32, (value < 0.0 : F32), 1.0, F32.min(255.0, value)))

def Color.transform(transform: Color.Transform, +pixel: U32) -> U32:
  match transform:
    case ImageGrayscale{}:
      +value = Color.grayscale(pixel)
      Color.rgba(value, value, value, 255)
    case ImageChannel{shift}:
      +channel = ((pixel >> shift) .&. 255 : U32)
      Color.rgba(channel, channel, channel, 255)
    case ImageTint{+color}:
      Color.rgba((Color.red(pixel) * Color.red(color) / 255 : U32), (Color.green(pixel) * Color.green(color) / 255 : U32),
        (Color.blue(pixel) * Color.blue(color) / 255 : U32), (Color.alpha(pixel) * Color.alpha(color) / 255 : U32))
    case ImageInvert{}: U32.xor(pixel, 4294967040)
    case ImageContrast{+factor}:
      Color.rgba(Color.image_contrast(Color.red(pixel), factor), Color.image_contrast(Color.green(pixel), factor),
        Color.image_contrast(Color.blue(pixel), factor), Color.alpha(pixel))
    case ImageBrightness{+amount}:
      Color.rgba(Color.image_brightness(Color.red(pixel), amount), Color.image_brightness(Color.green(pixel), amount),
        Color.image_brightness(Color.blue(pixel), amount), Color.alpha(pixel))
    case ImageReplace{original, replacement}: Bool.pick(U32, U32.is_eq(pixel, original), replacement, pixel)
    case AlphaClear{threshold, color}: Bool.pick(U32, (Color.alpha(pixel) <= threshold : U32), color, pixel)
    case AlphaPremultiply{}:
      +alpha = Color.alpha(pixel)
      +factor = (U32.to_f32(alpha) / 255.0 : F32)
      Color.rgba(F32.to_u32((U32.to_f32(Color.red(pixel)) * factor : F32)),
        F32.to_u32((U32.to_f32(Color.green(pixel)) * factor : F32)), F32.to_u32((U32.to_f32(Color.blue(pixel)) * factor : F32)), alpha)

def Color.is_equal(left: U32, right: U32) -> Bool:
  U32.is_eq(left, right)

def Color.with_alpha(color: U32, alpha: F32) -> U32:
  ((color .&. 4294967040) .|. F32.to_u32((255.0 * F32.clamp(alpha, 0.0, 1.0) : F32)) : U32)

def Color.multiply(color: U32, tint: U32) -> U32:
  Color.transform(ImageTint{tint}, color)

def Color.brightness.channel(channel: U32, +factor: F32) -> U32:
  +value = U32.to_f32(channel)
  F32.to_u32(Bool.pick(F32, (factor < 0.0 : F32), (value * (1.0 + factor) : F32), ((255.0 - value) * factor + value : F32)))

def Color.brightness(+color: U32, factor: F32) -> U32:
  +bounded = F32.clamp(factor, (0.0 - 1.0 : F32), 1.0)
  Color.rgba(Color.brightness.channel(Color.red(color), bounded), Color.brightness.channel(Color.green(color), bounded),
    Color.brightness.channel(Color.blue(color), bounded), Color.alpha(color))

def Color.contrast(color: U32, factor: F32) -> U32:
  +adjusted = (1.0 + F32.clamp(factor, (0.0 - 1.0 : F32), 1.0) : F32)
  Color.transform(ImageContrast{(adjusted * adjusted : F32)}, color)

def Color.lerp.channel(left: U32, right: U32, +factor: F32) -> U32:
  F32.to_u32(((1.0 - factor) * U32.to_f32(left) + factor * U32.to_f32(right) : F32))

def Color.lerp(+left: U32, +right: U32, factor: F32) -> U32:
  +bounded = F32.clamp(factor, 0.0, 1.0)
  Color.rgba(Color.lerp.channel(Color.red(left), Color.red(right), bounded), Color.lerp.channel(Color.green(left), Color.green(right), bounded),
    Color.lerp.channel(Color.blue(left), Color.blue(right), bounded), Color.lerp.channel(Color.alpha(left), Color.alpha(right), bounded))

type Random.State is Type:
  RandomState{state: Rng.State}

def Random.seed(seed: U32) -> Random.State:
  RandomState{Rng.seed(seed)}

def Random.next.result(result: Rng.State & U32) -> Random.State & U32:
  (state, value) = result
  (RandomState{state}, value)

def Random.next_u32(state: Random.State) -> Random.State & U32:
  RandomState{inner} = state
  Random.next.result(Rng.next(inner))

def Random.value.result(lower: F32, span: U32, result: Random.State & U32) -> Random.State & F32:
  (state, value) = result
  (state, (U32.to_f32((value % span : U32)) + lower : F32))

def Random.value(state: Random.State, +minimum: F32, +maximum: F32) -> Random.State & F32:
  +lower = F32.min(minimum, maximum)
  upper = F32.max(minimum, maximum)
  Random.value.result(lower, F32.to_u32((upper - lower + 1.0 : F32)), Random.next_u32(state))

type Random.Sequence is Type:
  RandomSequence{values: +List<F32>}

type Random.Sequence.Error is Type:
  InvalidSequenceRequest{}
  SequenceDrawLimit{partial: Random.Sequence}

def Random.Sequence.values(sequence: Random.Sequence) -> +List<F32>:
  RandomSequence{values} = sequence
  values

def Random.unload_sequence(sequence: Random.Sequence) -> Unit:
  Unit{}

def Random.sequence.contains(values: +List<F32>, +value: F32) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, rest}: F32.is_eq(head, value) || Random.sequence.contains(rest, value)

def Random.sequence.step(+remaining: Nat, +values: +List<F32>, draw: Random.State & F32) -> Random.State & (Nat & +List<F32>):
  (state, +value) = draw
  +duplicate = Random.sequence.contains(values, value)
  (state, (Bool.pick(Nat, duplicate, 1n+remaining, remaining), Bool.pick(+List<F32>, duplicate, values, Con{value, values})))

def Random.sequence.loop(budget: Nat, +minimum: F32, +span: U32, cursor: Random.State & (Nat & +List<F32>)) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  match budget cursor:
    case _ Tuple{state, Tuple{0n, values}}:
      (state, Done{RandomSequence{List.reverse(&2, F32, values)}})
    case 0n Tuple{state, Tuple{_, values}}:
      (state, Fail{SequenceDrawLimit{RandomSequence{List.reverse(&2, F32, values)}}})
    case 1n+more Tuple{state, Tuple{1n+remaining, values}}:
      Random.sequence.loop(more, minimum, span, Random.sequence.step(remaining, values,
        Random.value.result(minimum, span, Random.next_u32(state))))

def Random.sequence.count(valid: Bool, state: Random.State, count: U32, minimum: F32, span: U32, budget: Nat) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  match valid:
    case False{}: (state, Fail{InvalidSequenceRequest{}})
    case True{}: Random.sequence.loop(budget, minimum, span, (state, (U32.to_nat(count), Nil{})))

def Random.sequence.bounds(valid: Bool, state: Random.State, +count: U32, +minimum: F32, maximum: F32, budget: Nat) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  match valid:
    case False{}: (state, Fail{InvalidSequenceRequest{}})
    case True{}:
      +span = F32.to_u32((F32.abs((maximum - minimum : F32)) + 1.0 : F32))
      Random.sequence.count((count <= span : U32), state, count, minimum, span, budget)

def Random.load_sequence(state: Random.State, count: U32, +minimum: F32, +maximum: F32, budget: Nat) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  Random.sequence.bounds(((minimum >= F32.neg(32767.0)) && (minimum <= 32767.0)
    && (maximum >= F32.neg(32767.0)) && (maximum <= 32767.0) : F32)
    && F32.is_eq(F32.floor(minimum), minimum) && F32.is_eq(F32.floor(maximum), maximum),
    state, count, minimum, maximum, budget)

# Construct through Surface.create; preserve its dimensions/storage invariant.
type Surface is Type:
  Surface{width: U32, height: U32, pixels: Array<U32>}

type Surface.Error is Data:
  InvalidSize{}
  InvalidRectangle{}
  UnsafeNearestMapping{}
  InvalidDitherBits{}
  InvalidKernel{}

type Image.Packed16 is Type:
  Packed16{width: U32, height: U32, format: U32, pixels: Array<U32>}

def Image.list.prefix(~T: Type, n: Nat, values: List<T>, prefix: List<T>) -> List<T>:
  match n values:
    case 0n _: List.reverse(&1, T, prefix)
    case _ Nil{}: List.reverse(&1, T, prefix)
    case 1n+rest Con{value, tail}: Image.list.prefix(~T, rest, tail, Con{value, prefix})

def Image.list.take(~T: Type, values: List<T>, n: Nat) -> List<T>:
  Image.list.prefix(~T, n, values, Nil{})

def Image.Packed16.export(image: Image.Packed16) -> (U32 & U32) & (U32 & List<U32>):
  Packed16{+width, +height, format, pixels} = image
  ((width, height), (format, Image.list.take(~U32, Array.to_list(~U32, pixels), U32.to_nat((width * height : U32)))))

def Pixel.bits_per_pixel(format: U32) -> U32:
  match format:
    case 1: 8
    case 2: 16
    case 3: 16
    case 4: 24
    case 5: 16
    case 6: 16
    case 7: 32
    case 8: 32
    case 9: 96
    case 10: 128
    case 11: 16
    case 12: 48
    case 13: 64
    case 14: 4
    case 15: 4
    case 16: 8
    case 17: 8
    case 18: 4
    case 19: 4
    case 20: 8
    case 21: 4
    case 22: 4
    case 23: 8
    case 24: 2
    case _: 0

def Pixel.size.checked(valid: Bool, +width: U32, +height: U32, +format: U32) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}:
      size = (width * height * Pixel.bits_per_pixel(format) / 8 : U32)
      +small = ((width < 4) && (height < 4) : U32)
      Some{Bool.pick(U32, small && ((format >= 14) && (format < 16) : U32), 8,
        Bool.pick(U32, small && ((format >= 16) && (format < 24) : U32), 16, size))}

def Pixel.data_size(+width: U32, +height: U32, +format: U32) -> Maybe<&2, U32>:
  Pixel.size.checked(((width <= 4096) && (height <= 4096) && (format <= 2147483647) : U32), width, height, format)

type Pixel.Error is Data:
  UnsupportedPixelFormat{}
  InvalidPixelByte{}
  TruncatedPixelData{}

def Pixel.packed_color(format: U32, +word: U32) -> U32:
  match format:
    case 3:
      Color.rgba(((word >> 11n) * 255 / 31 : U32), (((word >> 5n) .&. 63) * 255 / 63 : U32), ((word .&. 31) * 255 / 31 : U32), 255)
    case 5:
      # GetPixelColor uses the low five bits directly for blue, including alpha.
      Color.rgba(((word >> 11n) * 255 / 31 : U32), (((word >> 6n) .&. 31) * 255 / 31 : U32), ((word .&. 31) * 255 / 31 : U32), ((word .&. 1) * 255 : U32))
    case _:
      Color.rgba(((word >> 12n) * 17 : U32), (((word >> 8n) .&. 15) * 17 : U32), (((word >> 4n) .&. 15) * 17 : U32), ((word .&. 15) * 17 : U32))

def Pixel.read.bytes(format: U32, bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, U32>:
  match format bytes:
    case 1 Con{+gray, _}: Done{Color.rgba(gray, gray, gray, 255)}
    case 2 Con{+gray, Con{alpha, _}}: Done{Color.rgba(gray, gray, gray, alpha)}
    case 3 Con{low, Con{high, _}}: Done{Pixel.packed_color(3, (low .|. (high << 8n) : U32))}
    case 4 Con{r, Con{g, Con{b, _}}}: Done{Color.rgba(r, g, b, 255)}
    case 5 Con{low, Con{high, _}}: Done{Pixel.packed_color(5, (low .|. (high << 8n) : U32))}
    case 6 Con{low, Con{high, _}}: Done{Pixel.packed_color(6, (low .|. (high << 8n) : U32))}
    case 7 Con{r, Con{g, Con{b, Con{a, _}}}}: Done{Color.rgba(r, g, b, a)}
    case _ _: Fail{TruncatedPixelData{}}

def Pixel.read.valid(valid: Bool, format: U32, bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, U32>:
  match valid:
    case False{}: Fail{InvalidPixelByte{}}
    case True{}: Pixel.read.bytes(format, bytes)

def Pixel.read.format(valid: Bool, format: U32, +bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, U32>:
  match valid:
    case False{}: Fail{UnsupportedPixelFormat{}}
    case True{}: Pixel.read.valid(Qoi.valid_bytes(bytes, True{}), format, bytes)

def Pixel.get_color(bytes: +List<U32>, +format: U32) -> Result<&2, &2, Pixel.Error, U32>:
  Pixel.read.format(((format >= 1) && (format <= 7) : U32), format, bytes)

def Pixel.quantize(channel: U32, maximum: U32) -> U32:
  ((2 * channel * maximum + 255) / 510 : U32)

def Pixel.word_bytes(+word: U32) -> +List<U32>:
  [(word .&. 255 : U32), (word >> 8n : U32)]

def Pixel.encode(format: U32, +color: U32) -> +List<U32>:
  match format:
    case 1: [Color.grayscale(color)]
    case 2: [Color.grayscale(color), Color.alpha(color)]
    case 3:
      Pixel.word_bytes(((Pixel.quantize(Color.red(color), 31) << 11n) .|. (Pixel.quantize(Color.green(color), 63) << 5n) .|. Pixel.quantize(Color.blue(color), 31) : U32))
    case 4: [Color.red(color), Color.green(color), Color.blue(color)]
    case 5:
      Pixel.word_bytes(((Pixel.quantize(Color.red(color), 31) << 11n) .|. (Pixel.quantize(Color.green(color), 31) << 6n)
        .|. (Pixel.quantize(Color.blue(color), 31) << 1n) .|. Bool.to_u32((Color.alpha(color) > 50 : U32)) : U32))
    case 6:
      Pixel.word_bytes(((Pixel.quantize(Color.red(color), 15) << 12n) .|. (Pixel.quantize(Color.green(color), 15) << 8n)
        .|. (Pixel.quantize(Color.blue(color), 15) << 4n) .|. Pixel.quantize(Color.alpha(color), 15) : U32))
    case _: [Color.red(color), Color.green(color), Color.blue(color), Color.alpha(color)]

def Pixel.enough(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n _: True{}
    case _ Nil{}: False{}
    case 1n+rest Con{_, tail}: Pixel.enough(rest, tail)

def Pixel.write.sized(valid: Bool, +format: U32, color: U32, bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, +List<U32>>:
  match valid:
    case False{}: Fail{TruncatedPixelData{}}
    case True{}:
      Done{List.append(&2, U32, Pixel.encode(format, color), List.drop(&2, U32, bytes, U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32))))}

def Pixel.write.bytes(valid: Bool, +format: U32, color: U32, +bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, +List<U32>>:
  match valid:
    case False{}: Fail{InvalidPixelByte{}}
    case True{}: Pixel.write.sized(Pixel.enough(U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), bytes), format, color, bytes)

def Pixel.write.format(valid: Bool, format: U32, color: U32, +bytes: +List<U32>) -> Result<&2, &2, Pixel.Error, +List<U32>>:
  match valid:
    case False{}: Fail{UnsupportedPixelFormat{}}
    case True{}: Pixel.write.bytes(Qoi.valid_bytes(bytes, True{}), format, color, bytes)

def Pixel.set_color(bytes: +List<U32>, color: U32, +format: U32) -> Result<&2, &2, Pixel.Error, +List<U32>>:
  Pixel.write.format(((format >= 1) && (format <= 7) : U32), format, color, bytes)

type Image.Decode.Reference is Data:
  UncontractedDecode{}
  FusedDecode{}

def Image.Decode.fused(reference: Image.Decode.Reference) -> Bool:
  match reference:
    case UncontractedDecode{}: False{}
    case FusedDecode{}: True{}

type Image.DecodeError is Data:
  InvalidImageHeader{}
  InvalidImageByte{}
  UnsupportedImageSize{}
  TruncatedImageData{}
  InvalidImageStream{}

type Image.LoadError is Type:
  ImageFileError{code: U32, message: String}
  ImageDecodeError{error: Image.DecodeError}

def Surface.qoi.error(error: Qoi.Error) -> Image.DecodeError:
  match error:
    case Qoi.BadHeader{}: InvalidImageHeader{}
    case Qoi.BadByte{}: InvalidImageByte{}
    case Qoi.BadSize{}: UnsupportedImageSize{}
    case Qoi.Truncated{}: TruncatedImageData{}
    case Qoi.BadStream{}: InvalidImageStream{}

def Surface.qoi.result(result: Result<&1, &1, Qoi.Error, Qoi.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.qoi.error(error)}
    case Done{Qoi.Image{width, height, _, pixels}}: Done{Surface{width, height, pixels}}

def Surface.decode_qoi(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.qoi.result(Qoi.decode(bytes))

def Surface.to_qoi(surface: Surface) -> +List<U32>:
  Surface{w, h, pixels} = surface
  Qoi.encode(w, h, pixels)

def Surface.bmp.error(error: Bmp.Error) -> Image.DecodeError:
  match error:
    case Bmp.BadHeader{}: InvalidImageHeader{}
    case Bmp.BadByte{}: InvalidImageByte{}
    case Bmp.BadSize{}: UnsupportedImageSize{}
    case Bmp.Truncated{}: TruncatedImageData{}
    case Bmp.BadStream{}: InvalidImageStream{}

def Surface.bmp.result(result: Result<&1, &1, Bmp.Error, Bmp.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.bmp.error(error)}
    case Done{Bmp.Image{w, h, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_bmp(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.bmp.result(Bmp.decode(bytes))

def Surface.to_bmp(surface: Surface) -> +List<U32>:
  Surface{w, h, pixels} = surface
  Bmp.encode(w, h, pixels)

def Surface.tga.error(error: Tga.Error) -> Image.DecodeError:
  match error:
    case Tga.BadHeader{}: InvalidImageHeader{}
    case Tga.BadByte{}: InvalidImageByte{}
    case Tga.BadSize{}: UnsupportedImageSize{}
    case Tga.Truncated{}: TruncatedImageData{}
    case Tga.BadStream{}: InvalidImageStream{}

def Surface.tga.result(result: Result<&1, &1, Tga.Error, Tga.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.tga.error(error)}
    case Done{Tga.Image{w, h, _, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_tga(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.tga.result(Tga.decode(bytes))

def Surface.to_tga(surface: Surface) -> +List<U32>:
  Surface{w, h, pixels} = surface
  Tga.encode(w, h, pixels)

def Surface.pnm.error(error: Pnm.Error) -> Image.DecodeError:
  match error:
    case Pnm.BadHeader{}: InvalidImageHeader{}
    case Pnm.BadByte{}: InvalidImageByte{}
    case Pnm.BadSize{}: UnsupportedImageSize{}
    case Pnm.Truncated{}: TruncatedImageData{}

def Surface.pnm.result(result: Result<&1, &1, Pnm.Error, Pnm.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.pnm.error(error)}
    case Done{Pnm.Image{w, h, _, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_pnm(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.pnm.result(Pnm.decode(bytes))

def Surface.psd.error(error: Psd.Error) -> Image.DecodeError:
  match error:
    case Psd.BadHeader{}: InvalidImageHeader{}
    case Psd.BadByte{}: InvalidImageByte{}
    case Psd.BadSize{}: UnsupportedImageSize{}
    case Psd.Truncated{}: TruncatedImageData{}
    case Psd.BadStream{}: InvalidImageStream{}

def Surface.psd.result(result: Result<&1, &1, Psd.Error, Psd.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.psd.error(error)}
    case Done{Psd.Image{w, h, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_psd_for(reference: Image.Decode.Reference, bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.psd.result(Psd.decode(Image.Decode.fused(reference), bytes))

def Surface.decode_psd(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.decode_psd_for(UncontractedDecode{}, bytes)

def Surface.pic.error(error: Pic.Error) -> Image.DecodeError:
  match error:
    case Pic.BadHeader{}: InvalidImageHeader{}
    case Pic.BadByte{}: InvalidImageByte{}
    case Pic.BadSize{}: UnsupportedImageSize{}
    case Pic.Truncated{}: TruncatedImageData{}
    case Pic.BadStream{}: InvalidImageStream{}

def Surface.pic.result(result: Result<&1, &1, Pic.Error, Pic.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.pic.error(error)}
    case Done{Pic.Image{w, h, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_pic(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.pic.result(Pic.decode(bytes))

def Surface.gif.error(error: Gif.Error) -> Image.DecodeError:
  match error:
    case Gif.BadHeader{}: InvalidImageHeader{}
    case Gif.BadByte{}: InvalidImageByte{}
    case Gif.BadSize{}: UnsupportedImageSize{}
    case Gif.Truncated{}: TruncatedImageData{}
    case Gif.BadStream{}: InvalidImageStream{}

def Surface.gif.result(result: Result<&1, &1, Gif.Error, Gif.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.gif.error(error)}
    case Done{Gif.Image{w, h, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_gif(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.gif.result(Gif.decode(bytes))

type Image.Animation is Type:
  Animation{width: U32, height: U32, count: U32, frames: List<Surface>}

def Image.Animation.convert(frames: List<Gif.Image>, values: List<Surface>) -> List<Surface>:
  match frames:
    case Nil{}: List.reverse(&1, Surface, values)
    case Con{Gif.Image{w, h, pixels}, rest}: Image.Animation.convert(rest, Con{Surface{w, h, pixels}, values})

def Image.Animation.result(result: Result<&1, &1, Gif.Error, GifAnimation.Animation>) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  match result:
    case Fail{error}: Fail{Surface.gif.error(error)}
    case Done{GifAnimation.Animation{width, height, count, frames}}: Done{Animation{width, height, count, Image.Animation.convert(frames, Nil{})}}

def Image.Animation.decode_gif(bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  Image.Animation.result(GifAnimation.decode(bytes, maximum_frames, maximum_pixels))

def Image.Animation.entries(animation: Image.Animation) -> U32 & U32 & U32 & List<Surface>:
  Animation{width, height, count, frames} = animation
  (width, height, count, frames)

def Image.Animation.unload(animation: Image.Animation) -> Unit:
  Unit{}

type Image.FloatRGB is Type:
  FloatRGB{width: U32, height: U32, pixels: Array<M.Vector3>}

def Image.FloatRGB.hdr.error(error: Hdr.Error) -> Image.DecodeError:
  match error:
    case Hdr.BadHeader{}: InvalidImageHeader{}
    case Hdr.BadByte{}: InvalidImageByte{}
    case Hdr.BadSize{}: UnsupportedImageSize{}
    case Hdr.Truncated{}: TruncatedImageData{}
    case Hdr.BadStream{}: InvalidImageStream{}

def Image.FloatRGB.hdr.result(result: Result<&1, &1, Hdr.Error, Hdr.Image>) -> Result<&1, &1, Image.DecodeError, Image.FloatRGB>:
  match result:
    case Fail{error}: Fail{Image.FloatRGB.hdr.error(error)}
    case Done{Hdr.Image{w, h, pixels}}: Done{FloatRGB{w, h, pixels}}

def Image.FloatRGB.decode_hdr(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.FloatRGB>:
  Image.FloatRGB.hdr.result(Hdr.decode(bytes))

def Image.FloatRGB.entries(image: Image.FloatRGB) -> U32 & U32 & List<M.Vector3>:
  FloatRGB{+width, +height, pixels} = image
  (width, height, Image.list.take(~M.Vector3, Array.to_list(~M.Vector3, pixels), U32.to_nat((width * height : U32))))

def Image.FloatRGB.unload(image: Image.FloatRGB) -> Unit:
  Unit{}

def Surface.png.error(error: Png.Error) -> Image.DecodeError:
  match error:
    case Png.BadHeader{}: InvalidImageHeader{}
    case Png.BadByte{}: InvalidImageByte{}
    case Png.BadSize{}: UnsupportedImageSize{}
    case Png.BadStream{}: InvalidImageStream{}

def Surface.png.result(result: Result<&1, &1, Png.Error, Png.Image>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match result:
    case Fail{error}: Fail{Surface.png.error(error)}
    case Done{Png.Image{w, h, pixels}}: Done{Surface{w, h, pixels}}

def Surface.decode_png(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.png.result(Png.decode(bytes))

def Surface.to_png(surface: Surface) -> +List<U32>:
  Surface{width, height, pixels} = surface
  PngEncode.encode(width, height, pixels)

def Surface.dimensions(surface: Surface) -> U32 & U32:
  Surface{w, h, _} = surface
  (w, h)

def Surface.capacity(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

def Surface.creation.checked(ok: Bool, +w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}}

# The initial profile supports 1..4096 pixels on each axis.
def Surface.create(+w: U32, +h: U32, color: U32) -> Maybe<Surface>:
  Surface.creation.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, color)

def Surface.float_rgb.color(color: U32) -> M.Vector3:
  +value = color
  M.Vector3{(U32.to_f32(Color.red(value)) / 255.0 : F32),
    (U32.to_f32(Color.green(value)) / 255.0 : F32), (U32.to_f32(Color.blue(value)) / 255.0 : F32)}

def Surface.to_float_rgb(surface: Surface) -> Image.FloatRGB:
  Surface{width, height, pixels} = surface
  FloatRGB{width, height, Array.map(~U32, ~M.Vector3, ~Surface.float_rgb.color, pixels)}

def Image.FloatRGB.channel.valid(value: F32) -> Bool:
  +bits = F32.bits(value)
  # Bit ordering retains the domain check even when a GPU flushes denormals.
  (bits <= 1065353216 : U32) || U32.is_eq(bits, 2147483648)

def Image.FloatRGB.pixel.valid(value: M.Vector3) -> Bool:
  M.Vector3{r, g, b} = value
  Image.FloatRGB.channel.valid(r) && Image.FloatRGB.channel.valid(g) && Image.FloatRGB.channel.valid(b)

def Image.FloatRGB.checked.read(~valid: M.Vector3 -> Bool, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Bool:
  (pixels, value) = result
  (pixels, valid(value))

def Image.FloatRGB.checked.pixels(~valid: M.Vector3 -> Bool, n: Nat, +index: U32, state: Array<M.Vector3> & Bool) -> Array<M.Vector3> & Bool:
  match n state:
    case _ Tuple{pixels, False{}}: (pixels, False{})
    case 0n _: state
    case 1n+rest Tuple{pixels, True{}}:
      Image.FloatRGB.checked.pixels(~valid, rest, (index + 1 : U32), Image.FloatRGB.checked.read(~valid, Array.get(M.Vector3, pixels, index)))

def Image.FloatRGB.pixel.color(value: M.Vector3) -> U32:
  M.Vector3{r, g, b} = value
  Color.rgba(F32.to_u32((r * 255.0 : F32)), F32.to_u32((g * 255.0 : F32)), F32.to_u32((b * 255.0 : F32)), 255)

def Image.FloatRGB.converted.read(index: U32, output: Array<U32>, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Array<U32>:
  (pixels, value) = result
  (pixels, Array.set(U32, output, index, Image.FloatRGB.pixel.color(value)))

def Image.FloatRGB.converted.pixels(n: Nat, +index: U32, state: Array<M.Vector3> & Array<U32>) -> Array<M.Vector3> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{pixels, output}:
      Image.FloatRGB.converted.pixels(rest, (index + 1 : U32), Image.FloatRGB.converted.read(index, output, Array.get(M.Vector3, pixels, index)))

def Image.FloatRGB.converted.surface(width: U32, height: U32, result: Array<M.Vector3> & Array<U32>) -> Surface:
  (_, pixels) = result
  Surface{width, height, pixels}

def Image.FloatRGB.converted(+width: U32, +height: U32, state: Array<M.Vector3> & Bool) -> Result<&1, &1, Image.FloatRGB, Surface>:
  match state:
    case Tuple{pixels, False{}}: Fail{FloatRGB{width, height, pixels}}
    case Tuple{pixels, True{}}:
      +count = (width * height : U32)
      Done{Image.FloatRGB.converted.surface(width, height, Image.FloatRGB.converted.pixels(U32.to_nat(count), 0, (pixels, Array.new(U32, Surface.capacity(count), 0))))}

def Image.FloatRGB.to_surface(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, Surface>:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.converted(width, height, Image.FloatRGB.checked.pixels(~Image.FloatRGB.pixel.valid, U32.to_nat((width * height : U32)), 0, (pixels, True{})))

def Image.FloatRGB.raw.word_valid(word: U32) -> Bool:
  ((word .&. 2147483647) <= 2139095040 : U32)

def Image.FloatRGB.raw.pixel_valid(pixel: M.Vector3) -> Bool:
  M.Vector3{r, g, b} = pixel
  Image.FloatRGB.raw.word_valid(F32.bits(r)) && Image.FloatRGB.raw.word_valid(F32.bits(g)) && Image.FloatRGB.raw.word_valid(F32.bits(b))

type Image.FloatRGB.Raw is Type:
  RawRGB{bytes: +List<U32>, pixels: Array<M.Vector3>}

def Image.FloatRGB.raw.stored(valid: Bool, index: U32, r: U32, g: U32, b: U32, bytes: +List<U32>, pixels: Array<M.Vector3>) -> Maybe<Image.FloatRGB.Raw>:
  match valid:
    case False{}: None{}
    case True{}: Some{RawRGB{bytes, Array.set(M.Vector3, pixels, index, M.Vector3{Hdr.float_bits(r), Hdr.float_bits(g), Hdr.float_bits(b)})}}

def Image.FloatRGB.raw.read(index: U32, pixels: Array<M.Vector3>, bytes: +List<U32>) -> Maybe<Image.FloatRGB.Raw>:
  match bytes:
    case Con{r0, Con{r1, Con{r2, Con{r3, Con{g0, Con{g1, Con{g2, Con{g3, Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}}}}}}}}}:
      +r = (r0 .|. (r1 << 8n) .|. (r2 << 16n) .|. (r3 << 24n) : U32)
      +g = (g0 .|. (g1 << 8n) .|. (g2 << 16n) .|. (g3 << 24n) : U32)
      +b = (b0 .|. (b1 << 8n) .|. (b2 << 16n) .|. (b3 << 24n) : U32)
      Image.FloatRGB.raw.stored(Image.FloatRGB.raw.word_valid(r) && Image.FloatRGB.raw.word_valid(g) && Image.FloatRGB.raw.word_valid(b), index, r, g, b, rest, pixels)
    case _: None{}

def Image.FloatRGB.raw.pixels(n: Nat, +index: U32, state: Maybe<Image.FloatRGB.Raw>) -> Maybe<Array<M.Vector3>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{RawRGB{_, pixels}}: Some{pixels}
    case 1n+rest Some{RawRGB{bytes, pixels}}: Image.FloatRGB.raw.pixels(rest, (index + 1 : U32), Image.FloatRGB.raw.read(index, pixels, bytes))

def Image.FloatRGB.raw.created(width: U32, height: U32, result: Maybe<Array<M.Vector3>>) -> Maybe<Image.FloatRGB>:
  match result:
    case None{}: None{}
    case Some{pixels}: Some{FloatRGB{width, height, pixels}}

def Image.FloatRGB.raw.checked(valid: Bool, +width: U32, +height: U32, bytes: +List<U32>) -> Maybe<Image.FloatRGB>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Image.FloatRGB.raw.created(width, height, Image.FloatRGB.raw.pixels(U32.to_nat(count), 0,
        Some{RawRGB{bytes, Array.new(M.Vector3, Surface.capacity(count), M.Vector3{0.0, 0.0, 0.0})}}))

def Image.FloatRGB.raw.sized(valid: Bool, +width: U32, +height: U32, +bytes: +List<U32>) -> Maybe<Image.FloatRGB>:
  match valid:
    case False{}: None{}
    case True{}: Image.FloatRGB.raw.checked(Formats.valid(bytes, (width * height * 12 : U32), True{}), width, height, bytes)

def Image.FloatRGB.from_bytes(+width: U32, +height: U32, bytes: +List<U32>) -> Maybe<Image.FloatRGB>:
  Image.FloatRGB.raw.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), width, height, bytes)

def Image.FloatRGB.raw.pack(pixels: List<M.Vector3>, values: +List<U32>) -> +List<U32>:
  match pixels:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{M.Vector3{r, g, b}, rest}:
      Image.FloatRGB.raw.pack(rest, Formats.word_bytes(~&2, 4n, F32.bits(b), Formats.word_bytes(~&2, 4n, F32.bits(g), Formats.word_bytes(~&2, 4n, F32.bits(r), values))))

def Image.FloatRGB.raw.exported(+width: U32, +height: U32, state: Array<M.Vector3> & Bool) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  match state:
    case Tuple{pixels, False{}}: Fail{FloatRGB{width, height, pixels}}
    case Tuple{pixels, True{}}:
      Done{Image.FloatRGB.raw.pack(Image.list.take(~M.Vector3, Array.to_list(~M.Vector3, pixels), U32.to_nat((width * height : U32))), Nil{})}

def Image.FloatRGB.to_bytes(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.raw.exported(width, height, Image.FloatRGB.checked.pixels(~Image.FloatRGB.raw.pixel_valid, U32.to_nat((width * height : U32)), 0, (pixels, True{})))

type Image.Formatted is Type:
  FormattedImage{width: U32, height: U32, format: U32, pixels: Array<U32>}

# QOI channel metadata selects native storage; decoding/cache state stays RGBA.
# Pack with integers rather than an ImageFormat floating-point round trip.
def Image.Formatted.qoi.format(channels: U32) -> U32:
  Bool.pick(U32, U32.is_eq(channels, 3), 4, 7)

def Image.Formatted.qoi.word(channels: U32, pixel: U32) -> U32:
  +word = Formats.swap(pixel)
  Bool.pick(U32, U32.is_eq(channels, 3), (word .&. 16777215 : U32), word)

def Image.Formatted.qoi.write(index: U32, channels: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = read
  Array.set(U32, pixels, index, Image.Formatted.qoi.word(channels, pixel))

def Image.Formatted.qoi.pixels(n: Nat, +index: U32, +channels: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest:
      Image.Formatted.qoi.pixels(rest, (index + 1 : U32), channels, Image.Formatted.qoi.write(index, channels, Array.get(U32, pixels, index)))

def Image.Formatted.qoi.result(result: Result<&1, &1, Qoi.Error, Qoi.Image>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  match result:
    case Fail{error}: Fail{Surface.qoi.error(error)}
    case Done{Qoi.Image{+width, +height, +channels, pixels}}:
      Done{FormattedImage{width, height, Image.Formatted.qoi.format(channels),
        Image.Formatted.qoi.pixels(U32.to_nat((width * height : U32)), 0, channels, pixels)}}

def Image.Formatted.decode_qoi(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  Image.Formatted.qoi.result(Qoi.decode(bytes))

# PNM magic retains native gray/RGB storage after the decoder's 8-bit reduction.
# Extract integer samples directly; a floating luminance round trip can alter gray.
def Image.Formatted.pnm.format(channels: U32) -> U32:
  Bool.pick(U32, U32.is_eq(channels, 1), 1, 4)

def Image.Formatted.pnm.word(channels: U32, +pixel: U32) -> U32:
  Bool.pick(U32, U32.is_eq(channels, 1), (pixel >> 24n : U32), (Formats.swap(pixel) .&. 16777215 : U32))

def Image.Formatted.pnm.write(index: U32, channels: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = read
  Array.set(U32, pixels, index, Image.Formatted.pnm.word(channels, pixel))

def Image.Formatted.pnm.pixels(n: Nat, +index: U32, +channels: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest:
      Image.Formatted.pnm.pixels(rest, (index + 1 : U32), channels, Image.Formatted.pnm.write(index, channels, Array.get(U32, pixels, index)))

def Image.Formatted.pnm.result(result: Result<&1, &1, Pnm.Error, Pnm.Image>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  match result:
    case Fail{error}: Fail{Surface.pnm.error(error)}
    case Done{Pnm.Image{+width, +height, +channels, pixels}}:
      Done{FormattedImage{width, height, Image.Formatted.pnm.format(channels),
        Image.Formatted.pnm.pixels(U32.to_nat((width * height : U32)), 0, channels, pixels)}}

def Image.Formatted.decode_pnm(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  Image.Formatted.pnm.result(Pnm.decode(bytes))

# TGA carries actual native output channels independently of input sample/index
# width. Pack canonical RGBA with integers, retaining gray and zero-alpha bytes.
def Image.Formatted.tga.format(channels: U32) -> U32:
  match channels:
    case 1: 1
    case 2: 2
    case 3: 4
    case _: 7

def Image.Formatted.tga.word(channels: U32, +pixel: U32) -> U32:
  match channels:
    case 1: (pixel >> 24n : U32)
    case 2: ((pixel >> 24n) .|. ((pixel .&. 255) << 8n) : U32)
    case 3: (Formats.swap(pixel) .&. 16777215 : U32)
    case _: Formats.swap(pixel)

def Image.Formatted.tga.write(index: U32, channels: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = read
  Array.set(U32, pixels, index, Image.Formatted.tga.word(channels, pixel))

def Image.Formatted.tga.pixels(n: Nat, +index: U32, +channels: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest:
      Image.Formatted.tga.pixels(rest, (index + 1 : U32), channels, Image.Formatted.tga.write(index, channels, Array.get(U32, pixels, index)))

def Image.Formatted.tga.result(result: Result<&1, &1, Tga.Error, Tga.Image>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  match result:
    case Fail{error}: Fail{Surface.tga.error(error)}
    case Done{Tga.Image{+width, +height, +native_channels, pixels}}:
      Done{FormattedImage{width, height, Image.Formatted.tga.format(native_channels),
        Image.Formatted.tga.pixels(U32.to_nat((width * height : U32)), 0, native_channels, pixels)}}

def Image.Formatted.decode_tga(bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Image.Formatted>:
  Image.Formatted.tga.result(Tga.decode(bytes))

def Image.Formatted.created(width: U32, height: U32, format: U32, result: Maybe<Array<U32>>) -> Maybe<Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{pixels}: Some{FormattedImage{width, height, format, pixels}}

def Image.Formatted.validated(valid: Bool, +width: U32, +height: U32, +format: U32, bytes: +List<U32>) -> Maybe<Image.Formatted>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Image.Formatted.created(width, height, format, Formats.unpack(U32.to_nat(count), 0,
        U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), Some{Formats.Input{bytes, Array.new(U32, Surface.capacity(count), 0)}}))

def Image.Formatted.checked(valid: Bool, +width: U32, +height: U32, +format: U32, +bytes: +List<U32>) -> Maybe<Image.Formatted>:
  match valid:
    case False{}: None{}
    case True{}:
      Image.Formatted.validated(Formats.valid(bytes, (width * height * (Pixel.bits_per_pixel(format) / 8) : U32), True{})
        && Formats.domain_valid(format, bytes), width, height, format, bytes)

def Image.Formatted.from_bytes(+width: U32, +height: U32, +format: U32, bytes: +List<U32>) -> Maybe<Image.Formatted>:
  Image.Formatted.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (format >= 1) && (format <= 8) : U32), width, height, format, bytes)

def Surface.to_formatted(surface: Surface) -> Image.Formatted:
  Surface{+width, +height, pixels} = surface
  FormattedImage{width, height, 7, Formats.swap_pixels(U32.to_nat((width * height : U32)), 0, pixels)}

def Image.Formatted.routed(unchanged: Bool, image: Image.Formatted, +to: U32) -> Image.Formatted:
  match unchanged image:
    case True{} _: image
    case False{} FormattedImage{+width, +height, from, pixels}:
      FormattedImage{width, height, to, Formats.convert(U32.to_nat((width * height : U32)), 0, from, to, pixels)}

def Image.Formatted.converted(valid: Bool, image: Image.Formatted, +target: U32) -> Result<&1, &1, Image.Formatted & Pixel.Error, Image.Formatted>:
  match valid image:
    case False{} _: Fail{(image, UnsupportedPixelFormat{})}
    case True{} FormattedImage{width, height, +format, pixels}:
      Done{Image.Formatted.routed(U32.is_eq(target, 0) || U32.is_eq(target, format), FormattedImage{width, height, format, pixels}, target)}

def Image.Formatted.convert(image: Image.Formatted, +target: U32) -> Result<&1, &1, Image.Formatted & Pixel.Error, Image.Formatted>:
  Image.Formatted.converted((target <= 8 : U32), image, target)

def Image.Formatted.export(image: Image.Formatted) -> (U32 & U32) & (U32 & List<U32>):
  FormattedImage{+width, +height, +format, pixels} = image
  words = Image.list.take(~U32, Array.to_list(~U32, pixels), U32.to_nat((width * height : U32)))
  ((width, height), (format, Formats.bytes(~&1, words, U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), Nil{})))

def Image.Formatted.surface(image: Image.Formatted) -> Surface:
  FormattedImage{+width, +height, _, pixels} = image
  Surface{width, height, Formats.swap_pixels(U32.to_nat((width * height : U32)), 0, pixels)}

def Image.Formatted.to_surface(image: Image.Formatted) -> Surface:
  FormattedImage{width, height, +format, pixels} = image
  Image.Formatted.surface(Image.Formatted.routed(U32.is_eq(format, 7), FormattedImage{width, height, format, pixels}, 7))

def Image.Formatted.float_rgb.normal(normal: Formats.Normal) -> M.Vector3:
  Formats.Normal{r, g, b, _} = normal
  M.Vector3{r, g, b}

def Image.Formatted.float_rgb.read(format: U32, index: U32, output: Array<M.Vector3>, result: Array<U32> & U32) -> Array<U32> & Array<M.Vector3>:
  (source, word) = result
  (source, Array.set(M.Vector3, output, index, Image.Formatted.float_rgb.normal(Formats.decode(format, word))))

def Image.Formatted.float_rgb.pixels(n: Nat, +index: U32, +format: U32, state: Array<U32> & Array<M.Vector3>) -> Array<M.Vector3>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{source, output}:
      Image.Formatted.float_rgb.pixels(rest, (index + 1 : U32), format, Image.Formatted.float_rgb.read(format, index, output, Array.get(U32, source, index)))

def Image.Formatted.to_float_rgb(image: Image.Formatted) -> Image.FloatRGB:
  FormattedImage{+width, +height, format, pixels} = image
  +count = (width * height : U32)
  FloatRGB{width, height, Image.Formatted.float_rgb.pixels(U32.to_nat(count), 0, format,
    (pixels, Array.new(M.Vector3, Surface.capacity(count), M.Vector3{0.0, 0.0, 0.0})))}

def Image.FloatRGB.formatted.read(format: U32, index: U32, output: Array<U32>, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Array<U32>:
  match result:
    case Tuple{pixels, M.Vector3{r, g, b}}:
      (pixels, Array.set(U32, output, index, Formats.encode(Formats.Normal{r, g, b, 1.0}, format)))

def Image.FloatRGB.formatted.pixels(n: Nat, +index: U32, +format: U32, state: Array<M.Vector3> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{pixels, output}:
      Image.FloatRGB.formatted.pixels(rest, (index + 1 : U32), format, Image.FloatRGB.formatted.read(format, index, output, Array.get(M.Vector3, pixels, index)))

def Image.FloatRGB.formatted.checked(+width: U32, +height: U32, +format: U32, state: Array<M.Vector3> & Bool) -> Result<&1, &1, Image.FloatRGB, Image.Formatted>:
  match state:
    case Tuple{pixels, False{}}: Fail{FloatRGB{width, height, pixels}}
    case Tuple{pixels, True{}}:
      +count = (width * height : U32)
      Done{FormattedImage{width, height, format, Image.FloatRGB.formatted.pixels(U32.to_nat(count), 0, format, (pixels, Array.new(U32, Surface.capacity(count), 0)))}}

def Image.FloatRGB.formatted.target(valid: Bool, image: Image.FloatRGB, format: U32) -> Result<&1, &1, Image.FloatRGB, Image.Formatted>:
  match valid image:
    case False{} _: Fail{image}
    case True{} FloatRGB{+width, +height, pixels}:
      Image.FloatRGB.formatted.checked(width, height, format, Image.FloatRGB.checked.pixels(~Image.FloatRGB.pixel.valid, U32.to_nat((width * height : U32)), 0, (pixels, True{})))

def Image.FloatRGB.to_formatted(image: Image.FloatRGB, +format: U32) -> Result<&1, &1, Image.FloatRGB, Image.Formatted>:
  Image.FloatRGB.formatted.target(((format >= 1) && (format <= 8) : U32), image, format)

def Image.FloatRGB.color_grayscale(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, Image.Formatted>:
  Image.FloatRGB.to_formatted(image, 1)

def Image.Formatted.png.channels(format: U32) -> U32:
  match format:
    case 1: 1
    case 2: 2
    case 4: 3
    case 7: 4
    case _: 0

# ExportImageToMemory reads the four raw bytes of each R32 sample as RGBA.
# Keep this separate from file export, which obtains red-only normalized colors.
def Image.Formatted.png.memory_channels(format: U32) -> U32:
  match format:
    case 8: 4
    case _: Image.Formatted.png.channels(format)

def Image.Formatted.png.checked(valid: Bool, channels: U32, image: Image.Formatted) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>:
  match valid image:
    case False{} _: Fail{(image, UnsupportedPixelFormat{})}
    case True{} FormattedImage{width, height, _, pixels}: Done{PngEncode.formatted(width, height, channels, pixels)}

def Image.Formatted.to_png(image: Image.Formatted) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>:
  FormattedImage{width, height, +format, pixels} = image
  +channels = Image.Formatted.png.memory_channels(format)
  Image.Formatted.png.checked((channels > 0 : U32), channels, FormattedImage{width, height, format, pixels})

def Image.Formatted.png.file_routed(direct: Bool, +width: U32, +height: U32, format: U32, channels: U32, pixels: Array<U32>) -> +List<U32>:
  match direct:
    case True{}: PngEncode.formatted(width, height, channels, pixels)
    case False{}: PngEncode.encode(width, height, Formats.packed_colors(U32.to_nat((width * height : U32)), 0, format, pixels))

def Image.Formatted.png.file_bytes(image: Image.Formatted) -> +List<U32>:
  FormattedImage{width, height, +format, pixels} = image
  +channels = Image.Formatted.png.channels(format)
  Image.Formatted.png.file_routed((channels > 0 : U32), width, height, format, channels, pixels)

# Pure convenience for ExportImage's BMP file bytes, not ExportImageToMemory.
# Native formats 1/2/4 select 24-bit output; every other checked format selects
# V4 using LoadImageColors expansion, which differs from ImageFormat for packed
# channels. The checked owner's dimensions bound the V4 file to 67,108,986 bytes.
def Image.Formatted.bmp.routed(direct: Bool, +width: U32, +height: U32, format: U32, pixels: Array<U32>) -> +List<U32>:
  match direct:
    case True{}: Bmp.encode24(width, height, format, pixels)
    case False{}: Bmp.encode(width, height, Formats.packed_colors(U32.to_nat((width * height : U32)), 0, format, pixels))

def Image.Formatted.to_bmp(image: Image.Formatted) -> +List<U32>:
  FormattedImage{width, height, +format, pixels} = image
  Image.Formatted.bmp.routed(U32.is_eq(format, 1) || U32.is_eq(format, 2) || U32.is_eq(format, 4), width, height, format, pixels)

# Pure convenience for ExportImage's TGA file bytes, not ExportImageToMemory.
# Compare after LoadImageColors expansion: distinct R32 words can collapse into
# the same color. The checked dimensions bound output to 83,886,098 bytes.
def Image.Formatted.tga.channels(format: U32) -> U32:
  match format:
    case 1: 1
    case 2: 2
    case 4: 3
    case _: 4

def Image.Formatted.to_tga(image: Image.Formatted) -> +List<U32>:
  FormattedImage{+width, +height, +format, pixels} = image
  Tga.encode.channels(width, height, Image.Formatted.tga.channels(format), Formats.packed_colors(U32.to_nat((width * height : U32)), 0, format, pixels))

# ExportImage's QOI branch accepts only the original RGB888/RGBA8888 format.
# Reject before conversion or IO; in particular preserve every checked R32 bit.
# Accepted colors use integer packing, with opaque alpha for RGB888. This maps
# file export bytes, not ExportImageToMemory (whose native dispatch is PNG-only).
def Image.Formatted.qoi.channels(format: U32) -> U32:
  match format:
    case 4: 3
    case 7: 4
    case _: 0

def Image.Formatted.qoi.checked(valid: Bool, channels: U32, image: Image.Formatted) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>:
  match valid image:
    case False{} _: Fail{(image, UnsupportedPixelFormat{})}
    case True{} FormattedImage{+width, +height, format, pixels}:
      Done{Qoi.encode.channels(width, height, channels, Formats.packed_colors(U32.to_nat((width * height : U32)), 0, format, pixels))}

def Image.Formatted.to_qoi(image: Image.Formatted) -> Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>:
  FormattedImage{width, height, +format, pixels} = image
  +channels = Image.Formatted.qoi.channels(format)
  Image.Formatted.qoi.checked((channels > 0 : U32), channels, FormattedImage{width, height, format, pixels})

def Image.FloatRGB.png.word(channel: U32, value: M.Vector3) -> U32:
  match channel value:
    case 0 M.Vector3{r, _, _}: F32.bits(r)
    case 1 M.Vector3{_, g, _}: F32.bits(g)
    case _ M.Vector3{_, _, b}: F32.bits(b)

def Image.FloatRGB.png.read(+index: U32, output: Array<U32>, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Array<U32>:
  (source, value) = result
  (source, Array.set(U32, output, index, Image.FloatRGB.png.word((index % 3 : U32), value)))

def Image.FloatRGB.png.words(n: Nat, +index: U32, state: Array<M.Vector3> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{source, output}:
      Image.FloatRGB.png.words(rest, (index + 1 : U32), Image.FloatRGB.png.read(index, output, Array.get(M.Vector3, source, (index / 3 : U32))))

def Image.FloatRGB.png.checked(+width: U32, +height: U32, state: Array<M.Vector3> & Bool) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  match state:
    case Tuple{pixels, False{}}: Fail{FloatRGB{width, height, pixels}}
    case Tuple{pixels, True{}}:
      # Native memory export reads four byte channels from the raw storage prefix.
      +count = (width * height : U32)
      Done{PngEncode.formatted(width, height, 4, Image.FloatRGB.png.words(U32.to_nat(count), 0, (pixels, Array.new(U32, Surface.capacity(count), 0))))}

def Image.FloatRGB.to_png(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.png.checked(width, height, Image.FloatRGB.checked.pixels(~Image.FloatRGB.raw.pixel_valid, U32.to_nat((width * height : U32)), 0, (pixels, True{})))

def Image.FloatRGB.file.encoded(~encode: Surface -> +List<U32>, result: Result<&1, &1, Image.FloatRGB, Surface>) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  match result:
    case Fail{image}: Fail{image}
    case Done{surface}: Done{encode(surface)}

def Image.FloatRGB.png.file_bytes(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  Image.FloatRGB.file.encoded(~Surface.to_png, Image.FloatRGB.to_surface(image))

def Image.FloatRGB.to_bmp(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  Image.FloatRGB.file.encoded(~Surface.to_bmp, Image.FloatRGB.to_surface(image))

def Image.FloatRGB.to_tga(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, +List<U32>>:
  Image.FloatRGB.file.encoded(~Surface.to_tga, Image.FloatRGB.to_surface(image))

def Surface.dither.checked(valid: Bool, surface: Surface, +r: U32, +g: U32, +b: U32, +a: U32) -> Result<&1, &1, Surface & Surface.Error, Image.Packed16>:
  match valid surface:
    case False{} _: Fail{(surface, InvalidDitherBits{})}
    case True{} Surface{+w, +h, pixels}:
      +count = (w * h : U32)
      Done{Packed16{w, h, Dither.format(r, g, b, a), Dither.loop(U32.to_nat(count), 0, w, h,
        Dither.Bits{U32.to_nat(r), U32.to_nat(g), U32.to_nat(b), U32.to_nat(a)},
        (pixels, Array.new(U32, Surface.capacity(count), 0)))}}

def Surface.dither(surface: Surface, +r: U32, +g: U32, +b: U32, +a: U32) -> Result<&1, &1, Surface & Surface.Error, Image.Packed16>:
  Surface.dither.checked(((r <= 8) && (g <= 8) && (b <= 8) && (a <= 8) && (r + g + b + a <= 16) : U32), surface, r, g, b, a)

def Surface.text.fill(n: Nat, +index: U32, bytes: +List<U32>, pixels: Array<U32>) -> Array<U32>:
  match n bytes:
    case 0n _: pixels
    case _ Nil{}: pixels
    case _ Con{0, _}: pixels
    case 1n+rest Con{+byte, tail}:
      Surface.text.fill(rest, (index + 1 : U32), tail, Array.set(U32, pixels, index, Color.rgba(byte, byte, byte, 255)))

def Surface.text.checked(valid: Bool, +width: U32, +height: U32, bytes: +List<U32>) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Surface.text.fill(U32.to_nat(count), 0, bytes, Array.new(U32, Surface.capacity(count), 255))}}

def Surface.create_text_bytes(+width: U32, +height: U32, +bytes: +List<U32>) -> Maybe<Surface>:
  Surface.text.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && Qoi.valid_bytes(bytes, True{}), width, height, bytes)

def Surface.noise.write(index: U32, threshold: U32, pixels: Array<U32>, draw: Random.State & U32) -> Random.State & Array<U32>:
  (state, value) = draw
  color = Bool.pick(U32, (value % 100 < threshold : U32), 4294967295, 255)
  (state, Array.set(U32, pixels, index, color))

def Surface.noise.loop(n: Nat, +index: U32, +threshold: U32, buffers: Random.State & Array<U32>) -> Random.State & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+k Tuple{state, pixels}:
      Surface.noise.loop(k, (index + 1 : U32), threshold, Surface.noise.write(index, threshold, pixels, Random.next_u32(state)))

def Surface.noise.finished(width: U32, height: U32, buffers: Random.State & Array<U32>) -> Random.State & Maybe<Surface>:
  (state, pixels) = buffers
  (state, Some{Surface{width, height, pixels}})

def Surface.noise.checked(valid: Bool, state: Random.State, +width: U32, +height: U32, factor: F32) -> Random.State & Maybe<Surface>:
  match valid:
    case False{}: (state, None{})
    case True{}:
      +count = (width * height : U32)
      Surface.noise.finished(width, height, Surface.noise.loop(U32.to_nat(count), 0, F32.to_u32((factor * 100.0 : F32)),
        (state, Array.new(U32, Surface.capacity(count), 255))))

def Surface.create_white_noise(state: Random.State, +width: U32, +height: U32, +factor: F32) -> Random.State & Maybe<Surface>:
  Surface.noise.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((factor >= 0.0) && (factor <= 1.0) : F32), state, width, height, factor)

def Surface.cellular.finished(width: U32, height: U32, result: Rng.State & Array<U32>) -> Random.State & Maybe<Surface>:
  (state, pixels) = result
  (RandomState{state}, Some{Surface{width, height, pixels}})

def Surface.cellular.checked(valid: Bool, state: Random.State, +width: U32, +height: U32, tile: U32) -> Random.State & Maybe<Surface>:
  match valid state:
    case False{} _: (state, None{})
    case True{} RandomState{inner}:
      Surface.cellular.finished(width, height, Cellular.generate(inner, width, height, tile))

def Surface.create_cellular(state: Random.State, +width: U32, +height: U32, +tile: U32) -> Random.State & Maybe<Surface>:
  Surface.cellular.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (tile > 0) && (tile <= 4096) : U32), state, width, height, tile)

type Noise.Reference is Data:
  UncontractedNoise{}
  FusedNoise{}

def Noise.fused(reference: Noise.Reference) -> Bool:
  match reference:
    case UncontractedNoise{}: False{}
    case FusedNoise{}: True{}

def Surface.perlin.checked(valid: Bool, reference: Noise.Reference, +width: U32, +height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Perlin.pixels(U32.to_nat(count), 0, Noise.fused(reference), width, height, offset_x, offset_y, scale,
        Array.new(U32, Surface.capacity(count), 255))}}

def Surface.create_perlin_for(reference: Noise.Reference, +width: U32, +height: U32, +offset_x: F32, +offset_y: F32, +scale: F32) -> Maybe<Surface>:
  Surface.perlin.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((F32.abs(offset_x) <= 32767.0) && (F32.abs(offset_y) <= 32767.0) && (F32.abs(scale) <= 256.0) : F32)
    && F32.is_eq(F32.floor(offset_x), offset_x) && F32.is_eq(F32.floor(offset_y), offset_y)
    && (F32.is_eq(scale, 0.0) || (F32.abs(scale) >= 0.0000152587890625 : F32)), reference, width, height, offset_x, offset_y, scale)

def Surface.create_perlin(width: U32, height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Surface>:
  Surface.create_perlin_for(UncontractedNoise{}, width, height, offset_x, offset_y, scale)

def Surface.checked.loop(n: Nat, +i: U32, +width: U32, +tx: U32, +ty: U32, +first: U32, +second: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      color = Bool.pick(U32, U32.is_eq((((i % width) / tx + (i / width) / ty) .&. 1 : U32), 0), first, second)
      Surface.checked.loop(k, (i + 1 : U32), width, tx, ty, first, second, Array.set(U32, pixels, i, color))

def Surface.checked.create(valid: Bool, +width: U32, +height: U32, tx: U32, ty: U32, +first: U32, second: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Surface.checked.loop(U32.to_nat(count), 0, width, tx, ty, first, second, Array.new(U32, Surface.capacity(count), first))}}

def Surface.create_checked(+width: U32, +height: U32, +tx: U32, +ty: U32, first: U32, second: U32) -> Maybe<Surface>:
  Surface.checked.create(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (tx > 0) && (ty > 0) && (tx <= 2147483647) && (ty <= 2147483647) : U32), width, height, tx, ty, first, second)

def Surface.square_gradient.loop(n: Nat, +i: U32, +width: U32, +cx: F32, +cy: F32, +density: F32, +inner: U32, +outer: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      nx = (F32.abs((U32.to_f32((i % width : U32)) - cx : F32)) / cx : F32)
      ny = (F32.abs((U32.to_f32((i / width : U32)) - cy : F32)) / cy : F32)
      factor = ((F32.max(nx, ny) - density) / (1.0 - density) : F32)
      Surface.square_gradient.loop(k, (i + 1 : U32), width, cx, cy, density, inner, outer,
        Array.set(U32, pixels, i, Color.lerp(inner, outer, factor)))

def Surface.square_gradient.checked(valid: Bool, solid: Bool, +width: U32, +height: U32, density: F32, +inner: U32, outer: U32) -> Maybe<Surface>:
  match valid solid:
    case False{} _: None{}
    case True{} True{}: Surface.create(width, height, inner)
    case True{} False{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Surface.square_gradient.loop(U32.to_nat(count), 0, width,
        (U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32), density, inner, outer,
        Array.new(U32, Surface.capacity(count), inner))}}

def Surface.create_gradient_square(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.square_gradient.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), F32.is_eq(density, 1.0), width, height, density, inner, outer)

def Surface.radial.checked(valid: Bool, +width: U32, +height: U32, density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      paint = {Gradients.Radial{(U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32),
        (U32.to_f32(U32.min(width, height)) / 2.0 : F32), density, inner, outer} : Gradients.Paint}
      Some{Surface{width, height, Gradients.generate(Surface.capacity(count), width, count, paint)}}

def Surface.create_gradient_radial(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.radial.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), width, height, density, inner, outer)

def Surface.linear.ready(valid: Bool, +width: U32, +height: U32, cosine: F32, sine: F32, start: F32, extent: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Surface{width, height, Gradients.generate(Surface.capacity(count), width, count,
        Gradients.Linear{cosine, sine, start, extent, inner, outer})}}

def Surface.linear.trigonometry(+width: U32, +height: U32, inner: U32, outer: U32, values: F32 & F32) -> Maybe<Surface>:
  (+cosine, +sine) = values
  +start = (0.5 - cosine * U32.to_f32(width) / 2.0 - sine * U32.to_f32(height) / 2.0 : F32)
  same_sign = U32.is_eq((F32.bits(sine) >> 31n : U32), (F32.bits(cosine) >> 31n : U32))
  +extent = F32.abs(Bool.pick(F32, same_sign, start, (start + U32.to_f32(width) * cosine : F32)))
  Surface.linear.ready((extent > 0.0 : F32), width, height, cosine, sine, start, extent, inner, outer)

def Surface.linear.checked(valid: Bool, reference: M.Gradient.Reference, +width: U32, +height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      radians = ((90.0 - direction) / 180.0 * 3.14159 : F32)
      Surface.linear.trigonometry(width, height, inner, outer, Trig.sincos_for(M.Gradient.gnu(reference), radians))

def Surface.create_gradient_linear_for(reference: M.Gradient.Reference, +width: U32, +height: U32, +direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.linear.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && (F32.abs(direction) <= 360.0 : F32) && F32.is_eq(F32.floor(direction), direction), reference, width, height, direction, inner, outer)

def Surface.create_gradient_linear(width: U32, height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.create_gradient_linear_for(M.AccurateGradient{}, width, height, direction, inner, outer)

def Surface.clear(surface: Surface, color: U32) -> Surface:
  Surface{+w, +h, _} = surface
  Surface{w, h, Array.new(U32, Surface.capacity((w * h : U32)), color)}

def Surface.color.step(i: U32, transform: Color.Transform, got: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = got
  Array.set(U32, pixels, i, Color.transform(transform, pixel))

def Surface.color.loop(n: Nat, +i: U32, +transform: Color.Transform, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      Surface.color.loop(k, (i + 1 : U32), transform, Surface.color.step(i, transform, Array.get(U32, pixels, i)))

def Surface.color.transform(surface: Surface, transform: Color.Transform) -> Surface:
  Surface{+w, +h, pixels} = surface
  Surface{w, h, Surface.color.loop(U32.to_nat((w * h : U32)), 0, transform, pixels)}

def Surface.color_grayscale(surface: Surface) -> Surface:
  Surface.color.transform(surface, ImageGrayscale{})

def Surface.color_tint(surface: Surface, color: U32) -> Surface:
  Surface.color.transform(surface, ImageTint{color})

def Surface.color_invert(surface: Surface) -> Surface:
  Surface.color.transform(surface, ImageInvert{})

def Color.Transform.contrast(amount: F32) -> Color.Transform:
  +contrast = ((100.0 + F32.clamp(amount, (0.0 - 100.0 : F32), 100.0)) / 100.0 : F32)
  ImageContrast{(contrast * contrast : F32)}

def Color.Transform.brightness(amount: F32) -> Color.Transform:
  ImageBrightness{F32.clamp(amount, (0.0 - 255.0 : F32), 255.0)}

def Surface.color_contrast(surface: Surface, amount: F32) -> Surface:
  Surface.color.transform(surface, Color.Transform.contrast(amount))

def Surface.color_brightness(surface: Surface, amount: F32) -> Surface:
  Surface.color.transform(surface, Color.Transform.brightness(amount))

def Surface.color_replace(surface: Surface, original: U32, replacement: U32) -> Surface:
  Surface.color.transform(surface, ImageReplace{original, replacement})

def Image.FloatRGB.color.transformed(transform: Color.Transform, result: Result<&1, &1, Image.FloatRGB, Surface>) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  match result:
    case Fail{image}: Fail{image}
    case Done{surface}: Done{Surface.to_float_rgb(Surface.color.transform(surface, transform))}

def Image.FloatRGB.color.transform(valid: Bool, image: Image.FloatRGB, transform: Color.Transform) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  match valid:
    case False{}: Fail{image}
    case True{}: Image.FloatRGB.color.transformed(transform, Image.FloatRGB.to_surface(image))

def Image.FloatRGB.color.finite(amount: F32) -> Bool:
  ((F32.bits(amount) .&. 2147483647) < 2139095040 : U32)

def Image.FloatRGB.color.integral(+amount: F32) -> Bool:
  +bits = (F32.bits(amount) .&. 2147483647 : U32)
  (bits < 2139095040 : U32) && (U32.is_eq(bits, 0) || ((bits >= 1065353216 : U32) && F32.is_eq(F32.floor(amount), amount)))

def Image.FloatRGB.color_tint(image: Image.FloatRGB, color: U32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.color.transform(True{}, image, ImageTint{color})

def Image.FloatRGB.color_invert(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.color.transform(True{}, image, ImageInvert{})

def Image.FloatRGB.color_contrast(image: Image.FloatRGB, +amount: F32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.color.transform(Image.FloatRGB.color.finite(amount), image, Color.Transform.contrast(amount))

def Image.FloatRGB.color_brightness(image: Image.FloatRGB, +amount: F32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.color.transform(Image.FloatRGB.color.integral(amount), image, Color.Transform.brightness(amount))

def Image.FloatRGB.color_replace(image: Image.FloatRGB, original: U32, replacement: U32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.color.transform(True{}, image, ImageReplace{original, replacement})

def Surface.alpha_clear(surface: Surface, color: U32, threshold: F32) -> Surface:
  Surface.color.transform(surface, AlphaClear{F32.to_u32((threshold * 255.0 : F32)), color})

def Surface.alpha_premultiply(surface: Surface) -> Surface:
  Surface.color.transform(surface, AlphaPremultiply{})

def Surface.blur_gaussian.premultiplied(size: U32, surface: Surface) -> Surface:
  Surface{+width, +height, pixels} = surface
  Surface{width, height, Blur.blur(width, height, size, pixels)}

def Surface.blur_gaussian.checked(valid: Bool, surface: Surface, size: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}: Done{Surface.blur_gaussian.premultiplied(size, Surface.alpha_premultiply(surface))}

def Surface.blur_gaussian(surface: Surface, +size: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, pixels} = surface
  Surface.blur_gaussian.checked(((size <= width) && (size <= height) : U32), Surface{width, height, pixels}, size)

def Surface.convolution.result(width: U32, height: U32, result: Result<&1, &1, Array<U32>, Array<U32>>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Fail{source}: Fail{(Surface{width, height, source}, InvalidKernel{})}
    case Done{output}: Done{Surface{width, height, output}}

def Surface.kernel_convolution(surface: Surface, kernel: +List<F32>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, pixels} = surface
  Surface.convolution.result(width, height, Convolution.apply(width, height, kernel, pixels))

def Surface.mask.pixel(destination: Array<U32> & U32, source: Array<U32> & U32, at: U32) -> Array<U32> & Array<U32>:
  (dst, color) = destination
  (mask, value) = source
  (Array.set(U32, dst, at, ((color .&. 4294967040) .|. Color.grayscale(value) : U32)), mask)

def Surface.mask.loop(n: Nat, +at: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+k Tuple{dst, mask}:
      Surface.mask.loop(k, (at + 1 : U32), Surface.mask.pixel(Array.get(U32, dst, at), Array.get(U32, mask, at), at))

def Surface.mask.finish(+w: U32, +h: U32, state: Array<U32> & Array<U32>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (dst, mask) = state
  Done{(Surface{w, h, dst}, Surface{w, h, mask})}

def Surface.mask.checked(valid: Bool, +w: U32, +h: U32, mw: U32, mh: U32, dst: Array<U32>, mask: Array<U32>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((Surface{w, h, dst}, Surface{mw, mh, mask}), InvalidSize{})}
    case True{}: Surface.mask.finish(w, h, Surface.mask.loop(U32.to_nat((w * h : U32)), 0, (dst, mask)))

def Surface.alpha_mask(destination: Surface, source: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, dst} = destination
  Surface{+mw, +mh, mask} = source
  Surface.mask.checked(U32.is_eq(w, mw) && U32.is_eq(h, mh), w, h, mw, mh, dst, mask)

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

def Surface.draw_pixel_v(surface: Surface, position: M.Vector2, color: U32) -> Surface:
  M.Vector2{x, y} = position
  Surface.draw_pixel(surface, Signed.trunc(x), Signed.trunc(y), color)

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

def Surface.draw_rectangle_v(surface: Surface, position: M.Vector2, size: M.Vector2, color: U32) -> Surface:
  M.Vector2{x, y} = position
  M.Vector2{width, height} = size
  Surface.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), Signed.trunc(height), color)

def Surface.draw_rectangle_rec(surface: Surface, rect: Rectangle, color: U32) -> Surface:
  Rectangle{x, y, width, height} = rect
  Surface.draw_rectangle(surface, x, y, width, height, color)

def Surface.draw_rectangle_lines(surface: Surface, rect: Rectangle, +thickness: U32, +color: U32) -> Surface:
  Rectangle{+x, +y, +width, +height} = rect
  +t = U32.to_f32(thickness)
  s0 = Surface.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), t, color)
  s1 = Surface.draw_rectangle(s0, Signed.trunc(x), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  s2 = Surface.draw_rectangle(s1, Signed.trunc((x + width - t : F32)), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  Surface.draw_rectangle(s2, Signed.trunc(x), Signed.trunc((y + height - t : F32)), Signed.trunc(width), t, color)

def Surface.circle.plot(outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +color: U32, surface: Surface) -> Surface:
  match outline:
    case False{}:
      s0 = Surface.draw_rectangle(surface, (cx - x : F32), (cy + y : F32), (x * 2.0 : F32), 1.0, color)
      s1 = Surface.draw_rectangle(s0, (cx - x : F32), (cy - y : F32), (x * 2.0 : F32), 1.0, color)
      s2 = Surface.draw_rectangle(s1, (cx - y : F32), (cy + x : F32), (y * 2.0 : F32), 1.0, color)
      Surface.draw_rectangle(s2, (cx - y : F32), (cy - x : F32), (y * 2.0 : F32), 1.0, color)
    case True{}:
      s0 = Surface.draw_pixel(surface, (cx + x : F32), (cy + y : F32), color)
      s1 = Surface.draw_pixel(s0, (cx - x : F32), (cy + y : F32), color)
      s2 = Surface.draw_pixel(s1, (cx + x : F32), (cy - y : F32), color)
      s3 = Surface.draw_pixel(s2, (cx - x : F32), (cy - y : F32), color)
      s4 = Surface.draw_pixel(s3, (cx + y : F32), (cy + x : F32), color)
      s5 = Surface.draw_pixel(s4, (cx - y : F32), (cy + x : F32), color)
      s6 = Surface.draw_pixel(s5, (cx + y : F32), (cy - x : F32), color)
      Surface.draw_pixel(s6, (cx - y : F32), (cy - x : F32), color)

def Surface.circle.loop(fuel: Nat, on: Bool, +outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +error: F32, +color: U32, surface: Surface) -> Surface:
  match fuel on:
    case 0n _:
      surface
    case 1n+k False{}:
      surface
    case 1n+k True{}:
      drawn = Surface.circle.plot(outline, cx, cy, x, y, color, surface)
      +nx = (x + 1.0 : F32)
      +down = (error > 0.0 : F32)
      +ny = Bool.pick(F32, down, (y - 1.0 : F32), y)
      ne = Bool.pick(F32, down, (error + 4.0 * (nx - ny) + 10.0 : F32), (error + 4.0 * nx + 6.0 : F32))
      Surface.circle.loop(k, (ny >= nx : F32), outline, cx, cy, nx, ny, ne, color, drawn)

# Midpoint scanlines match raylib ImageDrawCircle, including its edge coverage.
def Surface.draw_circle(surface: Surface, cx: F32, cy: F32, +radius: U32, color: U32) -> Surface:
  +r = U32.to_f32(radius)
  Surface.circle.loop(1n+U32.to_nat(radius), True{}, False{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Surface.draw_circle_v(surface: Surface, center: M.Vector2, radius: U32, color: U32) -> Surface:
  M.Vector2{x, y} = center
  Surface.draw_circle(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Surface.draw_circle_lines(surface: Surface, cx: F32, cy: F32, +radius: U32, color: U32) -> Surface:
  +r = U32.to_f32(radius)
  Surface.circle.loop(1n+U32.to_nat(radius), True{}, True{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Surface.draw_circle_lines_v(surface: Surface, center: M.Vector2, radius: U32, color: U32) -> Surface:
  M.Vector2{x, y} = center
  Surface.draw_circle_lines(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Surface.line.loop(n: Nat, +vertical: Bool, +x: F32, +y: F32, +direction: F32, +major: F32, +minor: U32, +step: U32, +color: U32, surface: Surface) -> Surface:
  match n:
    case 0n:
      surface
    case 1n+k:
      +offset = Signed.high16(minor)
      px = (x + Bool.pick(F32, vertical, offset, major) : F32)
      py = (y + Bool.pick(F32, vertical, major, offset) : F32)
      Surface.line.loop(k, vertical, x, y, direction, (major + direction : F32),
        (minor + step : U32), step, color, Surface.draw_pixel(surface, px, py, color))

# The 16.16 short-axis accumulator and excluded final endpoint match ImageDrawLine.
def Surface.draw_line(surface: Surface, +x0: F32, +y0: F32, x1: F32, y1: F32, color: U32) -> Surface:
  +dx = (x1 - x0 : F32)
  +dy = (y1 - y0 : F32)
  +vertical = (F32.abs(dy) > F32.abs(dx) : F32)
  +long = Bool.pick(F32, vertical, dy, dx)
  +short = Bool.pick(F32, vertical, dx, dy)
  +count = F32.to_u32(F32.abs(long))
  +magnitude = ((F32.to_u32(F32.abs(short)) << 16n) / U32.max(1, count) : U32)
  step = Bool.pick(U32, (short < 0.0 : F32), (0 - magnitude : U32), magnitude)
  Surface.line.loop(U32.to_nat(count), vertical, x0, y0,
    Bool.pick(F32, (long < 0.0 : F32), (0.0 - 1.0 : F32), 1.0), 0.0, 0, step, color, surface)

def Surface.draw_line_v(surface: Surface, start: M.Vector2, end: M.Vector2, color: U32) -> Surface:
  M.Vector2{x0, y0} = start
  M.Vector2{x1, y1} = end
  Surface.draw_line(surface, Signed.trunc((x0 + 0.5 : F32)), Signed.trunc((y0 + 0.5 : F32)),
    Signed.trunc((x1 + 0.5 : F32)), Signed.trunc((y1 + 0.5 : F32)), color)

def Surface.thick_line.loop(n: Nat, +horizontal: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +offset: F32, +step: F32, +color: U32, surface: Surface) -> Surface:
  match n:
    case 0n: surface
    case 1n+k:
      +ox = Bool.pick(F32, horizontal, 0.0, offset)
      +oy = Bool.pick(F32, horizontal, offset, 0.0)
      Surface.thick_line.loop(k, horizontal, x0, y0, x1, y1, (offset + step : F32), step, color,
        Surface.draw_line(surface, (x0 + ox : F32), (y0 + oy : F32), (x1 + ox : F32), (y1 + oy : F32), color))

def Surface.draw_line_ex(surface: Surface, start: M.Vector2, end: M.Vector2, +thickness: U32, +color: U32) -> Surface:
  M.Vector2{x0, y0} = start
  M.Vector2{x1, y1} = end
  +ax = Signed.trunc((x0 + 0.5 : F32))
  +ay = Signed.trunc((y0 + 0.5 : F32))
  +bx = Signed.trunc((x1 + 0.5 : F32))
  +by = Signed.trunc((y1 + 0.5 : F32))
  +horizontal = (F32.abs((by - ay : F32)) < F32.abs((bx - ax : F32)) : F32)
  lower = Surface.thick_line.loop(U32.to_nat((thickness / 2 + 1 : U32)), horizontal, ax, ay, bx, by, 0.0, 1.0, color, surface)
  Surface.thick_line.loop(U32.to_nat(((U32.max(1, thickness) - 1) / 2 : U32)), horizontal, ax, ay, bx, by, (0.0 - 1.0 : F32), (0.0 - 1.0 : F32), color, lower)

type Raster.Edge is Data:
  Edge{value: U32, dx: U32, dy: U32}

type Raster.Paint is Data:
  FlatPaint{color: U32}
  VertexPaint{first: U32, second: U32, third: U32, inverse: F32}

def Raster.paint(paint: Raster.Paint, a: U32, b: U32, c: U32) -> U32:
  match paint:
    case FlatPaint{color}: color
    case VertexPaint{+first, +second, +third, +inverse}:
      +wa = F32.to_u32((U32.to_f32(a) * inverse : F32))
      +wb = F32.to_u32((U32.to_f32(b) * inverse : F32))
      +wc = F32.to_u32((U32.to_f32(c) * inverse : F32))
      Color.rgba(((Color.red(first) * wa + Color.red(second) * wb + Color.red(third) * wc) / 255 : U32),
        ((Color.green(first) * wa + Color.green(second) * wb + Color.green(third) * wc) / 255 : U32),
        ((Color.blue(first) * wa + Color.blue(second) * wb + Color.blue(third) * wc) / 255 : U32),
        ((Color.alpha(first) * wa + Color.alpha(second) * wb + Color.alpha(third) * wc) / 255 : U32))

def Raster.inverse(a: Raster.Edge, b: Raster.Edge, c: Raster.Edge) -> F32:
  Edge{av, _, _} = a
  Edge{bv, _, _} = b
  Edge{cv, _, _} = c
  (255.0 / Signed.to_f32((av + bv + cv : U32)) : F32)

def Raster.edge(x: F32, y: F32, vx: F32, vy: F32, +dx: F32, +dy: F32) -> Raster.Edge:
  Edge{Signed.word(((x - vx) * dx + dy * (y - vy) : F32)), Signed.word(dx), Signed.word(dy)}

def Surface.triangle.pixel(inside: Bool, pixels: Array<U32>, at: U32, paint: Raster.Paint, a: U32, b: U32, c: U32) -> Array<U32>:
  match inside:
    case False{}:
      pixels
    case True{}:
      Array.set(U32, pixels, at, Raster.paint(paint, a, b, c))

def Surface.triangle.row(n: Nat, +at: U32, +a: U32, +b: U32, +c: U32, +ax: U32, +bx: U32, +cx: U32, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      inside = U32.is_eq(((a .|. b .|. c) .&. 2147483648 : U32), 0)
      Surface.triangle.row(k, (at + 1 : U32), (a + ax : U32), (b + bx : U32), (c + cx : U32),
        ax, bx, cx, paint, Surface.triangle.pixel(inside, pixels, at, paint, a, b, c))

def Surface.triangle.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, ea: Raster.Edge, eb: Raster.Edge, ec: Raster.Edge, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Edge{+a, +ax, +ay} = ea
      Edge{+b, +bx, +by} = eb
      Edge{+c, +cx, +cy} = ec
      Surface.triangle.rows(k, (at + stride : U32), stride, cols,
        Edge{(a + ay : U32), ax, ay}, Edge{(b + by : U32), bx, by}, Edge{(c + cy : U32), cx, cy}, paint,
        Surface.triangle.row(cols, at, a, b, c, ax, bx, cx, paint, pixels))

def Surface.triangle.fill(visible: Bool, +w: U32, h: U32, pixels: Array<U32>, +x0: F32, +y0: F32, x1: F32, y1: F32, a: Raster.Edge, b: Raster.Edge, c: Raster.Edge, paint: Raster.Paint) -> Surface:
  match visible:
    case False{}:
      Surface{w, h, pixels}
    case True{}:
      cols = U32.to_nat(F32.to_u32((x1 - x0 + 1.0 : F32)))
      rows = U32.to_nat(F32.to_u32((y1 - y0 + 1.0 : F32)))
      Surface{w, h, Surface.triangle.rows(rows, (F32.to_u32(y0) * w + F32.to_u32(x0) : U32), w,
        cols, a, b, c, paint, pixels)}

def Surface.draw_triangle(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, color: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  M.Vector2{+ax, +ay} = v1
  M.Vector2{+bx, +by} = v2
  M.Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, F32.min(ax, F32.min(bx, cx)))
  +y0 = F32.max(0.0, F32.min(ay, F32.min(by, cy)))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), F32.max(ax, F32.max(bx, cx)))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), F32.max(ay, F32.max(by, cy)))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  Surface.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1,
    Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32)),
    Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32)),
    Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32)), FlatPaint{color})

def Surface.draw_triangle_ex(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, c1: U32, c2: U32, c3: U32) -> Surface:
  Surface{+w, +h, pixels} = surface
  M.Vector2{+ax, +ay} = v1
  M.Vector2{+bx, +by} = v2
  M.Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, F32.min(ax, F32.min(bx, cx)))
  +y0 = F32.max(0.0, F32.min(ay, F32.min(by, cy)))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), F32.max(ax, F32.max(bx, cx)))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), F32.max(ay, F32.max(by, cy)))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  +ea = Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32))
  +eb = Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32))
  +ec = Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32))
  Surface.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1, ea, eb, ec,
    VertexPaint{c1, c2, c3, Raster.inverse(ea, eb, ec)})

def Surface.draw_triangle_lines(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, +color: U32) -> Surface:
  M.Vector2{ax, ay} = v1
  M.Vector2{bx, by} = v2
  M.Vector2{cx, cy} = v3
  +x0 = Signed.trunc(ax)
  +y0 = Signed.trunc(ay)
  +x1 = Signed.trunc(bx)
  +y1 = Signed.trunc(by)
  +x2 = Signed.trunc(cx)
  +y2 = Signed.trunc(cy)
  a = Surface.draw_line(surface, x0, y0, x1, y1, color)
  b = Surface.draw_line(a, x1, y1, x2, y2, color)
  Surface.draw_line(b, x2, y2, x0, y0, color)

def Surface.fan.loop(points: +List<M.Vector2>, +center: M.Vector2, previous: M.Vector2, +color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Surface.fan.loop(rest, center, next, color, Surface.draw_triangle(surface, center, previous, next, color))

def Surface.fan.start(points: +List<M.Vector2>, center: M.Vector2, color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Surface.fan.loop(rest, center, previous, color, surface)

def Surface.draw_triangle_fan(surface: Surface, points: +List<M.Vector2>, color: U32) -> Surface:
  match points:
    case Nil{}: surface
    case Con{center, rest}: Surface.fan.start(rest, center, color, surface)

def Surface.strip.loop(points: +List<M.Vector2>, +older: M.Vector2, +previous: M.Vector2, +even: Bool, +color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Surface.strip.loop(rest, previous, next, Bool.not(even), color,
        Surface.draw_triangle(surface, next, Bool.pick(M.Vector2, even, older, previous), Bool.pick(M.Vector2, even, previous, older), color))

def Surface.strip.start(points: +List<M.Vector2>, older: M.Vector2, color: U32, surface: Surface) -> Surface:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Surface.strip.loop(rest, older, previous, True{}, color, surface)

def Surface.draw_triangle_strip(surface: Surface, points: +List<M.Vector2>, color: U32) -> Surface:
  match points:
    case Nil{}: surface
    case Con{older, rest}: Surface.strip.start(rest, older, color, surface)

def Surface.blit.pixel(source: Array<U32> & U32, destination: Array<U32> & U32, at: U32, tint: U32) -> Array<U32> & Array<U32>:
  (src, sc) = source
  (dst, dc) = destination
  (src, Array.set(U32, dst, at, Color.alpha_blend(dc, sc, tint)))

def Surface.blit.row(n: Nat, +si: U32, +di: U32, +tint: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      buffers
    case 1n+k:
      (src, dst) = buffers
      Surface.blit.row(k, (si + 1 : U32), (di + 1 : U32), tint,
        Surface.blit.pixel(Array.get(U32, src, si), Array.get(U32, dst, di), di, tint))

def Surface.blit.rows(n: Nat, +cols: Nat, +si: U32, +di: U32, +sw: U32, +dw: U32, +tint: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      buffers
    case 1n+k:
      Surface.blit.rows(k, cols, (si + sw : U32), (di + dw : U32), sw, dw, tint,
        Surface.blit.row(cols, si, di, tint, buffers))

def Surface.blit.finish(dw: U32, dh: U32, sw: U32, sh: U32, buffers: Array<U32> & Array<U32>) -> Surface & Surface:
  (src, dst) = buffers
  (Surface{dw, dh, dst}, Surface{sw, sh, src})

type Raster.Mapping is Data:
  Region{stride: U32, columns: U32, x: U32, y: U32}
  Nearest{stride: U32, columns: U32, xr: U32, yr: U32}
  QuarterTurn{width: U32, height: U32, clockwise: Bool}
  Mirrored{width: U32, height: U32, horizontal: Bool}

def Raster.index(mapping: Raster.Mapping, +i: U32) -> U32:
  match mapping:
    case Region{stride, +columns, x, y}:
      ((y + i / columns) * stride + x + i % columns : U32)
    case Nearest{stride, +columns, xr, yr}:
      ((((i / columns) * yr) >> 16n) * stride + (((i % columns) * xr) >> 16n) : U32)
    case QuarterTurn{+width, +height, clockwise}:
      Bool.pick(U32, clockwise, ((height - 1 - i % height) * width + i / height : U32),
        ((i % height) * width + width - 1 - i / height : U32))
    case Mirrored{+width, height, horizontal}:
      +x = (i % width : U32)
      +y = (i / width : U32)
      Bool.pick(U32, horizontal, (y * width + width - 1 - x : U32), ((height - 1 - y) * width + x : U32))

def Raster.sample.loop(~T: Data, more: Nat, +i: U32, +mapping: Raster.Mapping, output: Array<T>, got: Array<T> & T) -> Array<T> & Array<T>:
  match more got:
    case 0n Tuple{source, color}:
      (source, Array.set(T, output, i, color))
    case 1n+k Tuple{source, color}:
      +next = (i + 1 : U32)
      Raster.sample.loop(~T, k, next, mapping, Array.set(T, output, i, color),
        Array.get(T, source, Raster.index(mapping, next)))

def Raster.sample(~T: Data, +count: U32, +mapping: Raster.Mapping, initial: T, source: Array<T>) -> Array<T> & Array<T>:
  Raster.sample.loop(~T, U32.to_nat((count - 1 : U32)), 0, mapping,
    Array.new(T, Surface.capacity(count), initial), Array.get(T, source, Raster.index(mapping, 0)))

def Surface.sample(+count: U32, +mapping: Raster.Mapping, source: Array<U32>) -> Array<U32> & Array<U32>:
  Raster.sample(~U32, count, mapping, 0, source)

type Raster.AlphaBounds is Data:
  AlphaBounds{left: U32, top: U32, right: U32, bottom: U32}

def Surface.border.expand(selected: Bool, +x: U32, +y: U32, bounds: Raster.AlphaBounds) -> Raster.AlphaBounds:
  match selected:
    case False{}: bounds
    case True{}:
      AlphaBounds{left, top, right, bottom} = bounds
      AlphaBounds{U32.min(left, x), U32.min(top, y), U32.max(right, x), U32.max(bottom, y)}

def Surface.border.pixel(+i: U32, +width: U32, threshold: U32, bounds: Raster.AlphaBounds, got: Array<U32> & U32) -> Array<U32> & Raster.AlphaBounds:
  (pixels, color) = got
  (pixels, Surface.border.expand((Color.alpha(color) > threshold : U32), (i % width : U32), (i / width : U32), bounds))

def Surface.border.scan(n: Nat, +i: U32, +width: U32, +threshold: U32, state: Array<U32> & Raster.AlphaBounds) -> Array<U32> & Raster.AlphaBounds:
  match n state:
    case 0n _: state
    case 1n+k Tuple{pixels, bounds}:
      Surface.border.scan(k, (i + 1 : U32), width, threshold, Surface.border.pixel(i, width, threshold, bounds, Array.get(U32, pixels, i)))

def Surface.border.finish(+width: U32, height: U32, result: Array<U32> & Raster.AlphaBounds) -> Surface & Rectangle:
  match result:
    case Tuple{pixels, AlphaBounds{+left, +top, right, bottom}}:
      (Surface{width, height, pixels}, Bool.pick(Rectangle, U32.is_eq(left, width), Rectangle{0.0, 0.0, 0.0, 0.0},
        Rectangle{U32.to_f32(left), U32.to_f32(top), U32.to_f32((right + 1 - left : U32)), U32.to_f32((bottom + 1 - top : U32))}))

def Surface.alpha_border(surface: Surface, threshold: F32) -> Surface & Rectangle:
  Surface{+width, +height, pixels} = surface
  Surface.border.finish(width, height, Surface.border.scan(U32.to_nat((width * height : U32)), 0, width,
    F32.to_u32((threshold * 255.0 : F32)), (pixels, AlphaBounds{width, height, 0, 0})))

def Surface.alpha_crop.pixels(width: U32, height: U32, buffers: Array<U32> & Array<U32>) -> Surface:
  (_, pixels) = buffers
  Surface{width, height, pixels}

def Surface.alpha_crop.route(empty: Bool, surface: Surface, rect: Rectangle) -> Surface:
  match empty:
    case True{}: surface
    case False{}:
      Surface{sw, _, pixels} = surface
      Rectangle{x, y, rw, rh} = rect
      +width = F32.to_u32(rw)
      +height = F32.to_u32(rh)
      Surface.alpha_crop.pixels(width, height, Surface.sample((width * height : U32),
        Region{sw, width, F32.to_u32(x), F32.to_u32(y)}, pixels))

def Surface.alpha_crop.observed(result: Surface & Rectangle) -> Surface:
  match result:
    case Tuple{surface, Rectangle{+x, +y, +width, +height}}:
      Surface.alpha_crop.route(F32.is_eq(width, 0.0), surface, Rectangle{x, y, width, height})

def Surface.alpha_crop(surface: Surface, threshold: F32) -> Surface:
  Surface.alpha_crop.observed(Surface.alpha_border(surface, threshold))

def Surface.rotate.result(width: U32, height: U32, buffers: Array<U32> & Array<U32>) -> Surface:
  (_, output) = buffers
  Surface{height, width, output}

def Surface.rotate(surface: Surface, clockwise: Bool) -> Surface:
  Surface{+width, +height, pixels} = surface
  Surface.rotate.result(width, height, Surface.sample((width * height : U32), QuarterTurn{width, height, clockwise}, pixels))

def Surface.rotate_cw(surface: Surface) -> Surface:
  Surface.rotate(surface, True{})

def Surface.rotate_ccw(surface: Surface) -> Surface:
  Surface.rotate(surface, False{})

def Surface.extract.finish(sw: U32, sh: U32, w: U32, h: U32, buffers: Array<U32> & Array<U32>) -> Surface & Maybe<Surface>:
  (source, region) = buffers
  (Surface{sw, sh, source}, Some{Surface{w, h, region}})

def Surface.extract.checked(valid: Bool, +sw: U32, sh: U32, pixels: Array<U32>, x: F32, y: F32, width: F32, height: F32) -> Surface & Maybe<Surface>:
  match valid:
    case False{}:
      (Surface{sw, sh, pixels}, None{})
    case True{}:
      +w = F32.to_u32(width)
      +h = F32.to_u32(height)
      Surface.extract.finish(sw, sh, w, h, Surface.sample((w * h : U32),
        Region{sw, w, F32.to_u32(x), F32.to_u32(y)}, pixels))

def Rectangle.integral(rect: Rectangle) -> Bool:
  Rectangle{+x, +y, +w, +h} = rect
  F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y)
    && F32.is_eq(F32.floor(w), w) && F32.is_eq(F32.floor(h), h)

def Rectangle.inside(rect: Rectangle, sw: U32, sh: U32) -> Bool:
  Rectangle{+x, +y, +w, +h} = rect
  ((x >= 0.0) && (y >= 0.0) && (w >= 1.0) && (h >= 1.0)
    && (x + w <= U32.to_f32(sw)) && (y + h <= U32.to_f32(sh)) : F32)

def Rectangle.crop.bounds(rect: Rectangle, sw: U32, sh: U32) -> Rectangle:
  Rectangle{+x, +y, width, height} = rect
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  cw = F32.min((width + F32.min(0.0, x) : F32), (U32.to_f32(sw) - sx : F32))
  ch = F32.min((height + F32.min(0.0, y) : F32), (U32.to_f32(sh) - sy : F32))
  Rectangle{sx, sy, cw, ch}

# ImageFromImage profile: positive integral in-bounds rectangle; source retained.
def Surface.extract(surface: Surface, +rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{+w, +h, pixels} = surface
  Rectangle{x, y, rw, rh} = rect
  Surface.extract.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h), w, h, pixels, x, y, rw, rh)

def Surface.crop.result(result: Surface & Maybe<Surface>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Tuple{original, None{}}:
      Fail{(original, InvalidRectangle{})}
    case Tuple{_, Some{region}}:
      Done{region}

def Surface.crop.route(integral: Bool, outside: Bool, original: Surface, rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match integral outside:
    case False{} _:
      Fail{(original, InvalidRectangle{})}
    case True{} True{}:
      Done{original}
    case True{} False{}:
      Surface.crop.result(Surface.extract(original, rect))

def Surface.crop(surface: Surface, +rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+w, +h, pixels} = surface
  Rectangle{x, y, _, _} = rect
  Surface.crop.route(Rectangle.integral(rect), ((x > U32.to_f32(w)) || (y > U32.to_f32(h)) : F32),
    Surface{w, h, pixels}, Rectangle.crop.bounds(rect, w, h))

def Surface.resize.finish(w: U32, h: U32, buffers: Array<U32> & Array<U32>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  (old, pixels) = buffers
  Done{Surface{w, h, pixels}}

def Surface.nearest.mapping(safe: Bool, sw: U32, sh: U32, pixels: Array<U32>, +w: U32, +h: U32, xr: U32, yr: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match safe:
    case False{}:
      Fail{(Surface{sw, sh, pixels}, UnsafeNearestMapping{})}
    case True{}:
      Surface.resize.finish(w, h, Surface.sample((w * h : U32), Nearest{sw, w, xr, yr}, pixels))

def Surface.nearest.checked(valid: Bool, +sw: U32, +sh: U32, pixels: Array<U32>, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}:
      Fail{(Surface{sw, sh, pixels}, InvalidSize{})}
    case True{}:
      +xr = (((sw << 16n) / w) + 1 : U32)
      +yr = (((sh << 16n) / h) + 1 : U32)
      last = (((((h - 1) * yr) >> 16n) * sw) + (((w - 1) * xr) >> 16n) : U32)
      Surface.nearest.mapping((last < sw * sh : U32), sw, sh, pixels, w, h, xr, yr)

# Preserve raylib's +1 fixed-point ratios. Refuse mappings beyond logical storage.
def Surface.resize_nn(surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{sw, sh, pixels} = surface
  Surface.nearest.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), sw, sh, pixels, w, h)

def Surface.resize.checked(valid: Bool, surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Surface{sw, sh, pixels} = surface
      Done{Surface{w, h, Resample.resize(sw, sh, w, h, pixels)}}

def Surface.resize(surface: Surface, +w: U32, +h: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.resize.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), surface, w, h)

def Raster.canvas.pixel(~T: Data, at: U32, output: Array<T>, got: Array<T> & T) -> Array<T> & Array<T>:
  (source, color) = got
  (source, Array.set(T, output, at, color))

def Raster.canvas.copy(~T: Data, n: Nat, +i: U32, +cols: U32, +sw: U32, +dw: U32, +source_at: U32, +output_at: U32, buffers: Array<T> & Array<T>) -> Array<T> & Array<T>:
  match n buffers:
    case 0n _: buffers
    case 1n+k Tuple{source, output}:
      +x = (i % cols : U32)
      +y = (i / cols : U32)
      Raster.canvas.copy(~T, k, (i + 1 : U32), cols, sw, dw, source_at, output_at,
        Raster.canvas.pixel(~T, (output_at + y * dw + x : U32), output, Array.get(T, source, (source_at + y * sw + x : U32))))

type Raster.Canvas is Data:
  Canvas{sx: U32, sy: U32, dx: U32, dy: U32, columns: U32, rows: U32}

def Raster.canvas.mapping(sw: U32, sh: U32, width: U32, height: U32, +x: F32, +y: F32) -> Raster.Canvas:
  +sx = F32.max(0.0, F32.neg(x))
  +sy = F32.max(0.0, F32.neg(y))
  +dx = F32.max(0.0, x)
  +dy = F32.max(0.0, y)
  cols = F32.max(0.0, F32.min((U32.to_f32(sw) - sx : F32), (U32.to_f32(width) - dx : F32)))
  rows = F32.max(0.0, F32.min((U32.to_f32(sh) - sy : F32), (U32.to_f32(height) - dy : F32)))
  Canvas{F32.to_u32(sx), F32.to_u32(sy), F32.to_u32(dx), F32.to_u32(dy), F32.to_u32(cols), F32.to_u32(rows)}

def Surface.canvas.overlap(valid: Bool, +sw: U32, sh: U32, pixels: Array<U32>, +width: U32, +height: U32, sx: U32, sy: U32, dx: U32, dy: U32, +cols: U32, rows: U32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(Surface{sw, sh, pixels}, InvalidRectangle{})}
    case True{}:
      Surface.resize.finish(width, height, Raster.canvas.copy(~U32, U32.to_nat((cols * rows : U32)), 0, cols, sw, width,
        (sy * sw + sx : U32), (dy * width + dx : U32), (pixels, Array.new(U32, Surface.capacity((width * height : U32)), fill))))

def Surface.canvas.mapped(sw: U32, sh: U32, pixels: Array<U32>, width: U32, height: U32, fill: U32, mapping: Raster.Canvas) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Canvas{sx, sy, dx, dy, +cols, +rows} = mapping
  Surface.canvas.overlap(((cols >= 1) && (rows >= 1) : U32), sw, sh, pixels, width, height, sx, sy, dx, dy, cols, rows, fill)

def Surface.canvas.route(same: Bool, +sw: U32, +sh: U32, pixels: Array<U32>, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match same:
    case True{}: Done{Surface{sw, sh, pixels}}
    case False{}:
      Surface.canvas.mapped(sw, sh, pixels, width, height, fill, Raster.canvas.mapping(sw, sh, width, height, x, y))

def Surface.canvas.checked(size_ok: Bool, offsets_ok: Bool, surface: Surface, +width: U32, +height: U32, x: F32, y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match size_ok offsets_ok:
    case False{} _: Fail{(surface, InvalidSize{})}
    case True{} False{}: Fail{(surface, InvalidRectangle{})}
    case True{} True{}:
      Surface{+sw, +sh, pixels} = surface
      Surface.canvas.route(U32.is_eq(sw, width) && U32.is_eq(sh, height), sw, sh, pixels, width, height, x, y, fill)

def Surface.resize_canvas(surface: Surface, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.canvas.checked(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) : F32)
      && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), surface, width, height, x, y, fill)

def Surface.to_pot(surface: Surface, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, pixels} = surface
  Surface.resize_canvas(Surface{width, height, pixels}, U32.shln(1, Surface.capacity(width)), U32.shln(1, Surface.capacity(height)), 0.0, 0.0, fill)

def Surface.rotation.sized(valid: Bool, surface: Surface, +width: U32, +height: U32, cosine: F32, sine: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Surface{sw, sh, pixels} = surface
      Done{Surface{width, height, Rotation.render(sw, sh, width, height, cosine, sine, pixels)}}

def Surface.rotation.trigonometry(surface: Surface, values: F32 & F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+sw, +sh, pixels} = surface
  (+cosine, +sine) = values
  +width = F32.to_u32((F32.abs((U32.to_f32(sw) * cosine : F32)) + F32.abs((U32.to_f32(sh) * sine : F32)) : F32))
  +height = F32.to_u32((F32.abs((U32.to_f32(sh) * cosine : F32)) + F32.abs((U32.to_f32(sw) * sine : F32)) : F32))
  Surface.rotation.sized(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    Surface{sw, sh, pixels}, width, height, cosine, sine)

def Surface.rotation.checked(valid: Bool, reference: M.Gradient.Reference, surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidRectangle{})}
    case True{}:
      radians = (degrees * 3.14159265358979323846 / 180.0 : F32)
      Surface.rotation.trigonometry(surface, Trig.sincos_for(M.Gradient.gnu(reference), radians))

def Surface.rotate_degrees_for(reference: M.Gradient.Reference, surface: Surface, +degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotation.checked((F32.abs(degrees) <= 360.0 : F32) && F32.is_eq(F32.floor(degrees), degrees), reference, surface, degrees)

def Surface.rotate_degrees(surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotate_degrees_for(M.AccurateGradient{}, surface, degrees)

def Surface.blit.region(destination: Surface, source: Surface, rect: Rectangle, +x: F32, +y: F32, tint: U32) -> Surface & Surface:
  Surface{+dw, +dh, dst} = destination
  Surface{+sw, +sh, src} = source
  Rectangle{rx, ry, rw, rh} = rect
  +skipx = F32.max(0.0, (0.0 - x : F32))
  +skipy = F32.max(0.0, (0.0 - y : F32))
  +dx = F32.max(0.0, x)
  +dy = F32.max(0.0, y)
  cols = F32.to_u32(F32.max(0.0, F32.min((rw - skipx : F32), (U32.to_f32(dw) - dx : F32))))
  rows = F32.to_u32(F32.max(0.0, F32.min((rh - skipy : F32), (U32.to_f32(dh) - dy : F32))))
  Surface.blit.finish(dw, dh, sw, sh, Surface.blit.rows(U32.to_nat(rows), U32.to_nat(cols),
    (F32.to_u32((ry + skipy : F32)) * sw + F32.to_u32((rx + skipx : F32)) : U32),
    (F32.to_u32(dy) * dw + F32.to_u32(dx) : U32), sw, dw, tint, (src, dst)))

def Surface.region.checked(valid: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}:
      Fail{((destination, source), InvalidRectangle{})}
    case True{}:
      Done{Surface.blit.region(destination, source, rect, x, y, tint)}

def Surface.draw_image_region(destination: Surface, source: Surface, +rect: Rectangle, +x: F32, +y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, pixels} = source
  Surface.region.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h)
    && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), destination, Surface{w, h, pixels}, rect, x, y, tint)

# Initial ImageDraw profile: full source, equal-size destination rectangle,
# RGBA8, one mip level. Both image owners are returned, destination first.
def Surface.draw_image(destination: Surface, source: Surface, +x: F32, +y: F32, tint: U32) -> Surface & Surface:
  Surface{+w, +h, pixels} = source
  Surface.blit.region(destination, Surface{w, h, pixels}, Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)}, x, y, tint)

def Surface.image_rect.finish(original: Surface, drawn: Surface & Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (destination, _) = drawn
  Done{(destination, original)}

def Surface.image_rect.resized(destination: Surface, original: Surface, x: F32, y: F32, tint: U32, resized: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match resized:
    case Fail{Tuple{_, error}}: Fail{((destination, original), error)}
    case Done{scaled}: Surface.image_rect.finish(original, Surface.draw_image(destination, scaled, x, y, tint))

def Surface.image_rect.extracted(destination: Surface, x: F32, y: F32, width: U32, height: U32, tint: U32, extracted: Surface & Maybe<Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match extracted:
    case Tuple{source, None{}}: Fail{((destination, source), InvalidRectangle{})}
    case Tuple{source, Some{region}}:
      Surface.image_rect.resized(destination, source, x, y, tint, Surface.resize(region, width, height))

def Surface.image_rect.extract(source: Surface, rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{w, h, pixels} = source
  Rectangle{x, y, width, height} = rect
  Surface.extract.checked(True{}, w, h, pixels, x, y, width, height)

def Surface.image_rect.route(scaled: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, width: U32, height: U32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match scaled:
    case False{}: Done{Surface.blit.region(destination, source, rect, x, y, tint)}
    case True{}: Surface.image_rect.extracted(destination, x, y, width, height, tint, Surface.image_rect.extract(source, rect))

def Surface.image_rect.checked(valid: Bool, destination: Surface, source: Surface, +rect: Rectangle, target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((destination, source), InvalidRectangle{})}
    case True{}:
      Rectangle{_, _, rw, rh} = rect
      Rectangle{x, y, +width, +height} = target
      Surface.image_rect.route((F32.is_ne(F32.floor(rw), F32.floor(width)) || F32.is_ne(F32.floor(rh), F32.floor(height))), destination, source, rect, x, y,
        F32.to_u32(width), F32.to_u32(height), tint)

def Rectangle.bounded(rect: Rectangle) -> Bool:
  Rectangle{x, y, w, h} = rect
  ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) && (F32.abs(w) <= 32767.0) && (F32.abs(h) <= 32767.0) : F32)

def Surface.draw_image_rect(destination: Surface, source: Surface, +rect: Rectangle, +target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+sw, +sh, pixels} = source
  Rectangle{+x, +y, width, height} = rect
  Rectangle{_, _, +tw, +th} = target
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.min((width + F32.min(0.0, x) : F32), (U32.to_f32(sw) - sx : F32))
  +ch = F32.min((height + F32.min(0.0, y) : F32), (U32.to_f32(sh) - sy : F32))
  Surface.image_rect.checked(Rectangle.bounded(rect) && Rectangle.bounded(target)
    && ((cw >= 1.0) && (ch >= 1.0) && (tw >= 1.0) && (th >= 1.0) && (F32.floor(tw) <= 4096.0) && (F32.floor(th) <= 4096.0) : F32),
    destination, Surface{sw, sh, pixels}, Rectangle{sx, sy, cw, ch}, target, tint)

# Export consumes the surface and excludes power-of-two storage padding.
def Surface.colors(surface: Surface) -> List<U32>:
  Surface{w, h, pixels} = surface
  Image.list.take(~U32, Array.to_list(~U32, pixels), U32.to_nat((w * h : U32)))

type Image.Palette is Type:
  Palette{count: U32, colors: +List<U32>}

def Image.Palette.entries(palette: Image.Palette) -> U32 & +List<U32>:
  Palette{count, colors} = palette
  (count, colors)

def Image.Palette.unload(palette: Image.Palette) -> Unit:
  Unit{}

def Surface.palette.contains(values: +List<U32>, +color: U32, found: Bool) -> Bool:
  match values found:
    case _ True{}: True{}
    case Nil{} False{}: False{}
    case Con{head, rest} False{}: Surface.palette.contains(rest, color, U32.is_eq(head, color))

def Surface.palette.collect(+remaining: U32, +values: +List<U32>, read: Array<U32> & U32) -> Array<U32> & (U32 & +List<U32>):
  (pixels, +color) = read
  +fresh = U32.is_ne(Color.alpha(color), 0) && Bool.not(Surface.palette.contains(values, color, False{}))
  (pixels, (Bool.pick(U32, fresh, (remaining - 1 : U32), remaining), Bool.pick(+List<U32>, fresh, Con{color, values}, values)))

def Surface.palette.loop(n: Nat, +index: U32, cursor: Array<U32> & (U32 & +List<U32>)) -> Array<U32> & (U32 & +List<U32>):
  match n cursor:
    case _ Tuple{pixels, Tuple{0, values}}: (pixels, (0, values))
    case 0n _: cursor
    case 1n+rest Tuple{pixels, Tuple{remaining, values}}:
      Surface.palette.loop(rest, (index + 1 : U32), Surface.palette.collect(remaining, values, Array.get(U32, pixels, index)))

def Surface.palette.pad(n: Nat, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, values)
    case 1n+rest: Surface.palette.pad(rest, Con{0, values})

def Surface.palette.finished(width: U32, height: U32, maximum: U32, result: Array<U32> & (U32 & +List<U32>)) -> Surface & Maybe<Image.Palette>:
  (pixels, (+remaining, values)) = result
  (Surface{width, height, pixels}, Some{Palette{(maximum - remaining : U32), Surface.palette.pad(U32.to_nat(remaining), values)}})

def Surface.palette.checked(valid: Bool, surface: Surface, +maximum: U32) -> Surface & Maybe<Image.Palette>:
  match valid surface:
    case False{} _: (surface, None{})
    case True{} Surface{+w, +h, pixels}:
      Surface.palette.finished(w, h, maximum, Surface.palette.loop(U32.to_nat((w * h : U32)), 0, (pixels, (maximum, Nil{}))))

def Surface.load_palette(surface: Surface, +maximum: U32) -> Surface & Maybe<Image.Palette>:
  Surface.palette.checked(((maximum > 0) && (maximum <= 4096) : U32), surface, maximum)

def Surface.copy.result(+w: U32, +h: U32, pair: Array<U32> & Array<U32>) -> Surface & Surface:
  (a, b) = pair
  (Surface{w, h, a}, Surface{w, h, b})

def Surface.copy(surface: Surface) -> Surface & Surface:
  Surface{w, h, pixels} = surface
  Surface.copy.result(w, h, Array.clone(U32, pixels))

type Image.Mipmaps is Type:
  Mipmaps{count: U32, levels: List<Surface>}

def Surface.mipmaps.copied(reversed: List<Surface>, pair: Surface & Surface) -> Surface & List<Surface>:
  (source, Surface{+width, +height, pixels}) = pair
  +w = U32.max(1, (width / 2 : U32))
  +h = U32.max(1, (height / 2 : U32))
  (Surface{w, h, Resample.resize(width, height, w, h, pixels)}, Con{source, reversed})

def Surface.mipmaps.step(state: Surface & List<Surface>) -> Surface & List<Surface>:
  (surface, reversed) = state
  Surface.mipmaps.copied(reversed, Surface.copy(surface))

def Surface.mipmaps.levels(n: Nat, state: Surface & List<Surface>) -> List<Surface>:
  match n state:
    case 0n Tuple{surface, reversed}: List.reverse(&1, Surface, Con{surface, reversed})
    case 1n+rest _: Surface.mipmaps.levels(rest, Surface.mipmaps.step(state))

# Altered adaptation of raylib ImageMipmaps; each level resizes the preceding one.
def Surface.mipmaps(surface: Surface) -> Image.Mipmaps:
  Surface{+width, +height, pixels} = surface
  +steps = U32.log2(U32.max(width, height))
  Mipmaps{(1 + U32.from_nat(steps) : U32), Surface.mipmaps.levels(steps, (Surface{width, height, pixels}, Nil{}))}

def Image.Mipmaps.entries(chain: Image.Mipmaps) -> U32 & List<Surface>:
  Mipmaps{count, levels} = chain
  (count, levels)

def Image.Mipmaps.unload(chain: Image.Mipmaps) -> Unit:
  Unit{}

def Surface.channel.copied(pair: Surface & Surface, selected: F32) -> Surface & Surface:
  (source, copy) = pair
  shift = U32.to_nat((24 - 8 * F32.to_u32(F32.clamp(selected, 0.0, 3.0)) : U32))
  (source, Surface.color.transform(copy, ImageChannel{shift}))

def Surface.from_channel(surface: Surface, selected: F32) -> Surface & Surface:
  Surface.channel.copied(Surface.copy(surface), selected)

def Image.channel.index(format: U32, +selected: U32) -> U32:
  match format:
    case 1: 0
    case 2: Bool.pick(U32, U32.is_eq(selected, 0), 0, 3)
    case 3: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case 4: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case 8: 0
    case 9: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case _: Bool.pick(U32, (selected > 3 : U32), 3, selected)

def Image.channel.valid(+selected: F32) -> Bool:
  Image.FloatRGB.color.integral(selected) && (F32.abs(selected) <= 32767.0 : F32)

def Image.channel.value(index: U32, normal: Formats.Normal) -> U32:
  match index normal:
    case 0 Formats.Normal{r, _, _, _}: F32.to_u32((r * 255.0 : F32))
    case 1 Formats.Normal{_, g, _, _}: F32.to_u32((g * 255.0 : F32))
    case 2 Formats.Normal{_, _, b, _}: F32.to_u32((b * 255.0 : F32))
    case _ Formats.Normal{_, _, _, a}: F32.to_u32((a * 255.0 : F32))

def Image.Formatted.channel.read(format: U32, channel: U32, index: U32, output: Array<U32>, result: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (source, word) = result
  (source, Array.set(U32, output, index, Image.channel.value(channel, Formats.decode(format, word))))

def Image.Formatted.channel.pixels(n: Nat, +index: U32, +format: U32, +channel: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{source, output}:
      Image.Formatted.channel.pixels(rest, (index + 1 : U32), format, channel, Image.Formatted.channel.read(format, channel, index, output, Array.get(U32, source, index)))

def Image.Formatted.channel.finished(+width: U32, +height: U32, format: U32, result: Array<U32> & Array<U32>) -> Image.Formatted & Maybe<Image.Formatted>:
  (source, pixels) = result
  (FormattedImage{width, height, format, source}, Some{FormattedImage{width, height, 1, pixels}})

def Image.Formatted.channel.checked(valid: Bool, image: Image.Formatted, selected: F32) -> Image.Formatted & Maybe<Image.Formatted>:
  match valid image:
    case False{} _: (image, None{})
    case True{} FormattedImage{+width, +height, +format, pixels}:
      +count = (width * height : U32)
      channel = Image.channel.index(format, F32.to_u32(F32.max(0.0, selected)))
      Image.Formatted.channel.finished(width, height, format, Image.Formatted.channel.pixels(U32.to_nat(count), 0, format, channel,
        (pixels, Array.new(U32, Surface.capacity(count), 0))))

def Image.Formatted.from_channel(image: Image.Formatted, +selected: F32) -> Image.Formatted & Maybe<Image.Formatted>:
  Image.Formatted.channel.checked(Image.channel.valid(selected), image, selected)

def Image.FloatRGB.channel.read(channel: U32, index: U32, output: Array<U32>, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Array<U32>:
  match result:
    case Tuple{source, M.Vector3{r, g, b}}:
      (source, Array.set(U32, output, index, Image.channel.value(channel, Formats.Normal{r, g, b, 1.0})))

def Image.FloatRGB.channel.pixels(n: Nat, +index: U32, +channel: U32, state: Array<M.Vector3> & Array<U32>) -> Array<M.Vector3> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{source, output}:
      Image.FloatRGB.channel.pixels(rest, (index + 1 : U32), channel, Image.FloatRGB.channel.read(channel, index, output, Array.get(M.Vector3, source, index)))

def Image.FloatRGB.channel.finished(+width: U32, +height: U32, result: Array<M.Vector3> & Array<U32>) -> Image.FloatRGB & Maybe<Image.Formatted>:
  (source, pixels) = result
  (FloatRGB{width, height, source}, Some{FormattedImage{width, height, 1, pixels}})

def Image.FloatRGB.channel.checked(+width: U32, +height: U32, channel: U32, state: Array<M.Vector3> & Bool) -> Image.FloatRGB & Maybe<Image.Formatted>:
  match state:
    case Tuple{pixels, False{}}: (FloatRGB{width, height, pixels}, None{})
    case Tuple{pixels, True{}}:
      +count = (width * height : U32)
      Image.FloatRGB.channel.finished(width, height, Image.FloatRGB.channel.pixels(U32.to_nat(count), 0, channel,
        (pixels, Array.new(U32, Surface.capacity(count), 0))))

def Image.FloatRGB.channel.selected(valid: Bool, image: Image.FloatRGB, selected: F32) -> Image.FloatRGB & Maybe<Image.Formatted>:
  match valid image:
    case False{} _: (image, None{})
    case True{} FloatRGB{+width, +height, pixels}:
      Image.FloatRGB.channel.checked(width, height, Image.channel.index(9, F32.to_u32(F32.max(0.0, selected))),
        Image.FloatRGB.checked.pixels(~Image.FloatRGB.pixel.valid, U32.to_nat((width * height : U32)), 0, (pixels, True{})))

def Image.FloatRGB.from_channel(image: Image.FloatRGB, +selected: F32) -> Image.FloatRGB & Maybe<Image.Formatted>:
  Image.FloatRGB.channel.selected(Image.channel.valid(selected), image, selected)

def Image.Formatted.colors.read(format: U32, values: List<U32>, result: Array<U32> & U32) -> Array<U32> & List<U32>:
  (pixels, word) = result
  (pixels, Con{Formats.image_color(format, word), values})

def Image.Formatted.colors.pixels(n: Nat, +index: U32, +format: U32, state: Array<U32> & List<U32>) -> List<U32>:
  match n state:
    case 0n Tuple{_, values}: List.reverse(&1, U32, values)
    case 1n+rest Tuple{source, values}:
      Image.Formatted.colors.pixels(rest, (index + 1 : U32), format, Image.Formatted.colors.read(format, values, Array.get(U32, source, index)))

def Image.Formatted.colors(image: Image.Formatted) -> List<U32>:
  FormattedImage{width, height, format, pixels} = image
  Image.Formatted.colors.pixels(U32.to_nat((width * height : U32)), 0, format, (pixels, Nil{}))

def Image.Formatted.get.read(width: U32, height: U32, +format: U32, result: Array<U32> & U32) -> Image.Formatted & Maybe<&2, U32>:
  (pixels, word) = result
  (FormattedImage{width, height, format, pixels}, Some{Formats.image_color(format, word)})

def Image.Formatted.get.checked(valid: Bool, +width: U32, height: U32, format: U32, pixels: Array<U32>, x: U32, y: U32) -> Image.Formatted & Maybe<&2, U32>:
  match valid:
    case False{}: (FormattedImage{width, height, format, pixels}, None{})
    case True{}: Image.Formatted.get.read(width, height, format, Array.get(U32, pixels, (y * width + x : U32)))

def Image.Formatted.get(image: Image.Formatted, +x: U32, +y: U32) -> Image.Formatted & Maybe<&2, U32>:
  FormattedImage{+width, +height, format, pixels} = image
  Image.Formatted.get.checked(((x < width) && (y < height) : U32), width, height, format, pixels, x, y)

def Image.FloatRGB.colors.result(result: Result<&1, &1, Image.FloatRGB, Surface>) -> Result<&1, &1, Image.FloatRGB, List<U32>>:
  match result:
    case Fail{image}: Fail{image}
    case Done{surface}: Done{Surface.colors(surface)}

def Image.FloatRGB.colors(image: Image.FloatRGB) -> Result<&1, &1, Image.FloatRGB, List<U32>>:
  Image.FloatRGB.colors.result(Image.FloatRGB.to_surface(image))

def Image.FloatRGB.get.valid(valid: Bool, width: U32, height: U32, pixels: Array<M.Vector3>, value: M.Vector3) -> Image.FloatRGB & Maybe<&2, U32>:
  match valid:
    case False{}: (FloatRGB{width, height, pixels}, None{})
    case True{}: (FloatRGB{width, height, pixels}, Some{Image.FloatRGB.pixel.color(value)})

def Image.FloatRGB.get.read(width: U32, height: U32, result: Array<M.Vector3> & M.Vector3) -> Image.FloatRGB & Maybe<&2, U32>:
  (pixels, +value) = result
  Image.FloatRGB.get.valid(Image.FloatRGB.pixel.valid(value), width, height, pixels, value)

def Image.FloatRGB.get.checked(valid: Bool, +width: U32, height: U32, pixels: Array<M.Vector3>, x: U32, y: U32) -> Image.FloatRGB & Maybe<&2, U32>:
  match valid:
    case False{}: (FloatRGB{width, height, pixels}, None{})
    case True{}: Image.FloatRGB.get.read(width, height, Array.get(M.Vector3, pixels, (y * width + x : U32)))

def Image.FloatRGB.get(image: Image.FloatRGB, +x: U32, +y: U32) -> Image.FloatRGB & Maybe<&2, U32>:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.get.checked(((x < width) && (y < height) : U32), width, height, pixels, x, y)

def Surface.flip.index(horizontal: Bool, +i: U32, +w: U32, h: U32) -> U32:
  Raster.index(Mirrored{w, h, horizontal}, i)

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

def Image.FloatRGB.copy.result(+width: U32, +height: U32, result: Array<M.Vector3> & Array<M.Vector3>) -> Image.FloatRGB & Image.FloatRGB:
  (source, clone) = result
  (FloatRGB{width, height, source}, FloatRGB{width, height, clone})

def Image.FloatRGB.copy(image: Image.FloatRGB) -> Image.FloatRGB & Image.FloatRGB:
  FloatRGB{width, height, pixels} = image
  Image.FloatRGB.copy.result(width, height, Array.clone(M.Vector3, pixels))

def Image.FloatRGB.sampled(width: U32, height: U32, result: Array<M.Vector3> & Array<M.Vector3>) -> Image.FloatRGB:
  (_, pixels) = result
  FloatRGB{width, height, pixels}

def Image.FloatRGB.flip(image: Image.FloatRGB, horizontal: Bool) -> Image.FloatRGB:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.sampled(width, height, Raster.sample(~M.Vector3, (width * height : U32), Mirrored{width, height, horizontal}, M.Vector3{0.0, 0.0, 0.0}, pixels))

def Image.FloatRGB.flip_horizontal(image: Image.FloatRGB) -> Image.FloatRGB:
  Image.FloatRGB.flip(image, True{})

def Image.FloatRGB.flip_vertical(image: Image.FloatRGB) -> Image.FloatRGB:
  Image.FloatRGB.flip(image, False{})

def Image.FloatRGB.rotate(image: Image.FloatRGB, clockwise: Bool) -> Image.FloatRGB:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.sampled(height, width, Raster.sample(~M.Vector3, (width * height : U32), QuarterTurn{width, height, clockwise}, M.Vector3{0.0, 0.0, 0.0}, pixels))

def Image.FloatRGB.rotate_cw(image: Image.FloatRGB) -> Image.FloatRGB:
  Image.FloatRGB.rotate(image, True{})

def Image.FloatRGB.rotate_ccw(image: Image.FloatRGB) -> Image.FloatRGB:
  Image.FloatRGB.rotate(image, False{})

def Image.FloatRGB.extract.finish(sw: U32, sh: U32, width: U32, height: U32, result: Array<M.Vector3> & Array<M.Vector3>) -> Image.FloatRGB & Maybe<Image.FloatRGB>:
  (source, pixels) = result
  (FloatRGB{sw, sh, source}, Some{FloatRGB{width, height, pixels}})

def Image.FloatRGB.extract.checked(valid: Bool, +sw: U32, sh: U32, pixels: Array<M.Vector3>, x: F32, y: F32, width: F32, height: F32) -> Image.FloatRGB & Maybe<Image.FloatRGB>:
  match valid:
    case False{}: (FloatRGB{sw, sh, pixels}, None{})
    case True{}:
      +w = F32.to_u32(width)
      +h = F32.to_u32(height)
      Image.FloatRGB.extract.finish(sw, sh, w, h, Raster.sample(~M.Vector3, (w * h : U32), Region{sw, w, F32.to_u32(x), F32.to_u32(y)}, M.Vector3{0.0, 0.0, 0.0}, pixels))

def Image.FloatRGB.extract(image: Image.FloatRGB, +rect: Rectangle) -> Image.FloatRGB & Maybe<Image.FloatRGB>:
  FloatRGB{+width, +height, pixels} = image
  Rectangle{x, y, w, h} = rect
  Image.FloatRGB.extract.checked(Rectangle.integral(rect) && Rectangle.inside(rect, width, height), width, height, pixels, x, y, w, h)

def Image.FloatRGB.crop.result(result: Image.FloatRGB & Maybe<Image.FloatRGB>) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  match result:
    case Tuple{original, None{}}: Fail{(original, InvalidRectangle{})}
    case Tuple{_, Some{region}}: Done{region}

def Image.FloatRGB.crop.route(integral: Bool, outside: Bool, image: Image.FloatRGB, rect: Rectangle) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  match integral outside:
    case False{} _: Fail{(image, InvalidRectangle{})}
    case True{} True{}: Done{image}
    case True{} False{}: Image.FloatRGB.crop.result(Image.FloatRGB.extract(image, rect))

def Image.FloatRGB.crop(image: Image.FloatRGB, +rect: Rectangle) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  FloatRGB{+width, +height, pixels} = image
  Rectangle{x, y, _, _} = rect
  Image.FloatRGB.crop.route(Rectangle.integral(rect), ((x > U32.to_f32(width)) || (y > U32.to_f32(height)) : F32),
    FloatRGB{width, height, pixels}, Rectangle.crop.bounds(rect, width, height))

def Image.FloatRGB.resize.result(original: Image.FloatRGB, result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  match result:
    case Fail{_}: Fail{original}
    case Done{surface}: Done{Surface.to_float_rgb(surface)}

def Image.FloatRGB.resize.surface(nearest: Bool, surface: Surface, width: U32, height: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match nearest:
    case True{}: Surface.resize_nn(surface, width, height)
    case False{}: Surface.resize(surface, width, height)

def Image.FloatRGB.resize.routed(nearest: Bool, +sw: U32, +sh: U32, width: U32, height: U32, result: Array<M.Vector3> & Array<U32>) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  (original, pixels) = result
  Image.FloatRGB.resize.result(FloatRGB{sw, sh, original}, Image.FloatRGB.resize.surface(nearest, Surface{sw, sh, pixels}, width, height))

def Image.FloatRGB.resize.checked(nearest: Bool, +sw: U32, +sh: U32, width: U32, height: U32, state: Array<M.Vector3> & Bool) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  match state:
    case Tuple{pixels, False{}}: Fail{FloatRGB{sw, sh, pixels}}
    case Tuple{pixels, True{}}:
      +count = (sw * sh : U32)
      Image.FloatRGB.resize.routed(nearest, sw, sh, width, height,
        Image.FloatRGB.converted.pixels(U32.to_nat(count), 0, (pixels, Array.new(U32, Surface.capacity(count), 0))))

def Image.FloatRGB.resize.sized(valid: Bool, nearest: Bool, image: Image.FloatRGB, width: U32, height: U32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  match valid image:
    case False{} _: Fail{image}
    case True{} FloatRGB{+sw, +sh, pixels}:
      Image.FloatRGB.resize.checked(nearest, sw, sh, width, height,
        Image.FloatRGB.checked.pixels(~Image.FloatRGB.pixel.valid, U32.to_nat((sw * sh : U32)), 0, (pixels, True{})))

def Image.FloatRGB.resize_nn(image: Image.FloatRGB, +width: U32, +height: U32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.resize.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), True{}, image, width, height)

def Image.FloatRGB.resize(image: Image.FloatRGB, +width: U32, +height: U32) -> Result<&1, &1, Image.FloatRGB, Image.FloatRGB>:
  Image.FloatRGB.resize.sized(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), False{}, image, width, height)

def Image.FloatRGB.canvas.finished(width: U32, height: U32, result: Array<M.Vector3> & Array<M.Vector3>) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  (_, pixels) = result
  Done{FloatRGB{width, height, pixels}}

def Image.FloatRGB.canvas.overlap(valid: Bool, +sw: U32, sh: U32, pixels: Array<M.Vector3>, +width: U32, +height: U32, sx: U32, sy: U32, dx: U32, dy: U32, +cols: U32, rows: U32) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  match valid:
    case False{}: Fail{(FloatRGB{sw, sh, pixels}, InvalidRectangle{})}
    case True{}:
      # Native SetPixelColor ignores format 9, leaving calloc's zero RGB fill.
      Image.FloatRGB.canvas.finished(width, height, Raster.canvas.copy(~M.Vector3, U32.to_nat((cols * rows : U32)), 0, cols, sw, width,
        (sy * sw + sx : U32), (dy * width + dx : U32), (pixels, Array.new(M.Vector3, Surface.capacity((width * height : U32)), M.Vector3{0.0, 0.0, 0.0}))))

def Image.FloatRGB.canvas.mapped(sw: U32, sh: U32, pixels: Array<M.Vector3>, width: U32, height: U32, mapping: Raster.Canvas) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  Canvas{sx, sy, dx, dy, +cols, +rows} = mapping
  Image.FloatRGB.canvas.overlap(((cols >= 1) && (rows >= 1) : U32), sw, sh, pixels, width, height, sx, sy, dx, dy, cols, rows)

def Image.FloatRGB.canvas.route(same: Bool, +sw: U32, +sh: U32, pixels: Array<M.Vector3>, +width: U32, +height: U32, x: F32, y: F32) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  match same:
    case True{}: Done{FloatRGB{sw, sh, pixels}}
    case False{}: Image.FloatRGB.canvas.mapped(sw, sh, pixels, width, height, Raster.canvas.mapping(sw, sh, width, height, x, y))

def Image.FloatRGB.canvas.checked(size_ok: Bool, offsets_ok: Bool, image: Image.FloatRGB, +width: U32, +height: U32, x: F32, y: F32) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  match size_ok offsets_ok:
    case False{} _: Fail{(image, InvalidSize{})}
    case True{} False{}: Fail{(image, InvalidRectangle{})}
    case True{} True{}:
      FloatRGB{+sw, +sh, pixels} = image
      Image.FloatRGB.canvas.route(U32.is_eq(sw, width) && U32.is_eq(sh, height), sw, sh, pixels, width, height, x, y)

def Image.FloatRGB.resize_canvas(image: Image.FloatRGB, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  Image.FloatRGB.canvas.checked(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) : F32) && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), image, width, height, x, y)

def Image.FloatRGB.to_pot(image: Image.FloatRGB, fill: U32) -> Result<&1, &1, Image.FloatRGB & Surface.Error, Image.FloatRGB>:
  FloatRGB{+width, +height, pixels} = image
  Image.FloatRGB.resize_canvas(FloatRGB{width, height, pixels}, U32.shln(1, Surface.capacity(width)), U32.shln(1, Surface.capacity(height)), 0.0, 0.0, fill)

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

def Surface.qoi.opened(bytes: +List<U32>, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write_bytes(file, bytes), Surface.ppm.written)

def Surface.write_qoi(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Surface.to_qoi(surface)))

def Surface.write_bmp(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Surface.to_bmp(surface)))

def Surface.write_tga(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Surface.to_tga(surface)))

def Surface.write_png(surface: Surface, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Surface.to_png(surface)))

type Image.FileKind is Data:
  QoiFile{}
  RasterFile{}
  UnsupportedImageFile{}

def Image.memory.selected(qoi: Bool, raster: Bool) -> Image.FileKind:
  match qoi raster:
    case True{} _: QoiFile{}
    case False{} True{}: RasterFile{}
    case False{} False{}: UnsupportedImageFile{}

def Image.memory.kind(+file_type: String) -> Image.FileKind:
  Image.memory.selected(String.eq(file_type, ".qoi") || String.eq(file_type, ".QOI"),
    String.eq(file_type, ".png") || String.eq(file_type, ".PNG")
      || String.eq(file_type, ".bmp") || String.eq(file_type, ".BMP")
      || String.eq(file_type, ".tga") || String.eq(file_type, ".TGA")
      || String.eq(file_type, ".pgm") || String.eq(file_type, ".PGM")
      || String.eq(file_type, ".ppm") || String.eq(file_type, ".PPM")
      || String.eq(file_type, ".jpg") || String.eq(file_type, ".JPG")
      || String.eq(file_type, ".jpeg") || String.eq(file_type, ".JPEG")
      || String.eq(file_type, ".gif") || String.eq(file_type, ".GIF")
      || String.eq(file_type, ".pic") || String.eq(file_type, ".PIC")
      || String.eq(file_type, ".psd") || String.eq(file_type, ".PSD"))

def Image.file.last_dot(path: String, +position: Nat, last: Nat) -> Nat:
  match path:
    case SNil{}: last
    case SCon{character, rest}: Image.file.last_dot(rest, 1n+position, Bool.pick(Nat, Char.is_eq(character, '.'), position, last))

def Image.file.suffix(valid: Bool, path: String, position: Nat) -> String:
  match valid:
    case False{}: ""
    case True{}: String.drop(path, position)

def Image.file.token(+path: String) -> String:
  +position = Image.file.last_dot(path, 0n, 0n)
  Image.file.suffix(Nat.is_lt(0n, position), path, position)

def Image.file.kind(path: String) -> Image.FileKind:
  Image.memory.kind(Image.file.token(path))

# ExportImage uses ASCII-insensitive suffixes, unlike LoadImageFromMemory.
# Adapted from raylib 6.0 rtextures.c / rcore.c; retain the native last-dot rule.
def Image.export.selected(png: Bool, bmp: Bool, tga: Bool, qoi: Bool, raw: Bool) -> U32:
  match png bmp tga qoi raw:
    case True{} _ _ _ _: 1
    case _ True{} _ _ _: 2
    case _ _ True{} _ _: 3
    case _ _ _ True{} _: 4
    case _ _ _ _ True{}: 5
    case _ _ _ _ _: 0

def Image.export.kind(path: String) -> U32:
  +token = String.to_lower(Image.file.token(path))
  Image.export.selected(String.eq(token, ".png"), String.eq(token, ".bmp"), String.eq(token, ".tga"), String.eq(token, ".qoi"), String.eq(token, ".raw"))

def Image.file.limit(kind: Image.FileKind) -> U32:
  match kind:
    case QoiFile{}: 83886102
    case _: 1048576

def Image.file.psd(bytes: +List<U32>) -> Bool:
  match bytes:
    case Con{56, Con{66, Con{80, Con{83, _}}}}: True{}
    case _: False{}

def Image.file.raster_selected(reference: Image.Decode.Reference, png: Bool, bmp: Bool, pnm: Bool, psd: Bool, pic: Bool, gif: Bool, bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match png bmp pnm psd pic gif:
    case True{} _ _ _ _ _: Surface.decode_png(bytes)
    case False{} True{} _ _ _ _: Surface.decode_bmp(bytes)
    case False{} False{} True{} _ _ _: Surface.decode_pnm(bytes)
    case False{} False{} False{} True{} _ _: Surface.decode_psd_for(reference, bytes)
    case False{} False{} False{} False{} True{} _: Surface.decode_pic(bytes)
    case False{} False{} False{} False{} False{} True{}: Surface.decode_gif(bytes)
    case False{} False{} False{} False{} False{} False{}: Surface.decode_tga(bytes)

def Image.file.raster(reference: Image.Decode.Reference, +bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match bytes:
    case Con{+a, Con{+b, _}}:
      Image.file.raster_selected(reference, U32.is_eq(a, 137) && U32.is_eq(b, 80), U32.is_eq(a, 66) && U32.is_eq(b, 77),
        U32.is_eq(a, 80) && (U32.is_eq(b, 53) || U32.is_eq(b, 54)), Image.file.psd(bytes), Pic.signature(bytes), Gif.signature(bytes), bytes)
    case _: Surface.decode_tga(bytes)

def Image.file.decode(reference: Image.Decode.Reference, kind: Image.FileKind, bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  match kind:
    case QoiFile{}: Surface.decode_qoi(bytes)
    case RasterFile{}: Image.file.raster(reference, bytes)
    case UnsupportedImageFile{}: Fail{InvalidImageHeader{}}

def Surface.decode_image_for(reference: Image.Decode.Reference, file_type: String, bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Image.file.decode(reference, Image.memory.kind(file_type), bytes)

def Surface.decode_image(file_type: String, bytes: +List<U32>) -> Result<&1, &1, Image.DecodeError, Surface>:
  Surface.decode_image_for(UncontractedDecode{}, file_type, bytes)

def Image.Animation.single.sized(valid: Bool, +width: U32, +height: U32, pixels: Array<U32>) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  match valid:
    case False{}: Fail{UnsupportedImageSize{}}
    case True{}: Done{Animation{width, height, 1, Con{Surface{width, height, pixels}, Nil{}}}}

def Image.Animation.single(maximum_pixels: U32, result: Result<&1, &1, Image.DecodeError, Surface>) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Surface{+width, +height, pixels}}: Image.Animation.single.sized((width * height <= maximum_pixels : U32), width, height, pixels)

def Image.Animation.memory.checked(valid: Bool, reference: Image.Decode.Reference, file_type: String, bytes: +List<U32>, maximum_pixels: U32) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  match valid:
    case False{}: Fail{UnsupportedImageSize{}}
    case True{}: Image.Animation.single(maximum_pixels, Surface.decode_image_for(reference, file_type, bytes))

def Image.Animation.memory.selected(gif: Bool, reference: Image.Decode.Reference, file_type: String, bytes: +List<U32>, maximum_frames: U32, +maximum_pixels: U32) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  match gif:
    case True{}: Image.Animation.decode_gif(bytes, maximum_frames, maximum_pixels)
    case False{}: Image.Animation.memory.checked(((maximum_frames > 0) && (maximum_pixels > 0) && (maximum_pixels <= 16777216) : U32), reference, file_type, bytes, maximum_pixels)

def Image.Animation.decode_image_for(reference: Image.Decode.Reference, +file_type: String, bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  Image.Animation.memory.selected(String.eq(file_type, ".gif") || String.eq(file_type, ".GIF"), reference, file_type, bytes, maximum_frames, maximum_pixels)

def Image.Animation.decode_image(file_type: String, bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Image.DecodeError, Image.Animation>:
  Image.Animation.decode_image_for(UncontractedDecode{}, file_type, bytes, maximum_frames, maximum_pixels)

def Image.file.decoded(-A: Type, result: Result<&1, &1, Image.DecodeError, A>) -> Result<&1, &1, Image.LoadError, A>:
  match result:
    case Fail{error}: Fail{ImageDecodeError{error}}
    case Done{image}: Done{image}

def Image.file.complete(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n Nil{}: True{}
    case 1n+rest Con{_, tail}: Image.file.complete(rest, tail)
    case _ _: False{}

def Image.file.loaded(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Image.LoadError, +List<U32>>:
  match valid:
    case False{}: Fail{ImageDecodeError{TruncatedImageData{}}}
    case True{}: Done{bytes}

def Image.file.payload(size: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> Result<&1, &1, Image.LoadError, +List<U32>>:
  match result:
    case Fail{Tuple{code, message}}: Fail{ImageFileError{code, message}}
    case Done{+bytes}: Image.file.loaded(Image.file.complete(U32.to_nat(size), bytes), bytes)

def Image.file.read(size: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, +List<U32>>):
  (file, status) = result
  do IO<Result<&1, &1, Image.LoadError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Image.LoadError, +List<U32>>, Image.file.payload(size, status))

def Image.file.bounded(valid: Bool, file: File, +size: U32) -> IO(Result<&1, &1, Image.LoadError, +List<U32>>):
  match valid:
    case False{}:
      do IO<Result<&1, &1, Image.LoadError, +List<U32>>>:
        Unit <- File.close(file)
        IO.pure(Result<&1, &1, Image.LoadError, +List<U32>>, Fail{ImageDecodeError{UnsupportedImageSize{}}})
    case True{}:
      IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Result<&1, &1, Image.LoadError, +List<U32>>,
        File.read_bytes(file, size), Image.file.read(size))

def Image.file.sized(limit: U32, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, Image.LoadError, +List<U32>>):
  match result:
    case Tuple{file, Fail{error}}: Image.file.read(0, (file, Fail{error}))
    case Tuple{file, Done{+size}}: Image.file.bounded((size <= limit : U32), file, size)

def Image.file.opened(limit: U32, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, Image.LoadError, +List<U32>>):
  match opened:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.LoadError, +List<U32>>, Fail{ImageFileError{code, message}})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&1, &1, Image.LoadError, +List<U32>>, File.size(file), Image.file.sized(limit))

def Image.file.bytes(path: String, limit: U32) -> IO(Result<&1, &1, Image.LoadError, +List<U32>>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, Image.LoadError, +List<U32>>, File.open(path, "r"), Image.file.opened(limit))

def Image.file.surface(reference: Image.Decode.Reference, kind: Image.FileKind, result: Result<&1, &1, Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.LoadError, Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Image.LoadError, Surface>, Image.file.decoded(Surface, Image.file.decode(reference, kind, bytes)))

def Image.file.load(reference: Image.Decode.Reference, +kind: Image.FileKind, path: String) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  IO.bind(Result<&1, &1, Image.LoadError, +List<U32>>, Result<&1, &1, Image.LoadError, Surface>,
    Image.file.bytes(path, Image.file.limit(kind)), Image.file.surface(reference, kind))

def Surface.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  Image.file.load(UncontractedDecode{}, QoiFile{}, path)

def Surface.load_image_for(reference: Image.Decode.Reference, +path: String) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  Image.file.load(reference, Image.file.kind(path), path)

def Surface.load_image(path: String) -> IO(Result<&1, &1, Image.LoadError, Surface>):
  Surface.load_image_for(UncontractedDecode{}, path)

def Image.Animation.file.token(+suffix: String) -> String:
  Bool.pick(String, String.eq(String.to_lower(suffix), ".gif"), ".gif", suffix)

def Image.Animation.file.loaded(reference: Image.Decode.Reference, token: String, maximum_frames: U32, maximum_pixels: U32, result: Result<&1, &1, Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Image.Animation>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.LoadError, Image.Animation>, Fail{error})
    case Done{bytes}:
      IO.pure(Result<&1, &1, Image.LoadError, Image.Animation>, Image.file.decoded(Image.Animation,
        Image.Animation.decode_image_for(reference, token, bytes, maximum_frames, maximum_pixels)))

def Image.Animation.load_image_for(reference: Image.Decode.Reference, +path: String, maximum_frames: U32, maximum_pixels: U32) -> IO(Result<&1, &1, Image.LoadError, Image.Animation>):
  +token = Image.Animation.file.token(Image.file.token(path))
  IO.bind(Result<&1, &1, Image.LoadError, +List<U32>>, Result<&1, &1, Image.LoadError, Image.Animation>,
    Image.file.bytes(path, Image.file.limit(Image.memory.kind(token))), Image.Animation.file.loaded(reference, token, maximum_frames, maximum_pixels))

def Image.Animation.load_image(path: String, maximum_frames: U32, maximum_pixels: U32) -> IO(Result<&1, &1, Image.LoadError, Image.Animation>):
  Image.Animation.load_image_for(UncontractedDecode{}, path, maximum_frames, maximum_pixels)

# Explicit QOI selection shares the bounded, complete, close-before-decode file boundary.
def Image.Formatted.qoi.file.loaded(result: Result<&1, &1, Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.LoadError, Image.Formatted>, Fail{error})
    case Done{bytes}:
      IO.pure(Result<&1, &1, Image.LoadError, Image.Formatted>, Image.file.decoded(Image.Formatted, Image.Formatted.decode_qoi(bytes)))

def Image.Formatted.load_qoi(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>):
  IO.bind(Result<&1, &1, Image.LoadError, +List<U32>>, Result<&1, &1, Image.LoadError, Image.Formatted>,
    Image.file.bytes(path, Image.file.limit(QoiFile{})), Image.Formatted.qoi.file.loaded)

# Explicit PNM selection shares the bounded, complete, close-before-decode file boundary.
def Image.Formatted.pnm.file.loaded(result: Result<&1, &1, Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.LoadError, Image.Formatted>, Fail{error})
    case Done{bytes}:
      IO.pure(Result<&1, &1, Image.LoadError, Image.Formatted>, Image.file.decoded(Image.Formatted, Image.Formatted.decode_pnm(bytes)))

def Image.Formatted.load_pnm(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.Formatted>):
  IO.bind(Result<&1, &1, Image.LoadError, +List<U32>>, Result<&1, &1, Image.LoadError, Image.Formatted>,
    Image.file.bytes(path, Image.file.limit(RasterFile{})), Image.Formatted.pnm.file.loaded)

def Image.FloatRGB.file.loaded(result: Result<&1, &1, Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, Image.LoadError, Image.FloatRGB>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.LoadError, Image.FloatRGB>, Fail{error})
    case Done{bytes}:
      IO.pure(Result<&1, &1, Image.LoadError, Image.FloatRGB>, Image.file.decoded(Image.FloatRGB, Image.FloatRGB.decode_hdr(bytes)))

def Image.FloatRGB.load_hdr(path: String) -> IO(Result<&1, &1, Image.LoadError, Image.FloatRGB>):
  IO.bind(Result<&1, &1, Image.LoadError, +List<U32>>, Result<&1, &1, Image.LoadError, Image.FloatRGB>,
    Image.file.bytes(path, 1048576), Image.FloatRGB.file.loaded)

type Image.RawLoadError is Type:
  RawFileError{code: U32, message: String}
  InvalidRawRequest{}
  InvalidRawSamples{}
  TruncatedRawImage{}
  RawFileTooLarge{}

def Image.Formatted.raw_bytes(image: Image.Formatted) -> +List<U32>:
  FormattedImage{width, height, format, pixels} = image
  words = Image.list.take(~U32, Array.to_list(~U32, pixels), U32.to_nat((width * height : U32)))
  Formats.bytes(~&2, words, U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), Nil{})

def Image.Formatted.write_raw(image: Image.Formatted, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Image.Formatted.raw_bytes(image)))

type Image.ExportError is Type:
  UnsupportedImageExport{surface: Surface}
  ImageExportFileError{code: U32, message: String}

def Image.export.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Image.ExportError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.ExportError, Unit>, Fail{ImageExportFileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Image.ExportError, Unit>, Done{unit})

def Image.export.write(kind: U32, surface: Surface, path: String) -> IO(Result<&1, &1, Image.ExportError, Unit>):
  match kind:
    case 1: IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.ExportError, Unit>, Surface.write_png(surface, path), Image.export.written)
    case 2: IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.ExportError, Unit>, Surface.write_bmp(surface, path), Image.export.written)
    case 3: IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.ExportError, Unit>, Surface.write_tga(surface, path), Image.export.written)
    case 4: IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.ExportError, Unit>, Surface.write_qoi(surface, path), Image.export.written)
    case 5: IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.ExportError, Unit>, Image.Formatted.write_raw(Surface.to_formatted(surface), path), Image.export.written)
    case _: IO.pure(Result<&1, &1, Image.ExportError, Unit>, Fail{UnsupportedImageExport{surface}})

def Surface.write_image(surface: Surface, +path: String) -> IO(Result<&1, &1, Image.ExportError, Unit>):
  Image.export.write(Image.export.kind(path), surface, path)

def Image.Formatted.write_png(image: Image.Formatted, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Image.Formatted.png.file_bytes(image)))

def Image.Formatted.write_bmp(image: Image.Formatted, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Image.Formatted.to_bmp(image)))

def Image.Formatted.write_tga(image: Image.Formatted, path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
    File.open(path, "w"), Surface.qoi.opened(Image.Formatted.to_tga(image)))

type Image.Formatted.QoiWriteError is Type:
  QoiSourceError{image: Image.Formatted}
  QoiFileError{code: U32, message: String}

def Image.Formatted.qoi.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>, Fail{QoiFileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>, Done{unit})

def Image.Formatted.qoi.file_bytes(path: String, result: Result<&1, &1, Image.Formatted & Pixel.Error, +List<U32>>) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>):
  match result:
    case Fail{Tuple{image, _}}: IO.pure(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>, Fail{QoiSourceError{image}})
    case Done{bytes}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.Formatted.QoiWriteError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>,
          File.open(path, "w"), Surface.qoi.opened(bytes)), Image.Formatted.qoi.written)

def Image.Formatted.write_qoi(image: Image.Formatted, path: String) -> IO(Result<&1, &1, Image.Formatted.QoiWriteError, Unit>):
  Image.Formatted.qoi.file_bytes(path, Image.Formatted.to_qoi(image))

# Called only after checked request parameters, a complete read and handle closure.
# A failed factory here therefore identifies unsupported sample values.
def Image.raw.decoded(result: Maybe<Image.Formatted>) -> Result<&1, &1, Image.RawLoadError, Image.Formatted>:
  match result:
    case None{}: Fail{InvalidRawSamples{}}
    case Some{image}: Done{image}

def Image.raw.complete(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Image.RawLoadError, +List<U32>>:
  match valid:
    case False{}: Fail{TruncatedRawImage{}}
    case True{}: Done{bytes}

def Image.raw.payload(needed: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> Result<&1, &1, Image.RawLoadError, +List<U32>>:
  match result:
    case Fail{Tuple{code, message}}: Fail{RawFileError{code, message}}
    case Done{+bytes}: Image.raw.complete(Image.file.complete(U32.to_nat(needed), bytes), bytes)

def Image.raw.read(needed: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  (file, status) = result
  do IO<Result<&1, &1, Image.RawLoadError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Image.RawLoadError, +List<U32>>, Image.raw.payload(needed, status))

def Image.raw.failed(file: File, error: Image.RawLoadError) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  do IO<Result<&1, &1, Image.RawLoadError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Image.RawLoadError, +List<U32>>, Fail{error})

def Image.raw.bounded(too_large: Bool, enough: Bool, +header: U32, +needed: U32, size: U32, file: File) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  match too_large enough:
    case True{} _: Image.raw.failed(file, RawFileTooLarge{})
    case False{} False{}: Image.raw.failed(file, TruncatedRawImage{})
    case False{} True{}:
      offset = Bool.pick(U32, ((header > 0) && (header + needed <= size) : U32), header, 0)
      IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Result<&1, &1, Image.RawLoadError, +List<U32>>,
        File.read_at(file, offset, needed), Image.raw.read(needed))

def Image.raw.sized(header: U32, +needed: U32, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  match result:
    case Tuple{file, Fail{Tuple{code, message}}}: Image.raw.failed(file, RawFileError{code, message})
    case Tuple{file, Done{+size}}:
      Image.raw.bounded((size > 2147483647 : U32), (size >= needed : U32), header, needed, size, file)

def Image.raw.opened(header: U32, needed: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.RawLoadError, +List<U32>>, Fail{RawFileError{code, message}})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&1, &1, Image.RawLoadError, +List<U32>>,
        File.size(file), Image.raw.sized(header, needed))

def Image.raw.request(valid: Bool, path: String, header: U32, needed: U32) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Image.RawLoadError, +List<U32>>, Fail{InvalidRawRequest{}})
    case True{}:
      IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, Image.RawLoadError, +List<U32>>,
        File.open(path, "r"), Image.raw.opened(header, needed))

def Image.raw.bytes(path: String, +header: U32, +needed: U32) -> IO(Result<&1, &1, Image.RawLoadError, +List<U32>>):
  Image.raw.request((header <= 2147483647 - needed : U32), path, header, needed)

def Image.raw.formatted(width: U32, height: U32, format: U32, result: Result<&1, &1, Image.RawLoadError, +List<U32>>) -> IO(Result<&1, &1, Image.RawLoadError, Image.Formatted>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.Formatted>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.Formatted>, Image.raw.decoded(Image.Formatted.from_bytes(width, height, format, bytes)))

def Image.raw.parameters(valid: Bool, path: String, +width: U32, +height: U32, +format: U32, +header: U32) -> IO(Result<&1, &1, Image.RawLoadError, Image.Formatted>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.Formatted>, Fail{InvalidRawRequest{}})
    case True{}:
      needed = (width * height * (Pixel.bits_per_pixel(format) / 8) : U32)
      IO.bind(Result<&1, &1, Image.RawLoadError, +List<U32>>, Result<&1, &1, Image.RawLoadError, Image.Formatted>,
        Image.raw.bytes(path, header, needed), Image.raw.formatted(width, height, format))

def Image.Formatted.load_raw(path: String, +width: U32, +height: U32, +format: U32, header_size: U32) -> IO(Result<&1, &1, Image.RawLoadError, Image.Formatted>):
  Image.raw.parameters(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (format >= 1) && (format <= 8) : U32), path, width, height, format, header_size)

def Image.FloatRGB.raw.file.created(result: Maybe<Image.FloatRGB>) -> Result<&1, &1, Image.RawLoadError, Image.FloatRGB>:
  match result:
    case None{}: Fail{InvalidRawRequest{}}
    case Some{image}: Done{image}

def Image.FloatRGB.raw.file.loaded(width: U32, height: U32, result: Result<&1, &1, Image.RawLoadError, +List<U32>>) -> IO(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>, Image.FloatRGB.raw.file.created(Image.FloatRGB.from_bytes(width, height, bytes)))

def Image.FloatRGB.raw.file.parameters(valid: Bool, path: String, +width: U32, +height: U32, header: U32) -> IO(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>, Fail{InvalidRawRequest{}})
    case True{}:
      IO.bind(Result<&1, &1, Image.RawLoadError, +List<U32>>, Result<&1, &1, Image.RawLoadError, Image.FloatRGB>,
        Image.raw.bytes(path, header, (width * height * 12 : U32)), Image.FloatRGB.raw.file.loaded(width, height))

def Image.FloatRGB.load_raw(path: String, +width: U32, +height: U32, header_size: U32) -> IO(Result<&1, &1, Image.RawLoadError, Image.FloatRGB>):
  Image.FloatRGB.raw.file.parameters(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32), path, width, height, header_size)

type Image.FloatRGB.WriteError is Type:
  FloatRGBSampleError{image: Image.FloatRGB}
  FloatRGBFileError{code: U32, message: String}

def Image.FloatRGB.file.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.FloatRGB.WriteError, Unit>, Fail{FloatRGBFileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Image.FloatRGB.WriteError, Unit>, Done{unit})

def Image.FloatRGB.file.write(path: String, result: Result<&1, &1, Image.FloatRGB, +List<U32>>) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  match result:
    case Fail{image}: IO.pure(Result<&1, &1, Image.FloatRGB.WriteError, Unit>, Fail{FloatRGBSampleError{image}})
    case Done{bytes}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.FloatRGB.WriteError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Surface.qoi.opened(bytes)), Image.FloatRGB.file.written)

def Image.FloatRGB.write_raw(image: Image.FloatRGB, path: String) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  Image.FloatRGB.file.write(path, Image.FloatRGB.to_bytes(image))

def Image.FloatRGB.write_png(image: Image.FloatRGB, path: String) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  Image.FloatRGB.file.write(path, Image.FloatRGB.png.file_bytes(image))

def Image.FloatRGB.write_bmp(image: Image.FloatRGB, path: String) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  Image.FloatRGB.file.write(path, Image.FloatRGB.to_bmp(image))

def Image.FloatRGB.write_tga(image: Image.FloatRGB, path: String) -> IO(Result<&1, &1, Image.FloatRGB.WriteError, Unit>):
  Image.FloatRGB.file.write(path, Image.FloatRGB.to_tga(image))

def Image.Formatted.code.exported(name: String, size: U32, result: (U32 & U32) & (U32 & List<U32>)) -> String:
  ((width, height), (format, bytes)) = result
  ImageCode.encode(~&1, name, width, height, format, size, bytes)

def Image.Formatted.code.checked(valid: Bool, name: Maybe<&2, String>, size: U32, image: Image.Formatted) -> Result<&1, &1, Image.Formatted, String>:
  match valid name:
    case True{} Some{text}: Done{Image.Formatted.code.exported(text, size, Image.Formatted.export(image))}
    case _ _: Fail{image}

def Image.Formatted.to_code(image: Image.Formatted, path: String) -> Result<&1, &1, Image.Formatted, String>:
  FormattedImage{+width, +height, +format, pixels} = image
  +size = (width * height * (Pixel.bits_per_pixel(format) / 8) : U32)
  Image.Formatted.code.checked((size <= 65536 : U32), ImageCode.name(path), size, FormattedImage{width, height, format, pixels})

type Image.Formatted.CodeWriteError is Type:
  CodeSourceError{image: Image.Formatted}
  CodeFileError{code: U32, message: String}

def Image.Formatted.code.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>, Fail{CodeFileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>, Done{unit})

def Image.Formatted.code.write(path: String, result: Result<&1, &1, Image.Formatted, String>) -> IO(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>):
  match result:
    case Fail{image}: IO.pure(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>, Fail{CodeSourceError{image}})
    case Done{text}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.Formatted.CodeWriteError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Surface.ppm.opened(text)), Image.Formatted.code.written)

def Image.Formatted.write_code(image: Image.Formatted, +path: String) -> IO(Result<&1, &1, Image.Formatted.CodeWriteError, Unit>):
  Image.Formatted.code.write(path, Image.Formatted.to_code(image, path))

def Image.FloatRGB.code.exported(name: String, width: U32, height: U32, size: U32, result: Result<&1, &1, Image.FloatRGB, +List<U32>>) -> Result<&1, &1, Image.FloatRGB, String>:
  match result:
    case Fail{image}: Fail{image}
    case Done{bytes}: Done{ImageCode.encode(~&2, name, width, height, 9, size, bytes)}

def Image.FloatRGB.code.checked(valid: Bool, name: Maybe<&2, String>, +width: U32, +height: U32, size: U32, pixels: Array<M.Vector3>) -> Result<&1, &1, Image.FloatRGB, String>:
  match valid name:
    case True{} Some{text}: Image.FloatRGB.code.exported(text, width, height, size, Image.FloatRGB.to_bytes(FloatRGB{width, height, pixels}))
    case _ _: Fail{FloatRGB{width, height, pixels}}

def Image.FloatRGB.to_code(image: Image.FloatRGB, path: String) -> Result<&1, &1, Image.FloatRGB, String>:
  FloatRGB{+width, +height, pixels} = image
  +size = (width * height * 12 : U32)
  Image.FloatRGB.code.checked((size <= 65536 : U32), ImageCode.name(path), width, height, size, pixels)

type Image.FloatRGB.CodeWriteError is Type:
  FloatCodeSourceError{image: Image.FloatRGB}
  FloatCodeFileError{code: U32, message: String}

def Image.FloatRGB.code.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>, Fail{FloatCodeFileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>, Done{unit})

def Image.FloatRGB.code.write(path: String, result: Result<&1, &1, Image.FloatRGB, String>) -> IO(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>):
  match result:
    case Fail{image}: IO.pure(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>, Fail{FloatCodeSourceError{image}})
    case Done{text}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Surface.ppm.opened(text)), Image.FloatRGB.code.written)

def Image.FloatRGB.write_code(image: Image.FloatRGB, +path: String) -> IO(Result<&1, &1, Image.FloatRGB.CodeWriteError, Unit>):
  Image.FloatRGB.code.write(path, Image.FloatRGB.to_code(image, path))
