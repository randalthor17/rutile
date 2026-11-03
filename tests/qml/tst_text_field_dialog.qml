// TextField and Dialog (plan 1.5) offscreen: the label floats on focus or text, typing and Enter, the trailing
// button, password hiding, the colors of focus, error and disabled from the tokens; the dialog's headline, actions,
// Enter and Escape, and its width limits.
import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "TextFieldDialog"
    width: 800
    height: 600
    visible: true
    when: windowShown

    Component { id: fieldComp; TextField { x: 20; y: 30; width: 300 } }
    Component { id: dialogComp; Dialog {} }
    Component { id: spyComp; SignalSpy {} }

    function init() { Colors.mode = "dark"; }

    function make(props) { const f = createTemporaryObject(fieldComp, root, props || {}); waitForRendering(f); return f; }
    function child(item, name) { return findChild(item, name); }

    function test_label_floats_with_focus_or_text() {
        const f = make({ label: "Name" });
        const label = child(f, "textFieldLabel");
        verify(!f.floating);
        compare(label.scale, 1);
        mouseClick(f, f.width / 2, f.fieldHeight / 2);
        verify(f.focused, "a click focuses the input");
        verify(f.floating);
        tryCompare(label, "scale", Type.bodySmall.size / Type.bodyLarge.size, 1000);
        f.input.focus = false;
        root.forceActiveFocus();
        verify(!f.floating, "empty and unfocused: back in the field");
        f.text = "Ada";
        verify(f.floating, "text keeps it up");
    }

    function test_typing_and_enter() {
        const f = make({ label: "Name" });
        const accepted = createTemporaryObject(spyComp, root, { target: f, signalName: "accepted" });
        mouseClick(f, f.width / 2, f.fieldHeight / 2);
        for (const c of "hi") keyClick(c);
        compare(f.text, "hi");
        keyClick(Qt.Key_Return);
        compare(accepted.count, 1);
        compare(accepted.signalArguments[0][0], "hi");
    }

    function test_placeholder_shows_only_when_it_does_not_cover_the_label() {
        const f = make({ label: "Name", placeholderText: "Ada Lovelace" });
        const ph = child(f, "textFieldPlaceholder");
        verify(!ph.visible, "the resting label is in its place");
        f.input.forceActiveFocus();
        verify(ph.visible);
        f.text = "x";
        verify(!ph.visible);
        const bare = make({ placeholderText: "Search" });
        verify(child(bare, "textFieldPlaceholder").visible, "no label: always while empty");
    }

    function test_trailing_button_and_password() {
        const f = make({ trailingIconName: "visibility", password: true });
        const clicked = createTemporaryObject(spyComp, root, { target: f, signalName: "trailingClicked" });
        compare(f.input.echoMode, TextInput.Password);
        mouseClick(child(f, "textFieldTrailing"));
        compare(clicked.count, 1);
        verify(child(f, "textFieldInput").width < f.width - 2 * f.padding, "the text stops before the button");
        f.password = false;
        compare(f.input.echoMode, TextInput.Normal);
    }

    function test_colors_follow_the_tokens() {
        const o = make({ label: "Name" });
        const s = ControlSpec.textFieldSpec.outlined;
        compare(o.indicatorColor, Colors[s.outlineColor]);
        compare(o.indicatorWidth, s.outlineWidth);
        o.input.forceActiveFocus();
        compare(o.indicatorColor, Colors[s.focusOutlineColor]);
        compare(o.labelColor, Colors[s.focusLabelColor]);
        compare(o.indicatorWidth, s.focusOutlineWidth);
        o.error = true;
        compare(o.indicatorColor, Colors[s.errorFocusOutlineColor]);
        compare(o.labelColor, Colors[s.errorFocusLabelColor]);
        o.enabled = false;
        compare(o.labelColor, Qt.alpha(Colors[s.disabledLabelColor], s.disabledLabelOpacity));
        const fl = make({ type: "filled", label: "Name" });
        const t = ControlSpec.textFieldSpec.filled;
        compare(fl.indicatorColor, Colors[t.activeIndicatorColor]);
        fl.input.forceActiveFocus();
        compare(fl.indicatorColor, Colors[t.focusActiveIndicatorColor]);
        compare(fl.indicatorWidth, t.focusActiveIndicatorHeight);
    }

    function test_supporting_text_adds_height() {
        const f = make({ label: "Name" });
        const h = f.implicitHeight;
        compare(h, f.fieldHeight);
        f.supportingText = "Required";
        verify(f.implicitHeight > h);
        f.error = true;
        compare(child(f, "textFieldSupporting").color, Colors[ControlSpec.textFieldSpec.outlined.errorSupportingColor]);
    }

    function test_dialog() {
        const d = createTemporaryObject(dialogComp, root, {
            headline: "Forget network?", supportingText: "Home will be removed.", iconName: "wifi",
            actions: [{ id: "cancel", text: "Cancel" }, { id: "forget", text: "Forget", type: "filled" }],
            acceptId: "forget", dismissId: "cancel" });
        waitForRendering(d);
        const chosen = createTemporaryObject(spyComp, root, { target: d, signalName: "chosen" });
        compare(child(d, "dialogHeadline").horizontalAlignment, Text.AlignHCenter, "centered under an icon");
        compare(d.color, Colors[ControlSpec.dialogSpec.containerColor]);
        compare(d.radius, ControlSpec.dialogSpec.containerShape);
        const cancel = child(d, "dialogAction_cancel"), forget = child(d, "dialogAction_forget");
        verify(cancel.mapToItem(d, 0, 0).x < forget.mapToItem(d, 0, 0).x, "left to right");
        verify(forget.mapToItem(d, forget.width, 0).x <= d.width - Spacing.xl + 0.5, "at the right");
        mouseClick(forget);
        compare(chosen.signalArguments[0][0], "forget");
        d.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(chosen.signalArguments[1][0], "cancel");
        keyClick(Qt.Key_Return);
        compare(chosen.signalArguments[2][0], "forget");
        compare(chosen.count, 3);
        d.dismissId = "";
        keyClick(Qt.Key_Escape);
        compare(chosen.count, 3, "no dismiss id: Escape is not taken");
    }

    function test_dialog_width_limits() {
        const d = createTemporaryObject(dialogComp, root, { headline: "Hi" });
        compare(d.width, d.minWidth);
        d.supportingText = "word ".repeat(200);
        compare(d.width, d.maxWidth);
        compare(child(d, "dialogHeadline").horizontalAlignment, Text.AlignLeft, "no icon: to the left");
    }
}
