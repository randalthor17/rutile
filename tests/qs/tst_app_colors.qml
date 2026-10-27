// AppColorsService (D52): everything off by default, and then the tool is never started; an app's switch does
// nothing until the main switch is on; a palette change themes the apps again; the main switch off takes the
// colors back out once, and after that a palette change starts nothing. The tool is a stand-in that logs.
// env XDG_CONFIG_HOME=@WS@/appcolors-config
// env XDG_STATE_HOME=@WS@/appcolors-state
// env RUTILE_PALETTE=@WS@/appcolors-palette.json
// env RUTILE_APPTHEME_TOOL=@WS@/bin/fake-apptheme-tool
// env FAKE_APPTHEME_LOG=@WS@/appcolors.log
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

ShellRoot {
    id: root
    property int stage: 0
    property var lines: []
    QsTest { id: t }
    // the palette exists before the service watches it (a watch does not see a file appear)
    Process {
        id: writer
        running: true
        command: ["sh", "-c", 'echo "{\\"n\\": $(date +%N)}" > "$RUTILE_PALETTE"']
    }
    Process {
        id: reader
        command: ["sh", "-c", 'cat "$FAKE_APPTHEME_LOG" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.lines = text.split("\n").filter(l => l) }
    }
    Timer {
        interval: 800
        repeat: true
        running: true
        onTriggered: {
            if (reader.running || writer.running) return;
            const S = AppColorsService;
            switch (root.stage) {
            case 0:
                t.verify(!S.enabled, "off by default");
                t.compare(JSON.stringify(S.wanted), "[]", "no app");
                for (const a of S.apps) t.compare(Settings.value("appColors." + a), false, a + " off by default");
                reader.running = true;
                break;
            case 1:
                t.compare(root.lines.length, 0, "all off: the tool is never started");
                Settings.set("appColors.kitty", true);
                Settings.set("appColors.firefox", true);
                break;
            case 2:
                t.compare(JSON.stringify(S.wanted), "[]", "an app on, the main switch off: nothing");
                Settings.set("appColors.enabled", true);
                break;
            case 3:
                reader.running = true;
                break;
            case 4:
                t.compare(root.lines.length, 1, "one run for the switch");
                t.compare(root.lines[0], "sync --palette " + S.palettePath + " --apps kitty,firefox", "the apps on");
                t.compare(JSON.stringify(S.synced), '["kitty","firefox"]', "remembered");
                writer.running = true;                   // a new palette (a new wallpaper)
                break;
            case 5:
                reader.running = true;
                break;
            case 6:
                t.compare(root.lines.length, 2, "the palette changed: themed again");
                Settings.set("appColors.enabled", false);
                break;
            case 7:
                reader.running = true;
                break;
            case 8:
                t.compare(root.lines.length, 3, "the main switch off: one run");
                t.compare(root.lines[2], "sync --palette " + S.palettePath + " --apps ", "with no apps: undo all");
                t.compare(JSON.stringify(S.synced), "[]");
                writer.running = true;
                break;
            case 9:
                reader.running = true;
                break;
            case 10:
                t.compare(root.lines.length, 3, "off and undone: a new palette starts nothing");
                t.compare(S.lastError, "", "no error");
                t.done();
                break;
            default:
                return;
            }
            root.stage++;
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: { t.verify(false, "timed out at stage " + root.stage); t.done(); }
    }
}
