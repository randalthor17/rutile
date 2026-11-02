// Sound (plan 5.2): the output and the input, each with its volume, mute and the devices to choose from. A page
// view: the app sets `app`, `store` and `backend` (SoundBackend.qml, or the tests' fake), which has
//   available; outputs, inputs: [{id, name}]; output, input: the default's id (-1: none);
//   volume, muted, inputVolume, inputMuted; setOutput(id), setInput(id), setVolume(v), setMuted(b),
//   setInputVolume(v), setInputMuted(b).
// The two groups are `setting_sound.output` and `setting_sound.input`, which search marks (Pages.js entries).
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

Column {
    id: page
    property var app: null
    property var store: null
    property var backend: null

    readonly property bool available: backend?.available ?? false

    spacing: Spacing.xl

    ListItem {
        objectName: "soundUnavailable"
        visible: !page.available
        width: page.width
        iconName: "volume_off"
        text: "No sound service"
        supportingText: "PipeWire is not running"
    }

    Repeater {
        model: page.available ? ["output", "input"] : []
        delegate: Column {
            id: group
            required property string modelData
            readonly property bool isOutput: modelData === "output"
            readonly property var devices: (isOutput ? page.backend.outputs : page.backend.inputs) ?? []
            readonly property int current: isOutput ? page.backend.output : page.backend.input
            readonly property real volume: isOutput ? page.backend.volume : page.backend.inputVolume
            readonly property bool muted: isOutput ? page.backend.muted : page.backend.inputMuted
            readonly property int rows: 1 + Math.max(1, devices.length)

            objectName: "setting_sound." + modelData
            width: page.width
            spacing: ControlSpec.listSpec.segmentedGap

            function setVolume(v) {
                if (isOutput) page.backend.setVolume(v);
                else page.backend.setInputVolume(v);
            }
            function setMuted(m) {
                if (isOutput) page.backend.setMuted(m);
                else page.backend.setInputMuted(m);
            }

            Text {
                height: implicitHeight + Spacing.sm
                leftPadding: Spacing.lg
                text: group.isOutput ? "Output" : "Input"
                color: Colors.primary
                font: Type.font(Type.titleSmall)
            }
            ListItem {
                objectName: "soundVolume_" + group.modelData
                width: group.width
                position: page.app ? page.app.segment(0, group.rows) : "first"
                tone: Colors.surfaceContainer
                iconName: group.isOutput ? (group.muted ? "volume_off" : "volume_up") : (group.muted ? "mic_off" : "mic")
                text: "Volume"
                trailingText: group.muted ? "Muted" : Math.round(group.volume * 100) + "%"
                enabled: group.current >= 0
                onClicked: group.setMuted(!group.muted)
                Row {
                    spacing: Spacing.sm
                    Slider {
                        objectName: "soundSlider_" + group.modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 200
                        value: group.volume
                        enabled: group.current >= 0
                        onMoved: v => group.setVolume(v)
                    }
                    IconButton {
                        objectName: "soundMute_" + group.modelData
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: group.isOutput ? (group.muted ? "volume_off" : "volume_up")
                                                 : (group.muted ? "mic_off" : "mic")
                        toggle: true
                        checked: group.muted
                        enabled: group.current >= 0
                        Accessible.name: group.muted ? "Unmute" : "Mute"
                        onClicked: group.setMuted(!group.muted)
                    }
                }
            }
            ListItem {
                visible: group.devices.length === 0
                width: group.width
                position: "last"
                tone: Colors.surfaceContainer
                text: group.isOutput ? "No output devices" : "No microphones"
                enabled: false
            }
            Repeater {
                model: group.devices
                delegate: ListItem {
                    id: device
                    required property var modelData
                    required property int index
                    readonly property bool chosen: modelData.id === group.current
                    objectName: "soundDevice_" + group.modelData + "_" + index
                    width: group.width
                    position: page.app ? page.app.segment(index + 1, group.rows) : "middle"
                    tone: Colors.surfaceContainer
                    iconName: group.isOutput ? "speaker" : "mic"
                    text: modelData.name
                    selected: chosen
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: chosen
                    onClicked: {
                        if (group.isOutput) page.backend.setOutput(modelData.id);
                        else page.backend.setInput(modelData.id);
                    }
                    Icon {
                        visible: device.chosen
                        name: "check"
                        color: Colors.primary
                    }
                }
            }
        }
    }
}
