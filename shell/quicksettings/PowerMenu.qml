// The menu under Quick Settings' power button (Googlebook's power button with a chevron): lock, sign out, restart
// and shut down as a segmented list. It only reports the choice; the panel asks the backend to act. A full-screen
// power menu over a blurred desktop is planned to replace it (plan 2.8).
import QtQuick
import qs.components
import "PowerActions.js" as PowerActions

Menu {
    items: PowerActions.actions
    itemPrefix: "qsPower_"
}
