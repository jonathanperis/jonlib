#!/usr/bin/env python3
"""Compare raylib's file callbacks with Jonlib's explicit loader forms.

The native program installs SetLoadFileDataCallback, SetSaveFileDataCallback,
SetLoadFileTextCallback and SetSaveFileTextCallback callbacks that serve an
in-memory table of files and print every call; the candidate passes the same
callbacks to the _with forms (Files.load_data_with ... Surface.write_code_with).
Both run LoadFileData/SaveFileData/LoadFileText/SaveFileText, FileTextFindIndex,
LoadImage, LoadImageRaw, LoadImageAnim, ExportImage (.png and .raw through the
callback, .bmp written directly by raylib), ExportImageAsCode and
ExportDataAsCode, and the
complete call logs and results must be equal. CPU/JS lanes.
"""
import json
import struct
import zlib

from byte_probe import C_IMAGE, SURFACE_EMITTER
import probekit
from probekit import ROOT, ProbeFailure

PIXELS = [(255, 0, 0, 255), (0, 255, 0, 128), (0, 0, 255, 0), (10, 20, 30, 40), (200, 100, 50, 255), (1, 2, 3, 4)]


def png(width, height, pixels):
    chunk = lambda kind, data: struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes(v for p in pixels[y * width:(y + 1) * width] for v in p) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def qoi(width, height, pixels):
    return (b'qoif' + struct.pack('>IIBB', width, height, 4, 0) + b''.join(b'\xff' + bytes(p) for p in pixels)
            + b'\0' * 7 + b'\1')


TEXT = 'hello, loaders\nsecond line'
FILES = {  # virtual path: bytes
    'v/data.bin': [0, 1, 2, 254, 255, 7],
    'v/image.png': list(png(3, 2, PIXELS)),
    'v/image.qoi': list(qoi(3, 2, PIXELS)),
    'v/raw.bin': [9, 9, 9, 9] + [v for p in PIXELS[:4] for v in p],
    'v/short.bin': [1, 2, 3],
}
TEXTS = {'v/text.txt': TEXT}
BMP = '.build/loaders-probe/direct.bmp'
REAL = '.build/loaders-probe/real.txt'  # exists on disk; the callback serves TEXT for it


def c_text(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def native(probe):
    table = ''.join(f'{{{json.dumps(name)},{len(data)},(const unsigned char[]){{{",".join(map(str, data))}}}}},' for name, data in FILES.items())
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>', C_IMAGE,
             f'static const struct {{const char *name;int size;const unsigned char *data;}} files[]={{{table}}};',
             'static void codes(const unsigned char *p,int n){printf("[");for(int i=0;i<n;i++)printf("%s%u",i?",":"",p[i]);puts("]");}',
             'static unsigned char *load_data(const char *name,int *size){printf("[\\"load\\", \\"%s\\"]\\n",name);',
             '  for(unsigned i=0;i<sizeof files/sizeof files[0];i++)if(!strcmp(files[i].name,name)){',
             '    unsigned char *d=malloc(files[i].size);memcpy(d,files[i].data,files[i].size);*size=files[i].size;return d;}',
             '  return NULL;}',
             'static bool save_data(const char *name,void *data,int size){printf("[\\"save\\", \\"%s\\"]\\n",name);codes(data,size);return true;}',
             f'static char *load_text(const char *name){{printf("[\\"load-text\\", \\"%s\\"]\\n",name);'
             f'if(!strcmp(name,"v/text.txt")||!strcmp(name,"{REAL}")){{char *t=malloc({len(TEXT) + 1});strcpy(t,{c_text(TEXT)});return t;}}return NULL;}}',
             'static bool save_text(const char *name,const char *text){printf("[\\"save-text\\", \\"%s\\"]\\n",name);codes((const unsigned char*)text,strlen(text));return true;}',
             'static void loaded(Image im){if(!im.data){puts("null");return;}image(im);UnloadImage(im);}',
             'static Image source(void){Image im={0};for(unsigned i=0;i<sizeof files/sizeof files[0];i++)if(!strcmp(files[i].name,"v/image.png"))'
             '  im=LoadImageFromMemory(".png",files[i].data,files[i].size);return im;}',
             'int main(void){SetTraceLogLevel(LOG_NONE);',
             'SetLoadFileDataCallback(load_data);SetSaveFileDataCallback(save_data);SetLoadFileTextCallback(load_text);SetSaveFileTextCallback(save_text);',
             '{int n=0;unsigned char *d=LoadFileData("v/data.bin",&n);if(d)codes(d,n);else puts("null");UnloadFileData(d);}',
             '{int n=0;unsigned char *d=LoadFileData("v/missing.bin",&n);if(d)codes(d,n);else puts("null");}',
             '{unsigned char d[]={5,6,7};puts(SaveFileData("v/out.bin",d,3)?"true":"false");}',
             '{char *t=LoadFileText("v/text.txt");if(t)codes((unsigned char*)t,strlen(t));else puts("null");UnloadFileText(t);}',
             '{char *t=LoadFileText("v/missing.txt");if(t)codes((unsigned char*)t,strlen(t));else puts("null");}',
             f'puts(SaveFileText("v/out.txt",{c_text("saved text")})?"true":"false");',
             'printf("%d\\n",FileTextFindIndex("v/text.txt","loaders"));',
             f'printf("%d\\n",FileTextFindIndex("{REAL}","loaders"));',
             'printf("%d\\n",FileTextFindIndex("v/missing.txt","x"));',
             'loaded(LoadImage("v/image.png"));loaded(LoadImage("v/image.qoi"));loaded(LoadImage("v/missing.png"));',
             'loaded(LoadImageRaw("v/raw.bin",2,2,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,4));',
             'loaded(LoadImageRaw("v/raw.bin",2,2,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,8));',
             'loaded(LoadImageRaw("v/short.bin",2,2,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,0));',
             '{int frames=0;Image im=LoadImageAnim("v/image.qoi",&frames);printf("%d\\n",im.data?frames:0);loaded(im);}',
             '{Image im=source();puts(ExportImage(im,"v/out.png")?"true":"false");UnloadImage(im);}',
             '{Image im=source();puts(ExportImage(im,"v/out.raw")?"true":"false");UnloadImage(im);}',
             f'{{Image im=source();puts(ExportImage(im,"{BMP}")?"true":"false");UnloadImage(im);}}',
             f'{{SetLoadFileDataCallback(NULL);int n=0;unsigned char *d=LoadFileData("{BMP}",&n);codes(d,n);UnloadFileData(d);SetLoadFileDataCallback(load_data);}}',
             '{Image im=source();puts(ExportImageAsCode(im,"v/out.h")?"true":"false");UnloadImage(im);}',
             '{unsigned char d[]={5,6,7,255};puts(ExportDataAsCode(d,4,"v/data.h")?"true":"false");}',
             'return 0;}']
    return probe.native('\n'.join(lines) + '\n')


R = 'Result<&1, &1, J.Surface.IOError, +List<U32>>'
U = 'Result<&1, &1, J.Surface.IOError, Unit>'
TS = 'Result<&1, &1, J.Surface.IOError, String>'


def bend_program():
    table = '  ' + '\n  '.join(f'found{i} = Bool.pick(Maybe<+List<U32>>, String.eq(path, {json.dumps(name)}), Some{{[{", ".join(map(str, data))}]}}, '
                                 + ('None{}' if i == 0 else f'found{i - 1}') + ')' for i, (name, data) in enumerate(FILES.items()))
    return f'''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
''' + SURFACE_EMITTER + f'''def codes(bytes: +List<U32>) -> IO(Unit):
  IO.print(List.show(~&2, ~U32, ~U32.show, bytes))
def char_codes(text: String) -> +List<U32>:
  match text:
    case SNil{{}}: Nil{{}}
    case SCon{{c, rest}}: Con{{Char.to_u32(c), char_codes(rest)}}
def table(+path: String) -> Maybe<+List<U32>>:
{table}
  found{len(FILES) - 1}
def served(found: Maybe<+List<U32>>) -> IO({R}):
  match found:
    case None{{}}: IO.pure({R}, Fail{{J.FileError{{2, "missing"}}}})
    case Some{{bytes}}: IO.pure({R}, Done{{bytes}})
def load_data.logged(+path: String) -> IO({R}):
  do IO<{R}>:
    Unit <- IO.print("[\\"load\\", \\"" ++ path ++ "\\"]")
    served(table(path))
def load_data(path: String) -> IO({R}):
  load_data.logged(path)
def save_data(path: String, bytes: +List<U32>) -> IO({U}):
  do IO<{U}>:
    Unit <- IO.print("[\\"save\\", \\"" ++ path ++ "\\"]")
    Unit <- codes(bytes)
    IO.pure({U}, Done{{Unit{{}}}})
def load_text.logged(+path: String) -> IO({TS}):
  do IO<{TS}>:
    Unit <- IO.print("[\\"load-text\\", \\"" ++ path ++ "\\"]")
    IO.pure({TS}, Bool.pick({TS}, String.eq(path, "v/text.txt") || String.eq(path, "{REAL}"), Done{{{json.dumps(TEXT)}}}, Fail{{J.FileError{{2, "missing"}}}}))
def load_text(path: String) -> IO({TS}):
  load_text.logged(path)
def save_text(path: String, text: String) -> IO({U}):
  do IO<{U}>:
    Unit <- IO.print("[\\"save-text\\", \\"" ++ path ++ "\\"]")
    Unit <- codes(char_codes(text))
    IO.pure({U}, Done{{Unit{{}}}})
def data(result: {R}) -> IO(Unit):
  match result:
    case Fail{{_}}: IO.print("null")
    case Done{{bytes}}: codes(bytes)
def text(result: {TS}) -> IO(Unit):
  match result:
    case Fail{{_}}: IO.print("null")
    case Done{{value}}: codes(char_codes(value))
def status(result: {U}) -> IO(Unit):
  match result:
    case Fail{{_}}: IO.print("false")
    case Done{{_}}: IO.print("true")
def index(found: Maybe<U32>) -> IO(Unit):
  match found:
    case None{{}}: IO.print("-1")
    case Some{{value}}: IO.print(U32.show(value))
def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{{_}}: IO.print("null")
    case Done{{surface}}: exported(J.Surface.export(surface))
def first(list: List<J.Surface>) -> IO(Unit):
  match list:
    case Nil{{}}: IO.print("null")
    case Con{{surface, _}}: exported(J.Surface.export(surface))
def animation(result: Result<&1, &1, J.Surface.IOError, J.Image.Animation>) -> IO(Unit):
  match result:
    case Fail{{_}}:
      do IO<Unit>:
        Unit <- IO.print("0")
        IO.print("null")
    case Done{{J.Animation{{_, _, count, list}}}}:
      do IO<Unit>:
        Unit <- IO.print(U32.show(count))
        first(list)
def decoded(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> J.Surface:
  match result:
    case Fail{{_}}: J.Surface{{1, 1, 7, J.Words{{[0 : U32^0n]}}}}
    case Done{{surface}}: surface
def source(found: Maybe<+List<U32>>) -> J.Surface:
  match found:
    case None{{}}: J.Surface{{1, 1, 7, J.Words{{[0 : U32^0n]}}}}
    case Some{{bytes}}: decoded(J.Surface.decode_image(".png", bytes))
def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.bind({R}, Unit, J.Files.load_data_with(~load_data, "v/data.bin"), data)
    Unit <- IO.bind({R}, Unit, J.Files.load_data_with(~load_data, "v/missing.bin"), data)
    Unit <- IO.bind({U}, Unit, J.Files.save_data_with(~save_data, "v/out.bin", [5, 6, 7]), status)
    Unit <- IO.bind({TS}, Unit, J.Files.load_text_with(~load_text, "v/text.txt"), text)
    Unit <- IO.bind({TS}, Unit, J.Files.load_text_with(~load_text, "v/missing.txt"), text)
    Unit <- IO.bind({U}, Unit, J.Files.save_text_with(~save_text, "v/out.txt", "saved text"), status)
    Unit <- IO.bind(Maybe<U32>, Unit, J.Files.text_find_index_with(~load_text, "v/text.txt", "loaders"), index)
    Unit <- IO.bind(Maybe<U32>, Unit, J.Files.text_find_index_with(~load_text, "{REAL}", "loaders"), index)
    Unit <- IO.bind(Maybe<U32>, Unit, J.Files.text_find_index_with(~load_text, "v/missing.txt", "x"), index)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_image_with(~load_data, M.Uncontracted{{}}, "v/image.png"), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_image_with(~load_data, M.Uncontracted{{}}, "v/image.qoi"), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_image_with(~load_data, M.Uncontracted{{}}, "v/missing.png"), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw_with(~load_data, "v/raw.bin", 2, 2, 7, 4), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw_with(~load_data, "v/raw.bin", 2, 2, 7, 8), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw_with(~load_data, "v/short.bin", 2, 2, 7, 0), loaded)
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Animation>, Unit, J.Image.Animation.load_image_with(~load_data, M.Uncontracted{{}}, "v/image.qoi", 16, 16777216), animation)
    Unit <- IO.bind({U}, Unit, J.Surface.write_image_with(~save_data, source(table("v/image.png")), "v/out.png"), status)
    Unit <- IO.bind({U}, Unit, J.Surface.write_image_with(~save_data, source(table("v/image.png")), "v/out.raw"), status)
    Unit <- IO.bind({U}, Unit, J.Surface.write_image_with(~save_data, source(table("v/image.png")), "{BMP}"), status)
    Unit <- IO.bind({R}, Unit, J.Files.load_data("{BMP}"), data)
    Unit <- IO.bind({U}, Unit, J.Surface.write_code_with(~save_text, source(table("v/image.png")), "v/out.h"), status)
    IO.bind({U}, Unit, J.Files.export_data_as_code_with(~save_text, [5, 6, 7, 255], "v/data.h"), status)
'''


def main():
    probe = probekit.Probe('loaders', probekit.arguments(__doc__))
    (ROOT / BMP).unlink(missing_ok=True)
    (ROOT / REAL).write_text('real content without the search word\n')
    expected = [json.loads(line) for line in native(probe).splitlines()]
    if '7' not in [json.dumps(row) for row in expected] or ['load', 'v/image.png'] not in expected or ['save', 'v/out.png'] not in expected or ['save', 'v/out.raw'] not in expected:
        raise ProbeFailure('loaders: native callbacks were not called as expected')

    def parse(text, selected):
        return [[json.loads(line) for line in text.splitlines()]]
    lanes = probe.candidates(lambda selected, gpu: bend_program(), ['all calls'], batch=1, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare([expected], lanes, describe=lambda i: 'callback log and results')
    probe.finish(lines=len(expected), loads=sum(row[:1] == ['load'] for row in expected if isinstance(row, list)),
                 saves=sum(row[:1] in (['save'], ['save-text']) for row in expected if isinstance(row, list)))


if __name__ == '__main__':
    main()
