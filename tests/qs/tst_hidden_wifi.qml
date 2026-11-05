// Joining a hidden network (D100) through the real hidden-wifi.sh with a stand-in nmcli (tests/qs/bin/nmcli; never
// the real one): a new network is added as hidden and joined, its password going in on stdin and never in any
// arguments; a saved one is reused; one that cannot be joined is removed again and shows a toast.
// env PATH=@WS@/bin:@PATH@
// env FAKE_NMCLI_LOG=@WS@/nmcli.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property bool ready: false              // the saved networks are written
    readonly property string log: Quickshell.env("FAKE_NMCLI_LOG")
    QsTest { id: t }
    FileView {
        id: logFile
        path: root.log
        blockLoading: true
        printErrors: false
    }
    // the saved networks, written before anything starts: a FileView's write lands later, and under load the
    // saved one's join could look before it had
    Process {
        id: known
        running: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "Saved Open\\n" > "$1"', "sh", root.log + ".known"]
        onExited: root.ready = true
    }
    function lines() {
        logFile.reload();
        return logFile.text().split("\n").filter(l => l);
    }
    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            const n = NetworkService;
            const l = root.lines();
            if (!root.ready) return;
            switch (root.stage) {
            case 0:
                t.verify(n.joinHiddenWifi("Secret Lab", "pa ss; $word"), "a join starts");
                t.verify(n.hiddenJoining, "joining");
                t.compare(n.hiddenName, "Secret Lab");
                t.verify(!n.joinHiddenWifi("Other", ""), "one at a time");
                t.verify(!n.joinHiddenWifi("", ""), "a name is needed");
                break;
            case 1:
                if (n.hiddenJoining || l.length < 4) return;
                t.compare(l.join("\n"), [
                    "connection show id Secret Lab",
                    "connection add type wifi con-name Secret Lab ifname * ssid Secret Lab 802-11-wireless.hidden yes wifi-sec.key-mgmt wpa-psk",
                    "--wait 90 connection up id Secret Lab passwd-file /dev/stdin",
                    "stdin: 802-11-wireless-security.psk:pa ss; $word"].join("\n"), "added as hidden, joined, the password on stdin");
                t.compare(ToastService.current, null, "no toast for a success");
                t.verify(n.joinHiddenWifi("Saved Open", ""), "a saved one");
                break;
            case 2:
                if (n.hiddenJoining || l.length < 7) return;
                t.compare(l.slice(4).join("\n"), [
                    "connection show id Saved Open",
                    "connection modify id Saved Open 802-11-wireless.hidden yes",
                    "--wait 90 connection up id Saved Open"].join("\n"), "reused and marked hidden; no password");
                t.verify(n.joinHiddenWifi("nowhere", ""), "one that is not there");
                break;
            case 3:
                if (n.hiddenJoining || l.length < 11) return;
                t.compare(l.slice(7).join("\n"), [
                    "connection show id nowhere",
                    "connection add type wifi con-name nowhere ifname * ssid nowhere 802-11-wireless.hidden yes",
                    "--wait 90 connection up id nowhere",
                    "connection delete id nowhere"].join("\n"), "removed again when it fails");
                t.compare(ToastService.current?.text, "Couldn't join nowhere");
                t.verify(l.every(x => x.startsWith("stdin:") || x.indexOf("pa ss") < 0), "no password in any arguments");
                t.done();
                return;
            }
            root.stage++;
        }
    }
}
