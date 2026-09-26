# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_perlin.h v0.5, Copyright (c) 2017 Sean Barrett.
# MIT alternative retained in LICENSES/stb-perlin.txt; raylib wrapper: LICENSES/raylib.txt.
import Base
import ./fused.bend as F

# Original tables packed into bytes/nibbles; indices wrap at the repeated 256 entries.
def permutation.word(index: U32) -> U32:
  match index:
    case 0: 882998551
    case 1: 625374567
    case 2: 2848679415
    case 3: 2066513532
    case 4: 764538520
    case 5: 184382123
    case 6: 2634320064
    case 7: 1210261241
    case 8: 1515012015
    case 9: 1868566709
    case 10: 2722850949
    case 11: 4030871645
    case 12: 3847500296
    case 13: 4021146161
    case 14: 307691917
    case 15: 965723650
    case 16: 3644498145
    case 17: 3438661288
    case 18: 1011418823
    case 19: 3922978324
    case 20: 156813406
    case 21: 253860682
    case 22: 3403842267
    case 23: 2888494163
    case 24: 3728202405
    case 25: 2590141230
    case 26: 2999206765
    case 27: 4077756031
    case 28: 4171648833
    case 29: 1349771289
    case 30: 2159555396
    case 31: 2056769768
    case 32: 728355866
    case 33: 2498483635
    case 34: 3272497554
    case 35: 1282428444
    case 36: 4212666362
    case 37: 3199888524
    case 38: 2344069860
    case 39: 4143234087
    case 40: 2423730308
    case 41: 3246820020
    case 42: 2037954130
    case 43: 64085078
    case 44: 1435890011
    case 45: 3631322829
    case 46: 2754176031
    case 47: 3885618865
    case 48: 2931377958
    case 49: 1595787617
    case 50: 4264975367
    case 51: 3710023359
    case 52: 1671629699
    case 53: 2481148394
    case 54: 2383523996
    case 55: 1047399493
    case 56: 3254845211
    case 57: 4243747899
    case 58: 901453075
    case 59: 2269151695
    case 60: 3987155005
    case 61: 2674581350
    case 62: 2312617413
    case _: 85336100

def permutation(+index: U32) -> U32:
  ((permutation.word(((index >> 2n) .&. 63 : U32)) >> U32.to_nat(((index .&. 3) * 8 : U32))) .&. 255 : U32)

def gradients.word(index: U32) -> U32:
  match index:
    case 0: 2518353303
    case 1: 1957174163
    case 2: 2846052712
    case 3: 2267354240
    case 4: 1946266039
    case 5: 2185325317
    case 6: 1965659304
    case 7: 1533159193
    case 8: 17864261
    case 9: 329550183
    case 10: 3048904834
    case 11: 1111729707
    case 12: 2788565929
    case 13: 3106645045
    case 14: 189352625
    case 15: 1728054452
    case 16: 1130049866
    case 17: 135278994
    case 18: 2789242998
    case 19: 546026280
    case 20: 379585412
    case 21: 822498338
    case 22: 2305381787
    case 23: 3110699395
    case 24: 831874426
    case 25: 371958279
    case 26: 923957171
    case 27: 2785350016
    case 28: 2315722939
    case 29: 1880823635
    case 30: 842685193
    case _: 1447597973

def gradients(+index: U32) -> U32:
  ((gradients.word(((index >> 3n) .&. 31 : U32)) >> U32.to_nat(((index .&. 7) * 4 : U32))) .&. 15 : U32)

def mad(fused: Bool, a: F32, b: F32, c: F32) -> F32:
  match fused:
    case False{}: (a * b + c : F32)
    case True{}: F.multiply_add(a, b, c)

def ease(+fused: Bool, +x: F32) -> F32:
  (mad(fused, mad(fused, x, 6.0, F32.neg(15.0)), x, 10.0) * x * x * x : F32)

def lerp(fused: Bool, +a: F32, b: F32, t: F32) -> F32:
  mad(fused, (b - a : F32), t, a)

def gradient.dot(+fused: Bool, a: F32, b: F32, c: F32, x: F32, y: F32, z: F32) -> F32:
  mad(fused, c, z, mad(fused, a, x, (b * y : F32)))

def gradient(index: U32, fused: Bool, x: F32, y: F32, z: F32) -> F32:
  match index:
    case 0: gradient.dot(fused, 1.0, 1.0, 0.0, x, y, z)
    case 1: gradient.dot(fused, F32.neg(1.0), 1.0, 0.0, x, y, z)
    case 2: gradient.dot(fused, 1.0, F32.neg(1.0), 0.0, x, y, z)
    case 3: gradient.dot(fused, F32.neg(1.0), F32.neg(1.0), 0.0, x, y, z)
    case 4: gradient.dot(fused, 1.0, 0.0, 1.0, x, y, z)
    case 5: gradient.dot(fused, F32.neg(1.0), 0.0, 1.0, x, y, z)
    case 6: gradient.dot(fused, 1.0, 0.0, F32.neg(1.0), x, y, z)
    case 7: gradient.dot(fused, F32.neg(1.0), 0.0, F32.neg(1.0), x, y, z)
    case 8: gradient.dot(fused, 0.0, 1.0, 1.0, x, y, z)
    case 9: gradient.dot(fused, 0.0, F32.neg(1.0), 1.0, x, y, z)
    case 10: gradient.dot(fused, 0.0, 1.0, F32.neg(1.0), x, y, z)
    case _: gradient.dot(fused, 0.0, F32.neg(1.0), F32.neg(1.0), x, y, z)

def coordinate(+value: F32) -> U32:
  +integer = F32.to_u32(F32.abs(value))
  (Bool.pick(U32, (value < 0.0 : F32), (0 - integer : U32), integer) .&. 255 : U32)

def noise(+fused: Bool, +x: F32, +y: F32, +z: F32, +seed: U32) -> F32:
  +px = F32.floor(x)
  +py = F32.floor(y)
  +pz = F32.floor(z)
  +ix = coordinate(px)
  +iy = coordinate(py)
  +iz = coordinate(pz)
  +r0 = permutation((ix + seed : U32))
  +r1 = permutation((((ix + 1) .&. 255) + seed : U32))
  +r00 = permutation((r0 + iy : U32))
  +r01 = permutation((r0 + ((iy + 1) .&. 255) : U32))
  +r10 = permutation((r1 + iy : U32))
  +r11 = permutation((r1 + ((iy + 1) .&. 255) : U32))
  +fx = (x - px : F32)
  +fy = (y - py : F32)
  +fz = (z - pz : F32)
  +u = ease(fused, fx)
  +v = ease(fused, fy)
  +w = ease(fused, fz)
  a = lerp(fused, gradient(gradients((r00 + iz : U32)), fused, fx, fy, fz),
    gradient(gradients((r00 + ((iz + 1) .&. 255) : U32)), fused, fx, fy, (fz - 1.0 : F32)), w)
  b = lerp(fused, gradient(gradients((r01 + iz : U32)), fused, fx, (fy - 1.0 : F32), fz),
    gradient(gradients((r01 + ((iz + 1) .&. 255) : U32)), fused, fx, (fy - 1.0 : F32), (fz - 1.0 : F32)), w)
  c = lerp(fused, gradient(gradients((r10 + iz : U32)), fused, (fx - 1.0 : F32), fy, fz),
    gradient(gradients((r10 + ((iz + 1) .&. 255) : U32)), fused, (fx - 1.0 : F32), fy, (fz - 1.0 : F32)), w)
  d = lerp(fused, gradient(gradients((r11 + iz : U32)), fused, (fx - 1.0 : F32), (fy - 1.0 : F32), fz),
    gradient(gradients((r11 + ((iz + 1) .&. 255) : U32)), fused, (fx - 1.0 : F32), (fy - 1.0 : F32), (fz - 1.0 : F32)), w)
  lerp(fused, lerp(fused, a, b, v), lerp(fused, c, d, v), u)

def fbm(n: Nat, +fused: Bool, +x: F32, +y: F32, +frequency: F32, +amplitude: F32, +seed: U32, total: F32) -> F32:
  match n:
    case 0n: total
    case 1n+rest:
      value = noise(fused, (x * frequency : F32), (y * frequency : F32), frequency, seed)
      fbm(rest, fused, x, y, (frequency * 2.0 : F32), (amplitude * 0.5 : F32), (seed + 1 : U32), mad(fused, value, amplitude, total))

def pixel(fused: Bool, +x: F32, +y: F32, +width: F32, +height: F32, offset_x: F32, offset_y: F32, +scale: F32) -> U32:
  +ratio = (width / height : F32)
  +nx = ((x + offset_x) * (scale / width) : F32)
  +ny = ((y + offset_y) * (scale / height) : F32)
  +wide = (width > height : F32)
  value = fbm(6n, fused, Bool.pick(F32, wide, (nx * ratio : F32), nx), Bool.pick(F32, wide, ny, (ny / ratio : F32)), 1.0, 1.0, 0, 0.0)
  +intensity = F32.to_u32(((F32.clamp(value, F32.neg(1.0), 1.0) + 1.0) / 2.0 * 255.0 : F32))
  ((intensity << 24n) .|. (intensity << 16n) .|. (intensity << 8n) .|. 255 : U32)

def pixels(n: Nat, +index: U32, +fused: Bool, +width: U32, +height: U32, +offset_x: F32, +offset_y: F32, +scale: F32, output: Array<U32>) -> Array<U32>:
  match n:
    case 0n: output
    case 1n+rest:
      color = pixel(fused, U32.to_f32((index % width : U32)), U32.to_f32((index / width : U32)), U32.to_f32(width), U32.to_f32(height), offset_x, offset_y, scale)
      pixels(rest, (index + 1 : U32), fused, width, height, offset_x, offset_y, scale, Array.set(U32, output, index, color))
