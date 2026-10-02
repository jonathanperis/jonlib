#!/usr/bin/env python3
"""Fresh checked-angle raw-word gate; never reuse a qualification receipt.

Modern accepted words come from actual original raymath calls in a freshly
qualified native context. Exact rational arithmetic independently checks every
ordered pre-scalar intermediate and rejection stage. The unmodified pinned
scalar source is an additional cross-check, not a Bend-derived expectation.
Apple/Sun comparisons establish compatibility with the retained old APIs only.
The historical 1,086-scalar regression remains a separate gate.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

import angle_manifest_audit as rational
import angle_reference as qualification
import conformance
import modern_angle_probe as common
import modern_angle_reference as pinned

ROOT = conformance.ROOT
CHUNK = 64
CORPUS_SHA256 = '5ce3b55c06361617b3f1f431bf19ca326af5833099823baeaf2f26b6781216d9'
LANES = common.LANES
PROFILES = qualification.PROFILES
APIS = ('Vector2Angle', 'Vector2LineAngle', 'Vector3Angle')
ARITIES = (4, 4, 6)
STAGES = ({1, 2, *range(10, 16), 31, 32}, {1, 2, 10, 11, 31, 32, 33},
          {1, 2, *range(10, 33)})
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
         '-ffp-contract=off', '-fno-lto', '-fno-builtin-atan2f', '-fno-builtin-fma']
DEPENDENCIES = ('tools/checked_angle_probe.py', 'tests/test_checked_angle.py',
                'tools/angle_reference.py', 'tools/angle_manifest_audit.py',
                'tools/modern_angle_probe.py', 'tools/modern_angle_reference.py',
                'tools/conformance.py', 'toolchain.json', 'LAWS.bend', 'PROOF.bend')
word = common.word
strict_json = common.strict_json
digest = common.digest
lane_commands = common.lane_commands
retain_artifacts = common.retain_artifacts
assert_artifacts_unchanged = common.assert_artifacts_unchanged


def normal(value):
    magnitude = word(value) & 0x7fffffff
    return magnitude == 0 or 0x00800000 <= magnitude < 0x7f800000


def finite(value):
    return (word(value) & 0x7fffffff) < 0x7f800000


def validate_rows(rows):
    if type(rows) is not list or not rows:
        raise ValueError('Expected nonempty raw-word input list')
    ids = set(); labels = set()
    for row in rows:
        if type(row) is not dict or set(row) != {'id', 'api', 'args', 'label', 'frozen'}:
            raise ValueError('Malformed raw-word input record')
        word(row['id']); word(row['api'])
        if row['id'] in ids or row['api'] >= len(APIS):
            raise ValueError('Duplicate input ID or unknown API')
        ids.add(row['id'])
        if type(row['args']) is not list or len(row['args']) != ARITIES[row['api']]:
            raise ValueError('Wrong raw-input arity')
        for value in row['args']: word(value)
        if type(row['label']) is not str or not row['label'] or row['label'] in labels:
            raise ValueError('Missing or duplicate stable control label')
        labels.add(row['label'])
        if row['frozen'] is not None and (type(row['frozen']) is not dict or
                set(row['frozen']) != set(PROFILES) or any(type(v) is not int for v in row['frozen'].values())):
            raise ValueError('Malformed independent frozen expectations')
        for value in (row['frozen'] or {}).values(): word(value)


def round32(value, zero=0):
    """Exact RN-even, including overflow and gradual underflow; no host float."""
    if not value: return zero
    sign = 0x80000000 if value < 0 else 0
    value = abs(value)
    # Midpoint between maxfinite and the next exponent's exact power of two.
    if value >= Fraction(2)**128 - Fraction(2)**103:
        return sign | 0x7f800000
    if value > rational.fp(0x7f7fffff): return sign | 0x7f7fffff
    return rational.rn(-value if sign else value)


def multiply(a, b):
    return round32(rational.fp(a)*rational.fp(b), (a ^ b) & 0x80000000)


def add(a, b):
    return round32(rational.fp(a)+rational.fp(b), 0x80000000 if a == b == 0x80000000 else 0)


def subtract(a, b):
    return add(a, b ^ 0x80000000)


def square_root(value):
    if value & 0x7fffffff == 0: return value
    target = rational.fp(value)
    if target < 0: raise ValueError('Negative rational square root')
    lo, hi = 0, 0x7f7fffff
    while lo < hi:
        mid = (lo+hi+1)//2
        if rational.fp(mid)**2 <= target: lo = mid
        else: hi = mid-1
    midpoint = (rational.fp(lo)+rational.fp(lo+1))/2
    return lo if target < midpoint**2 or (target == midpoint**2 and lo % 2 == 0) else lo+1


def domain(row):
    """Return (first failure stage, checked trace, effective atan2 pair)."""
    a = row['args']; trace = []
    if not all(finite(value) for value in a): return 1, trace, None
    class Rejected(Exception): pass
    def check(stage, value):
        trace.append([stage, value])
        if not normal(value): raise Rejected(stage)
        return value
    try:
        if row['api'] == 0:
            x,y,u,v = a
            p0=check(10,multiply(x,u)); p1=check(11,multiply(y,v)); dot=check(12,add(p0,p1))
            q0=check(13,multiply(x,v)); q1=check(14,multiply(y,u)); det=check(15,subtract(q0,q1))
            pair=[det,dot]
        elif row['api'] == 1:
            x,y,u,v=a
            pair=[check(10,subtract(v,y)),check(11,subtract(u,x))]
        elif row['api'] == 2:
            x,y,z,u,v,w=a
            products=[check(stage,multiply(a[i],a[j])) for stage,(i,j) in
                      enumerate(((1,5),(2,4),(2,3),(0,5),(0,4),(1,3)),10)]
            cross=[check(stage,subtract(products[i],products[i+1])) for stage,i in enumerate((0,2,4),16)]
            squares=[check(stage,multiply(value,value)) for stage,value in enumerate(cross,19)]
            sxy=check(22,add(squares[0],squares[1])); square=check(23,add(sxy,squares[2]))
            length=check(25,square_root(square))
            p0=check(26,multiply(x,u)); p1=check(27,multiply(y,v)); p2=check(28,multiply(z,w))
            dxy=check(29,add(p0,p1)); dot=check(30,add(dxy,p2)); pair=[length,dot]
        else: raise ValueError('Unknown raw wrapper API')
        return 0, trace, pair
    except Rejected as error:
        return error.args[0], trace, None


def samples():
    manifest = qualification.load_manifest()
    rational.audit(manifest)
    rows=[]
    def put(api,args,label,frozen=None):
        rows.append(dict(id=len(rows),api=api,args=list(args),label=label,frozen=frozen))
    for row in manifest['wrapper_controls']:
        put(APIS.index(row['api']),[int(value,16) for value in row['args']],
            'frozen-'+row['id'],{key:int(value,16) for key,value in row['expected'].items()})
    one=0x3f800000; half=0x3f000000; minimum=0x00800000; maximum=0x7f7fffff
    for api,arity in enumerate(ARITIES):
        for signs in itertools.product((0,0x80000000),repeat=arity):
            put(api,signs,'all-signed-zeros-%d-%s'%(api,''.join('1' if v else '0' for v in signs)))
        for position in range(arity):
            for special in (0x7f800000,0xff800000,0x7fc00000,0xffc00001,0x7f800001,0xff800001):
                args=[one]*arity; args[position]=special
                put(api,args,f'nonfinite-api{api}-field{position}-{special:08x}')
    controls=[
        (0,[minimum,one,half,one],'v2-dot-product-10'),
        (0,[0,minimum,0,half],'v2-dot-product-11'),
        (0,[minimum,minimum,one,0xbf800001],'v2-dot-cancellation-12'),
        (0,[minimum,one,one,half],'v2-det-product-13'),
        (0,[one,minimum,half,one],'v2-det-product-14'),
        (0,[minimum,minimum,one,0x3f800001],'v2-det-cancellation-15'),
        (0,[maximum,0,0x40000000,one],'v2-product-overflow'),
        (0,[maximum,maximum,one,one],'v2-dot-overflow'),
        (0,[maximum,maximum,0xbf800000,one],'v2-det-overflow'),
        (0,[0x3f800001,one,one,0x3f7ffffe],'fma-sensitive-determinant'),
        (1,[0,0,0x7f000000,one],'output-only-subnormal'),
        (1,[0,0,0x7f000000,minimum],'accepted-tiny-negative-zero'),
        (1,[one,minimum,0x40000000,minimum+1],'line-subnormal-dy'),
        (1,[minimum,0,minimum+1,one],'line-subnormal-dx'),
        (1,[maximum^0x80000000,0,maximum,one],'line-overflow-dx'),
        (1,[0,maximum^0x80000000,one,maximum],'line-overflow-dy'),
        (2,[0,0,one,0x5f400000,0xdf400000,0],'v3-first-length-sum-overflow-22'),
        (2,[one,0xbf800000,0,0x5f200000,0,0xdf200000],'v3-final-length-sum-overflow-23'),
        (2,[0,minimum,minimum,0,one,0x3f800001],'v3-cross-cancellation-16'),
        (2,[minimum,0,minimum,0x3f800001,0,one],'v3-cross-cancellation-17'),
        (2,[minimum,minimum,0,one,0x3f800001,0],'v3-cross-cancellation-18'),
        (2,[0,one,0,0,0,0x1c800000],'v3-square-subnormal-19'),
        (2,[0,0,one,0x1c800000,0,0],'v3-square-subnormal-20'),
        (2,[one,0,0,one,0x1c800000,0],'v3-square-subnormal-21'),
        (2,[one,0,0,0,0x62800000,0],'v3-square-overflow'),
        (2,[maximum,0,0,maximum,0,0],'v3-dot-overflow-26'),
        (2,[0,maximum,0,0,maximum,0],'v3-dot-overflow-27'),
        (2,[0,0,maximum,0,0,maximum],'v3-dot-overflow-28'),
        (2,[maximum,maximum,0,one,one,0],'v3-dot-sum-overflow-29'),
        (2,[0x7effffff]*3+[one]*3,'v3-dot-sum-overflow-30'),
        (2,[0xcb800000,0x4b800000,one,one,one,one],'left-associated-dot'),
        (2,[0,one,0xbf800000,0xb9800000,0x3f5364be,0x3ea6c97c],'left-associated-squares'),
        (0,[1,0,0,0],'subnormal-input-accepted-zero-products'),
        (0,[1,0,0x7e800000,0],'subnormal-input-accepted-normal-product'),
        (0,[minimum,0,minimum,0],'underflow-to-zero-allowed'),
        (2,[1,0,0,0,0,0],'v3-subnormal-input-accepted-zero-products'),
        (1,[1,0,0x00800001,one],'line-subnormal-input-normal-difference'),
    ]
    for stage,(i,j) in enumerate(((1,5),(2,4),(2,3),(0,5),(0,4),(1,3)),10):
        args=[0]*6; args[i]=minimum; args[j]=half
        controls.append((2,args,f'v3-cross-product-subnormal-{stage}'))
    for api,args,label in controls: put(api,args,label)
    validate_corpus(rows)
    return rows


def validate_corpus(rows):
    validate_rows(rows)
    fingerprint=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if len(rows)!=428 or fingerprint!=CORPUS_SHA256:
        raise ValueError('Required raw wrapper corpus/label/frozen-control drift')
    if [row['id'] for row in rows]!=list(range(len(rows))):
        raise ValueError('Full corpus IDs must be contiguous and ordered')
    required=({1,*range(10,16)}, {1,10,11}, {1,*range(10,24),*range(26,31)})
    for api,stages in enumerate(required):
        actual={domain(row)[0] for row in rows if row['api']==api}-{0}
        if actual!=stages: raise ValueError('Incomplete reachable arithmetic stage coverage')


def validate_coverage(rows,records):
    validate_corpus(rows)
    if type(records) is not list or len(records)!=len(rows):
        raise ValueError('Incomplete native wrapper coverage')
    lookup={row['label']:record for row,record in zip(rows,records)}
    for row,record in zip(rows,records):
        if record['id']!=row['id']: raise ValueError('Native coverage ID/order mismatch')
    if [lookup['output-only-subnormal'][key] for key in ('tag','stage','word')]!=[0,32,0]:
        raise ValueError('Output-only rejection control missing')
    if [lookup['accepted-tiny-negative-zero'][key] for key in ('tag','stage','word')]!=[1,0,0x80000000]:
        raise ValueError('Accepted underflow negative-zero control missing')
    for label in ('subnormal-input-accepted-zero-products','subnormal-input-accepted-normal-product',
                  'underflow-to-zero-allowed','v3-subnormal-input-accepted-zero-products',
                  'line-subnormal-input-normal-difference','fma-sensitive-determinant',
                  'left-associated-dot','left-associated-squares'):
        if lookup[label]['tag']!=1: raise ValueError('Required accepted control rejected: '+label)
    return dict(accepted=sum(row['tag'] for row in records),rejected=sum(not row['tag'] for row in records),
        rejection_stages=dict(Counter(str(row['stage']) for row in records if not row['tag'])),
        native_wrapper_calls=len(records),frozen_controls=sum(row['frozen'] is not None for row in rows),
        corpus_sha256=CORPUS_SHA256,required_strata_covered=True,
        synthetic_scope='impossible-helper paths kept separate from reachable wrapper stages')


def parse_record(value, row):
    if type(value) is not list or len(value) != 14:
        raise ValueError('Wrong candidate shape/count')
    for item in value: word(item)
    if value[0] != row['id']: raise ValueError('Wrong candidate ID/order')
    tag,stage,result=value[1:4]
    if tag not in (0,1) or (tag and (stage or not normal(result))) or (not tag and (stage not in STAGES[row['api']] or result)):
        raise ValueError('Invalid private result tag/stage/payload')
    for offset in (4,6,8):
        present,payload=value[offset:offset+2]
        if present not in (0,1) or (not present and payload) or (present and not normal(payload)):
            raise ValueError('Invalid public Maybe framing')
    if value[4:6] != [tag,result]: raise ValueError('Public modern/private result disagreement')
    legacy=value[10]
    if legacy not in (0,1) or (not legacy and any(value[11:])):
        raise ValueError('Invalid legacy diagnostic framing')
    if legacy:
        if not all(finite(v) for v in value[11:]) or value[11] != value[13]:
            raise ValueError('Legacy default changed or nonfinite compatibility result')
        for offset,old in ((6,value[11]),(8,value[12])):
            if value[offset:offset+2] != ([1,old] if normal(old) else [0,0]):
                raise ValueError('Checked historical profile differs from retained old API')
    elif any(value[4:10]):
        raise ValueError('Pre-scalar rejection accepted in a public profile')
    return value


def parse_output(output, rows):
    validate_rows(rows)
    if type(output) is not str or len(output.splitlines()) != len(rows):
        raise ValueError('Wrong candidate line count/framing')
    return [parse_record(strict_json(line),row) for line,row in zip(output.splitlines(),rows)]


def parse_native(output, rows):
    validate_rows(rows)
    if type(output) is not str or len(output.splitlines()) != len(rows):
        raise ValueError('Wrong native line count/framing')
    records=[]
    for line,row in zip(output.splitlines(),rows):
        value=strict_json(line)
        if type(value) is not list: raise ValueError('Malformed native frame')
        for item in value: word(item)
        arity=len(row['args']); header=[row['id'],row['api'],arity,*row['args']]
        if value[:len(header)] != header or len(value) < len(header)+6:
            raise ValueError('Native input ID/API/word/order mismatch')
        offset=len(header); tag,stage,result,actual,scalar,count=value[offset:offset+6]
        if count > 32 or len(value) != offset+6+2*count:
            raise ValueError('Native trace count/framing mismatch')
        trace=[value[index:index+2] for index in range(offset+6,len(value),2)]
        fail,expected,pair=domain(row)
        if fail:
            if [tag,stage,result,scalar] != [0,fail,0,0] or trace != expected:
                raise ValueError('Native rejection/stage/trace contradicts exact rational domain')
        else:
            if not finite(scalar): raise ValueError('Pinned finite scalar returned nonfinite word')
            final=scalar ^ (0x80000000 if row['api']==1 else 0)
            expected=expected+[[32,scalar]]
            if normal(scalar):
                if row['api']==1: expected.append([33,final])
                wanted=[1,0,actual]
            else: wanted=[0,32,0]
            if [tag,stage,result] != wanted or trace != expected or actual != final:
                raise ValueError('Original raymath/pinned scalar/domain disagreement')
            if row['frozen'] is not None and actual != row['frozen']['Glibc241AngleRn']:
                raise ValueError('Original raymath differs from independent frozen wrapper control')
        records.append(dict(id=row['id'],tag=tag,stage=stage,word=result,actual=actual,
                            scalar=scalar,trace=trace,pre_scalar_valid=pair is not None))
    return records


def compare(rows, native, actual):
    validate_rows(rows)
    if type(native) is not list or type(actual) is not list or len(rows)!=len(native) or len(rows)!=len(actual):
        raise ValueError('Incomplete wrapper comparison')
    for row,expected,value in zip(rows,native,actual):
        parse_record(value,row)
        if type(expected) is not dict or set(expected) != {'id','tag','stage','word','actual','scalar','trace','pre_scalar_valid'}:
            raise ValueError('Malformed native observation')
        for field in ('id','tag','stage','word','actual','scalar'): word(expected[field])
        if type(expected['trace']) is not list or any(type(pair) is not list or len(pair)!=2 for pair in expected['trace']):
            raise ValueError('Malformed native trace')
        for pair in expected['trace']:
            for item in pair: word(item)
        if expected['id'] != row['id'] or value[1:4] != [expected['tag'],expected['stage'],expected['word']]:
            raise ValueError('Exact modern acceptance/stage/word mismatch: '+row['label'])
        if type(expected['pre_scalar_valid']) is not bool or value[10] != int(expected['pre_scalar_valid']):
            raise ValueError('Legacy compatibility scope mismatch')
        if value[10] and row['frozen'] is not None:
            if value[11:13] != [row['frozen'][name] for name in PROFILES[:2]]:
                raise ValueError('Historical old-API/frozen control mismatch: '+row['label'])


def _imports(import_root):
    if type(import_root) is not str or not re.fullmatch(r'[./A-Za-z0-9_-]+',import_root):
        raise ValueError('Unsafe relative import root')
    return f'import Base\nimport {import_root}/jonmath.bend as M\nimport {import_root}/src/checked_angle.bend as C\n'


def program(rows, import_root='../..'):
    validate_rows(rows)
    if len(rows)>CHUNK: raise ValueError('Candidate exceeds bounded serial chunk limit')
    source=_imports(import_root)+'''def raw(value: U32) -> F32:
  U32{bits} = value
  F32{bits}
def pack(value: Result<&2, &2, U32, F32>, rest: List<U32>) -> List<U32>:
  match value:
    case Fail{stage}: Con{0, Con{stage, Con{0, rest}}}
    case Done{value}: Con{1, Con{0, Con{F32.bits(value), rest}}}
def maybe(value: Maybe<F32>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{0, Con{0, rest}}
    case Some{value}: Con{1, Con{F32.bits(value), rest}}
type Task is Data:
  Task{id: U32, api: U32, legacy: U32, x: U32, y: U32, z: U32, u: U32, v: U32, w: U32}
def legacy2(enabled: U32, line: U32, +left: M.Vector2, +right: M.Vector2) -> List<U32>:
  match enabled:
    case 0: [0,0,0,0]
    case _:
      match line:
        case 0: [1,F32.bits(M.Vector2.angle_for(M.AccurateGradient{},left,right)),F32.bits(M.Vector2.angle_for(M.GnuGradient{},left,right)),F32.bits(M.Vector2.angle(left,right))]
        case _: [1,F32.bits(M.Vector2.line_angle_for(M.AccurateGradient{},left,right)),F32.bits(M.Vector2.line_angle_for(M.GnuGradient{},left,right)),F32.bits(M.Vector2.line_angle(left,right))]
def legacy3(enabled: U32, +left: M.Vector3, +right: M.Vector3) -> List<U32>:
  match enabled:
    case 0: [0,0,0,0]
    case _: [1,F32.bits(M.Vector3.angle_for(M.AccurateGradient{},left,right)),F32.bits(M.Vector3.angle_for(M.GnuGradient{},left,right)),F32.bits(M.Vector3.angle(left,right))]
def observe.api(api: U32, id: U32, legacy: U32, +x: F32, +y: F32, +z: F32, +u: F32, +v: F32, +w: F32) -> List<U32>:
  match api:
    case 0:
      +left = {M.Vector2{x,y} : M.Vector2}
      +right = {M.Vector2{u,v} : M.Vector2}
      rest = legacy2(legacy,0,left,right)
      rest = maybe(M.Vector2.angle_with_reference(M.Sun239AngleRn{},left,right),rest)
      rest = maybe(M.Vector2.angle_with_reference(M.Apple2007AngleRn{},left,right),rest)
      rest = maybe(M.Vector2.angle_with_reference(M.Glibc241AngleRn{},left,right),rest)
      Con{id,pack(C.vector2(2,x,y,u,v),rest)}
    case 1:
      +left = {M.Vector2{x,y} : M.Vector2}
      +right = {M.Vector2{u,v} : M.Vector2}
      rest = legacy2(legacy,1,left,right)
      rest = maybe(M.Vector2.line_angle_with_reference(M.Sun239AngleRn{},left,right),rest)
      rest = maybe(M.Vector2.line_angle_with_reference(M.Apple2007AngleRn{},left,right),rest)
      rest = maybe(M.Vector2.line_angle_with_reference(M.Glibc241AngleRn{},left,right),rest)
      Con{id,pack(C.line(2,x,y,u,v),rest)}
    case _:
      +left = {M.Vector3{x,y,z} : M.Vector3}
      +right = {M.Vector3{u,v,w} : M.Vector3}
      rest = legacy3(legacy,left,right)
      rest = maybe(M.Vector3.angle_with_reference(M.Sun239AngleRn{},left,right),rest)
      rest = maybe(M.Vector3.angle_with_reference(M.Apple2007AngleRn{},left,right),rest)
      rest = maybe(M.Vector3.angle_with_reference(M.Glibc241AngleRn{},left,right),rest)
      Con{id,pack(C.vector3(2,x,y,z,u,v,w),rest)}
def observe(task: Task) -> List<U32>:
  Task{id,api,legacy,x,y,z,u,v,w} = task
  observe.api(api,id,legacy,raw(x),raw(y),raw(z),raw(u),raw(v),raw(w))
def emit(tasks: +List<Task>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{task,rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, observe(task)))
        emit(rest)
def main() -> IO(Unit):
  emit(['''
    values=[]
    for row in rows:
        args=row['args'] if row['api']==2 else [*row['args'][:2],0,*row['args'][2:],0]
        values.append('Task{'+','.join(map(str,[row['id'],row['api'],int(domain(row)[0]==0),*args]))+'}')
    return source+','.join(values)+'])\n'


def synthetic_cases():
    cases=[]
    def put(label,expression,tag,stage,value=0):
        cases.append(dict(id=len(cases),label=label,expression=expression,expected=[len(cases),tag,stage,value]))
    put('injected-scalar-none','C.scalar_result(None{})',0,31)
    for value in (1,0x80000001,0x7f800000,0xff800000,0x7fc00001,0x7f800001):
        put(f'invalid-successful-scalar-{value:08x}',f'C.scalar_result(Some{{{value}}})',0,32)
    for value in (0xbf800000,0x80800000,1,0x7f800000,0xff800000,0x7fc00001,0x7f800001):
        put(f'synthetic-invalid-square-{value:08x}',f'C.sqrt(raw({value}))',0,24)
    for value in (0,0x80000000,0x3f800000,0x00800000):
        put(f'sqrt-valid-{value:08x}',f'C.sqrt(raw({value}))',1,0,square_root(value))
    for stage in range(10,34):
        put(f'synthetic-stage-guard-{stage}',f'C.normal({stage},raw(1))',0,stage)
    for name,args in (('vector2','raw(0),raw(0),raw(0),raw(0)'),
                      ('line','raw(0),raw(0),raw(0),raw(0)'),
                      ('vector3',','.join(['raw(0)']*6))):
        put('invalid-profile-'+name,f'C.{name}(3,{args})',0,2)
    return cases


def synthetic_program(cases,import_root='../..'):
    if type(cases) is not list or not 0<len(cases)<=CHUNK: raise ValueError('Invalid synthetic chunk count')
    prefix=program([dict(id=0,api=0,args=[0]*4,label='header',frozen=None)],import_root).split('def maybe(')[0]
    source=prefix+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','label','expression','expected'} or case['id'] in ids:
            raise ValueError('Malformed synthetic case')
        word(case['id']); ids.add(case['id'])
        source+=f'    IO.print(List.show(~&1, ~U32, ~U32.show, Con{{{case["id"]},pack({case["expression"]},Nil{{}})}}))\n'
    return source


def parse_synthetic(output,cases):
    if type(output) is not str or len(output.splitlines())!=len(cases): raise ValueError('Wrong synthetic framing')
    actual=[]
    for line,case in zip(output.splitlines(),cases):
        value=strict_json(line)
        if type(value) is not list or len(value)!=4: raise ValueError('Wrong synthetic result shape')
        for item in value: word(item)
        if value!=case['expected']: raise ValueError('Synthetic helper result mismatch: '+case['label'])
        actual.append(value)
    return actual


def native_source(rows):
    validate_rows(rows)
    table=[]
    for row in rows:
        table.append('{'+','.join(str(value)+'u' for value in [row['id'],row['api'],*row['args'],*([0]*(6-len(row['args'])))])+'}')
    return r'''/* Generated raw-input diagnostic; original raymath calls remain intact. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#pragma STDC FENV_ACCESS ON
#pragma STDC FP_CONTRACT OFF
#include "raymath.h"
extern float aq_pinned_atan2f(float,float);
static uint32_t bits(float x) { uint32_t w; memcpy(&w,&x,4); return w; }
static float raw(uint32_t w) { float x; memcpy(&x,&w,4); return x; }
static int normal(float x) { uint32_t w=bits(x)&0x7fffffffu; return !w || (w>=0x00800000u && w<0x7f800000u); }
typedef struct { uint32_t tag,stage,value,scalar,count,trace[64]; } Observation;
static int take(Observation *r,uint32_t stage,float value) {
  r->trace[2*r->count]=stage; r->trace[2*r->count+1]=bits(value); ++r->count;
  if (!normal(value)) { r->stage=stage; return 0; } return 1;
}
#define STEP(name,stage,expression) float name=(expression); if (!take(&r,stage,name)) goto finish
static Observation ordered(uint32_t api, const uint32_t *words) {
  Observation r={0};
  for (unsigned i=0;i<(api==2?6u:4u);++i)
    if ((words[i]&0x7fffffffu)>=0x7f800000u) { r.stage=1; return r; }
  float yarg=0,xarg=0;
  if (api==0) {
    float x=raw(words[0]),y=raw(words[1]),u=raw(words[2]),v=raw(words[3]);
    STEP(p0,10,x*u); STEP(p1,11,y*v); STEP(dot,12,p0+p1);
    STEP(q0,13,x*v); STEP(q1,14,y*u); STEP(det,15,q0-q1);
    yarg=det; xarg=dot;
  } else if (api==1) {
    float x=raw(words[0]),y=raw(words[1]),u=raw(words[2]),v=raw(words[3]);
    STEP(dy,10,v-y); STEP(dx,11,u-x); yarg=dy; xarg=dx;
  } else {
    float x=raw(words[0]),y=raw(words[1]),z=raw(words[2]),u=raw(words[3]),v=raw(words[4]),w=raw(words[5]);
    STEP(a0,10,y*w); STEP(a1,11,z*v); STEP(b0,12,z*u); STEP(b1,13,x*w); STEP(c0,14,x*v); STEP(c1,15,y*u);
    STEP(cx,16,a0-a1); STEP(cy,17,b0-b1); STEP(cz,18,c0-c1);
    STEP(sx,19,cx*cx); STEP(sy,20,cy*cy); STEP(sz,21,cz*cz);
    STEP(sxy,22,sx+sy); STEP(square,23,sxy+sz);
    if (!(square>=0.0f)) { r.stage=24; goto finish; }
    STEP(length,25,sqrtf(square));
    STEP(p0,26,x*u); STEP(p1,27,y*v); STEP(p2,28,z*w);
    STEP(dxy,29,p0+p1); STEP(dot,30,dxy+p2); yarg=length; xarg=dot;
  }
  {
    float scalar=aq_pinned_atan2f(yarg,xarg); r.scalar=bits(scalar);
    if (!take(&r,32,scalar)) goto finish;
    float result=scalar;
    if (api==1) { result=-scalar; if (!take(&r,33,result)) goto finish; }
    r.tag=1; r.value=bits(result);
  }
finish: return r;
}
/* Separate original runtime-input wrappers, including rejected-domain diagnostics. */
__attribute__((noinline)) static float original(uint32_t api,const uint32_t *words) {
  if (api==0) { Vector2 a={raw(words[0]),raw(words[1])},b={raw(words[2]),raw(words[3])}; return Vector2Angle(a,b); }
  if (api==1) { Vector2 a={raw(words[0]),raw(words[1])},b={raw(words[2]),raw(words[3])}; return Vector2LineAngle(a,b); }
  Vector3 a={raw(words[0]),raw(words[1]),raw(words[2])},b={raw(words[3]),raw(words[4]),raw(words[5])};
  return Vector3Angle(a,b);
}
static volatile uint32_t inputs[][8]={''' + ',\n'.join(table) + r'''};
int main(void) {
  for (unsigned row=0;row<sizeof(inputs)/sizeof(inputs[0]);++row) {
    uint32_t values[8]; for (unsigned i=0;i<8;++i) values[i]=inputs[row][i];
    uint32_t id=values[0],api=values[1],arity=api==2?6u:4u;
    Observation r=ordered(api,values+2);
    uint32_t actual=bits(original(api,values+2));
    printf("[%u,%u,%u",id,api,arity);
    for (unsigned i=0;i<arity;++i) printf(",%u",values[i+2]);
    printf(",%u,%u,%u,%u,%u,%u",r.tag,r.stage,r.value,actual,r.scalar,r.count);
    for (unsigned i=0;i<2*r.count;++i) printf(",%u",r.trace[i]);
    puts("]");
  }
  return 0;
}
'''


def write_json(path,value):
    temporary=path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n')
    temporary.replace(path)


def execute(command,work,name,timeout=600,env=None,report=None):
    command=[str(part) for part in command]
    record=dict(name=name,argv=command,completed=False)
    if report is not None: report.setdefault('commands',[]).append(record)
    for suffix in ('stdout','stderr'): (work/(name+'.'+suffix)).unlink(missing_ok=True)
    stdout=stderr=''
    try:
        process=subprocess.run(command,cwd=ROOT,env=dict(os.environ,BEND_NO_TELEMETRY='1',**(env or {})),
                               text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
        stdout,stderr=process.stdout,process.stderr
        if type(stdout) is not str or type(stderr) is not str: raise ValueError('Command output must be text')
        record['returncode']=process.returncode
        if process.returncode: raise ValueError(f'{name} exited {process.returncode}')
        record['completed']=True
        return stdout
    except subprocess.TimeoutExpired as error:
        def decode(value): return value.decode(errors='replace') if isinstance(value,bytes) else value or ''
        stdout,stderr=decode(error.stdout),decode(error.stderr)
        raise
    finally:
        for suffix,value in (('stdout',stdout),('stderr',stderr)):
            (work/(name+'.'+suffix)).write_text(value)


def compile_fresh(command,outputs,work,name,**kwargs):
    for output in outputs: output.unlink(missing_ok=True)
    execute(command,work,name,**kwargs)
    if any(not path.is_file() or path.stat().st_size==0 for path in outputs):
        raise ValueError('Compiler did not produce fresh nonempty outputs')


def source_hashes(lock):
    result=dict(conformance.source_gate())
    paths=set(DEPENDENCIES)
    paths.update(str(path.relative_to(ROOT)) for path in (ROOT/'tools/reference').rglob('*') if path.is_file())
    paths.update(str(path.relative_to(ROOT)) for path in pinned.source_paths())
    if lock['bend'].get('patch'): paths.add(lock['bend']['patch']['path'])
    for path in sorted(paths): result[path]=digest(ROOT/path)
    return result


def assert_qualification(receipt,started_at):
    if (type(receipt) is not dict or receipt.get('qualified') is not True or
            receipt.get('selected_profile')!='Glibc241AngleRn' or receipt.get('phase')!='qualified' or
            receipt.get('matching_profiles')!=['Glibc241AngleRn'] or
            receipt.get('candidate_executed') is not False or
            type(receipt.get('run_id')) is not str or not receipt['run_id']):
        raise ValueError('Fresh unambiguous modern native qualification required')
    try:
        if datetime.fromisoformat(receipt['started_at']) < datetime.fromisoformat(started_at):
            raise ValueError('Stale native qualification receipt')
    except (KeyError,TypeError): raise ValueError('Missing qualification timestamp') from None
    if type(receipt.get('contexts')) is not dict or not receipt['contexts']:
        raise ValueError('Missing qualified process contexts')
    assert_receipt_artifacts(receipt)


def assert_receipt_artifacts(receipt):
    artifacts=receipt.get('artifacts')
    if type(artifacts) is not dict or not artifacts: raise ValueError('Missing qualification artifact evidence')
    for name,expected in artifacts.items():
        if type(name) is not str or not Path(name).is_absolute() or type(expected) is not str or not re.fullmatch('[0-9a-f]{64}',expected):
            raise ValueError('Malformed qualification artifact hash')
        if digest(name)!=expected: raise ValueError('Qualification artifact drift: '+name)


def check_context(stderr,receipt):
    context=qualification.parse_context(stderr)
    meta=context['initial']
    def stable(value):
        value=dict(value); value.pop('kind')
        if value['architecture']=='x86_64': value['control'] &= ~63
        return value
    for qualified in receipt['contexts'].values():
        if stable(meta)!=stable(qualified['initial']): raise ValueError('Raw wrapper process differs from fresh qualification')
        library=qualified['library']
        if digest(meta['library_realpath'])!=library['sha256']:
            raise ValueError('Loaded native library drift')
    path=Path(meta['library_realpath']); status=path.stat()
    observed=[status.st_dev,status.st_ino,status.st_size,status.st_mtime_ns//10**9,status.st_mtime_ns%10**9]
    if observed!=meta['library_stat'] or Path(meta['library_path']).resolve()!=path or path.resolve()!=path:
        raise ValueError('Loaded native library identity/stat drift')
    return context


def native_reference(rows,work,receipt,timeout=600,report=None):
    work.mkdir(parents=True,exist_ok=True)
    report={} if report is None else report
    pinned.assert_pins()
    compiler=receipt['compiler']['path']
    source=work/'raw-wrappers.c'; source.write_text(native_source(rows))
    include=work/'include'; include.mkdir(exist_ok=True)
    (include/'libm-alias-finite.h').write_text('#define libm_alias_finite(a,b)\n')
    (include/'math_config.h').write_text('#include "modern_atan2f_shim.h"\n')
    context=work/'context.o'; scalar=work/'pinned.o'; binary=work/'raw-wrappers'
    commands=(
        ('context-compile',[compiler,*FLAGS,'-c',qualification.REFERENCE/'angle_qualification_context.c','-o',context],[context]),
        ('scalar-compile',[compiler,*FLAGS,'-I'+str(include),'-I'+str(qualification.REFERENCE),
            '-D__ieee754_atan2f=aq_pinned_atan2f','-c',qualification.REFERENCE/'modern_atan2f_glibc241.c','-o',scalar],[scalar]),
        ('wrapper-compile',[compiler,*FLAGS,'-I'+str(Path(receipt['raylib']['source'])/'src'),source,context,scalar,'-lm','-ldl','-o',binary],[binary]))
    retain_artifacts(report,work,['raw-wrappers.c','include/libm-alias-finite.h','include/math_config.h'])
    for name,command,outputs in commands:
        compile_fresh(command,outputs,work,name,timeout=timeout,report=report)
        retain_artifacts(report,work,[*(str(path.relative_to(work)) for path in outputs),name+'.stdout',name+'.stderr'])
    output=execute([binary],work,'native-run',timeout=timeout,report=report)
    retain_artifacts(report,work,['native-run.stdout','native-run.stderr'])
    report['context']=check_context((work/'native-run.stderr').read_text(),receipt)
    report['flags']=FLAGS
    records=parse_native(output,rows)
    write_json(work/'observations.json',records); retain_artifacts(report,work,['observations.json'])
    return records


def run_candidates(rows,native,cases,work,cli,environment,bun,report,timeout=600):
    import_root=os.path.relpath(ROOT,work).replace(os.sep,'/')
    if not import_root.startswith('.'): import_root='./'+import_root
    totals=Counter()
    tasks=[('synthetic',synthetic_program(cases,import_root),None)]
    tasks.extend((f'candidate-{index:03}',program(rows[offset:offset+CHUNK],import_root),(offset,rows[offset:offset+CHUNK]))
                 for index,offset in enumerate(range(0,len(rows),CHUNK)))
    for name,text,selection in tasks:
        source=work/(name+'.bend'); source.write_text(text)
        retain_artifacts(report,work,[source.name])
        binary,javascript=work/name,work/(name+'.js')
        compile_fresh([*cli,source,'-o',binary,'-o',javascript],[binary,javascript],work,name+'-compile',
                      timeout=timeout,env=environment,report=report)
        retain_artifacts(report,work,[binary.name,javascript.name,name+'-compile.stdout',name+'-compile.stderr'])
        for lane,command in lane_commands(binary,javascript,bun):
            label=name+'-'+lane
            output=execute(command,work,label,timeout=timeout,report=report)
            retain_artifacts(report,work,[label+'.stdout',label+'.stderr'])
            if selection is None:
                parse_synthetic(output,cases)
                report.setdefault('synthetic',{})[lane]=dict(passed=True,checked=len(cases))
            else:
                offset,selected=selection
                compare(selected,native[offset:offset+len(selected)],parse_output(output,selected))
                totals[lane]+=len(selected)
                report['lanes'][lane]=dict(passed=False,checked=totals[lane])
        report['chunks'].append(dict(name=name,count=len(cases) if selection is None else len(selection[1]),passed=True))
        write_json(work/'results.json',report)
        print(name+': exact CPU-1/CPU-2/JavaScript observations match',flush=True)
    if set(totals)!=set(LANES) or any(count!=len(rows) for count in totals.values()):
        raise ValueError('Incomplete candidate lane coverage')


def run(args,report,report_path):
    work=report_path.parent; start=time.monotonic()
    lock=strict_json((ROOT/'toolchain.json').read_text())
    conformance.checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    sources=source_hashes(lock)
    bun=common.compiler_identity('bun',work,'bun-version')
    if bun['version']!=lock['bun']['version']: raise ValueError('Bun version differs from pinned toolchain')
    receipt=qualification.qualify(args.raylib_source,args.library,work,c_source=conformance.c_source,
                cases_from=conformance.cases_from,parse_output=conformance.parse_output,
                requested_profile='Glibc241AngleRn',timeout=args.timeout)
    assert_qualification(receipt,report['started_at'])
    compiler=common.compiler_identity(receipt['compiler']['path'],work,'compiler-version')
    if compiler['sha256']!=receipt['compiler']['sha256'] or compiler['version']!=receipt['compiler']['version']:
        raise ValueError('Compiler identity differs from fresh native qualification')
    environment=common.candidate_environment(compiler)
    rows=samples(); cases=synthetic_cases()
    write_json(work/'inputs.json',rows); write_json(work/'synthetic-inputs.json',cases)
    retain_artifacts(report,work,['inputs.json','synthetic-inputs.json','bun-version.stdout','bun-version.stderr',
                                  'compiler-version.stdout','compiler-version.stderr'])
    report.update(phase='native-raw-wrappers',qualification=receipt,sources=sources,bun=bun,compiler=compiler,
        candidate_environment=environment,observations=len(rows),synthetic_observations=len(cases),chunk_limit=CHUNK,
        scope='accepted modern original-raymath bits; exact staged rejection; old Apple/Sun/default compatibility only',
        gpu='not run; no device evidence',
        rejected_native_actual='pre-scalar/input rejections retain unconstrained original-raymath diagnostic words; scalar-reachable output-only rejection words are cross-checked against pinned source; neither is a successful checked payload or a claim native rejects; NaN payload/native invalid-domain semantics are unpromised',
        historical_scalar_regression='separate unchanged 1086-case gate',
        input_sha256=digest(work/'inputs.json'))
    write_json(report_path,report)
    native_report={}; report['raw_native']=native_report
    native=native_reference(rows,work/'raw-native',receipt,args.timeout,native_report)
    report['coverage']=validate_coverage(rows,native)
    write_json(report_path,report)
    if not args.native_only:
        report['phase']='candidate'; write_json(report_path,report)
        run_candidates(rows,native,cases,work,[bun['path'],args.bend_source/'bend2/main.ts'],environment,bun['path'],report,args.timeout)
    if source_hashes(lock)!=sources: raise ValueError('Source/harness/toolchain drift during gate')
    conformance.checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    for name,command,expected in (('bun','bun',bun),('compiler',receipt['compiler']['path'],compiler)):
        if common.compiler_identity(command,work,name+'-final-version')!=expected:
            raise ValueError('Compiler/runtime executable drift')
    if Path(shutil.which('clang') or '').absolute()!=Path(receipt['compiler']['path']) or Path(receipt['compiler']['path']).resolve()!=Path(receipt['compiler']['realpath']):
        raise ValueError('Qualified compiler path resolution drift')
    assert_receipt_artifacts(receipt); assert_artifacts_unchanged(native_report,work/'raw-native')
    assert_artifacts_unchanged(report,work)
    retain_artifacts(report,work,[name+'-final-version.'+suffix for name in ('bun','compiler') for suffix in ('stdout','stderr')])
    report.update(passed=not args.native_only,phase='native-only-complete' if args.native_only else 'complete',
                  elapsed_seconds=round(time.monotonic()-start,3),completed_at=datetime.now(timezone.utc).isoformat())
    if not args.native_only:
        for lane in report['lanes'].values(): lane['passed']=True
    write_json(report_path,report)
    return report


def report_directory(argv):
    """Find the last exact destination even after an earlier help/parse failure."""
    result=ROOT/'.build/checked-angle-probe'
    index=0
    argument_rules=argparse.ArgumentParser(add_help=False,allow_abbrev=False)
    while index<len(argv):
        value=argv[index]
        if value=='--': break
        if value.startswith('--build-dir='):
            result=Path(value.partition('=')[2])
        elif value=='--build-dir' and index+1<len(argv) and argument_rules._parse_optional(argv[index+1]) is None:
            index+=1; result=Path(argv[index])
        index+=1
    return result


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    admission_directory=report_directory(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--library',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=ROOT/'.build/checked-angle-probe')
    parser.add_argument('--timeout',type=int,default=600)
    parser.add_argument('--native-only',action='store_true')
    args=argparse.Namespace(build_dir=ROOT/'.build/checked-angle-probe')
    def admit(error=None):
        path=admission_directory.resolve()/'results.json'; path.parent.mkdir(parents=True,exist_ok=True)
        report=dict(schema=1,contract='checked-angle-raw-wrapper-v1',run_id=uuid.uuid4().hex,
                    started_at=datetime.now(timezone.utc).isoformat(),phase='argument-validation',
                    passed=False,lanes={},chunks=[],commands=[],error=None)
        if error is not None:
            report['phase']='help' if isinstance(error,SystemExit) and error.code==0 else 'argument-error'
            report['error']=dict(type=type(error).__name__,message=str(error))
        write_json(path,report); return path,report
    try:
        parser.parse_args(argv,namespace=args)
        if args.build_dir.resolve()!=admission_directory.resolve():
            parser.error('Destination admission disagrees with parsed --build-dir')
        if args.timeout<=0: parser.error('--timeout must be positive')
    except BaseException as error:
        admit(error); raise
    path,report=admit()
    try:
        result=run(args,report,path)
    except BaseException as error:
        report.update(passed=False,phase='failed',error=dict(type=type(error).__name__,message=str(error)))
        write_json(path,report); raise
    print(json.dumps({key:result[key] for key in ('passed','phase','observations')}))


if __name__=='__main__': main()
