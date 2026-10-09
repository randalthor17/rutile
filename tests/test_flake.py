import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FLAKE = (ROOT / "flake.nix").read_text()

# Escapes inside Nix indented strings: ''' (literal ''), ''$ (literal $), ''\ (escape sequence).
ESCAPES = re.compile(r"'''|''\$|''\\")


def string_delimiters(text):
    """Count the '' delimiters of indented strings, ignoring escapes."""
    return ESCAPES.sub("", text).count("''")


def code(text):
    """flake.nix without comments, so explanatory comments cannot trip the checks."""
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


class FlakeShape(unittest.TestCase):
    def test_declares_a_default_devshell_for_linux(self):
        self.assertIn("devShells", FLAKE)
        self.assertIn("default = pkgs.mkShell", FLAKE)
        self.assertIn("x86_64-linux", FLAKE)

    def test_provides_what_make_check_needs(self):
        for needle in ("pkgs.matugen", "qt.qtdeclarative", "pkgs.gnumake", "pkgs.git", "python"):
            self.assertIn(needle, code(FLAKE), needle)

    def test_exports_qml_import_path_from_nixpkgs_prefix(self):
        body = code(FLAKE)
        self.assertIn("QML2_IMPORT_PATH", body)
        self.assertIn("qtQmlPrefix", body)

    def test_shell_does_not_force_offscreen_rendering(self):
        # Exporting this would make Quickshell started from the devshell render offscreen.
        self.assertNotIn("QT_QPA_PLATFORM", code(FLAKE))

    def test_does_not_override_qt_plugin_path(self):
        self.assertIsNone(re.search(r"export\s+QT_PLUGIN_PATH", code(FLAKE)))

    def test_materialyoucolor_is_optional(self):
        self.assertIn("lib.optional (ps ? materialyoucolor)", FLAKE)

    def test_braces_and_strings_balance(self):
        body = code(FLAKE)
        for a, b in ("{}", "[]", "()"):
            self.assertEqual(body.count(a), body.count(b), f"{a}{b}")
        self.assertEqual(string_delimiters(FLAKE) % 2, 0)

    def test_delimiter_counter_handles_escapes_and_catches_unbalanced(self):
        balanced = "x = ''a ''${b} c'';"
        self.assertEqual(string_delimiters(balanced), 2)
        self.assertEqual(string_delimiters("x = ''a ''${b} c;"), 1)  # missing closer is odd
        self.assertEqual(string_delimiters("x = ''a ''' b'';"), 2)  # ''' is an escaped quote pair


if __name__ == "__main__":
    unittest.main()
