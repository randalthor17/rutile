// Keep awake (plan 2.6, D116): while `on`, nothing idles: no lock on idle (D49's IdleMonitor honours inhibitors), no
// screen blanking or sleep by an idle daemon that follows Wayland's idle inhibitors (swayidle, hypridle). shell.qml
// holds the inhibitor on a surface of its own while this is on. For this session only: off again when the shell
// starts.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool on: false

    function setOn(wanted) {
        on = wanted;
    }
}
