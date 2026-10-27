// The polkit agent's dialog (plan 2.8): an app asks for an administrator's permission (pkexec, a disk mount, a
// package install) and the shell asks for the password. A card in the middle of the screen over the blurred desktop
// (PolkitWindow), like the power menu: what is asked (`message`), as whom (the identities polkit offers; chips to
// pick another when there are several), the password field (shown as typed only when polkit says so) and Cancel /
// Authenticate. Enter sends the password, Escape cancels. A wrong password shakes the field and says so; polkit
// starts the next try by itself.
// `flow` is Quickshell's AuthFlow, or anything with its properties, functions and signals (the tests' fake). The
// dialog closes itself once the flow is done (succeeded or cancelled) or gone: the shared popup motion (D43) plays
// back and `hidden` fires. Plain QtQuick, so it tests offscreen; the window holds the agent.
pragma ComponentBehavior: Bound
import QtQuick
import qs.common
import qs.components

Item {
    id: root

    property var flow: null
    readonly property bool shown: !!flow && !flow.isCompleted && !flow.isCancelled
    readonly property bool asking: shown && flow.isResponseRequired
    readonly property var identities: flow?.identities ?? []
    property bool wrong: false           // the last try failed; cleared by typing
    // Kept from the flow, so the card does not empty while it closes.
    property string message: ""
    property string actionId: ""

    readonly property alias field: passwordInput
    readonly property alias card: card
    readonly property string errorText: {
        if (flow?.supplementaryIsError && flow.supplementaryMessage) return flow.supplementaryMessage;
        return wrong ? "Wrong password. Try again." : "";
    }
    readonly property string infoText: !flow?.supplementaryIsError ? (flow?.supplementaryMessage ?? "") : ""

    signal hidden()

    onFlowChanged: {
        wrong = false;
        passwordInput.text = "";
        if (!flow) return;
        message = flow.message;
        actionId = flow.actionId;
    }

    function submit() {
        if (!asking || passwordInput.text === "") return;
        const password = passwordInput.text;
        passwordInput.text = "";          // never kept in the item longer than needed
        wrong = false;
        flow.submit(password);
    }
    function cancel() {
        if (!shown) return;
        passwordInput.text = "";
        flow.cancelAuthenticationRequest();
    }
    function identityName(identity) {
        if (!identity) return "";
        return identity.displayName || identity.string || "";
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root.wrong = true;
            shake.restart();
        }
    }

    property real shakeOffset: 0
    SequentialAnimation {
        id: shake
        // motion-speed: each step's duration is Motion.duration()
        NumberAnimation { target: root; property: "shakeOffset"; to: Spacing.md; duration: Motion.duration(Motion.short2) } // motion-speed: Motion.duration
        NumberAnimation { target: root; property: "shakeOffset"; to: -Spacing.md; duration: Motion.duration(Motion.short3) } // motion-speed: Motion.duration
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: Motion.duration(Motion.short2) } // motion-speed: Motion.duration
    }

    // The veil fades with the motion; the blur behind it is the compositor's.
    Rectangle {
        anchors.fill: parent
        color: Colors.surface
        opacity: 0.5 * motion.fade
    }
    // A click outside the card does nothing: a password prompt is not dismissed by accident.

    Surface {
        id: card
        objectName: "polkitCard"
        anchors.centerIn: parent
        width: 400
        height: column.implicitHeight + 2 * Spacing.xl
        tone: Colors.surfaceContainerHigh
        radius: Shapes.extraLarge

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: Spacing.xl
            spacing: Spacing.lg

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "admin_panel_settings"
                size: 32
                color: Colors.secondary
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Authentication required"
                color: Colors.surfaceOn
                font: Type.font(Type.headlineSmall)
            }
            Text {
                objectName: "polkitMessage"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.message
                color: Colors.surfaceVariantOn
                font: Type.font(Type.bodyMedium)
            }

            // As whom: the one identity, or chips when polkit offers several (an admin group's members).
            Text {
                objectName: "polkitIdentity"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: root.identities.length <= 1
                text: root.identityName(root.flow?.selectedIdentity)
                color: Colors.surfaceOn
                font: Type.font(Type.titleMedium)
            }
            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, implicitWidth)
                spacing: Spacing.sm
                visible: root.identities.length > 1
                Repeater {
                    model: root.identities.length > 1 ? root.identities : []
                    delegate: Chip {
                        required property var modelData
                        required property int index
                        objectName: "polkitIdentity_" + index
                        type: "filter"
                        controlled: true
                        text: root.identityName(modelData)
                        selected: root.flow?.selectedIdentity === modelData
                        onToggled: if (root.flow) root.flow.selectedIdentity = modelData
                    }
                }
            }

            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.shakeOffset
                width: parent.width
                height: 56
                radius: Shapes.full
                color: Colors.surfaceContainerHighest
                border.width: passwordInput.activeFocus ? 2 : 0
                border.color: root.errorText !== "" ? Colors.error : Colors.primary

                Icon {
                    id: keyIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.asking ? "key" : "hourglass_top"
                    color: Colors.surfaceVariantOn
                }
                TextInput {
                    id: passwordInput
                    objectName: "polkitPassword"
                    anchors.left: keyIcon.right
                    anchors.leftMargin: Spacing.md
                    anchors.right: parent.right
                    anchors.rightMargin: Spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    clip: true
                    readOnly: !root.asking
                    echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    color: Colors.surfaceOn
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.primaryOn
                    font: Type.font(Type.bodyLarge)
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.cancel()
                    onTextChanged: if (text !== "") root.wrong = false
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: passwordInput.text === ""
                        // polkit's prompt is PAM's ("Password: "); without the colon it reads as a placeholder
                        text: root.asking ? ((root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password")
                                          : "Checking…"
                        color: Colors.surfaceVariantOn
                        font: passwordInput.font
                    }
                }
            }

            Text {
                objectName: "polkitError"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.errorText !== "" ? root.errorText : root.infoText
                color: root.errorText !== "" ? Colors.error : Colors.surfaceVariantOn
                font: Type.font(Type.bodyMedium)
            }

            Row {
                anchors.right: parent.right
                spacing: Spacing.sm
                Button {
                    objectName: "polkitCancel"
                    type: "text"
                    size: "s"
                    text: "Cancel"
                    onClicked: root.cancel()
                }
                Button {
                    objectName: "polkitAuthenticate"
                    type: "filled"
                    size: "s"
                    text: "Authenticate"
                    enabled: root.asking && passwordInput.text !== ""
                    onClicked: root.submit()
                }
            }
        }
    }

    PopupMotion {
        id: motion
        target: card
        shown: root.shown
        origin: Item.Center
        onHidden: root.hidden()
    }
}
