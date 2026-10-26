"""The uncontracted ray-exceptional column is the pinned rmodels source."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ray_exceptional_probe as probe


class RayExceptionalOracleTests(unittest.TestCase):
    def test_the_excerpt_is_only_the_pinned_ray_queries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'src'
            source.mkdir()
            (source / 'rmodels.c').write_text(
                'preamble\n'
                'RayCollision GetRayCollisionSphere(Ray ray, Vector3 center, float radius){return (RayCollision){0};}\n'
                '//----------------------------------------------------------------------------------\n'
                'after\n')
            text = probe.uncontracted_excerpt(root)
        self.assertIn('GetRayCollisionSphere', text)
        self.assertIn('Unaltered ray collision functions', text)
        self.assertNotIn('preamble', text)
        self.assertNotIn('after', text)

    def test_each_query_keeps_the_pinned_call_and_the_fused_shape(self):
        sphere = probe.native_case('sphere', (0,) * 10)
        self.assertIn('GetRayCollisionSphere', sphere)
        self.assertIn('sphere_fused', sphere)
        triangle = probe.native_case('triangle', (0,) * 15)
        self.assertIn('GetRayCollisionTriangle', triangle)
        self.assertIn('triangle_fused', triangle)
