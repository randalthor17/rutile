// The greeter's sign-in (plan 6.2, D97) against greetd's own stand-in, fakegreet (only the user "user": "password",
// then "7 + 2:" answered "9"): greetd's questions come through as prompts, secret or visible; a wrong answer fails and
// begins again; the right ones make it ready, and launching asks greetd to start the session.
// under fakegreet
import QtQuick
import Quickshell
import Quickshell.Services.Greetd
import qs.greeter

ShellRoot {
    id: root
    property int stage: 0
    property bool launchedSeen: false
    property int readyCount: 0
    QsTest { id: t }

    GreeterSession {
        id: session
        user: "user"
        quitOnLaunch: false
        onReady: root.readyCount++
    }
    Connections {
        target: Greetd
        function onLaunched() { root.launchedSeen = true; }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (ticks > 100) {
                t.verify(false, "timed out at stage " + root.stage + ", phase " + session.phase + ", prompt " + session.prompt);
                t.done();
                running = false;
                return;
            }
            if (root.stage === 0 && session.phase === "prompt") {
                t.verify(session.available, "greetd's socket is there");
                t.compare(session.prompt, "Password:", "the first question");
                t.verify(session.secret, "a password is hidden");
                session.answer("password");
                root.stage = 1;
            } else if (root.stage === 1 && session.phase === "prompt") {
                t.compare(session.prompt, "7 + 2:", "the second question");
                t.verify(!session.secret, "a visible question");
                session.answer("1");
                root.stage = 2;
            } else if (root.stage === 2 && session.error !== "" && session.phase === "prompt") {
                t.compare(session.error, "Wrong password. Try again.", "a sentence, not greetd's reason");
                t.compare(session.prompt, "Password:", "begun again: a new session asks again");
                session.answer("password");
                root.stage = 3;
            } else if (root.stage === 3 && session.phase === "prompt" && session.prompt === "7 + 2:") {
                session.answer("9");
                root.stage = 4;
            } else if (root.stage === 4 && session.phase === "ready") {
                t.compare(root.readyCount, 1, "ready once");
                session.launch({ id: "niri", desktop: "niri", command: ["niri-session"] });
                t.compare(session.phase, "launching", "launching");
                root.stage = 5;
            } else if (root.stage === 5 && root.launchedSeen) {
                t.compare(Greetd.state, GreetdState.Launched, "greetd took the session");
                t.done();
                running = false;
            }
        }
    }
}
