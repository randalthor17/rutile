// The battery source (plan 4.2, D79): UPower's display device, when it is a laptop battery.
import QtQuick
import qs.widgethost
import Quickshell.Services.UPower
import "../Sources.js" as Sources

WidgetSource {
    id: root
    readonly property var device: UPower.displayDevice
    readonly property bool present: !!device && device.ready && device.isLaptopBattery
    value: Sources.battery({
        present: present, percentage: present ? device.percentage : 0,
        state: !present ? "" : device.state === UPowerDeviceState.Charging ? "charging"
             : device.state === UPowerDeviceState.PendingCharge ? "pending"
             : device.state === UPowerDeviceState.FullyCharged ? "full"
             : device.state === UPowerDeviceState.Empty ? "empty" : "discharging",
        timeToFull: present ? device.timeToFull : 0, timeToEmpty: present ? device.timeToEmpty : 0
    })
}
