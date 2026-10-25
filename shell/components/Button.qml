// An M3 Expressive button: five types (filled, tonal, outlined, text, elevated), five
// sizes (xs, s, m, l, xl), round or square shape, optional leading icon, optional toggle.
// Elevated buttons show their container color only; shadows are not drawn yet.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common

ButtonBase {
    id: root

    property string text: ""
    property string iconName: ""
    property string type: "filled"   // filled | tonal | outlined | text | elevated
    property string size: "s"        // xs | s | m | l | xl

    spec: ControlSpec.buttonSizes[size]
    colors: ControlSpec.buttonTypes[type]

    readonly property bool hasIcon: iconName !== ""
    readonly property bool hasText: text !== ""

    implicitHeight: spec.height
    implicitWidth: spec.leading + row.implicitWidth + spec.trailing

    Accessible.name: text

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.hasIcon && root.hasText ? root.spec.iconLabelGap : 0

        // Created only for buttons with an icon.
        Loader {
            active: root.hasIcon
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Icon {
                name: root.iconName
                size: root.spec.icon
                color: root.contentColor
                fill: root.selected ? 1 : 0
            }
        }

        Text {
            visible: root.hasText
            text: root.text
            color: root.contentColor
            font: Type.font(Type[root.spec.labelStyle])
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
