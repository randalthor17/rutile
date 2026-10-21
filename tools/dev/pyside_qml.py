#!/usr/bin/env python3
"""Run Rutile's QML tests (or render the gallery) under a MODERN Qt, using PySide6's bundled Qt.

Why: Qt 6.4 (what Debian/Ubuntu ship) lacks font.variableAxes and renders differently from the
Qt 6.11 the project targets. PySide6 from PyPI carries a recent Qt, so this finds problems that only
show on a newer Qt (exact weights, the FILL axis, the filled-glyph artifacts) without a Nix session.

Optional dev dependency, not needed by `make check`:   pip install PySide6-Essentials PySide6-Addons

    pyside_qml.py suite [--only tst_spring ...]     the whole QML suite, offscreen, software renderer
    pyside_qml.py file PATH.qml [--gl]              one test file; with --gl the REAL scene graph
    pyside_qml.py render [--mode dark|light] [--out DIR]    gallery PNG slices under modern Qt

--gl needs a display. On a headless box run the whole thing under Xvfb with Mesa software OpenGL:

    xvfb-run -a -s "-screen 0 1280x800x24" python3 tools/dev/pyside_qml.py file tests/qml_gpu/tst_glyphs.qml --gl

(tools/dev/setup_sandbox.sh installs Xvfb and Mesa.) Exit code is 0 only if every test passed.
"""
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import qtws  # noqa: E402


def need_pyside():
    try:
        from PySide6 import QtCore
        from PySide6.QtQuickTest import QUICK_TEST_MAIN
    except ImportError as e:
        raise SystemExit(f"PySide6 is not installed ({e}). Run: pip install PySide6-Essentials PySide6-Addons")
    return QtCore, QUICK_TEST_MAIN


def run(ws, gl):
    QtCore, quick_test_main = need_pyside()
    env = {"QML_XHR_ALLOW_FILE_READ": "1", "QML_IMPORT_PATH": str(ws), "QML2_IMPORT_PATH": str(ws)}
    if gl:
        if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            raise SystemExit("--gl needs a display; run under xvfb-run (see --help)")
        env.setdefault("QT_QPA_PLATFORM", os.environ.get("QT_QPA_PLATFORM", "xcb"))
        env.setdefault("QSG_RHI_BACKEND", os.environ.get("QSG_RHI_BACKEND", "opengl"))
        env.setdefault("LIBGL_ALWAYS_SOFTWARE", os.environ.get("LIBGL_ALWAYS_SOFTWARE", "1"))
    else:
        env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
    os.environ.update(env)
    print(f"Qt {QtCore.qVersion()} ({'real scene graph' if gl else 'offscreen, software renderer'})", flush=True)
    return quick_test_main("rutile", argv=[sys.argv[0]], dir=str(ws / "tests"))


def cmd_suite(args):
    ws = qtws.workspace()
    try:
        if args.only:
            for f in (ws / "tests").glob("*.qml"):
                if f.stem not in args.only:
                    f.unlink()
        return run(ws, False)
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def cmd_file(args):
    src = Path(args.path).resolve()
    if not src.exists():
        raise SystemExit(f"no such file: {src}")
    ws = qtws.workspace()
    try:
        for f in (ws / "tests").glob("*.qml"):
            f.unlink()
        shutil.copy(src, ws / "tests" / src.name)
        return run(ws, args.gl)
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def cmd_render(args):
    ws = qtws.workspace()
    try:
        for f in (ws / "tests").glob("*.qml"):
            f.unlink()
        shutil.copy(ROOT / "tests" / "qml_render" / "tst_render.qml", ws / "tests" / "tst_render.qml")
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob(f"gallery-{args.mode}-*.png"):
            old.unlink()
        (ws / "data" / "render.json").write_text(json.dumps(
            {"out": str(out / f"gallery-{args.mode}.png"), "mode": args.mode, "width": 1180}))
        rc = run(ws, False)
        for p in sorted(out.glob(f"gallery-{args.mode}-*.png")):
            print(p)
        return rc
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def main(argv):
    import argparse
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("suite")
    s.add_argument("--only", nargs="*")
    f = sub.add_parser("file")
    f.add_argument("path")
    f.add_argument("--gl", action="store_true")
    r = sub.add_parser("render")
    r.add_argument("--mode", default="dark", choices=("dark", "light"))
    r.add_argument("--out", default="render-modern")
    a = p.parse_args(argv)
    return {"suite": cmd_suite, "file": cmd_file, "render": cmd_render}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
