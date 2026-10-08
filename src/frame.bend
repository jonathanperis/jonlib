# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of rlsw.h 1.5 as pinned raylib 6.0 vendors it
# (src/external/rlsw.h, Copyright (c) 2025-2026 Le Juez Victor, MIT;
# LICENSES/rlsw.txt) and of the rlgl.h OpenGL 1.1 immediate path that drives
# it (zlib; LICENSES/raylib.txt): the projection and modelview stacks and
# their matrix products, vertex transform, face culling, Sutherland-Hodgman and
# Liang-Barsky clipping (with the scissor planes), projection, the
# axis-aligned quad, scanline triangle and line rasterizers, nearest and
# bilinear REPEAT sampling of the shapes texture and of user textures,
# SRC_ALPHA/ONE_MINUS_SRC_ALPHA blending, ClearBackground's scissored fill,
# render-texture framebuffers and the texture and framebuffer id pools, scalar
# and uncontracted (RLSW_USE_SIMD_INTRINSICS off, -ffp-contract=off).
#
# Where rlsw would reach undefined behavior (float-to-int conversions out of
# range or of NaN, out-of-range pixel stores or texel reads, uint8 stores of
# values outside (-1, 256)), the canvas is marked undefined instead. A few
# defined but pathological cases are refused the same way: converted raster
# coordinates beyond 2^24 and rows or columns outside the framebuffer (they
# only arise from clipping round-off on huge inputs). See docs/FRAME.md.
import Base
import ./frame_font.bend as Font

# -----------------------------------------------------------------------------
# Constants and scalar helpers

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# SW_INV_255 (0.00392156862745098f)
def inv255() -> F32:
  float(998277249)

# SW_CLIP_EPSILON (1e-4f)
def clip_epsilon() -> F32:
  float(953267991)

# The triangle rasterizer's height threshold (1e-6f)
def height_epsilon() -> F32:
  float(897988541)

def fract(+x: F32) -> F32:
  (x - F32.floor(x) : F32)

# A C (int) conversion of a raster coordinate: refused beyond 2^24 or NaN.
def raster_int.valid(+x: F32) -> Bool:
  (x >= F32.neg(16777216.0) : F32) && (x <= 16777216.0 : F32)

def lut(+byte: U32) -> F32:
  (U32.to_f32(byte) * inv255() : F32)

# -----------------------------------------------------------------------------
# Vertices, matrices and attributes

# sw_vertex_t: clip/screen position, color and texture coordinates.
type Vertex is Data:
  Vertex{x: F32, y: F32, z: F32, w: F32, r: F32, g: F32, b: F32, a: F32, u: F32, v: F32}

# A matrix in rlsw's float[16] order (m0..m3 is the first column).
type Matrix4 is Data:
  Matrix4{m0: F32, m1: F32, m2: F32, m3: F32, m4: F32, m5: F32, m6: F32, m7: F32,
    m8: F32, m9: F32, m10: F32, m11: F32, m12: F32, m13: F32, m14: F32, m15: F32}

# Interpolated color and texture coordinates of a pixel, or their step.
type Attr is Data:
  Attr{r: F32, g: F32, b: F32, a: F32, u: F32, v: F32}

# Perspective-space accumulators of a triangle span (w, color, texcoord).
type Span is Data:
  Span{w: F32, r: F32, g: F32, b: F32, a: F32, u: F32, v: F32}

def Vertex.x(+v: Vertex) -> F32:
  Vertex{x, _, _, _, _, _, _, _, _, _} = v
  x

def Vertex.y(+v: Vertex) -> F32:
  Vertex{_, y, _, _, _, _, _, _, _, _} = v
  y

def Vertex.w(+v: Vertex) -> F32:
  Vertex{_, _, _, w, _, _, _, _, _, _} = v
  w

def Vertex.with_y(+v: Vertex, +row: F32) -> Vertex:
  Vertex{x, _, z, w, r, g, b, a, u, t} = v
  Vertex{x, row, z, w, r, g, b, a, u, t}

# sw_lerp_vertex_PCT
def Vertex.lerp(a: Vertex, b: Vertex, +t: F32) -> Vertex:
  Vertex{ax, ay, az, aw, ar, ag, ab, aa, au, av} = a
  Vertex{bx, by, bz, bw, br, bg, bb, ba, bu, bv} = b
  +s = (1.0 - t : F32)
  Vertex{(ax * s + bx * t : F32), (ay * s + by * t : F32), (az * s + bz * t : F32), (aw * s + bw * t : F32),
    (ar * s + br * t : F32), (ag * s + bg * t : F32), (ab * s + bb * t : F32), (aa * s + ba * t : F32),
    (au * s + bu * t : F32), (av * s + bv * t : F32)}

# sw_get_vertex_grad_PCT: (b - a)*scale
def Vertex.grad(a: Vertex, b: Vertex, +k: F32) -> Vertex:
  Vertex{ax, ay, az, aw, ar, ag, ab, aa, au, av} = a
  Vertex{bx, by, bz, bw, br, bg, bb, ba, bu, bv} = b
  Vertex{((bx - ax) * k : F32), ((by - ay) * k : F32), ((bz - az) * k : F32), ((bw - aw) * k : F32),
    ((br - ar) * k : F32), ((bg - ag) * k : F32), ((bb - ab) * k : F32), ((ba - aa) * k : F32),
    ((bu - au) * k : F32), ((bv - av) * k : F32)}

# sw_add_vertex_grad_PCT
def Vertex.add(a: Vertex, d: Vertex) -> Vertex:
  Vertex{ax, ay, az, aw, ar, ag, ab, aa, au, av} = a
  Vertex{dx, dy, dz, dw, dr, dg, db, da, du, dv} = d
  Vertex{(ax + dx : F32), (ay + dy : F32), (az + dz : F32), (aw + dw : F32), (ar + dr : F32), (ag + dg : F32),
    (ab + db : F32), (aa + da : F32), (au + du : F32), (av + dv : F32)}

# sw_add_vertex_grad_scaled_PCT
def Vertex.add_scaled(a: Vertex, d: Vertex, +k: F32) -> Vertex:
  Vertex{ax, ay, az, aw, ar, ag, ab, aa, au, av} = a
  Vertex{dx, dy, dz, dw, dr, dg, db, da, du, dv} = d
  Vertex{(ax + dx * k : F32), (ay + dy * k : F32), (az + dz * k : F32), (aw + dw * k : F32), (ar + dr * k : F32),
    (ag + dg * k : F32), (ab + db * k : F32), (aa + da * k : F32), (au + du * k : F32), (av + dv * k : F32)}

def Attr.add(a: Attr, d: Attr) -> Attr:
  Attr{ar, ag, ab, aa, au, av} = a
  Attr{dr, dg, db, da, du, dv} = d
  Attr{(ar + dr : F32), (ag + dg : F32), (ab + db : F32), (aa + da : F32), (au + du : F32), (av + dv : F32)}

def Attr.scale(a: Attr, +k: F32) -> Attr:
  Attr{r, g, b, aa, u, v} = a
  Attr{(r * k : F32), (g * k : F32), (b * k : F32), (aa * k : F32), (u * k : F32), (v * k : F32)}

# swOrtho(0, width, height, 0, 0, 1) applied to an identity projection (rcore.c
# SetupViewport); BeginDrawing's identity modelview leaves it as the MVP.
def Matrix4.ortho(+width: U32, +height: U32) -> Matrix4:
  Matrix4{(2.0 / U32.to_f32(width) : F32), 0.0, 0.0, 0.0, 0.0, (2.0 / F32.neg(U32.to_f32(height)) : F32), 0.0, 0.0,
    0.0, 0.0, F32.neg(2.0), 0.0, F32.neg(1.0), 1.0, F32.neg(1.0), 1.0}

# sw_immediate_push_vertex: clip coordinates of (x, y, 0, 1).
def Matrix4.vertex(+m: Matrix4, +x: F32, +y: F32, +r: F32, +g: F32, +b: F32, +a: F32, +u: F32, +v: F32) -> Vertex:
  Matrix4{m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15} = m
  Vertex{(m0 * x + m4 * y + m8 * 0.0 + m12 * 1.0 : F32), (m1 * x + m5 * y + m9 * 0.0 + m13 * 1.0 : F32),
    (m2 * x + m6 * y + m10 * 0.0 + m14 * 1.0 : F32), (m3 * x + m7 * y + m11 * 0.0 + m15 * 1.0 : F32),
    r, g, b, a, u, v}

def Matrix4.identity() -> Matrix4:
  Matrix4{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}

def Matrix4.cell(+a: F32, +b: F32, +c: F32, +d: F32, +e: F32, +f: F32, +g: F32, +h: F32) -> F32:
  (a * e + b * f + c * g + d * h : F32)

# sw_matrix_mul_rst: dst[4i + j] = sum over k of left[4i + k]*right[4k + j],
# accumulated in k order. MVP = mul(modelview, projection); swTranslatef,
# swRotatef, swScalef and swMultMatrixf replace the current matrix M by
# mul(T, M), swOrtho by mul(M, T).
def Matrix4.mul(left: Matrix4, right: Matrix4) -> Matrix4:
  Matrix4{+l0, +l1, +l2, +l3, +l4, +l5, +l6, +l7, +l8, +l9, +l10, +l11, +l12, +l13, +l14, +l15} = left
  Matrix4{+r0, +r1, +r2, +r3, +r4, +r5, +r6, +r7, +r8, +r9, +r10, +r11, +r12, +r13, +r14, +r15} = right
  Matrix4{Matrix4.cell(l0, l1, l2, l3, r0, r4, r8, r12), Matrix4.cell(l0, l1, l2, l3, r1, r5, r9, r13),
    Matrix4.cell(l0, l1, l2, l3, r2, r6, r10, r14), Matrix4.cell(l0, l1, l2, l3, r3, r7, r11, r15),
    Matrix4.cell(l4, l5, l6, l7, r0, r4, r8, r12), Matrix4.cell(l4, l5, l6, l7, r1, r5, r9, r13),
    Matrix4.cell(l4, l5, l6, l7, r2, r6, r10, r14), Matrix4.cell(l4, l5, l6, l7, r3, r7, r11, r15),
    Matrix4.cell(l8, l9, l10, l11, r0, r4, r8, r12), Matrix4.cell(l8, l9, l10, l11, r1, r5, r9, r13),
    Matrix4.cell(l8, l9, l10, l11, r2, r6, r10, r14), Matrix4.cell(l8, l9, l10, l11, r3, r7, r11, r15),
    Matrix4.cell(l12, l13, l14, l15, r0, r4, r8, r12), Matrix4.cell(l12, l13, l14, l15, r1, r5, r9, r13),
    Matrix4.cell(l12, l13, l14, l15, r2, r6, r10, r14), Matrix4.cell(l12, l13, l14, l15, r3, r7, r11, r15)}

# swTranslatef's matrix.
def Matrix4.translate(+x: F32, +y: F32, +z: F32) -> Matrix4:
  Matrix4{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, x, y, z, 1.0}

# swScalef's matrix.
def Matrix4.scale(+x: F32, +y: F32, +z: F32) -> Matrix4:
  Matrix4{x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0}

# swRotatef's matrix for a normalized axis, cosf and sinf of the angle.
def Matrix4.rotation(+x: F32, +y: F32, +z: F32, +c: F32, +s: F32) -> Matrix4:
  +t = (1.0 - c : F32)
  Matrix4{(x * x * t + c : F32), (y * x * t + z * s : F32), (z * x * t - y * s : F32), 0.0,
    (x * y * t - z * s : F32), (y * y * t + c : F32), (z * y * t + x * s : F32), 0.0,
    (x * z * t + y * s : F32), (y * z * t - x * s : F32), (z * z * t + c : F32), 0.0, 0.0, 0.0, 0.0, 1.0}

# -----------------------------------------------------------------------------
# Scissor (swScissor): the rectangle in framebuffer pixels (C ints, rows from
# the bottom) and in clip space for the viewport current when it was set.

type Scissor is Data:
  Scissor{enabled: Bool, x0: F32, y0: F32, x1: F32, y1: F32, cx0: F32, cx1: F32, cy0: F32, cy1: F32}

# swScissor(x, y, width, height) for a viewport of vw x vh pixels.
def Scissor.set(enabled: Bool, +x: F32, +y: F32, +width: F32, +height: F32, +vw: F32, +vh: F32) -> Scissor:
  +x1 = (x + width : F32)
  +y1 = (y + height : F32)
  Scissor{enabled, x, y, x1, y1, (((2.0 * x : F32) / vw : F32) - 1.0 : F32), (((2.0 * x1 : F32) / vw : F32) - 1.0 : F32),
    (1.0 - ((2.0 * y1 : F32) / vh : F32) : F32), (1.0 - ((2.0 * y : F32) / vh : F32) : F32)}

def Scissor.enable(enabled: Bool, scissor: Scissor) -> Scissor:
  Scissor{_, x0, y0, x1, y1, cx0, cx1, cy0, cy1} = scissor
  Scissor{enabled, x0, y0, x1, y1, cx0, cx1, cy0, cy1}

def Scissor.enabled(+scissor: Scissor) -> Bool:
  Scissor{enabled, _, _, _, _, _, _, _, _} = scissor
  enabled

# -----------------------------------------------------------------------------
# Polygon clipping (sw_polygon_clip): planes 0..6 are the frustum (w, +x, -x,
# +y, -y, +z, -z), 7..10 the scissor (x min, x max, y min, y max) with s its
# clip-space bound.

def plane.inside(plane: U32, +s: F32, +x: F32, +y: F32, +z: F32, +w: F32) -> Bool:
  match plane:
    case 0: (w >= clip_epsilon() : F32)
    case 1: (x < w : F32)
    case 2: (F32.neg(x) < w : F32)
    case 3: (y < w : F32)
    case 4: (F32.neg(y) < w : F32)
    case 5: (z <= w : F32)
    case 6: (F32.neg(z) <= w : F32)
    case 7: (x >= (s * w : F32) : F32)
    case 8: (x <= (s * w : F32) : F32)
    case 9: (y >= (s * w : F32) : F32)
    case _: (y <= (s * w : F32) : F32)

def inside(+plane: U32, +s: F32, +v: Vertex) -> Bool:
  Vertex{x, y, z, w, _, _, _, _, _, _} = v
  plane.inside(plane, s, x, y, z, w)

def plane.t(plane: U32, +s: F32, +px: F32, +py: F32, +pz: F32, +pw: F32, +cx: F32, +cy: F32, +cz: F32, +cw: F32) -> F32:
  match plane:
    case 0: ((clip_epsilon() - pw) / (cw - pw) : F32)
    case 1: ((pw - px) / ((pw - px) - (cw - cx)) : F32)
    case 2: ((pw + px) / ((pw + px) - (cw + cx)) : F32)
    case 3: ((pw - py) / ((pw - py) - (cw - cy)) : F32)
    case 4: ((pw + py) / ((pw + py) - (cw + cy)) : F32)
    case 5: ((pw - pz) / ((pw - pz) - (cw - cz)) : F32)
    case 6: ((pw + pz) / ((pw + pz) - (cw + cz)) : F32)
    case 7: (((s * pw : F32) - px : F32) / ((cx - (s * cw : F32) : F32) - (px - (s * pw : F32) : F32) : F32) : F32)
    case 8: (((s * pw : F32) - px : F32) / ((cx - (s * cw : F32) : F32) - (px - (s * pw : F32) : F32) : F32) : F32)
    case 9: (((s * pw : F32) - py : F32) / ((cy - (s * cw : F32) : F32) - (py - (s * pw : F32) : F32) : F32) : F32)
    case _: (((s * pw : F32) - py : F32) / ((cy - (s * cw : F32) : F32) - (py - (s * pw : F32) : F32) : F32) : F32)

def crossing(+plane: U32, +s: F32, +prev: Vertex, +curr: Vertex) -> F32:
  Vertex{px, py, pz, pw, _, _, _, _, _, _} = prev
  Vertex{cx, cy, cz, cw, _, _, _, _, _, _} = curr
  plane.t(plane, s, px, py, pz, pw, cx, cy, cz, cw)

def clip.cross(changed: Bool, +plane: U32, +s: F32, +prev: Vertex, +curr: Vertex, out: +List<Vertex>) -> +List<Vertex>:
  match changed:
    case False{}: out
    case True{}: Con{Vertex.lerp(prev, curr, crossing(plane, s, prev, curr)), out}

def clip.keep(keep: Bool, +curr: Vertex, out: +List<Vertex>) -> +List<Vertex>:
  match keep:
    case False{}: out
    case True{}: Con{curr, out}

def clip.loop(input: +List<Vertex>, +plane: U32, +s: F32, +prev: Vertex, +prev_in: Bool, out: +List<Vertex>) -> +List<Vertex>:
  match input:
    case Nil{}: List.reverse(&2, Vertex, out)
    case Con{+curr, rest}:
      +curr_in = inside(plane, s, curr)
      clip.loop(rest, plane, s, curr, curr_in, clip.keep(curr_in, curr, clip.cross(Bool.xor(prev_in, curr_in), plane, s, prev, curr, out)))

def clip.last(input: +List<Vertex>, +last: Vertex) -> Vertex:
  match input:
    case Nil{}: last
    case Con{+v, rest}: clip.last(rest, v)

def clip.pass(+plane: U32, +s: F32, input: +List<Vertex>) -> +List<Vertex>:
  match input:
    case Nil{}: Nil{}
    case Con{+first, +rest}:
      +prev = clip.last(rest, first)
      clip.loop(Con{first, rest}, plane, s, prev, inside(plane, s, prev), Nil{})

# Fewer than three vertices after a plane: the primitive is discarded.
def clip.enough(polygon: +List<Vertex>) -> +List<Vertex>:
  match polygon:
    case Con{+a, Con{+b, Con{+c, rest}}}: Con{a, Con{b, Con{c, rest}}}
    case _: Nil{}

def clip.planes(n: Nat, +plane: U32, polygon: +List<Vertex>) -> +List<Vertex>:
  match n:
    case 0n: polygon
    case 1n+rest: clip.planes(rest, (plane + 1 : U32), clip.enough(clip.pass(plane, 0.0, polygon)))

def clip.scissor(enabled: Bool, +cx0: F32, +cx1: F32, +cy0: F32, +cy1: F32, polygon: +List<Vertex>) -> +List<Vertex>:
  match enabled:
    case False{}: polygon
    case True{}:
      clip.enough(clip.pass(10, cy1, clip.enough(clip.pass(9, cy0, clip.enough(clip.pass(8, cx1, clip.enough(clip.pass(7, cx0, polygon))))))))

def clip.polygon(+scissor: Scissor, polygon: +List<Vertex>) -> +List<Vertex>:
  Scissor{enabled, _, _, _, _, cx0, cx1, cy0, cy1} = scissor
  clip.scissor(enabled, cx0, cx1, cy0, cy1, clip.planes(7n, 0, polygon))

# sw_triangle/quad_clip_and_project: divide by w, keep 1/w, map NDC to the
# viewport (center + ndc*half + 0.5).
def project(+cx: F32, +cy: F32, +hx: F32, +hy: F32, +v: Vertex) -> Vertex:
  Vertex{x, y, z, w, r, g, b, a, u, t} = v
  +k = (1.0 / w : F32)
  Vertex{((cx + (x * k : F32) * hx) + 0.5 : F32), ((cy + (y * k : F32) * hy) + 0.5 : F32), (z * k : F32), k,
    (r * k : F32), (g * k : F32), (b * k : F32), (a * k : F32), (u * k : F32), (t * k : F32)}

def project.loop(polygon: +List<Vertex>, +hx: F32, +hy: F32, out: +List<Vertex>) -> +List<Vertex>:
  match polygon:
    case Nil{}: List.reverse(&2, Vertex, out)
    case Con{+v, rest}: project.loop(rest, hx, hy, Con{project((0.0 + hx : F32), (0.0 + hy : F32), hx, hy, v), out})

# swViewport(0, 0, width, height): half = size/2.0f, center = 0 + half.
def project.all(+width: U32, +height: U32, polygon: +List<Vertex>) -> +List<Vertex>:
  project.loop(polygon, (U32.to_f32(width) / 2.0 : F32), (U32.to_f32(height) / 2.0 : F32), Nil{})

# -----------------------------------------------------------------------------
# Raster target: the R8G8B8A8 color buffer (bottom-up rows, canonical
# 0xRRGGBBAA words), the shapes atlas, the bound user texture and whether
# every step was defined.

# A bound user texture: texel (x, y) at y*width + x holds rlsw's readColor8
# result as a canonical word; rlsw samples it with REPEAT wrapping (raylib's
# CLAMP value is not one rlsw accepts) and the nearest or bilinear filter.
type Sampler is Type:
  Unbound{}
  Texels{width: U32, height: U32, linear: Bool, texels: Array<U32>}

type Raster is Type:
  Raster{pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool}

def Raster.refuse(raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, _} = raster
  Raster{pixels, atlas, sampler, False{}}

def Raster.require(valid: Bool, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok} = raster
  Raster{pixels, atlas, sampler, ok && valid}

# sw_color_to_color8: (uint8_t)(c*255.0f), defined for products in (-1, 256).
def pack.channel(+scaled: F32) -> U32:
  (F32.to_u32(F32.max(scaled, 0.0)) .&. 255 : U32)

def pack.valid(+scaled: F32) -> Bool:
  (scaled > F32.neg(1.0) : F32) && (scaled < 256.0 : F32)

def pack.scaled(+sr: F32, +sg: F32, +sb: F32, +sa: F32) -> U32 & Bool:
  (((pack.channel(sr) << 24n) .|. (pack.channel(sg) << 16n) .|. (pack.channel(sb) << 8n) .|. pack.channel(sa) : U32),
    pack.valid(sr) && pack.valid(sg) && pack.valid(sb) && pack.valid(sa))

def pack(+r: F32, +g: F32, +b: F32, +a: F32) -> U32 & Bool:
  pack.scaled((r * 255.0 : F32), (g * 255.0 : F32), (b * 255.0 : F32), (a * 255.0 : F32))

def store(+offset: U32, packed: U32 & Bool, raster: Raster) -> Raster:
  (word, valid) = packed
  Raster{pixels, atlas, sampler, ok} = raster
  Raster{Array.set(U32, pixels, offset, word), atlas, sampler, ok && valid}

# sw_blend_SRC_ALPHA_ONE_MINUS_SRC_ALPHA on the LUT-expanded destination.
def mix(+r: F32, +g: F32, +b: F32, +a: F32, +old: U32) -> U32 & Bool:
  +k = (1.0 - a : F32)
  pack((a * r + k * lut((old >> 24n : U32)) : F32), (a * g + k * lut(((old >> 16n) .&. 255 : U32)) : F32),
    (a * b + k * lut(((old >> 8n) .&. 255 : U32)) : F32), (a * a + k * lut((old .&. 255 : U32)) : F32))

def put.read(+offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, atlas: Array<U32>, sampler: Sampler, ok: Bool, read: Array<U32> & U32) -> Raster:
  (pixels, +old) = read
  store(offset, mix(r, g, b, a, old), Raster{pixels, atlas, sampler, ok})

def put.blend(+offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok} = raster
  put.read(offset, r, g, b, a, atlas, sampler, ok, Array.get(U32, pixels, offset))

def put(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, raster: Raster) -> Raster:
  match blend:
    case False{}: store(offset, pack(r, g, b, a), raster)
    case True{}: put.blend(offset, r, g, b, a, raster)

# sw_texture_sample_nearest on the 128x128 GRAY_ALPHA font atlas (REPEAT,
# NEAREST for both filters): returns the texel alpha; gray is always 255.
def sample.read(+bit: U32, inside: Bool, pixels: Array<U32>, sampler: Sampler, ok: Bool, read: Array<U32> & U32) -> Raster & F32:
  (atlas, +word) = read
  (Raster{pixels, atlas, sampler, ok && inside}, lut((((word >> U32.to_nat(bit)) .&. 1) * 255 : U32)))

def sample.at(+slot: U32, inside: Bool, raster: Raster) -> Raster & F32:
  Raster{pixels, atlas, sampler, ok} = raster
  sample.read((slot .&. 31 : U32), inside, pixels, sampler, ok, Array.get(U32, atlas, (slot >> 5n : U32)))

def sample(+u: F32, +v: F32, raster: Raster) -> Raster & F32:
  +x = (fract(u) * 128.0 : F32)
  +y = (fract(v) * 128.0 : F32)
  +index = (F32.trunc(y) * 128.0 + F32.trunc(x) : F32)
  +inside = raster_int.valid(x) && raster_int.valid(y) && (index >= 0.0 : F32) && (index < 16384.0 : F32)
  sample.at(Bool.pick(U32, inside, F32.to_u32(index), 0), inside, raster)

def pixel.textured.read(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, sampled: Raster & F32) -> Raster:
  (raster, +alpha) = sampled
  +gray = lut(255)
  put(blend, offset, (r * gray : F32), (g * gray : F32), (b * gray : F32), (a * alpha : F32), raster)

def pixel.textured(blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, u, v} = at
  pixel.textured.read(blend, offset, r, g, b, a, sample(u, v, raster))

# A user texel as rlsw's readColor returns it: each channel byte*SW_INV_255.
type Texel is Data:
  Texel{r: F32, g: F32, b: F32, a: F32}

def Texel.of(+word: U32) -> Texel:
  Texel{lut((word >> 24n : U32)), lut(((word >> 16n) .&. 255 : U32)), lut(((word >> 8n) .&. 255 : U32)), lut((word .&. 255 : U32))}

def rgba(+r: U32, +g: U32, +b: U32, +a: U32) -> U32:
  ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32)

# sw_expand_5to8 and sw_expand_6to8 (bit replication).
def expand5(+v: U32) -> U32:
  ((v << 3n) .|. (v >> 2n) : U32)

def expand6(+v: U32) -> U32:
  ((v << 2n) .|. (v >> 4n) : U32)

# rlsw's readColor8 of one stored pixel of an uncompressed raylib format
# 1..7, as a canonical word: Jonlib's Surface words hold the gray byte (1),
# gray | alpha << 8 (2), the 16-bit value (3, 5, 6), r | g << 8 | b << 16 (4)
# or the canonical word (7).
def texel.word(format: U32, +word: U32) -> U32:
  match format:
    case 1: rgba((word .&. 255 : U32), (word .&. 255 : U32), (word .&. 255 : U32), 255)
    case 2: rgba((word .&. 255 : U32), (word .&. 255 : U32), (word .&. 255 : U32), ((word >> 8n) .&. 255 : U32))
    case 3: rgba(expand5(((word >> 11n) .&. 31 : U32)), expand6(((word >> 5n) .&. 63 : U32)), expand5((word .&. 31 : U32)), 255)
    case 4: rgba((word .&. 255 : U32), ((word >> 8n) .&. 255 : U32), ((word >> 16n) .&. 255 : U32), 255)
    case 5: rgba(expand5(((word >> 11n) .&. 31 : U32)), expand5(((word >> 6n) .&. 31 : U32)), expand5(((word >> 1n) .&. 31 : U32)), ((word .&. 1) * 255 : U32))
    case 6: rgba((((word >> 12n) .&. 15) * 17 : U32), (((word >> 8n) .&. 15) * 17 : U32), (((word >> 4n) .&. 15) * 17 : U32), ((word .&. 15) * 17 : U32))
    case _: word

def texel.got(valid: Bool, read: Array<U32> & U32) -> Array<U32> & (Texel & Bool):
  (texels, +word) = read
  (texels, (Texel.of(word), valid))

# sw_texture_sample_nearest with REPEAT: (int)(fract(u)*width) and likewise v,
# read at y*width + x. fract of a tiny negative coordinate rounds to 1.0, so x
# (or y) can equal the size: the read lands on the next row, and past the last
# texel it is out of bounds (refused), as are NaN and infinite coordinates.
def nearest(+u: F32, +v: F32, +width: U32, +height: U32, texels: Array<U32>) -> Array<U32> & (Texel & Bool):
  +x = F32.trunc((fract(u) * U32.to_f32(width) : F32))
  +y = F32.trunc((fract(v) * U32.to_f32(height) : F32))
  +inside = (x >= 0.0 : F32) && (x <= U32.to_f32(width) : F32) && (y >= 0.0 : F32) && (y <= U32.to_f32(height) : F32)
  +index = (F32.to_u32(Bool.pick(F32, inside, y, 0.0)) * width + F32.to_u32(Bool.pick(F32, inside, x, 0.0)) : U32)
  +valid = inside && (index < (width * height : U32) : U32)
  texel.got(valid, Array.get(U32, texels, Bool.pick(U32, valid, index, 0)))

# C's (int) of a coordinate: defined for [-2^31, 2^31).
def int.range(+x: F32) -> Bool:
  (x >= F32.neg(2147483648.0) : F32) && (x < 2147483648.0 : F32)

# ((x%size) + size)%size for an integral x in int range.
def wrap.mod(+x: F32, +size: U32) -> U32:
  +m = (F32.to_u32(F32.abs(x)) % size : U32)
  Bool.pick(U32, (x >= 0.0 : F32), m, ((size - m) % size : U32))

def bilinear.channel(+c00: F32, +c10: F32, +c01: F32, +c11: F32, +fx: F32, +fy: F32) -> F32:
  +t = (c00 + fx * (c10 - c00) : F32)
  +b = (c01 + fx * (c11 - c01) : F32)
  (t + fy * (b - t) : F32)

def bilinear.mix(+fx: F32, +fy: F32, a: Texel, b: Texel, c: Texel, d: Texel) -> Texel:
  Texel{ar, ag, ab, aa} = a
  Texel{br, bg, bb, ba} = b
  Texel{cr, cg, cb, ca} = c
  Texel{dr, dg, db, da} = d
  Texel{bilinear.channel(ar, br, cr, dr, fx, fy), bilinear.channel(ag, bg, cg, dg, fx, fy),
    bilinear.channel(ab, bb, cb, db, fx, fy), bilinear.channel(aa, ba, ca, da, fx, fy)}

def bilinear.c11(+fx: F32, +fy: F32, valid: Bool, c00: Texel, c10: Texel, c01: Texel, read: Array<U32> & U32) -> Array<U32> & (Texel & Bool):
  (texels, +word) = read
  (texels, (bilinear.mix(fx, fy, c00, c10, c01, Texel.of(word)), valid))

def bilinear.c01(+fx: F32, +fy: F32, valid: Bool, +i11: U32, c00: Texel, c10: Texel, read: Array<U32> & U32) -> Array<U32> & (Texel & Bool):
  (texels, +word) = read
  bilinear.c11(fx, fy, valid, c00, c10, Texel.of(word), Array.get(U32, texels, i11))

def bilinear.c10(+fx: F32, +fy: F32, valid: Bool, +i01: U32, +i11: U32, c00: Texel, read: Array<U32> & U32) -> Array<U32> & (Texel & Bool):
  (texels, +word) = read
  bilinear.c01(fx, fy, valid, i11, c00, Texel.of(word), Array.get(U32, texels, i01))

def bilinear.c00(+fx: F32, +fy: F32, valid: Bool, +i10: U32, +i01: U32, +i11: U32, read: Array<U32> & U32) -> Array<U32> & (Texel & Bool):
  (texels, +word) = read
  bilinear.c10(fx, fy, valid, i01, i11, Texel.of(word), Array.get(U32, texels, i10))

def bilinear.at(+fx: F32, +fy: F32, valid: Bool, +width: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, texels: Array<U32>) -> Array<U32> & (Texel & Bool):
  bilinear.c00(fx, fy, valid, (y0 * width + x1 : U32), (y1 * width + x0 : U32), (y1 * width + x1 : U32), Array.get(U32, texels, (y0 * width + x0 : U32)))

# sw_texture_sample_linear with REPEAT: xf = u*width - 0.5, weights fract(xf),
# texels (int)xf (truncated toward zero) and the next one, both wrapped; the
# same on v. A coordinate whose (int) conversion is undefined is refused.
def bilinear(+u: F32, +v: F32, +width: U32, +height: U32, texels: Array<U32>) -> Array<U32> & (Texel & Bool):
  +xf = ((u * U32.to_f32(width) : F32) - 0.5 : F32)
  +yf = ((v * U32.to_f32(height) : F32) - 0.5 : F32)
  +valid = int.range(xf) && int.range(yf)
  +x0 = wrap.mod(F32.trunc(Bool.pick(F32, valid, xf, 0.0)), width)
  +y0 = wrap.mod(F32.trunc(Bool.pick(F32, valid, yf, 0.0)), height)
  bilinear.at(fract(xf), fract(yf), valid, width, x0, y0, ((x0 + 1) % width : U32), ((y0 + 1) % height : U32), texels)

def sample.filter(linear: Bool, +u: F32, +v: F32, +width: U32, +height: U32, texels: Array<U32>) -> Array<U32> & (Texel & Bool):
  match linear:
    case False{}: nearest(u, v, width, height, texels)
    case True{}: bilinear(u, v, width, height, texels)

def sample.rewrap(+width: U32, +height: U32, +linear: Bool, result: Array<U32> & (Texel & Bool)) -> Sampler & (Texel & Bool):
  (texels, rest) = result
  (Texels{width, height, linear, texels}, rest)

def sample.sampler(+u: F32, +v: F32, sampler: Sampler) -> Sampler & (Texel & Bool):
  match sampler:
    case Unbound{}: (Unbound{}, (Texel{0.0, 0.0, 0.0, 0.0}, False{}))
    case Texels{+width, +height, +linear, texels}: sample.rewrap(width, height, linear, sample.filter(linear, u, v, width, height, texels))

def sample.done(pixels: Array<U32>, atlas: Array<U32>, ok: Bool, sampler: Sampler, rest: Texel & Bool) -> Raster & Texel:
  (texel, valid) = rest
  (Raster{pixels, atlas, sampler, ok && valid}, texel)

def sample.rebuild(pixels: Array<U32>, atlas: Array<U32>, ok: Bool, result: Sampler & (Texel & Bool)) -> Raster & Texel:
  (sampler, rest) = result
  sample.done(pixels, atlas, ok, sampler, rest)

def sample.user(+u: F32, +v: F32, raster: Raster) -> Raster & Texel:
  Raster{pixels, atlas, sampler, ok} = raster
  sample.rebuild(pixels, atlas, ok, sample.sampler(u, v, sampler))

def pixel.user.mix(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, texel: Texel, raster: Raster) -> Raster:
  Texel{tr, tg, tb, ta} = texel
  put(blend, offset, (r * tr : F32), (g * tg : F32), (b * tb : F32), (a * ta : F32), raster)

def pixel.user.read(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, sampled: Raster & Texel) -> Raster:
  (raster, texel) = sampled
  pixel.user.mix(blend, offset, r, g, b, a, texel, raster)

# A user texture: the interpolated color times the sampled texel.
def pixel.user(blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, u, v} = at
  pixel.user.read(blend, offset, r, g, b, a, sample.user(u, v, raster))

def pixel.plain(blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, _, _} = at
  put(blend, offset, r, g, b, a, raster)

# tex: 0 untextured, 1 the shapes atlas, 2 the bound user texture.
def pixel(tex: U32, blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match tex:
    case 0: pixel.plain(blend, offset, at, raster)
    case 1: pixel.textured(blend, offset, at, raster)
    case _: pixel.user(blend, offset, at, raster)

# Consecutive pixels of a row, attributes stepped after each one.
def cols(n: Nat, +tex: U32, +blend: Bool, +offset: U32, +at: Attr, +step: Attr, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: cols(rest, tex, blend, (offset + 1 : U32), Attr.add(at, step), step, pixel(tex, blend, offset, at, raster))

def Vertex.attr(+v: Vertex) -> Attr:
  Vertex{_, _, _, _, r, g, b, a, u, t} = v
  Attr{r, g, b, a, u, t}

# -----------------------------------------------------------------------------
# Axis-aligned quads (SW_RASTER_QUAD): pixel centers in (x0, x1] x [y0, y1)
# from the corners classified by x+y and x-y; colors from three corners.

type Corners is Data:
  Corners{tl: Vertex, tr: Vertex, br: Vertex, bl: Vertex}

def Vertex.sum(+v: Vertex) -> F32:
  (Vertex.x(v) + Vertex.y(v) : F32)

def Vertex.diff(+v: Vertex) -> F32:
  (Vertex.x(v) - Vertex.y(v) : F32)

def quad.classify(+v: Vertex, corners: Corners) -> Corners:
  Corners{+tl, +tr, +br, +bl} = corners
  Corners{Bool.pick(Vertex, (Vertex.sum(v) < Vertex.sum(tl) : F32), v, tl), Bool.pick(Vertex, (Vertex.diff(v) > Vertex.diff(tr) : F32), v, tr),
    Bool.pick(Vertex, (Vertex.sum(v) > Vertex.sum(br) : F32), v, br), Bool.pick(Vertex, (Vertex.diff(v) < Vertex.diff(bl) : F32), v, bl)}

def rows(n: Nat, +tex: U32, +blend: Bool, +offset: U32, +stride: U32, +columns: Nat, +row: Attr, +dx: Attr, +dy: Attr, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: rows(rest, tex, blend, (offset + stride : U32), stride, columns, Attr.add(row, dy), dx, dy, cols(columns, tex, blend, offset, row, dx, raster))

def quad.fill(+tex: U32, +blend: Bool, +width: U32, +x0: F32, +y0: F32, +w: F32, +h: F32, +tl: Vertex, +tr: Vertex, +bl: Vertex, raster: Raster) -> Raster:
  +dx = Vertex.grad(tl, tr, (1.0 / w : F32))
  +dy = Vertex.grad(tl, bl, (1.0 / h : F32))
  +start = Vertex.add_scaled(Vertex.add_scaled(tl, dx, (1.0 - fract(Vertex.x(tl)) : F32)), dy, (1.0 - fract(Vertex.y(tl)) : F32))
  rows(U32.to_nat(F32.to_u32(h)), tex, blend, (F32.to_u32(y0) * width + F32.to_u32(x0) : U32), width, U32.to_nat(F32.to_u32(w)),
    Vertex.attr(start), Vertex.attr(dx), Vertex.attr(dy), raster)

def quad.inside(inside: Bool, +tex: U32, +blend: Bool, +width: U32, +x0: F32, +y0: F32, +w: F32, +h: F32, +tl: Vertex, +tr: Vertex, +bl: Vertex, raster: Raster) -> Raster:
  match inside:
    case False{}: Raster.refuse(raster)
    case True{}: quad.fill(tex, blend, width, x0, y0, w, h, tl, tr, bl, raster)

def quad.sized(empty: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +tl: Vertex, +tr: Vertex, +bl: Vertex, raster: Raster) -> Raster:
  match empty:
    case True{}: raster
    case False{}:
      +inside = (x0 >= 0.0 : F32) && (y0 >= 0.0 : F32) && (x1 <= U32.to_f32(width) : F32) && (y1 <= U32.to_f32(height) : F32)
      quad.inside(inside, tex, blend, width, x0, y0, (x1 - x0 : F32), (y1 - y0 : F32), tl, tr, bl, raster)

def quad.converted(valid: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +tl: Vertex, +tr: Vertex, +br: Vertex, +bl: Vertex, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}:
      +x0 = F32.trunc(Vertex.x(tl))
      +y0 = F32.trunc(Vertex.y(tl))
      +x1 = F32.trunc(Vertex.x(br))
      +y1 = F32.trunc(Vertex.y(br))
      quad.sized(((x1 - x0) <= 0.0 : F32) || ((y1 - y0) <= 0.0 : F32), tex, blend, width, height, x0, y0, x1, y1, tl, tr, bl, raster)

def quad.box(+tex: U32, +blend: Bool, +width: U32, +height: U32, corners: Corners, raster: Raster) -> Raster:
  Corners{+tl, +tr, +br, +bl} = corners
  +valid = raster_int.valid(Vertex.x(tl)) && raster_int.valid(Vertex.y(tl)) && raster_int.valid(Vertex.x(br)) && raster_int.valid(Vertex.y(br))
  quad.converted(valid, tex, blend, width, height, tl, tr, br, bl, raster)

def quad.raster(+tex: U32, +blend: Bool, +width: U32, +height: U32, +a: Vertex, +b: Vertex, +c: Vertex, +d: Vertex, raster: Raster) -> Raster:
  quad.box(tex, blend, width, height, quad.classify(d, quad.classify(c, quad.classify(b, Corners{a, a, a, a}))), raster)

# -----------------------------------------------------------------------------
# Triangles (SW_RASTER_TRIANGLE): scanlines between edge accumulators, spans
# over (x_left, x_right] in 16-pixel blocks with perspective-correct ends.

def Span.of(+v: Vertex) -> Span:
  Vertex{_, _, _, w, r, g, b, a, u, t} = v
  Span{w, r, g, b, a, u, t}

def Span.w(+s: Span) -> F32:
  Span{w, _, _, _, _, _, _} = s
  w

def Span.at(s: Span, d: Span, +k: F32) -> Span:
  Span{w, r, g, b, a, u, v} = s
  Span{dw, dr, dg, db, da, du, dv} = d
  Span{(w + dw * k : F32), (r + dr * k : F32), (g + dg * k : F32), (b + db * k : F32), (a + da * k : F32), (u + du * k : F32), (v + dv * k : F32)}

def span.slope(+start: Vertex, +end: Vertex, +k: F32) -> Span:
  Span.of(Vertex.grad(start, end, k))

def block.start(+acc: Span, +k: F32) -> Attr:
  Span{_, r, g, b, a, u, v} = acc
  Attr{(r * k : F32), (g * k : F32), (b * k : F32), (a * k : F32), (u * k : F32), (v * k : F32)}

def block.delta(+value: F32, +slope: F32, +len: F32, +ka: F32, +kb: F32, +kl: F32) -> F32:
  ((((value + slope * len : F32) * kb : F32) - (value * ka : F32)) * kl : F32)

def block.step.with(+acc: Span, +slope: Span, +len: F32, +ka: F32, +kb: F32) -> Attr:
  Span{_, r, g, b, a, u, v} = acc
  Span{_, dr, dg, db, da, du, dv} = slope
  +kl = (1.0 / len : F32)
  Attr{block.delta(r, dr, len, ka, kb, kl), block.delta(g, dg, len, ka, kb, kl), block.delta(b, db, len, ka, kb, kl),
    block.delta(a, da, len, ka, kb, kl), block.delta(u, du, len, ka, kb, kl), block.delta(v, dv, len, ka, kb, kl)}

def block.step(+acc: Span, +slope: Span, +len: F32, +ka: F32) -> Attr:
  block.step.with(acc, slope, len, ka, (1.0 / (Span.w(acc) + Span.w(slope) * len : F32) : F32))

def blocks(n: Nat, +tex: U32, +blend: Bool, +offset: U32, +x: F32, +x_end: F32, +acc: Span, +slope: Span, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest:
      +stop = F32.min((x + 16.0 : F32), x_end)
      +len = (stop - x : F32)
      +ka = (1.0 / Span.w(acc) : F32)
      blocks(rest, tex, blend, (offset + F32.to_u32(len) : U32), stop, x_end, Span.at(acc, slope, len), slope,
        cols(U32.to_nat(F32.to_u32(len)), tex, blend, offset, block.start(acc, ka), block.step(acc, slope, len, ka), raster))

def span.fill(+tex: U32, +blend: Bool, +width: U32, +x0: F32, +x1: F32, +y: F32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  +slope = span.slope(start, end, (1.0 / (Vertex.x(end) - Vertex.x(start)) : F32))
  +acc = Span.at(Span.of(start), slope, (1.0 - fract(Vertex.x(start)) : F32))
  blocks(U32.to_nat(((F32.to_u32((x1 - x0 : F32)) + 15) / 16 : U32)), tex, blend, (F32.to_u32(y) * width + F32.to_u32(x0) : U32),
    x0, x1, acc, slope, raster)

def span.inside(inside: Bool, +tex: U32, +blend: Bool, +width: U32, +x0: F32, +x1: F32, +y: F32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  match inside:
    case False{}: Raster.refuse(raster)
    case True{}: span.fill(tex, blend, width, x0, x1, y, start, end, raster)

def span.ordered(nonempty: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +x0: F32, +x1: F32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  match nonempty:
    case False{}: raster
    case True{}:
      +y = F32.trunc(Vertex.y(start))
      +inside = (y >= 0.0 : F32) && (y < U32.to_f32(height) : F32) && (x0 >= 0.0 : F32) && (x1 <= U32.to_f32(width) : F32)
      span.inside(inside, tex, blend, width, x0, x1, y, start, end, raster)

def span.checked(valid: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}:
      +x0 = F32.trunc(Vertex.x(start))
      +x1 = F32.trunc(Vertex.x(end))
      span.ordered((x0 < x1 : F32), tex, blend, width, height, x0, x1, start, end, raster)

def span(+tex: U32, +blend: Bool, +width: U32, +height: U32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  span.checked(raster_int.valid(Vertex.x(start)) && raster_int.valid(Vertex.x(end)), tex, blend, width, height, start, end, raster)

def tri.rows(n: Nat, +tex: U32, +blend: Bool, +width: U32, +height: U32, +row: F32, +left: Vertex, +right: Vertex, +gl: Vertex, +gr: Vertex, raster: Raster) -> Raster & Vertex:
  match n:
    case 0n: (raster, left)
    case 1n+rest:
      +l = Vertex.with_y(left, row)
      +r = Vertex.with_y(right, row)
      +long = (Vertex.x(l) < Vertex.x(r) : F32)
      tri.rows(rest, tex, blend, width, height, (row + 1.0 : F32), Vertex.add(l, gl), Vertex.add(r, gr), gl, gr,
        span(tex, blend, width, height, Bool.pick(Vertex, long, l, r), Bool.pick(Vertex, long, r, l), raster))

def tri.count(+from: F32, +to: F32) -> Nat:
  U32.to_nat(F32.to_u32(F32.max((to - from : F32), 0.0)))

def tri.finish(result: Raster & Vertex) -> Raster:
  (raster, _) = result
  raster

def tri.lower(+tex: U32, +blend: Bool, +width: U32, +height: U32, +mid: F32, +bottom: Vertex, +right: Vertex, +g02: Vertex, +g12: Vertex, upper: Raster & Vertex) -> Raster:
  (raster, +left) = upper
  tri.finish(tri.rows(tri.count(mid, F32.trunc(Vertex.y(bottom))), tex, blend, width, height, mid, left, right, g02, g12, raster))

def tri.scan(rows_ok: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  match rows_ok:
    case False{}: Raster.refuse(raster)
    case True{}:
      +y0 = Vertex.y(v0)
      +y1 = Vertex.y(v1)
      +h01 = (y1 - y0 : F32)
      +h12 = (Vertex.y(v2) - y1 : F32)
      +g02 = Vertex.grad(v0, v2, (1.0 / (Vertex.y(v2) - y0 : F32) : F32))
      +g01 = Vertex.grad(v0, v1, Bool.pick(F32, (h01 > height_epsilon() : F32), (1.0 / h01 : F32), 0.0))
      +g12 = Vertex.grad(v1, v2, Bool.pick(F32, (h12 > height_epsilon() : F32), (1.0 / h12 : F32), 0.0))
      +sub0 = (1.0 - fract(y0) : F32)
      +top = F32.trunc(y0)
      +mid = F32.trunc(y1)
      tri.lower(tex, blend, width, height, mid, v2, Vertex.add_scaled(v1, g12, (1.0 - fract(y1) : F32)), g02, g12,
        tri.rows(tri.count(top, mid), tex, blend, width, height, top, Vertex.add_scaled(v0, g02, sub0), Vertex.add_scaled(v0, g01, sub0), g02, g01, raster))

def tri.converted(valid: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}:
      +top = F32.trunc(Vertex.y(v0))
      +mid = F32.trunc(Vertex.y(v1))
      +bottom = F32.trunc(Vertex.y(v2))
      +h = U32.to_f32(height)
      +rows_ok = ((top >= mid : F32) || ((top >= 0.0 : F32) && (mid <= h : F32))) && ((mid >= bottom : F32) || ((mid >= 0.0 : F32) && (bottom <= h : F32)))
      tri.scan(rows_ok, tex, blend, width, height, v0, v1, v2, raster)

def tri.sorted(flat: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  match flat:
    case True{}: raster
    case False{}:
      +valid = raster_int.valid(Vertex.y(v0)) && raster_int.valid(Vertex.y(v1)) && raster_int.valid(Vertex.y(v2))
      tri.converted(valid, tex, blend, width, height, v0, v1, v2, raster)

def tri.order(+tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  tri.sorted(((Vertex.y(v2) - Vertex.y(v0)) < height_epsilon() : F32), tex, blend, width, height, v0, v1, v2, raster)

def tri.swap23(+tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  +swap = (Vertex.y(v0) > Vertex.y(v1) : F32)
  tri.order(tex, blend, width, height, Bool.pick(Vertex, swap, v1, v0), Bool.pick(Vertex, swap, v0, v1), v2, raster)

def triangle(+tex: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +v2: Vertex, raster: Raster) -> Raster:
  +first = (Vertex.y(v0) > Vertex.y(v1) : F32)
  +a0 = Bool.pick(Vertex, first, v1, v0)
  +a1 = Bool.pick(Vertex, first, v0, v1)
  +second = (Vertex.y(a1) > Vertex.y(v2) : F32)
  tri.swap23(tex, blend, width, height, a0, Bool.pick(Vertex, second, v2, a1), Bool.pick(Vertex, second, a1, v2), raster)

# -----------------------------------------------------------------------------
# Lines: Liang-Barsky clipping (sw_line_clip), projection, the int clamp of
# sw_line_clip_and_project and the DDA of SW_RASTER_LINE (lineWidth 0).

type Bounds is Data:
  Bounds{t0: F32, t1: F32, alive: Bool}

def lb.ratio(entering: Bool, +r: F32, +t0: F32, +t1: F32) -> Bounds:
  match entering:
    case True{}: Bounds{Bool.pick(F32, (r > t0 : F32), r, t0), t1, Bool.not((r > t1 : F32))}
    case False{}: Bounds{t0, Bool.pick(F32, (r < t1 : F32), r, t1), Bool.not((r < t0 : F32))}

def lb.flat(flat: Bool, +q: F32, +p: F32, +t0: F32, +t1: F32) -> Bounds:
  match flat:
    case True{}: Bounds{t0, t1, Bool.not((q < F32.neg(clip_epsilon()) : F32))}
    case False{}: lb.ratio((p < 0.0 : F32), (q / p : F32), t0, t1)

def lb.alive(alive: Bool, +q: F32, +p: F32, +t0: F32, +t1: F32) -> Bounds:
  match alive:
    case False{}: Bounds{t0, t1, False{}}
    case True{}: lb.flat((F32.abs(p) < clip_epsilon() : F32), q, p, t0, t1)

# sw_line_clip_coord
def lb.coord(+q: F32, +p: F32, bounds: Bounds) -> Bounds:
  Bounds{t0, t1, alive} = bounds
  lb.alive(alive, q, p, t0, t1)

# v + t*d on position and color (the line clipper leaves texcoords).
def Vertex.along(+v: Vertex, +d: Vertex, +t: F32) -> Vertex:
  Vertex{x, y, z, w, r, g, b, a, u, s} = v
  Vertex{dx, dy, dz, dw, dr, dg, db, da, _, _} = d
  Vertex{(x + t * dx : F32), (y + t * dy : F32), (z + t * dz : F32), (w + t * dw : F32), (r + t * dr : F32), (g + t * dg : F32),
    (b + t * db : F32), (a + t * da : F32), u, s}

# Screen position after sw_line_clip_and_project: x/w, y/w mapped to the
# viewport, then sw_clamp to [0, size - 1 + 0.5] returning int (NaN is UB).
def line.end(+hx: F32, +hy: F32, +max_x: F32, +max_y: F32, +v: Vertex) -> Vertex & Bool:
  Vertex{x, y, z, w, r, g, b, a, u, s} = v
  +k = (1.0 / w : F32)
  +sx = (((0.0 + hx : F32) + (x * k : F32) * hx) + 0.5 : F32)
  +sy = (((0.0 + hy : F32) + (y * k : F32) * hy) + 0.5 : F32)
  (Vertex{Bool.pick(F32, (sx < 0.0 : F32), 0.0, Bool.pick(F32, (sx > max_x : F32), F32.trunc(max_x), F32.trunc(sx))),
    Bool.pick(F32, (sy < 0.0 : F32), 0.0, Bool.pick(F32, (sy > max_y : F32), F32.trunc(max_y), F32.trunc(sy))),
    (z * k : F32), k, r, g, b, a, u, s}, F32.is_eq(sx, sx) && F32.is_eq(sy, sy))

def line.put(inside: Bool, blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, raster: Raster) -> Raster:
  match inside:
    case False{}: Raster.refuse(raster)
    case True{}: put(blend, offset, r, g, b, a, raster)

# Attr{r, g, b, a, x, y} carries a line pixel: color, then position.
def line.pixel(+blend: Bool, +width: U32, +height: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, x, y} = at
  +px = F32.trunc(x)
  +py = F32.trunc(y)
  line.put((px >= 0.0 : F32) && (px < U32.to_f32(width) : F32) && (py >= 0.0 : F32) && (py < U32.to_f32(height) : F32),
    blend, (F32.to_u32(py) * width + F32.to_u32(px) : U32), r, g, b, a, raster)

def line.pixels(n: Nat, +blend: Bool, +width: U32, +height: U32, +at: Attr, +step: Attr, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: line.pixels(rest, blend, width, height, Attr.add(at, step), step, line.pixel(blend, width, height, at, raster))

def line.count(valid: Bool, +blend: Bool, +width: U32, +height: U32, +count: F32, +at: Attr, +step: Attr, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}: line.pixels(U32.to_nat(F32.to_u32((F32.trunc(count) + 1.0 : F32))), blend, width, height, at, step, raster)

# Increments: color*(1/steps), position d/steps; Attr{r, g, b, a, x, y}.
def line.step(+v0: Vertex, +v1: Vertex, +dx: F32, +dy: F32, +steps: F32) -> Attr:
  Vertex{_, _, _, _, r0, g0, b0, a0, _, _} = v0
  Vertex{_, _, _, _, r1, g1, b1, a1, _, _} = v1
  +k = (1.0 / steps : F32)
  Attr{((r1 - r0) * k : F32), ((g1 - g0) * k : F32), ((b1 - b0) * k : F32), ((a1 - a0) * k : F32), (dx / steps : F32), (dy / steps : F32)}

def line.origin(+v0: Vertex, +x0: F32, +y0: F32) -> Attr:
  Vertex{_, _, _, _, r, g, b, a, _, _} = v0
  Attr{r, g, b, a, x0, y0}

def line.walk(+blend: Bool, +width: U32, +height: U32, +x0: F32, +y0: F32, +dx: F32, +dy: F32, +steps: F32, +substep: F32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +step = line.step(v0, v1, dx, dy, steps)
  +count = (steps - substep : F32)
  line.count((count >= 0.0 : F32) && raster_int.valid(count), blend, width, height, count,
    Attr.add(line.origin(v0, x0, y0), Attr.scale(step, substep)), step, raster)

def line.short(short: Bool, +blend: Bool, +width: U32, +height: U32, +x0: F32, +y0: F32, +dx: F32, +dy: F32, +steps: F32, +substep: F32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match short:
    case True{}: raster
    case False{}: line.walk(blend, width, height, x0, y0, dx, dy, steps, substep, v0, v1, raster)

def line.raster(+blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +x0 = (Vertex.x(v0) - 0.5 : F32)
  +y0 = (Vertex.y(v0) - 0.5 : F32)
  +dx = ((Vertex.x(v1) - 0.5 : F32) - x0 : F32)
  +dy = ((Vertex.y(v1) - 0.5 : F32) - y0 : F32)
  +major = (F32.abs(dx) > F32.abs(dy) : F32)
  +steps = Bool.pick(F32, major, F32.abs(dx), F32.abs(dy))
  +substep = Bool.pick(F32, major, Bool.pick(F32, (dx >= 0.0 : F32), (1.0 - fract(x0) : F32), fract(x0)),
    Bool.pick(F32, (dy >= 0.0 : F32), (1.0 - fract(y0) : F32), fract(y0)))
  line.short((steps < 1.0 : F32), blend, width, height, x0, y0, dx, dy, steps, substep, v0, v1, raster)

def line.checked(valid: Bool, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}: line.raster(blend, width, height, v0, v1, raster)

def line.ends(+blend: Bool, +width: U32, +height: U32, a: Vertex & Bool, b: Vertex & Bool, raster: Raster) -> Raster:
  (+v0, +valid0) = a
  (+v1, +valid1) = b
  line.checked(valid0 && valid1, blend, width, height, v0, v1, raster)

def line.project(+blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +hx = (U32.to_f32(width) / 2.0 : F32)
  +hy = (U32.to_f32(height) / 2.0 : F32)
  +max_x = (U32.to_f32((width - 1 : U32)) + 0.5 : F32)
  +max_y = (U32.to_f32((height - 1 : U32)) + 0.5 : F32)
  line.ends(blend, width, height, line.end(hx, hy, max_x, max_y, v0), line.end(hx, hy, max_x, max_y, v1), raster)

def line.alive(alive: Bool, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match alive:
    case False{}: raster
    case True{}: line.project(blend, width, height, v0, v1, raster)

def line.clipped(bounds: Bounds, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +d: Vertex, raster: Raster) -> Raster:
  Bounds{+t0, +t1, alive} = bounds
  line.alive(alive, blend, width, height, Bool.pick(Vertex, (t0 > 0.0 : F32), Vertex.along(v0, d, t0), v0),
    Bool.pick(Vertex, (t1 < 1.0 : F32), Vertex.along(v0, d, t1), v1), raster)

def line.bounds(+x: F32, +y: F32, +z: F32, +w: F32, +dx: F32, +dy: F32, +dz: F32, +nw: F32) -> Bounds:
  lb.coord((w + z : F32), (nw - dz : F32), lb.coord((w - z : F32), (nw + dz : F32),
    lb.coord((w + y : F32), (nw - dy : F32), lb.coord((w - y : F32), (nw + dy : F32),
    lb.coord((w + x : F32), (nw - dx : F32), lb.coord((w - x : F32), (nw + dx : F32), Bounds{0.0, 1.0, True{}}))))))

# The scissor's Liang-Barsky terms, after the frustum's: x min, x max, y min,
# y max against the clip-space bounds times w.
def line.scissor(enabled: Bool, +x: F32, +y: F32, +w: F32, +dx: F32, +dy: F32, +dw: F32, +cx0: F32, +cx1: F32, +cy0: F32, +cy1: F32, bounds: Bounds) -> Bounds:
  match enabled:
    case False{}: bounds
    case True{}:
      lb.coord(((cy1 * w : F32) - y : F32), (dy - (cy1 * dw : F32) : F32), lb.coord((y - (cy0 * w : F32) : F32), ((cy0 * dw : F32) - dy : F32),
        lb.coord(((cx1 * w : F32) - x : F32), (dx - (cx1 * dw : F32) : F32), lb.coord((x - (cx0 * w : F32) : F32), ((cx0 * dw : F32) - dx : F32), bounds))))

def line.planes.with(+scissor: Scissor, +x: F32, +y: F32, +z: F32, +w: F32, +dx: F32, +dy: F32, +dz: F32, +dw: F32) -> Bounds:
  Scissor{enabled, _, _, _, _, cx0, cx1, cy0, cy1} = scissor
  line.scissor(enabled, x, y, w, dx, dy, dw, cx0, cx1, cy0, cy1, line.bounds(x, y, z, w, dx, dy, dz, F32.neg(dw)))

def line.planes(+scissor: Scissor, +v0: Vertex, +d: Vertex) -> Bounds:
  Vertex{x, y, z, w, _, _, _, _, _, _} = v0
  Vertex{dx, dy, dz, dw, _, _, _, _, _, _} = d
  line.planes.with(scissor, x, y, z, w, dx, dy, dz, dw)

def line.clip.with(+blend: Bool, +width: U32, +height: U32, +scissor: Scissor, +v0: Vertex, +v1: Vertex, +d: Vertex, raster: Raster) -> Raster:
  line.clipped(line.planes(scissor, v0, d), blend, width, height, v0, v1, d, raster)

# sw_line_clip: six Liang-Barsky planes on (w -+ coordinate), then the
# scissor's four when it is enabled; d = v1 - v0.
def line.clip(+blend: Bool, +width: U32, +height: U32, +scissor: Scissor, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  line.clip.with(blend, width, height, scissor, v0, v1, Vertex.grad(v0, v1, 1.0), raster)

# -----------------------------------------------------------------------------
# Primitive rendering (sw_triangle_render, sw_quad_render, sw_line_render)

# sw_triangle_face_culling with SW_BACK: kept when the (x, y, w) determinant
# is positive (clockwise, zero-area and NaN primitives are dropped).
def cull.keep(+p0: Vertex, +p1: Vertex, +p2: Vertex) -> Bool:
  +area = (Vertex.x(p0) * (Vertex.y(p1) * Vertex.w(p2) - Vertex.y(p2) * Vertex.w(p1))
    + Vertex.x(p1) * (Vertex.y(p2) * Vertex.w(p0) - Vertex.y(p0) * Vertex.w(p2))
    + Vertex.x(p2) * (Vertex.y(p0) * Vertex.w(p1) - Vertex.y(p1) * Vertex.w(p0)) : F32)
  (area > 0.0 : F32)

def fan.one(more: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, +first: Vertex, +b: Vertex, raster: Raster) -> Raster:
  match more:
    case Nil{}: raster
    case Con{+c, _}: triangle(tex, blend, width, height, first, b, c, raster)

def fan.loop(rest: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, +first: Vertex, raster: Raster) -> Raster:
  match rest:
    case Nil{}: raster
    case Con{+b, +more}: fan.loop(more, tex, blend, width, height, first, fan.one(more, tex, blend, width, height, first, b, raster))

def fan(polygon: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, raster: Raster) -> Raster:
  match polygon:
    case Nil{}: raster
    case Con{+first, rest}: fan.loop(rest, tex, blend, width, height, first, raster)

def Vertex.aligned(+a: Vertex, +b: Vertex) -> Bool:
  (F32.abs((Vertex.y(b) - Vertex.y(a) : F32)) < 0.5 : F32) || (F32.abs((Vertex.x(b) - Vertex.x(a) : F32)) < 0.5 : F32)

# sw_quad_is_axis_aligned: affine (w == 1) and every edge within 0.5 px of an axis.
def quad.aligned(+a: Vertex, +b: Vertex, +c: Vertex, +d: Vertex) -> Bool:
  F32.is_eq(Vertex.w(a), 1.0) && F32.is_eq(Vertex.w(b), 1.0) && F32.is_eq(Vertex.w(c), 1.0) && F32.is_eq(Vertex.w(d), 1.0)
    && Vertex.aligned(a, b) && Vertex.aligned(b, c) && Vertex.aligned(c, d) && Vertex.aligned(d, a)

def quad.four(polygon: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, raster: Raster) -> Raster:
  match polygon:
    case Con{+a, Con{+b, Con{+c, Con{+d, Nil{}}}}}: quad.raster(tex, blend, width, height, a, b, c, d, raster)
    case _: raster

def quad.box_or_fan(aligned: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, polygon: +List<Vertex>, raster: Raster) -> Raster:
  match aligned:
    case False{}: fan(polygon, tex, blend, width, height, raster)
    case True{}: quad.four(polygon, tex, blend, width, height, raster)

def quad.projected(polygon: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, raster: Raster) -> Raster:
  match polygon:
    case Con{+a, Con{+b, Con{+c, Con{+d, Nil{}}}}}: quad.box_or_fan(quad.aligned(a, b, c, d), tex, blend, width, height, polygon, raster)
    case _: fan(polygon, tex, blend, width, height, raster)

def render.kind(quad: Bool, polygon: +List<Vertex>, +tex: U32, +blend: Bool, +width: U32, +height: U32, raster: Raster) -> Raster:
  match quad:
    case False{}: fan(polygon, tex, blend, width, height, raster)
    case True{}: quad.projected(polygon, tex, blend, width, height, raster)

def render.clipped(+quad: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  render.kind(quad, project.all(width, height, clip.polygon(scissor, polygon)), tex, blend, width, height, raster)

def render.culled(keep: Bool, +quad: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  match keep:
    case False{}: raster
    case True{}: render.clipped(quad, tex, blend, width, height, scissor, polygon, raster)

def render.polygon(+quad: Bool, +tex: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  match polygon:
    case Con{+a, Con{+b, Con{+c, +rest}}}: render.culled(cull.keep(a, b, c), quad, tex, blend, width, height, scissor, Con{a, Con{b, Con{c, rest}}}, raster)
    case _: raster

def render.line(+blend: Bool, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  match vertices:
    case Con{+a, Con{+b, _}}: line.clip(blend, width, height, scissor, a, b, raster)
    case _: raster

def render(mode: U32, +tex: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  match mode:
    case 2: render.line(blend, width, height, scissor, vertices, raster)
    case 3: render.polygon(False{}, tex, blend, width, height, scissor, vertices, raster)
    case _: render.polygon(True{}, tex, blend, width, height, scissor, vertices, raster)

# -----------------------------------------------------------------------------
# The rlgl immediate path: rlBegin/rlColor4ub/rlTexCoord2f/rlVertex2f/rlEnd
# and rlSetTexture reach swBegin/swColor4ub/... directly (no render batch);
# a primitive renders when its last vertex arrives (2 lines, 3 triangles,
# 4 quads). The current color and texcoord persist across primitives, and
# a primitive blends when its texture has alpha (the atlas always does) or
# when a color with alpha below 1 was set since the previous primitive.
# rlPushMatrix/rlPopMatrix/rlLoadIdentity/rlMultMatrixf (and the translate,
# rotate and scale matrices built by the caller) act on the modelview stack.

type Command is Data:
  Begin{count: U32}
  Color{color: U32}
  TexCoord{u: F32, v: F32}
  Point{x: F32, y: F32}
  Texture{kind: U32}
  End{}
  Push{}
  Pop{}
  Identity{}
  Multiply{matrix: Matrix4}

# bound: what rlSetTexture bound (0 none, 1 the shapes atlas, 2 a user texture
# with alpha, 3 an opaque one, 4 one without pixels, which rlsw treats as no
# texture); textured: the sampler captured by swBegin (0 none, 1 atlas, 2 user).
type Immediate is Data:
  Immediate{mode: U32, bound: U32, textured: U32, alpha: Bool, paint: Attr, pending: +List<Vertex>, count: U32}

# swInit: white, texcoord (0, 0), no primitive, texture disabled.
def Immediate.initial() -> Immediate:
  Immediate{0, 0, 0, False{}, Attr{1.0, 1.0, 1.0, 1.0, 0.0, 0.0}, Nil{}, 0}

def bound.sampler(bound: U32) -> U32:
  match bound:
    case 1: 1
    case 2: 2
    case 3: 2
    case _: 0

# A complete bound texture whose alpha mode is not SW_PIXEL_ALPHA_NONE.
def bound.alpha(bound: U32) -> Bool:
  match bound:
    case 1: True{}
    case 2: True{}
    case _: False{}

# -----------------------------------------------------------------------------
# Render state: rlsw's projection and modelview stacks (the projection has a
# single entry raylib reloads; the modelview holds at most 8), the scissor, and
# the texture (128 slots, id 1 the default font) and framebuffer (8 slots) id
# pools: sw_pool_alloc reuses the most recently freed id, else the next fresh
# one, and fails (id 0) when full.

type Pool is Data:
  Pool{next: U32, capacity: U32, free: +List<U32>}

type Rig is Data:
  Rig{projection: Matrix4, modelview: +List<Matrix4>, depth: U32, scissor: Scissor, textures: Pool, framebuffers: Pool}

# A render texture's ids and color texture state while it is the target.
type RenderTarget is Data:
  RenderTarget{id: U32, color: U32, depth: U32, linear: Bool, alpha: Bool}

# The color buffer drawn: the screen, or a render texture with the screen's
# size and pixels set aside.
type Target is Type:
  Screen{}
  Offscreen{width: U32, height: U32, pixels: Array<U32>, meta: RenderTarget}

# A render texture's color buffer handed back by EndTextureMode.
type Detached is Type:
  Detached{meta: RenderTarget, width: U32, height: U32, texels: Array<U32>}

type Canvas is Type:
  Canvas{width: U32, height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target}

def depth(+count: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))

# swOrtho(0, width, height, 0, 0, 1) on an identity projection.
def Matrix4.projection(+width: U32, +height: U32) -> Matrix4:
  Matrix4.mul(Matrix4.identity(), Matrix4.ortho(width, height))

def Pool.take.fresh(room: Bool, +next: U32, +capacity: U32) -> Pool & U32:
  match room:
    case True{}: (Pool{(next + 1 : U32), capacity, Nil{}}, next)
    case False{}: (Pool{next, capacity, Nil{}}, 0)

def Pool.take.from(free: +List<U32>, +next: U32, +capacity: U32) -> Pool & U32:
  match free:
    case Con{+id, rest}: (Pool{next, capacity, rest}, id)
    case Nil{}: Pool.take.fresh((next < capacity : U32), next, capacity)

# sw_pool_alloc: id 0 when the pool is full.
def Pool.take(pool: Pool) -> Pool & U32:
  Pool{next, capacity, free} = pool
  Pool.take.from(free, next, capacity)

# sw_pool_free: the id is the next one reused.
def Pool.give(+id: U32, pool: Pool) -> Pool:
  Pool{next, capacity, free} = pool
  Pool{next, capacity, Con{id, free}}

def Pool.count(free: +List<U32>, +n: U32) -> U32:
  match free:
    case Nil{}: n
    case Con{_, rest}: Pool.count(rest, (n + 1 : U32))

# Ids sw_pool_alloc can still return.
def Pool.room(pool: Pool) -> U32:
  Pool{next, capacity, free} = pool
  (Pool.count(free, 0) + (capacity - next) : U32)

def Rig.initial(+width: U32, +height: U32) -> Rig:
  Rig{Matrix4.projection(width, height), [Matrix4.identity()], 1, Scissor.set(False{}, 0.0, 0.0, U32.to_f32(width), U32.to_f32(height), U32.to_f32(width), U32.to_f32(height)),
    Pool{2, 128, Nil{}}, Pool{1, 8, Nil{}}}

def Rig.top(modelview: +List<Matrix4>) -> Matrix4:
  match modelview:
    case Con{+top, _}: top
    case Nil{}: Matrix4.identity()

# The MVP swBegin computes: mul(modelview top, projection top).
def Rig.mvp(+rig: Rig) -> Matrix4:
  Rig{projection, modelview, _, _, _, _} = rig
  Matrix4.mul(Rig.top(modelview), projection)

def Rig.scissor(+rig: Rig) -> Scissor:
  Rig{_, _, _, scissor, _, _} = rig
  scissor

def Rig.depth(+rig: Rig) -> U32:
  Rig{_, _, depth, _, _, _} = rig
  depth

def Rig.top.set(modelview: +List<Matrix4>, +matrix: Matrix4) -> +List<Matrix4>:
  match modelview:
    case Con{_, rest}: Con{matrix, rest}
    case Nil{}: [matrix]

def Rig.top.mul(modelview: +List<Matrix4>, +matrix: Matrix4) -> +List<Matrix4>:
  match modelview:
    case Con{+top, rest}: Con{Matrix4.mul(matrix, top), rest}
    case Nil{}: [matrix]

def Rig.top.push(modelview: +List<Matrix4>) -> +List<Matrix4>:
  match modelview:
    case Con{+top, rest}: Con{top, Con{top, rest}}
    case Nil{}: Nil{}

def Rig.top.pop(modelview: +List<Matrix4>) -> +List<Matrix4>:
  match modelview:
    case Con{_, rest}: rest
    case Nil{}: Nil{}

# swLoadIdentity on the modelview.
def Rig.identity(rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, Rig.top.set(modelview, Matrix4.identity()), depth, scissor, textures, framebuffers}

# swMultMatrixf (and the translate, rotate and scale matrices): M = mul(T, M).
def Rig.multiply(+matrix: Matrix4, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, Rig.top.mul(modelview, matrix), depth, scissor, textures, framebuffers}

def Rig.pushed(rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, Rig.top.push(modelview), (depth + 1 : U32), scissor, textures, framebuffers}

def Rig.popped(rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, Rig.top.pop(modelview), (depth - 1 : U32), scissor, textures, framebuffers}

# swPushMatrix: a full stack (8) is an error that changes nothing.
def Rig.push(+rig: Rig) -> Rig:
  Bool.pick(Rig, (Rig.depth(rig) < 8 : U32), Rig.pushed(rig), rig)

# swPopMatrix of the last modelview entry leaves the current matrix pointing
# before the stack (undefined): refused.
def Rig.pop(+rig: Rig) -> Rig & Bool:
  +ok = (Rig.depth(rig) >= 2 : U32)
  (Bool.pick(Rig, ok, Rig.popped(rig), rig), ok)

def Rig.apply(command: Command, +rig: Rig) -> Rig & Bool:
  match command:
    case Push{}: (Rig.push(rig), True{})
    case Pop{}: Rig.pop(rig)
    case Identity{}: (Rig.identity(rig), True{})
    case Multiply{matrix}: (Rig.multiply(matrix, rig), True{})
    case _: (rig, True{})

# The viewport and projection of a width x height color buffer (rlViewport,
# then rlOrtho on an identity projection) with an identity modelview, as
# BeginTextureMode and EndTextureMode's SetupViewport leave them.
def Rig.view(+width: U32, +height: U32, rig: Rig) -> Rig:
  Rig{_, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{Matrix4.projection(width, height), Rig.top.set(modelview, Matrix4.identity()), depth, scissor, textures, framebuffers}

# rlScissor(x, height - (y + h), w, h) after rlEnableScissorTest: negative
# sizes are rejected by swScissor, which keeps the previous rectangle.
def Scissor.begin(valid: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +vw: F32, +vh: F32, scissor: Scissor) -> Scissor:
  match valid:
    case False{}: Scissor.enable(True{}, scissor)
    case True{}: Scissor.set(True{}, x, y, w, h, vw, vh)

def Rig.scissor.begin(+x: F32, +y: F32, +w: F32, +h: F32, +width: U32, +height: U32, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, modelview, depth, Scissor.begin((w >= 0.0 : F32) && (h >= 0.0 : F32), x, (U32.to_f32(height) - (y + h : F32) : F32), w, h,
    U32.to_f32(width), U32.to_f32(height), scissor), textures, framebuffers}

def Rig.scissor.end(rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, modelview, depth, Scissor.enable(False{}, scissor), textures, framebuffers}

def Rig.take.texture.with(projection: Matrix4, modelview: +List<Matrix4>, depth: U32, scissor: Scissor, framebuffers: Pool, taken: Pool & U32) -> Rig & U32:
  (textures, id) = taken
  (Rig{projection, modelview, depth, scissor, textures, framebuffers}, id)

def Rig.take.texture(rig: Rig) -> Rig & U32:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig.take.texture.with(projection, modelview, depth, scissor, framebuffers, Pool.take(textures))

def Rig.take.framebuffer.with(projection: Matrix4, modelview: +List<Matrix4>, depth: U32, scissor: Scissor, textures: Pool, taken: Pool & U32) -> Rig & U32:
  (framebuffers, id) = taken
  (Rig{projection, modelview, depth, scissor, textures, framebuffers}, id)

def Rig.take.framebuffer(rig: Rig) -> Rig & U32:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig.take.framebuffer.with(projection, modelview, depth, scissor, textures, Pool.take(framebuffers))

def Rig.take(framebuffer: Bool, rig: Rig) -> Rig & U32:
  match framebuffer:
    case False{}: Rig.take.texture(rig)
    case True{}: Rig.take.framebuffer(rig)

def Rig.give(+framebuffer: Bool, +id: U32, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, +textures, +framebuffers} = rig
  Rig{projection, modelview, depth, scissor, Bool.pick(Pool, framebuffer, textures, Pool.give(id, textures)),
    Bool.pick(Pool, framebuffer, Pool.give(id, framebuffers), framebuffers)}

def Rig.room(+rig: Rig) -> U32:
  Rig{_, _, _, _, textures, _} = rig
  Pool.room(textures)

# -----------------------------------------------------------------------------
# Canvas: the current color buffer, its MVP and immediate state, the raster
# and render state, and the target.

def Canvas.build(+width: U32, +height: U32, state: Immediate, raster: Raster, +rig: Rig, target: Target) -> Canvas:
  Canvas{width, height, Rig.mvp(rig), state, raster, rig, target}

# rlClearColor (byte/255) stored by sw_framebuffer_fill_color.
def clear.word(+color: U32) -> U32 & Bool:
  pack((U32.to_f32((color >> 24n : U32)) / 255.0 : F32), (U32.to_f32(((color >> 16n) .&. 255 : U32)) / 255.0 : F32),
    (U32.to_f32(((color >> 8n) .&. 255 : U32)) / 255.0 : F32), (U32.to_f32((color .&. 255 : U32)) / 255.0 : F32))

def clear.fill(+count: U32, packed: U32 & Bool, raster: Raster) -> Raster:
  (+word, valid) = packed
  Raster{_, atlas, sampler, ok} = raster
  Raster{Array.new(U32, depth(count), word), atlas, sampler, ok && valid}

def clear.cols(n: Nat, +offset: U32, +word: U32, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: clear.cols(rest, (offset + 1 : U32), word, store(offset, (word, True{}), raster))

def clear.rows(n: Nat, +row: U32, +width: U32, +x: U32, +cols: Nat, +word: U32, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: clear.rows(rest, (row + 1 : U32), width, x, cols, word, clear.cols(cols, (row * width + x : U32), word, raster))

# sw_clamp_int(v, 0, high)
def clamp.low(+v: F32, +high: F32) -> F32:
  Bool.pick(F32, (v < 0.0 : F32), 0.0, Bool.pick(F32, (v > high : F32), high, v))

# With the scissor test, sw_framebuffer_fill_color fills the clamped
# rectangle from its minimum to its maximum corner inclusive: one pixel more
# than the scissor in each direction, and at least one pixel.
def clear.rect(+width: U32, +height: U32, +scissor: Scissor, packed: U32 & Bool, raster: Raster) -> Raster:
  Scissor{_, +x0, +y0, +x1, +y1, _, _, _, _} = scissor
  (+word, valid) = packed
  +right = U32.to_f32((width - 1 : U32))
  +top = U32.to_f32((height - 1 : U32))
  +xmin = clamp.low(x0, right)
  +ymin = clamp.low(y0, top)
  clear.rows(U32.to_nat(F32.to_u32(((clamp.low(y1, top) - ymin : F32) + 1.0 : F32))), F32.to_u32(ymin), width, F32.to_u32(xmin),
    U32.to_nat(F32.to_u32(((clamp.low(x1, right) - xmin : F32) + 1.0 : F32))), word, Raster.require(valid, raster))

def clear.select(enabled: Bool, +width: U32, +height: U32, +scissor: Scissor, packed: U32 & Bool, raster: Raster) -> Raster:
  match enabled:
    case False{}: clear.fill((width * height : U32), packed, raster)
    case True{}: clear.rect(width, height, scissor, packed, raster)

# ClearBackground: glClear on the current color buffer.
def Canvas.clear(+color: U32, canvas: Canvas) -> Canvas:
  Canvas{+width, +height, matrix, state, raster, +rig, target} = canvas
  +scissor = Rig.scissor(rig)
  Canvas{width, height, matrix, state, clear.select(Scissor.enabled(scissor), width, height, scissor, clear.word(color), raster), rig, target}

# rlglInit: swInit, then glClear with the clear color (0, 0, 0, 1).
def Canvas.new(+width: U32, +height: U32) -> Canvas:
  Canvas.clear(255, Canvas.build(width, height, Immediate.initial(), Raster{Array.new(U32, 0n, 0), Font.atlas(), Unbound{}, True{}},
    Rig.initial(width, height), Screen{}))

def Canvas.adjusted(+width: U32, +height: U32, state: Immediate, raster: Raster, target: Target, result: Rig & Bool) -> Canvas:
  (+rig, valid) = result
  Canvas.build(width, height, state, Raster.require(valid, raster), rig, target)

# A matrix command on the modelview stack; the MVP follows.
def Canvas.adjust(command: Command, canvas: Canvas) -> Canvas:
  Canvas{width, height, _, state, raster, rig, target} = canvas
  Canvas.adjusted(width, height, state, raster, target, Rig.apply(command, rig))

# BeginDrawing: rlLoadIdentity and rlMultMatrixf(identity screen scale) on the
# modelview.
def Canvas.reset(canvas: Canvas) -> Canvas:
  Canvas.adjust(Identity{}, canvas)

# BeginMode2D: rlLoadIdentity, then rlMultMatrixf(GetCameraMatrix2D).
def Canvas.camera(+matrix: Matrix4, canvas: Canvas) -> Canvas:
  Canvas.adjust(Multiply{matrix}, Canvas.adjust(Identity{}, canvas))

def Canvas.target.size(target: Target, +width: U32, +height: U32) -> Target & (U32 & U32):
  match target:
    case Screen{}: (Screen{}, (width, height))
    case Offscreen{+sw, +sh, pixels, meta}: (Offscreen{sw, sh, pixels, meta}, (sw, sh))

def Canvas.sized(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, result: Target & (U32 & U32)) -> Canvas & (U32 & U32):
  (target, size) = result
  (Canvas{width, height, matrix, state, raster, rig, target}, size)

# The screen's size (also while a render texture is the target).
def Canvas.dimensions(canvas: Canvas) -> Canvas & (U32 & U32):
  Canvas{+width, +height, matrix, state, raster, rig, target} = canvas
  Canvas.sized(width, height, matrix, state, raster, rig, Canvas.target.size(target, width, height))

def Canvas.target.offscreen(target: Target) -> Target & Bool:
  match target:
    case Screen{}: (Screen{}, False{})
    case Offscreen{sw, sh, pixels, meta}: (Offscreen{sw, sh, pixels, meta}, True{})

def Canvas.flagged(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, result: Target & Bool) -> Canvas & Bool:
  (target, flag) = result
  (Canvas{width, height, matrix, state, raster, rig, target}, flag)

# Whether a render texture is the target.
def Canvas.offscreen(canvas: Canvas) -> Canvas & Bool:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas.flagged(width, height, matrix, state, raster, rig, Canvas.target.offscreen(target))

# BeginScissorMode's rlScissor for C ints x, y, w, h (the caller bounds them):
# y from the bottom of the current color buffer, clip-space bounds from the
# current viewport.
def Canvas.scissor(+x: F32, +y: F32, +w: F32, +h: F32, canvas: Canvas) -> Canvas:
  Canvas{+width, +height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, raster, Rig.scissor.begin(x, y, w, h, width, height, rig), target}

# EndScissorMode: rlDisableScissorTest.
def Canvas.unscissor(canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, raster, Rig.scissor.end(rig), target}

def Canvas.target.enter(meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, +width: U32, +height: U32, state: Immediate, raster: Raster, rig: Rig) -> Canvas:
  Raster{pixels, atlas, sampler, ok} = raster
  Canvas.build(tw, th, state, Raster{texels, atlas, sampler, ok}, Rig.view(tw, th, rig), Offscreen{width, height, pixels, meta})

def Canvas.target.begin(target: Target, meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig) -> Canvas:
  match target:
    case Screen{}: Canvas.target.enter(meta, tw, th, texels, width, height, state, raster, rig)
    case Offscreen{sw, sh, pixels, active}: Canvas{width, height, matrix, state, Raster.refuse(raster), rig, Offscreen{sw, sh, pixels, active}}

# BeginTextureMode: the render texture's color buffer becomes the target,
# with its viewport and orthographic projection and an identity modelview; the
# scissor keeps the clip-space bounds computed for the previous viewport.
# Starting a texture mode while one is active is refused (the frame becomes
# undefined and the second target is dropped).
def Canvas.begin_target(meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas.target.begin(target, meta, tw, th, texels, width, height, matrix, state, raster, rig)

def Canvas.target.leave(+sw: U32, +sh: U32, screen: Array<U32>, meta: RenderTarget, +tw: U32, +th: U32, state: Immediate, raster: Raster, rig: Rig) -> Canvas & Maybe<Detached>:
  Raster{texels, atlas, sampler, ok} = raster
  (Canvas.build(sw, sh, state, Raster{screen, atlas, sampler, ok}, Rig.view(sw, sh, rig), Screen{}), Some{Detached{meta, tw, th, texels}})

def Canvas.target.end(target: Target, +width: U32, +height: U32, state: Immediate, raster: Raster, rig: Rig) -> Canvas & Maybe<Detached>:
  match target:
    case Screen{}: (Canvas.build(width, height, state, raster, Rig.view(width, height, rig), Screen{}), None{})
    case Offscreen{sw, sh, screen, meta}: Canvas.target.leave(sw, sh, screen, meta, width, height, state, raster, rig)

# EndTextureMode: back to the screen's color buffer, viewport and projection
# (SetupViewport) with an identity modelview; the render texture's color
# buffer is handed back. Without a texture mode the state is reset the same.
def Canvas.end_target(canvas: Canvas) -> Canvas & Maybe<Detached>:
  Canvas{width, height, _, state, raster, rig, target} = canvas
  Canvas.target.end(target, width, height, state, raster, rig)

def Canvas.rigged(width: U32, height: U32, matrix: Matrix4, state: Immediate, raster: Raster, target: Target, result: Rig & U32) -> Canvas & U32:
  (rig, id) = result
  (Canvas{width, height, matrix, state, raster, rig, target}, id)

# swGenTextures (framebuffer False) or swGenFramebuffers: 0 when full.
def Canvas.take(framebuffer: Bool, canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas.rigged(width, height, matrix, state, raster, target, Rig.take(framebuffer, rig))

# swDeleteTextures / swDeleteFramebuffers of a live id.
def Canvas.give(framebuffer: Bool, +id: U32, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, raster, Rig.give(framebuffer, id, rig), target}

# Texture ids still available.
def Canvas.room(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, +rig, target} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target}, Rig.room(rig))

def Immediate.started(+mode: U32, state: Immediate) -> Immediate:
  Immediate{_, +bound, _, _, paint, _, _} = state
  Immediate{mode, bound, bound.sampler(bound), False{}, paint, Nil{}, 0}

def Immediate.mode.of(+state: Immediate) -> U32:
  Immediate{mode, _, _, _, _, _, _} = state
  mode

# swBegin is refused (state unchanged) while a primitive is being recorded.
def Immediate.begin(+mode: U32, +state: Immediate) -> Immediate:
  Bool.pick(Immediate, U32.is_eq(Immediate.mode.of(state), 0), Immediate.started(mode, state), state)

def Immediate.end(state: Immediate) -> Immediate:
  Immediate{_, bound, textured, alpha, paint, pending, count} = state
  Immediate{0, bound, textured, alpha, paint, pending, count}

def Immediate.texture(+kind: U32, state: Immediate) -> Immediate:
  Immediate{mode, _, textured, alpha, paint, pending, count} = state
  Immediate{mode, kind, textured, alpha, paint, pending, count}

# swColor4ub: byte*SW_INV_255; any alpha below 1 marks the primitive.
def Immediate.color(+color: U32, state: Immediate) -> Immediate:
  Immediate{mode, bound, textured, alpha, paint, pending, count} = state
  Attr{_, _, _, _, u, v} = paint
  +a = lut((color .&. 255 : U32))
  Immediate{mode, bound, textured, alpha || (a < 1.0 : F32),
    Attr{lut((color >> 24n : U32)), lut(((color >> 16n) .&. 255 : U32)), lut(((color >> 8n) .&. 255 : U32)), a, u, v}, pending, count}

# sw_immediate_set_texcoord with the identity texture matrix.
def Immediate.texcoord(+u: F32, +v: F32, state: Immediate) -> Immediate:
  Immediate{mode, bound, textured, alpha, paint, pending, count} = state
  Attr{r, g, b, a, _, _} = paint
  Immediate{mode, bound, textured, alpha, Attr{r, g, b, a, (1.0 * u + 0.0 * v + 0.0 : F32), (0.0 * u + 1.0 * v + 0.0 : F32)}, pending, count}

def Canvas.with_state(state: Immediate, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, _, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, raster, rig, target}

def Canvas.render(+mode: U32, +textured: U32, +alpha: Bool, +bound: U32, +paint: Attr, pending: +List<Vertex>, canvas: Canvas) -> Canvas:
  Canvas{+width, +height, matrix, _, raster, +rig, target} = canvas
  Canvas{width, height, matrix, Immediate{mode, bound, textured, False{}, paint, Nil{}, 0},
    render(mode, textured, alpha || bound.alpha(bound), width, height, Rig.scissor(rig), List.reverse(&2, Vertex, pending), raster), rig, target}

def Canvas.emit(full: Bool, +mode: U32, +textured: U32, +alpha: Bool, +bound: U32, +paint: Attr, pending: +List<Vertex>, +count: U32, canvas: Canvas) -> Canvas:
  match full:
    case False{}: Canvas.with_state(Immediate{mode, bound, textured, alpha, paint, pending, count}, canvas)
    case True{}: Canvas.render(mode, textured, alpha, bound, paint, pending, canvas)

def Canvas.vertex(+vertex: Vertex, state: Immediate, canvas: Canvas) -> Canvas:
  Immediate{+mode, +bound, +textured, +alpha, +paint, pending, +count} = state
  Canvas.emit(U32.is_eq((count + 1 : U32), mode), mode, textured, alpha, bound, paint, Con{vertex, pending}, (count + 1 : U32), canvas)

def Immediate.paint(+state: Immediate) -> Attr:
  Immediate{_, _, _, _, paint, _, _} = state
  paint

def Matrix4.point(+matrix: Matrix4, +x: F32, +y: F32, +paint: Attr) -> Vertex:
  Attr{r, g, b, a, u, v} = paint
  Matrix4.vertex(matrix, x, y, r, g, b, a, u, v)

# sw_immediate_push_vertex: clip coordinates from the MVP, current attributes.
def Canvas.point(+x: F32, +y: F32, canvas: Canvas) -> Canvas:
  Canvas{width, height, +matrix, +state, raster, rig, target} = canvas
  Canvas.vertex(Matrix4.point(matrix, x, y, Immediate.paint(state)), state, Canvas{width, height, matrix, state, raster, rig, target})

def Canvas.mode(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, +state, raster, rig, target} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target}, Immediate.mode.of(state))

def Canvas.update(command: Command, state: Immediate) -> Immediate:
  match command:
    case Begin{count}: Immediate.begin(count, state)
    case Color{color}: Immediate.color(color, state)
    case TexCoord{u, v}: Immediate.texcoord(u, v, state)
    case Texture{kind}: Immediate.texture(kind, state)
    case End{}: Immediate.end(state)
    case _: state

def Canvas.step.state(command: Command, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, Canvas.update(command, state), raster, rig, target}

def Canvas.point.active(active: Bool, +x: F32, +y: F32, canvas: Canvas) -> Canvas:
  match active:
    case False{}: canvas
    case True{}: Canvas.point(x, y, canvas)

def Canvas.step.point(+x: F32, +y: F32, read: Canvas & U32) -> Canvas:
  (canvas, +mode) = read
  Canvas.point.active(Bool.not(U32.is_eq(mode, 0)), x, y, canvas)

def Canvas.step(+command: Command, canvas: Canvas) -> Canvas:
  match command:
    case Point{x, y}: Canvas.step.point(x, y, Canvas.mode(canvas))
    case Begin{count}: Canvas.step.state(Begin{count}, canvas)
    case Color{color}: Canvas.step.state(Color{color}, canvas)
    case TexCoord{u, v}: Canvas.step.state(TexCoord{u, v}, canvas)
    case Texture{kind}: Canvas.step.state(Texture{kind}, canvas)
    case End{}: Canvas.step.state(End{}, canvas)
    case Push{}: Canvas.adjust(Push{}, canvas)
    case Pop{}: Canvas.adjust(Pop{}, canvas)
    case Identity{}: Canvas.adjust(Identity{}, canvas)
    case Multiply{matrix}: Canvas.adjust(Multiply{matrix}, canvas)

def Canvas.run(commands: +List<Command>, canvas: Canvas) -> Canvas:
  match commands:
    case Nil{}: canvas
    case Con{command, rest}: Canvas.run(rest, Canvas.step(command, canvas))

# Marks the canvas undefined (a draw Jonlib refuses, such as an unverified
# libm argument) without drawing.
def Canvas.refuse(canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, Raster.refuse(raster), rig, target}

def Canvas.draw(valid: Bool, commands: +List<Command>, canvas: Canvas) -> Canvas:
  match valid:
    case False{}: Canvas.refuse(canvas)
    case True{}: Canvas.run(commands, canvas)

def Raster.bind(sampler: Sampler, raster: Raster) -> Raster:
  Raster{pixels, atlas, _, ok} = raster
  Raster{pixels, atlas, sampler, ok}

def Raster.unbind(raster: Raster) -> Raster & Sampler:
  Raster{pixels, atlas, sampler, ok} = raster
  (Raster{pixels, atlas, Unbound{}, ok}, sampler)

def Canvas.unbound(width: U32, height: U32, matrix: Matrix4, state: Immediate, rig: Rig, target: Target, result: Raster & Sampler) -> Canvas & Sampler:
  (raster, sampler) = result
  (Canvas{width, height, matrix, state, raster, rig, target}, sampler)

def Canvas.unbind(canvas: Canvas) -> Canvas & Sampler:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas.unbound(width, height, matrix, state, rig, target, Raster.unbind(raster))

def Canvas.bind(sampler: Sampler, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  Canvas{width, height, matrix, state, Raster.bind(sampler, raster), rig, target}

# A draw with a user texture's texels bound for its duration (the texture is
# handed back).
def Canvas.draw_sampled(valid: Bool, commands: +List<Command>, sampler: Sampler, canvas: Canvas) -> Canvas & Sampler:
  Canvas.unbind(Canvas.draw(valid, commands, Canvas.bind(sampler, canvas)))

# -----------------------------------------------------------------------------
# Readback: top-down canonical words; opaque forces alpha 255 like
# rlReadScreenPixels. None when any draw was refused or while a render
# texture is the target.

def read.copy(+index: U32, +mask: U32, out: Array<U32>, read: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (pixels, +word) = read
  (pixels, Array.set(U32, out, index, (word .|. mask : U32)))

def read.loop(n: Nat, +index: U32, +width: U32, +height: U32, +mask: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+rest Tuple{pixels, out}:
      read.loop(rest, (index + 1 : U32), width, height, mask,
        read.copy(index, mask, out, Array.get(U32, pixels, ((height - 1 - index / width) * width + index % width : U32))))

def read.result(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, atlas: Array<U32>, sampler: Sampler, rig: Rig, buffers: Array<U32> & Array<U32>) -> Canvas & Maybe<Array<U32>>:
  (pixels, out) = buffers
  (Canvas{width, height, matrix, state, Raster{pixels, atlas, sampler, True{}}, rig, Screen{}}, Some{out})

def read.checked(ok: Bool, +width: U32, +height: U32, +mask: U32, matrix: Matrix4, state: Immediate, rig: Rig, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler) -> Canvas & Maybe<Array<U32>>:
  match ok:
    case False{}: (Canvas{width, height, matrix, state, Raster{pixels, atlas, sampler, False{}}, rig, Screen{}}, None{})
    case True{}:
      +count = (width * height : U32)
      read.result(width, height, matrix, state, atlas, sampler, rig, read.loop(U32.to_nat(count), 0, width, height, mask, (pixels, Array.new(U32, depth(count), 0))))

def read.screen(+mask: U32, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, rig: Rig, raster: Raster) -> Canvas & Maybe<Array<U32>>:
  Raster{pixels, atlas, sampler, ok} = raster
  read.checked(ok, width, height, mask, matrix, state, rig, pixels, atlas, sampler)

def read.target(target: Target, +mask: U32, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig) -> Canvas & Maybe<Array<U32>>:
  match target:
    case Screen{}: read.screen(mask, width, height, matrix, state, rig, raster)
    case Offscreen{sw, sh, screen, meta}: (Canvas{width, height, matrix, state, raster, rig, Offscreen{sw, sh, screen, meta}}, None{})

def Canvas.read(+opaque: Bool, canvas: Canvas) -> Canvas & Maybe<Array<U32>>:
  Canvas{width, height, matrix, state, raster, rig, target} = canvas
  read.target(target, Bool.pick(U32, opaque, 255, 0), width, height, matrix, state, raster, rig)
