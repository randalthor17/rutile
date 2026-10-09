// Rutile-defined spacing scale on a 4px grid. Material 3 does not publish spacing
// as tokens, so these values are ours; change them here, never in components.
pragma Singleton
import QtQml

QtObject {
    readonly property int none: 0
    readonly property int xs: 4
    readonly property int sm: 8
    readonly property int md: 12
    readonly property int lg: 16
    readonly property int xl: 24
    readonly property int xxl: 32
    readonly property int xxxl: 48
}
