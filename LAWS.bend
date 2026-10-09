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
import ./src/jpeg.bend as Jpg
import ./src/tga.bend as Tga
import ./src/qoi.bend as Qoi
import ./src/png.bend as Png
import ./src/pic.bend as Pic
import ./src/formats.bend as Formats
import ./src/codec.bend as Codec
import ./src/qoa.bend as Qoa
import ./src/fma.bend as Fma
import ./src/asin.bend as Asin
import ./src/lgpl/asin.bend as GlibcAsin
import ./src/binary64_sqrt.bend as Sqrt
import ./src/wav.bend as Wav
import ./src/wav_adpcm.bend as Adpcm
import ./src/convert.bend as WaveConvert
import ./src/resampler.bend as Resampler
import ./src/lowpass.bend as Lowpass
import ./src/shapes.bend as Shapes
import ./src/frame.bend as FrameCore
import ./src/fonts.bend as FontCore
import ./src/input.bend as InputCore
import ./src/gestures.bend as GestureCore
import ./src/clock.bend as Clock
import ./src/core_state.bend as CoreState

law clear_dimensions:
  for +width: U32
  for +height: U32
  for format: U32
  for pixels: Array<U32>
  for color: U32
  {J.Surface.dimensions(J.Surface.clear(J.Surface{width, height, format, J.Words{pixels}}, color))
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

# Scoped export routing/structural laws; not a universal codec or numeric proof.
law export_gray_channels:
  {J.Surface.png.channels(1) == 1 : U32}

law export_gray_alpha_channels:
  {J.Surface.png.channels(2) == 2 : U32}

law export_rgb_channels:
  {J.Surface.png.channels(4) == 3 : U32}

law export_rgba_channels:
  {J.Surface.png.channels(7) == 4 : U32}

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

# Pure file-boundary facts; these do not prove host IO, allocation or closure.
law raster_file_limit:
  {J.Image.file.limit(J.RasterFile{}) == 1048576 : U32}

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
law qoi_export_rgb_channels:
  {J.Surface.qoi.channels(4) == 3 : U32}

law qoi_export_rgba_channels:
  {J.Surface.qoi.channels(7) == 4 : U32}

law qoi_export_gray_rejected:
  {J.Surface.qoi.channels(1) == 0 : U32}

law qoi_export_gray_alpha_rejected:
  {J.Surface.qoi.channels(2) == 0 : U32}

law qoi_export_rgb565_rejected:
  {J.Surface.qoi.channels(3) == 0 : U32}

law qoi_export_rgb5a1_rejected:
  {J.Surface.qoi.channels(5) == 0 : U32}

law qoi_export_rgba4_rejected:
  {J.Surface.qoi.channels(6) == 0 : U32}

law qoi_export_r32_rejected:
  {J.Surface.qoi.channels(8) == 0 : U32}

law qoi_export_rgb_packing:
  {Formats.image_color(4, 5649426) == 305420031 : U32}

law qoi_export_rgba_packing:
  {Formats.image_color(7, 2018915346) == 305419896 : U32}

law qoi_export_packing_empty:
  for index: U32
  for format: U32
  for pixels: Array<U32>
  {Formats.packed_colors(0n, index, format, pixels) == pixels : Array<U32>}

law qoi_surface_encoder_preserved:
  for width: U32
  for height: U32
  for pixels: Array<U32>
  {Qoi.encode(width, height, pixels) == Qoi.encode.channels(width, height, 4, pixels) : +List<U32>}

# Scoped TGA decode metadata/integer packing; not a universal codec proof.
law tga_native_gray8:
  {Tga.native.channels(8, False{}) == 1 : U32}

law tga_native_packed15:
  {Tga.native.channels(15, True{}) == 3 : U32}

law tga_native_packed16:
  {Tga.native.channels(16, False{}) == 3 : U32}

law tga_native_grayalpha16:
  {Tga.native.channels(16, True{}) == 2 : U32}

law tga_native_rgb24:
  {Tga.native.channels(24, True{}) == 3 : U32}

law tga_native_rgba32:
  {Tga.native.channels(32, False{}) == 4 : U32}

# Scoped BMP effective-layout metadata and packing, not a universal codec proof.
law bmp_native_absent_alpha:
  {Bmp.native.alpha(Bmp.ChannelValue{255}) == 3 : U32}

law bmp_native_alpha_field:
  for mask: U32
  for shift: Nat
  for multiplier: U32
  for shrink: Nat
  {Bmp.native.alpha(Bmp.ChannelField{mask, shift, multiplier, shrink}) == 4 : U32}

law bmp_native_layout_alpha:
  for red: Bmp.Channel
  for green: Bmp.Channel
  for blue: Bmp.Channel
  for +alpha: Bmp.Channel
  {Bmp.native.channels(Bmp.Layout{red, green, blue, alpha}) == Bmp.native.alpha(alpha) : U32}

# Scoped PNG structural metadata/packing laws, not a universal decoder proof.
law png_native_gray:
  {Png.native.channels(0, 1, None{}, False{}) == 1 : U32}

law png_native_gray_key:
  for key: Png.Key
  {Png.native.channels(0, 1, Some{key}, False{}) == 2 : U32}

law png_native_grayalpha:
  {Png.native.channels(4, 2, None{}, False{}) == 2 : U32}

law png_native_rgb:
  {Png.native.channels(2, 3, None{}, False{}) == 3 : U32}

law png_native_rgb_key:
  for key: Png.Key
  {Png.native.channels(2, 3, Some{key}, False{}) == 4 : U32}

law png_native_palette:
  {Png.native.channels(3, 1, None{}, False{}) == 3 : U32}

law png_native_palette_trns:
  {Png.native.channels(3, 1, None{}, True{}) == 4 : U32}

law png_native_rgba:
  {Png.native.channels(6, 4, None{}, False{}) == 4 : U32}

law png_palette_trns_sticky_plte:
  for +cfg: Png.Config
  for +key: Maybe<&2, Png.Key>
  for +compressed: +List<U32>
  for +seen: Bool
  for +raw: Bool
  for +bytes: +List<U32>
  {Png.more.plte(True{}, cfg, key, True{}, compressed, seen, raw, [1, 2, 3], bytes)
    == Done{Png.More{bytes, Png.Parts{Some{cfg}, [16909311], key, True{}, compressed, seen, raw}}}
    : Result<&2, &2, Codec.Error, Png.Parsing>}

# Scoped PIC packet-union and integer packing laws, not a decoder proof.
law pic_native_mask_empty:
  for mask: U32
  {Pic.native.mask([], mask) == mask : U32}

law pic_native_mask_union:
  {Pic.native.mask([Pic.Packet{0, 128, 0}, Pic.Packet{1, 64, 0}, Pic.Packet{2, 32, 0}, Pic.Packet{0, 16, 0}], 0) == 240 : U32}

law pic_native_rgb:
  {Pic.native.channels([Pic.Packet{0, 224, 0}]) == 3 : U32}

law pic_native_alpha_first:
  {Pic.native.channels([Pic.Packet{0, 16, 0}, Pic.Packet{2, 224, 0}]) == 4 : U32}

law pic_native_alpha_middle:
  {Pic.native.channels([Pic.Packet{0, 128, 0}, Pic.Packet{1, 16, 0}, Pic.Packet{2, 224, 0}]) == 4 : U32}

law pic_native_low_bits:
  {Pic.native.channels([Pic.Packet{2, 15, 0}, Pic.Packet{1, 239, 0}]) == 3 : U32}

law pic_native_alpha_low_bits:
  {Pic.native.channels([Pic.Packet{2, 31, 0}, Pic.Packet{0, 239, 0}]) == 4 : U32}

# Native packing shared by every codec decoder (scoped facts, not a
# universal decoding theorem): channel count -> raylib format, RGBA word -> native word.
law codec_native_format_1:
  {J.Surface.codec.format(1) == 1 : U32}

law codec_native_format_2:
  {J.Surface.codec.format(2) == 2 : U32}

law codec_native_format_3:
  {J.Surface.codec.format(3) == 4 : U32}

law codec_native_format_4:
  {J.Surface.codec.format(4) == 7 : U32}

law codec_native_word_1_2155905279:
  {J.Surface.codec.word(1, 2155905279) == 128 : U32}

law codec_native_word_2_2172748032:
  {J.Surface.codec.word(2, 2172748032) == 129 : U32}

law codec_native_word_2_305419896:
  {J.Surface.codec.word(2, 305419896) == 30738 : U32}

law codec_native_word_3_305419896:
  {J.Surface.codec.word(3, 305419896) == 5649426 : U32}

law codec_native_word_3_305420031:
  {J.Surface.codec.word(3, 305420031) == 5649426 : U32}

law codec_native_pixels_zero:
  for index: U32
  for channels: U32
  for pixels: Array<U32>
  {J.Surface.codec.pixels(0n, index, channels, pixels) == pixels : Array<U32>}

law codec_native_rgba_is_canonical:
  for +width: U32
  for +height: U32
  for pixels: Array<U32>
  {J.Surface.codec.stored(4, width, height, 4, pixels) == J.Surface{width, height, 7, J.Words{pixels}} : J.Surface}

# Unified Surface: format target 0 keeps the owner; R8G8B8A8 drawing stores the
# canonical Color word; SetPixelColor leaves R32 canvases zero.
law surface_format_zero_keeps_owner:
  for width: U32
  for height: U32
  for format: U32
  for pixels: J.Surface.Pixels
  {J.Surface.format(J.Surface{width, height, format, pixels}, 0) == Done{J.Surface{width, height, format, pixels}} : Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>}

law surface_draw_word_rgba_is_color:
  for color: U32
  {J.Surface.word.draw(7, color) == color : U32}

law surface_fill_word_r32_is_zero:
  for color: U32
  {J.Surface.word.fill(8, 8, color) == 0 : U32}

# Ray collisions: explicit refusal and early-exit structure, not a numeric
# intersection theorem (the ray probe carries the differential evidence).
law ray_box_undefined_is_none:
  for arithmetic: M.Contraction
  for inside: Bool
  for hit: Bool
  for distance: F32
  for point: M.Vector3
  for normal: M.Vector3
  {J.Collision.ray.box.finish(False{}, arithmetic, inside, hit, distance, point, normal) == None{} : Maybe<J.RayCollision>}

law ray_triangle_parallel_misses:
  for arithmetic: M.Contraction
  for ray: J.Ray
  for p1: M.Vector3
  for edge1: M.Vector3
  for edge2: M.Vector3
  for p: M.Vector3
  for det: F32
  {J.Collision.ray.triangle.u(True{}, arithmetic, ray, p1, edge1, edge2, p, det) == J.RayCollision.none() : J.RayCollision}

law ray_quad_keeps_first_hit:
  for arithmetic: M.Contraction
  for ray: J.Ray
  for p2: M.Vector3
  for p3: M.Vector3
  for p4: M.Vector3
  for distance: F32
  for point: M.Vector3
  for normal: M.Vector3
  {J.Collision.ray.quad.second(arithmetic, ray, p2, p3, p4, J.RayCollision{True{}, distance, point, normal}) == J.RayCollision{True{}, distance, point, normal} : J.RayCollision}

# Stored images: copies keep every level; compressed data has no Surface levels.
law stored_copy_keeps_every_level:
  for +width: U32
  for +height: U32
  for +format: U32
  for +mipmaps: U32
  for +data: +List<U32>
  {J.Image.Stored.copy(J.Stored{width, height, format, mipmaps, data}) == (J.Stored{width, height, format, mipmaps, data}, J.Stored{width, height, format, mipmaps, data}) : J.Image.Stored & J.Image.Stored}

law stored_compressed_levels_unsupported:
  for image: J.Image.Stored
  for width: U32
  for height: U32
  for format: U32
  for count: U32
  for data: +List<U32>
  {J.Image.Stored.levels.checked(False{}, image, width, height, format, count, data) == Fail{(image, J.UnsupportedFormat{})} : Result<&1, &1, J.Image.Stored & J.Surface.Error, J.Image.Mipmaps>}

# JPEG: stb's zeroed Huffman table decodes symbol 0 without consuming bits;
# corrupt runs past coefficient 63 sample 63; coefficients wrap to 16 bits and
# signed shifts are arithmetic (concrete values, not a decoder theorem).
law jpeg_absent_table_symbol_zero:
  for buffer: U32
  {Jpg.Huff.lookup(Jpg.Absent{}, 16, buffer) == Jpg.Found{0, 0} : Jpg.Found}

law jpeg_zig_past_end:
  {Jpg.zig(70) == 63 : U32}

law jpeg_short_wraps:
  {Jpg.short(32768) == 4294934528 : U32}

law jpeg_asr_negative:
  {Jpg.asr(4294967040, 4n) == 4294967280 : U32}

# Waves are Data: a copy is the same wave twice.
law wave_copy_twice:
  for +wave: J.Wave
  {J.Wave.copy(wave) == (wave, wave) : J.Wave & J.Wave}

# qoa_encode refuses a wave without frames, whatever its samples and fields.
law qoa_encode_no_frames:
  for +samples: +List<U32>
  for +channels: U32
  for +rate: U32
  {Qoa.encode(samples, 0, channels, rate) == None{} : Maybe<&2, +List<U32>>}

# Profiles without an acosf kernel never produce a value.
law acos_apple_none:
  for +x: F32
  {M.Libm.acos(M.AppleLibm{}, x) == None{} : Maybe<F32>}

# powf exists only under the glibc 2.39 profile, for exponents 2 and 3.
law pow_apple_none:
  for +x: F32
  for +exponent: U32
  {M.Libm.pow(M.AppleLibm{}, x, exponent) == None{} : Maybe<F32>}

# asinf (src/asin.bend, glibc 2.41): |x| = 1 takes the square-root branch,
# |x| > 1 and NaN are refused; AppleLibm stops below 0x1.d12edp-12, where
# macOS asinf leaves correct rounding (exhaustive results in
# docs/INVERSE-TRIG.md). Glibc239Libm uses glibc 2.39's kernel (laws below).
law asin_region_one:
  {Asin.region(2130706432) == 3 : U32}

law asin_region_above_one:
  {Asin.region(2130706434) == 0 : U32}

law asin_region_tiny:
  {Asin.region(1929379838) == 1 : U32}

# glibc 2.39 asinf (src/lgpl/asin.bend): the source's branches at |x| = 1,
# |x| > 1, 2^-27, 0.5 and 0x3F79999A (0.975).
law glibc_asin_region_one:
  {GlibcAsin.region(3212836864) == 0 : U32}

law glibc_asin_region_above_one:
  {GlibcAsin.region(1065353217) == 1 : U32}

law glibc_asin_region_tiny:
  {GlibcAsin.region(838860799) == 2 : U32}

law glibc_asin_region_small:
  {GlibcAsin.region(1056964607) == 3 : U32}

law glibc_asin_region_near_one:
  {GlibcAsin.region(1064933786) == 4 : U32}

law glibc_asin_region_middle:
  {GlibcAsin.region(1064933785) == 5 : U32}

# Binary64 square root (src/binary64_sqrt.bend): exact roots, signed zeros
# and the refused negative input.
law sqrt_four:
  {Sqrt.checked(1074790400, 0) == Some{F.Words{1073741824, 0}} : Maybe<F.Words>}

law sqrt_negative_zero:
  {Sqrt.checked(2147483648, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law sqrt_negative_none:
  {Sqrt.checked(3220176896, 0) == None{} : Maybe<F.Words>}

# QuaternionToEuler: a quaternion with a nonfinite component fails at stage 1,
# before any arithmetic or profile kernel.
law euler_invalid_first:
  for libm: M.Libm
  for x: F32
  for y: F32
  for z: F32
  for w: F32
  {M.Quaternion.euler.valid(False{}, libm, x, y, z, w) == Fail{1} : Result<&2, &2, U32, M.Vector3>}

# Total binary32 FMA (src/fma.bend): input classification, exact significand
# products and the final nearest-even step (concrete values; the arithmetic is
# compared with fmaf by gate camera, not proven here).
law fma_kind_nan_factor:
  {Fma.kind(2143289344, 1065353216, 1065353216) == 0 : U32}

law fma_kind_zero_factor:
  {Fma.kind(0, 2139095040, 1065353216) == 0 : U32}

law fma_kind_infinite_addend:
  {Fma.kind(1065353216, 1065353216, 2139095040) == 1 : U32}

law fma_kind_zero_addend:
  {Fma.kind(1065353216, 1065353216, 0) == 2 : U32}

law fma_product_largest_significands:
  {Fma.product(16777215, 16777215) == Resize.Wide{65535, 4261412865} : Resize.Wide}

law fma_round_odd_tie_up:
  {Fma.rounded(Resize.Wide{0, 6}) == 2 : U32}

law fma_round_even_tie_kept:
  {Fma.rounded(Resize.Wide{0, 10}) == 2 : U32}

# Cameras: CAMERA_PERSPECTIVE projections are None under AppleLibm, the
# profile-free form's (Apple's binary64 tan is unpublished, M.Libm.tan is
# None for it), and the AppleLibm profile reproduces only a zero sinf/cosf
# argument.
law libm_tan_apple_none:
  for x: M.Float64
  {M.Libm.tan(M.AppleLibm{}, x) == None{} : Maybe<M.Float64>}

law camera_projection_matrix_apple:
  for camera: J.Camera3D
  for aspect: F32
  {J.Camera.projection_matrix(camera, aspect) == J.Camera.projection_matrix_for(M.AppleLibm{}, camera, aspect) : Maybe<M.Matrix>}

# Shaders on the software renderer (docs/SHADERS.md): every load fails
# (id 0, 32 locations of -1) and no shader is valid.
law shader_load_never_valid:
  for vs: Maybe<String>
  for fs: Maybe<String>
  {J.Shader.is_valid(J.Shader.load(vs, fs)) == False{} : Bool}

law shader_location_unset:
  for shader: J.Shader
  for name: String
  {J.Shader.get_location(shader, name) == 4294967295 : U32}

law camera_perspective_projection_none:
  for position: M.Vector3
  for target: M.Vector3
  for up: M.Vector3
  for fovy: F32
  for aspect: F32
  {J.Camera.projection_matrix(J.Camera3D{position, target, up, fovy, 0}, aspect) == None{} : Maybe<M.Matrix>}

law camera_apple_zero_argument_only:
  for angle: F32
  for argument: F32
  {J.Camera.turnable(M.AppleLibm{}, angle, argument) == Bool.or(F32.is_eq(argument, 0.0), False{}) : Bool}

# drwav_aiff_extented_to_s64 reads 44100 from its 80-bit extended encoding.
law wav_aiff_rate_44100:
  {Wav.aiff.rate([64, 14, 172, 68, 0, 0, 0, 0, 0, 0], 0) == Wav.Rate{0, 44100} : Wav.Rate}

# Sign set, largest exponent and significand 2^63: dr_wav negates INT64_MIN,
# which is undefined (state 3), not a rate.
law wav_aiff_rate_int64_min_undefined:
  {Wav.aiff.rate([192, 62, 128, 0, 0, 0, 0, 0, 0, 0], 0) == Wav.Rate{3, 0} : Wav.Rate}

# MS ADPCM delta adaptation saturates at 0x7FFFFFFF ...
law msadpcm_adapt_saturates:
  {Adpcm.ms.adapt(768, 2147483647) == 2147483647 : U32}

# ... and a negative header delta adapts to the floor of 16.
law msadpcm_adapt_negative_floor:
  {Adpcm.ms.adapt(230, 4294966996) == 16 : U32}

# WaveFormat (miniaudio ma_convert_frames). The resampler's output count from
# its initial state is ceil(frames * rout / rin): 3 frames at 147:160 give 4.
law wave_format_expected_frames:
  {Resampler.expected(3, 147, 160) == Some{4} : Maybe<U32>}

# Default channel maps past 8 channels: AUX_0 at index 8, NONE from index 32.
law wave_format_aux_position:
  {WaveConvert.position(9, 8) == 20 : U32}

law wave_format_none_position:
  {WaveConvert.position(40, 35) == 0 : U32}

# Mono s16 output divides the int sum by the unsigned channel count, as C's
# usual conversions make it: (-3 + 0) / 2 keeps the low 16 bits of
# 0xFFFFFFFD / 2, which is -2, not -1.
law wave_format_mono_unsigned_division:
  {WaveConvert.mono.out([4294967293, 0], False{}, 2) == [4294967294] : +List<U32>}

# The s16 filter's int32 products are checked: 2^16 * 2^15 overflows.
law wave_format_filter_overflow:
  {Resampler.mul_ok(65536, 32768) == False{} : Bool}

# Integer sample rates convert to binary64 exactly.
law wave_format_rate_double:
  {Lowpass.from_u32(44100) == Lowpass.Ok{1088784512, 0} : Lowpass.V}

# Sample sizes other than 8, 16 and 32 are refused with the wave unchanged.
law wave_format_size_refused:
  {J.Wave.format(J.Wave{2, 8000, 24, 1, [1, 2]}, 8000, 16, 1) == Fail{(J.Wave{2, 8000, 24, 1, [1, 2]}, J.InvalidWaveRequest{})} : Result<&1, &1, J.Wave & J.Wave.Error, J.Wave>}

# Frame: InitWindow sizes are 1..4096; a zero or oversized width has no frame
# whatever the height.
law frame_init_window_zero_width:
  for height: U32
  {J.Frame.init_window(0, height) == None{} : Maybe<J.Frame>}

law frame_init_window_wide:
  for height: U32
  {J.Frame.init_window(4097, height) == None{} : Maybe<J.Frame>}

# A plan with an undefined C int conversion is refused whatever it draws.
law frame_plan_refused:
  for commands: +List<FrameCore.Command>
  {Shapes.Plan.require(False{}, Shapes.Plan{True{}, commands}) == Shapes.Plan{False{}, commands} : Shapes.Plan}

# Input (CORE.Input on the memory platform). The pressed-key and char queues
# hold 16 entries (MAX_KEY_PRESSED_QUEUE, MAX_CHAR_PRESSED_QUEUE): a 17th is
# dropped.
law input_queue_bounded:
  {InputCore.queue.push(True{}, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 17)
    == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] : +List<U32>}

# A GLFW key repeat sets IsKeyPressedRepeat until the next PollInputEvents.
law input_key_repeat_set:
  {InputCore.Keyboard.is_pressed_repeat(InputCore.Keyboard.callback(InputCore.Keyboard.new(), 65, 2, 0), 65) == True{} : Bool}

law input_key_repeat_cleared:
  {InputCore.Keyboard.is_pressed_repeat(InputCore.Keyboard.poll(InputCore.Keyboard.callback(InputCore.Keyboard.new(), 65, 2, 0)), 65)
    == False{} : Bool}

# The memory platform's PollInputEvents copies previous key states for keys
# 0..259 only: key 259 stops being pressed, key 301 (F12) stays pressed.
law input_poll_copies_low_keys:
  {InputCore.Keyboard.is_pressed(InputCore.Keyboard.poll(InputCore.Keyboard.press(InputCore.Keyboard.new(), 259)), 259) == False{} : Bool}

law input_poll_keeps_high_keys:
  {InputCore.Keyboard.is_pressed(InputCore.Keyboard.poll(InputCore.Keyboard.press(InputCore.Keyboard.new(), 301)), 301) == True{} : Bool}

# rgestures.h UpdateGestures turns a tap into a hold and ends a swipe.
law gesture_tap_becomes_hold:
  {GestureCore.Gestures.current(GestureCore.update(GestureCore.Gestures.with_current(GestureCore.Gestures.new(), 1), Clock.zero())) == 4 : U32}

law gesture_swipe_ends:
  {GestureCore.Gestures.current(GestureCore.update(GestureCore.Gestures.with_current(GestureCore.Gestures.new(), 64), Clock.zero())) == 0 : U32}

# Desktop polling (rcore_desktop_glfw.c, the desktop driver) copies every
# key's previous state, F12 included, unlike the memory platform.
law desktop_poll_copies_all_keys:
  {InputCore.Keyboard.is_pressed(InputCore.Keyboard.poll_desktop(InputCore.Keyboard.press(InputCore.Keyboard.new(), 301)), 301) == False{} : Bool}

# It registers the previous mouse buttons (and touch states), so a held
# button is pressed for one frame only.
law desktop_poll_button_pressed_once:
  {InputCore.mouse.pressed(InputCore.poll_desktop(InputCore.mouse_button_callback(InputCore.Input.new(), 0, True{})), 0) == False{} : Bool}

law desktop_button_pressed:
  {InputCore.mouse.pressed(InputCore.mouse_button_callback(InputCore.Input.new(), 0, True{}), 0) == True{} : Bool}

# It resets the wheel move.
law desktop_poll_wheel_reset:
  {InputCore.MouseState.wheel(InputCore.MouseState.poll_desktop(InputCore.MouseState.set_wheel(InputCore.MouseState.new(), InputCore.Point{0.0, 1.0})))
    == InputCore.Point{0.0, 0.0} : InputCore.Point}

# Base key codes as raylib keys (docs/DRIVER.md): letters, Escape, the Mac's
# arrow and function-key characters, a modifier, a shifted US-layout symbol,
# and a code with no raylib key.
# GetScreenWidth/GetScreenHeight (and the render size) are the InitWindow size.
law desktop_screen_size:
  for +width: U32
  for +height: U32
  {(CoreState.Screen.width(CoreState.Core.window(CoreState.Core.new(width, height, Clock.zero()))),
    CoreState.Screen.height(CoreState.Core.window(CoreState.Core.new(width, height, Clock.zero())))) == (width, height) : U32 & U32}

law desktop_key_letters:
  {(J.Desktop.key(97), J.Desktop.key(122)) == (65, 90) : U32 & U32}

law desktop_key_escape:
  {J.Desktop.key(27) == 256 : U32}

law desktop_key_arrows:
  {(J.Desktop.key(63232), J.Desktop.key(63235)) == (265, 262) : U32 & U32}

law desktop_key_function:
  {(J.Desktop.key(63236), J.Desktop.key(63247)) == (290, 301) : U32 & U32}

law desktop_key_shift:
  {J.Desktop.key(65592) == 340 : U32}

law desktop_key_shifted_symbol:
  {J.Desktop.key(33) == 49 : U32}

law desktop_key_unknown:
  {J.Desktop.key(65599) == 0 : U32}

# The software renderer ignores blend modes (rlSetBlendMode is GL3-only) and
# texture wrap modes (rlsw rejects GL_CLAMP_TO_EDGE): both leave their input.
law frame_blend_mode_unchanged:
  for frame: J.Frame
  for mode: U32
  {J.Frame.begin_blend_mode(frame, mode) == frame : J.Frame}

law texture_set_wrap_unchanged:
  for texture: J.Texture
  for wrap: U32
  {J.Texture.set_wrap(texture, wrap) == texture : J.Texture}

# TEXTURE_FILTER_POINT selects nearest sampling whatever the previous filter.
law texture_filter_point:
  for linear: Bool
  {J.Texture.filter(0, linear) == False{} : Bool}

# rlsw's id pools reuse the most recently freed id first.
law texture_pool_reuses_freed:
  for next: U32
  for capacity: U32
  for id: U32
  for rest: +List<U32>
  {FrameCore.Pool.take(FrameCore.Pool{next, capacity, Con{id, rest}}) == (FrameCore.Pool{next, capacity, rest}, id) : FrameCore.Pool & U32}

# Fonts (rtext.c): GetGlyphIndex of an invalid font (baseSize <= 0 or no
# glyphs) is 0 whatever the codepoint.
law font_index_invalid:
  for glyphs: +List<FontCore.Glyph>
  for base: U32
  for padding: U32
  for cp: U32
  {FontCore.index(FontCore.Face{glyphs, base, padding, False{}}, cp) == 0 : U32}

# MeasureTextEx and MeasureTextCodepoints of no codepoints are (0, 0).
law font_measure_empty:
  for face: FontCore.Face
  for size: F32
  for spacing: F32
  for line: F32
  {FontCore.measure(Nil{}, face, size, spacing, line) == FontCore.Extent{0.0, 0.0} : FontCore.Extent}

# UnloadFont keeps the default font's texture (id 1): the frame is unchanged.
law font_unload_default:
  for frame: J.Frame
  for base: U32
  for padding: U32
  for glyphs: +List<FontCore.Glyph>
  for width: U32
  for height: U32
  for format: U32
  for linear: Bool
  for alpha: Bool
  for texels: Maybe<Array<U32>>
  for atlas: J.Surface
  {J.Font.unload(frame, J.Font{base, padding, glyphs, J.Texture{1, width, height, format, linear, alpha, texels}, atlas}) == frame : J.Frame}

# rlgl under OpenGL 1.1 (GRAPHICS_API_OPENGL_SOFTWARE): rlSetBlendMode exists
# for OpenGL 3.3/ES2 only and leaves the frame; rlGetVersion is
# RL_OPENGL_SOFTWARE; rlMatrixMode(RL_PROJECTION) selects rlsw's projection
# stack and an unknown mode selects none; rlBegin draws lines, triangles and
# quads only (RL_LINES 1 takes 2 vertices, other modes record nothing).
law rlgl_blend_mode_unchanged:
  for frame: J.Frame
  for mode: U32
  {J.Rlgl.set_blend_mode(frame, mode) == frame : J.Frame}

law rlgl_version_software:
  {J.Rlgl.get_version() == 0 : U32}

law rlgl_matrix_mode_projection:
  {J.Rlgl.mode.of(5889) == 1 : U32}

law rlgl_matrix_mode_unknown:
  {J.Rlgl.mode.of(5891) == 3 : U32}

law rlgl_begin_lines:
  {J.Rlgl.begin.count(1) == 2 : U32}

law rlgl_begin_points_ignored:
  {J.Rlgl.begin.count(0) == 0 : U32}

# Meshes (rmodels.c): GenMeshCube always has 24 vertices and 12 triangles;
# GenMeshPoly with fewer than 3 sides is the empty mesh (all arrays NULL).
law mesh_cube_vertex_count:
  for width: F32
  for height: F32
  for length: F32
  {J.Mesh.vertex_count(J.Mesh.gen_cube(width, height, length)) == 24 : U32}

law mesh_cube_triangle_count:
  for width: F32
  for height: F32
  for length: F32
  {J.Mesh.triangle_count(J.Mesh.gen_cube(width, height, length)) == 12 : U32}

law mesh_poly_degenerate_empty:
  for libm: M.Libm
  for radius: F32
  {J.Mesh.gen_poly_for(libm, 2, radius) == Some{J.Mesh.empty()} : Maybe<J.Mesh>}

# Materials on the software renderer: no material is valid (every shader id
# is 0); LoadModelFromMesh's model has the default material and uses it.
law material_never_valid:
  for material: J.Material
  {J.Material.is_valid(material) == False{} : Bool}

law model_from_mesh_material:
  for mesh: J.Mesh
  {J.Model.from_mesh(mesh) == J.Model{M.Matrix.identity(), [mesh], [J.Material.load_default()], [0]} : J.Model}

# Window state on the memory platform (docs/DRIVER.md#window-state): a Core is
# a ready window that is never resized; SetWindowState and the toggles leave
# it unchanged; one monitor; no dropped files; the flags SetConfigFlags sets
# are the ones IsWindowState reads (checked by tools/window_probe.py).
law window_ready:
  for core: J.Core
  {J.Core.is_window_ready(core) == True{} : Bool}

law window_never_resized:
  for core: J.Core
  {J.Core.is_window_resized(core) == False{} : Bool}

law window_set_state_unchanged:
  for core: J.Core
  for flags: U32
  {J.Core.set_window_state(core, flags) == core : J.Core}

law window_toggle_fullscreen_unchanged:
  for core: J.Core
  {J.Core.toggle_fullscreen(core) == core : J.Core}

law window_monitor_count_one:
  for core: J.Core
  {J.Core.get_monitor_count(core) == 1 : U32}

law window_no_dropped_files:
  for core: J.Core
  {J.Core.is_file_dropped(core) == False{} : Bool}
