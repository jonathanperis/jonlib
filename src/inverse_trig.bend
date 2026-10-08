# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of the Sun float acosf (glibc 2.39
# sysdeps/ieee754/flt-32/e_acosf.c, commit ef321e23c20e), with the source's
# constants, branches and F32 operation order. Copyright (C) 1993 Sun
# Microsystems, Inc.; permission notice in LICENSES/sun-math.txt.
import Base

def word(+value: U32) -> F32:
  U32{bits} = value
  F32{bits}

def pi() -> F32:
  word(1078530010)

def pio2_hi() -> F32:
  word(1070141402)

def pio2_lo() -> F32:
  word(866263400)

# z*(pS0+z*(pS1+z*(pS2+z*(pS3+z*(pS4+z*pS5))))) over 1+z*(qS1+z*(qS2+z*(qS3+z*qS4))).
def ratio(+z: F32) -> F32:
  +p = (z * (word(1042983595) + z * (word(3198595216) + z * (word(1045301928) + z * (word(3173257542) + z * (word(978288388) + z * word(940699400)))))) : F32)
  +q = (1.0 + z * (word(3222917433) + z * (word(1073829677) + z * (word(3207607137) + z * word(1033750062)))) : F32)
  (p / q : F32)

# 0: |x| = 1; 1: |x| > 1 or NaN; 2: |x| <= 2^-26; 3: |x| < 0.5; 4: x <= -0.5; 5: x >= 0.5.
def region(+bits: U32) -> U32:
  +ix = (bits .&. 2147483647 : U32)
  Bool.pick(U32, U32.is_eq(ix, 1065353216), 0, Bool.pick(U32, (ix > 1065353216 : U32), 1,
    Bool.pick(U32, (ix < 1056964608 : U32), Bool.pick(U32, (ix <= 847249408 : U32), 2, 3), Bool.pick(U32, (bits >= 2147483648 : U32), 4, 5))))

def acos.large(+x: F32) -> F32:
  +z = ((1.0 - x) * 0.5 : F32)
  +s = F32.sqrt(z)
  +df = word((F32.bits(s) .&. 4294963200 : U32))
  +c = ((z - df * df) / (s + df) : F32)
  +w = (ratio(z) * s + c : F32)
  (2.0 * (df + w) : F32)

def acos.at(region: U32, +x: F32) -> Maybe<F32>:
  match region:
    case 0: Some{Bool.pick(F32, (F32.bits(x) >= 2147483648 : U32), (pi() + 2.0 * pio2_lo() : F32), 0.0)}
    case 1: None{}
    case 2: Some{(pio2_hi() + pio2_lo() : F32)}
    case 3:
      +r = ratio((x * x : F32))
      Some{(pio2_hi() - (x - (pio2_lo() - x * r)) : F32)}
    case 4:
      +z = ((1.0 + x) * 0.5 : F32)
      +s = F32.sqrt(z)
      +w = (ratio(z) * s - pio2_lo() : F32)
      Some{(pi() - 2.0 * (s + w) : F32)}
    case _: Some{acos.large(x)}

# glibc 2.39 acosf on [-1, 1]; None for |x| > 1 and NaN, where the source
# returns a NaN whose bits depend on the host.
def acos(+x: F32) -> Maybe<F32>:
  acos.at(region(F32.bits(x)), x)
