#!/usr/bin/env python3
"""Compare Jonlib's cameras with the pinned rcamera.h/rcore.c camera functions.

Every F32 result bit of GetCameraForward/Up/Right, CameraMoveForward/Up/Right/
ToTarget, CameraYaw/Pitch/Roll, GetCameraViewMatrix, GetCameraMatrix,
GetCameraProjectionMatrix, GetCameraMatrix2D, GetWorldToScreen2D,
GetScreenToWorld2D, GetWorldToScreenEx, GetScreenToWorldRayEx and
UpdateCameraPro must equal the reference; NaN words compare as one class. By
default the reference is the linked raylib with the host contraction profile
(conformance.contraction) and the host libm (sinf/cosf as
conformance.gradient_reference, atan2f selected from native controls as in
conformance.qualify_angles). --uncontracted-control and --fused-control
instead compile the pinned functions without or with clang contraction (no
linked raylib); --gnu-libm then replaces sinf/cosf with the Arm
optimized-routines model of tools/trig_probe.py and atan2f with the pinned
glibc 2.39 (Sun) or 2.41 source and tan with the glibc x86_64 FMA-variant
model (tools/glibc_tan.py), checking the glibc profiles on any host.

A C oracle repeats the refusal contract to decide where Jonlib must answer
None: CAMERA_PERSPECTIVE projections under AppleLibm (Apple's binary64 tan
is unpublished, docs/PERSPECTIVE.md) and with a nonfinite fovy*DEG2RAD or
aspect, nonzero sinf/cosf arguments under AppleLibm
(Jonmath's Apple sine/cosine is not macOS arm64's), glibc arguments that are
subnormal or nonfinite, lockView angles outside the
checked atan2f contract, screen sizes outside 1..INT_MAX and orthographic spans
outside the checked binary64 multiplier. The total binary32 FMA kernel
(src/fma.bend) behind M.Fused{} is also compared with the host fmaf over every
input class.

Inputs: random cameras and degenerate ones (target == position, up parallel
to the view, zero, signed-zero, subnormal, huge and nonfinite components), each
world-plane branch of the up vector and its 0.7071f thresholds, lockView
pitches near +-89 degrees, every rotateAroundTarget/rotateUp/lockView flag,
orthographic/perspective/other projections, 2D cameras with rotation, zoom and
offset, and screen sizes from 1x1 to INT_MAX. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import math
import platform
import random
import re
import struct

from conformance import LIBM_FOR_PROFILE, contraction, gradient_reference, qualify_angles
import glibc_tan
import probekit
from probekit import ROOT, ProbeFailure

NAN = 0x7FC00000
# words per case and results per case, in candidate/reference order
SECTIONS = {'fma': (3, 1), 'basis': (12, 6), 'move': (13, 4), 'turn': (13, 3), 'screen': (18, 2), 'view2d': (8, 3), 'pro': (18, 1)}
CHUNKS = {'fma': 1000, 'basis': 60, 'move': 60, 'turn': 60, 'screen': 40, 'view2d': 60, 'pro': 40}
PI = 3.14159265358979323846


def word(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


INF, NEG_INF, QNAN = 0x7F800000, 0xFF800000, 0x7FC00000
BOUND = word(6.283186)


class Raw(int):
    """An explicit binary32 word among float inputs."""


def words(values):
    return [int(v) if isinstance(v, Raw) else word(float(v)) for v in values]


# -----------------------------------------------------------------------------
# Inputs

def fma_cases(rng):
    def pick():
        k = rng.randrange(10)
        if k == 0:
            return rng.choice([0, 0x80000000, INF, NEG_INF, QNAN, 1, 0x80000001, 0x007FFFFF, 0x00800000,
                               0x7F7FFFFF, 0xFF7FFFFF, 0x3F800000, 0xBF800000])
        if k == 1:
            return (rng.randrange(2) << 31) | rng.randrange(1, 0x00800000)
        if k == 2:
            return (rng.randrange(2) << 31) | (rng.randint(1, 30) << 23) | rng.randrange(1 << 23)
        if k == 3:
            return (rng.randrange(2) << 31) | (rng.randint(220, 254) << 23) | rng.randrange(1 << 23)
        return (rng.randrange(2) << 31) | (rng.randint(90, 165) << 23) | rng.randrange(1 << 23)
    cases = [[pick(), pick(), pick()] for _ in range(3000)]
    for _ in range(1000):  # cancellation against the rounded product
        a = (rng.randint(60, 190) << 23) | rng.randrange(1 << 23)
        b = (rng.randint(60, 190) << 23) | rng.randrange(1 << 23)
        product = f32(f32(struct.unpack('<f', struct.pack('<I', a))[0]) * f32(struct.unpack('<f', struct.pack('<I', b))[0]))
        if math.isfinite(product):
            cases.append([a, b, ((word(product) ^ 0x80000000) + rng.randint(-3, 3)) & 0xFFFFFFFF])
    for _ in range(1000):  # subnormal products and sums
        a = (rng.randrange(2) << 31) | (rng.randint(1, 80) << 23) | rng.randrange(1 << 23)
        b = (rng.randrange(2) << 31) | (rng.randint(1, 80) << 23) | rng.randrange(1 << 23)
        cases.append([a, b, (rng.randrange(2) << 31) | rng.randrange(0, 0x01000000)])
    # Even and odd ties, a tiny addend straddling a tie, signed zeros and overflow.
    cases += [[word(1.0000001192092896), word(1.5), word(2.0 ** -100)], [word(1.0000001192092896), word(1.5), word(-2.0 ** -100)],
              [word(1.5), word(2.0), word(-3.0)], [0x80000000, word(1.0), 0x80000000], [0, word(-1.0), 0],
              [word(1e-30), word(-1e-30), 0], [word(1e-30), word(1e-30), 0x80000000], [0x7F7FFFFF, word(2.0), 0xFF7FFFFF],
              [0x7F7FFFFF, word(1.5), word(-1e38)], [word(3e38), word(3e38), NEG_INF], [word(1e20), word(1e20), INF]]
    return cases


def unit(rng):
    values = [rng.gauss(0, 1) for _ in range(3)]
    length = math.sqrt(sum(v * v for v in values)) or 1.0
    return [v / length for v in values]


def special_cameras():
    """(position, target, up, fovy, projection) rows for degenerate and edge cameras."""
    cameras = []
    add = lambda p, t, u, fovy=45.0, projection=1: cameras.append((list(p), list(t), list(u), fovy, projection))
    add([0, 2, 4], [0, 2, 4], [0, 1, 0])                       # target == position
    add([0, 0, 0], [0, 5, 0], [0, 1, 0])                       # up parallel to the view
    add([0, 0, 0], [0, -5, 0], [0, 2, 0])                      # up antiparallel
    add([1, 2, 3], [4, 5, 6], [0, 0, 0])                       # zero up
    add([-0.0, 0.0, -0.0], [0.0, -0.0, -1.0], [-0.0, 1.0, -0.0])
    add([0.0, 0.0, 0.0], [-0.0, -0.0, -0.0], [-0.0, -0.0, -0.0], -0.0, 1)
    add([1e30, -1e30, 2e30], [-1e30, 1e30, 0], [0, 1, 0], 1e30)
    add([3e38, 3e38, -3e38], [-3e38, 0, 0], [3e38, 3e38, 0], 3e38)
    add([1e-30, 2e-30, 0], [-1e-30, 0, 3e-30], [1e-40, 1.0, 0], 1e-30)
    add([1e-40, -1e-40, 0], [2e-40, 0, -1e-41], [0, 1e-39, 1e-40], 1e-40)
    add([1, 1, 1], [1, 1, 1 + 2 ** -22], [0, 1, 0])           # tiny view vector
    add([0, 0, 0], [1e-20, 1e-20, 1e-20], [0, 1, 0])
    add([0, 0, 0], [1, 0, 0], [0, 0, 1], 60.0, 0)
    add([0, 0, 0], [1, 1, 0], [0, 0, -1], 60.0, 2)
    add([0, 0, 0], [0, 1, 1], [1, 0, 0], 60.0, 0xFFFFFFFF)
    add([0, 0, 0], [0, 1, 1], [-1, 0, 0])
    add([2, 0, 0], [0, 0, 0], [0.7071, 0.7071, 0])            # 0.7071f thresholds
    add([2, 0, 0], [0, 1, 0], [0.70710003, 0.0, 0.7071])
    add([2, 0, 0], [0, 1, 0], [0.0, 0.5, f32(0.7071) + 2 ** -24])
    add([2, 0, 0], [0, 1, 0], [-0.70710003, 0.1, -0.7071])
    add([0, 0, 0], [5, 0.0001, 0], [0, 1, 0])                   # nearly horizontal view
    add([0, 0, 0], [1e-4, 10, 0], [0, 1, 0])                    # nearly straight up (pitch ~89 degrees)
    add([0, 0, 0], [1e-4, -10, 1e-5], [0, 1, 0])                # nearly straight down
    add([0, 0, 0], [0.0174, 1, 0], [0, 1, 0])
    add([0, 0, 0], [-0.0175, -1, 0.001], [0, 1, 0])
    add([float('nan'), 0, 0], [1, 2, 3], [0, 1, 0])
    add([0, 0, 0], [1, 2, 3], [0, float('inf'), 0])
    add([0, 0, 0], [float('inf'), 0, 0], [0, 1, 0], float('inf'))
    add([0, 0, 0], [0, 0, -1], [0, 1, 0], float('nan'))
    return cameras


def random_camera(rng):
    position = [rng.uniform(-100, 100) for _ in range(3)]
    direction = unit(rng)
    distance = rng.choice((rng.uniform(0.01, 1), rng.uniform(1, 100), rng.uniform(100, 5000)))
    target = [p + distance * d for p, d in zip(position, direction)]
    choice = rng.randrange(5)
    if choice == 0:
        up = [0.0, 1.0, 0.0]
    elif choice == 1:
        up = [0.0, 0.0, rng.choice((1.0, -1.0))]
    elif choice == 2:
        up = [rng.choice((1.0, -1.0)) * rng.uniform(0.71, 1), rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5)]
    elif choice == 3:
        up = [rng.uniform(-1, 1) * rng.choice((0.3, 1, 5)) for _ in range(3)]
    else:
        up = [rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7)]
    return (position, target, up, rng.choice((rng.uniform(1, 120), rng.uniform(0.01, 1000))), rng.choice((0, 1, 1, 1, 2)))


def camera_words(camera):
    position, target, up, fovy, projection = camera
    return words([*position, *target, *up, fovy]) + [projection]


def cameras(rng, count):
    rows = special_cameras()
    rows += [random_camera(rng) for _ in range(count - len(rows))]
    return rows


ANGLES = [0.0, -0.0, PI, -PI, PI / 2, -PI / 2, 6.283186, -6.283186, Raw(BOUND + 1), Raw((BOUND + 1) | 0x80000000), 7.0, -100.0,
          1e-40, -1e-39, 1e-30, 1e-8, 0.001, 1.5533430, -1.5533430, 3.0, float('nan'), float('inf'), float('-inf')]


def angle_word(value):
    return words([value])[0]


def basis_cases(rng):
    aspects = [16 / 9, 1.0, 4 / 3, 0.25, 0.0, -1.0, 1e30, 1e-40, float('inf'), float('nan'), 3e38]
    rows = []
    for index, camera in enumerate(cameras(rng, 360)):
        aspect = aspects[index % len(aspects)] if index % 3 == 0 else rng.uniform(0.2, 4)
        rows.append(camera_words(camera) + words([aspect]))
    return rows


def move_cases(rng):
    distances = [0.0, -0.0, 1.0, -1.0, 1e30, -1e-40, 5.4, -3e38, float('nan')]
    rows = []
    for index, camera in enumerate(cameras(rng, 360)):
        distance = distances[index % len(distances)] if index % 4 == 0 else rng.uniform(-20, 20)
        rows.append(camera_words(camera) + words([distance]) + [index & 1])
    return rows


def turn_cases(rng):
    rows = []
    for index, camera in enumerate(cameras(rng, 520)):
        angle = angle_word(ANGLES[index % len(ANGLES)]) if index % 3 == 0 else word(rng.uniform(-6.3, 6.3))
        rows.append(camera_words(camera) + [angle, index & 7])
    # lockView near the vertical: large pitches are clamped to the up/down limits.
    for _ in range(80):
        tilt = rng.uniform(-1e-3, 1e-3)
        target = [tilt, rng.choice((1, -1)) * rng.uniform(1, 10), rng.uniform(-1e-3, 1e-3)]
        camera = ([0, 0, 0], target, [0, 1, 0], 45.0, 1)
        rows.append(camera_words(camera) + [word(rng.choice((1, -1)) * rng.uniform(0.5, 3.1)), 1 | (rng.randrange(4) << 1)])
    return rows


SIZES = [(800, 450), (1920, 1080), (1, 1), (3, 7), (4096, 2160), (16777217, 3), (2147483647, 2147483647), (2147483647, 1),
         (1, 2147483647), (0, 600), (600, 0), (0x80000000, 600), (600, 0xFFFFFFFF), (1280, 720)]


def screen_cases(rng):
    rows = []
    fovies = [45.0, 0.0, -0.0, 1e-40, 1e30, 3e38, float('nan'), float('inf'), 1e-30, 2.0 ** 97, 2.0 ** 100]
    for index, camera in enumerate(cameras(rng, 320)):
        position, target, up, fovy, projection = camera
        if index % 4 == 0:
            fovy = fovies[index // 4 % len(fovies)]
        width, height = SIZES[index % len(SIZES)] if index % 2 == 0 else (rng.randint(1, 5000), rng.randint(1, 5000))
        world = [t + rng.uniform(-10, 10) for t in target] if all(map(math.isfinite, target)) else [1.0, 2.0, 3.0]
        screen = [rng.uniform(-10, min(width, 1e6) + 10), rng.uniform(-10, min(height, 1e6) + 10)]
        rows.append(camera_words((position, target, up, fovy, projection)) + words(world + screen) + [width, height])
    return rows


def view2d_cases(rng):
    rotations = [0.0, -0.0, 90.0, -90.0, 180.0, 360.0, -360.0, 360.0001, -360.0001, 720.0, 1e-40, 45.0, float('nan'), float('inf')]
    zooms = [1.0, 0.0, -1.0, 1e30, 1e-30, 2.5, float('nan')]
    rows = []
    for index in range(360):
        offset = [rng.uniform(-1000, 1000) for _ in range(2)]
        target = [rng.uniform(-1000, 1000) for _ in range(2)]
        rotation = rotations[index % len(rotations)] if index % 3 == 0 else rng.uniform(-360, 360)
        zoom = zooms[index % len(zooms)] if index % 5 == 0 else rng.uniform(0.05, 10)
        point = [rng.uniform(-2000, 2000) for _ in range(2)]
        if index % 17 == 0:
            offset, target, point = [-0.0, 0.0], [0.0, -0.0], [-0.0, -0.0]
        rows.append(words([*offset, *target, rotation, zoom, *point]))
    return rows


def pro_cases(rng):
    rows = []
    for index, camera in enumerate(cameras(rng, 280)):
        movement = [rng.uniform(-5, 5) for _ in range(3)]
        rotation = [rng.uniform(-180, 180) for _ in range(3)]
        if index % 5 == 0:
            rotation = [rng.choice((0.0, 360.0, 359.99, 400.0, -0.0)), rng.choice((0.0, 1000.0, -1000.0, 89.0)), rng.choice((0.0, -360.0, 10.0))]
        zoom = rng.choice((0.0, -1.0, 2.0, -1000.0, rng.uniform(-5, 5)))
        rows.append(camera_words(camera) + words(movement + rotation + [zoom]))
    return rows


GENERATORS = {'fma': fma_cases, 'basis': basis_cases, 'move': move_cases, 'turn': turn_cases, 'screen': screen_cases,
              'view2d': view2d_cases, 'pro': pro_cases}


# -----------------------------------------------------------------------------
# Native reference

ORACLE = r'''
static unsigned bits(float x) { unsigned b; memcpy(&b, &x, 4); return b; }
static float value(unsigned b) { float x; memcpy(&x, &b, 4); return x; }
static Vector3 vec(const unsigned *w) { return (Vector3){ value(w[0]), value(w[1]), value(w[2]) }; }
static Camera cam(const unsigned *w) {
  Camera c; c.position = vec(w); c.target = vec(w + 3); c.up = vec(w + 6); c.fovy = value(w[9]); c.projection = (int)w[10];
  return c;
}
static void v2(Vector2 v) { printf("%u,%u", bits(v.x), bits(v.y)); }
static void v3(Vector3 v) { printf("%u,%u,%u", bits(v.x), bits(v.y), bits(v.z)); }
static void mat(Matrix m) {
  float f[16] = { m.m0, m.m1, m.m2, m.m3, m.m4, m.m5, m.m6, m.m7, m.m8, m.m9, m.m10, m.m11, m.m12, m.m13, m.m14, m.m15 };
  for (int i = 0; i < 16; i++) printf(i ? ",%u" : "%u", bits(f[i]));
}
static void camera_text(Camera c) { v3(c.position); putchar(','); v3(c.target); putchar(','); v3(c.up); }

/* The refusal contract, repeating Jonlib's profile choices (compiled without contraction). */
static float madd(float a, float b, float c) { return FUSED ? fmaf(a, b, c) : a*b + c; }
static float dot3(Vector3 a, Vector3 b) { return madd(a.z, b.z, madd(a.x, b.x, a.y*b.y)); }
static Vector3 cross3(Vector3 a, Vector3 b) {
  return (Vector3){ madd(a.y, b.z, -(a.z*b.y)), madd(a.z, b.x, -(a.x*b.z)), madd(a.x, b.y, -(a.y*b.x)) };
}
static Vector3 norm3(Vector3 v) {
  float l = sqrtf(dot3(v, v));
  if (l != 0.0f) { float i = 1.0f/l; v.x *= i; v.y *= i; v.z *= i; }
  return v;
}
static int normal_or_zero(float x) { unsigned b = bits(x) & 0x7fffffffu; return b == 0 || (b >= 0x00800000u && b < 0x7f800000u); }
/* sinf/cosf arguments Jonlib reproduces: zero, or (glibc profiles) any normal argument. */
static int turnable(float angle, float argument) { (void) angle; return argument == 0.0f || (GNU && normal_or_zero(argument)); }
static int half_turnable(float angle) { return turnable(angle, angle/2.0f); }
static int angle_ok(Vector3 a, Vector3 b, float *out) {
  Vector3 c = cross3(a, b);
  float length = sqrtf(dot3(c, c)), dot = dot3(a, b);
  if (!normal_or_zero(length) || !normal_or_zero(dot)) return 0;
  float r = atan2f(length, dot);
  if (!normal_or_zero(r) || (r == 0.0f && length != 0.0f)) return 0;
  *out = r;
  return 1;
}
static int pitch_ok(Camera c, float angle, int lock) {
  if (lock) {
    Vector3 up = norm3(c.up), view = { c.target.x - c.position.x, c.target.y - c.position.y, c.target.z - c.position.z };
    Vector3 down = { -up.x, -up.y, -up.z };
    float upper, lower;
    if (!angle_ok(up, view, &upper) || !angle_ok(down, view, &lower)) return 0;
    upper -= 0.001f;
    if (angle > upper) angle = upper;
    lower *= -1.0f;
    lower += 0.001f;
    if (angle < lower) angle = lower;
  }
  return half_turnable(angle);
}
/* MatrixPerspective: the glibc profiles' tan; Jonlib refuses a nonfinite fovY or aspect. */
static int perspective_ok(float fovy, double aspect) {
  float angle = fovy*DEG2RAD;
  return GNU && isfinite(angle) && isfinite(aspect);
}
static int screen_ok(Camera c, unsigned width, unsigned height) {
  if (width < 1 || width > INT_MAX || height < 1 || height > INT_MAX) return 0;
  if (c.projection == CAMERA_PERSPECTIVE) return perspective_ok(c.fovy, 1.0);
  if (c.projection == CAMERA_ORTHOGRAPHIC) {
    if (!isfinite(c.fovy)) return 0;
    if (c.fovy != 0.0f) {
      int a, b;
      frexp(c.fovy/2.0, &a);
      frexp((double)width/(double)height, &b);
      if ((a - 1) + (b - 1) > 127) return 0;
    }
  }
  return 1;
}

static unsigned in[400000];
static int load(const char *path) {
  FILE *f = fopen(path, "rb"); int n = 0; unsigned char b[4];
  while (n < 400000 && fread(b, 1, 4, f) == 4) in[n++] = b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
  fclose(f);
  return n;
}
static void fma_section(int n) {
  for (int i = 0; i + 3 <= n; i += 3) printf("%u ", bits(fmaf(value(in[i]), value(in[i+1]), value(in[i+2]))));
}
static void basis_section(int n) {
  for (int i = 0; i + 12 <= n; i += 12) {
    Camera c = cam(in + i);
    v3(GetCameraForward(&c)); putchar('/'); v3(GetCameraUp(&c)); putchar('/'); v3(GetCameraRight(&c)); putchar('/');
    mat(GetCameraViewMatrix(&c)); putchar('/'); mat(GetCameraMatrix(c)); putchar('/');
    if (c.projection == CAMERA_PERSPECTIVE && !perspective_ok(c.fovy, value(in[i+11]))) printf("none");
    else mat(GetCameraProjectionMatrix(&c, value(in[i+11])));
    putchar(' ');
  }
}
static void move_section(int n) {
  for (int i = 0; i + 13 <= n; i += 13) {
    Camera c = cam(in + i), a = c, b = c, d = c, e = c;
    float distance = value(in[i+11]); int plane = in[i+12] & 1;
    CameraMoveForward(&a, distance, plane); CameraMoveRight(&b, distance, plane); CameraMoveUp(&d, distance); CameraMoveToTarget(&e, distance);
    camera_text(a); putchar('/'); camera_text(b); putchar('/'); camera_text(d); putchar('/'); camera_text(e); putchar(' ');
  }
}
static void turn_section(int n) {
  for (int i = 0; i + 13 <= n; i += 13) {
    Camera c = cam(in + i), a = c, b = c, d = c;
    float angle = value(in[i+11]); unsigned flags = in[i+12];
    int lock = flags & 1, around = (flags >> 1) & 1, rotate_up = (flags >> 2) & 1;
    if (half_turnable(angle)) { CameraYaw(&a, angle, around); camera_text(a); } else printf("none");
    putchar('/');
    if (pitch_ok(c, angle, lock)) { CameraPitch(&b, angle, lock, around, rotate_up); camera_text(b); } else printf("none");
    putchar('/');
    if (half_turnable(angle)) { CameraRoll(&d, angle); camera_text(d); } else printf("none");
    putchar(' ');
  }
}
static void screen_section(int n) {
  for (int i = 0; i + 18 <= n; i += 18) {
    Camera c = cam(in + i);
    Vector3 world = vec(in + i + 11);
    Vector2 point = { value(in[i+14]), value(in[i+15]) };
    unsigned width = in[i+16], height = in[i+17];
    if (screen_ok(c, width, height)) {
      v2(GetWorldToScreenEx(world, c, (int)width, (int)height)); putchar('/');
      Ray ray = GetScreenToWorldRayEx(point, c, (int)width, (int)height);
      v3(ray.position); putchar(','); v3(ray.direction);
    } else printf("none/none");
    putchar(' ');
  }
}
static void view2d_section(int n) {
  for (int i = 0; i + 8 <= n; i += 8) {
    Camera2D c = { { value(in[i]), value(in[i+1]) }, { value(in[i+2]), value(in[i+3]) }, value(in[i+4]), value(in[i+5]) };
    Vector2 point = { value(in[i+6]), value(in[i+7]) };
    float angle = c.rotation*DEG2RAD;
    if (turnable(angle, angle)) {
      mat(GetCameraMatrix2D(c)); putchar('/'); v2(GetWorldToScreen2D(point, c)); putchar('/'); v2(GetScreenToWorld2D(point, c));
    } else printf("none/none/none");
    putchar(' ');
  }
}
static void pro_section(int n) {
  for (int i = 0; i + 18 <= n; i += 18) {
    Camera c = cam(in + i), step = c;
    Vector3 movement = vec(in + i + 11), rotation = vec(in + i + 14);
    float zoom = value(in[i+17]);
    int ok = pitch_ok(step, -rotation.y*DEG2RAD, 1);
    if (ok) { CameraPitch(&step, -rotation.y*DEG2RAD, 1, 0, 0); ok = half_turnable(-rotation.x*DEG2RAD); }
    if (ok) { CameraYaw(&step, -rotation.x*DEG2RAD, 0); ok = half_turnable(rotation.z*DEG2RAD); }
    if (ok) { UpdateCameraPro(&c, movement, rotation, zoom); camera_text(c); } else printf("none");
    putchar(' ');
  }
}
int main(int argc, char **argv) {
  for (int i = 1; i + 1 < argc; i += 2) {
    int n = load(argv[i+1]);
    if (!strcmp(argv[i], "fma")) fma_section(n);
    else if (!strcmp(argv[i], "basis")) basis_section(n);
    else if (!strcmp(argv[i], "move")) move_section(n);
    else if (!strcmp(argv[i], "turn")) turn_section(n);
    else if (!strcmp(argv[i], "screen")) screen_section(n);
    else if (!strcmp(argv[i], "view2d")) view2d_section(n);
    else pro_section(n);
    printf("\n");
  }
  return 0;
}
'''

HEADER = '''#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "raylib.h"
#include "rcamera.h"
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
'''


def cull_distances(raylib_source):
    text = (raylib_source / 'src/rlgl.h').read_text()
    found = [re.search(rf'#ifndef {name}\s*\n\s*#define {name}\s+(\S+)', text) for name in ('RL_CULL_DISTANCE_NEAR', 'RL_CULL_DISTANCE_FAR')]
    if not all(found):
        raise ProbeFailure('camera: pinned rlgl.h cull distances not found')
    return [match.group(1) for match in found]


def between(text, begin, end):
    start = text.index(begin)
    return text[start:text.index(end, start)]


def control_source(raylib_source):
    """The pinned camera functions, unaltered, with rlgl's default cull distances."""
    near, far = cull_distances(raylib_source)
    rcamera = (raylib_source / 'src/rcamera.h').read_text()
    rcore = (raylib_source / 'src/rcore.c').read_text()
    pieces = [between(rcamera, 'Vector3 GetCameraForward(Camera *camera)\n{', '#if !defined(RCAMERA_STANDALONE)\n// Update camera position'),
              between(rcamera, 'void UpdateCameraPro(', '#endif // RCAMERA_IMPLEMENTATION'),
              between(rcore, 'Ray GetScreenToWorldRayEx(', '// Get the screen space position from a 3d world space position'),
              between(rcore, 'Vector2 GetWorldToScreenEx(', '//----------------------------------------------------------------------------------')]
    return (f'#define RL_CULL_DISTANCE_NEAR {near}\n#define RL_CULL_DISTANCE_FAR {far}\n'
            'static double rlGetCullDistanceNear(void) { return RL_CULL_DISTANCE_NEAR; }\n'
            'static double rlGetCullDistanceFar(void) { return RL_CULL_DISTANCE_FAR; }\n'
            '/* Unaltered camera functions from pinned raylib rcamera.h and rcore.c; zlib, LICENSES/raylib.txt. */\n'
            + '\n'.join(pieces))


# -----------------------------------------------------------------------------
# Candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/fma.bend as Fma
def float(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def words(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), words(rest)}
    case _: Nil{}
def bits(+x: F32) -> String:
  U32.show(F32.bits(x))
def v2(v: M.Vector2) -> String:
  M.Vector2{x, y} = v
  bits(x) ++ "," ++ bits(y)
def v3(v: M.Vector3) -> String:
  M.Vector3{x, y, z} = v
  bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z)
def matrix(m: M.Matrix) -> String:
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = m
  bits(m0) ++ "," ++ bits(m1) ++ "," ++ bits(m2) ++ "," ++ bits(m3) ++ "," ++ bits(m4) ++ "," ++ bits(m5) ++ "," ++ bits(m6) ++ "," ++ bits(m7) ++ "," ++ bits(m8) ++ "," ++ bits(m9) ++ "," ++ bits(m10) ++ "," ++ bits(m11) ++ "," ++ bits(m12) ++ "," ++ bits(m13) ++ "," ++ bits(m14) ++ "," ++ bits(m15)
def camera_text(c: J.Camera3D) -> String:
  J.Camera3D{p, t, u, _, _} = c
  v3(p) ++ "," ++ v3(t) ++ "," ++ v3(u)
def maybe_camera(m: Maybe<J.Camera3D>) -> String:
  match m:
    case None{}: "none"
    case Some{c}: camera_text(c)
def maybe_matrix(m: Maybe<M.Matrix>) -> String:
  match m:
    case None{}: "none"
    case Some{value}: matrix(value)
def maybe_v2(m: Maybe<M.Vector2>) -> String:
  match m:
    case None{}: "none"
    case Some{value}: v2(value)
def maybe_ray(m: Maybe<J.Ray>) -> String:
  match m:
    case None{}: "none"
    case Some{J.Ray{p, d}}: v3(p) ++ "," ++ v3(d)
def vector(+x: U32, +y: U32, +z: U32) -> M.Vector3:
  M.Vector3{float(x), float(y), float(z)}
def point(+x: U32, +y: U32) -> M.Vector2:
  M.Vector2{float(x), float(y)}
def camera(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32, j: U32, k: U32) -> J.Camera3D:
  J.Camera3D{vector(a, b, c), vector(d, e, f), vector(g, h, i), float(j), k}
def camera2d(a: U32, b: U32, c: U32, d: U32, e: U32, f: U32) -> J.Camera2D:
  J.Camera2D{point(a, b), point(c, d), float(e), float(f)}
def flag(+w: U32, +bit: U32) -> Bool:
  U32.is_ne((w .&. bit : U32), 0)
def fma(values: +List<U32>) -> String:
  match values:
    case PATTERN_fma: bits(Fma.multiply_add(float(w0), float(w1), float(w2))) ++ " " ++ fma(rest)
    case _: ""
def basis(values: +List<U32>) -> String:
  match values:
    case PATTERN_basis:
      +c = camera(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)
      v3(J.Camera.forward_for(ARITH, c)) ++ "/" ++ v3(J.Camera.up_for(ARITH, c)) ++ "/" ++ v3(J.Camera.right_for(ARITH, c)) ++ "/" ++ matrix(J.Camera.view_matrix_for(ARITH, c)) ++ "/" ++ matrix(J.Camera.matrix_for(ARITH, c)) ++ "/" ++ maybe_matrix(J.Camera.projection_matrix_for(LIBM, c, float(w11))) ++ " " ++ basis(rest)
    case _: ""
def move(values: +List<U32>) -> String:
  match values:
    case PATTERN_move:
      +c = camera(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)
      +d = float(w11)
      +plane = flag(w12, 1)
      camera_text(J.Camera.move_forward_for(ARITH, c, d, plane)) ++ "/" ++ camera_text(J.Camera.move_right_for(ARITH, c, d, plane)) ++ "/" ++ camera_text(J.Camera.move_up_for(ARITH, c, d)) ++ "/" ++ camera_text(J.Camera.move_to_target_for(ARITH, c, d)) ++ " " ++ move(rest)
    case _: ""
def turn(values: +List<U32>) -> String:
  match values:
    case PATTERN_turn:
      +c = camera(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)
      +angle = float(w11)
      maybe_camera(J.Camera.yaw_for(ARITH, LIBM, c, angle, flag(w12, 2))) ++ "/" ++ maybe_camera(J.Camera.pitch_for(ARITH, LIBM, c, angle, flag(w12, 1), flag(w12, 2), flag(w12, 4))) ++ "/" ++ maybe_camera(J.Camera.roll_for(ARITH, LIBM, c, angle)) ++ " " ++ turn(rest)
    case _: ""
def screen(values: +List<U32>) -> String:
  match values:
    case PATTERN_screen:
      +c = camera(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)
      maybe_v2(J.Camera.world_to_screen_ex_for(ARITH, LIBM, vector(w11, w12, w13), c, w16, w17)) ++ "/" ++ maybe_ray(J.Camera.screen_to_world_ray_ex_for(ARITH, LIBM, point(w14, w15), c, w16, w17)) ++ " " ++ screen(rest)
    case _: ""
def view2d(values: +List<U32>) -> String:
  match values:
    case PATTERN_view2d:
      +c = camera2d(w0, w1, w2, w3, w4, w5)
      +p = point(w6, w7)
      maybe_matrix(J.Camera.matrix_2d_for(ARITH, LIBM, c)) ++ "/" ++ maybe_v2(J.Camera.world_to_screen_2d_for(ARITH, LIBM, p, c)) ++ "/" ++ maybe_v2(J.Camera.screen_to_world_2d_for(ARITH, LIBM, p, c)) ++ " " ++ view2d(rest)
    case _: ""
def pro(values: +List<U32>) -> String:
  match values:
    case PATTERN_pro:
      maybe_camera(J.Camera.update_pro_for(ARITH, LIBM, camera(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10), vector(w11, w12, w13), vector(w14, w15, w16), float(w17))) ++ " " ++ pro(rest)
    case _: ""
def text(kind: U32, values: +List<U32>) -> String:
  match kind:
    case 0: fma(values)
    case 1: basis(values)
    case 2: move(values)
    case 3: turn(values)
    case 4: screen(values)
    case 5: view2d(values)
    case _: pro(values)
def section(kind: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{bytes}: IO.print(text(kind, words(bytes)))
def main() -> IO(Unit):
  do IO<Unit>:
'''

KINDS = {name: index for index, name in enumerate(SECTIONS)}


def pattern(count):
    """Con{w0, Con{w1, ... rest}} binding count words; reused flags are copyable."""
    text = 'rest'
    for index in reversed(range(count)):
        text = f'Con{{+w{index}, {text}}}'
    return text


def program(arithmetic, libm):
    text = PROGRAM.replace('ARITH', f'M.{arithmetic}{{}}').replace('LIBM', f'M.{libm}{{}}')
    for name, (size, _) in SECTIONS.items():
        text = text.replace(f'PATTERN_{name}', pattern(size))
    return text


def parse_line(line, results):
    """Rows of canonical results: one tuple of words (or None) per result."""
    rows = []
    for item in line.split():
        parts = item.split('/')
        if len(parts) != results:
            raise ProbeFailure(f'camera: malformed item {item[:80]}')
        rows.append(tuple(None if part == 'none' else tuple(NAN if (int(w) & 0x7FFFFFFF) > 0x7F800000 else int(w) for w in part.split(','))
                          for part in parts))
    return rows


GNU_LIBM = {'glibc239': ('Glibc239Libm', 'sun239_atan2f'), 'glibc241': ('Glibc241Libm', 'glibc241_atan2f')}


def configure(parser):
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--uncontracted-control', action='store_true',
                       help='compile the pinned camera functions without contraction instead of linking raylib')
    modes.add_argument('--fused-control', action='store_true',
                       help='compile the pinned camera functions with clang contraction into FMA instead of linking raylib')
    parser.add_argument('--gnu-libm', choices=sorted(GNU_LIBM),
                        help='with a control: sinf/cosf from the Arm optimized-routines model, atan2f from the pinned glibc source')


def gnu_objects(probe, symbol):
    """The Arm sinf/cosf model, the pinned glibc atan2f kernels and the glibc tan model as objects (contraction off)."""
    from angle_kernel_probe import build_oracle
    from trig_probe import REFERENCE as TRIG_REFERENCE
    model = TRIG_REFERENCE[TRIG_REFERENCE.index('/* Arm'):TRIG_REFERENCE.index('int main')].replace('\\\\', '\\')
    source, model_object = probe.work / 'arm-model.c', probe.work / 'arm-model.o'
    source.write_text(model + 'float model_sinf(float x) { float c, s; arm_model(x, &c, &s); return s; }\n'
                      'float model_cosf(float x) { float c, s; arm_model(x, &c, &s); return c; }\n')
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-c', source, '-o', model_object])
    _cc, kernels, _driver = build_oracle(probe)
    # <math.h> first: glibc's vector declarations expand the libm names, which must not be renamed yet.
    header = (f'#include <math.h>\n#define sinf model_sinf\n#define cosf model_cosf\n#define atan2f {symbol}\n'
              f'#define tan {glibc_tan.SYMBOL}\n'
              f'float model_sinf(float);\nfloat model_cosf(float);\nfloat {symbol}(float, float);\ndouble {glibc_tan.SYMBOL}(double);\n')
    return header, [model_object, *kernels, *glibc_tan.objects(probe)]


def main():
    args = probekit.arguments(__doc__, configure)
    control = 'uncontracted' if args.uncontracted_control else 'fused' if args.fused_control else None
    if args.gnu_libm and not control:
        raise SystemExit('--gnu-libm needs --uncontracted-control or --fused-control')
    name = 'camera' + (f'-{control}' if control else '') + (f'-{args.gnu_libm}' if args.gnu_libm else '')
    probe = probekit.Probe(name, args)
    # Clang contracts a*b + c per expression on every target; x86-64 needs -mfma to emit it.
    # M.Fused is arm64 clang's contraction (fnmadd folding, positive default NaNs); x86 FMA code differs in
    # zero and NaN signs. On other hosts the fused control runs as the host's (uncontracted) control, as the
    # linked-library gate selects its profile by host.
    fma_flags = {'arm64': [], 'aarch64': []}.get(platform.machine())
    if control == 'fused' and fma_flags is None:
        control = 'uncontracted'
        probe.report['fused_control'] = f'not on {platform.machine()}: run as the uncontracted control'
    arithmetic = {'uncontracted': 'Uncontracted', 'fused': 'Fused'}.get(control) or contraction()
    header, objects = '', []
    if args.gnu_libm:
        libm, symbol = GNU_LIBM[args.gnu_libm]
        header, objects = gnu_objects(probe, symbol)
    else:
        rotation_libm = gradient_reference()
        angle_profile = qualify_angles(args.raylib_source, probe.library)['selected_profile']
        libm = LIBM_FOR_PROFILE[angle_profile]
        if (libm == 'AppleLibm') != (rotation_libm == 'AppleLibm'):
            raise ProbeFailure(f'camera: atan2f profile {angle_profile} and sinf/cosf profile {rotation_libm} need different M.Libm values')
        if libm != 'AppleLibm' and not glibc_tan.host_is_model(probe):
            raise ProbeFailure('camera: the host tan is not the glibc x86_64 FMA-variant model of the glibc profiles')
    rng = random.Random(0xCA3E7A)
    work = probe.work / 'cases'
    work.mkdir(parents=True, exist_ok=True)
    actions, counts = [], {}
    for section, generate in GENERATORS.items():
        rows = generate(rng)
        counts[section] = len(rows)
        size = SECTIONS[section][0]
        if any(len(row) != size for row in rows):
            raise ProbeFailure(f'camera: {section} rows must have {size} words')
        for index in range(0, len(rows), CHUNKS[section]):
            path = (work / f'{section}-{index // CHUNKS[section]}.bin').relative_to(ROOT).as_posix()
            (ROOT / path).write_bytes(b''.join(struct.pack('<I', w) for row in rows[index:index + CHUNKS[section]] for w in row))
            actions.append((section, path))
    source = header + HEADER + f'#define FUSED {int(arithmetic == "Fused")}\n#define GNU {int(libm != "AppleLibm")}\n'
    if control:
        source = ('#pragma STDC FP_CONTRACT OFF\n' if control == 'uncontracted' else '') + source + control_source(args.raylib_source)
    source += ORACLE
    contract = ['-ffp-contract=on', *fma_flags] if control == 'fused' else ['-ffp-contract=off']
    probe.native(source, 'reference-build', extra_flags=(*contract, *objects), link_raylib=not control)
    argv = [part for section, path in actions for part in (section, path)]
    lines = probekit.run([probe.work / 'reference-build', *argv]).splitlines()
    if len(lines) != len(actions):
        raise ProbeFailure('camera: incomplete reference output')
    expected = [parse_line(line, SECTIONS[section][1]) for (section, _), line in zip(actions, lines)]
    text = program(arithmetic, libm)

    def render(selected, gpu):
        body = text
        for section, path in selected:
            body += (f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, '
                     f'J.Files.load_data("{path}"), section({KINDS[section]}))\n')
        return body + '    IO.print("done")\n'

    def parse(output, selected):
        rows = output.splitlines()
        if rows[-1:] != ['done'] or len(rows) != len(selected) + 1:
            raise ProbeFailure('camera: candidate output did not finish')
        return [parse_line(line, SECTIONS[section][1]) for (section, _), line in zip(selected, rows)]

    lanes = probe.candidates(render, actions, batch=8, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}

    def describe(index):
        section, path = actions[index]
        rows = next(iter(lanes.values()))[index]
        case = next((i for i, (a, b) in enumerate(zip(expected[index], rows)) if a != b), None)
        result = case is not None and next(k for k, (a, b) in enumerate(zip(expected[index][case], rows[case])) if a != b)
        return f'{section} {path} case {case} result {result}'

    probe.compare(expected, lanes, describe=describe)
    refused = {section: sum(part is None for (s, _), rows in zip(actions, expected) if s == section for row in rows for part in row)
               for section in SECTIONS}
    reference = {None: 'linked raylib', 'uncontracted': 'uncontracted source control', 'fused': 'contracted source control'}[control]
    probe.finish(reference=reference + (f' with {args.gnu_libm} sinf/cosf/atan2f models' if args.gnu_libm else ''),
                 profile=arithmetic, libm=libm, cases=counts, refused_results=refused,
                 inputs_sha256=hashlib.sha256(b''.join((ROOT / path).read_bytes() for _, path in actions)).hexdigest(),
                 reference_sha256=hashlib.sha256('\n'.join(lines).encode()).hexdigest())

if __name__ == '__main__':
    main()
