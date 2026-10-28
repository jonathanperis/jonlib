import Base
import ./src/checked_angle.bend as CA
import ./src/modern_angle.bend as MA
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./joneasings.bend as E
import ./jonlights.bend as Lt
import ./jonlgl.bend as Lgl
import ./joncamera.bend as Cam
import ./jongestures.bend as Gest
import ./src/mod.bend as Mods
import ./src/binary64_narrow.bend as N
import ./src/binary64_fma.bend as F
import ./src/binary64_add_sub.bend as A
import ./src/binary64_ops.bend as O
import ./src/binary64_gradual_multiply.bend as G
import ./src/resize_numeric.bend as Resize
import ./src/bmp.bend as Bmp
import ./src/jpeg.bend as Jpg
import ./src/tga.bend as Tga
import ./src/convolution.bend as Conv
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
import ./src/lgpl/acos.bend as GlibcAcos
import ./src/sincosf.bend as Sincosf
import ./src/power.bend as Power
import ./src/power64.bend as Power64
import ./src/stb_cubic.bend as Cubic
import ./src/msf_gif.bend as MsfGif
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
import ./src/mp3.bend as Mp3
import ./src/mp3_layer3.bend as Mp3L3
import ./src/mp3_layer12.bend as Mp3L12
import ./src/mp3_tables.bend as Mp3T
import ./src/mp3_stream.bend as Mp3S
import ./src/vorbis_codebook.bend as V
import ./src/vorbis_ogg.bend as Ogg
import ./src/vorbis_setup.bend as VS
import ./src/vorbis_maps.bend as VM
import ./src/vorbis_tables.bend as VT
import ./src/store.bend as St
import ./src/vorbis_decode.bend as VD
import ./src/vorbis_mdct.bend as VX
import ./src/vorbis_residue.bend as VR
import ./src/vorbis_floor.bend as VF
import ./src/vorbis_db.bend as VDb
import ./src/vorbis_packet.bend as VK
import ./src/vorbis_frame.bend as VFr
import ./src/vorbis_length.bend as VL
import ./src/xm_module.bend as Xm
import ./src/xm_pitch.bend as XmP
import ./src/xm_sample.bend as XmS
import ./src/xm_player.bend as XmPl
import ./src/xm_mixer.bend as XmX
import ./src/wav_adpcm.bend as Adpcm
import ./src/convert.bend as WaveConvert
import ./src/mixer.bend as Mixer
import ./src/resampler.bend as Resampler
import ./src/lowpass.bend as Lowpass
import ./src/shapes.bend as Shapes
import ./src/frame.bend as FrameCore
import ./src/shapes3d.bend as Shapes3D
import ./src/fonts.bend as FontCore
import ./src/font_data.bend as FontData
import ./src/input.bend as InputCore
import ./src/sha.bend as ShaCore
import ./src/gestures.bend as GestureCore
import ./src/clock.bend as Clock
import ./src/core_state.bend as CoreState
import ./src/automation.bend as AutomationCore
import ./src/obj.bend as Obj

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

# .pep and .PEP select the PEP decoder. Mixed case stays unsupported, as
# LoadImageFromMemory compares the token exactly. Export folds ASCII case.
law pep_file_kind:
  {(J.Image.file.kind.of(".pep"), J.Image.file.kind.of(".PEP")) == (J.PepFile{}, J.PepFile{}) : J.Image.FileKind & J.Image.FileKind}

law pep_file_kind_mixed_case:
  {J.Image.file.kind.of(".Pep") == J.UnsupportedImageFile{} : J.Image.FileKind}

law pep_file_limit:
  {J.Image.file.limit(J.PepFile{}) == 65536 : U32}

law pep_export_kind:
  {J.Image.export.kind("a.PeP") == 6 : U32}

# .jpg and .jpeg select JPEG export. ASCII case is folded, as IsFileExtension does.
law jpeg_export_kind:
  {(J.Image.export.kind("a.JPG"), J.Image.export.kind("a.JpEg")) == (7, 7) : U32 & U32}

# .ktx selects KTX export. ASCII case is folded, as IsFileExtension does.
law ktx_export_kind:
  {(J.Image.export.kind("a.KTX"), J.Image.export.kind("a.KtX")) == (8, 8) : U32 & U32}

# .hdr and .HDR select stbi_loadf. Mixed case stays unsupported. The shared
# file cap is the raster 1 MiB cap. Explicit load_hdr uses the same cap.
law hdr_file_kind:
  {(J.Image.file.kind.of(".hdr"), J.Image.file.kind.of(".HDR")) == (J.HdrFile{}, J.HdrFile{}) : J.Image.FileKind & J.Image.FileKind}

law hdr_file_kind_mixed_case:
  {J.Image.file.kind.of(".Hdr") == J.UnsupportedImageFile{} : J.Image.FileKind}

law hdr_file_limit:
  {J.Image.file.limit(J.HdrFile{}) == 1048576 : U32}

law png_signature_selects_the_decoder:
  {(J.Image.file.png_signed([137, 80, 78, 71]), J.Image.file.png_signed([66, 77, 0, 0])) == (True{}, False{}) : Bool & Bool}

law file_bytes_beyond_a_count:
  {(J.Image.file.beyond(2n, [1, 2, 3]), J.Image.file.beyond(3n, [1, 2, 3])) == (True{}, False{}) : Bool & Bool}

# The file system (rcore.c over Bend Base's Path, Dir and Process effects).
# MakeDirectory's walk makes each prefix before a '/' or '\\' and turns those
# separators into '/'; a ':' passes the character after it unread.
law files_made_prefixes:
  {J.Files.made("a/b\\c") == J.Files.Making{["a", "a/b"], "a/b/c"} : J.Files.Making}

law files_made_colon_passes_a_separator:
  {J.Files.made("c:/d/e") == J.Files.Making{["c:/d"], "c:/d/e"} : J.Files.Making}

# GetApplicationDirectory keeps the program's path up to and with its last
# '/', and is "./" without one.
law files_application_cut:
  {J.Files.application.cut("/usr/bin/tool") == "/usr/bin/" : String}

law files_application_without_slash:
  {J.Files.application.cut("tool") == "./" : String}

# OpenURL on the reference platform runs explorer "url", and nothing for a
# URL with a "'".
law system_url_command:
  {J.System.url.command("https://www.raylib.com") == Some{"explorer \"https://www.raylib.com\""} : Maybe<String>}

law system_url_quote_refused:
  {J.System.url.command("it's") == None{} : Maybe<String>}

# A path's bytes as UTF-8 decide where a scan skips (4096 on) or cuts (4095).
law files_utf8_length:
  {J.Files.utf8.length("a\u{e9}\u{20ac}\u{1f600}", 0) == 10 : U32}

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

# glibc powf(x, y) (src/power.bend's powf): which case the words of x and y
# are. +0 to a positive power is +0 and to a negative one has no answer (a
# division by zero); anything that is not a NaN to a zero power is 1; a
# positive finite base, a subnormal one too, takes the main path with a
# finite exponent that is not subnormal; a negative base, -0, an infinite
# one and the other exponents have no answer here. In the main path
# y*log2(x) at -150 and below underflows to +0, above that the result is
# computed (a subnormal down to -150), and from 127.984375 up there is no
# answer.
law glibc_powf_zero_to_a_positive_power:
  {Power.powf.region(0, 1073741824) == 0 : U32}

law glibc_powf_zero_to_a_negative_power_none:
  {Power.powf.region(0, 3221225472) == 3 : U32}

law glibc_powf_to_zero_is_one:
  {Power.powf.region(1073741824, 0) == 2 : U32}

law glibc_powf_infinity_to_minus_zero_is_one:
  {Power.powf.region(2139095040, 2147483648) == 2 : U32}

law glibc_powf_nan_to_zero_none:
  {Power.powf.region(2143289344, 0) == 3 : U32}

law glibc_powf_positive_base:
  {Power.powf.region(1073741824, 1077936128) == 1 : U32}

law glibc_powf_subnormal_base:
  {Power.powf.region(1, 1065353216) == 1 : U32}

law glibc_powf_negative_base_none:
  {Power.powf.region(3221225472, 1073741824) == 3 : U32}

law glibc_powf_minus_zero_base_none:
  {Power.powf.word(2147483648, 1073741824) == None{} : Maybe<F32>}

law glibc_powf_infinite_base_none:
  {Power.powf.region(2139095040, 1073741824) == 3 : U32}

law glibc_powf_subnormal_exponent_none:
  {Power.powf.region(1073741824, 1) == 3 : U32}

law glibc_powf_infinite_exponent_none:
  {Power.powf.region(1073741824, 2139095040) == 3 : U32}

law glibc_powf_underflow_from_minus_150:
  {Power.powf.bound(3227697152, 0) == 1 : U32}

law glibc_powf_subnormal_result_above_minus_150:
  {Power.powf.bound(3227697151, 4294967295) == 0 : U32}

law glibc_powf_top_none:
  {Power.powf.bound(1080033024, 0) == 2 : U32}

law glibc_powf_below_the_top:
  {Power.powf.bound(1080033023, 4294967295) == 0 : U32}

law glibc_powf_small_products_inside:
  {Power.powf.bound(1072693248, 0) == 0 : U32}

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

# logf's domain is every positive finite float. A subnormal one is scaled by
# 2^23 with 23 taken from its exponent, as glibc does: the word wraps below
# zero (the smallest subnormal's exponent field is 1 - 23).
law glibc_logf_answers_the_smallest_subnormal:
  {Power.log.domain(1) == True{} : Bool}

law glibc_logf_answers_the_largest_subnormal:
  {Power.log.domain(8388607) == True{} : Bool}

law glibc_logf_answers_the_largest_float:
  {Power.log.domain(2139095039) == True{} : Bool}

law glibc_logf_domain_without_zero:
  {Power.log.domain(0) == False{} : Bool}

law glibc_logf_domain_without_infinity:
  {Power.log.domain(2139095040) == False{} : Bool}

law glibc_logf_domain_without_negatives:
  {Power.log.domain(2147483649) == False{} : Bool}

law glibc_logf_smallest_subnormal_scaled:
  {Power.normalize(1) == 4110417920 : U32}

law glibc_logf_half_the_smallest_normal_scaled:
  {Power.normalize(4194304) == 0 : U32}

law glibc_logf_largest_subnormal_scaled:
  {Power.normalize(8388607) == 8388606 : U32}

law glibc_logf_normal_word_kept:
  {Power.normalize(8388608) == 8388608 : U32}

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
  {Gltf.look.with(4294967295, True{}, Gltf.Words{True{}, Nil{}}) == Gltf.Albedo{False{}, 4294967295, Nil{}} : Gltf.Look}

law gltf_base_color_image_kept:
  {Gltf.look.with(255, False{}, Gltf.Words{True{}, [137, 80]}) == Gltf.Albedo{True{}, 255, [137, 80]} : Gltf.Look}

# Wavefront OBJ files (src/obj.bend, docs/MODELS.md), raylib 6.2's bounds:
# parseLine takes lines of up to 4095 bytes; LoadOBJ copies a vertex, normal
# or texcoord only from a valid fixIndex below its array's count.
law obj_line_of_4095_bytes_parsed:
  {Obj.line.fits(4095) == True{} : Bool}

law obj_line_of_4096_bytes_refused:
  {Obj.line.fits(4096) == False{} : Bool}

law obj_index_inside_copied:
  {Obj.corner.inside(Obj.Fix{True{}, 2}, 3) == True{} : Bool}

law obj_index_past_the_end_skipped:
  {Obj.corner.inside(Obj.Fix{True{}, 3}, 3) == False{} : Bool}

law obj_index_negative_skipped:
  for n: U32
  {Obj.corner.inside(Obj.Fix{False{}, 0}, n) == False{} : Bool}

# MagicaVoxel files (src/vox.bend, docs/MODELS.md): LoadModel routes ".vox"
# to LoadVOX whatever the last test says; the array's sizes are padded to
# chunks of 16; a voxel's cell is (x*sizeZ + (sizeZ - y - 1))*sizeY + z with
# its id in the low byte, and (raylib 6.2) a voxel outside the sizes or cut
# short is not set; a quad's indices are 0 2 1 and 0 3 2; 189232 vertices
# make meshes of 65532, 65532 and 58168. An empty file and another magic or
# version are the empty model (Foreign); a magic cut short, and a file
# without a voxel (a header cut short before any SIZE among them), are
# refused (Unread).
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
  {Vox.voxels(1n, [1, 2, 3, 7], 16, 16, 16, Nil{}) == Vox.Sets{[119559], Nil{}} : Vox.Sets}

law vox_voxel_outside_skipped:
  {Vox.voxels(2n, [16, 2, 3, 7, 1, 2, 3, 7], 16, 16, 16, Nil{}) == Vox.Sets{[119559], Nil{}} : Vox.Sets}

law vox_voxel_before_size_skipped:
  {Vox.voxels(1n, [0, 0, 0, 1], 0, 0, 0, Nil{}) == Vox.Sets{Nil{}, Nil{}} : Vox.Sets}

law vox_voxel_count_cut_to_the_file:
  {Vox.voxels(2n, [1, 2, 3, 7, 1, 2], 16, 16, 16, Nil{}) == Vox.Sets{[119559], Nil{}} : Vox.Sets}

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

# raylib 6.2: the four bytes a palette leaves before the end of a file that
# ends with it are a chunk header cut short, which ends the reading with what
# was read; so do a SIZE, a voxel count and a palette cut short, and a chunk
# whose size passes the end of the file.
law vox_four_bytes_left_end:
  for read: Vox.Read
  {Vox.chunk([1, 2, 3, 4], read) == Vox.Next{Nil{}, read} : Vox.Step}

law vox_size_cut_short_ends:
  {Vox.chunk([83, 73, 90, 69, 12, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 4], Vox.Read{16, 16, 16, [7], [0]}) == Vox.Next{Nil{}, Vox.Read{16, 16, 16, [7], [0]}} : Vox.Step}

law vox_count_cut_short_ends:
  {Vox.chunk([88, 89, 90, 73, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0], Vox.Read{16, 16, 16, [7], [0]}) == Vox.Next{Nil{}, Vox.Read{16, 16, 16, [7], [0]}} : Vox.Step}

law vox_palette_cut_short_ends:
  {Vox.chunk([82, 71, 66, 65, 0, 4, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4], Vox.Read{16, 16, 16, [7], [0]}) == Vox.Next{Nil{}, Vox.Read{16, 16, 16, [7], [0]}} : Vox.Step}

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

# raylib 6.2: an empty material name is kept (it asks for no texture); a
# name from the root is still refused.
law iqm_material_names_a_file_or_none:
  {(Iqm.texture.named(Nil{}), (Iqm.texture.named([47, 97]), Iqm.texture.named([97, 46, 112]))) == (True{}, (False{}, True{})) : Bool & (Bool & Bool)}

law iqm_empty_material_asks_no_texture:
  {J.Model.iqm.request(Nil{}) == None{} : Maybe<&2, +List<U32>>}

law iqm_named_material_asks_its_texture:
  {J.Model.iqm.request([97, 46, 112]) == Some{[97, 46, 112]} : Maybe<&2, +List<U32>>}

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
# joints is its bone index and a node outside them has none (-1); fewer than
# two keys read key 0; bytes that are not a .glb file give neither a
# skeleton nor animations.
law gltf_anim_joint_place:
  {GltfAnim.find([5, 7, 9], 7, 0) == 1 : U32}

law gltf_anim_node_outside_skeleton:
  {GltfAnim.find([5, 7, 9], 6, 0) == 4294967295 : U32}

law gltf_anim_no_key_pair_reads_first:
  for time: F32
  {GltfAnim.key.index(GltfAnim.key(Nil{}, time)) == 0 : U32}

# raylib 6.2's GetPoseAtTimeGLTF without a pair that holds the time: the
# last pair (count - 2), the first one before the first key, the search's
# pair when there is one.
law gltf_anim_key_past_last_pair:
  {(GltfAnim.key.chosen(4294967295, False{}, 5), (GltfAnim.key.chosen(4294967295, True{}, 5), GltfAnim.key.chosen(1, False{}, 5))) == (3, (0, 1)) : U32 & (U32 & U32)}

# raylib 6.2's LoadBoneInfoGLTF walks up past nodes that are not joints: a
# node without a parent has no parent bone, a stopped walk keeps its answer,
# and a walk out of fuel (a cycle) is not a bone index, which refuses the
# skeleton.
law gltf_anim_parent_walk_root:
  {GltfAnim.parent.walk(2n, Nil{}, 0, Nil{}, 0, 0, True{}) == 4294967295 : U32}

law gltf_anim_parent_walk_stops:
  for nodes: +List<Json.Json>
  for total: U32
  for all: +List<U32>
  for at: U32
  {GltfAnim.parent.walk(3n, nodes, total, all, at, 7, False{}) == 7 : U32}

law gltf_anim_parent_walk_unended:
  for nodes: +List<Json.Json>
  for total: U32
  for all: +List<U32>
  for at: U32
  for answer: U32
  {GltfAnim.parent.walk(0n, nodes, total, all, at, answer, True{}) == 4294967294 : U32}

law gltf_anim_unended_parent_refused:
  {GltfAnim.bones.ok(Con{GltfAnim.Bone{Nil{}, 4294967294}, Nil{}}) == False{} : Bool}

# raylib 6.2's bind pose: without inverse bind matrices the world matrices
# (mode 0); float MAT4 inverses always bind, another layout is refused.
law gltf_anim_no_inverses_world_bind:
  for root: Json.Json
  for bin: +List<+List<U32>>
  for limit: U32
  for joints: U32
  {GltfAnim.inverses.read(False{}, root, bin, limit, joints) == GltfAnim.Inverses{0, Nil{}} : GltfAnim.Inverses}

law gltf_anim_inverse_modes_bind:
  for items: +List<U32>
  for nodes: +List<Json.Json>
  for total: U32
  {(GltfAnim.bind.ok(1, items, nodes, total), GltfAnim.bind.ok(2, items, nodes, total)) == (True{}, False{}) : Bool & Bool}

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
  for total: U32
  for all: +List<U32>
  {GltfAnim.rests(Nil{}, nodes, total, all) == Nil{} : +List<GltfAnim.Rest>}

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
  {J.Model.update_animation_bones_for(libm, J.ModelSkeleton{Nil{}, binds}, J.ModelAnimation{name, bones, count, poses}, frame, pose) == Some{pose} : Maybe<J.ModelPose>}

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
  {J.Model.update_animation_bones_for(libm, J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, bones, 0, poses}, frame, pose) == Some{pose} : Maybe<J.ModelPose>}

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
  {J.Model.update_animation_bones_ex_for(libm, J.ModelSkeleton{Nil{}, binds}, J.ModelAnimation{name, bones, count, poses}, first, J.ModelAnimation{name, bones, count, poses}, second, blend, pose) == Some{pose} : Maybe<J.ModelPose>}

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
  {J.Model.update_animation_bones_ex_for(libm, J.ModelSkeleton{Con{J.BoneInfo{bone, parent}, Nil{}}, binds}, J.ModelAnimation{name, bones, 0, poses}, first, J.ModelAnimation{name, bones, count, poses}, second, blend, pose) == Some{pose} : Maybe<J.ModelPose>}

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

# raylib 6.2's CPU skinning (UpdateModelAnimationVertexBuffers, docs/MODELS.md).
# DrawMesh draws animVertices once there are any, the vertices before.
law mesh_drawn_animated_vertices:
  {J.Mesh.drawn(Some{J.MeshBones{[0, 0, 0, 0], Nil{}, Some{Nil{}}}}, None{}) == Some{Nil{}} : Maybe<&2, +List<F32>>}

law mesh_drawn_vertices_before_skinning:
  {J.Mesh.drawn(Some{J.MeshBones{[0, 0, 0, 0], Nil{}, None{}}}, None{}) == None{} : Maybe<&2, +List<F32>>}

# A mesh keeps bone data only with both boneIndices and boneWeights.
law mesh_bones_need_weights:
  {J.Mesh.bones.of(Some{[1, 2, 3, 4]}, None{}) == None{} : Maybe<&2, J.MeshBones>}

law mesh_bones_need_indices:
  {J.Mesh.bones.of(None{}, Some{Nil{}}) == None{} : Maybe<&2, J.MeshBones>}

# Bone indices are unsigned chars.
law mesh_bone_indices_bytes:
  {(J.Mesh.bytes([0, 255]), J.Mesh.bytes([7, 256])) == (True{}, False{}) : Bool & Bool}

law mesh_bones_four_indices_a_vertex:
  {(J.Mesh.bones.sized(Some{J.MeshBones{Nil{}, Nil{}, None{}}}, 0), J.Mesh.bones.sized(Some{J.MeshBones{[1, 2, 3], Nil{}, None{}}}, 1)) == (True{}, False{}) : Bool & Bool}

# A weight of 0.0f skips its bone (the index is not read); a weighted bone
# past the skeleton reads outside boneMatrices: None.
law skin_zero_weight_skipped:
  {J.Model.skin.bone(True{}, None{}, M.Vector3{0.0, 0.0, 0.0}, Nil{}, 9, 0.0) == None{} : Maybe<&2, M.Vector3>}

law skin_bone_past_skeleton_refused:
  {J.Model.skin.bone(False{}, Some{M.Vector3{0.0, 0.0, 0.0}}, M.Vector3{0.0, 0.0, 0.0}, Nil{}, 0, 1.0) == None{} : Maybe<&2, M.Vector3>}

# A mesh without vertices: animVertices empty for an empty mesh, a NULL read otherwise.
law skin_empty_mesh_without_vertices:
  {(J.Model.skin.list(None{}, 0, Nil{}, Nil{}, Nil{}), J.Model.skin.list(None{}, 1, Nil{}, Nil{}, Nil{})) == (Some{Nil{}}, None{}) : Maybe<&2, +List<F32>> & Maybe<&2, +List<F32>>}

# A mesh without bone data is not skinned.
law skin_mesh_without_bones_unchanged:
  {J.Model.skin.mesh(J.Mesh.empty(), Nil{}) == Some{J.Mesh.empty()} : Maybe<J.Mesh>}

# The vertex buffers are not touched for a skeleton without bones or an
# animation without keyframes (UpdateModelAnimation returns first).
law skin_needs_bones_and_keyframes:
  {(J.Model.animation.active(J.ModelSkeleton{Nil{}, Nil{}}, J.ModelAnimation{"", 1, 1, Nil{}}),
    (J.Model.animation.active(J.ModelSkeleton{[J.BoneInfo{"", 4294967295}], Nil{}}, J.ModelAnimation{"", 1, 0, Nil{}}),
    J.Model.animation.active(J.ModelSkeleton{[J.BoneInfo{"", 4294967295}], Nil{}}, J.ModelAnimation{"", 1, 1, Nil{}}))) == (False{}, (False{}, True{})) : Bool & (Bool & Bool)}

# A refused bone update refuses the whole call.
law skin_refused_bones_refuse:
  {J.Model.animated(True{}, J.Model.empty(), None{}) == None{} : Maybe<J.AnimatedModel>}

# LoadGLTF: u16 joints kept as unsigned chars; a mesh under a joint gets
# that bone with weight 1 in each vertex's first slot.
law gltf_joint_bytes:
  {Gltf.joint.bytes([256, 511, 7]) == [0, 255, 7] : +List<U32>}

law gltf_parent_bone_indices:
  {Gltf.bone.indices(2n, 5, Nil{}) == [5, 0, 0, 0, 5, 0, 0, 0] : +List<U32>}

law gltf_component_sizes:
  {(Gltf.component(1, [7, 9]), (Gltf.component(2, [1, 2]), Gltf.component(4, [1, 0, 0, 1]))) == (7, (513, 16777217)) : U32 & (U32 & U32)}

law gltf_parent_bone_first_place:
  {(Gltf.position([Json.JNumber{[53]}, Json.JNumber{[51]}, Json.JNumber{[51]}], 3, 0), Gltf.position([Json.JNumber{[51]}], 4, 0)) == (1, 4294967295) : U32 & U32}

# LoadIQM: boneIndices of zeros without blend indexes.
law iqm_blend_indexes_zero_without_array:
  {Iqm.blended(None{}, 3, 2) == [0, 0, 0, 0, 0, 0, 0, 0] : +List<U32>}

law iqm_blend_indexes_of_mesh:
  {Iqm.blended(Some{[1, 2, 3, 4, 5, 6, 7, 8]}, 1, 1) == [5, 6, 7, 8] : +List<U32>}

# LoadM3D: no bone data without bones and skins.
law m3d_corner_ids_unskinned:
  {M3d.corner.ids(M3d.SkinSet{False{}, 3, M3d.empty.store()}, 0, [9]) == [9] : +List<U32>}

# A vertex without a skin goes to the no-bone bone (numbone).
law m3d_corner_ids_no_bone:
  {M3d.corner.ids(M3d.SkinSet{True{}, 259, M3d.empty.store()}, 4294967295, Nil{}) == [0, 0, 0, 3] : +List<U32>}

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

# raygui 5.1-dev's default style: TEXT_LINE_SPACING 12, and TABBAR (the
# control in CONTROL11's row) with TAB_ITEMS_WIDTH 160.
law gui_default_line_spacing:
  {JG.Gui.get_style(JG.Gui.new(), 0, 20) == 12 : U32}

law gui_default_tab_width:
  {JG.Gui.get_style(JG.Gui.new(), JG.Gui.TABBAR(), JG.Gui.TAB_ITEMS_WIDTH()) == 160 : U32}

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

# raygui 5.1-dev's GetTextIcon names icons below 512: "#511#" is one,
# "#512#" is text (the line stays whole), while the marker GetLineWidth
# skips is any '#', up to three digits and '#'.
law gui_icon_last_of_table:
  {JG.Gui.icon.of([35, 53, 49, 49, 35]) == JG.GuiIcon{511, []} : JG.Gui.Icon}

law gui_icon_past_max_is_text:
  {JG.Gui.icon.of([35, 53, 49, 50, 35, 97]) == JG.GuiIcon{4294967295, [35, 53, 49, 50, 35, 97]} : JG.Gui.Icon}

law gui_marker_any_number:
  {JG.Gui.icon.scan([35, 54, 48, 48, 35, 97]) == JG.GuiIcon{600, [97]} : JG.Gui.Icon}

law gui_marker_needs_digits_or_hash:
  {JG.Gui.icon.scan([35, 97, 35]) == JG.GuiIcon{4294967295, [35, 97, 35]} : JG.Gui.Icon}

# A line is refused only for an icon whose eight words are not in the icon
# table (raygui reads them past it): with a table of two icons, "#1#" is
# drawn and "#2#" refused; a lone '#' no longer is (GetLineWidth stops at
# the line's end).
law gui_icon_in_loaded_table_drawn:
  {JG.Gui.has_icon([[35, 49, 35]], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) == False{} : Bool}

law gui_icon_past_loaded_table_refused:
  {JG.Gui.has_icon([[35, 50, 35]], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) == True{} : Bool}

law gui_hash_before_another_line_drawn:
  {JG.Gui.has_icon([[35], [97]], [0, 0, 0, 0, 0, 0, 0, 0]) == False{} : Bool}

law gui_hash_on_last_line_drawn:
  {JG.Gui.has_icon([[97], [35]], [0, 0, 0, 0, 0, 0, 0, 0]) == False{} : Bool}

law gui_icon_table_holds_512:
  {JG.Gui.icons.has(GuiIcons.words(), 511) == True{} : Bool}

law gui_icon_table_ends_at_512:
  {JG.Gui.icons.has(GuiIcons.words(), 512) == False{} : Bool}

# The icon set: ICON_ARROW_LEFT_FILL's rows 6 and 7 are bits 6..9 and 5..9
# (word 3 is 0x03E003C0); ICON_FILETYPE_ICON (256, new in raygui 5.1-dev)
# starts with 0x3FF00000, and the icons past raygui's initializers are 0.
law gui_icon_filetype_icon_word:
  {GuiIcons.word(256, 0) == 1072693248 : U32}

law gui_icon_past_table_is_empty:
  {GuiIcons.word(511, 7) == 0 : U32}

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

# raygui 5.1-dev's GuiToggleGroup reads its items itself: ';' moves to the
# next column, '\n' to the next row's first; GROUP_WIDTH_FULL divides by the
# ';'s plus one.
law gui_toggle_group_cells:
  {JG.Gui.cells([65, 59, 66, 10, 67], 0, 0, Nil{}) == [JG.GuiCell{0, 0, [65]}, JG.GuiCell{0, 1, [66]}, JG.GuiCell{1, 0, [67]}] : +List<JG.Gui.Cell>}

law gui_toggle_group_semicolons:
  {JG.Gui.semis([65, 59, 66, 10, 67, 59, 68], 0) == 2 : U32}

# GuiMessageBox and GuiTextInputBox (raygui 5.1-dev): btnActive is kept and
# the result 0 when nothing was clicked; a click (the close button is 0)
# sets it and the result is 1.
law gui_reply_none:
  {JG.Gui.reply.of(7, 4294967295) == JG.GuiReply{7, 0} : JG.Gui.Reply}

law gui_reply_close:
  {JG.Gui.reply.of(7, 0) == JG.GuiReply{0, 1} : JG.Gui.Reply}

# GuiLoadIconsFromMemory's table is the data's words, little-endian.
law gui_icons_words_little_endian:
  {JG.Gui.icons.words(2n, [1, 0, 0, 0, 2, 1, 0, 0, 9], Nil{}) == [1, 258] : +List<U32>}

# GuiLoadStyle's 'v' line (raygui 5.1-dev): its %u value, other lines keep
# the version, and a '-' is refused.
law gui_style_version_line:
  {JG.Gui.rgs.version([118, 32, 54, 48, 48, 10], 0) == 600 : U32}

law gui_style_version_kept:
  {JG.Gui.rgs.version([112, 32, 49, 10], 600) == 600 : U32}

law gui_style_version_negative_refused:
  {JG.Gui.scan.fine(JG.Gui.rgs.version.scan([118, 32, 45, 49])) == False{} : Bool}

# An 'f' line names the font first from version 600, and each name is at
# most 31 bytes (the rest of a longer first word goes to the second).
law gui_style_font_line_modern:
  {JG.Gui.rgs.font.line([102, 32, 49, 54, 32, 97, 32, 98], True{}) == JG.GuiFontLine{16, [98], [97], True{}} : JG.Gui.FontLine}

law gui_style_font_line_31_bytes:
  {JG.Gui.rgs.font.line([102, 32, 49, 32, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 98, 99], False{})
    == JG.GuiFontLine{1, [97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97], [98, 99], True{}} : JG.Gui.FontLine}

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
  {J.AudioDevice.init(J.AudioDevice.none()) == J.AudioDevice{True{}, 1.0, 1, Nil{}, Nil{}, 0} : J.AudioDevice}

law audio_init_ready_unchanged:
  for +master: F32
  for +next: U32
  for +buffers: +List<J.AudioDevice.Buffer>
  for +blocks: +List<J.AudioDevice.Block>
  {J.AudioDevice.init(J.AudioDevice{True{}, master, next, buffers, blocks, 0}) == J.AudioDevice{True{}, master, next, buffers, blocks, 0} : J.AudioDevice}

law audio_close_keeps_buffers:
  for +master: F32
  for +next: U32
  for +buffers: +List<J.AudioDevice.Buffer>
  for +blocks: +List<J.AudioDevice.Block>
  {J.AudioDevice.close(J.AudioDevice{True{}, master, next, buffers, blocks, 0}) == J.AudioDevice{False{}, 0.0, next, buffers, blocks, 0} : J.AudioDevice}

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
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{1, 48000, 32, 2, [1056964608, 3204448256]}) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 1, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1056964608, 3204448256]}], 0}, Done{J.Sound{J.AudioStream{1, 48000, 32, 2}, 1}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_unready_device_refused:
  {J.Sound.load_from_wave(J.AudioDevice.none(), J.Wave{1, 48000, 16, 1, [16384]}) == (J.AudioDevice.none(), Fail{J.SoundDeviceNotReady{}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_zero_wave_is_zero_sound:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{0, 0, 0, 0, Nil{}}) == (J.AudioDevice.init(J.AudioDevice.none()), Done{J.Sound.none()}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

law sound_without_frames_has_empty_buffer:
  {J.Sound.load_from_wave(J.AudioDevice.init(J.AudioDevice.none()), J.Wave{0, 48000, 16, 1, Nil{}}) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 0, 0, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], Nil{}, 0}, Done{J.Sound{J.AudioStream{1, 48000, 32, 2}, 0}}) : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>}

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
  {J.Sound.load_alias(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == (J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) : J.AudioDevice & J.Sound}

law sound_alias_of_zero_sound:
  {J.Sound.load_alias(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound.none()) == (J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound.none()) : J.AudioDevice & J.Sound}

# PlaySound plays its own buffer only; StopSound leaves a paused buffer as it
# is (raylib stops buffers that are playing and not paused).
law sound_play_only_its_buffer:
  {J.Sound.play(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, True{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

law sound_played_is_playing:
  {J.Sound.is_playing(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == True{} : Bool}

law sound_paused_not_playing:
  {J.Sound.is_playing(J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == False{} : Bool}

law sound_stop_leaves_paused:
  {J.Sound.stop(J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.Sound.pause(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) : J.AudioDevice}

law sound_stop_after_play:
  {J.Sound.stop(J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

# SetSoundVolume sets its own buffer's volume only.
law sound_volume_only_its_buffer:
  {J.Sound.set_volume(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}, 0.25) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 0.25, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

# UnloadSound frees the block its buffer plays, UnloadSoundAlias only
# untracks the buffer.
law sound_unload_frees_block:
  {J.Sound.unload(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], Nil{}, 0} : J.AudioDevice}

law sound_unload_alias_keeps_block:
  {J.Sound.unload_alias(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

# UpdateSound writes the block every buffer over it plays; a request past
# the buffer changes nothing.
law sound_update_reaches_aliases:
  {J.Sound.data(J.Sound.update(J.AudioDevice{True{}, 1.0, 3, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}, J.AudioBuffer{2, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{2, 48000, 32, 2}, 2}, [9, 8], 1), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == Some{[9, 8, 3, 4]} : Maybe<&2, +List<U32>>}

law sound_update_past_buffer_ignored:
  {J.Sound.update(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}, [0, 0, 0, 0, 0, 0], 3) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

# Handles raylib cannot use change nothing: any buffer on an unready device,
# and a buffer that was unloaded.
law sound_unready_buffers_untouched:
  {J.Sound.play(J.AudioDevice.close(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice.close(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}) : J.AudioDevice}

law sound_unloaded_handle_ignored:
  {J.Sound.play(J.Sound.unload(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}), J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.Sound.unload(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head.new()}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) : J.AudioDevice}

# The mixer (AudioDevice.mix, docs/AUDIO.md#the-mixer). PlaySound starts a
# buffer from its first frame and a buffer that stops goes back to it; the
# frames its resampler holds stay.
law sound_play_from_the_start:
  {J.Sound.play(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, True{}, True{}, Mixer.Head{48000, 48000, 0, 0, 1, Resampler.St{1, 0, [5, 6], [7, 8], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, True{}, False{}, Mixer.Head{48000, 48000, 0, 0, 0, Resampler.St{1, 0, [5, 6], [7, 8], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

law sound_stop_back_to_the_start:
  {J.Sound.stop(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, True{}, False{}, Mixer.Head{48000, 48000, 0, 0, 1, Resampler.St{1, 0, [5, 6], [7, 8], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, False{}, False{}, Mixer.Head{48000, 48000, 0, 0, 0, Resampler.St{1, 0, [5, 6], [7, 8], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

law sound_stop_paused_keeps_its_place:
  {J.Sound.stop(J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, True{}, True{}, Mixer.Head{48000, 48000, 0, 0, 1, Resampler.St{1, 0, [0, 0], [0, 0], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0}, J.Sound{J.AudioStream{1, 48000, 32, 2}, 2}) == J.AudioDevice{True{}, 1.0, 2, [J.AudioBuffer{1, 1, 2, 1.0, 1.0, 0.0, True{}, True{}, Mixer.Head{48000, 48000, 0, 0, 1, Resampler.St{1, 0, [0, 0], [0, 0], [Resampler.Lane{0, 0, 0, 0}, Resampler.Lane{0, 0, 0, 0}], True{}}, Nil{}, Mixer.HeadStatic{}}}], [J.AudioBlock{1, [1, 2, 3, 4]}], 0} : J.AudioDevice}

# raudio's read of a static buffer (src/mixer.bend): the frames left, at most
# the frames asked for; it ends the buffer with its last frame; nothing when
# the buffer does not play, and nothing on the last frame of a buffer of an
# odd size (its cursor is past two halves of size/2 frames), where the buffer
# does not end either: the callback stops it for the short run.
law audio_read_within:
  {Mixer.read.count(8, 0, True{}, 3) == 3 : U32}

law audio_read_to_the_end:
  {Mixer.read.count(8, 6, True{}, 480) == 2 : U32}

law audio_read_ends_at_the_end:
  {Mixer.read.ends(8, 6, True{}, 2) == True{} : Bool}

law audio_read_goes_on_before_the_end:
  {Mixer.read.ends(8, 6, True{}, 1) == False{} : Bool}

law audio_read_stopped_buffer:
  {Mixer.read.count(8, 0, False{}, 3) == 0 : U32}

law audio_read_odd_last_frame_lost:
  {Mixer.read.count(5, 4, True{}, 1) == 0 : U32}

law audio_read_odd_last_frame_not_an_end:
  {Mixer.read.ends(5, 4, True{}, 1) == False{} : Bool}

law audio_read_odd_whole:
  {Mixer.read.count(5, 0, True{}, 480) == 5 : U32}

law audio_read_even_last_frame:
  {Mixer.read.count(4, 3, True{}, 1) == 1 : U32}

law audio_read_one_frame:
  {Mixer.read.count(1, 0, True{}, 4) == 1 : U32}

# raudio's read of a playing stream (src/mixer.bend): the frames left in the
# half the cursor is in, then the other half's from its start, each only
# while the device has not read that half through; the rest is silence. One
# read takes at most the frames 4096 bytes hold.
law audio_stream_read_to_the_end_of_the_half:
  {Mixer.read.here(960, 100, False{}, False{}, 480) == 380 : U32}

law audio_stream_read_goes_on_in_the_other_half:
  {Mixer.read.there(960, 100, False{}, False{}, 480) == 100 : U32}

law audio_stream_read_wraps_from_the_second_half:
  {(Mixer.read.here(960, 900, False{}, False{}, 480), Mixer.read.there(960, 900, False{}, False{}, 480)) == (60, 420) : U32 & U32}

law audio_stream_read_processed_half_gives_nothing:
  {(Mixer.read.here(960, 100, True{}, False{}, 480), Mixer.read.there(960, 100, True{}, False{}, 480)) == (0, 0) : U32 & U32}

law audio_stream_read_stops_at_a_processed_half:
  {Mixer.read.there(960, 100, False{}, True{}, 480) == 0 : U32}

law audio_stream_read_within_the_half:
  {(Mixer.read.here(960, 100, False{}, False{}, 200), Mixer.read.there(960, 100, False{}, False{}, 200)) == (200, 0) : U32 & U32}

law audio_read_cap_of_a_sound:
  {Mixer.read.cap(32, 2) == 512 : U32}

law audio_read_cap_of_a_16_bit_mono_stream:
  {Mixer.read.cap(16, 1) == 2048 : U32}

law audio_read_cap_of_a_wide_stream:
  {Mixer.read.cap(8, 1000) == 4 : U32}

# miniaudio's count of the input frames a converter needs carries the
# fractions of the output frames: floor((54 + 3*67)/80) whole frames here.
law audio_required_input_carries_fractions:
  {Mixer.carried(3n, 54, 67, 80, 0) == 3 : U32}

# A rate change keeps the resampler's place: the fraction of an input frame,
# counted in the old reduced output rate, becomes one in the new rate, and its
# whole frames move to the frames due.
law audio_rate_change_keeps_the_fraction:
  {Mixer.retimed(Resampler.St{0, 1, Nil{}, Nil{}, Nil{}, True{}}, 2, 3) == Resampler.St{0, 1, Nil{}, Nil{}, Nil{}, True{}} : Resampler.St}

law audio_rate_change_carries_whole_frames:
  {Mixer.retimed(Resampler.St{0, 5, Nil{}, Nil{}, Nil{}, True{}}, 2, 3) == Resampler.St{2, 1, Nil{}, Nil{}, Nil{}, True{}} : Resampler.St}

law audio_rate_unchanged_at_the_device_rate:
  {Mixer.Head.pitched(Mixer.Head.new(), 48000) == Mixer.Head.new() : Mixer.Head}

# A buffer's converter has miniaudio's first-order filter, whose coefficient
# is an exp(-w): the fixed-point series gives exactly 1 for w = 0.
law audio_first_order_series_at_zero:
  {Lowpass.fx.exp_neg(Lowpass.fx.zeros(9n, Nil{})) == Lowpass.fx.one() : +List<U32>}

# The callback runs with denormals disabled, as miniaudio sets it on x86: a
# subnormal is the zero of its sign there, and the smallest normal number is
# itself. A NaN (not an infinity) is what a callback is refused for.
law audio_mix_subnormal_is_zero:
  {Mixer.zero.word(1) == 0 : U32}

law audio_mix_negative_subnormal_is_negative_zero:
  {Mixer.zero.word(2155872255) == 2147483648 : U32}

law audio_mix_smallest_normal_kept:
  {Mixer.zero.word(8388608) == 8388608 : U32}

law audio_mix_nan_refused:
  {Mixer.nan(2143289344) == True{} : Bool}

law audio_mix_infinity_itself_fine:
  {Mixer.nan(2139095040) == False{} : Bool}

# No callback on an unready device, and none of no frames.
law audio_mix_unready_refused:
  {J.AudioDevice.mix(J.AudioDevice.none(), 4) == (J.AudioDevice.none(), None{}) : J.AudioDevice & Maybe<&2, +List<U32>>}

law audio_mix_no_frames_refused:
  {J.AudioDevice.mix(J.AudioDevice.init(J.AudioDevice.none()), 0) == (J.AudioDevice.init(J.AudioDevice.none()), None{}) : J.AudioDevice & Maybe<&2, +List<U32>>}

# The device's clock: the periods still to ask for are those due less those
# already asked for, none twice; a time before the device was opened and an
# unknown count are refused. No period, no callback; and a callback Jonlib
# does not make (here: an unready device) ends the catching up.
law audio_clock_periods_owed:
  {J.AudioClock.owed(3, Some{7}) == Some{4} : Maybe<U32>}

law audio_clock_no_period_twice:
  {J.AudioClock.owed(7, Some{7}) == Some{0} : Maybe<U32>}

law audio_clock_earlier_time_owes_nothing:
  {J.AudioClock.owed(7, Some{5}) == Some{0} : Maybe<U32>}

law audio_clock_before_opening_refused:
  {J.AudioClock.owed(0, Some{4294967295}) == None{} : Maybe<U32>}

law audio_clock_unknown_time_refused:
  {J.AudioClock.owed(0, None{}) == None{} : Maybe<U32>}

law audio_clock_no_period_no_callback:
  {J.AudioClock.pump(0n, (J.AudioDevice.none(), Some{Nil{}})) == (J.AudioDevice.none(), True{}) : J.AudioDevice & Bool}

law audio_clock_refused_callback_stops:
  {J.AudioClock.pump(3n, (J.AudioDevice.none(), Some{Nil{}})) == (J.AudioDevice.none(), False{}) : J.AudioDevice & Bool}

# Music streams: a music is valid with a decoder, frames and a stream's
# rate, size and channels, with or without a buffer; a stop takes the decoder
# back to its first frame and a seek no further than the file's last; a read
# past the end goes on from the first frame; the frames played are a C
# remainder brought into 0..frames-1; and the frames still in the halves are
# no more than the music has unless it loops. A 32-bit float's bytes are its
# bits, swapped from a big-endian container.
law music_none_invalid:
  {J.Music.is_valid(J.Music.none()) == False{} : Bool}

law music_valid_without_buffer:
  {J.Music.is_valid(J.Music{J.AudioStream{0, 44100, 16, 2}, 700, True{}, 1, J.MusicWav{[1, 2], 0}}) == True{} : Bool}

law music_stop_rewinds:
  {J.Music.context.rewound(J.MusicWav{[1, 2, 3, 4], 2}) == J.MusicWav{[1, 2, 3, 4], 0} : J.Music.Context}

law music_seek_within:
  {J.Music.context.sought(J.MusicWav{[1, 2, 3, 4], 0}, 3, 4) == J.MusicWav{[1, 2, 3, 4], 3} : J.Music.Context}

law music_seek_stops_at_the_end:
  {J.Music.context.sought(J.MusicWav{[1, 2, 3, 4], 0}, 9, 4) == J.MusicWav{[1, 2, 3, 4], 4} : J.Music.Context}

law music_read_goes_round:
  {J.Music.wav.read(5n, False{}, [1, 2, 3, 4, 5, 6], 1, 6, 4, 5, Nil{}) == ([3, 2, 1, 6, 5], 3) : +List<U32> & U32}

law music_read_within:
  {J.Music.wav.read(5n, False{}, [1, 2, 3, 4, 5, 6], 2, 3, 1, 1, Nil{}) == ([4, 3], 2) : +List<U32> & U32}

law music_played_negative_wraps:
  {J.Music.played.wrapped(4294967295, 700) == 699 : U32}

law music_played_whole_turns:
  {J.Music.played.wrapped(1400, 700) == 0 : U32}

law music_played_negative_whole_turn:
  {J.Music.played.wrapped(4294966596, 700) == 0 : U32}

law music_buffered_no_more_than_the_music:
  {J.Music.played.buffered(False{}, False{}, 480, 700, False{}) == 700 : U32}

law music_buffered_looping:
  {J.Music.played.buffered(False{}, False{}, 480, 700, True{}) == 960 : U32}

law music_buffered_one_half:
  {J.Music.played.buffered(True{}, False{}, 480, 700, False{}) == 480 : U32}

# QOA music: the header counts the frames; a seek goes to the start of the
# QOA frame (5120 samples) the position is in, at most the last frame's, and
# that is what the stream is told it was given (a WAV music: the position).
law music_qoa_declared_frames:
  {J.Music.qoa.declared([113, 111, 97, 102, 0, 0, 172, 68, 1]) == 44100 : U32}

law music_qoa_seek_to_its_frame:
  {J.Music.qoa.sought(11025, 44100) == 10240 : U32}

law music_qoa_seek_last_frame:
  {J.Music.qoa.sought(1102500, 44100) == 40960 : U32}

law music_qoa_seek_gives_its_frame:
  {J.Music.context.given(J.MusicQoa{Nil{}, 0}, 11025, 44100) == 10240 : U32}

law music_wav_seek_gives_the_position:
  {J.Music.context.given(J.MusicWav{Nil{}, 0}, 11025, 700) == 11025 : U32}

law music_qoa_stop_rewinds:
  {J.Music.context.rewound(J.MusicQoa{[1, 2], 1}) == J.MusicQoa{[1, 2], 0} : J.Music.Context}

# A QOA file's samples are gathered frame by frame, the last first.
law qoa_frame_samples_gathered:
  {Qoa.take.onto(2n, [7, 8, 9], [1]) == [8, 7, 1] : +List<U32>}

law music_float_bits_as_they_are:
  {Wav.wide.sample(12, [0, 0, 128, 63]) == 1065353216 : U32}

law music_float_bits_big_endian:
  {Wav.wide.sample(13, [63, 128, 0, 0]) == 1065353216 : U32}

# MP3 (src/mp3.bend, dr_mp3). The header of raylib's country.mp3, FF FB 90 44,
# is MPEG-1 Layer III at 128 kbit/s and 44100 Hz: 1152 samples in 417 bytes,
# one more with the padding bit; without a bit rate the frame's size is the
# free format's; MPEG-2 halves the rate and the samples, and Layer I has 384.
# A reserved layer, bit rate or sample rate is no header, and two headers are
# of one stream when their version, layer and sample rate agree.
law mp3_header_valid:
  {Mp3.hdr.valid(4294676548) == True{} : Bool}

law mp3_header_bit_rate:
  {Mp3.hdr.kbps(4294676548) == 128 : U32}

law mp3_header_sample_rate:
  {Mp3.hdr.hz(4294676548) == 44100 : U32}

law mp3_header_samples:
  {Mp3.hdr.samples(4294676548) == 1152 : U32}

law mp3_header_frame_bytes:
  {Mp3.hdr.bytes(4294676548, 0) == 417 : U32}

law mp3_header_padding_byte:
  {Mp3.hdr.padding(4294677060) == 1 : U32}

law mp3_header_free_format_size:
  {Mp3.hdr.bytes(4294639684, 300) == 300 : U32}

law mp3_header_mpeg2_rate:
  {Mp3.hdr.hz(4294152260) == 22050 : U32}

# MP3 Layers I and II (src/mp3_layer12.bend, drmp3_L12_subband_alloc_table
# and drmp3_L12_dequantize_granule). The bands a header's table has and how
# many of them are coded for each channel: Layer I's 32, joint stereo's
# bound (mode extension 2: 12); MPEG-1 Layer II's 27 at 64 kbit/s a
# channel, 30 at 192 in mono at 44100 Hz, 8 below 56; MPEG-2 Layer II's 30.
law mp3_layer1_bands:
  {Mp3L12.Layout.total(Mp3L12.layout.of(4294918240)) == 32 : U32}

law mp3_layer1_joint_stereo_bound:
  {Mp3L12.Layout.stereo(Mp3L12.layout.of(4294918240)) == 12 : U32}

law mp3_layer2_twenty_seven_bands:
  {Mp3L12.Layout.total(Mp3L12.layout.of(4294803456)) == 27 : U32}

law mp3_layer2_thirty_bands_in_mono:
  {Mp3L12.Layout.total(Mp3L12.layout.of(4294811840)) == 30 : U32}

law mp3_layer2_mono_has_no_stereo_bands:
  {Mp3L12.Layout.stereo(Mp3L12.layout.of(4294811840)) == 0 : U32}

law mp3_layer2_low_rate_bands:
  {Mp3L12.Layout.total(Mp3L12.layout.of(4294779072)) == 8 : U32}

law mp3_layer2_mpeg2_bands:
  {Mp3L12.Layout.total(Mp3L12.layout.of(4294279360)) == 30 : U32}

# The bits a band's samples take in a granule: none unallocated, `ba` a
# sample below 17, and one code of 5, 7 or 10 bits for three samples in
# base 3, 5 or 9.
law mp3_layer12_unallocated_band_reads_nothing:
  {Mp3L12.band.bits(0, 3) == 0 : U32}

law mp3_layer12_plain_band_bits:
  {Mp3L12.band.bits(5, 3) == 15 : U32}

law mp3_layer12_grouped_base_three:
  {Mp3L12.band.bits(17, 3) == 5 : U32}

law mp3_layer12_grouped_base_five:
  {Mp3L12.band.bits(18, 3) == 7 : U32}

law mp3_layer12_grouped_base_nine:
  {Mp3L12.band.bits(19, 3) == 10 : U32}

law mp3_header_mpeg2_samples:
  {Mp3.hdr.samples(4294152260) == 576 : U32}

law mp3_header_layer1_samples:
  {Mp3.hdr.samples(4294938692) == 384 : U32}

law mp3_header_reserved_layer:
  {Mp3.hdr.valid(4294545476) == False{} : Bool}

law mp3_header_reserved_sample_rate:
  {Mp3.hdr.valid(4294679620) == False{} : Bool}

law mp3_header_reserved_bit_rate:
  {Mp3.hdr.valid(4294701124) == False{} : Bool}

law mp3_header_same_stream_with_padding:
  {Mp3.hdr.compare(4294676548, 4294677060) == True{} : Bool}

law mp3_header_other_sample_rate_other_stream:
  {Mp3.hdr.compare(4294676548, 4294677572) == False{} : Bool}

# Bits are read by position, the first the highest, and are 0 past the limit
# (dr_mp3's reader gives 0 once its position is past it).
law mp3_bits_by_position:
  {Mp3.bits([171, 205], 16, 4, 8) == 188 : U32}

law mp3_bits_past_the_limit:
  {Mp3.bits([171, 205], 16, 12, 8) == 0 : U32}

law mp3_word_first_byte_highest:
  {Mp3.word([1, 2, 3, 4, 5]) == 16909060 : U32}

# The stream's tags: an ID3v2 tag is ten bytes and its size in four bytes of
# seven bits, ten more with a footer; an Xing/Info frame's fields are where
# its flags say; and the frames it counts lose LAME's delay and padding, each
# only when no more than what is left.
law mp3_id3v2_size:
  {Mp3.tags.id3v2([73, 68, 51, 4, 0, 0, 0, 0, 0, 21]) == 31 : U32}

law mp3_id3v2_footer:
  {Mp3.tags.id3v2([73, 68, 51, 4, 0, 16, 0, 0, 0, 5]) == 25 : U32}

law mp3_no_id3v2:
  {Mp3.tags.id3v2([255, 251, 144, 68, 0, 0, 0, 0, 0, 0]) == 0 : U32}

law mp3_info_every_field:
  {Mp3.info.fields(15) == 120 : U32}

law mp3_info_no_field:
  {Mp3.info.fields(0) == 8 : U32}

law mp3_total_less_delay_and_padding:
  {Mp3.total.tagged(4127616, 1105, 577, False{}) == 4125934 : U32}

law mp3_total_delay_too_large_ignored:
  {Mp3.total.tagged(1000, 1105, 577, False{}) == 423 : U32}

# dr_mp3 reads no more than it thinks is left of the stream, and no more than
# the file has; and a file of fewer than ten bytes does not open.
law mp3_read_clamped_to_the_stream:
  {Mp3.stream.read(1000, 900, 100, 100, 65536) == 800 : U32}

law mp3_read_clamped_to_the_file:
  {Mp3.stream.read(1000, 900, 950, 500, 65536) == 50 : U32}

law mp3_short_file_does_not_open:
  {Mp3.open([255, 251, 144, 68]) == None{} : Maybe<Mp3.Opened>}

# MP3 Layer III (src/mp3_layer3.bend, src/mp3_tables.bend, dr_mp3). A
# granule's scalefactor bands are its sample rate's row of the long, short or
# mixed table (country.mp3's header again); codebooks 16 to 23 are one
# Huffman table read with different linbits, and 4 has no values, as 0. The
# scalefactors' sizes are g_scfc_decode's in MPEG-1 and scalefac_compress in
# the mixed radix of g_mod's rows in MPEG-2 (halved for the second channel
# of an intensity stereo frame, whose rows are the last three); they are
# read in groups, a group that scfsi keeps taking the granule before's, and
# an MPEG-2 intensity position of all ones is 255. The cache takes bytes
# while it has room for one, and a byte past the main data's array counts:
# the granule is refused. A quad of the count1 region is plus or minus the
# band's scale where its code has the value, by the bit that follows. The
# right channel's top band in each window gives the last band's intensity
# position its default, or the band before's. A frame's main data is written
# over the start of what the array held, and is decoded when the reservoir
# reaches main_data_begin. A mixed block's short bands are reordered inside
# the granule's 576 values except at 8000 Hz (FF E3 18 00), where dr_mp3
# writes 24 past them: refused.
law mp3_long_bands_of_44100:
  {Mp3L3.bands(4294676548, 0) == [4, 4, 4, 4, 4, 4, 6, 6, 8, 8, 10, 12, 16, 20, 24, 28, 34, 42, 50, 54, 76, 158, 0] : +List<U32>}

law mp3_short_bands_of_44100:
  {Mp3.count(Mp3L3.bands(4294676548, 1), 0) == 40 : U32}

law mp3_mixed_bands_begin_long:
  {Mp3.take(8, Mp3L3.bands(4294676548, 2)) == [4, 4, 4, 4, 4, 4, 6, 6] : +List<U32>}

law mp3_codebooks_share_a_table:
  {Mp3T.book(16) == Mp3T.book(23) : +List<U32>}

law mp3_codebook_without_values:
  {Mp3T.book(4) == Mp3T.book(0) : +List<U32>}

law mp3_codebook_entries:
  {Mp3.count(Mp3T.book(31), 0) == 322 : U32}

law mp3_scalefactor_sizes_mpeg1:
  {Mp3L3.sizes.of(True{}, 4, False{}) == Mp3L3.Sizes{[3, 3, 0, 0], 0} : Mp3L3.Sizes}

law mp3_scalefactor_sizes_mpeg2:
  {Mp3L3.sizes.of(False{}, 399, False{}) == Mp3L3.Sizes{[4, 4, 3, 3], 4} : Mp3L3.Sizes}

law mp3_scalefactor_sizes_mpeg2_second_row:
  {Mp3L3.sizes.of(False{}, 400, False{}) == Mp3L3.Sizes{[0, 0, 0, 0], 8} : Mp3L3.Sizes}

law mp3_scalefactor_sizes_intensity_halved:
  {Mp3L3.sizes.of(False{}, 3, True{}) == Mp3L3.Sizes{[0, 0, 1, 0], 16} : Mp3L3.Sizes}

law mp3_scalefactors_read_in_groups:
  {Mp3L3.read.groups(4n, False{}, [3, 3, 0, 0], [2, 1, 1, 1], [177, 128], 16, 0, Mp3L3.Read{Nil{}, Nil{}, [9, 9, 9, 9, 9, 9], 0}) == Mp3L3.Read{[0, 0, 3, 4, 5], [0, 0, 3, 4, 5], [9], 9} : Mp3L3.Read}

law mp3_scalefactors_kept_by_scfsi:
  {Mp3L3.read.groups(4n, False{}, [3, 3, 0, 0], [2, 1, 1, 1], [177, 128], 16, 8, Mp3L3.Read{Nil{}, Nil{}, [7, 6, 9, 9, 9, 9], 0}) == Mp3L3.Read{[0, 0, 5, 6, 7], [0, 0, 5, 6, 7], [9], 3} : Mp3L3.Read}

law mp3_intensity_position_of_all_ones_mpeg2:
  {Mp3L3.read.groups(4n, False{}, [2, 0, 0, 0], [2, 0, 0, 0], [208], 8, 4294967280, Mp3L3.Read{Nil{}, Nil{}, Nil{}, 0}) == Mp3L3.Read{[1, 3], [1, 255], Nil{}, 4} : Mp3L3.Read}

law mp3_cache_filled_by_bytes:
  {Mp3L3.run.fill(5n, True{}, [171, 205, 7], 4, 0, 16, Nil{}) == Mp3L3.Run{[7], 6, 43981, 0, Nil{}} : Mp3L3.Run}

law mp3_cache_past_the_bytes_counts:
  {Mp3L3.run.fill(5n, True{}, Nil{}, 4, 1, 8, Nil{}) == Mp3L3.Run{Nil{}, 5, 1, 0, Nil{}} : Mp3L3.Run}

law mp3_quad_signs:
  {Mp3L3.quad.pair(1, 1, 1065353216, Nil{}, 4, 2147483648, 0, Nil{}) == Mp3L3.Run{Nil{}, 4, 0, 2, [1065353216, 3212836864]} : Mp3L3.Run}

law mp3_quad_value_absent:
  {Mp3L3.quad.pair(0, 1, 1065353216, Nil{}, 4, 2147483648, 0, Nil{}) == Mp3L3.Run{Nil{}, 4, 0, 1, [3212836864, 0]} : Mp3L3.Run}

law mp3_count1_quad:
  {Mp3.take(5, Mp3L3.Spectrum.values(Mp3L3.spectrum([10, 0, 0, 0, 0, 0, 0, 0], 8, 0, 8, 4294676548, Mp3.Gr{8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 1, 0, 0, 22, 0}, [1065353216]))) == [3212836864, 1065353216, 3212836864, 1065353216, 0] : +List<U32>}

law mp3_granule_576_values:
  {Mp3.count(Mp3L3.Spectrum.values(Mp3L3.spectrum([10, 0, 0, 0, 0, 0, 0, 0], 8, 0, 8, 4294676548, Mp3.Gr{8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 1, 0, 0, 22, 0}, [1065353216])), 0) == 576 : U32}

law mp3_values_read_inside_the_array:
  {Mp3L3.Spectrum.fine(Mp3L3.spectrum([10, 0, 0, 0, 0, 0, 0, 0], 8, 0, 8, 4294676548, Mp3.Gr{8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 1, 0, 0, 22, 0}, [1065353216])) == True{} : Bool}

law mp3_values_read_past_the_array_refused:
  {Mp3L3.Spectrum.fine(Mp3L3.spectrum([10, 0, 0, 0], 4, 0, 8, 4294676548, Mp3.Gr{8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 1, 0, 0, 22, 0}, [1065353216])) == False{} : Bool}

law mp3_top_bands_by_window:
  {Mp3L3.tops(4n, [2, 2, 2, 2], [0, 0, 0, 2147483648, 5, 0, 0, 0], 0, 0, 0, 0) == Mp3L3.Tops{0, 0, 3} : Mp3L3.Tops}

law mp3_intensity_position_default:
  {Mp3L3.positions(Mp3L3.Tops{3, 3, 3}, [1, 2, 7, 4, 5, 6], 4, 0, 3) == [1, 2, 7, 3, 5, 6] : +List<U32>}

law mp3_intensity_position_of_the_band_before:
  {Mp3L3.positions(Mp3L3.Tops{2, 2, 2}, [1, 2, 7, 4, 5, 6], 4, 0, 3) == [1, 2, 7, 7, 5, 6] : +List<U32>}

law mp3_intensity_positions_of_the_windows:
  {Mp3L3.positions(Mp3L3.Tops{1, 0, 0}, [1, 2, 3, 4, 5, 6, 7], 6, 6, 0) == [1, 2, 3, 0, 2, 3, 7] : +List<U32>}

law mp3_array_keeps_what_was_there:
  {Mp3L3.frame.array([1, 2], 2, [9, 8, 7, 6]) == [1, 2, 7, 6] : +List<U32>}

law mp3_reservoir_short_decodes_nothing:
  {Mp3L3.side.state(Mp3.Side{False{}, 5, Nil{}, 136}, 3336, 4) == 1 : U32}

law mp3_reservoir_reached_decodes:
  {Mp3L3.side.state(Mp3.Side{False{}, 5, Nil{}, 136}, 3336, 5) == 2 : U32}

law mp3_side_information_refused:
  {Mp3L3.side.state(Mp3.Side{True{}, 0, Nil{}, 136}, 3336, 511) == 0 : U32}

law mp3_no_frame_in_no_bytes:
  {Mp3L3.decode(Mp3L3.Decoder.zero(), Nil{}, 0) == Mp3L3.Decoded{Mp3L3.Decoder.zero(), 0, 0, 0, Nil{}, Nil{}} : Mp3L3.Decoded}

law mp3_mixed_block_reordered_inside_the_granule:
  {Mp3L3.reorder.inside(4294676548, Mp3.Gr{0, 0, 0, 0, 2, 1, 0, 0, 0, 7, 255, 255, 0, 0, 0, 0, 0, 0, 0, 2, 8, 30}) == True{} : Bool}

law mp3_mixed_block_at_8000_hz_refused:
  {Mp3L3.reorder.inside(4293072896, Mp3.Gr{0, 0, 0, 0, 2, 1, 0, 0, 0, 7, 255, 255, 0, 0, 0, 0, 0, 0, 0, 2, 6, 30}) == False{} : Bool}

law mp3_short_block_at_8000_hz_inside:
  {Mp3L3.reorder.inside(4293072896, Mp3.Gr{0, 0, 0, 0, 2, 0, 0, 0, 0, 8, 255, 255, 0, 0, 0, 0, 0, 0, 0, 1, 0, 39}) == True{} : Bool}

# The stereo step (drmp3_L3_decode): the header's intensity bit asks for
# drmp3_L3_intensity_stereo whatever the frame's mode (FF FB 90 54 is joint
# stereo, FF FB 90 D4 mono); mid/side is joint stereo with its bit and
# without the intensity bit (FF FB 90 64; FF FB 90 24 is plain stereo). A
# granule with long bands shares one top band between its windows. A band is
# an intensity band when it is past the right channel's top band and its
# position is below 7 in MPEG-1; a mono frame's right channel is zeros. The
# shift of MPEG-2's intensity scale is read from the granule information's
# second slot, which keeps what the last frame that wrote it left.
law mp3_top_bands_shared_with_long_bands:
  {Mp3L3.tops.merged(Mp3L3.Tops{0, 0, 3}, 4) == Mp3L3.Tops{3, 3, 3} : Mp3L3.Tops}

law mp3_top_bands_of_short_blocks_apart:
  {Mp3L3.tops.merged(Mp3L3.Tops{1, 0, 0}, 0) == Mp3L3.Tops{1, 0, 0} : Mp3L3.Tops}

law mp3_stereo_step_intensity:
  {Mp3L3.stereo.mode(4294676564) == 1 : U32}

law mp3_stereo_step_intensity_in_a_mono_frame:
  {Mp3L3.stereo.mode(4294676692) == 1 : U32}

law mp3_stereo_step_midside:
  {Mp3L3.stereo.mode(4294676580) == 2 : U32}

law mp3_stereo_step_midside_only_in_joint_stereo:
  {Mp3L3.stereo.mode(4294676516) == 0 : U32}

law mp3_stereo_step_none:
  {Mp3L3.stereo.mode(4294676548) == 0 : U32}

law mp3_stereo_values_kept:
  {Mp3L3.pair.kept(2n, [1, 2, 3], [7], Nil{}, Nil{}) == Mp3L3.Both{[3], Nil{}, [2, 1], [0, 7]} : Mp3L3.Both}

law mp3_intensity_position_7_is_no_intensity_band:
  {Mp3L3.stereo.bands(40n, False{}, [2, 2, 0], [7, 7], 0, Mp3L3.Tops{0, 0, 0}, True{}, 0, False{}, Nil{}, Mp3L3.Both{[1, 2, 3, 4], [5, 6, 7, 8], Nil{}, Nil{}}) == Mp3L3.Both{Nil{}, Nil{}, [4, 3, 2, 1], [8, 7, 6, 5]} : Mp3L3.Both}

law mp3_band_below_the_top_band_is_no_intensity_band:
  {Mp3L3.stereo.bands(40n, False{}, [2, 0], [0], 0, Mp3L3.Tops{1, 0, 0}, True{}, 0, False{}, Nil{}, Mp3L3.Both{[1, 2], [5, 6], Nil{}, Nil{}}) == Mp3L3.Both{Nil{}, Nil{}, [2, 1], [6, 5]} : Mp3L3.Both}

law mp3_second_slot_compress_written:
  {Mp3L3.slot.compress([Mp3.Gr{0, 288, 0, 5, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 22, 0}], 9) == 5 : U32}

law mp3_second_slot_compress_left_by_too_many_big_values:
  {Mp3L3.slot.compress([Mp3.Gr{0, 289, 0, 5, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 22, 0}], 9) == 9 : U32}

law mp3_second_slot_compress_left_by_a_mono_frame:
  {Mp3L3.slot.compress(Nil{}, 9) == 9 : U32}

# The filter bank's first half (the second loop of drmp3_L3_decode). A
# granule with the mixed block flag has two long subbands, four at 8000 Hz.
# A short band's three windows, one after another in the values, are
# interleaved from the end of the long part on. The alias reduction crosses
# all 31 boundaries of a granule without short bands, only those inside the
# long subbands of a mixed block, none in short blocks. A subband is
# transformed long in the long part, else by the block type (the start block
# with the long window). The sign change turns the odd values of the odd
# subbands, and a mono frame leaves the right channel's overlap alone.
law mp3_long_subbands_of_a_mixed_block:
  {Mp3L3.long.subbands(4294676548, 1) == 2 : U32}

law mp3_long_subbands_at_8000_hz:
  {Mp3L3.long.subbands(4293072896, 1) == 4 : U32}

law mp3_no_long_subbands_without_the_mixed_flag:
  {Mp3L3.long.subbands(4294676548, 0) == 0 : U32}

law mp3_values_moved_last_first:
  {Mp3L3.moved(2n, [1, 2, 3], [9]) == Mp3L3.Moved{[3], [2, 1, 9]} : Mp3L3.Moved}

law mp3_short_windows_interleaved:
  {Mp3L3.reorder([0, 1, 10, 11, 20, 21, 30, 31, 99], 2, [2, 2, 2, 0]) == [0, 1, 10, 20, 30, 11, 21, 31, 99] : +List<U32>}

law mp3_alias_reduction_between_all_long_subbands:
  {Mp3L3.alias.count(0, 0) == 31 : U32}

law mp3_alias_reduction_inside_a_mixed_block_long_part:
  {Mp3L3.alias.count(30, 2) == 1 : U32}

law mp3_no_alias_reduction_in_short_blocks:
  {Mp3L3.alias.count(39, 0) == 0 : U32}

law mp3_no_boundary_no_alias_reduction:
  {Mp3L3.antialias([1, 2, 3], 0) == [1, 2, 3] : +List<U32>}

law mp3_mixed_block_long_part_transformed_long:
  {Mp3L3.imdct.mode(1, 2, 2) == 0 : U32}

law mp3_short_block_transformed_short:
  {Mp3L3.imdct.mode(2, 2, 2) == 2 : U32}

law mp3_stop_block_window:
  {Mp3L3.imdct.mode(5, 0, 3) == 1 : U32}

law mp3_start_block_long_window:
  {Mp3L3.imdct.mode(5, 0, 1) == 0 : U32}

law mp3_sign_change_in_odd_subbands:
  {Mp3L3.signs([5, 4, 3], 20, Nil{}) == [3, 2147483652, 5] : +List<U32>}

law mp3_no_sign_change_in_even_subbands:
  {Mp3L3.signs([5, 4, 3], 2, Nil{}) == [3, 4, 5] : +List<U32>}

law mp3_mono_frame_keeps_the_right_overlap:
  {Mp3L3.filter.right(True{}, Nil{}, [1, 2], 4294676692, Mp3.Gr{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 22, 0}) == Mp3L3.Out{Nil{}, [1, 2]} : Mp3L3.Out}

# The synthesis filter (drmp3d_synth_granule). A time slot is the next
# sample of each subband, which are eighteen samples each. The window's sums
# become 16-bit samples by the processor's rounding (to nearest, a tie to
# the even integer), computed from the float's significand and the bits to
# cut from it. A row of the filter's buffer is fifteen groups of four
# entries, two of which the next call writes; a mono frame keeps the right
# channel's entries of the rows before it. A frame's samples are a channel
# after a channel, and a granule's nine calls in order.
law mp3_time_slot_takes_each_subband_next_sample:
  {Mp3L3.slot.heads([[1, 2], [3, 4]], Nil{}, Nil{}) == Mp3L3.Slot{[1, 3], [[2], [4]]} : Mp3L3.Slot}

law mp3_subbands_of_eighteen_samples:
  {Mp3L3.row.first(Mp3L3.subbands(2n, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19], Nil{})) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19] : +List<U32>}

law mp3_second_subband_begins_eighteen_later:
  {Mp3L3.row(Mp3L3.subbands(2n, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19], Nil{}), 1) == [18, 19] : +List<U32>}

law mp3_sum_rounded_to_nearest:
  {Mp3L3.int.nearest(14680064, 23) == 2 : U32}

law mp3_one_and_a_half_rounded_to_two:
  {Mp3L3.int.nearest(12582912, 23) == 2 : U32}

law mp3_sum_rounded_down:
  {Mp3L3.int.nearest(10485760, 23) == 1 : U32}

law mp3_tie_rounded_to_even_down:
  {Mp3L3.int.nearest(10485760, 22) == 2 : U32}

law mp3_tie_rounded_to_even_up:
  {Mp3L3.int.nearest(14680064, 22) == 4 : U32}

law mp3_half_rounded_to_zero:
  {Mp3L3.int.nearest(8388608, 24) == 0 : U32}

# A float is made from its bits by arithmetic: its significand as an integer
# times two to the power of its exponent field less 150. 1.0 is 2^23 times
# 2^-23; the smallest subnormal 1 times 2^-149 (its field counts as 1 and it
# has no hidden bit); the largest float a significand times 2^104; 2^23 its
# significand as it is. The sign is apart.
law mp3_float_power_of_one:
  {Mp3L3.float.power(1065353216) == 23 : U32}

law mp3_float_one_scaled_down:
  {Mp3L3.float.down(1065353216) == True{} : Bool}

law mp3_float_power_of_a_subnormal:
  {Mp3L3.float.power(1) == 149 : U32}

law mp3_float_subnormal_without_hidden_bit:
  {Mp3L3.float.significand(1) == 1 : U32}

law mp3_float_power_of_the_largest:
  {Mp3L3.float.power(2139095039) == 104 : U32}

law mp3_float_largest_scaled_up:
  {Mp3L3.float.down(2139095039) == False{} : Bool}

law mp3_float_integer_significand_at_2_to_23:
  {Mp3L3.float.power(1258291200) == 0 : U32}

law mp3_float_sign_not_in_the_power:
  {Mp3L3.float.power(3212836864) == 23 : U32}

law mp3_float_significand:
  {Mp3L3.float.significand(1065353216) == 8388608 : U32}

law mp3_float_integer_cut:
  {Mp3L3.float.cut(1191181824) == 9 : U32}

law mp3_negative_sample_bits:
  {Mp3L3.int16(True{}, 1) == 65535 : U32}

law mp3_lowest_sample_bits:
  {Mp3L3.int16(True{}, 32768) == 32768 : U32}

law mp3_row_groups_of_four:
  {Mp3L3.row.groups(2n, [1, 2], [3, 4], [5, 6], [7, 8], Nil{}) == [8, 6, 4, 2, 7, 5, 3, 1] : +List<U32>}

law mp3_row_completed_by_the_next_call:
  {Mp3L3.row.completed(2n, [1, 2, 0, 0, 5, 6, 0, 0, 9], [7, 8], [3, 4], Nil{}) == [1, 2, 7, 3, 5, 6, 8, 4, 9] : +List<U32>}

law mp3_mono_row_keeps_the_right_entries:
  {Mp3L3.row.merged([1, 2, 3, 4], [9, 8, 7, 6], Nil{}) == [1, 8, 3, 6] : +List<U32>}

law mp3_stereo_samples_left_then_right:
  {Mp3L3.onto(False{}, 1, 2, [9]) == [1, 2, 9] : +List<U32>}

law mp3_mono_samples_left_only:
  {Mp3L3.onto(True{}, 1, 2, [9]) == [1, 9] : +List<U32>}

law mp3_samples_built_backwards:
  {Mp3L3.onto.back(False{}, 1, 2, [9]) == [2, 1, 9] : +List<U32>}

law mp3_calls_joined_in_order:
  {Mp3L3.blocks.joined([[3, 4], [1, 2]], Nil{}) == [1, 2, 3, 4] : +List<U32>}

law mp3_history_of_the_newest_rows:
  {Mp3L3.rows.newest(1n, [[1], [2]], Nil{}) == [[1]] : +List<+List<U32>>}

# MP3 streams (src/mp3_stream.bend, dr_mp3's drmp3). A read first passes the
# frames of the LAME delay, which count in currentPCMFrame and not in what
# is read; it takes what the frame at hand has, no more than is wanted, and
# with an Xing/Info total no further than the total less the padding. A
# frame's samples are written over the start of those before, and a seek
# forward passes samples without keeping them. A seek goes by the count:
# frame 0 is the start, the count itself is no move, a later frame is read
# up to and an earlier one read up to from the start. A file too short to
# open has no stream, a read of no frame changes nothing, and a stream that
# stopped gives no frame.
law mp3_delay_passed_before_a_read:
  {Mp3S.turn.skip(0, 1105, 1152) == 1105 : U32}

law mp3_delay_longer_than_a_frame:
  {Mp3S.turn.skip(0, 1105, 576) == 576 : U32}

law mp3_no_delay_left:
  {Mp3S.turn.skip(1105, 1105, 47) == 0 : U32}

law mp3_read_takes_what_the_frame_has:
  {Mp3S.turn.take(47, 100, False{}, 0, 1105) == 47 : U32}

law mp3_read_takes_what_is_wanted:
  {Mp3S.turn.take(1152, 100, False{}, 0, 0) == 100 : U32}

law mp3_read_ends_at_the_padding:
  {Mp3S.turn.take(1152, 100, True{}, 4127039, 4127000) == 39 : U32}

law mp3_frame_written_over_the_samples_before:
  {Mp3S.pcm.written([1, 2], [9, 8, 7, 6]) == [1, 2, 7, 6] : +List<U32>}

law mp3_samples_taken_from_the_frame:
  {Mp3S.pcm.copied(True{}, [5, 6, 7, 8], 1, 2) == [6, 7] : +List<U32>}

law mp3_samples_passed_by_a_seek:
  {Mp3S.pcm.copied(False{}, [5, 6, 7, 8], 1, 2) == Nil{} : +List<U32>}

law mp3_seek_to_frame_0_is_the_start:
  {Mp3S.seek.which(0, 500) == 0 : U32}

law mp3_seek_to_the_count_stays:
  {Mp3S.seek.which(500, 500) == 1 : U32}

law mp3_seek_forward_reads_on:
  {Mp3S.seek.which(600, 500) == 2 : U32}

law mp3_seek_back_reads_from_the_start:
  {Mp3S.seek.which(400, 500) == 3 : U32}

law mp3_stream_of_a_short_file_does_not_open:
  {Mp3S.open([255, 251, 144, 68]) == None{} : Maybe<Mp3S.Player>}

law mp3_read_of_no_frame:
  {Mp3S.read.raw(Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 0, True{}) == Mp3S.Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 0, Nil{}} : Mp3S.Read}

law mp3_stopped_stream_gives_no_frame:
  {Mp3S.read.raw(Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 2}, 100, True{}) == Mp3S.Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 2}, 0, Nil{}} : Mp3S.Read}

# MP3 music (Music.mp3.read, raylib's loop in UpdateMusicStream). A read
# that brings every frame needed ends the loop; a short one takes the
# stream back to its start for the rest; and a stream that gives no frame
# from its start ends it, where raylib would go round for ever. The reads
# are joined in the order they were made, an MP3 context counts as a loaded
# decoder, and the music's stream has the MP3 stream's channels and rate.
law music_mp3_read_with_every_frame_is_over:
  {J.Music.mp3.turn(Mp3S.Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 5, [1, 2]}, 5, Nil{}, False{}) == J.MusicMp3Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 0, [[1, 2]], True{}, True{}} : J.Music.Mp3}

law music_mp3_short_read_goes_back_to_the_start:
  {J.Music.mp3.turn(Mp3S.Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 3, [1, 2]}, 5, Nil{}, False{}) == J.MusicMp3Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 2, [[1, 2]], True{}, False{}} : J.Music.Mp3}

law music_mp3_stream_without_frames_ends_the_read:
  {J.Music.mp3.turn(Mp3S.Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 0, Nil{}}, 5, Nil{}, True{}) == J.MusicMp3Read{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}, 5, [Nil{}], True{}, True{}} : J.Music.Mp3}

law music_mp3_reads_joined_in_order:
  {J.Music.mp3.joined([[3, 4], [1, 2]], Nil{}) == [1, 2, 3, 4] : +List<U32>}

law music_mp3_is_a_loaded_context:
  {J.Music.context.loaded(J.MusicMp3{Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}}) == True{} : Bool}

law music_mp3_stream_channels:
  {Mp3S.Player.channels(Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}) == 2 : U32}

law music_mp3_stream_rate:
  {Mp3S.Player.rate(Mp3S.Player{Mp3.Stream{Nil{}, 0, 0, 0, Nil{}, 0, 0, 0, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 2, 44100}, Mp3L3.Decoder.zero(), Nil{}, 0, 0, 2, 0, 0}) == 44100 : U32}

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

# raylib 6.2 shapes: a whole turn drops the cap lines of DrawCircleSectorLines
# and DrawRingLines, and of the *LinesEx outlines unless they grow inward; a
# partial arc keeps them.
law shapes_whole_turn_caps:
  for inward: Bool
  {Shapes.arc.caps(True{}, inward) == inward : Bool}

law shapes_partial_arc_caps:
  for inward: Bool
  {Shapes.arc.caps(False{}, inward) == True{} : Bool}

# A refused piece (an unreproduced libm result) refuses the plan it joins.
law shapes_refused_join:
  for commands: +List<FrameCore.Command>
  {Shapes.Plan.join(Shapes.Plan.refused(), Shapes.Plan{True{}, commands}) == Shapes.Plan{False{}, commands} : Shapes.Plan}

# A *LinesEx outline quad with one vertex the profile does not reproduce is
# refused, its texcoords (u0, v1), (u0, v0), (u1, v0), (u1, v1).
law shapes_outline_quad_unverified:
  for x: F32
  for y: F32
  {Shapes.Pt.quad(Shapes.Pt{x, y, True{}}, Shapes.Pt{x, y, True{}}, Shapes.Pt{x, y, False{}}, Shapes.Pt{x, y, True{}})
    == Shapes.Plan{False{}, [FrameCore.ShapeUV{2}, FrameCore.Point{x, y}, FrameCore.ShapeUV{0}, FrameCore.Point{x, y},
      FrameCore.ShapeUV{1}, FrameCore.Point{x, y}, FrameCore.ShapeUV{3}, FrameCore.Point{x, y}]} : Shapes.Plan}

# DrawTriangle is DrawTriangleGradient with one color (raylib 6.2).
law shapes_triangle_is_gradient:
  for x: F32
  for y: F32
  for color: U32
  {Shapes.triangle(Shapes.P2{x, y}, Shapes.P2{x, y}, Shapes.P2{x, y}, color)
    == Shapes.triangle.gradient(Shapes.P2{x, y}, Shapes.P2{x, y}, Shapes.P2{x, y}, color, color, color) : Shapes.Plan}

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

# raylib 6.2 bounds-checks gamepad indexes: a negative gamepad is not
# available and its buttons answer false, the axis count of any index outside
# 0..3 is 0, and the name of one is NULL (None).
law input_gamepad_negative_unavailable:
  {InputCore.gamepad.available(InputCore.Input.new(), 4294967295) == Some{False{}} : Maybe<Bool>}

law input_gamepad_negative_button:
  {InputCore.gamepad.button(InputCore.Input.new(), 1, 4294967295, 0) == Some{False{}} : Maybe<Bool>}

law input_gamepad_axis_count_outside:
  {(InputCore.gamepad.axis_count(InputCore.Input.new(), 4), InputCore.gamepad.axis_count(InputCore.Input.new(), 4294967295))
    == (Some{0}, Some{0}) : Maybe<U32> & Maybe<U32>}

law input_gamepad_name_negative_null:
  {InputCore.gamepad.name(4294967295) == None{} : Maybe<String>}

# GetFPS (raylib 6.2) counts its samples up to 30 and answers 0 before the
# first one.
law core_fps_counted_grows:
  {(CoreState.capture.counted(0), CoreState.capture.counted(29)) == (1, 30) : U32 & U32}

law core_fps_counted_capped:
  {CoreState.capture.counted(30) == 30 : U32}

law core_fps_unsampled_zero:
  {CoreState.fps.result(CoreState.Fps.new()) == Some{0} : Maybe<U32>}

# LoadAutomationEventList (raylib 6.2): a 64-byte description is read into
# its buffer up to 63 bytes, and an "e" line once the list holds 16384 events
# is skipped unread (even one whose numbers are out of range).
law automation_load_long_description:
  {AutomationCore.parse([101, 32, 49, 32, 50, 32, 51, 32, 52, 32, 53, 32, 54, 32, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 10])
    == Some{AutomationCore.AutoList{16384, 1, [AutomationCore.AutoEvent{1, 2, 3, 4, 5, 6}]}} : Maybe<AutomationCore.AutoList>}

law automation_load_event_added:
  {AutomationCore.scan.e(AutomationCore.Loading{0, [], False{}}, AutomationCore.Fields{[7, 2], False{}})
    == AutomationCore.Loading{1, [AutomationCore.AutoEvent{7, 2, 0, 0, 0, 0}], False{}} : AutomationCore.Loading}

law automation_load_full_skips:
  {AutomationCore.scan.e(AutomationCore.Loading{16384, [], False{}}, AutomationCore.Fields{[1], True{}})
    == AutomationCore.Loading{16384, [], False{}} : AutomationCore.Loading}

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

def desktop.fresh() -> J.Core:
  J.Core{CoreState.Core.new(8, 8, Clock.zero()), []}

def desktop.char.finish(pair: J.Core & U32, +first: U32) -> U32 & U32:
  (_, second) = pair
  (first, second)

def desktop.char.next(pair: J.Core & U32) -> U32 & U32:
  (rest, first) = pair
  desktop.char.finish(J.Input.get_char_pressed(rest), first)

def desktop.char.pair(core: J.Core) -> U32 & U32:
  desktop.char.next(J.Input.get_char_pressed(core))

def desktop.chars(moved: Maybe<J.Core>) -> Maybe<(U32 & U32)>:
  match moved:
    case None{}: None{}
    case Some{+core}: Some{desktop.char.pair(core)}

def desktop.wheel(moved: Maybe<J.Core>) -> Maybe<M.Vector2>:
  match moved:
    case None{}: None{}
    case Some{+core}: Some{J.Input.get_mouse_wheel_move_v(core)}

def desktop.delta(moved: Maybe<J.Core>) -> Maybe<M.Vector2>:
  match moved:
    case None{}: None{}
    case Some{+core}: Some{J.Input.get_mouse_delta(core)}

def desktop.scrolls() -> List<Event>:
  [Scroll{0, 0, 1.0, 0.0}, Scroll{9, 8, 0.0, F32.neg(2.0)}]

def desktop.scroll.want() -> M.Vector2:
  M.Vector2{0.0, F32.neg(2.0)}

def desktop.looks() -> List<Event>:
  [Look{3.0, F32.neg(2.0)}, Look{1.0, 0.5}]

# F32 arithmetic does not fold in the checker, so the expected delta is the
# same chain GetMouseDelta builds: add each look to the origin, subtract the
# position registered at the poll, then multiply by the scale (1).
def desktop.look.want() -> M.Vector2:
  M.Vector2{((((0.0 + 3.0 : F32) + 1.0 : F32) - 0.0 : F32) * 1.0 : F32),
    ((((0.0 + F32.neg(2.0) : F32) + 0.5 : F32) - 0.0 : F32) * 1.0 : F32)}

# A Text event queues each codepoint, in order (CharCallback).
law desktop_text_queues_codepoints:
  {desktop.chars(J.Desktop.event(0, desktop.fresh(), Text{SCon{Char.from_u32(65), SCon{Char.from_u32(233), SNil{}}}}, M.Float64{0, 0}))
    == Some{(65, 233)} : Maybe<(U32 & U32)>}

# Scroll replaces the wheel, and the last scroll of the poll wins. The
# pointer position on the event is not applied.
law desktop_scroll_last_wins:
  {desktop.wheel(J.Desktop.events(desktop.scrolls(), 0, M.Float64{0, 0}, Some{desktop.fresh()}))
    == Some{desktop.scroll.want()} : Maybe<M.Vector2>}

# Look adds each delta to the current position. GetMouseDelta is that
# position minus the one registered at the poll (the origin here).
law desktop_look_is_mouse_delta:
  {desktop.delta(J.Desktop.events(desktop.looks(), 0, M.Float64{0, 0}, Some{desktop.fresh()}))
    == Some{desktop.look.want()} : Maybe<M.Vector2>}

# The software renderer ignores blend modes (rlSetBlendMode is GL3-only) and
# texture wrap modes (rlsw rejects GL_CLAMP_TO_EDGE): both leave their input.
law frame_blend_mode_unchanged:
  for frame: J.Frame
  for mode: U32
  {J.Frame.begin_blend_mode(frame, mode) == frame : J.Frame}

# SetTextureWrap(CLAMP) passes GL_CLAMP_TO_EDGE, which rlsw rejects: the
# texture keeps its wraps.
law texture_set_wrap_clamp_unchanged:
  for texture: J.Texture
  {J.Texture.set_wrap(texture, 1) == texture : J.Texture}

# TEXTURE_FILTER_POINT selects nearest sampling both ways whatever the
# previous filters, and keeps the wraps.
law texture_filter_point:
  for mag: Bool
  for min: Bool
  for s_clamp: Bool
  for t_clamp: Bool
  {J.Texture.filter(0, FrameCore.Filtering{mag, min, s_clamp, t_clamp}) == FrameCore.Filtering{False{}, False{}, s_clamp, t_clamp} : FrameCore.Filtering}

# rlsw's id pools reuse the most recently freed id first.
law texture_pool_reuses_freed:
  for next: U32
  for capacity: U32
  for id: U32
  for rest: +List<U32>
  {FrameCore.Pool.take(FrameCore.Pool{next, capacity, Con{id, rest}}) == (FrameCore.Pool{next, capacity, rest}, id) : FrameCore.Pool & U32}

# Text (rtext.c, raylib 6.2): the functions 6.2 defines for every input
# answer Some; TextInsertAlloc's NULL (a negative position) is None.
law text_subtext_negative_position_is_empty:
  {J.Text.subtext("hello", 4294967295, 3) == Some{""} : Maybe<String>}

law text_subtext_zero_length_is_empty:
  {J.Text.subtext("hello", 1, 0) == Some{""} : Maybe<String>}

law text_subtext_clamped_to_the_text:
  {J.Text.subtext("hello", 3, 9) == Some{"lo"} : Maybe<String>}

law text_remove_spaces_tests_the_input_index:
  {J.Text.remove_spaces(" a b ") == Some{"ab"} : Maybe<String>}

law text_replace_between_short:
  {J.Text.replace_between("<m>z", "<", ">", "R") == Some{"<R>z"} : Maybe<String>}

law text_insert_inside:
  {J.Text.insert("abc", "XY", 1) == Some{"aXYbc"} : Maybe<String>}

law text_insert_clamped_past_the_end:
  {J.Text.insert("abc", "XY", 9) == Some{"abcXY"} : Maybe<String>}

law text_insert_negative_is_empty:
  {J.Text.insert("abc", "XY", 4294967295) == Some{""} : Maybe<String>}

law text_insert_alloc_negative_is_null:
  {J.Text.insert_alloc("abc", "XY", 4294967295) == None{} : Maybe<String>}

law text_join_delimiter_between:
  {J.Text.join(["a", "b"], ",") == Some{"a,b"} : Maybe<String>}

law text_split_pieces:
  {J.Text.split("a,,b", ',') == Some{["a", "", "b"]} : Maybe<+List<String>>}

law text_to_pascal_empty_is_empty:
  {J.Text.to_pascal("") == Some{""} : Maybe<String>}

law text_to_pascal_skips_underscore_runs:
  {J.Text.to_pascal("a__1") == Some{"A1"} : Maybe<String>}

law text_to_pascal_final_underscore_ends:
  {J.Text.to_pascal("trail_") == Some{"Trail"} : Maybe<String>}

law text_to_camel_copies_non_letters:
  {J.Text.to_camel("A_-b") == Some{"a-b"} : Maybe<String>}

law text_to_snake_spaces_collapse:
  {J.Text.to_snake("  a  b ") == Some{"a_b_"} : Maybe<String>}

law text_to_snake_acronym_word:
  {J.Text.to_snake("HTTPRequest") == Some{"http_request"} : Maybe<String>}

law text_to_snake_no_double_underscore:
  {J.Text.to_snake("a_B") == Some{"a_b"} : Maybe<String>}

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
  for linear: FrameCore.Filtering
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
  for linear: FrameCore.Filtering
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

# rlGetGlTextureFormats under OpenGL 1.1: R8G8B8A8 is GL_RGBA with
# GL_UNSIGNED_BYTE, R5G6B5 GL_RGB with GL_UNSIGNED_SHORT_5_6_5, and a float
# format (R32) has no answer; rlGenTextureMipmaps leaves the count.
# The render batch is OpenGL 3.3/ES2's: the software renderer's is zeroed,
# drawing it leaves it, and rlGetProcAddress is NULL.
law rlgl_render_batch_zeroed:
  for frame: J.Frame
  for buffers: U32
  for elements: U32
  {J.Rlgl.load_render_batch(frame, buffers, elements) == (frame, J.Rlgl.RenderBatch{0, 0, Nil{}, Nil{}, 0, 0.0}) : J.Frame & J.Rlgl.RenderBatch}

law rlgl_draw_render_batch_unchanged:
  for frame: J.Frame
  for batch: J.Rlgl.RenderBatch
  {J.Rlgl.draw_render_batch(frame, batch) == (frame, batch) : J.Frame & J.Rlgl.RenderBatch}

# rlsw's 8-bit pixel writers (rlCopyFramebuffer): luminance (77 r + 150 g +
# 29 b) >> 8, R5G6B5 of red (bytes reversed onto the list: high, low); and
# rlReadTexturePixels' zeroed bytes for formats 1..7, NULL otherwise.
law rlgl_copy_luminance:
  {J.Rlgl.copy.put(1, 10, 20, 30, 255, Nil{}) == [18] : +List<U32>}

law rlgl_copy_r5g6b5_red:
  {J.Rlgl.copy.put(3, 255, 0, 0, 255, Nil{}) == [248, 0] : +List<U32>}

law rlgl_read_texture_pixels_zeroed:
  {J.Rlgl.read_texture_pixels(2, 1, 7) == Some{[0, 0, 0, 0, 0, 0, 0, 0]} : Maybe<+List<U32>>}

law rlgl_read_texture_pixels_null:
  {J.Rlgl.read_texture_pixels(2, 2, 8) == None{} : Maybe<+List<U32>>}

law rlgl_proc_address_null:
  {J.Rlgl.get_proc_address("glClear") == 0 : U32}

law rlgl_gl_formats_rgba8:
  {J.Rlgl.get_gl_texture_formats(7) == J.Rlgl.GlFormats{6408, 6408, 5121} : J.Rlgl.GlFormats}

law rlgl_gl_formats_r5g6b5:
  {J.Rlgl.get_gl_texture_formats(3) == J.Rlgl.GlFormats{6407, 6407, 33635} : J.Rlgl.GlFormats}

law rlgl_gl_formats_float_none:
  {J.Rlgl.get_gl_texture_formats(8) == J.Rlgl.GlFormats{0, 0, 0} : J.Rlgl.GlFormats}

law rlgl_gen_texture_mipmaps_unchanged:
  for frame: J.Frame
  for id: U32
  for mipmaps: U32
  {J.Rlgl.gen_texture_mipmaps(frame, id, 4, 4, 7, mipmaps) == (frame, mipmaps) : J.Frame & U32}

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
  {J.Rlgl.render_texture_depth(J.RlglFramebuffer{1, 0, 0, 0, 0, 3, 1024, 1024, 19}, 1024, 1024, 3) == Some{J.RenderTexture{1, J.Texture{0, 1024, 1024, 0, FrameCore.Filtering.nearest(), False{}, None{}}, 3}} : Maybe<J.RenderTexture>}

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
  {J.Rlgl.texture.with(2, 5, 800, 450, 12, canvas) == (J.Frame{canvas, Nil{}}, Some{J.Texture{5, 800, 450, 12, FrameCore.Filtering.nearest(), False{}, None{}}}) : J.Frame & Maybe<J.Texture>}

law rlgl_framebuffer_float_color_is_incomplete:
  {J.Rlgl.Framebuffer.complete(J.Rlgl.framebuffer.attached(J.RlglFramebuffer{1, 0, 0, 0, 0, 0, 0, 0, 0}, 2, 800, 450, 12, 0, 100)) == False{} : Bool}

law blind_target_bound_directly_is_marked:
  for id: U32
  {FrameCore.RenderTarget.direct(FrameCore.RenderTarget{id, 0, 0, FrameCore.Filtering.nearest(), True{}}) == True{} : Bool}

law blind_texture_mode_is_not_bound_directly:
  for id: U32
  for depth: U32
  {FrameCore.RenderTarget.direct(FrameCore.RenderTarget{id, 0, depth, FrameCore.Filtering.nearest(), False{}}) == False{} : Bool}

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
  {J.Rlgl.cull.default_near() == M.Float64{1068079513, 2576980378} : M.Float64}

law rlgl_cull_distance_near_as_float:
  {N.checked(1068079513, 2576980378) == Some{1028443341} : Maybe<U32>}

law rlgl_cull_distance_far_is_the_default:
  {J.Rlgl.cull.default_far() == M.Float64{1085227008, 0} : M.Float64}

# A new frame's clip planes are rlgl's defaults; rlGetCullDistanceNear/Far
# read the planes rlSetClipPlanes stored; a far equal to the near divides by
# zero, which BeginMode3D's projections refuse.
law rlgl_clip_planes_initial_default:
  {FrameCore.Planes.initial() == FrameCore.Planes{1068079513, 2576980378, 1085227008, 0} : FrameCore.Planes}

law rlgl_clip_planes_read_near:
  for canvas: FrameCore.Canvas
  {J.Rlgl.planes.read(False{}, (canvas, FrameCore.Planes{1, 2, 3, 4})) == (J.Frame{canvas, Nil{}}, M.Float64{1, 2}) : J.Frame & M.Float64}

law rlgl_clip_planes_read_far:
  for canvas: FrameCore.Canvas
  {J.Rlgl.planes.read(True{}, (canvas, FrameCore.Planes{1, 2, 3, 4})) == (J.Frame{canvas, Nil{}}, M.Float64{3, 4}) : J.Frame & M.Float64}

law rlgl_clip_planes_zero_depth_refused:
  {J.Frame.f64.over(F.Words{1073741824, 0}, F.Words{0, 0}) == None{} : Maybe<U32>}

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

# UpdateMeshBuffer reaches vboId[index]: UploadMesh allocates 9 of them in
# the reference build (GPU skinning); index 9 and an int index of -1 are outside.
law mesh_buffer_last_exists:
  {J.Mesh.buffer_exists(8) == True{} : Bool}

law mesh_buffer_past_the_last:
  {J.Mesh.buffer_exists(9) == False{} : Bool}

law mesh_buffer_negative_index:
  {J.Mesh.buffer_exists(4294967295) == False{} : Bool}

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

# Audio streams (docs/AUDIO.md#audio-streams). A half holds the default size,
# raylib's 12800 frames without one, and the device's period of 480 at least.
law stream_half_default:
  {J.AudioStream.sub(0) == 12800 : U32}

law stream_half_at_least_a_period:
  {J.AudioStream.sub(100) == 480 : U32}

law stream_half_set:
  {J.AudioStream.sub(600) == 600 : U32}

law stream_size_default_kept:
  {J.AudioDevice.stream_size(J.AudioDevice.set_stream_buffer_size_default(J.AudioDevice.none(), 600)) == 600 : U32}

# No buffer on an unready device: the stream keeps its fields and is not valid.
law stream_unready_without_buffer:
  {J.AudioStream.load(J.AudioDevice.none(), 44100, 16, 1) == (J.AudioDevice.none(), J.AudioStream{0, 44100, 16, 1}) : J.AudioDevice & J.AudioStream}

law stream_without_buffer_invalid:
  {J.AudioStream.is_valid(J.AudioStream{0, 44100, 16, 1}) == False{} : Bool}

law stream_with_buffer_valid:
  {J.AudioStream.is_valid(J.AudioStream{1, 44100, 16, 1}) == True{} : Bool}

# UpdateAudioStream fills the first processed half; a play or a stop marks both.
law stream_first_half_first:
  {Mixer.Feed.target(Mixer.HeadStream{16, 1, True{}, True{}, False{}, 0}) == 0 : U32}

law stream_second_half_next:
  {Mixer.Feed.target(Mixer.HeadStream{16, 1, False{}, True{}, False{}, 0}) == 1 : U32}

law stream_no_half_left:
  {Mixer.Feed.target(Mixer.HeadStream{16, 1, False{}, False{}, False{}, 0}) == 2 : U32}

law stream_filled_half_unprocessed:
  {Mixer.Feed.filled(Mixer.HeadStream{16, 1, True{}, True{}, False{}, 0}, 0) == Mixer.HeadStream{16, 1, False{}, True{}, False{}, 0} : Mixer.Feed}

law stream_play_marks_both:
  {Mixer.Feed.fresh(Mixer.HeadStream{8, 2, False{}, False{}, False{}, 0}) == Mixer.HeadStream{8, 2, True{}, True{}, False{}, 0} : Mixer.Feed}

# SetAudioStreamCallback: a stream takes a callback and gives it back, its
# halves as they were, and a play keeps it; a sound takes none. The answers
# are read in order, the frames asked for each time, and where they end the
# frames are zeros (a callback made to learn what will be asked for); what a
# turn read is the sum of what it asked for.
law stream_callback_set:
  {Mixer.Feed.calling(Mixer.HeadStream{16, 1, True{}, False{}, False{}, 0}, True{}) == Mixer.HeadStream{16, 1, True{}, False{}, True{}, 0} : Mixer.Feed}

law stream_callback_removed:
  {Mixer.Feed.calling(Mixer.HeadStream{16, 1, False{}, False{}, True{}, 0}, False{}) == Mixer.HeadStream{16, 1, False{}, False{}, False{}, 0} : Mixer.Feed}

law stream_callback_kept_by_play:
  {Mixer.Feed.fresh(Mixer.HeadStream{8, 2, False{}, False{}, True{}, 0}) == Mixer.HeadStream{8, 2, True{}, True{}, True{}, 0} : Mixer.Feed}

law stream_callback_not_for_a_sound:
  {Mixer.Feed.called(Mixer.Feed.calling(Mixer.HeadStatic{}, True{})) == False{} : Bool}

law stream_callback_answers_in_order:
  {Mixer.take.padded(2n, [7, 8, 9], Nil{}) == [7, 8] : +List<U32>}

law stream_callback_zeros_after_the_answers:
  {Mixer.take.padded(3n, [7], Nil{}) == [7, 0, 0] : +List<U32>}

law stream_callback_frames_asked_for:
  {Mixer.asked.total([470, 80, 1], 0) == 551 : U32}

law stream_callback_asked_last_first:
  {Mixer.asked.next(True{}, 441, [1]) == [441, 1] : +List<U32>}

law stream_callback_nothing_asked_of_the_halves:
  {Mixer.asked.next(False{}, 441, Nil{}) == Nil{} : +List<U32>}

law stream_callback_answers_held:
  {J.AudioDevice.answers.hold(2n, [5, 6]) == True{} : Bool}

law stream_callback_answer_missing:
  {J.AudioDevice.answers.hold(3n, [5, 6]) == False{} : Bool}

law stream_callback_unready_asks_nothing:
  {J.AudioDevice.asks(J.AudioDevice.none(), 480) == None{} : Maybe<&2, +List<J.AudioDevice.Ask>>}

# Audio processors: a buffer's are called in the order they were attached,
# the mixed output's are those of buffer 0, and a detach takes every one with
# the tag. Nothing is attached on an unready device or to a stream without a
# buffer. A processor must give back as many samples as it was given, and
# each one is given what the one before wrote.
law processors_in_attach_order:
  {J.AudioProcessors.tags([J.AudioProcessor{1, 7}, J.AudioProcessor{2, 8}, J.AudioProcessor{1, 9}], 1, Nil{}) == [7, 9] : +List<U32>}

law processors_mixed_are_buffer_zero:
  {J.AudioProcessors.tags([J.AudioProcessor{0, 4}, J.AudioProcessor{1, 7}], 0, Nil{}) == [4] : +List<U32>}

law processors_detach_takes_every_one:
  {J.AudioProcessors.without([J.AudioProcessor{1, 7}, J.AudioProcessor{1, 8}, J.AudioProcessor{1, 7}, J.AudioProcessor{2, 7}], 1, 7, Nil{}) == [J.AudioProcessor{1, 8}, J.AudioProcessor{2, 7}] : +List<J.AudioDevice.Processor>}

law processors_mixed_attached_last:
  {J.AudioDevice.attach_mixed_processor(J.AudioProcessors{[J.AudioProcessor{0, 1}]}, J.AudioDevice.init(J.AudioDevice.none()), 3) == J.AudioProcessors{[J.AudioProcessor{0, 1}, J.AudioProcessor{0, 3}]} : J.AudioProcessors}

law processors_unready_attach_nothing:
  {J.AudioDevice.attach_mixed_processor(J.AudioProcessors.none(), J.AudioDevice.none(), 3) == J.AudioProcessors.none() : J.AudioProcessors}

law processors_no_buffer_attach_nothing:
  {J.AudioStream.attach_processor(J.AudioProcessors.none(), J.AudioDevice.init(J.AudioDevice.none()), J.AudioStream{0, 44100, 16, 1}, 3) == J.AudioProcessors.none() : J.AudioProcessors}

law processors_samples_come_back:
  {J.AudioDevice.process.sized([1, 2, 3, 4], 4) == True{} : Bool}

law processors_sample_lost:
  {J.AudioDevice.process.sized([1, 2, 3], 4) == False{} : Bool}

law processors_sample_added:
  {J.AudioDevice.process.sized([1, 2, 3, 4, 5], 4) == False{} : Bool}

law processors_chained:
  {J.AudioDevice.process.chain(~U32, ~(tag => samples => state => ((state + tag : U32), Con{tag, samples})), [3, 4], (0, [9])) == (7, [4, 3, 9]) : U32 & +List<U32>}

# framesProcessed: the frames a stream was given count up (an unsigned int),
# a play forgets them, and a sound counts none.
law stream_frames_given_counted:
  {Mixer.Feed.done(Mixer.Feed.given(Mixer.HeadStream{16, 1, True{}, True{}, False{}, 7}, 480)) == 487 : U32}

law stream_frames_given_wrap:
  {Mixer.Feed.done(Mixer.Feed.given(Mixer.HeadStream{16, 1, True{}, True{}, False{}, 4294967295}, 2)) == 1 : U32}

law stream_play_forgets_frames_given:
  {Mixer.Feed.done(Mixer.Feed.fresh(Mixer.HeadStream{8, 2, False{}, False{}, False{}, 99})) == 0 : U32}

law stream_sound_counts_no_frames:
  {Mixer.Feed.done(Mixer.Feed.given(Mixer.HeadStatic{}, 5)) == 0 : U32}

law stream_sound_always_processed:
  {Mixer.Feed.processed(Mixer.HeadStatic{}) == True{} : Bool}

# A half's samples are replaced in place, zeros after the frames given.
law stream_half_written_in_place:
  {Mixer.splice([1, 2, 3, 4, 5, 6], 2, [9], 1, 2) == [1, 2, 9, 0, 5, 6] : +List<U32>}

# VR stereo on the software renderer (docs/VR.md): the stereo mode leaves the
# frame as it is, and a configuration holds nothing to unload.
law vr_stereo_mode_begins_unchanged:
  for frame: J.Frame
  for config: J.VrStereoConfig
  {J.Frame.begin_vr_stereo_mode(frame, config) == frame : J.Frame}

law vr_stereo_mode_ends_unchanged:
  for frame: J.Frame
  {J.Frame.end_vr_stereo_mode(frame) == frame : J.Frame}

law vr_unload_stereo_config:
  for config: J.VrStereoConfig
  {J.Vr.unload_stereo_config(config) == Unit{} : Unit}

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

# msf_gif (src/msf_gif.bend): the GIF encoder of raylib's screen recording
# example. A depth gives each channel its bits (5, 6 and 5 at 16), a pixel
# is cooked with the 4x4 ordered dither into those bits whatever its alpha,
# a pass lists the colors it marked in ascending order, a channel's bits are
# spread over a byte for the palette, codes go to the stream low bits first,
# the stream is cut in sub-blocks of 255 bytes, and a frame the C code
# writes past its buffer is not answered. A frame equal to the one before it
# is written as the transparent index (the second 1x1 frame below differs
# from the first in its codes only: 4, 0, 5 instead of 4, 1, 5).

law msf_gif_bits_of_depth_16:
  {((MsfGif.red.bits(16) * 10000) + (MsfGif.green.bits(16) * 100) + MsfGif.blue.bits(16) : U32) == 50605 : U32}

law msf_gif_bits_of_depth_1:
  {((MsfGif.red.bits(1) * 10000) + (MsfGif.green.bits(1) * 100) + MsfGif.blue.bits(1) : U32) == 100 : U32}

law msf_gif_bits_add_up_to_the_depth:
  {(MsfGif.red.bits(11) + MsfGif.green.bits(11) + MsfGif.blue.bits(11) : U32) == 11 : U32}

law msf_gif_multiplier_five_bits:
  {MsfGif.multiplier(5) == 249 : U32}

law msf_gif_multiplier_no_bits:
  {MsfGif.multiplier(0) == 0 : U32}

law msf_gif_dither_second_column:
  {MsfGif.dither(1, 0) == 8 : U32}

law msf_gif_dither_last_corner:
  {MsfGif.dither(3, 3) == 5 : U32}

law msf_gif_dither_repeats_every_four:
  {MsfGif.dither(4, 6) == 3 : U32}

law msf_gif_white_cooks_to_all_bits:
  {MsfGif.cook.pixel(4294967295, 15, MsfGif.cook.scales(16)) == 65535 : U32}

law msf_gif_black_cooks_to_zero:
  {MsfGif.cook.pixel(255, 15, MsfGif.cook.scales(16)) == 0 : U32}

law msf_gif_alpha_is_not_cooked:
  {MsfGif.cook.pixel(3861460736, 9, MsfGif.cook.scales(16)) == MsfGif.cook.pixel(3861460991, 9, MsfGif.cook.scales(16)) : U32}

law msf_gif_pass_marks_colors_ascending:
  {MsfGif.cook.pass([4294967295, 255], 2, 3) == MsfGif.Pass{[7, 0], 2, [0, 7]} : MsfGif.Pass}

law msf_gif_channel_five_bits:
  {MsfGif.channel(31, 5) == 255 : U32}

law msf_gif_channel_one_bit:
  {MsfGif.channel(1, 1) == 240 : U32}

law msf_gif_channel_no_bits:
  {MsfGif.channel(0, 0) == 0 : U32}

law msf_gif_put_keeps_bits_below_a_byte:
  {MsfGif.put(5, 8, MsfGif.Bits{0, 1, Nil{}, 0}) == MsfGif.Bits{5, 8, Nil{}, 0} : MsfGif.Bits}

law msf_gif_put_fills_a_byte:
  {MsfGif.put(4095, 4096, MsfGif.Bits{1, 2, Nil{}, 0}) == MsfGif.Bits{31, 32, [255], 1} : MsfGif.Bits}

law msf_gif_put_fills_two_bytes:
  {MsfGif.put(4095, 4096, MsfGif.Bits{127, 128, [9], 1}) == MsfGif.Bits{7, 8, [255, 255, 9], 3} : MsfGif.Bits}

law msf_gif_kid_found:
  {MsfGif.kid(MsfGif.kid.added(MsfGif.kid.added(MsfGif.Kids{Nil{}}, 7, 300), 2, 301), 7) == 300 : U32}

law msf_gif_kid_missing:
  {MsfGif.kid(MsfGif.kid.added(MsfGif.Kids{Nil{}}, 7, 300), 6) == 0 : U32}

law msf_gif_minimum_code_size_two:
  {(MsfGif.lzw.minimum(1) + MsfGif.lzw.minimum(3) : U32) == 4 : U32}

law msf_gif_minimum_code_size_grows:
  {((MsfGif.lzw.minimum(4) * 100) + (MsfGif.lzw.minimum(127) * 10) + MsfGif.lzw.minimum(128) : U32) == 378 : U32}

law msf_gif_chunk_writes_size_first:
  {MsfGif.chunk([1, 2, 3], 0, 3, Nil{}) == [3, 2, 1, 3] : +List<U32>}

law msf_gif_buffer_holds_one_more_block:
  {MsfGif.blocks.flushed(256, Nil{}, MsfGif.Bits{0, 1, Nil{}, 255}) == MsfGif.Written{True{}, [0]} : MsfGif.Written}

law msf_gif_buffer_lacks_a_byte:
  {MsfGif.blocks.flushed(255, Nil{}, MsfGif.Bits{0, 1, Nil{}, 255}) == MsfGif.Written{False{}, [0]} : MsfGif.Written}

law msf_gif_depth_asked_zero:
  {MsfGif.asked.depth(0) == 1 : U32}

law msf_gif_depth_asked_negative:
  {MsfGif.asked.depth(4294967293) == 1 : U32}

law msf_gif_depth_asked_above:
  {MsfGif.asked.depth(20) == 16 : U32}

law msf_gif_begin_writes_the_screen:
  {MsfGif.begin(800, 450) == Some{MsfGif.Gif{800, 450, Nil{}, 0, 0, [0, 0, 0, 1, 3, 48, 46, 50, 69, 80, 65, 67, 83, 84, 69, 78, 11, 255, 33, 0, 0, 112, 1, 194, 3, 32, 97, 57, 56, 70, 73, 71]}} : Maybe<MsfGif.Gif>}

law msf_gif_begin_without_width_none:
  {MsfGif.begin(0, 4) == None{} : Maybe<MsfGif.Gif>}

law msf_gif_begin_above_the_limit_none:
  {MsfGif.begin(4, 4097) == None{} : Maybe<MsfGif.Gif>}

# The frames below are asked a depth of 3 (one bit a channel, 8 colors).
law msf_gif_frame_of_one_white_pixel:
  {MsfGif.frame(MsfGif.Gif{1, 1, Nil{}, 0, 0, Nil{}}, [4294967295], 5, 3) == Some{MsfGif.Gif{1, 1, [7], 3, 1, [0, 1, 76, 2, 2, 0, 0, 0, 0, 0, 0, 240, 240, 240, 0, 0, 0, 129, 0, 1, 0, 1, 0, 0, 0, 0, 44, 0, 0, 0, 5, 5, 4, 249, 33]}} : Maybe<MsfGif.Gif>}

law msf_gif_frame_equal_to_the_one_before_is_transparent:
  {MsfGif.frame(MsfGif.Gif{1, 1, [7], 3, 1, Nil{}}, [4294967295], 0, 3) == Some{MsfGif.Gif{1, 1, [7], 3, 1, [0, 1, 68, 2, 2, 0, 0, 0, 0, 0, 0, 240, 240, 240, 0, 0, 0, 129, 0, 1, 0, 1, 0, 0, 0, 0, 44, 0, 0, 0, 0, 5, 4, 249, 33]}} : Maybe<MsfGif.Gif>}

law msf_gif_frame_with_a_pixel_missing_none:
  {MsfGif.frame(MsfGif.Gif{2, 1, Nil{}, 0, 0, Nil{}}, [4294967295], 0, 16) == None{} : Maybe<MsfGif.Gif>}

law msf_gif_frame_with_a_pixel_more_none:
  {MsfGif.frame(MsfGif.Gif{1, 1, Nil{}, 0, 0, Nil{}}, [4294967295, 255], 0, 16) == None{} : Maybe<MsfGif.Gif>}

law msf_gif_finish_adds_the_trailer:
  {MsfGif.finish(MsfGif.Gif{1, 1, Nil{}, 0, 0, [2, 1]}) == [1, 2, 59] : +List<U32>}

# GuiListViewEx (jongui.bend): the scroll index is 0 when it is negative or
# past the last full page, the wheel moves it an item a notch between the
# first item and the last page, a press selects an item or clears its
# selection, and the selection is drawn before the focus. The control's
# rectangles are float arithmetic; core_directory_files compares them with
# raygui's.

law gui_list_counts_its_items:
  {JG.Gui.list.count(["a", "b", "c"], 0) == 3 : U32}

law gui_list_starts_at_its_scroll_index:
  {JG.Gui.list.start(14, 27, 13) == 14 : U32}

law gui_list_start_past_the_last_page_is_zero:
  {JG.Gui.list.start(15, 27, 13) == 0 : U32}

law gui_list_negative_start_is_zero:
  {JG.Gui.list.start(4294967295, 27, 13) == 0 : U32}

law gui_list_wheel_down_a_notch:
  {JG.Gui.list.wheeled(0, 4294967295, 27, 13) == 1 : U32}

law gui_list_wheel_stops_at_the_last_page:
  {JG.Gui.list.wheeled(13, 4294967293, 27, 13) == 14 : U32}

law gui_list_wheel_stops_at_the_first_item:
  {JG.Gui.list.wheeled(2, 5, 27, 13) == 0 : U32}

law gui_list_press_selects:
  {JG.Gui.list.pressed(4294967295, 3) == 3 : U32}

law gui_list_press_on_the_selected_item_clears:
  {JG.Gui.list.pressed(3, 3) == 4294967295 : U32}

law gui_list_press_moves_the_selection:
  {JG.Gui.list.pressed(2, 3) == 3 : U32}

law gui_list_selection_goes_before_focus:
  {JG.Gui.list.kind(False{}, 3, 3, 3) == 2 : U32}

law gui_list_focused_item:
  {JG.Gui.list.kind(False{}, 3, 9, 3) == 1 : U32}

law gui_list_plain_item:
  {JG.Gui.list.kind(False{}, 3, 9, 8) == 0 : U32}

law gui_list_disabled_items:
  {((JG.Gui.list.kind(True{}, 3, 3, 9) * 10) + JG.Gui.list.kind(True{}, 3, 9, 3) : U32) == 43 : U32}

law gui_font_base_size_is_the_default_font_s:
  {JG.Gui.font_base_size(JG.Gui.new()) == 10 : U32}

# GuiGrid draws (int)(size / spacing) + 1 lines of each kind: none for a
# count that comes out at 0 or below as an int (its loop never runs).
# GuiTextSplit's items picked by index (GuiToggleSlider, GuiComboBox): the
# second of "A;B" is "B"; none past the last.
law gui_item_at_second:
  {JG.Gui.item.at(JG.Gui.split([65, 59, 66], 59, 0, Nil{}), 1) == [66] : +List<U32>}

law gui_item_at_past_the_last:
  {JG.Gui.item.at(JG.Gui.split([65, 59, 66], 59, 0, Nil{}), 2) == [] : +List<U32>}

# GuiMessageBox numbers its buttons from 1: a click on the second sets the
# result to 2, and a button not clicked keeps the result.
law gui_message_button_number:
  for frame: J.Frame
  {JG.Gui.message.step(1, 4294967295, (frame, True{})) == JG.GuiButtons{frame, 2} : JG.Gui.Buttons}

law gui_message_unclicked_keeps_result:
  for frame: J.Frame
  {JG.Gui.message.step(1, 0, (frame, False{})) == JG.GuiButtons{frame, 0} : JG.Gui.Buttons}

# GuiTextInputBox places its box with C's int division of the message
# height, truncated toward zero: 77/4 is 19, -7/2 is -3.
law gui_int_over_positive:
  {JG.Gui.int.over(77, 4) == 19 : U32}

law gui_int_over_negative:
  {JG.Gui.int.over(4294967289, 2) == 4294967293 : U32}

law gui_grid_lines_counted:
  {JG.Gui.grid.n(3) == 3n : Nat}

law gui_grid_no_lines_below_one:
  {JG.Gui.grid.n(4294967295) == 0n : Nat}

# GuiLoadIcons reads the table's words little-endian. GuiDrawIcon keeps C's
# int in range: a pixel size of -2 is near enough, 2^26 is not.
law gui_icons_word_little_endian:
  {JG.Gui.icons.word([1, 2, 3, 4]) == 67305985 : U32}

law gui_icon_negative_size_near:
  {JG.Gui.icon.near(4294967294, 67108864) == True{} : Bool}

law gui_icon_size_past_range:
  {JG.Gui.icon.near(67108864, 67108864) == False{} : Bool}

# GuiTooltip's panel is 8 pixels higher a line, GetTextLines counting at
# most 128 lines.
law gui_tip_lines_counted:
  {JG.Gui.tip.count([[97], [98]], 0) == 2 : U32}

law gui_tip_lines_capped:
  {JG.Gui.tip.count([[97]], 128) == 128 : U32}

# ConvertHSVtoRGB's switch: sector 0 is (v, t, p); a (long)(hue/60) outside
# 0..4 takes the last case, (v, p, q). A hovered color control leaves the
# drag as it was.
law gui_rgb_sector_first:
  for v: F32
  for p: F32
  for q: F32
  for t: F32
  {JG.Gui.rgb.sector(0, v, p, q, t) == M.Vector3{v, t, p} : M.Vector3}

law gui_rgb_sector_other:
  for v: F32
  for p: F32
  for q: F32
  for t: F32
  {JG.Gui.rgb.sector(9, v, p, q, t) == M.Vector3{v, p, q} : M.Vector3}

# Font.Shared counts the words it copies; a new gui's font is the default
# one, of base size 10 (GuiGetFont().baseSize).
law font_shared_count:
  {J.Font.shared.count([7, 8, 9], 0) == 3 : U32}

law gui_default_font_base_size:
  {JG.Gui.font.base(JG.GuiFontDefault{}) == 10 : U32}

# GuiSetStyle's index is control*24 + property in C's int: a property of 24
# reaches the next control's row, -1*24 + 30 is 6, and 16*24 is past the
# table (undefined in raygui, 4294967295).
law gui_style_index_next_row:
  {JG.Gui.style.index(1, 24) == 48 : U32}

law gui_style_index_negative_control:
  {JG.Gui.style.index(4294967295, 30) == 6 : U32}

law gui_style_index_past_table:
  {JG.Gui.style.index(16, 0) == 4294967295 : U32}

# GuiLoadStyle's sscanf: %d skips spaces and takes a sign (" -12" is -12);
# 2147483648 is past int (undefined). fgets reads a line through its '\n'.
law gui_scan_int_negative:
  {JG.Gui.scan.value(JG.Gui.scan.int([32, 45, 49, 50])) == 4294967284 : U32}

law gui_scan_int_past_int:
  {JG.Gui.scan.fine(JG.Gui.scan.int([50, 49, 52, 55, 52, 56, 51, 54, 52, 56])) == False{} : Bool}

law gui_rgs_span_through_newline:
  {JG.Gui.rgs.span(255n, [97, 10, 98], 0) == 2 : U32}

# Header macros: a value macro is its literal, and one that names an
# enumerator has the enumerator's value.
law macro_rlgl_texture_wrap_s:
  {J.Rlgl.RL_TEXTURE_WRAP_S() == 10242 : U32}

law macro_mouse_left_button_is_its_enumerator:
  {J.Config.MOUSE_LEFT_BUTTON() == J.MouseButton.MOUSE_BUTTON_LEFT() : U32}

law macro_shader_loc_map_diffuse_is_albedo:
  {J.Rlgl.RL_SHADER_LOC_MAP_DIFFUSE() == J.rlShaderLocationIndex.RL_SHADER_LOC_MAP_ALBEDO() : U32}

# rlTextureParameters as swTexParameteri takes it: GL_LINEAR on the
# minification filter alone, GL_CLAMP on T alone, GL_CLAMP_TO_EDGE rejected;
# SetTextureWrap(REPEAT) clears both clamps.
law texture_params_min_linear:
  {J.Rlgl.texture.param(10241, 9729, FrameCore.Filtering.nearest()) == FrameCore.Filtering{False{}, True{}, False{}, False{}} : FrameCore.Filtering}

law texture_params_gl_clamp:
  {J.Rlgl.texture.param(10243, 10496, FrameCore.Filtering.nearest()) == FrameCore.Filtering{False{}, False{}, False{}, True{}} : FrameCore.Filtering}

law texture_params_clamp_to_edge_rejected:
  {J.Rlgl.texture.param(10242, 33071, FrameCore.Filtering.nearest()) == FrameCore.Filtering.nearest() : FrameCore.Filtering}

law texture_wrap_repeat_clears_clamps:
  {J.Texture.wrap.repeated(True{}, FrameCore.Filtering{True{}, False{}, True{}, True{}}) == FrameCore.Filtering{True{}, False{}, False{}, False{}} : FrameCore.Filtering}

# rlglInit is the frame InitWindow makes; rlResizeFramebuffer refuses a size
# of 0; rlUpdateTexture finds no OpenGL 1.1 format for format 8 (R32).
law rlgl_gl_init_is_init_window:
  for width: U32
  for height: U32
  {J.Rlgl.gl_init(width, height) == J.Frame.init_window(width, height) : Maybe<J.Frame>}

law rlgl_resize_framebuffer_zero_refused:
  for frame: J.Frame
  {J.Rlgl.resize_framebuffer(frame, 0, 8) == J.Frame.refuse(frame) : J.Frame}

law rlgl_update_texture_float_has_no_format:
  {J.Rlgl.GlFormats.internal(J.Rlgl.get_gl_texture_formats(8)) == 0 : U32}

# rlsw's client arrays: a NULL color pointer keeps the bound colors;
# glDisableClientState unbinds; glDrawArrays reads vertices offset onwards.
law rlgl_arrays_null_color_keeps:
  {J.Rlgl.enable_state_pointer(J.RlglArrays{[], False{}, [], False{}, [5], True{}}, 32886, None{}) == J.RlglArrays{[], False{}, [], False{}, [5], True{}} : J.Rlgl.Arrays}

law rlgl_arrays_disable_vertex:
  {J.Rlgl.disable_state_pointer(J.RlglArrays{[1], True{}, [], False{}, [], False{}}, 32884) == J.Rlgl.arrays() : J.Rlgl.Arrays}

law rlgl_arrays_range_from_offset:
  {J.Rlgl.arrays.range(3n, 4) == [4, 5, 6] : +List<U32>}

# config.h's options as raylib's default build sees them: rlgl compiles its
# OpenGL 1.1 software path; MAX_FILEPATH_CAPACITY is rcore.c's default.
law config_graphics_api_software:
  {J.Config.GRAPHICS_API_OPENGL_SOFTWARE() == True{} : Bool}

law config_graphics_api_11:
  {J.Config.GRAPHICS_API_OPENGL_11() == True{} : Bool}

law config_graphics_api_not_33:
  {J.Config.GRAPHICS_API_OPENGL_33() == False{} : Bool}

law config_filepath_capacity:
  {J.Config.MAX_FILEPATH_CAPACITY() == 8192 : U32}

# Importing Jonmath brings raymath's implementation.
law config_jonmath_implementation:
  {M.Config.JONMATH_IMPLEMENTATION() == True{} : Bool}

# Joneasings: the plain forms are the AppleLibm profile's; EaseExpoInOut's
# early returns need no libm.
law ease_sine_in_plain_is_apple:
  for t: F32
  for b: F32
  for c: F32
  for d: F32
  {E.Ease.sine_in(t, b, c, d) == E.Ease.sine_in_for(M.AppleLibm{}, t, b, c, d) : Maybe<F32>}

law ease_elastic_in_out_plain_is_apple:
  for t: F32
  for b: F32
  for c: F32
  for d: F32
  {E.Ease.elastic_in_out(t, b, c, d) == E.Ease.elastic_in_out_for(M.AppleLibm{}, t, b, c, d) : Maybe<F32>}

law ease_expo_in_out_start:
  for libm: M.Libm
  for t: F32
  for b: F32
  for c: F32
  for d: F32
  {E.Ease.expo_in_out.at(0, libm, t, b, c, d) == Some{b} : Maybe<F32>}

# Jonlights: at MAX_LIGHTS, CreateLight gives a zero light and keeps the count;
# the uniform names are rlights' lights[i].field.
law lights_create_full_is_zero:
  for kind: U32
  for position: M.Vector3
  for target: M.Vector3
  for color: U32
  for shader: J.Shader
  {Lt.Light.create(Lt.Lights{4}, kind, position, target, color, shader) == ((Lt.Lights{4}, Lt.Light.zero()), shader) : (Lt.Lights & Lt.Light) & J.Shader}

law lights_uniform_name:
  {Lt.Light.uniform(2, "color") == "lights[2].color" : String}

# The generated header modules call Jonlib's definitions.
law jonlgl_version_is_jonlib:
  {Lgl.Rlgl.get_version() == J.Rlgl.get_version() : U32}

law jonlgl_clip_planes_is_jonlib:
  for frame: J.Frame
  for near: M.Float64
  for far: M.Float64
  {Lgl.Rlgl.set_clip_planes(frame, near, far) == J.Rlgl.set_clip_planes(frame, near, far) : J.Frame}

law joncamera_forward_is_jonlib:
  for arithmetic: M.Contraction
  for camera: J.Camera3D
  {Cam.Camera.forward_for(arithmetic, camera) == J.Camera.forward_for(arithmetic, camera) : M.Vector3}

law jongestures_detected_is_jonlib:
  for core: J.Core
  {Gest.Gestures.get_detected(core) == J.Gestures.get_detected(core) : U32}

# jar_mod: "M.K." is four channels and "8CHN" eight; at 48000 Hz, speed 6
# and 125 beats a minute a row is 5760 + 2 samples; a short keeps its sign;
# the vibrato's half sine peaks at 16.
law mod_signature_mk:
  {Mods.signature.channels(77, 46, 75, 46) == 4 : U32}

law mod_signature_8chn:
  {Mods.signature.channels(56, 67, 72, 78) == 8 : U32}

law mod_start_aim:
  {Mods.tempo.aim(6, 125) == 5760 : U32}

law mod_short_negative:
  {Mods.s16(65535) == 4294967295 : U32}

law mod_sine_peak:
  {Mods.sine(16) == 255 : U32}

law mod_sine_after_peak:
  {Mods.sine(17) == 253 : U32}

# ".mod" and ".MOD" are raylib's MOD music (MUSIC_MODULE_MOD, 7).
law music_mod_kind:
  {J.Music.decode.kind(".mod") == 7 : U32}

law music_mod_kind_upper:
  {J.Music.decode.kind(".MOD") == 7 : U32}

# raylib 6.2's path checks: an absolute path starts with '/'; a hidden name
# starts with '.' but is not "." or ".."; GetPrevDirectoryPath passes a
# trailing separator.
law files_absolute:
  {J.Files.is_path_absolute("/usr") == True{} : Bool}

law files_relative:
  {J.Files.is_path_absolute("usr/bin") == False{} : Bool}

law files_hidden:
  {J.Files.is_file_hidden("dir/.config") == True{} : Bool}

law files_parent_not_hidden:
  {J.Files.is_file_hidden("dir/..") == False{} : Bool}

law files_previous_trailing:
  {J.Files.previous_directory_given("/usr/bin/", False{}) == Some{"/usr"} : Maybe<String>}

law pixel_size_empty:
  {J.Pixel.data_size(0, 2, 14) == Some{0} : Maybe<&2, U32>}

law pixel_size_last_fit:
  {J.Pixel.data_size_wide(2147483646, 1, 1) == Some{2147483646} : Maybe<&2, U32>}

law pixel_size_limit:
  {J.Pixel.data_size_wide(2147483647, 1, 1) == Some{0} : Maybe<&2, U32>}

law pixel_size_wrap:
  {J.Pixel.data_size_wide(67108865, 2147483617, 10) == Some{1073741328} : Maybe<&2, U32>}

law pixel_rgb5a1_blue:
  {J.Pixel.packed_color(5, 62) == 65280 : U32}

law convolution_edge_low:
  {Conv.neighbour(0, 1, 5) == 0 : U32}

law convolution_edge_high:
  {Conv.neighbour(6, 1, 5) == 4 : U32}

law ray_sphere_miss_zero:
  {J.Collision.ray.sphere.hit(M.Uncontracted{}, J.Ray{M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 1.0}}, M.Vector3{0.0, 0.0, 5.0}, False{}, False{}, 4.0) == J.RayCollision{False{}, 0.0, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 0.0}} : J.RayCollision}

law sha_padding_one_block:
  {ShaCore.padded_words(55) == 16 : U32}

law sha_padding_length_spills:
  {ShaCore.padded_words(56) == 32 : U32}

# 8*length as the two big-endian words raylib stores. The high word carries at 2^29.
law sha_bit_length_unit:
  {ShaCore.bit_length.words(1) == (0, 8) : U32 & U32}

law sha_bit_length_carry:
  {ShaCore.bit_length.words(536870912) == (1, 0) : U32 & U32}

# rlsw 6.2's SW_STATE_COLOR_INTERP rides in bit 32 of a primitive's sampler
# word: set only when its pushed colors differ, it leaves the texture kind
# (bits 0..2), the depth test (8) and the minification mark (16) alone.
law frame_interp_flag_set:
  {FrameCore.tex.interp(FrameCore.tex.with_interp(True{}, 26)) == True{} : Bool}

law frame_interp_flag_keeps_bits:
  {FrameCore.tex.with_interp(True{}, 26) == 58 : U32}

law frame_flat_keeps_sampler:
  {FrameCore.tex.with_interp(False{}, 26) == 26 : U32}

law frame_flat_not_interp:
  {FrameCore.tex.interp(26) == False{} : Bool}

# A primitive of one pushed vertex, or none, has no other color to differ from.
law frame_colors_single_vertex_flat:
  for v: FrameCore.Vertex
  {FrameCore.colors.interp(Con{v, Nil{}}) == False{} : Bool}

law frame_colors_empty_flat:
  {FrameCore.colors.interp(Nil{}) == False{} : Bool}

# Interpolated pixels keep their own colors.
law frame_interp_keeps_attributes:
  for flat: FrameCore.Attr
  for at: FrameCore.Attr
  {FrameCore.Attr.flat(True{}, flat, at) == at : FrameCore.Attr}

# raylib 6.2's DrawSphereEx face: triangles 0-3-1 and 0-2-3 of the rotated
# vertices; DrawSphereWires joins the same vertices with lines 0-1, 0-2, 0-3.
law sphere_face_triangles:
  {Shapes3D.sphere.face(False{}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{1.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 1.0}, M.Vector3{0.5, 0.5, 0.0}) == [FrameCore.Vertex3{0.0, 1.0, 0.0}, FrameCore.Vertex3{0.5, 0.5, 0.0}, FrameCore.Vertex3{1.0, 0.0, 0.0}, FrameCore.Vertex3{0.0, 1.0, 0.0}, FrameCore.Vertex3{0.0, 0.0, 1.0}, FrameCore.Vertex3{0.5, 0.5, 0.0}] : +List<FrameCore.Command>}

law sphere_wires_face_lines:
  {Shapes3D.sphere.face(True{}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{1.0, 0.0, 0.0}, M.Vector3{0.0, 0.0, 1.0}, M.Vector3{0.5, 0.5, 0.0}) == [FrameCore.Vertex3{0.0, 1.0, 0.0}, FrameCore.Vertex3{1.0, 0.0, 0.0}, FrameCore.Vertex3{0.0, 1.0, 0.0}, FrameCore.Vertex3{0.0, 0.0, 1.0}, FrameCore.Vertex3{0.0, 1.0, 0.0}, FrameCore.Vertex3{0.5, 0.5, 0.0}] : +List<FrameCore.Command>}

# GetImageColor, ImageDrawImageEx's reader: R8G8B8A8 words are Colors;
# GRAYSCALE replicates the byte with alpha 255.
law image_color_rgba:
  {J.Surface.image_color(7, 305419896) == 305419896 : U32}

law image_color_grayscale:
  {J.Surface.image_color(1, 128) == 2155905279 : U32}

# LoadRenderTextureEx: R8G8B8A8 loads, compressed formats are rejected, other
# color formats are outside the profile.
law render_texture_format_rgba:
  {J.RenderTexture.format_kind(7) == 0 : U32}

law render_texture_format_compressed:
  {J.RenderTexture.format_kind(14) == 1 : U32}

law render_texture_format_other:
  {J.RenderTexture.format_kind(4) == 2 : U32}


law gui_pick_hover_keeps_drag:
  for gui: JG.Gui
  for bounds: J.Rectangle
  {JG.Gui.pick.drag(4, gui, bounds) == gui : JG.Gui}

# dr_mp3's memory streams (src/mp3.bend): opened from memory, a stream has
# every byte before its tags at hand and none after them, is never filled,
# goes on while a decode passes bytes and is over when one passes none; a
# seek to its start gives it its bytes again. Waves and musics from memory
# are such streams; a music from a file is not.

law mp3_memory_stream_has_its_bytes_at_hand:
  {Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1) == Mp3.Stream{[1, 2, 3, 4, 5], 5, 4, 1, [2, 3, 4, 5], 3, 1, 1, 4294967295, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 0, 0} : Mp3.Stream}

law mp3_file_stream_begins_with_an_empty_buffer:
  {Mp3.stream.began(False{}, [1, 2, 3, 4, 5], 5, 4, 1) == Mp3.Stream{[1, 2, 3, 4, 5], 5, 4, 1, [2, 3, 4, 5], 0, 1, 1, 0, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 0, 0} : Mp3.Stream}

law mp3_memory_stream_is_told_by_its_capacity:
  {Mp3.stream.memory(Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1)) == True{} : Bool}

law mp3_file_stream_is_not_a_memory_stream:
  {Mp3.stream.memory(Mp3.stream.began(False{}, [1, 2, 3, 4, 5], 5, 4, 1)) == False{} : Bool}

law mp3_memory_stream_is_not_filled:
  {Mp3.stream.fill(Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1)) == Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1) : Mp3.Stream}

law mp3_memory_stream_goes_on_after_passed_bytes:
  {Mp3.stream.ended(Mp3.stream.refill(True{}, Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1), 2)) == False{} : Bool}

law mp3_memory_stream_is_over_when_no_byte_is_passed:
  {Mp3.stream.ended(Mp3.stream.refill(True{}, Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1), 0)) == True{} : Bool}

law mp3_memory_stream_rewound_has_its_bytes_again:
  {Mp3.stream.rewound(Mp3.stream.stopped(Mp3.stream.used(Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1), Mp3.Dec.zero(), 3), True{})) == Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1) : Mp3.Stream}

# dr_wav 0.14.6: a Wave64 chunk whose size is below its own 24-byte header
# ends the walk; one of exactly 24 is an empty chunk, skipped.
law wav_w64_chunk_below_header_ends_walk:
  {Wav.Scan.state(Wav.step([106, 117, 110, 107, 243, 172, 211, 17, 140, 209, 0, 192, 79, 142, 219, 138, 23, 0, 0, 0, 0, 0, 0, 0], 24, 2, False{}, Wav.Scan.initial(0, Wav.W{0, 0}, Wav.W{0, 0}, 0))) == 1 : U32}

law wav_w64_chunk_of_header_size_skipped:
  {Wav.Scan.state(Wav.step([106, 117, 110, 107, 243, 172, 211, 17, 140, 209, 0, 192, 79, 142, 219, 138, 24, 0, 0, 0, 0, 0, 0, 0], 24, 2, False{}, Wav.Scan.initial(0, Wav.W{0, 0}, Wav.W{0, 0}, 0))) == 0 : U32}

# dr_wav 0.14.6: a "fmt " chunk declared shorter than 16 bytes fails init.
law wav_fmt_chunk_below_16_fails:
  {Wav.Scan.state(Wav.fmt.chunk([1, 0, 1, 0, 64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0], 100, False{}, 0, Wav.W{0, 14}, 0, Wav.Scan.initial(0, Wav.W{0, 0}, Wav.W{0, 0}, 0))) == 2 : U32}

law wav_fmt_chunk_of_16_reads:
  {Wav.Scan.state(Wav.fmt.chunk([1, 0, 1, 0, 64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0], 100, False{}, 0, Wav.W{0, 16}, 0, Wav.Scan.initial(0, Wav.W{0, 0}, Wav.W{0, 0}, 0))) == 0 : U32}

# ADPCM blocks: a trailing partial block counts.
law wav_adpcm_blocks_count_partial:
  {Wav.block.count(Wav.W{0, 37}, 32) == Wav.W{0, 2} : Wav.W}

# IMA ADPCM without a fact count whose one block header (4 bytes) is the
# whole data chunk: dr_wav 0.14.6 fails init.
law wave_wav_ima_headers_fill_data:
  {J.Wave.decode(".wav", [82, 73, 70, 70, 44, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 20, 0, 0, 0, 17, 0, 1, 0, 64, 31, 0, 0, 0, 0, 0, 0, 36, 0, 4, 0, 2, 0, 65, 0, 100, 97, 116, 97, 4, 0, 0, 0, 232, 3, 0, 0]) == Fail{J.InvalidWaveHeader{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

# An AIFF COMM count of 3 frames over one frame of data: raylib 6.2's
# RL_CALLOC'd wave ends in zeros (0x0102 big-endian is 258).
law wave_aiff_unread_frames_are_zeros:
  {J.Wave.decode(".wav", [70, 79, 82, 77, 0, 0, 0, 48, 65, 73, 70, 70, 67, 79, 77, 77, 0, 0, 0, 18, 0, 1, 0, 0, 0, 3, 0, 16, 64, 14, 172, 68, 0, 0, 0, 0, 0, 0, 83, 83, 78, 68, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2]) == Done{J.Wave{3, 44100, 16, 1, [258, 0, 0]}} : Result<&1, &1, J.Wave.Error, J.Wave>}

# Zero padding: nothing added when no frame is missing, otherwise the zeros
# after the samples in order.
law wav_zero_padded_none_missing:
  {Wav.zero_padded(0n, [5, 7]) == [5, 7] : +List<U32>}

law wav_zero_padded_after_samples:
  {Wav.zero_padded(2n, [5, 7]) == [5, 7, 0, 0] : +List<U32>}

# Zeros past 2^24 samples are past the port's limits; none to add never is.
law wav_zeros_limit_past_2_24:
  {Wav.zero_filled.over(16777217, 0, 1) == True{} : Bool}

law wav_zeros_limit_at_2_24:
  {Wav.zero_filled.over(8388608, 0, 2) == False{} : Bool}

law wav_zeros_limit_nothing_unread:
  {Wav.zero_filled.over(16777217, 16777217, 1) == False{} : Bool}

# stb_vorbis gave 1 of 3 frames: raylib 6.2's wave ends in zeros.
law wave_ogg_unread_frames_are_zeros:
  {J.Wave.ogg.whole(True{}, 3, 8000, 1, 1, [5]) == Done{J.Wave{3, 8000, 16, 1, [5, 0, 0]}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_zeros_past_limit:
  {J.Wave.ogg.whole(True{}, 16777217, 8000, 1, 0, Nil{}) == Fail{J.UnsupportedWaveFormat{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

# qoa.h of raylib 6.2: a frame size below its own header, more than 256
# slices a channel; one slice in a 32-byte mono frame fits.
law qoa_frame_size_below_its_header:
  {Qoa.frame.refused(1000, 1, 8000, 1, 8000, 20, 23) == True{} : Bool}

law qoa_frame_of_one_slice_fits:
  {Qoa.frame.refused(1000, 1, 8000, 1, 8000, 20, 32) == False{} : Bool}

law qoa_frame_257_slices_refused:
  {Qoa.frame.refused(10000, 1, 8000, 1, 8000, 5121, 2080) == True{} : Bool}

# qoa_decode's buffer, rounded up to whole frames, past 0x7fffffff samples.
law qoa_buffer_rounded_at_limit:
  {Qoa.buffer.refused(2147481600, 1) == False{} : Bool}

law qoa_buffer_rounded_past_limit:
  {Qoa.buffer.refused(2147481601, 1) == True{} : Bool}

# dr_mp3 (raylib 6.2) checks that each part of an Xing/Info tag fits in the
# frame; one that does not ends the reading and the frame is played, with
# a frame count already read kept.
law mp3_info_table_past_frame_not_a_tag:
  {Mp3.info.read([73, 110, 102, 111, 0, 0, 0, 15, 0, 0, 0, 12], 36, 104) == Mp3.Info{False{}, 12, 0, 0} : Mp3.Info}

law mp3_info_too_small_for_its_name:
  {Mp3.info.read([73, 110, 102, 111, 0, 0, 0, 15, 0, 0, 0, 12], 36, 43) == Mp3.Info{False{}, 4294967295, 0, 0} : Mp3.Info}

law mp3_info_lame_tag_short_not_a_tag:
  {Mp3.info.read([73, 110, 102, 111, 0, 0, 0, 0, 76], 36, 79) == Mp3.Info{False{}, 4294967295, 0, 0} : Mp3.Info}

law mp3_info_lame_tag_fits:
  {Mp3.info.read([73, 110, 102, 111, 0, 0, 0, 0, 76], 36, 80) == Mp3.Info{True{}, 4294967295, 529, 0} : Mp3.Info}

# The 64-bit total's high word: 3728271 * 1152 = 2^32 + 896,
# 11184811 * 1152 = 3 * 2^32 + 384; country.mp3's fits in 32 bits.
law mp3_total_high_word_one:
  {Mp3.product.high(3728271, 1152) == 1 : U32}

law mp3_total_high_word_three:
  {Mp3.product.high(11184811, 1152) == 3 : U32}

law mp3_total_high_word_zero:
  {Mp3.product.high(3583, 1152) == 0 : U32}

# A total of 2^32 or more is above the delay and the padding: both go, and
# the low word is the count (3 * 2^32 + 384 - 1105 - 577, mod 2^32).
law mp3_total_wide_subtracts_both:
  {Mp3.total.tagged(384, 1105, 577, True{}) == 4294965998 : U32}

law mp3_total_narrow_keeps_small:
  {Mp3.total.tagged(384, 1105, 577, False{}) == 384 : U32}

# The padding edge: 2^32 + 896 less 577 is past a 32-bit position; 2^32 +
# 100 less 577 is 2^32 - 477.
law mp3_limit_wide_past_32_bits:
  {Mp3.limit.known(2, 896, 577) == False{} : Bool}

law mp3_limit_narrow_edge_known:
  {Mp3.limit.known(1, 4127616, 577) == True{} : Bool}

law mp3_limit_narrow_edge:
  {Mp3.limit.edge(1, 4127616, 577) == 4127039 : U32}

law mp3_limit_wide_below_padding:
  {Mp3.limit.known(2, 100, 577) == True{} : Bool}

law mp3_limit_wide_below_padding_edge:
  {Mp3.limit.edge(2, 100, 577) == 4294966819 : U32}

law mp3_limit_high_three:
  {Mp3.limit.known(4, 384, 577) == False{} : Bool}

# dr_mp3's temporary buffers hold 1152*2 samples (raylib 6.2).
law mp3_temp_frames_stereo:
  {Mp3S.temp.frames(2) == 1152 : U32}

law mp3_temp_frames_mono:
  {Mp3S.temp.frames(1) == 2304 : U32}

# Passing more bytes than the stream has leaves none to decode: the byte that
# stays listed is the tag's, past what the stream holds.
law mp3_memory_stream_holds_no_byte_of_its_tags:
  {Mp3.stream.used(Mp3.stream.began(True{}, [1, 2, 3, 4, 5], 5, 4, 1), Mp3.Dec.zero(), 9) == Mp3.Stream{[1, 2, 3, 4, 5], 5, 4, 1, [5], 0, 1, 1, 4294967295, False{}, Mp3.Dec.zero(), 0, 0, 0, 0, 0, 0} : Mp3.Stream}

law mp3_memory_of_a_short_file_does_not_open:
  {Mp3.open.memory([255, 251, 144, 68]) == None{} : Maybe<Mp3.Opened>}

law mp3_stream_memory_of_a_short_file_does_not_open:
  {Mp3S.open.memory([255, 251, 144, 68]) == None{} : Maybe<Mp3S.Player>}

law wave_mp3_length_counts_bytes:
  {J.Wave.mp3.length([7, 8, 9], 0) == 3 : U32}

law music_kind_of_mp3_tokens:
  {((J.Music.decode.kind(".mp3") * 100) + (J.Music.decode.kind(".MP3") * 10) + J.Music.decode.kind(".Mp3") : U32) == 440 : U32}

law music_kind_of_wav_and_qoa_tokens:
  {((J.Music.decode.kind(".wav") * 10) + J.Music.decode.kind(".QOA") : U32) == 15 : U32}

# PNG sizes (src/png.bend): the decoder takes headers of up to 16384 pixels on
# a side and 4096*4096 pixels, and each decode keeps to its own side: 4096
# for an image (Png.decode), 16384 for a texture's file (Png.decode.wide). An
# invalid header is refused before its size is looked at.

law png_image_keeps_4096_on_a_side:
  {Png.config.within(4096, Done{Png.Config{3, 5000, 6, 4, 8, False{}}}) == Fail{Codec.BadSize{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_texture_strip_within_16384:
  {Png.config.within(16384, Done{Png.Config{3, 5000, 6, 4, 8, False{}}}) == Done{Png.Config{3, 5000, 6, 4, 8, False{}}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_side_limit_passes_errors_on:
  {Png.config.within(16384, Fail{Codec.BadHeader{}}) == Fail{Codec.BadHeader{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_header_of_4096_squared_pixels:
  {Png.config.valid(True{}, 16384, 1024, 2, 3, 8, False{}) == Done{Png.Config{16384, 1024, 2, 3, 8, False{}}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_header_past_4096_squared_pixels:
  {Png.config.valid(True{}, 16384, 1025, 2, 3, 8, False{}) == Fail{Codec.BadSize{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_header_past_16384_on_a_side:
  {Png.config.valid(True{}, 1, 16385, 6, 4, 8, False{}) == Fail{Codec.BadSize{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_header_without_rows:
  {Png.config.valid(True{}, 7, 0, 6, 4, 8, False{}) == Fail{Codec.BadSize{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_image_of_4096_on_each_side:
  {Png.config.within(4096, Png.config.valid(True{}, 4096, 4096, 0, 1, 8, False{})) == Done{Png.Config{4096, 4096, 0, 1, 8, False{}}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_image_of_4097_on_a_side:
  {Png.config.within(4096, Png.config.valid(True{}, 4097, 1, 0, 1, 8, False{})) == Fail{Codec.BadSize{}} : Result<&2, &2, Codec.Error, Png.Config>}

law png_invalid_header_before_its_size:
  {Png.config.valid(False{}, 99999, 99999, 0, 1, 8, False{}) == Fail{Codec.BadHeader{}} : Result<&2, &2, Codec.Error, Png.Config>}

# Ogg Vorbis codebooks (src/vorbis_codebook.bend, after stb_vorbis): ilog and
# bit_reverse, float32_unpack's bits (a 21-bit mantissa scaled by a power of
# two and narrowed once: 2^(e - 788), so 788 is one), compute_codewords (the
# first code is 0, a later one the lowest free leaf at its length or above),
# the sorted table (the codes read the other way, ascending, with a sentinel)
# and the accelerated one (a short code at every index it begins).

law vorbis_ilog_counts_the_bits:
  {((V.ilog(0) * 1000) + (V.ilog(1) * 100) + (V.ilog(4) * 10) + V.ilog(7) : U32) == 133 : U32}

law vorbis_ilog_of_the_largest_int:
  {V.ilog(2147483647) == 31 : U32}

law vorbis_ilog_of_a_negative_int:
  {(V.ilog(4294967295) + V.ilog(2147483648) : U32) == 0 : U32}

law vorbis_bit_reverse_of_the_low_bit:
  {V.bit.reverse(1) == 2147483648 : U32}

law vorbis_bit_reverse_of_the_low_half:
  {V.bit.reverse(65535) == 4294901760 : U32}

law vorbis_bit_reverse_twice:
  {V.bit.reverse(V.bit.reverse(305419896)) == 305419896 : U32}

law vorbis_unpack_one:
  {V.unpack.bits(1, 0, 788) == 1065353216 : U32}

law vorbis_unpack_three:
  {V.unpack.bits(3, 1, 788) == 1077936128 : U32}

law vorbis_unpack_largest_finite:
  {V.unpack.bits(2097151, 20, 895) == 2139095032 : U32}

law vorbis_unpack_past_the_floats:
  {V.unpack.bits(1, 0, 916) == 2139095040 : U32}

law vorbis_unpack_smallest_normal:
  {V.unpack.bits(1, 0, 662) == 8388608 : U32}

law vorbis_unpack_smallest_subnormal:
  {V.unpack.bits(1, 0, 639) == 1 : U32}

law vorbis_unpack_half_the_smallest_is_zero:
  {V.unpack.bits(1, 0, 638) == 0 : U32}

law vorbis_unpack_a_tie_goes_to_even:
  {V.unpack.bits(3, 1, 638) == 2 : U32}

law vorbis_unpack_far_below_the_floats:
  {V.unpack.bits(2097151, 20, 0) == 0 : U32}

law vorbis_codewords_of_a_tree:
  {V.codewords([2, 1, 2]) == Some{[V.Entry{0, 0, 2}, V.Entry{1, 1, 1}, V.Entry{2, 2, 2}]} : Maybe<+List<V.Entry>>}

law vorbis_codewords_skip_a_symbol_without_a_code:
  {V.codewords([255, 1, 255, 2]) == Some{[V.Entry{1, 0, 1}, V.Entry{3, 1, 2}]} : Maybe<+List<V.Entry>>}

law vorbis_codewords_of_too_many_lengths:
  {V.codewords([1, 1, 1]) == None{} : Maybe<+List<V.Entry>>}

law vorbis_codewords_of_no_symbol:
  {V.codewords([255, 255]) == Some{Nil{}} : Maybe<+List<V.Entry>>}

law vorbis_free_level_is_the_highest_up_to_the_length:
  {V.free.level([0, 5, 0, 7, 9], 0, 3, 0) == 3 : U32}

law vorbis_free_level_without_a_leaf:
  {V.free.level([0, 0, 0, 7], 0, 2, 0) == 0 : U32}

law vorbis_taken_frees_the_leaves_beside_the_path:
  {V.taken([0, 2147483648, 0, 0], 0, 1, 3, 2147483648, Nil{}) == [0, 0, 3221225472, 2684354560] : +List<U32>}

law vorbis_sorted_by_the_codes_read_the_other_way:
  {V.symbols(V.sorted.runs(32n, V.runs.of([V.Entry{0, 0, 2}, V.Entry{1, 1, 1}, V.Entry{2, 2, 2}], Nil{})), Nil{}) == [0, 2, 1] : +List<U32>}

law vorbis_sorted_codewords_end_with_the_sentinel:
  {V.codes.reversed([V.Entry{0, 0, 2}, V.Entry{2, 2, 2}, V.Entry{1, 1, 1}], Nil{}) == [0, 1073741824, 2147483648, 4294967295] : +List<U32>}

law vorbis_sorted_table_keeps_the_long_codes:
  {V.kept([V.Entry{0, 0, 10}, V.Entry{1, 5, 11}], False{}, Nil{}) == [V.Entry{1, 5, 11}] : +List<V.Entry>}

law vorbis_sorted_table_of_a_sparse_codebook_keeps_all:
  {V.kept([V.Entry{0, 0, 10}, V.Entry{1, 5, 11}], True{}, Nil{}) == [V.Entry{0, 0, 10}, V.Entry{1, 5, 11}] : +List<V.Entry>}

law vorbis_fast_fill_steps_by_the_code_s_period:
  {Array.to_list(~U32, V.fast.fill(2n, 1, 2, 7, Array.new(U32, 2n, 9))) == [9, 7, 9, 7] : List<U32>}

law vorbis_fast_entry_past_the_shorts_fills_nothing:
  {Array.to_list(~U32, V.fast.entries([V.Entry{40000, 0, 1}], True{}, 0, Array.new(U32, 1n, 9))) == [9, 9] : List<U32>}

law vorbis_fast_entry_of_a_long_code_fills_nothing:
  {Array.to_list(~U32, V.fast.entries([V.Entry{3, 0, 11}], True{}, 0, Array.new(U32, 1n, 9))) == [9, 9] : List<U32>}

law vorbis_codewords_by_symbol:
  {V.by.symbol([2, 255, 1, 2], [V.Entry{0, 0, 2}, V.Entry{2, 1, 1}, V.Entry{3, 2, 2}], Nil{}) == [0, 0, 1, 2] : +List<U32>}

law vorbis_no_tree_no_codebook:
  {V.book.coded(None{}, [1, 1, 1], False{}) == None{} : Maybe<V.Book>}

# lookup1_values (src/vorbis_codebook.bend): the integer root where
# stb_vorbis's estimate of it is surely within its correction, nothing where
# it hangs on the C library's last bits or where the C code converts a
# power of 2^31 or more to int.

law vorbis_power_capped_is_the_power:
  {((V.power.capped(3, 4) * 1000) + V.power.capped(7, 1) : U32) == 81007 : U32}

law vorbis_power_capped_stops_at_2_26:
  {((V.power.capped(2, 26) + V.power.capped(2, 65535)) + V.power.capped(16777215, 2) : U32) == 201326592 : U32}

law vorbis_power_capped_of_one_and_zero:
  {((V.power.capped(1, 65535) * 10) + V.power.capped(0, 9) : U32) == 10 : U32}

law vorbis_root_of_one_dimension:
  {V.root(16777215, 1) == 16777215 : U32}

law vorbis_root_of_a_square:
  {((V.root(4096, 2) * 100) + V.root(4095, 2) : U32) == 6463 : U32}

law vorbis_root_of_many_dimensions:
  {((V.root(16777215, 23) * 10) + V.root(16777215, 24) : U32) == 21 : U32}

law vorbis_lookup1_of_a_perfect_power:
  {V.lookup1.values(6561, 8) == Some{3} : Maybe<U32>}

law vorbis_lookup1_under_a_perfect_power:
  {V.lookup1.values(6560, 8) == Some{2} : Maybe<U32>}

law vorbis_lookup1_of_one_entry:
  {V.lookup1.values(1, 5) == Some{1} : Maybe<U32>}

law vorbis_lookup1_without_entries:
  {V.lookup1.values(0, 3) == Some{0} : Maybe<U32>}

law vorbis_lookup1_without_entries_or_dimensions:
  {V.lookup1.values(0, 0) == Some{4294967295} : Maybe<U32>}

law vorbis_lookup1_without_dimensions_is_undefined:
  {V.lookup1.values(5, 0) == None{} : Maybe<U32>}

law vorbis_lookup1_of_2_19_entries_in_one_dimension:
  {V.lookup1.values(524288, 1) == Some{524288} : Maybe<U32>}

law vorbis_lookup1_past_2_19_entries_in_one_dimension:
  {V.lookup1.values(524289, 1) == None{} : Maybe<U32>}

law vorbis_lookup1_of_a_large_codebook_away_from_a_power:
  {V.lookup1.values(16777000, 2) == Some{4095} : Maybe<U32>}

law vorbis_lookup1_of_a_large_codebook_just_under_a_power:
  {V.lookup1.values(16777215, 2) == None{} : Maybe<U32>}

law vorbis_lookup1_of_30_dimensions:
  {V.lookup1.values(600000, 30) == Some{1} : Maybe<U32>}

law vorbis_lookup1_of_31_dimensions_is_undefined:
  {V.lookup1.values(5, 31) == None{} : Maybe<U32>}

law vorbis_lookup1_of_a_root_of_two_in_20_dimensions_is_undefined:
  {V.lookup1.values(1048576, 20) == None{} : Maybe<U32>}

law vorbis_lookup1_of_a_root_of_two_in_19_dimensions:
  {V.lookup1.values(524288, 19) == Some{2} : Maybe<U32>}

law vorbis_lookup1_past_24_bits_of_entries:
  {V.lookup1.values(16777216, 2) == None{} : Maybe<U32>}

law vorbis_lookup1_past_16_bits_of_dimensions:
  {V.lookup1.values(5, 65536) == None{} : Maybe<U32>}

# Ogg data as stb_vorbis reads it (src/vorbis_ogg.bend): bytes (0 and eof
# past the end, a skip that moves past it), pages (the capture pattern, the
# version, the segment table), packets over the pages' segments (EOP at
# their end, a continued page where one is and is not due) and bits (the
# first one lowest, zeros once they ran out).

law ogg_get8_at_the_end_is_zero:
  {Ogg.Reader.value(Ogg.get8(Ogg.open(Nil{}))) == 0 : U32}

law ogg_get8_at_the_end_is_eof:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.get8(Ogg.open(Nil{})))) == True{} : Bool}

law ogg_get32_is_low_byte_first:
  {Ogg.Reader.value(Ogg.get32(Ogg.open([1, 2, 3, 4]))) == 67305985 : U32}

law ogg_get32_past_the_end_reads_zeros:
  {Ogg.Reader.value(Ogg.get32(Ogg.open([1, 2]))) == 513 : U32}

law ogg_getn_of_more_than_is_left_fails:
  {Ogg.Reader.value(Ogg.getn(Ogg.open([1, 2, 3]), 4)) == 0 : U32}

law ogg_getn_of_more_than_is_left_reads_nothing:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.getn(Ogg.open([1, 2, 3]), 4))) == 0 : U32}

law ogg_getn_gives_the_bytes:
  {Ogg.Reader.taken(Ogg.getn(Ogg.open([1, 2, 3]), 2)) == [1, 2] : +List<U32>}

law ogg_skip_moves_past_the_end:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.skip(Ogg.open([1, 2, 3]), 5))) == 5 : U32}

law ogg_skip_to_the_end_is_eof:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.skip(Ogg.open([1, 2, 3]), 3))) == True{} : Bool}

law ogg_skip_short_of_the_end_is_not_eof:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.skip(Ogg.open([1, 2, 3]), 2))) == False{} : Bool}

law ogg_page_without_its_capture_pattern:
  {Ogg.Reader.error(Ogg.page.start(Ogg.open([79, 103, 103, 84, 0, 0]))) == 30 : U32}

law ogg_capture_pattern_stops_at_the_wrong_byte:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.page.start(Ogg.open([79, 104, 103, 83, 0, 0])))) == 2 : U32}

law ogg_page_of_another_version:
  {Ogg.Reader.error(Ogg.page.start(Ogg.open([79, 103, 103, 83, 1, 0]))) == 31 : U32}

law ogg_page_with_a_cut_segment_table:
  {Ogg.Reader.error(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 3, 9]))) == 10 : U32}

law ogg_page_starts:
  {Ogg.Reader.value(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7]))) == 1 : U32}

law ogg_page_start_stops_at_the_body:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))) == 28 : U32}

law ogg_page_keeps_its_flags:
  {Ogg.Page.flag(Ogg.Reader.page(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))) == 2 : U32}

law ogg_packet_first_byte:
  {Ogg.Reader.value(Ogg.packet.get8.raw(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7]))))) == 9 : U32}

law ogg_packet_ends_after_its_segment:
  {Ogg.Reader.value(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))))) == 4294967295 : U32}

law ogg_packet_end_is_no_error:
  {Ogg.Reader.error(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))))) == 0 : U32}

law ogg_get32_packet_adds_the_end_as_minus_one:
  {Ogg.Reader.value(Ogg.packet.get32(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7]))))) == 4278650889 : U32}

law ogg_bits_are_read_low_first:
  {Ogg.Reader.value(Ogg.bits.get(3, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 181, 8, 7]))))) == 5 : U32}

law ogg_bits_go_on_where_the_last_ended:
  {Ogg.Reader.value(Ogg.bits.get(5, Ogg.bits.get(3, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 181, 8, 7])))))) == 22 : U32}

law ogg_bits_of_no_width:
  {Ogg.Reader.value(Ogg.bits.get(0, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 181, 8, 7]))))) == 0 : U32}

law ogg_bits_of_32:
  {Ogg.Reader.value(Ogg.bits.get(32, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4, 1, 2, 3, 4]))))) == 67305985 : U32}

law ogg_bits_past_the_packet_are_zero:
  {Ogg.Reader.value(Ogg.bits.get(16, Ogg.bits.get(16, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))) == 0 : U32}

law ogg_bits_past_the_packet_stay_out:
  {Ogg.Packet.valid(Ogg.Reader.packet(Ogg.bits.get(1, Ogg.bits.get(16, Ogg.bits.get(16, Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))))) == 4294967295 : U32}

law ogg_flush_passes_the_packet:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.flush.packet(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))) == 31 : U32}

law ogg_no_packet_at_the_end_is_no_error:
  {(Ogg.Reader.error(Ogg.packet.maybe(Ogg.flush.packet(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))) + Ogg.Reader.value(Ogg.packet.maybe(Ogg.flush.packet(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))) : U32) == 0 : U32}

law ogg_start_packet_at_the_end_is_an_error:
  {Ogg.Reader.error(Ogg.packet.start(Ogg.flush.packet(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])))))) == 30 : U32}

law ogg_continued_page_starts_no_packet:
  {Ogg.Reader.error(Ogg.packet.start(Ogg.flush.packet(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7, 79, 103, 103, 83, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 5, 6])))))) == 32 : U32}

law ogg_continued_page_is_needed_to_go_on:
  {Ogg.Reader.value(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.get8.raw(Ogg.packet.start(Ogg.page.start(Ogg.open([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7, 79, 103, 103, 83, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 5, 6])))))))) == 4294967295 : U32}

# The Vorbis setup as far as the codebooks (src/vorbis_setup.bend): the
# first failed check of a header decides; a length or a count sizes an
# allocation (a negative one is out of memory, one over 16 MiB is refused);
# the identification header's tests and fields; what a comment header and a
# setup header that are not ones come to, with stb_vorbis's error codes
# (34 invalid first page, 38 Ogg skeleton, 10 unexpected end, 5 too many
# channels, 20 invalid setup, 3 out of memory, 30 no page, 0 none).

law vorbis_setup_going:
  {VS.going(VS.Going{}) == True{} : Bool}

law vorbis_setup_refused_is_not_going:
  {VS.going(VS.Refused{1}) == False{} : Bool}

law vorbis_setup_failed_without_an_error_is_not_going:
  {VS.going(VS.Failed{0}) == False{} : Bool}

law vorbis_setup_first_failed_check_wins:
  {VS.checked([VS.Check{False{}, VS.Failed{1}}, VS.Check{True{}, VS.Failed{2}}, VS.Check{True{}, VS.Refused{3}}], VS.Going{}, True{}) == VS.Failed{2} : VS.Status}

law vorbis_setup_no_failed_check_goes_on:
  {VS.checked([VS.Check{False{}, VS.Failed{1}}, VS.Check{False{}, VS.Failed{2}}], VS.Going{}, True{}) == VS.Going{} : VS.Status}

law vorbis_setup_name_is_vorbis:
  {VS.named([118, 111, 114, 98, 105, 115]) == True{} : Bool}

law vorbis_setup_name_of_another_case:
  {VS.named([86, 111, 114, 98, 105, 115]) == False{} : Bool}

law vorbis_setup_name_cut_short:
  {VS.named([118, 111, 114, 98, 105]) == False{} : Bool}

law vorbis_setup_length_within_the_budget:
  {VS.sized(16777216) == VS.Going{} : VS.Status}

law vorbis_setup_length_over_the_budget_is_refused:
  {VS.sized(16777217) == VS.Refused{3} : VS.Status}

law vorbis_setup_length_of_the_largest_int_is_refused:
  {VS.sized(2147483647) == VS.Refused{3} : VS.Status}

law vorbis_setup_negative_length_is_out_of_memory:
  {VS.sized(4294967295) == VS.Failed{3} : VS.Status}

law vorbis_setup_most_negative_length_is_out_of_memory:
  {VS.sized(2147483648) == VS.Failed{3} : VS.Status}

law vorbis_setup_no_comment_list:
  {VS.listed(0) == VS.Going{} : VS.Status}

law vorbis_setup_negative_comment_count_is_no_list:
  {(VS.comment.count(4294967295) + VS.comment.count(2147483648) : U32) == 0 : U32}

law vorbis_setup_negative_comment_count_goes_on:
  {VS.listed(4294967295) == VS.Going{} : VS.Status}

law vorbis_setup_comment_list_within_the_budget:
  {VS.listed(2097152) == VS.Going{} : VS.Status}

law vorbis_setup_comment_list_over_the_budget_is_refused:
  {VS.listed(2097153) == VS.Refused{3} : VS.Status}

law vorbis_setup_comment_list_of_negative_size_is_out_of_memory:
  {VS.listed(268435456) == VS.Failed{3} : VS.Status}

law vorbis_setup_comment_list_smaller_than_its_count_is_refused:
  {VS.listed(536870912) == VS.Refused{3} : VS.Status}

law vorbis_setup_product_of_entries_and_dimensions:
  {VS.product(4096, 1000) == Some{4096000} : Maybe<U32>}

law vorbis_setup_product_past_the_ints:
  {VS.product(524288, 4096) == None{} : Maybe<U32>}

law vorbis_setup_product_under_the_ints:
  {VS.product(524288, 4095) == Some{2146959360} : Maybe<U32>}

law vorbis_setup_product_without_dimensions:
  {VS.product(5, 0) == Some{0} : Maybe<U32>}

law vorbis_setup_divisor_within_the_unsigned_ints:
  {VS.div.over(31n, 2, 1, False{}) == False{} : Bool}

law vorbis_setup_divisor_past_the_unsigned_ints:
  {VS.div.over(32n, 2, 1, False{}) == True{} : Bool}

law vorbis_setup_divisor_of_one_value_never_passes:
  {VS.div.over(64n, 1, 1, False{}) == False{} : Bool}

law vorbis_setup_repeated:
  {VS.repeated(3n, 7, [1]) == [7, 7, 7, 1] : +List<U32>}

law vorbis_setup_range:
  {VS.range(3n, 5, Nil{}) == [5, 6, 7] : +List<U32>}

law vorbis_setup_of_no_data:
  {VS.Setup.status(VS.setup.codebooks([])) == VS.Failed{30} : VS.Status}

law vorbis_setup_first_page_of_another_length:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 9, 8, 7])) == VS.Failed{34} : VS.Status}

law vorbis_setup_first_page_not_flagged_first:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1])) == VS.Failed{34} : VS.Status}

law vorbis_setup_ogg_skeleton:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 64, 102, 105, 115, 104, 101, 97, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{38} : VS.Status}

law vorbis_setup_identification_alone:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1])) == VS.Failed{30} : VS.Status}

law vorbis_setup_identification_cut_in_its_name:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114])) == VS.Failed{10} : VS.Status}

law vorbis_setup_seventeen_channels:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 17, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1])) == VS.Failed{5} : VS.Status}

law vorbis_setup_no_sample_rate:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1])) == VS.Failed{34} : VS.Status}

law vorbis_setup_block_size_under_64:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 181, 1])) == VS.Failed{20} : VS.Status}

law vorbis_setup_first_block_size_over_the_second:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 154, 1])) == VS.Failed{20} : VS.Status}

law vorbis_setup_channels_of_the_identification:
  {VS.Head.channels(VS.Setup.head(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 6, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1]))) == 6 : U32}

law vorbis_setup_rate_of_the_identification:
  {VS.Head.rate(VS.Setup.head(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 34, 86, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1]))) == 22050 : U32}

law vorbis_setup_block_sizes_of_the_identification:
  {((VS.Head.blocksize_0(VS.Setup.head(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 214, 1]))) * 10000) + VS.Head.blocksize_1(VS.Setup.head(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 214, 1]))) : U32) == 648192 : U32}

law vorbis_setup_comment_header_of_another_type:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 5, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{20} : VS.Status}

law vorbis_setup_empty_comment_packet_fails_without_an_error:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 21, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{0} : VS.Status}

law vorbis_setup_negative_vendor_length:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 255, 255, 255, 255, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{3} : VS.Status}

law vorbis_setup_vendor_over_the_budget:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 1, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Refused{3} : VS.Status}

law vorbis_setup_comment_without_its_framing_bit:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 0, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{20} : VS.Status}

law vorbis_setup_without_its_third_packet:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 17, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1])) == VS.Failed{30} : VS.Status}

law vorbis_setup_header_of_another_type:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 3, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{20} : VS.Status}

law vorbis_setup_codebook_without_its_sync_pattern:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 87, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{20} : VS.Status}

law vorbis_setup_codebook_without_entries_is_out_of_memory:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 20, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 0, 0, 0, 0, 0, 0, 0])) == VS.Failed{3} : VS.Status}

law vorbis_setup_codebook_over_the_budget_is_refused:
  {VS.Setup.status(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 23, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 1, 0, 8, 103, 0, 0, 2, 0, 0, 0])) == VS.Refused{4} : VS.Status}

# The Vorbis setup after the codebooks (src/vorbis_maps.bend): a floor's
# classes and points (their order by place, each point's neighbours among
# the points before it), and what the floors, residues, mappings and modes
# come to: the stage the setup fails in, stb_vorbis's codes (4 a floor of
# type 0, 20 invalid setup), and the refusal of a sixteenth submap.

law vorbis_maps_nth:
  {((VM.nth([5, 6, 7], 1) * 10) + VM.nth([5, 6, 7], 3) : U32) == 60 : U32}

law vorbis_maps_subclass_book_past_the_codebooks:
  {VM.books.over([0, 3], 2, False{}) == True{} : Bool}

law vorbis_maps_subclass_book_the_last_codebook:
  {VM.books.over([0, 2], 2, False{}) == False{} : Bool}

law vorbis_maps_subclass_books_are_read_one_more:
  {VM.less.one([0, 5], Nil{}) == [4294967295, 4] : +List<U32>}

law vorbis_maps_classes_are_the_largest_and_one:
  {VM.classes.count([0, 3, 1], 0) == 4 : U32}

law vorbis_maps_no_partition_no_class:
  {VM.classes.count(Nil{}, 0) == 0 : U32}

law vorbis_maps_points_of_the_partitions:
  {VM.points.count([0, 1, 0], [VM.Class{2, 0, 0, Nil{}}, VM.Class{3, 0, 0, Nil{}}], 0) == 7 : U32}

law vorbis_maps_points_sorted_by_place:
  {VM.points.ids(VM.points.sorted([0, 32, 9, 30, 4], 0, Nil{}), Nil{}) == [0, 4, 2, 3, 1] : +List<U32>}

law vorbis_maps_two_points_at_one_place:
  {VM.points.doubled(VM.points.sorted([0, 16, 5, 5], 0, Nil{}), 0, True{}, False{}) == True{} : Bool}

law vorbis_maps_a_point_at_the_first_place:
  {VM.points.doubled(VM.points.sorted([0, 16, 5, 0], 0, Nil{}), 0, True{}, False{}) == True{} : Bool}

law vorbis_maps_points_at_different_places:
  {VM.points.doubled(VM.points.sorted([0, 16, 5, 6], 0, Nil{}), 0, True{}, False{}) == False{} : Bool}

law vorbis_maps_neighbor_below:
  {VM.neighbor([0, 32, 9], 30, False{}, 0, 0, 0) == 2 : U32}

law vorbis_maps_neighbor_above:
  {VM.neighbor([0, 32, 9], 30, True{}, 0, 65536, 0) == 1 : U32}

law vorbis_maps_neighbors_below:
  {VM.neighbors(3n, [0, 32, 9, 30, 4], 2, False{}, Nil{}) == [0, 2, 0] : +List<U32>}

law vorbis_maps_neighbors_above:
  {VM.neighbors(3n, [0, 32, 9, 30, 4], 2, True{}, Nil{}) == [1, 1, 2] : +List<U32>}

law vorbis_maps_channel_of_another_submap:
  {VM.mux.over([0, 2], 2, False{}) == True{} : Bool}

law vorbis_maps_channels_of_the_submaps:
  {VM.mux.over([1, 0], 2, False{}) == False{} : Bool}

law vorbis_maps_whole_setup_goes_on:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == VS.Going{} : VS.Status}

law vorbis_maps_whole_setup_comes_to_the_end:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == 5 : U32}

law vorbis_maps_audio_begins_after_the_header_s_page:
  {VM.Maps.audio(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == 155 : U32}

law vorbis_maps_setup_cut_after_its_floors_is_whole:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 25, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32]))) == 5 : U32}

law vorbis_maps_floor_of_type_0_is_not_supported:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{4} : VS.Status}

law vorbis_maps_floor_of_type_0_fails_in_the_floors:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 21, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0]))) == 1 : U32}

law vorbis_maps_floor_of_type_2:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 50, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0, 64, 41, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_floor_with_two_points_at_one_place:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 55, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 16, 32, 4, 64, 51, 0, 0, 0, 0, 0, 0, 4, 0, 192, 0, 0, 0, 0, 0, 0, 0, 0, 148, 2, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_residue_that_ends_before_it_begins:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 32, 1, 0, 0, 1, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_residue_fails_in_the_residues:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 32, 1, 0, 0, 1, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == 2 : U32}

law vorbis_maps_residue_of_type_3:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 96, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_mapping_coupling_a_channel_with_itself:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 53, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 64, 128, 41, 5, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_mapping_fails_in_the_mappings:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 53, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 64, 128, 41, 5, 0, 0, 0, 0, 0, 0, 0, 0]))) == 3 : U32}

law vorbis_maps_mapping_of_16_submaps_is_refused:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 98, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 224, 227, 161, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Refused{2} : VS.Status}

law vorbis_maps_mapping_of_15_submaps:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 95, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 160, 195, 161, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Going{} : VS.Status}

law vorbis_maps_mapping_that_fails_before_its_sixteenth_submap:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 98, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 224, 235, 161, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 160, 20, 0, 0, 0, 0, 0, 0, 0, 0]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_mode_of_another_mapping:
  {VM.Maps.status(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 1]))) == VS.Failed{20} : VS.Status}

law vorbis_maps_mode_fails_in_the_modes:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 51, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 32, 0, 0, 0, 0, 0, 0, 2, 0, 96, 0, 0, 0, 0, 0, 0, 0, 0, 74, 1, 0, 0, 0, 0, 0, 0, 1]))) == 4 : U32}

law vorbis_maps_setup_that_failed_is_not_read_on:
  {VM.Maps.stage(VM.maps.read(VS.setup.codebooks(Nil{}))) == 0 : U32}

# The Vorbis transform's tables (src/vorbis_tables.bend): the bit reversal,
# the ints and angles as doubles (exact products and quotients of M_PI),
# and the two-unit margin by which a float is sure under any library.

law vorbis_tables_bit_reversal_of_64:
  {VT.bitreverse(64) == [0, 16, 8, 24, 4, 20, 12, 28] : +List<U32>}

law vorbis_tables_bit_reversal_ends_of_8192:
  {VT.reverse.each(2n, 22, 1023, Nil{}) == [4092, 0] : +List<U32>}

law vorbis_tables_zero_as_a_double:
  {VT.whole(0) == M.Float64{0, 0} : M.Float64}

law vorbis_tables_one_as_a_double:
  {VT.whole(1) == M.Float64{1072693248, 0} : M.Float64}

law vorbis_tables_64_as_a_double:
  {VT.whole(64) == M.Float64{1078984704, 0} : M.Float64}

law vorbis_tables_8191_as_a_double:
  {VT.whole(8191) == M.Float64{1086324480, 0} : M.Float64}

law vorbis_tables_five_128ths:
  {VT.halved(VT.whole(5), 7) == M.Float64{1067712512, 0} : M.Float64}

law vorbis_tables_two_units_further:
  {VT.further(M.Float64{1, 4294967295}) == M.Float64{2, 1} : M.Float64}

law vorbis_tables_two_units_nearer:
  {VT.nearer(M.Float64{2, 1}) == M.Float64{1, 4294967295} : M.Float64}

law vorbis_tables_nearer_then_further:
  {VT.further(VT.nearer(M.Float64{1072652951, 3489094832})) == M.Float64{1072652951, 3489094832} : M.Float64}

law vorbis_tables_negative_zero_is_zero:
  {VT.zero(M.Float64{2147483648, 0}) == True{} : Bool}

law vorbis_tables_smallest_double_is_not_zero:
  {VT.zero(M.Float64{0, 1}) == False{} : Bool}

law vorbis_tables_glibc_values_are_the_library_s:
  {VT.library.own(M.Glibc239Libm{}) == True{} : Bool}

law vorbis_tables_other_profiles_take_sure_values:
  {(VT.library.own(M.AppleLibm{}) || VT.library.own(M.Glibc241Libm{})) == False{} : Bool}

# Rows read and written by index (src/store.bend), and the decoding of a
# codebook's symbols from a packet's bits (src/vorbis_decode.bend,
# prep_huffman in src/vorbis_ogg.bend): the search of the sorted table and
# of the symbols, the symbols of a packet, the refusal of DECODE on a
# sparse codebook without a code, a vector asked of a codebook without a
# lookup (stb_vorbis's error 21).

law store_index_of_one_value:
  {St.Index.list(St.Index.new(2, 7)) == [7, 7, 7, 7] : +List<U32>}

law store_index_write_then_read:
  {St.Index.get(St.Index.set(St.Index.new(3, 0), 5, 9), 5) == 9 : U32}

law store_index_write_leaves_the_other_places:
  {St.Index.list(St.Index.set(St.Index.new(2, 1), 2, 9)) == [1, 1, 9, 1] : +List<U32>}

law store_index_from_a_list:
  {St.Index.list(St.Index.from([1, 2, 3], 9)) == [1, 2, 3, 9] : +List<U32>}

law store_index_from_no_value:
  {St.Index.list(St.Index.from(Nil{}, 4)) == [4] : +List<U32>}

law store_index_of_one_place:
  {St.Index.get(St.Index.set(St.Index.new(0, 3), 0, 8), 0) == 8 : U32}

law store_depth_for_a_count:
  {((St.depth.for(32n, 5, 0) * 10000) + (St.depth.for(32n, 1024, 0) * 100) + St.depth.for(32n, 1025, 0) : U32) == 31011 : U32}

law store_depth_for_one_or_none:
  {(St.depth.for(32n, 1, 0) + St.depth.for(32n, 0, 0) : U32) == 0 : U32}

law vorbis_decode_bits_ran_out_are_fewer_than_any:
  {VD.short(4294967295, 0) == True{} : Bool}

law vorbis_decode_bits_fewer_than_a_code:
  {VD.short(5, 6) == True{} : Bool}

law vorbis_decode_bits_enough_for_a_code:
  {VD.short(6, 6) == False{} : Bool}

law vorbis_decode_search_finds_the_codeword:
  {VD.search(32n, St.Index.from([0, 1073741824, 2147483648, 4294967295], 4294967295), 1073741824, 0, 3) == 1 : U32}

law vorbis_decode_search_takes_the_last_not_above:
  {VD.search(32n, St.Index.from([0, 1073741824, 2147483648, 4294967295], 4294967295), 2147483647, 0, 3) == 1 : U32}

law vorbis_decode_search_of_the_highest_code:
  {VD.search(32n, St.Index.from([0, 1073741824, 2147483648, 4294967295], 4294967295), 4294967295, 0, 3) == 2 : U32}

law vorbis_decode_search_of_one_codeword:
  {VD.search(32n, St.Index.from([0, 4294967295], 4294967295), 4294967295, 0, 1) == 0 : U32}

law vorbis_decode_linear_finds_the_first_code_the_bits_begin_with:
  {VD.linear([1, 2, 2], [0, 1, 3], 0, 1, 8, 0, 0, 0) == VD.Hit{1, 1, 2} : VD.Hit}

law vorbis_decode_linear_of_a_one_bit_code:
  {VD.linear([1, 2, 2], [0, 1, 3], 0, 2, 8, 0, 0, 0) == VD.Hit{1, 0, 1} : VD.Hit}

law vorbis_decode_linear_without_bits_enough:
  {VD.linear([1, 2, 2], [0, 1, 3], 0, 3, 1, 0, 0, 0) == VD.Hit{2, 2, 2} : VD.Hit}

law vorbis_decode_linear_passes_symbols_without_a_code:
  {VD.linear([255, 1], [0, 0], 0, 0, 8, 0, 0, 0) == VD.Hit{1, 1, 1} : VD.Hit}

law vorbis_decode_linear_of_no_code:
  {VD.linear([2, 2], [0, 1], 0, 3, 8, 0, 0, 0) == VD.Hit{0, 0, 0} : VD.Hit}

law vorbis_decode_small_codebook_is_searched_by_symbol:
  {VD.raw.kind(VD.coder.of(VS.Codebook{1, 2, V.Book{False{}, 2, [1, 1], [0, 1], 0, [4294967295], Nil{}, Nil{}}, 0, 0.0, 0.0, 0, False{}, 0, Nil{}})) == 2 : U32}

law vorbis_decode_codebook_of_no_entry_is_searched_by_symbol:
  {VD.raw.kind(VD.coder.none()) == 2 : U32}

law vorbis_decode_first_symbol_of_a_packet:
  {Ogg.Reader.value(VD.decode.symbol(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])))))) == 0 : U32}

law vorbis_decode_second_symbol_of_a_packet:
  {Ogg.Reader.value(VD.decode.symbol(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 0), VD.decode.symbol(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2]))))))) == 1 : U32}

law vorbis_decode_symbol_uses_its_bits:
  {Ogg.Packet.valid(Ogg.Reader.packet(VD.decode.symbol(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2]))))))) == 7 : U32}

law vorbis_decode_raw_of_a_codebook_without_a_code:
  {Ogg.Reader.value(VD.decode.raw(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 1), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])))))) == 4294967295 : U32}

law vorbis_decode_symbol_of_a_sparse_codebook_without_a_code_is_refused:
  {Ogg.Reader.error(VD.decode.symbol(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 1), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])))))) == 1001 : U32}

law vorbis_decode_vector_of_a_codebook_without_a_lookup:
  {Ogg.Reader.error(VD.vector.start(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])))))) == 21 : U32}

law vorbis_decode_prep_takes_the_packet_s_byte:
  {((Ogg.Packet.valid(Ogg.Reader.packet(Ogg.huffman.prep(Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2]))))))) * 1000) + Ogg.Packet.acc(Ogg.Reader.packet(Ogg.huffman.prep(Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2]))))))) : U32) == 8002 : U32}

law vorbis_decode_prep_twice_is_prep_once:
  {Ogg.Packet.valid(Ogg.Reader.packet(Ogg.huffman.prep(Ogg.huffman.prep(Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 61, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 1, 66, 67, 86, 1, 0, 2, 0, 0, 0, 0, 66, 67, 86, 1, 0, 4, 0, 0, 2, 0, 0, 0, 64, 0, 0, 128, 0, 0, 0, 0, 0, 0, 8, 0, 128, 1, 0, 0, 0, 0, 0, 0, 0, 40, 5, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2])))))))) == 8 : U32}

# The inverse MDCT's loops take their butterflies four at a time
# (src/vorbis_mdct.bend); rows of floats (src/store.bend).

law vorbis_mdct_butterflies_come_in_fours:
  {VX.fours(7) == 4n : Nat}

law vorbis_mdct_block_of_64_has_no_butterfly_of_two:
  {VX.fours(2) == 0n : Nat}

law vorbis_mdct_fours_of_a_multiple_of_four:
  {VX.fours(64) == 64n : Nat}

law store_row_write_then_read:
  {St.Row.get(St.Row.set(St.Row.new(2, 0.0), 3, 2.5), 3) == 2.5 : F32}

law store_row_write_leaves_the_other_places:
  {St.Row.list(St.Row.set(St.Row.new(1, 0.5), 1, 2.5)) == [0.5, 2.5] : +List<F32>}

law store_row_from_a_list:
  {St.Row.list(St.Row.from([1.5, 2.5, 3.5])) == [1.5, 2.5, 3.5, 0.0] : +List<F32>}

# Vorbis residues (src/vorbis_residue.bend): a class's digits, the
# codebook of a class in a pass, and the vectors woven over the channels:
# how many values of a vector are used at the end of the floats (stb_vorbis
# adds the channel it is at instead of taking it away), and the refusal of
# values read past the codebook's.

law vorbis_residue_above_as_ints:
  {VR.above(1, 0) == True{} : Bool}

law vorbis_residue_minus_one_is_not_above_zero:
  {VR.above(4294967295, 0) == False{} : Bool}

law vorbis_residue_zero_is_above_minus_one:
  {VR.above(0, 4294967295) == True{} : Bool}

law vorbis_residue_class_digits_highest_first:
  {((VR.digit(5, 3, 2, 0) * 10) + VR.digit(5, 3, 2, 1) : U32) == 12 : U32}

law vorbis_residue_class_digits_in_base_two:
  {((((VR.digit(7, 2, 4, 0) * 1000) + (VR.digit(7, 2, 4, 1) * 100)) + (VR.digit(7, 2, 4, 2) * 10)) + VR.digit(7, 2, 4, 3) : U32) == 111 : U32}

law vorbis_residue_class_digits_of_one_classification:
  {(VR.digit(9, 1, 3, 0) + VR.digit(9, 1, 3, 2) : U32) == 0 : U32}

law vorbis_residue_class_digits_past_the_number:
  {VR.digit(5, 3, 60000, 7) == 0 : U32}

law vorbis_residue_codebook_of_a_class_in_a_pass:
  {((VR.book.of([[4294967295, 3], [7]], 0, 1) * 10) + VR.book.of([[4294967295, 3], [7]], 1, 0) : U32) == 37 : U32}

law vorbis_residue_class_without_a_codebook_in_a_pass:
  {VR.book.of([[4294967295, 3], [7]], 0, 0) == 4294967295 : U32}

law vorbis_residue_channel_decoded:
  {VR.live(5, 2) == True{} : Bool}

law vorbis_residue_channel_not_decoded:
  {VR.live(5, 1) == False{} : Bool}

law vorbis_residue_vector_inside_the_floats_is_whole:
  {VR.weave.room(4, 0, 8, 2, 10) == 4 : U32}

law vorbis_residue_vector_at_the_end_of_the_floats_is_cut:
  {VR.weave.room(4, 0, 9, 2, 10) == 2 : U32}

law vorbis_residue_cut_adds_the_channel_twice:
  {VR.weave.room(4, 1, 9, 2, 10) == 3 : U32}

law vorbis_residue_vector_past_the_floats_has_no_room:
  {VR.above(VR.weave.room(4, 0, 12, 2, 10), 0) == False{} : Bool}

law store_row_first_places_cleared:
  {St.Row.list(St.Row.cleared(St.Row.from([1.5, 2.5, 3.5, 4.5]), 2)) == [0.0, 0.0, 3.5, 4.5] : +List<F32>}

law store_row_one_place_cleared:
  {St.Row.list(St.Row.cleared(St.Row.from([1.5, 2.5, 3.5, 4.5]), 1)) == [0.0, 2.5, 3.5, 4.5] : +List<F32>}

law store_row_all_places_cleared:
  {St.Row.list(St.Row.cleared(St.Row.from([1.5, 2.5, 3.5, 4.5]), 4)) == [0.0, 0.0, 0.0, 0.0] : +List<F32>}

law vorbis_decode_codebook_of_no_entry_has_no_value:
  {VD.Coder.count(VD.coder.none()) == 0 : U32}

law vorbis_decode_single_symbol_has_its_dimensions_of_values:
  {VD.Coder.count(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])), Nil{}), 0)) == 4 : U32}

law vorbis_residue_vectors_woven_from_the_first_channel:
  {VR.Woven.fine(VR.weave.decode(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])))), [St.Row.new(4, 0.0), St.Row.new(4, 0.0), St.Row.new(4, 0.0)], 7, 3, 0, 0, 10, 4)) == True{} : Bool}

law vorbis_residue_vector_read_past_the_codebook_s_values_is_refused:
  {Ogg.Reader.error(VR.Woven.reader(VR.weave.decode(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])))), [St.Row.new(4, 0.0), St.Row.new(4, 0.0), St.Row.new(4, 0.0)], 7, 3, 2, 9, 10, 4))) == 1001 : U32}

law vorbis_residue_no_value_to_decode_is_fine:
  {VR.Woven.fine(VR.weave.decode(VD.coder.at(VD.coders.of(VS.Setup.books(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])), Nil{}), 0), Ogg.packet.maybe(VM.Maps.reader(VM.maps.read(VS.setup.codebooks([79, 103, 103, 83, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 30, 1, 118, 111, 114, 98, 105, 115, 0, 0, 0, 0, 2, 68, 172, 0, 0, 0, 0, 0, 0, 0, 244, 1, 0, 0, 0, 0, 0, 184, 1, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 17, 60, 3, 118, 111, 114, 98, 105, 115, 1, 0, 0, 0, 118, 0, 0, 0, 0, 1, 5, 118, 111, 114, 98, 105, 115, 0, 66, 67, 86, 4, 0, 1, 0, 0, 128, 8, 0, 0, 19, 11, 0, 0, 20, 19, 5, 0, 0, 128, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 80, 10, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0])))), [St.Row.new(4, 0.0), St.Row.new(4, 0.0), St.Row.new(4, 0.0)], 7, 3, 2, 9, 10, 0)) == True{} : Bool}

# A Vorbis floor's curve (src/vorbis_floor.bend, src/vorbis_db.bend): the
# table of 256 values, a line's slope as C divides ints, and the level end
# of a curve, which stb_vorbis reads from the table without a modulo:
# past it, the port refuses.

law vorbis_floor_table_has_256_values:
  {St.count.words(VDb.table(), 0) == 256 : U32}

law vorbis_floor_table_begins_at_its_least_value:
  {VF.head(VDb.table()) == 870626366 : U32}

law vorbis_floor_table_ends_at_one:
  {VF.nth(VDb.table(), 255) == 1065353216 : U32}

law vorbis_floor_negative_int:
  {VF.negative(4294967295) == True{} : Bool}

law vorbis_floor_positive_int:
  {VF.negative(2147483647) == False{} : Bool}

law vorbis_floor_magnitude_of_a_negative_int:
  {VF.magnitude(4294967291) == 5 : U32}

law vorbis_floor_slope_is_cut_toward_zero:
  {VF.slope(10, 3) == 3 : U32}

law vorbis_floor_negative_slope_is_cut_toward_zero:
  {VF.slope(4294967286, 3) == 4294967293 : U32}

law vorbis_floor_level_line_has_no_slope:
  {VF.slope(0, 7) == 0 : U32}

law vorbis_floor_level_end_inside_the_table:
  {VF.past.table(64, 255, 128) == False{} : Bool}

law vorbis_floor_level_end_past_the_table_is_refused:
  {VF.past.table(64, 256, 128) == True{} : Bool}

law vorbis_floor_negative_level_end_is_refused:
  {VF.past.table(0, 4294967295, 128) == True{} : Bool}

law vorbis_floor_no_level_end_at_the_block_s_end:
  {VF.past.table(128, 9999, 128) == False{} : Bool}

# A Vorbis audio packet (src/vorbis_packet.bend): the floors' int16 values
# and the point a line predicts, the channels a coupling brings back, and
# where a block is placed: the first one a half block before zero, the
# samples to drop, a page's position, and the last page's cut.

law vorbis_packet_int16_of_minus_one:
  {VK.s16(65535) == 4294967295 : U32}

law vorbis_packet_int16_of_the_largest:
  {VK.s16(32767) == 32767 : U32}

law vorbis_packet_int16_cuts_the_high_bits:
  {VK.s16(65541) == 5 : U32}

law vorbis_packet_int16_of_32768_is_negative:
  {VK.s16(32768) == 4294934528 : U32}

law vorbis_packet_minus_one_is_under_zero:
  {VK.under(4294967295, 0) == True{} : Bool}

law vorbis_packet_zero_is_not_under_minus_one:
  {VK.under(0, 4294967295) == False{} : Bool}

law vorbis_packet_half_of_a_negative_int_keeps_its_sign:
  {VK.halved(4294967293) == 4294967294 : U32}

law vorbis_packet_half_of_an_int:
  {VK.halved(7) == 3 : U32}

law vorbis_packet_predicted_point_on_a_rising_line:
  {VK.predict(5, 0, 10, 20, 40) == 30 : U32}

law vorbis_packet_predicted_point_on_a_falling_line:
  {VK.predict(5, 0, 10, 40, 20) == 30 : U32}

law vorbis_packet_predicted_point_is_cut_toward_the_first:
  {((VK.predict(1, 0, 3, 0, 1) * 10) + VK.predict(2, 0, 3, 10, 0) : U32) == 4 : U32}

law vorbis_packet_class_value_shifts_down:
  {VK.shifted(13, 2) == 3 : U32}

law vorbis_packet_no_class_value_stays_none:
  {VK.shifted(4294967295, 2) == 4294967295 : U32}

law vorbis_packet_floor_ranges:
  {((((VK.range.of(1) * 1000000) + (VK.range.of(2) * 10000)) + (VK.range.of(3) * 100)) + VK.range.of(4) : U32) == 257288664 : U32}

law vorbis_packet_coupled_channels_without_floors_stay_out:
  {VK.coupled.zeros([0], [1], 3) == 3 : U32}

law vorbis_packet_coupled_channel_with_a_floor_brings_the_other:
  {VK.coupled.zeros([0], [1], 2) == 0 : U32}

law vorbis_packet_coupled_pairs_bring_each_other_in_turn:
  {VK.coupled.zeros([0, 1], [1, 2], 6) == 0 : U32}

law vorbis_packet_coupled_pairs_do_not_reach_back:
  {VK.coupled.zeros([1, 0], [2, 1], 6) == 4 : U32}

law vorbis_packet_first_block_is_placed_a_half_block_before_zero:
  {VK.placed.of(True{}, False{}, False{}, 0, 0, False{}, 0, 512, 0, 256, 512) == VK.Placed{0, True{}, 0, 512, 0} : VK.Placed}

law vorbis_packet_long_first_block_leaves_samples_to_drop:
  {VK.placed.of(True{}, False{}, False{}, 0, 0, False{}, 0, 1024, 192, 704, 832) == VK.Placed{0, True{}, 192, 832, 192} : VK.Placed}

law vorbis_packet_samples_to_drop_move_the_left_part_up:
  {VK.placed.of(False{}, False{}, False{}, 0, 1000, True{}, 100, 512, 0, 256, 512) == VK.Placed{1156, True{}, 0, 512, 100} : VK.Placed}

law vorbis_packet_samples_to_drop_past_the_block_s_left_part:
  {VK.placed.of(False{}, False{}, False{}, 0, 1000, True{}, 300, 512, 0, 256, 512) == VK.Placed{1000, True{}, 44, 512, 256} : VK.Placed}

law vorbis_packet_block_without_a_position_is_a_window_further:
  {VK.placed.of(False{}, False{}, False{}, 0, 1000, True{}, 0, 512, 0, 256, 512) == VK.Placed{1256, True{}, 0, 512, 0} : VK.Placed}

law vorbis_packet_unknown_position_stays_unknown:
  {VK.placed.of(False{}, False{}, False{}, 0, 7, False{}, 0, 512, 0, 256, 512) == VK.Placed{7, False{}, 0, 512, 0} : VK.Placed}

law vorbis_packet_page_position_places_the_block:
  {VK.placed.of(False{}, True{}, False{}, 5000, 1000, False{}, 0, 512, 0, 256, 512) == VK.Placed{5000, True{}, 0, 512, 0} : VK.Placed}

law vorbis_packet_last_page_cuts_the_block_short:
  {VK.placed.of(False{}, True{}, True{}, 1100, 1000, True{}, 0, 512, 0, 256, 512) == VK.Placed{1100, True{}, 0, 100, 0} : VK.Placed}

law vorbis_packet_last_page_before_the_block_gives_none:
  {VK.placed.of(False{}, True{}, True{}, 900, 1000, True{}, 0, 512, 0, 256, 512) == VK.Placed{1000, True{}, 0, 0, 0} : VK.Placed}

law vorbis_packet_last_page_past_the_block_does_not_cut_it:
  {VK.placed.of(False{}, True{}, True{}, 9000, 1000, True{}, 0, 512, 0, 256, 512) == VK.Placed{9000, True{}, 0, 512, 0} : VK.Placed}

law vorbis_packet_no_data_is_no_decoder:
  {VK.open(M.Glibc239Libm{}, Nil{}) == VK.Closed{VS.Failed{30}} : VK.Decoder}

# After a refusal (the reader's error 1001) a call decodes nothing and
# leaves the reader, the floats and the position as they are.
law vorbis_packet_refused_reader_decodes_nothing:
  {VK.packet.decode(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VK.State{Ogg.undefined(Ogg.open([1, 2, 3])), Nil{}, 7, True{}, 3}) == VK.Packet{VK.State{Ogg.undefined(Ogg.open([1, 2, 3])), Nil{}, 7, True{}, 3}, False{}, 0, 0, 0} : VK.Packet}

# Vorbis frames and samples (src/vorbis_frame.bend): a float's short by the
# bits of its sum with 384 (the steps of 1/32768, a short's range, the sums
# whose conversion overflows an int), a NaN by its bits, the window of a
# previous length, what a frame gives, and reads that read nothing.

law vorbis_frame_short_of_no_step_is_zero:
  {VFr.short.clamped(1136656384) == 0 : U32}

law vorbis_frame_short_counts_the_steps_up:
  {VFr.short.clamped(1136656385) == 1 : U32}

law vorbis_frame_short_counts_the_steps_down:
  {VFr.short.clamped(1136656383) == 65535 : U32}

law vorbis_frame_short_reaches_its_largest:
  {VFr.short.clamped(1136689151) == 32767 : U32}

law vorbis_frame_short_stops_at_its_largest:
  {VFr.short.clamped(1136689152) == 32767 : U32}

law vorbis_frame_short_reaches_its_least:
  {VFr.short.clamped(1136623616) == 32768 : U32}

law vorbis_frame_short_stops_at_its_least:
  {VFr.short.clamped(1136623615) == 32768 : U32}

law vorbis_frame_short_of_infinity_is_the_largest:
  {VFr.short.clamped(2139095040) == 32767 : U32}

law vorbis_frame_short_of_minus_infinity_is_the_least:
  {VFr.short.clamped(4286578688) == 32768 : U32}

law vorbis_frame_short_of_a_sum_of_zero_is_the_least:
  {VFr.short.clamped(0) == 32768 : U32}

law vorbis_frame_short_of_a_sum_of_minus_384_is_the_least:
  {VFr.short.clamped(3284140032) == 32768 : U32}

law vorbis_frame_sum_just_above_minus_384_is_undefined:
  {VFr.short.undefined(3284140031) == True{} : Bool}

law vorbis_frame_sum_of_minus_384_is_defined:
  {VFr.short.undefined(3284140032) == False{} : Bool}

law vorbis_frame_sum_just_below_zero_is_undefined:
  {VFr.short.undefined(2147483649) == True{} : Bool}

law vorbis_frame_largest_positive_sum_is_defined:
  {VFr.short.undefined(2147483647) == False{} : Bool}

law vorbis_frame_nan_by_its_bits:
  {VFr.nan(2139095041) == True{} : Bool}

law vorbis_frame_negative_nan_by_its_bits:
  {VFr.nan(4290772992) == True{} : Bool}

law vorbis_frame_infinity_is_no_nan:
  {VFr.nan(2139095040) == False{} : Bool}

law vorbis_frame_minus_infinity_is_no_nan:
  {VFr.nan(4286578688) == False{} : Bool}

law vorbis_frame_half_a_block_has_its_window:
  {VFr.window.for(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, 32) == Some{St.Row.new(0, 0.0)} : Maybe<St.Row>}

law vorbis_frame_other_lengths_have_no_window:
  {VFr.window.for(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, 16) == None{} : Maybe<St.Row>}

law vorbis_frame_length_below_zero_has_no_window:
  {VFr.window.for(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, 4294967264) == None{} : Maybe<St.Row>}

law vorbis_frame_first_frame_gives_no_sample:
  {VFr.finish(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 0, 0, 0, 9}, 64, 0, 32) == VFr.Got{VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 0} : VFr.Got}

law vorbis_frame_frame_gives_its_left_part:
  {VFr.finish(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 64, 0, 32) == VFr.Got{VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 41}, 32} : VFr.Got}

law vorbis_frame_cut_block_gives_what_it_has:
  {VFr.finish(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 20, 0, 32) == VFr.Got{VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 4294967284, 0, 0, 29}, 20} : VFr.Got}

law vorbis_frame_no_window_gives_nothing_and_changes_nothing:
  {VFr.finish(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 5, 0, 0, 9}, 64, 0, 32) == VFr.Got{VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 5, 0, 0, 9}, 0} : VFr.Got}

law vorbis_frame_refused_decoder_reads_nothing:
  {VFr.samples.read(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.undefined(Ogg.open([1, 2, 3])), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 100) == VFr.Read{VFr.Frames{VK.State{Ogg.undefined(Ogg.open([1, 2, 3])), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 0, Nil{}, False{}} : VFr.Read}

law vorbis_frame_fewer_shorts_than_channels_read_nothing:
  {VFr.samples.read(VK.Plan{2, 64, 64, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, VX.Factors{St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Row.new(0, 0.0), St.Index.new(0, 0)}, St.Row.new(0, 0.0)}, VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 1) == VFr.Read{VFr.Frames{VK.State{Ogg.open([1, 2, 3]), Nil{}, 7, True{}, 3}, Nil{}, 32, 0, 0, 9}, 0, Nil{}, False{}} : VFr.Read}

law vorbis_frame_audio_begins_where_the_reader_is_between_pages:
  {VFr.first.audio(Ogg.Reader{Ogg.Stream{[9], [9], 7, 1, False{}}, Ogg.Page{0, 0, Nil{}, 4294967295, 0, 0, 0}, Ogg.First{False{}, 0, 0, 0}, Ogg.Packet{0, False{}, 0, 0, 0, 0}, 0, Nil{}, 0}) == 7 : U32}

law vorbis_frame_audio_inside_a_page_has_no_first_page:
  {VFr.first.audio(Ogg.skip(Ogg.open([1, 2, 3]), 2)) == 0 : U32}

law vorbis_frame_no_data_is_no_decoder:
  {VFr.memory.open(M.Glibc239Libm{}, Nil{}) == VFr.Unready{VS.Failed{30}} : VFr.Started}

# A Vorbis stream's length (src/vorbis_length.bend) and the reader's
# set_file_offset: the pages' checksum, a page found by it (and not found
# cut, changed, or in the data's first bytes), and the last page's position
# as the length: kept, not known, past 32 bits.

law vorbis_ogg_offset_inside_the_data:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.offset.set(Ogg.open([1, 2, 3]), 2))) == 2 : U32}

law vorbis_ogg_offset_inside_the_data_reads_from_there:
  {Ogg.Reader.value(Ogg.get8(Ogg.offset.set(Ogg.open([1, 2, 3]), 2))) == 3 : U32}

law vorbis_ogg_offset_inside_the_data_answers_one:
  {Ogg.Reader.value(Ogg.offset.set(Ogg.open([1, 2, 3]), 2)) == 1 : U32}

law vorbis_ogg_offset_at_the_data_s_end_is_its_end:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.offset.set(Ogg.open([1, 2, 3]), 3))) == True{} : Bool}

law vorbis_ogg_offset_past_the_data_is_its_end:
  {Ogg.Stream.at(Ogg.Reader.stream(Ogg.offset.set(Ogg.open([1, 2, 3]), 4000000000))) == 3 : U32}

law vorbis_ogg_offset_past_the_data_answers_zero:
  {Ogg.Reader.value(Ogg.offset.set(Ogg.open([1, 2, 3]), 9)) == 0 : U32}

law vorbis_ogg_offset_in_no_data_is_its_end:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.offset.set(Ogg.get8(Ogg.open(Nil{})), 0))) == True{} : Bool}

law vorbis_ogg_offset_inside_clears_the_end_of_data:
  {Ogg.Stream.eof(Ogg.Reader.stream(Ogg.offset.set(Ogg.get8(Ogg.get8(Ogg.open([7]))), 0))) == False{} : Bool}

law vorbis_length_crc_table_entry_of_one_is_the_polynomial:
  {VL.crc.entry(8n, 16777216) == 79764919 : U32}

law vorbis_length_crc_of_a_one:
  {VL.crc.update(VL.crc.table(), 0, 1) == 79764919 : U32}

law vorbis_length_crc_of_the_capture_pattern:
  {VL.crc.each([79, 103, 103, 83], VL.crc.table(), 0) == 1605413199 : U32}

law vorbis_length_crc_shifts_a_byte_through:
  {VL.crc.each([1, 0], VL.crc.table(), 0) == 3524903388 : U32}

law vorbis_length_crc_of_zeros_is_zero:
  {VL.crc.zeros(5n, VL.crc.table(), 0) == 0 : U32}

law vorbis_length_capture_pattern_is_there:
  {VL.capture.kind([103, 103, 83], [103, 103, 83, 0]) == 0 : U32}

law vorbis_length_capture_pattern_is_another_byte:
  {VL.capture.kind([103, 103, 83], [103, 104]) == 1 : U32}

law vorbis_length_capture_pattern_at_the_data_s_end:
  {VL.capture.kind([103, 103, 83], [103, 103]) == 2 : U32}

law vorbis_length_page_is_found_by_its_checksum:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0], 0, 57, VL.crc.table()) == VL.Found{True{}, 30, 57, True{}} : VL.Found}

law vorbis_length_page_with_a_body_is_found:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 52, 18, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 3, 0, 0, 0, 213, 121, 154, 17, 1, 2, 7, 8], 0, 60, VL.crc.table()) == VL.Found{True{}, 30, 60, False{}} : VL.Found}

law vorbis_length_page_with_another_body_is_none:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 52, 18, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 3, 0, 0, 0, 213, 121, 154, 17, 1, 2, 7, 9], 0, 60, VL.crc.table()) == VL.Found{False{}, 0, 0, False{}} : VL.Found}

law vorbis_length_page_cut_in_its_body_is_none:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 0, 52, 18, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 3, 0, 0, 0, 213, 121, 154, 17, 1, 2, 7], 0, 59, VL.crc.table()) == VL.Found{False{}, 0, 0, False{}} : VL.Found}

law vorbis_length_page_of_empty_segments_cut_short_is_found:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 5, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 62, 178, 110, 13, 3, 0, 0], 0, 59, VL.crc.table()) == VL.Found{True{}, 30, 59, True{}} : VL.Found}

law vorbis_length_page_in_the_first_bytes_is_none:
  {VL.page.find([79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0], 0, 27, VL.crc.table()) == VL.Found{False{}, 0, 0, False{}} : VL.Found}

law vorbis_length_search_from_the_data_s_end_finds_none:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0], 57, 57, VL.crc.table()) == VL.Found{False{}, 0, 0, False{}} : VL.Found}

law vorbis_length_search_after_a_page_s_start_finds_none:
  {VL.page.find([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0], 31, 57, VL.crc.table()) == VL.Found{False{}, 0, 0, False{}} : VL.Found}

law vorbis_length_is_the_last_page_s_position:
  {VL.Length.value(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0]), 0, 0)) == 77 : U32}

law vorbis_length_is_kept:
  {VL.Length.total(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0]), 0, 0)) == 77 : U32}

law vorbis_length_leaves_the_reader_where_it_was:
  {Ogg.Stream.at(Ogg.Reader.stream(VL.Length.reader(VL.length.samples(Ogg.skip(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0]), 5), 0, 0)))) == 5 : U32}

law vorbis_length_position_of_all_ones_is_not_known:
  {VL.Length.total(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 255, 255, 255, 255, 255, 255, 255, 255, 29, 0, 0, 0, 9, 0, 0, 0, 253, 42, 94, 231, 0]), 0, 0)) == 4294967295 : U32}

law vorbis_length_not_known_answers_zero:
  {VL.Length.value(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 255, 255, 255, 255, 255, 255, 255, 255, 29, 0, 0, 0, 9, 0, 0, 0, 253, 42, 94, 231, 0]), 0, 0)) == 0 : U32}

law vorbis_length_not_known_is_an_error:
  {Ogg.Reader.error(VL.Length.reader(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 255, 255, 255, 255, 255, 255, 255, 255, 29, 0, 0, 0, 9, 0, 0, 0, 253, 42, 94, 231, 0]), 0, 0))) == 36 : U32}

law vorbis_length_position_past_32_bits_is_the_most:
  {VL.Length.value(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 7, 0, 0, 0, 5, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 79, 80, 66, 146, 0]), 0, 0)) == 4294967294 : U32}

law vorbis_length_search_begins_where_the_audio_does:
  {VL.Length.total(VL.length.samples(Ogg.open([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 103, 103, 83, 0, 4, 77, 0, 0, 0, 0, 0, 0, 0, 29, 0, 0, 0, 9, 0, 0, 0, 188, 39, 167, 220, 0]), 31, 0)) == 4294967295 : U32}

law vorbis_length_kept_is_not_searched_for_again:
  {VL.Length.value(VL.length.samples(Ogg.open(Nil{}), 0, 500)) == 500 : U32}

law vorbis_length_kept_as_not_known_answers_zero:
  {VL.Length.value(VL.length.samples(Ogg.open(Nil{}), 0, 4294967295)) == 0 : U32}

law vorbis_length_of_no_data_is_not_known:
  {Ogg.Reader.error(VL.Length.reader(VL.length.samples(Ogg.open(Nil{}), 0, 0))) == 36 : U32}

# Waves from Ogg Vorbis data (Wave.decode_for): data stb_vorbis does not
# open, setups that are refused or past the port's limits, the count of
# shorts LoadWave asks for, and a wave only where every short was written.

law wave_ogg_of_no_data_is_no_wave:
  {J.Wave.decode_for(M.Glibc239Libm{}, ".ogg", Nil{}) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_token_in_capitals_is_the_same:
  {J.Wave.decode_for(M.Glibc239Libm{}, ".OGG", [1, 2, 3]) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_under_the_default_profile:
  {J.Wave.decode(".ogg", Nil{}) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_other_tokens_stay_unsupported:
  {J.Wave.decode_for(M.Glibc239Libm{}, ".oga", Nil{}) == Fail{J.UnsupportedWaveFormat{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_setup_stb_vorbis_fails_on_is_invalid:
  {J.Wave.ogg.unready(VS.Failed{20}) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_setup_c_leaves_undefined_is_invalid:
  {J.Wave.ogg.unready(VS.Refused{1}) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_setup_past_the_port_s_limits_is_unsupported:
  {J.Wave.ogg.unready(VS.Refused{3}) == Fail{J.UnsupportedWaveFormat{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_tables_the_profile_does_not_give_are_unsupported:
  {J.Wave.ogg.unready(VS.Refused{5}) == Fail{J.UnsupportedWaveFormat{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_shorts_are_frames_times_channels:
  {J.Wave.ogg.shorts(44100, 2) == 88200 : U32}

law wave_ogg_shorts_past_an_int_read_nothing:
  {J.Wave.ogg.shorts(1610612736, 2) == 0 : U32}

law wave_ogg_shorts_wrap_as_the_unsigned_product_does:
  {J.Wave.ogg.shorts(2147483649, 2) == 2 : U32}

law wave_ogg_every_short_written_is_a_wave:
  {J.Wave.ogg.whole(True{}, 2, 8000, 1, 2, [5, 65535]) == Done{J.Wave{2, 8000, 16, 1, [5, 65535]}} : Result<&1, &1, J.Wave.Error, J.Wave>}

law wave_ogg_shorts_never_written_are_no_wave:
  {J.Wave.ogg.whole(False{}, 2, 8000, 1, 1, [5]) == Fail{J.InvalidWaveData{}} : Result<&1, &1, J.Wave.Error, J.Wave>}

# An XM module read from its file (src/xm_module.bend): the data's bytes
# and offsets, sizes in jar_xm's block of memory, a sample's loop, packed
# slots (and those refused), the pattern order's check, and data that is no
# module.

law xm_module_byte_past_the_data_is_zero:
  {Xm.u8(St.Index.from([7, 8], 0), 2, 2) == 0 : U32}

law xm_module_bytes_are_read_the_lowest_first:
  {Xm.u32(St.Index.from([1, 2, 3, 4], 0), 4, 0) == 67305985 : U32}

law xm_module_word_cut_by_the_data_s_end:
  {Xm.u32(St.Index.from([1, 2, 3, 4], 0), 3, 0) == 197121 : U32}

law xm_module_offset_moves_on:
  {Xm.moved(60, 276) == 336 : U32}

law xm_module_offset_past_any_data_stays_there:
  {Xm.moved(4026531840, 5) == 4026531840 : U32}

law xm_module_offset_does_not_wrap:
  {Xm.moved(4000000000, 4000000000) == 4026531840 : U32}

law xm_module_int8_of_a_byte:
  {Xm.s8(255) == 4294967295 : U32}

law xm_module_int8_keeps_its_range:
  {Xm.s8(384) == 4294967168 : U32}

law xm_module_int16_of_two_bytes:
  {Xm.s16(65534) == 4294967294 : U32}

law xm_module_sizes_are_aligned_to_16:
  {Xm.aligned(424) == 432 : U32}

law xm_module_aligned_size_stays:
  {Xm.aligned(448) == 448 : U32}

law xm_module_sizes_stop_past_the_limit:
  {Xm.times(4000000000, 5) == 1073741824 : U32}

law xm_module_int_halved_toward_zero:
  {Xm.halved(4294967293) == 4294967295 : U32}

law xm_module_loop_of_a_16_bit_sample_is_halved:
  {Xm.loop.end(True{}, False{}, 21, 60) == 40 : U32}

law xm_module_loop_of_a_stereo_sample_is_halved_as_ints:
  {Xm.loop.start(False{}, True{}, 2147483651) == 3221225474 : U32}

law xm_module_loop_of_a_plain_sample_is_the_header_s:
  {Xm.loop.end(False{}, False{}, 4294967280, 49) == 33 : U32}

law xm_module_vibrato_waveforms_one_and_two_are_swapped:
  {((Xm.waveform(1) * 100) + ((Xm.waveform(2) * 10) + Xm.waveform(4)) : U32) == 214 : U32}

law xm_module_plain_slot_takes_five_bytes:
  {Xm.slot.size(49) == 5 : U32}

law xm_module_packed_slot_takes_what_it_says:
  {Xm.slot.size(154) == 4 : U32}

law xm_module_empty_packed_slot_takes_one_byte:
  {Xm.slot.size(128) == 1 : U32}

law xm_module_packed_slots_are_read:
  {Xm.unpack(St.Index.from([129, 60, 128], 0), 3, 0, 3, 2) == Xm.Unpacked{[Xm.Slot{0, 0, 0, 0, 0}, Xm.Slot{60, 0, 0, 0, 0}], 0} : Xm.Unpacked}

law xm_module_plain_slot_is_read:
  {Xm.unpack(St.Index.from([49, 1, 2, 3, 4], 0), 5, 0, 5, 1) == Xm.Unpacked{[Xm.Slot{49, 1, 2, 3, 4}], 0} : Xm.Unpacked}

law xm_module_slot_past_the_pattern_s_is_refused:
  {Xm.unpack(St.Index.from([128, 128, 128], 0), 3, 0, 3, 2) == Xm.Unpacked{[Xm.Slot{0, 0, 0, 0, 0}, Xm.Slot{0, 0, 0, 0, 0}], 1} : Xm.Unpacked}

law xm_module_bytes_for_no_slots_are_refused:
  {Xm.unpack(St.Index.from([128], 0), 1, 0, 1, 0) == Xm.Unpacked{Nil{}, 1} : Xm.Unpacked}

law xm_module_no_bytes_are_no_slots_read:
  {Xm.unpack(St.Index.from([128], 0), 1, 0, 0, 9) == Xm.Unpacked{Nil{}, 0} : Xm.Unpacked}

law xm_module_slots_left_out_are_zeros:
  {Xm.slots.whole([Xm.Slot{60, 0, 0, 0, 0}], 3) == [Xm.Slot{60, 0, 0, 0, 0}, Xm.Slot{0, 0, 0, 0, 0}, Xm.Slot{0, 0, 0, 0, 0}] : +List<Xm.Slot>}

law xm_module_order_of_its_patterns_is_fine:
  {Xm.order.check([0, 1, 0, 9], True{}, 0, 0, 3, 2) == Xm.Checked{0, 3} : Xm.Checked}

law xm_module_order_loses_a_last_entry_without_a_pattern:
  {Xm.order.check([0, 1, 9, 9], True{}, 0, 0, 3, 2) == Xm.Checked{0, 2} : Xm.Checked}

law xm_module_order_with_an_entry_without_a_pattern_fails:
  {Xm.order.check([0, 9, 1, 0], True{}, 0, 0, 3, 2) == Xm.Checked{1, 3} : Xm.Checked}

law xm_module_order_of_one_entry_without_a_pattern_fails:
  {Xm.order.check([9], True{}, 0, 0, 1, 2) == Xm.Checked{1, 1} : Xm.Checked}

law xm_module_order_past_its_bytes_is_checked_without_end:
  {Xm.order.check([0, 0], True{}, 0, 0, 256, 1) == Xm.Checked{2, 256} : Xm.Checked}

law xm_module_data_with_its_marks_is_sane:
  {Xm.sane(St.Index.from([69, 120, 116, 101, 110, 100, 101, 100, 32, 77, 111, 100, 117, 108, 101, 58, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 26, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 4, 1], 0), 60) == True{} : Bool}

law xm_module_data_of_59_bytes_is_not:
  {Xm.sane(St.Index.from([69, 120, 116, 101, 110, 100, 101, 100, 32, 77, 111, 100, 117, 108, 101, 58, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 26, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 4, 1], 0), 59) == False{} : Bool}

law xm_module_another_version_is_not_sane:
  {Xm.sane(St.Index.from([69, 120, 116, 101, 110, 100, 101, 100, 32, 77, 111, 100, 117, 108, 101, 58, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 26, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 3, 1], 0), 60) == False{} : Bool}

law xm_module_no_data_is_no_module:
  {Xm.load(Nil{}) == Xm.Failed{1} : Xm.Loaded}

law xm_module_other_data_is_no_module:
  {Xm.load([1, 2, 3]) == Xm.Failed{1} : Xm.Loaded}

# An XM channel's pitch and envelopes (src/xm_pitch.bend): an Amiga period
# shifted by octaves, the random waveform's state, an envelope's loop and
# its points.

law xm_pitch_amiga_period_an_octave_up_is_halved:
  {XmP.amiga.shifted(1712, 1) == 856 : U32}

law xm_pitch_amiga_period_an_octave_down_is_doubled:
  {XmP.amiga.shifted(1712, 4294967295) == 3424 : U32}

law xm_pitch_amiga_period_far_down_is_kept_in_16_bits:
  {XmP.amiga.shifted(1712, 4294967276) == 0 : U32}

law xm_pitch_amiga_period_ten_octaves_up_is_zero:
  {XmP.amiga.shifted(856, 10) == 0 : U32}

law xm_pitch_amiga_table_ends_an_octave_from_its_start:
  {((XmP.nth(XmP.amiga.table(), 0) * 10000) + XmP.nth(XmP.amiga.table(), 12) : U32) == 17120856 : U32}

law xm_pitch_random_waveform_s_first_step:
  {XmP.random.next(24492) == 3361166453 : U32}

law xm_pitch_envelope_counter_at_the_loop_s_end_goes_back:
  {XmP.envelope.looped(True{}, [Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 1, 3, 20) == 4 : U32}

law xm_pitch_envelope_counter_before_the_loop_s_end_stays:
  {XmP.envelope.looped(True{}, [Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 1, 3, 19) == 19 : U32}

law xm_pitch_envelope_without_a_loop_keeps_its_counter:
  {XmP.envelope.looped(False{}, [Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 1, 3, 25) == 25 : U32}

law xm_pitch_envelope_loop_backwards_wraps_in_16_bits:
  {XmP.envelope.looped(True{}, [Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 3, 1, 5) == 21 : U32}

law xm_pitch_envelope_without_points_changes_nothing:
  {XmP.envelope.tick(Xm.Envelope{Nil{}, 0, 0, 0, 0, True{}, True{}, True{}}, True{}, 7, 0.25) == XmP.Ticked{7, 0.25, True{}} : XmP.Ticked}

law xm_pitch_envelope_point_is_read_by_its_number:
  {XmP.Point.frame(XmP.point.nth([Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 2)) == 10 : U32}

law xm_pitch_envelope_point_past_the_12th_is_none_of_its:
  {XmP.point.nth([Xm.Point{0, 0}, Xm.Point{4, 64}, Xm.Point{10, 32}, Xm.Point{20, 48}, Xm.Point{30, 0}], 99) == Xm.Point{0, 0} : Xm.Point}

# An XM channel's next sample (src/xm_sample.bend): the values kept of the
# sample before a new note, the float after a position (a loop's start at
# its end, the right side in the data's second half), and where a step's
# value goes.

law xm_sample_kept_value_is_read_by_its_number:
  {XmS.nth([1.0, 2.0, 3.0], 1) == 2.0 : F32}

law xm_sample_kept_value_past_the_eight_is_zero:
  {XmS.nth([1.0, 2.0, 3.0], 9) == 0.0 : F32}

law xm_sample_kept_value_is_put_at_its_number:
  {XmS.put([1.0, 2.0, 3.0], 1, 9.0) == [1.0, 9.0, 3.0] : +List<F32>}

law xm_sample_value_past_the_kept_ones_is_not_put:
  {XmS.put([1.0, 2.0, 3.0], 5, 9.0) == [1.0, 2.0, 3.0] : +List<F32>}

law xm_sample_float_after_a_loop_s_end_is_its_start:
  {XmS.after(XmS.Tone{16, 4, 8, 12, True{}, False{}, St.Row.new(0, 0.0), 16}, 12, 0) == 4 : U32}

law xm_sample_float_after_inside_a_loop_is_the_next:
  {XmS.after(XmS.Tone{16, 4, 8, 12, True{}, False{}, St.Row.new(0, 0.0), 16}, 11, 0) == 11 : U32}

law xm_sample_right_side_is_the_data_s_second_half:
  {XmS.after(XmS.Tone{16, 4, 8, 12, True{}, False{}, St.Row.new(0, 0.0), 16}, 12, 16) == 20 : U32}

law xm_sample_float_after_without_a_loop_is_the_next:
  {XmS.after(XmS.Tone{16, 0, 0, 0, False{}, False{}, St.Row.new(0, 0.0), 16}, 12, 0) == 12 : U32}

law xm_sample_loop_always_has_a_float_after:
  {XmS.follows(XmS.Tone{16, 4, 8, 12, True{}, False{}, St.Row.new(0, 0.0), 16}, 4000) == True{} : Bool}

law xm_sample_last_float_without_a_loop_has_none_after:
  {XmS.follows(XmS.Tone{16, 0, 0, 0, False{}, False{}, St.Row.new(0, 0.0), 16}, 16) == False{} : Bool}

law xm_sample_float_before_the_last_has_one_after:
  {XmS.follows(XmS.Tone{16, 0, 0, 0, False{}, False{}, St.Row.new(0, 0.0), 16}, 15) == True{} : Bool}

law xm_sample_value_of_a_new_note_s_ramp_is_kept:
  {XmS.given(XmS.Head{0.5, 1.0, 3, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, 0.0}, 2, 0.25, 0.75) == XmS.Head{0.5, 1.0, 3, [0.0, 0.0, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.75, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, 0.0} : XmS.Head}

law xm_sample_value_of_a_frame_is_the_channel_s:
  {XmS.given(XmS.Head{0.5, 1.0, 3, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, 0.0}, 4294967295, 0.25, 0.75) == XmS.Head{0.5, 1.0, 3, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.25, 0.75} : XmS.Head}

# An XM player's rows and ticks (src/xm_player.bend): the parameters a
# channel remembers, the volume column's commands, jar_xm's tests for a
# tone portamento and a vibrato, the tempo and BPM, and where a row is
# after a jump, a break and the order's end.

law xm_player_speed_and_depth_keep_what_a_parameter_leaves_out:
  {((XmPl.nibbles(53, 64) * 65536) + ((XmPl.nibbles(53, 7) * 256) + XmPl.nibbles(53, 0)) : U32) == 4536117 : U32}

law xm_player_volume_column_sets_the_volume_from_0x10_to_0x50:
  {((((XmPl.column.kind(16) * 1000) + (XmPl.column.kind(79) * 100)) + (XmPl.column.kind(80) * 10)) + XmPl.column.kind(81) : U32) == 1110 : U32}

law xm_player_volume_column_s_other_commands_are_its_high_bits:
  {((XmPl.column.kind(96) * 100) + XmPl.column.kind(243) : U32) == 615 : U32}

law xm_player_empty_volume_column_does_nothing:
  {XmPl.column.kind(5) == 0 : U32}

law xm_player_remembered_parameter_is_kept:
  {XmPl.memo.get(XmPl.memo.set(XmPl.Memo{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 10, 7), 10) == 7 : U32}

law xm_player_remembered_parameter_leaves_the_others:
  {XmPl.memo.get(XmPl.memo.set(XmPl.Memo{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 10, 7), 11) == 0 : U32}

law xm_player_tone_portamento_by_its_effects:
  {XmPl.portamento.has(Xm.Slot{0, 0, 0, 3, 0}) == True{} : Bool}

law xm_player_tone_portamento_by_the_volume_column:
  {XmPl.portamento.has(Xm.Slot{0, 0, 241, 0, 0}) == True{} : Bool}

law xm_player_vibrato_is_no_tone_portamento:
  {XmPl.portamento.has(Xm.Slot{0, 0, 0, 4, 0}) == False{} : Bool}

law xm_player_vibrato_by_a_parameter_of_six_as_jar_xm_tests_it:
  {XmPl.vibrato.has(Xm.Slot{0, 0, 0, 1, 6}) == True{} : Bool}

law xm_player_effect_six_alone_is_no_vibrato_to_that_test:
  {XmPl.vibrato.has(Xm.Slot{0, 0, 0, 6, 1}) == False{} : Bool}

law xm_player_song_begins_again_at_its_restart_position:
  {XmPl.place.changed(Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, 2, 5, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}) == XmPl.Place{1, 5, XmPl.Song{6, 125, 1.0, False{}, False{}, 0, 0, 0, 24492, 0}} : XmPl.Place}

law xm_player_entry_inside_the_order_stays:
  {XmPl.place.changed(Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, 1, 5, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}) == XmPl.Place{1, 5, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}} : XmPl.Place}

law xm_player_low_parameter_sets_the_tempo:
  {XmPl.song.paced(XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 31) == XmPl.Song{31, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0} : XmPl.Song}

law xm_player_high_parameter_sets_the_bpm:
  {XmPl.song.paced(XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 32) == XmPl.Song{3, 32, 0.5, False{}, False{}, 0, 0, 0, 24492, 0} : XmPl.Song}

law xm_player_parameter_of_zero_sets_neither:
  {XmPl.song.paced(XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0) == XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0} : XmPl.Song}

law xm_player_first_reason_to_stop_is_kept:
  {XmPl.Song.why(XmPl.stopped(XmPl.stopped(XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 5), 1)) == 5 : U32}

law xm_player_pattern_break_goes_to_the_next_entry:
  {XmPl.place.of(Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, 0, 3, XmPl.Song{3, 99, 0.5, False{}, True{}, 0, 2, 0, 24492, 0}) == XmPl.Place{1, 2, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}} : XmPl.Place}

law xm_player_position_jump_goes_to_its_entry:
  {XmPl.place.of(Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, 1, 3, XmPl.Song{3, 99, 0.5, True{}, False{}, 0, 0, 0, 24492, 0}) == XmPl.Place{0, 0, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}} : XmPl.Place}

# An XM player's mixer (src/xm_mixer.bend): a channel's frame counted, a
# channel that does not sound, and the count and order of the samples
# generated.

law xm_mixer_frame_of_a_channel_is_counted:
  {XmX.head.counted(XmS.Head{0.5, 1.0, 3, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.25, 0.75}) == XmS.Head{0.5, 1.0, 4, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.25, 0.75} : XmS.Head}

law xm_mixer_channel_that_does_not_sound_is_kept_as_it_is:
  {XmX.channel.kept(XmPl.channel.new(), XmX.Mixed{Nil{}, 0.5, 0.25, True{}}) == XmX.Mixed{[XmPl.channel.new()], 0.5, 0.25, True{}} : XmX.Mixed}

law xm_mixer_samples_generated_are_the_player_s_count:
  {XmX.generated.of(XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}) == 7 : U32}

law xm_mixer_frames_asked_for_are_added_to_the_count:
  {XmX.generated.of(XmX.player.generated(XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}, 5)) == 12 : U32}

law xm_mixer_samples_come_in_the_order_they_were_made:
  {XmX.generated.ended(XmX.Generated{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}, [4.0, 3.0, 2.0, 1.0]}) == XmX.Generated{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}, [1.0, 2.0, 3.0, 4.0]} : XmX.Generated}

# XM musics (Music.load_for on a module, src/xm_mixer.bend's count): the
# count of samples generated is one of 32 bits, past which the player stops;
# a module's token, the device's rate for its player, and a load's error for
# what stops a player; a module's music has its player's reason, is a
# decoder, does not seek, and a stop is its player's reset.

law xm_mixer_count_of_32_bits_takes_the_frames_that_fit:
  {XmX.generated.fits(4294967290, 5) == True{} : Bool}

law xm_mixer_count_past_32_bits_does_not_fit:
  {XmX.generated.fits(4294967295, 1) == False{} : Bool}

law xm_mixer_player_whose_count_is_full_stops_without_a_frame:
  {XmX.generate(XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 4294967295, Nil{}}, 1) == XmX.Generated{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 4}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 4294967295, Nil{}}, Nil{}} : XmX.Generated}

law music_token_of_a_module:
  {((J.Music.decode.kind(".xm") * 100) + (J.Music.decode.kind(".XM") * 10) + J.Music.decode.kind(".Xm") : U32) == 660 : U32}

law music_device_rate_is_0_until_the_device_is_ready:
  {((J.Music.device.rate(True{}) * 2) + J.Music.device.rate(False{}) : U32) == 96000 : U32}

law music_module_past_the_port_s_limits_is_unsupported:
  {J.Music.xm.error(4) == J.UnsupportedWaveFormat{} : J.Wave.Error}

law music_module_that_needs_what_the_profile_lacks_is_unsupported:
  {J.Music.xm.error(5) == J.UnsupportedWaveFormat{} : J.Wave.Error}

law music_module_that_is_undefined_is_invalid_data:
  {J.Music.xm.error(1) == J.InvalidWaveData{} : J.Wave.Error}

law music_module_that_does_not_end_is_invalid_data:
  {J.Music.xm.error(2) == J.InvalidWaveData{} : J.Wave.Error}

law music_of_a_file_has_nothing_to_stop_for:
  {J.Music.why(J.Music{J.AudioStream{0, 44100, 16, 2}, 700, True{}, 1, J.MusicWav{[1, 2], 0}}) == 0 : U32}

law music_why_is_its_player_s:
  {J.Music.context.why(J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 5}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}}) == 5 : U32}

law music_module_is_a_decoder:
  {J.Music.context.loaded(J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}}) == True{} : Bool}

law music_module_does_not_seek:
  {J.Music.context.seeks(J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}}) == False{} : Bool}

law music_file_seeks:
  {J.Music.context.seeks(J.MusicWav{[1, 2], 0}) == True{} : Bool}

law music_module_sought_stays_where_it_is:
  {J.Music.context.sought(J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}}, 9, 4) == J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}} : J.Music.Context}

law music_module_stopped_goes_back_to_its_start:
  {J.Music.context.rewound(J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{3, 99, 0.5, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 7, Nil{}}}) == J.MusicXm{XmPl.Player{M.Glibc239Libm{}, Xm.Module{2, 1, 1, 0, 6, 125, [0, 0], Nil{}, Nil{}, 0}, Nil{}, 48000, XmPl.Song{6, 125, 1.0, False{}, False{}, 0, 0, 0, 24492, 0}, 0, 0, 0, 0.0, St.Index.new(0, 0), 0, 0, Nil{}}} : J.Music.Context}

# glibc 2.39's binary64 acos (src/lgpl/acos.bend, docs/MATH.md): a zero of
# either sign has pi/2 (its high part), 1 has 0 and -1 has pi; what is above
# 1, infinite or NaN is refused; a half is in the table's third interval and
# the last double below 1 in the root's; and only the glibc 2.39 profile
# answers.

law glibc_acos_of_zero:
  {GlibcAcos.acos(0, 0) == Some{F.Words{1073291771, 1413754136}} : Maybe<F.Words>}

law glibc_acos_of_negative_zero:
  {GlibcAcos.acos(2147483648, 0) == Some{F.Words{1073291771, 1413754136}} : Maybe<F.Words>}

law glibc_acos_of_one:
  {GlibcAcos.acos(1072693248, 0) == Some{F.Words{0, 0}} : Maybe<F.Words>}

law glibc_acos_of_minus_one:
  {GlibcAcos.acos(3220176896, 0) == Some{F.Words{1074340347, 1413754136}} : Maybe<F.Words>}

law glibc_acos_above_one_refused:
  {GlibcAcos.acos(1072693248, 1) == None{} : Maybe<F.Words>}

law glibc_acos_of_infinity_refused:
  {GlibcAcos.acos(2146435072, 0) == None{} : Maybe<F.Words>}

law glibc_acos_of_nan_refused:
  for low: U32
  {GlibcAcos.acos(2146959360, low) == None{} : Maybe<F.Words>}

law glibc_acos_interval_of_a_half:
  {GlibcAcos.interval(1071644672) == 4 : U32}

law glibc_acos_interval_below_one:
  {GlibcAcos.interval(1072693247) == 8 : U32}

law glibc_acos64_apple_refused:
  for value: M.Float64
  {M.Libm.acos64(M.AppleLibm{}, value) == None{} : Maybe<M.Float64>}

law glibc_acos64_glibc241_refused:
  for value: M.Float64
  {M.Libm.acos64(M.Glibc241Libm{}, value) == None{} : Maybe<M.Float64>}

# The cube root of stb_truetype's cubic solver (src/power64.bend,
# docs/MATH.md): a zero of either sign has the root +0; a negative float,
# an infinity and NaN are refused; and the exponential answers 1 + x below
# 2^-54, takes its main path at 1 and has no answer from 512 up.

law power64_third_of_zero:
  {Power64.third(0) == Some{0} : Maybe<U32>}

law power64_third_of_negative_zero:
  {Power64.third(2147483648) == Some{0} : Maybe<U32>}

law power64_third_of_minus_one_refused:
  {Power64.third(3212836864) == None{} : Maybe<U32>}

law power64_third_of_infinity_refused:
  {Power64.third(2139095040) == None{} : Maybe<U32>}

law power64_third_of_nan_refused:
  {Power64.third(2143289344) == None{} : Maybe<U32>}

law power64_tiny_exponential_is_one_plus_x:
  {Power64.exp.range(0) == 0 : U32}

law power64_exponential_of_one_is_the_main_path:
  {Power64.exp.range(1072693248) == 1 : U32}

law power64_exponential_from_512_has_no_answer:
  {Power64.exp.range(1082130432) == 2 : U32}

# stb_truetype's cubic solver (src/stb_cubic.bend) and its profile: an acos
# argument above 1 leaves three NaN roots, none used; terms that are not
# finite, and a cube root the port has no answer for, leave no answer; and
# Font.load_data_for solves only under the glibc 2.39 profile.

law cubic_acos_above_one_leaves_no_root:
  {Cubic.three.inside(True{}, 0.5, 0.25, 1072693248, 1) == Cubic.Roots{4, 0.0, 0.0, 0.0} : Cubic.Roots}

law cubic_without_finite_terms_has_no_answer:
  {Cubic.three.at(False{}, 0.5, 0.25, 0.125, 1.0) == Cubic.Roots{0, 0.0, 0.0, 0.0} : Cubic.Roots}

law cubic_one_root_of_an_unknown_cube_root_has_no_answer:
  {Cubic.one.rooted(0.5, None{}, Some{0.25}) == Cubic.Roots{0, 0.0, 0.0, 0.0} : Cubic.Roots}

law font_cubic_under_glibc239:
  {J.Font.cubic(M.Glibc239Libm{}) == True{} : Bool}

law font_no_cubic_under_apple:
  {J.Font.cubic(M.AppleLibm{}) == False{} : Bool}

law font_no_cubic_under_glibc241:
  {J.Font.cubic(M.Glibc241Libm{}) == False{} : Bool}

# A Font a program assembles itself (Font.assemble): each glyph of
# LoadFontData with its GenImageFontAtlas rectangle, in order, as many as
# there are pairs.

law font_assemble_pairs_a_glyph_with_its_rectangle:
  {J.Font.assemble.glyph(J.GlyphInfo{65, 1, 2, 9, J.GlyphEmpty{0, 0}}, J.Rectangle{1.0, 2.0, 3.0, 4.0}) == FontCore.Glyph{65, 1, 2, 9, 1.0, 2.0, 3.0, 4.0} : FontCore.Glyph}

law font_assemble_stops_at_the_shorter_list:
  {J.Font.assemble.glyphs([J.GlyphInfo{65, 1, 2, 9, J.GlyphEmpty{0, 0}}], Nil{}) == Nil{} : +List<FontCore.Glyph>}

# raylib 6.2's LoadFontData gives the Unicode space codepoints an empty
# advanceX x fontSize image (FontData.blank.codepoint): U+0020, U+00A0,
# U+1680, U+2000..U+200A, U+202F, U+205F and U+3000 (6.0: U+0020, U+3000).

law font_data_blank_no_break_space:
  {FontData.blank.codepoint(160) == True{} : Bool}

law font_data_blank_general_punctuation_spaces:
  {[Bool.to_u32(FontData.blank.codepoint(8191)), Bool.to_u32(FontData.blank.codepoint(8192)), Bool.to_u32(FontData.blank.codepoint(8202)),
    Bool.to_u32(FontData.blank.codepoint(8203)), Bool.to_u32(FontData.blank.codepoint(8239)), Bool.to_u32(FontData.blank.codepoint(8287))] == [0, 1, 1, 0, 1, 1] : +List<U32>}

law font_data_blank_ogham_ascii_and_ideographic:
  {(Bool.to_u32(FontData.blank.codepoint(5760)) + Bool.to_u32(FontData.blank.codepoint(32)) + Bool.to_u32(FontData.blank.codepoint(12288)) : U32) == 3 : U32}

law font_data_letter_not_blank:
  {FontData.blank.codepoint(65) == False{} : Bool}

# raylib 6.2's LoadFontDataBDF: HexToInt gives 0 for bytes that are not hex
# digits; a requested glyph (its first index) gets the ENCODING, the BBX x
# offset, fontAscent (FONTBOUNDINGBOX height plus y offset, here 2) minus
# BBX height plus y offset, the DWIDTH x and its rows (bit 8 >> (x % 4) of
# digit x / 4; rows not given stay zero); unrequested glyphs stay zeroed; a
# row past the glyph height ends the read.

law font_bdf_hex_digits:
  {[FontData.nibble(70), FontData.nibble(97), FontData.nibble(57), FontData.nibble(71), FontData.nibble(13)] == [15, 10, 9, 0, 0] : +List<U32>}

law font_bdf_reads_a_requested_glyph:
  {FontData.bdf([83, 84, 65, 82, 84, 70, 79, 78, 84, 10, 70, 79, 78, 84, 66, 79, 85, 78, 68, 73, 78, 71, 66, 79, 88, 32, 52, 32, 51, 32, 48, 32, 45, 49, 10, 83, 84, 65, 82, 84, 67, 72, 65, 82, 32, 65, 10, 69, 78, 67, 79, 68, 73, 78, 71, 32, 54, 53, 10, 66, 66, 88, 32, 51, 32, 51, 32, 49, 32, 45, 49, 10, 68, 87, 73, 68, 84, 72, 32, 52, 32, 48, 10, 66, 73, 84, 77, 65, 80, 10, 65, 48, 10, 52, 10, 69, 78, 68, 67, 72, 65, 82, 10, 69, 78, 68, 70, 79, 78, 84, 10], [66, 65], 9) ==
    FontData.Bdf{1, 9, [FontData.glyph.zero(), FontData.Glyph{65, 1, 0, 4, 3, 3, True{}, [255, 0, 255, 0, 255, 0, 0, 0, 0]}]} : FontData.Bdf}

law font_bdf_row_past_the_height_ends_the_read:
  {FontData.bdf([83, 84, 65, 82, 84, 70, 79, 78, 84, 10, 83, 84, 65, 82, 84, 67, 72, 65, 82, 10, 69, 78, 67, 79, 68, 73, 78, 71, 32, 54, 53, 10, 66, 66, 88, 32, 50, 32, 49, 32, 48, 32, 48, 10, 66, 73, 84, 77, 65, 80, 10, 56, 10, 67, 10, 69, 78, 68, 67, 72, 65, 82, 10, 83, 84, 65, 82, 84, 67, 72, 65, 82, 10, 69, 78, 67, 79, 68, 73, 78, 71, 32, 54, 54, 10, 66, 66, 88, 32, 49, 32, 49, 32, 48, 32, 48, 10, 66, 73, 84, 77, 65, 80, 10, 56, 10, 69, 78, 68, 67, 72, 65, 82, 10, 69, 78, 68, 70, 79, 78, 84, 10], [65, 66], 9) ==
    FontData.Bdf{1, 9, [FontData.Glyph{65, 0, 4294967295, 0, 2, 1, True{}, [255, 0]}, FontData.glyph.zero()]} : FontData.Bdf}

# ImageDrawTextPro (new in raylib 6.2) has an empty body: nothing changes.

law font_image_draw_text_pro_draws_nothing:
  for destination: J.Surface
  for font: J.Font
  for text: String
  for position: M.Vector2
  for origin: M.Vector2
  for rotation: F32
  for size: F32
  for spacing: F32
  for tint: U32
  {J.Font.image_draw_text_pro(destination, font, text, position, origin, rotation, size, spacing, tint) == (destination, font) : J.Surface & J.Font}

# Ogg Vorbis musics: the ".ogg" token in either case, and a read padded with
# zeros where it ended early, cut to the samples the stream takes.

law music_token_of_an_ogg_stream:
  {((J.Music.decode.kind(".ogg") * 10) + J.Music.decode.kind(".OGG") : U32) == 22 : U32}

law music_ogg_read_padded_with_zeros:
  {J.Music.ogg.padded(3n, [7], Nil{}) == [7, 0, 0] : +List<U32>}

law music_ogg_read_cut_to_the_frames_asked:
  {J.Music.ogg.padded(2n, [7, 8, 9], Nil{}) == [7, 8] : +List<U32>}

law base64_standard_text:
  {J.Base64.decode_wide("aGVsbG8=") == Some{J.Base64Decoded{5, [104, 101, 108, 108, 111]}} : Maybe<&2, J.Base64.Decoded>}

law base64_permissive_high_sextet:
  {J.Base64.decode_wide("BA==") == Some{J.Base64Decoded{1, [4]}} : Maybe<&2, J.Base64.Decoded>}

law base64_short_input:
  {J.Base64.decode_wide("AAA") == Some{J.Base64Decoded{0, Nil{}}} : Maybe<&2, J.Base64.Decoded>}

law base64_negative_estimate:
  {J.Base64.decode_wide("A=") == Some{J.Base64Decoded{4294967295, Nil{}}} : Maybe<&2, J.Base64.Decoded>}

law base64_undefined_empty:
  {J.Base64.decode_wide("") == None{} : Maybe<&2, J.Base64.Decoded>}

law base64_undefined_padding_only:
  {J.Base64.decode_wide("====") == None{} : Maybe<&2, J.Base64.Decoded>}
