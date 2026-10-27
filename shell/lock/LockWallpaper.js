// The lock screen's wallpaper image request, shared by LockPanel and the copy the shell keeps loaded (shell.qml), so
// both ask Qt's image cache for the same thing (the same URL and size) and the lock screen never waits to decode.
.pragma library

// Small on purpose: it is only seen blurred. 480x270 (16:9) is about 0.5 MB decoded.
var size = Qt.size(480, 270);

function url(path) {
    return path ? "file://" + path : "";
}
