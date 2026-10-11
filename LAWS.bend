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
import ./src/lgpl/tanf.bend as GlibcTanf
import ./src/lgpl/sin.bend as GlibcSin
import ./src/sincosf.bend as Sincosf
import ./src/power.bend as Power
import ./src/libc_rand.bend as CRand
import ./src/hypot.bend as Hypot
import ./src/strtod.bend as Strtod
import ./src/json.bend as Json
import ./src/gltf.bend as Gltf
import ./src/gltf_anim.bend as GltfAnim
import ./src/vox.bend as Vox
import ./src/iqm.bend as Iqm
import ./src/m3d.bend as M3d
import ./src/par_shapes.bend as ParShapes
import ./jongui.bend as JG
import ./src/gui_icons.bend as GuiIcons
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

# A file named .png (or .PNG) is read up to the PNG decoder's 2 MiB; other
# raster names keep 1 MiB. Under that name a PNG signature goes to the PNG
# decoder, and other contents keep the raster cap: more than 1 MiB of them
# is the size error it was before.
law png_file_limit:
  {J.Image.file.limit(J.PngFile{}) == 2097152 : U32}

law png_file_kind_by_name:
  {(J.Image.file.kind.of(".png"), (J.Image.file.kind.of(".PNG"), J.Image.file.kind.of(".bmp"))) == (J.PngFile{}, (J.PngFile{}, J.RasterFile{})) : J.Image.FileKind & (J.Image.FileKind & J.Image.FileKind)}

law png_file_kind_other_case_unsupported:
  {J.Image.file.kind.of(".Png") == J.UnsupportedImageFile{} : J.Image.FileKind}

law png_signature_selects_the_decoder:
  {(J.Image.file.png_signed([137, 80, 78, 71]), J.Image.file.png_signed([66, 77, 0, 0])) == (True{}, False{}) : Bool & Bool}

law file_bytes_beyond_a_count:
  {(J.Image.file.beyond(2n, [1, 2, 3]), J.Image.file.beyond(3n, [1, 2, 3])) == (True{}, False{}) : Bool & Bool}

law png_named_other_contents_over_the_raster_cap_refused:
  for reference: M.Contraction
  for bytes: List<&2, U32>
  {J.Image.file.named_png.other(True{}, reference, bytes) == Fail{J.UnsupportedImageSize{}} : Result<&1, &1, J.Surface.Error, J.Surface>}

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
# glibc 2.39/2.41 x86_64 sinf/cosf words (src/sincosf.bend): the tiny path's
# signed zero and an infinity (the reduced paths' binary64 helpers carry F32
# exponents the checker does not evaluate; the glibc-sinf gate covers them).
law glibc_sinf_negative_zero:
  {Sincosf.sinf.word(2147483648) == Some{2147483648} : Maybe<U32>}

law glibc_cosf_negative_zero:
  {Sincosf.cosf.word(2147483648) == Some{1065353216} : Maybe<U32>}

law glibc_sinf_infinity_none:
  {Sincosf.sinf.word(2139095040) == None{} : Maybe<U32>}

# (int) and (float) of a binary64 value (M.Float64.to_int, to_f32): the
# truncation toward zero as a two's-complement word (-2.5 is -2), None from
# 2^31 on, where C's conversion is undefined, and for an infinity; (float)
# of an infinity is None too.
law float64_to_int_truncates_toward_zero:
  {M.Float64.to_int(M.Float64{3221487616, 0}) == Some{4294967294} : Maybe<U32>}

law float64_to_int_2_31_none:
  {M.Float64.to_int(M.Float64{1105199104, 0}) == None{} : Maybe<U32>}

law float64_to_int_infinity_none:
  for low: U32
  {M.Float64.to_int(M.Float64{2146435072, low}) == None{} : Maybe<U32>}

law float64_to_f32_infinity_none:
  {M.Float64.to_f32(M.Float64{2146435072, 0}) == None{} : Maybe<F32>}

# glibc powf(2, y) / exp2f(y) (src/power.bend): the kernel answers a finite y
# below 126 in magnitude only; 126 and an infinity are refused (the answered
# words go through binary64 helpers the checker does not evaluate; the pow2
# gate covers them).
law glibc_pow2_126_none:
  {Power.exp2.word(1123811328) == None{} : Maybe<F32>}

law glibc_pow2_infinity_none:
  {Power.exp2.word(2139095040) == None{} : Maybe<F32>}

# glibc expf and logf (src/power.bend): expf answers below 87 in magnitude
# and refuses the two arguments at which glibc's SSE2 and FMA variants
# differ; logf answers positive normal arguments only (zero, a negative
# value and an infinity are refused). The answered words go through binary64
# helpers the checker does not evaluate; the explog gate covers them.
law glibc_expf_87_none:
  {Power.exp.word(1118699520) == None{} : Maybe<F32>}

law glibc_expf_variant_argument_none:
  {Power.exp.word(1107444271) == None{} : Maybe<F32>}

law glibc_expf_other_variant_argument_none:
  {Power.exp.word(3262932441) == None{} : Maybe<F32>}

law glibc_logf_zero_none:
  {Power.log.word(0) == None{} : Maybe<F32>}

law glibc_logf_negative_none:
  {Power.log.word(3212836864) == None{} : Maybe<F32>}

law glibc_logf_infinity_none:
  {Power.log.word(2139095040) == None{} : Maybe<F32>}

# glibc's rand() (src/libc_rand.bend): the seeds come from the minimal
# standard generator, a program that never calls srand gets 1804289383 first
# (the seed 1), a seed of 0 is the seed 1, a seed from 2^31 on is refused,
# and the Apple profile has no generator.
law glibc_rand_minimal_standard_step:
  {CRand.lcg(1) == 16807 : U32}

law glibc_rand_first_value:
  {CRand.value(CRand.seed(1)) == Some{1804289383} : Maybe<U32>}

law glibc_rand_seed_zero_is_one:
  {CRand.value(CRand.seed(0)) == Some{1804289383} : Maybe<U32>}

law glibc_rand_large_seed_none:
  {CRand.seed(2147483648) == None{} : Maybe<CRand.Rand>}

law libc_rand_apple_none:
  for seed: U32
  {M.Libc.srand(M.AppleLibm{}, seed) == None{} : Maybe<M.Libc.Rand>}

# glibc 2.39's binary64 sin and cos (src/lgpl/sin.bend, docs/MATH.md): a zero
# is its own sine and has cosine 1, infinities and NaN are refused, a
# quadrant is an int below 2^31, and only the glibc 2.39 profile answers.
law glibc_sin_of_zero:
  {GlibcSin.sin(0, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law glibc_sin_of_negative_zero:
  {GlibcSin.sin(2147483648, 0) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law glibc_cos_of_zero:
  {GlibcSin.cos(0, 0) == Some{F.Words{1072693248, 0}} : Maybe<F.Words>}

law glibc_sin_of_infinity_refused:
  {GlibcSin.sin(2146435072, 0) == None{} : Maybe<F.Words>}

law glibc_cos_of_nan_refused:
  for low: U32
  {GlibcSin.cos(2146959360, low) == None{} : Maybe<F.Words>}

law glibc_sin_quadrant_of_minus_three:
  {GlibcSin.quadrant.words(3221749760, 0) == 1 : U32}

law glibc_sin_quadrant_past_int_refused:
  for low: U32
  {GlibcSin.quadrant.words(1105199104, low) == 4 : U32}

# The binary64 operators around them (M.Float64.internal.add,
# subtract and divide): 1 + 1 is 2, 3 - 1 is 2, 0/3 is 0, and a zero divisor
# and an infinite operand are refused.
law float64_one_plus_one:
  {M.Float64.internal.add(M.Float64{1072693248, 0}, M.Float64{1072693248, 0}) == Some{M.Float64{1073741824, 0}} : Maybe<M.Float64>}

law float64_three_minus_one:
  {M.Float64.internal.subtract(M.Float64{1074266112, 0}, M.Float64{1072693248, 0}) == Some{M.Float64{1073741824, 0}} : Maybe<M.Float64>}

law float64_zero_by_three:
  {M.Float64.internal.divide(M.Float64{0, 0}, M.Float64{1074266112, 0}) == Some{M.Float64{0, 0}} : Maybe<M.Float64>}

law float64_divide_by_zero_refused:
  {M.Float64.internal.divide(M.Float64{1072693248, 0}, M.Float64{0, 0}) == None{} : Maybe<M.Float64>}

law float64_add_infinity_refused:
  {M.Float64.internal.add(M.Float64{2146435072, 0}, M.Float64{1072693248, 0}) == None{} : Maybe<M.Float64>}

law glibc_sin64_apple_refused:
  for value: M.Float64
  {M.Libm.sin64(M.AppleLibm{}, value) == None{} : Maybe<M.Float64>}

law glibc_cos64_glibc241_refused:
  for value: M.Float64
  {M.Libm.cos64(M.Glibc241Libm{}, value) == None{} : Maybe<M.Float64>}

# glibc 2.39's tanf (src/lgpl/tanf.bend, docs/MATH.md): infinities and NaN are
# refused; glibc 2.41's tanf is another algorithm and Apple's is not modeled,
# so those profiles answer nothing.
law glibc_tanf_infinity_none:
  {GlibcTanf.tanf.word(2139095040) == None{} : Maybe<U32>}

law glibc_tanf_nan_none:
  {GlibcTanf.tanf.word(2143289344) == None{} : Maybe<U32>}

law glibc241_tanf_none:
  for x: F32
  {M.Libm.tanf(M.Glibc241Libm{}, x) == None{} : Maybe<F32>}

law apple_tanf_none:
  for x: F32
  {M.Libm.tanf(M.AppleLibm{}, x) == None{} : Maybe<F32>}

# strtod (src/strtod.bend, docs/MATH.md): 1 is 0x3ff0000000000000; 0.1 rounds
# to 0x3fb999999999999a; 2^53 + 1 and 2^53 + 3, halfway between two doubles,
# go to the even one (2^53 and 2^53 + 4); a sign, a fraction and an exponent
# combine; -0 keeps its sign; twenty significant digits, a leading plus and
# an exponent without digits are refused.
law strtod_one:
  {Strtod.double([49]) == Some{F.Words{1072693248, 0}} : Maybe<F.Words>}

law strtod_tenth:
  {Strtod.double([48, 46, 49]) == Some{F.Words{1069128089, 2576980378}} : Maybe<F.Words>}

law strtod_tie_to_even:
  {Strtod.double([57, 48, 48, 55, 49, 57, 57, 50, 53, 52, 55, 52, 48, 57, 57, 51]) == Some{F.Words{1128267776, 0}} : Maybe<F.Words>}

law strtod_tie_to_even_up:
  {Strtod.double([57, 48, 48, 55, 49, 57, 57, 50, 53, 52, 55, 52, 48, 57, 57, 53]) == Some{F.Words{1128267776, 2}} : Maybe<F.Words>}

law strtod_exponent:
  {Strtod.double([45, 49, 46, 50, 53, 101, 45, 51]) == Some{F.Words{3209984737, 1202590843}} : Maybe<F.Words>}

law strtod_negative_zero:
  {Strtod.double([45, 48]) == Some{F.Words{2147483648, 0}} : Maybe<F.Words>}

law strtod_twenty_digits_none:
  {Strtod.double([49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48]) == None{} : Maybe<F.Words>}

law strtod_plus_none:
  {Strtod.double([43, 49]) == None{} : Maybe<F.Words>}

law strtod_empty_exponent_none:
  {Strtod.double([49, 101]) == None{} : Maybe<F.Words>}

# JSON (src/json.bend) and binary glTF (src/gltf.bend, docs/MODELS.md): an
# empty array, a number kept as written and an object's member parse; a
# trailing comma, a second top-level value, an unterminated string and a
# colon inside an array do not. glTF integers are plain digits (a sign makes
# one unreadable), TEXCOORD_1's set index is 1, and a file without the
# container's header is refused.
law json_empty_array:
  {Json.parse([91, 93]) == Some{Json.JArray{Nil{}}} : Maybe<&2, Json.Json>}

law json_number_kept_as_written:
  {Json.parse([91, 49, 46, 53, 101, 51, 93]) == Some{Json.JArray{[Json.JNumber{[49, 46, 53, 101, 51]}]}} : Maybe<&2, Json.Json>}

law json_object_member:
  {Json.parse([123, 34, 97, 34, 58, 32, 116, 114, 117, 101, 125]) == Some{Json.JObject{[Json.JMember{[97], Json.JBool{True{}}}]}} : Maybe<&2, Json.Json>}

law json_trailing_comma_none:
  {Json.parse([91, 49, 44, 93]) == None{} : Maybe<&2, Json.Json>}

law json_two_values_none:
  {Json.parse([49, 32, 50]) == None{} : Maybe<&2, Json.Json>}

law json_unterminated_string_none:
  {Json.parse([34, 97]) == None{} : Maybe<&2, Json.Json>}

law json_colon_in_array_none:
  {Json.parse([91, 34, 97, 34, 58, 49, 93]) == None{} : Maybe<&2, Json.Json>}

law gltf_integer_digits:
  {Gltf.digits([53, 49, 50, 54], 0, 0) == 5126 : U32}

law gltf_negative_integer_bad:
  {Gltf.digits([45, 49], 0, 0) == 4294967295 : U32}

law gltf_attribute_index:
  {Gltf.attribute.index([49], 0) == 1 : U32}

law gltf_empty_file_none:
  {Gltf.glb(Nil{}) == None{} : Maybe<Gltf.Parts>}

# A skinned file's JOINTS_n attribute is recognized (and then checked, not
# kept); an index at or past its array's size fails the file as cgltf's
# fixup does; a material with another texture kind is refused, and its base
# color image's bytes are kept otherwise.
law gltf_joints_attribute_kind:
  {Gltf.attribute.kind([74, 79, 73, 78, 84, 83, 95, 48]) == 6 : U32}

law gltf_index_past_array_refused:
  {Gltf.each.below([Json.JNumber{[52]}], 4) == False{} : Bool}

law gltf_other_texture_kind_refused:
  {Gltf.look.with(4294967295, True{}, Gltf.Words{True{}, Nil{}}) == Gltf.Look{False{}, 4294967295, Nil{}} : Gltf.Look}

law gltf_base_color_image_kept:
  {Gltf.look.with(255, False{}, Gltf.Words{True{}, [137, 80]}) == Gltf.Look{True{}, 255, [137, 80]} : Gltf.Look}

# MagicaVoxel files (src/vox.bend, docs/MODELS.md): LoadModel routes ".vox"
# to LoadVOX whatever the last test says; the array's sizes are padded to
# chunks of 16; a voxel's cell is (x*sizeZ + (sizeZ - y - 1))*sizeY + z with
# its id in the low byte, and a voxel outside the sizes fails the file; a
# quad's indices are 0 2 1 and 0 3 2; 189232 vertices make meshes of 65532,
# 65532 and 58168. An empty file and another magic or version are the empty
# model (Foreign); a magic or a header cut short, and a file without a
# voxel, are refused (Unread).
law vox_extension_routed:
  for iqm: Maybe<Bool>
  for m3d: Maybe<Bool>
  for other: Maybe<Bool>
  {J.Model.load.kind.of(Some{False{}}, Some{False{}}, Some{True{}}, iqm, m3d, other) == 5 : U32}

law vox_size_padded:
  {Vox.padded(20) == 32 : U32}

law vox_size_of_chunks_kept:
  {Vox.padded(16) == 16 : U32}

law vox_chunk_names:
  {(Vox.kind(1163544915), (Vox.kind(1230657880), (Vox.kind(1094862674), Vox.kind(1313423693)))) == (1, (2, (3, 0))) : U32 & (U32 & (U32 & U32))}

law vox_voxel_cell:
  {Vox.voxels(1n, [1, 2, 3, 7], 16, 16, 16, True{}, Nil{}) == Vox.Sets{True{}, [119559], Nil{}} : Vox.Sets}

law vox_voxel_outside_fails:
  {Vox.voxels(1n, [16, 2, 3, 7], 16, 16, 16, True{}, Nil{}) == Vox.Sets{False{}, [1102599], Nil{}} : Vox.Sets}

law vox_voxel_cut_short_fails:
  {Vox.voxels(1n, [1, 2, 3], 16, 16, 16, True{}, Nil{}) == Vox.Sets{False{}, Nil{}, Nil{}} : Vox.Sets}

law vox_quad_indices:
  {Vox.indices(2n, 2, Nil{}) == [0, 2, 1, 0, 3, 2, 4, 6, 5, 4, 7, 6] : List<&2, U32>}

law vox_mesh_vertex_counts:
  {(Vox.count.of(0, 189232), (Vox.count.of(1, 189232), Vox.count.of(2, 189232))) == (65532, (65532, 58168)) : U32 & (U32 & U32)}

law vox_empty_file_foreign:
  {Vox.load(Nil{}) == Vox.Foreign{} : Vox.Loaded}

law vox_other_magic_foreign:
  {Vox.load([86, 79, 88, 33, 150, 0, 0, 0]) == Vox.Foreign{} : Vox.Loaded}

law vox_other_version_foreign:
  {Vox.load([86, 79, 88, 32, 151, 0, 0, 0]) == Vox.Foreign{} : Vox.Loaded}

law vox_magic_cut_short_unread:
  {Vox.load([86, 79, 88]) == Vox.Unread{} : Vox.Loaded}

law vox_version_cut_short_unread:
  {Vox.load([86, 79, 88, 32, 150, 0]) == Vox.Unread{} : Vox.Loaded}

law vox_chunk_header_cut_short_unread:
  {Vox.load([86, 79, 88, 32, 150, 0, 0, 0, 77, 65, 73, 78, 0]) == Vox.Unread{} : Vox.Loaded}

law vox_without_voxels_unread:
  {Vox.load([86, 79, 88, 32, 200, 0, 0, 0]) == Vox.Unread{} : Vox.Loaded}

# The four bytes a palette leaves before the end of a file that ends with it
# are a chunk header cut short; a chunk whose size passes the end of the
# file ends the reading with what was read.
law vox_four_bytes_left_halt:
  for read: Vox.Read
  {Vox.chunk([1, 2, 3, 4], read) == Vox.Halt{} : Vox.Step}

law vox_chunk_past_the_end_ends:
  {Vox.chunk([77, 65, 84, 76, 160, 15, 0, 0, 0, 0, 0, 0, 1, 2], Vox.Read{16, 16, 16, [7], [0]}) == Vox.Next{Nil{}, Vox.Read{16, 16, 16, [7], [0]}} : Vox.Step}

# Inter-Quake Model files (src/iqm.bend, docs/MODELS.md): LoadModel routes
# ".iqm" to LoadIQM, and the skeleton and the animations of an ".iqm" file
# are its own. An empty file is the empty model without animations; a file
# shorter than the magic is refused. An array lies inside the file when its
# last byte does; a mesh's triangles have their corners reversed and
# rebased on its first vertex as unsigned shorts; a name is the bytes
# before the NUL among the 32 the loader copies; a material's name must be
# a file name; a pose's parent is a pose or negative.
law iqm_extension_routed:
  for m3d: Maybe<Bool>
  for other: Maybe<Bool>
  {J.Model.load.kind.of(Some{False{}}, Some{False{}}, Some{False{}}, Some{True{}}, m3d, other) == 6 : U32}

law iqm_skeleton_and_animations_routed:
  for m3d: Maybe<Bool>
  {J.Model.anim.kind(Some{False{}}, Some{True{}}, m3d) == 2 : U32}

law iqm_empty_file_foreign:
  {Iqm.model(Nil{}) == Iqm.Foreign{} : Iqm.Loaded}

law iqm_empty_file_no_animations:
  {Iqm.animations(Nil{}) == Iqm.Animations{Nil{}} : Iqm.Animated}

law iqm_magic_cut_short_unread:
  {Iqm.model([73, 78, 84, 69, 82]) == Iqm.Unread{} : Iqm.Loaded}

law iqm_array_inside:
  {(Iqm.inside(100, 3, 4, 112), Iqm.inside(100, 4, 4, 112)) == (True{}, False{}) : Bool & Bool}

law iqm_empty_array_past_the_end_outside:
  {Iqm.inside(113, 0, 4, 112) == False{} : Bool}

law iqm_triangle_reversed_and_rebased:
  {Iqm.indices(1n, [10, 11, 12], 10, Nil{}) == [2, 1, 0] : List<&2, U32>}

law iqm_corner_below_first_vertex_wraps:
  {Iqm.indices(1n, [3, 4, 2], 3, Nil{}) == [65535, 1, 0] : List<&2, U32>}

law iqm_name_before_its_nul:
  {Iqm.named.go(32n, [97, 98, 0, 99], Nil{}) == Iqm.Named{True{}, [97, 98]} : Iqm.Named}

law iqm_name_without_nul_refused:
  {Iqm.named.go(2n, [97, 98, 99], Nil{}) == Iqm.Named{False{}, Nil{}} : Iqm.Named}

law iqm_material_must_name_a_file:
  {(Iqm.texture.named(Nil{}), (Iqm.texture.named([47, 97]), Iqm.texture.named([97, 46, 112]))) == (False{}, (False{}, True{})) : Bool & (Bool & Bool)}

law iqm_pose_parents:
  {(Iqm.parented([4294967295, 0, 1], 3), Iqm.parented([4294967295, 0, 3], 3)) == (True{}, False{}) : Bool & Bool}

# Model 3D files (src/m3d.bend, docs/MODELS.md): LoadModel routes ".m3d" to
# LoadM3D and its skeleton and animations are the file's. The header's types
# word gives each index two bits (a size of 1, 2, 4 or 8 bytes; 8 means none
# for the optional ones); an index of one byte reads 254 and 255 as -2 and
# -1, one of two bytes 65534 and 65535 likewise; a mesh record's high nibble
# is its corner count (0 a selection, 3 a face, another the end); material
# properties 0 to 8 and 64 to 68 have a format and the rest below 128 are
# unknown; a color's bytes are r, g, b, a in memory. An empty file gives no
# model and no animations; a magic cut short is refused.
law m3d_extension_routed:
  for other: Maybe<Bool>
  {J.Model.load.kind.of(Some{False{}}, Some{False{}}, Some{False{}}, Some{False{}}, Some{True{}}, other) == 7 : U32}

law m3d_skeleton_and_animations_routed:
  {J.Model.anim.kind(Some{False{}}, Some{False{}}, Some{True{}}) == 4 : U32}

law m3d_index_sizes:
  {(M3d.sized(1859860, 0, False{}), (M3d.sized(1859860, 2, False{}), (M3d.sized(1859860, 12, False{}), M3d.sized(1859860, 18, True{})))) == (1, (2, (4, 0))) : U32 & (U32 & (U32 & U32))}

law m3d_index_one_byte_signed_at_the_top:
  {M3d.index(1, [255, 7], 0) == M3d.Index{True{}, 4294967295, [7]} : M3d.Index}

law m3d_index_one_byte_plain:
  {M3d.index(1, [253, 7], 0) == M3d.Index{True{}, 253, [7]} : M3d.Index}

law m3d_index_two_bytes_signed_at_the_top:
  {M3d.index(2, [254, 255], 0) == M3d.Index{True{}, 4294967294, Nil{}} : M3d.Index}

law m3d_index_cut_short:
  {M3d.index(4, [1, 2, 3], 9) == M3d.Index{False{}, 9, Nil{}} : M3d.Index}

law m3d_index_absent_keeps_its_value:
  {M3d.index(0, [5], 9) == M3d.Index{True{}, 9, [5]} : M3d.Index}

law m3d_record_kinds:
  {(M3d.record.kind(0), (M3d.record.kind(50), M3d.record.kind(67))) == (0, (1, 2)) : U32 & (U32 & U32)}

law m3d_property_formats:
  {(M3d.format(0), (M3d.format(3), (M3d.format(8), (M3d.format(66), M3d.format(9))))) == (0, (4, (1, (4, 9)))) : U32 & (U32 & (U32 & (U32 & U32)))}

law m3d_color_bytes:
  {J.Model.m3d.color(4279312947) == 857870847 : U32}

law m3d_empty_file_no_model:
  {M3d.model(Nil{}) == M3d.Empty{} : M3d.Loaded}

law m3d_empty_file_no_animations:
  {M3d.animations(Nil{}) == M3d.Animations{Nil{}} : M3d.Animated}

law m3d_magic_cut_short_refused:
  {M3d.model([51, 68, 77]) == M3d.Refused{} : M3d.Loaded}

law m3d_other_magic_no_model:
  {M3d.model([51, 100, 109, 111, 10]) == M3d.Empty{} : M3d.Loaded}

# Skeletons and animations (src/gltf_anim.bend): a joint's place among the
# joints is its bone index and a node outside them has none (-1); a time
# with no key pair reads key 0; bytes that are not a .glb file give neither
# a skeleton nor animations.
law gltf_anim_joint_place:
  {GltfAnim.find([5, 7, 9], 7, 0) == 1 : U32}

law gltf_anim_node_outside_skeleton:
  {GltfAnim.find([5, 7, 9], 6, 0) == 4294967295 : U32}

law gltf_anim_no_key_pair_reads_first:
  for time: F32
  {GltfAnim.key.index(GltfAnim.key(Nil{}, time, 0, 0.0, 0.0)) == 0 : U32}

law gltf_anim_empty_file_no_skeleton:
  {GltfAnim.skeleton(Nil{}) == None{} : Maybe<GltfAnim.Skeleton>}

law gltf_anim_empty_file_no_animations:
  for libm: M.Libm
  {GltfAnim.animations(Nil{}, libm) == None{} : Maybe<+List<GltfAnim.Animation>>}

# The BIN chunk in blocks: a window starts at its byte, a span without
# elements needs no bytes and one that is not valid reads none.
law gltf_anim_window_starts_at_byte:
  {GltfAnim.window(GltfAnim.blocks(1n, [1, 2, 3, 4]), 1, 2) == [2, 3, 4] : +List<U32>}

law gltf_anim_empty_span_needs_nothing:
  for step: U32
  for comps: U32
  for limit: U32
  {GltfAnim.needed(step, 0, comps, limit) == 0 : U32}

law gltf_anim_invalid_span_reads_nothing:
  for span: Gltf.Span
  for blocks: +List<+List<U32>>
  for comps: U32
  for limit: U32
  {GltfAnim.read(False{}, span, blocks, comps, limit) == Nil{} : +List<U32>}

# GenMeshCylinder and GenMeshCone (src/par_shapes.bend): a disk is a fan
# around its first point, a merged mesh's triangles are offset by the
# points before them, fewer than 3 slices give the empty mesh, and the
# contracted arithmetic is refused.
law par_shapes_disk_is_a_fan:
  {ParShapes.disk.tris(3n, 0, 3, Nil{}) == [0, 1, 2, 0, 2, 3, 0, 3, 1] : +List<U32>}

law par_shapes_merge_offsets_triangles:
  {ParShapes.offset.tris([0, 1, 2], 5, Nil{}) == [5, 6, 7] : +List<U32>}

law mesh_cylinder_of_two_slices_is_empty:
  for arithmetic: M.Contraction
  for libm: M.Libm
  for radius: F32
  for height: F32
  {J.Mesh.gen_cylinder_for(arithmetic, libm, radius, height, 2) == Some{J.Mesh.empty()} : Maybe<J.Mesh>}

law mesh_cone_fused_refused:
  for radius: F32
  for height: F32
  {J.Mesh.gen_cone_for(M.Fused{}, M.Glibc239Libm{}, radius, height, 8) == None{} : Maybe<J.Mesh>}

# GenMeshKnot: fewer than 3 sides give the empty mesh, and the contracted
# arithmetic is refused.
law mesh_knot_of_two_sides_is_empty:
  for arithmetic: M.Contraction
  for libm: M.Libm
  for radius: F32
  for size: F32
  for rad_seg: U32
  {J.Mesh.gen_knot_for(arithmetic, libm, radius, size, rad_seg, 2) == Some{J.Mesh.empty()} : Maybe<J.Mesh>}

law mesh_knot_fused_refused:
  for radius: F32
  for size: F32
  {J.Mesh.gen_knot_for(M.Fused{}, M.Glibc239Libm{}, radius, size, 8, 8) == None{} : Maybe<J.Mesh>}

# A joint's node transform is read once for the keyframes: no joints have
# none, and a bone whose node or channels cannot be read ends the pose.
law gltf_anim_no_joints_no_rest:
  for nodes: +List<Json.Json>
  {GltfAnim.rests(Nil{}, nodes) == Nil{} : +List<GltfAnim.Rest>}

law gltf_anim_unreadable_bone_ends_pose:
  for base: GltfAnim.Rest
  for tracks: GltfAnim.Tracks
  for time: F32
  for libm: M.Libm
  for rest: GltfAnim.Posed
  {GltfAnim.bone.posed(False{}, base, tracks, time, libm, rest) == GltfAnim.Posed{False{}, Nil{}} : GltfAnim.Posed}

# Model poses (UpdateModelAnimation and UpdateModelAnimationEx): a loaded
# model has zeroed transforms and identity matrices; the pose comes back as
# it is for a skeleton without bones and an animation without keyframes,
# blended or not; a call that is undefined natively answers nothing, and a
# blended animation has no keyframe for a frame outside an int.
law model_pose_loaded_is_zeroed_with_identities:
  for name: String
  for parent: U32
  for binds: +List<J.Transform>
  {J.Model.pose(J.ModelSkeleton{Con{J.BoneInfo{name, parent}, Nil{}}, binds}) == J.ModelPose{Con{J.Transform{M.Vector3{0.0, 0.0, 0.0}, M.Vector4{0.0, 0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}}, Nil{}}, Con{M.Matrix.identity(), Nil{}}} : J.ModelPose}

law model_pose_boneless_unchanged:
  for libm: M.Libm
  for binds: +List<J.Transform>
  for name: String
  for bones: U32
  for count: U32
  for poses: +List<+List<J.Transform>>
  for frame: F32
  for pose: J.ModelPose
  {J.Model.update_animation_for(libm, J.ModelSkeleton{Nil{}, binds}, J.ModelAnimation{name, bones, count, poses}, frame, pose) == Some{pose} : Maybe<J.ModelPose>}

law model_pose_no_keyframes_unchanged:
  for libm: M.Libm
  for bone: String
  for parent: U32
  for binds: +List<J.Transform>
  for name: String
  for bones: U32
  for poses: +List<+List<J.Transform>>
  for frame: F32
  for pose: J.ModelPose
  {J.Model.update_animation_for(libm, J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, bones, 0, poses}, frame, pose) == Some{pose} : Maybe<J.ModelPose>}

law model_pose_undefined_call_answers_nothing:
  for libm: M.Libm
  for binds: +List<J.Transform>
  for poses: +List<+List<J.Transform>>
  for count: U32
  for frame: F32
  for pose: J.ModelPose
  {J.Model.pose.updated(1, libm, binds, poses, count, frame, pose) == None{} : Maybe<J.ModelPose>}

law model_pose_blend_boneless_unchanged:
  for libm: M.Libm
  for binds: +List<J.Transform>
  for name: String
  for bones: U32
  for count: U32
  for poses: +List<+List<J.Transform>>
  for first: F32
  for second: F32
  for blend: F32
  for pose: J.ModelPose
  {J.Model.update_animation_ex_for(libm, J.ModelSkeleton{Nil{}, binds}, J.ModelAnimation{name, bones, count, poses}, first, J.ModelAnimation{name, bones, count, poses}, second, blend, pose) == Some{pose} : Maybe<J.ModelPose>}

law model_pose_blend_no_keyframes_unchanged:
  for libm: M.Libm
  for bone: String
  for parent: U32
  for binds: +List<J.Transform>
  for name: String
  for bones: U32
  for count: U32
  for poses: +List<+List<J.Transform>>
  for first: F32
  for second: F32
  for blend: F32
  for pose: J.ModelPose
  {J.Model.update_animation_ex_for(libm, J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, bones, 0, poses}, first, J.ModelAnimation{name, bones, count, poses}, second, blend, pose) == Some{pose} : Maybe<J.ModelPose>}

law model_pose_blend_frame_outside_int_refused:
  for frame: F32
  for count: U32
  {J.Model.pose.start(False{}, frame, count) == 4294967295 : U32}

# IsModelAnimationValid compares bone counts.
law model_animation_valid_same_bone_count:
  for bone: String
  for parent: U32
  for binds: +List<J.Transform>
  for name: String
  for count: U32
  for poses: +List<+List<J.Transform>>
  {J.Model.is_animation_valid(J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, 1, count, poses}) == True{} : Bool}

law model_animation_invalid_other_bone_count:
  for bone: String
  for parent: U32
  for binds: +List<J.Transform>
  for name: String
  for count: U32
  for poses: +List<+List<J.Transform>>
  {J.Model.is_animation_valid(J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, 2, count, poses}) == False{} : Bool}

# hypot(x, y) <= r for every faithful hypot (src/hypot.bend), from the order
# of the rounded x*x + y*y and r*r (0 equal, 1 less, 2 greater, 3 unknown):
# a sum below r*r is inside; a sum rounded onto r*r is inside unless its
# rounding error shows it above; a sum above r*r is outside only from
# r*r*(1 + 2^-50) on and refused below it (two faithful results could
# disagree there). A negative r is below every finite distance; a NaN, an
# infinity or any operand outside the checked range is refused.
law hypot_within_below_inside:
  for error: U32
  for limit: U32
  {Hypot.within.ordered(1, error, limit) == Some{True{}} : Maybe<Bool>}

law hypot_within_exact_inside:
  for limit: U32
  {Hypot.within.ordered(0, 0, limit) == Some{True{}} : Maybe<Bool>}

law hypot_within_rounded_down_onto_none:
  for limit: U32
  {Hypot.within.ordered(0, 1, limit) == None{} : Maybe<Bool>}

law hypot_within_band_none:
  for error: U32
  {Hypot.within.ordered(2, error, 1) == None{} : Maybe<Bool>}

law hypot_within_past_band_outside:
  for error: U32
  {Hypot.within.ordered(2, error, 2) == Some{False{}} : Maybe<Bool>}

law hypot_within_unknown_order_none:
  for error: U32
  for limit: U32
  {Hypot.within.ordered(3, error, limit) == None{} : Maybe<Bool>}

law hypot_within_negative_radius_outside:
  for xh: U32
  for xl: U32
  for yh: U32
  for yl: U32
  for rh: U32
  for rl: U32
  {Hypot.within.finite(True{}, Hypot.Ok{xh, xl}, Hypot.Ok{yh, yl}, Hypot.Ok{rh, rl}) == Some{False{}} : Maybe<Bool>}

law hypot_within_nan_none:
  {Hypot.within.word(2143289344, 0, 1065353216) == None{} : Maybe<Bool>}

law hypot_within_infinities_none:
  {Hypot.within.word(2139095040, 4286578688, 2139095040) == None{} : Maybe<Bool>}

# Programs (docs/DRIVER.md): before a frame, a closing loop draws nothing more
# and keeps what it has drawn; a Program's loop closes on the window's close
# request, an Until program's on its own condition only.
law replay_closing_stops:
  for update: J.Core -> Unit -> J.Core & Unit
  for draw: J.Core -> Unit -> J.Frame -> J.Core & (Unit & J.Frame)
  for show: J.Frame -> J.Frame & String
  for spec: J.ReplayFrame
  for core: J.Core
  for frame: J.Frame
  for out: List<String>
  {J.Replay.open(Unit, True{}, update, draw, show, spec, core, frame, Unit{}, out) == J.Stopped{out} : J.Replay<Unit>}

law replay_until_uses_its_condition:
  for update: J.Core -> Unit -> J.Core & Unit
  for draw: J.Core -> Unit -> J.Frame -> J.Core & (Unit & J.Frame)
  for show: J.Frame -> J.Frame & String
  for spec: J.ReplayFrame
  for core: J.Core
  for frame: J.Frame
  for out: List<String>
  {J.Replay.entered(Unit, J.Until{update, draw, state => (state, True{})}, show, spec, core, frame, Unit{}, out) == J.Stopped{out} : J.Replay<Unit>}

# Programs whose loop does IO (J.Effects, docs/DRIVER.md): the pure replay
# cannot run one and says so at once; the IO replay stops a closing loop
# before its update like the pure one, and runs no `after` for a run that
# stopped; the desktop driver runs `after` once a frame was presented, not
# before the first one.
law replay_effects_needs_io:
  for update: J.Core -> Unit -> J.Frame -> IO(J.Core & (Unit & J.Frame))
  for draw: J.Core -> Unit -> J.Frame -> J.Core & (Unit & J.Frame)
  for after: J.Core -> Unit -> J.Frame -> IO(J.Core & (Unit & J.Frame))
  for show: J.Frame -> J.Frame & String
  for spec: J.ReplayFrame
  for core: J.Core
  for frame: J.Frame
  for out: List<String>
  {J.Replay.entered(Unit, J.Effects{update, draw, after}, show, spec, core, frame, Unit{}, out) == J.Stopped{Con{"null", out}} : J.Replay<Unit>}

law replay_io_closing_stops:
  for update: J.Core -> Unit -> J.Frame -> IO(J.Core & (Unit & J.Frame))
  for draw: J.Core -> Unit -> J.Frame -> J.Core & (Unit & J.Frame)
  for after: J.Core -> Unit -> J.Frame -> IO(J.Core & (Unit & J.Frame))
  for show: J.Frame -> J.Frame & String
  for spec: J.ReplayFrame
  for core: J.Core
  for frame: J.Frame
  for out: List<String>
  {J.Replay.io.open(Unit, True{}, update, draw, after, show, spec, core, frame, Unit{}, out) == IO.pure(J.Replay<Unit>, J.Stopped{out}) : IO(J.Replay<Unit>)}

law replay_io_no_after_once_stopped:
  for after: J.Core -> Unit -> J.Frame -> IO(J.Core & (Unit & J.Frame))
  for out: List<String>
  {J.Replay.io.after(Unit, after, J.Stopped{out}) == IO.pure(J.Replay<Unit>, J.Stopped{out}) : IO(J.Replay<Unit>)}

law desktop_effects_no_after_before_the_first_frame:
  for render: U32
  for present: U32
  for wait: U32
  for mark: Nat
  {J.Desktop.unstarted(J.DesktopStats{0, render, present, wait, mark}) == True{} : Bool}

law desktop_effects_after_once_a_frame_was_presented:
  for render: U32
  for present: U32
  for wait: U32
  for mark: Nat
  {J.Desktop.unstarted(J.DesktopStats{1, render, present, wait, mark}) == False{} : Bool}

# The desktop's wall clock is an argument (Base has none): without
# arguments the frame limit and the time are 0, the two flags are told apart
# and each takes the number after it.
law desktop_clock_args_default:
  {J.Desktop.clock_args(Nil{}) == (0, 0) : U32 & U32}

law desktop_clock_args_frames_flag:
  {J.Desktop.clock_args.flag("--frames") == 1 : U32}

law desktop_clock_args_time_flag:
  {J.Desktop.clock_args.flag("--time") == 2 : U32}

law desktop_clock_args_other_argument:
  {J.Desktop.clock_args.flag("--times") == 0 : U32}

law desktop_clock_args_end_of_arguments:
  for frames: U32
  for time: U32
  {J.Desktop.clock_args.go(Nil{}, 2, frames, time) == (frames, time) : U32 & U32}

law desktop_clock_args_reads_both:
  {J.Desktop.clock_args(Con{"--frames", Con{"3", Con{"--time", Con{"50398", Nil{}}}}}) == (3, 50398) : U32 & U32}

law desktop_clock_args_last_time_counts:
  {J.Desktop.clock_args(Con{"--time", Con{"7", Con{"--time", Con{"86399", Nil{}}}}}) == (0, 86399) : U32 & U32}

# Jongui (raygui): the default style, GuiSetStyle's propagation of a DEFAULT
# base property (and only those), and GuiEnable/GuiDisable.
law gui_default_text_size:
  {JG.Gui.get_style(JG.Gui.new(), 0, 16) == 10 : U32}

law gui_default_button_border:
  {JG.Gui.get_style(JG.Gui.new(), 2, 12) == 2 : U32}

law gui_default_property_propagates:
  {JG.Gui.get_style(JG.Gui.set_style(JG.Gui.new(), 0, 12, 7), 4, 12) == 7 : U32}

law gui_extended_property_stays:
  {JG.Gui.get_style(JG.Gui.set_style(JG.Gui.new(), 0, 16, 20), 4, 16) == 16 : U32}

law gui_disable_then_enable:
  for gui: JG.Gui
  {JG.Gui.get_state(JG.Gui.enable(JG.Gui.disable(JG.Gui.set_state(gui, 0)))) == 0 : U32}

law gui_disable_keeps_focus:
  for gui: JG.Gui
  {JG.Gui.get_state(JG.Gui.disable(JG.Gui.set_state(gui, 1))) == 1 : U32}

# GuiLine and GuiGroupBox draw in DEFAULT's LINE_COLOR (property 18), and in
# its BORDER_COLOR_DISABLED (9) when the gui is disabled.
law gui_line_color_property:
  {JG.Gui.line.property(0) == 18 : U32}

law gui_line_color_focused_property:
  {JG.Gui.line.property(1) == 18 : U32}

law gui_line_color_disabled_property:
  {JG.Gui.line.property(3) == 9 : U32}

# Jongui icons. GetTextIcon: a line starting with '#', up to three digits and
# '#' names an icon and its text follows ("##" is icon 0); anything else is
# text (id 4294967295).
law gui_icon_prefix:
  {JG.Gui.icon.of([35, 49, 49, 56, 35, 97]) == JG.GuiIcon{118, [97]} : JG.Gui.Icon}

law gui_icon_empty_id:
  {JG.Gui.icon.of([35, 35]) == JG.GuiIcon{0, []} : JG.Gui.Icon}

law gui_icon_unclosed_is_text:
  {JG.Gui.icon.of([35, 49, 50]) == JG.GuiIcon{4294967295, [35, 49, 50]} : JG.Gui.Icon}

law gui_icon_four_digits_is_text:
  {JG.Gui.icon.of([35, 49, 50, 51, 52, 35]) == JG.GuiIcon{4294967295, [35, 49, 50, 51, 52, 35]} : JG.Gui.Icon}

# raygui's table has 256 icons: "#255#" is drawn, "#256#" (a read past the
# table) is refused. A line that is not the last and holds only '#' is
# refused too: GuiGetTextWidth would look for a second '#' in the next lines.
law gui_icon_last_of_table_drawn:
  {JG.Gui.has_icon([[35, 50, 53, 53, 35]]) == False{} : Bool}

law gui_icon_beyond_table_refused:
  {JG.Gui.has_icon([[35, 50, 53, 54, 35]]) == True{} : Bool}

law gui_hash_before_another_line_refused:
  {JG.Gui.has_icon([[35], [97]]) == True{} : Bool}

law gui_hash_on_last_line_drawn:
  {JG.Gui.has_icon([[97], [35]]) == False{} : Bool}

# GuiGetTextWidth measures from a second '#' at index 1 to 4, not further.
law gui_width_second_hash_at_four:
  {JG.Gui.width.offset(4n, [49, 49, 56, 35], 1) == 4 : U32}

law gui_width_second_hash_beyond:
  {JG.Gui.width.offset(4n, [97, 98, 99, 100, 35], 1) == 0 : U32}

# The icon set: ICON_ARROW_LEFT_FILL's rows 6 and 7 are bits 6..9 and 5..9
# (word 3 is 0x03E003C0); a word past the 256 icons is 0, not a read outside
# the table.
law gui_icon_past_table_is_empty:
  {GuiIcons.word(256, 0) == 0 : U32}

law gui_icon_arrow_left_word:
  {GuiIcons.word(118, 3) == 65012672 : U32}

# GuiValueBox and GuiSpinner hold C ints as two's-complement words: -1 is
# below 0, and the box clamps to max when above it, else to min when below.
law gui_int_minus_one_below_zero:
  {JG.Gui.int.less(4294967295, 0) == True{} : Bool}

law gui_int_zero_not_below_minus_one:
  {JG.Gui.int.less(0, 4294967295) == False{} : Bool}

law gui_int_clamp_above:
  {JG.Gui.int.clamp(9, 2, 8) == 8 : U32}

law gui_int_clamp_below_negative_min:
  {JG.Gui.int.clamp(4294967291, 4294967294, 8) == 4294967294 : U32}

law gui_int_clamp_inside:
  {JG.Gui.int.clamp(5, 2, 8) == 5 : U32}

# A value box is filled only when pressed or disabled: BLANK otherwise.
law gui_value_box_blank_when_normal:
  for gui: JG.Gui
  {JG.Gui.value.fill(0, gui) == 0 : U32}

law gui_value_box_blank_when_focused:
  for gui: JG.Gui
  {JG.Gui.value.fill(1, gui) == 0 : U32}

# GuiDropdownBox splits its text as GuiTextSplit does: "L;B" is two items,
# an empty text is one empty item, and no item under the pointer is 4294967295.
law gui_dropdown_two_items:
  {JG.Gui.drop.count(JG.Gui.split([76, 59, 66], 59, 0, Nil{}), 0) == 2 : U32}

law gui_dropdown_empty_text_is_one_item:
  {JG.Gui.drop.count(JG.Gui.split(Nil{}, 59, 0, Nil{}), 0) == 1 : U32}

law gui_dropdown_second_item:
  {JG.Gui.drop.bytes(List.drop(&2, JG.Gui.Item, JG.Gui.split([76, 59, 66], 59, 0, Nil{}), 1n)) == [66] : +List<U32>}

law gui_dropdown_focus_without_items:
  for mouse: M.Vector2
  for x: F32
  for y: F32
  for w: F32
  for h: F32
  for pitch: F32
  for up: Bool
  {JG.Gui.drop.focus(0n, 0, mouse, x, y, w, h, pitch, up) == 4294967295 : U32}

# GuiTextBox edits bytes at the cursor: a piece goes in before it, a
# codepoint comes out whole (two bytes for U+00E9), and nothing is before
# the start of the text.
law gui_text_box_insert_at_cursor:
  {JG.Gui.box.insert([65, 66], 1, [67]) == [65, 67, 66] : +List<U32>}

law gui_text_box_remove_at_cursor:
  {JG.Gui.box.remove([65, 66, 67], 1, 1) == [65, 67] : +List<U32>}

law gui_text_box_backspace_whole_codepoint:
  {JG.Gui.box.back([65, 195, 169], 3) == 2 : U32}

law gui_text_box_nothing_before_start:
  {JG.Gui.box.back([65], 0) == 0 : U32}

# A paste stops where the text would reach textSize, and at a control character.
law gui_text_box_paste_fits_size:
  {JG.Gui.box.paste(3n, [97, 98], 0, 3, 5) == 1 : U32}

law gui_text_box_paste_stops_at_control:
  {JG.Gui.box.paste(4n, [97, 10, 98], 0, 0, 95) == 1 : U32}

law gui_text_box_globals_start_at_zero:
  {JG.Gui.editing() == JG.GuiEditing{0, 0} : JG.Gui.Editing}

law gui_text_box_blank_when_normal:
  for gui: JG.Gui
  {JG.Gui.box.fill(0, gui) == 0 : U32}

# GuiSetIconScale: 1 at start; a scale below 1 (0, or a negative C int) is ignored.
law gui_icon_scale_starts_at_one:
  {JG.Gui.icon_scale(JG.Gui.new()) == 1 : U32}

law gui_icon_scale_set:
  for gui: JG.Gui
  {JG.Gui.icon_scale(JG.Gui.set_icon_scale(gui, 2)) == 2 : U32}

law gui_icon_scale_zero_ignored:
  for gui: JG.Gui
  {JG.Gui.icon_scale(JG.Gui.set_icon_scale(gui, 0)) == JG.Gui.icon_scale(gui) : U32}

law gui_icon_scale_negative_ignored:
  for gui: JG.Gui
  {JG.Gui.icon_scale(JG.Gui.set_icon_scale(gui, 4294967295)) == JG.Gui.icon_scale(gui) : U32}

# GuiScrollBar normalizes its int value to max when above it, then to min
# when below it (so min wins when the two cross), keeps a slider size of at
# least 1, and an arrow steps by range/SCROLL_SPEED truncated toward zero.
law gui_scroll_clamp_above:
  {JG.Gui.scroll.clamp(5, 0, 3) == 3 : U32}

law gui_scroll_clamp_below_zero:
  {JG.Gui.scroll.clamp(4294967295, 0, 3) == 0 : U32}

law gui_scroll_clamp_crossed_bounds:
  {JG.Gui.scroll.clamp(5, 3, 1) == 3 : U32}

law gui_scroll_slider_at_least_one:
  {JG.Gui.scroll.floor(0, 1) == 1 : U32}

law gui_scroll_step_truncates:
  {JG.Gui.int.div(30, 12) == 2 : U32}

law gui_scroll_step_negative_speed:
  {JG.Gui.int.div(30, 4294967284) == 4294967294 : U32}

# GuiProgressBar draws no text it is not given, no reached border before
# the value passes the minimum and no unreached one once it is at the maximum.
law gui_progress_no_text_draws_nothing:
  for gui: JG.Gui
  for frame: J.Frame
  for right: Bool
  for bounds: J.Rectangle
  for state: U32
  {JG.Gui.progress.label(gui, frame, None{}, right, bounds, state) == frame : J.Frame}

law gui_progress_not_started_has_no_reached_border:
  for frame: J.Frame
  for left: J.Rectangle
  for bottom: J.Rectangle
  for color: U32
  {JG.Gui.progress.behind(False{}, frame, left, bottom, color) == frame : J.Frame}

law gui_progress_full_has_no_unreached_border:
  for frame: J.Frame
  for bottom: J.Rectangle
  for right: J.Rectangle
  for color: U32
  {JG.Gui.progress.ahead(True{}, frame, bottom, right, color) == frame : J.Frame}

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

# WaveFormat's loops over samples and frames carry their results, so that
# their depth does not grow with the wave; they keep the order.
law wave_format_frames_in_order:
  {WaveConvert.split(2n, 2n, [1, 2, 3, 4]) == [[1, 2], [3, 4]] : +List<+List<U32>>}

law wave_format_frames_flattened_in_order:
  {WaveConvert.flat([[1, 2], [3, 4], [5]]) == [1, 2, 3, 4, 5] : +List<U32>}

law wave_format_samples_in_order:
  {WaveConvert.map.sample([0, 128, 255], 1) == [4294934528, 0, 32512] : +List<U32>}

law wave_format_nan_anywhere:
  {WaveConvert.any_nan([0, 2143289344, 0]) == True{} : Bool}

# Audio device (raudio.c's AUDIO state; docs/AUDIO.md#audio-device-and-sounds):
# no device before InitAudioDevice, which opens it at a master volume of 1 and
# leaves a ready device as it is; CloseAudioDevice leaves the buffers tracked
# and the master volume 0.
law audio_starts_unready:
  {J.AudioDevice.is_ready(J.AudioDevice.none()) == False{} : Bool}

law audio_init_full_volume:
  {J.AudioDevice.init(J.AudioDevice.none()) == J.AudioDevice{True{}, 1.0, 1, Nil{}, Nil{}} : J.AudioDevice}

law audio_init_ready_unchanged:
  for +master: F32
  for +next: U32
  for +buffers: +List<J.AudioDevice.Buffer>
  for +blocks: +List<J.AudioDevice.Block>
  {J.AudioDevice.init(J.AudioDevice{True{}, master, next, buffers, blocks}) == J.AudioDevice{True{}, master, next, buffers, blocks} : J.AudioDevice}

law audio_close_keeps_buffers:
  for +master: F32
  for +next: U32
  for +buffers: +List<J.AudioDevice.Buffer>
  for +blocks: +List<J.AudioDevice.Block>
  {J.AudioDevice.close(J.AudioDevice{True{}, master, next, buffers, blocks}) == J.AudioDevice{False{}, 0.0, next, buffers, blocks} : J.AudioDevice}

# GetMasterVolume: 0 before the device opens.
law audio_master_volume_starts_at_zero:
  {J.AudioDevice.master_volume(J.AudioDevice.none()) == 0.0 : F32}

law audio_master_volume_full_when_open:
  {J.AudioDevice.master_volume(J.AudioDevice.init(J.AudioDevice.none())) == 1.0 : F32}

# LoadSoundFromWave: the wave in the device format (a 32-bit stereo wave at
# 48000 Hz is kept as it is) in a new tracked buffer over its own block;
# nothing on an unready device; the zero sound for the zero wave; an invalid
# sound over an empty buffer for a wave without frames.
law sound_from_device_format_wave:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{1, 48000, 32, 2, [1056964608, 3204448256]}) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 1, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1056964608, 3204448256]}]}, Done{J.Sound{J.AudioStream{1, 48000, 32, 2}, 1}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_unready_device_refused:
  {J.Sound.load_from_wave(J.AudioDevice.none(), J.Wave{1, 48000, 16, 1, [16384]}) == (J.AudioDevice.none(), Fail{J.SoundDeviceNotReady{}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_zero_wave_is_zero_sound:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{0, 0, 0, 0, Nil{}}) == (J.AudioDevice.init(J.AudioDevice.none()), Done{J.Sound.none()}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_without_frames_has_empty_buffer:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{0, 48000, 16, 1, Nil{}}) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 0, 0, 1.0, 1.0, 0.0, False{}, False{}}], Nil{}}, Done{J.Sound{J.AudioStream{1, 48000, 32, 2}, 0}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_refused_wave_tracks_nothing:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{1, 48000, 24, 1, [1]}) == (J.AudioDevice.init(J.AudioDevice.none()), Fail{J.SoundWaveError{J.WaveDataError{J.InvalidWaveRequest{}}}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

# IsSoundValid: frames, buffer and stream fields all nonzero.
law sound_zero_invalid:
  {J.Sound.is_valid(J.Sound.none()) == False{} : Bool}

law sound_without_frames_invalid:
  {J.Sound.is_valid(J.Sound{J.AudioStream{1, 48000, 32, 2}, 0}) == False{} : Bool}

law sound_with_frames_valid:
  {J.Sound.is_valid(J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == True{} : Bool}

# LoadSoundAlias: a new buffer with its own state over the source's block;
# the zero sound has none.
law sound_alias_shares_block:
  {J.Sound.load_alias(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == (J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) : J.AudioDevice & J.Sound}

law sound_alias_of_zero_sound:
  {J.Sound.load_alias(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound.none()) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound.none()) : J.AudioDevice & J.Sound}

# PlaySound plays its own buffer only; StopSound leaves a paused buffer as it
# is (raylib stops buffers that are playing and not paused).
law sound_play_only_its_buffer:
  {J.Sound.play(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, True{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]} : J.AudioDevice}

law sound_played_is_playing:
  {J.Sound.is_playing(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == True{} : Bool}

law sound_paused_not_playing:
  {J.Sound.is_playing(J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == False{} : Bool}

law sound_stop_leaves_paused:
  {J.Sound.stop(J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) : J.AudioDevice}

law sound_stop_after_play:
  {J.Sound.stop(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]} : J.AudioDevice}

# SetSoundVolume sets its own buffer's volume only.
law sound_volume_only_its_buffer:
  {J.Sound.set_volume(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}, 0.25) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 0.25, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]} : J.AudioDevice}

# UnloadSound frees the block its buffer plays, UnloadSoundAlias only
# untracks the buffer.
law sound_unload_frees_block:
  {J.Sound.unload(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], Nil{}} : J.AudioDevice}

law sound_unload_alias_keeps_block:
  {J.Sound.unload_alias(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]} : J.AudioDevice}

# UpdateSound writes the block every buffer over it plays; a request past
# the buffer changes nothing.
law sound_update_reaches_aliases:
  {J.Sound.data(J.Sound.update(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}, [9, 8], 1), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == Some{[9, 8, 3, 4]} : Maybe<&2, +List<U32>>}

law sound_update_past_buffer_ignored:
  {J.Sound.update(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}, [0, 0, 0, 0, 0, 0], 3) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]} : J.AudioDevice}

# Handles raylib cannot use change nothing: any buffer on an unready device,
# and a buffer that was unloaded.
law sound_unready_buffers_untouched:
  {J.Sound.play(J.AudioDevice.close(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice.close(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}) : J.AudioDevice}

law sound_unloaded_handle_ignored:
  {J.Sound.play(J.Sound.unload(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.Sound.unload(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}}], [J.AudioBlock{1, [1, 2, 3, 4]}]}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) : J.AudioDevice}

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

# LoadImageColors kept as an image (Surface.colors_image): the canonical
# colors are an R8G8B8A8 image (format 7) of the same size, and a failure is
# handed on with its owner.
law surface_colors_image_is_rgba8:
  for width: U32
  for height: U32
  for pixels: Array<U32>
  {J.Surface.colors_image.rgba(Done{J.Rgba{width, height, pixels}}) == Done{J.Surface{width, height, 7, J.Words{pixels}}} : Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>}

law surface_colors_image_failure_kept:
  for failure: J.Surface & J.Surface.Error
  {J.Surface.colors_image.rgba(Fail{failure}) == Fail{failure} : Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>}

# font.texture.width and font.texture.height (Font.texture_size) are the
# texture's own, and the font comes back as it was.
law font_texture_size_is_the_textures:
  for base: U32
  for padding: U32
  for glyphs: +List<FontCore.Glyph>
  for id: U32
  for width: U32
  for height: U32
  for format: U32
  for linear: Bool
  for alpha: Bool
  for texels: Maybe<Array<U32>>
  for atlas: J.Surface
  {J.Font.texture_size(J.Font{base, padding, glyphs, J.Texture{id, width, height, format, linear, alpha, texels}, atlas}) ==
    (J.Font{base, padding, glyphs, J.Texture{id, width, height, format, linear, alpha, texels}, atlas}, (width, height)) : J.Font & (U32 & U32)}

# Render textures (docs/RLGL.md): every framebuffer has its own depth buffer,
# as rlsw gives each a depth renderbuffer. One that was never drawn into has
# none set aside and starts from a zeroed buffer; BeginTextureMode takes the
# framebuffer's own buffer back (it is kept between texture modes) and leaves
# another framebuffer's where it is.
law render_depth_unstashed:
  for wanted: U32
  {FrameCore.Stash.take(Nil{}, wanted, (Nil{}, None{})) == (Nil{}, None{}) : List<FrameCore.Stash> & Maybe<Array<U32>>}

law render_depth_starts_zeroed:
  for count: U32
  {FrameCore.Stash.buffer(None{}, count) == Array.new(U32, FrameCore.depth(count), 0) : Array<U32>}

law render_depth_kept_between_modes:
  for depth: Array<U32>
  {FrameCore.Stash.take(Con{FrameCore.Stash{3, depth}, Nil{}}, 3, (Nil{}, None{})) == (Nil{}, Some{depth}) : List<FrameCore.Stash> & Maybe<Array<U32>>}

law render_depth_other_framebuffer_stays:
  for depth: Array<U32>
  {FrameCore.Stash.take(Con{FrameCore.Stash{2, depth}, Nil{}}, 3, (Nil{}, None{})) == (Con{FrameCore.Stash{2, depth}, Nil{}}, None{}) : List<FrameCore.Stash> & Maybe<Array<U32>>}

law render_depth_reused:
  for depth: Array<U32>
  for count: U32
  {FrameCore.Stash.buffer(Some{depth}, count) == depth : Array<U32>}

# rlgl under OpenGL 1.1 (GRAPHICS_API_OPENGL_SOFTWARE): rlSetBlendMode exists
# for OpenGL 3.3/ES2 only and leaves the frame; rlGetVersion is
# RL_OPENGL_SOFTWARE; rlMatrixMode(RL_PROJECTION) selects rlsw's projection
# stack and an unknown mode selects none; rlBegin draws lines, triangles and
# quads only (RL_LINES 1 takes 2 vertices, other modes record nothing).
law rlgl_blend_mode_unchanged:
  for frame: J.Frame
  for mode: U32
  {J.Rlgl.set_blend_mode(frame, mode) == frame : J.Frame}

# The uniform setters and rlSetShader have bodies under OpenGL 3.3/ES2 only:
# the software renderer's frame is the one given.
law rlgl_set_uniform_unchanged:
  for frame: J.Frame
  for location: U32
  for value: +List<U32>
  for kind: U32
  {J.Rlgl.set_uniform(frame, location, value, kind) == frame : J.Frame}

law rlgl_set_uniform_matrix_unchanged:
  for frame: J.Frame
  for location: U32
  for matrix: M.Matrix
  {J.Rlgl.set_uniform_matrix(frame, location, matrix) == frame : J.Frame}

law rlgl_set_uniform_matrices_unchanged:
  for frame: J.Frame
  for location: U32
  for matrices: +List<M.Matrix>
  {J.Rlgl.set_uniform_matrices(frame, location, matrices) == frame : J.Frame}

law rlgl_set_uniform_sampler_unchanged:
  for frame: J.Frame
  for location: U32
  for texture: U32
  {J.Rlgl.set_uniform_sampler(frame, location, texture) == frame : J.Frame}

law rlgl_set_shader_unchanged:
  for frame: J.Frame
  for id: U32
  for locations: +List<U32>
  {J.Rlgl.set_shader(frame, id, locations) == frame : J.Frame}

# Vertex arrays, buffers, shader objects, compute shaders and storage buffers
# have bodies under OpenGL 3.3/ES2 (4.3) only: locations are -1, a storage
# buffer's size 0, and the frame is the one given.
law rlgl_location_uniform_absent:
  for id: U32
  for name: String
  {J.Rlgl.get_location_uniform(id, name) == 4294967295 : U32}

law rlgl_location_attrib_absent:
  for id: U32
  for name: String
  {J.Rlgl.get_location_attrib(id, name) == 4294967295 : U32}

law rlgl_shader_buffer_size_zero:
  for id: U32
  {J.Rlgl.get_shader_buffer_size(id) == 0 : U32}

law rlgl_set_vertex_attribute_unchanged:
  for frame: J.Frame
  for index: U32
  for size: U32
  for kind: U32
  for normalized: Bool
  for stride: U32
  for offset: U32
  {J.Rlgl.set_vertex_attribute(frame, index, size, kind, normalized, stride, offset) == frame : J.Frame}

law rlgl_update_vertex_buffer_unchanged:
  for frame: J.Frame
  for id: U32
  for size: U32
  for offset: U32
  {J.Rlgl.update_vertex_buffer(frame, id, size, offset) == frame : J.Frame}

law rlgl_compute_dispatch_unchanged:
  for frame: J.Frame
  for x: U32
  for y: U32
  for z: U32
  {J.Rlgl.compute_shader_dispatch(frame, x, y, z) == frame : J.Frame}

law rlgl_pixel_format_name_rgba:
  {J.Rlgl.get_pixel_format_name(7) == "R8G8B8A8" : String}

law rlgl_pixel_format_name_unknown:
  {J.Rlgl.get_pixel_format_name(0) == "UNKNOWN" : String}

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

# rlgl framebuffer objects as values: framebuffer 0 is complete and takes no
# attachment; a color texture alone completes one; a depth attachment of
# another size does not; channel 1 is not rlsw's color attachment; and a
# render texture needs the attached depth id.
law rlgl_framebuffer_zero_is_complete:
  {J.Rlgl.Framebuffer.complete(J.Rlgl.Framebuffer.none()) == True{} : Bool}

law rlgl_framebuffer_zero_takes_no_attachment:
  for id: U32
  for width: U32
  for height: U32
  for format: U32
  for attach: U32
  for kind: U32
  {J.Rlgl.framebuffer.attached(J.Rlgl.Framebuffer.none(), id, width, height, format, attach, kind) == J.Rlgl.Framebuffer.none() : J.Rlgl.Framebuffer}

law rlgl_framebuffer_color_alone_is_complete:
  {J.Rlgl.Framebuffer.complete(J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 2, 64, 48, 7, 0, 100)) == True{} : Bool}

law rlgl_framebuffer_empty_is_incomplete:
  {J.Rlgl.Framebuffer.complete(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}) == False{} : Bool}

law rlgl_framebuffer_depth_of_other_size_is_incomplete:
  {J.Rlgl.Framebuffer.complete(J.Rlgl.framebuffer.attached(J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 2, 64, 48, 7, 0, 100), 3, 32, 32, 19, 100, 200)) == False{} : Bool}

law rlgl_framebuffer_channel_one_is_ignored:
  {J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 2, 64, 48, 7, 1, 100) == J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0} : J.Rlgl.Framebuffer}

law rlgl_framebuffer_depth_attaches_as_texture_or_renderbuffer:
  {J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 3, 64, 48, 19, 100, 200) == J.RlglFramebuffer{1, 0, 0, 0, 0, 3, 64, 48, 19} : J.Rlgl.Framebuffer}

# A framebuffer with a depth attachment alone (a shadow map's) is incomplete
# on rlsw, which then refuses swBegin and swClear: its RenderTexture2D has no
# color texture, a framebuffer with one or framebuffer 0 gives none, the
# screen is never such a target, and leaving one sets no depth buffer aside
# where leaving a render texture does.
law rlgl_framebuffer_depth_alone_is_incomplete:
  {J.Rlgl.Framebuffer.complete(J.RlglFramebuffer{1, 0, 0, 0, 0, 3, 1024, 1024, 19}) == False{} : Bool}

law rlgl_render_texture_depth_has_no_color_texture:
  {J.Rlgl.render_texture_depth(J.RlglFramebuffer{1, 0, 0, 0, 0, 3, 1024, 1024, 19}, 1024, 1024, 3) == Some{J.RenderTexture{1, J.Texture{0, 1024, 1024, 0, False{}, False{}, None{}}, 3}} : Maybe<J.RenderTexture>}

law rlgl_render_texture_depth_refuses_a_color_attachment:
  {J.Rlgl.render_texture_depth(J.RlglFramebuffer{1, 2, 64, 48, 7, 3, 64, 48, 19}, 64, 48, 3) == None{} : Maybe<J.RenderTexture>}

law rlgl_render_texture_depth_refuses_another_depth:
  {J.Rlgl.render_texture_depth(J.RlglFramebuffer{1, 0, 0, 0, 0, 3, 64, 48, 19}, 64, 48, 4) == None{} : Maybe<J.RenderTexture>}

law rlgl_render_texture_depth_refuses_framebuffer_zero:
  {J.Rlgl.render_texture_depth(J.Rlgl.Framebuffer.none(), 64, 48, 0) == None{} : Maybe<J.RenderTexture>}

law blind_target_never_the_screen:
  for stash: List<FrameCore.Stash>
  {FrameCore.Canvas.target.blind(FrameCore.Screen{stash}) == (FrameCore.Screen{stash}, False{}) : FrameCore.Target & Bool}

law blind_target_leaves_no_depth_buffer:
  for id: U32
  for buffer: Array<U32>
  for stash: List<FrameCore.Stash>
  {FrameCore.Canvas.target.left(True{}, id, buffer, stash) == FrameCore.Screen{stash} : FrameCore.Target}

law render_target_leaves_its_depth_buffer:
  for id: U32
  for buffer: Array<U32>
  for stash: List<FrameCore.Stash>
  {FrameCore.Canvas.target.left(False{}, id, buffer, stash) == FrameCore.Screen{Con{FrameCore.Stash{id, buffer}, stash}} : FrameCore.Target}

# A deferred renderer's G-buffer on rlsw: a float format is not supported
# under OpenGL 1.1, so its texture has an id and no storage and the
# framebuffer it colors is incomplete. Such a framebuffer is bound to draw
# with rlEnableFramebuffer (marked in the target, unlike a texture mode's);
# EndTextureMode hands no render texture back for it; binding framebuffer 0
# with rlBindFramebuffer is rlDisableFramebuffer; rlActiveDrawBuffers does
# nothing.
law rlgl_float_texture_has_no_storage:
  for canvas: FrameCore.Canvas
  {J.Rlgl.texture.with(2, 5, 800, 450, 12, canvas) == (J.Frame{canvas, Nil{}}, Some{J.Texture{5, 800, 450, 12, False{}, False{}, None{}}}) : J.Frame & Maybe<J.Texture>}

law rlgl_framebuffer_float_color_is_incomplete:
  {J.Rlgl.Framebuffer.complete(J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 2, 800, 450, 12, 0, 100)) == False{} : Bool}

law blind_target_bound_directly_is_marked:
  for id: U32
  {FrameCore.RenderTarget.direct(FrameCore.RenderTarget{id, 0, 0, False{}, True{}}) == True{} : Bool}

law blind_texture_mode_is_not_bound_directly:
  for id: U32
  for depth: U32
  {FrameCore.RenderTarget.direct(FrameCore.RenderTarget{id, 0, depth, False{}, False{}}) == False{} : Bool}

law blind_target_bound_directly_hands_nothing_back:
  for meta: FrameCore.RenderTarget
  for width: U32
  for height: U32
  for texels: Array<U32>
  {FrameCore.Canvas.target.detached(True{}, meta, width, height, texels) == None{} : Maybe<FrameCore.Detached>}

law rlgl_bind_framebuffer_zero_is_disable:
  for frame: J.Frame
  for target: U32
  {J.Rlgl.bind_framebuffer(frame, target, J.Rlgl.Framebuffer.none()) == J.Rlgl.disable_framebuffer(frame) : J.Frame}

law rlgl_bound_active_draw_buffers_unchanged:
  for bound: J.Rlgl.Bound
  for count: F32
  {J.Rlgl.Bound.active_draw_buffers(bound, count) == bound : J.Rlgl.Bound}

# rlLoadTextureCubemap has no body under OpenGL 1.1 (id 0, the frame as it
# was), and the cull distances are rlgl's defaults: as floats, the 0.05f and
# 4000.0f the projections are built with.
law rlgl_load_texture_cubemap_is_zero:
  for frame: J.Frame
  for data: List<&2, U32>
  for size: U32
  for format: U32
  for mipmaps: U32
  {J.Rlgl.load_texture_cubemap(frame, data, size, format, mipmaps) == (frame, 0) : J.Frame & U32}

law rlgl_cull_distance_near_is_the_default:
  {J.Rlgl.get_cull_distance_near() == M.Float64{1068079513, 2576980378} : M.Float64}

law rlgl_cull_distance_near_as_float:
  {N.checked(1068079513, 2576980378) == Some{1028443341} : Maybe<U32>}

law rlgl_cull_distance_far_is_the_default:
  {J.Rlgl.get_cull_distance_far() == M.Float64{1085227008, 0} : M.Float64}

law rlgl_cull_distance_far_as_float:
  {N.checked(1085227008, 0) == Some{1165623296} : Maybe<U32>}

# ColorFromHSV's fmodf(phase, 6) (docs/API.md): the terms subtracted are
# 6*2^j (6.0 is 0x40c00000, each doubling adds one to the exponent), starting
# from as many doublings as the magnitude's exponent is above 6.0's: none
# below 8, one from 8 on, 125 for the largest binary32 value.
law color_hsv_term_six:
  {J.Color.hsv.term(0) == 1086324736 : U32}

law color_hsv_term_doubles:
  {J.Color.hsv.term(5) == 1128267776 : U32}

law color_hsv_steps_below_six:
  {J.Color.hsv.steps(1086324735) == 0 : U32}

law color_hsv_steps_below_eight:
  {J.Color.hsv.steps(1090519039) == 0 : U32}

law color_hsv_steps_eight:
  {J.Color.hsv.steps(1090519040) == 1 : U32}

law color_hsv_steps_largest:
  {J.Color.hsv.steps(2139095039) == 125 : U32}

# UploadMesh has vertex buffers under OpenGL 3.3/ES2 only: the software
# renderer's mesh is the one given.
law mesh_upload_unchanged:
  for mesh: J.Mesh
  for dynamic: Bool
  {J.Mesh.upload(mesh, dynamic) == mesh : J.Mesh}

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
