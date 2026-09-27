#!/usr/bin/env python3
"""Native full-canvas first-frame GIF fixtures using the bitmap comparison gate."""
import random
import struct

from bmp_probe import main


def lzw_codes(values,minimum,reset_every=None):
    clear=1<<minimum;codes=[]
    groups=[values] if reset_every is None else [values[i:i+reset_every] for i in range(0,len(values),reset_every)]
    for group in groups:
        table={(i,):i for i in range(clear)};next_code=clear+2;prefix=()
        codes.append(clear)
        for value in group:
            candidate=prefix+(value,)
            if candidate in table:prefix=candidate;continue
            codes.append(table[prefix])
            if next_code<4096:table[candidate]=next_code;next_code+=1
            else:codes.append(clear);table={(i,):i for i in range(clear)};next_code=clear+2
            prefix=(value,)
        if prefix:codes.append(table[prefix])
    return codes+[clear+1]


def pack_codes(codes,minimum):
    clear=1<<minimum;width=minimum+1;next_code=clear+2;old=False;word=0;count=0;data=bytearray();maximum=width
    for code in codes:
        if code>=(1<<width):raise ValueError('Code does not fit its declared width')
        word|=code<<count;count+=width
        while count>=8:data.append(word&255);word>>=8;count-=8
        if code==clear:width=minimum+1;next_code=clear+2;old=False
        elif code==clear+1:break
        else:
            if old:
                next_code+=1
                if next_code==(1<<width) and next_code<=4095:width+=1
            old=True
        maximum=max(maximum,width)
    if count:data.append(word&255)
    return bytes(data),maximum


def blocks(data,size=255):
    return b''.join(bytes([len(data[i:i+size])])+data[i:i+size] for i in range(0,len(data),size))+b'\0'


def gce(index=None):
    return bytes([33,249,4,0 if index is None else 1,9,0,99 if index is None else index,0])


def gif(width,height,indices,palette,*,minimum=2,local=None,transparent=None,version=b'9',block_size=255,extensions=b'',codes=None,reset_every=None,background=0):
    flags=0 if palette is None else 128|(len(palette).bit_length()-2)
    data=b'GIF8'+version[:1]+b'a'+struct.pack('<HHBBB',width,height,flags,background,0)
    if palette is not None:data+=b''.join(color.to_bytes(4,'big')[:3] for color in palette)
    data+=extensions
    if transparent is not None:data+=gce(transparent)
    local_flags=0 if local is None else 128|(len(local).bit_length()-2)
    data+=b','+struct.pack('<HHHHB',0,0,width,height,local_flags)
    if local is not None:data+=b''.join(color.to_bytes(4,'big')[:3] for color in local)
    sequence=lzw_codes(indices,minimum,reset_every) if codes is None else codes
    packed,_=pack_codes(sequence,minimum)
    return list(data+bytes([minimum])+blocks(packed,block_size)+b';')


def fixtures():
    colors=[0x010203ff,0x112233ff,0xaabbccff,0xfedcbaff]
    inputs=[]
    for version in (b'7',b'9'):
        for transparent in (None,1):
            inputs.append(dict(id=f'basic-{version.decode()}-{transparent}',bytes=gif(2,1,[0,1],colors[:2],version=version,transparent=transparent,background=1)))
    inputs += [dict(id='single',bytes=gif(1,1,[1],colors[:2])),
               dict(id='local-overrides',bytes=gif(3,2,[0,1,2,3,2,1],colors,local=list(reversed(colors)),transparent=2)),
               dict(id='local-only',bytes=gif(3,2,[0,1,2,3,2,1],None,local=colors)),
               dict(id='self-reference',bytes=gif(128,1,[0]*128,colors[:2])),
               dict(id='clear-resets',bytes=gif(32,4,[i%4 for i in range(128)],colors,reset_every=7)),
               dict(id='extensions',bytes=gif(3,2,[0,1,2,3,2,1],colors,extensions=b'!\xfe'+blocks(b'comment',3)+b'!\xff'+blocks(b'JONLIB-data',4)+gce(1)+gce())),
               dict(id='trailing-data',bytes=gif(2,1,[0,1],colors[:2])+[0,1,2,3])]
    for minimum in range(2,9):
        palette=[i<<24|(255-i)<<16|((i*73)&255)<<8|255 for i in range(1<<minimum)]
        values=[(i*17+i//3)%len(palette) for i in range(51)]
        inputs.append(dict(id=f'minimum-{minimum}',bytes=gif(17,3,values,palette,minimum=minimum,block_size=1 if minimum%2 else 3)))
    rng=random.Random(0x61f);values=[rng.randrange(256) for _ in range(4096)]
    palette=[i<<24|(255-i)<<16|((i*73)&255)<<8|255 for i in range(256)]
    codes=lzw_codes(values,8);_,maximum=pack_codes(codes,8)
    if maximum!=12 or codes.count(256)<2:raise ValueError('GIF growth fixture did not reach twelve bits and reset')
    inputs.append(dict(id='width-growth-and-clear',bytes=gif(4096,1,values,palette,minimum=8,codes=codes),maximum_code_width=maximum,clear_codes=codes.count(256)))
    base=gif(2,1,[0,1],colors[:2]);descriptor=19
    malformed=[dict(id='empty',bytes=[],error=0),dict(id='byte',bytes=[*base,256],error=1),
               dict(id='short-header',bytes=base[:12],error=0),dict(id='short-palette',bytes=base[:18],error=3),
               dict(id='short-descriptor',bytes=base[:descriptor+9],error=0),
               dict(id='short-subblock',bytes=base[:-3],error=3),
               dict(id='no-table',bytes=gif(2,1,[0,1],None),error=0),
               dict(id='no-clear',bytes=gif(2,1,[0,1],colors[:2],codes=[0,1,5]),error=4),
               dict(id='first-invalid-code',bytes=gif(1,1,[0],colors[:2],codes=[4,6,5]),error=4),
               dict(id='invalid-code',bytes=gif(2,1,[0,1],colors[:2],codes=[4,0,7,5]),error=4),
               dict(id='early-end',bytes=gif(2,1,[0,1],colors[:2],codes=[4,0,5]),error=4),
               dict(id='output-overrun',bytes=gif(1,1,[0],colors[:2],codes=[4,0,1,5]),error=4),
               dict(id='dictionary-overrun',bytes=gif(4096,2,[],colors[:2],codes=[4,*([0]*8192),5]),error=4),
               dict(id='palette-index',bytes=gif(1,1,[3],colors[:2]),error=4)]
    for name,offset,value,error in [('version',4,54,0),('zero-width',6,0,2),('wide-high',7,17,2),
                                    ('offset',descriptor+1,1,0),('interlaced',descriptor+9,64,0),('minimum',descriptor+10,1,0)]:
        data=base.copy();data[offset]=value;malformed.append(dict(id=name,bytes=data,error=error))
    return inputs,malformed,[]


if __name__=='__main__':
    main('gif',fixtures)
