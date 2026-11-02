// The Power page's backend (PowerPage.qml has the interface): the battery through Quickshell's UPower (the
// aggregate display device, when it is a laptop battery) and the power mode through PowerProfiles
// (power-profiles-daemon). Quickshell cannot tell whether that daemon is there, so `busctl` looks for its name on
// the system bus once, when the page opens (the window loads this only then, D31).
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool batteryAvailable: !!device && device.ready && device.isLaptopBattery
    readonly property real battery: batteryAvailable ? device.percentage : 0
    readonly property string state: {
        if (!batteryAvailable) return "";
        switch (device.state) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.PendingCharge: return "pending";
        case UPowerDeviceState.FullyCharged: return "full";
        case UPowerDeviceState.Empty: return "empty";
        default: return "discharging";
        }
    }
    readonly property real timeToFull: batteryAvailable ? device.timeToFull : 0
    readonly property real timeToEmpty: batteryAvailable ? device.timeToEmpty : 0
    readonly property real health: batteryAvailable && device.healthSupported ? device.healthPercentage / 100 : -1

    property bool profilesAvailable: false
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property string profile: PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
                                    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    // apps holding a mode (a game holding Performance, say): [{profile, app, reason}]
    readonly property var holds: (PowerProfiles.holds ?? []).map(h => ({
        profile: h.profile === PowerProfile.PowerSaver ? "power-saver" : h.profile === PowerProfile.Performance ? "performance" : "balanced",
        app: h.applicationId ?? "", reason: h.reason ?? ""
    }))

    function setProfile(name) {
        if (!profilesAvailable) return;
        if (name === "performance" && !hasPerformance) return;
        PowerProfiles.profile = name === "power-saver" ? PowerProfile.PowerSaver
                              : name === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
    }

    Process {
        running: true
        command: ["busctl", "--system", "list", "--no-legend", "--no-pager"]
        stdout: StdioCollector {
            onStreamFinished: root.profilesAvailable = /^(net\.hadess|org\.freedesktop\.UPower)\.PowerProfiles\s/m.test(text)
        }
    }
}
