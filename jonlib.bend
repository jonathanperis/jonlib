# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Image/color algorithms adapted from raylib 6.0 rtextures.c; shared math in Jonmath.
# Collision queries adapted from the same release's rshapes.c; file and path
# utilities from rcore.c.
# 3D collision queries adapted from rmodels.c.
# Altered Bend implementations; see THIRD_PARTY_NOTICES.md and LICENSES/raylib.txt.
#
# Sections, in order (each starts with a "# ----" banner):
#   1. Data utilities: compression, Base64, checksums and splines
#   2. Geometry and collision
#   3. Colors
#   4. Random streams and owned-buffer storage
#   5. Image types and errors
#   6. Raw pixel bytes (GetPixelDataSize, GetPixelColor, SetPixelColor)
#   7. RGBA8 kernels: generation, color, drawing, geometry and resampling
#   8. Shared file boundary: suffix rules, bounded reads and closed writes
#   9. Surface: the public image API, dispatching on pixel format
#   10. Codecs, exporters, writers and loaders
#   11. Files: rcore.c path and file-data utilities
# Functions must be defined before use, so kernels precede the Surface layer
# that dispatches to them.
import Base
import ./jonmath.bend as M
import ./src/codec.bend as Codec
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
import ./src/dds.bend as Dds

# -----------------------------------------------------------------------------
# Data utilities: compression, Base64, checksums and splines

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
    case Some{_}: Some{(Checksums.crc(bytes, 4294967295) .^. 4294967295 : U32)}

def Checksum.crc32(+bytes: +List<U32>) -> Maybe<&2, U32>:
  Checksum.crc32.checked(Checksums.input_size(bytes, 0, True{}), bytes)

def Checksum.md5(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Checksums.md5(bytes)

def Checksum.sha1(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Sha.hash(False{}, bytes)

def Checksum.sha256(bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  Sha.hash(True{}, bytes)

def Spline.linear_for(reference: M.Contraction, start: M.Vector2, end: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{x, y} = start
  M.Vector2{u, v} = end
  +fused = M.Contraction.fused(reference)
  M.Vector2{SplineNumeric.linear(fused, x, u, t), SplineNumeric.linear(fused, y, v, t)}

def Spline.linear(start: M.Vector2, end: M.Vector2, t: F32) -> M.Vector2:
  Spline.linear_for(M.Uncontracted{}, start, end, t)

def Spline.basis_for(reference: M.Contraction, first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = first
  M.Vector2{bx, by} = second
  M.Vector2{cx, cy} = third
  M.Vector2{dx, dy} = fourth
  +fused = M.Contraction.fused(reference)
  M.Vector2{SplineNumeric.basis(fused, ax, bx, cx, dx, t), SplineNumeric.basis(fused, ay, by, cy, dy, t)}

def Spline.basis(first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  Spline.basis_for(M.Uncontracted{}, first, second, third, fourth, t)

def Spline.catmull_rom_for(reference: M.Contraction, first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = first
  M.Vector2{bx, by} = second
  M.Vector2{cx, cy} = third
  M.Vector2{dx, dy} = fourth
  +fused = M.Contraction.fused(reference)
  +weights = SplineNumeric.catmull_weights(fused, t)
  M.Vector2{SplineNumeric.catmull(fused, weights, ax, bx, cx, dx), SplineNumeric.catmull(fused, weights, ay, by, cy, dy)}

def Spline.catmull_rom(first: M.Vector2, second: M.Vector2, third: M.Vector2, fourth: M.Vector2, t: F32) -> M.Vector2:
  Spline.catmull_rom_for(M.Uncontracted{}, first, second, third, fourth, t)

def Spline.bezier_quad_for(reference: M.Contraction, start: M.Vector2, control: M.Vector2, end: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{ax, ay} = start
  M.Vector2{bx, by} = control
  M.Vector2{cx, cy} = end
  +fused = M.Contraction.fused(reference)
  M.Vector2{SplineNumeric.bezier_quad(fused, ax, bx, cx, t), SplineNumeric.bezier_quad(fused, ay, by, cy, t)}

def Spline.bezier_quad(start: M.Vector2, control: M.Vector2, end: M.Vector2, t: F32) -> M.Vector2:
  Spline.bezier_quad_for(M.Uncontracted{}, start, control, end, t)

# -----------------------------------------------------------------------------
# Geometry and collision

type BoundingBox is Data:
  BoundingBox{min: M.Vector3, max: M.Vector3}

type Rectangle is Data:
  Rectangle{x: F32, y: F32, width: F32, height: F32}

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

def Collision.multiply_add(arithmetic: M.Contraction, a: F32, b: F32, c: F32) -> F32:
  match arithmetic:
    case M.Uncontracted{}: (a * b + c : F32)
    case M.Fused{}: Fused.multiply_add(a, b, c)

# dx*dx + dy*dy as the linked reference evaluates it: fma(dx, dx, dy*dy) when fused.
def Collision.square_sum(+arithmetic: M.Contraction, +dx: F32, +dy: F32) -> F32:
  Collision.multiply_add(arithmetic, dx, dx, (dy * dy : F32))

# Vector3DistanceSqr inlined into rmodels.c: fma(dz, dz, fma(dx, dx, dy*dy)) when fused.
def Collision.distance_sqr(+arithmetic: M.Contraction, left: M.Vector3, right: M.Vector3) -> F32:
  M.Vector3{x, y, z} = left
  M.Vector3{u, v, w} = right
  +dz = (w - z : F32)
  Collision.multiply_add(arithmetic, dz, dz, Collision.square_sum(arithmetic, (u - x : F32), (v - y : F32)))

def Collision.spheres_for(+arithmetic: M.Contraction, left: M.Vector3, radius: F32, right: M.Vector3, other_radius: F32) -> Bool:
  +sum = (radius + other_radius : F32)
  (Collision.distance_sqr(arithmetic, left, right) <= sum * sum : F32)

def Collision.spheres(left: M.Vector3, radius: F32, right: M.Vector3, other_radius: F32) -> Bool:
  Collision.spheres_for(M.Uncontracted{}, left, radius, right, other_radius)

def Collision.boxes(left: BoundingBox, right: BoundingBox) -> Bool:
  BoundingBox{M.Vector3{ax, ay, az}, M.Vector3{bx, by, bz}} = left
  BoundingBox{M.Vector3{cx, cy, cz}, M.Vector3{dx, dy, dz}} = right
  ((bx >= cx) && (ax <= dx) && (by >= cy) && (ay <= dy) && (bz >= cz) && (az <= dz) : F32)

def Collision.box_sphere_for(+arithmetic: M.Contraction, box: BoundingBox, center: M.Vector3, +radius: F32) -> Bool:
  BoundingBox{M.Vector3{lx, ly, lz}, M.Vector3{ux, uy, uz}} = box
  M.Vector3{+x, +y, +z} = center
  closest = {M.Vector3{M.Math.clamp(x, lx, ux), M.Math.clamp(y, ly, uy), M.Math.clamp(z, lz, uz)} : M.Vector3}
  (Collision.distance_sqr(arithmetic, M.Vector3{x, y, z}, closest) <= radius * radius : F32)

def Collision.box_sphere(box: BoundingBox, center: M.Vector3, +radius: F32) -> Bool:
  Collision.box_sphere_for(M.Uncontracted{}, box, center, radius)

def Collision.recs(left: Rectangle, right: Rectangle) -> Bool:
  Rectangle{+x, +y, w, h} = left
  Rectangle{+u, +v, rw, rh} = right
  ((x < u + rw) && (x + w > u) && (y < v + rh) && (y + h > v) : F32)

def Collision.circles_for(+arithmetic: M.Contraction, left: M.Vector2, radius: F32, right: M.Vector2, other_radius: F32) -> Bool:
  M.Vector2{x, y} = left
  M.Vector2{u, v} = right
  +sum = (radius + other_radius : F32)
  (Collision.square_sum(arithmetic, (u - x : F32), (v - y : F32)) <= sum * sum : F32)

def Collision.circles(left: M.Vector2, radius: F32, right: M.Vector2, other_radius: F32) -> Bool:
  Collision.circles_for(M.Uncontracted{}, left, radius, right, other_radius)

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

def Collision.point_circle_for(+arithmetic: M.Contraction, point: M.Vector2, center: M.Vector2, +radius: F32) -> Bool:
  M.Vector2{x, y} = point
  M.Vector2{cx, cy} = center
  (Collision.square_sum(arithmetic, (x - cx : F32), (y - cy : F32)) <= radius * radius : F32)

def Collision.point_circle(point: M.Vector2, center: M.Vector2, +radius: F32) -> Bool:
  Collision.point_circle_for(M.Uncontracted{}, point, center, radius)

def Collision.circle_rec_for(+arithmetic: M.Contraction, center: M.Vector2, +radius: F32, rectangle: Rectangle) -> Bool:
  M.Vector2{x, y} = center
  Rectangle{rx, ry, w, h} = rectangle
  +half_w = (w / 2.0 : F32)
  +half_h = (h / 2.0 : F32)
  +dx = F32.abs((x - (rx + half_w) : F32))
  +dy = F32.abs((y - (ry + half_h) : F32))
  +corner_x = (dx - half_w : F32)
  +corner_y = (dy - half_h : F32)
  (((dx <= half_w + radius) && (dy <= half_h + radius))
    && ((dx <= half_w) || (dy <= half_h) || (Collision.square_sum(arithmetic, corner_x, corner_y) <= radius * radius)) : F32)

def Collision.circle_rec(center: M.Vector2, +radius: F32, rectangle: Rectangle) -> Bool:
  Collision.circle_rec_for(M.Uncontracted{}, center, radius, rectangle)

def Collision.lines.hit(inside: Bool, +arithmetic: M.Contraction, x: F32, y: F32, rx: F32, ry: F32, +t: F32) -> Maybe<&2, M.Vector2>:
  match inside:
    case False{}: None{}
    case True{}: Some{M.Vector2{Collision.multiply_add(arithmetic, t, rx, x), Collision.multiply_add(arithmetic, t, ry, y)}}

def Collision.lines.divided(nonparallel: Bool, +arithmetic: M.Contraction, +x: F32, +y: F32, +rx: F32, +ry: F32, +sx: F32, +sy: F32, u: F32, v: F32, +divisor: F32) -> Maybe<&2, M.Vector2>:
  match nonparallel:
    case False{}: None{}
    case True{}:
      +dx = (u - x : F32)
      +dy = (v - y : F32)
      +t = (Collision.multiply_add(arithmetic, dx, sy, F32.neg((dy * sx : F32))) / divisor : F32)
      +s = (Collision.multiply_add(arithmetic, dx, ry, F32.neg((dy * rx : F32))) / divisor : F32)
      Collision.lines.hit(((0.0 <= t) && (t <= 1.0) && (0.0 <= s) && (s <= 1.0) : F32), arithmetic, x, y, rx, ry, t)

def Collision.lines_for(+arithmetic: M.Contraction, start: M.Vector2, end: M.Vector2, other_start: M.Vector2, other_end: M.Vector2) -> Maybe<&2, M.Vector2>:
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
  Collision.lines_for(M.Uncontracted{}, start, end, other_start, other_end)

# Each a*b + c*d below is fma(a, b, c*d) in the fused linked reference.
def Collision.point_triangle_for(+arithmetic: M.Contraction, point: M.Vector2, first: M.Vector2, second: M.Vector2, third: M.Vector2) -> Bool:
  M.Vector2{+x, +y} = point
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  M.Vector2{+cx, +cy} = third
  +denominator = Collision.multiply_add(arithmetic, (by - cy : F32), (ax - cx : F32), ((cx - bx) * (ay - cy) : F32))
  +alpha = (Collision.multiply_add(arithmetic, (by - cy : F32), (x - cx : F32), ((cx - bx) * (y - cy) : F32)) / denominator : F32)
  +beta = (Collision.multiply_add(arithmetic, (cy - ay : F32), (x - cx : F32), ((ax - cx) * (y - cy) : F32)) / denominator : F32)
  gamma = (1.0 - alpha - beta : F32)
  ((alpha > 0.0) && (beta > 0.0) && (gamma > 0.0) : F32)

def Collision.point_triangle(point: M.Vector2, first: M.Vector2, second: M.Vector2, third: M.Vector2) -> Bool:
  Collision.point_triangle_for(M.Uncontracted{}, point, first, second, third)

# cross = fma(dxc, dyl, -(dyc*dxl)) in the fused linked reference; the int
# threshold truncates like C's implicit conversion.
def Collision.point_line_for(+arithmetic: M.Contraction, point: M.Vector2, first: M.Vector2, second: M.Vector2, threshold: F32) -> Bool:
  M.Vector2{+x, +y} = point
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  cross = Collision.multiply_add(arithmetic, (x - ax : F32), dy, F32.neg(((y - ay) * dx : F32)))
  along_x = Bool.pick(Bool, (dx > 0.0 : F32), ((ax <= x) && (x <= bx) : F32), ((bx <= x) && (x <= ax) : F32))
  along_y = Bool.pick(Bool, (dy > 0.0 : F32), ((ay <= y) && (y <= by) : F32), ((by <= y) && (y <= ay) : F32))
  (F32.abs(cross) < Signed.trunc(threshold) * F32.max(F32.abs(dx), F32.abs(dy)) : F32)
    && Bool.pick(Bool, (F32.abs(dx) >= F32.abs(dy) : F32), along_x, along_y)

def Collision.point_line(point: M.Vector2, first: M.Vector2, second: M.Vector2, threshold: F32) -> Bool:
  Collision.point_line_for(M.Uncontracted{}, point, first, second, threshold)

# Fused reference: squares as fma(a, a, b*b) and p1 - t*d as one fmsub.
def Collision.circle_line.route(degenerate: Bool, +arithmetic: M.Contraction, +x: F32, +y: F32, +radius: F32, +ax: F32, +ay: F32, bx: F32, by: F32, +dx: F32, +dy: F32) -> Bool:
  match degenerate:
    case True{}: Collision.circles_for(arithmetic, M.Vector2{ax, ay}, 0.0, M.Vector2{x, y}, radius)
    case False{}:
      length_squared = Collision.square_sum(arithmetic, dx, dy)
      +dot = Collision.multiply_add(arithmetic, (x - ax : F32), (bx - ax : F32), ((y - ay) * (by - ay) : F32))
      +projection = M.Math.clamp((dot / length_squared : F32), 0.0, 1.0)
      +distance_x = (Collision.multiply_add(arithmetic, F32.neg(projection), dx, ax) - x : F32)
      +distance_y = (Collision.multiply_add(arithmetic, F32.neg(projection), dy, ay) - y : F32)
      (Collision.square_sum(arithmetic, distance_x, distance_y) <= radius * radius : F32)

def Collision.circle_line_for(+arithmetic: M.Contraction, center: M.Vector2, radius: F32, first: M.Vector2, second: M.Vector2) -> Bool:
  M.Vector2{x, y} = center
  M.Vector2{+ax, +ay} = first
  M.Vector2{+bx, +by} = second
  +dx = (ax - bx : F32)
  +dy = (ay - by : F32)
  Collision.circle_line.route((F32.abs(dx) + F32.abs(dy) <= 0.00000011920928955078125 : F32), arithmetic, x, y, radius, ax, ay, bx, by, dx, dy)

def Collision.circle_line(center: M.Vector2, radius: F32, first: M.Vector2, second: M.Vector2) -> Bool:
  Collision.circle_line_for(M.Uncontracted{}, center, radius, first, second)

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

# raylib requires pointCount > 2; checking the list shape avoids walking it.
def Collision.polygon.enough(points: +List<M.Vector2>) -> Bool:
  match points:
    case Con{_, Con{_, Con{_, _}}}: True{}
    case _: False{}

def Collision.point_poly(point: M.Vector2, +points: +List<M.Vector2>) -> Bool:
  Collision.polygon.enough(points)
    && Collision.polygon.loop(points, point, Collision.polygon.last(points, M.Vector2.zero()), False{})

# -----------------------------------------------------------------------------
# Colors

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

# -----------------------------------------------------------------------------
# Random streams and owned-buffer storage

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

# GetRandomValue(int, int): fractional bounds truncate as C's implicit conversion does.
def Random.value(state: Random.State, minimum: F32, maximum: F32) -> Random.State & F32:
  +low = Signed.trunc(minimum)
  +high = Signed.trunc(maximum)
  +lower = F32.min(low, high)
  upper = F32.max(low, high)
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

# Depth of a balanced Array holding count entries; shared by every owned buffer
# (image storage, random sequences) so padding never reaches an export.
def Storage.depth(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

# Duplicate flags indexed by value - minimum (span <= 65535) keep each draw O(1)
# while accepting exactly the values rprand's linear duplicate scan accepts.
def Random.sequence.mark(+remaining: Nat, +values: +List<F32>, +value: F32, +slot: U32, state: Random.State, read: Array<U32> & U32) -> Random.State & (Nat & (+List<F32> & Array<U32>)):
  (seen, +flag) = read
  +duplicate = U32.is_eq(flag, 1)
  (state, (Bool.pick(Nat, duplicate, 1n+remaining, remaining),
    (Bool.pick(+List<F32>, duplicate, values, Con{value, values}), Array.set(U32, seen, slot, 1))))

def Random.sequence.step(+remaining: Nat, +values: +List<F32>, +minimum: F32, seen: Array<U32>, draw: Random.State & F32) -> Random.State & (Nat & (+List<F32> & Array<U32>)):
  (state, +value) = draw
  +slot = F32.to_u32((value - minimum : F32))
  Random.sequence.mark(remaining, values, value, slot, state, Array.get(U32, seen, slot))

def Random.sequence.loop(budget: Nat, +minimum: F32, +span: U32, cursor: Random.State & (Nat & (+List<F32> & Array<U32>))) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  match budget cursor:
    case _ Tuple{state, Tuple{0n, Tuple{values, _}}}:
      (state, Done{RandomSequence{List.reverse(&2, F32, values)}})
    case 0n Tuple{state, Tuple{_, Tuple{values, _}}}:
      (state, Fail{SequenceDrawLimit{RandomSequence{List.reverse(&2, F32, values)}}})
    case 1n+more Tuple{state, Tuple{1n+remaining, Tuple{values, seen}}}:
      Random.sequence.loop(more, minimum, span, Random.sequence.step(remaining, values, minimum, seen,
        Random.value.result(minimum, span, Random.next_u32(state))))

def Random.sequence.count(valid: Bool, state: Random.State, count: U32, minimum: F32, +span: U32, budget: Nat) -> Random.State & Result<&1, &1, Random.Sequence.Error, Random.Sequence>:
  match valid:
    case False{}: (state, Fail{InvalidSequenceRequest{}})
    case True{}: Random.sequence.loop(budget, minimum, span, (state, (U32.to_nat(count), (Nil{}, Array.new(U32, Storage.depth(span), 0)))))

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

# -----------------------------------------------------------------------------
# Image types and errors

# One owned image, mirroring raylib's Image: dimensions 1..4096, one mip level
# and an uncompressed raylib PixelFormat 1..9. Formats 1..8 store one word per
# pixel (R8G8B8A8 as the canonical Color word, the others as their native
# little-endian sample bytes); the wide formats store one Quad of sample words.
# Build it through a Surface factory, decoder or loader, which keep power-of-two
# storage and each format's sample domain (finite [0, 1] R32 and R16 words, no
# NaN F32 samples in the wide formats).
type Surface is Type:
  Surface{width: U32, height: U32, format: U32, pixels: Surface.Pixels}

# A wide sample as stored words: F32 bits for R32G32B32 (a..c) and R32G32B32A32
# (a..d), half-float bits for R16G16B16 (a..c) and R16G16B16A16 (a..d); unused
# words are zero.
type Surface.Quad is Data:
  Quad{a: U32, b: U32, c: U32, d: U32}

type Surface.Pixels is Type:
  Words{values: Array<U32>}
  Quads{values: Array<Surface.Quad>}

# Internal R8G8B8A8 kernel record: the RGBA8 algorithms below run on it and the
# Surface layer converts formats around them as raylib does.
type Rgba is Type:
  Rgba{width: U32, height: U32, pixels: Array<U32>}

type Surface.Error is Data:
  InvalidSize{}
  InvalidRectangle{}
  InvalidRequest{}
  UnsafeNearestMapping{}
  InvalidDitherBits{}
  InvalidKernel{}
  UnsupportedFormat{}
  OutOfDomain{}
  UnsupportedFileType{}
  InvalidPixelByte{}
  TruncatedPixelData{}
  InvalidImageHeader{}
  InvalidImageByte{}
  UnsupportedImageSize{}
  TruncatedImageData{}
  InvalidImageStream{}

# Loaders report file or data errors; writers return a rejected owner.
type Surface.IOError is Type:
  FileError{code: U32, message: String}
  DataError{error: Surface.Error}
  SourceError{surface: Surface, error: Surface.Error}

# Operations raylib applies as LoadImageColors, an RGBA8 step, then ImageFormat.
type Surface.Recolor is Type:
  Recolored{transform: Color.Transform}
  Replaced{original: U32, replacement: U32}
  BlurredPremultiplied{size: U32}
  Convolved{kernel: +List<F32>}
  Resized{width: U32, height: U32}
  ResizedNearest{width: U32, height: U32}

# Operations raylib applies through ImageDrawPixel (no blending).
type Surface.Draw is Type:
  DrawPixel{x: F32, y: F32}
  DrawPixelV{position: M.Vector2}
  DrawRectangle{x: F32, y: F32, width: F32, height: F32}
  DrawRectangleV{position: M.Vector2, size: M.Vector2}
  DrawRectangleRec{rect: Rectangle}
  DrawRectangleLines{rect: Rectangle, thickness: U32}
  DrawCircle{cx: F32, cy: F32, radius: U32}
  DrawCircleV{center: M.Vector2, radius: U32}
  DrawCircleLines{cx: F32, cy: F32, radius: U32}
  DrawCircleLinesV{center: M.Vector2, radius: U32}
  DrawLine{x0: F32, y0: F32, x1: F32, y1: F32}
  DrawLineV{start: M.Vector2, end: M.Vector2}
  DrawLineEx{start: M.Vector2, end: M.Vector2, thickness: U32}
  DrawTriangle{v1: M.Vector2, v2: M.Vector2, v3: M.Vector2}
  DrawTriangleLines{v1: M.Vector2, v2: M.Vector2, v3: M.Vector2}
  DrawTriangleFan{points: +List<M.Vector2>}
  DrawTriangleStrip{points: +List<M.Vector2>}
  ClearBackground{}

# Two-image RGBA8 operations; both owners come back, destination first.
type Image.Animation is Type:
  Animation{width: U32, height: U32, count: U32, frames: List<Surface>}

type Image.Mipmaps is Type:
  Mipmaps{count: U32, levels: List<Surface>}

def Image.list.prefix(~T: Type, n: Nat, values: List<T>, prefix: List<T>) -> List<T>:
  match n values:
    case 0n _: List.reverse(&1, T, prefix)
    case _ Nil{}: List.reverse(&1, T, prefix)
    case 1n+rest Con{value, tail}: Image.list.prefix(~T, rest, tail, Con{value, prefix})

def Image.list.take(~T: Type, values: List<T>, n: Nat) -> List<T>:
  Image.list.prefix(~T, n, values, Nil{})

# -----------------------------------------------------------------------------
# Raw pixel bytes (GetPixelDataSize, GetPixelColor, SetPixelColor)

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

def Pixel.packed_color(format: U32, +word: U32) -> U32:
  match format:
    case 3:
      Color.rgba(((word >> 11n) * 255 / 31 : U32), (((word >> 5n) .&. 63) * 255 / 63 : U32), ((word .&. 31) * 255 / 31 : U32), 255)
    case 5:
      # GetPixelColor uses the low five bits directly for blue, including alpha.
      Color.rgba(((word >> 11n) * 255 / 31 : U32), (((word >> 6n) .&. 31) * 255 / 31 : U32), ((word .&. 31) * 255 / 31 : U32), ((word .&. 1) * 255 : U32))
    case _:
      Color.rgba(((word >> 12n) * 17 : U32), (((word >> 8n) .&. 15) * 17 : U32), (((word >> 4n) .&. 15) * 17 : U32), ((word .&. 15) * 17 : U32))

def Pixel.read.bytes(format: U32, bytes: +List<U32>) -> Result<&2, &2, Surface.Error, U32>:
  match format bytes:
    case 1 Con{+gray, _}: Done{Color.rgba(gray, gray, gray, 255)}
    case 2 Con{+gray, Con{alpha, _}}: Done{Color.rgba(gray, gray, gray, alpha)}
    case 3 Con{low, Con{high, _}}: Done{Pixel.packed_color(3, (low .|. (high << 8n) : U32))}
    case 4 Con{r, Con{g, Con{b, _}}}: Done{Color.rgba(r, g, b, 255)}
    case 5 Con{low, Con{high, _}}: Done{Pixel.packed_color(5, (low .|. (high << 8n) : U32))}
    case 6 Con{low, Con{high, _}}: Done{Pixel.packed_color(6, (low .|. (high << 8n) : U32))}
    case 7 Con{r, Con{g, Con{b, Con{a, _}}}}: Done{Color.rgba(r, g, b, a)}
    case _ _: Fail{TruncatedPixelData{}}

def Pixel.read.valid(valid: Bool, format: U32, bytes: +List<U32>) -> Result<&2, &2, Surface.Error, U32>:
  match valid:
    case False{}: Fail{InvalidPixelByte{}}
    case True{}: Pixel.read.bytes(format, bytes)

def Pixel.read.format(valid: Bool, format: U32, +bytes: +List<U32>) -> Result<&2, &2, Surface.Error, U32>:
  match valid:
    case False{}: Fail{UnsupportedFormat{}}
    case True{}: Pixel.read.valid(Codec.valid_bytes(bytes, True{}), format, bytes)

def Pixel.get_color(bytes: +List<U32>, +format: U32) -> Result<&2, &2, Surface.Error, U32>:
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

def Pixel.write.sized(valid: Bool, +format: U32, color: U32, bytes: +List<U32>) -> Result<&2, &2, Surface.Error, +List<U32>>:
  match valid:
    case False{}: Fail{TruncatedPixelData{}}
    case True{}:
      Done{List.append(&2, U32, Pixel.encode(format, color), List.drop(&2, U32, bytes, U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32))))}

def Pixel.write.bytes(valid: Bool, +format: U32, color: U32, +bytes: +List<U32>) -> Result<&2, &2, Surface.Error, +List<U32>>:
  match valid:
    case False{}: Fail{InvalidPixelByte{}}
    case True{}: Pixel.write.sized(Pixel.enough(U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), bytes), format, color, bytes)

def Pixel.write.format(valid: Bool, format: U32, color: U32, +bytes: +List<U32>) -> Result<&2, &2, Surface.Error, +List<U32>>:
  match valid:
    case False{}: Fail{UnsupportedFormat{}}
    case True{}: Pixel.write.bytes(Codec.valid_bytes(bytes, True{}), format, color, bytes)

def Pixel.set_color(bytes: +List<U32>, color: U32, +format: U32) -> Result<&2, &2, Surface.Error, +List<U32>>:
  Pixel.write.format(((format >= 1) && (format <= 7) : U32), format, color, bytes)

# -----------------------------------------------------------------------------
# RGBA8 kernels: generation, color, drawing, geometry and resampling

def Rgba.creation.checked(ok: Bool, +w: U32, +h: U32, color: U32) -> Maybe<Rgba>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Rgba{w, h, Array.new(U32, Storage.depth((w * h : U32)), color)}}

# The initial profile supports 1..4096 pixels on each axis.
def Rgba.create(+w: U32, +h: U32, color: U32) -> Maybe<Rgba>:
  Rgba.creation.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), w, h, color)

def Rgba.text.fill(n: Nat, +index: U32, bytes: +List<U32>, pixels: Array<U32>) -> Array<U32>:
  match n bytes:
    case 0n _: pixels
    case _ Nil{}: pixels
    case _ Con{0, _}: pixels
    case 1n+rest Con{+byte, tail}:
      Rgba.text.fill(rest, (index + 1 : U32), tail, Array.set(U32, pixels, index, Color.rgba(byte, byte, byte, 255)))

def Rgba.text.checked(valid: Bool, +width: U32, +height: U32, bytes: +List<U32>) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Rgba{width, height, Rgba.text.fill(U32.to_nat(count), 0, bytes, Array.new(U32, Storage.depth(count), 255))}}

def Rgba.create_text_bytes(+width: U32, +height: U32, +bytes: +List<U32>) -> Maybe<Rgba>:
  Rgba.text.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && Codec.valid_bytes(bytes, True{}), width, height, bytes)

def Rgba.noise.write(index: U32, threshold: U32, pixels: Array<U32>, draw: Random.State & U32) -> Random.State & Array<U32>:
  (state, value) = draw
  color = Bool.pick(U32, (value % 100 < threshold : U32), 4294967295, 255)
  (state, Array.set(U32, pixels, index, color))

def Rgba.noise.loop(n: Nat, +index: U32, +threshold: U32, buffers: Random.State & Array<U32>) -> Random.State & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+k Tuple{state, pixels}:
      Rgba.noise.loop(k, (index + 1 : U32), threshold, Rgba.noise.write(index, threshold, pixels, Random.next_u32(state)))

def Rgba.noise.finished(width: U32, height: U32, buffers: Random.State & Array<U32>) -> Random.State & Maybe<Rgba>:
  (state, pixels) = buffers
  (state, Some{Rgba{width, height, pixels}})

def Rgba.noise.checked(valid: Bool, state: Random.State, +width: U32, +height: U32, factor: F32) -> Random.State & Maybe<Rgba>:
  match valid:
    case False{}: (state, None{})
    case True{}:
      +count = (width * height : U32)
      Rgba.noise.finished(width, height, Rgba.noise.loop(U32.to_nat(count), 0, F32.to_u32((factor * 100.0 : F32)),
        (state, Array.new(U32, Storage.depth(count), 255))))

def Rgba.create_white_noise(state: Random.State, +width: U32, +height: U32, +factor: F32) -> Random.State & Maybe<Rgba>:
  Rgba.noise.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((factor >= 0.0) && (factor <= 1.0) : F32), state, width, height, factor)

def Rgba.cellular.finished(width: U32, height: U32, result: Rng.State & Array<U32>) -> Random.State & Maybe<Rgba>:
  (state, pixels) = result
  (RandomState{state}, Some{Rgba{width, height, pixels}})

def Rgba.cellular.checked(valid: Bool, state: Random.State, +width: U32, +height: U32, tile: U32) -> Random.State & Maybe<Rgba>:
  match valid state:
    case False{} _: (state, None{})
    case True{} RandomState{inner}:
      Rgba.cellular.finished(width, height, Cellular.generate(inner, width, height, tile))

def Rgba.create_cellular(state: Random.State, +width: U32, +height: U32, +tile: U32) -> Random.State & Maybe<Rgba>:
  Rgba.cellular.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (tile > 0) && (tile <= 4096) : U32), state, width, height, tile)

def Rgba.perlin.checked(valid: Bool, reference: M.Contraction, +width: U32, +height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Rgba{width, height, Perlin.pixels(U32.to_nat(count), 0, M.Contraction.fused(reference), width, height, offset_x, offset_y, scale,
        Array.new(U32, Storage.depth(count), 255))}}

def Rgba.create_perlin_for(reference: M.Contraction, +width: U32, +height: U32, +offset_x: F32, +offset_y: F32, +scale: F32) -> Maybe<Rgba>:
  Rgba.perlin.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((F32.abs(offset_x) <= 32767.0) && (F32.abs(offset_y) <= 32767.0) && (F32.abs(scale) <= 256.0) : F32)
    && F32.is_eq(F32.floor(offset_x), offset_x) && F32.is_eq(F32.floor(offset_y), offset_y)
    && (F32.is_eq(scale, 0.0) || (F32.abs(scale) >= 0.0000152587890625 : F32)), reference, width, height, offset_x, offset_y, scale)

def Rgba.create_perlin(width: U32, height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Rgba>:
  Rgba.create_perlin_for(M.Uncontracted{}, width, height, offset_x, offset_y, scale)

def Rgba.checked.loop(n: Nat, +i: U32, +width: U32, +tx: U32, +ty: U32, +first: U32, +second: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      color = Bool.pick(U32, U32.is_eq((((i % width) / tx + (i / width) / ty) .&. 1 : U32), 0), first, second)
      Rgba.checked.loop(k, (i + 1 : U32), width, tx, ty, first, second, Array.set(U32, pixels, i, color))

def Rgba.checked.create(valid: Bool, +width: U32, +height: U32, tx: U32, ty: U32, +first: U32, second: U32) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Rgba{width, height, Rgba.checked.loop(U32.to_nat(count), 0, width, tx, ty, first, second, Array.new(U32, Storage.depth(count), first))}}

def Rgba.create_checked(+width: U32, +height: U32, +tx: U32, +ty: U32, first: U32, second: U32) -> Maybe<Rgba>:
  Rgba.checked.create(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (tx > 0) && (ty > 0) && (tx <= 2147483647) && (ty <= 2147483647) : U32), width, height, tx, ty, first, second)

def Rgba.square_gradient.loop(n: Nat, +i: U32, +width: U32, +cx: F32, +cy: F32, +density: F32, +inner: U32, +outer: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      nx = (F32.abs((U32.to_f32((i % width : U32)) - cx : F32)) / cx : F32)
      ny = (F32.abs((U32.to_f32((i / width : U32)) - cy : F32)) / cy : F32)
      factor = ((F32.max(nx, ny) - density) / (1.0 - density) : F32)
      Rgba.square_gradient.loop(k, (i + 1 : U32), width, cx, cy, density, inner, outer,
        Array.set(U32, pixels, i, Color.lerp(inner, outer, factor)))

def Rgba.square_gradient.checked(valid: Bool, solid: Bool, +width: U32, +height: U32, density: F32, +inner: U32, outer: U32) -> Maybe<Rgba>:
  match valid solid:
    case False{} _: None{}
    case True{} True{}: Rgba.create(width, height, inner)
    case True{} False{}:
      +count = (width * height : U32)
      Some{Rgba{width, height, Rgba.square_gradient.loop(U32.to_nat(count), 0, width,
        (U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32), density, inner, outer,
        Array.new(U32, Storage.depth(count), inner))}}

def Rgba.create_gradient_square(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  Rgba.square_gradient.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), F32.is_eq(density, 1.0), width, height, density, inner, outer)

def Rgba.radial.checked(valid: Bool, +width: U32, +height: U32, density: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      paint = {Gradients.Radial{(U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32),
        (U32.to_f32(U32.min(width, height)) / 2.0 : F32), density, inner, outer} : Gradients.Paint}
      Some{Rgba{width, height, Gradients.generate(Storage.depth(count), width, count, paint)}}

def Rgba.create_gradient_radial(+width: U32, +height: U32, +density: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  Rgba.radial.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && ((density >= 0.0) && (density <= 1.0) : F32), width, height, density, inner, outer)

def Rgba.linear.ready(valid: Bool, +width: U32, +height: U32, cosine: F32, sine: F32, start: F32, extent: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      +count = (width * height : U32)
      Some{Rgba{width, height, Gradients.generate(Storage.depth(count), width, count,
        Gradients.Linear{cosine, sine, start, extent, inner, outer})}}

def Rgba.linear.trigonometry(+width: U32, +height: U32, inner: U32, outer: U32, values: F32 & F32) -> Maybe<Rgba>:
  (+cosine, +sine) = values
  +start = (0.5 - cosine * U32.to_f32(width) / 2.0 - sine * U32.to_f32(height) / 2.0 : F32)
  same_sign = U32.is_eq((F32.bits(sine) >> 31n : U32), (F32.bits(cosine) >> 31n : U32))
  +extent = F32.abs(Bool.pick(F32, same_sign, start, (start + U32.to_f32(width) * cosine : F32)))
  Rgba.linear.ready((extent > 0.0 : F32), width, height, cosine, sine, start, extent, inner, outer)

def Rgba.linear.checked(valid: Bool, reference: M.Libm, +width: U32, +height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  match valid:
    case False{}: None{}
    case True{}:
      radians = ((90.0 - direction) / 180.0 * 3.14159 : F32)
      Rgba.linear.trigonometry(width, height, inner, outer, Trig.sincos_for(M.Libm.gnu(reference), radians))

def Rgba.create_gradient_linear_for(reference: M.Libm, +width: U32, +height: U32, +direction: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  Rgba.linear.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32)
    && (F32.abs(direction) <= 360.0 : F32) && F32.is_eq(F32.floor(direction), direction), reference, width, height, direction, inner, outer)

def Rgba.create_gradient_linear(width: U32, height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Rgba>:
  Rgba.create_gradient_linear_for(M.AppleLibm{}, width, height, direction, inner, outer)

def Rgba.clear(surface: Rgba, color: U32) -> Rgba:
  Rgba{+w, +h, _} = surface
  Rgba{w, h, Array.new(U32, Storage.depth((w * h : U32)), color)}

def Rgba.color.step(i: U32, transform: Color.Transform, got: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = got
  Array.set(U32, pixels, i, Color.transform(transform, pixel))

def Rgba.color.loop(n: Nat, +i: U32, +transform: Color.Transform, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+k:
      Rgba.color.loop(k, (i + 1 : U32), transform, Rgba.color.step(i, transform, Array.get(U32, pixels, i)))

def Rgba.color.transform(surface: Rgba, transform: Color.Transform) -> Rgba:
  Rgba{+w, +h, pixels} = surface
  Rgba{w, h, Rgba.color.loop(U32.to_nat((w * h : U32)), 0, transform, pixels)}

def Color.Transform.contrast(amount: F32) -> Color.Transform:
  +contrast = ((100.0 + F32.clamp(amount, (0.0 - 100.0 : F32), 100.0)) / 100.0 : F32)
  ImageContrast{(contrast * contrast : F32)}

# ImageColorBrightness takes int: truncate toward zero, then clamp like raylib.
def Color.Transform.brightness(amount: F32) -> Color.Transform:
  ImageBrightness{F32.clamp(Signed.trunc(amount), (0.0 - 255.0 : F32), 255.0)}

def Rgba.alpha_clear(surface: Rgba, color: U32, threshold: F32) -> Rgba:
  Rgba.color.transform(surface, AlphaClear{F32.to_u32((threshold * 255.0 : F32)), color})

def Rgba.blur_gaussian.premultiplied(size: U32, surface: Rgba) -> Rgba:
  Rgba{+width, +height, pixels} = surface
  Rgba{width, height, Blur.blur(width, height, size, pixels)}

def Rgba.convolution.result(width: U32, height: U32, result: Result<&1, &1, Array<U32>, Array<U32>>) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  match result:
    case Fail{source}: Fail{(Rgba{width, height, source}, InvalidKernel{})}
    case Done{output}: Done{Rgba{width, height, output}}

def Rgba.kernel_convolution(surface: Rgba, kernel: +List<F32>) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  Rgba{+width, +height, pixels} = surface
  Rgba.convolution.result(width, height, Convolution.apply(width, height, kernel, pixels))

def Rgba.pixel.checked(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: F32, y: F32, color: U32) -> Rgba:
  match ok:
    case False{}:
      Rgba{w, h, pixels}
    case True{}:
      Rgba{w, h, Array.set(U32, pixels, (F32.to_u32(y) * w + F32.to_u32(x) : U32), color)}

# Drawing coordinates are finite integral F32 values in the initial profile.
# ImageDrawPixel replaces RGBA bytes; it does not alpha-blend them.
def Rgba.draw_pixel(surface: Rgba, +x: F32, +y: F32, color: U32) -> Rgba:
  Rgba{+w, +h, pixels} = surface
  Rgba.pixel.checked(((x >= 0.0) && (y >= 0.0) && (x < U32.to_f32(w)) && (y < U32.to_f32(h)) : F32), w, h, pixels, x, y, color)

def Rgba.draw_pixel_v(surface: Rgba, position: M.Vector2, color: U32) -> Rgba:
  M.Vector2{x, y} = position
  Rgba.draw_pixel(surface, Signed.trunc(x), Signed.trunc(y), color)

def Rgba.span(n: Nat, +at: U32, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Rgba.span(k, (at + 1 : U32), color, Array.set(U32, pixels, at, color))

def Rgba.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, +color: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Rgba.rows(k, (at + stride : U32), stride, cols, color, Rgba.span(cols, at, color, pixels))

def Rgba.rectangle.fill(ok: Bool, +w: U32, h: U32, pixels: Array<U32>, x: U32, y: U32, +cols: U32, rows: U32, color: U32) -> Rgba:
  match ok:
    case False{}:
      Rgba{w, h, pixels}
    case True{}:
      # raylib writes the first pixel even for an accepted zero-width rectangle;
      # subsequent rows copy zero bytes. Zero height still writes the first row.
      +nr = Bool.pick(U32, U32.is_eq(cols, 0), 1, U32.max(1, rows))
      Rgba{w, h, Rgba.rows(U32.to_nat(nr), (y * w + x : U32), w,
        U32.to_nat(U32.max(1, cols)), color, pixels)}

def Rgba.draw_rectangle(surface: Rgba, +x: F32, +y: F32, width: F32, height: F32, color: U32) -> Rgba:
  Rgba{+w, +h, pixels} = surface
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.max(0.0, F32.min(F32.max(0.0, (width + F32.min(0.0, x) : F32)), (U32.to_f32(w) - sx : F32)))
  +ch = F32.max(0.0, F32.min(F32.max(0.0, (height + F32.min(0.0, y) : F32)), (U32.to_f32(h) - sy : F32)))
  Rgba.rectangle.fill(((sx < U32.to_f32(w)) && (sy < U32.to_f32(h)) && (sx + cw > 0.0) && (sy + ch > 0.0) : F32),
    w, h, pixels, F32.to_u32(sx), F32.to_u32(sy), F32.to_u32(cw), F32.to_u32(ch), color)

def Rgba.draw_rectangle_v(surface: Rgba, position: M.Vector2, size: M.Vector2, color: U32) -> Rgba:
  M.Vector2{x, y} = position
  M.Vector2{width, height} = size
  Rgba.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), Signed.trunc(height), color)

def Rgba.draw_rectangle_rec(surface: Rgba, rect: Rectangle, color: U32) -> Rgba:
  Rectangle{x, y, width, height} = rect
  Rgba.draw_rectangle(surface, x, y, width, height, color)

def Rgba.draw_rectangle_lines(surface: Rgba, rect: Rectangle, +thickness: U32, +color: U32) -> Rgba:
  Rectangle{+x, +y, +width, +height} = rect
  +t = U32.to_f32(thickness)
  s0 = Rgba.draw_rectangle(surface, Signed.trunc(x), Signed.trunc(y), Signed.trunc(width), t, color)
  s1 = Rgba.draw_rectangle(s0, Signed.trunc(x), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  s2 = Rgba.draw_rectangle(s1, Signed.trunc((x + width - t : F32)), Signed.trunc((y + t : F32)), t, Signed.trunc((height - t * 2.0 : F32)), color)
  Rgba.draw_rectangle(s2, Signed.trunc(x), Signed.trunc((y + height - t : F32)), Signed.trunc(width), t, color)

def Rgba.circle.plot(outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +color: U32, surface: Rgba) -> Rgba:
  match outline:
    case False{}:
      s0 = Rgba.draw_rectangle(surface, (cx - x : F32), (cy + y : F32), (x * 2.0 : F32), 1.0, color)
      s1 = Rgba.draw_rectangle(s0, (cx - x : F32), (cy - y : F32), (x * 2.0 : F32), 1.0, color)
      s2 = Rgba.draw_rectangle(s1, (cx - y : F32), (cy + x : F32), (y * 2.0 : F32), 1.0, color)
      Rgba.draw_rectangle(s2, (cx - y : F32), (cy - x : F32), (y * 2.0 : F32), 1.0, color)
    case True{}:
      s0 = Rgba.draw_pixel(surface, (cx + x : F32), (cy + y : F32), color)
      s1 = Rgba.draw_pixel(s0, (cx - x : F32), (cy + y : F32), color)
      s2 = Rgba.draw_pixel(s1, (cx + x : F32), (cy - y : F32), color)
      s3 = Rgba.draw_pixel(s2, (cx - x : F32), (cy - y : F32), color)
      s4 = Rgba.draw_pixel(s3, (cx + y : F32), (cy + x : F32), color)
      s5 = Rgba.draw_pixel(s4, (cx - y : F32), (cy + x : F32), color)
      s6 = Rgba.draw_pixel(s5, (cx + y : F32), (cy - x : F32), color)
      Rgba.draw_pixel(s6, (cx - y : F32), (cy - x : F32), color)

def Rgba.circle.loop(fuel: Nat, on: Bool, +outline: Bool, +cx: F32, +cy: F32, +x: F32, +y: F32, +error: F32, +color: U32, surface: Rgba) -> Rgba:
  match fuel on:
    case 0n _:
      surface
    case 1n+k False{}:
      surface
    case 1n+k True{}:
      drawn = Rgba.circle.plot(outline, cx, cy, x, y, color, surface)
      +nx = (x + 1.0 : F32)
      +down = (error > 0.0 : F32)
      +ny = Bool.pick(F32, down, (y - 1.0 : F32), y)
      ne = Bool.pick(F32, down, (error + 4.0 * (nx - ny) + 10.0 : F32), (error + 4.0 * nx + 6.0 : F32))
      Rgba.circle.loop(k, (ny >= nx : F32), outline, cx, cy, nx, ny, ne, color, drawn)

# Midpoint scanlines match raylib ImageDrawCircle, including its edge coverage.
def Rgba.draw_circle(surface: Rgba, cx: F32, cy: F32, +radius: U32, color: U32) -> Rgba:
  +r = U32.to_f32(radius)
  Rgba.circle.loop(1n+U32.to_nat(radius), True{}, False{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Rgba.draw_circle_v(surface: Rgba, center: M.Vector2, radius: U32, color: U32) -> Rgba:
  M.Vector2{x, y} = center
  Rgba.draw_circle(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Rgba.draw_circle_lines(surface: Rgba, cx: F32, cy: F32, +radius: U32, color: U32) -> Rgba:
  +r = U32.to_f32(radius)
  Rgba.circle.loop(1n+U32.to_nat(radius), True{}, True{}, cx, cy, 0.0, r, (3.0 - 2.0 * r : F32), color, surface)

def Rgba.draw_circle_lines_v(surface: Rgba, center: M.Vector2, radius: U32, color: U32) -> Rgba:
  M.Vector2{x, y} = center
  Rgba.draw_circle_lines(surface, Signed.trunc(x), Signed.trunc(y), radius, color)

def Rgba.line.loop(n: Nat, +vertical: Bool, +x: F32, +y: F32, +direction: F32, +major: F32, +minor: U32, +step: U32, +color: U32, surface: Rgba) -> Rgba:
  match n:
    case 0n:
      surface
    case 1n+k:
      +offset = Signed.high16(minor)
      px = (x + Bool.pick(F32, vertical, offset, major) : F32)
      py = (y + Bool.pick(F32, vertical, major, offset) : F32)
      Rgba.line.loop(k, vertical, x, y, direction, (major + direction : F32),
        (minor + step : U32), step, color, Rgba.draw_pixel(surface, px, py, color))

# The 16.16 short-axis accumulator and excluded final endpoint match ImageDrawLine.
def Rgba.draw_line(surface: Rgba, +x0: F32, +y0: F32, x1: F32, y1: F32, color: U32) -> Rgba:
  +dx = (x1 - x0 : F32)
  +dy = (y1 - y0 : F32)
  +vertical = (F32.abs(dy) > F32.abs(dx) : F32)
  +long = Bool.pick(F32, vertical, dy, dx)
  +short = Bool.pick(F32, vertical, dx, dy)
  +count = F32.to_u32(F32.abs(long))
  +magnitude = ((F32.to_u32(F32.abs(short)) << 16n) / U32.max(1, count) : U32)
  step = Bool.pick(U32, (short < 0.0 : F32), (0 - magnitude : U32), magnitude)
  Rgba.line.loop(U32.to_nat(count), vertical, x0, y0,
    Bool.pick(F32, (long < 0.0 : F32), (0.0 - 1.0 : F32), 1.0), 0.0, 0, step, color, surface)

def Rgba.draw_line_v(surface: Rgba, start: M.Vector2, end: M.Vector2, color: U32) -> Rgba:
  M.Vector2{x0, y0} = start
  M.Vector2{x1, y1} = end
  Rgba.draw_line(surface, Signed.trunc((x0 + 0.5 : F32)), Signed.trunc((y0 + 0.5 : F32)),
    Signed.trunc((x1 + 0.5 : F32)), Signed.trunc((y1 + 0.5 : F32)), color)

def Rgba.thick_line.loop(n: Nat, +horizontal: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +offset: F32, +step: F32, +color: U32, surface: Rgba) -> Rgba:
  match n:
    case 0n: surface
    case 1n+k:
      +ox = Bool.pick(F32, horizontal, 0.0, offset)
      +oy = Bool.pick(F32, horizontal, offset, 0.0)
      Rgba.thick_line.loop(k, horizontal, x0, y0, x1, y1, (offset + step : F32), step, color,
        Rgba.draw_line(surface, (x0 + ox : F32), (y0 + oy : F32), (x1 + ox : F32), (y1 + oy : F32), color))

def Rgba.draw_line_ex(surface: Rgba, start: M.Vector2, end: M.Vector2, +thickness: U32, +color: U32) -> Rgba:
  M.Vector2{x0, y0} = start
  M.Vector2{x1, y1} = end
  +ax = Signed.trunc((x0 + 0.5 : F32))
  +ay = Signed.trunc((y0 + 0.5 : F32))
  +bx = Signed.trunc((x1 + 0.5 : F32))
  +by = Signed.trunc((y1 + 0.5 : F32))
  +horizontal = (F32.abs((by - ay : F32)) < F32.abs((bx - ax : F32)) : F32)
  lower = Rgba.thick_line.loop(U32.to_nat((thickness / 2 + 1 : U32)), horizontal, ax, ay, bx, by, 0.0, 1.0, color, surface)
  Rgba.thick_line.loop(U32.to_nat(((U32.max(1, thickness) - 1) / 2 : U32)), horizontal, ax, ay, bx, by, (0.0 - 1.0 : F32), (0.0 - 1.0 : F32), color, lower)

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

# raylib truncates each step to int before seeding the row value in float.
def Raster.edge(x: F32, y: F32, vx: F32, vy: F32, +dx: F32, +dy: F32) -> Raster.Edge:
  +sx = Signed.trunc(dx)
  +sy = Signed.trunc(dy)
  Edge{Signed.word(((x - vx) * sx + sy * (y - vy) : F32)), Signed.word(sx), Signed.word(sy)}

def Rgba.triangle.pixel(inside: Bool, pixels: Array<U32>, at: U32, paint: Raster.Paint, a: U32, b: U32, c: U32) -> Array<U32>:
  match inside:
    case False{}:
      pixels
    case True{}:
      Array.set(U32, pixels, at, Raster.paint(paint, a, b, c))

def Rgba.triangle.row(n: Nat, +at: U32, +a: U32, +b: U32, +c: U32, +ax: U32, +bx: U32, +cx: U32, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      inside = U32.is_eq(((a .|. b .|. c) .&. 2147483648 : U32), 0)
      Rgba.triangle.row(k, (at + 1 : U32), (a + ax : U32), (b + bx : U32), (c + cx : U32),
        ax, bx, cx, paint, Rgba.triangle.pixel(inside, pixels, at, paint, a, b, c))

def Rgba.triangle.rows(n: Nat, +at: U32, +stride: U32, +cols: Nat, ea: Raster.Edge, eb: Raster.Edge, ec: Raster.Edge, +paint: Raster.Paint, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      pixels
    case 1n+k:
      Edge{+a, +ax, +ay} = ea
      Edge{+b, +bx, +by} = eb
      Edge{+c, +cx, +cy} = ec
      Rgba.triangle.rows(k, (at + stride : U32), stride, cols,
        Edge{(a + ay : U32), ax, ay}, Edge{(b + by : U32), bx, by}, Edge{(c + cy : U32), cx, cy}, paint,
        Rgba.triangle.row(cols, at, a, b, c, ax, bx, cx, paint, pixels))

def Rgba.triangle.fill(visible: Bool, +w: U32, h: U32, pixels: Array<U32>, +x0: F32, +y0: F32, x1: F32, y1: F32, a: Raster.Edge, b: Raster.Edge, c: Raster.Edge, paint: Raster.Paint) -> Rgba:
  match visible:
    case False{}:
      Rgba{w, h, pixels}
    case True{}:
      cols = U32.to_nat(F32.to_u32((x1 - x0 + 1.0 : F32)))
      rows = U32.to_nat(F32.to_u32((y1 - y0 + 1.0 : F32)))
      Rgba{w, h, Rgba.triangle.rows(rows, (F32.to_u32(y0) * w + F32.to_u32(x0) : U32), w,
        cols, a, b, c, paint, pixels)}

def Rgba.draw_triangle(surface: Rgba, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, color: U32) -> Rgba:
  Rgba{+w, +h, pixels} = surface
  M.Vector2{+ax, +ay} = v1
  M.Vector2{+bx, +by} = v2
  M.Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, Signed.trunc(F32.min(ax, F32.min(bx, cx))))
  +y0 = F32.max(0.0, Signed.trunc(F32.min(ay, F32.min(by, cy))))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), Signed.trunc(F32.max(ax, F32.max(bx, cx))))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), Signed.trunc(F32.max(ay, F32.max(by, cy))))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  Rgba.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1,
    Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32)),
    Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32)),
    Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32)), FlatPaint{color})

def Rgba.draw_triangle_ex(surface: Rgba, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, c1: U32, c2: U32, c3: U32) -> Rgba:
  Rgba{+w, +h, pixels} = surface
  M.Vector2{+ax, +ay} = v1
  M.Vector2{+bx, +by} = v2
  M.Vector2{+cx, +cy} = v3
  +x0 = F32.max(0.0, Signed.trunc(F32.min(ax, F32.min(bx, cx))))
  +y0 = F32.max(0.0, Signed.trunc(F32.min(ay, F32.min(by, cy))))
  +x1 = F32.min(U32.to_f32((w - 1 : U32)), Signed.trunc(F32.max(ax, F32.max(bx, cx))))
  +y1 = F32.min(U32.to_f32((h - 1 : U32)), Signed.trunc(F32.max(ay, F32.max(by, cy))))
  +sign = Bool.pick(F32, ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay) > 0.0 : F32), (0.0 - 1.0 : F32), 1.0)
  +ea = Raster.edge(x0, y0, bx, by, ((cy - by) * sign : F32), ((bx - cx) * sign : F32))
  +eb = Raster.edge(x0, y0, cx, cy, ((ay - cy) * sign : F32), ((cx - ax) * sign : F32))
  +ec = Raster.edge(x0, y0, ax, ay, ((by - ay) * sign : F32), ((ax - bx) * sign : F32))
  Rgba.triangle.fill(((x0 <= x1) && (y0 <= y1) : F32), w, h, pixels, x0, y0, x1, y1, ea, eb, ec,
    VertexPaint{c1, c2, c3, Raster.inverse(ea, eb, ec)})

def Rgba.draw_triangle_lines(surface: Rgba, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, +color: U32) -> Rgba:
  M.Vector2{ax, ay} = v1
  M.Vector2{bx, by} = v2
  M.Vector2{cx, cy} = v3
  +x0 = Signed.trunc(ax)
  +y0 = Signed.trunc(ay)
  +x1 = Signed.trunc(bx)
  +y1 = Signed.trunc(by)
  +x2 = Signed.trunc(cx)
  +y2 = Signed.trunc(cy)
  a = Rgba.draw_line(surface, x0, y0, x1, y1, color)
  b = Rgba.draw_line(a, x1, y1, x2, y2, color)
  Rgba.draw_line(b, x2, y2, x0, y0, color)

def Rgba.fan.loop(points: +List<M.Vector2>, +center: M.Vector2, previous: M.Vector2, +color: U32, surface: Rgba) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Rgba.fan.loop(rest, center, next, color, Rgba.draw_triangle(surface, center, previous, next, color))

def Rgba.fan.start(points: +List<M.Vector2>, center: M.Vector2, color: U32, surface: Rgba) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Rgba.fan.loop(rest, center, previous, color, surface)

def Rgba.draw_triangle_fan(surface: Rgba, points: +List<M.Vector2>, color: U32) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{center, rest}: Rgba.fan.start(rest, center, color, surface)

def Rgba.strip.loop(points: +List<M.Vector2>, +older: M.Vector2, +previous: M.Vector2, +even: Bool, +color: U32, surface: Rgba) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{+next, rest}:
      Rgba.strip.loop(rest, previous, next, Bool.not(even), color,
        Rgba.draw_triangle(surface, next, Bool.pick(M.Vector2, even, older, previous), Bool.pick(M.Vector2, even, previous, older), color))

def Rgba.strip.start(points: +List<M.Vector2>, older: M.Vector2, color: U32, surface: Rgba) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{previous, rest}: Rgba.strip.loop(rest, older, previous, True{}, color, surface)

def Rgba.draw_triangle_strip(surface: Rgba, points: +List<M.Vector2>, color: U32) -> Rgba:
  match points:
    case Nil{}: surface
    case Con{older, rest}: Rgba.strip.start(rest, older, color, surface)

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
    Array.new(T, Storage.depth(count), initial), Array.get(T, source, Raster.index(mapping, 0)))

def Rgba.sample(+count: U32, +mapping: Raster.Mapping, source: Array<U32>) -> Array<U32> & Array<U32>:
  Raster.sample(~U32, count, mapping, 0, source)

type Raster.AlphaBounds is Data:
  AlphaBounds{left: U32, top: U32, right: U32, bottom: U32}

def Rgba.border.expand(selected: Bool, +x: U32, +y: U32, bounds: Raster.AlphaBounds) -> Raster.AlphaBounds:
  match selected:
    case False{}: bounds
    case True{}:
      AlphaBounds{left, top, right, bottom} = bounds
      AlphaBounds{U32.min(left, x), U32.min(top, y), U32.max(right, x), U32.max(bottom, y)}

def Rgba.border.pixel(+i: U32, +width: U32, threshold: U32, bounds: Raster.AlphaBounds, got: Array<U32> & U32) -> Array<U32> & Raster.AlphaBounds:
  (pixels, color) = got
  (pixels, Rgba.border.expand((Color.alpha(color) > threshold : U32), (i % width : U32), (i / width : U32), bounds))

def Rgba.border.scan(n: Nat, +i: U32, +width: U32, +threshold: U32, state: Array<U32> & Raster.AlphaBounds) -> Array<U32> & Raster.AlphaBounds:
  match n state:
    case 0n _: state
    case 1n+k Tuple{pixels, bounds}:
      Rgba.border.scan(k, (i + 1 : U32), width, threshold, Rgba.border.pixel(i, width, threshold, bounds, Array.get(U32, pixels, i)))

def Rgba.border.finish(+width: U32, height: U32, result: Array<U32> & Raster.AlphaBounds) -> Rgba & Rectangle:
  match result:
    case Tuple{pixels, AlphaBounds{+left, +top, right, bottom}}:
      (Rgba{width, height, pixels}, Bool.pick(Rectangle, U32.is_eq(left, width), Rectangle{0.0, 0.0, 0.0, 0.0},
        Rectangle{U32.to_f32(left), U32.to_f32(top), U32.to_f32((right + 1 - left : U32)), U32.to_f32((bottom + 1 - top : U32))}))

def Rgba.alpha_border(surface: Rgba, threshold: F32) -> Rgba & Rectangle:
  Rgba{+width, +height, pixels} = surface
  Rgba.border.finish(width, height, Rgba.border.scan(U32.to_nat((width * height : U32)), 0, width,
    F32.to_u32((threshold * 255.0 : F32)), (pixels, AlphaBounds{width, height, 0, 0})))

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

def Rgba.resize.finish(w: U32, h: U32, buffers: Array<U32> & Array<U32>) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  (old, pixels) = buffers
  Done{Rgba{w, h, pixels}}

def Rgba.nearest.mapping(safe: Bool, sw: U32, sh: U32, pixels: Array<U32>, +w: U32, +h: U32, xr: U32, yr: U32) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  match safe:
    case False{}:
      Fail{(Rgba{sw, sh, pixels}, UnsafeNearestMapping{})}
    case True{}:
      Rgba.resize.finish(w, h, Rgba.sample((w * h : U32), Nearest{sw, w, xr, yr}, pixels))

def Rgba.nearest.checked(valid: Bool, +sw: U32, +sh: U32, pixels: Array<U32>, +w: U32, +h: U32) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  match valid:
    case False{}:
      Fail{(Rgba{sw, sh, pixels}, InvalidSize{})}
    case True{}:
      +xr = (((sw << 16n) / w) + 1 : U32)
      +yr = (((sh << 16n) / h) + 1 : U32)
      last = (((((h - 1) * yr) >> 16n) * sw) + (((w - 1) * xr) >> 16n) : U32)
      Rgba.nearest.mapping((last < sw * sh : U32), sw, sh, pixels, w, h, xr, yr)

# Preserve raylib's +1 fixed-point ratios. Refuse mappings beyond logical storage.
def Rgba.resize_nn(surface: Rgba, +w: U32, +h: U32) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  Rgba{sw, sh, pixels} = surface
  Rgba.nearest.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), sw, sh, pixels, w, h)

def Rgba.resize.checked(valid: Bool, surface: Rgba, +w: U32, +h: U32) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Rgba{sw, sh, pixels} = surface
      Done{Rgba{w, h, Resample.resize(sw, sh, w, h, pixels)}}

def Rgba.resize(surface: Rgba, +w: U32, +h: U32) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  Rgba.resize.checked(((w > 0) && (h > 0) && (w <= 4096) && (h <= 4096) : U32), surface, w, h)

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

def Rectangle.bounded(rect: Rectangle) -> Bool:
  Rectangle{x, y, w, h} = rect
  ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) && (F32.abs(w) <= 32767.0) && (F32.abs(h) <= 32767.0) : F32)

# Consumes the image and excludes power-of-two storage padding.
def Rgba.colors(surface: Rgba) -> List<U32>:
  Rgba{w, h, pixels} = surface
  Image.list.take(~U32, Array.to_list(~U32, pixels), U32.to_nat((w * h : U32)))

type Image.Palette is Type:
  Palette{count: U32, colors: +List<U32>}

def Image.Palette.entries(palette: Image.Palette) -> U32 & +List<U32>:
  Palette{count, colors} = palette
  (count, colors)

def Image.Palette.unload(palette: Image.Palette) -> Unit:
  Unit{}

def Rgba.palette.contains(values: +List<U32>, +color: U32, found: Bool) -> Bool:
  match values found:
    case _ True{}: True{}
    case Nil{} False{}: False{}
    case Con{head, rest} False{}: Rgba.palette.contains(rest, color, U32.is_eq(head, color))

def Rgba.palette.collect(+remaining: U32, +values: +List<U32>, read: Array<U32> & U32) -> Array<U32> & (U32 & +List<U32>):
  (pixels, +color) = read
  +fresh = U32.is_ne(Color.alpha(color), 0) && Bool.not(Rgba.palette.contains(values, color, False{}))
  (pixels, (Bool.pick(U32, fresh, (remaining - 1 : U32), remaining), Bool.pick(+List<U32>, fresh, Con{color, values}, values)))

def Rgba.palette.loop(n: Nat, +index: U32, cursor: Array<U32> & (U32 & +List<U32>)) -> Array<U32> & (U32 & +List<U32>):
  match n cursor:
    case _ Tuple{pixels, Tuple{0, values}}: (pixels, (0, values))
    case 0n _: cursor
    case 1n+rest Tuple{pixels, Tuple{remaining, values}}:
      Rgba.palette.loop(rest, (index + 1 : U32), Rgba.palette.collect(remaining, values, Array.get(U32, pixels, index)))

def Rgba.palette.pad(n: Nat, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, values)
    case 1n+rest: Rgba.palette.pad(rest, Con{0, values})

def Rgba.palette.finished(width: U32, height: U32, maximum: U32, result: Array<U32> & (U32 & +List<U32>)) -> Rgba & Maybe<Image.Palette>:
  (pixels, (+remaining, values)) = result
  (Rgba{width, height, pixels}, Some{Palette{(maximum - remaining : U32), Rgba.palette.pad(U32.to_nat(remaining), values)}})

def Rgba.palette.checked(valid: Bool, surface: Rgba, +maximum: U32) -> Rgba & Maybe<Image.Palette>:
  match valid surface:
    case False{} _: (surface, None{})
    case True{} Rgba{+w, +h, pixels}:
      Rgba.palette.finished(w, h, maximum, Rgba.palette.loop(U32.to_nat((w * h : U32)), 0, (pixels, (maximum, Nil{}))))

def Rgba.load_palette(surface: Rgba, +maximum: U32) -> Rgba & Maybe<Image.Palette>:
  Rgba.palette.checked(((maximum > 0) && (maximum <= 4096) : U32), surface, maximum)

def Rgba.copy.result(+w: U32, +h: U32, pair: Array<U32> & Array<U32>) -> Rgba & Rgba:
  (a, b) = pair
  (Rgba{w, h, a}, Rgba{w, h, b})

def Rgba.copy(surface: Rgba) -> Rgba & Rgba:
  Rgba{w, h, pixels} = surface
  Rgba.copy.result(w, h, Array.clone(U32, pixels))

def Image.channel.index(format: U32, +selected: U32) -> U32:
  match format:
    case 1: 0
    case 2: Bool.pick(U32, U32.is_eq(selected, 0), 0, 3)
    case 3: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case 4: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case 8: 0
    case 9: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case 11: 0
    case 12: Bool.pick(U32, (selected > 2 : U32), 0, selected)
    case _: Bool.pick(U32, (selected > 3 : U32), 3, selected)

def Image.channel.value(index: U32, normal: Formats.Normal) -> U32:
  match index normal:
    case 0 Formats.Normal{r, _, _, _}: F32.to_u32((r * 255.0 : F32))
    case 1 Formats.Normal{_, g, _, _}: F32.to_u32((g * 255.0 : F32))
    case 2 Formats.Normal{_, _, b, _}: F32.to_u32((b * 255.0 : F32))
    case _ Formats.Normal{_, _, _, a}: F32.to_u32((a * 255.0 : F32))

# Base.Image contains RGB colors. Alpha is discarded, not composited.
def Rgba.tree.leaf(got: Array<U32> & U32) -> Array<U32> & Image:
  (pixels, color) = got
  (pixels, Pix{(color >> 8n : U32)})

def Rgba.tree.pixel(inside: Bool, +w: U32, x: U32, y: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match inside:
    case False{}:
      (pixels, Pix{0})
    case True{}:
      Rgba.tree.leaf(Array.get(U32, pixels, (y * w + x : U32)))

def Rgba.tree.bind(got: Array<U32> & Image, next: Array<U32> -> Image -> (Array<U32> & Image)) -> Array<U32> & Image:
  (pixels, image) = got
  next(pixels, image)

def Rgba.tree(+depth: Nat, +size: U32, +x: U32, +y: U32, +w: U32, +h: U32, pixels: Array<U32>) -> Array<U32> & Image:
  match depth:
    case 0n:
      Rgba.tree.pixel(((x < w) && (y < h) : U32), w, x, y, pixels)
    case 1n+k:
      +half = (size / 2 : U32)
      Rgba.tree.bind(Rgba.tree(k, half, x, y, w, h, pixels), p0 => tl =>
        Rgba.tree.bind(Rgba.tree(k, half, (x + half : U32), y, w, h, p0), p1 => tr =>
          Rgba.tree.bind(Rgba.tree(k, half, x, (y + half : U32), w, h, p1), p2 => bl =>
            Rgba.tree.bind(Rgba.tree(k, half, (x + half : U32), (y + half : U32), w, h, p2), p3 => br =>
              (p3, Qua{tl, tr, bl, br})))))

def Rgba.to_image(surface: Rgba) -> Image:
  Rgba{+w, +h, pixels} = surface
  +depth = Storage.depth(U32.max(w, h))
  Pair.snd(Array<U32>, Image, Rgba.tree(depth, U32.shln(1, depth), 0, 0, w, h, pixels))

# Portable, inspectable P3 PPM output for headless programs. Alpha is discarded.
# Walks colors in reverse, prepending each short line, so the text is built
# with constant stack depth on every backend (the JS lane overflowed per pixel).
def Rgba.ppm.colors(colors: List<U32>, acc: String) -> String:
  match colors:
    case Nil{}:
      acc
    case Con{+color, rest}:
      Rgba.ppm.colors(rest, U32.show(Color.red(color)) ++ " " ++ U32.show(Color.green(color)) ++ " "
        ++ U32.show(Color.blue(color)) ++ "\n" ++ acc)

def Rgba.to_ppm(surface: Rgba) -> String:
  Rgba{+w, +h, pixels} = surface
  "P3\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n"
    ++ Rgba.ppm.colors(List.reverse(&1, U32, Rgba.colors(Rgba{w, h, pixels})), "")

# -----------------------------------------------------------------------------
# Shared file boundary: suffix rules, bounded reads and closed writes

# Shared file writers: write once, close the handle, return the write status.
def Image.file.write.closed(result: File & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, Unit>):
  (file, status) = result
  do IO<Result<&1, &1, U32 & String, Unit>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, U32 & String, Unit>, status)

def Image.file.write_text.opened(text: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write(file, text), Image.file.write.closed)

def Image.file.write.opened(bytes: +List<U32>, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Result<&1, &1, U32 & String, Unit>,
        File.write_bytes(file, bytes), Image.file.write.closed)

type Image.FileKind is Data:
  QoiFile{}
  DdsFile{}
  RasterFile{}
  UnsupportedImageFile{}

def Image.memory.selected(qoi: Bool, dds: Bool, raster: Bool) -> Image.FileKind:
  match qoi dds raster:
    case True{} _ _: QoiFile{}
    case False{} True{} _: DdsFile{}
    case False{} False{} True{}: RasterFile{}
    case False{} False{} False{}: UnsupportedImageFile{}

# raylib 6.0's default file formats: stb_image signatures for the raster
# suffixes, QOI and DDS (rltexgpu.h).
def Image.memory.kind(+file_type: String) -> Image.FileKind:
  Image.memory.selected(String.eq(file_type, ".qoi") || String.eq(file_type, ".QOI"),
    String.eq(file_type, ".dds") || String.eq(file_type, ".DDS"),
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

# DDS admits its 128-byte header plus the largest uncompressed payload.
def Image.file.limit(kind: Image.FileKind) -> U32:
  match kind:
    case QoiFile{}: 83886102
    case DdsFile{}: 67109000
    case _: 1048576

def Image.file.psd(bytes: +List<U32>) -> Bool:
  match bytes:
    case Con{56, Con{66, Con{80, Con{83, _}}}}: True{}
    case _: False{}

def Image.file.decoded(-A: Type, result: Result<&1, &1, Surface.Error, A>) -> Result<&1, &1, Surface.IOError, A>:
  match result:
    case Fail{error}: Fail{DataError{error}}
    case Done{image}: Done{image}

def Image.file.complete(n: Nat, bytes: +List<U32>) -> Bool:
  match n bytes:
    case 0n Nil{}: True{}
    case 1n+rest Con{_, tail}: Image.file.complete(rest, tail)
    case _ _: False{}

def Image.file.loaded(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Surface.IOError, +List<U32>>:
  match valid:
    case False{}: Fail{DataError{TruncatedImageData{}}}
    case True{}: Done{bytes}

def Image.file.payload(size: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> Result<&1, &1, Surface.IOError, +List<U32>>:
  match result:
    case Fail{Tuple{code, message}}: Fail{FileError{code, message}}
    case Done{+bytes}: Image.file.loaded(Image.file.complete(U32.to_nat(size), bytes), bytes)

def Image.file.read(size: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  (file, status) = result
  do IO<Result<&1, &1, Surface.IOError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Image.file.payload(size, status))

def Image.file.bounded(valid: Bool, file: File, +size: U32) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match valid:
    case False{}:
      do IO<Result<&1, &1, Surface.IOError, +List<U32>>>:
        Unit <- File.close(file)
        IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Fail{DataError{UnsupportedImageSize{}}})
    case True{}:
      IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Result<&1, &1, Surface.IOError, +List<U32>>,
        File.read_bytes(file, size), Image.file.read(size))

def Image.file.sized(limit: U32, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match result:
    case Tuple{file, Fail{error}}: Image.file.read(0, (file, Fail{error}))
    case Tuple{file, Done{+size}}: Image.file.bounded((size <= limit : U32), file, size)

def Image.file.opened(limit: U32, opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match opened:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Fail{FileError{code, message}})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&1, &1, Surface.IOError, +List<U32>>, File.size(file), Image.file.sized(limit))

def Image.file.bytes(path: String, limit: U32) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, Surface.IOError, +List<U32>>, File.open(path, "r"), Image.file.opened(limit))

def Image.raw.complete(valid: Bool, bytes: +List<U32>) -> Result<&1, &1, Surface.IOError, +List<U32>>:
  match valid:
    case False{}: Fail{DataError{TruncatedImageData{}}}
    case True{}: Done{bytes}

def Image.raw.payload(needed: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> Result<&1, &1, Surface.IOError, +List<U32>>:
  match result:
    case Fail{Tuple{code, message}}: Fail{FileError{code, message}}
    case Done{+bytes}: Image.raw.complete(Image.file.complete(U32.to_nat(needed), bytes), bytes)

def Image.raw.read(needed: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  (file, status) = result
  do IO<Result<&1, &1, Surface.IOError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Image.raw.payload(needed, status))

def Image.raw.failed(file: File, error: Surface.IOError) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  do IO<Result<&1, &1, Surface.IOError, +List<U32>>>:
    Unit <- File.close(file)
    IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Fail{error})

def Image.raw.bounded(too_large: Bool, enough: Bool, +header: U32, +needed: U32, size: U32, file: File) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match too_large enough:
    case True{} _: Image.raw.failed(file, DataError{UnsupportedImageSize{}})
    case False{} False{}: Image.raw.failed(file, DataError{TruncatedImageData{}})
    case False{} True{}:
      offset = Bool.pick(U32, ((header > 0) && (header + needed <= size) : U32), header, 0)
      IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Result<&1, &1, Surface.IOError, +List<U32>>,
        File.read_at(file, offset, needed), Image.raw.read(needed))

def Image.raw.sized(header: U32, +needed: U32, result: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match result:
    case Tuple{file, Fail{Tuple{code, message}}}: Image.raw.failed(file, FileError{code, message})
    case Tuple{file, Done{+size}}:
      Image.raw.bounded((size > 2147483647 : U32), (size >= needed : U32), header, needed, size, file)

def Image.raw.opened(header: U32, needed: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Fail{FileError{code, message}})
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, Result<&1, &1, Surface.IOError, +List<U32>>,
        File.size(file), Image.raw.sized(header, needed))

def Image.raw.request(valid: Bool, path: String, header: U32, needed: U32) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Surface.IOError, +List<U32>>, Fail{DataError{InvalidRequest{}}})
    case True{}:
      IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, Surface.IOError, +List<U32>>,
        File.open(path, "r"), Image.raw.opened(header, needed))

def Image.raw.bytes(path: String, +header: U32, +needed: U32) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  Image.raw.request((header <= 2147483647 - needed : U32), path, header, needed)

# -----------------------------------------------------------------------------
# Surface: the public image API, dispatching on pixel format

# Surface: the one owned image. The RGBA8 kernels above run on Rgba; this layer
# dispatches on the pixel format the way raylib 6.0 rtextures.c does: byte-level
# operations move stored pixels intact, color operations run LoadImageColors, the
# RGBA8 step and ImageFormat back, and drawing encodes colors like ImageDrawPixel.
def Surface.rgba.wrap(image: Rgba) -> Surface:
  Rgba{width, height, pixels} = image
  Surface{width, height, 7, Words{pixels}}

def Surface.rgba.maybe(result: Maybe<Rgba>) -> Maybe<Surface>:
  match result:
    case None{}: None{}
    case Some{image}: Some{Surface.rgba.wrap(image)}

def Surface.rgba.stream(result: Random.State & Maybe<Rgba>) -> Random.State & Maybe<Surface>:
  (state, image) = result
  (state, Surface.rgba.maybe(image))

def Surface.rgba.result(result: Result<&1, &1, Rgba & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Fail{Tuple{image, error}}: Fail{(Surface.rgba.wrap(image), error)}
    case Done{image}: Done{Surface.rgba.wrap(image)}

# Generators produce R8G8B8A8 images; see each kernel for its input profile.
def Surface.create(w: U32, h: U32, color: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create(w, h, color))

def Surface.create_checked(width: U32, height: U32, tx: U32, ty: U32, first: U32, second: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_checked(width, height, tx, ty, first, second))

def Surface.create_text_bytes(width: U32, height: U32, bytes: +List<U32>) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_text_bytes(width, height, bytes))

def Surface.create_white_noise(state: Random.State, width: U32, height: U32, factor: F32) -> Random.State & Maybe<Surface>:
  Surface.rgba.stream(Rgba.create_white_noise(state, width, height, factor))

def Surface.create_cellular(state: Random.State, width: U32, height: U32, tile: U32) -> Random.State & Maybe<Surface>:
  Surface.rgba.stream(Rgba.create_cellular(state, width, height, tile))

def Surface.create_perlin_for(reference: M.Contraction, width: U32, height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_perlin_for(reference, width, height, offset_x, offset_y, scale))

def Surface.create_perlin(width: U32, height: U32, offset_x: F32, offset_y: F32, scale: F32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_perlin(width, height, offset_x, offset_y, scale))

def Surface.create_gradient_square(width: U32, height: U32, density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_gradient_square(width, height, density, inner, outer))

def Surface.create_gradient_radial(width: U32, height: U32, density: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_gradient_radial(width, height, density, inner, outer))

def Surface.create_gradient_linear_for(reference: M.Libm, width: U32, height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_gradient_linear_for(reference, width, height, direction, inner, outer))

def Surface.create_gradient_linear(width: U32, height: U32, direction: F32, inner: U32, outer: U32) -> Maybe<Surface>:
  Surface.rgba.maybe(Rgba.create_gradient_linear(width, height, direction, inner, outer))

def Surface.dimensions(surface: Surface) -> U32 & U32:
  Surface{width, height, _, _} = surface
  (width, height)

def Surface.pixel_format(surface: Surface) -> Surface & U32:
  Surface{width, height, +format, pixels} = surface
  (Surface{width, height, format, pixels}, format)

# Storage-level helpers shared by every format. Wide formats store Quads.
def Surface.wide(+format: U32) -> Bool:
  U32.is_eq(format, 9) || U32.is_eq(format, 10) || U32.is_eq(format, 12) || U32.is_eq(format, 13)

def Surface.quad.zero() -> Surface.Quad:
  Quad{0, 0, 0, 0}

def Surface.pixels.words(result: Array<U32> & Array<U32>) -> Surface.Pixels & Surface.Pixels:
  (source, output) = result
  (Words{source}, Words{output})

def Surface.pixels.quads(result: Array<Surface.Quad> & Array<Surface.Quad>) -> Surface.Pixels & Surface.Pixels:
  (source, output) = result
  (Quads{source}, Quads{output})

def Surface.pixels.sample(pixels: Surface.Pixels, +count: U32, +mapping: Raster.Mapping) -> Surface.Pixels & Surface.Pixels:
  match pixels:
    case Words{values}: Surface.pixels.words(Raster.sample(~U32, count, mapping, 0, values))
    case Quads{values}: Surface.pixels.quads(Raster.sample(~Surface.Quad, count, mapping, Surface.quad.zero(), values))

def Surface.pixels.clone(pixels: Surface.Pixels) -> Surface.Pixels & Surface.Pixels:
  match pixels:
    case Words{values}: Surface.pixels.words(Array.clone(U32, values))
    case Quads{values}: Surface.pixels.quads(Array.clone(Surface.Quad, values))

# Format 7 words are canonical Colors; Formats routines read native byte order.
def Surface.words.native(format: U32, count: Nat, values: Array<U32>) -> Array<U32>:
  match format:
    case 7: Formats.swap_pixels(count, 0, values)
    case _: values

def Surface.words.normal(+format: U32, +word: U32) -> Formats.Normal:
  Formats.decode(format, Bool.pick(U32, U32.is_eq(format, 7), Formats.swap(word), word))

def Surface.word.bytes(bytes: +List<U32>, +shift: Nat, value: U32) -> U32:
  match bytes:
    case Nil{}: value
    case Con{byte, rest}: Surface.word.bytes(rest, (shift + 8n : Nat), (value .|. (byte << shift) : U32))

# The stored word ImageDrawPixel writes for a Color in word formats 1..8 and 11.
def Surface.word.draw.selected(kind: U32, +format: U32, +color: U32) -> U32:
  match kind:
    case 7: color
    case 8: Formats.encode(Formats.decode(7, Formats.swap(color)), 8)
    case 11: Formats.encode(Formats.decode(7, Formats.swap(color)), 11)
    case _: Surface.word.bytes(Pixel.encode(format, color), 0n, 0)

def Surface.word.draw(+format: U32, color: U32) -> U32:
  Surface.word.draw.selected(format, format, color)

# SetPixelColor writes formats 1..7; float canvases stay zero.
def Surface.word.fill(kind: U32, +format: U32, color: U32) -> U32:
  match kind:
    case 8: 0
    case 11: 0
    case _: Surface.word.draw(format, color)

# GetPixelColor, ImageDraw's reader, on stored words: packed formats use
# Pixel.packed_color's integer expansion (LoadImageColors uses float factors)
# and R32/R16 fill r, g and b.
def Surface.word.read(kind: U32, +word: U32) -> U32:
  match kind:
    case 1: Color.rgba((word .&. 255 : U32), (word .&. 255 : U32), (word .&. 255 : U32), 255)
    case 2: Color.rgba((word .&. 255 : U32), (word .&. 255 : U32), (word .&. 255 : U32), (word >> 8n : U32))
    case 4: Color.rgba((word .&. 255 : U32), ((word >> 8n) .&. 255 : U32), ((word >> 16n) .&. 255 : U32), 255)
    case 7: word
    case 8:
      +value = F32.to_u32((Formats.r32.value(word) * 255.0 : F32))
      Color.rgba(value, value, value, 255)
    case 11:
      +value = F32.to_u32((Formats.half.value(word) * 255.0 : F32))
      Color.rgba(value, value, value, 255)
    case _: Pixel.packed_color(kind, word)

# SetPixelColor: ImageDrawPixel's encoding for formats 1..7; R32/R16 keep their word.
def Surface.word.write(kind: U32, +color: U32, +word: U32) -> U32:
  match kind:
    case 8: word
    case 11: word
    case _: Surface.word.draw(kind, color)

# LoadImageDataNormalized of a wide sample: F32 or HalfToFloat channels; formats
# without alpha read 1.
def Surface.quad.normal(kind: U32, quad: Surface.Quad) -> Formats.Normal:
  match kind quad:
    case 9 Quad{a, b, c, _}: Formats.Normal{Formats.r32.value(a), Formats.r32.value(b), Formats.r32.value(c), 1.0}
    case 10 Quad{a, b, c, d}: Formats.Normal{Formats.r32.value(a), Formats.r32.value(b), Formats.r32.value(c), Formats.r32.value(d)}
    case 12 Quad{a, b, c, _}: Formats.Normal{Formats.half.value(a), Formats.half.value(b), Formats.half.value(c), 1.0}
    case _ Quad{a, b, c, d}: Formats.Normal{Formats.half.value(a), Formats.half.value(b), Formats.half.value(c), Formats.half.value(d)}

# ImageFormat into a wide format: F32 channels or FloatToHalf.
def Surface.quad.from_normal(kind: U32, sample: Formats.Normal) -> Surface.Quad:
  match kind sample:
    case 9 Formats.Normal{r, g, b, _}: Quad{F32.bits(r), F32.bits(g), F32.bits(b), 0}
    case 10 Formats.Normal{r, g, b, a}: Quad{F32.bits(r), F32.bits(g), F32.bits(b), F32.bits(a)}
    case 12 Formats.Normal{r, g, b, _}: Quad{Formats.half.bits(r), Formats.half.bits(g), Formats.half.bits(b), 0}
    case _ Formats.Normal{r, g, b, a}: Quad{Formats.half.bits(r), Formats.half.bits(g), Formats.half.bits(b), Formats.half.bits(a)}

# The sample ImageDrawPixel and ImageFormat store for a Color (channel/255).
def Surface.quad.from_color(kind: U32, color: U32) -> Surface.Quad:
  Surface.quad.from_normal(kind, Formats.decode(7, Formats.swap(color)))

# LoadImageColors converts float samples with C casts that are defined on
# [0, 1] (and -0); bit checks keep the domain on GPUs that flush denormals.
def Surface.channel.valid(value: F32) -> Bool:
  +bits = F32.bits(value)
  (bits <= 1065353216 : U32) || U32.is_eq(bits, 2147483648)

def Surface.normal.valid(sample: Formats.Normal) -> Bool:
  Formats.Normal{r, g, b, a} = sample
  Surface.channel.valid(r) && Surface.channel.valid(g) && Surface.channel.valid(b) && Surface.channel.valid(a)

def Surface.normal.color(sample: Formats.Normal) -> U32:
  Formats.Normal{r, g, b, a} = sample
  Color.rgba(F32.to_u32((r * 255.0 : F32)), F32.to_u32((g * 255.0 : F32)), F32.to_u32((b * 255.0 : F32)), F32.to_u32((a * 255.0 : F32)))

def Surface.quad.valid(kind: U32, quad: Surface.Quad) -> Bool:
  Surface.normal.valid(Surface.quad.normal(kind, quad))

def Surface.quad.color(kind: U32, quad: Surface.Quad) -> U32:
  Surface.normal.color(Surface.quad.normal(kind, quad))

# F32 sample words other than NaN: no factory creates NaN and backends do not
# all keep NaN payloads in float arithmetic, so writers reject it.
def Surface.sample.word(word: U32) -> Bool:
  ((word .&. 2147483647) <= 2139095040 : U32)

def Surface.quad.ordered(kind: U32, quad: Surface.Quad) -> Bool:
  match kind quad:
    case 9 Quad{a, b, c, _}: Surface.sample.word(a) && Surface.sample.word(b) && Surface.sample.word(c)
    case 10 Quad{a, b, c, d}: Surface.sample.word(a) && Surface.sample.word(b) && Surface.sample.word(c) && Surface.sample.word(d)
    case _ _: True{}

# Every sample in the owner domain (ordered) or the byte-conversion domain.
def Surface.quads.checked.read(+kind: U32, ordered: Bool, result: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad> & Bool:
  (values, +quad) = result
  (values, Bool.pick(Bool, ordered, Surface.quad.ordered(kind, quad), Surface.quad.valid(kind, quad)))

def Surface.quads.checked(n: Nat, +index: U32, +kind: U32, +ordered: Bool, state: Array<Surface.Quad> & Bool) -> Array<Surface.Quad> & Bool:
  match n state:
    case _ Tuple{values, False{}}: (values, False{})
    case 0n _: state
    case 1n+rest Tuple{values, True{}}:
      Surface.quads.checked(rest, (index + 1 : U32), kind, ordered, Surface.quads.checked.read(kind, ordered, Array.get(Surface.Quad, values, index)))

def Surface.quads.colors.read(+kind: U32, index: U32, output: Array<U32>, result: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad> & Array<U32>:
  (values, quad) = result
  (values, Array.set(U32, output, index, Surface.quad.color(kind, quad)))

def Surface.quads.colors(n: Nat, +index: U32, +kind: U32, state: Array<Surface.Quad> & Array<U32>) -> Array<Surface.Quad> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{values, output}:
      Surface.quads.colors(rest, (index + 1 : U32), kind, Surface.quads.colors.read(kind, index, output, Array.get(Surface.Quad, values, index)))

def Surface.quads.from_words.read(+format: U32, +target: U32, index: U32, output: Array<Surface.Quad>, result: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (source, word) = result
  (source, Array.set(Surface.Quad, output, index, Surface.quad.from_normal(target, Formats.decode(format, word))))

def Surface.quads.from_words(n: Nat, +index: U32, +format: U32, +target: U32, state: Array<U32> & Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{source, output}:
      Surface.quads.from_words(rest, (index + 1 : U32), format, target,
        Surface.quads.from_words.read(format, target, index, output, Array.get(U32, source, index)))

def Surface.words.from_quads.read(+kind: U32, +target: U32, index: U32, output: Array<U32>, result: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad> & Array<U32>:
  (values, quad) = result
  (values, Array.set(U32, output, index, Formats.encode(Surface.quad.normal(kind, quad), target)))

def Surface.words.from_quads(n: Nat, +index: U32, +kind: U32, +target: U32, state: Array<Surface.Quad> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{values, output}:
      Surface.words.from_quads(rest, (index + 1 : U32), kind, target,
        Surface.words.from_quads.read(kind, target, index, output, Array.get(Surface.Quad, values, index)))

def Surface.quads.convert.read(+kind: U32, +target: U32, index: U32, result: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad>:
  (values, quad) = result
  Array.set(Surface.Quad, values, index, Surface.quad.from_normal(target, Surface.quad.normal(kind, quad)))

def Surface.quads.convert(n: Nat, +index: U32, +kind: U32, +target: U32, values: Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n:
    case 0n: values
    case 1n+rest:
      Surface.quads.convert(rest, (index + 1 : U32), kind, target, Surface.quads.convert.read(kind, target, index, Array.get(Surface.Quad, values, index)))

def Surface.rgba.converted(width: U32, height: U32, result: Array<Surface.Quad> & Array<U32>) -> Rgba:
  (_, pixels) = result
  Rgba{width, height, pixels}

def Surface.rgba.quads(+width: U32, +height: U32, +format: U32, state: Array<Surface.Quad> & Bool) -> Result<&1, &1, Surface & Surface.Error, Rgba>:
  match state:
    case Tuple{values, False{}}: Fail{(Surface{width, height, format, Quads{values}}, OutOfDomain{})}
    case Tuple{values, True{}}:
      +count = (width * height : U32)
      Done{Surface.rgba.converted(width, height, Surface.quads.colors(U32.to_nat(count), 0, format, (values, Array.new(U32, Storage.depth(count), 0))))}

# LoadImageColors: one canonical Color per pixel. A wide owner with samples
# outside [0, 1] is returned unchanged with OutOfDomain.
def Surface.rgba.load.selected(kind: U32, pixels: Surface.Pixels, +width: U32, +height: U32, +format: U32) -> Result<&1, &1, Surface & Surface.Error, Rgba>:
  match kind pixels:
    case 7 Words{values}: Done{Rgba{width, height, values}}
    case _ Words{values}: Done{Rgba{width, height, Formats.packed_colors(U32.to_nat((width * height : U32)), 0, format, values)}}
    case _ Quads{values}:
      Surface.rgba.quads(width, height, format, Surface.quads.checked(U32.to_nat((width * height : U32)), 0, format, False{}, (values, True{})))

def Surface.rgba.load(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Rgba>:
  Surface{width, height, +format, pixels} = surface
  Surface.rgba.load.selected(format, pixels, width, height, format)

# ImageFormat from R8G8B8A8, as raylib's color operations end.
def Surface.rgba.store.quad(+format: U32, index: U32, result: Array<U32> & U32, output: Array<Surface.Quad>) -> Array<U32> & Array<Surface.Quad>:
  (colors, color) = result
  (colors, Array.set(Surface.Quad, output, index, Surface.quad.from_color(format, color)))

def Surface.rgba.store.quads(n: Nat, +index: U32, +format: U32, state: Array<U32> & Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{colors, output}:
      Surface.rgba.store.quads(rest, (index + 1 : U32), format, Surface.rgba.store.quad(format, index, Array.get(U32, colors, index), output))

def Surface.rgba.store.converted(wide: Bool, +format: U32, +width: U32, +height: U32, pixels: Array<U32>) -> Surface:
  match wide:
    case True{}:
      +count = (width * height : U32)
      Surface{width, height, format, Quads{Surface.rgba.store.quads(U32.to_nat(count), 0, format, (pixels, Array.new(Surface.Quad, Storage.depth(count), Surface.quad.zero())))}}
    case False{}:
      Surface{width, height, format, Words{Formats.convert(U32.to_nat((width * height : U32)), 0, 7, format,
        Formats.swap_pixels(U32.to_nat((width * height : U32)), 0, pixels))}}

def Surface.rgba.store.selected(kind: U32, +format: U32, +width: U32, +height: U32, pixels: Array<U32>) -> Surface:
  match kind:
    case 7: Surface{width, height, 7, Words{pixels}}
    case _: Surface.rgba.store.converted(Surface.wide(format), format, width, height, pixels)

def Surface.rgba.store(image: Rgba, +format: U32) -> Surface:
  Rgba{width, height, pixels} = image
  Surface.rgba.store.selected(format, format, width, height, pixels)

# Owners that reach an RGBA8 kernel unchanged; other formats are not yet
# supported by that operation.
def Surface.rgba.only.selected(kind: U32, pixels: Surface.Pixels, +width: U32, +height: U32, format: U32) -> Result<&1, &1, Surface & Surface.Error, Rgba>:
  match kind pixels:
    case 7 Words{values}: Done{Rgba{width, height, values}}
    case _ _: Fail{(Surface{width, height, format, pixels}, UnsupportedFormat{})}

def Surface.rgba.only(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Rgba>:
  Surface{width, height, +format, pixels} = surface
  Surface.rgba.only.selected(format, pixels, width, height, format)

# ImageFormat: formats 1..13; target 0 or the current format keeps the owner.
def Surface.format.words(wide: Bool, +width: U32, +height: U32, +format: U32, +target: U32, values: Array<U32>) -> Surface:
  match wide:
    case True{}:
      +count = (width * height : U32)
      Surface{width, height, target, Quads{Surface.quads.from_words(U32.to_nat(count), 0, format, target,
        (Surface.words.native(format, U32.to_nat(count), values), Array.new(Surface.Quad, Storage.depth(count), Surface.quad.zero())))}}
    case False{}:
      +count = (width * height : U32)
      Surface{width, height, target, Words{Surface.words.native(target, U32.to_nat(count),
        Formats.convert(U32.to_nat(count), 0, format, target, Surface.words.native(format, U32.to_nat(count), values)))}}

# Wide samples convert from finite [0, 1], like the byte conversions they share.
def Surface.format.quads.converted(wide: Bool, +width: U32, +height: U32, +format: U32, +target: U32, values: Array<Surface.Quad>) -> Surface:
  match wide:
    case True{}: Surface{width, height, target, Quads{Surface.quads.convert(U32.to_nat((width * height : U32)), 0, format, target, values)}}
    case False{}:
      +count = (width * height : U32)
      Surface{width, height, target, Words{Surface.words.native(target, U32.to_nat(count),
        Surface.words.from_quads(U32.to_nat(count), 0, format, target, (values, Array.new(U32, Storage.depth(count), 0))))}}

def Surface.format.quads(+width: U32, +height: U32, +format: U32, +target: U32, state: Array<Surface.Quad> & Bool) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match state:
    case Tuple{values, False{}}: Fail{(Surface{width, height, format, Quads{values}}, OutOfDomain{})}
    case Tuple{values, True{}}: Done{Surface.format.quads.converted(Surface.wide(target), width, height, format, target, values)}

def Surface.format.checked(unchanged: Bool, supported: Bool, surface: Surface, +target: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match unchanged supported surface:
    case True{} _ _: Done{surface}
    case False{} False{} _: Fail{(surface, UnsupportedFormat{})}
    case False{} True{} Surface{+width, +height, +format, Words{values}}: Done{Surface.format.words(Surface.wide(target), width, height, format, target, values)}
    case False{} True{} Surface{+width, +height, +format, Quads{values}}:
      Surface.format.quads(width, height, format, target, Surface.quads.checked(U32.to_nat((width * height : U32)), 0, format, False{}, (values, True{})))

def Surface.format(surface: Surface, +target: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{width, height, +format, pixels} = surface
  Surface.format.checked(U32.is_eq(target, 0) || U32.is_eq(target, format), (target <= 13 : U32),
    Surface{width, height, format, pixels}, target)

# ImageColorGrayscale is ImageFormat(GRAYSCALE).
def Surface.color_grayscale(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.format(surface, 1)

# Byte-level operations: every stored pixel moves intact, whatever its format.
def Surface.pixels.resampled(+width: U32, +height: U32, format: U32, result: Surface.Pixels & Surface.Pixels) -> Surface:
  (_, pixels) = result
  Surface{width, height, format, pixels}

def Surface.flip(surface: Surface, horizontal: Bool) -> Surface:
  Surface{+width, +height, format, pixels} = surface
  Surface.pixels.resampled(width, height, format, Surface.pixels.sample(pixels, (width * height : U32), Mirrored{width, height, horizontal}))

def Surface.flip_horizontal(surface: Surface) -> Surface:
  Surface.flip(surface, True{})

def Surface.flip_vertical(surface: Surface) -> Surface:
  Surface.flip(surface, False{})

def Surface.rotate.quarter(surface: Surface, clockwise: Bool) -> Surface:
  Surface{+width, +height, format, pixels} = surface
  Surface.pixels.resampled(height, width, format, Surface.pixels.sample(pixels, (width * height : U32), QuarterTurn{width, height, clockwise}))

def Surface.rotate_cw(surface: Surface) -> Surface:
  Surface.rotate.quarter(surface, True{})

def Surface.rotate_ccw(surface: Surface) -> Surface:
  Surface.rotate.quarter(surface, False{})

def Surface.copy.result(+width: U32, +height: U32, +format: U32, pair: Surface.Pixels & Surface.Pixels) -> Surface & Surface:
  (first, second) = pair
  (Surface{width, height, format, first}, Surface{width, height, format, second})

def Surface.copy(surface: Surface) -> Surface & Surface:
  Surface{width, height, format, pixels} = surface
  Surface.copy.result(width, height, format, Surface.pixels.clone(pixels))

def Surface.extract.finish(+sw: U32, +sh: U32, +format: U32, +width: U32, +height: U32, result: Surface.Pixels & Surface.Pixels) -> Surface & Maybe<Surface>:
  (source, region) = result
  (Surface{sw, sh, format, source}, Some{Surface{width, height, format, region}})

def Surface.extract.checked(valid: Bool, +sw: U32, sh: U32, format: U32, pixels: Surface.Pixels, x: F32, y: F32, width: F32, height: F32) -> Surface & Maybe<Surface>:
  match valid:
    case False{}: (Surface{sw, sh, format, pixels}, None{})
    case True{}:
      +w = F32.to_u32(width)
      +h = F32.to_u32(height)
      Surface.extract.finish(sw, sh, format, w, h, Surface.pixels.sample(pixels, (w * h : U32), Region{sw, w, F32.to_u32(x), F32.to_u32(y)}))

# ImageFromImage profile: positive integral in-bounds rectangle; source retained.
def Surface.extract(surface: Surface, +rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{+w, +h, format, pixels} = surface
  Rectangle{x, y, rw, rh} = rect
  Surface.extract.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h), w, h, format, pixels, x, y, rw, rh)

def Surface.crop.result(result: Surface & Maybe<Surface>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Tuple{original, None{}}: Fail{(original, InvalidRectangle{})}
    case Tuple{_, Some{region}}: Done{region}

def Surface.crop.route(integral: Bool, outside: Bool, original: Surface, rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match integral outside:
    case False{} _: Fail{(original, InvalidRectangle{})}
    case True{} True{}: Done{original}
    case True{} False{}: Surface.crop.result(Surface.extract(original, rect))

def Surface.crop(surface: Surface, +rect: Rectangle) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+w, +h, format, pixels} = surface
  Rectangle{x, y, _, _} = rect
  Surface.crop.route(Rectangle.integral(rect), ((x > U32.to_f32(w)) || (y > U32.to_f32(h)) : F32),
    Surface{w, h, format, pixels}, Rectangle.crop.bounds(rect, w, h))

def Surface.canvas.storage(pixels: Surface.Pixels, +format: U32, fill: U32, depth: Nat, +count: U32, +cols: U32, +sw: U32, +dw: U32, +source_at: U32, +output_at: U32) -> Surface.Pixels & Surface.Pixels:
  match pixels:
    case Words{values}:
      Surface.pixels.words(Raster.canvas.copy(~U32, U32.to_nat(count), 0, cols, sw, dw, source_at, output_at,
        (values, Array.new(U32, depth, Surface.word.fill(format, format, fill)))))
    case Quads{values}:
      Surface.pixels.quads(Raster.canvas.copy(~Surface.Quad, U32.to_nat(count), 0, cols, sw, dw, source_at, output_at,
        (values, Array.new(Surface.Quad, depth, Surface.quad.zero()))))

def Surface.canvas.overlap(valid: Bool, +sw: U32, sh: U32, +format: U32, pixels: Surface.Pixels, +width: U32, +height: U32, sx: U32, sy: U32, dx: U32, dy: U32, +cols: U32, rows: U32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(Surface{sw, sh, format, pixels}, InvalidRectangle{})}
    case True{}:
      Done{Surface.pixels.resampled(width, height, format, Surface.canvas.storage(pixels, format, fill, Storage.depth((width * height : U32)),
        (cols * rows : U32), cols, sw, width, (sy * sw + sx : U32), (dy * width + dx : U32)))}

def Surface.canvas.mapped(sw: U32, sh: U32, format: U32, pixels: Surface.Pixels, width: U32, height: U32, fill: U32, mapping: Raster.Canvas) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Canvas{sx, sy, dx, dy, +cols, +rows} = mapping
  Surface.canvas.overlap(((cols >= 1) && (rows >= 1) : U32), sw, sh, format, pixels, width, height, sx, sy, dx, dy, cols, rows, fill)

def Surface.canvas.route(same: Bool, +sw: U32, +sh: U32, format: U32, pixels: Surface.Pixels, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match same:
    case True{}: Done{Surface{sw, sh, format, pixels}}
    case False{}:
      Surface.canvas.mapped(sw, sh, format, pixels, width, height, fill, Raster.canvas.mapping(sw, sh, width, height, x, y))

def Surface.canvas.checked(size_ok: Bool, offsets_ok: Bool, surface: Surface, +width: U32, +height: U32, x: F32, y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match size_ok offsets_ok:
    case False{} _: Fail{(surface, InvalidSize{})}
    case True{} False{}: Fail{(surface, InvalidRectangle{})}
    case True{} True{}:
      Surface{+sw, +sh, format, pixels} = surface
      Surface.canvas.route(U32.is_eq(sw, width) && U32.is_eq(sh, height), sw, sh, format, pixels, width, height, x, y, fill)

# ImageResizeCanvas: integral offsets; the fill color is stored with SetPixelColor.
def Surface.resize_canvas(surface: Surface, +width: U32, +height: U32, +x: F32, +y: F32, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.canvas.checked(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    ((F32.abs(x) <= 32767.0) && (F32.abs(y) <= 32767.0) : F32)
      && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), surface, width, height, x, y, fill)

def Surface.to_pot(surface: Surface, fill: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, format, pixels} = surface
  Surface.resize_canvas(Surface{width, height, format, pixels}, U32.shln(1, Storage.depth(width)), U32.shln(1, Storage.depth(height)), 0.0, 0.0, fill)

# Color operations: LoadImageColors, the RGBA8 kernel, then ImageFormat back.
# Owners in other formats keep a copy so a rejected request returns them intact.
def Surface.recolor.apply(op: Surface.Recolor, image: Rgba) -> Result<&1, &1, Rgba & Surface.Error, Rgba>:
  match op:
    case Recolored{transform}: Done{Rgba.color.transform(image, transform)}
    case Replaced{original, replacement}: Done{Rgba.color.transform(image, ImageReplace{original, replacement})}
    case BlurredPremultiplied{size}: Done{Rgba.blur_gaussian.premultiplied(size, image)}
    case Convolved{kernel}: Rgba.kernel_convolution(image, kernel)
    case Resized{width, height}: Rgba.resize(image, width, height)
    case ResizedNearest{width, height}: Rgba.resize_nn(image, width, height)

def Surface.recolor.finish(keep: Surface, +format: U32, result: Result<&1, &1, Rgba & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Fail{Tuple{_, error}}: Fail{(keep, error)}
    case Done{image}: Done{Surface.rgba.store(image, format)}

# ImageColorReplace returns to the original format only when it has no alpha
# channel (GRAYSCALE, R5G6B5, R8G8B8, R32G32B32, R16G16B16); others stay R8G8B8A8.
def Surface.recolor.output(op: Surface.Recolor, +format: U32) -> Surface.Recolor & U32:
  match op:
    case Replaced{original, replacement}:
      (Replaced{original, replacement}, Bool.pick(U32, U32.is_eq(format, 1) || U32.is_eq(format, 3) || U32.is_eq(format, 4) || U32.is_eq(format, 9) || U32.is_eq(format, 12), format, 7))
    case _: (op, format)

def Surface.recolor.applied(keep: Surface, image: Rgba, selected: Surface.Recolor & U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  (op, target) = selected
  Surface.recolor.finish(keep, target, Surface.recolor.apply(op, image))

def Surface.recolor.converted(keep: Surface, op: Surface.Recolor, +format: U32, converted: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match converted:
    case Fail{Tuple{_, error}}: Fail{(keep, error)}
    case Done{image}: Surface.recolor.applied(keep, image, Surface.recolor.output(op, format))

def Surface.recolor.cloned(op: Surface.Recolor, +width: U32, +height: U32, +format: U32, pair: Surface.Pixels & Surface.Pixels) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  (keep, work) = pair
  Surface.recolor.converted(Surface{width, height, format, keep}, op, format, Surface.rgba.load(Surface{width, height, format, work}))

def Surface.recolor.selected(kind: U32, pixels: Surface.Pixels, op: Surface.Recolor, +width: U32, +height: U32, format: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match kind pixels:
    case 7 Words{values}: Surface.rgba.result(Surface.recolor.apply(op, Rgba{width, height, values}))
    case _ _: Surface.recolor.cloned(op, width, height, format, Surface.pixels.clone(pixels))

def Surface.recolor.run(surface: Surface, op: Surface.Recolor) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{width, height, +format, pixels} = surface
  Surface.recolor.selected(format, pixels, op, width, height, format)

def Surface.recolor.checked(valid: Bool, surface: Surface, op: Surface.Recolor) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidRequest{})}
    case True{}: Surface.recolor.run(surface, op)

def Surface.amount.finite(amount: F32) -> Bool:
  ((F32.bits(amount) .&. 2147483647) < 2139095040 : U32)

def Surface.color_tint(surface: Surface, color: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, Recolored{ImageTint{color}})

def Surface.color_invert(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, Recolored{ImageInvert{}})

# ImageColorContrast takes a float; non-finite amounts are rejected.
def Surface.color_contrast(surface: Surface, +amount: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.checked(Surface.amount.finite(amount), surface, Recolored{Color.Transform.contrast(amount)})

# ImageColorBrightness takes int: amounts must convert to int (truncation).
def Surface.color_brightness(surface: Surface, +amount: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.checked(Surface.amount.finite(amount) && (F32.abs(amount) < 2147483648.0 : F32), surface,
    Recolored{Color.Transform.brightness(amount)})

def Surface.color_replace(surface: Surface, original: U32, replacement: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, Replaced{original, replacement})

def Surface.alpha_premultiply(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, Recolored{AlphaPremultiply{}})

def Surface.blur.premultiplied(size: U32, result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{surface}: Surface.recolor.run(surface, BlurredPremultiplied{size})

def Surface.blur.checked(valid: Bool, surface: Surface, size: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}: Surface.blur.premultiplied(size, Surface.recolor.run(surface, Recolored{AlphaPremultiply{}}))

# ImageBlurGaussian first runs ImageAlphaPremultiply, which returns to the
# original format, then blurs that image's colors and converts back again.
def Surface.blur_gaussian(surface: Surface, +size: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+width, +height, format, pixels} = surface
  Surface.blur.checked(((size <= width) && (size <= height) : U32), Surface{width, height, format, pixels}, size)

def Surface.kernel_convolution(surface: Surface, kernel: +List<F32>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, Convolved{kernel})

# Preserve raylib's +1 fixed-point ratios. Refuse mappings beyond logical storage.
def Surface.resize_nn(surface: Surface, width: U32, height: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.recolor.run(surface, ResizedNearest{width, height})

def Surface.resize.words(valid: Bool, +layout: U32, +sw: U32, +sh: U32, +format: U32, pixels: Surface.Pixels, +width: U32, +height: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid pixels:
    case True{} Words{values}: Done{Surface{width, height, format, Words{Resample.resize_layout(layout, sw, sh, width, height, values)}}}
    case True{} Quads{values}: Fail{(Surface{sw, sh, format, Quads{values}}, UnsupportedFormat{})}
    case False{} other: Fail{(Surface{sw, sh, format, other}, InvalidSize{})}

def Surface.resize.routed(direct: Bool, surface: Surface, +width: U32, +height: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match direct:
    case True{}:
      Surface{sw, sh, +format, pixels} = surface
      Surface.resize.words(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096) : U32),
        Bool.pick(U32, U32.is_eq(format, 4), 3, format), sw, sh, format, pixels, width, height)
    case False{}: Surface.recolor.run(surface, Resized{width, height})

# ImageResize filters GRAYSCALE, GRAY_ALPHA and R8G8B8 words directly with the
# 1..3-channel stbir layouts; other formats take the RGBA8 path and convert back.
def Surface.resize(surface: Surface, width: U32, height: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{w, h, +format, pixels} = surface
  Surface.resize.routed(U32.is_eq(format, 1) || U32.is_eq(format, 2) || U32.is_eq(format, 4),
    Surface{w, h, format, pixels}, width, height)

def Surface.dither.rgba(+r: U32, +g: U32, +b: U32, +a: U32, converted: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match converted:
    case Fail{failure}: Fail{failure}
    case Done{Rgba{+width, +height, pixels}}:
      +count = (width * height : U32)
      Done{Surface{width, height, Dither.format(r, g, b, a), Words{Dither.loop(U32.to_nat(count), 0, width, height,
        Dither.Bits{U32.to_nat(r), U32.to_nat(g), U32.to_nat(b), U32.to_nat(a)},
        (pixels, Array.new(U32, Storage.depth(count), 0)))}}}

def Surface.dither.checked(valid: Bool, surface: Surface, r: U32, g: U32, b: U32, a: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidDitherBits{})}
    case True{}: Surface.dither.rgba(r, g, b, a, Surface.rgba.load(surface))

# ImageDither: LoadImageColors, then Floyd-Steinberg into the 16-bit format the
# bit counts name (R5G6B5, R5G5B5A1 or R4G4B4A4); other counts are rejected.
def Surface.dither(surface: Surface, +r: U32, +g: U32, +b: U32, +a: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.dither.checked((Dither.format(r, g, b, a) > 0 : U32), surface, r, g, b, a)

# Drawing: covered pixels receive the color encoded as ImageDrawPixel stores it.
# R32G32B32 owners mark coverage first, then write the vector.
def Surface.draw.apply(draw: Surface.Draw, +word: U32, image: Rgba) -> Rgba:
  match draw:
    case DrawPixel{x, y}: Rgba.draw_pixel(image, x, y, word)
    case DrawPixelV{position}: Rgba.draw_pixel_v(image, position, word)
    case DrawRectangle{x, y, width, height}: Rgba.draw_rectangle(image, x, y, width, height, word)
    case DrawRectangleV{position, size}: Rgba.draw_rectangle_v(image, position, size, word)
    case DrawRectangleRec{rect}: Rgba.draw_rectangle_rec(image, rect, word)
    case DrawRectangleLines{rect, thickness}: Rgba.draw_rectangle_lines(image, rect, thickness, word)
    case DrawCircle{cx, cy, radius}: Rgba.draw_circle(image, cx, cy, radius, word)
    case DrawCircleV{center, radius}: Rgba.draw_circle_v(image, center, radius, word)
    case DrawCircleLines{cx, cy, radius}: Rgba.draw_circle_lines(image, cx, cy, radius, word)
    case DrawCircleLinesV{center, radius}: Rgba.draw_circle_lines_v(image, center, radius, word)
    case DrawLine{x0, y0, x1, y1}: Rgba.draw_line(image, x0, y0, x1, y1, word)
    case DrawLineV{start, end}: Rgba.draw_line_v(image, start, end, word)
    case DrawLineEx{start, end, thickness}: Rgba.draw_line_ex(image, start, end, thickness, word)
    case DrawTriangle{v1, v2, v3}: Rgba.draw_triangle(image, v1, v2, v3, word)
    case DrawTriangleLines{v1, v2, v3}: Rgba.draw_triangle_lines(image, v1, v2, v3, word)
    case DrawTriangleFan{points}: Rgba.draw_triangle_fan(image, points, word)
    case DrawTriangleStrip{points}: Rgba.draw_triangle_strip(image, points, word)
    case ClearBackground{}: Rgba.clear(image, word)

def Surface.mark.write(marked: Bool, index: U32, value: Surface.Quad, values: Array<Surface.Quad>) -> Array<Surface.Quad>:
  match marked:
    case False{}: values
    case True{}: Array.set(Surface.Quad, values, index, value)

def Surface.mark.read(+index: U32, value: Surface.Quad, values: Array<Surface.Quad>, read: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (marks, mark) = read
  (marks, Surface.mark.write(U32.is_eq(mark, 1), index, value, values))

def Surface.mark.loop(n: Nat, +index: U32, +value: Surface.Quad, state: Array<U32> & Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n state:
    case 0n Tuple{_, values}: values
    case 1n+rest Tuple{marks, values}:
      Surface.mark.loop(rest, (index + 1 : U32), value, Surface.mark.read(index, value, values, Array.get(U32, marks, index)))

# Wide formats paint a coverage mask, then store the encoded Color where covered.
def Surface.mark.quads(+width: U32, +height: U32, format: U32, value: Surface.Quad, values: Array<Surface.Quad>, marks: Rgba) -> Surface:
  Rgba{_, _, mask} = marks
  Surface{width, height, format, Quads{Surface.mark.loop(U32.to_nat((width * height : U32)), 0, value, (mask, values))}}

def Surface.paint.words(format: U32, image: Rgba) -> Surface:
  Rgba{width, height, pixels} = image
  Surface{width, height, format, Words{pixels}}

def Surface.paint.selected(pixels: Surface.Pixels, draw: Surface.Draw, color: U32, +width: U32, +height: U32, +format: U32) -> Surface:
  match pixels:
    case Words{values}: Surface.paint.words(format, Surface.draw.apply(draw, Surface.word.draw(format, color), Rgba{width, height, values}))
    case Quads{values}:
      Surface.mark.quads(width, height, format, Surface.quad.from_color(format, color), values,
        Surface.draw.apply(draw, 1, Rgba{width, height, Array.new(U32, Storage.depth((width * height : U32)), 0)}))

def Surface.paint.run(surface: Surface, draw: Surface.Draw, color: U32) -> Surface:
  Surface{width, height, format, pixels} = surface
  Surface.paint.selected(pixels, draw, color, width, height, format)

# ImageClearBackground stores the color with ImageDrawPixel in every pixel.
def Surface.clear(surface: Surface, color: U32) -> Surface:
  Surface.paint.run(surface, ClearBackground{}, color)

def Surface.draw_pixel(surface: Surface, x: F32, y: F32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawPixel{x, y}, color)

def Surface.draw_pixel_v(surface: Surface, position: M.Vector2, color: U32) -> Surface:
  Surface.paint.run(surface, DrawPixelV{position}, color)

def Surface.draw_rectangle(surface: Surface, x: F32, y: F32, width: F32, height: F32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawRectangle{x, y, width, height}, color)

def Surface.draw_rectangle_v(surface: Surface, position: M.Vector2, size: M.Vector2, color: U32) -> Surface:
  Surface.paint.run(surface, DrawRectangleV{position, size}, color)

def Surface.draw_rectangle_rec(surface: Surface, rect: Rectangle, color: U32) -> Surface:
  Surface.paint.run(surface, DrawRectangleRec{rect}, color)

def Surface.draw_rectangle_lines(surface: Surface, rect: Rectangle, thickness: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawRectangleLines{rect, thickness}, color)

def Surface.draw_circle(surface: Surface, cx: F32, cy: F32, radius: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawCircle{cx, cy, radius}, color)

def Surface.draw_circle_v(surface: Surface, center: M.Vector2, radius: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawCircleV{center, radius}, color)

def Surface.draw_circle_lines(surface: Surface, cx: F32, cy: F32, radius: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawCircleLines{cx, cy, radius}, color)

def Surface.draw_circle_lines_v(surface: Surface, center: M.Vector2, radius: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawCircleLinesV{center, radius}, color)

def Surface.draw_line(surface: Surface, x0: F32, y0: F32, x1: F32, y1: F32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawLine{x0, y0, x1, y1}, color)

def Surface.draw_line_v(surface: Surface, start: M.Vector2, end: M.Vector2, color: U32) -> Surface:
  Surface.paint.run(surface, DrawLineV{start, end}, color)

def Surface.draw_line_ex(surface: Surface, start: M.Vector2, end: M.Vector2, thickness: U32, color: U32) -> Surface:
  Surface.paint.run(surface, DrawLineEx{start, end, thickness}, color)

def Surface.draw_triangle(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, color: U32) -> Surface:
  Surface.paint.run(surface, DrawTriangle{v1, v2, v3}, color)

def Surface.draw_triangle_lines(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, color: U32) -> Surface:
  Surface.paint.run(surface, DrawTriangleLines{v1, v2, v3}, color)

def Surface.draw_triangle_fan(surface: Surface, points: +List<M.Vector2>, color: U32) -> Surface:
  Surface.paint.run(surface, DrawTriangleFan{points}, color)

def Surface.draw_triangle_strip(surface: Surface, points: +List<M.Vector2>, color: U32) -> Surface:
  Surface.paint.run(surface, DrawTriangleStrip{points}, color)

# DrawTriangleEx computes one Color per covered pixel, then ImageDrawPixel stores
# it. Other formats shade a canonical copy and encode the covered colors.
def Surface.shade.word(marked: Bool, +format: U32, index: U32, color: U32, values: Array<U32>) -> Array<U32>:
  match marked:
    case False{}: values
    case True{}: Array.set(U32, values, index, Surface.word.draw(format, color))

def Surface.shade.quad(marked: Bool, +format: U32, index: U32, color: U32, values: Array<Surface.Quad>) -> Array<Surface.Quad>:
  match marked:
    case False{}: values
    case True{}: Array.set(Surface.Quad, values, index, Surface.quad.from_color(format, color))

def Surface.shade.store(values: Surface.Pixels, marked: Bool, +format: U32, index: U32, color: U32) -> Surface.Pixels:
  match values:
    case Words{words}: Words{Surface.shade.word(marked, format, index, color, words)}
    case Quads{quads}: Quads{Surface.shade.quad(marked, format, index, color, quads)}

def Surface.shade.read(+format: U32, +index: U32, colors: Array<U32> & U32, marks: Array<U32> & U32, values: Surface.Pixels) -> (Array<U32> & Array<U32>) & Surface.Pixels:
  (shades, color) = colors
  (mask, mark) = marks
  ((shades, mask), Surface.shade.store(values, U32.is_eq(mark, 1), format, index, color))

def Surface.shade.step(+format: U32, +index: U32, buffers: Array<U32> & Array<U32>, values: Surface.Pixels) -> (Array<U32> & Array<U32>) & Surface.Pixels:
  (shades, mask) = buffers
  Surface.shade.read(format, index, Array.get(U32, shades, index), Array.get(U32, mask, index), values)

def Surface.shade.loop(n: Nat, +index: U32, +format: U32, state: (Array<U32> & Array<U32>) & Surface.Pixels) -> Surface.Pixels:
  match n state:
    case 0n Tuple{_, values}: values
    case 1n+rest Tuple{buffers, values}:
      Surface.shade.loop(rest, (index + 1 : U32), format, Surface.shade.step(format, index, buffers, values))

def Surface.shade.merged(+width: U32, +height: U32, +format: U32, pixels: Surface.Pixels, shades: Rgba, marks: Rgba) -> Surface:
  Rgba{_, _, colors} = shades
  Rgba{_, _, mask} = marks
  Surface{width, height, format, Surface.shade.loop(U32.to_nat((width * height : U32)), 0, format, ((colors, mask), pixels))}

def Surface.triangle_ex.selected(kind: U32, pixels: Surface.Pixels, +width: U32, +height: U32, +format: U32, +v1: M.Vector2, +v2: M.Vector2, +v3: M.Vector2, c1: U32, c2: U32, c3: U32) -> Surface:
  match kind pixels:
    case 7 Words{values}: Surface.rgba.wrap(Rgba.draw_triangle_ex(Rgba{width, height, values}, v1, v2, v3, c1, c2, c3))
    case _ _:
      +depth = Storage.depth((width * height : U32))
      Surface.shade.merged(width, height, format, pixels,
        Rgba.draw_triangle_ex(Rgba{width, height, Array.new(U32, depth, 0)}, v1, v2, v3, c1, c2, c3),
        Rgba.draw_triangle(Rgba{width, height, Array.new(U32, depth, 0)}, v1, v2, v3, 1))

def Surface.draw_triangle_ex(surface: Surface, v1: M.Vector2, v2: M.Vector2, v3: M.Vector2, c1: U32, c2: U32, c3: U32) -> Surface:
  Surface{width, height, +format, pixels} = surface
  Surface.triangle_ex.selected(format, pixels, width, height, format, v1, v2, v3, c1, c2, c3)

# ImageDraw on every format. Each drawn pixel is GetPixelColor of both images,
# ColorAlphaBlend unless the source has no alpha and tint.a is 255, then
# SetPixelColor; without blending, equal formats copy stored samples (memcpy).
type Surface.Blit is Data:
  Blit{source: U32, target: U32, copy: Bool, blend: Bool, tint: U32}

def Surface.blit.blended(blend: Bool, +dst: U32, +src: U32, +tint: U32) -> U32:
  match blend:
    case True{}: Color.alpha_blend(dst, src, tint)
    case False{}: src

def Surface.blit.convert(mode: Surface.Blit, +sc: U32, +dc: U32) -> U32:
  Blit{+source, +target, _, blend, tint} = mode
  Surface.word.write(target, Surface.blit.blended(blend, Surface.word.read(target, dc), Surface.word.read(source, sc), tint), dc)

def Surface.blit.word(copy: Bool, mode: Surface.Blit, +sc: U32, +dc: U32) -> U32:
  match copy:
    case True{}: sc
    case False{}: Surface.blit.convert(mode, sc, dc)

def Surface.blit.copying(mode: Surface.Blit) -> Bool:
  Blit{_, _, copy, _, _} = mode
  copy

def Surface.blit.pixel(+mode: Surface.Blit, at: U32, source: Array<U32> & U32, destination: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (src, +sc) = source
  (dst, +dc) = destination
  (src, Array.set(U32, dst, at, Surface.blit.word(Surface.blit.copying(mode), mode, sc, dc)))

def Surface.blit.row(n: Nat, +si: U32, +di: U32, +mode: Surface.Blit, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+k Tuple{src, dst}:
      Surface.blit.row(k, (si + 1 : U32), (di + 1 : U32), mode,
        Surface.blit.pixel(mode, di, Array.get(U32, src, si), Array.get(U32, dst, di)))

def Surface.blit.rows(n: Nat, +cols: Nat, +si: U32, +di: U32, +sw: U32, +dw: U32, +mode: Surface.Blit, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n: buffers
    case 1n+k: Surface.blit.rows(k, cols, (si + sw : U32), (di + dw : U32), sw, dw, mode, Surface.blit.row(cols, si, di, mode, buffers))

# The clipped source rectangle at (x, y), in destination and source indices.
type Surface.Area is Data:
  Area{columns: U32, rows: U32, source_at: U32, output_at: U32}

def Surface.blit.area(+dw: U32, +dh: U32, +sw: U32, rect: Rectangle, +x: F32, +y: F32) -> Surface.Area:
  Rectangle{rx, ry, rw, rh} = rect
  +skipx = F32.max(0.0, (0.0 - x : F32))
  +skipy = F32.max(0.0, (0.0 - y : F32))
  +dx = F32.max(0.0, x)
  +dy = F32.max(0.0, y)
  Area{F32.to_u32(F32.max(0.0, F32.min((rw - skipx : F32), (U32.to_f32(dw) - dx : F32)))),
    F32.to_u32(F32.max(0.0, F32.min((rh - skipy : F32), (U32.to_f32(dh) - dy : F32)))),
    (F32.to_u32((ry + skipy : F32)) * sw + F32.to_u32((rx + skipx : F32)) : U32), (F32.to_u32(dy) * dw + F32.to_u32(dx) : U32)}

def Surface.blit.words(area: Surface.Area, +sw: U32, +dw: U32, +mode: Surface.Blit, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  Area{+columns, rows, source_at, output_at} = area
  Surface.blit.rows(U32.to_nat(rows), U32.to_nat(columns), source_at, output_at, sw, dw, mode, buffers)

def Surface.blit.quads(area: Surface.Area, +sw: U32, +dw: U32, buffers: Array<Surface.Quad> & Array<Surface.Quad>) -> Array<Surface.Quad> & Array<Surface.Quad>:
  Area{+columns, +rows, +source_at, +output_at} = area
  Raster.canvas.copy(~Surface.Quad, U32.to_nat((columns * rows : U32)), 0, columns, sw, dw, source_at, output_at, buffers)

def Surface.blit.drawn(buffers: Array<U32> & Array<U32>) -> Array<U32>:
  (_, dst) = buffers
  dst

def Surface.blit.owners(+dw: U32, +dh: U32, +df: U32, +sw: U32, +sh: U32, +sf: U32, buffers: Surface.Pixels & Surface.Pixels) -> Surface & Surface:
  (src, dst) = buffers
  (Surface{dw, dh, df, dst}, Surface{sw, sh, sf, src})

def Surface.blit.word_pair(result: Array<U32> & Array<U32>) -> Surface.Pixels & Surface.Pixels:
  (src, dst) = result
  (Words{src}, Words{dst})

def Surface.blit.quad_pair(result: Array<Surface.Quad> & Array<Surface.Quad>) -> Surface.Pixels & Surface.Pixels:
  (src, dst) = result
  (Quads{src}, Quads{dst})

# SetPixelColor cannot write wide formats: only an unblended same-format copy changes them.
def Surface.blit.quad_copy(copy: Bool, area: Surface.Area, +sw: U32, +dw: U32, src: Array<Surface.Quad>, dst: Array<Surface.Quad>) -> Surface.Pixels & Surface.Pixels:
  match copy:
    case True{}: Surface.blit.quad_pair(Surface.blit.quads(area, sw, dw, (src, dst)))
    case False{}: (Quads{src}, Quads{dst})

# Formats without alpha skip ColorAlphaBlend when tint.a is 255.
def Surface.blit.opaque(+format: U32, +tint: U32) -> Bool:
  U32.is_eq(Color.alpha(tint), 255) && (U32.is_eq(format, 1) || U32.is_eq(format, 3) || U32.is_eq(format, 4) || U32.is_eq(format, 8)
    || U32.is_eq(format, 9) || U32.is_eq(format, 11) || U32.is_eq(format, 12))

def Surface.blit.recolored(destination: Surface, colors: Surface, source: Surface, area: Surface.Area, +opaque: Bool, +tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match destination colors:
    case Surface{+dw, +dh, +df, Words{dst}} Surface{+sw, _, _, Words{src}}:
      Done{(Surface{dw, dh, df, Words{Surface.blit.drawn(Surface.blit.words(area, sw, dw, Blit{7, df, False{}, Bool.not(opaque), tint}, (src, dst)))}}, source)}
    case unchanged _: Done{(unchanged, source)}

def Surface.blit.colors(destination: Surface, source: Surface, area: Surface.Area, +opaque: Bool, +tint: U32, colors: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match colors:
    case Fail{Tuple{_, error}}: Fail{((destination, source), error)}
    case Done{converted}: Surface.blit.recolored(destination, converted, source, area, opaque, tint)

# A wide source is read through its RGBA8 colors (GetPixelColor's casts, finite
# [0,1] only); the original source owner is returned unchanged.
def Surface.blit.colored(destination: Surface, area: Surface.Area, +opaque: Bool, +tint: U32, pair: Surface & Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (source, copy) = pair
  Surface.blit.colors(destination, source, area, opaque, tint, Surface.format(copy, 7))

def Surface.blit.selected(dp: Surface.Pixels, sp: Surface.Pixels, area: Surface.Area, +dw: U32, +dh: U32, +df: U32, +sw: U32, +sh: U32, +sf: U32, +tint: U32, +opaque: Bool) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match dp sp:
    case Words{dst} Words{src}:
      Done{Surface.blit.owners(dw, dh, df, sw, sh, sf, Surface.blit.word_pair(
        Surface.blit.words(area, sw, dw, Blit{sf, df, opaque && U32.is_eq(sf, df), Bool.not(opaque), tint}, (src, dst))))}
    case Words{dst} Quads{src}:
      Surface.blit.colored(Surface{dw, dh, df, Words{dst}}, area, opaque, tint, Surface.copy(Surface{sw, sh, sf, Quads{src}}))
    case Quads{dst} Quads{src}:
      Done{Surface.blit.owners(dw, dh, df, sw, sh, sf, Surface.blit.quad_copy(opaque && U32.is_eq(sf, df), area, sw, dw, src, dst))}
    case Quads{dst} Words{src}: Done{(Surface{dw, dh, df, Quads{dst}}, Surface{sw, sh, sf, Words{src}})}

def Surface.blit.region(destination: Surface, source: Surface, rect: Rectangle, +x: F32, +y: F32, +tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+dw, +dh, df, dp} = destination
  Surface{+sw, sh, +sf, sp} = source
  Surface.blit.selected(dp, sp, Surface.blit.area(dw, dh, sw, rect, x, y), dw, dh, df, sw, sh, sf, tint, Surface.blit.opaque(sf, tint))

def Surface.region.checked(valid: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((destination, source), InvalidRectangle{})}
    case True{}: Surface.blit.region(destination, source, rect, x, y, tint)

# Unscaled ImageDraw of an integral, in-bounds source rectangle at integral (x, y).
def Surface.draw_image_region(destination: Surface, source: Surface, +rect: Rectangle, +x: F32, +y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, format, pixels} = source
  Surface.region.checked(Rectangle.integral(rect) && Rectangle.inside(rect, w, h)
    && F32.is_eq(F32.floor(x), x) && F32.is_eq(F32.floor(y), y), destination, Surface{w, h, format, pixels}, rect, x, y, tint)

# ImageDraw of the full source at (x, y).
def Surface.draw_image(destination: Surface, source: Surface, +x: F32, +y: F32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+w, +h, format, pixels} = source
  Surface.blit.region(destination, Surface{w, h, format, pixels}, Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)}, x, y, tint)

def Surface.image_rect.finish(original: Surface, drawn: Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match drawn:
    case Fail{Tuple{Tuple{destination, _}, error}}: Fail{((destination, original), error)}
    case Done{Tuple{destination, _}}: Done{(destination, original)}

def Surface.image_rect.resized(destination: Surface, original: Surface, x: F32, y: F32, tint: U32, resized: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match resized:
    case Fail{Tuple{_, error}}: Fail{((destination, original), error)}
    case Done{scaled}: Surface.image_rect.finish(original, Surface.draw_image(destination, scaled, x, y, tint))

def Surface.image_rect.extracted(destination: Surface, x: F32, y: F32, width: U32, height: U32, tint: U32, extracted: Surface & Maybe<Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match extracted:
    case Tuple{source, None{}}: Fail{((destination, source), InvalidRectangle{})}
    case Tuple{source, Some{region}}:
      Surface.image_rect.resized(destination, source, x, y, tint, Surface.resize(region, width, height))

# ImageFromImage truncates the clipped (possibly fractional) source rectangle.
def Surface.image_rect.extract(source: Surface, rect: Rectangle) -> Surface & Maybe<Surface>:
  Surface{w, h, format, pixels} = source
  Rectangle{x, y, width, height} = rect
  Surface.extract.checked(True{}, w, h, format, pixels, x, y, width, height)

def Surface.image_rect.route(scaled: Bool, destination: Surface, source: Surface, rect: Rectangle, x: F32, y: F32, width: U32, height: U32, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match scaled:
    case False{}: Surface.blit.region(destination, source, rect, x, y, tint)
    case True{}: Surface.image_rect.extracted(destination, x, y, width, height, tint, Surface.image_rect.extract(source, rect))

def Surface.image_rect.checked(valid: Bool, destination: Surface, source: Surface, +rect: Rectangle, target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((destination, source), InvalidRectangle{})}
    case True{}:
      Rectangle{_, _, rw, rh} = rect
      Rectangle{x, y, +width, +height} = target
      Surface.image_rect.route((F32.is_ne(F32.floor(rw), F32.floor(width)) || F32.is_ne(F32.floor(rh), F32.floor(height))), destination, source, rect, x, y,
        F32.to_u32(width), F32.to_u32(height), tint)

# Scaled ImageDraw: the clipped source rectangle is extracted and resized in
# its own format (ImageFromImage + ImageResize) when its integral size differs.
def Surface.draw_image_rect(destination: Surface, source: Surface, +rect: Rectangle, +target: Rectangle, tint: U32) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+sw, +sh, format, pixels} = source
  Rectangle{+x, +y, width, height} = rect
  Rectangle{_, _, +tw, +th} = target
  +sx = F32.max(0.0, x)
  +sy = F32.max(0.0, y)
  +cw = F32.min((width + F32.min(0.0, x) : F32), (U32.to_f32(sw) - sx : F32))
  +ch = F32.min((height + F32.min(0.0, y) : F32), (U32.to_f32(sh) - sy : F32))
  Surface.image_rect.checked(Rectangle.bounded(rect) && Rectangle.bounded(target)
    && ((cw >= 1.0) && (ch >= 1.0) && (tw >= 1.0) && (th >= 1.0) && (F32.floor(tw) <= 4096.0) && (F32.floor(th) <= 4096.0) : F32),
    destination, Surface{sw, sh, format, pixels}, Rectangle{sx, sy, cw, ch}, target, tint)

# ImageAlphaMask: the mask is a GRAYSCALE copy of `source` (ImageFormat). A
# GRAYSCALE destination becomes GRAY_ALPHA; others become R8G8B8A8 (ImageFormat)
# whose alpha bytes are the mask. Rejections return both owners unchanged.
def Surface.mask.pixel(+gray_alpha: Bool, at: U32, destination: Array<U32> & U32, mask: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (dst, +word) = destination
  (gray, +value) = mask
  (Array.set(U32, dst, at, Bool.pick(U32, gray_alpha, (word .|. (value << 8n) : U32), ((word .&. 4294967040) .|. value : U32))), gray)

def Surface.mask.loop(n: Nat, +at: U32, +gray_alpha: Bool, state: Array<U32> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{dst, _}: dst
    case 1n+k Tuple{dst, gray}:
      Surface.mask.loop(k, (at + 1 : U32), gray_alpha, Surface.mask.pixel(gray_alpha, at, Array.get(U32, dst, at), Array.get(U32, gray, at)))

def Surface.mask.write(+gray_alpha: Bool, source: Surface, target: Surface, mask: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match target mask:
    case Surface{+w, +h, _, Words{dst}} Surface{_, _, _, Words{gray}}:
      Done{(Surface{w, h, Bool.pick(U32, gray_alpha, 2, 7), Words{Surface.mask.loop(U32.to_nat((w * h : U32)), 0, gray_alpha, (dst, gray))}}, source)}
    case _ _: Fail{((target, source), UnsupportedFormat{})}

def Surface.mask.rgba(source: Surface, mask: Surface, converted: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match converted:
    case Fail{Tuple{destination, error}}: Fail{((destination, source), error)}
    case Done{target}: Surface.mask.write(False{}, source, target, mask)

def Surface.mask.target(kind: U32, destination: Surface, source: Surface, mask: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match kind:
    case 1: Surface.mask.write(True{}, source, destination, mask)
    case _: Surface.mask.rgba(source, mask, Surface.format(destination, 7))

def Surface.mask.dispatch(destination: Surface, source: Surface, mask: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{w, h, +format, pixels} = destination
  Surface.mask.target(format, Surface{w, h, format, pixels}, source, mask)

def Surface.mask.converted(destination: Surface, source: Surface, gray: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match gray:
    case Fail{Tuple{_, error}}: Fail{((destination, source), error)}
    case Done{mask}: Surface.mask.dispatch(destination, source, mask)

def Surface.mask.copied(destination: Surface, pair: Surface & Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  (source, copy) = pair
  Surface.mask.converted(destination, source, Surface.format(copy, 1))

def Surface.mask.sized(valid: Bool, destination: Surface, source: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  match valid:
    case False{}: Fail{((destination, source), InvalidSize{})}
    case True{}: Surface.mask.copied(destination, Surface.copy(source))

def Surface.alpha_mask(destination: Surface, source: Surface) -> Result<&1, &1, (Surface & Surface) & Surface.Error, Surface & Surface>:
  Surface{+dw, +dh, df, dp} = destination
  Surface{+mw, +mh, mf, mp} = source
  Surface.mask.sized(U32.is_eq(dw, mw) && U32.is_eq(dh, mh), Surface{dw, dh, df, dp}, Surface{mw, mh, mf, mp})

# ImageAlphaClear on native words: GRAY_ALPHA compares its alpha byte and
# stores (color.r, color.a); R5G5B5A1 and R4G4B4A4 compare their alpha bits.
def Surface.alpha_clear.word(kind: U32, +cutoff: U32, +replacement: U32, +word: U32) -> U32:
  match kind:
    case 2: Bool.pick(U32, ((word >> 8n) <= cutoff : U32), replacement, word)
    case 5: Bool.pick(U32, ((word .&. 1) <= cutoff : U32), replacement, word)
    case _: Bool.pick(U32, ((word .&. 15) <= cutoff : U32), replacement, word)

def Surface.alpha_clear.step(+kind: U32, +cutoff: U32, +replacement: U32, i: U32, got: Array<U32> & U32) -> Array<U32>:
  (values, word) = got
  Array.set(U32, values, i, Surface.alpha_clear.word(kind, cutoff, replacement, word))

def Surface.alpha_clear.loop(n: Nat, +i: U32, +kind: U32, +cutoff: U32, +replacement: U32, values: Array<U32>) -> Array<U32>:
  match n:
    case 0n: values
    case 1n+k:
      Surface.alpha_clear.loop(k, (i + 1 : U32), kind, cutoff, replacement,
        Surface.alpha_clear.step(kind, cutoff, replacement, i, Array.get(U32, values, i)))

# raylib computes round(channel*31.0f) and round(channel*15.0f) from unscaled
# bytes and casts them to unsigned char, which is defined only up to 255.
def Surface.alpha_clear.packed(+c: U32, +scale: U32) -> U32:
  (c * scale : U32)

def Surface.alpha_clear.r5g5b5a1(+color: U32) -> U32:
  (((Surface.alpha_clear.packed(Color.red(color), 31) << 11n) .|. (Surface.alpha_clear.packed(Color.green(color), 31) << 6n)
    .|. (Surface.alpha_clear.packed(Color.blue(color), 31) << 1n) .|. Bool.pick(U32, (Color.alpha(color) < 128 : U32), 0, 1)) .&. 65535 : U32)

def Surface.alpha_clear.r4g4b4a4(+color: U32) -> U32:
  (((Surface.alpha_clear.packed(Color.red(color), 15) << 12n) .|. (Surface.alpha_clear.packed(Color.green(color), 15) << 8n)
    .|. (Surface.alpha_clear.packed(Color.blue(color), 15) << 4n) .|. Surface.alpha_clear.packed(Color.alpha(color), 15)) .&. 65535 : U32)

# R32G32B32A32 and R16G16B16A16 compare their float alpha with the threshold and
# store the Color as channel/255 F32 or half floats.
def Surface.normal.alpha(sample: Formats.Normal) -> F32:
  Formats.Normal{_, _, _, alpha} = sample
  alpha

def Surface.alpha_clear.quad(+kind: U32, +threshold: F32, +replacement: Surface.Quad, +quad: Surface.Quad) -> Surface.Quad:
  Bool.pick(Surface.Quad, (Surface.normal.alpha(Surface.quad.normal(kind, quad)) <= threshold : F32), replacement, quad)

def Surface.alpha_clear.quad.step(+kind: U32, +threshold: F32, +replacement: Surface.Quad, i: U32, got: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad>:
  (values, quad) = got
  Array.set(Surface.Quad, values, i, Surface.alpha_clear.quad(kind, threshold, replacement, quad))

def Surface.alpha_clear.quads(n: Nat, +i: U32, +kind: U32, +threshold: F32, +replacement: Surface.Quad, values: Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n:
    case 0n: values
    case 1n+k:
      Surface.alpha_clear.quads(k, (i + 1 : U32), kind, threshold, replacement,
        Surface.alpha_clear.quad.step(kind, threshold, replacement, i, Array.get(Surface.Quad, values, i)))

def Surface.alpha_clear.selected(kind: U32, pixels: Surface.Pixels, +width: U32, +height: U32, +format: U32, +color: U32, +threshold: F32) -> Surface:
  match kind pixels:
    case 7 Words{values}: Surface.rgba.wrap(Rgba.alpha_clear(Rgba{width, height, values}, color, threshold))
    case 2 Words{values}:
      Surface{width, height, format, Words{Surface.alpha_clear.loop(U32.to_nat((width * height : U32)), 0, 2,
        F32.to_u32((threshold * 255.0 : F32)), (Color.red(color) .|. (Color.alpha(color) << 8n) : U32), values)}}
    case 5 Words{values}:
      Surface{width, height, format, Words{Surface.alpha_clear.loop(U32.to_nat((width * height : U32)), 0, 5,
        Bool.pick(U32, (threshold < 0.5 : F32), 0, 1), Surface.alpha_clear.r5g5b5a1(color), values)}}
    case 6 Words{values}:
      Surface{width, height, format, Words{Surface.alpha_clear.loop(U32.to_nat((width * height : U32)), 0, 6,
        F32.to_u32((threshold * 15.0 : F32)), Surface.alpha_clear.r4g4b4a4(color), values)}}
    case 10 Quads{values}:
      Surface{width, height, format, Quads{Surface.alpha_clear.quads(U32.to_nat((width * height : U32)), 0, 10, threshold, Surface.quad.from_color(10, color), values)}}
    case 13 Quads{values}:
      Surface{width, height, format, Quads{Surface.alpha_clear.quads(U32.to_nat((width * height : U32)), 0, 13, threshold, Surface.quad.from_color(13, color), values)}}
    case _ other: Surface{width, height, format, other}

def Surface.alpha_clear.checked(valid: Bool, +width: U32, +height: U32, +format: U32, pixels: Surface.Pixels, color: U32, threshold: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(Surface{width, height, format, pixels}, InvalidRequest{})}
    case True{}: Done{Surface.alpha_clear.selected(format, pixels, width, height, format, color, threshold)}

# The unscaled R5G5B5A1/R4G4B4A4 channels overflow the byte cast for channels
# above 8 (times 31) or 17 (times 15): undefined native results, refused here.
def Surface.alpha_clear.defined(+format: U32, +color: U32) -> Bool:
  +rgb = U32.max(Color.red(color), U32.max(Color.green(color), Color.blue(color)))
  Bool.pick(Bool, U32.is_eq(format, 5), (rgb <= 8 : U32),
    Bool.pick(Bool, U32.is_eq(format, 6), (U32.max(rgb, Color.alpha(color)) <= 17 : U32), True{}))

# ImageAlphaClear: formats without alpha are unchanged, as in raylib. The
# threshold is a finite 0..1 alpha fraction and the color must keep raylib's
# packed conversions defined; other requests are InvalidRequest.
def Surface.alpha_clear(surface: Surface, +color: U32, +threshold: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{width, height, +format, pixels} = surface
  Surface.alpha_clear.checked(Surface.amount.finite(threshold) && (threshold >= 0.0 : F32) && (threshold <= 1.0 : F32)
    && Surface.alpha_clear.defined(format, color), width, height, format, pixels, color, threshold)

# ImageRotate blends every stored byte on its own: word formats rotate their
# stored words, wide formats each sample word (unused words stay zero).
def Surface.rotation.quad(a: Surface.Quad, b: Surface.Quad, c: Surface.Quad, d: Surface.Quad, +x: F32, +y: F32) -> Surface.Quad:
  Quad{a0, a1, a2, a3} = a
  Quad{b0, b1, b2, b3} = b
  Quad{c0, c1, c2, c3} = c
  Quad{d0, d1, d2, d3} = d
  Quad{Rotation.mix(a0, b0, c0, d0, x, y), Rotation.mix(a1, b1, c1, d1, x, y), Rotation.mix(a2, b2, c2, d2, x, y), Rotation.mix(a3, b3, c3, d3, x, y)}

def Surface.rotation.blend(a: Surface.Quad, b: Surface.Quad, c: Surface.Quad, d: Surface.Quad, x: F32, y: F32) -> Surface.Quad:
  Surface.rotation.quad(a, b, c, d, x, y)

def Surface.rotation.pixels(pixels: Surface.Pixels, +sw: U32, +sh: U32, +width: U32, +height: U32, +cosine: F32, +sine: F32) -> Surface.Pixels:
  match pixels:
    case Words{values}: Words{Rotation.render(sw, sh, width, height, cosine, sine, values)}
    case Quads{values}:
      Quads{Rotation.render.with(~Surface.Quad, ~Surface.rotation.blend, Surface.quad.zero(), sw, sh, width, height, cosine, sine, values)}

# The R32 and R16 owner domain: finite [0, 1] samples (both zero signs).
def Surface.words.unit.read(+kind: U32, result: Array<U32> & U32) -> Array<U32> & Bool:
  (values, +word) = result
  (values, Bool.pick(Bool, U32.is_eq(kind, 11), Formats.r16.word_valid(word), Formats.r32.word_valid(word)))

def Surface.words.unit(n: Nat, +index: U32, +kind: U32, state: Array<U32> & Bool) -> Array<U32> & Bool:
  match n state:
    case _ Tuple{values, False{}}: (values, False{})
    case 0n _: state
    case 1n+rest Tuple{values, True{}}:
      Surface.words.unit(rest, (index + 1 : U32), kind, Surface.words.unit.read(kind, Array.get(U32, values, index)))

def Surface.rotation.words(state: Array<U32> & Bool) -> Surface.Pixels & Bool:
  (values, ok) = state
  (Words{values}, ok)

def Surface.rotation.quads(state: Array<Surface.Quad> & Bool) -> Surface.Pixels & Bool:
  (values, ok) = state
  (Quads{values}, ok)

# Blended float bytes can leave the owner domain (R32/R16 finite [0,1], wide F32
# samples non-NaN); such results are refused and the original owner is returned.
def Surface.rotation.domain(kind: U32, +format: U32, +count: U32, pixels: Surface.Pixels) -> Surface.Pixels & Bool:
  match kind pixels:
    case 8 Words{values}: Surface.rotation.words(Surface.words.unit(U32.to_nat(count), 0, 8, (values, True{})))
    case 11 Words{values}: Surface.rotation.words(Surface.words.unit(U32.to_nat(count), 0, 11, (values, True{})))
    case _ Quads{values}: Surface.rotation.quads(Surface.quads.checked(U32.to_nat(count), 0, format, True{}, (values, True{})))
    case _ other: (other, True{})

def Surface.rotation.checked(original: Surface, +width: U32, +height: U32, +format: U32, result: Surface.Pixels & Bool) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match result:
    case Tuple{_, False{}}: Fail{(original, OutOfDomain{})}
    case Tuple{rotated, True{}}: Done{Surface{width, height, format, rotated}}

def Surface.rotation.render(+width: U32, +height: U32, +cosine: F32, +sine: F32, pair: Surface & Surface) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  (original, Surface{+sw, +sh, +format, pixels}) = pair
  Surface.rotation.checked(original, width, height, format,
    Surface.rotation.domain(format, format, (width * height : U32), Surface.rotation.pixels(pixels, sw, sh, width, height, cosine, sine)))

# Only float formats can be refused, so only they keep a copy of the original.
def Surface.rotation.selected(guarded: Bool, surface: Surface, +width: U32, +height: U32, +cosine: F32, +sine: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match guarded:
    case True{}: Surface.rotation.render(width, height, cosine, sine, Surface.copy(surface))
    case False{}:
      Surface{+sw, +sh, format, pixels} = surface
      Done{Surface{width, height, format, Surface.rotation.pixels(pixels, sw, sh, width, height, cosine, sine)}}

def Surface.rotation.sized(valid: Bool, surface: Surface, +width: U32, +height: U32, cosine: F32, sine: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidSize{})}
    case True{}:
      Surface{sw, sh, +format, pixels} = surface
      Surface.rotation.selected(U32.is_eq(format, 8) || U32.is_eq(format, 9) || U32.is_eq(format, 10) || U32.is_eq(format, 11),
        Surface{sw, sh, format, pixels}, width, height, cosine, sine)

def Surface.rotation.trigonometry(surface: Surface, values: F32 & F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{+sw, +sh, format, pixels} = surface
  (+cosine, +sine) = values
  +width = F32.to_u32((F32.abs((U32.to_f32(sw) * cosine : F32)) + F32.abs((U32.to_f32(sh) * sine : F32)) : F32))
  +height = F32.to_u32((F32.abs((U32.to_f32(sh) * cosine : F32)) + F32.abs((U32.to_f32(sw) * sine : F32)) : F32))
  Surface.rotation.sized(((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) : U32),
    Surface{sw, sh, format, pixels}, width, height, cosine, sine)

def Surface.rotation.angle(valid: Bool, reference: M.Libm, surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match valid:
    case False{}: Fail{(surface, InvalidRectangle{})}
    case True{}:
      radians = (degrees * 3.14159265358979323846 / 180.0 : F32)
      Surface.rotation.trigonometry(surface, Trig.sincos_for(M.Libm.gnu(reference), radians))

# ImageRotate with integral degrees in -360..360 on every format.
def Surface.rotate_degrees_for(reference: M.Libm, surface: Surface, +degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotation.angle((F32.abs(degrees) <= 360.0 : F32) && F32.is_eq(F32.floor(degrees), degrees), reference, surface, degrees)

def Surface.rotate_degrees(surface: Surface, degrees: F32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface.rotate_degrees_for(M.AppleLibm{}, surface, degrees)

# Halving sizes are always valid, so resize never rejects a level here.
def Surface.mipmaps.level(result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Surface:
  match result:
    case Fail{Tuple{surface, _}}: surface
    case Done{surface}: surface

def Surface.mipmaps.copied(reversed: List<Surface>, pair: Surface & Surface) -> Surface & List<Surface>:
  (source, Surface{+width, +height, format, pixels}) = pair
  (Surface.mipmaps.level(Surface.resize(Surface{width, height, format, pixels}, U32.max(1, (width / 2 : U32)), U32.max(1, (height / 2 : U32)))),
    Con{source, reversed})

def Surface.mipmaps.levels(n: Nat, state: Surface & List<Surface>) -> List<Surface>:
  match n state:
    case 0n Tuple{surface, reversed}: List.reverse(&1, Surface, Con{surface, reversed})
    case 1n+rest Tuple{surface, reversed}: Surface.mipmaps.levels(rest, Surface.mipmaps.copied(reversed, Surface.copy(surface)))

# Altered adaptation of raylib ImageMipmaps: every format; each level is
# ImageResize of the preceding one, so converted formats requantize per level.
def Surface.mipmaps(surface: Surface) -> Image.Mipmaps:
  Surface{+width, +height, format, pixels} = surface
  +steps = U32.log2(U32.max(width, height))
  Mipmaps{(1 + U32.from_nat(steps) : U32), Surface.mipmaps.levels(steps, (Surface{width, height, format, pixels}, Nil{}))}

def Image.Mipmaps.entries(chain: Image.Mipmaps) -> U32 & List<Surface>:
  Mipmaps{count, levels} = chain
  (count, levels)

def Image.Mipmaps.unload(chain: Image.Mipmaps) -> Unit:
  Unit{}

# LoadImageColors and readers that keep the owner.
def Surface.colors.rgba(result: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, List<U32>>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{image}: Done{Rgba.colors(image)}

# IsImageValid: positive dimensions and a format. A Surface from any factory
# passes; a hand-built record also needs 1..4096 dimensions, a format 1..13 and
# the storage variant of that format. The owner is returned.
def Surface.valid.storage(wide: Bool, pixels: Surface.Pixels) -> Surface.Pixels & Bool:
  match wide pixels:
    case True{} Quads{values}: (Quads{values}, True{})
    case False{} Words{values}: (Words{values}, True{})
    case _ other: (other, False{})

def Surface.valid.result(+width: U32, +height: U32, +format: U32, sized: Bool, checked: Surface.Pixels & Bool) -> Surface & Bool:
  (pixels, stored) = checked
  (Surface{width, height, format, pixels}, sized && stored)

def Surface.is_valid(surface: Surface) -> Surface & Bool:
  Surface{+width, +height, +format, pixels} = surface
  Surface.valid.result(width, height, format,
    ((width >= 1) && (height >= 1) && (width <= 4096) && (height <= 4096) && (format >= 1) && (format <= 13) : U32),
    Surface.valid.storage(Surface.wide(format), pixels))

# UnloadImage and UnloadImageColors: consuming the owner releases its storage.
def Surface.unload(surface: Surface) -> Unit:
  Unit{}

def Surface.unload_colors(colors: List<U32>) -> Unit:
  Unit{}

# Consumes the owner; padding storage is excluded.
def Surface.colors(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, List<U32>>:
  Surface.colors.rgba(Surface.rgba.load(surface))

def Surface.get.words(+width: U32, height: U32, +format: U32, result: Array<U32> & U32) -> Surface & Maybe<&2, U32>:
  (values, +word) = result
  (Surface{width, height, format, Words{values}}, Some{Bool.pick(U32, U32.is_eq(format, 7), word, Formats.image_color(format, word))})

def Surface.get.quads(width: U32, height: U32, +format: U32, result: Array<Surface.Quad> & Surface.Quad) -> Surface & Maybe<&2, U32>:
  (values, +value) = result
  (Surface{width, height, format, Quads{values}}, Bool.pick(Maybe<&2, U32>, Surface.quad.valid(format, value), Some{Surface.quad.color(format, value)}, None{}))

def Surface.get.checked(valid: Bool, +width: U32, height: U32, format: U32, pixels: Surface.Pixels, x: U32, y: U32) -> Surface & Maybe<&2, U32>:
  match valid pixels:
    case False{} _: (Surface{width, height, format, pixels}, None{})
    case True{} Words{values}: Surface.get.words(width, height, format, Array.get(U32, values, (y * width + x : U32)))
    case True{} Quads{values}: Surface.get.quads(width, height, format, Array.get(Surface.Quad, values, (y * width + x : U32)))

# GetImageColor: out-of-bounds U32 coordinates and wide samples outside the
# LoadImageColors domain return None; coordinates never wrap.
def Surface.get(surface: Surface, +x: U32, +y: U32) -> Surface & Maybe<&2, U32>:
  Surface{+width, +height, format, pixels} = surface
  Surface.get.checked(((x < width) && (y < height) : U32), width, height, format, pixels, x, y)

def Surface.rgba.inspect.converted(keep: Surface, converted: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Surface & Maybe<Rgba>:
  match converted:
    case Fail{_}: (keep, None{})
    case Done{image}: (keep, Some{image})

def Surface.rgba.inspect.cloned(+width: U32, +height: U32, +format: U32, pair: Surface.Pixels & Surface.Pixels) -> Surface & Maybe<Rgba>:
  (keep, work) = pair
  Surface.rgba.inspect.converted(Surface{width, height, format, keep}, Surface.rgba.load(Surface{width, height, format, work}))

# LoadImageColors on a copy; the owner comes back unchanged.
def Surface.rgba.inspect(surface: Surface) -> Surface & Maybe<Rgba>:
  Surface{width, height, format, pixels} = surface
  Surface.rgba.inspect.cloned(width, height, format, Surface.pixels.clone(pixels))

def Surface.palette.found(owner: Surface, result: Rgba & Maybe<Image.Palette>) -> Surface & Maybe<Image.Palette>:
  (_, palette) = result
  (owner, palette)

def Surface.palette.inspected(+maximum: U32, result: Surface & Maybe<Rgba>) -> Surface & Maybe<Image.Palette>:
  match result:
    case Tuple{owner, None{}}: (owner, None{})
    case Tuple{owner, Some{image}}: Surface.palette.found(owner, Rgba.load_palette(image, maximum))

# LoadImagePalette: distinct non-transparent colors in scan order, up to maximum.
def Surface.load_palette(surface: Surface, maximum: U32) -> Surface & Maybe<Image.Palette>:
  Surface.palette.inspected(maximum, Surface.rgba.inspect(surface))

def Surface.border.found(owner: Surface, result: Rgba & Rectangle) -> Surface & Rectangle:
  (_, rect) = result
  (owner, rect)

def Surface.border.inspected(threshold: F32, result: Surface & Maybe<Rgba>) -> Surface & Rectangle:
  match result:
    case Tuple{owner, None{}}: (owner, Rectangle{0.0, 0.0, 0.0, 0.0})
    case Tuple{owner, Some{image}}: Surface.border.found(owner, Rgba.alpha_border(image, threshold))

# GetImageAlphaBorder reads only alpha, which LoadImageColors sets to 255 for
# R32G32B32 and R16G16B16 whatever the samples, so they have a defined border;
# other formats go through LoadImageColors (no border outside its domain).
def Surface.alpha_border.selected(opaque: Bool, pixels: Surface.Pixels, threshold: F32, +width: U32, +height: U32, format: U32) -> Surface & Rectangle:
  match opaque:
    case False{}: Surface.border.inspected(threshold, Surface.rgba.inspect(Surface{width, height, format, pixels}))
    case True{}:
      Surface.border.found(Surface{width, height, format, pixels},
        Rgba.alpha_border(Rgba{width, height, Array.new(U32, Storage.depth((width * height : U32)), 255)}, threshold))

def Surface.alpha_border(surface: Surface, threshold: F32) -> Surface & Rectangle:
  Surface{width, height, +format, pixels} = surface
  Surface.alpha_border.selected(U32.is_eq(format, 9) || U32.is_eq(format, 12), pixels, threshold, width, height, format)

def Surface.alpha_crop.route(empty: Bool, surface: Surface, rect: Rectangle) -> Surface:
  match empty:
    case True{}: surface
    case False{}:
      Surface{sw, _, format, pixels} = surface
      Rectangle{x, y, rw, rh} = rect
      +width = F32.to_u32(rw)
      +height = F32.to_u32(rh)
      Surface.pixels.resampled(width, height, format, Surface.pixels.sample(pixels, (width * height : U32),
        Region{sw, width, F32.to_u32(x), F32.to_u32(y)}))

def Surface.alpha_crop.observed(result: Surface & Rectangle) -> Surface:
  match result:
    case Tuple{surface, Rectangle{+x, +y, +width, +height}}:
      Surface.alpha_crop.route(F32.is_eq(width, 0.0), surface, Rectangle{x, y, width, height})

# ImageAlphaCrop: the alpha border, then a byte-level crop.
def Surface.alpha_crop(surface: Surface, threshold: F32) -> Surface:
  Surface.alpha_crop.observed(Surface.alpha_border(surface, threshold))

def Image.channel.integral(+amount: F32) -> Bool:
  +bits = (F32.bits(amount) .&. 2147483647 : U32)
  (bits < 2139095040 : U32) && (U32.is_eq(bits, 0) || ((bits >= 1065353216 : U32) && F32.is_eq(F32.floor(amount), amount)))

def Image.channel.valid(+selected: F32) -> Bool:
  Image.channel.integral(selected) && (F32.abs(selected) <= 32767.0 : F32)

def Surface.channel.word.read(+format: U32, channel: U32, index: U32, output: Array<U32>, result: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (source, word) = result
  (source, Array.set(U32, output, index, Image.channel.value(channel, Surface.words.normal(format, word))))

def Surface.channel.words(n: Nat, +index: U32, +format: U32, +channel: U32, state: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{source, output}:
      Surface.channel.words(rest, (index + 1 : U32), format, channel, Surface.channel.word.read(format, channel, index, output, Array.get(U32, source, index)))

def Surface.channel.quad.read(+format: U32, channel: U32, index: U32, output: Array<U32>, result: Array<Surface.Quad> & Surface.Quad) -> Array<Surface.Quad> & Array<U32>:
  (source, quad) = result
  (source, Array.set(U32, output, index, Image.channel.value(channel, Surface.quad.normal(format, quad))))

def Surface.channel.quads(n: Nat, +index: U32, +format: U32, +channel: U32, state: Array<Surface.Quad> & Array<U32>) -> Array<Surface.Quad> & Array<U32>:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{source, output}:
      Surface.channel.quads(rest, (index + 1 : U32), format, channel, Surface.channel.quad.read(format, channel, index, output, Array.get(Surface.Quad, source, index)))

def Surface.channel.words.finished(+width: U32, +height: U32, format: U32, result: Array<U32> & Array<U32>) -> Surface & Maybe<Surface>:
  (source, pixels) = result
  (Surface{width, height, format, Words{source}}, Some{Surface{width, height, 1, Words{pixels}}})

def Surface.channel.quads.finished(+width: U32, +height: U32, format: U32, result: Array<Surface.Quad> & Array<U32>) -> Surface & Maybe<Surface>:
  (source, pixels) = result
  (Surface{width, height, format, Quads{source}}, Some{Surface{width, height, 1, Words{pixels}}})

# Wide samples convert like LoadImageColors: every channel in finite [0, 1].
def Surface.channel.quads.checked(+width: U32, +height: U32, +format: U32, channel: U32, state: Array<Surface.Quad> & Bool) -> Surface & Maybe<Surface>:
  match state:
    case Tuple{values, False{}}: (Surface{width, height, format, Quads{values}}, None{})
    case Tuple{values, True{}}:
      +count = (width * height : U32)
      Surface.channel.quads.finished(width, height, format, Surface.channel.quads(U32.to_nat(count), 0, format, channel,
        (values, Array.new(U32, Storage.depth(count), 0))))

def Surface.channel.checked(valid: Bool, surface: Surface, selected: F32) -> Surface & Maybe<Surface>:
  match valid surface:
    case False{} _: (surface, None{})
    case True{} Surface{+width, +height, +format, Words{values}}:
      +count = (width * height : U32)
      Surface.channel.words.finished(width, height, format, Surface.channel.words(U32.to_nat(count), 0, format,
        Image.channel.index(format, F32.to_u32(F32.max(0.0, selected))), (values, Array.new(U32, Storage.depth(count), 0))))
    case True{} Surface{+width, +height, +format, Quads{values}}:
      Surface.channel.quads.checked(width, height, format, Image.channel.index(format, F32.to_u32(F32.max(0.0, selected))),
        Surface.quads.checked(U32.to_nat((width * height : U32)), 0, format, False{}, (values, True{})))

# ImageFromChannel: a GRAYSCALE image of one normalized channel; the source is kept.
def Surface.from_channel(surface: Surface, +selected: F32) -> Surface & Maybe<Surface>:
  Surface.channel.checked(Image.channel.valid(selected), surface, selected)

# Raw pixel bytes as raylib stores them (ExportImage ".raw", ExportImageAsCode).
# Wide samples as stored: words a..c (formats 9, 12) or a..d, each 4 bytes for
# F32 formats and 2 bytes for half floats, little-endian.
def Surface.quads.pack.alpha(~q: Quant, four: Bool, +size: Nat, d: U32, bytes: List<q, U32>) -> List<q, U32>:
  match four:
    case True{}: Formats.word_bytes(~q, size, d, bytes)
    case False{}: bytes

def Surface.quads.pack.sample(~q: Quant, +channels: U32, +size: Nat, quad: Surface.Quad, bytes: List<q, U32>) -> List<q, U32>:
  Quad{a, b, c, d} = quad
  Surface.quads.pack.alpha(~q, U32.is_eq(channels, 4), size, d,
    Formats.word_bytes(~q, size, c, Formats.word_bytes(~q, size, b, Formats.word_bytes(~q, size, a, bytes))))

def Surface.quads.pack(~q: Quant, +channels: U32, +size: Nat, values: List<Surface.Quad>, bytes: List<q, U32>) -> List<q, U32>:
  match values:
    case Nil{}: List.reverse(q, U32, bytes)
    case Con{quad, rest}: Surface.quads.pack(~q, channels, size, rest, Surface.quads.pack.sample(~q, channels, size, quad, bytes))

def Surface.raw.selected(~q: Quant, pixels: Surface.Pixels, +width: U32, +height: U32, +format: U32) -> List<q, U32>:
  match pixels:
    case Words{values}:
      Formats.bytes(~q, Image.list.take(~U32, Array.to_list(~U32, Surface.words.native(format, U32.to_nat((width * height : U32)), values)),
        U32.to_nat((width * height : U32))), U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), Nil{})
    case Quads{values}:
      Surface.quads.pack(~q, Bool.pick(U32, U32.is_eq(format, 10) || U32.is_eq(format, 13), 4, 3), Bool.pick(Nat, (format < 11 : U32), 4n, 2n),
        Image.list.take(~Surface.Quad, Array.to_list(~Surface.Quad, values), U32.to_nat((width * height : U32))), Nil{})

def Surface.raw(~q: Quant, surface: Surface) -> List<q, U32>:
  Surface{width, height, format, pixels} = surface
  Surface.raw.selected(~q, pixels, width, height, format)

def Surface.payload.quads(+width: U32, +height: U32, format: U32, state: Array<Surface.Quad> & Bool) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match state:
    case Tuple{values, False{}}: Fail{(Surface{width, height, format, Quads{values}}, OutOfDomain{})}
    case Tuple{values, True{}}: Done{Surface{width, height, format, Quads{values}}}

def Surface.payload.selected(pixels: Surface.Pixels, +width: U32, +height: U32, +format: U32) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  match pixels:
    case Words{values}: Done{Surface{width, height, format, Words{values}}}
    case Quads{values}:
      Surface.payload.quads(width, height, format, Surface.quads.checked(U32.to_nat((width * height : U32)), 0, format, True{}, (values, True{})))

# Owners whose stored words writers accept: every owner except NaN F32 samples.
def Surface.payload.check(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Surface>:
  Surface{width, height, format, pixels} = surface
  Surface.payload.selected(pixels, width, height, format)

# Consumes the owner: dimensions, format and its raw bytes without padding.
def Surface.export(surface: Surface) -> (U32 & U32) & (U32 & List<U32>):
  Surface{+width, +height, +format, pixels} = surface
  ((width, height), (format, Surface.raw(~&1, Surface{width, height, format, pixels})))

def Surface.from_bytes.words(+width: U32, +height: U32, +format: U32, result: Maybe<Array<U32>>) -> Maybe<Surface>:
  match result:
    case None{}: None{}
    case Some{values}: Some{Surface{width, height, format, Words{Surface.words.native(format, U32.to_nat((width * height : U32)), values)}}}

# Wide samples from raw words: channel words a..c (and d) of each pixel in turn.
def Surface.quads.group.write(+channels: U32, i: U32, a: U32, b: U32, c: U32, output: Array<Surface.Quad>, got: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (flat, d) = got
  (flat, Array.set(Surface.Quad, output, i, Quad{a, b, c, Bool.pick(U32, U32.is_eq(channels, 4), d, 0)}))

def Surface.quads.group.c(+channels: U32, +at: U32, i: U32, a: U32, b: U32, output: Array<Surface.Quad>, got: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (flat, c) = got
  Surface.quads.group.write(channels, i, a, b, c, output, Array.get(U32, flat, (at + channels - 1 : U32)))

def Surface.quads.group.b(+channels: U32, +at: U32, i: U32, a: U32, output: Array<Surface.Quad>, got: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (flat, b) = got
  Surface.quads.group.c(channels, at, i, a, b, output, Array.get(U32, flat, (at + 2 : U32)))

def Surface.quads.group.a(+channels: U32, +at: U32, i: U32, output: Array<Surface.Quad>, got: Array<U32> & U32) -> Array<U32> & Array<Surface.Quad>:
  (flat, a) = got
  Surface.quads.group.b(channels, at, i, a, output, Array.get(U32, flat, (at + 1 : U32)))

def Surface.quads.group(n: Nat, +i: U32, +channels: U32, state: Array<U32> & Array<Surface.Quad>) -> Array<Surface.Quad>:
  match n state:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{flat, output}:
      Surface.quads.group(rest, (i + 1 : U32), channels, Surface.quads.group.a(channels, (i * channels : U32), i, output, Array.get(U32, flat, (i * channels : U32))))

def Surface.from_bytes.quads.checked(+width: U32, +height: U32, +format: U32, state: Array<Surface.Quad> & Bool) -> Maybe<Surface>:
  match state:
    case Tuple{_, False{}}: None{}
    case Tuple{values, True{}}: Some{Surface{width, height, format, Quads{values}}}

def Surface.from_bytes.quads(+width: U32, +height: U32, +format: U32, +channels: U32, flat: Maybe<Array<U32>>) -> Maybe<Surface>:
  match flat:
    case None{}: None{}
    case Some{words}:
      +count = (width * height : U32)
      Surface.from_bytes.quads.checked(width, height, format, Surface.quads.checked(U32.to_nat(count), 0, format, True{},
        (Surface.quads.group(U32.to_nat(count), 0, channels, (words, Array.new(Surface.Quad, Storage.depth(count), Surface.quad.zero()))), True{})))

def Surface.from_bytes.stored(wide: Bool, +width: U32, +height: U32, +format: U32, bytes: +List<U32>) -> Maybe<Surface>:
  match wide:
    case True{}:
      +channels = Bool.pick(U32, U32.is_eq(format, 10) || U32.is_eq(format, 13), 4, 3)
      +words = (width * height * channels : U32)
      Surface.from_bytes.quads(width, height, format, channels, Formats.unpack(U32.to_nat(words), 0, Bool.pick(Nat, (format < 11 : U32), 4n, 2n),
        Some{Formats.Input{bytes, Array.new(U32, Storage.depth(words), 0)}}))
    case False{}:
      +count = (width * height : U32)
      Surface.from_bytes.words(width, height, format, Formats.unpack(U32.to_nat(count), 0,
        U32.to_nat((Pixel.bits_per_pixel(format) / 8 : U32)), Some{Formats.Input{bytes, Array.new(U32, Storage.depth(count), 0)}}))

def Surface.from_bytes.validated(valid: Bool, +width: U32, +height: U32, +format: U32, bytes: +List<U32>) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}: Surface.from_bytes.stored(Surface.wide(format), width, height, format, bytes)

def Surface.from_bytes.checked(valid: Bool, +width: U32, +height: U32, +format: U32, +bytes: +List<U32>) -> Maybe<Surface>:
  match valid:
    case False{}: None{}
    case True{}:
      Surface.from_bytes.validated(Formats.valid(bytes, (width * height * (Pixel.bits_per_pixel(format) / 8) : U32), True{})
        && Formats.domain_valid(format, bytes), width, height, format, bytes)

# Owned raw image data (LoadImageRaw bytes): formats 1..13, exactly width*height
# samples; R32 and R16 words must be finite [0, 1] and F32 samples of the wide
# formats must not be NaN (half-float samples are unrestricted).
def Surface.from_bytes(+width: U32, +height: U32, +format: U32, bytes: +List<U32>) -> Maybe<Surface>:
  Surface.from_bytes.checked(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (format >= 1) && (format <= 13) : U32), width, height, format, bytes)

# Base.Image contains RGB colors. Alpha is discarded, not composited.
def Surface.to_image.rgba(result: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, Image>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{image}: Done{Rgba.to_image(image)}

def Surface.to_image(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, Image>:
  Surface.to_image.rgba(Surface.rgba.load(surface))

def Surface.to_ppm.rgba(result: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, String>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{image}: Done{Rgba.to_ppm(image)}

# Portable, inspectable P3 PPM output for headless programs. Alpha is discarded.
def Surface.to_ppm(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, String>:
  Surface.to_ppm.rgba(Surface.rgba.load(surface))

# -----------------------------------------------------------------------------
# Codecs, exporters, writers and loaders

# Codecs. Decoders return raylib's native format for the file (LoadImage).
def Image.codec.error(error: Codec.Error) -> Surface.Error:
  match error:
    case Codec.BadHeader{}: InvalidImageHeader{}
    case Codec.BadByte{}: InvalidImageByte{}
    case Codec.BadSize{}: UnsupportedImageSize{}
    case Codec.Truncated{}: TruncatedImageData{}
    case Codec.BadStream{}: InvalidImageStream{}

def Surface.codec.format(channels: U32) -> U32:
  match channels:
    case 1: 1
    case 2: 2
    case 3: 4
    case _: 7

def Surface.codec.word(channels: U32, +pixel: U32) -> U32:
  match channels:
    case 1: (pixel >> 24n : U32)
    case 2: ((pixel >> 24n) .|. ((pixel .&. 255) << 8n) : U32)
    case _: (Formats.swap(pixel) .&. 16777215 : U32)

def Surface.codec.write(index: U32, channels: U32, read: Array<U32> & U32) -> Array<U32>:
  (pixels, pixel) = read
  Array.set(U32, pixels, index, Surface.codec.word(channels, pixel))

def Surface.codec.pixels(n: Nat, +index: U32, +channels: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: Surface.codec.pixels(rest, (index + 1 : U32), channels, Surface.codec.write(index, channels, Array.get(U32, pixels, index)))

# Codec decoders return canonical RGBA words plus their native output channel
# count (1 gray, 2 gray+alpha, 3 RGB, 4 RGBA). Pack them into raylib's native
# storage with integers: a floating ImageFormat round trip could alter samples.
def Surface.codec.stored(kind: U32, +width: U32, +height: U32, +channels: U32, pixels: Array<U32>) -> Surface:
  match kind:
    case 4: Surface{width, height, 7, Words{pixels}}
    case _: Surface{width, height, Surface.codec.format(channels), Words{Surface.codec.pixels(U32.to_nat((width * height : U32)), 0, channels, pixels)}}

def Surface.codec.result(result: Result<&1, &1, Codec.Error, Codec.Image>) -> Result<&1, &1, Surface.Error, Surface>:
  match result:
    case Fail{error}: Fail{Image.codec.error(error)}
    case Done{Codec.Image{width, height, +channels, pixels}}: Done{Surface.codec.stored(channels, width, height, channels, pixels)}

# QOI channel metadata selects native storage; decoding/cache state stays RGBA.
def Surface.decode_qoi(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Qoi.decode(bytes))

# BMP retains native components from the effective alpha-mask layout. Indexed,
# RGB555 and RGB888 inputs expand to RGB; alpha repair never changes metadata.
def Surface.decode_bmp(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Bmp.decode(bytes))

# TGA carries actual native output channels independently of input sample/index
# width, retaining gray and zero-alpha bytes.
def Surface.decode_tga(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Tga.decode(bytes))

# PNM magic retains native gray/RGB storage after the decoder's 8-bit reduction.
def Surface.decode_pnm(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Pnm.decode(bytes))

# PIC retains native components from the union of validated packet masks.
def Surface.decode_pic(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Pic.decode(bytes))

def Surface.dds.created(result: Maybe<Surface>) -> Result<&1, &1, Surface.Error, Surface>:
  match result:
    case None{}: Fail{UnsupportedImageSize{}}
    case Some{surface}: Done{surface}

def Surface.dds.result(outcome: Dds.Outcome) -> Result<&1, &1, Surface.Error, Surface>:
  match outcome:
    case Dds.Decoded{Dds.Image{width, height, format, data}}: Surface.dds.created(Surface.from_bytes(width, height, format, data))
    case Dds.Unsupported{}: Fail{UnsupportedFormat{}}
    case Dds.Invalid{error}: Fail{Image.codec.error(error)}

# DDS (raylib's rl_load_dds_from_memory): uncompressed single-level R5G6B5,
# A1R5G5B5, A4R4G4B4, 24-bit and 32-bit files in raylib's channel order;
# compressed (DXT) files and mipmap chains are UnsupportedFormat.
def Surface.decode_dds(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.dds.result(Dds.decode(bytes))

# PNG retains native output components from structural color/tRNS metadata.
def Surface.decode_png(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.codec.result(Png.decode(bytes))

def Surface.psd.result(result: Result<&1, &1, Codec.Error, Psd.Image>) -> Result<&1, &1, Surface.Error, Surface>:
  match result:
    case Fail{error}: Fail{Image.codec.error(error)}
    case Done{Psd.Image{width, height, pixels}}: Done{Surface{width, height, 7, Words{pixels}}}

def Surface.decode_psd_for(reference: M.Contraction, bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.psd.result(Psd.decode(M.Contraction.fused(reference), bytes))

def Surface.decode_psd(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.decode_psd_for(M.Uncontracted{}, bytes)

def Surface.gif.result(result: Result<&1, &1, Codec.Error, Gif.Image>) -> Result<&1, &1, Surface.Error, Surface>:
  match result:
    case Fail{error}: Fail{Image.codec.error(error)}
    case Done{Gif.Image{width, height, pixels}}: Done{Surface{width, height, 7, Words{pixels}}}

def Surface.decode_gif(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.gif.result(Gif.decode(bytes))

def Surface.quad.of_vector(value: M.Vector3) -> Surface.Quad:
  M.Vector3{r, g, b} = value
  Quad{F32.bits(r), F32.bits(g), F32.bits(b), 0}

def Surface.hdr.result(result: Result<&1, &1, Codec.Error, Hdr.Image>) -> Result<&1, &1, Surface.Error, Surface>:
  match result:
    case Fail{error}: Fail{Image.codec.error(error)}
    case Done{Hdr.Image{width, height, pixels}}: Done{Surface{width, height, 9, Quads{Array.map(~M.Vector3, ~Surface.Quad, ~Surface.quad.of_vector, pixels)}}}

def Surface.decode_hdr(bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.hdr.result(Hdr.decode(bytes))

def Image.file.raster_selected(reference: M.Contraction, png: Bool, bmp: Bool, pnm: Bool, psd: Bool, pic: Bool, gif: Bool, bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  match png bmp pnm psd pic gif:
    case True{} _ _ _ _ _: Surface.decode_png(bytes)
    case False{} True{} _ _ _ _: Surface.decode_bmp(bytes)
    case False{} False{} True{} _ _ _: Surface.decode_pnm(bytes)
    case False{} False{} False{} True{} _ _: Surface.decode_psd_for(reference, bytes)
    case False{} False{} False{} False{} True{} _: Surface.decode_pic(bytes)
    case False{} False{} False{} False{} False{} True{}: Surface.decode_gif(bytes)
    case False{} False{} False{} False{} False{} False{}: Surface.decode_tga(bytes)

def Image.file.raster(reference: M.Contraction, +bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  match bytes:
    case Con{+a, Con{+b, _}}:
      Image.file.raster_selected(reference, U32.is_eq(a, 137) && U32.is_eq(b, 80), U32.is_eq(a, 66) && U32.is_eq(b, 77),
        U32.is_eq(a, 80) && (U32.is_eq(b, 53) || U32.is_eq(b, 54)), Image.file.psd(bytes), Pic.signature(bytes), Gif.signature(bytes), bytes)
    case _: Surface.decode_tga(bytes)

def Image.file.decode(reference: M.Contraction, kind: Image.FileKind, bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  match kind:
    case QoiFile{}: Surface.decode_qoi(bytes)
    case DdsFile{}: Surface.decode_dds(bytes)
    case RasterFile{}: Image.file.raster(reference, bytes)
    case UnsupportedImageFile{}: Fail{InvalidImageHeader{}}

# LoadImageFromMemory: the file type token selects QOI or the raster signatures.
def Surface.decode_image_for(reference: M.Contraction, file_type: String, bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Image.file.decode(reference, Image.memory.kind(file_type), bytes)

def Surface.decode_image(file_type: String, bytes: +List<U32>) -> Result<&1, &1, Surface.Error, Surface>:
  Surface.decode_image_for(M.Uncontracted{}, file_type, bytes)

# Exporters. ExportImage writes GRAYSCALE, GRAY_ALPHA, R8G8B8 and R8G8B8A8
# samples directly and every other format through LoadImageColors.
def Surface.png.channels(format: U32) -> U32:
  match format:
    case 1: 1
    case 2: 2
    case 4: 3
    case 7: 4
    case _: 0

def Surface.file.png(image: Rgba) -> +List<U32>:
  Rgba{width, height, pixels} = image
  PngEncode.encode(width, height, pixels)

def Surface.file.bmp(image: Rgba) -> +List<U32>:
  Rgba{width, height, pixels} = image
  Bmp.encode(width, height, pixels)

def Surface.file.tga(channels: U32, image: Rgba) -> +List<U32>:
  Rgba{width, height, pixels} = image
  Tga.encode.channels(width, height, channels, pixels)

def Surface.file.direct(kind: U32, +width: U32, +height: U32, +format: U32, values: Array<U32>) -> +List<U32>:
  match kind:
    case 1: PngEncode.formatted(width, height, Surface.png.channels(format), values)
    case _: Bmp.encode24(width, height, format, values)

def Surface.file.encoded(kind: U32, +channels: U32, image: Rgba) -> +List<U32>:
  match kind:
    case 1: Surface.file.png(image)
    case 2: Surface.file.bmp(image)
    case _: Surface.file.tga(channels, image)

def Surface.file.colors(kind: U32, channels: U32, result: Result<&1, &1, Surface & Surface.Error, Rgba>) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{image}: Done{Surface.file.encoded(kind, channels, image)}

def Surface.file.routed(direct: Bool, kind: U32, channels: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match direct surface:
    case True{} Surface{+width, +height, +format, Words{values}}: Done{Surface.file.direct(kind, width, height, format, values)}
    case _ _: Surface.file.colors(kind, channels, Surface.rgba.load(surface))

# BMP: 1..3 components select 24-bit output, four select V4. TGA keeps 1..4
# components after LoadImageColors. Checked dimensions bound every file.
def Surface.file.bytes(+kind: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface{width, height, +format, pixels} = surface
  +channels = Surface.png.channels(format)
  Surface.file.routed(((channels > 0) && (channels < 4) && (kind < 3) : U32), kind,
    Bool.pick(U32, U32.is_eq(channels, 0), 4, channels), Surface{width, height, format, pixels})

def Surface.to_png(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface.file.bytes(1, surface)

def Surface.to_bmp(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface.file.bytes(2, surface)

def Surface.to_tga(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface.file.bytes(3, surface)

def Surface.qoi.channels(format: U32) -> U32:
  match format:
    case 4: 3
    case 7: 4
    case _: 0

def Surface.qoi.colors(kind: U32, +format: U32, count: Nat, values: Array<U32>) -> Array<U32>:
  match kind:
    case 7: values
    case _: Formats.packed_colors(count, 0, format, values)

def Surface.qoi.checked(valid: Bool, +channels: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match valid surface:
    case True{} Surface{+width, +height, +format, Words{values}}:
      Done{Qoi.encode.channels(width, height, channels, Surface.qoi.colors(format, format, U32.to_nat((width * height : U32)), values))}
    case _ _: Fail{(surface, UnsupportedFormat{})}

# ExportImage's QOI branch accepts only R8G8B8 and R8G8B8A8; R8G8B8 is opaque.
def Surface.to_qoi(surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface{width, height, +format, pixels} = surface
  +channels = Surface.qoi.channels(format)
  Surface.qoi.checked((channels > 0 : U32), channels, Surface{width, height, format, pixels})

def Surface.memory.channels(format: U32) -> U32:
  match format:
    case 8: 4
    case 9: 4
    case 10: 4
    case 12: 4
    case 13: 4
    case _: Surface.png.channels(format)

def Surface.memory.packed(+width: U32, +height: U32, words: Maybe<Array<U32>>) -> +List<U32>:
  match words:
    case None{}: Nil{}
    case Some{values}: PngEncode.formatted(width, height, 4, values)

# The first width*height*4 stored bytes, read as RGBA words.
def Surface.memory.quads(+width: U32, +height: U32, +format: U32, values: Array<Surface.Quad>) -> +List<U32>:
  +count = (width * height : U32)
  Surface.memory.packed(width, height, Formats.unpack(U32.to_nat(count), 0, 4n,
    Some{Formats.Input{Surface.raw(~&2, Surface{width, height, format, Quads{values}}), Array.new(U32, Storage.depth(count), 0)}}))

def Surface.memory.words(+width: U32, +height: U32, format: U32, +channels: U32, values: Array<U32>) -> +List<U32>:
  match format:
    case 7: PngEncode.encode(width, height, values)
    case _: PngEncode.formatted(width, height, channels, values)

def Surface.memory.checked(valid: Bool, +channels: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match valid surface:
    case False{} _: Fail{(surface, UnsupportedFormat{})}
    case True{} Surface{+width, +height, +format, Words{values}}: Done{Surface.memory.words(width, height, format, channels, values)}
    case True{} Surface{+width, +height, +format, Quads{values}}: Done{Surface.memory.quads(width, height, format, values)}

def Surface.memory.typed(png: Bool, +channels: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match png:
    case False{}: Fail{(surface, UnsupportedFileType{})}
    case True{}: Surface.memory.checked((channels > 0 : U32), channels, surface)

# ExportImageToMemory (".png" only) hands stbi the raw storage with four
# components for every format other than GRAYSCALE, GRAY_ALPHA and R8G8B8:
# R32 and R32G32B32 bytes are read as RGBA, the 16-bit formats would overread.
def Surface.memory.payload(png: Bool, result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{Surface{width, height, +format, pixels}}:
      Surface.memory.typed(png, Surface.memory.channels(format), Surface{width, height, format, pixels})

def Surface.export_to_memory(surface: Surface, +file_type: String) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  Surface.memory.payload(String.eq(file_type, ".png") || String.eq(file_type, ".PNG"), Surface.payload.check(surface))

def Surface.code.exported(name: String, size: U32, result: (U32 & U32) & (U32 & List<U32>)) -> String:
  ((width, height), (format, bytes)) = result
  ImageCode.encode(~&1, name, width, height, format, size, bytes)

def Surface.code.checked(valid: Bool, name: Maybe<&2, String>, size: U32, surface: Surface) -> Result<&1, &1, Surface & Surface.Error, String>:
  match valid name:
    case True{} Some{text}: Done{Surface.code.exported(text, size, Surface.export(surface))}
    case _ _: Fail{(surface, InvalidRequest{})}

def Surface.code.payload(path: String, result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, Surface & Surface.Error, String>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{Surface{+width, +height, +format, pixels}}:
      +size = (width * height * (Pixel.bits_per_pixel(format) / 8) : U32)
      Surface.code.checked((size <= 65536 : U32), ImageCode.name(path), size, Surface{width, height, format, pixels})

# ExportImageAsCode: raw bytes up to 64 KiB, named from the path.
def Surface.to_code(surface: Surface, path: String) -> Result<&1, &1, Surface & Surface.Error, String>:
  Surface.code.payload(path, Surface.payload.check(surface))

# Writers: one file, closed before the status returns; rejected owners come back.
def Surface.write.written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{FileError{code, message}})
    case Done{unit}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Done{unit})

def Surface.write.bytes(path: String, result: Result<&1, &1, Surface & Surface.Error, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match result:
    case Fail{Tuple{surface, error}}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{SourceError{surface, error}})
    case Done{bytes}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Surface.IOError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Image.file.write.opened(bytes)),
        Surface.write.written)

def Surface.write.text(path: String, result: Result<&1, &1, Surface & Surface.Error, String>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match result:
    case Fail{Tuple{surface, error}}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{SourceError{surface, error}})
    case Done{text}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Surface.IOError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Image.file.write_text.opened(text)),
        Surface.write.written)

def Surface.write_png(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.bytes(path, Surface.to_png(surface))

def Surface.write_bmp(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.bytes(path, Surface.to_bmp(surface))

def Surface.write_tga(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.bytes(path, Surface.to_tga(surface))

def Surface.write_qoi(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.bytes(path, Surface.to_qoi(surface))

def Surface.raw.payload(result: Result<&1, &1, Surface & Surface.Error, Surface>) -> Result<&1, &1, Surface & Surface.Error, +List<U32>>:
  match result:
    case Fail{failure}: Fail{failure}
    case Done{surface}: Done{Surface.raw(~&2, surface)}

def Surface.write_raw(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.bytes(path, Surface.raw.payload(Surface.payload.check(surface)))

def Surface.write_code(surface: Surface, +path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.text(path, Surface.to_code(surface, path))

def Surface.write_ppm(surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.text(path, Surface.to_ppm(surface))

def Surface.write.kind(kind: U32, surface: Surface, path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match kind:
    case 1: Surface.write_png(surface, path)
    case 2: Surface.write_bmp(surface, path)
    case 3: Surface.write_tga(surface, path)
    case 4: Surface.write_qoi(surface, path)
    case 5: Surface.write_raw(surface, path)
    case _: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{SourceError{surface, UnsupportedFileType{}}})

# ExportImage: the ASCII-insensitive suffix selects PNG, BMP, TGA, QOI or raw bytes.
def Surface.write_image(surface: Surface, +path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Surface.write.kind(Image.export.kind(path), surface, path)

# Animations: GIF frames are R8G8B8A8; other files load one native frame.
def Image.Animation.gif.frames(frames: List<Gif.Image>, values: List<Surface>) -> List<Surface>:
  match frames:
    case Nil{}: List.reverse(&1, Surface, values)
    case Con{Gif.Image{width, height, pixels}, rest}: Image.Animation.gif.frames(rest, Con{Surface{width, height, 7, Words{pixels}}, values})

def Image.Animation.gif.result(result: Result<&1, &1, Codec.Error, GifAnimation.Animation>) -> Result<&1, &1, Surface.Error, Image.Animation>:
  match result:
    case Fail{error}: Fail{Image.codec.error(error)}
    case Done{GifAnimation.Animation{width, height, count, frames}}: Done{Animation{width, height, count, Image.Animation.gif.frames(frames, Nil{})}}

def Image.Animation.decode_gif(bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Surface.Error, Image.Animation>:
  Image.Animation.gif.result(GifAnimation.decode(bytes, maximum_frames, maximum_pixels))

def Image.Animation.entries(animation: Image.Animation) -> U32 & U32 & U32 & List<Surface>:
  Animation{width, height, count, frames} = animation
  (width, height, count, frames)

def Image.Animation.unload(animation: Image.Animation) -> Unit:
  Unit{}

def Image.Animation.single.sized(valid: Bool, +width: U32, +height: U32, surface: Surface) -> Result<&1, &1, Surface.Error, Image.Animation>:
  match valid:
    case False{}: Fail{UnsupportedImageSize{}}
    case True{}: Done{Animation{width, height, 1, Con{surface, Nil{}}}}

def Image.Animation.single.decoded(maximum_pixels: U32, result: Result<&1, &1, Surface.Error, Surface>) -> Result<&1, &1, Surface.Error, Image.Animation>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Surface{+width, +height, format, pixels}}:
      Image.Animation.single.sized((width * height <= maximum_pixels : U32), width, height, Surface{width, height, format, pixels})

def Image.Animation.memory.checked(valid: Bool, reference: M.Contraction, file_type: String, bytes: +List<U32>, maximum_pixels: U32) -> Result<&1, &1, Surface.Error, Image.Animation>:
  match valid:
    case False{}: Fail{UnsupportedImageSize{}}
    case True{}: Image.Animation.single.decoded(maximum_pixels, Surface.decode_image_for(reference, file_type, bytes))

def Image.Animation.memory.selected(gif: Bool, reference: M.Contraction, file_type: String, bytes: +List<U32>, maximum_frames: U32, +maximum_pixels: U32) -> Result<&1, &1, Surface.Error, Image.Animation>:
  match gif:
    case True{}: Image.Animation.decode_gif(bytes, maximum_frames, maximum_pixels)
    case False{}: Image.Animation.memory.checked(((maximum_frames > 0) && (maximum_pixels > 0) && (maximum_pixels <= 16777216) : U32), reference, file_type, bytes, maximum_pixels)

def Image.Animation.decode_image_for(reference: M.Contraction, +file_type: String, bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Surface.Error, Image.Animation>:
  Image.Animation.memory.selected(String.eq(file_type, ".gif") || String.eq(file_type, ".GIF"), reference, file_type, bytes, maximum_frames, maximum_pixels)

def Image.Animation.decode_image(file_type: String, bytes: +List<U32>, maximum_frames: U32, maximum_pixels: U32) -> Result<&1, &1, Surface.Error, Image.Animation>:
  Image.Animation.decode_image_for(M.Uncontracted{}, file_type, bytes, maximum_frames, maximum_pixels)

# Loaders read a bounded, complete file and close it before decoding.
def Image.file.surface(reference: M.Contraction, kind: Image.FileKind, result: Result<&1, &1, Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Image.file.decoded(Surface, Image.file.decode(reference, kind, bytes)))

def Image.file.load(reference: M.Contraction, +kind: Image.FileKind, path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  IO.bind(Result<&1, &1, Surface.IOError, +List<U32>>, Result<&1, &1, Surface.IOError, Surface>,
    Image.file.bytes(path, Image.file.limit(kind)), Image.file.surface(reference, kind))

# LoadImage: the path suffix selects QOI or the raster signatures.
def Surface.load_image_for(reference: M.Contraction, +path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Image.file.load(reference, Image.file.kind(path), path)

def Surface.load_image(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_image_for(M.Uncontracted{}, path)

def Surface.load.decoded(~decode: +List<U32> -> Result<&1, &1, Surface.Error, Surface>, result: Result<&1, &1, Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Image.file.decoded(Surface, decode(bytes)))

# Explicit codec selection shares the bounded, complete, close-before-decode
# file boundary. The decoder is a parameter so a program links only its codec.
def Surface.load_with(~decode: +List<U32> -> Result<&1, &1, Surface.Error, Surface>, limit: U32, path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  IO.bind(Result<&1, &1, Surface.IOError, +List<U32>>, Result<&1, &1, Surface.IOError, Surface>,
    Image.file.bytes(path, limit), Surface.load.decoded(~decode))

def Surface.load_qoi(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_qoi, Image.file.limit(QoiFile{}), path)

def Surface.load_dds(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_dds, Image.file.limit(DdsFile{}), path)

def Surface.load_png(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_png, Image.file.limit(RasterFile{}), path)

def Surface.load_bmp(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_bmp, Image.file.limit(RasterFile{}), path)

def Surface.load_tga(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_tga, Image.file.limit(RasterFile{}), path)

def Surface.load_pnm(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_pnm, Image.file.limit(RasterFile{}), path)

def Surface.load_pic(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_pic, Image.file.limit(RasterFile{}), path)

def Surface.load_hdr(path: String) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Surface.load_with(~Surface.decode_hdr, Image.file.limit(RasterFile{}), path)

def Image.Animation.file.token(+suffix: String) -> String:
  Bool.pick(String, String.eq(String.to_lower(suffix), ".gif"), ".gif", suffix)

def Image.Animation.file.loaded(reference: M.Contraction, token: String, maximum_frames: U32, maximum_pixels: U32, result: Result<&1, &1, Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, Image.Animation>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Surface.IOError, Image.Animation>, Fail{error})
    case Done{bytes}:
      IO.pure(Result<&1, &1, Surface.IOError, Image.Animation>, Image.file.decoded(Image.Animation,
        Image.Animation.decode_image_for(reference, token, bytes, maximum_frames, maximum_pixels)))

def Image.Animation.load_image_for(reference: M.Contraction, +path: String, maximum_frames: U32, maximum_pixels: U32) -> IO(Result<&1, &1, Surface.IOError, Image.Animation>):
  +token = Image.Animation.file.token(Image.file.token(path))
  IO.bind(Result<&1, &1, Surface.IOError, +List<U32>>, Result<&1, &1, Surface.IOError, Image.Animation>,
    Image.file.bytes(path, Image.file.limit(Image.memory.kind(token))), Image.Animation.file.loaded(reference, token, maximum_frames, maximum_pixels))

def Image.Animation.load_image(path: String, maximum_frames: U32, maximum_pixels: U32) -> IO(Result<&1, &1, Surface.IOError, Image.Animation>):
  Image.Animation.load_image_for(M.Uncontracted{}, path, maximum_frames, maximum_pixels)

# Called only after checked request parameters, a complete read and handle closure.
# A failed factory here therefore identifies unsupported sample values.
def Image.raw.decoded(result: Maybe<Surface>) -> Result<&1, &1, Surface.IOError, Surface>:
  match result:
    case None{}: Fail{DataError{OutOfDomain{}}}
    case Some{surface}: Done{surface}

def Image.raw.surface(width: U32, height: U32, format: U32, result: Result<&1, &1, Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Image.raw.decoded(Surface.from_bytes(width, height, format, bytes)))

def Image.raw.parameters(valid: Bool, path: String, +width: U32, +height: U32, +format: U32, +header: U32) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Surface.IOError, Surface>, Fail{DataError{InvalidRequest{}}})
    case True{}:
      needed = (width * height * (Pixel.bits_per_pixel(format) / 8) : U32)
      IO.bind(Result<&1, &1, Surface.IOError, +List<U32>>, Result<&1, &1, Surface.IOError, Surface>,
        Image.raw.bytes(path, header, needed), Image.raw.surface(width, height, format))

# LoadImageRaw: formats 1..13; a header is skipped only when the file holds it
# and the samples.
def Surface.load_raw(path: String, +width: U32, +height: U32, +format: U32, header_size: U32) -> IO(Result<&1, &1, Surface.IOError, Surface>):
  Image.raw.parameters(((width > 0) && (height > 0) && (width <= 4096) && (height <= 4096)
    && (format >= 1) && (format <= 13) : U32), path, width, height, format, header_size)

# -----------------------------------------------------------------------------
# Files: rcore.c path and file-data utilities
#
# Paths are byte strings in raylib; ASCII paths compare byte for byte here.
# Results raylib computes in fixed static buffers are None where the C code
# would read past the input or overflow the buffer.

def Files.slash(+character: Char) -> Bool:
  U32.is_eq(Char.to_u32(character), 47) || U32.is_eq(Char.to_u32(character), 92)

# One past the last '/' or '\\' (strprbrk), or 0 when there is none.
def Files.after_slash(path: String, +position: Nat, after: Nat) -> Nat:
  match path:
    case SNil{}: after
    case SCon{+character, rest}: Files.after_slash(rest, 1n+position, Bool.pick(Nat, Files.slash(character), 1n+position, after))

# GetFileExtension: from the last '.' of the whole path, unless there is none
# or it is the first character.
def Files.extension(+path: String) -> Maybe<String>:
  +position = Image.file.last_dot(path, 0n, 0n)
  Bool.pick(Maybe<String>, Nat.is_lt(0n, position), Some{String.drop(path, position)}, None{})

# GetFileName: the text after the last separator.
def Files.name(+path: String) -> String:
  String.drop(path, Files.after_slash(path, 0n, 0n))

# GetFileNameWithoutExt: the name (at most 255 bytes) cut at its last '.' past
# the first character.
def Files.name_without_ext(path: String) -> String:
  +name = String.take(Files.name(path), 255n)
  +position = Image.file.last_dot(name, 0n, 0n)
  Bool.pick(String, Nat.is_lt(0n, position), String.take(name, position), name)

def Files.code.of(found: Maybe<&2, Char>) -> U32:
  match found:
    case None{}: 0
    case Some{character}: Char.to_u32(character)

def Files.code(+path: String, index: Nat) -> U32:
  Files.code.of(String.get(path, index))

# A path without a drive letter ("C:") or a leading separator.
def Files.relative(+path: String) -> Bool:
  Bool.not(U32.is_eq(Files.code(path, 1n), 58) || U32.is_eq(Files.code(path, 0n), 92) || U32.is_eq(Files.code(path, 0n), 47))

def Files.directory.found(+path: String, +after: Nat) -> String:
  +prefix = Bool.pick(String, Files.relative(path), "./", "")
  Bool.pick(String, Nat.is_eq(after, 0n), prefix,
    Bool.pick(String, Nat.is_eq(after, 1n), String.take(path, 1n), prefix ++ String.take(path, Nat.sub(after, 1n))))

# GetDirectoryPath: "./" before relative paths, the path up to its last separator
# ("/" or "\\" alone for a root file). Paths of 1..4093 bytes fit its buffer.
def Files.directory(+path: String) -> Maybe<String>:
  +length = String.length(path)
  Bool.pick(Maybe<String>, Nat.is_lt(0n, length) && Nat.is_le(length, 4093n),
    Some{Files.directory.found(path, Files.after_slash(path, 0n, 0n))}, None{})

def Files.previous.cut(+path: String, +after: Nat) -> String:
  +slash = Nat.sub(after, 1n)
  +root = Nat.is_eq(slash, 0n) || (Nat.is_eq(slash, 2n) && U32.is_eq(Files.code(path, 1n), 58))
  Bool.pick(String, Nat.is_eq(after, 0n), "", String.take(path, Bool.pick(Nat, root, after, slash)))

# GetPrevDirectoryPath: paths of up to 3 bytes unchanged; otherwise the path up
# to its last separator, keeping a root "/" or "C:\\". Paths up to 4096 bytes.
def Files.previous_directory(+path: String) -> Maybe<String>:
  +length = String.length(path)
  Bool.pick(Maybe<String>, Nat.is_le(length, 4096n),
    Some{Bool.pick(String, Nat.is_le(length, 3n), path, Files.previous.cut(path, Files.after_slash(path, 0n, 0n)))}, None{})

def Files.lower(+character: Char) -> Char:
  +code = Char.to_u32(character)
  Bool.pick(Char, ((code >= 65) && (code <= 90) : U32), Char.from_u32((code + 32 : U32)), character)

def Files.lowered(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{character, rest}: Files.lowered(rest, SCon{Files.lower(character), reversed})

# The ';'-separated extension list: at most 31 entries, the last keeping any
# further separators.
def Files.extensions.limited(+pieces: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Nat.is_le(List.length(&2, String, pieces), 31n), pieces,
    List.append(&2, String, List.take(&2, String, pieces, 30n), [String.join(List.drop(&2, String, pieces, 30n), ";")]))

def Files.extensions(text: String) -> List<&2, String>:
  Files.extensions.limited(String.split(text, ';'))

def Files.extension.matches(+extension: String, entries: List<&2, String>) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{+entry, rest}:
      +dotted = U32.is_eq(Files.code(entry, 0n), 46)
      String.eq(Bool.pick(String, dotted, extension, String.drop(extension, 1n)), entry) || Files.extension.matches(extension, rest)

def Files.has_extension.found(found: Maybe<String>, +extensions: String) -> Maybe<Bool>:
  match found:
    case None{}: Some{False{}}
    case Some{+extension}:
      Bool.pick(Maybe<Bool>, Nat.is_lt(String.length(extension), 16n),
        Some{Files.extension.matches(Files.lowered(extension, ""), Files.extensions(Files.lowered(extensions, "")))}, None{})

# IsFileExtension: ASCII-case-insensitive match of GetFileExtension against a
# ';'-separated list (entries without a leading '.' compare without it). File
# extensions of 16+ bytes overflow raylib's buffer: None.
def Files.has_extension(path: String, extensions: String) -> Maybe<Bool>:
  Files.has_extension.found(Files.extension(path), extensions)

def Files.valid_name.scan(name: String, periods: Bool) -> Bool:
  match name:
    case SNil{}: Bool.not(periods)
    case SCon{+character, rest}:
      +code = Char.to_u32(character)
      +invalid = (code < 32 : U32) || U32.is_eq(code, 60) || U32.is_eq(code, 62) || U32.is_eq(code, 58) || U32.is_eq(code, 34)
        || U32.is_eq(code, 47) || U32.is_eq(code, 92) || U32.is_eq(code, 124) || U32.is_eq(code, 63) || U32.is_eq(code, 42)
      Bool.not(invalid) && Files.valid_name.scan(rest, periods && U32.is_eq(code, 46))

# IsFileNameValid: an empty name is valid; otherwise no <>:"/\\|?* or control
# characters and not only periods.
def Files.valid_name(+name: String) -> Bool:
  Bool.pick(Bool, String.is_empty(name), True{}, Files.valid_name.scan(name, True{}))

# File data. Reads close their handle before returning; the byte domain is 0..255.
def Files.exists.opened(opened: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match opened:
    case Fail{_}: IO.pure(Bool, False{})
    case Done{file}:
      do IO<Bool>:
        Unit <- File.close(file)
        IO.pure(Bool, True{})

# FileExists: the path opens for reading (raylib asks access(), which also
# accepts unreadable files).
def Files.exists(path: String) -> IO(Bool):
  IO.bind(Result<&1, &1, U32 & String, File>, Bool, File.open(path, "r"), Files.exists.opened)

def Files.length.value(size: Result<&1, &1, U32 & String, U32>) -> U32:
  match size:
    case Fail{_}: 0
    case Done{value}: value

def Files.length.sized(result: File & Result<&1, &1, U32 & String, U32>) -> IO(U32):
  (file, size) = result
  do IO<U32>:
    Unit <- File.close(file)
    IO.pure(U32, Files.length.value(size))

def Files.length.opened(opened: Result<&1, &1, U32 & String, File>) -> IO(U32):
  match opened:
    case Fail{_}: IO.pure(U32, 0)
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, U32>, U32, File.size(file), Files.length.sized)

# GetFileLength: the size in bytes, 0 when the file does not open.
def Files.length(path: String) -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, File>, U32, File.open(path, "r"), Files.length.opened)

# LoadFileData: every byte of the file (up to raylib's INT_MAX size).
def Files.load_data(path: String) -> IO(Result<&1, &1, Surface.IOError, +List<U32>>):
  Image.file.bytes(path, 2147483647)

def Files.unload_data(bytes: +List<U32>) -> Unit:
  Unit{}

def Files.saved(result: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{FileError{code, message}})
    case Done{_}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Done{Unit{}})

def Files.save.checked(valid: Bool, path: String, bytes: +List<U32>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match valid:
    case False{}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{DataError{InvalidRequest{}}})
    case True{}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Result<&1, &1, Surface.IOError, Unit>,
        IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), Image.file.write.opened(bytes)), Files.saved)

# SaveFileData: writes every byte (values above 255 are InvalidRequest, before opening).
def Files.save_data(path: String, +bytes: +List<U32>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Files.save.checked(Codec.valid_bytes(bytes, True{}), path, bytes)

def Files.text.chars(bytes: +List<U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case Con{byte, rest}: Files.text.chars(rest, SCon{Char.from_u32(byte), reversed})

def Files.text.loaded(result: Result<&1, &1, Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, Surface.IOError, String>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Surface.IOError, String>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, Surface.IOError, String>, Done{Files.text.chars(bytes, "")})

# LoadFileText: the file's bytes as characters 0..255 (text and binary modes
# agree on the reference hosts).
def Files.load_text(path: String) -> IO(Result<&1, &1, Surface.IOError, String>):
  IO.bind(Result<&1, &1, Surface.IOError, +List<U32>>, Result<&1, &1, Surface.IOError, String>, Files.load_data(path), Files.text.loaded)

def Files.unload_text(text: String) -> Unit:
  Unit{}

# strstr: the first index where search starts (an empty search matches at 0).
def Files.find(text: String, found: Bool, +search: String, +index: U32) -> Maybe<U32>:
  match text found:
    case _ True{}: Some{index}
    case SNil{} False{}: None{}
    case SCon{_, +rest} False{}: Files.find(rest, String.starts_with(rest, search), search, (index + 1 : U32))

def Files.push.unless(stop: Bool, character: Char, reversed: String) -> String:
  match stop:
    case True{}: reversed
    case False{}: SCon{character, reversed}

# C strings end at the first NUL.
def Files.until_nul(text: String, stop: Bool, reversed: String) -> String:
  match text stop:
    case _ True{}: String.reverse(reversed)
    case SNil{} False{}: String.reverse(reversed)
    case SCon{+character, rest} False{}:
      Files.until_nul(rest, U32.is_eq(Char.to_u32(character), 0), Files.push.unless(U32.is_eq(Char.to_u32(character), 0), character, reversed))

# fprintf("%s") stops at the first NUL; characters above 255 are not bytes.
def Files.text.bytes(text: String, reversed: +List<U32>, valid: Bool) -> +List<U32> & Bool:
  match text:
    case SNil{}: (List.reverse(&2, U32, reversed), valid)
    case SCon{+character, rest}:
      Files.text.bytes(rest, Con{Char.to_u32(character), reversed}, valid && (Char.to_u32(character) <= 255 : U32))

def Files.save_text.checked(path: String, encoded: +List<U32> & Bool) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  (bytes, valid) = encoded
  Files.save.checked(valid, path, bytes)

# SaveFileText: the text up to its first NUL as bytes (characters above 255 are
# InvalidRequest, before opening).
def Files.save_text(path: String, text: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Files.save_text.checked(path, Files.text.bytes(Files.until_nul(text, False{}, ""), Nil{}, True{}))

def Files.found(+text: String, +search: String) -> Maybe<U32>:
  Files.find(text, String.starts_with(text, search), search, 0)

def Files.find.loaded(+search: String, result: Result<&1, &1, Surface.IOError, String>) -> IO(Maybe<U32>):
  match result:
    case Fail{_}: IO.pure(Maybe<U32>, None{})
    case Done{+text}: IO.pure(Maybe<U32>, Bool.pick(Maybe<U32>, String.is_empty(text), None{}, Files.found(Files.until_nul(text, False{}, ""), search)))

# FileTextFindIndex: the byte index of the first occurrence of search in the
# file's text (up to a NUL), None when absent or the file is missing; an empty
# file, which raylib would scan through a NULL text, is None.
def Files.text_find_index(path: String, +search: String) -> IO(Maybe<U32>):
  IO.bind(Result<&1, &1, Surface.IOError, String>, Maybe<U32>, Files.load_text(path), Files.find.loaded(search))

def Files.code.text(name: Maybe<&2, String>, +size: U32, bytes: +List<U32>) -> Maybe<String>:
  match name:
    case None{}: None{}
    case Some{symbol}: Some{ImageCode.data.encode(~&2, symbol, size, bytes)}

# ExportDataAsCode text: 1..1048576 bytes 0..255 and an ASCII basename of
# 1..200 characters; None otherwise.
def Files.data_as_code(+bytes: +List<U32>, path: String) -> Maybe<String>:
  +size = U32.from_nat(Codec.byte_count(bytes, 0n))
  Bool.pick(Maybe<String>, ((size >= 1) && (size <= 1048576) : U32) && Codec.valid_bytes(bytes, True{}),
    Files.code.text(ImageCode.data.name(path), size, bytes), None{})

def Files.export.text(path: String, text: Maybe<String>) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  match text:
    case None{}: IO.pure(Result<&1, &1, Surface.IOError, Unit>, Fail{DataError{InvalidRequest{}}})
    case Some{code}: Files.save_text(path, code)

# ExportDataAsCode: the generated header written to path.
def Files.export_data_as_code(bytes: +List<U32>, +path: String) -> IO(Result<&1, &1, Surface.IOError, Unit>):
  Files.export.text(path, Files.data_as_code(bytes, path))
