// Folder icons (D64) end to end, with the real Papirus-Dark found in XDG_DATA_DIRS (the dev shell has it) and real
// matugen, in a sandbox HOME: the switch makes the Rutile icon theme in XDG_DATA_HOME, its folders recolored from
// Papirus's blue, an index that inherits Papirus-Dark; a new palette recolors them; off removes the theme. Without
// Papirus-Dark it logs a skip.
// env RUTILE_PALETTE=@WS@/no-such/palette.json
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property int runsBefore: 0
    property string out: ""
    readonly property string theme: Quickshell.env("XDG_DATA_HOME") + "/icons/Rutile"
    QsTest { id: t }
    Process {
        id: look
        // the index, folder.svg and user-home.svg at 48 px, how many folder icons there are, and whether Papirus is found
        command: ["sh", "-c", 'papirus=no; IFS=:; for b in $XDG_DATA_DIRS; do [ -f "$b/icons/Papirus-Dark/index.theme" ] && papirus=yes; done; ' +
                  'echo "papirus=$papirus"; [ -d "$1" ] || { echo "theme=none"; exit 0; }; echo "theme=yes"; ' +
                  'echo "count=$(find "$1" -name "*.svg" | wc -l)"; cat "$1/index.theme"; ' +
                  'echo "@@folder"; cat "$1/48x48/places/folder.svg"; echo "@@home"; cat "$1/48x48/places/user-home.svg"; ' +
                  'echo "@@done"', "sh", root.theme]
        stdout: StdioCollector { onStreamFinished: root.out = text }
    }
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            const S = AppColorsService;
            if (look.running) return;
            switch (root.stage) {
            case 0:
                look.running = true;
                break;
            case 1:
                if (root.out.indexOf("papirus=yes") < 0) {
                    console.log("QSTEST SKIPPED: no Papirus-Dark in XDG_DATA_DIRS (nix develop has it)");
                    t.done();
                    root.stage = 100;
                    return;
                }
                Settings.set("appColors.folders", true);
                Settings.set("appColors.enabled", true);
                break;
            case 2:
                if (S.runs < 1) return;
                look.running = true;
                break;
            case 3: {
                t.compare(S.lastError, "", "no error");
                t.verify(root.out.indexOf("theme=yes") >= 0, "the theme is made: " + root.out.slice(0, 200));
                const count = Number((/count=(\d+)/.exec(root.out) || [])[1]);
                t.verify(count > 500, "Papirus's folder icons at every size: " + count);
                t.verify(root.out.indexOf("Inherits=Papirus-Dark,breeze-dark,hicolor") >= 0, "inherits Papirus-Dark");
                t.verify(/Directories=.*48x48\/places/.test(root.out) && root.out.indexOf("[48x48@2x/places]\nContext=Places\nSize=48\nScale=2") >= 0,
                         "its folders listed with their size and scale");
                const folder = root.out.split("@@folder")[1].split("@@home")[0];
                const home = root.out.split("@@home")[1].split("@@done")[0];
                t.verify(folder.indexOf("<svg") >= 0 && folder.indexOf("#5294e2") < 0 && folder.indexOf("#4877b1") < 0,
                         "folder.svg recolored from Papirus's blue: " + folder.slice(0, 300));
                t.verify(home.indexOf("<svg") >= 0 && home.indexOf("#5294e2") < 0 && home.indexOf("#1d344f") < 0, "user-home.svg too");
                root.colors = folder;
                root.runsBefore = S.runs;
                Settings.set("style.seed", "#9c2b2b");    // a new palette (no wallpaper: from the style's color, D65)
                break;
            }
            case 4:
                if (S.runs <= root.runsBefore) return;
                look.running = true;
                break;
            case 5: {
                const folder = root.out.split("@@folder")[1].split("@@home")[0];
                t.verify(folder !== root.colors && folder.indexOf("<svg") >= 0, "a new palette: new folder colors");
                root.runsBefore = S.runs;
                Settings.set("appColors.folders", false);
                break;
            }
            case 6:
                if (S.runs <= root.runsBefore) return;
                look.running = true;
                break;
            case 7:
                t.verify(root.out.indexOf("theme=none") >= 0, "off: the theme is gone");
                t.compare(S.synced.join(), "", "nothing themed");
                t.done();
                break;
            default:
                return;
            }
            root.stage++;
        }
    }
    property string colors: ""
    Timer {
        interval: 40000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
