#!/usr/bin/env python3
"""Native PNG 8-bit color/filter/transparency fixtures for the bitmap gate."""
import struct
import zlib

from bmp_probe import main


SIGNATURE=b'\x89PNG\r\n\x1a\n'
CHANNELS={0:1,2:3,3:1,4:2,6:4}


def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))


def paeth(a,b,c):
    p=a+b-c
    pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
    return a if pa<=pb and pa<=pc else b if pb<=pc else c


def filtered(width,height,color,raw,filters):
    channels=CHANNELS[color];stride=width*channels;output=bytearray()
    for y in range(height):
        mode=filters[y%len(filters)];output.append(mode)
        for x in range(stride):
            i=y*stride+x
            a=raw[i-channels] if x>=channels else 0
            b=raw[i-stride] if y else 0
            c=raw[i-stride-channels] if y and x>=channels else 0
            predictor=(0,a,b,(a+b)//2,paeth(a,b,c))[mode]
            output.append((raw[i]-predictor)&255)
    return bytes(output)


def png(width,height,color,raw,filters=(0,),*,palette=None,transparency=None,stream=None,extra=(),split=False):
    header=struct.pack('>IIBBBBB',width,height,8,color,0,0,0)
    data=SIGNATURE+chunk(b'IHDR',header)
    if palette is not None:data+=chunk(b'PLTE',palette)
    if transparency is not None:data+=chunk(b'tRNS',transparency)
    for kind,body in extra:data+=chunk(kind,body)
    stream=zlib.compress(filtered(width,height,color,raw,filters)) if stream is None else stream
    if split:
        data+=chunk(b'IDAT',stream[:1])+chunk(b'IDAT',b'')+chunk(b'tEXt',b'between\x00chunks')+chunk(b'IDAT',stream[1:4])+chunk(b'IDAT',stream[4:])
    else:data+=chunk(b'IDAT',stream)
    return data+chunk(b'IEND',b'')


def fixtures():
    inputs=[]
    palette=bytes([17,63,201,255,0,127,0,255,128,1,2,3])
    for color,channels in CHANNELS.items():
        raw=bytes(((i*73+17)^((i//channels)*29))&255 for i in range(5*5*channels))
        options={}
        if color==0:options['transparency']=b'\x09\x11'
        if color==2:
            raw=bytes([17,63,201])+raw[3:];options['transparency']=bytes([9,17,8,63,7,201])
        if color==3:
            raw=bytes(i%4 for i in range(25));options=dict(palette=palette,transparency=b'\x00\x80')
        for mode in range(6):
            filters=(mode,) if mode<5 else (0,1,2,3,4)
            inputs.append(dict(id=f'color-{color}-filter-{mode}',bytes=list(png(5,5,color,raw,filters,**options))))
    inputs.append(dict(id='palette-opaque',bytes=list(png(4,1,3,bytes(range(4)),palette=palette))))
    for name,w,h in [('thin',1,5),('wide',4096,1),('tall',1,4096)]:
        raw=bytes((i*61+17)&255 for i in range(w*h*4))
        inputs.append(dict(id=name,bytes=list(png(w,h,6,raw,(4,3,2,1,0)))))
    raw=bytes(range(36));scan=filtered(3,3,6,raw,(1,2,4))
    obj=zlib.compressobj();stream=obj.compress(scan[:9])+obj.flush(zlib.Z_SYNC_FLUSH)+obj.compress(scan[9:])+obj.flush()
    inputs.append(dict(id='split-idat-empty-stored',bytes=list(png(3,3,6,raw,stream=stream,split=True))))
    inputs.append(dict(id='ancillary-and-tail',bytes=list(png(3,3,6,raw,extra=[(b'zzZZ',b'ignored')])+b'trailing')))
    stream=zlib.compress(scan)
    broken=bytearray(png(3,3,6,raw,stream=stream[:-4]+b'\x00\x00\x00\x00'))
    broken[-1]^=255  # The native PNG decoder ignores both CRC and Adler-32.
    inputs.append(dict(id='ignored-checksums',bytes=list(broken)))
    inputs.append(dict(id='absent-adler',bytes=list(png(3,3,6,raw,stream=stream[:-4]))))
    base=png(1,1,6,bytes([1,2,3,4]))
    gray=png(1,1,0,b'\1')
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='bad-byte',bytes=[256],error=1),
               dict(id='short-chunk',bytes=list(base[:-1]),error=0)]
    for name,width,height,depth,color,method,filter_method,interlace,error in [
        ('zero-width',0,1,8,6,0,0,0,2),('wide-size',4097,1,8,6,0,0,0,2),
        ('filtered-limit',4096,4096,8,6,0,0,0,2),('depth16',1,1,16,6,0,0,0,0),
        ('bad-color',1,1,8,5,0,0,0,0),('compression',1,1,8,6,1,0,0,0),
        ('filter-method',1,1,8,6,0,1,0,0),('adam7',1,1,8,6,0,0,1,0)]:
        header=struct.pack('>IIBBBBB',width,height,depth,color,method,filter_method,interlace)
        data=SIGNATURE+chunk(b'IHDR',header)+base[33:]
        malformed.append(dict(id=name,bytes=list(data),error=error))
    malformed += [dict(id='unknown-critical',bytes=list(png(1,1,6,b'\1\2\3\4',extra=[(b'ABCD',b'')])),error=0),
                  dict(id='missing-palette',bytes=list(png(1,1,3,b'\0')),error=0),
                  dict(id='palette-index',bytes=list(png(1,1,3,b'\4',palette=palette)),error=4),
                  dict(id='palette-alpha-too-long',bytes=list(png(1,1,3,b'\0',palette=palette,transparency=b'\0'*5)),error=0),
                  dict(id='transparency-with-alpha',bytes=list(png(1,1,6,b'\1\2\3\4',transparency=b'\0\1')),error=0),
                  dict(id='missing-idat',bytes=list(base[:33]+chunk(b'IEND',b'')),error=0),
                  dict(id='duplicate-header',bytes=list(base[:33]+base[8:]),error=0),
                  dict(id='before-header',bytes=list(SIGNATURE+chunk(b'tEXt',b'x')+base[8:]),error=0),
                  dict(id='late-transparency',bytes=list(gray[:-12]+chunk(b'tRNS',b'\0\1')+gray[-12:]),error=0),
                  dict(id='chunk-overflow',bytes=list(SIGNATURE+b'\xff\xff\xff\xffIHDR'),error=0)]
    for name,stream in [('bad-zlib',b'\x78\x00'+zlib.compress(b'\0\1\2\3\4')[2:]),
                        ('bad-filter',zlib.compress(b'\5\1\2\3\4')),
                        ('short-raster',zlib.compress(b'\0\1\2\3')),
                        ('extra-raster',zlib.compress(b'\0\1\2\3\4\5')),
                        ('truncated-deflate',b'\x78\x9c\x03')]:
        malformed.append(dict(id=name,bytes=list(png(1,1,6,b'\1\2\3\4',stream=stream)),error=4))
    return inputs,malformed,[]


if __name__=='__main__':
    main('png',fixtures)
