// An M3 Expressive icon button: four types (standard, filled, tonal, outlined), five
// sizes, three widths (default is square), round or square shape, optional toggle.
import QtQuick
import qs.common

ButtonBase {
    id: root

    property string iconName: ""
    property string type: "standard"        // standard | filled | tonal | outlined
    property string size: "s"               // xs | s | m | l | xl
    property string widthVariant: "default" // default | narrow | wide

    spec: ControlSpec.iconButtonSizes[size]
    colors: ControlSpec.iconButtonTypes[type]

    implicitHeight: spec.height
    implicitWidth: spec.width[widthVariant]

    Accessible.name: iconName

    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.spec.icon
        color: root.contentColor
        fill: root.selected ? 1 : 0
    }
}
