# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned stb_image GIF retain/restore frame composition.
# MIT notice: LICENSES/stb-image.txt. See THIRD_PARTY_NOTICES.md.
import Base
import ./gif.bend as G
import ./qoi.bend as Q

type Animation is Type:
  Animation{width: U32, height: U32, count: U32, frames: List<G.Image>}

type Previous is Type:
  Initial{}
  Previous{canvas: Array<U32>, saved: Array<U32>, region: G.Region, disposal: U32}

type Prepared is Type:
  Prepared{canvas: Array<U32>, saved: Array<U32>}

def restore.write(index: U32, canvas: Array<U32>, read: Array<U32> & U32) -> Array<U32> & Array<U32>:
  (saved, color) = read
  (saved, Array.set(U32, canvas, index, color))

def restore.pixels(n: Nat, +index: U32, +width: U32, +region: G.Region, state: Array<U32> & Array<U32>) -> Array<U32>:
  match n state:
    case 0n Tuple{_, canvas}: canvas
    case 1n+rest Tuple{saved, canvas}:
      +at = G.position(index, width, region)
      restore.pixels(rest, (index + 1 : U32), width, region, restore.write(at, canvas, Array.get(U32, saved, at)))

def restore(active: Bool, width: U32, region: G.Region, canvas: Array<U32>, saved: Array<U32>) -> Array<U32>:
  match active region:
    case False{} _: canvas
    case True{} G.Region{x, y, +w, +h, interlaced}:
      restore.pixels(U32.to_nat((w * h : U32)), 0, width, G.Region{x, y, w, h, interlaced}, (saved, canvas))

def prepared.clone(result: Array<U32> & Array<U32>) -> Prepared:
  (canvas, saved) = result
  Prepared{canvas, saved}

def prepare(width: U32, height: U32, background: U32, previous: Previous) -> Prepared:
  match previous:
    case Initial{}:
      +count = (width * height : U32)
      +depth = Bool.pick(Nat, U32.is_eq(count, 1), 0n, 1n+U32.log2((count - 1 : U32)))
      Prepared{Array.new(U32, depth, background), Array.new(U32, depth, 0)}
    case Previous{canvas, saved, region, disposal}:
      prepared.clone(Array.clone(U32, restore(U32.is_eq(disposal, 2), width, region, canvas, saved)))

type State is Type:
  Continuing{header: G.Header, previous: Previous, count: U32, remaining: U32, frames: List<G.Image>}
  Complete{animation: Animation}

def retained(width: U32, height: U32, region: G.Region, disposal: U32, following: G.Header, +count: U32, remaining: U32, frames: List<G.Image>, saved: Array<U32>, result: Array<U32> & Array<U32>) -> State:
  (canvas, copy) = result
  Continuing{following, Previous{canvas, saved, region, disposal}, (count + 1 : U32), remaining, Con{G.Image{width, height, copy}, frames}}

def drawn(width: U32, height: U32, region: G.Region, disposal: U32, following: G.Header, count: U32, remaining: U32, frames: List<G.Image>, saved: Array<U32>, result: Result<&1, &1, G.Error, Array<U32>>) -> Result<&1, &1, G.Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{canvas}: Done{retained(width, height, region, disposal, following, count, remaining, frames, saved, Array.clone(U32, canvas))}

def drawing(width: U32, height: U32, region: G.Region, disposal: U32, following: G.Header, +count: U32, remaining: U32, frames: List<G.Image>, frame: G.Frame, prepared: Prepared) -> Result<&1, &1, G.Error, State>:
  Prepared{canvas, saved} = prepared
  drawn(width, height, region, disposal, following, count, remaining, frames, saved, G.draw(frame, (count > 0 : U32), canvas))

def frame.checked(supported: Bool, budget: Bool, +width: U32, +height: U32, region: G.Region, background: U32, disposal: U32, following: G.Header, previous: Previous, count: U32, remaining: U32, frames: List<G.Image>, frame: G.Frame) -> Result<&1, &1, G.Error, State>:
  match supported budget:
    case False{} _: Fail{G.BadHeader{}}
    case True{} False{}: Fail{G.BadSize{}}
    case True{} True{}:
      drawing(width, height, region, disposal, following, count, (remaining - width * height : U32), frames, frame, prepare(width, height, background, previous))

def frame(allowed: Bool, +width: U32, +height: U32, previous: Previous, count: U32, +remaining: U32, frames: List<G.Image>, frame: G.Frame) -> Result<&1, &1, G.Error, State>:
  G.Frame{fw, fh, +region, +background, palette, selected, minimum, data, G.Header{cw, ch, global, bg, transparent, +disposal, tail}} = frame
  +following = {G.Header{cw, ch, global, bg, transparent, disposal, tail} : G.Header}
  frame.checked((disposal <= 2 : U32), allowed && (width * height <= remaining : U32), width, height, region, background, disposal,
    following, previous, count, remaining, frames, G.Frame{fw, fh, region, background, palette, selected, minimum, data, following})

def finished(valid: Bool, width: U32, height: U32, count: U32, frames: List<G.Image>) -> Result<&1, &1, G.Error, State>:
  match valid:
    case False{}: Fail{G.BadHeader{}}
    case True{}: Done{Complete{Animation{width, height, count, List.reverse(&1, G.Image, frames)}}}

def step(allowed: Bool, width: U32, height: U32, previous: Previous, +count: U32, remaining: U32, frames: List<G.Image>, result: Result<&2, &2, G.Error, G.Search>) -> Result<&1, &1, G.Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{G.End{}}: finished((count > 0 : U32), width, height, count, frames)
    case Done{G.Found{value}}: frame(allowed, width, height, previous, count, remaining, frames, value)
    case _: Fail{G.BadHeader{}}

def run(n: Nat, +width: U32, +height: U32, state: Result<&1, &1, G.Error, State>) -> Result<&1, &1, G.Error, Animation>:
  match n state:
    case _ Fail{error}: Fail{error}
    case _ Done{Complete{animation}}: Done{animation}
    case 0n _: Fail{G.BadSize{}}
    case Succ{+rest} Done{Continuing{header, previous, count, remaining, frames}}:
      run(rest, width, height, step(Nat.is_lt(0n, rest), width, height, previous, count, remaining, frames, G.scanned(Done{header})))

def header(maximum_frames: U32, maximum_pixels: U32, result: Result<&2, &2, G.Error, G.Header>) -> Result<&1, &1, G.Error, Animation>:
  match result:
    case Fail{error}: Fail{error}
    case Done{G.Header{+width, +height, palette, background, transparent, disposal, data}}:
      run(1n+U32.to_nat(maximum_frames), width, height,
        Done{Continuing{G.Header{width, height, palette, background, transparent, disposal, data}, Initial{}, 0, maximum_pixels, Nil{}}})

def bytes(valid: Bool, maximum_frames: U32, maximum_pixels: U32, data: +List<U32>) -> Result<&1, &1, G.Error, Animation>:
  match valid:
    case False{}: Fail{G.BadByte{}}
    case True{}: header(maximum_frames, maximum_pixels, G.header(data))

def request(valid: Bool, maximum_frames: U32, maximum_pixels: U32, +data: +List<U32>) -> Result<&1, &1, G.Error, Animation>:
  match valid:
    case False{}: Fail{G.BadSize{}}
    case True{}: bytes(Q.valid_bytes(data, True{}), maximum_frames, maximum_pixels, data)

def decode(data: +List<U32>, +maximum_frames: U32, +maximum_pixels: U32) -> Result<&1, &1, G.Error, Animation>:
  request(((maximum_frames > 0) && (maximum_pixels > 0) && (maximum_pixels <= 16777216) : U32), maximum_frames, maximum_pixels, data)
