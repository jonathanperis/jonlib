#!/usr/bin/env python3
"""Native opaque raw PSD fixtures using the shared bitmap comparison gate."""
import struct

from bmp_probe import main


def psd(width,height,planes,*,depth=8,sections=(b'',b'',b''),reserved=b'\0'*6):
    header=b'8BPS'+struct.pack('>H',1)+reserved+struct.pack('>HIIHH',len(planes),height,width,depth,3)
    for section in sections:header+=struct.pack('>I',len(section))+section
    payload=b''.join(value.to_bytes(depth//8,'big') for plane in planes for value in plane)
    return list(header+b'\0\0'+payload)


def rle_psd(width,height,streams,*,depth=8,row_lengths=None):
    header=psd(width,height,[[] for _ in streams],depth=depth);header[-2:]=[0,1]
    counts=[0]*(height*len(streams)) if row_lengths is None else row_lengths
    return [*header,*b''.join(struct.pack('>H',value) for value in counts),*b''.join(bytes(stream) for stream in streams)]


def fixtures():
    inputs=[]
    for channels in range(4):
        for depth in (8,16):
            planes=[[(i*61+c*43+17)&255 for i in range(6)] for c in range(channels)]
            if depth==16:planes=[[(value<<8)|((i*37+c*13)&255) for i,value in enumerate(plane)] for c,plane in enumerate(planes)]
            inputs.append(dict(id=f'raw-{channels}-{depth}',bytes=psd(3,2,planes,depth=depth)))
    planes=[[1,4,7,10,13,16],[2,5,8,11,14,17],[3,6,9,12,15,18]]
    inputs += [dict(id='reserved-and-sections',bytes=psd(3,2,planes,sections=(b'JON\0\xff',b'8BPS-resource',b'layer-data'),reserved=b'ABCDEF')+[9,8,7]),
               dict(id='single',bytes=psd(1,1,[[0],[127],[255]])),
               dict(id='wide',bytes=psd(4096,1,[[i&255 for i in range(4096)]])),
               dict(id='tall16',bytes=psd(1,4096,[[(i&255)<<8|(255-(i&255)) for i in range(4096)]],depth=16))]
    for channels in range(4):
        streams=[[128,1,(17+c*43)&255,(78+c*43)&255,253,(139+c*43)&255] for c in range(channels)]
        for depth in (8,16):inputs.append(dict(id=f'rle-{channels}-{depth}',bytes=rle_psd(3,2,streams,depth=depth)))
    inputs += [dict(id='rle-literal128-repeat2',bytes=rle_psd(130,1,[[128,127,*range(128),128,255,199]])),
               dict(id='rle-repeat128-literal2',bytes=rle_psd(130,1,[[129,37,128,1,0,255]])),
               dict(id='rle-wide',bytes=rle_psd(4096,1,[[129,37]*32])),
               dict(id='rle-row-lengths-ignored',bytes=rle_psd(2,3,[[5,1,2,3,4,5,6]],row_lengths=[65535]*3))]
    base=psd(1,1,[[1],[2],[3]])
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='invalid-byte',bytes=[*base,256],error=1),
               dict(id='short-header',bytes=base[:25],error=0),dict(id='short-compression',bytes=base[:39],error=0),
               dict(id='short-plane',bytes=base[:-1],error=3),
               dict(id='short-wide-sample',bytes=psd(1,1,[[0x1234]],depth=16)[:-1],error=3),
               dict(id='short-section-length',bytes=base[:29],error=0),
               dict(id='oversize-section',bytes=[*base[:26],255,255,255,255,1],error=3)]
    for name,offset,fmt,value,error in [('magic',0,'I',0,0),('version',4,'H',2,0),('alpha-channels',12,'H',4,0),
                                      ('depth',22,'H',32,0),('color-mode',24,'H',1,0),('compression',38,'H',2,0),
                                      ('zero-width',18,'I',0,2),('large-height',14,'I',4097,2)]:
        data=bytearray(base);struct.pack_into('>'+fmt,data,offset,value)
        malformed.append(dict(id=name,bytes=list(data),error=error))
    malformed += [dict(id='rle-empty',bytes=rle_psd(1,1,[[]]),error=3),
                  dict(id='rle-short-literal',bytes=rle_psd(3,1,[[2,1,2]]),error=3),
                  dict(id='rle-short-repeat',bytes=rle_psd(2,1,[[255]]),error=3),
                  dict(id='rle-overrun-literal',bytes=rle_psd(1,1,[[1,1,2]]),error=4),
                  dict(id='rle-overrun-repeat',bytes=rle_psd(1,1,[[255,1]]),error=4),
                  dict(id='rle-noops-eof',bytes=rle_psd(1,1,[[128]*2048]),error=3),
                  dict(id='rle-short-table',bytes=rle_psd(1,2,[[255,1]])[:43],error=3)]
    return inputs,malformed,[]


if __name__=='__main__':
    main('psd',fixtures)
