// The sign-in itself (plan 6.2, D97), over Quickshell's Greetd: `begin()` asks greetd to sign `user` in, and greetd's
// questions come back as `prompt` (with `secret` for a password); `answer(text)` replies. Messages that need no
// answer show as `info`, or `error`. A failed sign-in sets `error` and begins again, so the next try is a new
// session. Once greetd is ready, `ready()` fires: the owner saves what it remembers and plays its motion, then
// calls `launch(session)`, and greetd starts the session when the greeter quits (`quitOnLaunch`; the tests keep it
// running).
import QtQuick
import Quickshell
import Quickshell.Services.Greetd
import "Greeter.js" as Greeter

Scope {
    id: root

    property string user: ""
    property bool quitOnLaunch: true
    property string phase: "idle"           // idle | waiting (for greetd) | prompt | ready | launching
    property string prompt: ""
    property bool secret: true
    property string info: ""
    property string error: ""
    readonly property bool available: Greetd.available

    signal ready()

    function begin() {
        if (user === "" || !Greetd.available) return;
        prompt = "";
        info = "";
        phase = "waiting";
        // another person chosen mid-way: end that session first, and begin once greetd has answered (see `restart`)
        if (Greetd.state !== GreetdState.Inactive) {
            Greetd.cancelSession();
            restart.restart();
            return;
        }
        Greetd.createSession(user);
    }
    function answer(text) {
        if (phase !== "prompt") return;
        phase = "waiting";
        Greetd.respond(text);
    }
    function cancel() {
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        phase = "idle";
        prompt = "";
    }
    function launch(session) {
        if (phase !== "ready" || !session) return;
        phase = "launching";
        Greetd.launch(Greeter.launchCommand(session), Greeter.sessionEnv(session), quitOnLaunch);
    }

    property string failureText: "Wrong password. Try again."
    property bool started: false
    property bool again: false              // a failed sign-in: begin again once greetd has ended it
    onUserChanged: {
        error = "";
        if (started) begin();
    }
    Component.onCompleted: {
        started = true;
        begin();
    }

    // A cancel (Quickshell's own after a failure, or ours) makes it Inactive at once, before greetd's reply to the
    // cancel; a session begun before that reply takes it for its own ("unexpected greetd response") and its answers
    // fall out of step with greetd's questions.
    Timer {
        id: restart
        interval: 300
        onTriggered: root.begin()
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            if (responseRequired) {
                root.prompt = message;
                root.secret = !echoResponse;
                root.phase = "prompt";
            } else if (isError) {
                root.error = message;
            } else {
                root.info = message;
            }
        }
        // greetd's reason is PAM's ("pam_authenticate: AUTH_ERR"): the log gets it, the person a sentence
        function onAuthFailure(message) {
            console.warn("greeter: sign-in failed:", message);
            root.error = root.failureText;
            root.again = true;
            root.phase = "waiting";
        }
        function onStateChanged() {
            if (root.again && Greetd.state === GreetdState.Inactive) {
                root.again = false;
                restart.start();
            }
        }
        function onReadyToLaunch() {
            root.phase = "ready";
            root.ready();
        }
        // greetd drops the connection after a failed sign-in, and the reconnect's error is not the person's
        function onError(message) {
            console.warn("greeter: greetd:", message);
            if (root.again || restart.running) return;
            root.error = message;
            root.phase = "idle";
        }
    }
}
