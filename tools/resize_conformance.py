#!/usr/bin/env python3
"""Exact coefficient-bit, filtered-image and 1..3-channel layout probes against pinned raylib/stb."""
import hashlib
import json
import math
import platform
import random
import struct

if __package__:
    from .byte_probe import C_IMAGE, SURFACE_EMITTER, parse_results
    from .conformance import BUILD, ROOT, bend_source, cases_from, c_source, f32, parse_output, result_size, source_gate
    from . import probekit
    from .probekit import ProbeFailure
else:
    from byte_probe import C_IMAGE, SURFACE_EMITTER, parse_results
    from conformance import BUILD, ROOT, bend_source, cases_from, c_source, f32, parse_output, result_size, source_gate
    import probekit
    from probekit import ProbeFailure

STB_FLAGS = ('-O3', '-fno-strict-aliasing')
KERNEL_PAIRS = [(w, out) for w in range(1, 18) for out in range(1, 18)]
LANE_ALIASES = {'cpu': ('cpu-1', 'cpu-2'), 'metal': ('gpu',)}


def integer_rows(text):
    return [[int(value) for value in line.split()] for line in text.splitlines() if line.strip()]


def coefficient_vectors(source, work, probe):
    """Observe the stock normalization step, before clamp-edge folding."""
    header = (source / 'src/external/stb_image_resize2.h').read_text()
    start = '    // add all contribs\n'
    finish = '    ++contribs;\n    coeffs += coefficient_width;\n'
    if header.count(start) != 1 or header.count(finish) != 2:
        raise ValueError('Pinned coefficient instrumentation anchors changed')
    instrumented = header.replace(start, '''    printf("{\\"input\\":[");
    for (int q=0;q<=contribs->n1-contribs->n0;q++) {
      unsigned bits; memcpy(&bits,coeffs+q,4); printf("%s%u",q?",":"",bits);
    }
    printf("],\\"output\\":[");
''' + start).replace(finish, '''    for (int q=0;q<=e;q++) {
      unsigned bits; memcpy(&bits,coeffs+q,4); printf("%s%u",q?",":"",bits);
    }
    printf("]}\\n");
''' + finish, 1)
    observed = work / 'stb_observed.h'
    observed.write_text(instrumented)
    program = '''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define STB_IMAGE_RESIZE_STATIC
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STBIR__HEADER_FILENAME "stb_observed.h"
#include "stb_observed.h"
int main(void) {
  for(int w=1;w<=17;w++) for(int n=1;n<=17;n++) {
    unsigned char *in=calloc(w,4);
    unsigned char *out=stbir_resize_uint8_linear(in,w,1,0,NULL,n,1,0,STBIR_RGBA);
    if (!out) return 2;
    free(in); free(out);
  }
  return 0;
}
'''
    # The observed header sits beside the generated source; no raylib symbol is referenced.
    text = probe.native(program, 'coefficients', extra_flags=STB_FLAGS)
    rows = [json.loads(line) for line in text.splitlines()]
    unique = {}
    for row in rows:
        key = tuple(row['input'])
        if key in unique and unique[key] != row['output']:
            raise ValueError('Identical stock inputs had inconsistent normalization')
        unique[key] = row['output']
    if not unique:
        raise ValueError('No normalization vectors observed')
    vectors = [dict(input=list(key), output=value) for key, value in unique.items()]
    (work / 'coefficient-vectors.json').write_text(json.dumps(vectors, indent=2) + '\n')
    return vectors, hashlib.sha256(header.encode()).hexdigest()


def bend_coefficients(vectors, gpu=False):
    lines = ['import Base', 'import ../../src/resize_numeric.bend as N',
             'def bits(values: +List<F32>) -> List<U32>:', '  match values:',
             '    case Nil{}: Nil{}', '    case Con{v, rest}: Con{F32.bits(v), bits(rest)}',
             'def normalize(groups: List<+List<F32>>) -> List<List<U32>>:',
             '  match groups:', '    case Nil{}: Nil{}',
             '    case Con{group, rest}: Con{bits(N.normalize(group)), normalize(rest)}',
             'def show.row(values: List<U32>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: U32.show(v) ++ " " ++ show.row(rest)',
             'def show(values: List<List<U32>>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: show.row(v) ++ "\\n" ++ show(rest)',
             '']
    batches = [vectors[i:i+16] for i in range(0, len(vectors), 16)]
    for batch, rows in enumerate(batches):
        lines += [f'def inputs_{batch}() -> List<+List<F32>>:', '  [']
        for index, row in enumerate(rows):
            values = [struct.unpack('<f', struct.pack('<I', value))[0] for value in row['input']]
            lines.append('    [' + ', '.join(f32(value) for value in values) + ']' + (',' if index+1<len(rows) else ''))
        lines += ['  ]']
    lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
    for batch in range(len(batches)):
        lines += [f'    IO.print(show(normalize{"!" if gpu else ""}(inputs_{batch}())))']
    return '\n'.join(lines) + '\n'


KERNEL_PROGRAM = '''#include <stdio.h>
#include <string.h>
#define STB_IMAGE_RESIZE_STATIC
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "external/stb_image_resize2.h"
int main(void) {
  for(int w=1;w<=17;w++) for(int n=1;n<=17;n++) {
    STBIR_RESIZE r;
    stbir_resize_init(&r,NULL,w,1,0,NULL,n,1,0,STBIR_RGBA,STBIR_TYPE_UINT8);
    if (!stbir_build_samplers(&r)) return 2;
    stbir__sampler *s=&r.samplers->horizontal;
    for(int p=0;p<n;p++) {
      stbir__contributors c=s->contributors[p];
      printf("%d",c.n0);
      for(int j=0;j<=c.n1-c.n0;j++) {
        unsigned bits; memcpy(&bits,s->coefficients+p*s->coefficient_width+j,4);
        printf(" %u",bits);
      }
      printf("\\n");
    }
    stbir_free_samplers(&r);
  }
  return 0;
}
'''


def kernel_vectors(probe):
    return integer_rows(probe.native(KERNEL_PROGRAM, 'kernels', extra_flags=STB_FLAGS))


def bend_kernels(gpu=False, pairs=None):
    lines = ['import Base', 'import ../../src/resample.bend as R',
             'def bits(values: +List<F32>) -> List<U32>:', '  match values:',
             '    case Nil{}: Nil{}', '    case Con{v, rest}: Con{F32.bits(v), bits(rest)}',
             'def row(kernel: R.Kernel) -> List<U32>:', '  R.Kernel{first, weights} = kernel',
             '  Con{F32.to_u32(first), bits(weights)}',
             'def kernels(n: Nat, +i: U32, +w: U32, +out: U32) -> +List<R.Kernel>:',
             '  match n:', '    case 0n: Nil{}',
             '    case 1n+k: Con{R.Kernel.make(w, out, i), kernels(k, (i + 1 : U32), w, out)}',
             'def width(kernel: R.Kernel) -> U32:', '  R.Kernel{_, weights} = kernel',
             '  U32.from_nat(List.length(&2, F32, weights))',
             'def widest(values: +List<R.Kernel>) -> U32:', '  match values:',
             '    case Nil{}: 0', '    case Con{v, rest}: U32.max(width(v), widest(rest))',
             'def pack(values: +List<R.Kernel>, +wide: U32, +size: U32) -> List<List<U32>>:',
             '  match values:', '    case Nil{}: Nil{}',
             '    case Con{v, rest}: Con{row(R.Kernel.pack(wide, size, v)), pack(rest, wide, size)}',
             'def encoded(+values: +List<R.Kernel>, size: U32) -> List<List<U32>>:',
             '  pack(values, widest(values), size)',
             'def all(n: Nat, +w: U32, out: U32) -> List<List<U32>>:',
             '  encoded(kernels(n, 0, w, out), w)',
             'def show.row(values: List<U32>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: U32.show(v) ++ " " ++ show.row(rest)',
             'def show(values: List<List<U32>>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: show.row(v) ++ "\\n" ++ show(rest)',
             'def main() -> IO(Unit):', '  do IO<Unit>:']
    for w, out in KERNEL_PAIRS if pairs is None else pairs:
        lines.append(f'    IO.print(show(all{"!" if gpu else ""}({out}n, {w}, {out})))')
    return '\n'.join(lines) + '\n'


def kernel_groups(rows, pairs):
    """One group of `out` packed kernels per (width, out) action."""
    if len(rows) != sum(out for _, out in pairs):
        raise ProbeFailure(f'resize: {len(rows)} kernel rows for {sum(out for _, out in pairs)} expected')
    groups, at = [], 0
    for _, out in pairs:
        groups.append(rows[at:at+out])
        at += out
    return groups


def image_cases():
    rng = random.Random(20260925)
    cases = []
    for i in range(512):
        w, h, nw, nh = [rng.randint(1, limit) for limit in (11, 9, 17, 15)]
        pixels = [[rng.randrange(256), rng.randrange(256), rng.randrange(256),
                   rng.choice([0, 1, 2, 64, 128, 254, 255])] for _ in range(w*h)]
        operations = [dict(op='pixel', x=j%w, y=j//w, color=pixel) for j,pixel in enumerate(pixels)]
        operations.append(dict(op='resize', width=nw, height=nh))
        cases.append(dict(id=f'resize-{i:03}', width=w, height=h, background=[0,0,0,0], operations=operations))
    for i, (w,h,nw,nh,alpha) in enumerate([
        (1,1,1,1,0), (1,1,17,9,0), (7,5,7,5,255), (7,5,3,9,0),
        (31,1,3,1,255), (1,65,1,2,None), (33,35,3,2,None), (3,2,33,35,None),
        (17,13,1,1,None), (17,17,5,4,None), (17,17,2,17,None),
        (64,7,7,4,None), (4,64,13,1,None), (4096,1,1,1,None), (1,4096,1,1,None),
        (1,1,4096,1,128), (1,1,1,4096,128),
    ]):
        pixels = [[rng.randrange(256),rng.randrange(256),rng.randrange(256),
                   rng.choice([0,1,128,255]) if alpha is None else alpha] for _ in range(w*h)]
        if w*h > 512:
            # Large boundary images use 16 mixed-alpha bands, keeping generated
            # programs bounded while exercising the complete source allocation.
            horizontal = w >= h
            extent = w if horizontal else h
            step = (extent + 15) // 16
            operations = [dict(op='rectangle', x=at if horizontal else 0, y=0 if horizontal else at,
                               width=min(step,extent-at) if horizontal else w,
                               height=h if horizontal else min(step,extent-at), color=pixels[at//step])
                          for at in range(0,extent,step)]
        else:
            operations = [dict(op='pixel', x=j%w, y=j//w, color=pixel) for j,pixel in enumerate(pixels)]
        operations.append(dict(op='resize', width=nw, height=nh))
        cases.append(dict(id=f'resize-boundary-{i:02}', width=w, height=h, background=[0,0,0,0], operations=operations))
    return cases_from(dict(schema=1, cases=cases))


def resize_probe(args, results):
    """A probekit run kept in .build/resize (the gate's published report location)."""
    probe = probekit.Probe('resize', args)
    probe.results.unlink(missing_ok=True)
    try:
        probe.work.rmdir()
    except OSError:
        pass
    probe.work = BUILD / 'resize'
    probe.work.mkdir(parents=True, exist_ok=True)
    probe.results = results
    probe.save()
    return probe


def selected_lanes(probe):
    names = probe.lanes
    if getattr(probe.args, 'lane', None):
        names = LANE_ALIASES.get(probe.args.lane, (probe.args.lane,))
    return names


def verify_images(args, work, probe=None):
    report_path = work / 'images-results.json'
    report_path.write_text(json.dumps(dict(passed=False)) + '\n')
    cases = image_cases()
    if args.case_prefix:
        cases = cases_from(dict(schema=1, cases=[case for case in cases if case['id'].startswith(args.case_prefix)]))
    probe = probe or resize_probe(args, report_path)
    (work / 'images.json').write_text(json.dumps(dict(schema=1, cases=cases), indent=2) + '\n')
    reference_text = probe.native(c_source(cases), 'images-reference')
    (work / 'images-reference.jsonl').write_text(reference_text)
    reference = parse_output(reference_text, cases)
    report = dict(passed=False, scenarios=len(cases), pixels=sum(w*h for w,h in map(result_size,cases)), lanes={},
                  source_sha256=source_gate(), fixtures_sha256=hashlib.sha256(json.dumps(cases,sort_keys=True).encode()).hexdigest(),
                  retained_counterexamples=[31,136,200,386], toolchain=json.loads((ROOT/'toolchain.json').read_text()),
                  host=dict(system=platform.system(), machine=platform.machine()),
                  reference_library_sha256=hashlib.sha256(probe.library.read_bytes()).hexdigest())
    if report_path != probe.results:
        report_path.write_text(json.dumps(report, indent=2) + '\n')

    def render(selected, gpu):
        return bend_source(selected, gpu=gpu).replace('import ../jonlib.bend', 'import ../../jonlib.bend').replace('import ../jonmath.bend', 'import ../../jonmath.bend')

    lanes = probe.candidates(render, cases, batch=64, parse=lambda text, selected: parse_output(text, selected))
    lanes = {name: rows for name, rows in lanes.items() if name in selected_lanes(probe)}
    for name, rows in lanes.items():
        (work / f'images-{name}.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in rows))
    probe.compare(reference, lanes, describe=lambda i: cases[i]['id'])
    for name in lanes:
        report['lanes'][name] = dict(passed=True)
        print(f'{name}: {len(cases)} default resize images, {report["pixels"]} exact pixels', flush=True)
    report['passed'] = True
    if report_path != probe.results:
        report_path.write_text(json.dumps(report, indent=2) + '\n')
    return report


# ImageResize filters these formats' bytes directly with stbir 1..3-channel layouts.
LAYOUT_FORMATS = {1: 1, 2: 2, 4: 3}
LAYOUT_PIXELS = 512
LAYOUT_PROGRAM = '''import Base
import ../../jonlib.bend as J
''' + SURFACE_EMITTER + '''def resized(source: Maybe<J.Surface>, +width: U32, +height: U32) -> IO(Unit):
  match source:
    case None{}: IO.die(Unit, 1, "fixture creation failed")
    case Some{surface}: image(J.Surface.resize(surface, width, height))
'''


def stbir_class(sw, sh, nw, nh):
    """stbir__should_do_vertical_first's v_classification, mirrored to prove corpus coverage."""
    vs = nh / sh
    vw = 1 if sh == nh else 4 if nh > sh else math.ceil(4 / vs)
    gather = vw <= 32
    if nw <= 4 or nh <= 4:
        return 6 if nh < nw else 7
    if not gather and (nw <= 16 or nh <= 16):
        return 4
    if vs <= 1:
        return 1 if gather else 0
    return 2 if vs <= 2 else 3 if vs <= 3 else 5


def layout_cases():
    """GRAYSCALE, GRAY_ALPHA and R8G8B8 resizes: 1..3-coefficient kernels, both
    pass orders and every vertical-first cost class."""
    rng = random.Random(20261007)
    # Literal fixtures stay within LAYOUT_PIXELS (long list literals exhaust the JavaScript stack).
    sizes = [(1, 1, 1, 1), (1, 1, 9, 7), (3, 1, 1, 1), (2, 2, 3, 3), (3, 3, 5, 2), (5, 3, 2, 2), (7, 5, 7, 5),
             (9, 4, 3, 4), (17, 13, 4, 3), (4, 3, 17, 13), (31, 2, 5, 9), (2, 31, 9, 5), (64, 5, 3, 2),
             (5, 64, 2, 3), (20, 12, 17, 3), (12, 20, 3, 17), (23, 17, 3, 2), (13, 11, 13, 2), (13, 11, 2, 11),
             (1, 140, 17, 17), (2, 100, 5, 6), (6, 9, 7, 17), (9, 6, 9, 15), (8, 5, 8, 7), (19, 15, 23, 19)]
    sizes += [tuple(rng.randint(1, limit) for limit in (19, 15, 23, 19)) for _ in range(56)]
    classes = {stbir_class(*size) for size in sizes}
    if classes != set(range(8)) or max(w * h for w, h, _, _ in sizes) > LAYOUT_PIXELS:
        raise ValueError(f'layout corpus misses cost classes {sorted(set(range(8)) - classes)} or exceeds {LAYOUT_PIXELS} pixels')
    return [dict(id=f'layout-{fmt}-{i:02}', format=fmt, width=w, height=h, new_width=nw, new_height=nh,
                 bytes=[rng.randrange(256) for _ in range(w * h * channels)])
            for fmt, channels in LAYOUT_FORMATS.items() for i, (w, h, nw, nh) in enumerate(sizes)]


# Seeded native search over the stock stb header (standalone, no raylib). It
# first checks the 1..3-channel horizontal lane model against stbir on every
# sampled channel output, then emits fixtures that pin details random images
# almost never expose: rows whose bytes change under a serial, two-lane or
# other three-term sum, and sizes where a layout's cost table picks another
# pass order than the RGBA table (forced through stbir's v-first test hook).
LAYOUT_SEARCH = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define STB_IMAGE_RESIZE_STATIC
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STBIR__V_FIRST_INFO_BUFFER stbir_vfirst
#include "external/stb_image_resize2.h"

static unsigned state = 20261007u;
static unsigned next(void) { state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state; }
static unsigned char encode(float v) { float f = v + 0.5f; if (!(f > 0)) f = 0; if (f > 255) f = 255; return (unsigned char)f; }
static void emit(const char *pins, int layout, int sw, int sh, int nw, int nh, const unsigned char *bytes) {
  printf("{\"pins\":\"%s\",\"layout\":%d,\"width\":%d,\"height\":%d,\"new_width\":%d,\"new_height\":%d,\"bytes\":[", pins, layout, sw, sh, nw, nh);
  for (int i = 0; i < sw * sh * layout; i++) printf("%s%u", i ? "," : "", bytes[i]);
  printf("]}\n");
}

/* Horizontal sum of one packed kernel: order 0 is stbir's for the layout,
   1 serial, 2 two alternating lanes, 3 the other three-term association. */
static float sum(int order, int layout, int width, const float *p) {
  if (order == 1) { float t = p[0]; for (int j = 1; j < width; j++) t = t + p[j]; return t; }
  if (order == 2) { float e = 0, o = 0; for (int j = 0; j < width; j++) if (j & 1) o = o + p[j]; else e = e + p[j]; return e + o; }
  if (width == 3) return ((layout == 2) != (order == 3)) ? (p[0] + p[2]) + p[1] : (p[0] + p[1]) + p[2];
  float l[4] = {0, 0, 0, 0};
  for (int j = 0; j < width; j++) l[j & 3] = l[j & 3] + p[j];
  return (l[0] + l[2]) + (l[1] + l[3]);
}

int main(void) {
  static const char *names[4] = {"", "serial-sum", "two-lane-sum", "three-term-order"};
  long checked = 0;
  for (int layout = 1; layout <= 3; layout++) {
    int found[4] = {0, 0, 0, 0};
    for (int sw = 3; sw <= 6; sw++) for (int nw = 1; nw <= 17; nw++) {
      STBIR_RESIZE r;
      stbir_resize_init(&r, NULL, sw, 1, 0, NULL, nw, 1, 0, (stbir_pixel_layout)layout, STBIR_TYPE_UINT8);
      if (!stbir_build_samplers(&r)) return 2;
      stbir__sampler *s = &r.samplers->horizontal;
      int width = s->coefficient_width;
      for (int trial = 0; trial < 60000; trial++) {
        unsigned char row[18], out[51];
        for (int i = 0; i < sw * layout; i++) row[i] = next() & 255;
        if (!stbir_resize_uint8_linear(row, sw, 1, 0, out, nw, 1, 0, (stbir_pixel_layout)layout)) return 3;
        for (int p = 0; p < nw; p++) for (int k = 0; k < layout; k++) {
          float terms[16] = {0}; int n0 = s->contributors[p].n0;
          for (int j = 0; j < width; j++) terms[j] = (n0 + j < sw ? (float)row[(n0 + j) * layout + k] : 0) * s->coefficients[p * width + j];
          unsigned char stock = encode(sum(0, layout, width, terms));
          checked++;
          if (stock != out[p * layout + k]) { fprintf(stderr, "lane model differs from stbir: layout %d, %d->%d, pixel %d\n", layout, sw, nw, p); return 4; }
          for (int order = 1; order <= 3; order++)
            if ((order == 3) == (width == 3) && found[order] < 3 && encode(sum(order, layout, width, terms)) != stock) {
              found[order]++;
              emit(names[order], layout, sw, 1, nw, 1, row);
            }
        }
      }
      stbir_free_samplers(&r);
    }
  }
  fprintf(stderr, "%ld channel outputs match the lane model\n", checked);
  /* Part B: sizes whose layout cost table picks another pass order than the RGBA table. */
  for (int layout = 1; layout <= 3; layout++) {
    int found = 0;
    for (int area = 2; area <= 512 && found < 4; area++)
      for (int sw = 1; sw <= area && found < 4; sw++) {
        if (area % sw) continue;
        int sh = area / sw, hit = 0;
        for (int nw = 5; nw <= 24 && !hit; nw += 3) for (int nh = 5; nh <= 24 && !hit; nh += 3) {
          int first[2];
          for (int v = 0; v < 2; v++) {
            STBIR_RESIZE r;
            stbir_resize_init(&r, NULL, sw, sh, 0, NULL, nw, nh, 0, v ? STBIR_RGBA : (stbir_pixel_layout)layout, STBIR_TYPE_UINT8);
            if (!stbir_build_samplers(&r)) return 5;
            first[v] = r.samplers->vertical_first;
            stbir_free_samplers(&r);
          }
          if (first[0] == first[1]) continue;
          unsigned char *in = malloc(area * layout), *a = malloc(nw * nh * layout), *b = malloc(nw * nh * layout);
          for (int trial = 0; trial < 4000; trial++) {
            for (int i = 0; i < area * layout; i++) in[i] = next() & 255;
            stbir_vfirst.control_v_first = 1;
            stbir_resize_uint8_linear(in, sw, sh, 0, a, nw, nh, 0, (stbir_pixel_layout)layout);
            stbir_vfirst.control_v_first = 2;
            stbir_resize_uint8_linear(in, sw, sh, 0, b, nw, nh, 0, (stbir_pixel_layout)layout);
            stbir_vfirst.control_v_first = 0;
            if (memcmp(a, b, nw * nh * layout)) { emit("pass-order", layout, sw, sh, nw, nh, in); found++; hit = 1; break; }
          }
          free(in); free(a); free(b);
        }
      }
    if (found < 4) { fprintf(stderr, "layout %d: only %d pass-order discriminators\n", layout, found); return 6; }
  }
  return 0;
}
'''


def layout_search(probe):
    text = probe.native(LAYOUT_SEARCH, 'layouts-search', extra_flags=(*STB_FLAGS, '-ffp-contract=off'), link_raylib=False)
    found = [json.loads(line) for line in text.splitlines()]
    formats = {layout: fmt for fmt, layout in LAYOUT_FORMATS.items()}
    return [dict(id=f'layout-{formats[row["layout"]]}-{row["pins"]}-{i:02}', format=formats[row['layout']],
                 **{key: row[key] for key in ('width', 'height', 'new_width', 'new_height', 'bytes')})
            for i, row in enumerate(found)]


def layout_native(cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>', C_IMAGE]
    for i, case in enumerate(cases):
        lines.append(f'static const unsigned char data{i}[]={{{",".join(map(str, case["bytes"]))}}};')
    lines.append('int main(void){SetTraceLogLevel(LOG_NONE);')
    for i, case in enumerate(cases):
        lines.append(f'{{Image im={{0}};im.width={case["width"]};im.height={case["height"]};im.mipmaps=1;im.format={case["format"]};'
                     f'im.data=malloc(sizeof data{i});memcpy(im.data,data{i},sizeof data{i});'
                     f'ImageResize(&im,{case["new_width"]},{case["new_height"]});image(im);UnloadImage(im);}}')
    return '\n'.join(lines + ['return 0;}']) + '\n'


def layout_render(selected, gpu):
    body = LAYOUT_PROGRAM
    for i, case in enumerate(selected):
        body += (f'def source{i}() -> Maybe<J.Surface>:\n  J.Surface.from_bytes({case["width"]}, {case["height"]}, '
                 f'{case["format"]}, [{",".join(map(str, case["bytes"]))}])\n')
    body += 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for i, case in enumerate(selected):
        body += f'    resized(source{i}(), {case["new_width"]}, {case["new_height"]})\n'
    return body


def verify_layouts(probe, work):
    searched = layout_search(probe)
    cases = layout_cases() + searched
    (work / 'layouts.json').write_text(json.dumps(cases) + '\n')
    expected = parse_results(probe.native(layout_native(cases), 'layouts-reference'))
    if len(expected) != len(cases) or None in expected:
        raise ProbeFailure('resize: native layout reference is incomplete')
    lanes = probe.candidates(layout_render, cases, batch=96, parse=lambda text, selected: parse_results(text))
    lanes = {name: rows for name, rows in lanes.items() if name in selected_lanes(probe)}
    probe.compare(expected, lanes, describe=lambda i: cases[i]['id'])
    for name in lanes:
        print(f'{name}: {len(cases)} GRAYSCALE/GRAY_ALPHA/R8G8B8 resizes exact', flush=True)
    return dict(scenarios=len(cases), searched=len(searched), formats=sorted(LAYOUT_FORMATS), bytes=sum(len(row) for row in expected),
                fixtures_sha256=hashlib.sha256(json.dumps(cases, sort_keys=True).encode()).hexdigest())


def main():
    def configure(parser):
        parser.add_argument('--images-only', action='store_true', help='Run whole-image comparisons without repeating coefficient probes')
        parser.add_argument('--layouts-only', action='store_true', help='Run only the GRAYSCALE/GRAY_ALPHA/R8G8B8 layout corpus')
        parser.add_argument('--lane', choices=('cpu-1', 'cpu-2', 'javascript', 'gpu', *LANE_ALIASES),
                            help='Compare/report one image lane for focused diagnosis (cpu: both CPU lanes; metal: gpu)')
        parser.add_argument('--case-prefix', help='Select image cases by stable ID prefix for focused diagnosis')
    args = probekit.arguments(__doc__, configure)
    if args.lane in ('gpu', 'metal') and not args.gpu:
        raise SystemExit(f'--lane {args.lane} requires --gpu')
    work = BUILD / 'resize'
    work.mkdir(parents=True, exist_ok=True)
    host = dict(system=platform.system(), machine=platform.machine())
    if args.layouts_only:
        probe = resize_probe(args, work / 'layouts-results.json')
        probe.report.update(scope='layouts-only', source_sha256=source_gate(), host=host)
        layouts = verify_layouts(probe, work)
        probe.finish(**layouts)
        return
    if args.images_only:
        probe = resize_probe(args, work / 'images-results.json')
        images = verify_images(args, work, probe)
        probe.report.update({k: v for k, v in images.items() if k not in ('passed', 'lanes')}, scope='images-only',
                            case_prefix=args.case_prefix, lane=args.lane)
        probe.finish(scenarios=images['scenarios'], pixels=images['pixels'], fixtures_sha256=images['fixtures_sha256'])
        return
    probe = resize_probe(args, work / 'results.json')
    probe.report.update(scope='full', source_sha256=source_gate(), host=host, stages={})
    vectors, header_hash = coefficient_vectors(args.raylib_source, work, probe)
    expected = [row['output'] for row in vectors]
    lanes = probe.candidates(lambda selected, gpu: bend_coefficients(selected, gpu), vectors, batch=len(vectors),
                             parse=lambda text, selected: integer_rows(text))
    for name, rows in lanes.items():
        (work / f'coefficients-{name}.json').write_text(json.dumps(rows) + '\n')
    probe.compare(expected, lanes, describe=lambda i: f'normalization vector {i}')
    probe.report.update(normalization_vectors=len(vectors), coefficients=sum(map(len, expected)), header_sha256=header_hash)
    probe.report['stages']['coefficients'] = json.loads(json.dumps(probe.report['lanes']))
    for name in lanes:
        print(f'{name}: {len(vectors)} normalization vectors, {probe.report["coefficients"]} coefficient bits exact', flush=True)
    expected_kernels = kernel_vectors(probe)
    (work / 'kernels-reference.json').write_text(json.dumps(expected_kernels) + '\n')
    lanes = probe.candidates(lambda selected, gpu: bend_kernels(gpu, selected), KERNEL_PAIRS, batch=len(KERNEL_PAIRS),
                             parse=lambda text, selected: kernel_groups(integer_rows(text), selected))
    for name, groups in lanes.items():
        (work / f'kernels-{name}.json').write_text(json.dumps([row for group in groups for row in group]) + '\n')
    probe.compare(kernel_groups(expected_kernels, KERNEL_PAIRS), lanes, describe=lambda i: f'kernels for width/out {KERNEL_PAIRS[i]}')
    probe.report['kernels'] = len(expected_kernels)
    probe.report['stages']['kernels'] = json.loads(json.dumps(probe.report['lanes']))
    for name in lanes:
        print(f'{name}: {len(expected_kernels)} kernels match exact first index and coefficient bits', flush=True)
    images = verify_images(args, work, probe)
    probe.report['images'] = images
    probe.report['stages']['images'] = json.loads(json.dumps(probe.report['lanes']))
    probe.report['layouts'] = verify_layouts(probe, work)
    probe.finish(normalization_vectors=len(vectors), coefficients=probe.report['coefficients'], kernels=len(expected_kernels),
                 scenarios=images['scenarios'], pixels=images['pixels'], layout_scenarios=probe.report['layouts']['scenarios'])


if __name__ == '__main__':
    main()
