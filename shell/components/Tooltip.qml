// The M3 plain tooltip (plan 1.5, D106), from Compose's PlainTooltipTokens and Tooltip.kt (ControlSpec.tooltipSpec):
// a short text on the inverse surface, at least 40 x 24 and at most 200 px wide (longer text wraps). It grows in with
// the shared popup motion (D43) while `shown`, and says `hidden` once it has faded out, so its owner can unload it
// (D31). Where it goes is the owner's: Compose puts it `spec.impl.anchorSpace` from what it explains.
import QtQuick
import qs.common

Rectangle {
    id: root

    property string text: ""
    property bool shown: true
    property int origin: Item.Bottom            // the edge it grows from: the one nearest what it explains
    readonly property var spec: ControlSpec.tooltipSpec

    signal hidden()

    readonly property real horizontalPadding: spec.impl.horizontalPadding
    readonly property real verticalPadding: spec.impl.verticalPadding
    implicitWidth: Math.max(spec.impl.minWidth, Math.min(spec.impl.maxWidth, label.implicitWidth + 2 * horizontalPadding))
    implicitHeight: Math.max(spec.impl.minHeight, label.height + 2 * verticalPadding)
    width: implicitWidth
    height: implicitHeight
    radius: spec.plain.containerShape
    color: Colors[spec.plain.containerColor]

    Accessible.role: Accessible.ToolTip
    Accessible.name: text

    PopupMotion {
        target: root
        shown: root.shown
        origin: root.origin
        onHidden: root.hidden()
    }

    Text {
        id: label
        objectName: "tooltipText"
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.spec.impl.maxWidth - 2 * root.horizontalPadding)
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        text: root.text
        color: Colors[root.spec.plain.supportingTextColor]
        font: Type.font(Type[root.spec.plain.supportingTextFont])
    }
}
