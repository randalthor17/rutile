// The battery through Quickshell's UPower service: the aggregate display device, shown only when it is a
// laptop battery (desktops have none). `percentage` is 0..1 (UPower's energy / energyCapacity).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    readonly property var device: UPower.displayDevice
    readonly property bool batteryAvailable: !!device && device.ready && device.isLaptopBattery
    readonly property real battery: batteryAvailable ? device.percentage : 0
    readonly property bool charging: batteryAvailable
        && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.FullyCharged
            || device.state === UPowerDeviceState.PendingCharge)
}
