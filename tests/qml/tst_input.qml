// Typing in other languages through fcitx5 (D118): the D-Bus answers (InputMethod.js), the input pill, and fcitx5's
// tray item kept out of the indicators (TrayModel.js).
import QtQuick
import QtTest
import qs.common
import qs.bar
import "../qs/services/InputMethod.js" as Ime
import "../qs/bar/TrayModel.js" as TrayModel

TestCase {
    id: root
    name: "Input"
    width: 300
    height: 100
    visible: true
    when: windowShown

    // fcitx5 5.1's answers, as busctl --json=short printed them (trimmed)
    readonly property string group: '{"type":"sssa{sv}a(sssssssbsa{sv})","data":["Default","keyboard-us","us",{},[' +
        '["keyboard-us","Keyboard - English (US)","","input-keyboard","en","en","keyboard",true,"",{}],' +
        '["m17n_bn_itrans","itrans (M17N)","","/m17n/icons/bn-itrans.png","","bn","m17n",true,"",{}],' +
        '["keyboard-de-neo","Keyboard - German - Neo 2","","input-keyboard","","","keyboard",true,"",{}]]]}'

    Component { id: pillComp; InputPill {} }
    Component { id: spyComp; SignalSpy {} }

    function test_answers() {
        const list = Ime.methods(group);
        compare(JSON.stringify(list), JSON.stringify([
            { id: "keyboard-us", name: "Keyboard - English (US)", label: "EN" },
            { id: "m17n_bn_itrans", name: "itrans (M17N)", label: "BN" },
            { id: "keyboard-de-neo", name: "Keyboard - German - Neo 2", label: "KEY" }]),
            "the label, else the language, else the id's start");
        compare(Ime.methods("").length, 0);
        compare(Ime.methods("not json").length, 0);
        compare(Ime.methods('{"type":"s","data":["x"]}').length, 0);
        compare(Ime.string('{"type":"s","data":["Default"]}'), "Default");
        compare(Ime.string('{"type":"s","data":[""]}'), "");
        compare(Ime.string("Call failed"), "");
        compare(Ime.shown(list, "m17n_bn_itrans").id, "m17n_bn_itrans");
        compare(Ime.shown(list, "").id, "keyboard-us", "no window takes text: the group's first");
        compare(Ime.shown(list, "gone").id, "keyboard-us");
        compare(Ime.shown([], ""), null);
        compare(Ime.next(list, ""), "m17n_bn_itrans");
        compare(Ime.next(list, "keyboard-de-neo"), "keyboard-us", "round");
        compare(Ime.next([], ""), "");
        compare(Ime.call("SetCurrentIM", "s", ["m17n_bn_itrans"]).join(" "),
                "busctl --user --json=short call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetCurrentIM s m17n_bn_itrans");
        compare(Ime.call("CurrentInputMethod").slice(-2).join(" "), "org.fcitx.Fcitx.Controller1 CurrentInputMethod");
    }

    function test_pill() {
        const pill = createTemporaryObject(pillComp, root, { label: "", name: "" });
        verify(!pill.visible, "nothing to show: no pill");
        compare(pill.implicitWidth, 0, "and no room taken");
        pill.label = "BN";
        verify(pill.visible);
        compare(findChild(pill, "inputLabel").text, "BN");
        verify(pill.width >= Spacing.xl);
        const clicked = createTemporaryObject(spyComp, root, { target: pill, signalName: "clicked" });
        waitForRendering(pill);
        mouseClick(pill);
        compare(clicked.count, 1);
        compare(pill.color, Panels.tint(Colors.surfaceContainer));
        pill.open = true;
        tryCompare(pill, "color", Panels.tint(Colors.secondaryContainer), 2000, "tinted while its menu is open");
    }

    function test_tray_keeps_fcitx_out() {
        const items = [{ id: "nm-applet", title: "Network", status: 1 }, { id: "Fcitx", title: "Input Method", status: 1 },
                       { id: "steam", title: "Steam", status: 0 }];
        compare(TrayModel.shown(items, 0, 2).map(e => e.id).join(), "nm-applet", "not among the indicators");
        const entry = TrayModel.inputMethod(items);
        compare(entry.id, "Fcitx");
        compare(entry.item, items[1], "the input pill opens its menu");
        compare(TrayModel.inputMethod(items.slice(0, 1)), null);
    }
}
