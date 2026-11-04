//@ pragma IconTheme Papirus-Dark
// Rutile's greeter (plan 6.2, D97): the sign-in screen greetd shows, in the shell's look. Run by greetd inside a niri
// of its own (nixosModules.greeter):   rutile-shell greeter   (quickshell -p shell/greeter.qml)
// It reads the people from /etc/passwd, the sessions from the data directories' wayland-sessions, and remembers who
// signed in last, into which session, in /var/lib/rutile-greeter/greeter/state.json (RUTILE_GREETER_STATE). It shows
// the chosen person's wallpaper and colors, which their shell copies to /var/lib/rutile-greeter/users/<name>
// (RUTILE_GREETER_USERS; it cannot read anyone's home, D98); without them, RUTILE_GREETER_WALLPAPER and RUTILE_PALETTE
// (the system's), else Rutile's own wallpaper.
// For the tests: RUTILE_PASSWD replaces /etc/passwd, RUTILE_SESSION_DIRS (colon-separated) the data directories,
// RUTILE_GREETER_NO_QUIT keeps it running after a launch.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.greeter
import "greeter/Greeter.js" as Greeter
import "services/Files.js" as Files

ShellRoot {
    id: greeter

    readonly property string statePath: Quickshell.env("RUTILE_GREETER_STATE")
        || "/var/lib/rutile-greeter/greeter/state.json"
    readonly property string usersDir: Quickshell.env("RUTILE_GREETER_USERS") || "/var/lib/rutile-greeter/users"
    // GNOME Settings' pictures (AccountsService), after the one each person's shell shares (D99)
    readonly property string accountsIcons: Quickshell.env("RUTILE_ACCOUNTS_ICONS") || "/var/lib/AccountsService/icons"
    property string avatar: ""
    readonly property string builtinWallpaper: Quickshell.shellDir + "/../theme/wallpapers/rutile-default.jpg"
    // the chosen person's, else the system's (D98)
    property string wallpaper: ""
    property string palette: Quickshell.env("RUTILE_PALETTE")
    readonly property var dataDirs: (Quickshell.env("RUTILE_SESSION_DIRS")
                                     || [Quickshell.env("XDG_DATA_DIRS"), "/run/current-system/sw/share",
                                         "/usr/local/share", "/usr/share"].filter(d => !!d).join(":"))
                                    .split(":").filter(d => d !== "")
    property var users: []
    property var sessions: []
    property var saved: ({})
    property string user: ""
    property string sessionId: ""
    property bool leaving: false
    readonly property var session: sessions.find(s => s.id === sessionId) ?? null

    // what is shown first, once the people, the sessions and the saved state are read
    property bool chosen: false
    function choose() {
        if (chosen || !passwd.loaded || !stateFile.done || !sessionsRead.done) return;
        chosen = true;
        user = Greeter.initialUser(users, saved);
        sessionId = Greeter.initialSession(sessions, saved, user);
    }
    function chooseUser(name) {
        if (!users.some(u => u.name === name)) return false;
        user = name;
        sessionId = Greeter.initialSession(sessions, saved, name);
        return true;
    }

    PaletteWatcher {
        path: greeter.palette
    }
    // later: the commands' bindings take the new person after this handler (LESSONS)
    onUserChanged: Qt.callLater(pickLooks)
    // a person chosen while the last one's are still being looked up: look again after
    property bool lookAgain: false
    function pickLooks() {
        if (wallpaperPick.running || palettePick.running || avatarPick.running) {
            lookAgain = true;
            return;
        }
        wallpaperPick.running = true;
        palettePick.running = true;
        avatarPick.running = true;
    }
    function looked() {
        if (wallpaperPick.running || palettePick.running || avatarPick.running || !lookAgain) return;
        lookAgain = false;
        pickLooks();
    }
    Process {
        id: wallpaperPick
        command: Files.firstReadableCommand([greeter.usersDir + "/" + greeter.user + "/wallpaper",
                                               Quickshell.env("RUTILE_GREETER_WALLPAPER"), greeter.builtinWallpaper])
        stdout: StdioCollector { onStreamFinished: greeter.wallpaper = text }
        onExited: greeter.looked()
    }
    Process {
        id: palettePick
        command: Files.firstReadableCommand([greeter.usersDir + "/" + greeter.user + "/palette.json",
                                               Quickshell.env("RUTILE_PALETTE")])
        stdout: StdioCollector { onStreamFinished: if (text !== "") greeter.palette = text }
        onExited: greeter.looked()
    }
    // their picture (D99): the ~/.face their shell shared, else GNOME Settings' one, else their initial ("")
    Process {
        id: avatarPick
        command: Files.firstReadableCommand([greeter.usersDir + "/" + greeter.user + "/avatar",
                                             greeter.accountsIcons + "/" + greeter.user])
        stdout: StdioCollector { onStreamFinished: greeter.avatar = text }
        onExited: greeter.looked()
    }

    FileView {
        id: passwd
        property bool loaded: false
        path: Quickshell.env("RUTILE_PASSWD") || "/etc/passwd"
        onLoaded: {
            greeter.users = Greeter.users(text());
            loaded = true;
            greeter.choose();
        }
    }
    FileView {
        id: stateFile
        property bool done: false
        path: greeter.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            greeter.saved = Greeter.parseState(text());
            done = true;
            greeter.choose();
        }
        onLoadFailed: {
            done = true;
            greeter.choose();
        }
    }
    Process {
        id: sessionsRead
        property bool done: false
        running: true
        command: Greeter.sessionsCommand(greeter.dataDirs)
        stdout: StdioCollector {
            onStreamFinished: {
                greeter.sessions = Greeter.sessions(text);
                sessionsRead.done = true;
                greeter.choose();
            }
        }
    }

    GreeterSession {
        id: auth
        user: greeter.chosen ? greeter.user : ""
        quitOnLaunch: !Quickshell.env("RUTILE_GREETER_NO_QUIT")
        // signed in: remember, play the motion out, then start the session
        onReady: {
            greeter.saved = Greeter.remembered(greeter.saved, greeter.user, greeter.sessionId);
            stateFile.setText(JSON.stringify(greeter.saved));
            greeter.leaving = true;
        }
    }
    function launchWhenGone() {
        if (leaving && motion.settled && motion.value < 0.001) auth.launch(session);
    }

    // in when it starts, out once signed in: LockPanel's motion
    Spring {
        id: motion
        value: 0
        target: greeter.leaving ? 0 : 1
        onSettledChanged: greeter.launchWhenGone()
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: power
    }
    function runPower(action) {
        if (action !== "poweroff" && action !== "reboot") return false;
        power.command = ["systemctl", action];
        power.running = true;
        return true;
    }

    Variants {
        model: Quickshell.screens
        GreeterWindow {
            id: window
            required property var modelData
            screen: modelData
            keyboard: modelData === Quickshell.screens[0]
            GreeterPanel {
                anchors.fill: parent
                now: clock.date
                users: greeter.users
                user: greeter.user
                sessions: greeter.sessions
                session: greeter.sessionId
                prompt: auth.prompt
                secret: auth.secret
                busy: auth.phase === "waiting" || auth.phase === "ready" || auth.phase === "launching"
                error: auth.error
                info: auth.info
                wallpaper: greeter.wallpaper
                avatar: greeter.avatar
                progress: motion.value
                onSubmitted: text => auth.answer(text)
                onEdited: auth.error = ""
                onUserChosen: name => greeter.chooseUser(name)
                onSessionChosen: id => greeter.sessionId = id
                onPowerRequested: action => greeter.runPower(action)
            }
        }
    }

    // For the smoke test and diagnostics: quickshell -p shell/greeter.qml ipc call greeter state
    IpcHandler {
        target: "greeter"
        function state(): string {
            return JSON.stringify({ users: greeter.users.map(u => u.name), user: greeter.user,
                                    sessions: greeter.sessions.map(s => s.id), session: greeter.sessionId,
                                    phase: auth.phase, prompt: auth.prompt, secret: auth.secret, error: auth.error,
                                    available: auth.available, leaving: greeter.leaving, progress: motion.value,
                                    settled: motion.settled, wallpaper: greeter.wallpaper, palette: greeter.palette,
                                    avatar: greeter.avatar,
                                    saved: greeter.saved });
        }
        // as typing it and pressing Enter
        function answer(text: string): bool {
            if (auth.phase !== "prompt") return false;
            auth.answer(text);
            return true;
        }
        function chooseUser(name: string): bool { return greeter.chooseUser(name); }
        function chooseSession(id: string): bool {
            if (!greeter.sessions.some(s => s.id === id)) return false;
            greeter.sessionId = id;
            return true;
        }
    }
}
