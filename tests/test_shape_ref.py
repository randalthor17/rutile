import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shape_ref as ref  # noqa: E402


def samples(cubics, per=24):
    pts = []
    for c in cubics:
        for i in range(per):
            pts.append(ref.point_on(c, i / per))
    return pts


def area(cubics):
    pts = samples(cubics)
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))) / 2


def nearest(p, pts):
    return min(math.dist(p, q) for q in pts)


def distance_to(p, cubics):
    """Distance from p to the outline: a coarse pass, then a ternary search on the two best curves."""
    coarse = sorted((math.dist(p, ref.point_on(c, i / 16)), i / 16, c) for c in cubics for i in range(17))
    best = coarse[0][0]
    for _, t, c in coarse[:2]:
        lo, hi = max(0.0, t - 1 / 16), min(1.0, t + 1 / 16)
        for _ in range(40):
            m1, m2 = lo + (hi - lo) / 3, hi - (hi - lo) / 3
            if math.dist(p, ref.point_on(c, m1)) < math.dist(p, ref.point_on(c, m2)):
                hi = m2
            else:
                lo = m1
        best = min(best, math.dist(p, ref.point_on(c, (lo + hi) / 2)))
    return best


class ReferenceIsCorrect(unittest.TestCase):
    """Geometry the shapes must have, checked without the JS (which mirrors this file)."""

    @classmethod
    def setUpClass(cls):
        cls.defs = ref.definitions()
        cls.shapes = {n: ref.build(d) for n, d in cls.defs.items()}

    def test_every_shape_is_closed_and_fills_the_unit_square(self):
        for name, poly in self.shapes.items():
            cs = ref.cubics(poly)
            for a, b in zip(cs, cs[1:] + cs[:1]):
                self.assertAlmostEqual(a[6], b[0], delta=1e-9, msg=name)
                self.assertAlmostEqual(a[7], b[1], delta=1e-9, msg=name)
            left, top, right, bottom = ref.bounds(poly)
            self.assertGreaterEqual(min(left, top), -1e-9, name)
            self.assertLessEqual(max(right, bottom), 1 + 1e-9, name)
            self.assertAlmostEqual(max(right - left, bottom - top), 1, delta=1e-9, msg=name)
            # centered on the shorter axis
            self.assertAlmostEqual(left + right, 1, delta=1e-9, msg=name)
            self.assertAlmostEqual(top + bottom, 1, delta=1e-9, msg=name)

    def test_circle_is_round(self):
        cs = ref.cubics(self.shapes["circle"])
        pts = samples(cs)
        # normalized() uses the control points' bounds (as Compose does): the 10-gon's arcs bulge
        # differently left and right, so the circle sits a hair off center and inside the square
        cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
        self.assertAlmostEqual(cx, 0.504, delta=1e-3)
        radius = [math.dist(p, (cx, 0.5)) for p in pts]
        self.assertLess(max(radius) - min(radius), 1e-5)
        self.assertAlmostEqual(area(cs), math.pi * max(radius) ** 2, delta=2e-3)

    def test_square_has_straight_sides_and_round_corners(self):
        cs = ref.cubics(self.shapes["square"])
        pts = samples(cs)
        # each side is straight between the 0.3 corners
        for x in (0.3, 0.5, 0.7):
            self.assertLess(nearest((x, 0), pts), 1e-3)
            self.assertLess(nearest((0, x), pts), 1e-3)
        # the corner is an arc of radius 0.3 around (0.3, 0.3)
        diag = 0.3 - 0.3 / math.sqrt(2)
        self.assertLess(nearest((diag, diag), pts), 2e-3)
        self.assertGreater(nearest((0, 0), pts), 0.1)

    def test_stars_alternate_convex_and_concave_corners(self):
        kinds = [k for k, _ in self.shapes["cookie9Sided"]["features"] if k != "edge"]
        self.assertEqual(len(kinds), 18)
        self.assertEqual(kinds, ["convex", "concave"] * 9)
        # all corners of a convex shape are convex
        self.assertEqual({k for k, _ in self.shapes["square"]["features"] if k != "edge"}, {"convex"})

    def test_cookie_has_its_points_and_dips(self):
        cs = ref.cubics(self.shapes["cookie9Sided"])
        radius = [math.dist(p, (0.5, 0.5)) for p in samples(cs)]
        # 9 bumps reaching the edge and dips toward the inner radius (0.8, softened by rounding)
        # (normalizing uses the control points' bounds, as Compose does, so the bumps stop short of 0.5)
        self.assertTrue(0.47 < max(radius) <= 0.5, max(radius))
        self.assertTrue(0.36 < min(radius) < 0.45, min(radius))
        # rotated by -90 degrees: a bump points straight up
        self.assertLess(nearest((0.5, 0.0), samples(cs)), 0.02)

    def test_mirrored_shapes_are_symmetric(self):
        for name in ("heart", "pentagon", "gem", "ghostish", "bun"):
            pts = samples(ref.cubics(self.shapes[name]), 96)
            worst = max(nearest((1 - x, y), pts) for x, y in pts[::61])
            self.assertLess(worst, 5e-3, name)

    def test_repeated_shapes_have_rotational_symmetry(self):
        for name, reps in (("softBurst", 10), ("clover8Leaf", 8), ("cookie4Sided", 4)):
            pts = samples(ref.cubics(self.shapes[name]), 96)
            a = 2 * math.pi / reps
            rot = lambda p: (0.5 + (p[0] - 0.5) * math.cos(a) - (p[1] - 0.5) * math.sin(a),
                             0.5 + (p[0] - 0.5) * math.sin(a) + (p[1] - 0.5) * math.cos(a))
            worst = max(nearest(rot(p), pts) for p in pts[::61])
            self.assertLess(worst, 5e-3, name)

    def test_morph_starts_and_ends_on_the_two_shapes(self):
        for a, b in ref.MORPHS + [("heart", "circle"), ("flower", "square")]:
            pa, pb = self.shapes[a], self.shapes[b]
            pairs = ref.match(pa, pb)
            start, end = ref.morph(pairs, 0), ref.morph(pairs, 1)
            ca, cb = ref.cubics(pa), ref.cubics(pb)
            self.assertLess(max(distance_to(p, ca) for p in samples(start, 3)), 1e-5, f"{a} to {b} at 0")
            self.assertLess(max(distance_to(p, cb) for p in samples(end, 3)), 1e-5, f"{a} to {b} at 1")
            self.assertAlmostEqual(area(start), area(ref.cubics(pa)), delta=2e-3, msg=a)
            self.assertAlmostEqual(area(end), area(ref.cubics(pb)), delta=2e-3, msg=b)
            mid = area(ref.morph(pairs, 0.5))
            self.assertTrue(min(area(start), area(end)) - 0.05 < mid < max(area(start), area(end)) + 0.05)

    def test_morph_maps_corners_to_nearby_corners(self):
        # square to cookie4: each square corner goes to the cookie bump in the same quadrant
        pairs = ref.match(self.shapes["square"], self.shapes["cookie4Sided"])
        for a, b in pairs:
            qa = (a[0] > 0.5, a[1] > 0.5)
            qb = (b[0] > 0.5, b[1] > 0.5)
            if math.dist((a[0], a[1]), (0.5, 0.5)) > 0.6:
                self.assertEqual(qa, qb)

    def test_mapping_keeps_progress_order(self):
        m1 = ref.Measured.of(self.shapes["sunny"])
        m2 = ref.Measured.of(self.shapes["softBoom"])
        mapping = ref.feature_mapping(m1.features, m2.features)
        self.assertGreater(len(mapping), 4)
        firsts = [a for a, _ in mapping]
        self.assertEqual(firsts, sorted(firsts))
        kinds1 = {f[0]: f[1] for f in m1.features}
        kinds2 = {f[0]: f[1] for f in m2.features}
        self.assertEqual({kinds1[a] == kinds2[b] for a, b in mapping}, {True}, "only corners of one kind pair up")
        self.assertEqual({kinds1[a] for a, _ in mapping}, {"convex", "concave"})
        seconds = [b for _, b in mapping]
        wraps = sum(1 for x, y in zip(seconds, seconds[1:]) if y < x)
        self.assertLessEqual(wraps, 1)

    def test_degenerate_inputs(self):
        with self.assertRaises(ValueError):
            ref.direction(0, 0)
        with self.assertRaises(ValueError):
            ref.build({"kind": "blob"})
        unrounded = ref.polygon([(0, 0), (1, 0), (0, 1)], [(0, 0)] * 3)
        self.assertEqual(len(ref.cubics(unrounded)), 3)
        self.assertEqual(ref.feature_mapping([], []), [(0.0, 0.0), (0.5, 0.5)])

    def test_cases_cover_every_shape(self):
        c = ref.cases()
        self.assertEqual(set(c["shapes"]), set(self.defs))
        self.assertEqual(len(c["morphs"]), len(ref.MORPHS))


if __name__ == "__main__":
    unittest.main()
