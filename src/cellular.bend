# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 GenImageCellular; LICENSES/raylib.txt.
import Base
import ./random.bend as R

def capacity(+count: U32) -> Nat:
  Bool.pick(Nat, (count <= 1 : U32), 0n, 1n+U32.log2((count - 1 : U32)))

def seeds.x(index: U32, offset: U32, tile: U32, y: U32, seeds: Array<U32>, draw: R.State & U32) -> R.State & Array<U32>:
  (state, word) = draw
  x = (offset + word % tile : U32)
  (state, Array.set(U32, seeds, index, ((y << 16n) .|. x : U32)))

def seeds.y(+index: U32, +columns: U32, +tile: U32, seeds: Array<U32>, draw: R.State & U32) -> R.State & Array<U32>:
  (state, word) = draw
  y = (index / columns * tile + word % tile : U32)
  seeds.x(index, (index % columns * tile : U32), tile, y, seeds, R.next(state))

def seeds.loop(n: Nat, +index: U32, +columns: U32, +tile: U32, buffers: R.State & Array<U32>) -> R.State & Array<U32>:
  match n buffers:
    case 0n _: buffers
    case 1n+rest Tuple{state, seeds}:
      seeds.loop(rest, (index + 1 : U32), columns, tile, seeds.y(index, columns, tile, seeds, R.next(state)))

def difference(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a >= b : U32), (a - b : U32), (b - a : U32))

def distance(x: U32, y: U32, +best: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (seeds, +point) = read
  +dx = difference(x, (point .&. 65535 : U32))
  +dy = difference(y, (point >> 16n : U32))
  +square = (dx * dx + dy * dy : U32)
  (seeds, Bool.pick(U32, (square < best : U32), square, best))

def neighbor(valid: Bool, index: U32, x: U32, y: U32, buffers: Array<U32> & U32) -> Array<U32> & U32:
  match valid buffers:
    case False{} _: buffers
    case True{} Tuple{seeds, best}: distance(x, y, best, Array.get(U32, seeds, index))

def nearest(n: Nat, +at: U32, +x: U32, +y: U32, +tile: U32, +columns: U32, +rows: U32, buffers: Array<U32> & U32) -> Array<U32> & U32:
  match n:
    case 0n: buffers
    case 1n+rest:
      +nx = (x / tile + at / 3 - 1 : U32)
      +ny = (y / tile + at % 3 - 1 : U32)
      nearest(rest, (at + 1 : U32), x, y, tile, columns, rows,
        neighbor(((nx < columns) && (ny < rows) : U32), (ny * columns + nx : U32), x, y, buffers))

def paint(index: U32, tile: U32, output: Array<U32>, nearest: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (seeds, square) = nearest
  +intensity = F32.to_u32(F32.min(255.0, (F32.sqrt(U32.to_f32(square)) * 256.0 / U32.to_f32(tile) : F32)))
  pixel = ((intensity << 24n) .|. (intensity << 16n) .|. (intensity << 8n) .|. 255 : U32)
  (seeds, Array.set(U32, output, index, pixel))

def pixels(n: Nat, +index: U32, +width: U32, +tile: U32, +columns: U32, +rows: U32, buffers: Array<U32> & Array<U32>) -> Array<U32>:
  match n buffers:
    case 0n Tuple{_, output}: output
    case 1n+rest Tuple{seeds, output}:
      pixels(rest, (index + 1 : U32), width, tile, columns, rows,
        paint(index, tile, output, nearest(9n, 0, (index % width : U32), (index / width : U32), tile, columns, rows, (seeds, (tile * tile : U32)))))

def seeded(+width: U32, +height: U32, +tile: U32, result: R.State & Array<U32>) -> R.State & Array<U32>:
  (state, seeds) = result
  +count = (width * height : U32)
  (state, pixels(U32.to_nat(count), 0, width, tile, (width / tile : U32), (height / tile : U32),
    (seeds, Array.new(U32, capacity(count), 255))))

def generate(state: R.State, +width: U32, +height: U32, +tile: U32) -> R.State & Array<U32>:
  +columns = (width / tile : U32)
  +count = (columns * (height / tile) : U32)
  seeded(width, height, tile, seeds.loop(U32.to_nat(count), 0, columns, tile, (state, Array.new(U32, capacity(count), 0))))
