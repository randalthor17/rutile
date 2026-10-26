// The clock's layer-shell surface at the top left of one screen, on the top layer like the status pill; the space
// it sits in is the pill's reserved strip (ScreenStatus.qml). The time comes from Quickshell's SystemClock, which
// ticks once a minute.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

PanelWindow {
    id: root

    readonly property alias pill: pill

    anchors.top: true
    anchors.left: true
    margins.top: Spacing.sm
    margins.left: Spacing.sm
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rutile-clock"
    WlrLayershell.layer: WlrLayer.Top
    implicitWidth: pill.width
    implicitHeight: pill.height
    color: "transparent"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ClockPill {
        id: pill
        now: clock.date
    }
}
