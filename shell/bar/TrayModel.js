// App indicators (plan 2.10, D61): which tray items show, and a tray menu's entries as Menu items. Plain functions
// of plain values (the Quickshell side passes its enum values in), so it tests offscreen.
.pragma library

// SystemTray items to show, in the tray's order: Passive ones are hidden (the StatusNotifierItem spec: nothing to
// show right now). [{id, title, icon, attention, item}]
function shown(items, passive, attention) {
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        if (!it || it.status === passive) continue;
        out.push({ id: it.id, title: it.tooltipTitle || it.title || it.id, icon: it.icon,
                   attention: it.status === attention, item: it });
    }
    return out;
}

// An entry's text as shown. Quickshell already removes DBusMenu's mnemonic marks (seen with a real tray app), so
// an underscore left is a real one and stays.
function label(text) {
    return String(text || "");
}

// QsMenuEntry list as Menu items (shell/components/Menu.qml): ids are the entries' indexes; separators at the
// ends or doubled are dropped. buttons: {checkBox, radioButton} (QsMenuButtonType); checked: Qt.Checked.
function entries(list, buttons, checked) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var e = list[i];
        if (e.isSeparator) {
            if (out.length && !out[out.length - 1].separator) out.push({ id: "sep" + i, separator: true });
            continue;
        }
        var kind = e.buttonType === buttons.checkBox ? "checkbox" : e.buttonType === buttons.radioButton ? "radio" : "";
        out.push({ id: String(i), text: label(e.text), image: e.icon || "", enabled: e.enabled !== false,
                   check: kind, checked: kind !== "" && e.checkState === checked, submenu: !!e.hasChildren });
    }
    while (out.length && out[out.length - 1].separator) out.pop();
    return out;
}

// The next choosable item from `index` by `step` (1 or -1), wrapping; -1 when none is. Separators and disabled
// items are skipped.
function next(items, index, step) {
    var n = items.length;
    var from = index >= 0 ? index : step > 0 ? -1 : n;     // nothing chosen yet: from the first or the last
    for (var k = 1; k <= n; k++) {
        var i = ((from + step * k) % n + n) % n;
        if (!items[i].separator && items[i].enabled !== false) return i;
    }
    return -1;
}
