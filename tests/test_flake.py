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

    def test_depends_on_the_vendored_google_sans_flex_package(self):
        body = code(FLAKE)
        self.assertIn("./nix/googlesans-flex.nix", body)
        self.assertIn("google-sans-flex", body)
        self.assertTrue((ROOT / "nix" / "googlesans-flex.nix").exists())

    def test_devshell_exposes_fonts_to_qt_without_losing_system_fonts(self):
        body = code(FLAKE)
        self.assertIn("pkgs.material-symbols", body)
        self.assertIn("RUTILE_FONT_DIRS", body)
        self.assertIn("FONTCONFIG_FILE", body)
        self.assertIn("tools/fontconf.py", body)
        # the helper includes the system config; the shell must not point FONTCONFIG_FILE elsewhere
        self.assertEqual(body.count("export FONTCONFIG_FILE"), 1)

    def test_local_ai_shell_and_module(self):
        body = code(FLAKE)
        self.assertIn("local-ai = pkgs.mkShell", body)
        self.assertIn("pkgs.ollama-rocm", body)
        self.assertIn("pkgs.opencode", body)
        self.assertIn("nixosModules.local-ai", body)
        self.assertIn("./nix/local-ai-module.nix", body)
        self.assertTrue((ROOT / "nix" / "local-ai-module.nix").exists())

    def test_local_ai_shell_is_x86_64_only_and_does_not_leak_into_the_default_shell(self):
        body = code(FLAKE)
        self.assertIn("isx86_64", body)
        self.assertLess(body.index("isx86_64"), body.index("local-ai = pkgs.mkShell"),
                        "the local-ai shell must sit behind the x86_64 guard")
        default_part = body[body.index("default = pkgs.mkShell"):body.index("isx86_64")]
        for heavy in ("ollama", "opencode"):
            self.assertNotIn(heavy, default_part, f"{heavy} must not be in the everyday shell")

    def test_local_ai_shell_has_everything_the_default_shell_has(self):
        # An agent in local-ai runs `make check` and the acceptance checks; without qmltestrunner,
        # QML2_IMPORT_PATH and the fonts they fail for reasons that are not its work.
        body = code(FLAKE)
        local_ai = body[body.index("local-ai = pkgs.mkShell"):]
        self.assertRegex(local_ai, r"packages\s*=\s*devPackages\s*\+\+")
        self.assertRegex(local_ai, r"shellHook\s*=\s*devHook\s*\+")
        default = body[body.index("default = pkgs.mkShell"):body.index("isx86_64")]
        self.assertRegex(default, r"packages\s*=\s*devPackages;")
        self.assertRegex(default, r"shellHook\s*=\s*devHook\s*\+")
        shared = body[body.index("devPackages = ["):body.index("default = pkgs.mkShell")]
        for need in ("qt.qtdeclarative", "pkgs.quickshell", "pkgs.matugen", "QML2_IMPORT_PATH", "fontconf.py"):
            self.assertIn(need, shared)

    def test_claude_code_is_the_only_unfree_package_allowed(self):
        # pkgs.claude-code straight from legacyPackages fails to evaluate (unfree), which broke
        # `nix develop .#local-ai`; allowing all unfree software would hide the next one.
        body = code(FLAKE)
        self.assertIsNone(re.search(r"\bpkgs\.claude-code\b", body), "plain pkgs.claude-code does not evaluate")
        self.assertNotRegex(body, r"allowUnfree\s*=\s*true")
        self.assertRegex(body, r'allowUnfreePredicate\s*=\s*pkg:\s*lib\.getName pkg == "claude-code"')
        local_ai = body[body.index("local-ai = pkgs.mkShell"):]
        self.assertIn(").claude-code", local_ai)

    def test_module_uses_the_rocm_package_with_a_vulkan_escape_hatch(self):
        text = (ROOT / "nix" / "local-ai-module.nix").read_text()
        self.assertIn("lib.mkDefault pkgs.ollama-rocm", text)
        self.assertIn("pkgs.ollama-vulkan", text)
        self.assertIn("services.ollama", text)

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
