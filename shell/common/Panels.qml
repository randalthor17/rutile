// How see-through the shell's panels are (D115): the shelf, the pills at the top of the screen and the panels
// they open (Quick Settings, the notification list, the calendar). shell.qml sets `opacity` from the
// style.panelOpacity setting; it stays 1 (solid) elsewhere, as in the offscreen tests.
pragma Singleton
import QtQuick

QtObject {
    property real opacity: 1
    // `c` at the panels' opacity: for a panel's own background, never for what is drawn on it
    function tint(c) {
        return Qt.alpha(c, opacity);
    }
}
