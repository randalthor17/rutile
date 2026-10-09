// Exact solution of a damped spring (mass 1) moving toward a fixed target.
// stiffness and dampingRatio are the Material 3 / Compose parameters, so M3E
// motion tokens apply unchanged. Time is in seconds.
.pragma library

// Returns {x, v}: position and velocity after t seconds, starting from
// position x0 with velocity v0, pulled toward target.
function evaluate(t, x0, v0, target, stiffness, dampingRatio) {
    if (!(stiffness > 0) || !(dampingRatio >= 0)) {
        return { x: target, v: 0 };
    }
    var d0 = x0 - target;
    if (t <= 0) {
        return { x: x0, v: v0 };
    }
    var w0 = Math.sqrt(stiffness);
    var z = dampingRatio;
    var d, v;
    if (Math.abs(z - 1) < 1e-9) {
        // critically damped
        var b = v0 + w0 * d0;
        var e = Math.exp(-w0 * t);
        d = (d0 + b * t) * e;
        v = (b - w0 * (d0 + b * t)) * e;
    } else if (z < 1) {
        // underdamped
        var wd = w0 * Math.sqrt(1 - z * z);
        var a = z * w0;
        var B = (v0 + a * d0) / wd;
        var env = Math.exp(-a * t);
        var c = Math.cos(wd * t);
        var s = Math.sin(wd * t);
        d = env * (d0 * c + B * s);
        v = env * ((B * wd - a * d0) * c - (d0 * wd + a * B) * s);
    } else {
        // overdamped
        var q = w0 * Math.sqrt(z * z - 1);
        var r1 = -z * w0 + q;
        var r2 = -z * w0 - q;
        var c2 = (v0 - r1 * d0) / (r2 - r1);
        var c1 = d0 - c2;
        var e1 = Math.exp(r1 * t);
        var e2 = Math.exp(r2 * t);
        d = c1 * e1 + c2 * e2;
        v = c1 * r1 * e1 + c2 * r2 * e2;
    }
    return { x: target + d, v: v };
}
