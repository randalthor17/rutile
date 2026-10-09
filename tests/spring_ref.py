"""Independent reference for the spring math used by SpringMath.js.

`analytic` is the closed form (same model, written separately in Python);
`rk4` numerically integrates x'' = -k (x - target) - 2 z sqrt(k) x' and is used
to prove the closed form correct. Test cases for the JS come from `analytic`.
"""
import math


def analytic(t, x0, v0, target, k, z):
    d0 = x0 - target
    if t <= 0:
        return x0, v0
    w0 = math.sqrt(k)
    if abs(z - 1) < 1e-9:
        b = v0 + w0 * d0
        e = math.exp(-w0 * t)
        return target + (d0 + b * t) * e, (b - w0 * (d0 + b * t)) * e
    if z < 1:
        wd = w0 * math.sqrt(1 - z * z)
        a = z * w0
        B = (v0 + a * d0) / wd
        env = math.exp(-a * t)
        c, s = math.cos(wd * t), math.sin(wd * t)
        return (target + env * (d0 * c + B * s),
                env * ((B * wd - a * d0) * c - (d0 * wd + a * B) * s))
    q = w0 * math.sqrt(z * z - 1)
    r1, r2 = -z * w0 + q, -z * w0 - q
    c2 = (v0 - r1 * d0) / (r2 - r1)
    c1 = d0 - c2
    return (target + c1 * math.exp(r1 * t) + c2 * math.exp(r2 * t),
            c1 * r1 * math.exp(r1 * t) + c2 * r2 * math.exp(r2 * t))


def rk4(t, x0, v0, target, k, z, steps=20000):
    c = 2 * z * math.sqrt(k)
    h = t / steps
    x, v = x0, v0
    acc = lambda x, v: -k * (x - target) - c * v
    for _ in range(steps):
        k1x, k1v = v, acc(x, v)
        k2x, k2v = v + h / 2 * k1v, acc(x + h / 2 * k1x, v + h / 2 * k1v)
        k3x, k3v = v + h / 2 * k2v, acc(x + h / 2 * k2x, v + h / 2 * k2v)
        k4x, k4v = v + h * k3v, acc(x + h * k3x, v + h * k3v)
        x += h / 6 * (k1x + 2 * k2x + 2 * k3x + k4x)
        v += h / 6 * (k1v + 2 * k2v + 2 * k3v + k4v)
    return x, v


# (stiffness, damping ratio) pairs: every M3 token pair plus overdamped and near-critical.
PAIRS = [(800, 0.6), (380, 0.8), (200, 0.8), (3800, 1), (1600, 1), (800, 1),
         (1400, 0.9), (700, 0.9), (300, 0.9), (400, 1.5), (500, 3.0), (600, 0.999999)]
STARTS = [(0.0, 0.0, 1.0), (0.0, 5.0, 1.0), (10.0, -3.0, 4.0), (-2.0, 0.0, 0.0)]
TIMES = [0.0, 0.01, 0.05, 0.2, 1.0]


def cases():
    out = []
    for k, z in PAIRS:
        for x0, v0, target in STARTS:
            for t in TIMES:
                x, v = analytic(t, x0, v0, target, k, z)
                out.append({"k": k, "z": z, "x0": x0, "v0": v0, "target": target, "t": t, "x": x, "v": v})
    return out
