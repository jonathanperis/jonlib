import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import frame_probe as fp
import rlgl_probe as rp
from probekit import ProbeFailure


class ShapesProbeRuleTests(unittest.TestCase):
    """The raylib 6.2 rshapes.c rules the frame and rlgl probes predict refusals with."""

    def test_arcs_limited_to_one_turn(self):
        self.assertEqual(fp.arc_order(0.0, 400.0), (0.0, 360.0))
        self.assertEqual(fp.arc_order(300.0, -90.0), (-90.0, 270.0))
        self.assertEqual(fp.arc_order(10.0, 100.0), (10.0, 100.0))
        # A whole turn of 12 segments: 30 degrees a step, from the ordered start.
        self.assertEqual(fp.sector_plan(-30.0, 400.0, 12.0), (-30.0, 30.0, 12))
        self.assertEqual(rp.arc_segments(-30.0, 400.0, 12.0, 'AppleLibm'), (-30.0, 330.0, 12))

    def test_no_positive_radius_draws_nothing(self):
        for libm in ('AppleLibm', 'Glibc239Libm', 'Glibc241Libm'):
            self.assertFalse(fp.refused(('sector', 3.0, 9.0, -2.0, 45.0, 315.0, 9.0, 0), libm))
            self.assertFalse(fp.refused(('sector_lines', 3.0, 9.0, 0.0, 13.0, 103.0, 1.0, 0), libm))
            self.assertFalse(fp.refused(('ring', 9.0, 7.0, -1.0, -2.0, 0.0, 90.0, 3.0, 0), libm))
            self.assertFalse(rp.op_refused(('ring_lines', 25.0, 6.0, -2.0, -1.0, 0.0, 90.0, 3.0, 0), libm))
            self.assertFalse(rp.op_refused(('sector_ex', 30.0, 8.0, 0.0, 0.0, 90.0, 4.0, 1.0, 0), libm))
            self.assertFalse(rp.op_refused(('ring_ex', 5.0, 5.0, -2.0, -1.0, 0.0, 90.0, 4.0, 1.0, 0), libm))

    def test_new_frame_shapes(self):
        self.assertEqual(fp.trig_arguments(('tri_lines_ex', 1.0, 1.0, 1.0, 5.0, 5.0, 5.0, 1.0, 0)), [])
        self.assertEqual(fp.trig_arguments(('ellipse_lines_ex', 5.0, 5.0, 3.0, 2.0, 1.0, 0)), fp.circle_args())
        # DrawCircleLinesEx is DrawRing(radius - thick, radius, 0, 360, 36): 10-degree steps.
        self.assertTrue(all(fp.accepted('AppleLibm', x) for x in fp.trig_arguments(('circle_lines_ex', 5.0, 5.0, 4.0, -1.5, 0))))
        self.assertEqual(fp.trig_arguments(('circle_lines_ex', 5.0, 5.0, -2.0, 1.0, 0)), [])
        self.assertIn('DrawTriangleGradient(', fp.c_op(('tri_grad', 1.0, 1.0, 1.0, 5.0, 5.0, 5.0, 1, 2, 3), 0))
        self.assertIn('J.Draw.ellipse_lines_ex_for(M.AppleLibm{}', fp.b_op(('ellipse_lines_ex', 5.0, 5.0, 3.0, 2.0, 1.0, 7), 'AppleLibm', 'f0'))

    def test_rounded_segments_estimated_below_one(self):
        rounded = ('rounded', 2.0, 2.0, 20.0, 12.0, 0.5, 2.0, 0)
        self.assertFalse(rp.op_refused(rounded, 'AppleLibm'))
        self.assertTrue(rp.op_refused(rounded[:6] + (0.0, 0), 'AppleLibm'))
        self.assertFalse(rp.op_refused(rounded[:6] + (0.0, 0), 'Glibc239Libm'))
        # DrawRectangleRoundedLines with roundness 0 is DrawRectangleLines of C ints.
        self.assertTrue(rp.op_refused(('rounded_lines', 3e9, 1.0, 4.0, 4.0, 0.0, 4.0, 0), 'Glibc239Libm'))
        self.assertFalse(rp.op_refused(('rounded_lines', 3.5, 1.0, 4.0, 4.0, 0.0, 4.0, 0), 'AppleLibm'))
        self.assertEqual(len(rp.estimate_rows()), 17*22)

    def test_thick_outlines(self):
        sector = ('sector_ex', 20.0, 15.0, 10.0, 0.0, 90.0, 6.0, 2.0, 0)
        self.assertTrue(rp.op_refused(sector, 'AppleLibm'))
        self.assertFalse(rp.op_refused(sector, 'Glibc241Libm'))
        # Too few segments: estimated under glibc 2.39 only.
        estimated = ('ring_ex', 28.0, 15.0, 6.0, 10.0, 0.0, 300.0, 1.0, 0.5, 0)
        self.assertFalse(rp.op_refused(estimated, 'Glibc239Libm'))
        self.assertTrue(rp.op_refused(estimated, 'Glibc241Libm'))
        # No inner radius and a zero thickness: (int)NaN steps.
        self.assertTrue(rp.op_refused(('ring_ex', 8.0, 6.0, 0.0, 5.0, 0.0, 90.0, 4.0, 0.0, 0), 'Glibc239Libm'))
        # A whole-degree apothem argument is beyond what the Apple rule predicts.
        with self.assertRaises(ProbeFailure):
            rp.op_refused(('sector_ex', 12.0, 12.0, 10.0, 0.0, 40.0, 1.0, 4.0, 0), 'AppleLibm')
        self.assertIn('DrawRingLinesEx(', rp.c_op(estimated))
        self.assertEqual(rp.op_words(estimated)[0], 214)

    def test_scenes_predictable(self):
        for libm in ('AppleLibm', 'Glibc239Libm', 'Glibc241Libm'):
            [rp.refused(scene, libm) for scene in rp.scenes()]
            [fp.refused(op, libm) for scene in fp.scenes() for op in scene['ops']]


if __name__ == '__main__':
    unittest.main()
