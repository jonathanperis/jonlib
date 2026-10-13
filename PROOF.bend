import Base
import ./src/modern_angle.bend as MA
import ./LAWS.bend as Laws
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./jongui.bend as JG

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

def Laws.png_file_limit():
  {==}

def Laws.png_file_kind_by_name():
  {==}

def Laws.png_file_kind_other_case_unsupported():
  {==}

def Laws.png_signature_selects_the_decoder():
  {==}

def Laws.file_bytes_beyond_a_count():
  {==}

def Laws.png_named_other_contents_over_the_raster_cap_refused(reference, bytes):
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

def Laws.surface_format_zero_keeps_owner(width, height, format, pixels):
  {==}

def Laws.surface_draw_word_rgba_is_color(color):
  {==}

def Laws.surface_fill_word_r32_is_zero(color):
  {==}

def Laws.ray_box_undefined_is_none(arithmetic, inside, hit, distance, point, normal):
  {==}

def Laws.ray_triangle_parallel_misses(arithmetic, ray, p1, edge1, edge2, p, det):
  {==}

def Laws.ray_quad_keeps_first_hit(arithmetic, ray, p2, p3, p4, distance, point, normal):
  {==}

def Laws.stored_copy_keeps_every_level(width, height, format, mipmaps, data):
  {==}

def Laws.stored_compressed_levels_unsupported(image, width, height, format, count, data):
  {==}

def Laws.jpeg_absent_table_symbol_zero(buffer):
  {==}

def Laws.jpeg_zig_past_end():
  {==}

def Laws.jpeg_short_wraps():
  {==}

def Laws.jpeg_asr_negative():
  {==}

def Laws.wave_copy_twice(wave):
  {==}

def Laws.qoa_encode_no_frames(samples, channels, rate):
  {==}

def Laws.acos_apple_none(x):
  {==}

def Laws.pow_apple_none(x, exponent):
  {==}

def Laws.asin_region_one():
  {==}

def Laws.asin_region_above_one():
  {==}

def Laws.asin_region_tiny():
  {==}

def Laws.glibc_asin_region_one():
  {==}

def Laws.glibc_asin_region_above_one():
  {==}

def Laws.glibc_asin_region_tiny():
  {==}

def Laws.glibc_asin_region_small():
  {==}

def Laws.glibc_asin_region_near_one():
  {==}

def Laws.glibc_asin_region_middle():
  {==}

def Laws.sqrt_four():
  {==}

def Laws.sqrt_negative_zero():
  {==}

def Laws.sqrt_negative_none():
  {==}

def Laws.euler_invalid_first(libm, x, y, z, w):
  {==}

def Laws.fma_kind_nan_factor():
  {==}

def Laws.fma_kind_zero_factor():
  {==}

def Laws.fma_kind_infinite_addend():
  {==}

def Laws.fma_kind_zero_addend():
  {==}

def Laws.fma_product_largest_significands():
  {==}

def Laws.fma_round_odd_tie_up():
  {==}

def Laws.fma_round_even_tie_kept():
  {==}

def Laws.libm_tan_apple_none(x):
  {==}

def Laws.camera_projection_matrix_apple(camera, aspect):
  {==}

def Laws.glibc_sinf_negative_zero():
  {==}

def Laws.glibc_cosf_negative_zero():
  {==}

def Laws.glibc_sinf_infinity_none():
  {==}

def Laws.float64_to_int_truncates_toward_zero():
  {==}

def Laws.float64_to_int_2_31_none():
  {==}

def Laws.float64_to_int_infinity_none(low):
  {==}

def Laws.float64_to_f32_infinity_none():
  {==}

def Laws.glibc_pow2_126_none():
  {==}

def Laws.glibc_pow2_infinity_none():
  {==}

def Laws.glibc_powf_zero_to_a_positive_power():
  {==}

def Laws.glibc_powf_zero_to_a_negative_power_none():
  {==}

def Laws.glibc_powf_to_zero_is_one():
  {==}

def Laws.glibc_powf_infinity_to_minus_zero_is_one():
  {==}

def Laws.glibc_powf_nan_to_zero_none():
  {==}

def Laws.glibc_powf_positive_base():
  {==}

def Laws.glibc_powf_subnormal_base():
  {==}

def Laws.glibc_powf_negative_base_none():
  {==}

def Laws.glibc_powf_minus_zero_base_none():
  {==}

def Laws.glibc_powf_infinite_base_none():
  {==}

def Laws.glibc_powf_subnormal_exponent_none():
  {==}

def Laws.glibc_powf_infinite_exponent_none():
  {==}

def Laws.glibc_powf_underflow_from_minus_150():
  {==}

def Laws.glibc_powf_subnormal_result_above_minus_150():
  {==}

def Laws.glibc_powf_top_none():
  {==}

def Laws.glibc_powf_below_the_top():
  {==}

def Laws.glibc_powf_small_products_inside():
  {==}

def Laws.glibc_expf_87_none():
  {==}

def Laws.glibc_expf_variant_argument_none():
  {==}

def Laws.glibc_expf_other_variant_argument_none():
  {==}

def Laws.glibc_logf_answers_the_smallest_subnormal():
  {==}

def Laws.glibc_logf_answers_the_largest_subnormal():
  {==}

def Laws.glibc_logf_answers_the_largest_float():
  {==}

def Laws.glibc_logf_domain_without_zero():
  {==}

def Laws.glibc_logf_domain_without_infinity():
  {==}

def Laws.glibc_logf_domain_without_negatives():
  {==}

def Laws.glibc_logf_smallest_subnormal_scaled():
  {==}

def Laws.glibc_logf_half_the_smallest_normal_scaled():
  {==}

def Laws.glibc_logf_largest_subnormal_scaled():
  {==}

def Laws.glibc_logf_normal_word_kept():
  {==}

def Laws.glibc_logf_zero_none():
  {==}

def Laws.glibc_logf_negative_none():
  {==}

def Laws.glibc_logf_infinity_none():
  {==}

def Laws.glibc_rand_minimal_standard_step():
  {==}

def Laws.glibc_rand_first_value():
  {==}

def Laws.glibc_rand_seed_zero_is_one():
  {==}

def Laws.glibc_rand_large_seed_none():
  {==}

def Laws.libc_rand_apple_none(seed):
  {==}

def Laws.glibc_sin_of_zero():
  {==}

def Laws.glibc_sin_of_negative_zero():
  {==}

def Laws.glibc_cos_of_zero():
  {==}

def Laws.glibc_sin_of_infinity_refused():
  {==}

def Laws.glibc_cos_of_nan_refused(low):
  {==}

def Laws.glibc_sin_quadrant_of_minus_three():
  {==}

def Laws.glibc_sin_quadrant_past_int_refused(low):
  {==}

def Laws.float64_one_plus_one():
  {==}

def Laws.float64_three_minus_one():
  {==}

def Laws.float64_zero_by_three():
  {==}

def Laws.float64_divide_by_zero_refused():
  {==}

def Laws.float64_add_infinity_refused():
  {==}

def Laws.glibc_sin64_apple_refused(value):
  {==}

def Laws.glibc_cos64_glibc241_refused(value):
  {==}

def Laws.glibc_tanf_infinity_none():
  {==}

def Laws.glibc_tanf_nan_none():
  {==}

def Laws.glibc241_tanf_none(x):
  {==}

def Laws.apple_tanf_none(x):
  {==}

def Laws.strtod_one():
  {==}

def Laws.strtod_tenth():
  {==}

def Laws.strtod_tie_to_even():
  {==}

def Laws.strtod_tie_to_even_up():
  {==}

def Laws.strtod_exponent():
  {==}

def Laws.strtod_negative_zero():
  {==}

def Laws.strtod_twenty_digits_none():
  {==}

def Laws.strtod_plus_none():
  {==}

def Laws.strtod_empty_exponent_none():
  {==}

def Laws.json_empty_array():
  {==}

def Laws.json_number_kept_as_written():
  {==}

def Laws.json_object_member():
  {==}

def Laws.json_trailing_comma_none():
  {==}

def Laws.json_two_values_none():
  {==}

def Laws.json_unterminated_string_none():
  {==}

def Laws.json_colon_in_array_none():
  {==}

def Laws.gltf_integer_digits():
  {==}

def Laws.gltf_negative_integer_bad():
  {==}

def Laws.gltf_attribute_index():
  {==}

def Laws.gltf_empty_file_none():
  {==}

def Laws.gltf_joints_attribute_kind():
  {==}

def Laws.gltf_index_past_array_refused():
  {==}

def Laws.gltf_other_texture_kind_refused():
  {==}

def Laws.gltf_base_color_image_kept():
  {==}

def Laws.vox_extension_routed(iqm, m3d, other):
  {==}

def Laws.vox_size_padded():
  {==}

def Laws.vox_size_of_chunks_kept():
  {==}

def Laws.vox_chunk_names():
  {==}

def Laws.vox_voxel_cell():
  {==}

def Laws.vox_voxel_outside_fails():
  {==}

def Laws.vox_voxel_cut_short_fails():
  {==}

def Laws.vox_quad_indices():
  {==}

def Laws.vox_mesh_vertex_counts():
  {==}

def Laws.vox_empty_file_foreign():
  {==}

def Laws.vox_other_magic_foreign():
  {==}

def Laws.vox_other_version_foreign():
  {==}

def Laws.vox_magic_cut_short_unread():
  {==}

def Laws.vox_version_cut_short_unread():
  {==}

def Laws.vox_chunk_header_cut_short_unread():
  {==}

def Laws.vox_without_voxels_unread():
  {==}

def Laws.vox_four_bytes_left_halt(read):
  {==}

def Laws.vox_chunk_past_the_end_ends():
  {==}

def Laws.iqm_extension_routed(m3d, other):
  {==}

def Laws.iqm_skeleton_and_animations_routed(m3d):
  {==}

def Laws.iqm_empty_file_foreign():
  {==}

def Laws.iqm_empty_file_no_animations():
  {==}

def Laws.iqm_magic_cut_short_unread():
  {==}

def Laws.iqm_array_inside():
  {==}

def Laws.iqm_empty_array_past_the_end_outside():
  {==}

def Laws.iqm_triangle_reversed_and_rebased():
  {==}

def Laws.iqm_corner_below_first_vertex_wraps():
  {==}

def Laws.iqm_name_before_its_nul():
  {==}

def Laws.iqm_name_without_nul_refused():
  {==}

def Laws.iqm_material_must_name_a_file():
  {==}

def Laws.iqm_pose_parents():
  {==}

def Laws.m3d_extension_routed(other):
  {==}

def Laws.m3d_skeleton_and_animations_routed():
  {==}

def Laws.m3d_index_sizes():
  {==}

def Laws.m3d_index_one_byte_signed_at_the_top():
  {==}

def Laws.m3d_index_one_byte_plain():
  {==}

def Laws.m3d_index_two_bytes_signed_at_the_top():
  {==}

def Laws.m3d_index_cut_short():
  {==}

def Laws.m3d_index_absent_keeps_its_value():
  {==}

def Laws.m3d_record_kinds():
  {==}

def Laws.m3d_property_formats():
  {==}

def Laws.m3d_color_bytes():
  {==}

def Laws.m3d_empty_file_no_model():
  {==}

def Laws.m3d_empty_file_no_animations():
  {==}

def Laws.m3d_magic_cut_short_refused():
  {==}

def Laws.m3d_other_magic_no_model():
  {==}

def Laws.gltf_anim_joint_place():
  {==}

def Laws.gltf_anim_node_outside_skeleton():
  {==}

def Laws.gltf_anim_no_key_pair_reads_first(time):
  {==}

def Laws.gltf_anim_empty_file_no_skeleton():
  {==}

def Laws.gltf_anim_empty_file_no_animations(libm):
  {==}

def Laws.gltf_anim_window_starts_at_byte():
  {==}

def Laws.gltf_anim_empty_span_needs_nothing(step, comps, limit):
  {==}

def Laws.gltf_anim_invalid_span_reads_nothing(span, blocks, comps, limit):
  {==}

def Laws.par_shapes_disk_is_a_fan():
  {==}

def Laws.par_shapes_merge_offsets_triangles():
  {==}

def Laws.mesh_cylinder_of_two_slices_is_empty(arithmetic, libm, radius, height):
  {==}

def Laws.mesh_cone_fused_refused(radius, height):
  {==}

def Laws.mesh_knot_of_two_sides_is_empty(arithmetic, libm, radius, size, rad_seg):
  {==}

def Laws.mesh_knot_fused_refused(radius, size):
  {==}

def Laws.gltf_anim_no_joints_no_rest(nodes):
  {==}

def Laws.gltf_anim_unreadable_bone_ends_pose(base, tracks, time, libm, rest):
  {==}

def Laws.model_pose_loaded_is_zeroed_with_identities(name, parent, binds):
  {==}

def Laws.model_pose_boneless_unchanged(libm, binds, name, bones, count, poses, frame, pose):
  {==}

def Laws.model_pose_no_keyframes_unchanged(libm, bone, parent, binds, name, bones, poses, frame, pose):
  {==}

def Laws.model_pose_undefined_call_answers_nothing(libm, binds, poses, count, frame, pose):
  {==}

def Laws.model_pose_blend_boneless_unchanged(libm, binds, name, bones, count, poses, first, second, blend, pose):
  {==}

def Laws.model_pose_blend_no_keyframes_unchanged(libm, bone, parent, binds, name, bones, count, poses, first, second, blend, pose):
  {==}

def Laws.model_pose_blend_frame_outside_int_refused(frame, count):
  {==}

def Laws.model_animation_valid_same_bone_count(bone, parent, binds, name, count, poses):
  {==}

def Laws.model_animation_invalid_other_bone_count(bone, parent, binds, name, count, poses):
  {==}

def Laws.hypot_within_below_inside(error, limit):
  {==}

def Laws.hypot_within_exact_inside(limit):
  {==}

def Laws.hypot_within_rounded_down_onto_none(limit):
  {==}

def Laws.hypot_within_band_none(error):
  {==}

def Laws.hypot_within_past_band_outside(error):
  {==}

def Laws.hypot_within_unknown_order_none(error, limit):
  {==}

def Laws.hypot_within_negative_radius_outside(xh, xl, yh, yl, rh, rl):
  {==}

def Laws.hypot_within_nan_none():
  {==}

def Laws.hypot_within_infinities_none():
  {==}

def Laws.replay_closing_stops(update, draw, show, spec, core, frame, out):
  {==}

def Laws.replay_until_uses_its_condition(update, draw, show, spec, core, frame, out):
  {==}

def Laws.replay_effects_needs_io(update, draw, after, show, spec, core, frame, out):
  {==}

def Laws.replay_io_closing_stops(update, draw, after, show, spec, core, frame, out):
  {==}

def Laws.replay_io_no_after_once_stopped(after, out):
  {==}

def Laws.desktop_effects_no_after_before_the_first_frame(render, present, wait, mark):
  {==}

def Laws.desktop_effects_after_once_a_frame_was_presented(render, present, wait, mark):
  {==}

def Laws.desktop_clock_args_default():
  {==}

def Laws.desktop_clock_args_frames_flag():
  {==}

def Laws.desktop_clock_args_time_flag():
  {==}

def Laws.desktop_clock_args_other_argument():
  {==}

def Laws.desktop_clock_args_end_of_arguments(frames, time):
  {==}

def Laws.desktop_clock_args_reads_both():
  {==}

def Laws.desktop_clock_args_last_time_counts():
  {==}

def Laws.gui_default_text_size():
  {==}

def Laws.gui_default_button_border():
  {==}

def Laws.gui_default_property_propagates():
  {==}

def Laws.gui_extended_property_stays():
  {==}

def Laws.gui_disable_then_enable(gui):
  JG.Gui{state, locked, alpha, exclusive, rec, style, scale} = gui
  {==}

def Laws.gui_disable_keeps_focus(gui):
  JG.Gui{state, locked, alpha, exclusive, rec, style, scale} = gui
  {==}

def Laws.gui_line_color_property():
  {==}

def Laws.gui_line_color_focused_property():
  {==}

def Laws.gui_line_color_disabled_property():
  {==}

def Laws.gui_icon_prefix():
  {==}

def Laws.gui_icon_empty_id():
  {==}

def Laws.gui_icon_unclosed_is_text():
  {==}

def Laws.gui_icon_four_digits_is_text():
  {==}

def Laws.gui_icon_last_of_table_drawn():
  {==}

def Laws.gui_icon_beyond_table_refused():
  {==}

def Laws.gui_hash_before_another_line_refused():
  {==}

def Laws.gui_hash_on_last_line_drawn():
  {==}

def Laws.gui_width_second_hash_at_four():
  {==}

def Laws.gui_width_second_hash_beyond():
  {==}

def Laws.gui_icon_past_table_is_empty():
  {==}

def Laws.gui_icon_arrow_left_word():
  {==}

def Laws.gui_int_minus_one_below_zero():
  {==}

def Laws.gui_int_zero_not_below_minus_one():
  {==}

def Laws.gui_int_clamp_above():
  {==}

def Laws.gui_int_clamp_below_negative_min():
  {==}

def Laws.gui_int_clamp_inside():
  {==}

def Laws.gui_value_box_blank_when_normal(gui):
  {==}

def Laws.gui_value_box_blank_when_focused(gui):
  {==}

def Laws.gui_dropdown_two_items():
  {==}

def Laws.gui_dropdown_empty_text_is_one_item():
  {==}

def Laws.gui_dropdown_second_item():
  {==}

def Laws.gui_dropdown_focus_without_items(mouse, x, y, w, h, pitch, up):
  {==}

def Laws.gui_text_box_insert_at_cursor():
  {==}

def Laws.gui_text_box_remove_at_cursor():
  {==}

def Laws.gui_text_box_backspace_whole_codepoint():
  {==}

def Laws.gui_text_box_nothing_before_start():
  {==}

def Laws.gui_text_box_paste_fits_size():
  {==}

def Laws.gui_text_box_paste_stops_at_control():
  {==}

def Laws.gui_text_box_globals_start_at_zero():
  {==}

def Laws.gui_text_box_blank_when_normal(gui):
  {==}

def Laws.gui_icon_scale_starts_at_one():
  {==}

def Laws.gui_icon_scale_set(gui):
  JG.Gui{state, locked, alpha, exclusive, rec, style, scale} = gui
  {==}

def Laws.gui_icon_scale_zero_ignored(gui):
  JG.Gui{state, locked, alpha, exclusive, rec, style, scale} = gui
  {==}

def Laws.gui_icon_scale_negative_ignored(gui):
  JG.Gui{state, locked, alpha, exclusive, rec, style, scale} = gui
  {==}

def Laws.gui_scroll_clamp_above():
  {==}

def Laws.gui_scroll_clamp_below_zero():
  {==}

def Laws.gui_scroll_clamp_crossed_bounds():
  {==}

def Laws.gui_scroll_slider_at_least_one():
  {==}

def Laws.gui_scroll_step_truncates():
  {==}

def Laws.gui_scroll_step_negative_speed():
  {==}

def Laws.gui_progress_no_text_draws_nothing(gui, frame, right, bounds, state):
  {==}

def Laws.gui_progress_not_started_has_no_reached_border(frame, left, bottom, color):
  {==}

def Laws.gui_progress_full_has_no_unreached_border(frame, bottom, right, color):
  {==}

def Laws.shader_load_never_valid(vs, fs):
  {==}

def Laws.shader_location_unset(shader, name):
  {==}

def Laws.camera_perspective_projection_none(position, target, up, fovy, aspect):
  {==}

def Laws.camera_apple_zero_argument_only(angle, argument):
  {==}

def Laws.wav_aiff_rate_44100():
  {==}

def Laws.wav_aiff_rate_int64_min_undefined():
  {==}

def Laws.msadpcm_adapt_saturates():
  {==}

def Laws.msadpcm_adapt_negative_floor():
  {==}

def Laws.wave_format_expected_frames():
  {==}

def Laws.wave_format_aux_position():
  {==}

def Laws.wave_format_none_position():
  {==}

def Laws.wave_format_mono_unsigned_division():
  {==}

def Laws.wave_format_filter_overflow():
  {==}

def Laws.wave_format_rate_double():
  {==}

def Laws.wave_format_size_refused():
  {==}

def Laws.wave_format_frames_in_order():
  {==}

def Laws.wave_format_frames_flattened_in_order():
  {==}

def Laws.wave_format_samples_in_order():
  {==}

def Laws.wave_format_nan_anywhere():
  {==}

def Laws.audio_starts_unready():
  {==}

def Laws.audio_init_full_volume():
  {==}

def Laws.audio_init_ready_unchanged(master, next, buffers, blocks):
  {==}

def Laws.audio_close_keeps_buffers(master, next, buffers, blocks):
  {==}

def Laws.audio_master_volume_starts_at_zero():
  {==}

def Laws.audio_master_volume_full_when_open():
  {==}

def Laws.sound_from_device_format_wave():
  {==}

def Laws.sound_unready_device_refused():
  {==}

def Laws.sound_zero_wave_is_zero_sound():
  {==}

def Laws.sound_without_frames_has_empty_buffer():
  {==}

def Laws.sound_refused_wave_tracks_nothing():
  {==}

def Laws.sound_zero_invalid():
  {==}

def Laws.sound_without_frames_invalid():
  {==}

def Laws.sound_with_frames_valid():
  {==}

def Laws.sound_alias_shares_block():
  {==}

def Laws.sound_alias_of_zero_sound():
  {==}

def Laws.sound_play_only_its_buffer():
  {==}

def Laws.sound_played_is_playing():
  {==}

def Laws.sound_paused_not_playing():
  {==}

def Laws.sound_stop_leaves_paused():
  {==}

def Laws.sound_stop_after_play():
  {==}

def Laws.sound_volume_only_its_buffer():
  {==}

def Laws.sound_unload_frees_block():
  {==}

def Laws.sound_unload_alias_keeps_block():
  {==}

def Laws.sound_update_reaches_aliases():
  {==}

def Laws.sound_update_past_buffer_ignored():
  {==}

def Laws.sound_unready_buffers_untouched():
  {==}

def Laws.sound_unloaded_handle_ignored():
  {==}

def Laws.sound_play_from_the_start():
  {==}

def Laws.sound_stop_back_to_the_start():
  {==}

def Laws.sound_stop_paused_keeps_its_place():
  {==}

def Laws.audio_read_within():
  {==}

def Laws.audio_read_to_the_end():
  {==}

def Laws.audio_read_ends_at_the_end():
  {==}

def Laws.audio_read_goes_on_before_the_end():
  {==}

def Laws.audio_read_stopped_buffer():
  {==}

def Laws.audio_read_odd_last_frame_lost():
  {==}

def Laws.audio_read_odd_last_frame_not_an_end():
  {==}

def Laws.audio_read_odd_whole():
  {==}

def Laws.audio_read_even_last_frame():
  {==}

def Laws.audio_read_one_frame():
  {==}

def Laws.audio_stream_read_to_the_end_of_the_half():
  {==}

def Laws.audio_stream_read_goes_on_in_the_other_half():
  {==}

def Laws.audio_stream_read_wraps_from_the_second_half():
  {==}

def Laws.audio_stream_read_processed_half_gives_nothing():
  {==}

def Laws.audio_stream_read_stops_at_a_processed_half():
  {==}

def Laws.audio_stream_read_within_the_half():
  {==}

def Laws.audio_read_cap_of_a_sound():
  {==}

def Laws.audio_read_cap_of_a_16_bit_mono_stream():
  {==}

def Laws.audio_read_cap_of_a_wide_stream():
  {==}

def Laws.audio_required_input_carries_fractions():
  {==}

def Laws.audio_rate_change_keeps_the_fraction():
  {==}

def Laws.audio_rate_change_carries_whole_frames():
  {==}

def Laws.audio_rate_unchanged_at_the_device_rate():
  {==}

def Laws.audio_first_order_series_at_zero():
  {==}

def Laws.audio_mix_subnormal_is_zero():
  {==}

def Laws.audio_mix_nan_refused():
  {==}

def Laws.audio_mix_smallest_normal_kept():
  {==}

def Laws.audio_mix_infinity_itself_fine():
  {==}

def Laws.audio_mix_negative_subnormal_is_negative_zero():
  {==}

def Laws.audio_mix_unready_refused():
  {==}

def Laws.audio_mix_no_frames_refused():
  {==}

def Laws.music_none_invalid():
  {==}

def Laws.music_valid_without_buffer():
  {==}

def Laws.music_stop_rewinds():
  {==}

def Laws.music_seek_within():
  {==}

def Laws.music_seek_stops_at_the_end():
  {==}

def Laws.music_read_goes_round():
  {==}

def Laws.music_read_within():
  {==}

def Laws.music_played_negative_wraps():
  {==}

def Laws.music_played_whole_turns():
  {==}

def Laws.music_played_negative_whole_turn():
  {==}

def Laws.music_buffered_no_more_than_the_music():
  {==}

def Laws.music_buffered_looping():
  {==}

def Laws.music_buffered_one_half():
  {==}

def Laws.music_qoa_declared_frames():
  {==}

def Laws.music_qoa_seek_to_its_frame():
  {==}

def Laws.music_qoa_seek_last_frame():
  {==}

def Laws.music_qoa_seek_gives_its_frame():
  {==}

def Laws.music_wav_seek_gives_the_position():
  {==}

def Laws.music_qoa_stop_rewinds():
  {==}

def Laws.qoa_frame_samples_gathered():
  {==}

def Laws.music_float_bits_as_they_are():
  {==}

def Laws.music_float_bits_big_endian():
  {==}

def Laws.mp3_header_valid():
  {==}

def Laws.mp3_header_bit_rate():
  {==}

def Laws.mp3_header_sample_rate():
  {==}

def Laws.mp3_header_samples():
  {==}

def Laws.mp3_header_frame_bytes():
  {==}

def Laws.mp3_header_padding_byte():
  {==}

def Laws.mp3_header_free_format_size():
  {==}

def Laws.mp3_header_mpeg2_rate():
  {==}

def Laws.mp3_header_mpeg2_samples():
  {==}

def Laws.mp3_header_layer1_samples():
  {==}

def Laws.mp3_header_reserved_layer():
  {==}

def Laws.mp3_header_reserved_sample_rate():
  {==}

def Laws.mp3_header_reserved_bit_rate():
  {==}

def Laws.mp3_header_same_stream_with_padding():
  {==}

def Laws.mp3_header_other_sample_rate_other_stream():
  {==}

def Laws.mp3_bits_by_position():
  {==}

def Laws.mp3_bits_past_the_limit():
  {==}

def Laws.mp3_word_first_byte_highest():
  {==}

def Laws.mp3_id3v2_size():
  {==}

def Laws.mp3_id3v2_footer():
  {==}

def Laws.mp3_no_id3v2():
  {==}

def Laws.mp3_info_every_field():
  {==}

def Laws.mp3_info_no_field():
  {==}

def Laws.mp3_total_less_delay_and_padding():
  {==}

def Laws.mp3_total_delay_too_large_ignored():
  {==}

def Laws.mp3_read_clamped_to_the_stream():
  {==}

def Laws.mp3_read_clamped_to_the_file():
  {==}

def Laws.mp3_short_file_does_not_open():
  {==}

def Laws.mp3_long_bands_of_44100():
  {==}

def Laws.mp3_short_bands_of_44100():
  {==}

def Laws.mp3_mixed_bands_begin_long():
  {==}

def Laws.mp3_codebooks_share_a_table():
  {==}

def Laws.mp3_codebook_without_values():
  {==}

def Laws.mp3_codebook_entries():
  {==}

def Laws.mp3_scalefactor_sizes_mpeg1():
  {==}

def Laws.mp3_scalefactor_sizes_mpeg2():
  {==}

def Laws.mp3_scalefactor_sizes_mpeg2_second_row():
  {==}

def Laws.mp3_scalefactor_sizes_intensity_halved():
  {==}

def Laws.mp3_scalefactors_read_in_groups():
  {==}

def Laws.mp3_scalefactors_kept_by_scfsi():
  {==}

def Laws.mp3_intensity_position_of_all_ones_mpeg2():
  {==}

def Laws.mp3_cache_filled_by_bytes():
  {==}

def Laws.mp3_cache_past_the_bytes_counts():
  {==}

def Laws.mp3_quad_signs():
  {==}

def Laws.mp3_quad_value_absent():
  {==}

def Laws.mp3_count1_quad():
  {==}

def Laws.mp3_granule_576_values():
  {==}

def Laws.mp3_values_read_inside_the_array():
  {==}

def Laws.mp3_values_read_past_the_array_refused():
  {==}

def Laws.mp3_top_bands_by_window():
  {==}

def Laws.mp3_intensity_position_default():
  {==}

def Laws.mp3_intensity_position_of_the_band_before():
  {==}

def Laws.mp3_intensity_positions_of_the_windows():
  {==}

def Laws.mp3_array_keeps_what_was_there():
  {==}

def Laws.mp3_reservoir_short_decodes_nothing():
  {==}

def Laws.mp3_reservoir_reached_decodes():
  {==}

def Laws.mp3_side_information_refused():
  {==}

def Laws.mp3_no_frame_in_no_bytes():
  {==}

def Laws.mp3_mixed_block_reordered_inside_the_granule():
  {==}

def Laws.mp3_mixed_block_at_8000_hz_refused():
  {==}

def Laws.mp3_short_block_at_8000_hz_inside():
  {==}

def Laws.mp3_top_bands_shared_with_long_bands():
  {==}

def Laws.mp3_top_bands_of_short_blocks_apart():
  {==}

def Laws.mp3_stereo_step_intensity():
  {==}

def Laws.mp3_stereo_step_intensity_in_a_mono_frame():
  {==}

def Laws.mp3_stereo_step_midside():
  {==}

def Laws.mp3_stereo_step_midside_only_in_joint_stereo():
  {==}

def Laws.mp3_stereo_step_none():
  {==}

def Laws.mp3_stereo_values_kept():
  {==}

def Laws.mp3_intensity_position_7_is_no_intensity_band():
  {==}

def Laws.mp3_band_below_the_top_band_is_no_intensity_band():
  {==}

def Laws.mp3_second_slot_compress_written():
  {==}

def Laws.mp3_second_slot_compress_left_by_too_many_big_values():
  {==}

def Laws.mp3_second_slot_compress_left_by_a_mono_frame():
  {==}

def Laws.mp3_long_subbands_of_a_mixed_block():
  {==}

def Laws.mp3_long_subbands_at_8000_hz():
  {==}

def Laws.mp3_no_long_subbands_without_the_mixed_flag():
  {==}

def Laws.mp3_values_moved_last_first():
  {==}

def Laws.mp3_short_windows_interleaved():
  {==}

def Laws.mp3_alias_reduction_between_all_long_subbands():
  {==}

def Laws.mp3_alias_reduction_inside_a_mixed_block_long_part():
  {==}

def Laws.mp3_no_alias_reduction_in_short_blocks():
  {==}

def Laws.mp3_no_boundary_no_alias_reduction():
  {==}

def Laws.mp3_mixed_block_long_part_transformed_long():
  {==}

def Laws.mp3_short_block_transformed_short():
  {==}

def Laws.mp3_stop_block_window():
  {==}

def Laws.mp3_start_block_long_window():
  {==}

def Laws.mp3_sign_change_in_odd_subbands():
  {==}

def Laws.mp3_no_sign_change_in_even_subbands():
  {==}

def Laws.mp3_mono_frame_keeps_the_right_overlap():
  {==}

def Laws.mp3_time_slot_takes_each_subband_next_sample():
  {==}

def Laws.mp3_subbands_of_eighteen_samples():
  {==}

def Laws.mp3_second_subband_begins_eighteen_later():
  {==}

def Laws.mp3_sum_rounded_to_nearest():
  {==}

def Laws.mp3_one_and_a_half_rounded_to_two():
  {==}

def Laws.mp3_sum_rounded_down():
  {==}

def Laws.mp3_tie_rounded_to_even_down():
  {==}

def Laws.mp3_tie_rounded_to_even_up():
  {==}

def Laws.mp3_half_rounded_to_zero():
  {==}

def Laws.mp3_float_power_of_one():
  {==}

def Laws.mp3_float_one_scaled_down():
  {==}

def Laws.mp3_float_power_of_a_subnormal():
  {==}

def Laws.mp3_float_subnormal_without_hidden_bit():
  {==}

def Laws.mp3_float_power_of_the_largest():
  {==}

def Laws.mp3_float_largest_scaled_up():
  {==}

def Laws.mp3_float_integer_significand_at_2_to_23():
  {==}

def Laws.mp3_float_sign_not_in_the_power():
  {==}

def Laws.mp3_float_significand():
  {==}

def Laws.mp3_float_integer_cut():
  {==}

def Laws.mp3_negative_sample_bits():
  {==}

def Laws.mp3_lowest_sample_bits():
  {==}

def Laws.mp3_row_groups_of_four():
  {==}

def Laws.mp3_row_completed_by_the_next_call():
  {==}

def Laws.mp3_mono_row_keeps_the_right_entries():
  {==}

def Laws.mp3_stereo_samples_left_then_right():
  {==}

def Laws.mp3_mono_samples_left_only():
  {==}

def Laws.mp3_samples_built_backwards():
  {==}

def Laws.mp3_calls_joined_in_order():
  {==}

def Laws.mp3_history_of_the_newest_rows():
  {==}

def Laws.mp3_delay_passed_before_a_read():
  {==}

def Laws.mp3_delay_longer_than_a_frame():
  {==}

def Laws.mp3_no_delay_left():
  {==}

def Laws.mp3_read_takes_what_the_frame_has():
  {==}

def Laws.mp3_read_takes_what_is_wanted():
  {==}

def Laws.mp3_read_ends_at_the_padding():
  {==}

def Laws.mp3_frame_written_over_the_samples_before():
  {==}

def Laws.mp3_samples_taken_from_the_frame():
  {==}

def Laws.mp3_samples_passed_by_a_seek():
  {==}

def Laws.mp3_seek_to_frame_0_is_the_start():
  {==}

def Laws.mp3_seek_to_the_count_stays():
  {==}

def Laws.mp3_seek_forward_reads_on():
  {==}

def Laws.mp3_seek_back_reads_from_the_start():
  {==}

def Laws.mp3_stream_of_a_short_file_does_not_open():
  {==}

def Laws.mp3_read_of_no_frame():
  {==}

def Laws.mp3_stopped_stream_gives_no_frame():
  {==}

def Laws.music_mp3_read_with_every_frame_is_over():
  {==}

def Laws.music_mp3_short_read_goes_back_to_the_start():
  {==}

def Laws.music_mp3_stream_without_frames_ends_the_read():
  {==}

def Laws.music_mp3_reads_joined_in_order():
  {==}

def Laws.music_mp3_is_a_loaded_context():
  {==}

def Laws.music_mp3_stream_channels():
  {==}

def Laws.music_mp3_stream_rate():
  {==}

def Laws.audio_clock_periods_owed():
  {==}

def Laws.audio_clock_no_period_twice():
  {==}

def Laws.audio_clock_earlier_time_owes_nothing():
  {==}

def Laws.audio_clock_before_opening_refused():
  {==}

def Laws.audio_clock_unknown_time_refused():
  {==}

def Laws.audio_clock_no_period_no_callback():
  {==}

def Laws.audio_clock_refused_callback_stops():
  {==}

def Laws.frame_init_window_zero_width(height):
  {==}

def Laws.frame_init_window_wide(height):
  {==}

def Laws.frame_plan_refused(commands):
  {==}

def Laws.input_queue_bounded():
  {==}

def Laws.input_key_repeat_set():
  {==}

def Laws.input_key_repeat_cleared():
  {==}

def Laws.input_poll_copies_low_keys():
  {==}

def Laws.input_poll_keeps_high_keys():
  {==}

def Laws.gesture_tap_becomes_hold():
  {==}

def Laws.gesture_swipe_ends():
  {==}

def Laws.desktop_poll_copies_all_keys():
  {==}

def Laws.desktop_poll_button_pressed_once():
  {==}

def Laws.desktop_button_pressed():
  {==}

def Laws.desktop_poll_wheel_reset():
  {==}

def Laws.desktop_screen_size(width, height):
  {==}

def Laws.desktop_key_letters():
  {==}

def Laws.desktop_key_escape():
  {==}

def Laws.desktop_key_arrows():
  {==}

def Laws.desktop_key_function():
  {==}

def Laws.desktop_key_shift():
  {==}

def Laws.desktop_key_shifted_symbol():
  {==}

def Laws.desktop_key_unknown():
  {==}

def Laws.frame_blend_mode_unchanged(frame, mode):
  {==}

def Laws.texture_set_wrap_unchanged(texture, wrap):
  {==}

def Laws.texture_filter_point(linear):
  {==}

def Laws.texture_pool_reuses_freed(next, capacity, id, rest):
  {==}

def Laws.font_index_invalid(glyphs, base, padding, cp):
  {==}

def Laws.font_measure_empty(face, size, spacing, line):
  {==}

def Laws.font_unload_default(frame, base, padding, glyphs, width, height, format, linear, alpha, texels, atlas):
  {==}

def Laws.surface_colors_image_is_rgba8(width, height, pixels):
  {==}

def Laws.surface_colors_image_failure_kept(failure):
  {==}

def Laws.font_texture_size_is_the_textures(base, padding, glyphs, id, width, height, format, linear, alpha, texels, atlas):
  {==}

def Laws.render_depth_unstashed(wanted):
  {==}

def Laws.render_depth_starts_zeroed(count):
  {==}

def Laws.render_depth_kept_between_modes(depth):
  {==}

def Laws.render_depth_other_framebuffer_stays(depth):
  {==}

def Laws.render_depth_reused(depth, count):
  {==}

def Laws.rlgl_blend_mode_unchanged(frame, mode):
  {==}

def Laws.rlgl_set_uniform_unchanged(frame, location, value, kind):
  {==}

def Laws.rlgl_set_uniform_matrix_unchanged(frame, location, matrix):
  {==}

def Laws.rlgl_set_uniform_matrices_unchanged(frame, location, matrices):
  {==}

def Laws.rlgl_set_uniform_sampler_unchanged(frame, location, texture):
  {==}

def Laws.rlgl_set_shader_unchanged(frame, id, locations):
  {==}

def Laws.rlgl_location_uniform_absent(id, name):
  {==}

def Laws.rlgl_location_attrib_absent(id, name):
  {==}

def Laws.rlgl_shader_buffer_size_zero(id):
  {==}

def Laws.rlgl_set_vertex_attribute_unchanged(frame, index, size, kind, normalized, stride, offset):
  {==}

def Laws.rlgl_update_vertex_buffer_unchanged(frame, id, size, offset):
  {==}

def Laws.rlgl_compute_dispatch_unchanged(frame, x, y, z):
  {==}

def Laws.rlgl_pixel_format_name_rgba():
  {==}

def Laws.rlgl_pixel_format_name_unknown():
  {==}

def Laws.rlgl_version_software():
  {==}

def Laws.rlgl_matrix_mode_projection():
  {==}

def Laws.rlgl_matrix_mode_unknown():
  {==}

def Laws.rlgl_begin_lines():
  {==}

def Laws.rlgl_begin_points_ignored():
  {==}

def Laws.rlgl_framebuffer_zero_is_complete():
  {==}

def Laws.rlgl_framebuffer_zero_takes_no_attachment(id, width, height, format, attach, kind):
  {==}

def Laws.rlgl_framebuffer_color_alone_is_complete():
  {==}

def Laws.rlgl_framebuffer_empty_is_incomplete():
  {==}

def Laws.rlgl_framebuffer_depth_of_other_size_is_incomplete():
  {==}

def Laws.rlgl_framebuffer_channel_one_is_ignored():
  {==}

def Laws.rlgl_framebuffer_depth_attaches_as_texture_or_renderbuffer():
  {==}

def Laws.rlgl_framebuffer_depth_alone_is_incomplete():
  {==}

def Laws.rlgl_render_texture_depth_has_no_color_texture():
  {==}

def Laws.rlgl_render_texture_depth_refuses_a_color_attachment():
  {==}

def Laws.rlgl_render_texture_depth_refuses_another_depth():
  {==}

def Laws.rlgl_render_texture_depth_refuses_framebuffer_zero():
  {==}

def Laws.blind_target_never_the_screen(stash):
  {==}

def Laws.blind_target_leaves_no_depth_buffer(id, buffer, stash):
  {==}

def Laws.render_target_leaves_its_depth_buffer(id, buffer, stash):
  {==}

def Laws.rlgl_float_texture_has_no_storage(canvas):
  {==}

def Laws.rlgl_framebuffer_float_color_is_incomplete():
  {==}

def Laws.blind_target_bound_directly_is_marked(id):
  {==}

def Laws.blind_texture_mode_is_not_bound_directly(id, depth):
  {==}

def Laws.blind_target_bound_directly_hands_nothing_back(meta, width, height, texels):
  {==}

def Laws.rlgl_bind_framebuffer_zero_is_disable(frame, target):
  {==}

def Laws.rlgl_bound_active_draw_buffers_unchanged(bound, count):
  {==}

def Laws.rlgl_load_texture_cubemap_is_zero(frame, data, size, format, mipmaps):
  {==}

def Laws.rlgl_cull_distance_near_is_the_default():
  {==}

def Laws.rlgl_cull_distance_near_as_float():
  {==}

def Laws.rlgl_cull_distance_far_is_the_default():
  {==}

def Laws.rlgl_cull_distance_far_as_float():
  {==}

def Laws.color_hsv_term_six():
  {==}

def Laws.color_hsv_term_doubles():
  {==}

def Laws.color_hsv_steps_below_six():
  {==}

def Laws.color_hsv_steps_below_eight():
  {==}

def Laws.color_hsv_steps_eight():
  {==}

def Laws.color_hsv_steps_largest():
  {==}

def Laws.mesh_upload_unchanged(mesh, dynamic):
  {==}

def Laws.mesh_cube_vertex_count(width, height, length):
  {==}

def Laws.mesh_cube_triangle_count(width, height, length):
  {==}

def Laws.mesh_poly_degenerate_empty(libm, radius):
  {==}

def Laws.material_never_valid(material):
  {==}

def Laws.model_from_mesh_material(mesh):
  {==}

def Laws.window_ready(core):
  {==}

def Laws.window_never_resized(core):
  {==}

def Laws.window_set_state_unchanged(core, flags):
  {==}

def Laws.window_toggle_fullscreen_unchanged(core):
  {==}

def Laws.window_monitor_count_one(core):
  {==}

def Laws.window_no_dropped_files(core):
  {==}

def Laws.vr_stereo_mode_begins_unchanged(frame, config):
  {==}

def Laws.vr_stereo_mode_ends_unchanged(frame):
  {==}

def Laws.vr_unload_stereo_config(config):
  {==}

def Laws.stream_half_default():
  {==}

def Laws.stream_half_at_least_a_period():
  {==}

def Laws.stream_half_set():
  {==}

def Laws.stream_size_default_kept():
  {==}

def Laws.stream_unready_without_buffer():
  {==}

def Laws.stream_without_buffer_invalid():
  {==}

def Laws.stream_with_buffer_valid():
  {==}

def Laws.stream_first_half_first():
  {==}

def Laws.stream_second_half_next():
  {==}

def Laws.stream_no_half_left():
  {==}

def Laws.stream_filled_half_unprocessed():
  {==}

def Laws.stream_play_marks_both():
  {==}

def Laws.stream_callback_set():
  {==}

def Laws.stream_callback_removed():
  {==}

def Laws.stream_callback_kept_by_play():
  {==}

def Laws.stream_callback_not_for_a_sound():
  {==}

def Laws.stream_callback_answers_in_order():
  {==}

def Laws.stream_callback_zeros_after_the_answers():
  {==}

def Laws.stream_callback_frames_asked_for():
  {==}

def Laws.stream_callback_asked_last_first():
  {==}

def Laws.stream_callback_nothing_asked_of_the_halves():
  {==}

def Laws.stream_callback_answers_held():
  {==}

def Laws.stream_callback_answer_missing():
  {==}

def Laws.stream_callback_unready_asks_nothing():
  {==}

def Laws.processors_in_attach_order():
  {==}

def Laws.processors_mixed_are_buffer_zero():
  {==}

def Laws.processors_detach_takes_every_one():
  {==}

def Laws.processors_mixed_attached_last():
  {==}

def Laws.processors_unready_attach_nothing():
  {==}

def Laws.processors_no_buffer_attach_nothing():
  {==}

def Laws.processors_samples_come_back():
  {==}

def Laws.processors_sample_lost():
  {==}

def Laws.processors_sample_added():
  {==}

def Laws.processors_chained():
  {==}

def Laws.stream_frames_given_counted():
  {==}

def Laws.stream_frames_given_wrap():
  {==}

def Laws.stream_play_forgets_frames_given():
  {==}

def Laws.stream_sound_counts_no_frames():
  {==}

def Laws.stream_sound_always_processed():
  {==}

def Laws.stream_half_written_in_place():
  {==}

def Laws.msf_gif_bits_of_depth_16():
  {==}

def Laws.msf_gif_bits_of_depth_1():
  {==}

def Laws.msf_gif_bits_add_up_to_the_depth():
  {==}

def Laws.msf_gif_multiplier_five_bits():
  {==}

def Laws.msf_gif_multiplier_no_bits():
  {==}

def Laws.msf_gif_dither_second_column():
  {==}

def Laws.msf_gif_dither_last_corner():
  {==}

def Laws.msf_gif_dither_repeats_every_four():
  {==}

def Laws.msf_gif_white_cooks_to_all_bits():
  {==}

def Laws.msf_gif_black_cooks_to_zero():
  {==}

def Laws.msf_gif_alpha_is_not_cooked():
  {==}

def Laws.msf_gif_pass_marks_colors_ascending():
  {==}

def Laws.msf_gif_channel_five_bits():
  {==}

def Laws.msf_gif_channel_one_bit():
  {==}

def Laws.msf_gif_channel_no_bits():
  {==}

def Laws.msf_gif_put_keeps_bits_below_a_byte():
  {==}

def Laws.msf_gif_put_fills_a_byte():
  {==}

def Laws.msf_gif_put_fills_two_bytes():
  {==}

def Laws.msf_gif_kid_found():
  {==}

def Laws.msf_gif_kid_missing():
  {==}

def Laws.msf_gif_minimum_code_size_two():
  {==}

def Laws.msf_gif_minimum_code_size_grows():
  {==}

def Laws.msf_gif_chunk_writes_size_first():
  {==}

def Laws.msf_gif_buffer_holds_one_more_block():
  {==}

def Laws.msf_gif_buffer_lacks_a_byte():
  {==}

def Laws.msf_gif_depth_asked_zero():
  {==}

def Laws.msf_gif_depth_asked_negative():
  {==}

def Laws.msf_gif_depth_asked_above():
  {==}

def Laws.msf_gif_begin_writes_the_screen():
  {==}

def Laws.msf_gif_begin_without_width_none():
  {==}

def Laws.msf_gif_begin_above_the_limit_none():
  {==}

def Laws.msf_gif_frame_of_one_white_pixel():
  {==}

def Laws.msf_gif_frame_equal_to_the_one_before_is_transparent():
  {==}

def Laws.msf_gif_frame_with_a_pixel_missing_none():
  {==}

def Laws.msf_gif_frame_with_a_pixel_more_none():
  {==}

def Laws.msf_gif_finish_adds_the_trailer():
  {==}

def Laws.gui_list_counts_its_items():
  {==}

def Laws.gui_list_starts_at_its_scroll_index():
  {==}

def Laws.gui_list_start_past_the_last_page_is_zero():
  {==}

def Laws.gui_list_negative_start_is_zero():
  {==}

def Laws.gui_list_wheel_down_a_notch():
  {==}

def Laws.gui_list_wheel_stops_at_the_last_page():
  {==}

def Laws.gui_list_wheel_stops_at_the_first_item():
  {==}

def Laws.gui_list_press_selects():
  {==}

def Laws.gui_list_press_on_the_selected_item_clears():
  {==}

def Laws.gui_list_press_moves_the_selection():
  {==}

def Laws.gui_list_selection_goes_before_focus():
  {==}

def Laws.gui_list_focused_item():
  {==}

def Laws.gui_list_plain_item():
  {==}

def Laws.gui_list_disabled_items():
  {==}

def Laws.gui_font_base_size_is_the_default_font_s():
  {==}

def Laws.mp3_memory_stream_has_its_bytes_at_hand():
  {==}

def Laws.mp3_file_stream_begins_with_an_empty_buffer():
  {==}

def Laws.mp3_memory_stream_is_told_by_its_capacity():
  {==}

def Laws.mp3_file_stream_is_not_a_memory_stream():
  {==}

def Laws.mp3_memory_stream_is_not_filled():
  {==}

def Laws.mp3_memory_stream_goes_on_after_passed_bytes():
  {==}

def Laws.mp3_memory_stream_is_over_when_no_byte_is_passed():
  {==}

def Laws.mp3_memory_stream_rewound_has_its_bytes_again():
  {==}

def Laws.mp3_memory_stream_holds_no_byte_of_its_tags():
  {==}

def Laws.mp3_memory_of_a_short_file_does_not_open():
  {==}

def Laws.mp3_stream_memory_of_a_short_file_does_not_open():
  {==}

def Laws.wave_mp3_length_counts_bytes():
  {==}

def Laws.music_kind_of_mp3_tokens():
  {==}

def Laws.music_kind_of_wav_and_qoa_tokens():
  {==}

def Laws.png_image_keeps_4096_on_a_side():
  {==}

def Laws.png_texture_strip_within_16384():
  {==}

def Laws.png_side_limit_passes_errors_on():
  {==}

def Laws.png_header_of_4096_squared_pixels():
  {==}

def Laws.png_header_past_4096_squared_pixels():
  {==}

def Laws.png_header_past_16384_on_a_side():
  {==}

def Laws.png_header_without_rows():
  {==}

def Laws.png_image_of_4096_on_each_side():
  {==}

def Laws.png_image_of_4097_on_a_side():
  {==}

def Laws.png_invalid_header_before_its_size():
  {==}

def Laws.vorbis_ilog_counts_the_bits():
  {==}

def Laws.vorbis_ilog_of_the_largest_int():
  {==}

def Laws.vorbis_ilog_of_a_negative_int():
  {==}

def Laws.vorbis_bit_reverse_of_the_low_bit():
  {==}

def Laws.vorbis_bit_reverse_of_the_low_half():
  {==}

def Laws.vorbis_bit_reverse_twice():
  {==}

def Laws.vorbis_unpack_one():
  {==}

def Laws.vorbis_unpack_three():
  {==}

def Laws.vorbis_unpack_largest_finite():
  {==}

def Laws.vorbis_unpack_past_the_floats():
  {==}

def Laws.vorbis_unpack_smallest_normal():
  {==}

def Laws.vorbis_unpack_smallest_subnormal():
  {==}

def Laws.vorbis_unpack_half_the_smallest_is_zero():
  {==}

def Laws.vorbis_unpack_a_tie_goes_to_even():
  {==}

def Laws.vorbis_unpack_far_below_the_floats():
  {==}

def Laws.vorbis_codewords_of_a_tree():
  {==}

def Laws.vorbis_codewords_skip_a_symbol_without_a_code():
  {==}

def Laws.vorbis_codewords_of_too_many_lengths():
  {==}

def Laws.vorbis_codewords_of_no_symbol():
  {==}

def Laws.vorbis_free_level_is_the_highest_up_to_the_length():
  {==}

def Laws.vorbis_free_level_without_a_leaf():
  {==}

def Laws.vorbis_taken_frees_the_leaves_beside_the_path():
  {==}

def Laws.vorbis_sorted_by_the_codes_read_the_other_way():
  {==}

def Laws.vorbis_sorted_codewords_end_with_the_sentinel():
  {==}

def Laws.vorbis_sorted_table_keeps_the_long_codes():
  {==}

def Laws.vorbis_sorted_table_of_a_sparse_codebook_keeps_all():
  {==}

def Laws.vorbis_fast_fill_steps_by_the_code_s_period():
  {==}

def Laws.vorbis_fast_entry_past_the_shorts_fills_nothing():
  {==}

def Laws.vorbis_fast_entry_of_a_long_code_fills_nothing():
  {==}

def Laws.vorbis_codewords_by_symbol():
  {==}

def Laws.vorbis_no_tree_no_codebook():
  {==}

def Laws.vorbis_power_capped_is_the_power():
  {==}

def Laws.vorbis_power_capped_stops_at_2_26():
  {==}

def Laws.vorbis_power_capped_of_one_and_zero():
  {==}

def Laws.vorbis_root_of_one_dimension():
  {==}

def Laws.vorbis_root_of_a_square():
  {==}

def Laws.vorbis_root_of_many_dimensions():
  {==}

def Laws.vorbis_lookup1_of_a_perfect_power():
  {==}

def Laws.vorbis_lookup1_under_a_perfect_power():
  {==}

def Laws.vorbis_lookup1_of_one_entry():
  {==}

def Laws.vorbis_lookup1_without_entries():
  {==}

def Laws.vorbis_lookup1_without_entries_or_dimensions():
  {==}

def Laws.vorbis_lookup1_without_dimensions_is_undefined():
  {==}

def Laws.vorbis_lookup1_of_2_19_entries_in_one_dimension():
  {==}

def Laws.vorbis_lookup1_past_2_19_entries_in_one_dimension():
  {==}

def Laws.vorbis_lookup1_of_a_large_codebook_away_from_a_power():
  {==}

def Laws.vorbis_lookup1_of_a_large_codebook_just_under_a_power():
  {==}

def Laws.vorbis_lookup1_of_30_dimensions():
  {==}

def Laws.vorbis_lookup1_of_31_dimensions_is_undefined():
  {==}

def Laws.vorbis_lookup1_of_a_root_of_two_in_20_dimensions_is_undefined():
  {==}

def Laws.vorbis_lookup1_of_a_root_of_two_in_19_dimensions():
  {==}

def Laws.vorbis_lookup1_past_24_bits_of_entries():
  {==}

def Laws.vorbis_lookup1_past_16_bits_of_dimensions():
  {==}

def Laws.ogg_get8_at_the_end_is_zero():
  {==}

def Laws.ogg_get8_at_the_end_is_eof():
  {==}

def Laws.ogg_get32_is_low_byte_first():
  {==}

def Laws.ogg_get32_past_the_end_reads_zeros():
  {==}

def Laws.ogg_getn_of_more_than_is_left_fails():
  {==}

def Laws.ogg_getn_of_more_than_is_left_reads_nothing():
  {==}

def Laws.ogg_getn_gives_the_bytes():
  {==}

def Laws.ogg_skip_moves_past_the_end():
  {==}

def Laws.ogg_skip_to_the_end_is_eof():
  {==}

def Laws.ogg_skip_short_of_the_end_is_not_eof():
  {==}

def Laws.ogg_page_without_its_capture_pattern():
  {==}

def Laws.ogg_capture_pattern_stops_at_the_wrong_byte():
  {==}

def Laws.ogg_page_of_another_version():
  {==}

def Laws.ogg_page_with_a_cut_segment_table():
  {==}

def Laws.ogg_page_starts():
  {==}

def Laws.ogg_page_start_stops_at_the_body():
  {==}

def Laws.ogg_page_keeps_its_flags():
  {==}

def Laws.ogg_packet_first_byte():
  {==}

def Laws.ogg_packet_ends_after_its_segment():
  {==}

def Laws.ogg_packet_end_is_no_error():
  {==}

def Laws.ogg_get32_packet_adds_the_end_as_minus_one():
  {==}

def Laws.ogg_bits_are_read_low_first():
  {==}

def Laws.ogg_bits_go_on_where_the_last_ended():
  {==}

def Laws.ogg_bits_of_no_width():
  {==}

def Laws.ogg_bits_of_32():
  {==}

def Laws.ogg_bits_past_the_packet_are_zero():
  {==}

def Laws.ogg_bits_past_the_packet_stay_out():
  {==}

def Laws.ogg_flush_passes_the_packet():
  {==}

def Laws.ogg_no_packet_at_the_end_is_no_error():
  {==}

def Laws.ogg_start_packet_at_the_end_is_an_error():
  {==}

def Laws.ogg_continued_page_starts_no_packet():
  {==}

def Laws.ogg_continued_page_is_needed_to_go_on():
  {==}

def Laws.vorbis_setup_going():
  {==}

def Laws.vorbis_setup_refused_is_not_going():
  {==}

def Laws.vorbis_setup_failed_without_an_error_is_not_going():
  {==}

def Laws.vorbis_setup_first_failed_check_wins():
  {==}

def Laws.vorbis_setup_no_failed_check_goes_on():
  {==}

def Laws.vorbis_setup_name_is_vorbis():
  {==}

def Laws.vorbis_setup_name_of_another_case():
  {==}

def Laws.vorbis_setup_name_cut_short():
  {==}

def Laws.vorbis_setup_length_within_the_budget():
  {==}

def Laws.vorbis_setup_length_over_the_budget_is_refused():
  {==}

def Laws.vorbis_setup_length_of_the_largest_int_is_refused():
  {==}

def Laws.vorbis_setup_negative_length_is_out_of_memory():
  {==}

def Laws.vorbis_setup_most_negative_length_is_out_of_memory():
  {==}

def Laws.vorbis_setup_no_comment_list():
  {==}

def Laws.vorbis_setup_negative_comment_count_is_no_list():
  {==}

def Laws.vorbis_setup_negative_comment_count_goes_on():
  {==}

def Laws.vorbis_setup_comment_list_within_the_budget():
  {==}

def Laws.vorbis_setup_comment_list_over_the_budget_is_refused():
  {==}

def Laws.vorbis_setup_comment_list_of_negative_size_is_out_of_memory():
  {==}

def Laws.vorbis_setup_comment_list_smaller_than_its_count_is_refused():
  {==}

def Laws.vorbis_setup_product_of_entries_and_dimensions():
  {==}

def Laws.vorbis_setup_product_past_the_ints():
  {==}

def Laws.vorbis_setup_product_under_the_ints():
  {==}

def Laws.vorbis_setup_product_without_dimensions():
  {==}

def Laws.vorbis_setup_divisor_within_the_unsigned_ints():
  {==}

def Laws.vorbis_setup_divisor_past_the_unsigned_ints():
  {==}

def Laws.vorbis_setup_divisor_of_one_value_never_passes():
  {==}

def Laws.vorbis_setup_repeated():
  {==}

def Laws.vorbis_setup_range():
  {==}

def Laws.vorbis_setup_of_no_data():
  {==}

def Laws.vorbis_setup_first_page_of_another_length():
  {==}

def Laws.vorbis_setup_first_page_not_flagged_first():
  {==}

def Laws.vorbis_setup_ogg_skeleton():
  {==}

def Laws.vorbis_setup_identification_alone():
  {==}

def Laws.vorbis_setup_identification_cut_in_its_name():
  {==}

def Laws.vorbis_setup_seventeen_channels():
  {==}

def Laws.vorbis_setup_no_sample_rate():
  {==}

def Laws.vorbis_setup_block_size_under_64():
  {==}

def Laws.vorbis_setup_first_block_size_over_the_second():
  {==}

def Laws.vorbis_setup_channels_of_the_identification():
  {==}

def Laws.vorbis_setup_rate_of_the_identification():
  {==}

def Laws.vorbis_setup_block_sizes_of_the_identification():
  {==}

def Laws.vorbis_setup_comment_header_of_another_type():
  {==}

def Laws.vorbis_setup_empty_comment_packet_fails_without_an_error():
  {==}

def Laws.vorbis_setup_negative_vendor_length():
  {==}

def Laws.vorbis_setup_vendor_over_the_budget():
  {==}

def Laws.vorbis_setup_comment_without_its_framing_bit():
  {==}

def Laws.vorbis_setup_without_its_third_packet():
  {==}

def Laws.vorbis_setup_header_of_another_type():
  {==}

def Laws.vorbis_setup_codebook_without_its_sync_pattern():
  {==}

def Laws.vorbis_setup_codebook_without_entries_is_out_of_memory():
  {==}

def Laws.vorbis_setup_codebook_over_the_budget_is_refused():
  {==}
