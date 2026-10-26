import QtQuick
import QtTest
import qs.common
import qs.components
import qs.gallery

TestCase {
    id: root
    name: "Gallery"
    width: 1180
    height: 900
    visible: true
    when: windowShown

    Component { id: galleryComp; GalleryContent { width: 1180; height: 900 } }

    function init() { Colors.mode = "dark"; }
    function cleanup() { Colors.mode = "dark"; }

    // every descendant satisfying keep(item), searching delegates (parented to the Repeater's parent)
    function collect(item, keep, out) {
        if (keep(item)) out.push(item);
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) collect(kids[i], keep, out);
        return out;
    }
    function byName(g, name) { return collect(g, function (it) { return it.objectName === name; }, []); }

    function test_gallery_shows_every_role_and_every_type_style() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        compare(byName(g, "swatch").length, Colors.roles.length);
        compare(Colors.roles.length, 49);
        compare(byName(g, "typeRow").length, Type.styleNames.length);
        compare(Type.styleNames.length, 30);
    }

    function test_gallery_contains_the_full_button_and_icon_button_matrices() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        var buttons = collect(g, function (it) { return it.type !== undefined && it.text !== undefined && it.iconName !== undefined && it.spec !== undefined; }, []);
        var icons = collect(g, function (it) { return it.type !== undefined && it.widthVariant !== undefined; }, []);
        var seen = {};
        buttons.forEach(function (b) { seen[b.type + "/" + b.size] = true; });
        var types = ["filled", "tonal", "elevated", "outlined", "text"], sizes = ["xs", "s", "m", "l", "xl"];
        for (var t = 0; t < types.length; t++)
            for (var s = 0; s < sizes.length; s++)
                verify(seen[types[t] + "/" + sizes[s]], "missing button " + types[t] + "/" + sizes[s]);
        var iconSeen = {};
        icons.forEach(function (b) { iconSeen[b.type + "/" + b.size] = true; });
        var itypes = ["standard", "filled", "tonal", "outlined"];
        for (var a = 0; a < itypes.length; a++)
            for (var c = 0; c < sizes.length; c++)
                verify(iconSeen[itypes[a] + "/" + sizes[c]], "missing icon button " + itypes[a] + "/" + sizes[c]);
    }

    function test_gallery_shows_switches_sliders_and_progress_in_every_state() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        var sw = byName(g, "gallerySwitch");
        compare(sw.length, 6);
        verify(sw.some(function (s) { return s.checked && s.hasIcon; }), "a checked switch with an icon");
        verify(sw.some(function (s) { return !s.enabled; }), "a disabled switch");
        var sl = byName(g, "gallerySlider");
        compare(sl.length, 3);
        verify(sl.some(function (s) { return s.stepCount > 0; }), "a stepped slider");
        var pr = byName(g, "galleryProgress");
        compare(pr.length, 2);
        verify(pr.some(function (p) { return p.wavy && p.waveOn; }), "a visibly wavy bar");
        sl[0].value = 0.9;
        compare(pr[0].value, 0.9, "progress follows the first slider");
    }

    function test_gallery_shows_slider_sizes_and_quick_settings_sliders() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        var sized = byName(g, "gallerySizedSlider");
        compare(sized.map(function (s) { return s.size; }).join(), "s,m,l,xl");
        verify(sized.every(function (s) { return s.endIconShown === (s.size !== "s") && !s.startIconShown; }),
               "one end icon, from m up");
        var qs = byName(g, "galleryQsSlider");
        compare(qs.length, 2, "brightness and volume");
        verify(qs.every(function (s) { return s.size === "m" && s.endIconShown && !s.startIconShown; }));
    }

    function test_gallery_grid_edits_quick_settings_tiles() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        var grid = byName(g, "galleryGrid")[0];
        var edit = byName(g, "galleryGridEdit")[0];
        verify(grid !== undefined && edit !== undefined);
        compare(grid.items.length, 9);
        compare(grid.slotLayout.slots[0].cols, 2, "Wi-Fi is a large tile");
        compare(grid.slotLayout.slots[2].cols, 1, "the rest are small");
        verify(!grid.editMode);
        g.flickable.contentY = Math.max(0, edit.mapToItem(g.flickable.contentItem, 0, 0).y - 100);
        wait(50);
        var p = edit.mapToItem(g, edit.width / 2, edit.height / 2);
        mouseClick(g, p.x, p.y);
        verify(grid.editMode, "the button opens edit mode");
        grid.selectedIndex = 2;
        grid.items = grid.items.filter(function (item, i) { return i !== grid.selectedIndex; });
        compare(grid.items.length, 8);
        mouseClick(g, p.x, p.y);
        verify(!grid.editMode);
    }

    function test_content_is_scrollable_and_taller_than_the_window() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        verify(g.flickable.contentHeight > 2000, "content height " + g.flickable.contentHeight);
        g.flickable.contentY = 500;
        compare(g.flickable.contentY, 500);
    }

    function test_theme_toggle_switches_the_palette_mode() {
        var g = createTemporaryObject(galleryComp, root);
        wait(200);
        var toggle = byName(g, "themeToggle")[0];
        verify(toggle !== undefined);
        compare(toggle.iconName, "dark_mode");
        var p = toggle.mapToItem(g, toggle.width / 2, toggle.height / 2);
        mouseClick(g, p.x, p.y);
        compare(Colors.mode, "light");
        compare(toggle.iconName, "light_mode");
        mouseClick(g, p.x, p.y);
        compare(Colors.mode, "dark");
    }
}
