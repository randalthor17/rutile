#!/usr/bin/env python3
"""Rutile Shell's native-messaging host for the Pywalfox Firefox extension (D52), so Firefox wears the shell's
colors without Pywalfox's own program. Firefox starts it (the manifest tools/apptheme.py installs) and talks to it
over stdin/stdout: each message is a 4-byte native-endian length and that much UTF-8 JSON.

It answers the extension's requests (`debug:version`, `action:colors`; the custom-CSS ones are not supported and
say so) with the 16 colors apptheme.py renders into $XDG_CACHE_HOME/rutile/pywalfox.json, and sends the colors
again, with the dark or light mode, whenever that file changes, so a new wallpaper reaches Firefox at once.
Written from Pywalfox's protocol (pywalfox-native 2.9, MPL-2.0); none of its code.
"""
import json
import os
import struct
import sys
import threading
import time
from pathlib import Path

VERSION = "2.9.0"                    # the protocol version the extension expects
COLORS = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "rutile" / "pywalfox.json"
POLL = float(os.environ.get("RUTILE_PYWALFOX_POLL", "1"))

_out = threading.Lock()


def send(message, stream=None):
    stream = stream or sys.stdout.buffer
    body = json.dumps(message).encode("utf-8")
    with _out:
        stream.write(struct.pack("@I", len(body)))
        stream.write(body)
        stream.flush()


def receive(stream=None):
    stream = stream or sys.stdin.buffer
    head = stream.read(4)
    if len(head) < 4:
        return None
    (length,) = struct.unpack("@I", head)
    return json.loads(stream.read(length).decode("utf-8"))


def reply(action, data=None, success=True, error=None):
    m = {"action": action, "success": success}
    if data is not None:
        m["data"] = data
    if error is not None:
        m["error"] = error
    return m


def colors_message(path=None):
    path = Path(path or COLORS)
    try:
        doc = json.loads(path.read_text())
        colors = [doc["colors"][f"color{i}"] for i in range(16)]
    except (OSError, ValueError, KeyError, TypeError) as e:
        return reply("action:colors", success=False, error=f"No colors from Rutile Shell yet ({path}: {e})"), None
    return reply("action:colors", {"colors": colors, "wallpaper": doc.get("wallpaper", "")}), doc.get("mode")


def handle(message, path=None):
    """The replies to one message from the extension."""
    action = (message or {}).get("action")
    if action == "debug:version":
        return [reply("debug:version", VERSION)]
    if action == "action:colors":
        m, mode = colors_message(path)
        return [m] + ([reply("theme:mode", mode)] if mode in ("dark", "light") else [])
    if action in ("css:enable", "css:disable", "css:font:size"):
        return [reply(action, message.get("target"), success=False,
                      error="Rutile Shell's host does not change Firefox's CSS")]
    return [reply("action:invalid", success=False)]


def watch(path=None, stop=None):
    """Sends the colors again whenever the file changes."""
    path = Path(path or COLORS)
    seen = path.stat().st_mtime_ns if path.exists() else None
    while not (stop and stop.is_set()):
        time.sleep(POLL)
        now = path.stat().st_mtime_ns if path.exists() else None
        if now != seen and now is not None:
            seen = now
            m, mode = colors_message(path)
            send(m)
            if mode in ("dark", "light"):
                send(reply("theme:mode", mode))
        seen = now


def main():
    threading.Thread(target=watch, daemon=True).start()
    while True:
        message = receive()
        if message is None:
            return 0
        for r in handle(message):
            send(r)


if __name__ == "__main__":
    sys.exit(main())
