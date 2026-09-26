#!/usr/bin/env python3
"""Full-pixel differential tests. Requires existing pinned checkouts; installs nothing."""
import argparse
from decimal import Decimal
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import platform
import time
import struct

UNARY_IMAGE_APIS = {'flip_horizontal':'ImageFlipHorizontal', 'flip_vertical':'ImageFlipVertical',
                    'rotate_cw':'ImageRotateCW', 'rotate_ccw':'ImageRotateCCW', 'color_invert':'ImageColorInvert',
                    'alpha_premultiply':'ImageAlphaPremultiply'}
COLOR_IMAGE_APIS = {'color_tint':'ImageColorTint', 'color_contrast':'ImageColorContrast',
                   'color_brightness':'ImageColorBrightness', 'color_replace':'ImageColorReplace'}
COLOR_VALUE_APIS = {'alpha':('ColorAlpha','with_alpha'), 'fade':('Fade','with_alpha'),
                   'tint':('ColorTint','multiply'), 'brightness':('ColorBrightness','brightness'),
                   'contrast':('ColorContrast','contrast'), 'lerp':('ColorLerp','lerp'), 'equal':('ColorIsEqual','is_equal')}
MATH_APIS = {'clamp':('Clamp',3), 'lerp':('Lerp',3), 'normalize':('Normalize',3),
             'remap':('Remap',5), 'wrap':('Wrap',3), 'float_equals':('FloatEquals',2)}
VECTOR2_APIS = {
    'zero':('Vector2Zero','','vector'), 'one':('Vector2One','','vector'),
    'add':('Vector2Add','vv','vector'), 'add_value':('Vector2AddValue','vs','vector'),
    'subtract':('Vector2Subtract','vv','vector'), 'subtract_value':('Vector2SubtractValue','vs','vector'),
    'scale':('Vector2Scale','vs','vector'), 'multiply':('Vector2Multiply','vv','vector'),
    'negate':('Vector2Negate','v','vector'), 'divide':('Vector2Divide','vv','vector'),
    'invert':('Vector2Invert','v','vector'), 'lerp':('Vector2Lerp','vvs','vector'),
    'reflect':('Vector2Reflect','vv','vector'), 'length_sqr':('Vector2LengthSqr','v','float'),
    'distance_sqr':('Vector2DistanceSqr','vv','float'), 'dot_product':('Vector2DotProduct','vv','float'),
    'cross_product':('Vector2CrossProduct','vv','float'), 'equals':('Vector2Equals','vv','bool'),
    'length':('Vector2Length','v','float'), 'normalize':('Vector2Normalize','v','vector'),
    'distance':('Vector2Distance','vv','float'), 'move_towards':('Vector2MoveTowards','vvs','vector'),
    'clamp':('Vector2Clamp','vvv','vector'), 'clamp_value':('Vector2ClampValue','vss','vector'),
    'refract':('Vector2Refract','vvs','vector'), 'rotate':('Vector2Rotate','vs','vector'),
    'min':('Vector2Min','vv','vector'), 'max':('Vector2Max','vv','vector'),
    'transform':('Vector2Transform','vm','vector'),
}
VECTOR3_APIS = {
    'zero':('Vector3Zero','','vector'), 'one':('Vector3One','','vector'),
    'add':('Vector3Add','tt','vector'), 'subtract':('Vector3Subtract','tt','vector'),
    'scale':('Vector3Scale','ts','vector'), 'multiply':('Vector3Multiply','tt','vector'),
    'cross_product':('Vector3CrossProduct','tt','vector'), 'dot_product':('Vector3DotProduct','tt','float'),
    'distance_sqr':('Vector3DistanceSqr','tt','float'),
    'add_value':('Vector3AddValue','ts','vector'), 'subtract_value':('Vector3SubtractValue','ts','vector'),
    'negate':('Vector3Negate','t','vector'), 'divide':('Vector3Divide','tt','vector'),
    'length':('Vector3Length','t','float'), 'length_sqr':('Vector3LengthSqr','t','float'),
    'distance':('Vector3Distance','tt','float'), 'normalize':('Vector3Normalize','t','vector'),
    'project':('Vector3Project','tt','vector'), 'reject':('Vector3Reject','tt','vector'),
    'perpendicular':('Vector3Perpendicular','t','vector'), 'lerp':('Vector3Lerp','tts','vector'),
    'reflect':('Vector3Reflect','tt','vector'), 'invert':('Vector3Invert','t','vector'),
    'equals':('Vector3Equals','tt','bool'), 'move_towards':('Vector3MoveTowards','tts','vector'),
    'clamp':('Vector3Clamp','ttt','vector'), 'clamp_value':('Vector3ClampValue','tss','vector'),
    'refract':('Vector3Refract','tts','vector'),
    'min':('Vector3Min','tt','vector'), 'max':('Vector3Max','tt','vector'),
    'barycenter':('Vector3Barycenter','tttt','vector'),
    'cubic_hermite':('Vector3CubicHermite','tttts','vector'),
    'ortho_normalize':('Vector3OrthoNormalize','tt','pair'),
    'transform':('Vector3Transform','tm','vector'),
    'to_float_v':('Vector3ToFloatV','t','buffer'),
}
VECTOR4_APIS = {
    'zero':('Vector4Zero','','vector'), 'one':('Vector4One','','vector'),
    'add':('Vector4Add','qq','vector'), 'subtract':('Vector4Subtract','qq','vector'),
    'scale':('Vector4Scale','qs','vector'), 'multiply':('Vector4Multiply','qq','vector'),
    'add_value':('Vector4AddValue','qs','vector'), 'subtract_value':('Vector4SubtractValue','qs','vector'),
    'length':('Vector4Length','q','float'), 'length_sqr':('Vector4LengthSqr','q','float'),
    'dot_product':('Vector4DotProduct','qq','float'), 'distance':('Vector4Distance','qq','float'),
    'distance_sqr':('Vector4DistanceSqr','qq','float'), 'negate':('Vector4Negate','q','vector'),
    'divide':('Vector4Divide','qq','vector'), 'normalize':('Vector4Normalize','q','vector'),
    'min':('Vector4Min','qq','vector'), 'max':('Vector4Max','qq','vector'),
    'lerp':('Vector4Lerp','qqs','vector'), 'move_towards':('Vector4MoveTowards','qqs','vector'),
    'invert':('Vector4Invert','q','vector'), 'equals':('Vector4Equals','qq','bool'),
}
QUATERNION_APIS = {
    'identity':('QuaternionIdentity','','vector'), 'add':('QuaternionAdd','qq','vector'),
    'subtract':('QuaternionSubtract','qq','vector'), 'multiply':('QuaternionMultiply','qq','vector'),
    'add_value':('QuaternionAddValue','qs','vector'), 'subtract_value':('QuaternionSubtractValue','qs','vector'),
    'length':('QuaternionLength','q','float'), 'normalize':('QuaternionNormalize','q','vector'),
    'invert':('QuaternionInvert','q','vector'), 'scale':('QuaternionScale','qs','vector'),
    'divide':('QuaternionDivide','qq','vector'), 'lerp':('QuaternionLerp','qqs','vector'),
    'nlerp':('QuaternionNlerp','qqs','vector'), 'equals':('QuaternionEquals','qq','bool'),
}
COLOR_VECTOR3_APIS = {'to_hsv':('ColorToHSV','c','vector')}
COLOR_VECTOR4_APIS = {'normalize':('ColorNormalize','c','vector')}
COLOR_NUMERIC_APIS = {'from_normalized':('ColorFromNormalized','q','color'), 'from_hsv':('ColorFromHSV','sss','color')}
MATRIX_APIS = {
    'identity':('MatrixIdentity','','matrix'), 'transpose':('MatrixTranspose','m','matrix'),
    'add':('MatrixAdd','mm','matrix'), 'subtract':('MatrixSubtract','mm','matrix'),
    'multiply':('MatrixMultiply','mm','matrix'), 'trace':('MatrixTrace','m','float'),
    'determinant':('MatrixDeterminant','m','float'), 'invert':('MatrixInvert','m','matrix'),
    'translate':('MatrixTranslate','sss','matrix'), 'scale':('MatrixScale','sss','matrix'),
    'multiply_value':('MatrixMultiplyValue','ms','matrix'), 'look_at':('MatrixLookAt','ttt','matrix'),
    'rotate_x':('MatrixRotateX','s','matrix'), 'rotate_y':('MatrixRotateY','s','matrix'),
    'rotate_z':('MatrixRotateZ','s','matrix'), 'rotate_xyz':('MatrixRotateXYZ','t','matrix'),
    'rotate_zyx':('MatrixRotateZYX','t','matrix'), 'rotate':('MatrixRotate','ts','matrix'),
    'to_float_v':('MatrixToFloatV','m','buffer'),
}
MATRIX_ROTATIONS = {'rotate_x','rotate_y','rotate_z','rotate_xyz','rotate_zyx','rotate'}
MATRIX_FIELDS = tuple(f'm{row+4*column}' for row in range(4) for column in range(4))
ARGUMENT_SIZES = {'v':2, 't':3, 'q':4, 'c':4, 'm':16, 'b':6, 'r':4, 's':1, 'i':1}
VECTOR_APIS = {'vector_value':('Vector2',2,VECTOR2_APIS), 'vector3_value':('Vector3',3,VECTOR3_APIS),
               'vector4_value':('Vector4',4,VECTOR4_APIS),
               'quaternion_value':('Quaternion',4,QUATERNION_APIS),
               'color_vector3_value':('Color',3,COLOR_VECTOR3_APIS),
               'color_vector4_value':('Color',4,COLOR_VECTOR4_APIS),
               'color_numeric_value':('Color',1,COLOR_NUMERIC_APIS),
               'matrix_value':('Matrix',16,MATRIX_APIS)}
COLLISION_APIS = {
    'recs':('CheckCollisionRecs','rr','bool'),
    'circles':('CheckCollisionCircles','vsvs','bool'),
    'rectangle':('GetCollisionRec','rr','rectangle'),
    'point_rec':('CheckCollisionPointRec','vr','bool'),
    'point_circle':('CheckCollisionPointCircle','vvs','bool'),
    'circle_rec':('CheckCollisionCircleRec','vsr','bool'),
    'lines':('CheckCollisionLines','vvvv','hit'),
    'point_triangle':('CheckCollisionPointTriangle','vvvv','bool'),
    'point_line':('CheckCollisionPointLine','vvvi','bool'),
    'circle_line':('CheckCollisionCircleLine','vsvv','bool'),
    'point_poly':('CheckCollisionPointPoly','v','bool'),
    'spheres':('CheckCollisionSpheres','tsts','bool'),
    'boxes':('CheckCollisionBoxes','bb','bool'),
    'box_sphere':('CheckCollisionBoxSphere','bts','bool'),
}
COLLISION_CELLS = {'bool':1, 'rectangle':4, 'hit':3}

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
ENV = dict(os.environ, BEND_NO_TELEMETRY="1")


def run(command, cwd=ROOT):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=ENV,
                            capture_output=True, text=True, timeout=240)
    if result.returncode:
        raise RuntimeError(f"Command failed: {' '.join(map(str, command))}\n"
                           + result.stdout[-4000:] + result.stderr[-4000:])
    return result.stdout


def checkout(path, revision, overlay=None):
    actual = run(["git", "rev-parse", "HEAD"], path).strip()
    if actual != revision:
        raise ValueError(f"{path}: expected {revision}, found {actual}")
    if overlay is None:
        if run(["git", "status", "--porcelain", "--untracked-files=no"], path).strip():
            raise ValueError(f"{path}: tracked changes invalidate the pinned reference")
        return
    patch = ROOT / overlay['path']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:
        raise ValueError('Declared compiler patch hash mismatch')
    files = overlay['files']
    if not files:
        raise ValueError('A compiler overlay must declare its resulting source files')
    changed = set(run(['git', 'diff', 'HEAD', '--name-only'], path).splitlines())
    if changed - set(files):
        raise ValueError(f'{path}: unexpected tracked changes outside the compiler overlay')
    for filename, expected in files.items():
        source = path / filename
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise ValueError(f'{path}: compiler overlay mismatch in {filename}; apply the declared patch')


def integer(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def rgba(value):
    if not isinstance(value, list) or len(value) != 4 or not all(integer(c, 0, 255) for c in value):
        raise ValueError(f"Invalid RGBA color: {value!r}")
    return sum(c << shift for c, shift in zip(value, (24, 16, 8, 0)))


def coordinate(value, fractional=False):
    if not fractional:
        return integer(value, -32767, 32767)
    return type(value) in (int, float) and math.isfinite(value) and -32767 <= value <= 32767


def rounded_f32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def dot3_f32(left, right):
    products = [rounded_f32(a*b) for a,b in zip(left,right)]
    return rounded_f32(rounded_f32(products[0]+products[1])+products[2])


def matrix_inverse_denominator(values):
    """Validate MatrixInvert's own minor expansion, not MatrixDeterminant's."""
    m = {name:rounded_f32(value) for name,value in zip(MATRIX_FIELDS,values)}
    pairs = ((0,5,1,4),(0,6,2,4),(0,7,3,4),(1,6,2,5),(1,7,3,5),(2,7,3,6),
             (8,13,9,12),(8,14,10,12),(8,15,11,12),(9,14,10,13),(9,15,11,13),(10,15,11,14))
    b = [rounded_f32(rounded_f32(m[f'm{a}']*m[f'm{c}'])-rounded_f32(m[f'm{d}']*m[f'm{e}'])) for a,c,d,e in pairs]
    result = rounded_f32(b[0]*b[11])
    for a,c,sign in ((1,10,-1),(2,9,1),(3,8,1),(4,7,-1),(5,6,1)):
        result = rounded_f32(result+sign*rounded_f32(b[a]*b[c]))
    return result


def numeric_cells(kind, function):
    _, dimensions, apis = VECTOR_APIS[kind]
    result = apis[function][2]
    return dimensions*2 if result=='pair' else dimensions if result in ('vector','matrix','buffer') else 1


def crop_rectangle(width, height, op):
    x, y, w, h = (op[k] for k in ('x', 'y', 'width', 'height'))
    if x > width or y > height:
        return 0, 0, width, height
    if x < 0:
        w, x = w + x, 0
    if y < 0:
        h, y = h + y, 0
    return x, y, min(w, width - x), min(h, height - y)


def gradient_contract(width, height, op):
    """Keep gradient fixtures inside defined reference signed/F32 arithmetic."""
    def fp(value):
        return struct.unpack('f', struct.pack('f', value))[0]
    points = [(op['x'+str(i)], op['y'+str(i)]) for i in range(3)]
    (ax,ay),(bx,by),(cx,cy) = points
    sign = -1 if fp(fp((bx-ax)*(cy-ay))-fp((cx-ax)*(by-ay))) > 0 else 1
    x0, y0 = max(0,min(p[0] for p in points)), max(0,min(p[1] for p in points))
    x1, y1 = min(width,max(p[0] for p in points)), min(height,max(p[1] for p in points))
    edges = [(bx,by,(cy-by)*sign,(bx-cx)*sign), (cx,cy,(ay-cy)*sign,(cx-ax)*sign), (ax,ay,(by-ay)*sign,(ax-bx)*sign)]
    weights = []
    for vx,vy,dx,dy in edges:
        value = fp(fp((x0-vx)*dx) + fp((y0-vy)*dy))
        if not -2**31 <= value < 2**31:
            return False
        value = math.trunc(value)
        weights.append(value)
        for x in (x0,max(x0,x1+1)):
            for y in (y0,max(y0,y1+1)):
                if not -2**31 <= value+(x-x0)*dx+(y-y0)*dy < 2**31:
                    return False
    return -2**31 <= weights[0]+weights[1] < 2**31 and 0 < sum(weights) < 2**31


def cases_from(document):
    if document.get("schema") != 1 or not isinstance(document.get("cases"), list):
        raise ValueError("Expected fixture schema 1 and a cases array")
    cases = list(document["cases"])
    config = document.get("random")
    if config:
        if not (integer(config.get("seed"), 0, 2**32 - 1)
                and integer(config.get("cases"), 0, 100)
                and integer(config.get("operations_per_case"), 0, 100)):
            raise ValueError("Invalid seeded-fixture configuration")
        rng = random.Random(config["seed"])
        for i in range(config["cases"]):
            w, h = rng.randint(1, 23), rng.randint(1, 19)
            ops = []
            for _ in range(config["operations_per_case"]):
                op = rng.choice(("pixel", "rectangle", "circle", "clear", "flip_horizontal", "flip_vertical"))
                item = {"op": op}
                if not op.startswith('flip_'):
                    item['color'] = [rng.randrange(256) for _ in range(4)]
                if op in ('pixel', 'rectangle', 'circle'):
                    item.update(x=rng.randint(-12, w + 5), y=rng.randint(-12, h + 5))
                if op == "rectangle":
                    item.update(width=rng.randint(-3, 30), height=rng.randint(-3, 26))
                elif op == "circle":
                    item["radius"] = rng.randint(0, 18)
                ops.append(item)
            cases.append(dict(id=f"seeded-{i:03}", width=w, height=h,
                              background=[rng.randrange(256) for _ in range(4)], operations=ops))
    if not cases:
        raise ValueError("An empty conformance suite cannot pass")
    ids = set()
    for case in cases:
        name = case.get("id")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]+", name) or name in ids:
            raise ValueError(f"Invalid or duplicate scenario ID: {name!r}")
        ids.add(name)
        if not all(integer(case.get(k), 1, 4096) for k in ("width", "height")):
            raise ValueError(f"{name}: dimensions must be 1..4096")
        rgba(case["background"])
        if type(case.get('export_qoi', False)) is not bool:
            raise ValueError(f'{name}: export_qoi must be Boolean')
        if 'alpha_border' in case and (not coordinate(case['alpha_border'], True) or not 0 <= case['alpha_border'] <= 1):
            raise ValueError(f'{name}: alpha border threshold must be in 0..1')
        if sum(key in case for key in ('qoi','checked','gradient_square','gradient_radial','gradient_linear')) > 1:
            raise ValueError(f'{name}: only one image source may be selected')
        for kind in ('gradient_square','gradient_radial','gradient_linear'):
            if kind not in case:
                continue
            gradient = case[kind]
            if not isinstance(gradient, dict):
                raise ValueError(f'{name}: expected gradient parameters')
            if kind == 'gradient_linear':
                if not integer(gradient.get('direction'),-360,360) or min(case['width'],case['height']) < 2:
                    raise ValueError(f'{name}: linear fixtures require integral angles in -360..360 and dimensions at least 2')
            elif not coordinate(gradient.get('density'), True) or not 0 <= gradient['density'] <= 1:
                raise ValueError(f'{name}: gradient density must be in 0..1')
            rgba(gradient['outer'])
        if 'checked' in case:
            checked = case['checked']
            if 'qoi' in case or not isinstance(checked, dict) or not all(integer(checked.get(k), 1, 2147483647) for k in ('tile_width','tile_height')):
                raise ValueError(f'{name}: invalid checkerboard source')
            rgba(checked['color'])
        if 'qoi' in case:
            data = case['qoi']
            if not isinstance(data, list) or len(data) < 22 or not all(integer(v, 0, 255) for v in data):
                raise ValueError(f'{name}: invalid QOI fixture bytes')
            if data[:4] != [113,111,105,102] or data[12] not in (3,4) or data[13] not in (0,1) or data[-8:] != [0,0,0,0,0,0,0,1]:
                raise ValueError(f'{name}: invalid QOI fixture header/end marker')
            if int.from_bytes(bytes(data[4:8]), 'big') != case['width'] or int.from_bytes(bytes(data[8:12]), 'big') != case['height']:
                raise ValueError(f'{name}: QOI dimensions differ from the fixture')
        if not isinstance(case.get("operations"), list):
            raise ValueError(f"{name}: operations must be an array")
        current_w, current_h = case['width'], case['height']
        for op in case["operations"]:
            kind = op.get("op")
            if not isinstance(kind, str) or kind not in ("pixel", "rectangle", "circle", "clear", "flip_horizontal", "flip_vertical", "blend_color",
                             "line", "line_v", "triangle", "triangle_lines", "blit", "blit_region", "blit_rect", "crop", "extract", "resize_nn", "resize",
                             "pixel_v", "circle_v", "circle_lines", "circle_lines_v", "rectangle_v", "rectangle_rec", "rectangle_lines",
                             "line_ex", "triangle_fan", "triangle_strip", "triangle_ex", "color_value", "number_value", "collision_value", "from_channel", "alpha_clear", "alpha_mask", "alpha_crop", "resize_canvas", "rotate_degrees", "to_pot") and kind not in UNARY_IMAGE_APIS and kind not in COLOR_IMAGE_APIS and kind not in VECTOR_APIS:
                raise ValueError(f"{name}: unknown operation {kind!r}")
            if kind in ('blit', 'blit_region', 'blit_rect', 'alpha_mask'):
                if kind != 'alpha_mask':
                    rgba(op['tint'])
                source = op['source']
                if not all(integer(source.get(k), 1, 4096) for k in ('width', 'height')):
                    raise ValueError(f'{name}: invalid source dimensions')
                if not isinstance(source.get('pixels'), list) or len(source['pixels']) != source['width'] * source['height']:
                    raise ValueError(f'{name}: source pixel count must match its dimensions')
                for pixel in source['pixels']:
                    rgba(pixel)
                if type(op.get('observe_source', False)) is not bool:
                    raise ValueError(f'{name}: observe_source must be Boolean')
                if kind == 'alpha_mask' and (source['width'],source['height']) != (current_w,current_h):
                    raise ValueError(f'{name}: alpha mask dimensions must match the image')
                if kind in ('blit_region', 'blit_rect'):
                    rect = op['source_rect']
                    if not all(coordinate(rect.get(k), kind == 'blit_rect') for k in ('x', 'y', 'width', 'height')):
                        raise ValueError(f'{name}: invalid source rectangle')
                    if kind == 'blit_region':
                        if not (rect['x'] >= 0 and rect['y'] >= 0 and rect['width'] > 0 and rect['height'] > 0
                                and rect['x'] + rect['width'] <= source['width'] and rect['y'] + rect['height'] <= source['height']):
                            raise ValueError(f'{name}: region must fit its source without implicit resizing')
                    else:
                        cw = min(rect['width'] + min(0, rect['x']), source['width'] - max(0, rect['x']))
                        ch = min(rect['height'] + min(0, rect['y']), source['height'] - max(0, rect['y']))
                        target = op['dest_rect']
                        if cw < 1 or ch < 1:
                            raise ValueError(f'{name}: clipped image source must remain nonempty')
                        if not all(coordinate(target.get(k), True) for k in ('x', 'y', 'width', 'height')) or not all(1 <= math.trunc(target[k]) <= 4096 for k in ('width', 'height')):
                            raise ValueError(f'{name}: invalid destination rectangle')
                if op.get('observe_source'):
                    current_w, current_h = source['width'], source['height']
            elif kind not in ('crop', 'extract', 'resize_nn', 'resize', 'color_contrast', 'color_brightness', 'number_value', 'collision_value', 'from_channel', 'alpha_crop', 'rotate_degrees') and kind not in UNARY_IMAGE_APIS and kind not in VECTOR_APIS:
                rgba(op["color"])
            if kind == 'color_replace':
                rgba(op['replacement'])
            if kind == 'triangle_ex':
                rgba(op['color2'])
                rgba(op['color3'])
            if kind == 'color_value':
                function = op.get('function')
                if not isinstance(function, str) or function not in COLOR_VALUE_APIS:
                    raise ValueError(f'{name}: unknown color function')
                if function in ('tint', 'lerp', 'equal'):
                    rgba(op['other'])
                if function not in ('tint', 'equal') and not coordinate(op.get('factor'), True):
                    raise ValueError(f'{name}: expected finite color factor')
            if kind == 'number_value':
                function, values = op.get('function'), op.get('args')
                if not isinstance(function, str) or function not in MATH_APIS or not isinstance(values, list) or len(values) != MATH_APIS[function][1] or not all(coordinate(v, True) for v in values):
                    raise ValueError(f'{name}: invalid scalar math arguments')
                inputs = [struct.unpack('f',struct.pack('f',v))[0] for v in values]
                if function in ('normalize','remap','wrap') and inputs[1] == inputs[2]:
                    raise ValueError(f'{name}: scalar range must remain nonzero in F32')
            if kind in VECTOR_APIS:
                namespace, dimensions, apis = VECTOR_APIS[kind]
                function, values = op.get('function'), op.get('args')
                if not isinstance(function, str) or function not in apis or not isinstance(values, list):
                    raise ValueError(f'{name}: invalid {namespace} function/arguments')
                _, signature, result = apis[function]
                if len(values) != sum(ARGUMENT_SIZES[p] for p in signature) or not all(coordinate(v, True) for v in values):
                    raise ValueError(f'{name}: invalid {namespace} argument arity/domain')
                if signature == 'c':
                    rgba(values)
                if namespace=='Color' and function=='from_normalized' and any(not 0<=v<=1 for v in values):
                    raise ValueError(f'{name}: normalized color components must be in 0..1')
                if namespace=='Color' and function=='from_hsv' and (not 0<=values[0]<=360 or any(not 0<=v<=1 for v in values[1:])):
                    raise ValueError(f'{name}: HSV requires hue 0..360 and saturation/value 0..1')
                divisors = values[dimensions:] if function=='divide' else values if function=='invert' and namespace in ('Vector2','Vector3','Vector4') else []
                if any(struct.unpack('f',struct.pack('f',v))[0] == 0 for v in divisors):
                    raise ValueError(f'{name}: vector divisors must remain nonzero in F32')
                if namespace=='Matrix' and function=='invert' and matrix_inverse_denominator(values)==0:
                    raise ValueError(f'{name}: matrix inverse denominator must remain nonzero in F32')
                if function in ('project','reject'):
                    target = [rounded_f32(v) for v in values[dimensions:]]
                    if dot3_f32(target,target) == 0:
                        raise ValueError(f'{name}: projection squared target length must remain nonzero in F32')
                if function == 'barycenter':
                    a,b,c = ([rounded_f32(v) for v in values[start:start+3]] for start in (3,6,9))
                    v0,v1 = ([rounded_f32(x-y) for x,y in zip(vertex,a)] for vertex in (b,c))
                    d00,d01,d11 = dot3_f32(v0,v0),dot3_f32(v0,v1),dot3_f32(v1,v1)
                    if rounded_f32(rounded_f32(d00*d11)-rounded_f32(d01*d01)) == 0:
                        raise ValueError(f'{name}: barycentric denominator must remain nonzero in F32')
                if namespace=='Vector2' and function == 'rotate' and abs(values[2]) > 6.283186:
                    raise ValueError(f'{name}: vector rotation profile is bounded to one cycle')
                if namespace=='Matrix' and function in MATRIX_ROTATIONS:
                    angles = values[-1:] if function=='rotate' else values
                    if any(abs(value)>6.283186 for value in angles):
                        raise ValueError(f'{name}: matrix rotation profile is bounded to one cycle')
                if not integer(op.get('x'),0,current_w-numeric_cells(kind,function)) or not integer(op.get('y'),0,current_h-1):
                    raise ValueError(f'{name}: all numeric output components must fit the image')
            if kind == 'collision_value':
                function, values = op.get('function'), op.get('args')
                if not isinstance(function, str) or function not in COLLISION_APIS or not isinstance(values, list):
                    raise ValueError(f'{name}: invalid collision function/arguments')
                _, signature, result = COLLISION_APIS[function]
                if len(values) != sum(ARGUMENT_SIZES[p] for p in signature) or not all(coordinate(v, True) for v in values):
                    raise ValueError(f'{name}: invalid collision argument arity/domain')
                if function == 'point_line' and not coordinate(values[-1]):
                    raise ValueError(f'{name}: point-line threshold must be integral')
                if function == 'point_poly':
                    points = op.get('points')
                    if not isinstance(points, list) or len(points)>4096 or any(not isinstance(p,list) or len(p)!=2 or not all(coordinate(v,True) for v in p) for p in points):
                        raise ValueError(f'{name}: expected bounded polygon vertices')
                cells = COLLISION_CELLS[result]
                if not integer(op.get('x'),0,current_w-cells) or not integer(op.get('y'),0,current_h-1):
                    raise ValueError(f'{name}: all collision result fields must fit the image')
            if kind == 'from_channel':
                if not coordinate(op.get('channel')) or type(op.get('observe_source', False)) is not bool:
                    raise ValueError(f'{name}: channel requires an integral selector and Boolean source observation')
            if kind in ('color_contrast', 'color_brightness') and not coordinate(op.get('amount'), kind == 'color_contrast'):
                raise ValueError(f'{name}: invalid color adjustment amount')
            if kind in ('alpha_clear','alpha_crop') and (not coordinate(op.get('threshold'), True) or not 0 <= op['threshold'] <= 1):
                raise ValueError(f'{name}: alpha threshold must be finite in 0..1')
            if kind == 'blend_color':
                rgba(op['destination'])
                rgba(op['tint'])
            fields = [] if kind in ('clear', 'resize_nn', 'resize', 'blit_rect', 'triangle_fan', 'triangle_strip', 'alpha_clear', 'alpha_mask', 'alpha_crop', 'rotate_degrees', 'to_pot', 'from_channel') or kind in UNARY_IMAGE_APIS or kind in COLOR_IMAGE_APIS else ["x", "y"]
            if kind in ('line', 'line_v', 'line_ex', 'triangle', 'triangle_lines', 'triangle_ex'):
                fields = ['x0', 'y0', 'x1', 'y1']
                if kind.startswith('triangle'):
                    fields += ['x2', 'y2']
            if kind in ('rectangle', 'rectangle_v', 'rectangle_rec', 'rectangle_lines', 'crop', 'extract'):
                fields += ["width", "height"]
            fractional = kind in ('line_v', 'line_ex', 'triangle_lines', 'pixel_v', 'circle_v', 'circle_lines_v', 'rectangle_v', 'rectangle_rec', 'rectangle_lines')
            if any(not coordinate(op.get(k), fractional) for k in fields):
                raise ValueError(f"{name}: invalid coordinates for {kind}")
            if kind == 'triangle_ex' and not gradient_contract(current_w, current_h, op):
                raise ValueError(f'{name}: gradient requires defined arithmetic and a nonzero weight sum')
            if kind in ('triangle_fan', 'triangle_strip'):
                points = op.get('points')
                if not isinstance(points, list) or any(not isinstance(p, list) or len(p)!=2 or any(not coordinate(v) for v in p) for p in points):
                    raise ValueError(f'{name}: expected integral triangle points')
            if kind in ('line_ex', 'rectangle_lines') and not integer(op.get('thickness'), 0, 32767):
                raise ValueError(f'{name}: thickness must be 0..32767')
            if kind in ('line', 'line_v', 'line_ex', 'triangle_lines'):
                points = [(op['x0'], op['y0']), (op['x1'], op['y1'])]
                if kind == 'triangle_lines':
                    points += [(op['x2'], op['y2']), points[0]]
                rounded = [(math.trunc(x + (0.5 if kind in ('line_v', 'line_ex') else 0)),
                             math.trunc(y + (0.5 if kind in ('line_v', 'line_ex') else 0))) for x, y in points]
                if any(min(abs(x1-x0), abs(y1-y0)) > 32767 for (x0, y0), (x1, y1) in zip(rounded, rounded[1:])):
                    raise ValueError(f'{name}: fixed-point short-axis delta exceeds the supported line profile')
            if kind in ('circle', 'circle_v', 'circle_lines', 'circle_lines_v') and not integer(op.get("radius"), 0, 32767):
                raise ValueError(f"{name}: radius must be 0..32767")
            if kind == 'crop':
                _, _, current_w, current_h = crop_rectangle(current_w, current_h, op)
                if current_w < 1 or current_h < 1:
                    raise ValueError(f'{name}: empty/invalid crop belongs in error-contract tests')
            elif kind == 'extract':
                if not (op['x'] >= 0 and op['y'] >= 0 and op['width'] > 0 and op['height'] > 0
                        and op['x'] + op['width'] <= current_w and op['y'] + op['height'] <= current_h):
                    raise ValueError(f'{name}: extraction must fit the current image')
                if type(op.get('observe_source', False)) is not bool:
                    raise ValueError(f'{name}: observe_source must be Boolean')
                if not op.get('observe_source'):
                    current_w, current_h = op['width'], op['height']
            elif kind == 'alpha_crop':
                if not all(integer(op.get(key),1,4096) for key in ('result_width','result_height')):
                    raise ValueError(f'{name}: alpha crop requires checked post-size hints')
                if op['result_width'] > current_w or op['result_height'] > current_h:
                    raise ValueError(f'{name}: alpha crop cannot increase dimensions')
                current_w, current_h = op['result_width'], op['result_height']
            elif kind == 'rotate_degrees':
                if not integer(op.get('degrees'),-360,360) or not all(integer(op.get(key),1,4096) for key in ('result_width','result_height')):
                    raise ValueError(f'{name}: rotation requires a supported angle and checked output size')
                current_w,current_h=op['result_width'],op['result_height']
            elif kind == 'to_pot':
                current_w,current_h=1<<(current_w-1).bit_length(),1<<(current_h-1).bit_length()
            elif kind in ('resize_nn', 'resize', 'resize_canvas'):
                w, h = op.get('width'), op.get('height')
                if not integer(w, 1, 4096) or not integer(h, 1, 4096):
                    raise ValueError(f'{name}: invalid resize dimensions')
                if kind == 'resize_nn':
                    xr, yr = ((current_w << 16) // w) + 1, ((current_h << 16) // h) + 1
                    last = (((h-1)*yr) >> 16) * current_w + (((w-1)*xr) >> 16)
                    if last >= current_w * current_h:
                        raise ValueError(f'{name}: reference nearest mapping reads outside the image')
                if kind == 'resize_canvas' and (w,h) != (current_w,current_h):
                    cols = min(current_w-max(0,-op['x']), w-max(0,op['x']))
                    rows = min(current_h-max(0,-op['y']), h-max(0,op['y']))
                    if cols < 1 or rows < 1:
                        raise ValueError(f'{name}: canvas fixtures require positive source overlap')
                current_w, current_h = w, h
            elif kind in ('rotate_cw', 'rotate_ccw'):
                current_w, current_h = current_h, current_w
    return cases


def result_size(case):
    width, height = case['width'], case['height']
    for op in case['operations']:
        if op['op'] in ('blit', 'blit_region', 'blit_rect', 'alpha_mask') and op.get('observe_source'):
            width, height = op['source']['width'], op['source']['height']
        elif op['op'] == 'crop':
            _, _, width, height = crop_rectangle(width, height, op)
        elif op['op'] in ('resize_nn', 'resize', 'resize_canvas') or (op['op'] == 'extract' and not op.get('observe_source')):
            width, height = op['width'], op['height']
        elif op['op'] == 'alpha_crop':
            width, height = op['result_width'], op['result_height']
        elif op['op'] == 'rotate_degrees':
            width, height = op['result_width'], op['result_height']
        elif op['op'] == 'to_pot':
            width,height=1<<(width-1).bit_length(),1<<(height-1).bit_length()
        elif op['op'] in ('rotate_cw', 'rotate_ccw'):
            width, height = height, width
    return width, height


def gradient_reference():
    if platform.system() == 'Darwin':
        return 'AccurateGradient'
    if platform.system() == 'Linux' and platform.libc_ver()[0] == 'glibc':
        return 'GnuGradient'
    raise ValueError('Declare a verified gradient math reference for this host')


def collision_arithmetic():
    if platform.system() == 'Darwin' and platform.machine() == 'arm64':
        return 'FusedCollision'
    if platform.system() == 'Linux' and platform.machine() == 'x86_64':
        return 'UncontractedCollision'
    raise ValueError('Declare a verified linked collision arithmetic profile for this host')


def vector_arguments(signature, values, bend=False):
    result, at = [], 0
    literal = f32 if bend else lambda value: f'{float(value)!r}f'
    for parameter in signature:
        if parameter in ('v','t','q','r','m'):
            size, name = {'v':(2,'Vector2'), 't':(3,'Vector3'), 'q':(4,'Vector4'), 'r':(4,'Rectangle'), 'm':(16,'Matrix')}[parameter]
            vector = ', '.join(literal(v) for v in values[at:at+size])
            result.append((f'J.{name}{{' if bend else f'({name}){{') + vector + '}')
            at += size
        elif parameter == 'b':
            vectors = vector_arguments('tt',values[at:at+6],bend)
            result.append(('J.BoundingBox{' if bend else '(BoundingBox){') + vectors + '}')
            at += 6
        elif parameter == 'c':
            color = rgba(values[at:at+4])
            result.append(str(color) if bend else f'GetColor({color}u)')
            at += 4
        else:
            result.append(literal(values[at]))
            at += 1
    return ', '.join(result)


def c_source(cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
             '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
             'static Color float_bits(float value) { unsigned int bits; memcpy(&bits, &value, 4); return GetColor(bits); }',
             'int main(void) {',
             'SetTraceLogLevel(LOG_NONE);']
    if any(op['op']=='to_pot' for case in cases for op in case['operations']):
        lines += ['for (int n=1;n<=4096;n++) { int expected=1; while(expected<n) expected*=2;',
                  'Image probe=GenImageColor(n,1,BLANK); ImageToPOT(&probe,WHITE);',
                  'if(probe.width!=expected || probe.height!=1) { fprintf(stderr,"POT axis contract mismatch\\n"); return 5; }',
                  'UnloadImage(probe); }']
    if any(op['op']=='from_channel' for case in cases for op in case['operations']):
        lines += ['{ Image probe=GenImageColor(256,1,BLANK);',
                  'for(int n=0;n<256;n++) ImageDrawPixel(&probe,n,0,(Color){n,255-n,(73*n)%256,(151*n)%256});',
                  'for(int channel=0;channel<4;channel++) { Image extracted=ImageFromChannel(probe,channel);',
                  'for(int n=0;n<256;n++) { unsigned char expected=((unsigned char*)probe.data)[4*n+channel];',
                  'Color got=GetImageColor(extracted,n,0);',
                  'if(got.r!=expected || got.g!=expected || got.b!=expected || got.a!=255) { fprintf(stderr,"channel byte contract mismatch\\n"); return 7; } }',
                  'UnloadImage(extracted); } UnloadImage(probe); }']
    for case in cases:
        w, h = case["width"], case["height"]
        if 'qoi' in case:
            lines += ['{', 'unsigned char encoded[] = {' + ','.join(map(str,case['qoi'])) + '};',
                      'Image image = LoadImageFromMemory(".qoi", encoded, sizeof(encoded));',
                      'if (!image.data) return 2;', 'ImageFormat(&image, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);']
        elif 'checked' in case:
            checked = case['checked']
            lines += ['{', f'Image image = GenImageChecked({w}, {h}, {checked["tile_width"]}, {checked["tile_height"]}, GetColor({rgba(case["background"])}u), GetColor({rgba(checked["color"])}u));']
        elif any(key in case for key in ('gradient_square','gradient_radial','gradient_linear')):
            kind = next(key for key in ('gradient_square','gradient_radial','gradient_linear') if key in case)
            gradient = case[kind]
            function = {'gradient_square':'GenImageGradientSquare','gradient_radial':'GenImageGradientRadial','gradient_linear':'GenImageGradientLinear'}[kind]
            parameter = gradient['direction'] if kind=='gradient_linear' else gradient['density']
            lines += ['{', f'Image image = {function}({w}, {h}, {parameter}, GetColor({rgba(case["background"])}u), GetColor({rgba(gradient["outer"])}u));']
        else:
            lines += ['{', f'Image image = GenImageColor({w}, {h}, GetColor({rgba(case["background"])}u));']
        for op in case["operations"]:
            kind = op["op"]
            if kind == 'from_channel':
                lines += ['{', f'Image extracted=ImageFromChannel(image,{op["channel"]});',
                          'ImageFormat(&extracted, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);']
                lines += ['UnloadImage(extracted);'] if op.get('observe_source') else ['UnloadImage(image);','image=extracted;']
                lines += ['}']
                continue
            if kind == 'rotate_degrees':
                lines += [f'ImageRotate(&image, {op["degrees"]});',
                          f'if(image.width!={op["result_width"]} || image.height!={op["result_height"]}) {{ fprintf(stderr,"rotation size hint mismatch\\n"); return 6; }}']
                continue
            if kind == 'to_pot':
                lines += [f'ImageToPOT(&image, GetColor({rgba(op["color"])}u));']
                continue
            if kind == 'alpha_crop':
                lines += [f'ImageAlphaCrop(&image, {op["threshold"]});',
                          f'if (image.width != {op["result_width"]} || image.height != {op["result_height"]}) {{ fprintf(stderr, "alpha crop size hint mismatch\\n"); return 4; }}']
                continue
            if kind == 'resize_canvas':
                lines += [f'ImageResizeCanvas(&image, {op["width"]}, {op["height"]}, {op["x"]}, {op["y"]}, GetColor({rgba(op["color"])}u));']
                continue
            if kind in ('blit', 'blit_region', 'blit_rect', 'alpha_mask'):
                source = op['source']
                sw, sh = source['width'], source['height']
                lines += ['{', f'Image source = GenImageColor({sw}, {sh}, BLANK);']
                for i, pixel in enumerate(source['pixels']):
                    lines += [f'ImageDrawPixel(&source, {i % sw}, {i // sw}, GetColor({rgba(pixel)}u));']
                if kind == 'alpha_mask':
                    lines += ['ImageAlphaMask(&image, source);']
                else:
                    rect = op.get('source_rect', dict(x=0, y=0, width=sw, height=sh))
                    target = op['dest_rect'] if kind == 'blit_rect' else dict(x=op['x'], y=op['y'], width=rect['width'], height=rect['height'])
                    lines += [f'ImageDraw(&image, source, (Rectangle){{{rect["x"]}, {rect["y"]}, {rect["width"]}, {rect["height"]}}}, '
                              f'(Rectangle){{{target["x"]}, {target["y"]}, {target["width"]}, {target["height"]}}}, GetColor({rgba(op["tint"])}u));']
                if op.get('observe_source'):
                    lines += ['UnloadImage(image);', 'image = source;']
                else:
                    lines += ['UnloadImage(source);']
                lines += ['}']
                continue
            if kind in ('crop', 'extract', 'resize_nn', 'resize'):
                if kind in ('resize_nn', 'resize'):
                    function = 'ImageResizeNN' if kind == 'resize_nn' else 'ImageResize'
                    lines += [f'{function}(&image, {op["width"]}, {op["height"]});']
                else:
                    rect = f'(Rectangle){{{op["x"]}, {op["y"]}, {op["width"]}, {op["height"]}}}'
                    if kind == 'crop':
                        lines += [f'ImageCrop(&image, {rect});']
                    else:
                        lines += ['{', f'Image extracted = ImageFromImage(image, {rect});']
                        lines += ['UnloadImage(extracted);'] if op.get('observe_source') else ['UnloadImage(image);', 'image = extracted;']
                        lines += ['}']
                continue
            if kind in UNARY_IMAGE_APIS:
                function = UNARY_IMAGE_APIS[kind]
                lines += [f'{function}(&image);']
                continue
            if kind in COLOR_IMAGE_APIS:
                values = str(op['amount']) if kind in ('color_contrast', 'color_brightness') else f'GetColor({rgba(op["color"])}u)'
                if kind == 'color_replace':
                    values += f', GetColor({rgba(op["replacement"])}u)'
                lines += [f'{COLOR_IMAGE_APIS[kind]}(&image, {values});']
                continue
            if kind == 'number_value':
                function = op['function']
                values = ', '.join(f'{float(v)!r}f' for v in op['args'])
                expression = f'{MATH_APIS[function][0]}({values})'
                color = f'GetColor((unsigned int){expression})' if function == 'float_equals' else f'float_bits({expression})'
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {color});']
                continue
            if kind in VECTOR_APIS:
                namespace, dimensions, apis = VECTOR_APIS[kind]
                function, signature, result = apis[op['function']]
                expression = f'{function}({vector_arguments(signature,op["args"])})'
                if result == 'color':
                    lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {expression});']
                elif result == 'buffer':
                    lines += ['{', f'float{dimensions} v = {expression};']
                    for index in range(dimensions):
                        lines += [f'ImageDrawPixel(&image, {op["x"]+index}, {op["y"]}, float_bits(v.v[{index}]));']
                    lines += ['}']
                elif result == 'pair':
                    left,right = vector_arguments('t',op['args'][:3]),vector_arguments('t',op['args'][3:])
                    lines += ['{',f'Vector3 left={left}, right={right};',f'{function}(&left,&right);']
                    for index, field in enumerate(('left.x','left.y','left.z','right.x','right.y','right.z')):
                        lines += [f'ImageDrawPixel(&image, {op["x"]+index}, {op["y"]}, float_bits({field}));']
                    lines += ['}']
                elif result in ('vector','matrix'):
                    output_type = f'Vector{dimensions}' if result=='vector' else namespace
                    lines += ['{', f'{output_type} v = {expression};']
                    for index, field in enumerate(MATRIX_FIELDS if result=='matrix' else ('x','y','z','w')[:dimensions]):
                        lines += [f'ImageDrawPixel(&image, {op["x"]+index}, {op["y"]}, float_bits(v.{field}));']
                    lines += ['}']
                else:
                    color = f'GetColor((unsigned int){expression})' if result=='bool' else f'float_bits({expression})'
                    lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {color});']
                continue
            if kind == 'collision_value':
                function, signature, result = COLLISION_APIS[op['function']]
                arguments = vector_arguments(signature,op['args'])
                if op['function']=='point_poly':
                    points = '(Vector2[]){' + ','.join('{' + ','.join(f'{float(v)!r}f' for v in p) + '}' for p in op['points']) + '}' if op['points'] else 'NULL'
                    arguments += f', {points}, {len(op["points"])}'
                expression = f'{function}({arguments})'
                if result == 'rectangle':
                    lines += ['{', f'Rectangle result={expression};']
                    for index, field in enumerate(('x','y','width','height')):
                        lines += [f'ImageDrawPixel(&image, {op["x"]+index}, {op["y"]}, float_bits(result.{field}));']
                    lines += ['}']
                elif result == 'hit':
                    lines += ['{', 'Vector2 point={0};', f'bool hit={function}({arguments}, &point);',
                              f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, GetColor((unsigned int)hit));',
                              f'ImageDrawPixel(&image, {op["x"]+1}, {op["y"]}, float_bits(point.x));',
                              f'ImageDrawPixel(&image, {op["x"]+2}, {op["y"]}, float_bits(point.y));', '}']
                else:
                    lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, GetColor((unsigned int){expression}));']
                continue
            color = f'GetColor({rgba(op["color"])}u)'
            if kind == "clear":
                lines += [f'ImageClearBackground(&image, {color});']
            elif kind == 'alpha_clear':
                lines += [f'ImageAlphaClear(&image, {color}, {op["threshold"]});']
            elif kind == "pixel":
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {color});']
            elif kind == 'pixel_v':
                lines += [f'ImageDrawPixelV(&image, (Vector2){{{op["x"]}, {op["y"]}}}, {color});']
            elif kind == "rectangle":
                lines += [f'ImageDrawRectangle(&image, {op["x"]}, {op["y"]}, {op["width"]}, {op["height"]}, {color});']
            elif kind == 'rectangle_v':
                lines += [f'ImageDrawRectangleV(&image, (Vector2){{{op["x"]}, {op["y"]}}}, (Vector2){{{op["width"]}, {op["height"]}}}, {color});']
            elif kind in ('rectangle_rec', 'rectangle_lines'):
                rect = f'(Rectangle){{{op["x"]}, {op["y"]}, {op["width"]}, {op["height"]}}}'
                function = 'ImageDrawRectangleRec' if kind == 'rectangle_rec' else 'ImageDrawRectangleLines'
                thick = f'{op["thickness"]}, ' if kind == 'rectangle_lines' else ''
                lines += [f'{function}(&image, {rect}, {thick}{color});']
            elif kind in ('circle', 'circle_v', 'circle_lines', 'circle_lines_v'):
                function = {'circle':'ImageDrawCircle','circle_v':'ImageDrawCircleV','circle_lines':'ImageDrawCircleLines','circle_lines_v':'ImageDrawCircleLinesV'}[kind]
                position = f'(Vector2){{{op["x"]}, {op["y"]}}}' if kind.endswith('_v') else f'{op["x"]}, {op["y"]}'
                lines += [f'{function}(&image, {position}, {op["radius"]}, {color});']
            elif kind == "blend_color":
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, ColorAlphaBlend(GetColor({rgba(op["destination"])}u), {color}, GetColor({rgba(op["tint"])}u)));']
            elif kind == 'color_value':
                function = op['function']
                args = [color]
                if function in ('tint', 'lerp', 'equal'):
                    args += [f'GetColor({rgba(op["other"])}u)']
                if function not in ('tint', 'equal'):
                    args += [str(op['factor'])]
                value = f'{COLOR_VALUE_APIS[function][0]}({", ".join(args)})'
                if function == 'equal':
                    value = f'GetColor((unsigned int){value})'
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {value});']
            elif kind == 'line':
                lines += [f'ImageDrawLine(&image, {op["x0"]}, {op["y0"]}, {op["x1"]}, {op["y1"]}, {color});']
            elif kind in ('line_v', 'line_ex', 'triangle', 'triangle_lines', 'triangle_ex'):
                count = 2 if kind in ('line_v', 'line_ex') else 3
                vectors = ', '.join(f'(Vector2){{{op["x"+str(i)]}, {op["y"+str(i)]}}}' for i in range(count))
                function = {'line_v':'ImageDrawLineV', 'line_ex':'ImageDrawLineEx', 'triangle':'ImageDrawTriangle', 'triangle_lines':'ImageDrawTriangleLines', 'triangle_ex':'ImageDrawTriangleEx'}[kind]
                thick = f'{op["thickness"]}, ' if kind == 'line_ex' else ''
                colors = f'{color}, GetColor({rgba(op["color2"])}u), GetColor({rgba(op["color3"])}u)' if kind == 'triangle_ex' else color
                lines += [f'{function}(&image, {vectors}, {thick}{colors});']
            elif kind in ('triangle_fan', 'triangle_strip'):
                points = '(Vector2[]){' + ','.join(f'{{{x},{y}}}' for x,y in op['points']) + '}' if op['points'] else 'NULL'
                function = 'ImageDrawTriangleFan' if kind == 'triangle_fan' else 'ImageDrawTriangleStrip'
                lines += [f'{function}(&image, {points}, {len(op["points"])}, {color});']
        prefix = '{"id":"' + case["id"] + '","width":%d,"height":%d,"pixels":['
        lines += [f'printf({json.dumps(prefix)}, image.width, image.height);',
                  'for (int y = 0; y < image.height; y++) for (int x = 0; x < image.width; x++) {',
                  'if (x || y) putchar(\',\');',
                  'printf("%u", (unsigned int)ColorToInt(GetImageColor(image, x, y)));',
                  '}', 'printf("]");']
        if 'alpha_border' in case:
            lines += [f'Rectangle border = GetImageAlphaBorder(image, {case["alpha_border"]});',
                      'printf(",\\"alpha_border\\":[%d,%d,%d,%d]", (int)border.x, (int)border.y, (int)border.width, (int)border.height);']
        if case.get('export_qoi'):
            export_path = json.dumps(f'.build/reference-{case["id"]}.qoi')
            lines += ['printf(",\\"qoi\\":[");', 'int qoi_size = 0;',
                      f'if (!ExportImage(image, {export_path})) return 3;',
                      f'unsigned char *qoi_data = LoadFileData({export_path}, &qoi_size);',
                      'if (!qoi_data || qoi_size < 22) return 3;',
                      'for (int i=0;i<qoi_size;i++) printf("%s%u", i?",":"", qoi_data[i]);',
                      'printf("]");', 'UnloadFileData(qoi_data);']
        lines += ['puts("}");', 'UnloadImage(image);', '}']
    return '\n'.join(lines + ['return 0;', '}']) + '\n'


def f32(value):
    literal = format(Decimal(str(abs(value))), 'f')
    if '.' not in literal:
        literal += '.0'
    return f'F32.neg({literal})' if math.copysign(1.0, value) < 0 else literal


def bend_source(cases, gpu=False):
    lines = ['import Base', 'import ../jonlib.bend as J', '',
             'def emit(name: String, image: J.Surface, extra: String) -> IO(Unit):',
             '  J.Surface{+w, +h, pixels} = image',
             '  IO.print("{\\"id\\":\\"" ++ name ++ "\\",\\"width\\":" ++ U32.show(w)',
             '    ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":"',
             '    ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ extra ++ "}")', '']
    lines += [
        'def write_vector(surface: J.Surface, +x: F32, +y: F32, vector: J.Vector2) -> J.Surface:',
        '  J.Vector2{u, v} = vector',
        '  first = J.Surface.draw_pixel(surface, x, y, F32.bits(u))',
        '  J.Surface.draw_pixel(first, (x + 1.0 : F32), y, F32.bits(v))',
        'def write_vector3(surface: J.Surface, +x: F32, +y: F32, vector: J.Vector3) -> J.Surface:',
        '  J.Vector3{u, v, w} = vector',
        '  first = write_vector(surface, x, y, J.Vector2{u, v})',
        '  J.Surface.draw_pixel(first, (x + 2.0 : F32), y, F32.bits(w))',
        'def write_vector4(surface: J.Surface, +x: F32, +y: F32, vector: J.Vector4) -> J.Surface:',
        '  J.Vector4{u, v, w, q} = vector',
        '  first = write_vector3(surface, x, y, J.Vector3{u, v, w})',
        '  J.Surface.draw_pixel(first, (x + 3.0 : F32), y, F32.bits(q))',
        'def write_float_buffer(n: Nat, surface: J.Surface, +x: F32, +y: F32, values: +List<F32>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:',
        '  match n values:',
        '    case 0n Nil{}: Done{surface}',
        '    case 1n+k Con{value, rest}:',
        '      write_float_buffer(k, J.Surface.draw_pixel(surface, x, y, F32.bits(value)), (x + 1.0 : F32), y, rest)',
        '    case _ _: Fail{(surface, J.InvalidSize{})}',
        'def write_vector_pair(surface: J.Surface, +x: F32, +y: F32, pair: J.Vector3 & J.Vector3) -> J.Surface:',
        '  (left, right) = pair',
        '  first = write_vector3(surface, x, y, left)',
        '  write_vector3(first, (x + 3.0 : F32), y, right)',
        'def write_rectangle(surface: J.Surface, +x: F32, +y: F32, rectangle: J.Rectangle) -> J.Surface:',
        '  J.Rectangle{rx, ry, w, h} = rectangle',
        '  first = write_vector(surface, x, y, J.Vector2{rx, ry})',
        '  write_vector(first, (x + 2.0 : F32), y, J.Vector2{w, h})',
        'def write_hit(surface: J.Surface, +x: F32, +y: F32, hit: Maybe<&2, J.Vector2>) -> J.Surface:',
        '  match hit:',
        '    case None{}:',
        '      first = J.Surface.draw_pixel(surface, x, y, 0)',
        '      write_vector(first, (x + 1.0 : F32), y, J.Vector2{0.0, 0.0})',
        '    case Some{point}:',
        '      first = J.Surface.draw_pixel(surface, x, y, 1)',
        '      write_vector(first, (x + 1.0 : F32), y, point)',
        'def emit_qoi_data(name: String, image: J.Surface, bytes: +List<U32>, extra: String) -> IO(Unit):',
        '  J.Surface{+w, +h, pixels} = image',
        '  IO.print("{\\"id\\":\\"" ++ name ++ "\\",\\"width\\":" ++ U32.show(w)',
        '    ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":"',
        '    ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels}))',
        '    ++ ",\\"qoi\\":" ++ List.show(~&2, ~U32, ~U32.show, bytes) ++ extra ++ "}")',
        'def emit_qoi(name: String, pair: J.Surface & J.Surface, extra: String) -> IO(Unit):',
        '  (original, copy) = pair',
        f'  emit_qoi_data(name, original, J.Surface.to_qoi{"!" if gpu else ""}(copy), extra)',
        'def emit_choice(encoded: Bool, name: String, image: J.Surface, extra: String) -> IO(Unit):',
        '  match encoded:', '    case False{}: emit(name, image, extra)',
        '    case True{}: emit_qoi(name, J.Surface.copy(image), extra)',
        'def emit_bordered(name: String, encoded: Bool, observed: J.Surface & J.Rectangle) -> IO(Unit):',
        '  match observed:', '    case Tuple{surface, J.Rectangle{x, y, w, h}}:',
        '      emit_choice(encoded, name, surface, ",\\"alpha_border\\":[" ++ U32.show(F32.to_u32(x)) ++ "," ++ U32.show(F32.to_u32(y)) ++ "," ++ U32.show(F32.to_u32(w)) ++ "," ++ U32.show(F32.to_u32(h)) ++ "]")',
        'def emit_observed(border: Maybe<&2, F32>, name: String, encoded: Bool, image: J.Surface) -> IO(Unit):',
        '  match border:', '    case None{}: emit_choice(encoded, name, image, "")',
        f'    case Some{{threshold}}: emit_bordered(name, encoded, J.Surface.alpha_border{"!" if gpu else ""}(image, threshold))',
        'def emit_result(name: String, encoded: Bool, border: Maybe<&2, F32>, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):',
        '  match result:', '    case Fail{_}:',
        '      IO.die(Unit, 1, "valid transform fixture was rejected")',
        '    case Done{surface}:', '      emit_observed(border, name, encoded, surface)', '',
        'def extracted(keep: Bool, pair: J.Surface & Maybe<J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:',
        '  match pair:', '    case Tuple{source, None{}}:',
        '      Fail{(source, J.InvalidRectangle{})}', '    case Tuple{source, Some{region}}:',
        '      Done{Bool.pick(J.Surface, keep, source, region)}', '',
        'def composed(keep: Bool, result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:',
        '  match result:', '    case Fail{Tuple{Tuple{destination, source}, error}}:',
        '      Fail{(Bool.pick(J.Surface, keep, source, destination), error)}',
        '    case Done{Tuple{destination, source}}:',
        '      Done{Bool.pick(J.Surface, keep, source, destination)}', '',
    ]
    lines += ['def write_matrix(surface: J.Surface, +x: F32, +y: F32, matrix: J.Matrix) -> J.Surface:',
              '  J.Matrix{' + ', '.join(MATRIX_FIELDS) + '} = matrix']
    for index, field in enumerate(MATRIX_FIELDS):
        previous = 'surface' if index==0 else f'p{index-1}'
        lines += [f'  p{index} = J.Surface.draw_pixel({previous}, (x + {index}.0 : F32), y, F32.bits({field}))']
    lines += ['  p15', '']
    for i, case in enumerate(cases):
        for j, op in enumerate(case['operations']):
            if op['op'] not in ('blit', 'blit_region', 'blit_rect', 'alpha_mask'):
                continue
            source = op['source']
            depth = (source['width'] * source['height'] - 1).bit_length()
            lines += [f'def source_{i}_{j}() -> J.Surface:', f'  p0 = Array.new(U32, {depth}n, 0)']
            for k, pixel in enumerate(source['pixels']):
                lines += [f'  p{k+1} = Array.set(U32, p{k}, {k}, {rgba(pixel)})']
            lines += [f'  J.Surface{{{source["width"]}, {source["height"]}, p{len(source["pixels"])}}}', '']
        lines += [f'def draw_{i}(surface: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:',
                  '  do Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:']
        previous = 'surface'
        for j, op in enumerate(case["operations"]):
            kind = op["op"]
            if kind == 'from_channel':
                draw = f'J.Surface.from_channel({previous}, {f32(op["channel"])})'
                previous = f's{j}'
                pick = 'fst' if op.get('observe_source') else 'snd'
                lines += [f'    {previous} : J.Surface = Pair.{pick}(J.Surface, J.Surface, {draw})']
                continue
            if kind in ('rotate_degrees','to_pot'):
                draw = f'J.Surface.rotate_degrees_for(J.{gradient_reference()}{{}}, {previous}, {f32(op["degrees"])})' if kind=='rotate_degrees' else f'J.Surface.to_pot({previous}, {rgba(op["color"])})'
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface <- {draw}']
                continue
            if kind in ('alpha_crop','resize_canvas'):
                if kind == 'alpha_crop':
                    draw = f'J.Surface.alpha_crop({previous}, {f32(op["threshold"])})'
                else:
                    draw = f'J.Surface.resize_canvas({previous}, {op["width"]}, {op["height"]}, {f32(op["x"])}, {f32(op["y"])}, {rgba(op["color"])})'
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface {"=" if kind == "alpha_crop" else "<-"} {draw}']
                continue
            if kind == 'alpha_mask':
                draw = f'J.Surface.alpha_mask({previous}, source_{i}_{j}())'
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface <- composed({"True{}" if op.get("observe_source") else "False{}"}, {draw})']
                continue
            if kind in ('blit', 'blit_region', 'blit_rect'):
                args = f'{previous}, source_{i}_{j}(), '
                if kind in ('blit_region', 'blit_rect'):
                    rect = op['source_rect']
                    args += 'J.Rectangle{' + ', '.join(f32(rect[k]) for k in ('x', 'y', 'width', 'height')) + '}, '
                if kind == 'blit_rect':
                    target = op['dest_rect']
                    args += 'J.Rectangle{' + ', '.join(f32(target[k]) for k in ('x', 'y', 'width', 'height')) + '}, '
                else:
                    args += f'{f32(op["x"])}, {f32(op["y"])}, '
                args += str(rgba(op['tint']))
                function = {'blit':'draw_image', 'blit_region':'draw_image_region', 'blit_rect':'draw_image_rect'}[kind]
                draw = f'J.Surface.{function}({args})'
                pick = 'snd' if op.get('observe_source') else 'fst'
                previous = f's{j}'
                if kind in ('blit_region', 'blit_rect'):
                    lines += [f'    {previous} : J.Surface <- composed({"True{}" if op.get("observe_source") else "False{}"}, {draw})']
                else:
                    lines += [f'    {previous} : J.Surface = Pair.{pick}(J.Surface, J.Surface, {draw})']
                continue
            if kind in ('crop', 'extract', 'resize_nn', 'resize'):
                if kind in ('resize_nn', 'resize'):
                    draw = f'J.Surface.{kind}({previous}, {op["width"]}, {op["height"]})'
                else:
                    rect = 'J.Rectangle{' + ', '.join(f32(op[k]) for k in ('x', 'y', 'width', 'height')) + '}'
                    draw = f'J.Surface.{kind}({previous}, {rect})'
                    if kind == 'extract':
                        draw = f'extracted({"True{}" if op.get("observe_source") else "False{}"}, {draw})'
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface <- {draw}']
                continue
            args = [previous]
            if kind in VECTOR_APIS:
                namespace, dimensions, apis = VECTOR_APIS[kind]
                _, signature, result = apis[op['function']]
                profiled = (op['function'] in ('clamp','min','max') or kind=='vector_value' and op['function']=='rotate'
                            or kind=='matrix_value' and op['function'] in MATRIX_ROTATIONS)
                function_name = op['function']+'_for' if profiled else op['function']
                profile = f'J.{gradient_reference()}{{}}, ' if profiled else ''
                expression = f'J.{namespace}.{function_name}({profile}{vector_arguments(signature,op["args"],bend=True)})'
                if result == 'buffer':
                    previous = f's{j}'
                    lines += [f'    {previous} : J.Surface <- write_float_buffer({dimensions}n, {args[0]}, {f32(op["x"])}, {f32(op["y"])}, {expression})']
                    continue
                function = {'vector':{2:'write_vector',3:'write_vector3',4:'write_vector4'}.get(dimensions), 'matrix':'write_matrix', 'pair':'write_vector_pair'}.get(result,'J.Surface.draw_pixel')
                value = expression if result in ('vector','matrix','pair','color') else f'Bool.to_u32({expression})' if result=='bool' else f'F32.bits({expression})'
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface = {function}({args[0]}, {f32(op["x"])}, {f32(op["y"])}, {value})']
                continue
            if kind == 'collision_value':
                _, signature, result = COLLISION_APIS[op['function']]
                arguments = vector_arguments(signature,op['args'],bend=True)
                if op['function']=='point_poly':
                    arguments += ', [' + ','.join('J.Vector2{' + ','.join(f32(v) for v in p) + '}' for p in op['points']) + ']'
                function_name = op['function']
                if function_name == 'lines':
                    function_name = 'lines_for'
                    arguments = f'J.{collision_arithmetic()}{{}}, ' + arguments
                expression = f'J.Collision.{function_name}({arguments})'
                function = {'rectangle':'write_rectangle','hit':'write_hit','bool':'J.Surface.draw_pixel'}[result]
                value = f'Bool.to_u32({expression})' if result=='bool' else expression
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface = {function}({args[0]}, {f32(op["x"])}, {f32(op["y"])}, {value})']
                continue
            if kind == 'alpha_clear':
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface = J.Surface.alpha_clear({args[0]}, {rgba(op["color"])}, {f32(op["threshold"])})']
                continue
            if kind in COLOR_IMAGE_APIS:
                args += [f32(op['amount'])] if kind in ('color_contrast', 'color_brightness') else [str(rgba(op['color']))]
                if kind == 'color_replace':
                    args += [str(rgba(op['replacement']))]
                previous = f's{j}'
                lines += [f'    {previous} : J.Surface = J.Surface.{kind}({", ".join(args)})']
                continue
            if kind in ('line', 'line_v', 'line_ex', 'triangle', 'triangle_lines', 'triangle_ex'):
                count = 2 if kind.startswith('line') else 3
                for point in range(count):
                    x, y = f32(op['x'+str(point)]), f32(op['y'+str(point)])
                    args += [x, y] if kind == 'line' else [f'J.Vector2{{{x}, {y}}}']
            elif kind in ('pixel_v', 'circle_v', 'circle_lines_v'):
                args += [f'J.Vector2{{{f32(op["x"])}, {f32(op["y"])}}}']
            elif kind == 'rectangle_v':
                args += [f'J.Vector2{{{f32(op["x"])}, {f32(op["y"])}}}', f'J.Vector2{{{f32(op["width"])}, {f32(op["height"])}}}']
            elif kind in ('rectangle_rec', 'rectangle_lines'):
                args += ['J.Rectangle{' + ', '.join(f32(op[k]) for k in ('x','y','width','height')) + '}']
            elif kind in ('triangle_fan', 'triangle_strip'):
                args += ['[' + ', '.join(f'J.Vector2{{{f32(x)}, {f32(y)}}}' for x,y in op['points']) + ']']
            elif kind != 'clear' and kind not in UNARY_IMAGE_APIS:
                args += [f32(op['x']), f32(op['y'])]
            if kind == 'rectangle':
                args += [f32(op['width']), f32(op['height'])]
            if kind in ('circle', 'circle_v', 'circle_lines', 'circle_lines_v'):
                args += [str(op['radius'])]
            if kind in ('line_ex', 'rectangle_lines'):
                args += [str(op['thickness'])]
            if kind == 'blend_color':
                args += [f'J.Color.alpha_blend({rgba(op["destination"])}, {rgba(op["color"])}, {rgba(op["tint"])})']
            elif kind == 'color_value':
                function = op['function']
                values = [str(rgba(op['color']))]
                if function in ('tint', 'lerp', 'equal'):
                    values += [str(rgba(op['other']))]
                if function not in ('tint', 'equal'):
                    values += [f32(op['factor'])]
                value = f'J.Color.{COLOR_VALUE_APIS[function][1]}({", ".join(values)})'
                args += [f'Bool.to_u32({value})' if function == 'equal' else value]
            elif kind == 'number_value':
                value = f'J.Math.{op["function"]}(' + ', '.join(f32(v) for v in op['args']) + ')'
                args += [f'Bool.to_u32({value})' if op['function'] == 'float_equals' else f'F32.bits({value})']
            elif kind not in UNARY_IMAGE_APIS:
                args += [str(rgba(op['color']))]
            if kind == 'triangle_ex':
                args += [str(rgba(op['color2'])), str(rgba(op['color3']))]
            function = kind if kind == 'clear' or kind in UNARY_IMAGE_APIS else 'draw_' + kind
            if kind in ('blend_color', 'color_value', 'number_value'):
                function = 'draw_pixel'
            previous = f's{j}'
            lines += [f'    {previous} : J.Surface = J.Surface.{function}({", ".join(args)})']
        created_type = 'Result<&1, &1, J.Image.DecodeError, J.Surface>' if 'qoi' in case else 'Maybe<J.Surface>'
        failure = 'Fail{_}' if 'qoi' in case else 'None{}'
        success = 'Done{surface}' if 'qoi' in case else 'Some{surface}'
        border = 'Some{' + f32(case['alpha_border']) + '}' if 'alpha_border' in case else 'None{}'
        lines += [f'    return {previous}', '', f'def case_{i}(created: {created_type}) -> IO(Unit):',
                  '  match created:', f'    case {failure}:',
                  '      IO.die(Unit, 1, "valid fixture image creation failed")',
                  f'    case {success}:',
                  f'      emit_result("{case["id"]}", {"True{}" if case.get("export_qoi") else "False{}"}, {border}, draw_{i}{"!" if gpu else ""}(surface))', '']
    lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
    for i, case in enumerate(cases):
        creation = f'J.Surface.decode_qoi{"!" if gpu else ""}([' + ','.join(map(str,case['qoi'])) + '])' if 'qoi' in case else f'J.Surface.create({case["width"]}, {case["height"]}, {rgba(case["background"])})'
        if 'checked' in case:
            checked = case['checked']
            creation = f'J.Surface.create_checked{"!" if gpu else ""}({case["width"]}, {case["height"]}, {checked["tile_width"]}, {checked["tile_height"]}, {rgba(case["background"])}, {rgba(checked["color"])})'
        for kind in ('gradient_square','gradient_radial','gradient_linear'):
            if kind in case:
                gradient = case[kind]
                parameter = gradient['direction'] if kind=='gradient_linear' else gradient['density']
                function = 'create_gradient_linear_for' if kind=='gradient_linear' else 'create_'+kind
                profile = f'J.{gradient_reference()}{{}}, ' if kind=='gradient_linear' else ''
                creation = f'J.Surface.{function}{"!" if gpu else ""}({profile}{case["width"]}, {case["height"]}, {f32(parameter)}, {rgba(case["background"])}, {rgba(gradient["outer"])})'
        lines += [f'    case_{i}({creation})']
    return '\n'.join(lines) + '\n'


def parse_output(output, cases):
    rows = [json.loads(line) for line in output.splitlines() if line.strip()]
    if len(rows) != len(cases):
        raise ValueError(f"Expected {len(cases)} result rows, received {len(rows)}")
    for row, case in zip(rows, cases):
        width, height = result_size(case)
        if not all(integer(row[k], 1, 4096) for k in ('width', 'height')):
            raise ValueError(f"Invalid output dimensions: {row['id']}")
        if (row['id'], row['width'], row['height']) != (case['id'], width, height):
            raise ValueError(f"Wrong scenario identity/dimensions: {row['id']}")
        if len(row['pixels']) != width * height:
            raise ValueError(f"Wrong pixel count: {row['id']}")
        if not all(integer(p, 0, 2**32 - 1) for p in row['pixels']):
            raise ValueError(f"Invalid RGBA word: {row['id']}")
        if case.get('export_qoi'):
            encoded = row.get('qoi')
            if not isinstance(encoded, list) or not encoded or not all(integer(v, 0, 255) for v in encoded):
                raise ValueError(f"Invalid QOI bytes: {row['id']}")
        if 'alpha_border' in case:
            border = row.get('alpha_border')
            if not isinstance(border, list) or len(border)!=4 or not all(integer(v,0,4096) for v in border):
                raise ValueError(f"Invalid alpha border: {row['id']}")
            x,y,w,h = border
            if x+w > width or y+h > height:
                raise ValueError(f"Alpha border exceeds image: {row['id']}")
    return rows


def compare(expected, actual):
    if not expected or len(expected) != len(actual):
        raise ValueError("Missing or empty results")
    for reference, candidate in zip(expected, actual):
        if {k: reference[k] for k in ('id', 'width', 'height')} != {k: candidate[k] for k in ('id', 'width', 'height')}:
            raise ValueError("Scenario identity/dimensions mismatch")
        if len(reference['pixels']) != len(candidate['pixels']):
            raise ValueError(f"{reference['id']}: pixel count mismatch")
        for i, (a, b) in enumerate(zip(reference['pixels'], candidate['pixels'])):
            if a != b:
                x, y = i % reference['width'], i // reference['width']
                raise ValueError(f"{reference['id']}: pixel ({x}, {y}): raylib={a:08x}, Jonlib={b:08x}")
        if reference.get('qoi') != candidate.get('qoi'):
            raise ValueError(f"{reference['id']}: QOI export bytes differ")
        if reference.get('alpha_border') != candidate.get('alpha_border'):
            raise ValueError(f"{reference['id']}: alpha border differs")


def source_gate():
    sources = [ROOT / 'jonlib.bend', *sorted((ROOT / 'src').glob('**/*.bend'))]
    for path in sources:
        text = path.read_text()
        if re.search(r'@unsafe|^def\s+[\w.]+\?', text, re.M):
            raise ValueError(f"Unsafe library implementation: {path}")
        for line in text.splitlines():
            if line.strip().startswith('import '):
                if line.startswith((' ', '\t')) or not re.fullmatch(r'import (Base|\./[\w/.-]+\.bend(?: as \w+)?)', line):
                    raise ValueError(f"Unexpected library import: {path}: {line}")
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}


def inventory(header):
    reference = json.loads((ROOT / 'api/reference.json').read_text())
    if hashlib.sha256(header.encode()).hexdigest() != reference['headers']['raylib.h']['sha256']:
        raise ValueError('raylib.h differs from the committed API reference')
    declarations = [entry for entry in reference['entries'] if entry['header'] == 'raylib.h' and entry['kind'] == 'function']
    names = {entry['name'] for entry in declarations}
    mapping = json.loads((ROOT / 'docs/api-map.json').read_text())
    if set(mapping) - names:
        raise ValueError('Compatibility map contains unknown raylib APIs')
    return [dict(raylib=entry['name'], signature=entry['signature'],
                 **mapping.get(entry['name'], dict(jonlib=None, status='not-implemented')))
            for entry in declarations]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, default=Path.home() / 'Projetos/bendlang/bend')
    parser.add_argument('--raylib-source', type=Path, default=Path.home() / 'Projetos/raysan5/raylib')
    parser.add_argument('--fixtures', type=Path, default=ROOT / 'tests/fixtures/images.json')
    parser.add_argument('--gpu', action='store_true', help='Build and force the native GPU lane; failure is fatal')
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    report = dict(passed=False, lanes={}, profile='rgba8-cpu-images-v1')
    report_path = BUILD / 'conformance.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    started = time.monotonic()
    lock = json.loads((ROOT / 'toolchain.json').read_text())
    checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    checkout(args.raylib_source, lock['raylib']['revision'])
    run([sys.executable, ROOT / 'tools/api_plan.py', 'check', '--raylib-source', args.raylib_source])
    report['toolchain'] = lock
    report['host'] = dict(system=platform.system(), machine=platform.machine(),
                          bun=run(['bun', '--version']).strip(),
                          clang=run(['clang', '--version']).splitlines()[0])
    report['sources'] = source_gate()
    api = inventory((args.raylib_source / 'src/raylib.h').read_text())
    (BUILD / 'api-inventory.json').write_text(json.dumps(api, indent=2) + '\n')
    report['api_inventory'] = dict(total=len(api), mapped=sum(row['jonlib'] is not None for row in api))
    report['progression'] = json.loads((ROOT / 'api/summary.json').read_text())['core_functions']
    report['verification_sources'] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (ROOT / 'tools/conformance.py', ROOT / 'tests/contracts.bend',
                     ROOT / 'tests/transforms.bend', ROOT / 'tests/transforms_gpu.bend', ROOT / 'examples/transforms.bend',
                     ROOT / 'tests/decoding.bend', ROOT / 'tests/decoding_gpu.bend',
                     ROOT / 'tests/io_decoding.bend',
                     ROOT / 'examples/qoi_roundtrip.bend',
                     ROOT / 'LAWS.bend', ROOT / 'PROOF.bend', ROOT / 'examples/headless.bend', ROOT / 'examples/composite.bend',
                     ROOT / 'docs/api-map.json', ROOT / 'tools/api_catalog.py', ROOT / 'tools/api_plan.py',
                     ROOT / 'api/reference.json', ROOT / 'api/milestones.json', ROOT / 'api/progress.json',
                     ROOT / 'api/summary.json')
    }
    cases = cases_from(json.loads(args.fixtures.read_text()))
    expanded = json.dumps(cases, sort_keys=True)
    (BUILD / 'scenarios.json').write_text(expanded + '\n')
    report['fixtures_sha256'] = hashlib.sha256(expanded.encode()).hexdigest()
    report['scenarios'] = [c['id'] for c in cases]
    report['pixels_per_lane'] = sum(width * height for width, height in map(result_size, cases))
    report['numeric_probe_cells'] = sum(1 if op['op']=='number_value' else numeric_cells(op['op'],op['function'])
                                        for case in cases for op in case['operations'] if op['op']=='number_value' or op['op'] in VECTOR_APIS and VECTOR_APIS[op['op']][2][op['function']][2]!='color')
    report['numeric_probe_cells'] += sum(COLLISION_CELLS[COLLISION_APIS[op['function']][2]]
                                        for case in cases for op in case['operations'] if op['op']=='collision_value')
    report['alpha_border_observations'] = sum('alpha_border' in case for case in cases)
    report['pot_axes_checked'] = 4096 if any(op['op']=='to_pot' for case in cases for op in case['operations']) else 0
    report['channel_bytes_checked'] = 1024 if any(op['op']=='from_channel' for case in cases for op in case['operations']) else 0
    cli = ['bun', args.bend_source / 'bend2/main.ts']
    library_verdict = run([*cli, ROOT / 'jonlib.bend', '--check-only'])
    if library_verdict.strip() != 'All terms check.':
        raise ValueError(f"Unexpected library verdict: {library_verdict}")
    proof_verdict = run([*cli, ROOT / 'PROOF.bend', '--check-only'])
    if proof_verdict.strip() != 'All terms check.':
        raise ValueError(f"Unexpected proof verdict: {proof_verdict}")
    report['proof'] = proof_verdict.strip()
    report['scalar_profile'] = 'raymath-f32-uncontracted-v1'
    cmake = BUILD / 'raylib'
    print('Building pinned raylib reference...', flush=True)
    run(['cmake', '-S', args.raylib_source, '-B', cmake, '-DPLATFORM=Memory',
         '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_EXAMPLES=OFF', '-DCUSTOMIZE_BUILD=ON',
         '-DSUPPORT_MODULE_RAUDIO=OFF', '-DUSE_EXTERNAL_GLFW=OFF'])
    run(['cmake', '--build', cmake, '--parallel', '4'])
    (BUILD / 'reference.c').write_text(c_source(cases))
    run(['clang', '-std=c11', '-O2', '-I' + str(args.raylib_source / 'src'),
         BUILD / 'reference.c', cmake / 'raylib/libraylib.a', '-lm', '-o', BUILD / 'reference'])
    reference_text = run([BUILD / 'reference'])
    (BUILD / 'reference.jsonl').write_text(reference_text)
    reference = parse_output(reference_text, cases)
    exports = [row for row in reference if 'qoi' in row]
    report['qoi_exports'] = dict(scenarios=len(exports), bytes=sum(len(row['qoi']) for row in exports))
    source = BUILD / 'candidate.bend'
    source.write_text(bend_source(cases))
    print('Building Bend CPU and JavaScript runners...', flush=True)
    run([*cli, source, '-o', BUILD / 'candidate', '-o', BUILD / 'candidate.js'])
    lanes = [('cpu-1', [BUILD / 'candidate', '--threads', '1']),
             ('cpu-2', [BUILD / 'candidate', '--threads', '2']),
             ('javascript', ['bun', BUILD / 'candidate.js'])]
    if args.gpu:
        gpu_source = BUILD / 'candidate-gpu.bend'
        gpu_source.write_text(bend_source(cases, gpu=True))
        print('Building native GPU runner...', flush=True)
        run([*cli, gpu_source, '-o', BUILD / 'candidate-gpu'])
        lanes.append(('gpu-forced', [BUILD / 'candidate-gpu', '--gpu', 'on']))
    for lane, command in lanes:
        output = run(command)
        (BUILD / f'{lane}.jsonl').write_text(output)
        compare(reference, parse_output(output, cases))
        report['lanes'][lane] = dict(passed=True, scenarios=len(cases), pixels=report['pixels_per_lane'])
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'{lane}: {len(cases)} scenarios, {report["pixels_per_lane"]} pixels match exactly', flush=True)
    for name, expected, key in [('contracts', 'contracts ok', 'contracts'),
                                ('transforms', 'transform contracts ok', 'transform_contracts'),
                                ('decoding', 'decode contracts ok', 'decode_contracts')]:
        binary = BUILD / f'verify-{name}'
        run([*cli, ROOT / f'tests/{name}.bend', '-o', binary, '-o', str(binary) + '.js'])
        for lane, command in [('cpu', [binary]), ('javascript', ['bun', str(binary) + '.js'])]:
            if run(command).strip() != expected:
                raise ValueError(f'{lane}: {name} contract failed')
        report[key] = ['cpu', 'javascript']
        print(f'{name}: CPU/JS passed', flush=True)
    if args.gpu:
        for name, expected, key in [('transforms','transform contracts ok','transform_contracts'),
                                    ('decoding','decode contracts ok','decode_contracts')]:
            binary = BUILD / f'verify-{name}-gpu'
            run([*cli, ROOT / f'tests/{name}_gpu.bend', '-o', binary])
            if run([binary, '--gpu', 'on']).strip() != expected:
                raise ValueError(f'GPU {name} contract failed')
            report[key].append('gpu-forced')
            print(f'{name}: forced GPU contracts passed', flush=True)
    for name, scenario, key in [('headless', 'radius-12-regression', 'example'),
                                ('composite', 'composite-example', 'composite_example'),
                                ('transforms', 'transform-example', 'transform_example')]:
        example_reference = next((row for row in reference if row['id'] == scenario), None)
        if example_reference is None:
            raise ValueError(f'Fixtures must include {scenario} for the {name} example comparison')
        run([*cli, ROOT / f'examples/{name}.bend', '-o', BUILD / name])
        run([BUILD / name])
        ppm = (BUILD / f'{name}.ppm').read_text().split()
        if ppm[:4] != ['P3', str(example_reference['width']), str(example_reference['height']), '255']:
            raise ValueError(f'{name}: PPM header mismatch')
        expected_rgb = [str((p >> shift) & 255) for p in example_reference['pixels'] for shift in (24, 16, 8)]
        if ppm[4:] != expected_rgb:
            raise ValueError(f'{name}: RGB pixels differ from raylib')
        report[key] = dict(path=f'.build/{name}.ppm', pixels=len(example_reference['pixels']), passed=True)
        print(f'{name} PPM export: every RGB pixel matches raylib', flush=True)
    qoi_reference = next((row for row in reference if row['id'] == 'qoi-all-opcodes'), None)
    if qoi_reference is None or 'qoi' not in qoi_reference:
        raise ValueError('Fixtures must include qoi-all-opcodes with export_qoi for the file round trip')
    qoi_binary = BUILD / 'qoi-roundtrip'
    if (BUILD / 'qoi-roundtrip.missing').exists():
        raise ValueError('The missing-file QOI test path already exists')
    (BUILD / 'qoi-roundtrip.bad').write_bytes(b'bad')
    with (BUILD / 'qoi-roundtrip.large').open('wb') as oversized:
        oversized.truncate(83886103)
    run([*cli, ROOT / 'examples/qoi_roundtrip.bend', '-o', qoi_binary, '-o', str(qoi_binary)+'.js'])
    expected = {key:qoi_reference[key] for key in ('id','width','height','pixels')}
    fixture = dict(id=expected['id'], width=expected['width'], height=expected['height'], operations=[])
    for lane, command in [('cpu',[qoi_binary]), ('javascript',['bun',str(qoi_binary)+'.js'])]:
        loaded = parse_output(run(command), [fixture])
        compare([expected], loaded)
        if (BUILD / 'qoi-roundtrip.qoi').read_bytes() != bytes(qoi_reference['qoi']):
            raise ValueError(f'{lane}: QOI file bytes differ from actual raylib ExportImage')
    io_binary = BUILD / 'verify-io-decoding'
    run([*cli, ROOT / 'tests/io_decoding.bend', '-o', io_binary, '-o', str(io_binary)+'.js'])
    for command in ([io_binary], ['bun',str(io_binary)+'.js']):
        if run(command).strip() != 'qoi file errors ok':
            raise ValueError('QOI file error contract failed')
    report['qoi_file_roundtrip'] = dict(passed=True, lanes=['cpu','javascript'], path='.build/qoi-roundtrip.qoi', error_cases=['missing-file','malformed-file','oversized-file'])
    print('QOI file export/load: CPU/JS bytes and decoded pixels match raylib', flush=True)
    report['passed'] = True
    report['elapsed_seconds'] = round(time.monotonic() - started, 3)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS — evidence: .build/conformance.json')


if __name__ == '__main__':
    main()
