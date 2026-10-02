import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/binary64_narrow.bend as N
import ./src/binary64_fma.bend as F
import ./src/binary64_add_sub.bend as A

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
