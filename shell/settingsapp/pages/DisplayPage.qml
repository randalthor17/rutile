// Display (plan 5.2): each of niri's outputs with its resolution, refresh rate, scale, orientation and variable
// refresh rate, and on or off (not the last one on). A page view: the app sets `app`, `store` and `backend`
// (DisplayBackend.qml, or the tests' fake), which has
//   available; outputs: niri's JSON (`niri msg -j outputs`'s values); error: the last change's complaint;
//   command(name, args) (`niri msg output NAME ARGS...`), kept (the outputs whose choices the shell keeps, D74),
//   reset(name) (back to niri's own config); brightness: BrightnessService's displays (D113), and
//   setBrightness(id, value), for a slider under each output whose brightness can be set.
// The outputs are the group `setting_display.outputs` (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components
import qs.settingsapp
import "../../services/NiriDisplay.js" as Display
import "../../services/BrightnessCtl.js" as Brightness

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property bool available: backend?.available ?? false
    readonly property var outputs: available ? backend.outputs ?? [] : []
    readonly property int onCount: Display.enabledCount(outputs)

    function segment(i, n) {
        return app ? app.segment(i, n) : "single";
    }

    spacing: Spacing.xl

    ListItem {
        objectName: "displayUnavailable"
        visible: !page.available
        width: page.width
        iconName: "desktop_access_disabled"
        text: "No displays found"
        supportingText: "niri is not running, or `niri msg` is not on PATH"
    }
    ListItem {
        objectName: "displayNotice"
        visible: page.app?.conditions?.niriNotIncluded === true
        width: page.width
        tone: Colors.tertiaryContainer
        iconName: "info"
        text: "niri does not read Rutile's file yet"
        supportingText: 'The shell applies these while it runs; to keep them without it, add include optional=true "rutile.kdl" to niri\'s config.kdl'
    }
    ListItem {
        objectName: "displayError"
        visible: page.available && (page.backend?.error ?? "") !== ""
        width: page.width
        iconName: "error"
        text: "niri did not take the change"
        supportingText: page.backend?.error ?? ""
    }

    Column {
        objectName: "setting_display.outputs"
        visible: page.available
        width: page.width
        spacing: Spacing.xl

        Repeater {
            model: page.outputs
            delegate: Column {
                id: out
                required property var modelData
                required property int index
                readonly property bool on: Display.enabled(modelData)
                readonly property var mode: Display.current(modelData)
                readonly property var resolutions: Display.resolutions(modelData)
                readonly property var rates: mode ? Display.rates(modelData, mode.width, mode.height) : []
                readonly property var scales: Display.scales(modelData)
                readonly property bool vrr: on && modelData.vrr_supported
                readonly property var light: on ? Brightness.forOutput(page.backend?.brightness, modelData.name) : null
                readonly property int b: light ? 1 : 0       // the rows after brightness move down one
                readonly property int rows: (on ? 5 + b + (vrr ? 1 : 0) : 1) + (kept ? 1 : 0)
                readonly property string key: "display." + modelData.name
                readonly property bool kept: (page.backend?.kept ?? []).indexOf(modelData.name) >= 0
                width: page.width
                spacing: ControlSpec.listSpec.segmentedGap

                function run(args) {
                    page.backend.command(modelData.name, args);
                }

                Text {
                    height: implicitHeight + Spacing.sm
                    leftPadding: Spacing.lg
                    text: Display.title(out.modelData)
                    color: Colors.primary
                    font: Type.font(Type.titleSmall)
                }
                ListItem {
                    id: power
                    objectName: "displayOn_" + out.index
                    width: page.width
                    position: page.segment(0, out.rows)
                    tone: Colors.surfaceContainer
                    iconName: out.on ? "desktop_windows" : "desktop_access_disabled"
                    text: out.modelData.name
                    supportingText: !out.on ? "Off"
                                  : Display.resolutionLabel(out.mode) + ", " + Display.rateLabel(out.mode.refresh_rate)
                    // the last output on stays on: there would be nothing left to turn it on from
                    readonly property bool canSwitch: !out.on || page.onCount > 1
                    onClicked: if (canSwitch) out.run([out.on ? "off" : "on"])
                    Switch {
                        objectName: "displaySwitch_" + out.index
                        controlled: true
                        checked: out.on
                        enabled: power.canSwitch
                        onToggled: want => out.run([want ? "on" : "off"])
                    }
                }
                ListItem {
                    objectName: "displayBrightness_" + out.index
                    visible: !!out.light
                    width: page.width
                    position: page.segment(1, out.rows)
                    tone: Colors.surfaceContainer
                    iconName: "brightness_medium"
                    text: "Brightness"
                    Slider {
                        id: lightSlider
                        objectName: "displayBrightnessSlider_" + out.index
                        anchors.verticalCenter: parent?.verticalCenter
                        width: 200
                        ticks: false
                        onMoved: v => page.backend.setBrightness(out.light.id, v)
                        Binding on value {
                            value: out.light?.value ?? 0
                            when: !lightSlider.pressed
                        }
                    }
                }
                ChoiceRow {
                    visible: out.on
                    app: page.app
                    key: out.key + ".resolution"
                    width: page.width
                    position: page.segment(1 + out.b, out.rows)
                    iconName: "aspect_ratio"
                    text: "Resolution"
                    choices: out.resolutions.map(r => r.label)
                    current: out.mode ? Display.resolutionLabel(out.mode) : ""
                    onChosen: index => {
                        const r = out.resolutions[index];
                        const m = Display.modeFor(out.modelData, r.width, r.height);
                        if (m) out.run(["mode", Display.modeArg(m)]);
                    }
                }
                ChoiceRow {
                    visible: out.on
                    app: page.app
                    key: out.key + ".rate"
                    width: page.width
                    position: page.segment(2 + out.b, out.rows)
                    iconName: "speed"
                    text: "Refresh rate"
                    choices: out.rates.map(m => Display.rateLabel(m.refresh_rate))
                    current: out.mode ? Display.rateLabel(out.mode.refresh_rate) : ""
                    onChosen: index => out.run(["mode", Display.modeArg(out.rates[index])])
                }
                ChoiceRow {
                    visible: out.on
                    app: page.app
                    key: out.key + ".scale"
                    width: page.width
                    position: page.segment(3 + out.b, out.rows)
                    iconName: "zoom_in"
                    text: "Display size"
                    supportingText: "How large everything is drawn"
                    choices: out.scales.map(Display.scaleLabel)
                    current: Display.scaleLabel(out.modelData.logical?.scale ?? 1)
                    onChosen: index => out.run(["scale", String(out.scales[index])])
                }
                ChoiceRow {
                    visible: out.on
                    app: page.app
                    key: out.key + ".transform"
                    width: page.width
                    position: page.segment(4 + out.b, out.rows)
                    iconName: "screen_rotation"
                    text: "Orientation"
                    supportingText: "Turned counter-clockwise"
                    choices: Display.TRANSFORMS.map(t => t[2])
                    current: Display.transformLabel(out.modelData.logical?.transform ?? "Normal")
                    onChosen: index => out.run(["transform", Display.TRANSFORMS[index][1]])
                }
                ListItem {
                    id: vrrRow
                    objectName: "displayVrr_" + out.index
                    visible: out.vrr
                    width: page.width
                    position: page.segment(5 + out.b, out.rows)
                    tone: Colors.surfaceContainer
                    iconName: "animation"
                    text: "Variable refresh rate"
                    supportingText: "Smoother games and video, where the display allows"
                    onClicked: out.run(["vrr", out.modelData.vrr_enabled ? "off" : "on"])
                    Switch {
                        objectName: "displayVrrSwitch_" + out.index
                        controlled: true
                        checked: out.modelData.vrr_enabled
                        onToggled: want => out.run(["vrr", want ? "on" : "off"])
                    }
                }
                ListItem {
                    objectName: "displayReset_" + out.index
                    visible: out.kept
                    width: page.width
                    position: "last"
                    tone: Colors.surfaceContainer
                    iconName: "restart_alt"
                    text: "Back to niri's config"
                    supportingText: "Rutile keeps these choices for this display, over niri's own config"
                    onClicked: page.backend.reset(out.modelData.name)
                }
            }
        }
    }
}
