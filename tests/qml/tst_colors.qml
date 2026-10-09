import QtQuick
import QtTest
import "../imp"

TestCase {
    name: "Colors"

    property string goldenText: readText("../data/palette.json")
    property var golden: JSON.parse(goldenText)
    property var roles: JSON.parse(readText("../data/roles.json")).roles

    function readText(rel) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return xhr.responseText;
    }
    function camel(s) {
        return s.replace(/_([a-z0-9])/g, function (m, c) { return c.toUpperCase(); });
    }
    // Mirrors tools/gen_qml.py qml_name(): on_* roles become <rest>On (QML reserves onXxx).
    function qmlName(role) {
        return role.indexOf("on_") === 0 ? camel(role.slice(3)) + "On" : camel(role);
    }
    function clone(o) { return JSON.parse(JSON.stringify(o)); }

    function init() {
        verify(Colors.load(goldenText));
        Colors.mode = "dark";
    }

    function test_every_role_is_exposed_with_golden_values() {
        compare(roles.length, 49);
        for (var i = 0; i < roles.length; i++) {
            var c = Colors[qmlName(roles[i])];
            verify(c !== undefined, roles[i]);
            compare(c.toString(), golden.colors.dark[roles[i]], roles[i]);
        }
    }

    function test_on_roles_are_not_signal_handlers() {
        compare(Colors.primaryOn.toString(), golden.colors.dark.on_primary);
        compare(Colors.backgroundOn.toString(), "#e3e2e9");
        compare(Colors.surfaceVariantOn.toString(), golden.colors.dark.on_surface_variant);
        compare(Colors.inverseOnSurface.toString(), golden.colors.dark.inverse_on_surface);
        var names = Object.keys(Colors);
        for (var i = 0; i < names.length; i++)
            verify(!/^on[A-Z]/.test(names[i]), names[i]);
    }

    function test_known_values() {
        compare(Colors.primary.toString(), "#b2c5ff");
        compare(Colors.surfaceContainerHighest.toString(), "#33343a");
        Colors.mode = "light";
        compare(Colors.primary.toString(), "#495d92");
    }

    function test_mode_switch_changes_all_surfaces() {
        var before = Colors.surface.toString();
        Colors.mode = "light";
        verify(Colors.surface.toString() !== before);
        Colors.mode = "dark";
        compare(Colors.surface.toString(), before);
    }

    function test_load_takes_mode_and_source_from_document() {
        var d = clone(golden);
        d.mode = "light";
        d.source_color = "#6750a4";
        d.colors.light.primary = "#123456";
        verify(Colors.load(JSON.stringify(d)));
        compare(Colors.mode, "light");
        compare(Colors.sourceColor, "#6750a4");
        compare(Colors.primary.toString(), "#123456");
        compare(Colors.lastError, "");
        verify(Colors.loaded);
    }

    function test_invalid_json_keeps_previous_colors() {
        var before = Colors.primary.toString();
        verify(!Colors.load("{ not json"));
        compare(Colors.lastError, "invalid JSON");
        compare(Colors.primary.toString(), before);
    }

    function test_missing_role_rejected() {
        var d = clone(golden);
        delete d.colors.dark.surface_container_high;
        var before = Colors.primary.toString();
        verify(!Colors.load(JSON.stringify(d)));
        verify(Colors.lastError.indexOf("surface_container_high") >= 0);
        compare(Colors.primary.toString(), before);
    }

    function test_bad_hex_rejected() {
        var cases = ["#ABCDEF", "#12345", "red", 12, null];
        for (var i = 0; i < cases.length; i++) {
            var d = clone(golden);
            d.colors.light.primary = cases[i];
            verify(!Colors.load(JSON.stringify(d)), String(cases[i]));
        }
    }

    function test_wrong_format_or_mode_rejected() {
        var d = clone(golden);
        d.format = 2;
        verify(!Colors.load(JSON.stringify(d)));
        d = clone(golden);
        d.mode = "sepia";
        verify(!Colors.load(JSON.stringify(d)));
        d = clone(golden);
        delete d.colors.light;
        verify(!Colors.load(JSON.stringify(d)));
        verify(!Colors.load("null"));
    }
}
