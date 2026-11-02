// A tray app's menu (plan 2.10, D61): the shared Menu with the app's entries (TrayModel.entries), opened under its
// icon with the popup motion (D43). A submenu replaces the list in place, with a Back row on top (as GNOME's do).
// Keyboard: up and down (separators and disabled entries skipped), Enter or Right to choose or go into a submenu,
// Left or Backspace to go back, Escape to close; losing the window's focus closes it too. Plain QtQuick on
// `entries`, so it tests offscreen; the window holds the menus (QsMenuOpener) and runs the choice.
import QtQuick
import qs.common
import qs.components
import "TrayModel.js" as TrayModel

Item {
    id: root

    property var entries: []                    // Menu items (TrayModel.entries)
    property int depth: 0                       // 0: the app's menu; more: a submenu, with a Back row
    property string title: ""                   // the submenu's name, on its Back row
    property bool shown: true
    readonly property alias menu: choices
    readonly property var items: depth > 0
        ? [{ id: "back", text: title || "Back", icon: "arrow_back" }, { id: "backSep", separator: true }].concat(entries)
        : entries

    signal chosen(string id)                    // an entry's id (its index among the menu's children)
    signal back()
    signal closeRequested()
    signal windowFocusLost()
    signal hidden()

    implicitWidth: choices.width
    implicitHeight: choices.height
    width: implicitWidth
    height: implicitHeight
    focus: true

    onItemsChanged: choices.currentIndex = -1

    function choose(index) {
        const it = items[index];
        if (!it || it.separator || it.enabled === false) return;
        if (it.id === "back") root.back();
        else root.chosen(it.id);
    }

    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Down || k === Qt.Key_Tab) choices.currentIndex = TrayModel.next(items, choices.currentIndex, 1);
        else if (k === Qt.Key_Up || k === Qt.Key_Backtab) choices.currentIndex = TrayModel.next(items, choices.currentIndex, -1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) choose(choices.currentIndex);
        else if (k === Qt.Key_Right && items[choices.currentIndex]?.submenu) choose(choices.currentIndex);
        else if ((k === Qt.Key_Left || k === Qt.Key_Backspace) && depth > 0) root.back();
        else if (k === Qt.Key_Escape) root.closeRequested();
        else return;
        event.accepted = true;
    }

    property bool windowActive: Window.active   // not readonly: the offscreen tests cannot move window focus
    property bool hadWindowFocus: false
    onWindowActiveChanged: {
        if (windowActive) hadWindowFocus = true;
        else if (hadWindowFocus) windowFocusLost();
    }

    Menu {
        id: choices
        objectName: "trayMenu"
        items: root.items
        itemPrefix: "trayEntry_"
        minimumWidth: 200
        onChosen: id => root.choose(root.items.findIndex(it => it.id === id))
    }

    PopupMotion {
        target: choices
        shown: root.shown
        origin: Item.TopRight
        onHidden: root.hidden()
    }
}
