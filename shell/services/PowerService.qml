// The battery through Quickshell's UPower service: the aggregate display device, shown only when it is a
// laptop battery (desktops have none). `percentage` is 0..1 (UPower's energy / energyCapacity).
// Low battery warnings (plan 2.13 B1, D136): while power.lowBatteryWarnings is on, a notification at 20% and 10%
// and a critical one at 5% (Battery.js), each once per discharge, sent to the session's notification server; the
// critical one stays until the computer is plugged in, then it is closed. What happens at the very end is UPower's
// (its critical action), which the critical one names.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Battery.js" as Battery

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool batteryAvailable: !!device && device.ready && device.isLaptopBattery
    readonly property real battery: batteryAvailable ? device.percentage : 0
    readonly property bool charging: batteryAvailable
        && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged
            || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool discharging: batteryAvailable && device.state === UPowerDeviceState.Discharging
    readonly property real timeToEmpty: batteryAvailable ? device.timeToEmpty : 0     // seconds, 0 unknown

    // ---- low battery warnings ----
    readonly property bool warnings: Settings.value("power.lowBatteryWarnings") !== false
    property var warned: []                 // Battery.LEVELS keys warned this discharge
    property int warningId: 0               // the warning shown, which the next replaces
    property bool warningCritical: false
    property string criticalAction: ""      // UPower's GetCriticalAction, read once there is a battery

    function check() {
        if (!discharging) {
            warned = [];
            if (warningCritical && warningId > 0) Quickshell.execDetached(Battery.closeCommand(warningId));
            warningCritical = false;
            return;
        }
        const level = warnings ? Battery.due(battery * 100, true, warned) : null;
        if (!level || sender.running) return;
        warned = Battery.warnedAfter(level);
        warningCritical = level.critical;
        sender.command = Battery.notifyCommand(Battery.message(level, battery * 100, timeToEmpty, criticalAction),
                                               warningId);
        sender.running = true;
    }
    onBatteryChanged: Qt.callLater(check)
    onDischargingChanged: Qt.callLater(check)
    onWarningsChanged: Qt.callLater(check)
    onBatteryAvailableChanged: if (batteryAvailable && criticalAction === "") actionReader.running = true

    Process {
        id: sender
        stdout: StdioCollector { onStreamFinished: root.warningId = Battery.parseId(text) || root.warningId }
        onExited: Qt.callLater(root.check)     // one that came due meanwhile
    }
    Process {
        id: actionReader
        command: ["busctl", "--system", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower",
                  "org.freedesktop.UPower", "GetCriticalAction"]
        stdout: StdioCollector {
            onStreamFinished: root.criticalAction = (/^s "(\w+)"/.exec(text.trim()) ?? ["", ""])[1]
        }
    }
}
