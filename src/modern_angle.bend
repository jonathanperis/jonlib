# Private finite-input RN-even adaptation of glibc 2.41 e_atan2f.c.
# Original source SHA-256: 96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38
# Adaptation: canonical words and checked private arithmetic, with diagnostic traces.
# No public routing, host atan2/FMA hook, exception/errno or other-rounding claim.
# Copyright (c) 2022-2024 Alexei Sibidanov and Paul Zimmermann.
# 
# The original version of this file was copied from the CORE-MATH
# project (file src/binary32/atan2/atan2f.c, revision 7835c5d).
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import Base
import ./binary64_fma.bend as F
import ./binary64_add_sub.bend as A
import ./binary64_ops.bend as O
import ./binary64_gradual_multiply.bend as G
import ./binary64_narrow.bend as N

type Value is Data:
  Good{words: F.Words}
  Failed{operation: U32, operands: +List<U32>}

type TraceEvent is Data:
  TraceEvent{tag: U32, value: Value}

type Packet is Data:
  Packet{value: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>}

type DoubleDouble is Data:
  DoubleDouble{high: Value, low: Value}

type Evaluation is Data:
  Evaluation{value: Value, events: +List<TraceEvent>}

type Polynomial is Data:
  Polynomial{high: Value, low: Value, events: +List<TraceEvent>}

# A rejected primitive retains the exact call ID and input words. No substitute
# numeric value is introduced; dependencies propagate a deterministic left-first
# failure (not a claim about temporal C evaluation order).
def accepted(operation: U32, operands: +List<U32>, result: Maybe<F.Words>) -> Value:
  match result:
    case None{}: Failed{operation, operands}
    case Some{words}: Good{words}

def promote(+operation: U32, +bits: U32) -> Value:
  accepted(operation, [bits], O.checked_promote(bits))

def negate(value: Value) -> Value:
  match value:
    case Failed{operation, operands}: Failed{operation, operands}
    case Good{F.Words{high, low}}: Good{O.negate(high, low)}

def add(operation: U32, a: Value, b: Value) -> Value:
  match a b:
    case Failed{id, words} _: Failed{id, words}
    case _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah, +al}} Good{F.Words{+bh, +bl}}:
      accepted(operation, [ah,al,bh,bl], A.checked_add(ah,al,bh,bl))

def sub(operation: U32, a: Value, b: Value) -> Value:
  match a b:
    case Failed{id, words} _: Failed{id, words}
    case _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah, +al}} Good{F.Words{+bh, +bl}}:
      accepted(operation, [ah,al,bh,bl], A.checked_sub(ah,al,bh,bl))

def mul(operation: U32, a: Value, b: Value) -> Value:
  match a b:
    case Failed{id, words} _: Failed{id, words}
    case _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah, +al}} Good{F.Words{+bh, +bl}}:
      accepted(operation, [ah,al,bh,bl], O.checked_multiply(ah,al,bh,bl))

def div(operation: U32, a: Value, b: Value) -> Value:
  match a b:
    case Failed{id, words} _: Failed{id, words}
    case _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah, +al}} Good{F.Words{+bh, +bl}}:
      accepted(operation, [ah,al,bh,bl], O.checked_divide(ah,al,bh,bl))

def gradual(operation: U32, a: Value, b: Value) -> Value:
  match a b:
    case Failed{id, words} _: Failed{id, words}
    case _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah, +al}} Good{F.Words{+bh, +bl}}:
      accepted(operation, [ah,al,bh,bl], G.checked(ah,al,bh,bl))

def fma(operation: U32, a: Value, b: Value, c: Value) -> Value:
  match a b c:
    case Failed{id, words} _ _: Failed{id, words}
    case _ Failed{id, words} _: Failed{id, words}
    case _ _ Failed{id, words}: Failed{id, words}
    case Good{F.Words{+ah,+al}} Good{F.Words{+bh,+bl}} Good{F.Words{+ch,+cl}}:
      accepted(operation, [ah,al,bh,bl,ch,cl], F.checked(ah,al,bh,bl,ch,cl))

def narrow(value: Value) -> Maybe<U32>:
  match value:
    case Failed{_,_}: None{}
    case Good{F.Words{high,low}}: N.checked(high,low)

def append(events: +List<TraceEvent>, tail: +List<TraceEvent>) -> +List<TraceEvent>:
  List.append(&2, TraceEvent, events, tail)

# Exact binary64 constants from the pinned MIT source; decimal numbers below
# are integer encodings, never rounded decimal floating-point literals.
def constant.zero() -> Value:
  Good{F.Words{0,0}}

def constant.one() -> Value:
  Good{F.Words{1072693248,0}}

def constant.minus_one() -> Value:
  Good{F.Words{3220176896,0}}

def constant.third() -> Value:
  Good{F.Words{3218429269,1431655765}}

def constant.small() -> Value:
  Good{F.Words{1009778688,0}}

def constant.up() -> Value:
  Good{F.Words{1072955392,0}}

def constant.down() -> Value:
  Good{F.Words{1072168960,0}}

def constant.cn(+index: U32) -> Value:
  match index:
    case 0: Good{F.Words{1072693248,0}}
    case 1: Good{F.Words{1074007558,2566474805}}
    case 2: Good{F.Words{1073891525,3660873485}}
    case 3: Good{F.Words{1072531251,2253859190}}
    case 4: Good{F.Words{1069838244,186708432}}
    case 5: Good{F.Words{1065566046,69135631}}
    case 6: Good{F.Words{1058358971,4068894661}}
    case _: Failed{9000,[index]}

def constant.cd(+index: U32) -> Value:
  match index:
    case 0: Good{F.Words{1072693248,0}}
    case 1: Good{F.Words{1074182321,1134819034}}
    case 2: Good{F.Words{1074283026,30510805}}
    case 3: Good{F.Words{1073226269,141104363}}
    case 4: Good{F.Words{1071018085,2117732282}}
    case 5: Good{F.Words{1067512981,533849901}}
    case 6: Good{F.Words{1061894260,3094971014}}
    case _: Failed{9000,[index]}

def constant.coefficient(+index: U32) -> DoubleDouble:
  match index:
    case 0: DoubleDouble{Good{F.Words{1072693248,0}},Good{F.Words{3129524698,3309904456}}}
    case 1: DoubleDouble{Good{F.Words{3218429269,1431655765}},Good{F.Words{3161806163,3208260286}}}
    case 2: DoubleDouble{Good{F.Words{1070176665,2576980378}},Good{F.Words{3161038318,3521941617}}}
    case 3: DoubleDouble{Good{F.Words{3217180964,2454267026}},Good{F.Words{3160398236,2367170202}}}
    case 4: DoubleDouble{Good{F.Words{1069314503,477218583}},Good{F.Words{3156627950,3838106064}}}
    case 5: DoubleDouble{Good{F.Words{3216459217,1952257609}},Good{F.Words{3159765608,1030505638}}}
    case 6: DoubleDouble{Good{F.Words{1068740923,330374243}},Good{F.Words{1012659868,529200157}}}
    case 7: DoubleDouble{Good{F.Words{3216052497,286155576}},Good{F.Words{1008976868,837335912}}}
    case 8: DoubleDouble{Good{F.Words{1068375582,499407946}},Good{F.Words{3159089883,96959423}}}
    case 9: DoubleDouble{Good{F.Words{3215651462,3088468815}},Good{F.Words{1009403507,1226770754}}}
    case 10: DoubleDouble{Good{F.Words{1067999621,3920447558}},Good{F.Words{1011749603,762969326}}}
    case 11: DoubleDouble{Good{F.Words{3215344326,3574996910}},Good{F.Words{1011076726,3251241968}}}
    case 12: DoubleDouble{Good{F.Words{1067743958,4067943871}},Good{F.Words{3157966221,2243802900}}}
    case 13: DoubleDouble{Good{F.Words{3215128138,786991469}},Good{F.Words{1009711229,1264669475}}}
    case 14: DoubleDouble{Good{F.Words{1067558562,3004645813}},Good{F.Words{1008360861,2536851438}}}
    case 15: DoubleDouble{Good{F.Words{3214966717,2909135014}},Good{F.Words{3156630208,2136815092}}}
    case 16: DoubleDouble{Good{F.Words{1067379091,714760075}},Good{F.Words{1009748886,603387226}}}
    case 17: DoubleDouble{Good{F.Words{3214731445,3109572038}},Good{F.Words{1009771951,2531846701}}}
    case 18: DoubleDouble{Good{F.Words{1067108811,679511991}},Good{F.Words{3157545165,4243256778}}}
    case 19: DoubleDouble{Good{F.Words{3214428930,1397879782}},Good{F.Words{1009088854,453866458}}}
    case 20: DoubleDouble{Good{F.Words{1066741595,2395854123}},Good{F.Words{1009792701,745519687}}}
    case 21: DoubleDouble{Good{F.Words{3213976488,3293120988}},Good{F.Words{1009880947,1610325782}}}
    case 22: DoubleDouble{Good{F.Words{1066024973,3460229743}},Good{F.Words{3157037142,2618039132}}}
    case 23: DoubleDouble{Good{F.Words{3212954279,2330385210}},Good{F.Words{3156526607,2170677769}}}
    case 24: DoubleDouble{Good{F.Words{1064642162,1161561905}},Good{F.Words{1008219375,3046687544}}}
    case 25: DoubleDouble{Good{F.Words{3211101452,1541486543}},Good{F.Words{3154396668,353150965}}}
    case 26: DoubleDouble{Good{F.Words{1062354617,2367873482}},Good{F.Words{3153299707,2937944112}}}
    case 27: DoubleDouble{Good{F.Words{3208180969,1956906817}},Good{F.Words{1003647257,2325207604}}}
    case 28: DoubleDouble{Good{F.Words{1058692338,3922687717}},Good{F.Words{3149432811,1248048741}}}
    case 29: DoubleDouble{Good{F.Words{3203670210,1886494258}},Good{F.Words{999226713,1529317515}}}
    case 30: DoubleDouble{Good{F.Words{1053014573,1773475447}},Good{F.Words{3143957254,2191318983}}}
    case 31: DoubleDouble{Good{F.Words{3196230526,1869046661}},Good{F.Words{3140122683,1843861755}}}
    case _: DoubleDouble{Failed{9001,[index]},Failed{9001,[index]}}

def constant.offset(+index: U32) -> Value:
  match index:
    case 0: Good{F.Words{0,0}}
    case 1: Good{F.Words{1073291771,1413754136}}
    case 2: Good{F.Words{1074340347,1413754136}}
    case 3: Good{F.Words{1073291771,1413754136}}
    case 4: Good{F.Words{2147483648,0}}
    case 5: Good{F.Words{3220775419,1413754136}}
    case 6: Good{F.Words{3221823995,1413754136}}
    case 7: Good{F.Words{3220775419,1413754136}}
    case _: Failed{9002,[index]}

def constant.offset_low(+index: U32) -> Value:
  match index:
    case 0: Good{F.Words{0,0}}
    case 1: Good{F.Words{1016178214,856972295}}
    case 2: Good{F.Words{1017226790,856972295}}
    case 3: Good{F.Words{1016178214,856972295}}
    case 4: Good{F.Words{2147483648,0}}
    case 5: Good{F.Words{3163661862,856972295}}
    case 6: Good{F.Words{3164710438,856972295}}
    case 7: Good{F.Words{3163661862,856972295}}
    case _: Failed{9002,[index]}

# muldd preserves each source operation and grouping, including the FMA residual.
def muldd(+id: U32, +xh: Value, xl: Value, +ch: Value, cl: Value) -> DoubleDouble:
  ahlh = mul(id, ch, xl)
  alhh = mul((id + 1 : U32), cl, xh)
  +ahhh = mul((id + 2 : U32), ch, xh)
  ahhl0 = fma((id + 3 : U32), ch, xh, negate(ahhh))
  +ahhl = add((id + 5 : U32), ahhl0, add((id + 4 : U32), alhh, ahlh))
  +high = add((id + 6 : U32), ahhh, ahhl)
  low = add((id + 8 : U32), sub((id + 7 : U32), ahhh, high), ahhl)
  DoubleDouble{high,low}

def polydd.combine(+id: U32, coefficient: DoubleDouble, product: DoubleDouble, events: +List<TraceEvent>) -> Polynomial:
  match coefficient product:
    case DoubleDouble{+ci,cil} DoubleDouble{+ph,pl}:
      +th = add((id + 9 : U32), ph, ci)
      tl = add((id + 11 : U32), sub((id + 10 : U32), ci, th), ph)
      +low = add((id + 13 : U32), pl, add((id + 12 : U32), tl, cil))
      Polynomial{th,low,append(events,[TraceEvent{25,th},TraceEvent{26,low}])}

def polydd.step(count: Nat, +xh: Value, +xl: Value, state: Polynomial) -> Polynomial:
  match count:
    case 0n: state
    case 1n++rest:
      Polynomial{ch,cl,events} = state
      +i = U32.from_nat(rest)
      +id = (1000 + i * 16 : U32)
      polydd.step(rest,xh,xl,polydd.combine(id,constant.coefficient(i),muldd(id,xh,xl,ch,cl),events))

def polydd.seed(xh: Value, xl: Value, coefficient: DoubleDouble) -> Polynomial:
  DoubleDouble{ch,cl} = coefficient
  polydd.step(31n,xh,xl,Polynomial{ch,cl,Nil{}})

def polydd(xh: Value, xl: Value) -> Polynomial:
  polydd.seed(xh,xl,constant.coefficient(31))


# Only the guarded rational branch evaluates z4/z8. Each coefficient has its
# own uncontracted multiply and add, exactly as in the pinned expression tree.
def rational(enabled: Bool, +z: Value) -> Evaluation:
  match enabled:
    case False{}: Evaluation{constant.one(),[TraceEvent{11,constant.one()}]}
    case True{}:
      +z2 = mul(20,z,z)
      +z4 = mul(21,z2,z2)
      +z8 = mul(22,z4,z4)
      cn0a = add(24,constant.cn(0),mul(23,z2,constant.cn(1)))
      +cn2 = add(26,constant.cn(2),mul(25,z2,constant.cn(3)))
      cn4a = add(28,constant.cn(4),mul(27,z2,constant.cn(5)))
      cn0b = add(30,cn0a,mul(29,z4,cn2))
      +cn4 = add(32,cn4a,mul(31,z4,constant.cn(6)))
      +cn0 = add(34,cn0b,mul(33,z8,cn4))
      cd0a = add(36,constant.cd(0),mul(35,z2,constant.cd(1)))
      +cd2 = add(38,constant.cd(2),mul(37,z2,constant.cd(3)))
      cd4a = add(40,constant.cd(4),mul(39,z2,constant.cd(5)))
      cd0b = add(42,cd0a,mul(41,z4,cd2))
      +cd4 = add(44,cd4a,mul(43,z4,constant.cd(6)))
      +cd0 = add(46,cd0b,mul(45,z8,cd4))
      +r = div(47,cn0,cd0)
      Evaluation{r,[TraceEvent{2,z2},TraceEvent{3,z4},TraceEvent{4,z8},TraceEvent{5,cn0},TraceEvent{6,cn2},TraceEvent{7,cn4},TraceEvent{8,cd0},TraceEvent{9,cd2},TraceEvent{10,cd4},TraceEvent{11,r}]}

# Literal tiny z*e uses the separately checked gradual product. The encoding
# adjustment is unsigned raw64 +/-1, not numerical nextafter.
def tiny.stepped(positive: Bool, high: U32, low: U32) -> Value:
  match positive:
    case True{}: Good{O.increment(high,low)}
    case False{}: Good{O.decrement(high,low)}

def tiny.product(product: Value, zh: U32, zl: U32, +mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match product:
    case Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{F.Words{+high,+low}}:
      +positive = ((high < 2147483648) && Bool.not(O.is_zero(high,low)) : U32)
      +adjusted = tiny.stepped(positive,zh,zl)
      Packet{adjusted,(mask .|. Bool.pick(U32,positive,32,64) : U32),index,gt,append(events,[TraceEvent{20,adjusted}])}

def tiny.boundary.ready(boundary: Bool, +high: U32, +low: U32, e: Value, +mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match boundary:
    case False{}:
      +value = {Good{F.Words{high,low}} : Value}
      Packet{value,mask,index,gt,append(events,[TraceEvent{20,value}])}
    case True{}:
      +product = gradual(88,Good{F.Words{high,low}},e)
      tiny.product(product,high,low,(mask .|. 16 : U32),index,gt,append(events,[TraceEvent{19,product}]))

def tiny.boundary(z: Value, e: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match z e:
    case Failed{id,words} _: Packet{Failed{id,words},mask,index,gt,events}
    case _ Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{F.Words{high,+low}} Good{ewords}:
      tiny.boundary.ready(U32.is_eq((low .&. 268435455 : U32),0),high,low,Good{ewords},mask,index,gt,events)

def tiny(+y: Value, +x: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  +z = div(80,y,x)
  +residual = fma(81,negate(z),x,y)
  +zz = mul(82,z,z)
  +cz = mul(83,constant.third(),z)
  +e = add(86,div(84,residual,x),mul(85,cz,zz))
  tiny.boundary(z,e,(mask .|. 8 : U32),index,gt,
    append(events,[TraceEvent{14,z},TraceEvent{15,residual},TraceEvent{16,zz},TraceEvent{17,cz},TraceEvent{18,e}]))

# Final double-rounding correction retains the source's comparison and exact
# exponent-only threshold, then one 1.25/0.75 multiplication and final add.
def correction.scale(+greater: Bool, +tm: Value, +th: Value, +mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  +scaled = mul(231,tm,Bool.pick(Value,greater,constant.up(),constant.down()))
  +r = add(232,th,scaled)
  Packet{r,(mask .|. 256 .|. Bool.pick(U32,greater,512,1024) : U32),index,gt,
    append(events,[TraceEvent{38,scaled},TraceEvent{39,r}])}

def correction.threshold.ready(valid: Bool, stored: U32, +thh: U32, +thl: U32, +tmh: U32, +tml: U32, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match valid:
    case False{}: Packet{Failed{230,[thh,thl,tmh,tml]},mask,index,gt,events}
    case True{}:
      threshold = ((stored - 24) << 20n : U32)
      greater = U32.is_eq(O.magnitude_order(tmh,tml,threshold,0),2)
      correction.scale(greater,Good{F.Words{tmh,tml}},Good{F.Words{thh,thl}},mask,index,gt,events)

def correction.threshold(th: Value, tm: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match th tm:
    case Failed{id,words} _: Packet{Failed{id,words},mask,index,gt,events}
    case _ Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{F.Words{+thh,thl}} Good{F.Words{tmh,tml}}:
      # Reviewed finite fallback has nonzero normal th and exponent >24.
      +stored = O.exponent(thh)
      correction.threshold.ready((stored > 24 : U32),stored,thh,thl,tmh,tml,mask,index,gt,events)

def correction.compare.ready(equal: Bool, +th: Value, +tm: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match equal:
    case True{}: correction.threshold(th,tm,mask,index,gt,events)
    case False{}:
      +r = add(233,th,tm)
      Packet{r,mask,index,gt,append(events,[TraceEvent{39,r}])}

def correction.compare(left: Value, right: Value, th: Value, tm: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match left right:
    case Failed{id,words} _: Packet{Failed{id,words},mask,index,gt,events}
    case _ Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{F.Words{lh,ll}} Good{F.Words{rh,rl}}:
      correction.compare.ready(O.numerical_equal(lh,ll,rh,rl),th,tm,mask,index,gt,events)

def correction(th: Value, dh: Value, sl: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  +th0 = th
  +tm = add(225,dh,sl)
  +delta = mul(226,th0,constant.small())
  left = add(227,th0,delta)
  right = sub(228,th0,delta)
  correction.compare(left,right,th0,tm,mask,index,gt,append(events,[TraceEvent{37,tm}]))

def general.narrowed(value: Maybe<U32>, +sh: Value, sl: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match value:
    case None{}:
      match sh:
        case Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
        case Good{F.Words{high,low}}: Packet{Failed{222,[high,low]},mask,index,gt,events}
    case Some{bits}:
      +th = promote(223,bits)
      +dh = sub(224,sh,th)
      correction(th,dh,sl,mask,index,gt,append(events,[TraceEvent{35,th},TraceEvent{36,dh}]))

def general.prepare(sh: Value, sl: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match sh:
    case Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{+words}:
      general.narrowed(narrow(Good{words}),Good{words},sl,mask,index,gt,events)

def general.product(product: DoubleDouble, mask: U32, +index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  DoubleDouble{+outph,+outpl} = product
  +offset = constant.offset(index)
  +sh = add(212,outph,offset)
  sl0 = add(214,sub(213,offset,sh),outph)
  +sl = add(216,add(215,sl0,outpl),constant.offset_low(index))
  general.prepare(sh,sl,mask,index,gt,append(events,
    [TraceEvent{31,outph},TraceEvent{32,outpl},TraceEvent{33,sh},TraceEvent{34,sl}]))

def general.polynomial(poly: Polynomial, zh: Value, zl: Value, +sgn: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  Polynomial{+ph,+pl,pevents} = poly
  +szh = mul(200,zh,sgn)
  +szl = mul(201,zl,sgn)
  general.product(muldd(202,szh,szl,ph,pl),mask,index,gt,append(append(events,pevents),
    [TraceEvent{27,ph},TraceEvent{28,pl},TraceEvent{29,szh},TraceEvent{30,szl}]))

def general.square(square: DoubleDouble, zh: Value, zl: Value, sgn: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  DoubleDouble{+z2h,+z2l} = square
  general.polynomial(polydd(z2h,z2l),zh,zl,sgn,mask,index,gt,
    append(events,[TraceEvent{23,z2h},TraceEvent{24,z2l}]))

def general(+num: Value, +den: Value, sgn: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  +zh = div(180,num,den)
  +zl = div(182,fma(181,zh,negate(den),num),den)
  general.square(muldd(183,zh,zl,zh,zl),zh,zl,sgn,(mask .|. 128 : U32),index,gt,
    append(events,[TraceEvent{21,zh},TraceEvent{22,zl}]))

def first.fallback(is_tiny: Bool, +y: Value, +x: Value, sgn: Value, mask: U32, index: U32, +gt: U32, events: +List<TraceEvent>) -> Packet:
  match is_tiny:
    case True{}: tiny(y,x,mask,index,gt,events)
    case False{}:
      +vertical = U32.is_ne(gt,0)
      general(Bool.pick(Value,vertical,x,y),Bool.pick(Value,vertical,y,x),sgn,mask,index,gt,events)

def first.ambiguous(ambiguous: Bool, +ay: U32, +ax: U32, y: Value, x: Value, sgn: Value, +r: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match ambiguous:
    case False{}: Packet{r,mask,index,gt,append(events,[TraceEvent{39,r}])}
    case True{}:
      first.fallback(((ay < ax) && (((ax - ay) >> 23n) >= 25) : U32),y,x,sgn,(mask .|. 4 : U32),index,gt,events)

def first.inspect(ay: U32, ax: U32, y: Value, x: Value, sgn: Value, r: Value, mask: U32, index: U32, gt: U32, events: +List<TraceEvent>) -> Packet:
  match r:
    case Failed{id,words}: Packet{Failed{id,words},mask,index,gt,events}
    case Good{F.Words{high,+low}}:
      first.ambiguous((((low + 8) .&. 268435455) <= 16 : U32),ay,ax,y,x,sgn,Good{F.Words{high,low}},mask,index,gt,events)

def first.rational(result: Evaluation, +z: Value, ay: U32, ax: U32, y: Value, x: Value, +mask: U32, +index: U32, +gt: U32) -> Packet:
  Evaluation{ratio,events} = result
  +sgn = Bool.pick(Value,U32.is_eq(gt,0),constant.one(),constant.minus_one())
  +signed_z = mul(48,z,sgn)
  +r = add(50,mul(49,signed_z,ratio),constant.offset(index))
  first.inspect(ay,ax,y,x,sgn,r,mask,index,gt,append(Con{TraceEvent{1,z},events},[TraceEvent{12,signed_z},TraceEvent{13,r}]))

def first(+ay: U32, +ax: U32, +yb: U32, +xb: U32) -> Packet:
  +y = promote(2,yb)
  +x = promote(3,xb)
  +gt = Bool.to_u32((ay > ax : U32))
  +vertical = U32.is_ne(gt,0)
  +m0 = Bool.pick(Value,vertical,constant.one(),constant.zero())
  +m1 = Bool.pick(Value,vertical,constant.zero(),constant.one())
  numerator = add(12,mul(10,m0,x),mul(11,m1,y))
  denominator = add(15,mul(13,m0,y),mul(14,m1,x))
  +z = div(16,numerator,denominator)
  # ax and ay are signed-int-safe magnitudes; absolute unsigned difference
  # is exactly the source's two-sided signed d guard.
  +distance = Bool.pick(U32,(ax >= ay : U32),(ax - ay : U32),(ay - ax : U32))
  +enabled = (distance < 226492416 : U32)
  index = (((yb >> 31n) * 4) + ((xb >> 31n) * 2) + gt : U32)
  first.rational(rational(enabled,z),z,ay,ax,y,x,Bool.pick(U32,enabled,1,2),index,gt)

def finite.zero(negative_x: Bool, +index: U32) -> Packet:
  match negative_x:
    case False{}: Packet{constant.offset(index),2048,0,0,Nil{}}
    case True{}: Packet{add(4,constant.offset(index),constant.offset_low(index)),2048,0,0,Nil{}}

def finite.ready(early: Bool, ay: U32, ax: U32, +yb: U32, +xb: U32) -> Packet:
  match early:
    case False{}: first(ay,ax,yb,xb)
    case True{}:
      index = (((yb >> 31n) * 4) + ((xb >> 31n) * 2) : U32)
      finite.zero((xb >= 2147483648 : U32),index)

def finite(+yb: U32, +xb: U32) -> Packet:
  +ay = (yb .&. 2147483647 : U32)
  +ax = (xb .&. 2147483647 : U32)
  early = U32.is_eq(ay,0) && (U32.is_eq(ax,0) || (xb < 2147483648 : U32))
  finite.ready(early,ay,ax,yb,xb)

def traced.valid(valid: Bool, yb: U32, xb: U32) -> Packet:
  match valid:
    case False{}: Packet{Failed{1,[yb,xb]},4096,0,0,Nil{}}
    case True{}: finite(yb,xb)

# All finite raw binary32 pairs, including subnormals and signed zero. Specials
# are rejected before promotion/reduction. Arithmetic rejection remains explicit.
def traced(+yb: U32, +xb: U32) -> Packet:
  traced.valid((((yb .&. 2147483647) < 2139095040) && ((xb .&. 2147483647) < 2139095040) : U32),yb,xb)

def checked.packet(packet: Packet) -> Maybe<U32>:
  Packet{value,_,_,_,_} = packet
  narrow(value)

def checked(yb: U32, xb: U32) -> Maybe<U32>:
  checked.packet(traced(yb,xb))
