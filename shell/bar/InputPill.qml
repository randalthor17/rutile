// The input method in use (D118), left of the app indicators: its short label (EN, BN) on the same tonal container
// as the bell, shown while fcitx5 has more than one input method in its group. A click asks for its menu (fcitx5's
// own: the input methods, Configure); tinted while that is open. Plain QtQuick, so it tests offscreen.
import QtQuick
import qs.common
import qs.components

Rectangle {
    id: root

    property string label: ""
    property string name: ""          // the input method's full name
    property bool open: false

    signal clicked()

    readonly property color contentColor: open ? Colors.secondaryContainerOn : Colors.surfaceOn

    visible: label !== ""
    implicitWidth: visible ? Math.max(Spacing.xl, text.implicitWidth + 2 * Spacing.sm) : 0
    implicitHeight: Spacing.xl
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Panels.tint(open ? Colors.secondaryContainer : Colors.surfaceContainer)
    Behavior on color { EffectsColor {} }

    Accessible.role: Accessible.Button
    Accessible.name: name

    Text {
        id: text
        objectName: "inputLabel"
        anchors.centerIn: parent
        text: root.label
        color: root.contentColor
        font: Type.font(Type.labelLarge)
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        stateColor: root.contentColor
        onClicked: root.clicked()
    }
}
