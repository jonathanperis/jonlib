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

def Laws.glibc_expf_87_none():
  {==}

def Laws.glibc_expf_variant_argument_none():
  {==}

def Laws.glibc_expf_other_variant_argument_none():
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
