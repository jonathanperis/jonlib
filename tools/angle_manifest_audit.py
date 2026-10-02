#!/usr/bin/env python3
"""Independent exact-rational audit of the frozen angle qualification manifest.

No atan2, native library, fixture or Bend candidate is evaluated. Scalar words
are the source-branch derivations documented in ANGLE-QUALIFICATION.md. The
wrapper audit rounds exact Fractions by binary search, independently of the
manifest preparation's exponent/quotient implementation. Only exact square-root
controls are admitted. This tool checks expectations; it never updates them.
"""
from fractions import Fraction as F
import json
import math

def fp(b):
 s=-1 if b>>31 else 1;b&=0x7fffffff;e=b>>23;n=b&0x7fffff
 if e:n|=0x800000;e-=127+23
 else:e=-149
 return s*F(n)*(F(2)**e)
def rn(x,zero=0):
 if not x:return zero
 s=0x80000000 if x<0 else 0;x=abs(x)
 lo=0;hi=0x7f7fffff
 while lo<hi:
  mid=(lo+hi+1)//2
  if fp(mid)<=x:lo=mid
  else:hi=mid-1
 a=lo;b=lo+1;da=x-fp(a);db=fp(b)-x
 return s|(a if da<db or (da==db and a%2==0) else b)
def mul(a,b):return rn(fp(a)*fp(b),(a^b)&0x80000000)
def add(a,b):return rn(fp(a)+fp(b),0x80000000 if a==b==0x80000000 else 0)
def sub(a,b):return add(a,b^0x80000000)
def sqrt(a):
 q=fp(a);
 if q<0:raise ValueError("Negative frozen square root")
 n=math.isqrt(q.numerator);d=math.isqrt(q.denominator)
 
 if n*n!=q.numerator or d*d!=q.denominator:raise ValueError("Nonexact frozen square root: "+hex(a))
 return rn(F(n,d))
def h(v):return f'{v:08x}'
def derived_scalar(row):
 y,x=int(row['y'],16),int(row['x'],16); sign=y&0x80000000
 tag=row['derivation']; negative_x=bool(x>>31)
 if tag in ('zero-y-axis','zero-origin'):
  values=[0x40490fda,0x40490fdb,0x40490fdb] if negative_x else [0]*3
 elif tag=='zero-x-axis':values=[0x3fc90fdb]*3
 elif tag=='equal-magnitude':values=[0x4016cbe4 if negative_x else 0x3f490fdb]*3
 elif tag in ('near-half-k70','sun-k60-neighbor'):
  values=[0x3fc90fdb,0x3fc90fda if negative_x else 0x3fc90fdb,0x3fc90fdb]
 elif tag=='apple-ratio-2^-22-neighbor':values=[0x40490fda if negative_x else y&0x7fffffff]*3
 else:raise ValueError('Unknown scalar branch derivation: '+tag)
 return {p:h(v^sign) for p,v in zip(('Apple2007AngleRn','Sun239AngleRn','Glibc241AngleRn'),values)}

def audit(m):
 problems=[];pairs=[]
 lookup={(r['y'],r['x']):derived_scalar(r) for r in m['scalar_controls']}
 for r in m['scalar_controls']:
  if r['expected']!=derived_scalar(r):problems.append(('scalar',r['id']))
 for r in m['wrapper_controls']:
  a=[int(x,16) for x in r['args']];v=[]
  if r['api']=='Vector2Angle':
   p=mul(a[0],a[2]);q=mul(a[1],a[3]);dot=add(p,q)
   u=mul(a[0],a[3]);w=mul(a[1],a[2]);det=sub(u,w)
   v=[p,q,dot,u,w,det];pair=[det,dot]
  elif r['api']=='Vector2LineAngle':
   v=[sub(a[3],a[1]),sub(a[2],a[0])];pair=v[:]
  else:
   p=mul(a[1],a[5]);q=mul(a[2],a[4]);x=sub(p,q)
   u=mul(a[2],a[3]);w=mul(a[0],a[5]);y=sub(u,w)
   j=mul(a[0],a[4]);k=mul(a[1],a[3]);z=sub(j,k)
   xx=mul(x,x);yy=mul(y,y);zz=mul(z,z);xy=add(xx,yy);xyz=add(xy,zz);length=sqrt(xyz)
   p0=mul(a[0],a[3]);p1=mul(a[1],a[4]);p01=add(p0,p1);p2=mul(a[2],a[5]);dot=add(p01,p2)
   v=[p,q,x,u,w,y,j,k,z,xx,yy,zz,xy,xyz,length,p0,p1,p01,p2,dot];pair=[length,dot]
  if [h(x) for x in v] != [x[1] for x in r['intermediates']]: problems.append(('intermediate',r['id']))
  pair=[h(x) for x in pair];pairs.append(pair)
  if pair !=r['atan2_inputs']:problems.append(('atan2-input',r['id']))
  try:expected=lookup[tuple(pair)]
  except KeyError:problems.append(('unfrozen-input',r['id'],pair));continue
  if r['api']=='Vector2LineAngle':expected={p:h(int(v,16)^0x80000000) for p,v in expected.items()}
  if expected!=r['expected']:problems.append(('wrapper-final',r['id']))
 if problems:raise ValueError('Frozen angle derivation mismatches: '+repr(problems))
 return dict(scalar_controls=len(m['scalar_controls']),wrapper_controls=len(m['wrapper_controls']),exact_intermediates=sum(len(r['intermediates']) for r in m['wrapper_controls']),passed=True)

if __name__=='__main__':
 from angle_reference import load_manifest
 print(json.dumps(audit(load_manifest())))
