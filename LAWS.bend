import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/binary64_narrow.bend as N

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
