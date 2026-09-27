#!/usr/bin/env python3
"""Native TGA raw/RLE/grayscale fixtures using the shared bitmap comparison gate."""
import random
import struct

from bmp_probe import main


def targa(width,height,channels,payload,*,rle=False,top=False,identifier=b'',descriptor=0,bits=None):
    kind=(3 if channels<3 else 2)+(8 if rle else 0)
    return list(struct.pack('<BBBHHBHHHHBB',len(identifier),0,kind,0,0,0,11,17,width,height,channels*8 if bits is None else bits,descriptor|(32 if top else 0))+identifier+bytes(payload))


def indexed_targa(width,height,entries,index_bits,entry_bits,payload,*,rle=False,top=False,skip=0,identifier=b''):
    header=struct.pack('<BBBHHBHHHHBB',len(identifier),1,9 if rle else 1,skip,len(entries),entry_bits,0,0,width,height,index_bits,32 if top else 0)
    return list(header+identifier+b'\xa5'*skip+b''.join(entries)+bytes(payload))


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
    words=[struct.pack('<H',(high<<15)|(i<<10)|(((i*5)&31)<<5)|(31-i)) for high in (0,1) for i in range(32)]
    raw=b''.join(words)
    encoded=b''.join(b'\0'+words[i]+b'\x81'+words[i+1] for i in range(0,64,2))
    for bits in (15,16):
        for top in (False,True):
            for rle,payload,height in ((False,raw,2),(True,encoded,3)):
                inputs.append(dict(id=f'rgb555-{bits}-{top}-{rle}',bytes=targa(32,height,3,payload,rle=rle,top=top,identifier=b'packed',descriptor=17,bits=bits)))
    cross_types=[(2,8,[bytes([value]) for value in (0,1,127,128,254,255)]),
                 (3,15,[struct.pack('<H',value) for value in (0,0x1000,0x9000,0x7fff,0xffff,0x4210)]),
                 (3,24,[bytes(((i*37+3)&255,(i*53+2)&255,(i*71+1)&255)) for i in range(6)]),
                 (3,32,[bytes(((i*37+3)&255,(i*53+2)&255,(i*71+1)&255,i*51)) for i in range(6)])]
    for kind,bits,samples in cross_types:
        for top in (False,True):
            for rle in (False,True):
                payload=b'\1'+samples[0]+samples[1]+b'\x83'+samples[2] if rle else b''.join(samples)
                data=targa(3,2,(bits+7)//8,payload,rle=rle,top=top,bits=bits);data[2]=kind+(8 if rle else 0)
                inputs.append(dict(id=f'cross-type-{kind}-{bits}-{top}-{rle}',bytes=data))
    palettes={8:[bytes([value]) for value in (0,127,255)],
              15:[struct.pack('<H',value) for value in (0,0x4210,0xffff)],
              16:[struct.pack('<H',value) for value in (0,0x4210,0xffff)],
              24:[bytes(pixel) for pixel in ((3,2,1),(7,6,5),(30,20,10))],
              32:[bytes(pixel) for pixel in ((3,2,1,0),(7,6,5,128),(30,20,10,255))]}
    for entry_bits,entries in palettes.items():
        for index_bits in (8,16):
            values=[value.to_bytes(index_bits//8,'little') for value in (0,1,2,3,(1<<index_bits)-1)]
            for rle in (False,True):
                payload=b'\1'+values[0]+values[1]+b'\x81'+values[2]+b'\1'+values[3]+values[4] if rle else b''.join([*values[:3],values[2],*values[3:]])
                inputs.append(dict(id=f'palette-{entry_bits}-{index_bits}-{rle}',bytes=indexed_targa(3,2,entries,index_bits,entry_bits,payload,rle=rle,top=rle,skip=3 if index_bits==8 else 0,identifier=b'idx\0')))
    entries=[bytes((i&255,i>>8,255-(i&255),i&255)) for i in range(257)]
    inputs.append(dict(id='palette-wide-index',bytes=indexed_targa(5,1,entries,16,32,b''.join(struct.pack('<H',i) for i in (0,255,256,257,65535)))))
    base=targa(1,1,4,[3,2,1,0])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[256],error=1),
               dict(id='short-header',bytes=base[:17],error=0),dict(id='short-pixel',bytes=base[:-1],error=3)]
    for name,offset,value,error in [('palette',1,1,0),('kind',2,1,0),('depth',16,17,0),('zero-width',12,0,2),('large-width',13,17,2),('short-id',0,255,3)]:
        data=base.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=error))
    for name,payload,error in [('no-command',[],3),('short-repeat',[128,1,2],3),('overrun-repeat',[129,1,2,3,4],4),('overrun-raw',[1,1,2,3,4,5,6,7,8],4)]:
        malformed.append(dict(id=name,bytes=targa(1,1,4,payload,rle=True),error=error))
    malformed += [dict(id='rgb555-short-pixel',bytes=targa(1,1,3,[1],bits=15),error=3),
                  dict(id='rgb555-short-repeat',bytes=targa(1,1,3,[128,1],rle=True,bits=16),error=3)]
    indexed=indexed_targa(1,1,[b'\3\2\1'],8,24,[0])
    for name,offset,value in [('palette-empty',5,0),('palette-depth',7,17),('index-depth',16,24)]:
        data=indexed.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=0))
    malformed += [dict(id='palette-truncated',bytes=indexed[:20],error=3),
                  dict(id='palette-missing-index',bytes=indexed[:-1],error=3),
                  dict(id='palette-short-wide-index',bytes=indexed_targa(1,1,[b'\3\2\1'],16,24,[0]),error=3),
                  dict(id='palette-packet-overrun',bytes=indexed_targa(1,1,[b'\3\2\1'],8,24,[129,0],rle=True),error=4)]
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
