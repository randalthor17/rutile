// Material 3 Expressive shapes and shape morphing.
// A port of androidx graphics-shapes (RoundedPolygon, normalized, Morph; Apache-2.0, vendored as
// tokens/sources/GraphicsShapes*.kt) and of MaterialShapes.kt's customPolygon. Definitions come from
// MaterialShapes.js (generated); tests/shape_ref.py is the independent Python reference.
// A cubic is an array of 8 numbers: anchor0, control0, control1, anchor1 (x, y each).
// A feature is {kind: "edge" | "convex" | "concave", cubics: [...]}.
.pragma library

var DistanceEpsilon = 1e-4;
var AngleEpsilon = 1e-6;

function dist(x, y) { return Math.sqrt(x * x + y * y); }

function direction(x, y) {
    var d = dist(x, y);
    if (!(d > 0)) throw new Error("direction of a zero vector");
    return [x / d, y / d];
}

function lerp(a, b, t) { return (1 - t) * a + t * b; }

function pointOn(c, t) {
    var u = 1 - t;
    return [c[0] * u * u * u + c[2] * 3 * t * u * u + c[4] * 3 * t * t * u + c[6] * t * t * t,
            c[1] * u * u * u + c[3] * 3 * t * u * u + c[5] * 3 * t * t * u + c[7] * t * t * t];
}

function straight(x0, y0, x1, y1) {
    return [x0, y0, lerp(x0, x1, 1 / 3), lerp(y0, y1, 1 / 3), lerp(x0, x1, 2 / 3), lerp(y0, y1, 2 / 3), x1, y1];
}

function arc(cx, cy, x0, y0, x1, y1) {
    var p0 = direction(x0 - cx, y0 - cy), p1 = direction(x1 - cx, y1 - cy);
    var r0 = [-p0[1], p0[0]], r1 = [-p1[1], p1[0]];
    var clockwise = r0[0] * (x1 - cx) + r0[1] * (y1 - cy) >= 0;
    var cosa = p0[0] * p1[0] + p0[1] * p1[1];
    if (cosa > 0.999) return straight(x0, y0, x1, y1);
    var k = dist(x0 - cx, y0 - cy) * 4 / 3 * (Math.sqrt(2 * (1 - cosa)) - Math.sqrt(1 - cosa * cosa))
            / (1 - cosa) * (clockwise ? 1 : -1);
    return [x0, y0, x0 + r0[0] * k, y0 + r0[1] * k, x1 - r1[0] * k, y1 - r1[1] * k, x1, y1];
}

function zeroLength(c) {
    return Math.abs(c[0] - c[6]) < DistanceEpsilon && Math.abs(c[1] - c[7]) < DistanceEpsilon;
}

function split(c, t) {
    var u = 1 - t, p = pointOn(c, t);
    return [[c[0], c[1], c[0] * u + c[2] * t, c[1] * u + c[3] * t,
             c[0] * u * u + c[2] * 2 * u * t + c[4] * t * t, c[1] * u * u + c[3] * 2 * u * t + c[5] * t * t, p[0], p[1]],
            [p[0], p[1], c[2] * u * u + c[4] * 2 * u * t + c[6] * t * t, c[3] * u * u + c[5] * 2 * u * t + c[7] * t * t,
             c[4] * u + c[6] * t, c[5] * u + c[7] * t, c[6], c[7]]];
}

function reverse(c) { return [c[6], c[7], c[4], c[5], c[2], c[3], c[0], c[1]]; }

function convex(prev, cur, next) {
    return (cur[0] - prev[0]) * (next[1] - cur[1]) - (cur[1] - prev[1]) * (next[0] - cur[0]) > 0;
}

function lineIntersection(p0, d0, p1, d1) {
    var rx = -d1[1], ry = d1[0];
    var den = d0[0] * rx + d0[1] * ry;
    if (Math.abs(den) < DistanceEpsilon) return null;
    var num = (p1[0] - p0[0]) * rx + (p1[1] - p0[1]) * ry;
    if (Math.abs(den) < DistanceEpsilon * Math.abs(num)) return null;
    return [p0[0] + d0[0] * num / den, p0[1] + d0[1] * num / den];
}

// ---- rounded polygon ----

function roundedCorner(p0, p1, p2, rounding) {
    var c = { p0: p0, p1: p1, p2: p2, d1: [0, 0], d2: [0, 0], radius: 0, smoothing: 0, roundCut: 0 };
    var v01 = [p0[0] - p1[0], p0[1] - p1[1]], v21 = [p2[0] - p1[0], p2[1] - p1[1]];
    var d01 = dist(v01[0], v01[1]), d21 = dist(v21[0], v21[1]);
    if (d01 > 0 && d21 > 0) {
        c.d1 = [v01[0] / d01, v01[1] / d01];
        c.d2 = [v21[0] / d21, v21[1] / d21];
        c.radius = rounding[0];
        c.smoothing = rounding[1];
        var cosA = c.d1[0] * c.d2[0] + c.d1[1] * c.d2[1];
        var sinA = Math.sqrt(Math.max(0, 1 - cosA * cosA));
        c.roundCut = sinA > 1e-3 ? c.radius * (cosA + 1) / sinA : 0;
    }
    c.cut = (1 + c.smoothing) * c.roundCut;
    return c;
}

function cornerCubics(c, cut0, cut1) {
    var allowed = Math.min(cut0, cut1), p1 = c.p1;
    if (c.roundCut < DistanceEpsilon || allowed < DistanceEpsilon || c.radius < DistanceEpsilon)
        return [straight(p1[0], p1[1], p1[0], p1[1])];
    var roundCut = Math.min(allowed, c.roundCut);
    function smoothing(cut) {
        if (cut > c.cut) return c.smoothing;
        if (cut > c.roundCut) return c.smoothing * (cut - c.roundCut) / (c.cut - c.roundCut);
        return 0;
    }
    var r = c.radius * roundCut / c.roundCut;
    var centerDistance = Math.sqrt(r * r + roundCut * roundCut);
    var bis = direction((c.d1[0] + c.d2[0]) / 2, (c.d1[1] + c.d2[1]) / 2);
    var center = [p1[0] + bis[0] * centerDistance, p1[1] + bis[1] * centerDistance];
    var hit0 = [p1[0] + c.d1[0] * roundCut, p1[1] + c.d1[1] * roundCut];
    var hit2 = [p1[0] + c.d2[0] * roundCut, p1[1] + c.d2[1] * roundCut];
    function flank(s, sideStart, hit, other) {
        var side = direction(sideStart[0] - p1[0], sideStart[1] - p1[1]);
        var start = [p1[0] + side[0] * roundCut * (1 + s), p1[1] + side[1] * roundCut * (1 + s)];
        var p = [lerp(hit[0], (hit[0] + other[0]) / 2, s), lerp(hit[1], (hit[1] + other[1]) / 2, s)];
        var dir = direction(p[0] - center[0], p[1] - center[1]);
        var end = [center[0] + dir[0] * r, center[1] + dir[1] * r];
        var tangent = [-(end[1] - center[1]), end[0] - center[0]];
        var anchorEnd = lineIntersection(sideStart, side, end, tangent) || hit;
        return [start[0], start[1], (start[0] + anchorEnd[0] * 2) / 3, (start[1] + anchorEnd[1] * 2) / 3,
                anchorEnd[0], anchorEnd[1], end[0], end[1]];
    }
    var f0 = flank(smoothing(cut0), c.p0, hit0, hit2);
    var f2 = reverse(flank(smoothing(cut1), c.p2, hit2, hit0));
    return [f0, arc(center[0], center[1], f0[6], f0[7], f2[0], f2[1]), f2];
}

// RoundedPolygon(vertices, perVertexRounding, center): [[x, y]...], [[radius, smoothing]...].
function polygon(vertices, roundings, center) {
    var n = vertices.length, i, corners = [], adjust = [], curves = [], features = [];
    for (i = 0; i < n; i++)
        corners.push(roundedCorner(vertices[(i + n - 1) % n], vertices[i], vertices[(i + 1) % n], roundings[i]));
    for (i = 0; i < n; i++) {
        var a = corners[i], b = corners[(i + 1) % n], v = vertices[i], w = vertices[(i + 1) % n];
        var roundCut = a.roundCut + b.roundCut, cut = a.cut + b.cut, side = dist(v[0] - w[0], v[1] - w[1]);
        if (roundCut > side) adjust.push([side / roundCut, 0]);
        else if (cut > side) adjust.push([1, (side - roundCut) / (cut - roundCut)]);
        else adjust.push([1, 1]);
    }
    for (i = 0; i < n; i++) {
        var cuts = [], c = corners[i];
        for (var delta = 0; delta < 2; delta++) {
            var ratio = adjust[(i + n - 1 + delta) % n];
            cuts.push(c.roundCut * ratio[0] + (c.cut - c.roundCut) * ratio[1]);
        }
        curves.push(cornerCubics(c, cuts[0], cuts[1]));
    }
    for (i = 0; i < n; i++) {
        var kind = convex(vertices[(i + n - 1) % n], vertices[i], vertices[(i + 1) % n]) ? "convex" : "concave";
        features.push({ kind: kind, cubics: curves[i] });
        var last = curves[i][curves[i].length - 1], first = curves[(i + 1) % n][0];
        features.push({ kind: "edge", cubics: [straight(last[6], last[7], first[0], first[1])] });
    }
    return { features: features, center: center };
}

// RoundedPolygon.cubics: the outline with zero-length curves folded in, starting mid first corner.
function outline(poly) {
    var feats = poly.features, out = [], first = null, last = null, splitStart = null, splitEnd = null;
    if (feats.length > 0 && feats[0].cubics.length === 3) {
        var halves = split(feats[0].cubics[1], 0.5);
        splitStart = [feats[0].cubics[0], halves[0]];
        splitEnd = [halves[1], feats[0].cubics[2]];
    }
    for (var i = 0; i <= feats.length; i++) {
        var group;
        if (i === 0 && splitEnd) group = splitEnd;
        else if (i === feats.length) {
            if (!splitStart) break;
            group = splitStart;
        } else group = feats[i].cubics;
        for (var j = 0; j < group.length; j++) {
            var c = group[j];
            if (!zeroLength(c)) {
                if (last) out.push(last);
                last = c;
                if (!first) first = c;
            } else if (last) {
                last = last.slice(0, 6).concat([c[6], c[7]]);
            }
        }
    }
    if (last && first) out.push(last.slice(0, 6).concat([first[0], first[1]]));
    else out.push([poly.center[0], poly.center[1], poly.center[0], poly.center[1],
                   poly.center[0], poly.center[1], poly.center[0], poly.center[1]]);
    return out;
}

function transformed(poly, f) {
    function tc(c) {
        var out = [];
        for (var i = 0; i < 8; i += 2) {
            var p = f(c[i], c[i + 1]);
            out.push(p[0], p[1]);
        }
        return out;
    }
    return {
        features: poly.features.map(function (ft) { return { kind: ft.kind, cubics: ft.cubics.map(tc) }; }),
        center: f(poly.center[0], poly.center[1])
    };
}

function bounds(poly) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, cs = outline(poly);
    for (var i = 0; i < cs.length; i++) {
        var c = cs[i], n = zeroLength(c) ? 2 : 8;
        for (var k = 0; k < n; k += 2) {
            minX = Math.min(minX, c[k]); maxX = Math.max(maxX, c[k]);
            minY = Math.min(minY, c[k + 1]); maxY = Math.max(maxY, c[k + 1]);
        }
    }
    return [minX, minY, maxX, maxY];
}

function normalized(poly) {
    var b = bounds(poly), w = b[2] - b[0], h = b[3] - b[1], side = Math.max(w, h);
    var ox = (side - w) / 2 - b[0], oy = (side - h) / 2 - b[1];
    return transformed(poly, function (x, y) { return [(x + ox) / side, (y + oy) / side]; });
}

// ---- MaterialShapes definitions ----

function regularVertices(n, radius) {
    var out = [];
    for (var i = 0; i < n; i++)
        out.push([radius * Math.cos(Math.PI / n * 2 * i), radius * Math.sin(Math.PI / n * 2 * i)]);
    return out;
}

function repeatPoints(points, reps, mirror) {
    var cx = 0.5, cy = 0.5, out = [], it, i;
    if (mirror) {
        var angles = points.map(function (p) { return Math.atan2(p[1] - cy, p[0] - cx) * 180 / Math.PI; });
        var dists = points.map(function (p) { return dist(p[0] - cx, p[1] - cy); });
        var section = 360 / (reps * 2);
        for (it = 0; it < reps * 2; it++) {
            for (var index = 0; index < points.length; index++) {
                i = it % 2 === 0 ? index : points.length - 1 - index;
                if (i > 0 || it % 2 === 0) {
                    var a = (section * it + (it % 2 === 0 ? angles[i] : section - angles[i] + 2 * angles[0]))
                            * Math.PI / 180;
                    out.push([cx + Math.cos(a) * dists[i], cy + Math.sin(a) * dists[i], points[i][2], points[i][3]]);
                }
            }
        }
    } else {
        for (it = 0; it < points.length * reps; it++) {
            var p = points[it % points.length];
            var r = Math.floor(it / points.length) * 360 / reps * Math.PI / 180;
            var dx = p[0] - cx, dy = p[1] - cy;
            out.push([dx * Math.cos(r) - dy * Math.sin(r) + cx, dx * Math.sin(r) + dy * Math.cos(r) + cy, p[2], p[3]]);
        }
    }
    return out;
}

function fill(n, value) {
    var out = [];
    for (var i = 0; i < n; i++) out.push(value);
    return out;
}

// A definition from MaterialShapes.js -> the normalized polygon MaterialShapes exposes.
function build(d) {
    var poly, i;
    if (d.kind === "custom") {
        var pts = repeatPoints(d.points, d.reps, d.mirror);
        poly = polygon(pts.map(function (p) { return [p[0], p[1]]; }),
                       pts.map(function (p) { return [p[2], p[3]]; }), [0.5, 0.5]);
    } else if (d.kind === "star") {
        var verts = [];
        for (i = 0; i < d.n; i++) {
            verts.push([Math.cos(Math.PI / d.n * 2 * i), Math.sin(Math.PI / d.n * 2 * i)]);
            var a = Math.PI / d.n * (2 * i + 1);
            verts.push([d.inner * Math.cos(a), d.inner * Math.sin(a)]);
        }
        poly = polygon(verts, fill(verts.length, d.rounding), [0, 0]);
    } else if (d.kind === "circle") {
        poly = polygon(regularVertices(d.n, 1 / Math.cos(Math.PI / d.n)), fill(d.n, [1, 0]), [0, 0]);
    } else if (d.kind === "rect") {
        var w = d.w / 2, h = d.h / 2;
        poly = polygon([[w, h], [-w, h], [-w, -h], [w, -h]], d.rounding, [0, 0]);
    } else if (d.kind === "regular") {
        poly = polygon(regularVertices(d.n, 1), d.rounding, [0, 0]);
    } else {
        throw new Error("unknown shape kind " + d.kind);
    }
    (d.transform || []).forEach(function (op) {
        if (op[0] === "scale") {
            poly = transformed(poly, function (x, y) { return [x * op[1], y * op[2]]; });
        } else {
            var c = Math.cos(op[1] * Math.PI / 180), s = Math.sin(op[1] * Math.PI / 180);
            poly = transformed(poly, function (x, y) { return [c * x - s * y, s * x + c * y]; });
        }
    });
    return normalized(poly);
}

// ---- morph ----

function positiveMod(x, m) { return (x % m + m) % m; }

function progressDistance(a, b) {
    var d = Math.abs(a - b);
    return Math.min(d, 1 - d);
}

function inRange(p, lo, hi) { return hi >= lo ? p >= lo && p <= hi : p >= lo || p <= hi; }

// LengthMeasurer: length along three chords, and the t at which length m is reached.
function measure(c) {
    var total = 0, prev = [c[0], c[1]];
    for (var i = 1; i <= 3; i++) {
        var p = pointOn(c, i / 3);
        total += dist(p[0] - prev[0], p[1] - prev[1]);
        prev = p;
    }
    return total;
}

function cutPoint(c, m) {
    var remainder = m, prev = [c[0], c[1]];
    for (var i = 1; i <= 3; i++) {
        var p = pointOn(c, i / 3), seg = dist(p[0] - prev[0], p[1] - prev[1]);
        if (seg >= remainder) return i / 3 - (1 - remainder / seg) / 3;
        remainder -= seg;
        prev = p;
    }
    return 1;
}

// MeasuredPolygon: items are [cubic, startProgress, endProgress]; features are corners with a progress.
function measured(features, curves, progress) {
    var items = [], start = 0;
    for (var i = 0; i < curves.length; i++) {
        if (progress[i + 1] - progress[i] > DistanceEpsilon) {
            items.push([curves[i], start, progress[i + 1]]);
            start = progress[i + 1];
        }
    }
    items[items.length - 1][2] = 1;
    return { features: features, items: items };
}

function measurePolygon(poly) {
    var curves = [], marks = [], i;
    poly.features.forEach(function (ft) {
        for (var j = 0; j < ft.cubics.length; j++) {
            if (ft.kind !== "edge" && j === Math.floor(ft.cubics.length / 2)) marks.push([ft, curves.length]);
            curves.push(ft.cubics[j]);
        }
    });
    var sums = [0];
    for (i = 0; i < curves.length; i++) sums.push(sums[i] + measure(curves[i]));
    var progress = sums.map(function (s) { return s / sums[sums.length - 1]; });
    var feats = marks.map(function (m) {
        return { progress: positiveMod((progress[m[1]] + progress[m[1] + 1]) / 2, 1), feature: m[0] };
    });
    return measured(feats, curves, progress);
}

function cutItem(item, at) {
    var start = item[1], end = item[2];
    at = Math.min(Math.max(at, start), end);
    var t = cutPoint(item[0], (at - start) / (end - start) * measure(item[0]));
    var halves = split(item[0], t);
    return [[halves[0], start, at], [halves[1], at, end]];
}

function cutAndShift(mp, point) {
    if (point < DistanceEpsilon) return mp;
    var items = mp.items, n = items.length, idx = 0, i;
    while (!(items[idx][1] <= point && point <= items[idx][2])) idx++;
    var parts = cutItem(items[idx], point);
    var curves = [parts[1][0]], progress = [0];
    for (i = 1; i < n; i++) curves.push(items[(i + idx) % n][0]);
    curves.push(parts[0][0]);
    for (i = 1; i <= n; i++) progress.push(positiveMod(items[(idx + i - 1) % n][2] - point, 1));
    progress.push(1);
    var feats = mp.features.map(function (f) {
        return { progress: positiveMod(f.progress - point, 1), feature: f.feature };
    });
    return measured(feats, curves, progress);
}

function representative(cs) {
    var a = cs[0], b = cs[cs.length - 1];
    return [(a[0] + b[6]) / 2, (a[1] + b[7]) / 2];
}

// doMapping: (progress on 1, progress on 2) pairs, matching the nearest corners of the same kind.
function featureMapping(f1, f2) {
    var pairs = [], i, j;
    for (i = 0; i < f1.length; i++) {
        for (j = 0; j < f2.length; j++) {
            if (f1[i].feature.kind !== f2[j].feature.kind) continue;
            var pa = representative(f1[i].feature.cubics), pb = representative(f2[j].feature.cubics);
            pairs.push({ d: (pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1]),
                         a: i, b: j, order: pairs.length });
        }
    }
    // a stable sort, as Kotlin's sortedBy
    pairs.sort(function (x, y) { return x.d - y.d || x.order - y.order; });
    if (pairs.length === 0) return [[0, 0], [0.5, 0.5]];
    if (pairs.length === 1) {
        var p1 = f1[pairs[0].a].progress, p2 = f2[pairs[0].b].progress;
        return [[p1, p2], [(p1 + 0.5) % 1, (p2 + 0.5) % 1]];
    }
    var mapping = [], used1 = {}, used2 = {};
    for (var k = 0; k < pairs.length; k++) {
        var pr = pairs[k];
        if (used1[pr.a] || used2[pr.b]) continue;
        var a = f1[pr.a].progress, b = f2[pr.b].progress, ins = 0, n = mapping.length;
        while (ins < n && mapping[ins][0] < a) ins++;
        if (n >= 1) {
            var before = mapping[(ins + n - 1) % n], after = mapping[ins % n];
            if (progressDistance(a, before[0]) < DistanceEpsilon || progressDistance(a, after[0]) < DistanceEpsilon
                    || progressDistance(b, before[1]) < DistanceEpsilon
                    || progressDistance(b, after[1]) < DistanceEpsilon)
                continue;
            if (n > 1 && !inRange(b, before[1], after[1])) continue;
        }
        mapping.splice(ins, 0, [a, b]);
        used1[pr.a] = true;
        used2[pr.b] = true;
    }
    return mapping;
}

function linearMap(xs, ys, x) {
    var n = xs.length, i = 0;
    while (!inRange(x, xs[i], xs[(i + 1) % n])) i++;
    var j = (i + 1) % n;
    var sizeX = positiveMod(xs[j] - xs[i], 1), sizeY = positiveMod(ys[j] - ys[i], 1);
    var pos = sizeX < 0.001 ? 0.5 : positiveMod(x - xs[i], 1) / sizeX;
    return positiveMod(ys[i] + sizeY * pos, 1);
}

// Morph.match: pairs of cubics, one from each shape, to interpolate.
function match(p1, p2) {
    var m1 = measurePolygon(p1), m2 = measurePolygon(p2);
    var mapping = featureMapping(m1.features, m2.features);
    var xs = mapping.map(function (m) { return m[0]; }), ys = mapping.map(function (m) { return m[1]; });
    var cut = linearMap(xs, ys, 0);
    var bs1 = m1.items, bs2 = cutAndShift(m2, cut).items;
    var out = [], i1 = 1, i2 = 1, b1 = bs1[0], b2 = bs2[0], seg1, seg2, parts;
    while (b1 && b2) {
        var a1 = i1 === bs1.length ? 1 : b1[2];
        var a2 = i2 === bs2.length ? 1 : linearMap(ys, xs, positiveMod(b2[2] + cut, 1));
        var lo = Math.min(a1, a2);
        if (a1 > lo + AngleEpsilon) {
            parts = cutItem(b1, lo);
            seg1 = parts[0]; b1 = parts[1];
        } else {
            seg1 = b1; b1 = i1 < bs1.length ? bs1[i1] : null; i1++;
        }
        if (a2 > lo + AngleEpsilon) {
            parts = cutItem(b2, positiveMod(linearMap(xs, ys, lo) - cut, 1));
            seg2 = parts[0]; b2 = parts[1];
        } else {
            seg2 = b2; b2 = i2 < bs2.length ? bs2[i2] : null; i2++;
        }
        out.push([seg1[0], seg2[0]]);
    }
    if (b1 || b2) throw new Error("morph did not match every curve");
    return out;
}

// Morph.asCubics(t): the closed outline at progress t (t may overshoot, as a spring does).
function morph(pairs, t) {
    var out = pairs.map(function (p) {
        var c = [];
        for (var k = 0; k < 8; k++) c.push(lerp(p[0][k], p[1][k], t));
        return c;
    });
    var last = out[out.length - 1];
    out[out.length - 1] = last.slice(0, 6).concat([out[0][0], out[0][1]]);
    return out;
}

// An SVG path of the cubics scaled from the unit square to w x h.
function svgPath(cubics, w, h) {
    if (!cubics || cubics.length === 0) return "";
    function f(v) { return Math.round(v * 100) / 100; }
    var s = "M" + f(cubics[0][0] * w) + " " + f(cubics[0][1] * h);
    for (var i = 0; i < cubics.length; i++) {
        var c = cubics[i];
        s += "C" + f(c[2] * w) + " " + f(c[3] * h) + " " + f(c[4] * w) + " " + f(c[5] * h)
             + " " + f(c[6] * w) + " " + f(c[7] * h);
    }
    return s + "Z";
}

