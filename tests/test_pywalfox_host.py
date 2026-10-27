"""native/pywalfox-host.c (D54), Rutile Shell's Pywalfox native-messaging host, built here with AddressSanitizer
and UndefinedBehaviorSanitizer (any finding aborts it, and the test fails): the protocol over stdio, a strict
reading of what Firefox sends, framing errors, a colors file that is missing, short, broken or hostile, the
push when it changes, and seeded fuzzing of both the messages and the file. Its colors file and HOME are in a
temporary directory."""
import json
import os
import random
import select
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "native" / "pywalfox-host.c"
CC = shutil.which(os.environ.get("CC", "cc")) or shutil.which("gcc")
SANITIZE = ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
FLAGS = ["-std=c11", "-O1", "-g", "-Wall", "-Wextra", "-Werror", "-Wconversion", "-Wshadow"]
ASAN_ENV = {"ASAN_OPTIONS": "abort_on_error=1:detect_leaks=1:strict_string_checks=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"}
COLORS = [f"#{i:02x}{i:02x}{i:02x}" for i in range(16)]


def conf(colors=COLORS, mode="dark", extra=""):
    lines = [f"mode {mode}"] if mode else []
    lines += [f"color{i} {c}" for i, c in enumerate(colors)]
    return "# Rutile's colors\n" + "\n".join(lines) + "\n" + extra


@unittest.skipUnless(CC, "no C compiler; the Firefox host's tests SKIPPED")
class Host(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = Path(tempfile.mkdtemp(prefix="rutile-host-build-"))
        cls.binary = cls.build / "host"
        r = subprocess.run([CC, *FLAGS, *SANITIZE, "-o", str(cls.binary), str(SOURCE)], capture_output=True, text=True)
        if r.returncode != 0:
            raise AssertionError("the host does not build with sanitizers:\n" + r.stderr)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.build, ignore_errors=True)

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="rutile-host-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.colors = self.dir / "cache" / "rutile" / "pywalfox.conf"
        self.colors.parent.mkdir(parents=True)

    def start(self, poll="0.05"):
        env = dict(os.environ, XDG_CACHE_HOME=str(self.dir / "cache"), HOME=str(self.dir), RUTILE_PYWALFOX_POLL=poll,
                   **ASAN_ENV)
        p = subprocess.Popen([str(self.binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env, bufsize=0)
        self.addCleanup(self.stop, p)
        return p

    def stop(self, p):
        if p.poll() is None:
            p.kill()
        p.wait(timeout=10)
        for f in (p.stdin, p.stdout, p.stderr):
            if f and not f.closed:
                f.close()

    def frame(self, p, body):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        p.stdin.write(struct.pack("@I", len(data)) + data)
        p.stdin.flush()

    def exactly(self, p, n, timeout):
        data = b""
        while len(data) < n:
            ready, _, _ = select.select([p.stdout], [], [], timeout)
            self.assertTrue(ready, "the host sent nothing")
            chunk = p.stdout.read(n - len(data))
            if not chunk:
                self.fail("the host closed its output: " + self.died(p))
            data += chunk
        return data

    def read(self, p, timeout=5):
        (n,) = struct.unpack("@I", self.exactly(p, 4, timeout))
        body = self.exactly(p, n, timeout)
        return json.loads(body.decode("utf-8"))           # strict: it must be valid UTF-8 and JSON

    def nothing(self, p, wait=0.3):
        ready, _, _ = select.select([p.stdout], [], [], wait)
        self.assertFalse(ready, "the host sent something unasked")

    def died(self, p):
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            return "still running"
        ready, _, _ = select.select([p.stderr], [], [], 1)     # never block on it (a symbolizer may hold it)
        err = p.stderr.read1(65536) if ready else b""
        return f"exit {p.returncode}: {err.decode(errors='replace')[-2000:]}"

    def ends(self, p, code):
        p.stdin.close()
        try:
            got = p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.fail("the host did not end")
        err = p.stderr.read().decode(errors="replace")
        self.assertEqual(got, code, err[-2000:])
        self.assertNotIn("Sanitizer", err)
        self.assertNotIn("runtime error", err)

    def ask(self, p, message):
        self.frame(p, message)
        return self.read(p)

    # ---- the protocol ----
    def test_version_colors_mode(self):
        self.colors.write_text(conf(mode="light"))
        p = self.start()
        self.assertEqual(self.ask(p, {"action": "debug:version"}),
                         {"action": "debug:version", "success": True, "data": "2.9.0"})
        self.assertEqual(self.ask(p, {"action": "action:colors"}),
                         {"action": "action:colors", "success": True, "data": {"colors": COLORS, "wallpaper": ""}})
        self.assertEqual(self.read(p), {"action": "theme:mode", "success": True, "data": "light"})
        self.ends(p, 0)

    def test_css_is_refused_and_unknown_is_invalid(self):
        p = self.start()
        r = self.ask(p, {"action": "css:enable", "target": "userChrome"})
        self.assertEqual((r["action"], r["success"], r["data"]), ("css:enable", False, "userChrome"))
        self.assertIn("does not change Firefox's CSS", r["error"])
        self.assertNotIn("data", self.ask(p, {"action": "css:font:size", "size": 12}), "no target: no data")
        invalid = {"action": "action:invalid", "success": False}
        for message in [{"action": "nope"}, {"target": "x"}, {"action": 5}, {"action": None}, [], "x", 1, None,
                        {"action": "debug:version", "nested": {"action": "action:colors"}} | {"action": "x"}]:
            self.assertEqual(self.ask(p, message), invalid, message)
        self.ends(p, 0)

    def test_strict_json(self):
        p = self.start()
        version = {"action": "debug:version", "success": True, "data": "2.9.0"}
        good = [b'{"action":"debug:version"}', b' \n{ "action" : "debug:version" } \t',
                b'{"action":"debug\\u003aversion"}', b'{"x":[1,-2.5e+3,0.1,true,false,null,{"a":[]}],"action":"debug:version"}',
                b'{"action":"x","action":"debug:version"}', b'{"target":"\\ud83d\\ude00","action":"debug:version"}',
                ('{"t":"' + "é😀" + '","action":"debug:version"}').encode()]
        for body in good:
            self.assertEqual(self.ask(p, body), version, body)
        bad = [b"", b"{", b"}", b'{"action":"debug:version"', b'{"action":"debug:version"}x', b'{"action" "x"}',
               b'{"action":"debug:version",}', b"{'action':'debug:version'}", b'{"action":"\\x"}',
               b'{"action":"\\ud83d"}', b'{"action":"\\udc00"}', b'{"action":"\\u12"}', b'{"a":01,"action":"debug:version"}',
               b'{"a":1.,"action":"debug:version"}', b'{"a":-,"action":"debug:version"}', b'{"a":tru,"action":"debug:version"}',
               b'{"action":"debug:\x01version"}', b'{"action":"\xff"}', b'{"action":"\xc0\xaf"}', b'{"action":"\xed\xa0\x80"}',
               b"\x00\x00\x00\x00", b'{"a":' + b"[" * 64 + b"]" * 64 + b',"action":"debug:version"}',
               b'{"action":"' + b"a" * 300 + b'"}',
               # broken text elsewhere in a message that would otherwise be good: still refused
               b'{"x":"a\x01b","action":"debug:version"}', b'{"x":"\xed\xa0\x80","action":"debug:version"}',
               b'{"x":"\xe0\x80\xaf","action":"debug:version"}', b'{"x":"\xf4\x90\x80\x80","action":"debug:version"}',
               b'{"x":"\\udc00","action":"debug:version"}', b'{"x":"\\ud83dx","action":"debug:version"}']
        for body in bad:
            self.assertEqual(self.ask(p, body)["action"], "action:invalid", body[:80])
        self.assertEqual(self.ask(p, b'{"a":' + b"[" * 62 + b"]" * 62 + b',"action":"debug:version"}'), version,
                         "nesting up to the limit is fine")
        # escaped keys and values right at their buffers' size (16-byte key, 256-byte field) and one past
        for n in (15, 16, 17):
            key = b"\\u0061" * n
            self.assertEqual(self.ask(p, b'{"' + key + b'":1,"action":"debug:version"}'), version, n)
        for n in (254, 255, 256, 257):
            self.assertEqual(self.ask(p, b'{"target":"' + b"\\u00e9" * (n // 2) + b'","action":"debug:version"}'),
                             version, n)
        self.ends(p, 0)

    # ---- framing ----
    def test_end_of_input(self):
        self.ends(self.start(), 0)

    def test_a_frame_too_long_ends_it(self):
        p = self.start()
        p.stdin.write(struct.pack("@I", (1 << 20) + 1))
        p.stdin.flush()
        self.ends(p, 1)

    def test_a_huge_frame_header_ends_it_at_once(self):
        p = self.start()
        p.stdin.write(b"\xff\xff\xff\xff")             # 4 GB announced; stdin stays open
        p.stdin.flush()
        try:
            code = p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.fail("it waited for 4 GB instead of stopping")
        self.assertEqual(code, 1)
        self.assertNotIn("Sanitizer", p.stderr.read().decode(errors="replace"))

    def test_a_nesting_bomb_is_refused_not_a_stack_overflow(self):
        p = self.start()
        for body in [b"[" * 500000, b'{"a":' * 200000, b'{"x":' + b"[" * 100000 + b',"action":"debug:version"}']:
            self.assertEqual(self.ask(p, body)["action"], "action:invalid")
        self.ends(p, 0)

    def test_a_cut_frame_ends_it(self):
        for data in [b"\x05\x00", struct.pack("@I", 20) + b'{"action":']:
            p = self.start()
            p.stdin.write(data)
            self.ends(p, 1)

    def test_firefox_gone_while_it_writes(self):
        p = self.start()
        p.stdout.close()
        self.frame(p, {"action": "debug:version"})
        try:
            p.stdin.close()
        except BrokenPipeError:
            pass
        self.assertEqual(p.wait(timeout=10), 1, "a write to nobody ends it, quietly (no SIGPIPE death)")
        self.assertNotIn("Sanitizer", p.stderr.read().decode(errors="replace"))

    def test_a_large_frame_within_the_limit(self):
        p = self.start()
        body = b'{"pad":"' + b"x" * (1 << 19) + b'","action":"debug:version"}'
        self.assertEqual(self.ask(p, body)["data"], "2.9.0")
        self.ends(p, 0)

    # ---- the colors file ----
    def test_file_problems_are_reported(self):
        p = self.start(poll="60")
        r = self.ask(p, {"action": "action:colors"})
        self.assertFalse(r["success"])
        self.assertIn("No colors from Rutile Shell yet", r["error"])
        cases = {"short": conf(COLORS[:15]), "bad hex": conf(COLORS[:3] + ["#12345g"] + COLORS[4:]),
                 "no hash": conf(COLORS[:1] + ["123456"] + COLORS[2:]), "too long": "x" * (64 * 1024 + 1),
                 "binary": conf() + "\x00junk\n", "out of range": conf(COLORS[:15]) + "color16 #000000\n"}
        for name, text in cases.items():
            self.colors.write_text(text)
            r = self.ask(p, {"action": "action:colors"})
            self.assertFalse(r["success"], name)
            self.assertTrue(r["error"], name)
        self.colors.write_text(conf(mode="purple", extra="junk line\n#color0 #ffffff\ncolor0x #ffffff\n\r\n"))
        r = self.ask(p, {"action": "action:colors"})
        self.assertEqual(r["data"]["colors"], COLORS, "junk ignored, nothing shifted")
        self.nothing(p, 0.2)                      # an unknown mode: no theme:mode
        self.colors.write_text(conf().replace("\n", "\r\n"))
        self.assertTrue(self.ask(p, {"action": "action:colors"})["success"], "CRLF lines")
        self.read(p)
        self.ends(p, 0)

    def test_hostile_wallpaper_is_escaped(self):
        nasty = 'a"b\\c\td\x1fe\x7f' + "é" + "\U0001F600"
        self.colors.write_bytes((conf(extra=f"wallpaper {nasty}\n")).encode() + b"wallpaper2 x\n")
        p = self.start(poll="60")
        r = self.ask(p, {"action": "action:colors"})
        self.assertEqual(r["data"]["wallpaper"], nasty)
        self.read(p)
        self.colors.write_bytes(conf().encode() + b"wallpaper \xff\xfe\xc3(\n")
        r = self.ask(p, {"action": "action:colors"})
        self.assertEqual(r["data"]["wallpaper"], "���(", "invalid UTF-8 becomes U+FFFD")
        self.read(p)
        self.ends(p, 0)

    def test_pushes_when_the_file_changes(self):
        self.colors.write_text(conf())
        p = self.start()
        self.nothing(p)
        time.sleep(0.05)
        self.colors.write_text(conf(["#ff0000"] + COLORS[1:]))
        r = self.read(p)
        self.assertEqual((r["action"], r["data"]["colors"][0]), ("action:colors", "#ff0000"), "unasked")
        self.assertEqual(self.read(p)["action"], "theme:mode")
        self.colors.unlink()
        self.nothing(p, 0.4)                      # gone: nothing to send
        self.colors.write_text(conf(["#00ff00"] + COLORS[1:]))
        self.assertEqual(self.read(p)["data"]["colors"][0], "#00ff00", "back: sent")
        self.read(p)
        self.ends(p, 0)

    # ---- fuzzing ----
    def test_fuzzed_messages(self):
        rng = random.Random(1234)
        seeds = [b'{"action":"debug:version"}', b'{"action":"css:enable","target":"userChrome"}',
                 b'{"x":[1,{"y":"\\u00e9"}],"action":"nope"}', b'["\\ud83d\\ude00", 1e5, null]']
        p = self.start(poll="60")
        for i in range(3000):
            kind = i % 3
            if kind == 0:
                body = bytes(rng.randrange(256) for _ in range(rng.randrange(64)))
            else:
                body = bytearray(rng.choice(seeds))
                for _ in range(rng.randrange(1, 6)):
                    op = rng.randrange(3)
                    pos = rng.randrange(len(body) + 1)
                    if op == 0 and body:
                        del body[min(pos, len(body) - 1)]
                    elif op == 1:
                        body.insert(pos, rng.choice(b'{}[]",:\\u0123456789abcdefnulltrue\x00\xff\xc3 '))
                    elif body:
                        body[min(pos, len(body) - 1)] = rng.randrange(256)
                body = bytes(body)
            if b"action:colors" in body:
                continue                          # two replies; covered above
            r = self.ask(p, body)
            self.assertIn(r["action"], ("action:invalid", "debug:version", "css:enable", "css:disable", "css:font:size"),
                          body)
        self.ends(p, 0)

    def test_fuzzed_colors_file(self):
        rng = random.Random(99)
        base = conf(extra="wallpaper /home/u/w.png\n").encode()
        p = self.start(poll="60")
        for i in range(400):
            data = bytearray(base)
            for _ in range(rng.randrange(1, 20)):
                pos = rng.randrange(len(data))
                data[pos] = rng.randrange(256)
            if i % 7 == 0:
                data = bytes(rng.randrange(256) for _ in range(rng.randrange(2000)))
            self.colors.write_bytes(bytes(data))
            r = self.ask(p, {"action": "action:colors"})
            self.assertEqual(r["action"], "action:colors")
            if r["success"]:
                self.assertEqual(len(r["data"]["colors"]), 16)
                if b"mode dark\n" in data or b"mode light\n" in data:
                    self.assertEqual(self.read(p)["action"], "theme:mode")
        self.ends(p, 0)


@unittest.skipUnless(CC, "no C compiler")
class Build(unittest.TestCase):
    def test_strict_and_hardened_build_is_clean(self):
        with tempfile.TemporaryDirectory() as d:
            r = subprocess.run(["make", "-s", "-B", f"CC={CC}", "native"], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stderr.strip(), "", "no warnings at all")
            self.assertTrue(os.access(ROOT / "build" / "rutile-pywalfox-host", os.X_OK))
            del d


if __name__ == "__main__":
    unittest.main()
