//@ pragma IconTheme Papirus-Dark
// Rutile's greeter (plan 6.2, D97): the sign-in screen greetd shows, in the shell's look. Run by greetd inside a niri
// of its own (nixosModules.greeter):   rutile-shell greeter   (quickshell -p shell/greeter.qml)
// It reads the people from /etc/passwd, the sessions from the data directories' wayland-sessions, and remembers who
// signed in last, into which session, in /var/lib/rutile-greeter/state.json (RUTILE_GREETER_STATE). The wallpaper
// is RUTILE_GREETER_WALLPAPER (the greeter cannot read anyone's home); the colors, RUTILE_PALETTE as the shell's.
// For the tests: RUTILE_PASSWD replaces /etc/passwd, RUTILE_SESSION_DIRS (colon-separated) the data directories,
// RUTILE_GREETER_NO_QUIT keeps it running after a launch.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.greeter
import "greeter/Greeter.js" as Greeter

ShellRoot {
    id: greeter

    readonly property string statePath: Quickshell.env("RUTILE_GREETER_STATE") || "/var/lib/rutile-greeter/state.json"
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

    PaletteWatcher {}

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
                wallpaper: Quickshell.env("RUTILE_GREETER_WALLPAPER") || ""
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
                                    settled: motion.settled,
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
