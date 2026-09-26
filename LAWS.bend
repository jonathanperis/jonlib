import Base
import ./jonlib.bend as J

law clear_dimensions:
  for +width: U32
  for +height: U32
  for pixels: Array<U32>
  for color: U32
  {J.Surface.dimensions(J.Surface.clear(J.Surface{width, height, pixels}, color))
    == (width, height) : U32 & U32}

law transpose_involution:
  for +matrix: J.Matrix
  {J.Matrix.transpose(J.Matrix.transpose(matrix)) == matrix : J.Matrix}

law vector3_float_count:
  for vector: J.Vector3
  {List.length(&2, F32, J.Vector3.to_float_v(vector)) == 3n : Nat}

law matrix_float_count:
  for matrix: J.Matrix
  {List.length(&2, F32, J.Matrix.to_float_v(matrix)) == 16n : Nat}
