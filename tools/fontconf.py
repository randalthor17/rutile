#!/usr/bin/env python3
"""Write a fontconfig file that adds Rutile's font directories to the system config.

The dev shell sets RUTILE_FONT_DIRS to the nix store directories of the fonts the
shell depends on, then points FONTCONFIG_FILE at the file written here, so Qt finds
them even when they are not installed system-wide. The system configuration is
included first, so every other font keeps working.

    fontconf.py write [--out PATH]    prints the path written; exit 1 if there are
                                      no usable directories in RUTILE_FONT_DIRS
"""
import argparse
import os
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

SYSTEM_CONF = "/etc/fonts/fonts.conf"


def usable_dirs(dirs, warn=lambda msg: None):
    out = []
    for d in dirs:
        if not os.path.isabs(d):
            warn(f"ignoring non-absolute font dir {d!r}")
        elif not os.path.isdir(d):
            warn(f"ignoring missing font dir {d!r}")
        elif d not in out:
            out.append(d)
    return out


def render(dirs, include=SYSTEM_CONF):
    lines = ['<?xml version="1.0"?>',
             '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">',
             "<fontconfig>"]
    if include:
        lines.append(f'  <include ignore_missing="yes">{escape(include)}</include>')
    lines += [f"  <dir>{escape(d)}</dir>" for d in dirs]
    lines.append("</fontconfig>")
    return "\n".join(lines) + "\n"


def default_out():
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(cache) / "rutile" / "fonts.conf"


def write(out, dirs, include=SYSTEM_CONF):
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out.parent, prefix=".fonts-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(render(dirs, include))
        os.chmod(tmp, 0o644)
        os.replace(tmp, out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return out


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("write")
    w.add_argument("--out")
    a = p.parse_args(argv)
    raw = [d for d in os.environ.get("RUTILE_FONT_DIRS", "").split(os.pathsep) if d]
    dirs = usable_dirs(raw, lambda m: print(f"fontconf: {m}", file=sys.stderr))
    if not dirs:
        print("fontconf: no usable directories in RUTILE_FONT_DIRS", file=sys.stderr)
        return 1
    print(write(a.out or default_out(), dirs))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
