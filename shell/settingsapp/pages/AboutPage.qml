// About Rutile (Pages.js): where the settings live (D45). A page view: the app sets `app`, `store` and `backend`.
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    spacing: ControlSpec.listSpec.segmentedGap
    ListItem {
        objectName: "aboutSettingsFile"
        width: page.width
        position: "first"
        iconName: "description"
        text: "Your settings"
        supportingText: (page.store?.configDir ?? "") + "/settings.json"
    }
    ListItem {
        width: page.width
        position: "middle"
        iconName: "lock"
        text: "Set in Nix (home-manager)"
        supportingText: (page.store?.configDir ?? "") + "/managed.json"
    }
    ListItem {
        width: page.width
        position: "last"
        iconName: "terminal"
        text: "From a script or keybind"
        supportingText: "rutile-shell settings open <page>"
    }
}
