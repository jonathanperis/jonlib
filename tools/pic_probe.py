#!/usr/bin/env python3
"""Native raw Softimage PIC fixtures using the shared bitmap comparison gate."""
import struct

from bmp_probe import main


def pic_header(width,height):
    header=bytearray(104);header[:4]=b'\x53\x80\xf6\x34'
    header[4:88]=bytes((i*37+11)&255 for i in range(84));header[88:92]=b'PICT'
    struct.pack_into('>HHIHH',header,92,width,height,0x12345678,0xabcd,0xef01)
    return header


def pic(width,height,packets):
    header=pic_header(width,height)
    descriptors=bytearray()
    for i,(mask,_) in enumerate(packets):descriptors.extend((7 if i+1<len(packets) else 0,8,0,mask))
    payload=bytearray()
    for y in range(height):
        for mask,colors in packets:
            for color in colors[y*width:(y+1)*width]:
                rgba=color.to_bytes(4,'big')
                payload.extend(value for i,value in enumerate(rgba) if mask&(128>>i))
    return list(header+descriptors+(payload if payload else b'\0'))


def pic_packets(width,height,packets):
    header=pic_header(width,height);descriptors=bytearray()
    for i,(kind,mask,_) in enumerate(packets):descriptors.extend((7 if i+1<len(packets) else 0,8,kind,mask))
    payload=b''.join(bytes(rows[y]) for y in range(height) for _,_,rows in packets)
    return list(header+descriptors+(payload if payload else b'\0'))


def fixtures():
    colors=[0x01020300,0x11223380,0xaabbccff,0x00ff007f,0xff00ff01,0xfefdfcfe]
    inputs=[dict(id=f'mask-{mask:02x}',bytes=pic(3,2,[(mask,colors)])) for mask in range(0,256,16)]
    replacement=[0x07000000,0x08000080,0x090000ff,0x0a00007f,0x0b000001,0x0c0000fe]
    inputs += [dict(id='ignored-mask-bits',bytes=pic(3,2,[(0x8f,colors)])),
               dict(id='overlapping-packets',bytes=pic(3,2,[(0xe0,colors),(0x90,replacement)])),
               dict(id='ten-packets',bytes=pic(2,2,[(0x80,[(i*17)<<24]*4) for i in range(10)])),
               dict(id='wide',bytes=pic(4096,1,[(0xe0,[(i*65793&0xffffff)<<8 for i in range(4096)])]))]
    for kind in (1,2):
        inputs.append(dict(id=f'rle-empty-mask-{kind}',bytes=pic_packets(3,1,[(kind,0,[[3 if kind==1 else 2,0]])])))
        for mask in (0x80,0x50,0xf0):
            rows=[]
            for y in range(2):
                samples=[[value for i,value in enumerate(color.to_bytes(4,'big')) if mask&(128>>i)] for color in colors[y*3:(y+1)*3]]
                rows.append([0,*samples[0],255,*samples[1]] if kind==1 else [128,0,0,*samples[0],1,*samples[0],*samples[1],128,0,1,*samples[2]])
            inputs.append(dict(id=f'rle-{kind}-{mask:02x}',bytes=pic_packets(3,2,[(kind,mask,rows)])))
    inputs += [dict(id='raw-pure-mixed-overlap',bytes=pic_packets(3,2,
                    [(0,0xe0,[[1,2,3,4,5,6,7,8,9],[11,12,13,14,15,16,17,18,19]]),
                     (1,0x80,[[1,21,255,22],[1,31,255,32]]),
                     (2,0x10,[[1,0,128,128,0,1,255],[1,255,128,128,0,1,0]])])),
               dict(id='pure-255-and-one',bytes=pic_packets(256,1,[(1,0x80,[[255,17,1,34]])])),
               dict(id='mixed-short-repeat-boundaries',bytes=pic_packets(130,1,[(2,0x80,[[255,17,129,34]])])),
               dict(id='mixed-extended-wide',bytes=pic_packets(4096,1,[(2,0x80,[[128,16,0,37]])])),
               dict(id='mixed-raw128-and-one',bytes=pic_packets(129,1,[(2,0x80,[[127,*range(128),0,255]])]))]
    base=pic(1,1,[(0xe0,[0x12345678])])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[256],error=1),
               dict(id='short-header',bytes=base[:103],error=0),dict(id='short-descriptor',bytes=base[:107],error=0),
               dict(id='descriptor-at-eof',bytes=base[:108],error=0),dict(id='short-sample',bytes=base[:-1],error=3),
               dict(id='too-many-packets',bytes=pic(1,1,[(0x80,[0])]*11),error=0)]
    for name,offset,value in [('magic',0,0),('marker',88,0),('packet-depth',105,16),('compression',106,3),('missing-chain',104,1)]:
        data=base.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=0))
    for name,offset,value in [('zero-width',92,0),('large-height',94,4097)]:
        data=bytearray(base);struct.pack_into('>H',data,offset,value);malformed.append(dict(id=name,bytes=list(data),error=2))
    for name,kind,mask,width,payload,error in [
            ('pure-control-eof',1,0x80,1,[1],3),('pure-short-sample',1,0xf0,1,[1,1,2],3),
            ('pure-zero-eof',1,0x80,1,[0,17]*1024,3),('mixed-empty-mask-control-eof',2,0,1,[0],3),
            ('mixed-short-count',2,0x80,1,[128,1],3),('mixed-short-literal',2,0x80,2,[1,9],3),
            ('mixed-overrun-literal',2,0x80,1,[1,9,10],4),('mixed-overrun-repeat',2,0x80,1,[129,9],4),
            ('mixed-overrun-long',2,0x80,1,[128,0,2,9],4),('mixed-zero-eof',2,0x80,1,[128,0,0,99],3)]:
        malformed.append(dict(id=name,bytes=pic_packets(width,1,[(kind,mask,[payload])]),error=error))
    return inputs,malformed,[]


if __name__=='__main__':
    main('pic',fixtures)
