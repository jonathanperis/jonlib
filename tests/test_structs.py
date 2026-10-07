"""Jonlib/Jonmath value structs keep the pinned headers' field names, order and types."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Catalog struct ID -> (Bend file, Bend type). Every header's copy of a shared
# struct maps to the same Bend type.
STRUCTS = {
    **{f'{header}:type:{name}': ('jonmath.bend', name) for header in ('raylib', 'raymath') for name in ('Vector2', 'Vector3', 'Vector4', 'Matrix')},
    'rlgl:type:Matrix': ('jonmath.bend', 'Matrix'),
    'rcamera:type:Vector2': ('jonmath.bend', 'Vector2'),
    'rcamera:type:Vector3': ('jonmath.bend', 'Vector3'),
    'rcamera:type:Matrix': ('jonmath.bend', 'Matrix'),
    'rgestures:type:Vector2': ('jonmath.bend', 'Vector2'),
    'raylib:type:Rectangle': ('jonlib.bend', 'Rectangle'),
    'raylib:type:BoundingBox': ('jonlib.bend', 'BoundingBox'),
    'raylib:type:Ray': ('jonlib.bend', 'Ray'),
    'raylib:type:RayCollision': ('jonlib.bend', 'RayCollision'),
    'raylib:type:Camera3D': ('jonlib.bend', 'Camera3D'),
    'rcamera:type:Camera3D': ('jonlib.bend', 'Camera3D'),
    'raylib:type:Camera2D': ('jonlib.bend', 'Camera2D'),
    'raylib:type:Transform': ('jonlib.bend', 'Transform'),
}
C_TYPES = {'float': 'F32', 'bool': 'Bool', 'Vector2': 'Vector2', 'Vector3': 'Vector3', 'Vector4': 'Vector4', 'Quaternion': 'Vector4'}
# C int fields holding an enum value are U32, like the enum constants.
ENUM_FIELDS = {('Camera3D', 'projection')}


def c_fields(members):
    fields = []
    for member in members:
        ctype, names = member.split(' ', 1)
        fields += [(name.strip(), ctype) for name in names.split(',')]
    return fields


def bend_fields(source, name):
    match = re.search(r'^type ' + re.escape(name) + r' is Data:\n  ' + re.escape(name) + r'\{([^}]*)\}', source, re.M)
    if not match:
        raise AssertionError(f'type {name} not found')
    return [(field.split(':')[0].strip(), field.split(':')[1].strip().removeprefix('M.')) for field in match.group(1).split(',')]


class StructLayout(unittest.TestCase):
    def test_fields_match_headers(self):
        entries = json.loads((ROOT / 'api/reference.json').read_text())['entries']
        rows = {row['id']: row for row in (entries if isinstance(entries, list) else entries.values())}
        sources = {name: (ROOT / name).read_text() for name in ('jonlib.bend', 'jonmath.bend')}
        for identifier, (path, name) in STRUCTS.items():
            with self.subTest(identifier):
                members = rows[identifier]['variants'][0]['members']
                expected = [(field, 'U32' if (name, field) in ENUM_FIELDS else C_TYPES[ctype]) for field, ctype in c_fields(members)]
                self.assertEqual(bend_fields(sources[path], name), expected)

    def test_progress_maps_every_checked_struct(self):
        progress = json.loads((ROOT / 'api/progress.json').read_text())['entries']
        for identifier in STRUCTS:
            with self.subTest(identifier):
                self.assertIn(identifier, progress)
                self.assertIn('tests/test_structs.py', progress[identifier]['evidence'])


if __name__ == '__main__':
    unittest.main()
