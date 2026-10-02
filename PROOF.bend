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

def Laws.bounded_fma_shift_zero(value):
  {==}

def Laws.bounded_fma_shift_successor(count, value):
  {==}

def Laws.bounded_fma_reject(ah, al, bh, bl, ch, cl):
  {==}

def Laws.bounded_fma_negative_zero():
  {==}

def Laws.bounded_fma_mixed_zero():
  {==}

def Laws.bounded_fma_exact_cancellation():
  {==}

def Laws.bounded_fma_product_residual():
  {==}

def Laws.bounded_fma_even_tie():
  {==}

def Laws.bounded_fma_odd_tie():
  {==}

def Laws.bounded_fma_lattice_floor():
  {==}

def Laws.bounded_add_sub_reject(ah, al, bh, bl):
  {==}

def Laws.bounded_sub_sign_inversion(ah, al, bh, bl):
  {==}

def Laws.bounded_add_negative_zeros():
  {==}

def Laws.bounded_add_mixed_zeros():
  {==}

def Laws.bounded_sub_negative_zero():
  {==}

def Laws.bounded_sub_equal_negative_zeros():
  {==}

def Laws.bounded_add_cancellation():
  {==}

def Laws.bounded_add_even_tie():
  {==}

def Laws.bounded_add_odd_tie():
  {==}

def Laws.bounded_sub_lattice_floor():
  {==}

def Laws.bounded_add_largest_carry():
  {==}

def Laws.checked_multiply_reject(ah, al, bh, bl):
  {==}

def Laws.checked_divide_reject(ah, al, bh, bl):
  {==}

def Laws.checked_decode_reject(high, low):
  {==}




def Laws.checked_multiply_negative_zero():
  {==}

def Laws.checked_multiply_zero_invalid():
  {==}

def Laws.checked_divide_negative_zero():
  {==}

def Laws.checked_divide_zero_denominator():
  {==}





def Laws.words_increment_negative_carry():
  {==}

def Laws.words_decrement_negative_borrow():
  {==}

def Laws.words_zero_equality():
  {==}

def Laws.checked_promote_reject_infinity():
  {==}

def Laws.checked_identity_negative_zero():
  {==}

def Laws.checked_identity_reject_subnormal():
  {==}

def Laws.checked_finite_subnormal():
  {==}

def Laws.words_negative_magnitude():
  {==}

def Laws.words_power_minimum():
  {==}

def Laws.words_power_reject_zero():
  {==}

def Laws.gradual_multiply_reject(ah, al, bh, bl):
  {==}

def Laws.gradual_multiply_zero_branch(sign, biased_sum, ah, al, bh, bl):
  {==}

def Laws.gradual_multiply_negative_zero():
  {==}

def Laws.gradual_multiply_negative_zero_pair():
  {==}

def Laws.gradual_multiply_invalid_first_with_zero():
  {==}

def Laws.gradual_multiply_invalid_second_with_zero():
  {==}

def Laws.gradual_multiply_half_minimum():
  {==}

def Laws.gradual_multiply_above_half():
  {==}

def Laws.gradual_multiply_odd_tie():
  {==}

def Laws.gradual_multiply_even_tie():
  {==}

def Laws.gradual_multiply_minimum_normal_tie():
  {==}

def Laws.gradual_multiply_already_normal():
  {==}

def Laws.gradual_multiply_k107_zero():
  {==}

def Laws.gradual_multiply_k192_negative_zero():
  {==}

def Laws.gradual_multiply_once_rounded_subnormal():
  {==}

def Laws.gradual_multiply_once_rounded_minimum_normal_edge():
  {==}

def Laws.gradual_multiply_once_rounded_half_minimum_edge():
  {==}

def Laws.gradual_multiply_normal_carry():
  {==}

def Laws.gradual_multiply_internal_k106_half_window():
  {==}

def Laws.gradual_multiply_internal_minimum_normal_half_window():
  {==}
