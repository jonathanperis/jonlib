#!/usr/bin/env python3
"""Native binary PGM/PPM fixtures using the shared bitmap comparison gate."""
from bmp_probe import main


def fixtures():
    inputs=[]
    for kind,channels in ((b'P5',1),(b'P6',3)):
        for maximum in (1,15,100,255):
            payload=bytes((i*61+17)&255 for i in range(6*channels))
            inputs.append(dict(id=f'{kind.decode()}-max-{maximum}',bytes=list(kind+b'\n3 2\n'+str(maximum).encode()+b'\n'+payload)))
        for name,header in [('comments',b' # first\n3\t# between\r2\v255\n'),
                            ('spaces',b'\r\n\t\v\f3\n2\t255\n'),
                            ('leading-zeros',b'0003 0002 00255 '),
                            ('inline-comments',b'3# width\n2# height\r255\n')]:
            inputs.append(dict(id=f'{kind.decode()}-{name}',bytes=list(kind+header+bytes(range(6*channels))+b'ignored-tail')))
        for maximum in (256,1000,65535):
            payload=bytes(value for i in range(6*channels) for value in ((i*43+128)&255,(i*61+17)&255))
            inputs.append(dict(id=f'{kind.decode()}-16bit-max-{maximum}',bytes=list(kind+b'\n3 2\n'+str(maximum).encode()+b'\n'+payload)))
        payload=bytes(value for i in range(256*channels) for value in ((i*43+1)&255,i&255))
        inputs.append(dict(id=f'{kind.decode()}-16bit-bytes',bytes=list(kind+b' # wide samples\n16 16\n65535\n'+payload+b'tail')))
    inputs += [dict(id='crlf-payload',bytes=list(b'P5\n2 1\n255\r\n\x80')),
               dict(id='space-payload',bytes=list(b'P5\n2 1\n255\n \n')),
               dict(id='hash-payload',bytes=list(b'P5\n2 1\n255\n#\xff')),
               dict(id='wide',bytes=list(b'P5\n4096 1\n255\n'+bytes(range(256))*16)),
               dict(id='tall',bytes=list(b'P5\n1 4096\n255\n'+bytes(range(255,-1,-1))*16)),
               dict(id='16bit-crlf-payload',bytes=list(b'P5\n2 1\n65535\r\n\x80\x12\x34'))]
    malformed=[]
    for name,data,error in [('magic',b'P3\n1 1\n255\n\0',0),('empty',b'',0),
                            ('missing-number',b'P6\n# no numbers',0),('negative',b'P5 -1 1 255\n\0',0),
                            ('overflow',b'P5 4294967297 1 255\n\0',0),('wide',b'P5 4097 1 255\n\0',2),
                            ('zero-size',b'P5 0 1 255\n\0',2),('zero-max',b'P5 1 1 0\n\0',0),
                            ('max-overflow',b'P5 1 1 65536\n\0\0',0),('unterminated',b'P5 1 1 255',0),
                            ('invalid-separator',b'P5 1 1 255x\0',0),('truncated',b'P6 1 1 255\n\1\2',3),
                            ('16bit-truncated-sample',b'P5 1 1 256\n\1',3),
                            ('16bit-truncated-channel',b'P6 1 1 65535\n\1\2\3\4',3)]:
        malformed.append(dict(id=name,bytes=list(data),error=error))
    malformed.append(dict(id='invalid-byte',bytes=[*b'P5 1 1 255\n',256],error=1))
    malformed.append(dict(id='16bit-invalid-discarded-byte',bytes=[*b'P5 1 1 256\n',256,0],error=1))
    return inputs,malformed,[]


if __name__=='__main__':
    main('pnm',fixtures,'ppm')
