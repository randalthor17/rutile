#!/usr/bin/env python3
"""Render and validate Rutile's palette.json (the shell's only color input).

palette.json (format 1) is the stable interface between whatever produces
colors (today: matugen) and the QML `Colors` singleton. Swapping the producer
must not require touching QML.

    palette.py render --seed '#134aae' [--scheme scheme-tonal-spot]
                      [--mode dark|light] [--contrast 0] --out PATH
    palette.py validate PATH

`render` runs matugen into a temp prefix, validates the result and replaces
PATH atomically, so a file watcher never sees a partial or invalid palette and
a failed render leaves the previous palette untouched.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "theme" / "matugen.toml"
TEMPLATE_OUT = ROOT / "theme" / "out" / "palette.json"  # as named in matugen.toml
HEX = re.compile(r"^#[0-9a-f]{6}$")
SCHEMES = ("scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad",
           "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-tonal-spot",
           "scheme-vibrant")


class PaletteError(Exception):
    pass


def required_roles():
    return json.loads((ROOT / "theme" / "roles.json").read_text())["roles"]


def validate(doc):
    """Return a list of problems (empty list means valid)."""
    errs = []
    if not isinstance(doc, dict):
        return ["palette is not an object"]
    if doc.get("format") != 1:
        errs.append(f"format must be 1, got {doc.get('format')!r}")
    if doc.get("mode") not in ("dark", "light"):
        errs.append(f"mode must be dark or light, got {doc.get('mode')!r}")
    if not HEX.match(str(doc.get("source_color", ""))):
        errs.append(f"bad source_color {doc.get('source_color')!r}")
    colors = doc.get("colors")
    if not isinstance(colors, dict) or set(colors) != {"dark", "light"}:
        return errs + ["colors must have exactly the keys dark and light"]
    want = set(required_roles())
    for mode in ("dark", "light"):
        table = colors[mode]
        if not isinstance(table, dict):
            errs.append(f"colors.{mode} is not an object")
            continue
        missing = want - set(table)
        if missing:
            errs.append(f"colors.{mode} missing roles: {sorted(missing)}")
        for role, val in table.items():
            if role == "source_color":
                continue
            if role not in want:
                errs.append(f"colors.{mode} has unexpected role {role!r}")
            if not HEX.match(str(val)):
                errs.append(f"colors.{mode}.{role} is not #rrggbb: {val!r}")
    return errs


def render(seed, scheme, mode, contrast, out, matugen="matugen", image=None):
    """Render from a seed color, or from an image (a wallpaper: matugen picks its dominant color); exactly one."""
    if scheme not in SCHEMES:
        raise PaletteError(f"unknown scheme {scheme!r}")
    if (seed is None) == (image is None):
        raise PaletteError("give a seed or an image, not both or neither")
    if image is not None and not Path(image).is_file():
        raise PaletteError(f"image not found: {image}")
    if seed is not None and not re.fullmatch(r"#[0-9a-fA-F]{6}", seed):
        raise PaletteError(f"seed must be #rrggbb, got {seed!r}")
    if not -1 <= contrast <= 1:
        raise PaletteError("contrast must be within -1..1")
    if shutil.which(matugen) is None and not os.path.exists(matugen):
        raise PaletteError(f"matugen not found ({matugen})")
    with tempfile.TemporaryDirectory() as prefix:
        source = ["image", str(Path(image).resolve())] if image is not None else ["color", "hex", seed]
        # --source-color-index 0: an image's most dominant color, never matugen's interactive choice
        pick = ["--source-color-index", "0"] if image is not None else []
        cmd = [matugen, "-q", "-c", str(CONFIG), "-p", prefix, *source,
               "-t", scheme, "-m", mode, "--contrast", str(contrast), *pick]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        produced = Path(prefix) / str(TEMPLATE_OUT).lstrip("/")
        if proc.returncode != 0 or not produced.exists():
            raise PaletteError(f"matugen failed (exit {proc.returncode}): {proc.stderr.strip()[-300:]}")
        try:
            doc = json.loads(produced.read_text())
        except json.JSONDecodeError as e:
            raise PaletteError(f"matugen produced invalid JSON: {e}")
    errs = validate(doc)
    if errs:
        raise PaletteError("invalid palette: " + "; ".join(errs))
    # how it was made, so tools/apptheme.py can give other apps the same colors (D52)
    doc["scheme"] = scheme
    doc["contrast"] = contrast
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out.parent, prefix=".palette-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(doc, f, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o644)
        os.replace(tmp, out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    src = r.add_mutually_exclusive_group(required=True)
    src.add_argument("--seed", help="a #rrggbb seed color")
    src.add_argument("--image", help="an image, e.g. the wallpaper: its dominant color is the seed")
    r.add_argument("--scheme", default="scheme-tonal-spot", choices=SCHEMES)
    r.add_argument("--mode", default="dark", choices=("dark", "light"))
    r.add_argument("--contrast", type=float, default=0.0)
    r.add_argument("--out", required=True)
    r.add_argument("--matugen", default="matugen")
    v = sub.add_parser("validate")
    v.add_argument("path")
    a = p.parse_args(argv)
    try:
        if a.cmd == "render":
            render(a.seed, a.scheme, a.mode, a.contrast, a.out, a.matugen, image=a.image)
            print(f"wrote {a.out}")
        else:
            errs = validate(json.loads(Path(a.path).read_text()))
            for e in errs:
                print(e, file=sys.stderr)
            return 1 if errs else 0
    except PaletteError as e:
        print(f"palette error: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
