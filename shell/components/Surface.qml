// A rounded tonal surface. M3 Expressive elevation is mostly tonal (surface container
// roles), so there is no shadow here; pick the container role that matches the layer.
// Set `tone` (not `color`) so changes animate with an effects spring.
import QtQuick
import qs.common

Rectangle {
    id: root

    property color tone: Colors.surfaceContainer

    color: fade.value
    radius: Shapes.medium

    SpringColor {
        id: fade
        target: root.tone
    }
}
