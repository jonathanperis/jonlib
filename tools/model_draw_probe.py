#!/usr/bin/env python3
"""Compare Jonlib's materials, DrawMesh, DrawModel* and DrawBillboard* with
raylib's software renderer.

Same reference as tools/models_probe.py: pinned raylib on PLATFORM=Memory
(rlgl.h's OpenGL 1.1 path into src/external/rlsw.h) built with
CMAKE_C_FLAGS=-ffp-contract=off, read back with rlCopyFramebuffer. Scenes run
InitWindow and operations: the models, rlgl and texture probes' ones plus
DrawMesh (generated cubes, planes, polygons, the empty mesh and custom meshes
with and without texcoords, colors and indices, a vertex count not a
multiple of 3, materials with translucent colors and textures from the
scene's slots), DrawModel, DrawModelEx, DrawModelWires(Ex), two-mesh models
with SetModelMeshMaterial and a model transform, DrawMeshInstanced (no-op
under OpenGL 1.1), DrawBillboard, DrawBillboardRec and DrawBillboardPro
(negative sizes, origins, rotations), UnloadMaterial (a texture referenced
by several maps; its id is reused by the next texture), and logged results
of IsMaterialValid, IsModelValid and LoadMaterialDefault/SetMaterialTexture
maps.

Contracts (Jonlib must answer null): indices beyond the vertex count, a
diffuse texture id Jonlib does not hold, a negative mesh material index,
SetMaterialTexture beyond the 12 maps, DrawMesh while an rlBegin primitive
is recorded, and sinf/cosf arguments outside the host profile's verified set
(DrawModelEx angles, half the DrawBillboardPro rotation). CPU-1, CPU-2 and
JavaScript lanes.
"""
import hashlib
import json
import random

from conformance import gradient_reference
import frame_probe as fp
import mesh_probe as meshp
import models_probe as mp
import probekit
import rlgl_probe as rp
import texture_probe as tp
from probekit import ProbeFailure

C = fp.C
f32 = fp.f32
cf = fp.cf
cc = fp.cc
W = fp.word
DEG2RAD = fp.DEG2RAD
RED, GREEN, BLUE, WHITE, BLACK = rp.RED, rp.GREEN, rp.BLUE, rp.WHITE, rp.BLACK
NONE = 255

KINDS = {'mesh': 400, 'model': 401, 'model_ex': 402, 'wires': 403, 'wires_ex': 404, 'model2': 405, 'billboard': 406, 'billboard_rec': 407,
         'billboard_pro': 408, 'instanced': 409, 'unload_mat': 410, 'valid': 411, 'matinfo': 412}
IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]


# -----------------------------------------------------------------------------
# Meshes: ('cube', w, h, l), ('plane', w, l, rx, rz), ('poly', sides, r),
# ('empty',), ('custom', vertices, texcoords, colors, indices, no_vertices)

def custom(vertices, texcoords=None, colors=None, indices=None, no_vertices=False):
    return ('custom', [f32(v) for v in vertices], None if texcoords is None else [f32(v) for v in texcoords], colors, indices, no_vertices)


def c_floats(values):
    return '(float[]){ ' + ', '.join(cf(v) for v in values) + ' }'


def c_mesh(spec):
    kind = spec[0]
    if kind == 'cube':
        return f'GenMeshCube({cf(spec[1])}, {cf(spec[2])}, {cf(spec[3])})'
    if kind == 'plane':
        return f'GenMeshPlane({cf(spec[1])}, {cf(spec[2])}, {spec[3]}, {spec[4]})'
    if kind == 'poly':
        return f'GenMeshPoly({spec[1]}, {cf(spec[2])})'
    if kind == 'empty':
        return 'GenMeshPoly(2, 1.0f)'
    _, vertices, texcoords, colors, indices, no_vertices = spec
    vc = len(vertices) // 3
    tc = len(indices) // 3 if indices is not None else vc // 3
    v = 'NULL' if no_vertices else c_floats(vertices)
    t = 'NULL' if texcoords is None else c_floats(texcoords)
    c = 'NULL' if colors is None else '(unsigned char[]){ ' + ', '.join(map(str, colors)) + ' }'
    i = 'NULL' if indices is None else '(unsigned short[]){ ' + ', '.join(map(str, indices)) + ' }'
    return f'custom({vc}, {tc}, {v}, {t}, {c}, {i})'


def w_mesh(spec):
    kind = spec[0]
    if kind == 'cube':
        words = [1] + [W(x) for x in spec[1:]]
    elif kind == 'plane':
        words = [2, W(spec[1]), W(spec[2]), spec[3], spec[4]]
    elif kind == 'poly':
        words = [3, spec[1], W(spec[2])]
    elif kind == 'empty':
        words = [5]
    else:
        _, vertices, texcoords, colors, indices, no_vertices = spec
        vc = len(vertices) // 3
        tc = len(indices) // 3 if indices is not None else vc // 3
        flags = (texcoords is not None) | (colors is not None) << 1 | (indices is not None) << 2 | no_vertices << 3
        words = [4, vc, tc, flags] + [W(x) for x in vertices] + [W(x) for x in texcoords or []] + list(colors or []) + list(indices or [])
    return [len(words)] + words


def c_slot(slot):
    return 'NULL' if slot == NONE else f'&t[{slot}]'


def c_mat(slot, color, fake):
    return f'mat({cc(color)}, {c_slot(slot)}, {fake}u)'


def c_matrix(m):
    order = [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15]
    return '(Matrix){ ' + ', '.join(cf(m[i]) for i in order) + ' }'


def v3(x, y, z):
    return (f32(x), f32(y), f32(z))


def cv3(p):
    return mp.cv3(*p)


def c_camera(cam):
    return f'(Camera3D){{ {cv3(cam[0:3])}, {cv3(cam[3:6])}, {cv3(cam[6:9])}, {cf(cam[9])}, {cam[10]} }}'


def camera(position, target, up=(0.0, 1.0, 0.0), fovy=8.0, projection=1):
    return v3(*position) + v3(*target) + v3(*up) + (f32(fovy), projection)


def w_camera(cam):
    return [W(x) for x in cam[:10]] + [cam[10]]


# -----------------------------------------------------------------------------
# Operations
#   ('mesh', slot, color, fake, matrix16, mesh)
#   ('model' | 'wires', slot, color, fake, pos3, scale, tint, mesh)
#   ('model_ex' | 'wires_ex', slot, color, fake, pos3, axis3, angle, scale3, tint, mesh)
#   ('model2', slot, color1, color2, mesh_id, material_id, transform16, pos3, scale, tint, mesh1, mesh2)
#   ('billboard', slot, camera, pos3, scale, tint)
#   ('billboard_rec', slot, camera, source4, pos3, size2, tint)
#   ('billboard_pro', slot, camera, source4, pos3, up3, size2, origin2, rotation, tint)
#   ('instanced', slot, color, fake, mesh), ('unload_mat', slot), ('valid',), ('matinfo', slot, map_type)

def c_op(op):
    name, a = op[0], op[1:]
    if name not in KINDS:
        return mp.c_op(op)
    if name == 'mesh':
        slot, color, fake, m, mesh = a
        return f'    {{ Mesh me = {c_mesh(mesh)}; DrawMesh(me, {c_mat(slot, color, fake)}, {c_matrix(m)}); }}'
    if name in ('model', 'wires'):
        slot, color, fake, pos, scale, tint, mesh = a
        call = 'DrawModel' if name == 'model' else 'DrawModelWires'
        return (f'    {{ Model mo = LoadModelFromMesh({c_mesh(mesh)}); mo.materials[0] = {c_mat(slot, color, fake)}; '
                f'{call}(mo, {cv3(pos)}, {cf(scale)}, {cc(tint)}); }}')
    if name in ('model_ex', 'wires_ex'):
        slot, color, fake, pos, axis, angle, scale, tint, mesh = a
        call = 'DrawModelEx' if name == 'model_ex' else 'DrawModelWiresEx'
        return (f'    {{ Model mo = LoadModelFromMesh({c_mesh(mesh)}); mo.materials[0] = {c_mat(slot, color, fake)}; '
                f'{call}(mo, {cv3(pos)}, {cv3(axis)}, {cf(angle)}, {cv3(scale)}, {cc(tint)}); }}')
    if name == 'model2':
        slot, color1, color2, mesh_id, material_id, transform, pos, scale, tint, mesh1, mesh2 = a
        return (f'    {{ Model mo = {{ 0 }}; mo.transform = {c_matrix(transform)}; mo.meshCount = 2; mo.materialCount = 2; '
                f'mo.meshes = (Mesh[]){{ {c_mesh(mesh1)}, {c_mesh(mesh2)} }}; '
                f'mo.materials = (Material[]){{ {c_mat(slot, color1, 0)}, {c_mat(NONE, color2, 0)} }}; mo.meshMaterial = (int[]){{ 0, 0 }}; '
                f'SetModelMeshMaterial(&mo, {mesh_id}, {material_id}); DrawModel(mo, {cv3(pos)}, {cf(scale)}, {cc(tint)}); }}')
    if name == 'billboard':
        slot, cam, pos, scale, tint = a
        return f'    DrawBillboard({c_camera(cam)}, t[{slot}], {cv3(pos)}, {cf(scale)}, {cc(tint)});'
    if name == 'billboard_rec':
        slot, cam, source, pos, size, tint = a
        return f'    DrawBillboardRec({c_camera(cam)}, t[{slot}], {fp.crec(*source)}, {cv3(pos)}, {fp.cv(*size)}, {cc(tint)});'
    if name == 'billboard_pro':
        slot, cam, source, pos, up, size, origin, rotation, tint = a
        return (f'    DrawBillboardPro({c_camera(cam)}, t[{slot}], {fp.crec(*source)}, {cv3(pos)}, {cv3(up)}, {fp.cv(*size)}, {fp.cv(*origin)}, '
                f'{cf(rotation)}, {cc(tint)});')
    if name == 'instanced':
        slot, color, fake, mesh = a
        return (f'    {{ Matrix ms[2] = {{ MatrixIdentity(), MatrixTranslate(1, 2, 3) }}; DrawMeshInstanced({c_mesh(mesh)}, {c_mat(slot, color, fake)}, ms, 2); }}')
    if name == 'unload_mat':
        slot = a[0]
        return (f'    {{ Material ma = LoadMaterialDefault(); ma.maps[0].texture = t[{slot}]; ma.maps[1].texture = t[{slot}]; ma.maps[4].texture = t[{slot}]; '
                f'UnloadMaterial(ma); t[{slot}] = (Texture2D){{ 0 }}; }}')
    if name == 'valid':
        return '    valid_note();'
    slot, map_type = a
    texture = '(Texture2D){ 0 }' if slot == NONE else f't[{slot}]'
    return f'    {{ Material ma = LoadMaterialDefault(); SetMaterialTexture(&ma, {map_type}, {texture}); material_note(ma); }}'


def op_words(op):
    name, a = op[0], op[1:]
    if name not in KINDS:
        return mp.op_words(op)
    kind = KINDS[name]
    if name == 'mesh':
        slot, color, fake, m, mesh = a
        return kind, [slot, color, fake] + [W(x) for x in m] + w_mesh(mesh)
    if name in ('model', 'wires'):
        slot, color, fake, pos, scale, tint, mesh = a
        return kind, [slot, color, fake] + [W(x) for x in pos] + [W(scale), tint] + w_mesh(mesh)
    if name in ('model_ex', 'wires_ex'):
        slot, color, fake, pos, axis, angle, scale, tint, mesh = a
        return kind, [slot, color, fake] + [W(x) for x in pos + axis + (angle,) + scale] + [tint] + w_mesh(mesh)
    if name == 'model2':
        slot, color1, color2, mesh_id, material_id, transform, pos, scale, tint, mesh1, mesh2 = a
        return kind, ([slot, color1, color2, mesh_id & 0xFFFFFFFF, material_id & 0xFFFFFFFF] + [W(x) for x in transform] + [W(x) for x in pos]
                      + [W(scale), tint] + w_mesh(mesh1) + w_mesh(mesh2))
    if name == 'billboard':
        slot, cam, pos, scale, tint = a
        return kind, [slot] + w_camera(cam) + [W(x) for x in pos] + [W(scale), tint]
    if name == 'billboard_rec':
        slot, cam, source, pos, size, tint = a
        return kind, [slot] + w_camera(cam) + [W(x) for x in source + pos + size] + [tint]
    if name == 'billboard_pro':
        slot, cam, source, pos, up, size, origin, rotation, tint = a
        return kind, [slot] + w_camera(cam) + [W(x) for x in source + pos + up + size + origin + (rotation,)] + [tint]
    if name == 'instanced':
        slot, color, fake, mesh = a
        return kind, [slot, color, fake] + w_mesh(mesh)
    return kind, list(a)


# -----------------------------------------------------------------------------
# Contract rules

def mesh_refused(mesh, libm):
    if mesh[0] == 'poly':
        return meshp.poly_refused(mesh[1], mesh[2], libm)
    if mesh[0] == 'custom':
        vertices, indices, no_vertices = mesh[1], mesh[4], mesh[5]
        return indices is not None and not no_vertices and any(i >= len(vertices) // 3 for i in indices)
    return False


def op_refused(op, libm):
    name, a = op[0], op[1:]
    if name in ('mesh', 'model', 'wires', 'instanced'):
        return name != 'instanced' and (a[2] != 0 or mesh_refused(a[-1], libm))
    if name in ('model_ex', 'wires_ex'):
        return a[2] != 0 or mesh_refused(a[-1], libm) or not fp.accepted(libm, f32(a[5] * DEG2RAD))
    if name == 'model2':
        return a[4] < 0 or mesh_refused(a[-1], libm) or mesh_refused(a[-2], libm)
    if name == 'billboard_pro':
        rotation = a[7]
        return rotation != 0.0 and not fp.accepted(libm, f32(f32(rotation * DEG2RAD) / 2.0))
    if name == 'matinfo':
        return not 0 <= a[1] < 12
    return False


def refused(scene, libm):
    if scene.get('contract'):
        return True
    plain = dict(scene, ops=[op for op in scene['ops'] if op[0] not in KINDS])
    if mp.refused(plain, libm):
        return True
    return any(op_refused(op, libm) for op in scene['ops'] if op[0] in KINDS)


# -----------------------------------------------------------------------------
# Scenes

def translate(x, y, z):
    m = list(IDENTITY)
    m[12], m[13], m[14] = f32(x), f32(y), f32(z)
    return m


def scale_matrix(sx, sy, sz, x=0.0, y=0.0, z=0.0):
    m = translate(x, y, z)
    m[0], m[5], m[10] = f32(sx), f32(sy), f32(sz)
    return m


def scenes():
    rng = random.Random(0x3D0D)
    out = []

    def add(name, width, height, ops, contract=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, screen=False, contract=contract))

    front = mp.camera((0.0, 0.0, 10.0), (0.0, 0.0, 0.0))
    cam_front = camera((0.0, 0.0, 10.0), (0.0, 0.0, 0.0))
    angled = mp.camera((5.0, 4.0, 6.0), (0.0, 0.5, 0.0), fovy=7.0)
    cam_angled = camera((5.0, 4.0, 6.0), (0.0, 0.5, 0.0), fovy=7.0)
    tex_a = tp.image(8, 8, 7, 11)
    tex_b = tp.image(4, 6, 7, 23, opaque=True)
    tex_gray = tp.image(5, 5, 2, 31)

    # Screen-space custom meshes: per-vertex colors, a translucent material,
    # leftover vertices, texcoords without a texture, the alpha flag reset.
    tri = custom([2, 2, 0, 2, 20, 0, 18, 2, 0, 20, 20, 0, 30, 4, 0, 26, 18, 0, 5, 5, 0],
                 colors=[255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 255, 255, 0, 64, 0, 255, 255, 255, 255, 0, 255, 200, 9, 9, 9, 9])
    add('mesh-screen', 32, 24, [('begin',), ('clear', C(40, 40, 40)), ('mesh', NONE, C(255, 255, 255), 0, IDENTITY, tri),
                                ('mesh', NONE, C(255, 200, 0, 128), 0, translate(1.0, 1.0, 0.0),
                                 custom([4, 4, 0, 4, 14, 0, 14, 4, 0, 14, 14, 0, 26, 14, 0, 20, 6, 0], texcoords=[0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0])),
                                ('end',)])
    add('mesh-translucent', 32, 24, [('begin',), ('clear', C(0, 0, 90)), ('rect', 0.0, 0.0, 16.0, 24.0, WHITE),
                                     ('mesh', NONE, C(255, 0, 0, 100), 0, IDENTITY, custom([2, 2, 0, 2, 22, 0, 30, 2, 0, 30, 2, 0, 2, 22, 0, 30, 22, 0])),
                                     ('mesh', NONE, C(0, 255, 0, 100), 0, IDENTITY,
                                      custom([4, 4, 0, 4, 20, 0, 28, 4, 0], colors=[0, 255, 0, 100, 0, 255, 0, 100, 0, 255, 0, 100])),
                                     ('end',)])
    quad = custom([2, 2, 0, 2, 21, 0, 29, 21, 0, 29, 2, 0], texcoords=[0, 0, 0, 1, 1, 1, 1, 0], indices=[0, 1, 2, 0, 2, 3])
    add('mesh-indexed-textured', 32, 24, [('load', 0, tex_a), ('load', 1, tex_b), ('begin',), ('clear', BLACK),
                                          ('mesh', 0, WHITE, 0, IDENTITY, quad), ('mesh', 1, C(255, 255, 255, 160), 0, scale_matrix(0.5, 0.5, 1.0, 8.0, 6.0), quad),
                                          ('mesh', NONE, C(0, 255, 0), 0, translate(0.0, 0.0, 0.0),
                                           custom([20, 3, 0, 20, 10, 0, 30, 3, 0, 30, 10, 0], colors=[255] * 16, indices=[0, 1, 2, 2, 1, 3, 3, 1, 0])),
                                          ('end',)])
    add('mesh-generated', 40, 30, [('load', 0, tex_a), ('load', 2, tex_gray), ('begin',), ('clear', C(10, 20, 30)), front,
                                   ('mesh', 0, WHITE, 0, IDENTITY, ('cube', 2.0, 2.0, 2.0)),
                                   ('mesh', NONE, C(255, 128, 0), 0, translate(2.5, 1.5, 0.0), ('cube', 1.0, 1.5, 0.5)),
                                   ('mesh', 2, C(200, 200, 255), 0, translate(-2.5, -1.5, 0.5), ('plane', 2.0, 2.0, 2, 3)),
                                   ('mesh', NONE, C(0, 255, 0), 0, translate(-2.5, 2.0, 0.0), ('poly', 6, 1.25)),
                                   ('mesh', NONE, C(255, 0, 255), 0, translate(2.5, -2.0, 0.0), ('empty',)),
                                   ('rl_begin', 4), ('v3f', -1.0, -3.5, 0.0), ('v3f', 1.0, -3.5, 0.0), ('v3f', 0.0, -2.0, 0.0), ('rl_end',),
                                   ('end3d',), ('end',)])
    add('mesh-angled', 40, 30, [('load', 0, tex_a), ('begin',), ('clear', BLACK), angled,
                                ('mesh', 0, WHITE, 0, IDENTITY, ('cube', 1.5, 1.0, 1.5)),
                                ('mesh', NONE, C(255, 255, 0, 200), 0, scale_matrix(1.0, 1.0, 1.0, 1.5, 0.0, -1.0), ('plane', 1.5, 1.5, 1, 1)),
                                ('end3d',), ('end',)])
    add('model-basic', 40, 30, [('load', 0, tex_a), ('begin',), ('clear', C(30, 30, 30)), angled,
                                ('model', 0, WHITE, 0, v3(0.0, 0.5, 0.0), 1.0, WHITE, ('cube', 1.5, 1.5, 1.5)),
                                ('model', NONE, C(0, 128, 255), 0, v3(2.0, 0.0, -1.0), 0.75, C(255, 128, 128, 200), ('cube', 1.0, 1.0, 1.0)),
                                ('model', NONE, C(255, 255, 255, 128), 0, v3(-2.0, 0.0, 1.0), 1.25, C(0, 255, 0), ('poly', 8, 1.0)),
                                ('end3d',), ('end',)])
    add('model-ex', 40, 30, [('load', 1, tex_b), ('begin',), ('clear', BLACK), front,
                             ('model_ex', 1, WHITE, 0, v3(-2.0, 1.0, 0.0), v3(1.0, 1.0, 0.0), 45.0, v3(1.0, 1.5, 1.0), WHITE, ('cube', 1.5, 1.5, 1.5)),
                             ('model_ex', NONE, C(255, 0, 0), 0, v3(2.0, -1.0, 0.0), v3(0.0, 0.0, 1.0), 90.0, v3(2.0, 1.0, 1.0), C(255, 255, 255, 128),
                              ('plane', 1.0, 1.0, 1, 1)),
                             ('model_ex', NONE, C(0, 255, 0), 0, v3(2.0, 2.5, 0.0), v3(0.0, 1.0, 0.0), -30.0, v3(1.0, 1.0, 1.0), WHITE, ('cube', 1.0, 0.5, 1.0)),
                             ('end3d',), ('end',)])
    add('model-ex-13', 32, 24, [('begin',), ('clear', BLACK), front,
                                ('model_ex', NONE, C(255, 0, 0), 0, v3(0.0, 0.0, 0.0), v3(0.0, 0.0, 1.0), 13.0, v3(2.0, 2.0, 2.0), WHITE, ('cube', 1.0, 1.0, 1.0)),
                                ('end3d',), ('end',)])
    add('model-wires', 40, 30, [('load', 0, tex_a), ('begin',), ('clear', C(0, 0, 40)), angled,
                                ('wires', 0, WHITE, 0, v3(0.0, 0.5, 0.0), 1.0, WHITE, ('cube', 1.5, 1.5, 1.5)),
                                ('wires_ex', NONE, C(255, 255, 0), 0, v3(2.0, 0.0, -1.0), v3(0.0, 1.0, 0.0), 30.0, v3(1.0, 2.0, 1.0), WHITE,
                                 ('plane', 1.0, 1.0, 2, 2)),
                                ('toggle', 'point', True), ('model', NONE, RED, 0, v3(-2.0, 0.0, 1.0), 1.0, WHITE, ('cube', 1.0, 1.0, 1.0)),
                                ('wires', NONE, GREEN, 0, v3(-2.0, 1.5, 1.0), 1.0, WHITE, ('cube', 0.5, 0.5, 0.5)),
                                ('model', NONE, BLUE, 0, v3(1.0, 2.0, 1.0), 1.0, WHITE, ('cube', 0.75, 0.75, 0.75)),
                                ('end3d',), ('end',)])
    m2 = scale_matrix(1.0, 1.0, 1.0, 0.5, 0.0, 0.0)
    add('model-two-meshes', 40, 30, [('load', 0, tex_a), ('begin',), ('clear', BLACK), front,
                                     ('model2', 0, WHITE, C(255, 0, 0), 1, 1, m2, v3(-1.0, 0.0, 0.0), 1.0, WHITE, ('cube', 1.5, 1.5, 1.5), ('poly', 6, 1.0)),
                                     ('model2', 0, C(128, 255, 128), C(0, 0, 255), 5, 0, IDENTITY, v3(2.0, 1.5, 0.0), 0.75, C(255, 255, 255, 180),
                                      ('cube', 1.0, 1.0, 1.0), ('cube', 0.5, 0.5, 2.0)),
                                     ('model2', NONE, C(255, 255, 0), C(0, 255, 255), 1, 9, translate(0.0, -2.5, 0.0), v3(0.0, 0.0, 0.0), 1.0, WHITE,
                                      ('cube', 1.0, 1.0, 1.0), ('plane', 2.0, 1.0, 1, 1)),
                                     ('end3d',), ('end',)])
    add('billboards', 40, 30, [('load', 0, tex_a), ('load', 1, tex_b), ('begin',), ('clear', C(20, 40, 20)), angled,
                               ('billboard', 0, cam_angled, v3(0.0, 0.5, 0.0), 2.0, WHITE),
                               ('billboard', 1, cam_angled, v3(2.0, 0.0, -1.0), 1.5, C(255, 128, 128, 200)),
                               ('billboard_rec', 0, cam_angled, (2.0, 1.0, 4.0, 5.0), v3(-2.0, 1.0, 1.0), (1.5, 2.0), WHITE),
                               ('billboard_rec', 1, cam_angled, (0.0, 0.0, 4.0, 6.0), v3(-1.0, -1.0, 2.0), (-1.5, 2.0), WHITE),
                               ('end3d',), ('end',)])
    add('billboards-pro', 40, 30, [('load', 0, tex_a), ('load', 1, tex_b), ('begin',), ('clear', BLACK), front,
                                   ('billboard_pro', 0, cam_front, (0.0, 0.0, 8.0, 8.0), v3(-2.0, 1.0, 0.0), v3(0.0, 1.0, 0.0), (2.0, 2.0), (1.0, 1.0), 0.0, WHITE),
                                   ('billboard_pro', 1, cam_front, (1.0, 1.0, 3.0, 4.0), v3(2.0, 1.0, 0.0), v3(0.0, 1.0, 0.0), (2.0, -2.5), (0.5, 0.25), 90.0, WHITE),
                                   ('billboard_pro', 0, cam_front, (0.0, 0.0, 8.0, 8.0), v3(0.0, -2.0, 0.5), v3(1.0, 1.0, 0.0), (-2.0, 1.5), (0.0, 0.0), 180.0,
                                    C(255, 255, 255, 128)),
                                   ('billboard_pro', 1, cam_front, (0.0, 0.0, 4.0, 6.0), v3(2.5, -2.0, 0.0), v3(0.0, 1.0, 0.0), (1.0, 1.5), (0.5, 0.75), -60.0, WHITE),
                                   ('end3d',), ('end',)])
    add('billboard-pro-26', 32, 24, [('load', 0, tex_a), ('begin',), ('clear', BLACK), front,
                                     ('billboard_pro', 0, cam_front, (0.0, 0.0, 8.0, 8.0), v3(0.0, 0.0, 0.0), v3(0.0, 1.0, 0.0), (2.0, 2.0), (1.0, 1.0), 26.0, WHITE),
                                     ('end3d',), ('end',)])
    add('instanced-empty', 32, 24, [('begin',), ('clear', C(50, 50, 50)), front,
                                    ('instanced', NONE, RED, 0, ('cube', 2.0, 2.0, 2.0)),
                                    ('mesh', NONE, C(0, 200, 255, 77), 0, IDENTITY, ('empty',)),
                                    ('rl_begin', 4), ('v3f', -2.0, -2.0, 0.0), ('v3f', 2.0, -2.0, 0.0), ('v3f', 0.0, 2.0, 0.0), ('rl_end',),
                                    ('end3d',), ('end',)])
    add('mesh-no-vertices', 32, 24, [('load', 0, tex_a), ('begin',), ('clear', BLACK),
                                     ('mesh', 0, C(255, 0, 0, 90), 0, IDENTITY, custom([1, 1, 0, 1, 9, 0, 9, 1, 0], texcoords=[0, 0, 0, 1, 1, 0], no_vertices=True)),
                                     ('rl_begin', 4), ('tc', 0.25, 0.25), ('v2f', 2.0, 2.0), ('v2f', 2.0, 20.0), ('v2f', 28.0, 2.0), ('rl_end',),
                                     ('end',)])
    add('materials', 16, 12, [('load', 0, tex_a), ('load', 1, tex_b), ('valid',), ('matinfo', NONE, 0), ('matinfo', 0, 0), ('matinfo', 1, 3),
                              ('matinfo', 0, 11), ('unload_mat', 0), ('load', 2, tex_gray), ('info', 2), ('unload_mat', 3), ('info', 1)])

    # Contracts.
    add('mesh-index-range', 16, 12, [('mesh', NONE, WHITE, 0, IDENTITY, custom([1, 1, 0, 1, 9, 0, 9, 1, 0], indices=[0, 1, 3]))])
    add('mesh-unknown-texture', 16, 12, [('load', 0, tex_a), ('mesh', 0, WHITE, 99, IDENTITY, quad)])
    add('model-negative-material', 16, 12, [('model2', NONE, WHITE, RED, 1, -1, IDENTITY, v3(0.0, 0.0, 0.0), 1.0, WHITE, ('cube', 1.0, 1.0, 1.0), ('cube', 1.0, 1.0, 1.0))])
    add('material-map-range', 16, 12, [('matinfo', NONE, 12)])
    add('mesh-in-primitive', 16, 12, [('rl_begin', 4), ('v2f', 1.0, 1.0), ('mesh', NONE, WHITE, 0, IDENTITY, custom([1, 1, 0, 1, 9, 0, 9, 1, 0])),
                                      ('v2f', 1.0, 10.0), ('v2f', 10.0, 1.0), ('rl_end',)], contract=True)

    # Random scenes of custom meshes (indexed or not, texcoords, colors) under an orthographic camera.
    for index in range(6):
        w, h = rng.choice(((32, 24), (40, 30)))
        direction = (rng.uniform(-1, 1), rng.uniform(0.3, 1), rng.uniform(-1, 1))
        norm = sum(c * c for c in direction) ** 0.5
        position = tuple(8.0 * c / norm for c in direction)
        ops = [('load', 0, tp.image(rng.choice((4, 8)), rng.choice((4, 8)), 7, rng.randrange(1000), opaque=rng.random() < 0.5)), ('begin',),
               ('clear', C(rng.randrange(256), rng.randrange(256), rng.randrange(256))),
               mp.camera(position, (rng.uniform(-0.5, 0.5), 0.0, rng.uniform(-0.5, 0.5)), fovy=rng.uniform(4, 9))]
        if rng.random() < 0.5:
            ops.append(('toggle', 'cull', False))
        for _ in range(rng.randint(2, 4)):
            vc = rng.randint(3, 9)
            vertices = [rng.uniform(-2.5, 2.5) for _ in range(3 * vc)]
            texcoords = [rng.uniform(-0.5, 1.5) for _ in range(2 * vc)] if rng.random() < 0.6 else None
            colors = [rng.randrange(256) for _ in range(4 * vc)] if rng.random() < 0.4 else None
            indices = [rng.randrange(vc) for _ in range(3 * rng.randint(1, 4))] if rng.random() < 0.5 else None
            slot = 0 if texcoords is not None and rng.random() < 0.7 else NONE
            color = C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 160)))
            matrix = scale_matrix(rng.uniform(0.5, 1.5), rng.uniform(0.5, 1.5), rng.uniform(0.5, 1.5), rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
            ops.append(('mesh', slot, color, 0, matrix, custom(vertices, texcoords, colors, indices)))
        ops += [('end3d',), ('end',)]
        add(f'md-random-{index}', w, h, ops)
    return out


# -----------------------------------------------------------------------------
# C reference

C_HELPERS = r'''static Material mat(Color c, const Texture2D *t, unsigned int fake)
{
    Material m = LoadMaterialDefault();
    m.maps[MATERIAL_MAP_DIFFUSE].color = c;
    if (t) m.maps[MATERIAL_MAP_DIFFUSE].texture = *t;
    if (fake) m.maps[MATERIAL_MAP_DIFFUSE].texture.id = fake;
    return m;
}
static Mesh custom(int vc, int tc, float *v, float *t, unsigned char *c, unsigned short *ix)
{
    Mesh m = { 0 };
    m.vertexCount = vc; m.triangleCount = tc; m.vertices = v; m.texcoords = t; m.colors = c; m.indices = ix;
    return m;
}
static void valid_note(void)
{
    char s[64];
    snprintf(s, sizeof s, " v%d,%d,%d", (int)IsMaterialValid(LoadMaterialDefault()), (int)IsModelValid(LoadModelFromMesh(GenMeshCube(1, 1, 1))),
             (int)IsModelValid(LoadModelFromMesh(GenMeshPoly(2, 1.0f))));
    note(s);
}
static void material_note(Material m)
{
    note(" M");
    for (int i = 0; i < 12; i++)
    {
        char s[128]; MaterialMap p = m.maps[i];
        snprintf(s, sizeof s, "%u,%d,%d,%d,%d,%02x%02x%02x%02x,%u;", p.texture.id, p.texture.width, p.texture.height, p.texture.mipmaps, p.texture.format,
                 p.color.r, p.color.g, p.color.b, p.color.a, fb(p.value));
        note(s);
    }
}
static void dump(int w, int h, int screen)'''

C_PREFIX = rp.C_PREFIX.replace('static void dump(int w, int h, int screen)', C_HELPERS, 1)
if 'static void valid_note(void)' not in C_PREFIX:
    raise ProbeFailure('model-draw: tools/rlgl_probe.py C_PREFIX changed; update the model draw probe hooks')


def c_scene(scene):
    lines = ['    { Texture2D t[4] = { 0 }; RenderTexture2D r[2] = { 0 }; (void)t; (void)r;', f'    InitWindow({scene["width"]}, {scene["height"]}, "");']
    lines += [c_op(op) for op in scene['ops']]
    lines += [f'    dump({scene["width"]}, {scene["height"]}, {int(scene["screen"])});', '    CloseWindow(); }']
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

MODEL_DRAW_BEND = '''
def wtake.f32(n: Nat, +ws: +List<U32>) -> +List<F32>:
  match n ws:
    case 0n _: Nil{}
    case _ Nil{}: Nil{}
    case 1n+k Con{+w, rest}: Con{FC.float(w), wtake.f32(k, rest)}

def wtake.u32(n: Nat, +ws: +List<U32>) -> +List<U32>:
  match n ws:
    case 0n _: Nil{}
    case _ Nil{}: Nil{}
    case 1n+k Con{+w, rest}: Con{w, wtake.u32(k, rest)}

def wflag(+flags: U32, +bit: U32) -> Bool:
  Bool.not(U32.is_eq((flags .&. bit : U32), 0))

def wsome.f32(on: Bool, +values: +List<F32>) -> Maybe<&2, +List<F32>>:
  match on:
    case True{}: Some{values}
    case False{}: None{}

def wsome.u32(on: Bool, +values: +List<U32>) -> Maybe<&2, +List<U32>>:
  match on:
    case True{}: Some{values}
    case False{}: None{}

# A custom mesh: vertex and triangle counts, flags (1 texcoords, 2 colors,
# 4 indices, 8 no vertices), the vertex words, then the present arrays.
def wcustom(+w: +List<U32>) -> J.Mesh:
  +vc = wu(0n, w)
  +tc = wu(1n, w)
  +flags = wu(2n, w)
  +nv = U32.to_nat((vc * 3 : U32))
  +nt = Bool.pick(Nat, wflag(flags, 1), U32.to_nat((vc * 2 : U32)), 0n)
  +nc = Bool.pick(Nat, wflag(flags, 2), U32.to_nat((vc * 4 : U32)), 0n)
  +a = word.drop(3n, w)
  +b = word.drop(nv, a)
  +c = word.drop(nt, b)
  +d = word.drop(nc, c)
  J.Mesh{vc, tc, wsome.f32(Bool.not(wflag(flags, 8)), wtake.f32(nv, a)), wsome.f32(wflag(flags, 1), wtake.f32(nt, b)), None{}, None{}, None{},
    wsome.u32(wflag(flags, 2), wtake.u32(nc, c)), wsome.u32(wflag(flags, 4), wtake.u32(U32.to_nat((tc * 3 : U32)), d))}

def wmesh.kind(kind: U32, +w: +List<U32>) -> Maybe<J.Mesh>:
  match kind:
    case 1: Some{J.Mesh.gen_cube(wf(0n, w), wf(1n, w), wf(2n, w))}
    case 2: J.Mesh.gen_plane(wf(0n, w), wf(1n, w), wu(2n, w), wu(3n, w))
    case 3: J.Mesh.gen_poly_for(libm(), wu(0n, w), wf(1n, w))
    case 4: Some{wcustom(w)}
    case _: J.Mesh.gen_poly_for(libm(), 2, 1.0)

# A mesh spec: its word count, its kind, its words.
def wmesh(+w: +List<U32>) -> Maybe<J.Mesh>:
  wmesh.kind(wu(1n, w), word.drop(2n, w))

def wmesh.skip(+w: +List<U32>) -> +List<U32>:
  word.drop(U32.to_nat((wu(0n, w) + 1 : U32)), w)

def wmat.info(+info: J.TextureInfo, +fake: U32) -> J.TextureInfo:
  J.TextureInfo{+id, +w, +h, +m, +f} = info
  J.TextureInfo{Bool.pick(U32, U32.is_eq(fake, 0), id, fake), w, h, m, f}

def wmat.build(maps: +List<J.MaterialMap>, +params: +List<F32>, +color: U32, +info: J.TextureInfo) -> J.Material:
  match maps:
    case Con{+first, rest}: J.Material{Con{J.MaterialMap.with_color(J.MaterialMap.with_texture(first, info), color), rest}, params}
    case Nil{}: J.Material{Nil{}, params}

def wmat.from(+m: J.Material, +color: U32, +info: J.TextureInfo) -> J.Material:
  J.Material{+maps, +params} = m
  wmat.build(maps, params, color, info)

# LoadMaterialDefault with the diffuse color and texture struct.
def wmat(+color: U32, +info: J.TextureInfo) -> J.Material:
  wmat.from(J.Material.load_default(), color, info)

def tex.list(t: Maybe<J.Texture>) -> List<J.Texture>:
  match t:
    case None{}: Nil{}
    case Some{x}: Con{x, Nil{}}

def tex.head(ts: List<J.Texture>) -> Maybe<J.Texture>:
  match ts:
    case Nil{}: None{}
    case Con{t, _}: Some{t}

def tex.info.cons(r: J.Texture & J.TextureInfo, rest: List<J.Texture>) -> List<J.Texture> & J.TextureInfo:
  (t, info) = r
  (Con{t, rest}, info)

# The textures and the diffuse struct a material gets: the slot's texture, or
# LoadMaterialDefault's (Texture2D){ 0, 1, 1, 1, 7 }.
def tex.info(ts: List<J.Texture>) -> List<J.Texture> & J.TextureInfo:
  match ts:
    case Nil{}: (Nil{}, J.TextureInfo{0, 1, 1, 1, 7})
    case Con{t, rest}: tex.info.cons(J.Texture.info(t), rest)

def St.use.back(r: J.Frame & List<J.Texture>, +slot: U32, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, ts) = r
  St.put(St{frame, t0, t1, t2, t3, r0, r1, log}, slot, tex.head(ts))

def St.use.apply(s: St, t: Maybe<J.Texture>, +slot: U32, f: J.Frame -> List<J.Texture> -> J.Frame & List<J.Texture>) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.use.back(f(frame, tex.list(t)), slot, t0, t1, t2, t3, r0, r1, log)

def St.use.taken(r: St & Maybe<J.Texture>, +slot: U32, f: J.Frame -> List<J.Texture> -> J.Frame & List<J.Texture>) -> St:
  (s, t) = r
  St.use.apply(s, t, slot, f)

# Runs f on the frame and the slot's texture as a list (empty for slot 255);
# the texture handed back returns to the slot.
def St.use(s: St, +slot: U32, f: J.Frame -> List<J.Texture> -> J.Frame & List<J.Texture>) -> St:
  St.use.taken(St.take(s, slot), slot, f)

def draw.refused(frame: J.Frame, ts: List<J.Texture>) -> J.Frame & List<J.Texture>:
  (J.Frame.refuse(frame), ts)

def draw.mesh.go(mesh: Maybe<J.Mesh>, frame: J.Frame, ts: List<J.Texture>, +mat: J.Material, +m: M.Matrix) -> J.Frame & List<J.Texture>:
  match mesh:
    case None{}: draw.refused(frame, ts)
    case Some{+x}: J.Draw.mesh(frame, ts, x, mat, m)

def draw.mesh.with(frame: J.Frame, r: List<J.Texture> & J.TextureInfo, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  (ts, +info) = r
  draw.mesh.go(wmesh(word.drop(19n, w)), frame, ts, wmat(wu(1n, w), wmat.info(info, wu(2n, w))), wmatrix(word.drop(3n, w)))

def draw.mesh(frame: J.Frame, ts: List<J.Texture>, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  draw.mesh.with(frame, tex.info(ts), w)

def model.of(mesh: Maybe<J.Mesh>, +mat: J.Material) -> Maybe<J.Model>:
  match mesh:
    case None{}: None{}
    case Some{+x}: Some{J.Model{M.Matrix.identity(), [x], [mat], [0]}}

def draw.model.go(kind: U32, frame: J.Frame, ts: List<J.Texture>, +m: J.Model, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  match kind:
    case 401: J.Draw.model(frame, ts, m, wv3(3n, w), wf(6n, w), wu(7n, w))
    case 403: J.Draw.model_wires(frame, ts, m, wv3(3n, w), wf(6n, w), wu(7n, w))
    case 402: J.Draw.model_ex_for(libm(), frame, ts, m, wv3(3n, w), wv3(6n, w), wf(9n, w), wv3(10n, w), wu(13n, w))
    case _: J.Draw.model_wires_ex_for(libm(), frame, ts, m, wv3(3n, w), wv3(6n, w), wf(9n, w), wv3(10n, w), wu(13n, w))

def draw.model.kind(model: Maybe<J.Model>, +kind: U32, frame: J.Frame, ts: List<J.Texture>, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  match model:
    case None{}: draw.refused(frame, ts)
    case Some{+m}: draw.model.go(kind, frame, ts, m, w)

def draw.model.with(+kind: U32, frame: J.Frame, r: List<J.Texture> & J.TextureInfo, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  (ts, +info) = r
  +at = Bool.pick(Nat, U32.is_eq(kind, 401) || U32.is_eq(kind, 403), 8n, 14n)
  draw.model.kind(model.of(wmesh(word.drop(at, w)), wmat(wu(1n, w), wmat.info(info, wu(2n, w)))), kind, frame, ts, w)

def draw.model(+kind: U32, frame: J.Frame, ts: List<J.Texture>, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  draw.model.with(kind, frame, tex.info(ts), w)

def model2.of(a: Maybe<J.Mesh>, b: Maybe<J.Mesh>, +transform: M.Matrix, +ma: J.Material, +mb: J.Material, +mesh_id: U32, +material_id: U32) -> Maybe<J.Model>:
  match a b:
    case Some{+x} Some{+y}: J.Model.set_mesh_material(J.Model{transform, [x, y], [ma, mb], [0, 0]}, mesh_id, material_id)
    case _ _: None{}

def draw.model2.with(frame: J.Frame, r: List<J.Texture> & J.TextureInfo, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  (ts, +info) = r
  +meshes = word.drop(26n, w)
  draw.model.kind(model2.of(wmesh(meshes), wmesh(wmesh.skip(meshes)), wmatrix(word.drop(5n, w)), wmat(wu(1n, w), info),
    wmat(wu(2n, w), J.TextureInfo{0, 1, 1, 1, 7}), wu(3n, w), wu(4n, w)), 401, frame, ts, Con{0, Con{0, Con{0, word.drop(21n, w)}}})

def draw.model2(frame: J.Frame, ts: List<J.Texture>, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  draw.model2.with(frame, tex.info(ts), w)

def draw.instanced.go(mesh: Maybe<J.Mesh>, frame: J.Frame, ts: List<J.Texture>, +mat: J.Material) -> J.Frame & List<J.Texture>:
  match mesh:
    case None{}: draw.refused(frame, ts)
    case Some{+x}: J.Draw.mesh_instanced(frame, ts, x, mat, [M.Matrix.identity(), M.Matrix.translate(1.0, 2.0, 3.0)])

def draw.instanced.with(frame: J.Frame, r: List<J.Texture> & J.TextureInfo, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  (ts, +info) = r
  draw.instanced.go(wmesh(word.drop(3n, w)), frame, ts, wmat(wu(1n, w), wmat.info(info, wu(2n, w))))

def draw.instanced(frame: J.Frame, ts: List<J.Texture>, +w: +List<U32>) -> J.Frame & List<J.Texture>:
  draw.instanced.with(frame, tex.info(ts), w)

def mat.set(+m: J.Material, +k: U32, +info: J.TextureInfo) -> J.Material:
  Maybe.default(&1, J.Material, J.Material.set_texture(m, k, info), m)

def unload.mat.with(frame: J.Frame, r: List<J.Texture> & J.TextureInfo) -> J.Frame & List<J.Texture>:
  (ts, +info) = r
  J.Material.unload(frame, ts, mat.set(mat.set(mat.set(J.Material.load_default(), 0, info), 1, info), 4, info))

def unload.mat(frame: J.Frame, ts: List<J.Texture>) -> J.Frame & List<J.Texture>:
  unload.mat.with(frame, tex.info(ts))

def draw.billboard(kind: U32, +w: +List<U32>, frame: J.Frame, tex: J.Texture) -> J.Frame & J.Texture:
  match kind:
    case 406: J.Draw.billboard(frame, wcamera(word.drop(1n, w)), tex, wv3(12n, w), wf(15n, w), wu(16n, w))
    case 407: J.Draw.billboard_rec(frame, wcamera(word.drop(1n, w)), tex, wrect(12n, w), wv3(16n, w), wv(19n, w), wu(21n, w))
    case _: J.Draw.billboard_pro_for(libm(), frame, wcamera(word.drop(1n, w)), tex, wrect(12n, w), wv3(16n, w), wv3(19n, w), wv(22n, w), wv(24n, w),
      wf(26n, w), wu(27n, w))

def flag.digit(b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"

def valid.text() -> String:
  " v" ++ flag.digit(J.Material.is_valid(J.Material.load_default())) ++ "," ++ flag.digit(J.Model.is_valid(J.Model.from_mesh(J.Mesh.gen_cube(1.0, 1.0, 1.0))))
    ++ "," ++ flag.digit(J.Model.is_valid(J.Model.from_mesh(Maybe.default(&1, J.Mesh, J.Mesh.gen_poly_for(libm(), 2, 1.0), J.Mesh.gen_cube(1.0, 1.0, 1.0)))))

def info.fields(+info: J.TextureInfo) -> String:
  J.TextureInfo{+id, +w, +h, +m, +f} = info
  U32.show(id) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(m) ++ "," ++ U32.show(f)

def map.text(+map: J.MaterialMap) -> String:
  J.MaterialMap{+info, +color, +value} = map
  info.fields(info) ++ "," ++ hex.word(color, "") ++ "," ++ bits.f(value) ++ ";"

def maps.text(maps: +List<J.MaterialMap>) -> String:
  match maps:
    case Nil{}: ""
    case Con{+map, rest}: map.text(map) ++ maps.text(rest)

def material.text(+m: J.Material) -> String:
  J.Material{+maps, _} = m
  " M" ++ maps.text(maps)

def matinfo.note(m: Maybe<J.Material>, s: St) -> St:
  match m:
    case None{}: St.frame(s, f => J.Frame.refuse(f))
    case Some{+x}: St.note(s, material.text(x))

def tex.maybe.some(r: J.Texture & J.TextureInfo) -> Maybe<J.Texture> & J.TextureInfo:
  (x, info) = r
  (Some{x}, info)

def tex.maybe(t: Maybe<J.Texture>) -> Maybe<J.Texture> & J.TextureInfo:
  match t:
    case None{}: (None{}, J.TextureInfo{0, 0, 0, 0, 0})
    case Some{x}: tex.maybe.some(J.Texture.info(x))

def matinfo.info(s: St, +slot: U32, +map_type: U32, r: Maybe<J.Texture> & J.TextureInfo) -> St:
  (t, +info) = r
  matinfo.note(J.Material.set_texture(J.Material.load_default(), map_type, info), St.put(s, slot, t))

def matinfo.taken(r: St & Maybe<J.Texture>, +slot: U32, +map_type: U32) -> St:
  (s, t) = r
  matinfo.info(s, slot, map_type, tex.maybe(t))

# Model, mesh and billboard operations (kinds 400..).
def mdstep.mine(kind: U32, +code: U32, +w: +List<U32>, s: St) -> St:
  match kind:
    case 400: St.use(s, wu(0n, w), fr => ts => draw.mesh(fr, ts, w))
    case 405: St.use(s, wu(0n, w), fr => ts => draw.model2(fr, ts, w))
    case 406: St.tex(s, wu(0n, w), fr => tx => draw.billboard(406, w, fr, tx))
    case 407: St.tex(s, wu(0n, w), fr => tx => draw.billboard(407, w, fr, tx))
    case 408: St.tex(s, wu(0n, w), fr => tx => draw.billboard(408, w, fr, tx))
    case 409: St.use(s, wu(0n, w), fr => ts => draw.instanced(fr, ts, w))
    case 410: St.use(s, wu(0n, w), fr => ts => unload.mat(fr, ts))
    case 411: St.note(s, valid.text())
    case 412: matinfo.taken(St.take(s, wu(0n, w)), wu(0n, w), wu(1n, w))
    case _: St.use(s, wu(0n, w), fr => ts => draw.model(code, fr, ts, w))

def mdstep.select(mine: Bool, +kind: U32, +w: +List<U32>, s: St) -> St:
  match mine:
    case True{}: mdstep.mine(kind, kind, w, s)
    case False{}: mstep(Op{kind, w}, s)

def mdstep(op: Op, s: St) -> St:
  Op{+kind, +w} = op
  mdstep.select((kind >= 400 : U32), kind, w, s)

def mdexec(ops: +List<Op>, s: St) -> St:
  match ops:
    case Nil{}: s
    case Con{op, rest}: mdexec(rest, mdstep(op, s))

def St.mdrun(ops: +List<Op>, +screen: Bool, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: St.finish(screen, mdexec(ops, St.new(f)))
'''


def b_op(op):
    kind, words = op_words(op)
    return f'Op{{{kind}, [{", ".join(str(w) for w in words)}]}}'


def b_scene(index, scene):
    return f'def scene.{index}() -> +List<Op>:\n  [' + ',\n    '.join(b_op(op) for op in scene['ops']) + ']'


def render(libm):
    def build(selected, gpu):
        body = [rp.PROGRAM, f'def libm() -> M.Libm:\n  M.{libm}{{}}', rp.NEW_BEND, mp.MODELS_BEND, MODEL_DRAW_BEND]
        prints = []
        for index, item in selected:
            body.append(b_scene(index, item))
            prints.append(f'    IO.print(St.mdrun(scene.{index}(), False{{}}, J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('model-draw', args, raylib_options=fp.OPTIONS)
    libm = gradient_reference()
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'model-draw: the reference build contains fused multiply-adds: {fused}')
    items = scenes()
    native_items = [s for s in items if not refused(s, libm)]
    contracts = [s for s in items if s not in native_items]
    if len(native_items) < 18 or len(contracts) < 5:
        raise ProbeFailure(f'model-draw: {len(native_items)} compared and {len(contracts)} refused scenes; the corpus lost coverage')
    source_text = C_PREFIX + '\n'.join(c_scene(s) for s in native_items) + '\n    return 0;\n}\n'
    output = probe.native(source_text, 'reference', extra_flags=('-ffp-contract=off',)).splitlines()
    frames = [line for line in output if line.startswith('F ')]
    if len(frames) != len(native_items):
        raise ProbeFailure(f'model-draw: reference printed {len(frames)} frames for {len(native_items)} scenes')
    expected_by_id = {}
    for scene, line in zip(native_items, frames):
        parts = line[2:].split(' ')
        expected_by_id[scene['id']] = parts[0] + ''.join(' ' + p for p in parts[1:] if p)
    for scene in contracts:
        expected_by_id[scene['id']] = 'null'
    expected = [expected_by_id[s['id']] for s in items]
    actions = list(enumerate(items))
    lanes = probe.candidates(render(libm), actions, batch=6, parse=lambda text, selected: [line for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'scene {items[i]["id"]}')
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), libm=libm,
                 operations=sum(len(s['ops']) for s in items), fused_free_objects=len(fused), refused=[s['id'] for s in contracts],
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
