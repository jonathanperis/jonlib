import Base
import ./src/checked_angle.bend as CA
import ./src/modern_angle.bend as MA
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/binary64_narrow.bend as N
import ./src/binary64_fma.bend as F
import ./src/binary64_add_sub.bend as A
import ./src/binary64_ops.bend as O
import ./src/binary64_gradual_multiply.bend as G
import ./src/resize_numeric.bend as Resize
import ./src/bmp.bend as Bmp
import ./src/tga.bend as Tga
import ./src/qoi.bend as Qoi
import ./src/formats.bend as Formats

law clear_dimensions:
  for +width: U32
  for +height: U32
  for pixels: Array<U32>
  for color: U32
  {J.Surface.dimensions(J.Surface.clear(J.Surface{width, height, pixels}, color))
    == (width, height) : U32 & U32}

law transpose_involution:
  for +matrix: M.Matrix
  {M.Matrix.transpose(M.Matrix.transpose(matrix)) == matrix : M.Matrix}

law vector3_float_count:
  for vector: M.Vector3
  {List.length(&2, F32, M.Vector3.to_float_v(vector)) == 3n : Nat}

law matrix_float_count:
  for matrix: M.Matrix
  {List.length(&2, F32, M.Matrix.to_float_v(matrix)) == 16n : Nat}

# Structural recursion and explicit classification branches, not a complete
# proof of IEEE rounding arithmetic. Boundary equalities below are concrete.
law binary64_jam_zero:
  for value: N.Wide
  {N.Wide.jam(0n, value) == value : N.Wide}

law binary64_jam_successor:
  for count: Nat
  for value: N.Wide
  {N.Wide.jam(1n+count, value) == N.Wide.jam(count, N.Wide.jam1(value)) : N.Wide}

law binary64_reject_special:
  for exponent: U32
  for sign: U32
  for value: N.Wide
  {N.checked.special(True{}, exponent, sign, value) == None{} : Maybe<U32>}

law binary64_half_minimum:
  {N.checked(915406848, 0) == Some{0} : Maybe<U32>}

law binary64_above_half_minimum:
  {N.checked(915406848, 1) == Some{1} : Maybe<U32>}

law binary64_minimum_normal_carry:
  {N.checked(940572671, 3758096384) == Some{8388608} : Maybe<U32>}

law binary64_overflow_carry:
  {N.checked(1206910975, 4026531840) == Some{2139095040} : Maybe<U32>}

law binary64_negative_zero:
  {N.checked(2147483648, 0) == Some{2147483648} : Maybe<U32>}

law binary64_odd_halfway:
  {N.checked(916979712, 0) == Some{2} : Maybe<U32>}

# Private bounded FMA: structural statements and concrete equalities only.
# These do not constitute a universal arithmetic correctness theorem.
law bounded_fma_shift_zero:
  for value: F.Words
  {F.Words.shl(0n, value) == value : F.Words}

law bounded_fma_shift_successor:
  for count: Nat
  for value: F.Words
  {F.Words.shl(1n+count, value) == F.Words.shl(count, F.Words.shl1(value)) : F.Words}

law bounded_fma_reject:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  for ch: U32
  for cl: U32
  {F.checked.valid(False{}, ah, al, bh, bl, ch, cl) == None{} : Maybe<F.Words>}

law bounded_fma_negative_zero:
  {F.checked(2147483648, 0, 0, 0, 2147483648, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law bounded_fma_mixed_zero:
  {F.checked(0, 0, 0, 0, 2147483648, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law bounded_fma_exact_cancellation:
  {F.checked(1072693248, 0, 1072693248, 0, 3220176896, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law bounded_fma_product_residual:
  {F.checked(1072693248, 1, 1072693247, 4294967294, 3220176896, 0) == Some{F.Words{3111124992, 0}} : Maybe<F.Words>}

law bounded_fma_even_tie:
  {F.checked(1072693248, 0, 1072693248, 0, 1017118720, 0) == Some{F.Words{1072693248, 0}} : Maybe<F.Words>}

law bounded_fma_odd_tie:
  {F.checked(1072693248, 0, 1072693248, 1, 1017118720, 0) == Some{F.Words{1072693248, 2}} : Maybe<F.Words>}

law bounded_fma_lattice_floor:
  {F.checked(782237696, 1, 782237696, 1, 2639265792, 2) == Some{F.Words{382730240, 0}} : Maybe<F.Words>}

# Bounded add/sub: branch/definition structure and selected concrete results,
# not a universal accumulator or IEEE rounding theorem.
law bounded_add_sub_reject:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {A.checked.valid(False{}, ah, al, bh, bl) == None{} : Maybe<F.Words>}

law bounded_sub_sign_inversion:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {A.checked_sub(ah, al, bh, bl) == A.checked_add(ah, al, (bh .^. 2147483648 : U32), bl) : Maybe<F.Words>}

law bounded_add_negative_zeros:
  {A.checked_add(2147483648, 0, 2147483648, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law bounded_add_mixed_zeros:
  {A.checked_add(0, 0, 2147483648, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law bounded_sub_negative_zero:
  {A.checked_sub(2147483648, 0, 0, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law bounded_sub_equal_negative_zeros:
  {A.checked_sub(2147483648, 0, 2147483648, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law bounded_add_cancellation:
  {A.checked_add(1072693248, 0, 3220176896, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law bounded_add_even_tie:
  {A.checked_add(1072693248, 0, 1017118720, 0) == Some{F.Words{1072693248, 0}} : Maybe<F.Words>}

law bounded_add_odd_tie:
  {A.checked_add(1072693248, 1, 1017118720, 0) == Some{F.Words{1072693248, 2}} : Maybe<F.Words>}

law bounded_sub_lattice_floor:
  {A.checked_sub(128974848, 1, 128974848, 0) == Some{F.Words{74448896, 0}} : Maybe<F.Words>}

law bounded_add_largest_carry:
  {A.checked_add(1210056703, 4294967295, 1210056703, 4294967295) == Some{F.Words{1211105279, 4294967295}} : Maybe<F.Words>}

# Checked normal ops and raw adapters: structural branches and concrete vectors.
# These establish neither universal rounding nor a kernel-reachability theorem.
law checked_multiply_reject:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {O.checked_multiply.valid(False{}, ah, al, bh, bl) == None{} : Maybe<F.Words>}

law checked_divide_reject:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {O.checked_divide.valid(False{}, ah, al, bh, bl) == None{} : Maybe<F.Words>}

law checked_decode_reject:
  for high: U32
  for low: U32
  {O.checked_decode.valid(False{}, high, low) == None{} : Maybe<Resize.Double>}




law checked_multiply_negative_zero:
  {O.checked_multiply(2147483648, 0, 1072693248, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law checked_multiply_zero_invalid:
  {O.checked_multiply(0, 0, 2146435072, 0) == None{} : Maybe<F.Words>}

law checked_divide_negative_zero:
  {O.checked_divide(0, 0, 3220176896, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law checked_divide_zero_denominator:
  {O.checked_divide(0, 0, 2147483648, 0) == None{} : Maybe<F.Words>}





law words_increment_negative_carry:
  {O.increment(3220176896, 4294967295) == F.Words{3220176897, 0} : F.Words}

law words_decrement_negative_borrow:
  {O.decrement(3220176896, 0) == F.Words{3220176895, 4294967295} : F.Words}

law words_zero_equality:
  {O.numerical_equal(0, 0, 2147483648, 0) == True{} : Bool}

law checked_promote_reject_infinity:
  {O.checked_promote(2139095040) == None{} : Maybe<F.Words>}

law checked_identity_negative_zero:
  {O.checked_identity(2147483648, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law checked_identity_reject_subnormal:
  {O.checked_identity(0, 1) == None{} : Maybe<F.Words>}

law checked_finite_subnormal:
  {O.checked_finite(0, 1) == Some{F.Words{0, 1}} : Maybe<F.Words>}

law words_negative_magnitude:
  {O.magnitude_order(3220176896, 1, 1072693248, 0) == 2 : U32}

law words_power_minimum:
  {O.checked_power(1) == Some{F.Words{1048576, 0}} : Maybe<F.Words>}

law words_power_reject_zero:
  {O.checked_power(0) == None{} : Maybe<F.Words>}

# Gradual-output multiplication: two structural branches and concrete controls.
# Internal raw-window ties are not claims about reachable significand pairs.
# These laws are not a universal product or rounding theorem.
law gradual_multiply_reject:
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {G.checked.valid(False{}, ah, al, bh, bl) == None{} : Maybe<F.Words>}

law gradual_multiply_zero_branch:
  for sign: U32
  for biased_sum: U32
  for ah: U32
  for al: U32
  for bh: U32
  for bl: U32
  {G.calculate.zero(True{}, sign, biased_sum, ah, al, bh, bl) == F.Words{sign, 0} : F.Words}

law gradual_multiply_negative_zero:
  {G.checked(2147483648,0,1072693248,0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law gradual_multiply_negative_zero_pair:
  {G.checked(2147483648,0,2147483648,0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law gradual_multiply_invalid_first_with_zero:
  {G.checked(0,1,0,0) == None{} : Maybe<F.Words>}

law gradual_multiply_invalid_second_with_zero:
  {G.checked(0,0,0,1) == None{} : Maybe<F.Words>}

law gradual_multiply_half_minimum:
  {G.checked(782237696,0,235929600,0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law gradual_multiply_above_half:
  {G.checked(782237696,0,235929600,1) == Some{F.Words{0, 1}} : Maybe<F.Words>}

law gradual_multiply_odd_tie:
  {G.checked(782237696,0,237502464,0) == Some{F.Words{0, 2}} : Maybe<F.Words>}

law gradual_multiply_even_tie:
  {G.checked(782237696,0,238288896,0) == Some{F.Words{0, 2}} : Maybe<F.Words>}

law gradual_multiply_minimum_normal_tie:
  {G.checked(782237696,0,291504127,4294967295) == Some{F.Words{1048576, 0}} : Maybe<F.Words>}

law gradual_multiply_already_normal:
  {G.checked(782761984,0,290979840,0) == Some{F.Words{1179648, 0}} : Maybe<F.Words>}

law gradual_multiply_k107_zero:
  {G.checked(783286271,4294967295,234881023,4294967295) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law gradual_multiply_k192_negative_zero:
  {G.checked(783286271,4294967295,2293235711,4294967295) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law gradual_multiply_once_rounded_subnormal:
  {G.checked(782237696,1,290455552,4) == Some{F.Words{524288, 3}} : Maybe<F.Words>}

law gradual_multiply_once_rounded_minimum_normal_edge:
  {G.checked(782237696,1,291504127,4294967293) == Some{F.Words{1048575, 4294967295}} : Maybe<F.Words>}

law gradual_multiply_once_rounded_half_minimum_edge:
  {G.checked(782237696,1,235929599,4294967295) == Some{F.Words{0, 1}} : Maybe<F.Words>}

law gradual_multiply_normal_carry:
  {G.checked(1073217536,0,1073042773,1431655765) == Some{F.Words{1073741824, 0}} : Maybe<F.Words>}

law gradual_multiply_internal_k106_half_window:
  {G.gradual(0,F.Words{0,4}) == F.Words{0,0} : F.Words}

law gradual_multiply_internal_minimum_normal_half_window:
  {G.gradual(0,F.Words{8388607,4294967292}) == F.Words{1048576,0} : F.Words}

# Private modern atan2: explicit failure propagation and finite zero branches.
# These are scoped laws, not a universal transcendental-correctness theorem.
law modern_angle_reject_before_arithmetic:
  for y: U32
  for x: U32
  {MA.traced.valid(False{},y,x) == MA.Packet{MA.Failed{1,[y,x]},4096,0,0,Nil{}} : MA.Packet}

law modern_angle_add_failure:
  for id: U32
  for words: +List<U32>
  for other: MA.Value
  {MA.add(10,MA.Failed{id,words},other) == MA.Failed{id,words} : MA.Value}

law modern_angle_multiply_failure:
  for id: U32
  for words: +List<U32>
  for other: MA.Value
  {MA.mul(20,MA.Failed{id,words},other) == MA.Failed{id,words} : MA.Value}

law modern_angle_fma_failure:
  for id: U32
  for words: +List<U32>
  for b: MA.Value
  for c: MA.Value
  {MA.fma(81,MA.Failed{id,words},b,c) == MA.Failed{id,words} : MA.Value}

law modern_angle_failed_narrow:
  for id: U32
  for words: +List<U32>
  {MA.narrow(MA.Failed{id,words}) == None{} : Maybe<U32>}

law modern_angle_reject_infinite_y:
  {MA.checked(2139095040,1065353216) == None{} : Maybe<U32>}

law modern_angle_reject_nan_x:
  {MA.checked(0,2143289344) == None{} : Maybe<U32>}

law modern_angle_zero_positive_axis:
  {MA.checked(0,1065353216) == Some{0} : Maybe<U32>}

law modern_angle_negative_zero_positive_axis:
  {MA.checked(2147483648,1065353216) == Some{2147483648} : Maybe<U32>}

law modern_angle_positive_zeros:
  {MA.checked(0,0) == Some{0} : Maybe<U32>}

law modern_angle_negative_y_zero_x:
  {MA.checked(2147483648,0) == Some{2147483648} : Maybe<U32>}

law modern_angle_positive_y_negative_zero_x:
  {MA.checked(0,2147483648) == Some{1078530011} : Maybe<U32>}

law modern_angle_negative_zeros:
  {MA.checked(2147483648,2147483648) == Some{3226013659} : Maybe<U32>}

# Checked angle wrapper laws prove staged rejection/propagation and preserved
# defaults, not universal transcendental accuracy or all native host behavior.
law checked_angle_scalar_none:
  {CA.scalar_result(None{}) == Fail{31} : Result<&2, &2, U32, F32>}

law checked_angle_normal_reject:
  for stage: U32
  for value: F32
  {CA.normal.route(False{}, stage, value) == Fail{stage} : Result<&2, &2, U32, F32>}

law checked_angle_sqrt_reject:
  for value: F32
  {CA.sqrt.valid(False{}, value) == Fail{24} : Result<&2, &2, U32, F32>}

law checked_angle_maybe_failure:
  for stage: U32
  {CA.maybe(Fail{stage}) == None{} : Maybe<F32>}

law checked_angle_vector2_input_reject:
  for profile: U32
  for x: F32
  for y: F32
  for u: F32
  for v: F32
  {CA.vector2.valid(False{}, profile, x, y, u, v) == Fail{1} : Result<&2, &2, U32, F32>}

law checked_angle_line_input_reject:
  for profile: U32
  for x: F32
  for y: F32
  for u: F32
  for v: F32
  {CA.line.valid(False{}, profile, x, y, u, v) == Fail{1} : Result<&2, &2, U32, F32>}

law checked_angle_vector3_input_reject:
  for profile: U32
  for x: F32
  for y: F32
  for z: F32
  for u: F32
  for v: F32
  for w: F32
  {CA.vector3.valid(False{}, profile, x, y, z, u, v, w) == Fail{1} : Result<&2, &2, U32, F32>}

law angle_vector2_default_preserved:
  for +left: M.Vector2
  for +right: M.Vector2
  {M.Vector2.angle(left, right) == M.Vector2.angle_for(M.AccurateGradient{}, left, right) : F32}

law angle_line_default_preserved:
  for +left: M.Vector2
  for +right: M.Vector2
  {M.Vector2.line_angle(left, right) == M.Vector2.line_angle_for(M.AccurateGradient{}, left, right) : F32}

law angle_vector3_default_preserved:
  for +left: M.Vector3
  for +right: M.Vector3
  {M.Vector3.angle(left, right) == M.Vector3.angle_for(M.AccurateGradient{}, left, right) : F32}

law checked_angle_scalar_some:
  for word: U32
  {CA.scalar_result(Some{word}) == CA.normal(32, CA.from_word(word)) : Result<&2, &2, U32, F32>}

# BMP structural padding laws; byte/channel arithmetic is differential evidence.
law bmp_padding_zero:
  for bytes: +List<U32>
  {Bmp.encode24.padding(0n, bytes) == bytes : +List<U32>}

law bmp_padding_successor:
  for count: Nat
  for bytes: +List<U32>
  {Bmp.encode24.padding(1n+count, bytes) == Bmp.encode24.padding(count, Con{0, bytes}) : +List<U32>}

law bmp_nonterminal_row:
  for padding: Nat
  for bytes: +List<U32>
  {Bmp.encode24.row(False{}, padding, bytes) == bytes : +List<U32>}

law bmp_terminal_row:
  for padding: Nat
  for bytes: +List<U32>
  {Bmp.encode24.row(True{}, padding, bytes) == Bmp.encode24.padding(padding, bytes) : +List<U32>}

# Scoped TGA routing/structural laws; not a universal codec or numeric proof.
law formatted_tga_gray_channels:
  {J.Image.Formatted.tga.channels(1) == 1 : U32}

law formatted_tga_gray_alpha_channels:
  {J.Image.Formatted.tga.channels(2) == 2 : U32}

law formatted_tga_rgb_channels:
  {J.Image.Formatted.tga.channels(4) == 3 : U32}

law formatted_tga_rgba_channels:
  {J.Image.Formatted.tga.channels(7) == 4 : U32}

law tga_values_zero:
  for channels: U32
  for colors: +List<U32>
  for bytes: +List<U32>
  {Tga.encode.values(0n, channels, colors, bytes) == bytes : +List<U32>}

law tga_row_zero:
  for channels: U32
  for colors: +List<U32>
  for bytes: +List<U32>
  {Tga.encode.row(0n, channels, (colors, bytes)) == bytes : +List<U32>}

# Scoped QOI metadata/packing laws; not a universal decoding theorem.
law formatted_qoi_rgb_format:
  {J.Image.Formatted.qoi.format(3) == 4 : U32}

law formatted_qoi_rgba_format:
  {J.Image.Formatted.qoi.format(4) == 7 : U32}

law formatted_qoi_rgb_word:
  {J.Image.Formatted.qoi.word(3, 305419896) == 5649426 : U32}

law formatted_qoi_rgba_word:
  {J.Image.Formatted.qoi.word(4, 305419896) == 2018915346 : U32}

law formatted_qoi_pixels_zero:
  for index: U32
  for channels: U32
  for pixels: Array<U32>
  {J.Image.Formatted.qoi.pixels(0n, index, channels, pixels) == pixels : Array<U32>}

# Scoped PNM metadata/packing structural facts, not a universal codec proof.
law formatted_pnm_gray_format:
  {J.Image.Formatted.pnm.format(1) == 1 : U32}

law formatted_pnm_rgb_format:
  {J.Image.Formatted.pnm.format(3) == 4 : U32}

law formatted_pnm_gray_word:
  {J.Image.Formatted.pnm.word(1, 2155905279) == 128 : U32}

law formatted_pnm_rgb_word:
  {J.Image.Formatted.pnm.word(3, 305420031) == 5649426 : U32}

law formatted_pnm_pixels_zero:
  for index: U32
  for channels: U32
  for pixels: Array<U32>
  {J.Image.Formatted.pnm.pixels(0n, index, channels, pixels) == pixels : Array<U32>}

# Pure file-boundary facts; these do not prove host IO, allocation or closure.
law qoi_file_limit:
  {J.Image.file.limit(J.QoiFile{}) == 83886102 : U32}

law image_file_complete_empty:
  {J.Image.file.complete(0n, Nil{}) == True{} : Bool}

law image_file_complete_exact:
  {J.Image.file.complete(2n, [1, 2]) == True{} : Bool}

law image_file_complete_short:
  {J.Image.file.complete(2n, [1]) == False{} : Bool}

law image_file_complete_long:
  {J.Image.file.complete(1n, [1, 2]) == False{} : Bool}

# Scoped QOI export routing/packing facts, not a universal encoder or IO theorem.
law formatted_qoi_export_rgb_channels:
  {J.Image.Formatted.qoi.channels(4) == 3 : U32}

law formatted_qoi_export_rgba_channels:
  {J.Image.Formatted.qoi.channels(7) == 4 : U32}

law formatted_qoi_export_gray_rejected:
  {J.Image.Formatted.qoi.channels(1) == 0 : U32}

law formatted_qoi_export_gray_alpha_rejected:
  {J.Image.Formatted.qoi.channels(2) == 0 : U32}

law formatted_qoi_export_rgb565_rejected:
  {J.Image.Formatted.qoi.channels(3) == 0 : U32}

law formatted_qoi_export_rgb5a1_rejected:
  {J.Image.Formatted.qoi.channels(5) == 0 : U32}

law formatted_qoi_export_rgba4_rejected:
  {J.Image.Formatted.qoi.channels(6) == 0 : U32}

law formatted_qoi_export_r32_rejected:
  {J.Image.Formatted.qoi.channels(8) == 0 : U32}

law formatted_qoi_export_rgb_packing:
  {Formats.image_color(4, 5649426) == 305420031 : U32}

law formatted_qoi_export_rgba_packing:
  {Formats.image_color(7, 2018915346) == 305419896 : U32}

law formatted_qoi_export_packing_empty:
  for index: U32
  for format: U32
  for pixels: Array<U32>
  {Formats.packed_colors(0n, index, format, pixels) == pixels : Array<U32>}

law qoi_surface_encoder_preserved:
  for width: U32
  for height: U32
  for pixels: Array<U32>
  {Qoi.encode(width, height, pixels) == Qoi.encode.channels(width, height, 4, pixels) : +List<U32>}
