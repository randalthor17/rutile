// Default apps (plan 5.2): which app opens web links, folders, mail, pictures, videos, music, text and PDFs. A page
// view: the app sets `app`, `store` and `backend` (AppsBackend.qml, or the tests' fake), which has
//   available; managed (mimeapps.list is home-manager's: nothing can be set here); error;
//   kinds: [{id, title, icon, current (app id, "" none), apps: [{id, name, icon}]}]; setDefault(kind, app).
// The group is `setting_apps.defaults` (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import qs.settingsapp

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property var kinds: backend?.available ? backend.kinds ?? [] : []
    readonly property bool managed: backend?.managed ?? false

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "appsManaged"
        visible: page.managed
        width: page.width
        iconName: "lock"
        text: "Set in your Nix configuration"
        supportingText: "Your mimeapps.list comes from home-manager (xdg.mimeApps): change default apps there"
    }
    ListItem {
        objectName: "appsError"
        visible: (page.backend?.error ?? "") !== ""
        width: page.width
        iconName: "error"
        text: "Not changed"
        supportingText: page.backend?.error ?? ""
    }

    Column {
        objectName: "setting_apps.defaults"
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Default apps"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        Repeater {
            model: page.kinds
            delegate: ChoiceRow {
                id: kindRow
                required property var modelData
                required property int index
                readonly property var defaultApp: modelData.apps.find(a => a.id === modelData.current) ?? null
                app: page.app
                key: "apps." + modelData.id
                width: page.width
                position: page.segment(index, page.kinds.length)
                iconName: modelData.icon
                text: modelData.title
                supportingText: modelData.apps.length === 0 ? "No app for this is installed" : ""
                choices: modelData.apps.map(a => a.name)
                current: defaultApp ? defaultApp.name : (modelData.apps.length ? "Not set" : "")
                enabled: !page.managed && modelData.apps.length > 0
                onChosen: index => page.backend.setDefault(modelData.id, modelData.apps[index].id)
            }
        }
    }
}
