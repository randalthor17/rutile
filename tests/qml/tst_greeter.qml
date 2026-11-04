import QtQuick
import QtTest
import qs.common
import qs.greeter
import "../qs/greeter/Greeter.js" as Greeter

TestCase {
    id: root
    name: "Greeter"
    width: 1000
    height: 700
    visible: true
    when: windowShown

    readonly property string passwd: "root:x:0:0:System administrator:/root:/run/current-system/sw/bin/bash\n" +
        "nixbld1:x:30001:30000:Nix build user 1:/var/empty:/run/current-system/sw/bin/nologin\n" +
        "rand:x:1000:100:Rand Al'Thor,,,:/home/rand:/run/current-system/sw/bin/bash\n" +
        "greeter:x:999:999::/var/empty:/run/current-system/sw/bin/nologin\n" +
        "rand-test:x:1001:100::/home/rand-test:/run/current-system/sw/bin/zsh\n" +
        "svc:x:1002:100::/var/empty:/bin/false\n" +
        "nobody:x:65534:65534:Unprivileged account:/var/empty:/run/current-system/sw/bin/nologin\nbroken line\n"

    function session(path, text) {
        return "\n" + Greeter.MARK + path + "\n" + text;
    }

    function test_users() {
        const u = Greeter.users(passwd);
        compare(u.map(x => x.name).join(), "rand,rand-test", "people only: uid 1000 and up with a login shell, by uid");
        compare(u[0].realName, "Rand Al'Thor", "the GECOS name's first part");
        compare(u[1].realName, "rand-test", "the name when there is none");
        compare(Greeter.users("").length, 0);
    }

    function test_sessions() {
        const text = session("/run/current-system/sw/share/wayland-sessions/niri.desktop",
                             "[Desktop Entry]\nName=Niri\nExec=niri-session\nDesktopNames=niri\nType=Application\n") +
                     session("/run/current-system/sw/share/wayland-sessions/sway.desktop",
                             "[Desktop Entry]\nName=Sway\nExec=sway --unsupported-gpu %U\n[Desktop Action x]\nExec=other\n") +
                     session("/usr/share/wayland-sessions/niri.desktop", "[Desktop Entry]\nName=Old niri\nExec=old\n") +
                     session("/x/wayland-sessions/hidden.desktop", "[Desktop Entry]\nName=Hidden\nExec=h\nHidden=true\n") +
                     session("/x/wayland-sessions/noexec.desktop", "[Desktop Entry]\nName=Nothing\n") +
                     session("/x/wayland-sessions/gnome.desktop",
                             "[Desktop Entry]\nName=GNOME\nExec=\"/nix/store/x y/bin/gnome-session\" --session=gnome\nDesktopNames=GNOME;\n");
        const s = Greeter.sessions(text);
        compare(s.map(x => x.id).join(), "gnome,niri,sway", "by name; hidden and Exec-less left out");
        const niri = s.find(x => x.id === "niri");
        compare(niri.name, "Niri", "the first directory's wins");
        compare(niri.command.join("|"), "niri-session");
        compare(s.find(x => x.id === "sway").command.join("|"), "sway|--unsupported-gpu", "field codes dropped; only [Desktop Entry]");
        const gnome = s.find(x => x.id === "gnome");
        compare(gnome.command.join("|"), "/nix/store/x y/bin/gnome-session|--session=gnome", "quotes");
        compare(gnome.desktop, "GNOME");
        compare(Greeter.sessionEnv(niri).join(" "), "XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=niri XDG_CURRENT_DESKTOP=niri");
        compare(Greeter.launchCommand(niri).join("|"), "niri-session", "as it is: greetd's shell reads /etc/profile");
        compare(Greeter.launchCommand(gnome).join(" "), "'/nix/store/x y/bin/gnome-session' --session=gnome",
                "a word with a space quoted for greetd's shell");
        compare(Greeter.launchCommand({ command: ["it's", "$HOME", "a;b"] }).join(" "), "'it'\\''s' '$HOME' 'a;b'",
                "quotes and anything else a shell reads");
        compare(Greeter.execArgs('a "b \\" c" 100%% %f').join("|"), 'a|b " c|100%');
        const cmd = Greeter.sessionsCommand(["/a", "/b"]);
        compare(cmd.slice(-2).join(), "/a,/b");
    }

    function test_choices_and_state() {
        const users = Greeter.users(passwd);
        const sessions = [{ id: "gnome" }, { id: "niri" }, { id: "sway" }];
        compare(Greeter.initialUser(users, {}), "rand", "the first person");
        compare(Greeter.initialUser(users, { lastUser: "rand-test" }), "rand-test", "the last one to sign in");
        compare(Greeter.initialUser(users, { lastUser: "gone" }), "rand", "someone no longer there");
        compare(Greeter.initialUser([], {}), "");
        compare(Greeter.initialSession(sessions, {}, "rand"), "niri", "niri by default");
        compare(Greeter.initialSession(sessions, { sessions: { rand: "sway" } }, "rand"), "sway", "the person's last");
        compare(Greeter.initialSession(sessions, { sessions: { rand: "gone" } }, "rand"), "niri");
        compare(Greeter.initialSession([{ id: "x" }], {}, "rand"), "x", "the first without niri");
        const st = Greeter.remembered({ lastUser: "a", sessions: { a: "niri" } }, "b", "sway");
        compare(JSON.stringify(st), '{"lastUser":"b","sessions":{"a":"niri","b":"sway"}}');
        compare(JSON.stringify(Greeter.parseState("not json")), "{}");
        compare(JSON.stringify(Greeter.parseState("3")), "{}");
        compare(Greeter.parseState(JSON.stringify(st)).lastUser, "b");
    }

    function test_first_readable() {
        const cmd = Greeter.firstReadableCommand(["/u/alice/wallpaper", "", "/builtin.jpg"]);
        compare(cmd.slice(0, 2).join(" "), "sh -c");
        compare(cmd.slice(-3).join(","), "/u/alice/wallpaper,,/builtin.jpg", "in order; an empty one skipped by the script");
    }

    function test_prompt_text() {
        compare(JSON.stringify(Greeter.promptText("Password: ", true)), '{"placeholder":"Password","message":""}');
        compare(JSON.stringify(Greeter.promptText("", true)), '{"placeholder":"Password","message":""}');
        compare(JSON.stringify(Greeter.promptText("7 + 2:", false)), '{"placeholder":"7 + 2","message":"7 + 2:"}');
        compare(Greeter.promptText("Verification code:", true).message, "Verification code:", "any other question shows");
    }

    // ---- the panel ----
    Component { id: panelComp; GreeterPanel {} }
    Component { id: spyComp; SignalSpy {} }
    function panel(props) {
        const p = createTemporaryObject(panelComp, root, Object.assign({
            width: 1000, height: 700, now: new Date(2026, 10, 4, 9, 30),
            users: Greeter.users(passwd), user: "rand",
            sessions: [{ id: "niri", name: "Niri", command: ["niri-session"], desktop: "niri" },
                       { id: "sway", name: "Sway", command: ["sway"], desktop: "sway" }],
            session: "niri", prompt: "Password:", secret: true }, props || {}));
        waitForRendering(p);
        return p;
    }

    function test_panel_shows_the_choice() {
        const p = panel();
        compare(p.face.user, "Rand Al'Thor", "the person's name");
        compare(p.face.placeholder, "Password");
        compare(p.face.message, "");
        compare(findChild(p, "greeterUser").text, "Rand Al'Thor");
        compare(findChild(p, "greeterSession").text, "Niri");
        p.prompt = "7 + 2:";
        p.secret = false;
        compare(p.face.field.echoMode, TextInput.Normal, "a visible question shows its answer");
        compare(p.face.message, "7 + 2:");
        const alone = panel({ users: [{ name: "rand", realName: "Rand", uid: 1000 }],
                              sessions: [{ id: "niri", name: "Niri", command: [], desktop: "niri" }] });
        verify(!findChild(alone, "greeterUser").visible, "one person: no choice");
        verify(findChild(alone, "greeterSession").visible, "the session is always shown, one or several");
        compare(findChild(alone, "greeterSession").text, "Niri");
    }

    function test_panel_answers_and_power() {
        const p = panel();
        const answered = createTemporaryObject(spyComp, root, { target: p, signalName: "submitted" });
        const power = createTemporaryObject(spyComp, root, { target: p, signalName: "powerRequested" });
        p.face.field.forceActiveFocus();
        for (const c of "secret") keyClick(c);
        keyClick(Qt.Key_Return);
        compare(answered.count, 1);
        compare(answered.signalArguments[0][0], "secret");
        compare(p.face.field.text, "", "never kept after sending");
        mouseClick(findChild(p, "greeterPoweroff"));
        mouseClick(findChild(p, "greeterReboot"));
        compare(power.signalArguments.map(a => a[0]).join(), "poweroff,reboot");
    }

    function test_panel_menus() {
        const p = panel();
        const users = createTemporaryObject(spyComp, root, { target: p, signalName: "userChosen" });
        const sessions = createTemporaryObject(spyComp, root, { target: p, signalName: "sessionChosen" });
        mouseClick(findChild(p, "greeterUser"));
        tryVerify(() => findChild(p, "greeterUser_rand-test") !== null);
        const item = findChild(p, "greeterUser_rand-test");
        tryCompare(item, "opacity", 1);
        mouseClick(item);
        compare(users.signalArguments[0][0], "rand-test");
        mouseClick(findChild(p, "greeterSession"));
        tryVerify(() => findChild(p, "greeterSession_sway") !== null);
        mouseClick(findChild(p, "greeterSession_sway"));
        compare(sessions.signalArguments[0][0], "sway");
    }
}
