#!/usr/bin/env python3
"""Native TGA raw/RLE/grayscale fixtures using the shared bitmap comparison gate."""
import random
import struct

from bmp_probe import main


def targa(width,height,channels,payload,*,rle=False,top=False,identifier=b'',descriptor=0):
    kind=(3 if channels<3 else 2)+(8 if rle else 0)
    return list(struct.pack('<BBBHHBHHHHBB',len(identifier),0,kind,0,0,0,11,17,width,height,channels*8,descriptor|(32 if top else 0))+identifier+bytes(payload))


def fixtures():
    inputs=[]
    for channels in range(1,5):
        data=[[((i*61+j*37)+17)&255 for j in range(channels)] for i in range(6)]
        if channels in (2,4):data[0][-1]=0
        raw=[v for pixel in data for v in pixel]
        encoded=[1,*data[0],*data[1],131,*data[2]]  # Run crosses the row boundary.
        for top in (False,True):
            for rle,payload in ((False,raw),(True,encoded)):
                inputs.append(dict(id=f'{channels}-{top}-{rle}',bytes=targa(3,2,channels,payload,rle=rle,top=top,identifier=b'JON\x00\xff',descriptor=16 if top else 0)))
    for repeat in (False,True):
        payload=[255,3,2,1,0,129,7,6,5,0] if repeat else [127,*[v for i in range(128) for v in (i,255-i,i^0x55,0)],1,1,2,3,0,4,5,6,0]
        inputs.append(dict(id=f'packet-limit-{repeat}',bytes=targa(130,1,4,payload,rle=True,top=True)))
    inputs.append(dict(id='ignored-attributes',bytes=targa(2,1,4,[3,2,1,0,6,5,4,0],descriptor=0xcf)))
    base=targa(1,1,4,[3,2,1,0])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[256],error=1),
               dict(id='short-header',bytes=base[:17],error=0),dict(id='short-pixel',bytes=base[:-1],error=3)]
    for name,offset,value,error in [('palette',1,1,0),('kind',2,1,0),('depth',16,16,0),('zero-width',12,0,2),('large-width',13,17,2),('short-id',0,255,3)]:
        data=base.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=error))
    for name,payload,error in [('no-command',[],3),('short-repeat',[128,1,2],3),('overrun-repeat',[129,1,2,3,4],4),('overrun-raw',[1,1,2,3,4,5,6,7,8],4)]:
        malformed.append(dict(id=name,bytes=targa(1,1,4,payload,rle=True),error=error))
    outputs=[]
    a,b,c=0x11223300,0x12345678,0x90abcdef
    for name,pixels in [('two',[a,b]),('aba',[a,b,a]),('abbc',[a,b,b,c]),('run128',[a]*128),('run129',[a]*129),
                        ('raw128',[(i*65537+0x10101080)&0xffffffff for i in range(128)]),
                        ('raw130',[(i*65537+0x10101080)&0xffffffff for i in range(130)]),
                        ('mixed',[a,b,c,c,c,a,b,a,b,b,c])]:
        outputs.append(dict(id=name,width=len(pixels),height=1,pixels=pixels))
    outputs.append(dict(id='row-boundary',width=2,height=3,pixels=[a,a,a,a,b,b]))
    rng=random.Random(0x76a)
    pixels=[]
    for i in range(514):pixels.append(rng.choice([a,b,c,rng.getrandbits(32)]))
    outputs.append(dict(id='seeded',width=257,height=2,pixels=pixels))
    outputs.append(dict(id='rgba-single',width=1,height=1,pixels=[0xffffffff]))
    return inputs,malformed,outputs


if __name__=='__main__':
    main('tga',fixtures)
