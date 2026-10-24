#!/usr/bin/env python3
"""Compare shared .hdr/.HDR dispatch with pinned LoadImage and LoadImageFromMemory.

Radiance signatures stay format 9. Raster tokens tone-map that signature to
R8G8B8. A .hdr token promotes an admitted 8-bit raster with pow(byte/255, 2.2).
Gray-alpha under .hdr is a refusal: raylib unloads a by-value copy and leaves
the caller's pointer dangling, so both sides emit a sentinel and neither reads
those samples. Surface.load_hdr stays Radiance-only regardless of the suffix.
"""
import hashlib
import json

from bmp_probe import bitmap, bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from png_probe import png
import probekit
from probekit import ROOT, ProbeFailure


def radiance(width, height, samples, signature=b'#?RADIANCE'):
    line = f'-Y {height} +X {width}'.encode()
    return list(signature + b'\nFORMAT=32-bit_rle_rgbe\n\n' + line + b'\n' + bytes(samples))


def pixel(r, g, b, a=0):
    return (r << 24) | (g << 16) | (b << 8) | a


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def prepend(reversed: List<U32>, values: List<U32>) -> List<U32>:
  match reversed:
    case Nil{}: values
    case Con{value, rest}: prepend(rest, Con{value, values})
''' + BEND_EMITTER + '''
def exported(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  emit_bytes(~&1, prepend(word_bytes(4n, height, word_bytes(4n, width, word_bytes(4n, format, Nil{}))), bytes))
def memory_image(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{surface}: exported(J.Surface.export(surface))
def file_image(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{surface}: exported(J.Surface.export(surface))
def refused_memory(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.InvalidImageHeader{}}: emit_bytes(~&1, [1, 0, 0, 0])
    case Fail{_}: IO.die(Unit, 1, "gray-alpha HDR refusal changed")
    case Done{_}: IO.die(Unit, 1, "gray-alpha HDR refusal changed")
def refused_file(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.DataError{J.InvalidImageHeader{}}}: emit_bytes(~&1, [1, 0, 0, 0])
    case Fail{_}: IO.die(Unit, 1, "gray-alpha HDR file refusal changed")
    case Done{_}: IO.die(Unit, 1, "gray-alpha HDR file refusal changed")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe = probekit.Probe('hdr-dispatch', probekit.arguments(__doc__))
    work = probe.work
    wide = radiance(1, 2, [1, 2, 3, 128, 255, 127, 1, 136])
    rgbe = radiance(1, 1, [10, 20, 30, 200], signature=b'#?RGBE')
    png_rgb = list(png(1, 1, 2, bytes([10, 20, 30])))
    png_gray = list(png(1, 1, 0, bytes([200])))
    png_rgba = list(png(1, 1, 6, bytes([10, 20, 30, 40])))
    png_ga = list(png(1, 1, 4, bytes([80, 40])))
    bmp_rgb = bitmap(1, 1, [pixel(10, 20, 30)])
    garbage = list(b'not an image!!')
    memory = [
        ('radiance-hdr', '.hdr', wide),
        ('radiance-HDR', '.HDR', wide),
        ('radiance-png', '.png', wide),
        ('radiance-bmp', '.bmp', wide),
        ('radiance-tga', '.tga', wide),
        ('radiance-jpg', '.jpg', wide),
        ('radiance-gif', '.gif', wide),
        ('radiance-PNG', '.PNG', wide),
        ('rgbe-hdr', '.hdr', rgbe),
        ('rgbe-png', '.png', rgbe),
        ('png-rgb-hdr', '.hdr', png_rgb),
        ('png-rgb-png', '.png', png_rgb),
        ('png-gray-hdr', '.hdr', png_gray),
        ('png-gray-png', '.png', png_gray),
        ('png-rgba-hdr', '.hdr', png_rgba),
        ('png-rgba-png', '.png', png_rgba),
        ('bmp-rgb-hdr', '.hdr', bmp_rgb),
        ('bmp-rgb-bmp', '.bmp', bmp_rgb),
        ('garbage-hdr', '.hdr', garbage),
        ('garbage-png', '.png', garbage),
        ('mixed-case', '.Hdr', wide),
    ]
    files = {
        'scene.hdr': wide,
        'scene.HDR': rgbe,
        'scene.png': wide,
        'photo.hdr': png_rgb,
        'plain.png': png_rgb,
        'scene.Hdr': wide,
        'misnamed.png': wide,
        'empty.hdr': [],
        'ga.hdr': png_ga,
    }
    for name, data in files.items():
        (work / name).write_bytes(bytes(data))
    actions = [('memory', name, token, data) for name, token, data in memory]
    actions += [('file', name, None, files[name]) for name in ('scene.hdr', 'scene.HDR', 'scene.png', 'photo.hdr', 'plain.png', 'scene.Hdr', 'empty.hdr')]
    actions.append(('explicit', 'misnamed.png', None, wide))
    actions.append(('refuse', 'gray-alpha', '.hdr', png_ga))
    actions.append(('refuse-file', 'ga.hdr', None, png_ga))

    def c_bytes(values):
        return '{' + ','.join(map(str, values)) + '}'

    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>',
             C_EMITTER,
             'static void emit(Image image){if(!image.data){puts("null");return;}if(image.format==0)exit(3);',
             'word(image.format);word(image.width);word(image.height);unsigned char *p=image.data;',
             'int n=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<n;i++)byte(p[i]);end();UnloadImage(image);}',
             'static void memory_image(const char *token,const unsigned char *data,int size){emit(LoadImageFromMemory(token,data,size));}',
             'static void file_image(const char *path){emit(LoadImage(path));}',
             'static void explicit_image(const char *path){int size=0;unsigned char *data=LoadFileData(path,&size);',
             'if(!data){puts("null");return;}Image image=LoadImageFromMemory(".hdr",data,size);UnloadFileData(data);emit(image);}',
             'static void refuse(const unsigned char *data,int size){Image image=LoadImageFromMemory(".hdr",data,size);',
             'if(!image.data||image.format!=0)exit(2);word(1);end();}',
             'static void refuse_file(const char *path){Image image=LoadImage(path);if(!image.data||image.format!=0)exit(2);word(1);end();}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for kind, name, token, data in actions:
        if kind == 'memory':
            lines.append(f'{{unsigned char data[]={c_bytes(data)};memory_image({json.dumps(token)},data,sizeof(data));}}')
        elif kind == 'file':
            lines.append(f'file_image({json.dumps(str((work / name).relative_to(ROOT)))});')
        elif kind == 'explicit':
            lines.append(f'explicit_image({json.dumps(str((work / name).relative_to(ROOT)))});')
        elif kind == 'refuse':
            lines.append(f'{{unsigned char data[]={c_bytes(data)};refuse(data,sizeof(data));}}')
        else:
            lines.append(f'refuse_file({json.dumps(str((work / name).relative_to(ROOT)))});')
    text = probe.native('\n'.join(lines + ['}']) + '\n')
    expected = parse_results(text)
    if len(expected) != len(actions):
        raise ProbeFailure('Incomplete native HDR dispatch results')
    if expected[-2] != [1, 0, 0, 0] or expected[-1] != [1, 0, 0, 0]:
        raise ProbeFailure('Gray-alpha HDR was readable instead of a dangling refusal')

    def render(selected, gpu):
        body = PROGRAM
        for kind, name, token, data in selected:
            if kind == 'memory':
                body += f'    memory_image(J.Surface.decode_image({json.dumps(token)}, {bend_bytes(data)}))\n'
            elif kind == 'file':
                path = json.dumps(str((work / name).relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_image({path}), file_image)\n'
            elif kind == 'explicit':
                path = json.dumps(str((work / name).relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_hdr({path}), file_image)\n'
            elif kind == 'refuse':
                body += f'    refused_memory(J.Surface.decode_image(".hdr", {bend_bytes(data)}))\n'
            else:
                path = json.dumps(str((work / name).relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_image({path}), refused_file)\n'
        return body

    probe.compare(expected, probe.candidates(render, actions, batch=len(actions), parse=lambda text, selected: parse_results(text)),
                  lambda i: actions[i][0] + ' ' + actions[i][1])
    loaded = sum(row is not None and row != [1, 0, 0, 0] for row in expected)
    probe.finish(cases=len(actions), loaded=loaded, refusals=2, explicit_loader=1,
                 inputs_sha256=hashlib.sha256(json.dumps(actions, default=list).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
