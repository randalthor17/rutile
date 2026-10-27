// The toasts' layer-shell surface: at the bottom left, above the shelf (it keeps clear of the shelf's exclusive
// zone; the OSD has the bottom centre), on the overlay layer, without keyboard focus. The shell creates it in a
// LazyLoader while ToastService has a toast (D31). It is as big as the toast showing, so it changes size only
// from one toast to the next, never during the motion.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

PanelWindow {
    id: root

    readonly property alias toast: toast

    anchors.bottom: true
    anchors.left: true
    margins.bottom: Spacing.lg
    margins.left: Spacing.lg
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "rutile-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: toast.implicitWidth
    implicitHeight: toast.implicitHeight
    color: "transparent"

    readonly property var current: ToastService.current
    onCurrentChanged: if (current) toast.show()
    Component.onCompleted: if (current) toast.show()
    Connections {
        target: ToastService
        function onRepeatsChanged() { if (ToastService.repeats > 0) toast.show(); }
    }

    Toast {
        id: toast
        width: root.implicitWidth
        height: root.implicitHeight
        text: root.current?.text ?? ""
        iconName: root.current?.icon ?? ""
        actionText: root.current?.action?.text ?? ""
        onActionClicked: ToastService.invoke(root.current.id)
        onHidden: ToastService.done(root.current?.id ?? -1)
    }
}
