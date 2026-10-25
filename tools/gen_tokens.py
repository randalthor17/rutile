#!/usr/bin/env python3
"""Generate tokens/m3e.json from the vendored Material 3 token sources.

The Kotlin files in tokens/sources/ come from androidx Compose Material3
(Apache-2.0). This script parses them and fails loudly on anything it does
not understand, so a source update can never silently change a token.

    gen_tokens.py            write tokens/m3e.json
    gen_tokens.py --check    exit 1 if tokens/m3e.json is stale or sources
                             do not match manifest.json checksums
    gen_tokens.py --refresh  re-download sources, update manifest (network)
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tokens" / "sources"
OUT = ROOT / "tokens" / "m3e.json"

WEIGHTS = {"WeightRegular": 400, "WeightMedium": 500, "WeightBold": 700}
FONTS = {"Plain": "plain", "Brand": "brand"}
STYLE_SUFFIXES = ("LineHeight", "Font", "Size", "Tracking", "Weight")


class TokenError(Exception):
    pass


def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def num(text):
    return float(text.rstrip("f")) if "." in text else int(text.rstrip("f"))


def clean(v):
    """Render integral floats as ints so JSON stays stable and readable."""
    return int(v) if isinstance(v, float) and v.is_integer() else v


def parse_springs(text):
    out = {}
    for kind, axis, prop, val in re.findall(
        r"const val Spring(Default|Fast|Slow)(Spatial|Effects)(Damping|Stiffness) = ([\d.]+)f", text
    ):
        key = "damping_ratio" if prop == "Damping" else "stiffness"
        out.setdefault(axis.lower(), {}).setdefault(kind.lower(), {})[key] = clean(num(val))
    for axis in ("spatial", "effects"):
        for kind in ("fast", "default", "slow"):
            got = out.get(axis, {}).get(kind, {})
            if set(got) != {"damping_ratio", "stiffness"}:
                raise TokenError(f"incomplete spring {axis}/{kind}: {got}")
    return out


def parse_durations(text):
    d = {snake(n): clean(num(v)) for n, v in re.findall(r"const val Duration(\w+) = ([\d.]+)", text)}
    if len(d) != 16:
        raise TokenError(f"expected 16 durations, found {len(d)}")
    return d


def parse_easings(text):
    out = {}
    for name, args in re.findall(
        r"inline val Easing(\w+)CubicBezier: [^\n]*\n\s*get\(\) = CubicBezierEasing\(([^)]*)\)", text
    ):
        vals = [clean(num(a.strip())) for a in args.split(",")]
        if len(vals) != 4:
            raise TokenError(f"bad easing {name}: {args}")
        out[snake(name)] = vals
    if len(out) != 10:
        raise TokenError(f"expected 10 easings, found {len(out)}")
    return out


def parse_corners(text):
    out = {
        snake(n): clean(num(v))
        for n, v in re.findall(r"val CornerValue(\w+) = CornerSize\((\d+(?:\.\d+)?)\.dp\)", text)
    }
    if "val CornerFull = CircleShape" not in text:
        raise TokenError("CornerFull is no longer CircleShape")
    if len(out) != 9:
        raise TokenError(f"expected 9 corner values, found {len(out)}")
    out["full"] = "full"
    return out


def parse_elevation(text):
    out = {
        f"level{n}": clean(num(v))
        for n, v in re.findall(r"inline val Level(\d): [^\n]*\n\s*get\(\) = (\d+(?:\.\d+)?)\.dp", text)
    }
    if len(out) != 6:
        raise TokenError(f"expected 6 elevation levels, found {len(out)}")
    return out


def parse_type(text):
    raw = {}
    pat = re.compile(r"inline val (\w+?)(LineHeight|Font|Size|Tracking|Weight): [^\n]*\n\s*get\(\) = ([^\n]+)")
    for style, prop, expr in pat.findall(text):
        expr = expr.strip()
        if prop == "Font":
            m = re.fullmatch(r"TypefaceTokens\.(\w+)", expr)
            if not m or m.group(1) not in FONTS:
                raise TokenError(f"unknown font expr {expr!r} for {style}")
            val = FONTS[m.group(1)]
        elif prop == "Weight":
            m = re.fullmatch(r"TypefaceTokens\.(\w+)", expr)
            if not m or m.group(1) not in WEIGHTS:
                raise TokenError(f"unknown weight expr {expr!r} for {style}")
            val = WEIGHTS[m.group(1)]
        else:
            m = re.fullmatch(r"(-?\d+(?:\.\d+)?)\.sp", expr)
            if not m:
                raise TokenError(f"unknown unit expr {expr!r} for {style}{prop}")
            val = clean(num(m.group(1)))
        key = {"LineHeight": "line_height_sp", "Size": "size_sp", "Tracking": "tracking_sp",
               "Font": "font", "Weight": "weight"}[prop]
        raw.setdefault(snake(style), {})[key] = val
    for style, props in raw.items():
        if set(props) != {"font", "line_height_sp", "size_sp", "tracking_sp", "weight"}:
            raise TokenError(f"incomplete type style {style}: {sorted(props)}")
    if len(raw) != 30:
        raise TokenError(f"expected 30 type styles, found {len(raw)}")
    return raw


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest():
    return json.loads((SRC / "manifest.json").read_text())


def verify_sources(manifest):
    for name, want in manifest["files"].items():
        got = sha256(SRC / name)
        if got != want:
            raise TokenError(f"{name} checksum mismatch (manifest {want[:12]}, file {got[:12]})")


def build():
    manifest = load_manifest()
    verify_sources(manifest)
    read = lambda n: (SRC / n).read_text()
    sources = {
        key: {"url": manifest["base_url"] + fname, "sha256": manifest["files"][fname]}
        for key, fname in {
            "expressive_motion": "ExpressiveMotionTokens.kt",
            "standard_motion": "StandardMotionTokens.kt",
            "motion": "MotionTokens.kt",
            "shape": "ShapeTokens.kt",
            "type": "TypeScaleTokens.kt",
            "elevation": "ElevationTokens.kt",
        }.items()
    }
    return {
        "_meta": {
            "generator": "tools/gen_tokens.py",
            "note": "Generated from androidx Compose Material3 token sources (Apache-2.0), "
                    "not from m3.material.io pages. Do not edit by hand.",
            "ref": manifest["ref"],
            "fetched": manifest["fetched"],
            "sources": sources,
        },
        "shape": {"src": "shape", "corner_dp": parse_corners(read("ShapeTokens.kt"))},
        "motion": {
            "src": ["expressive_motion", "standard_motion", "motion"],
            "expressive": parse_springs(read("ExpressiveMotionTokens.kt")),
            "standard": parse_springs(read("StandardMotionTokens.kt")),
            "duration_ms": parse_durations(read("MotionTokens.kt")),
            "easing_cubic_bezier": parse_easings(read("MotionTokens.kt")),
        },
        "elevation": {"src": "elevation", "dp": parse_elevation(read("ElevationTokens.kt"))},
        "type": {"src": "type", "styles": parse_type(read("TypeScaleTokens.kt"))},
    }


def render(tokens):
    return json.dumps(tokens, indent=2, sort_keys=True) + "\n"


def refresh():
    import base64
    import urllib.request
    manifest = load_manifest()
    from urllib.parse import urljoin
    for name in manifest["files"]:
        url = urljoin(manifest["base_url"], manifest.get("paths", {}).get(name, name))
        with urllib.request.urlopen(url, timeout=30) as r:
            data = r.read()
        if "format=TEXT" in url:          # googlesource (AOSP) serves raw files base64-encoded
            data = base64.b64decode(data)
        (SRC / name).write_bytes(data)
        manifest["files"][name] = sha256(SRC / name)
    (SRC / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("sources refreshed; review the diff, then run gen_tokens.py")


def main(argv):
    try:
        if "--refresh" in argv:
            refresh()
            return 0
        text = render(build())
        if "--check" in argv:
            if not OUT.exists() or OUT.read_text() != text:
                print("tokens/m3e.json is stale: run tools/gen_tokens.py", file=sys.stderr)
                return 1
            print("tokens/m3e.json is up to date")
            return 0
        OUT.write_text(text)
        print(f"wrote {OUT.relative_to(ROOT)}")
        return 0
    except TokenError as e:
        print(f"token error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
