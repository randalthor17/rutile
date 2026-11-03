// Power (plan 5.2): the battery (charge, time left or to full, health) and the power mode. A page view: the app
// sets `app`, `store` and `backend` (PowerBackend.qml, or the tests' fake), which has
//   batteryAvailable, battery (0-1), state (charging, pending, full, empty, discharging), timeToFull and
//   timeToEmpty (seconds, 0 unknown), health (0-1, -1 unknown); profilesAvailable, hasPerformance, profile
//   (power-saver, balanced, performance), holds [(profile, app, reason)]; setProfile(name).
// The groups are `setting_power.battery` and `setting_power.mode` (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property bool hasBattery: backend?.batteryAvailable ?? false
    readonly property bool hasProfiles: backend?.profilesAvailable ?? false
    readonly property var modes: [
        { id: "power-saver", title: "Power saver", icon: "energy_savings_leaf", text: "Longer battery, slower" },
        { id: "balanced", title: "Balanced", icon: "balance", text: "The usual" },
        { id: "performance", title: "Performance", icon: "speed", text: "Fastest, uses more power" }
    ].filter(m => m.id !== "performance" || (backend?.hasPerformance ?? false))

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }
    // "2 h 5 min", "40 min"; "" for unknown
    function duration(s) {
        if (!(s > 0)) return "";
        const m = Math.round(s / 60);
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min";
    }
    function batteryText() {
        const b = backend;
        switch (b.state) {
        case "charging": return duration(b.timeToFull) ? "Charging, full in " + duration(b.timeToFull) : "Charging";
        case "pending": return "Plugged in, not charging";
        case "full": return "Fully charged";
        case "empty": return "Empty";
        default: return duration(b.timeToEmpty) ? duration(b.timeToEmpty) + " left" : "On battery";
        }
    }
    function batteryIcon() {
        if (backend.state === "charging" || backend.state === "full") return "battery_charging_full";
        const n = Math.min(6, Math.floor(backend.battery * 7));
        return backend.battery >= 0.95 ? "battery_full" : "battery_" + n + "_bar";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "powerNothing"
        visible: !page.hasBattery && !page.hasProfiles
        width: page.width
        iconName: "power"
        text: "No battery or power modes"
        supportingText: "This computer has no battery, and power-profiles-daemon is not running"
    }

    Column {
        objectName: "setting_power.battery"
        visible: page.hasBattery
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        readonly property bool showHealth: page.hasBattery && page.backend.health >= 0
        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Battery"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        ListItem {
            objectName: "powerBattery"
            width: page.width
            position: page.segment(0, parent.showHealth ? 2 : 1)
            tone: Colors.surfaceContainer
            iconName: page.hasBattery ? page.batteryIcon() : "battery_unknown"
            text: page.hasBattery ? Math.round(page.backend.battery * 100) + "%" : ""
            supportingText: page.hasBattery ? page.batteryText() : ""
            ProgressBar {
                width: 160
                value: page.hasBattery ? page.backend.battery : 0
            }
        }
        ListItem {
            objectName: "powerHealth"
            visible: parent.showHealth
            width: page.width
            position: "last"
            tone: Colors.surfaceContainer
            iconName: "health_and_safety"
            text: "Battery health"
            supportingText: "Of what it held when new"
            trailingText: parent.showHealth ? Math.round(page.backend.health * 100) + "%" : ""
        }
    }

    Column {
        objectName: "setting_power.mode"
        visible: page.hasProfiles
        width: page.width
        spacing: ControlSpec.listSpec.segmentedGap
        Text {
            height: implicitHeight + Spacing.sm
            leftPadding: Spacing.lg
            text: "Power mode"
            color: Colors.primary
            font: Type.font(Type.titleSmall)
        }
        Repeater {
            model: page.modes
            delegate: ListItem {
                id: mode
                required property var modelData
                required property int index
                readonly property bool chosen: page.backend?.profile === modelData.id
                readonly property var hold: (page.backend?.holds ?? []).find(h => h.profile === modelData.id) ?? null
                objectName: "powerMode_" + modelData.id
                width: page.width
                position: page.segment(index, page.modes.length)
                tone: Colors.surfaceContainer
                iconName: modelData.icon
                text: modelData.title
                supportingText: hold ? "Held by " + (hold.app || "an app") + (hold.reason ? ": " + hold.reason : "") : modelData.text
                selected: chosen
                Accessible.role: Accessible.RadioButton
                Accessible.checked: chosen
                onClicked: page.backend.setProfile(modelData.id)
                Icon {
                    visible: mode.chosen
                    name: "check"
                    color: Colors.primary
                }
            }
        }
    }
}
