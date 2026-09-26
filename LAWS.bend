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
