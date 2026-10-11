#!/usr/bin/env python3
"""Compare Jonlib's LoadModel of .glb files (LoadGLTF) with the pinned raylib.

The probe writes .glb files under its work directory and loads each one, and
the two models the examples use (plane.glb and old_car_new.glb, read in place
from the pinned raylib checkout), natively (InitWindow on PLATFORM=Memory,
then LoadModel) and with Jonlib (Model.load_for). Each row has the mesh and
material counts, IsModelValid, every mesh's vertex and triangle counts, mesh
material and every vertex, normal, tangent, texcoord and second texcoord
word, every index, and every material map.

The files cover: a bare triangle; indices of 8, 16 and 32 bits (a value above
65535 is kept as its low 16 bits); node translations, rotations and scales
(decimals of up to 17 digits, read as cgltf reads them, (float)atof), a node
matrix, a three-level hierarchy, a non-uniform scale (the normals go through
the inverse transpose), one mesh under two nodes, nodes without a mesh;
tangents and two texcoord sets, a third set and a custom attribute (both
ignored); interleaved views (byteStride), accessor and view offsets, offsets
that are not multiples of the component size (LOAD_ATTRIBUTE divides them);
several primitives, a line primitive (skipped), materials with and without a
base color factor or pbrMetallicRoughness, primitives without a material; a
file without nodes; a missing file.

The reference is the raylib built with -ffp-contract=off (the loader's
arithmetic is uncontracted). Contracts (Jonlib must answer null, and the
reference is not run): a skin, a texture, a base color texture, a COLOR_0
attribute, a sparse accessor, an accessor without a buffer view, short
positions, a buffer with a uri, a required extension, JSON that is not well
formed, another magic or version, a truncated file, an accessor reaching past
the buffer, a node with two parents, a factor outside 0..1, a number of 20
digits, and glTF as text (.gltf). CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import struct

import frame_probe as fp
import obj_probe as op
import probekit
from probekit import ProbeFailure


def glb(document, binary=b'', *, magic=b'glTF', version=2, text=None):
    """A binary glTF file: the JSON chunk (padded with spaces) and the BIN chunk (padded with zeros)."""
    body = (text if text is not None else json.dumps(document, separators=(',', ':'))).encode()
    body += b' ' * (-len(body) % 4)
    binary += b'\x00' * (-len(binary) % 4)
    size = 12 + 8 + len(body) + 8 + len(binary)
    return magic + struct.pack('<II', version, size) + struct.pack('<I', len(body)) + b'JSON' + body + struct.pack('<I', len(binary)) + b'BIN\x00' + binary


class Builder:
    """Accumulates buffer data, views and accessors."""

    def __init__(self):
        self.data, self.views, self.accessors = b'', [], []

    def view(self, payload, stride=None, pad=0):
        self.data += b'\x00' * pad
        entry = dict(buffer=0, byteOffset=len(self.data), byteLength=len(payload))
        if stride:
            entry['byteStride'] = stride
        self.data += payload
        self.data += b'\x00' * (-len(self.data) % 4)
        self.views.append(entry)
        return len(self.views) - 1

    def accessor(self, view, component, kind, count, offset=None, **extra):
        entry = dict(bufferView=view, componentType=component, count=count, type=kind, **extra)
        if offset is not None:
            entry['byteOffset'] = offset
        self.accessors.append(entry)
        return len(self.accessors) - 1

    def floats(self, values, kind):
        size = dict(VEC2=2, VEC3=3, VEC4=4)[kind]
        return self.accessor(self.view(struct.pack(f'<{len(values)}f', *values)), 5126, kind, len(values) // size)

    def indices(self, values, component=5123):
        code = {5121: 'B', 5123: 'H', 5125: 'I'}[component]
        return self.accessor(self.view(struct.pack(f'<{len(values)}{code}', *values)), component, 'SCALAR', len(values))

    def document(self, **parts):
        return dict(asset=dict(version='2.0'), accessors=self.accessors, bufferViews=self.views, buffers=[dict(byteLength=len(self.data))], **parts)


QUAD = [-1.0, 0.0, 1.0, 1.0, 0.0, 1.0, -1.0, 0.0, -1.0, 1.0, 0.0, -1.0]
TRIANGLE = [0.0, 0.0, 0.0, 1.5, 0.0, 0.0, 0.0, 2.25, -0.5]
UP = [0.0, 1.0, 0.0] * 4
SLANTED = [0.6, 0.8, 0.0, 0.0, 0.6, 0.8, 0.8, 0.0, 0.6, 0.0, 1.0, 0.0]
TANGENTS = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.6, 0.0, 0.8, 1.0, 1.0, 0.0, 0.0, -1.0]
UVS = [0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0]
UVS2 = [0.25, 0.75, 0.5, 0.125, 0.0, 0.0, 1.0, 0.875]


def quad(builder, **attributes):
    """A quad primitive with positions and indices, plus the given attribute accessors."""
    return dict(attributes=dict(POSITION=builder.floats(QUAD, 'VEC3'), **attributes), indices=builder.indices([0, 1, 3, 0, 3, 2]))


def simple(nodes, materials=None, primitives=None, **extra):
    builder = Builder()
    prims = primitives(builder) if primitives else [quad(builder, NORMAL=builder.floats(SLANTED, 'VEC3'))]
    parts = dict(nodes=nodes, meshes=[dict(primitives=prims)], **extra)
    if materials is not None:
        parts['materials'] = materials
    return glb(builder.document(**parts), builder.data)


def raw(text):
    """A JSON number written as given (json.dumps keeps a float's repr; these are checked decimals)."""
    return json.loads(text)


def cases(work, raylib):
    out, files = [], {}

    def add(name, data, contract=False):
        path = work / f'{name}.glb'
        files[path] = data
        out.append(dict(id=name, kind='model', path=str(path), contract=contract))

    models = raylib / 'examples/shaders/resources/models'
    for name in ('plane', 'old_car_new'):
        out.append(dict(id=name, kind='model', path=str(models / f'{name}.glb'), contract=False))
    out.append(dict(id='missing', kind='model', path=str(work / 'missing.glb'), contract=False))

    b = Builder()
    add('triangle', glb(b.document(nodes=[dict(mesh=0)], meshes=[dict(primitives=[dict(attributes=dict(POSITION=b.floats(TRIANGLE, 'VEC3')))])]), b.data))
    for component, values in ((5121, [0, 1, 3, 0, 3, 2]), (5123, [0, 1, 3, 0, 3, 2]), (5125, [0, 1, 3, 65536, 65539, 131074])):
        b = Builder()
        prim = dict(attributes=dict(POSITION=b.floats(QUAD, 'VEC3')), indices=b.indices(values, component))
        add(f'indices-{component}', glb(b.document(nodes=[dict(mesh=0)], meshes=[dict(primitives=[prim])]), b.data))
    add('translation', simple([dict(mesh=0, translation=[1, raw('-0.12091026455163956'), raw('2.5')])]))
    add('scale', simple([dict(mesh=0, scale=[raw('0.02540000155568123'), 2, raw('0.5')])]))
    add('rotation', simple([dict(mesh=0, rotation=[raw('0.7071067690849304'), 0, 0, raw('0.7071067690849304')])]))
    add('rotation-general', simple([dict(mesh=0, rotation=[raw('0.18257418274879456'), raw('0.3651483654975891'), raw('0.547722578048706'), raw('0.7302967309951782')],
                                         scale=[raw('1.5'), raw('0.75'), 3], translation=[raw('0.1'), raw('0.2'), raw('-0.3')])]))
    add('matrix', simple([dict(mesh=0, matrix=[1, 0, 0, 0, 0, raw('0.5'), raw('0.25'), 0, 0, raw('-0.25'), 2, 0, 3, 4, 5, 1])]))
    add('matrix-and-trs', simple([dict(mesh=0, matrix=[2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 1, 1, 1, 1], translation=[9, 9, 9])]))
    add('hierarchy', simple([dict(children=[1], translation=[1, 2, 3], scale=[2, 2, 2]),
                             dict(children=[2], rotation=[0, raw('0.3826834261417389'), 0, raw('0.9238795042037964')], translation=[raw('0.5'), 0, 0]),
                             dict(mesh=0, scale=[1, raw('0.5'), 1], translation=[0, raw('0.25'), 0])]))
    add('two-nodes', simple([dict(mesh=0, translation=[5, 0, 0]), dict(name='empty'), dict(mesh=0, scale=[3, 3, 3])]))
    add('child-first', simple([dict(mesh=0, translation=[0, 1, 0]), dict(children=[0], scale=[2, 3, 4])]))

    def rich(b):
        return [quad(b, NORMAL=b.floats(UP, 'VEC3'), TANGENT=b.floats(TANGENTS, 'VEC4'), TEXCOORD_0=b.floats(UVS, 'VEC2'), TEXCOORD_1=b.floats(UVS2, 'VEC2'),
                     TEXCOORD_2=b.floats(UVS, 'VEC2'), _CUSTOM=b.floats(UVS, 'VEC2'))]
    add('attributes', simple([dict(mesh=0, scale=[2, 1, raw('0.5')], translation=[0, 1, 0])], primitives=rich))

    def interleaved(b):
        rows = b''.join(struct.pack('<3f3f2f', *QUAD[3 * i:3 * i + 3], *SLANTED[3 * i:3 * i + 3], *UVS[2 * i:2 * i + 2]) for i in range(4))
        view = b.view(rows, stride=32)
        return [dict(attributes=dict(POSITION=b.accessor(view, 5126, 'VEC3', 4), NORMAL=b.accessor(view, 5126, 'VEC3', 4, offset=12),
                                     TEXCOORD_0=b.accessor(view, 5126, 'VEC2', 4, offset=24)), indices=b.indices([0, 1, 3, 0, 3, 2]))]
    add('interleaved', simple([dict(mesh=0)], primitives=interleaved))

    def offsets(b):
        view = b.view(struct.pack('<2f', 9.0, 8.0) + struct.pack('<12f', *QUAD), pad=4)
        odd = b.view(b'\x07\x07' + struct.pack('<6H', 0, 1, 3, 0, 3, 2) + b'\x09\x09', pad=6)
        return [dict(attributes=dict(POSITION=b.accessor(view, 5126, 'VEC3', 4, offset=8)), indices=b.accessor(odd, 5123, 'SCALAR', 6, offset=2)),
                dict(attributes=dict(POSITION=b.accessor(view, 5126, 'VEC3', 4, offset=10)), indices=b.accessor(odd, 5123, 'SCALAR', 6, offset=3))]
    add('offsets', simple([dict(mesh=0)], primitives=offsets))

    def several(b):
        return [dict(quad(b), material=1), dict(attributes=dict(POSITION=b.floats(TRIANGLE, 'VEC3')), mode=1), dict(attributes=dict(POSITION=b.floats(TRIANGLE, 'VEC3')), material=0),
                quad(b), dict(attributes=dict(POSITION=b.floats(TRIANGLE, 'VEC3')), mode=4, material=2)]
    materials = [dict(pbrMetallicRoughness=dict(baseColorFactor=[raw('0.800000011920929'), raw('0.800000011920929'), raw('0.800000011920929'), 1], metallicFactor=0, roughnessFactor=raw('0.5'))),
                 dict(name='plain'), dict(pbrMetallicRoughness=dict(baseColorFactor=[raw('0.2'), raw('0.999'), 0, raw('0.5')])), dict(pbrMetallicRoughness=dict(metallicFactor=1))]
    add('materials', simple([dict(mesh=0)], materials=materials, primitives=several))
    b = Builder()
    add('no-nodes', glb(b.document(meshes=[dict(primitives=[quad(b)])]), b.data))
    add('spaced-json', glb(None, text='{ "asset" : { "version" : "2.0" } ,\n\t"nodes" : [ ] , "buffers" : [ { "byteLength" : 0 } ] }'))

    # Contracts.
    add('skin', simple([dict(mesh=0)], skins=[dict(joints=[0])]), contract=True)
    add('texture', simple([dict(mesh=0)], textures=[dict(source=0)]), contract=True)
    add('image', simple([dict(mesh=0)], images=[dict(uri='a.png')]), contract=True)
    add('base-color-texture', simple([dict(mesh=0)], materials=[dict(pbrMetallicRoughness=dict(baseColorTexture=dict(index=0)))]), contract=True)
    add('color-attribute', simple([dict(mesh=0)], primitives=lambda b: [quad(b, COLOR_0=b.floats(TANGENTS, 'VEC4'))]), contract=True)
    add('joints-attribute', simple([dict(mesh=0)], primitives=lambda b: [quad(b, JOINTS_0=b.floats(TANGENTS, 'VEC4'))]), contract=True)

    def sparse(b):
        prim = quad(b)
        b.accessors[prim['attributes']['POSITION']]['sparse'] = dict(count=1, indices=dict(bufferView=0, componentType=5123), values=dict(bufferView=0))
        return [prim]
    add('sparse', simple([dict(mesh=0)], primitives=sparse), contract=True)

    def viewless(b):
        prim = quad(b)
        del b.accessors[prim['attributes']['POSITION']]['bufferView']
        return [prim]
    add('no-buffer-view', simple([dict(mesh=0)], primitives=viewless), contract=True)

    def shorts(b):
        view = b.view(struct.pack('<12h', *[int(v) for v in QUAD]))
        return [dict(attributes=dict(POSITION=b.accessor(view, 5122, 'VEC3', 4)))]
    add('short-positions', simple([dict(mesh=0)], primitives=shorts), contract=True)

    def past(b):
        prim = quad(b)
        b.accessors[prim['attributes']['POSITION']]['count'] = 400
        return [prim]
    add('past-the-buffer', simple([dict(mesh=0)], primitives=past), contract=True)
    b = Builder()
    document = b.document(nodes=[dict(mesh=0)], meshes=[dict(primitives=[quad(b)])])
    document['buffers'][0]['uri'] = 'data.bin'
    add('buffer-uri', glb(document, b.data), contract=True)
    add('required-extension', simple([dict(mesh=0)], extensionsRequired=['KHR_draco_mesh_compression']), contract=True)
    add('two-parents', simple([dict(children=[2]), dict(children=[2]), dict(mesh=0)]), contract=True)
    add('factor-above-one', simple([dict(mesh=0)], materials=[dict(pbrMetallicRoughness=dict(baseColorFactor=[2, 0, 0, 1]))]), contract=True)
    add('long-number', glb(None, text='{"asset":{"version":"2.0"},"nodes":[{"mesh":0,"translation":[0.12345678901234567890,0,0]}],"meshes":[{"primitives":[]}],"buffers":[{"byteLength":0}]}'),
        contract=True)
    add('bad-json', glb(None, text='{"asset":{"version":"2.0"},"nodes":[,]}'), contract=True)
    add('bad-magic', glb(dict(asset=dict(version='2.0')), magic=b'glTG'), contract=True)
    add('version-1', glb(dict(asset=dict(version='1.0')), version=1), contract=True)
    whole = simple([dict(mesh=0)])
    add('truncated', whole[:-8], contract=True)
    add('short-header', whole[:20], contract=True)
    text_path = work / 'text.gltf'
    files[text_path] = b'{"asset":{"version":"2.0"}}'
    out.append(dict(id='gltf-text', kind='model', path=str(text_path), contract=True))
    return out, files


C_PREFIX = op.C_PREFIX.replace(
    '''        words("v", e->vertices, e->vertexCount*3); words("n", e->normals, e->vertexCount*3); words("t", e->texcoords, e->vertexCount*2);
        printf(" c%d", e->colors != NULL);
''', '''        words("v", e->vertices, e->vertexCount*3); words("n", e->normals, e->vertexCount*3); words("t", e->texcoords, e->vertexCount*2);
        printf(" c%d", e->colors != NULL);
        words("g", e->tangents, e->vertexCount*4); words("u", e->texcoords2, e->vertexCount*2);
        printf(" i");
        if (!e->indices) printf("-");
        else for (int k = 0; k < e->triangleCount*3; k++) printf("%04x", e->indices[k]);
''')

PROGRAM = op.PROGRAM.replace(
    '''def mesh.text(+mesh: J.Mesh, +material: U32) -> String:
  J.Mesh{+vc, +tc, +vs, +ts, _, +ns, _, +cs, _} = mesh
  " m" ++ U32.show(vc) ++ "," ++ U32.show(tc) ++ "," ++ U32.show(material) ++ words("v", vs) ++ words("n", ns) ++ words("t", ts) ++ colors.flag(cs)
''', '''def hex.shorts(xs: +List<U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+x, rest}: hex.shorts(rest, acc ++ SCon{hex.digit(((x >> 12n) .&. 15 : U32)), SCon{hex.digit(((x >> 8n) .&. 15 : U32)), SCon{hex.digit(((x >> 4n) .&. 15 : U32)), SCon{hex.digit((x .&. 15 : U32)), SNil{}}}}})

def indices.text(xs: Maybe<&2, +List<U32>>) -> String:
  match xs:
    case None{}: " i-"
    case Some{+v}: " i" ++ hex.shorts(v, "")

def mesh.text(+mesh: J.Mesh, +material: U32) -> String:
  J.Mesh{+vc, +tc, +vs, +ts, +t2, +ns, +gs, +cs, +ix} = mesh
  " m" ++ U32.show(vc) ++ "," ++ U32.show(tc) ++ "," ++ U32.show(material) ++ words("v", vs) ++ words("n", ns) ++ words("t", ts) ++ colors.flag(cs)
    ++ words("g", gs) ++ words("u", t2) ++ indices.text(ix)
''')
assert C_PREFIX != op.C_PREFIX and PROGRAM != op.PROGRAM


def render(selected, gpu):
    body = [PROGRAM.replace('import ../../src/frame.bend as FC\n', 'import ../../src/frame.bend as FC\n\ndef arith() -> M.Contraction:\n  M.Uncontracted{}\n')]
    steps = [f'    s{index} : String <- run.model(J.Frame.init_window(16, 16), {json.dumps(case["path"])})\n    IO.print(s{index})' for index, (_, case) in enumerate(selected)]
    body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(steps) + '\n')
    return '\n\n'.join(body)


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('gltf', args, raylib_options=fp.OPTIONS)
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'gltf: the uncontracted reference build contains fused multiply-adds: {fused}')
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    items, files = cases(work, args.raylib_source.resolve())
    for path, data in files.items():
        path.write_bytes(data)
    native = [c for c in items if not c['contract']]
    contracts = [c for c in items if c['contract']]
    if len(native) < 20 or len(contracts) < 20:
        raise ProbeFailure(f'gltf: {len(native)} compared and {len(contracts)} refused cases; the corpus lost coverage')
    source = C_PREFIX + '\n'.join(op.c_case(c) for c in native) + '\n    return 0;\n}\n'
    output = [line for line in probe.native(source, 'reference').splitlines() if line[:1] == 'n']
    if len(output) != len(native):
        raise ProbeFailure(f'gltf: reference printed {len(output)} lines for {len(native)} cases')
    expected_by_id = {c['id']: line.rstrip() for c, line in zip(native, output)}
    if expected_by_id['plane'].count(' m') != 1 or expected_by_id['old_car_new'].count(' m') != 2 or expected_by_id['missing'][:2] != 'n0':
        raise ProbeFailure('gltf: the reference did not load the examples\' models as expected')
    for c in contracts:
        expected_by_id[c['id']] = 'null'
    expected = [expected_by_id[c['id']] for c in items]
    lanes = probe.candidates(render, list(enumerate(items)), batch=8, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts))


if __name__ == '__main__':
    main()
