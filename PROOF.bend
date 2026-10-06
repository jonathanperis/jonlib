import Base
import ./src/modern_angle.bend as MA
import ./LAWS.bend as Laws
import ./jonlib.bend as J
import ./jonmath.bend as M

def Laws.clear_dimensions(width, height, format, pixels, color):
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

def Laws.modern_angle_reject_before_arithmetic(y, x):
  {==}

def Laws.modern_angle_add_failure(id, words, other):
  match other:
    case MA.Good{w}: {==}
    case MA.Failed{op, args}: {==}

def Laws.modern_angle_multiply_failure(id, words, other):
  match other:
    case MA.Good{w}: {==}
    case MA.Failed{op, args}: {==}

def Laws.modern_angle_fma_failure(id, words, b, c):
  match b c:
    case MA.Good{bw} MA.Good{cw}: {==}
    case MA.Good{bw} MA.Failed{op,args}: {==}
    case MA.Failed{op,args} MA.Good{cw}: {==}
    case MA.Failed{op,args} MA.Failed{op2,args2}: {==}

def Laws.modern_angle_failed_narrow(id, words):
  {==}

def Laws.modern_angle_reject_infinite_y():
  {==}

def Laws.modern_angle_reject_nan_x():
  {==}

def Laws.modern_angle_zero_positive_axis():
  {==}

def Laws.modern_angle_negative_zero_positive_axis():
  {==}

def Laws.modern_angle_positive_zeros():
  {==}

def Laws.modern_angle_negative_y_zero_x():
  {==}

def Laws.modern_angle_positive_y_negative_zero_x():
  {==}

def Laws.modern_angle_negative_zeros():
  {==}

def Laws.checked_angle_scalar_none():
  {==}

def Laws.checked_angle_normal_reject(stage, value):
  {==}

def Laws.checked_angle_sqrt_reject(value):
  {==}

def Laws.checked_angle_maybe_failure(stage):
  {==}

def Laws.checked_angle_vector2_input_reject(profile, x, y, u, v):
  {==}

def Laws.checked_angle_line_input_reject(profile, x, y, u, v):
  {==}

def Laws.checked_angle_vector3_input_reject(profile, x, y, z, u, v, w):
  {==}

def Laws.checked_angle_scalar_some(word):
  {==}

def Laws.bmp_padding_zero(bytes):
  {==}

def Laws.bmp_padding_successor(count, bytes):
  {==}

def Laws.bmp_nonterminal_row(padding, bytes):
  {==}

def Laws.bmp_terminal_row(padding, bytes):
  {==}

def Laws.export_gray_channels():
  {==}

def Laws.export_gray_alpha_channels():
  {==}

def Laws.export_rgb_channels():
  {==}

def Laws.export_rgba_channels():
  {==}

def Laws.tga_values_zero(channels, colors, bytes):
  match colors:
    case Nil{}: {==}
    case Con{_, _}: {==}

def Laws.tga_row_zero(channels, colors, bytes):
  match colors:
    case Nil{}: {==}
    case Con{_, _}: {==}

def Laws.raster_file_limit():
  {==}

def Laws.qoi_file_limit():
  {==}

def Laws.image_file_complete_empty():
  {==}

def Laws.image_file_complete_exact():
  {==}

def Laws.image_file_complete_short():
  {==}

def Laws.image_file_complete_long():
  {==}

def Laws.qoi_export_rgb_channels():
  {==}

def Laws.qoi_export_rgba_channels():
  {==}

def Laws.qoi_export_gray_rejected():
  {==}

def Laws.qoi_export_gray_alpha_rejected():
  {==}

def Laws.qoi_export_rgb565_rejected():
  {==}

def Laws.qoi_export_rgb5a1_rejected():
  {==}

def Laws.qoi_export_rgba4_rejected():
  {==}

def Laws.qoi_export_r32_rejected():
  {==}

def Laws.qoi_export_rgb_packing():
  {==}

def Laws.qoi_export_rgba_packing():
  {==}

def Laws.qoi_export_packing_empty(index, format, pixels):
  {==}

def Laws.qoi_surface_encoder_preserved(width, height, pixels):
  {==}

def Laws.tga_native_gray8():
  {==}

def Laws.tga_native_packed15():
  {==}

def Laws.tga_native_packed16():
  {==}

def Laws.tga_native_grayalpha16():
  {==}

def Laws.tga_native_rgb24():
  {==}

def Laws.tga_native_rgba32():
  {==}

def Laws.bmp_native_absent_alpha():
  {==}

def Laws.bmp_native_alpha_field(mask, shift, multiplier, shrink):
  {==}

def Laws.bmp_native_layout_alpha(red, green, blue, alpha):
  {==}

def Laws.png_native_gray():
  {==}

def Laws.png_native_gray_key(key):
  {==}

def Laws.png_native_grayalpha():
  {==}

def Laws.png_native_rgb():
  {==}

def Laws.png_native_rgb_key(key):
  {==}

def Laws.png_native_palette():
  {==}

def Laws.png_native_palette_trns():
  {==}

def Laws.png_native_rgba():
  {==}

def Laws.png_palette_trns_sticky_plte(cfg, key, compressed, seen, raw, bytes):
  {==}

def Laws.pic_native_mask_empty(mask):
  {==}

def Laws.pic_native_mask_union():
  {==}

def Laws.pic_native_rgb():
  {==}

def Laws.pic_native_alpha_first():
  {==}

def Laws.pic_native_alpha_middle():
  {==}

def Laws.pic_native_low_bits():
  {==}

def Laws.pic_native_alpha_low_bits():
  {==}

def Laws.codec_native_format_1():
  {==}

def Laws.codec_native_format_2():
  {==}

def Laws.codec_native_format_3():
  {==}

def Laws.codec_native_format_4():
  {==}

def Laws.codec_native_word_1_2155905279():
  {==}

def Laws.codec_native_word_2_2172748032():
  {==}

def Laws.codec_native_word_2_305419896():
  {==}

def Laws.codec_native_word_3_305419896():
  {==}

def Laws.codec_native_word_3_305420031():
  {==}

def Laws.codec_native_pixels_zero(index, channels, pixels):
  {==}

def Laws.codec_native_rgba_is_canonical(width, height, pixels):
  {==}
