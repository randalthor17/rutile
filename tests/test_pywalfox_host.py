"""tools/pywalfox_host.py (D52), Rutile Shell's Pywalfox native-messaging host: its replies, and the protocol over
stdio with a colors file in a temporary directory."""
import json
import os
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOST = ROOT / "tools" / "pywalfox_host.py"
sys.path.insert(0, str(ROOT / "tools"))
import pywalfox_host  # noqa: E402


class PywalfoxHost(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="rutile-pywalfox-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.colors = self.dir / "rutile" / "pywalfox.json"
        self.colors.parent.mkdir()

    def write(self, first, mode="dark"):
        cols = {f"color{i}": f"#{i:02x}{i:02x}{i:02x}" for i in range(16)}
        cols["color0"] = first
        self.colors.write_text(json.dumps({"wallpaper": "", "mode": mode, "colors": cols}))

    def test_replies(self):
        self.assertEqual(pywalfox_host.handle({"action": "debug:version"}),
                         [{"action": "debug:version", "success": True, "data": "2.9.0"}])
        self.write("#111111", "light")
        replies = pywalfox_host.handle({"action": "action:colors"}, self.colors)
        self.assertEqual(replies[0]["data"]["colors"][0], "#111111")
        self.assertEqual(len(replies[0]["data"]["colors"]), 16)
        self.assertEqual(replies[1], {"action": "theme:mode", "success": True, "data": "light"})
        css = pywalfox_host.handle({"action": "css:enable", "target": "userChrome"}, self.colors)
        self.assertEqual(css[0]["success"], False)
        self.assertEqual(css[0]["data"], "userChrome")
        self.assertEqual(pywalfox_host.handle({"action": "nope"})[0]["action"], "action:invalid")
        missing = pywalfox_host.handle({"action": "action:colors"}, self.dir / "none.json")
        self.assertEqual(len(missing), 1)
        self.assertFalse(missing[0]["success"])
        self.assertIn("No colors from Rutile Shell yet", missing[0]["error"])

    def test_over_stdio_and_pushes_changes(self):
        self.write("#222222")
        env = dict(os.environ, XDG_CACHE_HOME=str(self.dir), RUTILE_PYWALFOX_POLL="0.05")
        proc = subprocess.Popen([sys.executable, str(HOST)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env,
                                bufsize=0)          # unbuffered: select() then sees every byte not yet read
        self.addCleanup(proc.stdout.close)
        self.addCleanup(proc.kill)

        def ask(message):
            body = json.dumps(message).encode()
            proc.stdin.write(struct.pack("@I", len(body)) + body)
            proc.stdin.flush()

        def exactly(n, timeout):
            data = b""
            while len(data) < n:
                ready, _, _ = select.select([proc.stdout], [], [], timeout)
                self.assertTrue(ready, "the host sent nothing")
                chunk = proc.stdout.read(n - len(data))
                self.assertTrue(chunk, "the host closed its output")
                data += chunk
            return data

        def read(timeout=5):
            (n,) = struct.unpack("@I", exactly(4, timeout))
            return json.loads(exactly(n, timeout))

        ask({"action": "debug:version"})
        self.assertEqual(read()["data"], "2.9.0")
        ask({"action": "action:colors"})
        self.assertEqual(read()["data"]["colors"][0], "#222222")
        self.assertEqual(read()["data"], "dark")
        time.sleep(0.1)
        self.write("#333333")
        pushed = read()
        self.assertEqual((pushed["action"], pushed["data"]["colors"][0]), ("action:colors", "#333333"),
                         "a new palette reaches Firefox without being asked")
        self.assertEqual(read()["action"], "theme:mode")
        proc.stdin.close()
        self.assertEqual(proc.wait(timeout=5), 0, "Firefox closing stdin ends it")


if __name__ == "__main__":
    unittest.main()
