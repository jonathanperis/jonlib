#!/usr/bin/env python3
"""Native raw Softimage PIC fixtures using the shared bitmap comparison gate."""
import struct

from bmp_probe import main


def pic(width,height,packets):
    header=bytearray(104);header[:4]=b'\x53\x80\xf6\x34'
    header[4:88]=bytes((i*37+11)&255 for i in range(84));header[88:92]=b'PICT'
    struct.pack_into('>HHIHH',header,92,width,height,0x12345678,0xabcd,0xef01)
    descriptors=bytearray()
    for i,(mask,_) in enumerate(packets):descriptors.extend((7 if i+1<len(packets) else 0,8,0,mask))
    payload=bytearray()
    for y in range(height):
        for mask,colors in packets:
            for color in colors[y*width:(y+1)*width]:
                rgba=color.to_bytes(4,'big')
                payload.extend(value for i,value in enumerate(rgba) if mask&(128>>i))
    return list(header+descriptors+(payload if payload else b'\0'))


def fixtures():
    colors=[0x01020300,0x11223380,0xaabbccff,0x00ff007f,0xff00ff01,0xfefdfcfe]
    inputs=[dict(id=f'mask-{mask:02x}',bytes=pic(3,2,[(mask,colors)])) for mask in range(0,256,16)]
    replacement=[0x07000000,0x08000080,0x090000ff,0x0a00007f,0x0b000001,0x0c0000fe]
    inputs += [dict(id='ignored-mask-bits',bytes=pic(3,2,[(0x8f,colors)])),
               dict(id='overlapping-packets',bytes=pic(3,2,[(0xe0,colors),(0x90,replacement)])),
               dict(id='ten-packets',bytes=pic(2,2,[(0x80,[(i*17)<<24]*4) for i in range(10)])),
               dict(id='wide',bytes=pic(4096,1,[(0xe0,[(i*65793&0xffffff)<<8 for i in range(4096)])]))]
    base=pic(1,1,[(0xe0,[0x12345678])])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[256],error=1),
               dict(id='short-header',bytes=base[:103],error=0),dict(id='short-descriptor',bytes=base[:107],error=0),
               dict(id='descriptor-at-eof',bytes=base[:108],error=0),dict(id='short-sample',bytes=base[:-1],error=3),
               dict(id='too-many-packets',bytes=pic(1,1,[(0x80,[0])]*11),error=0)]
    for name,offset,value in [('magic',0,0),('marker',88,0),('packet-depth',105,16),('compression',106,1),('missing-chain',104,1)]:
        data=base.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=0))
    for name,offset,value in [('zero-width',92,0),('large-height',94,4097)]:
        data=bytearray(base);struct.pack_into('>H',data,offset,value);malformed.append(dict(id=name,bytes=list(data),error=2))
    return inputs,malformed,[]


if __name__=='__main__':
    main('pic',fixtures)
