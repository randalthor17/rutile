// The layer-shell surface of a tray app's menu (plan 2.10, D61), under the status bar with its right edge under the
// app's icon. As the other panels (D41): loaded only while open (D31), it takes the keyboard, Escape or a click
// into a window closes it, and closing plays the motion before closeRequested asks the shell to unload it. It keeps
// one QsMenuOpener per menu level (the app's menu, then each submenu opened), and runs the choice: an entry is
// triggered and the menu closes; an entry with children opens them in place.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import "TrayModel.js" as TrayModel

PanelWindow {
    id: root

    required property var trayItem              // the SystemTrayItem
    property real right: Spacing.sm             // from the screen's right edge to the menu's
    readonly property bool closing: !panel.shown
    readonly property alias panel: panel

    signal closeRequested()

    function close() { panel.shown = false; }

    // the menu levels: [{opener, title}]
    property var levels: []
    readonly property var top: levels.length ? levels[levels.length - 1] : null
    readonly property var children: top ? top.opener.children.values : []
    readonly property var buttons: ({ checkBox: QsMenuButtonType.CheckBox, radioButton: QsMenuButtonType.RadioButton })

    function push(handle, title) {
        const opener = openerComponent.createObject(root, { menu: handle });
        levels = levels.concat([{ opener: opener, title: title }]);
    }
    function pop() {
        if (levels.length <= 1) return;
        const last = levels[levels.length - 1];
        levels = levels.slice(0, -1);
        last.opener.destroy();
    }
    // Choose the entry at `index` among the current level's children (also from IPC).
    function choose(index) {
        const entry = children[index];
        if (!entry || entry.isSeparator || !entry.enabled) return false;
        if (entry.hasChildren) {
            push(entry, TrayModel.label(entry.text));
            return true;
        }
        entry.triggered();
        close();
        return true;
    }

    Component {
        id: openerComponent
        QsMenuOpener {}
    }
    Component.onCompleted: push(trayItem.menu, "")
    Component.onDestruction: levels.forEach(l => l.opener.destroy())

    anchors.top: true
    anchors.right: true
    margins.top: 2 * Spacing.sm + Spacing.xl       // below the status bar
    margins.right: right
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "rutile-tray-menu"
    implicitWidth: panel.width
    implicitHeight: panel.height
    color: "transparent"

    TrayMenuPanel {
        id: panel
        entries: TrayModel.entries(root.children, root.buttons, Qt.Checked)
        depth: root.levels.length - 1
        title: root.top?.title ?? ""
        onChosen: id => root.choose(Number(id))
        onBack: root.pop()
        onCloseRequested: root.close()
        onWindowFocusLost: root.close()
        onHidden: root.closeRequested()
    }
}
