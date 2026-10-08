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

# Interpolated color, texture coordinates and depth of a pixel, or their step.
type Attr is Data:
  Attr{r: F32, g: F32, b: F32, a: F32, u: F32, v: F32, z: F32}

# Perspective-space accumulators of a triangle span (w, color, texcoord).
type Span is Data:
  Span{w: F32, r: F32, g: F32, b: F32, a: F32, u: F32, v: F32}

def Vertex.x(+v: Vertex) -> F32:
  Vertex{x, _, _, _, _, _, _, _, _, _} = v
  x

def Vertex.y(+v: Vertex) -> F32:
  Vertex{_, y, _, _, _, _, _, _, _, _} = v
  y

def Vertex.z(+v: Vertex) -> F32:
  Vertex{_, _, z, _, _, _, _, _, _, _} = v
  z

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
  Attr{ar, ag, ab, aa, au, av, az} = a
  Attr{dr, dg, db, da, du, dv, dz} = d
  Attr{(ar + dr : F32), (ag + dg : F32), (ab + db : F32), (aa + da : F32), (au + du : F32), (av + dv : F32), (az + dz : F32)}

def Attr.scale(a: Attr, +k: F32) -> Attr:
  Attr{r, g, b, aa, u, v, z} = a
  Attr{(r * k : F32), (g * k : F32), (b * k : F32), (aa * k : F32), (u * k : F32), (v * k : F32), (z * k : F32)}

def Attr.z(+a: Attr) -> F32:
  Attr{_, _, _, _, _, _, z} = a
  z

# swOrtho(0, width, height, 0, 0, 1) applied to an identity projection (rcore.c
# SetupViewport); BeginDrawing's identity modelview leaves it as the MVP.
def Matrix4.ortho(+width: U32, +height: U32) -> Matrix4:
  Matrix4{(2.0 / U32.to_f32(width) : F32), 0.0, 0.0, 0.0, 0.0, (2.0 / F32.neg(U32.to_f32(height)) : F32), 0.0, 0.0,
    0.0, 0.0, F32.neg(2.0), 0.0, F32.neg(1.0), 1.0, F32.neg(1.0), 1.0}

# sw_immediate_push_vertex: clip coordinates of (x, y, z, 1) (swVertex2f and
# swVertex2i pass z = 0).
def Matrix4.vertex(+m: Matrix4, +x: F32, +y: F32, +z: F32, +r: F32, +g: F32, +b: F32, +a: F32, +u: F32, +v: F32) -> Vertex:
  Matrix4{m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15} = m
  Vertex{(m0 * x + m4 * y + m8 * z + m12 * 1.0 : F32), (m1 * x + m5 * y + m9 * z + m13 * 1.0 : F32),
    (m2 * x + m6 * y + m10 * z + m14 * 1.0 : F32), (m3 * x + m7 * y + m11 * z + m15 * 1.0 : F32),
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

# The viewport transform of sw_project_ndc_to_screen: center + ndc*half + 0.5
# with half = size/2.0f and center = (float)x + half (swViewport).
type View is Data:
  View{cx: F32, cy: F32, hx: F32, hy: F32}

def View.of(+x: F32, +y: F32, +width: F32, +height: F32) -> View:
  +hx = (width / 2.0 : F32)
  +hy = (height / 2.0 : F32)
  View{(x + hx : F32), (y + hy : F32), hx, hy}

def project.view(+port: View, +v: Vertex) -> Vertex:
  View{cx, cy, hx, hy} = port
  project(cx, cy, hx, hy, v)

def project.loop(polygon: +List<Vertex>, +port: View, out: +List<Vertex>) -> +List<Vertex>:
  match polygon:
    case Nil{}: List.reverse(&2, Vertex, out)
    case Con{+v, rest}: project.loop(rest, port, Con{project.view(port, v), out})

def project.all(+port: View, polygon: +List<Vertex>) -> +List<Vertex>:
  project.loop(polygon, port, Nil{})

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

# The screen's depth buffer (F32 bits of rlsw's D32 buffer, bottom-up rows like
# the color buffer) and the user textures the frame holds: the shapes texture
# set by SetShapesTexture (slot 3) and the texture bound by rlSetTexture
# (slot 4); slot 2 is a texture bound for one Draw* call.
type Extra is Type:
  Extra{depth: Array<U32>, shapes: Sampler, held: Sampler}

type Raster is Type:
  Raster{pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra}

def Raster.refuse(raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, _, extra} = raster
  Raster{pixels, atlas, sampler, False{}, extra}

def Raster.require(valid: Bool, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Raster{pixels, atlas, sampler, ok && valid, extra}

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
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Raster{Array.set(U32, pixels, offset, word), atlas, sampler, ok && valid, extra}

# sw_blend_SRC_ALPHA_ONE_MINUS_SRC_ALPHA on the LUT-expanded destination.
def mix(+r: F32, +g: F32, +b: F32, +a: F32, +old: U32) -> U32 & Bool:
  +k = (1.0 - a : F32)
  pack((a * r + k * lut((old >> 24n : U32)) : F32), (a * g + k * lut(((old >> 16n) .&. 255 : U32)) : F32),
    (a * b + k * lut(((old >> 8n) .&. 255 : U32)) : F32), (a * a + k * lut((old .&. 255 : U32)) : F32))

def put.read(+offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra, read: Array<U32> & U32) -> Raster:
  (pixels, +old) = read
  store(offset, mix(r, g, b, a, old), Raster{pixels, atlas, sampler, ok, extra})

def put.blend(+offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  put.read(offset, r, g, b, a, atlas, sampler, ok, extra, Array.get(U32, pixels, offset))

def put(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, raster: Raster) -> Raster:
  match blend:
    case False{}: store(offset, pack(r, g, b, a), raster)
    case True{}: put.blend(offset, r, g, b, a, raster)

# sw_texture_sample_nearest on the 128x128 GRAY_ALPHA font atlas (REPEAT,
# NEAREST for both filters): returns the texel alpha; gray is always 255.
def sample.read(+bit: U32, inside: Bool, pixels: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra, read: Array<U32> & U32) -> Raster & F32:
  (atlas, +word) = read
  (Raster{pixels, atlas, sampler, ok && inside, extra}, lut((((word >> U32.to_nat(bit)) .&. 1) * 255 : U32)))

def sample.at(+slot: U32, inside: Bool, raster: Raster) -> Raster & F32:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  sample.read((slot .&. 31 : U32), inside, pixels, sampler, ok, extra, Array.get(U32, atlas, (slot >> 5n : U32)))

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
  Attr{r, g, b, a, u, v, _} = at
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

def sample.done(pixels: Array<U32>, atlas: Array<U32>, ok: Bool, extra: Extra, sampler: Sampler, rest: Texel & Bool) -> Raster & Texel:
  (texel, valid) = rest
  (Raster{pixels, atlas, sampler, ok && valid, extra}, texel)

def sample.rebuild(pixels: Array<U32>, atlas: Array<U32>, ok: Bool, extra: Extra, result: Sampler & (Texel & Bool)) -> Raster & Texel:
  (sampler, rest) = result
  sample.done(pixels, atlas, ok, extra, sampler, rest)

# A held texture (slot 3 shapes, 4 rlSetTexture) sampled in place.
def Extra.with(shapes_slot: Bool, depth: Array<U32>, other: Sampler, chosen: Sampler) -> Extra:
  match shapes_slot:
    case True{}: Extra{depth, chosen, other}
    case False{}: Extra{depth, other, chosen}

def sample.slot.rest(shapes_slot: Bool, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, depth: Array<U32>, other: Sampler, chosen: Sampler, rest: Texel & Bool) -> Raster & Texel:
  (texel, valid) = rest
  (Raster{pixels, atlas, sampler, ok && valid, Extra.with(shapes_slot, depth, other, chosen)}, texel)

def sample.slot.done(shapes_slot: Bool, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, depth: Array<U32>, other: Sampler, result: Sampler & (Texel & Bool)) -> Raster & Texel:
  (chosen, rest) = result
  sample.slot.rest(shapes_slot, pixels, atlas, sampler, ok, depth, other, chosen, rest)

def sample.slot.go(shapes_slot: Bool, +u: F32, +v: F32, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, depth: Array<U32>, shapes: Sampler, held: Sampler) -> Raster & Texel:
  match shapes_slot:
    case True{}: sample.slot.done(True{}, pixels, atlas, sampler, ok, depth, held, sample.sampler(u, v, shapes))
    case False{}: sample.slot.done(False{}, pixels, atlas, sampler, ok, depth, shapes, sample.sampler(u, v, held))

def sample.slot.pick(+slot: U32, +u: F32, +v: F32, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra) -> Raster & Texel:
  Extra{depth, shapes, held} = extra
  sample.slot.go(U32.is_eq(slot, 3), u, v, pixels, atlas, sampler, ok, depth, shapes, held)

def sample.user.at(temp: Bool, +slot: U32, +u: F32, +v: F32, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra) -> Raster & Texel:
  match temp:
    case True{}: sample.rebuild(pixels, atlas, ok, extra, sample.sampler(u, v, sampler))
    case False{}: sample.slot.pick(slot, u, v, pixels, atlas, sampler, ok, extra)

# A user texture in slot 2 (one Draw* call), 3 (the shapes texture) or 4
# (rlSetTexture).
def sample.user(+slot: U32, +u: F32, +v: F32, raster: Raster) -> Raster & Texel:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  sample.user.at(U32.is_eq(slot, 2), slot, u, v, pixels, atlas, sampler, ok, extra)

def pixel.user.mix(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, texel: Texel, raster: Raster) -> Raster:
  Texel{tr, tg, tb, ta} = texel
  put(blend, offset, (r * tr : F32), (g * tg : F32), (b * tb : F32), (a * ta : F32), raster)

def pixel.user.read(blend: Bool, +offset: U32, +r: F32, +g: F32, +b: F32, +a: F32, sampled: Raster & Texel) -> Raster:
  (raster, texel) = sampled
  pixel.user.mix(blend, offset, r, g, b, a, texel, raster)

# A user texture: the interpolated color times the sampled texel.
def pixel.user(+slot: U32, blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, u, v, _} = at
  pixel.user.read(blend, offset, r, g, b, a, sample.user(slot, u, v, raster))

def pixel.plain(blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Attr{r, g, b, a, _, _, _} = at
  put(blend, offset, r, g, b, a, raster)

def pixel.sampled(atlas: Bool, +tex: U32, blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match atlas:
    case True{}: pixel.textured(blend, offset, at, raster)
    case False{}: pixel.user(tex, blend, offset, at, raster)

def pixel.kind(plain: Bool, +tex: U32, blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match plain:
    case True{}: pixel.plain(blend, offset, at, raster)
    case False{}: pixel.sampled(U32.is_eq(tex, 1), tex, blend, offset, at, raster)

# tex: 0 untextured, 1 the shapes atlas, 2..4 a user texture slot.
def pixel.base(+tex: U32, blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  pixel.kind(U32.is_eq(tex, 0), tex, blend, offset, at, raster)

def depth.store(pass: Bool, +offset: U32, +z: F32, depth: Array<U32>) -> Array<U32>:
  match pass:
    case False{}: depth
    case True{}: Array.set(U32, depth, offset, F32.bits(z))

def pixel.depth.test(pass: Bool, +tex: U32, +blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match pass:
    case False{}: raster
    case True{}: pixel.base(tex, blend, offset, at, raster)

def pixel.depth.read(+tex: U32, +blend: Bool, +offset: U32, +at: Attr, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, shapes: Sampler, held: Sampler, read: Array<U32> & U32) -> Raster:
  (depth, +word) = read
  +z = Attr.z(at)
  +pass = Bool.not((z > float(word) : F32))
  pixel.depth.test(pass, tex, blend, offset, at, Raster{pixels, atlas, sampler, ok, Extra{depth.store(pass, offset, z, depth), shapes, held}})

def pixel.depth.extra(+tex: U32, +blend: Bool, +offset: U32, +at: Attr, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra) -> Raster:
  Extra{depth, shapes, held} = extra
  pixel.depth.read(tex, blend, offset, at, pixels, atlas, sampler, ok, shapes, held, Array.get(U32, depth, offset))

# The depth test of rlsw's DEPTH rasterizer variants: a fragment is discarded
# when z > the stored depth, otherwise z is stored (glDepthFunc and glDepthMask
# are no-ops in rlsw) before the color is written.
def pixel.depth(+tex: U32, +blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  pixel.depth.extra(tex, blend, offset, at, pixels, atlas, sampler, ok, extra)

def pixel.select(tested: Bool, +tex: U32, +blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match tested:
    case False{}: pixel.base(tex, blend, offset, at, raster)
    case True{}: pixel.depth((tex - 8 : U32), blend, offset, at, raster)

# tex 0..4 as pixel.base; tex + 8 adds the depth test.
def pixel(+tex: U32, +blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  pixel.select((tex >= 8 : U32), tex, blend, offset, at, raster)

# Consecutive pixels of a row, attributes stepped after each one; the
# attributes after the last pixel come back with the raster.
def cols(n: Nat, +tex: U32, +blend: Bool, +offset: U32, +at: Attr, +step: Attr, raster: Raster) -> Raster & Attr:
  match n:
    case 0n: (raster, at)
    case 1n+rest: cols(rest, tex, blend, (offset + 1 : U32), Attr.add(at, step), step, pixel(tex, blend, offset, at, raster))

def cols.raster(result: Raster & Attr) -> Raster:
  (raster, _) = result
  raster

def Vertex.attr(+v: Vertex) -> Attr:
  Vertex{_, _, z, _, r, g, b, a, u, t} = v
  Attr{r, g, b, a, u, t, z}

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
    case 1n+rest: rows(rest, tex, blend, (offset + stride : U32), stride, columns, Attr.add(row, dy), dx, dy, cols.raster(cols(columns, tex, blend, offset, row, dx, raster)))

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

def block.start(+acc: Span, +k: F32, +z: F32) -> Attr:
  Span{_, r, g, b, a, u, v} = acc
  Attr{(r * k : F32), (g * k : F32), (b * k : F32), (a * k : F32), (u * k : F32), (v * k : F32), z}

def block.delta(+value: F32, +slope: F32, +len: F32, +ka: F32, +kb: F32, +kl: F32) -> F32:
  ((((value + slope * len : F32) * kb : F32) - (value * ka : F32)) * kl : F32)

def block.step.with(+acc: Span, +slope: Span, +len: F32, +ka: F32, +kb: F32, +dz: F32) -> Attr:
  Span{_, r, g, b, a, u, v} = acc
  Span{_, dr, dg, db, da, du, dv} = slope
  +kl = (1.0 / len : F32)
  Attr{block.delta(r, dr, len, ka, kb, kl), block.delta(g, dg, len, ka, kb, kl), block.delta(b, db, len, ka, kb, kl),
    block.delta(a, da, len, ka, kb, kl), block.delta(u, du, len, ka, kb, kl), block.delta(v, dv, len, ka, kb, kl), dz}

def block.step(+acc: Span, +slope: Span, +len: F32, +ka: F32, +dz: F32) -> Attr:
  block.step.with(acc, slope, len, ka, (1.0 / (Span.w(acc) + Span.w(slope) * len : F32) : F32), dz)

# 16-pixel blocks; the depth z (with dz per pixel) runs on across blocks and
# comes back from each block's pixels.
def blocks(n: Nat, +tex: U32, +blend: Bool, +offset: U32, +x: F32, +x_end: F32, +acc: Span, +slope: Span, +dz: F32, state: Raster & Attr) -> Raster:
  match n state:
    case 0n Tuple{raster, _}: raster
    case 1n+rest Tuple{raster, +at}:
      +stop = F32.min((x + 16.0 : F32), x_end)
      +len = (stop - x : F32)
      +ka = (1.0 / Span.w(acc) : F32)
      blocks(rest, tex, blend, (offset + F32.to_u32(len) : U32), stop, x_end, Span.at(acc, slope, len), slope, dz,
        cols(U32.to_nat(F32.to_u32(len)), tex, blend, offset, block.start(acc, ka, Attr.z(at)), block.step(acc, slope, len, ka, dz), raster))

def Attr.depth(+z: F32) -> Attr:
  Attr{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, z}

def span.blocks(+tex: U32, +blend: Bool, +width: U32, +x0: F32, +x1: F32, +y: F32, +start: Vertex, +grad: Vertex, raster: Raster) -> Raster:
  +slope = Span.of(grad)
  +xsub = (1.0 - fract(Vertex.x(start)) : F32)
  +dz = Vertex.z(grad)
  blocks(U32.to_nat(((F32.to_u32((x1 - x0 : F32)) + 15) / 16 : U32)), tex, blend, (F32.to_u32(y) * width + F32.to_u32(x0) : U32),
    x0, x1, Span.at(Span.of(start), slope, xsub), slope, dz, (raster, Attr.depth((Vertex.z(start) + dz * xsub : F32))))

def span.fill(+tex: U32, +blend: Bool, +width: U32, +x0: F32, +x1: F32, +y: F32, +start: Vertex, +end: Vertex, raster: Raster) -> Raster:
  span.blocks(tex, blend, width, x0, x1, y, start, Vertex.grad(start, end, (1.0 / (Vertex.x(end) - Vertex.x(start)) : F32)), raster)

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
# viewport, then sw_clamp to [0, size - 1 + 0.5] of the color buffer returning
# int (NaN is UB).
def line.end.at(+cx: F32, +cy: F32, +hx: F32, +hy: F32, +max_x: F32, +max_y: F32, +v: Vertex) -> Vertex & Bool:
  Vertex{x, y, z, w, r, g, b, a, u, s} = v
  +k = (1.0 / w : F32)
  +sx = ((cx + (x * k : F32) * hx) + 0.5 : F32)
  +sy = ((cy + (y * k : F32) * hy) + 0.5 : F32)
  (Vertex{Bool.pick(F32, (sx < 0.0 : F32), 0.0, Bool.pick(F32, (sx > max_x : F32), F32.trunc(max_x), F32.trunc(sx))),
    Bool.pick(F32, (sy < 0.0 : F32), 0.0, Bool.pick(F32, (sy > max_y : F32), F32.trunc(max_y), F32.trunc(sy))),
    (z * k : F32), k, r, g, b, a, u, s}, F32.is_eq(sx, sx) && F32.is_eq(sy, sy))

def line.end(+port: View, +max_x: F32, +max_y: F32, +v: Vertex) -> Vertex & Bool:
  View{cx, cy, hx, hy} = port
  line.end.at(cx, cy, hx, hy, max_x, max_y, v)

def line.put(inside: Bool, +zt: U32, +blend: Bool, +offset: U32, +at: Attr, raster: Raster) -> Raster:
  match inside:
    case False{}: Raster.refuse(raster)
    case True{}: pixel(zt, blend, offset, at, raster)

def Attr.u(+a: Attr) -> F32:
  Attr{_, _, _, _, u, _, _} = a
  u

def Attr.v(+a: Attr) -> F32:
  Attr{_, _, _, _, _, v, _} = a
  v

# Attr{r, g, b, a, x, y, z} carries a line pixel: color, position, depth. zt is
# 0, or 8 with the depth test.
def line.pixel(+zt: U32, +blend: Bool, +width: U32, +height: U32, +at: Attr, raster: Raster) -> Raster:
  +px = F32.trunc(Attr.u(at))
  +py = F32.trunc(Attr.v(at))
  line.put((px >= 0.0 : F32) && (px < U32.to_f32(width) : F32) && (py >= 0.0 : F32) && (py < U32.to_f32(height) : F32),
    zt, blend, (F32.to_u32(py) * width + F32.to_u32(px) : U32), at, raster)

def line.pixels(n: Nat, +zt: U32, +blend: Bool, +width: U32, +height: U32, +at: Attr, +step: Attr, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest: line.pixels(rest, zt, blend, width, height, Attr.add(at, step), step, line.pixel(zt, blend, width, height, at, raster))

def line.count(valid: Bool, +zt: U32, +blend: Bool, +width: U32, +height: U32, +count: F32, +at: Attr, +step: Attr, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}: line.pixels(U32.to_nat(F32.to_u32((F32.trunc(count) + 1.0 : F32))), zt, blend, width, height, at, step, raster)

# Increments: color and depth times 1/steps, position d/steps;
# Attr{r, g, b, a, x, y, z}.
def line.step(+v0: Vertex, +v1: Vertex, +dx: F32, +dy: F32, +steps: F32) -> Attr:
  Vertex{_, _, z0, _, r0, g0, b0, a0, _, _} = v0
  Vertex{_, _, z1, _, r1, g1, b1, a1, _, _} = v1
  +k = (1.0 / steps : F32)
  Attr{((r1 - r0) * k : F32), ((g1 - g0) * k : F32), ((b1 - b0) * k : F32), ((a1 - a0) * k : F32), (dx / steps : F32), (dy / steps : F32),
    ((z1 - z0) * k : F32)}

def line.origin(+v0: Vertex, +x0: F32, +y0: F32) -> Attr:
  Vertex{_, _, z, _, r, g, b, a, _, _} = v0
  Attr{r, g, b, a, x0, y0, z}

def line.walk(+zt: U32, +blend: Bool, +width: U32, +height: U32, +x0: F32, +y0: F32, +dx: F32, +dy: F32, +steps: F32, +substep: F32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +step = line.step(v0, v1, dx, dy, steps)
  +count = (steps - substep : F32)
  line.count((count >= 0.0 : F32) && raster_int.valid(count), zt, blend, width, height, count,
    Attr.add(line.origin(v0, x0, y0), Attr.scale(step, substep)), step, raster)

def line.short(short: Bool, +zt: U32, +blend: Bool, +width: U32, +height: U32, +x0: F32, +y0: F32, +dx: F32, +dy: F32, +steps: F32, +substep: F32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match short:
    case True{}: raster
    case False{}: line.walk(zt, blend, width, height, x0, y0, dx, dy, steps, substep, v0, v1, raster)

# SW_RASTER_LINE: a DDA from the pixel centers, n + 0.5 moved to n.
def line.raster(+zt: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +x0 = (Vertex.x(v0) - 0.5 : F32)
  +y0 = (Vertex.y(v0) - 0.5 : F32)
  +dx = ((Vertex.x(v1) - 0.5 : F32) - x0 : F32)
  +dy = ((Vertex.y(v1) - 0.5 : F32) - y0 : F32)
  +major = (F32.abs(dx) > F32.abs(dy) : F32)
  +steps = Bool.pick(F32, major, F32.abs(dx), F32.abs(dy))
  +substep = Bool.pick(F32, major, Bool.pick(F32, (dx >= 0.0 : F32), (1.0 - fract(x0) : F32), fract(x0)),
    Bool.pick(F32, (dy >= 0.0 : F32), (1.0 - fract(y0) : F32), fract(y0)))
  line.short((steps < 1.0 : F32), zt, blend, width, height, x0, y0, dx, dy, steps, substep, v0, v1, raster)

# A copy of a projected line end moved by i pixels in y (or x when across).
def Vertex.shift(across: Bool, +v: Vertex, +i: F32) -> Vertex:
  Vertex{x, y, z, w, r, g, b, a, u, t} = v
  Bool.pick(Vertex, across, Vertex{(x + i : F32), y, z, w, r, g, b, a, u, t}, Vertex{x, (y + i : F32), z, w, r, g, b, a, u, t})

def line.offsets(n: Nat, +i: F32, +across: Bool, +zt: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest:
      line.offsets(rest, (i + 1.0 : F32), across, zt, blend, width, height, v0, v1,
        line.raster(zt, blend, width, height, Vertex.shift(across, v0, i), Vertex.shift(across, v1, i),
          line.raster(zt, blend, width, height, Vertex.shift(across, v0, F32.neg(i)), Vertex.shift(across, v1, F32.neg(i)), raster)))

# (int)((lineWidth - 1)*|d|/sqrtf(dx*dx + dy*dy)) >> 1 for the integral end
# deltas (their int sum of squares converted to float, as the F32 sum rounds it).
def line.half(+thick: F32, +along: F32, +dx: F32, +dy: F32) -> Nat:
  U32.to_nat((F32.to_u32(F32.trunc((((thick - 1.0 : F32) * F32.abs(along) : F32) / F32.sqrt((dx * dx + dy * dy : F32)) : F32))) >> 1n : U32))

# SW_RASTER_LINE_THICK (lineWidth >= 2): the line, then copies shifted by
# -i and +i pixels in y for mostly horizontal lines (|dy| < |dx|, the int
# division dy/dx being 0) or else in x, i = 1..half the scaled width. The
# copies are not clipped: one reaching outside the color buffer is refused.
def line.thick(+thick: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +dx = (Vertex.x(v1) - Vertex.x(v0) : F32)
  +dy = (Vertex.y(v1) - Vertex.y(v0) : F32)
  +flat = Bool.not(F32.is_eq(dx, 0.0)) && (F32.abs(dy) < F32.abs(dx) : F32)
  +steep = Bool.not(flat) && Bool.not(F32.is_eq(dy, 0.0))
  +count = Bool.pick(Nat, flat, line.half(thick, dx, dx, dy), Bool.pick(Nat, steep, line.half(thick, dy, dx, dy), 0n))
  line.offsets(count, 1.0, steep, zt, blend, width, height, v0, v1, line.raster(zt, blend, width, height, v0, v1, raster))

def line.width(wide: Bool, +thick: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match wide:
    case False{}: line.raster(zt, blend, width, height, v0, v1, raster)
    case True{}: line.thick(thick, zt, blend, width, height, v0, v1, raster)

def line.checked(valid: Bool, +thick: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match valid:
    case False{}: Raster.refuse(raster)
    case True{}: line.width((thick >= 2.0 : F32), thick, zt, blend, width, height, v0, v1, raster)

def line.ends(+thick: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, a: Vertex & Bool, b: Vertex & Bool, raster: Raster) -> Raster:
  (+v0, +valid0) = a
  (+v1, +valid1) = b
  line.checked(valid0 && valid1, thick, zt, blend, width, height, v0, v1, raster)

def line.project(+thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  +max_x = (U32.to_f32((width - 1 : U32)) + 0.5 : F32)
  +max_y = (U32.to_f32((height - 1 : U32)) + 0.5 : F32)
  line.ends(thick, zt, blend, width, height, line.end(port, max_x, max_y, v0), line.end(port, max_x, max_y, v1), raster)

def line.alive(alive: Bool, +thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  match alive:
    case False{}: raster
    case True{}: line.project(thick, zt, blend, port, width, height, v0, v1, raster)

def line.clipped(bounds: Bounds, +thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +v0: Vertex, +v1: Vertex, +d: Vertex, raster: Raster) -> Raster:
  Bounds{+t0, +t1, alive} = bounds
  line.alive(alive, thick, zt, blend, port, width, height, Bool.pick(Vertex, (t0 > 0.0 : F32), Vertex.along(v0, d, t0), v0),
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

def line.clip.with(+thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, +v0: Vertex, +v1: Vertex, +d: Vertex, raster: Raster) -> Raster:
  line.clipped(line.planes(scissor, v0, d), thick, zt, blend, port, width, height, v0, v1, d, raster)

# sw_line_render: sw_line_clip (six Liang-Barsky planes on (w -+ coordinate),
# then the scissor's four when it is enabled; d = v1 - v0), projection, and
# the thin or thick rasterizer.
def line.clip(+thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, +v0: Vertex, +v1: Vertex, raster: Raster) -> Raster:
  line.clip.with(thick, zt, blend, port, width, height, scissor, v0, v1, Vertex.grad(v0, v1, 1.0), raster)

# -----------------------------------------------------------------------------
# Points (sw_point_render): only vertices with w != 1 are tested against the
# frustum and divided; the projected center must lie within the point radius
# of the color buffer (or the scissor rectangle clamped to it); then the
# (2r + 1)^2 pixels around (int)x, (int)y take the vertex color, rows from
# -r to r, without bounds checks (a pixel outside the color buffer is
# refused).

def point.put(+zt: U32, +blend: Bool, +width: U32, +height: U32, +px: F32, +py: F32, +at: Attr, raster: Raster) -> Raster:
  line.put((px >= 0.0 : F32) && (px < U32.to_f32(width) : F32) && (py >= 0.0 : F32) && (py < U32.to_f32(height) : F32),
    zt, blend, (F32.to_u32(py) * width + F32.to_u32(px) : U32), at, raster)

def point.grid(n: Nat, +i: U32, +side: U32, +cx: F32, +cy: F32, +radius: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +at: Attr, raster: Raster) -> Raster:
  match n:
    case 0n: raster
    case 1n+rest:
      +px = (cx + (U32.to_f32((i % side : U32)) - radius : F32) : F32)
      +py = (cy + (U32.to_f32((i / side : U32)) - radius : F32) : F32)
      point.grid(rest, (i + 1 : U32), side, cx, cy, radius, zt, blend, width, height, at, point.put(zt, blend, width, height, px, py, at, raster))

def point.draw(inside: Bool, +radius: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +x: F32, +y: F32, +at: Attr, raster: Raster) -> Raster:
  match inside:
    case False{}: raster
    case True{}:
      +side = F32.to_u32(((2.0 * F32.max(radius, F32.neg(0.5)) : F32) + 1.0 : F32))
      point.grid(U32.to_nat((side * side : U32)), 0, side, F32.trunc(x), F32.trunc(y), radius, zt, blend, width, height, at, raster)

def point.clamp(+v: F32, +high: F32) -> F32:
  Bool.pick(F32, (v < 0.0 : F32), 0.0, Bool.pick(F32, (v > high : F32), high, v))

def point.bounds(+radius: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, +x: F32, +y: F32, +at: Attr, raster: Raster) -> Raster:
  Scissor{enabled, +sx0, +sy0, +sx1, +sy1, _, _, _, _} = scissor
  +w = U32.to_f32(width)
  +h = U32.to_f32(height)
  +min_x = Bool.pick(F32, enabled, point.clamp(sx0, w), 0.0)
  +min_y = Bool.pick(F32, enabled, point.clamp(sy0, h), 0.0)
  +max_x = Bool.pick(F32, enabled, point.clamp(sx1, w), w)
  +max_y = Bool.pick(F32, enabled, point.clamp(sy1, h), h)
  +inside = ((x - radius : F32) < max_x : F32) && ((x + radius : F32) > min_x : F32) && ((y - radius : F32) < max_y : F32) && ((y + radius : F32) > min_y : F32)
  point.draw(inside, radius, zt, blend, width, height, x, y, at, raster)

def point.accepted(projected: Bool, +radius: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, +x: F32, +y: F32, +at: Attr, raster: Raster) -> Raster:
  match projected:
    case False{}: raster
    case True{}: point.bounds(radius, zt, blend, width, height, scissor, x, y, at, raster)

def point.unit(unit: Bool, +x: F32, +y: F32, +z: F32, +w: F32) -> Vertex & Bool:
  match unit:
    case True{}: (Vertex{x, y, z, w, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, True{})
    case False{}:
      +inside = Bool.not((x < F32.neg(w) : F32) || (x > w : F32) || (y < F32.neg(w) : F32) || (y > w : F32) || (z < F32.neg(w) : F32) || (z > w : F32))
      +k = (1.0 / w : F32)
      (Vertex{(x * k : F32), (y * k : F32), (z * k : F32), k, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, inside)

def point.screen(+port: View, +p: Vertex) -> F32 & F32:
  View{cx, cy, hx, hy} = port
  (((cx + Vertex.x(p) * hx) + 0.5 : F32), ((cy + Vertex.y(p) * hy) + 0.5 : F32))

def point.placed(+inside: Bool, +radius: F32, +zt: U32, +blend: Bool, +width: U32, +height: U32, +scissor: Scissor, +at: Attr, xy: F32 & F32, raster: Raster) -> Raster:
  (+sx, +sy) = xy
  point.accepted(inside, radius, zt, blend, width, height, scissor, sx, sy, at, raster)

def point.projected(+radius: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, +r: F32, +g: F32, +b: F32, +a: F32, ndc: Vertex & Bool, raster: Raster) -> Raster:
  (+p, +inside) = ndc
  point.placed(inside, radius, zt, blend, width, height, scissor, Attr{r, g, b, a, 0.0, 0.0, Vertex.z(p)}, point.screen(port, p), raster)

def point.render(+radius: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, +v: Vertex, raster: Raster) -> Raster:
  Vertex{x, y, z, w, r, g, b, a, _, _} = v
  point.projected(radius, zt, blend, port, width, height, scissor, r, g, b, a, point.unit(F32.is_eq(w, 1.0), x, y, z, w), raster)

# -----------------------------------------------------------------------------
# Primitive rendering (sw_triangle_render, sw_quad_render, sw_line_render,
# sw_point_render and the polygon modes of sw_immediate_push_vertex)

# Per-primitive pipeline state read when a primitive completes: face culling
# (0 off, 1 back faces, 2 front faces), polygon mode (0 fill, 1 line, 2
# point), line width and point radius as rlsw stores them, the viewport and
# whether the depth test was captured by swBegin.
type Pipe is Data:
  Pipe{cull: U32, poly: U32, thick: F32, radius: F32, port: View, depth: Bool}

# sw_triangle_face_culling: the (x, y, w) determinant of the first three
# clip-space vertices.
def cull.area(+p0: Vertex, +p1: Vertex, +p2: Vertex) -> F32:
  (Vertex.x(p0) * (Vertex.y(p1) * Vertex.w(p2) - Vertex.y(p2) * Vertex.w(p1))
    + Vertex.x(p1) * (Vertex.y(p2) * Vertex.w(p0) - Vertex.y(p0) * Vertex.w(p2))
    + Vertex.x(p2) * (Vertex.y(p0) * Vertex.w(p1) - Vertex.y(p1) * Vertex.w(p0)) : F32)

# Back-face culling keeps a positive determinant (clockwise, zero-area and NaN
# primitives are dropped), front-face culling a negative one.
def cull.keep(cull: U32, +area: F32) -> Bool:
  match cull:
    case 0: True{}
    case 1: (area > 0.0 : F32)
    case _: (area < 0.0 : F32)

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

def render.clipped(+quad: Bool, +tex: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  render.kind(quad, project.all(port, clip.polygon(scissor, polygon)), tex, blend, width, height, raster)

def render.culled(keep: Bool, +quad: Bool, +tex: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  match keep:
    case False{}: raster
    case True{}: render.clipped(quad, tex, blend, port, width, height, scissor, polygon, raster)

def render.polygon(+quad: Bool, +cull: U32, +tex: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, polygon: +List<Vertex>, raster: Raster) -> Raster:
  match polygon:
    case Con{+a, Con{+b, Con{+c, +rest}}}: render.culled(cull.keep(cull, cull.area(a, b, c)), quad, tex, blend, port, width, height, scissor, Con{a, Con{b, Con{c, rest}}}, raster)
    case _: raster

def render.line(+thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  match vertices:
    case Con{+a, Con{+b, _}}: line.clip(thick, zt, blend, port, width, height, scissor, a, b, raster)
    case _: raster

# sw_poly_line_render: lines between consecutive unclipped vertices, then
# from the last back to the first (a line primitive is drawn both ways).
def render.edges(rest: +List<Vertex>, +first: Vertex, +prev: Vertex, +thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, raster: Raster) -> Raster:
  match rest:
    case Nil{}: line.clip(thick, zt, blend, port, width, height, scissor, prev, first, raster)
    case Con{+v, more}: render.edges(more, first, v, thick, zt, blend, port, width, height, scissor, line.clip(thick, zt, blend, port, width, height, scissor, prev, v, raster))

def render.wire(vertices: +List<Vertex>, +thick: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, raster: Raster) -> Raster:
  match vertices:
    case Nil{}: raster
    case Con{+first, rest}: render.edges(rest, first, first, thick, zt, blend, port, width, height, scissor, raster)

# sw_poly_point_render: every vertex as a point.
def render.points(vertices: +List<Vertex>, +radius: F32, +zt: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, raster: Raster) -> Raster:
  match vertices:
    case Nil{}: raster
    case Con{+v, more}: render.points(more, radius, zt, blend, port, width, height, scissor, point.render(radius, zt, blend, port, width, height, scissor, v, raster))

def render.fill(mode: U32, +cull: U32, +thick: F32, +zt: U32, +tex: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  match mode:
    case 2: render.line(thick, zt, blend, port, width, height, scissor, vertices, raster)
    case 3: render.polygon(False{}, cull, (tex + zt : U32), blend, port, width, height, scissor, vertices, raster)
    case _: render.polygon(True{}, cull, (tex + zt : U32), blend, port, width, height, scissor, vertices, raster)

def render.mode(poly: U32, +mode: U32, +cull: U32, +thick: F32, +radius: F32, +zt: U32, +tex: U32, +blend: Bool, +port: View, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  match poly:
    case 0: render.fill(mode, cull, thick, zt, tex, blend, port, width, height, scissor, vertices, raster)
    case 1: render.wire(vertices, thick, zt, blend, port, width, height, scissor, raster)
    case _: render.points(vertices, radius, zt, blend, port, width, height, scissor, raster)

# A complete primitive (mode = its vertex count) with the sampler tex, the
# blend decision and the pipeline state.
def render(+mode: U32, +tex: U32, +blend: Bool, +pipe: Pipe, +width: U32, +height: U32, +scissor: Scissor, vertices: +List<Vertex>, raster: Raster) -> Raster:
  Pipe{cull, poly, thick, radius, port, depth} = pipe
  render.mode(poly, mode, cull, thick, radius, Bool.pick(U32, depth, 8, 0), tex, blend, port, width, height, scissor, vertices, raster)

# -----------------------------------------------------------------------------
# The rlgl immediate path: rlBegin/rlColor*/rlTexCoord2f/rlVertex*/rlEnd and
# rlSetTexture reach swBegin/swColor*/... directly (no render batch); a
# primitive renders when its last vertex arrives (2 lines, 3 triangles, 4
# quads). The current color and texcoord persist across primitives. swBegin
# latches the MVP, the texture (when GL_TEXTURE_2D is enabled and the bound
# texture has pixels) and the blend and depth-test states; a primitive blends
# when blending was enabled and its texture has alpha (the atlas always does)
# or a color with alpha below 1 was set since the previous primitive. Culling,
# the scissor, the polygon mode, line width, point size and viewport are read
# when the primitive completes. Matrix commands act on the stack selected by
# rlMatrixMode.

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
  Vertex3{x: F32, y: F32, z: F32}
  ColorF{r: F32, g: F32, b: F32, a: F32}
  ShapeUV{corner: U32}
  ShapeTexture{}
  HeldTexture{}
  Mode{mode: U32}
  PostMultiply{matrix: Matrix4}
  Viewport{x: F32, y: F32, w: F32, h: F32}
  Enable{cap: U32, on: Bool}
  CullFace{front: Bool}
  PolyMode{mode: U32}
  LineWidth{width: F32}
  PointSize{size: F32}
  ClearColor{color: U32}
  Clear{}
  ScissorRect{x: F32, y: F32, w: F32, h: F32}
  Refuse{}

# bound: what is bound to GL_TEXTURE_2D (0 none, 1 the default font atlas; a
# user texture with alpha, opaque or without pixels: 2, 3, 4 for one Draw*
# call, 5, 6, 7 the shapes texture, 8, 9, 10 the rlSetTexture texture);
# textured: the sampler latched by swBegin (0 none, 1 atlas, 2..4 a user
# slot); caps: blending (1) and depth testing (2) latched by swBegin.
type Immediate is Data:
  Immediate{mode: U32, bound: U32, textured: U32, alpha: Bool, paint: Attr, pending: +List<Vertex>, count: U32, caps: U32}

# swInit: white, texcoord (0, 0), no primitive, nothing bound.
def Immediate.initial() -> Immediate:
  Immediate{0, 0, 0, False{}, Attr{1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0}, Nil{}, 0, 0}

def bound.sampler(bound: U32) -> U32:
  match bound:
    case 1: 1
    case 2: 2
    case 3: 2
    case 5: 3
    case 6: 3
    case 8: 4
    case 9: 4
    case _: 0

# A complete bound texture whose alpha mode is not SW_PIXEL_ALPHA_NONE.
def bound.alpha(bound: U32) -> Bool:
  match bound:
    case 1: True{}
    case 2: True{}
    case 5: True{}
    case 8: True{}
    case _: False{}

# -----------------------------------------------------------------------------
# Render state: rlsw's projection, modelview and texture stacks (2, 8 and 2
# entries), the scissor, and the texture (128 slots, id 1 the default font) and
# framebuffer (8 slots) id pools: sw_pool_alloc reuses the most recently freed
# id, else the next fresh one, and fails (id 0) when full.

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

# A user texture held by the frame (the texels live in the raster's Extra);
# id 0 for none.
type Meta is Data:
  Meta{id: U32, width: U32, height: U32, format: U32, linear: Bool, alpha: Bool, complete: Bool}

def Meta.none() -> Meta:
  Meta{0, 0, 0, 0, False{}, False{}, False{}}

def Meta.id(+meta: Meta) -> U32:
  Meta{id, _, _, _, _, _, _} = meta
  id

# rshapes.c's texShapes and texShapesRec: a user texture (or Meta.none() for
# the default font atlas, id 1), the texture size the texture coordinates
# divide by, its format, and the source rectangle.
type Shapes is Data:
  Shapes{user: Meta, id: U32, width: U32, height: U32, format: U32, x: F32, y: F32, w: F32, h: F32}

# rlsw state rlgl reaches: GL_BLEND, GL_DEPTH_TEST, GL_CULL_FACE and its face
# (front or back), the polygon mode (0 fill, 1 line, 2 point), lineWidth
# (roundf of glLineWidth) and pointRadius (floorf of half glPointSize),
# GL_TEXTURE_2D, the clear color (bytes as rlClearColor takes them), the
# matrix mode (0 modelview, 1 projection, 2 texture), the viewport, the
# projection entries below the top and the texture stack (top first), the
# shapes texture and the rlSetTexture texture.
type Gl is Data:
  Gl{blend: Bool, depth: Bool, cull: Bool, front: Bool, poly: U32, thick: F32, radius: F32, enabled: Bool, clear: U32, mode: U32,
    x: F32, y: F32, vw: F32, vh: F32, lower: +List<Matrix4>, texture: +List<Matrix4>, shapes: Shapes, held: Meta}

# The GL state boxed: a Canvas carries it as one heap value. The compiler
# lays a non-recursive datatype out flat in its holder's fields, and a
# flattened Gl in every Canvas made generated work-loop segments too wide for
# Apple clang 21's arm64 backend (docs/VERIFICATION.md); the never-used
# `spare` list makes GlBox recursive, which the compiler always boxes.
type GlBox is Type:
  GlBox{gl: Gl, spare: List<GlBox>}

type Canvas is Type:
  Canvas{width: U32, height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, gl: GlBox}

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

def Rig.modelview(+rig: Rig) -> Matrix4:
  Rig{_, modelview, _, _, _, _} = rig
  Rig.top(modelview)

def Rig.projection(+rig: Rig) -> Matrix4:
  Rig{projection, _, _, _, _, _} = rig
  projection

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

def Rig.top.post(modelview: +List<Matrix4>, +matrix: Matrix4) -> +List<Matrix4>:
  match modelview:
    case Con{+top, rest}: Con{Matrix4.mul(top, matrix), rest}
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

# swOrtho and swFrustum: M = mul(M, T).
def Rig.post(+matrix: Matrix4, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, Rig.top.post(modelview, matrix), depth, scissor, textures, framebuffers}

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
    case PostMultiply{matrix}: (Rig.post(matrix, rig), True{})
    case _: (rig, True{})

def Rig.with_projection(+matrix: Matrix4, rig: Rig) -> Rig:
  Rig{_, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{matrix, modelview, depth, scissor, textures, framebuffers}

# The viewport and projection of a width x height color buffer (rlViewport,
# then rlOrtho on an identity projection) with an identity modelview, as
# BeginTextureMode and EndTextureMode's SetupViewport leave them.
def Rig.view(+width: U32, +height: U32, rig: Rig) -> Rig:
  Rig{_, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{Matrix4.projection(width, height), Rig.top.set(modelview, Matrix4.identity()), depth, scissor, textures, framebuffers}

# rlScissor(x, y, w, h): negative sizes are rejected by swScissor, which keeps
# the previous rectangle; clip bounds use the current viewport size.
def Scissor.rect(valid: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +vw: F32, +vh: F32, scissor: Scissor) -> Scissor:
  match valid:
    case False{}: scissor
    case True{}: Scissor.set(Scissor.enabled(scissor), x, y, w, h, vw, vh)

def Rig.scissor.rect(+x: F32, +y: F32, +w: F32, +h: F32, +vw: F32, +vh: F32, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, modelview, depth, Scissor.rect((w >= 0.0 : F32) && (h >= 0.0 : F32), x, y, w, h, vw, vh, scissor), textures, framebuffers}

def Rig.scissor.enable(on: Bool, rig: Rig) -> Rig:
  Rig{projection, modelview, depth, scissor, textures, framebuffers} = rig
  Rig{projection, modelview, depth, Scissor.enable(on, scissor), textures, framebuffers}

# BeginScissorMode: rlEnableScissorTest, then rlScissor(x, fbo height -
# (y + h), w, h).
def Rig.scissor.begin(+x: F32, +y: F32, +w: F32, +h: F32, +height: U32, +vw: F32, +vh: F32, rig: Rig) -> Rig:
  Rig.scissor.rect(x, (U32.to_f32(height) - (y + h : F32) : F32), w, h, vw, vh, Rig.scissor.enable(True{}, rig))

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
# GL state

# InitWindow: the default font atlas (id 1, 128x128 GRAY_ALPHA) with glyph 95
# inset by one pixel, (41, 46, 2, 8).
def Shapes.initial() -> Shapes:
  Shapes{Meta.none(), 1, 128, 128, 2, 41.0, 46.0, 2.0, 8.0}

# SetShapesTexture with id 0 or an empty source: (Texture2D){ 1, 1, 1, 1, 7 }
# (rlsw's id 1 is the font atlas) and (0, 0, 1, 1).
def Shapes.reset() -> Shapes:
  Shapes{Meta.none(), 1, 1, 1, 7, 0.0, 0.0, 1.0, 1.0}

# rlglInit and SetupViewport: blending and back-face culling on, depth test
# off, filled polygons, line width and point radius 0 (rlsw's zeroed state),
# GL_TEXTURE_2D off, clear color (0, 0, 0, 1), modelview mode, the viewport
# (0, 0, width, height) and identity texture matrix.
def Gl.initial(+width: U32, +height: U32) -> Gl:
  Gl{True{}, False{}, True{}, False{}, 0, 0.0, 0.0, False{}, 255, 0, 0.0, 0.0, U32.to_f32(width), U32.to_f32(height), Nil{}, [Matrix4.identity()],
    Shapes.initial(), Meta.none()}

def Gl.mode(+gl: Gl) -> U32:
  Gl{_, _, _, _, _, _, _, _, _, mode, _, _, _, _, _, _, _, _} = gl
  mode

def Gl.enabled(+gl: Gl) -> Bool:
  Gl{_, _, _, _, _, _, _, enabled, _, _, _, _, _, _, _, _, _, _} = gl
  enabled

def Gl.clear(+gl: Gl) -> U32:
  Gl{_, _, _, _, _, _, _, _, clear, _, _, _, _, _, _, _, _, _} = gl
  clear

def Gl.vw(+gl: Gl) -> F32:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, vw, _, _, _, _, _} = gl
  vw

def Gl.vh(+gl: Gl) -> F32:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, vh, _, _, _, _} = gl
  vh

def Gl.viewport.size(+gl: Gl) -> F32 & F32:
  (Gl.vw(gl), Gl.vh(gl))

def Gl.thick(+gl: Gl) -> F32:
  Gl{_, _, _, _, _, thick, _, _, _, _, _, _, _, _, _, _, _, _} = gl
  thick

def Gl.radius(+gl: Gl) -> F32:
  Gl{_, _, _, _, _, _, radius, _, _, _, _, _, _, _, _, _, _, _} = gl
  radius

def Gl.shapes(+gl: Gl) -> Shapes:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, shapes, _} = gl
  shapes

def Gl.held(+gl: Gl) -> Meta:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, held} = gl
  held

def Gl.texture.top(+gl: Gl) -> Matrix4:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, texture, _, _} = gl
  Rig.top(texture)

# blend (1) and depth (2) for swBegin.
def Gl.caps(+gl: Gl) -> U32:
  Gl{blend, depth, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = gl
  (Bool.pick(U32, blend, 1, 0) + Bool.pick(U32, depth, 2, 0) : U32)

# GL_TEXTURE_2D and the blend (1) and depth (2) states swBegin latches.
def Gl.begin.info(+gl: Gl) -> Bool & U32:
  (Gl.enabled(gl), Gl.caps(gl))

def Gl.pipe(+gl: Gl, +depth: Bool) -> Pipe:
  Gl{_, _, cull, front, poly, thick, radius, _, _, _, x, y, vw, vh, _, _, _, _} = gl
  Pipe{Bool.pick(U32, cull, Bool.pick(U32, front, 2, 1), 0), poly, thick, radius, View.of(x, y, vw, vh), depth}

# swEnable/swDisable: 0 GL_BLEND, 1 GL_DEPTH_TEST, 2 GL_CULL_FACE.
def Gl.set_blend(+on: Bool, gl: Gl) -> Gl:
  Gl{_, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{on, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.set_depth(+on: Bool, gl: Gl) -> Gl:
  Gl{blend, _, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, on, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.set_cull(+on: Bool, gl: Gl) -> Gl:
  Gl{blend, depth, _, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, on, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.enable(cap: U32, +on: Bool, gl: Gl) -> Gl:
  match cap:
    case 0: Gl.set_blend(on, gl)
    case 1: Gl.set_depth(on, gl)
    case _: Gl.set_cull(on, gl)

def Gl.cull_face(+front: Bool, gl: Gl) -> Gl:
  Gl{blend, depth, cull, _, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.poly(+poly: U32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, _, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.line(+thick: F32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, _, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.point(+radius: F32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, _, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.texturing(+enabled: Bool, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, _, clear, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.clear_color(+clear: U32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, _, mode, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

# swMatrixMode: other values are an error that changes nothing.
def Gl.matrix_mode(+mode: U32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, old, x, y, vw, vh, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, Bool.pick(U32, (mode <= 2 : U32), mode, old), x, y, vw, vh, lower, texture, shapes, held}

# swViewport: negative sizes are an error that changes nothing.
def Gl.viewport(+nx: F32, +ny: F32, +nw: F32, +nh: F32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, +x, +y, +vw, +vh, lower, texture, shapes, held} = gl
  +ok = (nw >= 0.0 : F32) && (nh >= 0.0 : F32)
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, Bool.pick(F32, ok, nx, x), Bool.pick(F32, ok, ny, y),
    Bool.pick(F32, ok, nw, vw), Bool.pick(F32, ok, nh, vh), lower, texture, shapes, held}

# BeginTextureMode / SetupViewport: rlViewport(0, 0, w, h), and the
# projection and modelview reloaded in modelview mode.
def Gl.view(+width: U32, +height: U32, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, _, _, _, _, _, lower, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, 0, 0.0, 0.0, U32.to_f32(width), U32.to_f32(height), lower, texture, shapes, held}

def Gl.point.size(+gl: Gl) -> F32:
  (2.0 * Gl.radius(gl) : F32)

def Gl.with_shapes(+shapes: Shapes, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, _, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.with_held(+held: Meta, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, _} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

# The projection (mode 1, at most one entry below the top) and texture (mode 2,
# two entries) stacks: a push beyond the capacity changes nothing; popping the
# last entry is undefined (refused).
def stack.small.push(+top: Matrix4, lower: +List<Matrix4>) -> +List<Matrix4>:
  match lower:
    case Nil{}: [top]
    case Con{+m, rest}: Con{m, rest}

def stack.small.pop(+top: Matrix4, lower: +List<Matrix4>) -> (Matrix4 & +List<Matrix4>) & Bool:
  match lower:
    case Nil{}: ((top, Nil{}), False{})
    case Con{+m, _}: ((m, Nil{}), True{})

def stack.apply(command: Command, +top: Matrix4, lower: +List<Matrix4>) -> (Matrix4 & +List<Matrix4>) & Bool:
  match command:
    case Push{}: ((top, stack.small.push(top, lower)), True{})
    case Pop{}: stack.small.pop(top, lower)
    case Identity{}: ((Matrix4.identity(), lower), True{})
    case Multiply{matrix}: ((Matrix4.mul(matrix, top), lower), True{})
    case PostMultiply{matrix}: ((Matrix4.mul(top, matrix), lower), True{})
    case _: ((top, lower), True{})

def Gl.with_lower(lower: +List<Matrix4>, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, _, texture, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def Gl.lower(+gl: Gl) -> +List<Matrix4>:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, _, lower, _, _, _} = gl
  lower

def Gl.texture.stack(+gl: Gl) -> +List<Matrix4>:
  Gl{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, texture, _, _} = gl
  texture

def Gl.with_texture(texture: +List<Matrix4>, gl: Gl) -> Gl:
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, _, shapes, held} = gl
  Gl{blend, depth, cull, front, poly, thick, radius, enabled, clear, mode, x, y, vw, vh, lower, texture, shapes, held}

def stack.list(+top: Matrix4, rest: +List<Matrix4>) -> +List<Matrix4>:
  Con{top, rest}

def stack.split(stack: +List<Matrix4>) -> Matrix4 & +List<Matrix4>:
  match stack:
    case Con{+top, rest}: (top, rest)
    case Nil{}: (Matrix4.identity(), Nil{})

def Gl.swap.held(+meta: Meta, +gl: Gl) -> Gl & Meta:
  (Gl.with_held(meta, gl), Gl.held(gl))

def Shapes.user(+shapes: Shapes) -> Meta:
  Shapes{user, _, _, _, _, _, _, _, _} = shapes
  user

def Gl.swap.shapes(+shapes: Shapes, +gl: Gl) -> Gl & Meta:
  (Gl.with_shapes(shapes, gl), Shapes.user(Gl.shapes(gl)))

# -----------------------------------------------------------------------------
# Canvas: the current color buffer, its MVP and immediate state, the raster,
# render and GL state, and the target.

# The canvas and a value read from its GL state. These are first-order on
# purpose: a def taking a closure becomes a work-loop function in the
# generated C, whose shared signature grows to the widest such def (a whole
# flattened Canvas here); that crashed Apple clang 21's arm64 backend.
def Canvas.read.clear(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.clear(gl))

def Canvas.read.mode(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.mode(gl))

def Canvas.read.viewport(canvas: Canvas) -> Canvas & F32 & F32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.viewport.size(gl))

def Canvas.read.pipe(canvas: Canvas) -> Canvas & Pipe:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.pipe(gl, False{}))

def Canvas.read.begin(canvas: Canvas) -> Canvas & Bool & U32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.begin.info(gl))

def Canvas.read.texture(canvas: Canvas) -> Canvas & Matrix4:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.texture.top(gl))

# rshapes.c's texture coordinates: shapeRect.x/texShapes.width (or x + width)
# and likewise y, chosen by the corner bits (1: right, 2: bottom).
def Shapes.uv(+shapes: Shapes, +corner: U32) -> F32 & F32:
  Shapes{_, _, width, height, _, x, y, w, h} = shapes
  +tw = U32.to_f32(width)
  +th = U32.to_f32(height)
  (Bool.pick(F32, U32.is_eq((corner .&. 1 : U32), 1), ((x + w : F32) / tw : F32), (x / tw : F32)),
    Bool.pick(F32, U32.is_eq((corner .&. 2 : U32), 2), ((y + h : F32) / th : F32), (y / th : F32)))

def Canvas.read.shape_uv(+corner: U32, canvas: Canvas) -> Canvas & F32 & F32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Shapes.uv(Gl.shapes(gl), corner))

# A held user texture's binding kind: with alpha, opaque, or without pixels.
def Meta.kind(+meta: Meta, +base: U32) -> U32:
  Meta{_, _, _, _, _, alpha, complete} = meta
  (base + Bool.pick(U32, complete, Bool.pick(U32, alpha, 0, 1), 2) : U32)

def Shapes.kind.user(+user: Meta) -> U32:
  Bool.pick(U32, U32.is_eq(Meta.id(user), 0), 1, Meta.kind(user, 5))

def Shapes.kind(+shapes: Shapes) -> U32:
  Shapes{user, _, _, _, _, _, _, _, _} = shapes
  Shapes.kind.user(user)

def Canvas.read.shapes_kind(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Shapes.kind(Gl.shapes(gl)))

def held.kind(+held: Meta) -> U32:
  Bool.pick(U32, U32.is_eq(Meta.id(held), 0), 0, Meta.kind(held, 8))

def Canvas.read.held_kind(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, held.kind(Gl.held(gl)))

def Canvas.read.shapes(canvas: Canvas) -> Canvas & Shapes:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.shapes(gl))

def Canvas.read.thick(canvas: Canvas) -> Canvas & F32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.thick(gl))

def Canvas.read.point_size(canvas: Canvas) -> Canvas & F32:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{+gl, _} = box
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, Gl.point.size(gl))

def Canvas.updated.swap_held(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, result: Gl & Meta) -> Canvas & Meta:
  (gl, value) = result
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, value)

def Canvas.update.swap_held(+meta: Meta, canvas: Canvas) -> Canvas & Meta:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{gl, _} = box
  Canvas.updated.swap_held(width, height, matrix, state, raster, rig, target, Gl.swap.held(meta, gl))

def Canvas.updated.swap_shapes(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, result: Gl & Meta) -> Canvas & Meta:
  (gl, value) = result
  (Canvas{width, height, matrix, state, raster, rig, target, GlBox{gl, Nil{}}}, value)

def Canvas.update.swap_shapes(+shapes: Shapes, canvas: Canvas) -> Canvas & Meta:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  GlBox{gl, _} = box
  Canvas.updated.swap_shapes(width, height, matrix, state, raster, rig, target, Gl.swap.shapes(shapes, gl))

# A GL state command (glMatrixMode, glViewport, glEnable/glDisable,
# glCullFace, glPolygonMode, glLineWidth, glPointSize, glClearColor).
def Gl.set(+command: Command, gl: Gl) -> Gl:
  match command:
    case Mode{mode}: Gl.matrix_mode(mode, gl)
    case Viewport{x, y, w, h}: Gl.viewport(x, y, w, h, gl)
    case Enable{cap, on}: Gl.enable(cap, on, gl)
    case CullFace{front}: Gl.cull_face(front, gl)
    case PolyMode{mode}: Gl.poly(mode, gl)
    case LineWidth{width}: Gl.line(width, gl)
    case PointSize{size}: Gl.point(size, gl)
    case ClearColor{color}: Gl.clear_color(color, gl)
    case _: gl

def GlBox.set(+command: Command, box: GlBox) -> GlBox:
  GlBox{gl, _} = box
  GlBox{Gl.set(command, gl), Nil{}}

def GlBox.view(+width: U32, +height: U32, box: GlBox) -> GlBox:
  GlBox{gl, _} = box
  GlBox{Gl.view(width, height, gl), Nil{}}

def GlBox.texturing(+enabled: Bool, box: GlBox) -> GlBox:
  GlBox{gl, _} = box
  GlBox{Gl.texturing(enabled, gl), Nil{}}

def Canvas.set(+command: Command, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas{width, height, matrix, state, raster, rig, target, GlBox.set(command, box)}

# glEnable(GL_TEXTURE_2D) when a texture is held during a primitive.
def Canvas.texturing(canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas{width, height, matrix, state, raster, rig, target, GlBox.texturing(True{}, box)}

def Canvas.scissor.enable(+on: Bool, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas{width, height, matrix, state, raster, Rig.scissor.enable(on, rig), target, box}

def Canvas.build(+width: U32, +height: U32, state: Immediate, raster: Raster, +rig: Rig, target: Target, gl: GlBox) -> Canvas:
  Canvas{width, height, Rig.mvp(rig), state, raster, rig, target, gl}

# rlClearColor (byte/255) stored by sw_framebuffer_fill_color.
def clear.word(+color: U32) -> U32 & Bool:
  pack((U32.to_f32((color >> 24n : U32)) / 255.0 : F32), (U32.to_f32(((color >> 16n) .&. 255 : U32)) / 255.0 : F32),
    (U32.to_f32(((color >> 8n) .&. 255 : U32)) / 255.0 : F32), (U32.to_f32((color .&. 255 : U32)) / 255.0 : F32))

def fill.cols(n: Nat, +offset: U32, +word: U32, values: Array<U32>) -> Array<U32>:
  match n:
    case 0n: values
    case 1n+rest: fill.cols(rest, (offset + 1 : U32), word, Array.set(U32, values, offset, word))

def fill.rows(n: Nat, +row: U32, +width: U32, +x: U32, +cols: Nat, +word: U32, values: Array<U32>) -> Array<U32>:
  match n:
    case 0n: values
    case 1n+rest: fill.rows(rest, (row + 1 : U32), width, x, cols, word, fill.cols(cols, (row * width + x : U32), word, values))

# sw_clamp_int(v, 0, high)
def clamp.low(+v: F32, +high: F32) -> F32:
  Bool.pick(F32, (v < 0.0 : F32), 0.0, Bool.pick(F32, (v > high : F32), high, v))

# sw_framebuffer_fill_color/depth: the whole buffer, or with the scissor test
# the clamped rectangle from its minimum to its maximum corner inclusive (one
# pixel more than the scissor in each direction, and at least one pixel).
def fill.rect(+width: U32, +height: U32, +scissor: Scissor, +word: U32, values: Array<U32>) -> Array<U32>:
  Scissor{_, +x0, +y0, +x1, +y1, _, _, _, _} = scissor
  +right = U32.to_f32((width - 1 : U32))
  +top = U32.to_f32((height - 1 : U32))
  +xmin = clamp.low(x0, right)
  +ymin = clamp.low(y0, top)
  fill.rows(U32.to_nat(F32.to_u32(((clamp.low(y1, top) - ymin : F32) + 1.0 : F32))), F32.to_u32(ymin), width, F32.to_u32(xmin),
    U32.to_nat(F32.to_u32(((clamp.low(x1, right) - xmin : F32) + 1.0 : F32))), word, values)

def fill.select(enabled: Bool, +width: U32, +height: U32, +scissor: Scissor, +word: U32, values: Array<U32>) -> Array<U32>:
  match enabled:
    case False{}: Array.new(U32, depth((width * height : U32)), word)
    case True{}: fill.rect(width, height, scissor, word, values)

def clear.color(+width: U32, +height: U32, +scissor: Scissor, packed: U32 & Bool, raster: Raster) -> Raster:
  (+word, valid) = packed
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Raster{fill.select(Scissor.enabled(scissor), width, height, scissor, word, pixels), atlas, sampler, ok && valid, extra}

def clear.depth.extra(+width: U32, +height: U32, +scissor: Scissor, extra: Extra) -> Extra:
  Extra{depth, shapes, held} = extra
  Extra{fill.select(Scissor.enabled(scissor), width, height, scissor, 1065353216, depth), shapes, held}

# glClear's depth part (clear depth 1.0) on the screen's depth buffer.
def clear.depth(+width: U32, +height: U32, +scissor: Scissor, raster: Raster) -> Raster:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Raster{pixels, atlas, sampler, ok, clear.depth.extra(width, height, scissor, extra)}

def clear.target(target: Target, +width: U32, +height: U32, +scissor: Scissor, raster: Raster) -> Target & Raster:
  match target:
    case Screen{}: (Screen{}, clear.depth(width, height, scissor, raster))
    case Offscreen{sw, sh, pixels, meta}: (Offscreen{sw, sh, pixels, meta}, raster)

def Canvas.cleared(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, rig: Rig, gl: GlBox, result: Target & Raster) -> Canvas:
  (target, raster) = result
  Canvas{width, height, matrix, state, raster, rig, target, gl}

def Canvas.clear.buffers.with(result: Canvas & U32) -> Canvas:
  (canvas, +color) = result
  Canvas{+width, +height, matrix, state, raster, +rig, target, box} = canvas
  +scissor = Rig.scissor(rig)
  Canvas.cleared(width, height, matrix, state, rig, box, clear.target(target, width, height, scissor,
    clear.color(width, height, scissor, clear.word(color), raster)))

# rlClearScreenBuffers: glClear(COLOR | DEPTH) with the clear color on the
# current color buffer; a render texture's depth buffer is not modeled (draws
# testing depth into one are refused).
def Canvas.clear.buffers(canvas: Canvas) -> Canvas:
  Canvas.clear.buffers.with(Canvas.read.clear(canvas))

def Canvas.clear_color(+color: U32, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, raster, rig, target, GlBox.set(ClearColor{color}, gl)}

# ClearBackground: rlClearColor, then rlClearScreenBuffers.
def Canvas.clear(+color: U32, canvas: Canvas) -> Canvas:
  Canvas.clear.buffers(Canvas.clear_color(color, canvas))

# rlglInit: swInit, then glClear with the clear color (0, 0, 0, 1) and depth 1.
def Canvas.new(+width: U32, +height: U32) -> Canvas:
  Canvas.clear(255, Canvas.build(width, height, Immediate.initial(),
    Raster{Array.new(U32, 0n, 0), Font.atlas(), Unbound{}, True{}, Extra{Array.new(U32, 0n, 0), Unbound{}, Unbound{}}},
    Rig.initial(width, height), Screen{}, GlBox{Gl.initial(width, height), Nil{}}))

def Canvas.adjusted(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, target: Target, gl: GlBox, result: Rig & Bool) -> Canvas:
  (rig, valid) = result
  Canvas{width, height, matrix, state, Raster.require(valid, raster), rig, target, gl}

def GlBox.project.pair(+gl: Gl, +valid: Bool, pair: Matrix4 & +List<Matrix4>) -> GlBox & (Matrix4 & Bool):
  (+top, lower) = pair
  (GlBox{Gl.with_lower(lower, gl), Nil{}}, (top, valid))

def GlBox.project.done(+gl: Gl, result: (Matrix4 & +List<Matrix4>) & Bool) -> GlBox & (Matrix4 & Bool):
  (pair, +valid) = result
  GlBox.project.pair(gl, valid, pair)

# A projection-stack command on (top, entries below in the box).
def GlBox.project(command: Command, +top: Matrix4, box: GlBox) -> GlBox & (Matrix4 & Bool):
  GlBox{+gl, _} = box
  GlBox.project.done(gl, stack.apply(command, top, Gl.lower(gl)))

def GlBox.texture.pair(+gl: Gl, +valid: Bool, pair: Matrix4 & +List<Matrix4>) -> GlBox & Bool:
  (+top, lower) = pair
  (GlBox{Gl.with_texture(stack.list(top, lower), gl), Nil{}}, valid)

def GlBox.texture.done(+gl: Gl, result: (Matrix4 & +List<Matrix4>) & Bool) -> GlBox & Bool:
  (pair, +valid) = result
  GlBox.texture.pair(gl, valid, pair)

def GlBox.texture.split(command: Command, +gl: Gl, split: Matrix4 & +List<Matrix4>) -> GlBox & Bool:
  (+top, lower) = split
  GlBox.texture.done(gl, stack.apply(command, top, lower))

# A texture-stack command.
def GlBox.texture(command: Command, box: GlBox) -> GlBox & Bool:
  GlBox{+gl, _} = box
  GlBox.texture.split(command, gl, stack.split(Gl.texture.stack(gl)))

def Canvas.projected.top(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, box: GlBox, pair: Matrix4 & Bool) -> Canvas:
  (+top, valid) = pair
  Canvas{width, height, matrix, state, Raster.require(valid, raster), Rig.with_projection(top, rig), target, box}

def Canvas.projected.box(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, result: GlBox & (Matrix4 & Bool)) -> Canvas:
  (box, pair) = result
  Canvas.projected.top(width, height, matrix, state, raster, rig, target, box, pair)

def Canvas.textured.box(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, target: Target, result: GlBox & Bool) -> Canvas:
  (box, valid) = result
  Canvas{width, height, matrix, state, Raster.require(valid, raster), rig, target, box}

def Canvas.adjust.mode(mode: U32, command: Command, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, +rig: Rig, target: Target, box: GlBox) -> Canvas:
  match mode:
    case 0: Canvas.adjusted(width, height, matrix, state, raster, target, box, Rig.apply(command, rig))
    case 1: Canvas.projected.box(width, height, matrix, state, raster, rig, target, GlBox.project(command, Rig.projection(rig), box))
    case _: Canvas.textured.box(width, height, matrix, state, raster, rig, target, GlBox.texture(command, box))

def Canvas.adjust.with(command: Command, result: Canvas & U32) -> Canvas:
  (canvas, +mode) = result
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas.adjust.mode(mode, command, width, height, matrix, state, raster, rig, target, box)

# A matrix command on the stack of the current matrix mode. The MVP is
# recomputed by the next swBegin.
def Canvas.adjust(command: Command, canvas: Canvas) -> Canvas:
  Canvas.adjust.with(command, Canvas.read.mode(canvas))

# BeginDrawing and EndMode2D: rlLoadIdentity (and rlMultMatrixf of the
# identity screen scale) on the current matrix.
def Canvas.reset(canvas: Canvas) -> Canvas:
  Canvas.adjust(Identity{}, canvas)

# BeginMode2D: rlLoadIdentity, then rlMultMatrixf(GetCameraMatrix2D).
def Canvas.camera(+matrix: Matrix4, canvas: Canvas) -> Canvas:
  Canvas.adjust(Multiply{matrix}, Canvas.adjust(Identity{}, canvas))

def Canvas.target.size(target: Target, +width: U32, +height: U32) -> Target & (U32 & U32):
  match target:
    case Screen{}: (Screen{}, (width, height))
    case Offscreen{+sw, +sh, pixels, meta}: (Offscreen{sw, sh, pixels, meta}, (sw, sh))

def Canvas.sized(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, gl: GlBox, result: Target & (U32 & U32)) -> Canvas & (U32 & U32):
  (target, size) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, size)

# The screen's size (also while a render texture is the target).
def Canvas.dimensions(canvas: Canvas) -> Canvas & (U32 & U32):
  Canvas{+width, +height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.sized(width, height, matrix, state, raster, rig, gl, Canvas.target.size(target, width, height))

def Canvas.target.offscreen(target: Target) -> Target & Bool:
  match target:
    case Screen{}: (Screen{}, False{})
    case Offscreen{sw, sh, pixels, meta}: (Offscreen{sw, sh, pixels, meta}, True{})

def Canvas.flagged(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, gl: GlBox, result: Target & Bool) -> Canvas & Bool:
  (target, flag) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, flag)

# Whether a render texture is the target.
def Canvas.offscreen(canvas: Canvas) -> Canvas & Bool:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.flagged(width, height, matrix, state, raster, rig, gl, Canvas.target.offscreen(target))

def RenderTarget.id(+meta: RenderTarget) -> U32:
  RenderTarget{id, _, _, _, _} = meta
  id

def Canvas.target.id(target: Target) -> Target & U32:
  match target:
    case Screen{}: (Screen{}, 0)
    case Offscreen{sw, sh, pixels, +meta}: (Offscreen{sw, sh, pixels, meta}, RenderTarget.id(meta))

def Canvas.identified(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, gl: GlBox, result: Target & U32) -> Canvas & U32:
  (target, id) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, id)

# rlGetActiveFramebuffer: the bound framebuffer id (0 for the screen).
def Canvas.framebuffer_id(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.identified(width, height, matrix, state, raster, rig, gl, Canvas.target.id(target))

def Canvas.scissor.size(+x: F32, +y: F32, +w: F32, +h: F32, canvas: Canvas, size: F32 & F32) -> Canvas:
  Canvas{+width, +height, matrix, state, raster, rig, target, box} = canvas
  (+vw, +vh) = size
  Canvas{width, height, matrix, state, raster, Rig.scissor.begin(x, y, w, h, height, vw, vh, rig), target, box}

def Canvas.scissor.with(+x: F32, +y: F32, +w: F32, +h: F32, result: Canvas & (F32 & F32)) -> Canvas:
  (canvas, size) = result
  Canvas.scissor.size(x, y, w, h, canvas, size)

# BeginScissorMode's rlScissor for C ints x, y, w, h (the caller bounds them):
# y from the bottom of the current color buffer, clip-space bounds from the
# current viewport.
def Canvas.scissor(+x: F32, +y: F32, +w: F32, +h: F32, canvas: Canvas) -> Canvas:
  Canvas.scissor.with(x, y, w, h, Canvas.read.viewport(canvas))

# EndScissorMode: rlDisableScissorTest.
def Canvas.unscissor(canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, raster, Rig.scissor.enable(False{}, rig), target, gl}

def Canvas.target.enter(meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, +width: U32, +height: U32, state: Immediate, raster: Raster, rig: Rig, gl: GlBox) -> Canvas:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Canvas.build(tw, th, state, Raster{texels, atlas, sampler, ok, extra}, Rig.view(tw, th, rig), Offscreen{width, height, pixels, meta}, GlBox.view(tw, th, gl))

def Canvas.target.begin(target: Target, meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, gl: GlBox) -> Canvas:
  match target:
    case Screen{}: Canvas.target.enter(meta, tw, th, texels, width, height, state, raster, rig, gl)
    case Offscreen{sw, sh, pixels, active}: Canvas{width, height, matrix, state, Raster.refuse(raster), rig, Offscreen{sw, sh, pixels, active}, gl}

# BeginTextureMode: the render texture's color buffer becomes the target,
# with its viewport and orthographic projection and an identity modelview; the
# scissor keeps the clip-space bounds computed for the previous viewport.
# Starting a texture mode while one is active is refused (the frame becomes
# undefined and the second target is dropped).
def Canvas.begin_target(meta: RenderTarget, +tw: U32, +th: U32, texels: Array<U32>, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.target.begin(target, meta, tw, th, texels, width, height, matrix, state, raster, rig, gl)

def Canvas.target.leave(+sw: U32, +sh: U32, screen: Array<U32>, meta: RenderTarget, +tw: U32, +th: U32, state: Immediate, raster: Raster, rig: Rig, gl: GlBox) -> Canvas & Maybe<Detached>:
  Raster{texels, atlas, sampler, ok, extra} = raster
  (Canvas.build(sw, sh, state, Raster{screen, atlas, sampler, ok, extra}, Rig.view(sw, sh, rig), Screen{}, GlBox.view(sw, sh, gl)), Some{Detached{meta, tw, th, texels}})

def Canvas.target.end(target: Target, +width: U32, +height: U32, state: Immediate, raster: Raster, rig: Rig, gl: GlBox) -> Canvas & Maybe<Detached>:
  match target:
    case Screen{}: (Canvas.build(width, height, state, raster, Rig.view(width, height, rig), Screen{}, GlBox.view(width, height, gl)), None{})
    case Offscreen{sw, sh, screen, meta}: Canvas.target.leave(sw, sh, screen, meta, width, height, state, raster, rig, gl)

# EndTextureMode: back to the screen's color buffer, viewport and projection
# (SetupViewport) with an identity modelview; the render texture's color
# buffer is handed back. Without a texture mode the state is reset the same.
def Canvas.end_target(canvas: Canvas) -> Canvas & Maybe<Detached>:
  Canvas{width, height, _, state, raster, rig, target, gl} = canvas
  Canvas.target.end(target, width, height, state, raster, rig, gl)

def Canvas.rigged(width: U32, height: U32, matrix: Matrix4, state: Immediate, raster: Raster, target: Target, gl: GlBox, result: Rig & U32) -> Canvas & U32:
  (rig, id) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, id)

# swGenTextures (framebuffer False) or swGenFramebuffers: 0 when full.
def Canvas.take(framebuffer: Bool, canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.rigged(width, height, matrix, state, raster, target, gl, Rig.take(framebuffer, rig))

# swDeleteTextures / swDeleteFramebuffers of a live id.
def Canvas.give(framebuffer: Bool, +id: U32, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, raster, Rig.give(framebuffer, id, rig), target, gl}

# Texture ids still available.
def Canvas.room(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, state, raster, +rig, target, gl} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, Rig.room(rig))

# -----------------------------------------------------------------------------
# Immediate state updates

def Immediate.mode.of(+state: Immediate) -> U32:
  Immediate{mode, _, _, _, _, _, _, _} = state
  mode

def Immediate.bound.of(+state: Immediate) -> U32:
  Immediate{_, bound, _, _, _, _, _, _} = state
  bound

def Immediate.active(+state: Immediate) -> Bool:
  Bool.not(U32.is_eq(Immediate.mode.of(state), 0))

def Immediate.started(+mode: U32, +textured: U32, +caps: U32, state: Immediate) -> Immediate:
  Immediate{_, +bound, _, _, paint, _, _, _} = state
  Immediate{mode, bound, textured, False{}, paint, Nil{}, 0, caps}

def Immediate.end(state: Immediate) -> Immediate:
  Immediate{_, bound, textured, alpha, paint, pending, count, caps} = state
  Immediate{0, bound, textured, alpha, paint, pending, count, caps}

# glBindTexture (refused while a primitive is being recorded).
def Immediate.texture(+kind: U32, state: Immediate) -> Immediate:
  Immediate{+mode, +bound, textured, alpha, paint, pending, count, caps} = state
  Immediate{mode, Bool.pick(U32, U32.is_eq(mode, 0), kind, bound), textured, alpha, paint, pending, count, caps}

def Immediate.paint.color(+r: F32, +g: F32, +b: F32, +a: F32, state: Immediate) -> Immediate:
  Immediate{mode, bound, textured, alpha, paint, pending, count, caps} = state
  Attr{_, _, _, _, u, v, z} = paint
  Immediate{mode, bound, textured, alpha || (a < 1.0 : F32), Attr{r, g, b, a, u, v, z}, pending, count, caps}

# swColor4ub: byte*SW_INV_255; any alpha below 1 marks the primitive.
def Immediate.color(+color: U32, state: Immediate) -> Immediate:
  Immediate.paint.color(lut((color >> 24n : U32)), lut(((color >> 16n) .&. 255 : U32)), lut(((color >> 8n) .&. 255 : U32)), lut((color .&. 255 : U32)), state)

# sw_immediate_set_texcoord: the texture matrix applied as m0*u + m4*v + m12,
# m1*u + m5*v + m13.
def Immediate.texcoord(+m: Matrix4, +u: F32, +v: F32, state: Immediate) -> Immediate:
  Matrix4{m0, m1, _, _, m4, m5, _, _, _, _, _, _, m12, m13, _, _} = m
  Immediate{mode, bound, textured, alpha, paint, pending, count, caps} = state
  Attr{r, g, b, a, _, _, z} = paint
  Immediate{mode, bound, textured, alpha, Attr{r, g, b, a, (m0 * u + m4 * v + m12 : F32), (m1 * u + m5 * v + m13 : F32), z}, pending, count, caps}

def Immediate.paint(+state: Immediate) -> Attr:
  Immediate{_, _, _, _, paint, _, _, _} = state
  paint

def Canvas.with_state(state: Immediate, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, _, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, raster, rig, target, gl}

def caps.blend(+caps: U32) -> Bool:
  U32.is_eq((caps .&. 1 : U32), 1)

def caps.depth(+caps: U32) -> Bool:
  U32.is_eq((caps .&. 2 : U32), 2)

def blend.textured(+textured: U32, +bound: U32) -> Bool:
  Bool.not(U32.is_eq(textured, 0)) && bound.alpha(bound)

def Pipe.with_depth(+pipe: Pipe, +depth: Bool) -> Pipe:
  Pipe{cull, poly, thick, radius, port, _} = pipe
  Pipe{cull, poly, thick, radius, port, depth}

def Canvas.render.target(+mode: U32, +textured: U32, +blend: Bool, +depth: Bool, +width: U32, +height: U32, +rig: Rig, +pipe: Pipe, pending: +List<Vertex>, raster: Raster, result: Target & Bool) -> Target & Raster:
  (target, +offscreen) = result
  +tested = depth && Bool.not(offscreen)
  (target, render(mode, textured, blend, Pipe.with_depth(pipe, tested), width, height, Rig.scissor(rig), List.reverse(&2, Vertex, pending),
    Raster.require(Bool.not(depth && offscreen), raster)))

def Canvas.rendered(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, rig: Rig, gl: GlBox, result: Target & Raster) -> Canvas:
  (target, raster) = result
  Canvas{width, height, matrix, state, raster, rig, target, gl}

def Canvas.render.with(+mode: U32, +textured: U32, +alpha: Bool, +bound: U32, +paint: Attr, +caps: U32, pending: +List<Vertex>, result: Canvas & Pipe) -> Canvas:
  (canvas, +pipe) = result
  Canvas{+width, +height, matrix, _, raster, +rig, target, box} = canvas
  +blend = caps.blend(caps) && (alpha || blend.textured(textured, bound))
  Canvas.rendered(width, height, matrix, Immediate{mode, bound, textured, False{}, paint, Nil{}, 0, caps}, rig, box,
    Canvas.render.target(mode, textured, blend, caps.depth(caps), width, height, rig, pipe, pending, raster, Canvas.target.offscreen(target)))

# A complete primitive: rendered, then the alpha flag and vertices reset. A
# depth-tested primitive into a render texture is refused (its depth buffer
# is not modeled).
def Canvas.render(+mode: U32, +textured: U32, +alpha: Bool, +bound: U32, +paint: Attr, +caps: U32, pending: +List<Vertex>, canvas: Canvas) -> Canvas:
  Canvas.render.with(mode, textured, alpha, bound, paint, caps, pending, Canvas.read.pipe(canvas))

def Canvas.emit(full: Bool, +mode: U32, +textured: U32, +alpha: Bool, +bound: U32, +paint: Attr, +caps: U32, pending: +List<Vertex>, +count: U32, canvas: Canvas) -> Canvas:
  match full:
    case False{}: Canvas.with_state(Immediate{mode, bound, textured, alpha, paint, pending, count, caps}, canvas)
    case True{}: Canvas.render(mode, textured, alpha, bound, paint, caps, pending, canvas)

def Canvas.vertex(+vertex: Vertex, state: Immediate, canvas: Canvas) -> Canvas:
  Immediate{+mode, +bound, +textured, +alpha, +paint, pending, +count, +caps} = state
  Canvas.emit(U32.is_eq((count + 1 : U32), mode), mode, textured, alpha, bound, paint, caps, Con{vertex, pending}, (count + 1 : U32), canvas)

def Matrix4.point(+matrix: Matrix4, +x: F32, +y: F32, +z: F32, +paint: Attr) -> Vertex:
  Attr{r, g, b, a, u, v, _} = paint
  Matrix4.vertex(matrix, x, y, z, r, g, b, a, u, v)

# sw_immediate_push_vertex: clip coordinates from the MVP, current attributes.
def Canvas.point(+x: F32, +y: F32, +z: F32, canvas: Canvas) -> Canvas:
  Canvas{width, height, +matrix, +state, raster, rig, target, gl} = canvas
  Canvas.vertex(Matrix4.point(matrix, x, y, z, Immediate.paint(state)), state, Canvas{width, height, matrix, state, raster, rig, target, gl})

def Canvas.mode(canvas: Canvas) -> Canvas & U32:
  Canvas{width, height, matrix, +state, raster, rig, target, gl} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, Immediate.mode.of(state))

def Canvas.point.active(active: Bool, +x: F32, +y: F32, +z: F32, canvas: Canvas) -> Canvas:
  match active:
    case False{}: canvas
    case True{}: Canvas.point(x, y, z, canvas)

def Canvas.step.point(+x: F32, +y: F32, +z: F32, read: Canvas & U32) -> Canvas:
  (canvas, +mode) = read
  Canvas.point.active(Bool.not(U32.is_eq(mode, 0)), x, y, z, canvas)

# swBegin (refused while a primitive is being recorded): the MVP, the sampler
# when GL_TEXTURE_2D is enabled and the bound texture has pixels, and the
# blend and depth-test states.
def Canvas.begin.info(+count: U32, canvas: Canvas, info: Bool & U32) -> Canvas:
  Canvas{width, height, _, +state, raster, +rig, target, box} = canvas
  (+enabled, +caps) = info
  +bound = Immediate.bound.of(state)
  Canvas{width, height, Rig.mvp(rig), Immediate.started(count, Bool.pick(U32, enabled, bound.sampler(bound), 0), caps, state), raster, rig, target, box}

def Canvas.begin.go.with(+count: U32, result: Canvas & (Bool & U32)) -> Canvas:
  (canvas, info) = result
  Canvas.begin.info(count, canvas, info)

def Canvas.begin.go(+count: U32, canvas: Canvas) -> Canvas:
  Canvas.begin.go.with(count, Canvas.read.begin(canvas))

def Canvas.begin.start(start: Bool, +count: U32, canvas: Canvas) -> Canvas:
  match start:
    case False{}: canvas
    case True{}: Canvas.begin.go(count, canvas)

def Canvas.begin.read(+count: U32, read: Canvas & U32) -> Canvas:
  (canvas, +mode) = read
  Canvas.begin.start(U32.is_eq(mode, 0), count, canvas)

def Canvas.begin(+count: U32, canvas: Canvas) -> Canvas:
  Canvas.begin.read(count, Canvas.mode(canvas))

def Canvas.state(command: Command, state: Immediate) -> Immediate:
  match command:
    case Color{color}: Immediate.color(color, state)
    case ColorF{r, g, b, a}: Immediate.paint.color(r, g, b, a, state)
    case End{}: Immediate.end(state)
    case _: state

def Canvas.step.state(command: Command, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, Canvas.state(command, state), raster, rig, target, gl}

def Canvas.texcoord.with(+u: F32, +v: F32, result: Canvas & Matrix4) -> Canvas:
  (canvas, +m) = result
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas{width, height, matrix, Immediate.texcoord(m, u, v, state), raster, rig, target, box}

def Canvas.texcoord(+u: F32, +v: F32, canvas: Canvas) -> Canvas:
  Canvas.texcoord.with(u, v, Canvas.read.texture(canvas))

def Canvas.shape_uv.apply(uv: F32 & F32, canvas: Canvas) -> Canvas:
  (+u, +v) = uv
  Canvas.texcoord(u, v, canvas)

def Canvas.shape_uv.with(result: Canvas & (F32 & F32)) -> Canvas:
  (canvas, uv) = result
  Canvas.shape_uv.apply(uv, canvas)

def Canvas.shape_uv(+corner: U32, canvas: Canvas) -> Canvas:
  Canvas.shape_uv.with(Canvas.read.shape_uv(corner, canvas))

# rlSetTexture(id): glEnable or glDisable(GL_TEXTURE_2D), then glBindTexture
# (refused while a primitive is being recorded).
def Canvas.bind(+kind: U32, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, Immediate.texture(kind, state), raster, rig, target, GlBox.texturing(Bool.not(U32.is_eq(kind, 0)), gl)}

def Canvas.bind.kind(result: Canvas & U32) -> Canvas:
  (canvas, +kind) = result
  Canvas.bind(kind, canvas)

def Canvas.bind.shapes(canvas: Canvas) -> Canvas:
  Canvas.bind.kind(Canvas.read.shapes_kind(canvas))

def Canvas.bind.held(canvas: Canvas) -> Canvas:
  Canvas.bind.kind(Canvas.read.held_kind(canvas))

# Marks the canvas undefined (a draw Jonlib refuses, such as an unverified
# libm argument) without drawing.
def Canvas.refuse(canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, Raster.refuse(raster), rig, target, gl}

def Canvas.enable(cap: U32, +on: Bool, canvas: Canvas) -> Canvas:
  match cap:
    case 3: Canvas.scissor.enable(on, canvas)
    case 0: Canvas.set(Enable{0, on}, canvas)
    case 1: Canvas.set(Enable{1, on}, canvas)
    case _: Canvas.set(Enable{2, on}, canvas)

def Canvas.scissor.rect.size(+x: F32, +y: F32, +w: F32, +h: F32, canvas: Canvas, size: F32 & F32) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  (+vw, +vh) = size
  Canvas{width, height, matrix, state, raster, Rig.scissor.rect(x, y, w, h, vw, vh, rig), target, box}

def Canvas.scissor.rect.with(+x: F32, +y: F32, +w: F32, +h: F32, result: Canvas & (F32 & F32)) -> Canvas:
  (canvas, size) = result
  Canvas.scissor.rect.size(x, y, w, h, canvas, size)

# rlScissor(x, y, w, h) for C ints, with the current viewport's size.
def Canvas.scissor.rect(+x: F32, +y: F32, +w: F32, +h: F32, canvas: Canvas) -> Canvas:
  Canvas.scissor.rect.with(x, y, w, h, Canvas.read.viewport(canvas))

def Canvas.step(+command: Command, canvas: Canvas) -> Canvas:
  match command:
    case Point{x, y}: Canvas.step.point(x, y, 0.0, Canvas.mode(canvas))
    case Vertex3{x, y, z}: Canvas.step.point(x, y, z, Canvas.mode(canvas))
    case Begin{count}: Canvas.begin(count, canvas)
    case Color{color}: Canvas.step.state(Color{color}, canvas)
    case ColorF{r, g, b, a}: Canvas.step.state(ColorF{r, g, b, a}, canvas)
    case TexCoord{u, v}: Canvas.texcoord(u, v, canvas)
    case ShapeUV{corner}: Canvas.shape_uv(corner, canvas)
    case Texture{kind}: Canvas.bind(kind, canvas)
    case ShapeTexture{}: Canvas.bind.shapes(canvas)
    case HeldTexture{}: Canvas.bind.held(canvas)
    case End{}: Canvas.step.state(End{}, canvas)
    case Push{}: Canvas.adjust(Push{}, canvas)
    case Pop{}: Canvas.adjust(Pop{}, canvas)
    case Identity{}: Canvas.adjust(Identity{}, canvas)
    case Multiply{matrix}: Canvas.adjust(Multiply{matrix}, canvas)
    case PostMultiply{matrix}: Canvas.adjust(PostMultiply{matrix}, canvas)
    case Mode{mode}: Canvas.set(Mode{mode}, canvas)
    case Viewport{x, y, w, h}: Canvas.set(Viewport{x, y, w, h}, canvas)
    case Enable{cap, on}: Canvas.enable(cap, on, canvas)
    case CullFace{front}: Canvas.set(CullFace{front}, canvas)
    case PolyMode{mode}: Canvas.set(PolyMode{mode}, canvas)
    case LineWidth{width}: Canvas.set(LineWidth{width}, canvas)
    case PointSize{size}: Canvas.set(PointSize{size}, canvas)
    case ClearColor{color}: Canvas.clear_color(color, canvas)
    case Clear{}: Canvas.clear.buffers(canvas)
    case ScissorRect{x, y, w, h}: Canvas.scissor.rect(x, y, w, h, canvas)
    case Refuse{}: Canvas.refuse(canvas)

def Canvas.run(commands: +List<Command>, canvas: Canvas) -> Canvas:
  match commands:
    case Nil{}: canvas
    case Con{command, rest}: Canvas.run(rest, Canvas.step(command, canvas))

def Canvas.draw(valid: Bool, commands: +List<Command>, canvas: Canvas) -> Canvas:
  match valid:
    case False{}: Canvas.refuse(canvas)
    case True{}: Canvas.run(commands, canvas)

def Raster.bind(sampler: Sampler, raster: Raster) -> Raster:
  Raster{pixels, atlas, _, ok, extra} = raster
  Raster{pixels, atlas, sampler, ok, extra}

def Raster.unbind(raster: Raster) -> Raster & Sampler:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  (Raster{pixels, atlas, Unbound{}, ok, extra}, sampler)

def Canvas.unbound(width: U32, height: U32, matrix: Matrix4, state: Immediate, rig: Rig, target: Target, gl: GlBox, result: Raster & Sampler) -> Canvas & Sampler:
  (raster, sampler) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, sampler)

def Canvas.unbind(canvas: Canvas) -> Canvas & Sampler:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas.unbound(width, height, matrix, state, rig, target, gl, Raster.unbind(raster))

def Canvas.bind.sampler(sampler: Sampler, canvas: Canvas) -> Canvas:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  Canvas{width, height, matrix, state, Raster.bind(sampler, raster), rig, target, gl}

# A draw with a user texture's texels bound for its duration (the texture is
# handed back).
def Canvas.draw_sampled(valid: Bool, commands: +List<Command>, sampler: Sampler, canvas: Canvas) -> Canvas & Sampler:
  Canvas.unbind(Canvas.draw(valid, commands, Canvas.bind.sampler(sampler, canvas)))

# -----------------------------------------------------------------------------
# Held textures: rlSetTexture's texture (slot 4) and the shapes texture
# (slot 3) live in the frame while it uses them; each is handed back with its
# metadata when replaced or released.

def Extra.held.swap(sampler: Sampler, extra: Extra) -> Extra & Sampler:
  Extra{depth, shapes, held} = extra
  (Extra{depth, shapes, sampler}, held)

def Extra.shapes.swap(sampler: Sampler, extra: Extra) -> Extra & Sampler:
  Extra{depth, shapes, held} = extra
  (Extra{depth, sampler, held}, shapes)

def Raster.swapped(pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, result: Extra & Sampler) -> Raster & Sampler:
  (extra, old) = result
  (Raster{pixels, atlas, sampler, ok, extra}, old)

def Raster.swap.with(shapes_slot: Bool, incoming: Sampler, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, ok: Bool, extra: Extra) -> Raster & Sampler:
  match shapes_slot:
    case True{}: Raster.swapped(pixels, atlas, sampler, ok, Extra.shapes.swap(incoming, extra))
    case False{}: Raster.swapped(pixels, atlas, sampler, ok, Extra.held.swap(incoming, extra))

def Raster.swap(shapes_slot: Bool, incoming: Sampler, raster: Raster) -> Raster & Sampler:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  Raster.swap.with(shapes_slot, incoming, pixels, atlas, sampler, ok, extra)

def held.pair.some(some: Bool, +meta: Meta, sampler: Sampler) -> Maybe<(Meta & Sampler)>:
  match some:
    case False{}: None{}
    case True{}: Some{(meta, sampler)}

def held.pair(+meta: Meta, sampler: Sampler) -> Maybe<(Meta & Sampler)>:
  held.pair.some(Bool.not(U32.is_eq(Meta.id(meta), 0)), meta, sampler)

def Canvas.swapped(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, rig: Rig, target: Target, gl: GlBox, +old: Meta, result: Raster & Sampler) -> Canvas & Maybe<(Meta & Sampler)>:
  (raster, sampler) = result
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, held.pair(old, sampler))

def Canvas.active(canvas: Canvas) -> Canvas & Bool:
  Canvas{width, height, matrix, +state, raster, rig, target, gl} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, Immediate.active(state))

def Canvas.hold.bound(result: Canvas & Maybe<(Meta & Sampler)>) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, old) = result
  (Canvas.bind.held(canvas), old)

def Canvas.hold.store.with(sampler: Sampler, result: Canvas & Meta) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, +old) = result
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas.hold.bound(Canvas.swapped(width, height, matrix, state, rig, target, box, old, Raster.swap(False{}, sampler, raster)))

def Canvas.hold.store(+meta: Meta, sampler: Sampler, canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  Canvas.hold.store.with(sampler, Canvas.update.swap_held(meta, canvas))

def Canvas.hold.done(active: Bool, meta: Meta, sampler: Sampler, canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  match active:
    case True{}: (Canvas.texturing(canvas), Some{(meta, sampler)})
    case False{}: Canvas.hold.store(meta, sampler, canvas)

def Canvas.hold.read(meta: Meta, sampler: Sampler, read: Canvas & Bool) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, active) = read
  Canvas.hold.done(active, meta, sampler, canvas)

# rlSetTexture(texture.id) for a texture the frame takes: bound and held until
# released or replaced (the previous one is handed back). While a primitive is
# being recorded the bind is refused (GL_TEXTURE_2D is still enabled) and the
# texture is handed back at once.
def Canvas.hold(meta: Meta, sampler: Sampler, canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  Canvas.hold.read(meta, sampler, Canvas.active(canvas))

def Canvas.release.store.with(result: Canvas & Meta) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, +old) = result
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas.swapped(width, height, matrix, state, rig, target, box, old, Raster.swap(False{}, Unbound{}, raster))

def Canvas.release.store(canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  Canvas.release.store.with(Canvas.update.swap_held(Meta.none(), canvas))

def Canvas.release.done(active: Bool, canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  match active:
    case True{}: (Canvas.bind(0, canvas), None{})
    case False{}: Canvas.release.store(Canvas.bind(0, canvas))

def Canvas.release.read(read: Canvas & Bool) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, active) = read
  Canvas.release.done(active, canvas)

# rlSetTexture(0): GL_TEXTURE_2D disabled and nothing bound; the held texture
# is handed back (kept while a primitive is being recorded, as the unbind is
# refused then).
def Canvas.release(canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  Canvas.release.read(Canvas.active(canvas))

def Canvas.shapes.swapped(result: Canvas & Maybe<(Meta & Sampler)>) -> Canvas & Maybe<(Meta & Sampler)>:
  result

def Canvas.set_shapes.with(sampler: Sampler, result: Canvas & Meta) -> Canvas & Maybe<(Meta & Sampler)>:
  (canvas, +old) = result
  Canvas{width, height, matrix, state, raster, rig, target, box} = canvas
  Canvas.swapped(width, height, matrix, state, rig, target, box, old, Raster.swap(True{}, sampler, raster))

# SetShapesTexture with a user texture (taken) and its source rectangle, or
# with none (Shapes.reset); the previous user shapes texture is handed back.
def Canvas.set_shapes(+shapes: Shapes, sampler: Sampler, canvas: Canvas) -> Canvas & Maybe<(Meta & Sampler)>:
  Canvas.set_shapes.with(sampler, Canvas.update.swap_shapes(shapes, canvas))

# GetShapesTexture's fields and GetShapesTextureRectangle.
def Canvas.shapes(canvas: Canvas) -> Canvas & Shapes:
  Canvas.read.shapes(canvas)

# rlGetLineWidth (lineWidth) and rlGetPointSize (2*pointRadius).
def Canvas.line_width(canvas: Canvas) -> Canvas & F32:
  Canvas.read.thick(canvas)

def Canvas.point_size(canvas: Canvas) -> Canvas & F32:
  Canvas.read.point_size(canvas)

# rlGetMatrixModelview and rlGetMatrixProjection: the stack tops.
def Canvas.modelview(canvas: Canvas) -> Canvas & Matrix4:
  Canvas{width, height, matrix, state, raster, +rig, target, gl} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, Rig.modelview(rig))

def Canvas.projection(canvas: Canvas) -> Canvas & Matrix4:
  Canvas{width, height, matrix, state, raster, +rig, target, gl} = canvas
  (Canvas{width, height, matrix, state, raster, rig, target, gl}, Rig.projection(rig))

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

def read.result(+width: U32, +height: U32, matrix: Matrix4, state: Immediate, atlas: Array<U32>, sampler: Sampler, extra: Extra, rig: Rig, gl: GlBox, buffers: Array<U32> & Array<U32>) -> Canvas & Maybe<Array<U32>>:
  (pixels, out) = buffers
  (Canvas{width, height, matrix, state, Raster{pixels, atlas, sampler, True{}, extra}, rig, Screen{}, gl}, Some{out})

def read.checked(ok: Bool, +width: U32, +height: U32, +mask: U32, matrix: Matrix4, state: Immediate, rig: Rig, gl: GlBox, pixels: Array<U32>, atlas: Array<U32>, sampler: Sampler, extra: Extra) -> Canvas & Maybe<Array<U32>>:
  match ok:
    case False{}: (Canvas{width, height, matrix, state, Raster{pixels, atlas, sampler, False{}, extra}, rig, Screen{}, gl}, None{})
    case True{}:
      +count = (width * height : U32)
      read.result(width, height, matrix, state, atlas, sampler, extra, rig, gl, read.loop(U32.to_nat(count), 0, width, height, mask, (pixels, Array.new(U32, depth(count), 0))))

def read.screen(+mask: U32, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, rig: Rig, gl: GlBox, raster: Raster) -> Canvas & Maybe<Array<U32>>:
  Raster{pixels, atlas, sampler, ok, extra} = raster
  read.checked(ok, width, height, mask, matrix, state, rig, gl, pixels, atlas, sampler, extra)

def read.target(target: Target, +mask: U32, +width: U32, +height: U32, matrix: Matrix4, state: Immediate, raster: Raster, rig: Rig, gl: GlBox) -> Canvas & Maybe<Array<U32>>:
  match target:
    case Screen{}: read.screen(mask, width, height, matrix, state, rig, gl, raster)
    case Offscreen{sw, sh, screen, meta}: (Canvas{width, height, matrix, state, raster, rig, Offscreen{sw, sh, screen, meta}, gl}, None{})

def Canvas.read(+opaque: Bool, canvas: Canvas) -> Canvas & Maybe<Array<U32>>:
  Canvas{width, height, matrix, state, raster, rig, target, gl} = canvas
  read.target(target, Bool.pick(U32, opaque, 255, 0), width, height, matrix, state, raster, rig, gl)
