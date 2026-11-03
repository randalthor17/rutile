// Night light (D91): the screen's colors warmed by wlsunset while the Quick Settings tile is on: all day, or from
// sunset to sunrise (`nightLight.schedule`; NightLight.js builds the command). The switch is kept in state.json, so
// Night light comes back on with the shell; the rest is Settings > Display's (`nightLight.*`), and a change to it
// restarts wlsunset. `available` is false without wlsunset on PATH. When it
// stops by itself (another program holds the screen's gamma, such as gammastep; or the compositor has no gamma control,
// as niri nested in a window), the switch goes off, `error` says why and a toast shows it.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NightLight.js" as NightLight

Singleton {
    id: root

    property bool available: false
    readonly property bool on: Settings.stateValue("nightLight.on", false) === true
    readonly property int temperature: Settings.value("nightLight.temperature") ?? 4000
    readonly property bool schedule: Settings.value("nightLight.schedule") === true
    readonly property var commandLine: NightLight.command({
        temperature: temperature, schedule: schedule,
        latitude: Settings.value("widgets.latitude") ?? null, longitude: Settings.value("widgets.longitude") ?? null,
        sunset: Settings.value("nightLight.sunset") ?? "19:00", sunrise: Settings.value("nightLight.sunrise") ?? "07:00"
    })
    readonly property bool running: sunset.running
    property string error: ""

    function setOn(wanted) {
        if (wanted) error = "";
        Settings.setState("nightLight.on", wanted);
    }

    function sync() {
        const want = available && on;
        if (!want) {
            sunset.running = false;
            return;
        }
        // a new command: stop, and start again once stopped (a second change while it stops only changes the command;
        // the process reads as running until it has exited)
        restarting = sunset.running;
        sunset.running = false;
        sunset.command = commandLine;
        if (!restarting) sunset.running = true;
    }
    property bool restarting: false

    onOnChanged: sync()
    onCommandLineChanged: sync()
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
