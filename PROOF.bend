import Base
import ./LAWS.bend as Laws
import ./jonlib.bend as J
import ./jonmath.bend as M

def Laws.clear_dimensions(width, height, pixels, color):
  {==}

def Laws.transpose_involution(matrix):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  {==}

def Laws.vector3_float_count(vector):
  M.Vector3{x, y, z} = vector
  {==}

def Laws.matrix_float_count(matrix):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = matrix
  {==}

def Laws.binary64_jam_zero(value):
  {==}

def Laws.binary64_jam_successor(count, value):
  {==}

def Laws.binary64_reject_special(exponent, sign, value):
  {==}

def Laws.binary64_half_minimum():
  {==}

def Laws.binary64_above_half_minimum():
  {==}

def Laws.binary64_minimum_normal_carry():
  {==}

def Laws.binary64_overflow_carry():
  {==}

def Laws.binary64_negative_zero():
  {==}

def Laws.binary64_odd_halfway():
  {==}
