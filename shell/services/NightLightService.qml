// Night light (D91): the screen's colors warmed by wlsunset while the Quick Settings tile is on. wlsunset has no
// "always" mode, so it gets its night temperature and one kelvin more for the day: warm at any hour. The switch is
// kept in state.json, so Night light comes back on with the shell; the warmth is Settings > Display's
// (`nightLight.temperature`), and a change restarts wlsunset. `available` is false without wlsunset on PATH. When it
// stops by itself (another program holds the screen's gamma, such as gammastep; or the compositor has no gamma control,
// as niri nested in a window), the switch goes off, `error` says why and a toast shows it.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    readonly property bool on: Settings.stateValue("nightLight.on", false) === true
    readonly property int temperature: Settings.value("nightLight.temperature") ?? 4000
    readonly property bool running: sunset.running
    property string error: ""

    function setOn(wanted) {
        if (wanted) error = "";
        Settings.setState("nightLight.on", wanted);
    }

    // what runs: the night temperature all day
    function command(t) {
        return ["wlsunset", "-t", String(t), "-T", String(t + 1)];
    }
    function sync() {
        const want = available && on;
        if (!want) {
            sunset.running = false;
            return;
        }
        restarting = sunset.running;            // a new warmth: stop, and start again once stopped
        sunset.running = false;
        sunset.command = command(temperature);
        if (!restarting) sunset.running = true;
    }
    property bool restarting: false

    onOnChanged: sync()
    onTemperatureChanged: sync()
    onAvailableChanged: sync()

    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.available = code === 0
    }
    Process {
        id: sunset
        stderr: StdioCollector { id: sunsetErr }
        onExited: code => {
            if (root.restarting) {
                root.restarting = false;
                sunset.running = true;
                return;
            }
            if (root.on && root.available) {
                // wlsunset's last line says why: no gamma control in the compositor, or another program holds it
                const why = sunsetErr.text.trim().split("\n").pop();
                root.error = "Night light stopped" + (why ? ": " + why : "");
                Settings.setState("nightLight.on", false);
                ToastService.show(root.error, { icon: "nightlight" });
            }
        }
    }
}
