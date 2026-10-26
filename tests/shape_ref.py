"""Independent reference for the shape math used by shell/common/ShapeMath.js.

A Python port of androidx graphics-shapes (RoundedPolygon, normalized, Morph; vendored as
tokens/sources/GraphicsShapes*.kt) and of MaterialShapes.kt's customPolygon. It builds the
definitions tools/gen_components.py writes to tokens/components.json ("material_shapes").
Test cases for the JS come from `cases()`; tests/test_shape_ref.py checks this file on its own.

A cubic is a list of 8 floats: anchor0, control0, control1, anchor1 (x, y each).
A feature is (kind, cubics) with kind "edge", "convex" or "concave".
"""
import json
import math
from pathlib import Path

DISTANCE_EPSILON = 1e-4
ANGLE_EPSILON = 1e-6
ROOT = Path(__file__).resolve().parent.parent


# ---- points and cubics ----------------------------------------------------------------------

def dist(x, y):
    return math.sqrt(x * x + y * y)


def direction(x, y):
    d = dist(x, y)
    if d <= 0:
        raise ValueError("direction of a zero vector")
    return x / d, y / d


def lerp(a, b, t):
    return (1 - t) * a + t * b


def point_on(c, t):
    u = 1 - t
    return (c[0] * u * u * u + c[2] * 3 * t * u * u + c[4] * 3 * t * t * u + c[6] * t * t * t,
            c[1] * u * u * u + c[3] * 3 * t * u * u + c[5] * 3 * t * t * u + c[7] * t * t * t)


def straight(x0, y0, x1, y1):
    return [x0, y0, lerp(x0, x1, 1 / 3), lerp(y0, y1, 1 / 3), lerp(x0, x1, 2 / 3), lerp(y0, y1, 2 / 3), x1, y1]


def arc(cx, cy, x0, y0, x1, y1):
    p0 = direction(x0 - cx, y0 - cy)
    p1 = direction(x1 - cx, y1 - cy)
    r0 = (-p0[1], p0[0])
    r1 = (-p1[1], p1[0])
    clockwise = r0[0] * (x1 - cx) + r0[1] * (y1 - cy) >= 0
    cosa = p0[0] * p1[0] + p0[1] * p1[1]
    if cosa > 0.999:
        return straight(x0, y0, x1, y1)
    k = (dist(x0 - cx, y0 - cy) * 4 / 3 * (math.sqrt(2 * (1 - cosa)) - math.sqrt(1 - cosa * cosa))
         / (1 - cosa) * (1 if clockwise else -1))
    return [x0, y0, x0 + r0[0] * k, y0 + r0[1] * k, x1 - r1[0] * k, y1 - r1[1] * k, x1, y1]


def zero_length(c):
    return abs(c[0] - c[6]) < DISTANCE_EPSILON and abs(c[1] - c[7]) < DISTANCE_EPSILON


def split(c, t):
    u = 1 - t
    px, py = point_on(c, t)
    return ([c[0], c[1], c[0] * u + c[2] * t, c[1] * u + c[3] * t,
             c[0] * u * u + c[2] * 2 * u * t + c[4] * t * t, c[1] * u * u + c[3] * 2 * u * t + c[5] * t * t, px, py],
            [px, py, c[2] * u * u + c[4] * 2 * u * t + c[6] * t * t, c[3] * u * u + c[5] * 2 * u * t + c[7] * t * t,
             c[4] * u + c[6] * t, c[5] * u + c[7] * t, c[6], c[7]])


def reverse(c):
    return [c[6], c[7], c[4], c[5], c[2], c[3], c[0], c[1]]


def convex(prev, cur, nxt):
    ax, ay = cur[0] - prev[0], cur[1] - prev[1]
    bx, by = nxt[0] - cur[0], nxt[1] - cur[1]
    return ax * by - ay * bx > 0


# ---- rounded polygon ------------------------------------------------------------------------

def rounded_corner(p0, p1, p2, rounding):
    """The geometry of one corner; `cubics(cut0, cut1)` gives its curves."""
    v01 = (p0[0] - p1[0], p0[1] - p1[1])
    v21 = (p2[0] - p1[0], p2[1] - p1[1])
    d01, d21 = dist(*v01), dist(*v21)
    c = {"p0": p0, "p1": p1, "p2": p2}
    if d01 > 0 and d21 > 0:
        c["d1"] = (v01[0] / d01, v01[1] / d01)
        c["d2"] = (v21[0] / d21, v21[1] / d21)
        c["radius"], c["smoothing"] = rounding
        cos_a = c["d1"][0] * c["d2"][0] + c["d1"][1] * c["d2"][1]
        sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
        c["round_cut"] = c["radius"] * (cos_a + 1) / sin_a if sin_a > 1e-3 else 0.0
    else:
        c.update(d1=(0.0, 0.0), d2=(0.0, 0.0), radius=0.0, smoothing=0.0, round_cut=0.0)
    c["cut"] = (1 + c["smoothing"]) * c["round_cut"]
    return c


def corner_cubics(c, cut0, cut1):
    allowed = min(cut0, cut1)
    p1 = c["p1"]
    if c["round_cut"] < DISTANCE_EPSILON or allowed < DISTANCE_EPSILON or c["radius"] < DISTANCE_EPSILON:
        return [straight(p1[0], p1[1], p1[0], p1[1])]
    round_cut = min(allowed, c["round_cut"])

    def smoothing(cut):
        if cut > c["cut"]:
            return c["smoothing"]
        if cut > c["round_cut"]:
            return c["smoothing"] * (cut - c["round_cut"]) / (c["cut"] - c["round_cut"])
        return 0.0

    r = c["radius"] * round_cut / c["round_cut"]
    center_distance = math.sqrt(r * r + round_cut * round_cut)
    bis = direction((c["d1"][0] + c["d2"][0]) / 2, (c["d1"][1] + c["d2"][1]) / 2)
    center = (p1[0] + bis[0] * center_distance, p1[1] + bis[1] * center_distance)
    hit0 = (p1[0] + c["d1"][0] * round_cut, p1[1] + c["d1"][1] * round_cut)
    hit2 = (p1[0] + c["d2"][0] * round_cut, p1[1] + c["d2"][1] * round_cut)

    def flank(s, side_start, hit, other):
        side = direction(side_start[0] - p1[0], side_start[1] - p1[1])
        start = (p1[0] + side[0] * round_cut * (1 + s), p1[1] + side[1] * round_cut * (1 + s))
        p = (lerp(hit[0], (hit[0] + other[0]) / 2, s), lerp(hit[1], (hit[1] + other[1]) / 2, s))
        dx, dy = direction(p[0] - center[0], p[1] - center[1])
        end = (center[0] + dx * r, center[1] + dy * r)
        tangent = (-(end[1] - center[1]), end[0] - center[0])
        anchor_end = line_intersection(side_start, side, end, tangent) or hit
        anchor_start = ((start[0] + anchor_end[0] * 2) / 3, (start[1] + anchor_end[1] * 2) / 3)
        return [*start, *anchor_start, *anchor_end, *end]

    f0 = flank(smoothing(cut0), c["p0"], hit0, hit2)
    f2 = reverse(flank(smoothing(cut1), c["p2"], hit2, hit0))
    return [f0, arc(center[0], center[1], f0[6], f0[7], f2[0], f2[1]), f2]


def line_intersection(p0, d0, p1, d1):
    rd1 = (-d1[1], d1[0])
    den = d0[0] * rd1[0] + d0[1] * rd1[1]
    if abs(den) < DISTANCE_EPSILON:
        return None
    num = (p1[0] - p0[0]) * rd1[0] + (p1[1] - p0[1]) * rd1[1]
    if abs(den) < DISTANCE_EPSILON * abs(num):
        return None
    k = num / den
    return (p0[0] + d0[0] * k, p0[1] + d0[1] * k)


def polygon(vertices, roundings, center=None):
    """RoundedPolygon(vertices, perVertexRounding, centerX, centerY): features and center."""
    n = len(vertices)
    corners = [rounded_corner(vertices[(i - 1) % n], vertices[i], vertices[(i + 1) % n], roundings[i])
               for i in range(n)]
    adjust = []
    for i in range(n):
        a, b = corners[i], corners[(i + 1) % n]
        round_cut = a["round_cut"] + b["round_cut"]
        cut = a["cut"] + b["cut"]
        side = dist(vertices[i][0] - vertices[(i + 1) % n][0], vertices[i][1] - vertices[(i + 1) % n][1])
        if round_cut > side:
            adjust.append((side / round_cut, 0.0))
        elif cut > side:
            adjust.append((1.0, (side - round_cut) / (cut - round_cut)))
        else:
            adjust.append((1.0, 1.0))
    curves = []
    for i in range(n):
        cuts = []
        for delta in (0, 1):
            round_ratio, cut_ratio = adjust[(i + n - 1 + delta) % n]
            c = corners[i]
            cuts.append(c["round_cut"] * round_ratio + (c["cut"] - c["round_cut"]) * cut_ratio)
        curves.append(corner_cubics(corners[i], *cuts))
    features = []
    for i in range(n):
        kind = "convex" if convex(vertices[(i - 1) % n], vertices[i], vertices[(i + 1) % n]) else "concave"
        features.append((kind, curves[i]))
        a, b = curves[i][-1], curves[(i + 1) % n][0]
        features.append(("edge", [straight(a[6], a[7], b[0], b[1])]))
    if center is None:
        center = (sum(v[0] for v in vertices) / n, sum(v[1] for v in vertices) / n)
    return {"features": features, "center": center}


def cubics(poly):
    """RoundedPolygon.cubics: the outline with zero-length curves folded in, starting mid first corner."""
    feats = poly["features"]
    out, first, last = [], None, None
    split_start = split_end = None
    if feats and len(feats[0][1]) == 3:
        a, b = split(feats[0][1][1], 0.5)
        split_start, split_end = [feats[0][1][0], a], [b, feats[0][1][2]]
    for i in range(len(feats) + 1):
        if i == 0 and split_end is not None:
            group = split_end
        elif i == len(feats):
            if split_start is None:
                break
            group = split_start
        else:
            group = feats[i][1]
        for c in group:
            if not zero_length(c):
                if last is not None:
                    out.append(last)
                last = c
                if first is None:
                    first = c
            elif last is not None:
                last = last[:6] + [c[6], c[7]]
    if last is not None and first is not None:
        out.append(last[:6] + [first[0], first[1]])
    else:
        cx, cy = poly["center"]
        out.append([cx, cy] * 4)
    return out


def transformed(poly, f):
    def tc(c):
        out = []
        for i in range(0, 8, 2):
            out.extend(f(c[i], c[i + 1]))
        return out
    return {"features": [(k, [tc(c) for c in cs]) for k, cs in poly["features"]],
            "center": f(*poly["center"])}


def bounds(poly):
    xs, ys = [], []
    for c in cubics(poly):
        if zero_length(c):
            xs.append(c[0])
            ys.append(c[1])
        else:
            xs.extend(c[0::2])
            ys.extend(c[1::2])
    return min(xs), min(ys), max(xs), max(ys)


def normalized(poly):
    left, top, right, bottom = bounds(poly)
    w, h = right - left, bottom - top
    side = max(w, h)
    ox, oy = (side - w) / 2 - left, (side - h) / 2 - top
    return transformed(poly, lambda x, y: ((x + ox) / side, (y + oy) / side))


# ---- MaterialShapes definitions -------------------------------------------------------------

def regular_vertices(n, radius=1.0):
    return [(radius * math.cos(math.pi / n * 2 * i), radius * math.sin(math.pi / n * 2 * i)) for i in range(n)]


def repeat_points(points, reps, mirror, center=(0.5, 0.5)):
    """MaterialShapes.doRepeat: (x, y, radius, smoothing) points repeated around `center`."""
    cx, cy = center
    out = []
    if mirror:
        angles = [math.degrees(math.atan2(p[1] - cy, p[0] - cx)) for p in points]
        dists = [dist(p[0] - cx, p[1] - cy) for p in points]
        section = 360 / (reps * 2)
        for it in range(reps * 2):
            for index in range(len(points)):
                i = index if it % 2 == 0 else len(points) - 1 - index
                if i > 0 or it % 2 == 0:
                    a = math.radians(section * it + (angles[i] if it % 2 == 0
                                                     else section - angles[i] + 2 * angles[0]))
                    out.append((cx + math.cos(a) * dists[i], cy + math.sin(a) * dists[i], points[i][2], points[i][3]))
    else:
        for it in range(len(points) * reps):
            p = points[it % len(points)]
            a = math.radians((it // len(points)) * 360 / reps)
            dx, dy = p[0] - cx, p[1] - cy
            out.append((dx * math.cos(a) - dy * math.sin(a) + cx, dx * math.sin(a) + dy * math.cos(a) + cy, p[2], p[3]))
    return out


def build(d):
    """A definition from tokens/components.json -> the normalized polygon MaterialShapes exposes."""
    kind = d["kind"]
    if kind == "custom":
        pts = repeat_points(d["points"], d["reps"], d["mirror"])
        poly = polygon([(p[0], p[1]) for p in pts], [(p[2], p[3]) for p in pts], (0.5, 0.5))
    elif kind == "star":
        verts = []
        for i in range(d["n"]):
            verts.append((math.cos(math.pi / d["n"] * 2 * i), math.sin(math.pi / d["n"] * 2 * i)))
            a = math.pi / d["n"] * (2 * i + 1)
            verts.append((d["inner"] * math.cos(a), d["inner"] * math.sin(a)))
        poly = polygon(verts, [tuple(d["rounding"])] * len(verts), (0.0, 0.0))
    elif kind == "circle":
        poly = polygon(regular_vertices(d["n"], 1 / math.cos(math.pi / d["n"])), [(1.0, 0.0)] * d["n"], (0.0, 0.0))
    elif kind == "rect":
        w, h = d["w"] / 2, d["h"] / 2
        poly = polygon([(w, h), (-w, h), (-w, -h), (w, -h)], [tuple(r) for r in d["rounding"]], (0.0, 0.0))
    elif kind == "regular":
        poly = polygon(regular_vertices(d["n"]), [tuple(r) for r in d["rounding"]], (0.0, 0.0))
    else:
        raise ValueError(f"unknown shape kind {kind}")
    for op in d.get("transform", []):
        if op[0] == "scale":
            sx, sy = op[1], op[2]
            poly = transformed(poly, lambda x, y, sx=sx, sy=sy: (x * sx, y * sy))
        else:
            a = math.radians(op[1])
            c, s = math.cos(a), math.sin(a)
            poly = transformed(poly, lambda x, y, c=c, s=s: (c * x - s * y, s * x + c * y))
    return normalized(poly)


# ---- morph ----------------------------------------------------------------------------------

def positive_mod(x, m):
    return (x % m + m) % m


def progress_distance(a, b):
    d = abs(a - b)
    return min(d, 1 - d)


def in_range(p, lo, hi):
    return lo <= p <= hi if hi >= lo else p >= lo or p <= hi


def measure(c):
    """LengthMeasurer: length along three chords."""
    total, prev = 0.0, (c[0], c[1])
    for i in (1, 2, 3):
        p = point_on(c, i / 3)
        total += dist(p[0] - prev[0], p[1] - prev[1])
        prev = p
    return total


def cut_point(c, m):
    remainder, prev = m, (c[0], c[1])
    for i in (1, 2, 3):
        p = point_on(c, i / 3)
        seg = dist(p[0] - prev[0], p[1] - prev[1])
        if seg >= remainder:
            return i / 3 - (1 - remainder / seg) / 3
        remainder -= seg
        prev = p
    return 1.0


class Measured:
    """MeasuredPolygon: curves with outline progress ranges, and corner features with a progress."""

    def __init__(self, features, curves, progress):
        self.features = features
        self.items = []
        start = 0.0
        for i, c in enumerate(curves):
            if progress[i + 1] - progress[i] > DISTANCE_EPSILON:
                self.items.append([c, start, progress[i + 1]])
                start = progress[i + 1]
        self.items[-1][2] = 1.0

    @classmethod
    def of(cls, poly):
        curves, marks = [], []
        for kind, cs in poly["features"]:
            for j, c in enumerate(cs):
                if kind != "edge" and j == len(cs) // 2:
                    marks.append((kind, cs, len(curves)))
                curves.append(c)
        sums = [0.0]
        for c in curves:
            sums.append(sums[-1] + measure(c))
        progress = [s / sums[-1] for s in sums]
        feats = [(positive_mod((progress[ix] + progress[ix + 1]) / 2, 1), kind, cs) for kind, cs, ix in marks]
        return cls(feats, curves, progress)

    @staticmethod
    def cut(item, at):
        c, start, end = item
        at = min(max(at, start), end)
        t = cut_point(c, (at - start) / (end - start) * measure(c))
        a, b = split(c, t)
        return [a, start, at], [b, at, end]

    def cut_and_shift(self, point):
        if point < DISTANCE_EPSILON:
            return self
        idx = next(i for i, it in enumerate(self.items) if it[1] <= point <= it[2])
        b1, b2 = self.cut(self.items[idx], point)
        n = len(self.items)
        curves = [b2[0]] + [self.items[(i + idx) % n][0] for i in range(1, n)] + [b1[0]]
        progress = [0.0] + [positive_mod(self.items[(idx + i - 1) % n][2] - point, 1) for i in range(1, n + 1)] + [1.0]
        feats = [(positive_mod(p - point, 1), k, cs) for p, k, cs in self.features]
        return Measured(feats, curves, progress)


def representative(cs):
    return ((cs[0][0] + cs[-1][6]) / 2, (cs[0][1] + cs[-1][7]) / 2)


def feature_mapping(f1, f2):
    """doMapping: pairs of (progress on 1, progress on 2), matching nearest corners of the same kind."""
    pairs = []
    for a in f1:
        for b in f2:
            if a[1] != b[1]:
                continue
            pa, pb = representative(a[2]), representative(b[2])
            pairs.append(((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2, a, b))
    pairs.sort(key=lambda x: x[0])
    if not pairs:
        return [(0.0, 0.0), (0.5, 0.5)]
    if len(pairs) == 1:
        a, b = pairs[0][1][0], pairs[0][2][0]
        return [(a, b), ((a + 0.5) % 1, (b + 0.5) % 1)]
    mapping, used1, used2 = [], set(), set()
    for _, a, b in pairs:
        if id(a) in used1 or id(b) in used2:
            continue
        ins = 0
        while ins < len(mapping) and mapping[ins][0] < a[0]:
            ins += 1
        n = len(mapping)
        if n >= 1:
            before, after = mapping[(ins + n - 1) % n], mapping[ins % n]
            if (progress_distance(a[0], before[0]) < DISTANCE_EPSILON
                    or progress_distance(a[0], after[0]) < DISTANCE_EPSILON
                    or progress_distance(b[0], before[1]) < DISTANCE_EPSILON
                    or progress_distance(b[0], after[1]) < DISTANCE_EPSILON):
                continue
            if n > 1 and not in_range(b[0], before[1], after[1]):
                continue
        mapping.insert(ins, (a[0], b[0]))
        used1.add(id(a))
        used2.add(id(b))
    return mapping


def linear_map(xs, ys, x):
    n = len(xs)
    i = next(i for i in range(n) if in_range(x, xs[i], xs[(i + 1) % n]))
    j = (i + 1) % n
    size_x = positive_mod(xs[j] - xs[i], 1)
    size_y = positive_mod(ys[j] - ys[i], 1)
    pos = 0.5 if size_x < 0.001 else positive_mod(x - xs[i], 1) / size_x
    return positive_mod(ys[i] + size_y * pos, 1)


def match(p1, p2):
    """Morph.match: pairs of cubics, one from each shape, to interpolate."""
    m1, m2 = Measured.of(p1), Measured.of(p2)
    mapping = feature_mapping([f for f in m1.features], [f for f in m2.features])
    xs, ys = [a for a, _ in mapping], [b for _, b in mapping]
    fwd = lambda x: linear_map(xs, ys, x)
    back = lambda y: linear_map(ys, xs, y)
    cut = fwd(0.0)
    bs1, bs2 = m1.items, m2.cut_and_shift(cut).items
    out, i1, i2 = [], 1, 1
    b1, b2 = bs1[0], bs2[0]
    while b1 is not None and b2 is not None:
        a1 = 1.0 if i1 == len(bs1) else b1[2]
        a2 = 1.0 if i2 == len(bs2) else back(positive_mod(b2[2] + cut, 1))
        lo = min(a1, a2)
        if a1 > lo + ANGLE_EPSILON:
            seg1, b1 = Measured.cut(b1, lo)
        else:
            seg1, b1 = b1, (bs1[i1] if i1 < len(bs1) else None)
            i1 += 1
        if a2 > lo + ANGLE_EPSILON:
            seg2, b2 = Measured.cut(b2, positive_mod(fwd(lo) - cut, 1))
        else:
            seg2, b2 = b2, (bs2[i2] if i2 < len(bs2) else None)
            i2 += 1
        out.append((seg1[0], seg2[0]))
    if b1 is not None or b2 is not None:
        raise ValueError("morph did not match every curve")
    return out


def morph(pairs, t):
    """Morph.asCubics(t): the closed outline at progress t."""
    out = [[lerp(a[k], b[k], t) for k in range(8)] for a, b in pairs]
    out[-1] = out[-1][:6] + out[0][:2]
    return out


# ---- cases for the JS test ------------------------------------------------------------------

# The last three each depend on a detail of the matching (mapping order, the end epsilon, corner kinds).
MORPHS = [("circle", "cookie9Sided"), ("square", "softBurst"), ("cookie4Sided", "heart"),
          ("pill", "clover8Leaf"), ("triangle", "pixelCircle"), ("sunny", "softBoom"),
          ("arrow", "heart"), ("arch", "circle"), ("arch", "cookie9Sided")]


def definitions():
    return json.loads((ROOT / "tokens" / "components.json").read_text())["material_shapes"]["shapes"]


def cases():
    defs = definitions()
    shapes = {name: cubics(build(d)) for name, d in defs.items()}
    morphs = []
    for a, b in MORPHS:
        pairs = match(build(defs[a]), build(defs[b]))
        morphs.append({"from": a, "to": b, "count": len(pairs),
                       "at": {str(t): morph(pairs, t) for t in (0.0, 0.5, 1.0)}})
    return {"shapes": shapes, "morphs": morphs}
