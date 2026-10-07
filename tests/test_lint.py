import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import lint_hardcoded as lint  # noqa: E402


def project(files):
    root = Path(tempfile.mkdtemp())
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    return root


class Lint(unittest.TestCase):
    def test_flags_hex_radius_duration(self):
        root = project({"shell/A.qml": "Rectangle {\n color: \"#ff00aa\"\n radius: 12\n}\nNumberAnimation { duration: 200 }\n"})
        kinds = [p.split(": ")[1] for p in lint.scan(root)]
        self.assertEqual(sorted(kinds), ["hex color", "numeric duration", "numeric radius"])

    def test_token_references_pass(self):
        root = project({"shell/B.qml": "Rectangle { color: Colors.primary; radius: Shapes.medium }\n"})
        self.assertEqual(lint.scan(root), [])

    def test_ignore_marker_and_comments(self):
        root = project({"settings/C.qml": "color: \"#fff\" // lint-ignore\n// radius: 4 is documented here\n"})
        self.assertEqual(lint.scan(root), [])

    def test_only_scans_shell_and_settings(self):
        root = project({"docs/D.qml": "color: \"#123456\"\n", "tokens/x.qml": "radius: 3\n"})
        self.assertEqual(lint.scan(root), [])

    def test_exit_code(self):
        bad = project({"shell/E.qml": "radius: 8\n"})
        ok = project({"shell/F.qml": "radius: Shapes.small\n"})
        self.assertEqual(lint.main([str(bad)]), 1)
        self.assertEqual(lint.main([str(ok)]), 0)


if __name__ == "__main__":
    unittest.main()
