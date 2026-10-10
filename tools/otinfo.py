#!/usr/bin/env python3
"""Minimal OpenType reader (stdlib only): family names and variation axes.

Just enough to check that the fonts Rutile depends on report the family name and
axes recorded in theme/fonts.json. Not a general font parser.

    otinfo.py FONT.ttf        print names and axes as JSON
"""
import json
import os
import struct
import sys

NAME_IDS = {1: "family", 2: "subfamily", 4: "full", 6: "postscript", 13: "license", 14: "license_url"}


class FontError(Exception):
    pass


def _tables(data):
    if len(data) < 12:
        raise FontError("file too short for an sfnt header")
    tag = data[:4]
    if tag == b"ttcf":
        raise FontError("font collections are not supported")
    if tag not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
        raise FontError(f"not an sfnt font (header {tag!r})")
    (count,) = struct.unpack(">H", data[4:6])
    out = {}
    for i in range(count):
        off = 12 + 16 * i
        if off + 16 > len(data):
            raise FontError("truncated table directory")
        t, _, offset, length = struct.unpack(">4sIII", data[off:off + 16])
        if offset + length > len(data):
            raise FontError(f"table {t!r} extends past end of file")
        out[t.decode("latin-1")] = data[offset:offset + length]
    return out


def _names(table):
    if len(table) < 6:
        raise FontError("name table too short")
    _, count, string_off = struct.unpack(">HHH", table[:6])
    best = {}
    for i in range(count):
        rec = table[6 + 12 * i:6 + 12 * (i + 1)]
        if len(rec) < 12:
            raise FontError("truncated name records")
        platform, _enc, lang, name_id, length, offset = struct.unpack(">6H", rec)
        if name_id not in NAME_IDS:
            continue
        raw = table[string_off + offset:string_off + offset + length]
        if platform in (0, 3):
            text, rank = raw.decode("utf-16-be", "replace"), (2 if (platform == 3 and lang == 0x409) else 1)
        elif platform == 1:
            text, rank = raw.decode("mac_roman", "replace"), 0
        else:
            continue
        key = NAME_IDS[name_id]
        if key not in best or rank > best[key][0]:
            best[key] = (rank, text)
    return {k: v[1] for k, v in best.items()}


def _axes(table):
    if len(table) < 16:
        raise FontError("fvar table too short")
    _maj, _min, axes_off, _res, count, size = struct.unpack(">HHHHHH", table[:12])
    if size < 20:
        raise FontError("unexpected fvar axis record size")
    axes = {}
    for i in range(count):
        rec = table[axes_off + size * i:axes_off + size * i + 20]
        if len(rec) < 20:
            raise FontError("truncated fvar axes")
        tag, lo, default, hi = struct.unpack(">4siii", rec[:16])
        axes[tag.decode("latin-1")] = {"min": lo / 65536, "default": default / 65536, "max": hi / 65536}
    return axes


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    tables = _tables(data)
    if "name" not in tables:
        raise FontError("no name table")
    return {"names": _names(tables["name"]), "axes": _axes(tables["fvar"]) if "fvar" in tables else {}}


def find_font(file_name, dirs):
    """First path named file_name under any of dirs (searched recursively), or None."""
    for d in dirs:
        for root, _dirs, files in os.walk(d):
            if file_name in files:
                return os.path.join(root, file_name)
    return None


def font_dirs():
    """Directories from RUTILE_FONT_DIRS (os.pathsep separated)."""
    return [d for d in os.environ.get("RUTILE_FONT_DIRS", "").split(os.pathsep) if d]


def main(argv):
    if len(argv) != 1:
        print(__doc__)
        return 2
    try:
        print(json.dumps(read(argv[0]), indent=2))
    except (FontError, OSError) as e:
        print(f"otinfo: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
