import QtQuick
import QtTest
import qs.common
import qs.notifications
import "../qs/notifications/NotificationModel.js" as Model

TestCase {
    id: root
    name: "Notifications"
    width: 600
    height: 800
    visible: true
    when: windowShown

    function cleanup() { Motion.speed = 1; }

    function note(id, extra) {
        return Object.assign({ id: id, appName: "Mail", appIcon: "", image: "", summary: "Summary " + id,
                               body: "Body " + id, urgency: 1, critical: false, actions: [], time: Date.now(),
                               timeout: 0 }, extra || {});
    }

    Component { id: cardComp; NotificationCard { width: 360 } }
    Component { id: popupsComp; NotificationPopups { width: 360 } }
    Component { id: spyComp; SignalSpy {} }

    function test_plain() {
        compare(Model.plain(""), "");
        compare(Model.plain(null), "");
        compare(Model.plain("<b>Hi</b> <i>there</i>"), "Hi there");
        compare(Model.plain("a<br>b<br/>c<br />d"), "a\nb\nc\nd");
        compare(Model.plain("<p>one</p><p>two</p>"), "one\ntwo");
        compare(Model.plain("<img src=\"http://x/y.png\"/>pic"), "pic", "no images");
        compare(Model.plain("a &lt;b&gt; &amp; &quot;c&quot; &#39;d&apos;"), "a <b> & \"c\" 'd'");
        compare(Model.plain("&amp;lt;"), "&lt;", "decoded once");
        compare(Model.plain("  padded \n"), "padded");
        compare(Model.plain(42), "42");
    }

    function test_timeout() {
        compare(Model.timeout(-1, 1), Model.defaultTimeout, "the sender does not mind: ours");
        compare(Model.timeout(undefined, 1), Model.defaultTimeout);
        compare(Model.timeout(3000, 1), 3000, "the sender's");
        compare(Model.timeout(0, 1), 0, "0 stays");
        compare(Model.timeout(3000, 2), 0, "critical stays");
        compare(Model.timeout(3000, 0), 3000, "low");
    }

    function test_ago() {
        const now = new Date(2026, 9, 27, 18, 0, 0).getTime();
        const t = d => "T" + d.getHours();
        const d = d => "D" + d.getDate();
        compare(Model.ago(now, now, t, d), "now");
        compare(Model.ago(now - 59000, now, t, d), "now");
        compare(Model.ago(now - 60000, now, t, d), "1 min");
        compare(Model.ago(now - 59 * 60000, now, t, d), "59 min");
        compare(Model.ago(now - 3600000, now, t, d), "1 h");
        compare(Model.ago(now - 5 * 3600000 - 1, now, t, d), "5 h");
        compare(Model.ago(now - 6 * 3600000, now, t, d), "T12", "earlier today: the time");
        compare(Model.ago(now - 19 * 3600000, now, t, d), "D26", "yesterday: the date");
    }

    function test_visible_popups_and_pops() {
        compare(Model.visiblePopups([1, 2]).join(), "1,2");
        compare(Model.visiblePopups([1, 2, 3, 4, 5]).join(), "3,4,5", "the newest three");
        const ids = [1, 2, 3, 4];
        Model.visiblePopups(ids);
        compare(ids.length, 4, "the list is not changed");
        verify(Model.pops(1, false));
        verify(!Model.pops(1, true), "Do not disturb");
        verify(!Model.pops(0, true));
        verify(Model.pops(2, true), "critical still pops");
    }

    function test_card_shows_and_reports() {
        const c = createTemporaryObject(cardComp, root, { notification: note(7, {
            actions: [{ id: "default", text: "Open" }, { id: "reply", text: "Reply" }, { id: "x", text: "" }],
            body: "Hello there" }) });
        waitForRendering(c);
        compare(findChild(c, "notificationSummary").text, "Summary 7");
        compare(findChild(c, "notificationBody").text, "Hello there");
        compare(findChild(c, "notificationBody").textFormat, Text.PlainText);
        verify(findChild(c, "notificationApp").text.indexOf("Mail · now") === 0);
        compare(c.buttons.map(b => b.id).join(), "reply", "default and unnamed actions are not buttons");
        const many = createTemporaryObject(cardComp, root, { y: 400, notification: note(8, {
            actions: [1, 2, 3, 4].map(i => ({ id: "a" + i, text: "A" + i })) }) });
        waitForRendering(many);
        verify(findChild(many, "notificationAction_a3") && !findChild(many, "notificationAction_a4"), "three buttons at most");
        verify(c.hasDefault);
        verify(!findChild(c, "notificationImage"), "no image loaded without one");
        verify(!c.border.width, "not critical: no outline");
        const invoked = createTemporaryObject(spyComp, root, { target: c, signalName: "actionInvoked" });
        const activated = createTemporaryObject(spyComp, root, { target: c, signalName: "activated" });
        const dismissed = createTemporaryObject(spyComp, root, { target: c, signalName: "dismissed" });
        const reply = findChild(c, "notificationAction_reply");
        mouseClick(reply, reply.width / 2, reply.height / 2);
        compare(invoked.count, 1);
        compare(invoked.signalArguments[0][0], "reply");
        compare(activated.count, 0, "a button is not a click on the card");
        mouseClick(c, Spacing.lg, c.height - Spacing.sm);
        compare(invoked.count, 2);
        compare(invoked.signalArguments[1][0], "default", "a click on the card is the default action");
        compare(activated.count, 1);
        const close = findChild(c, "notificationClose");
        mouseClick(close, close.width / 2, close.height / 2);
        compare(dismissed.count, 1);
        compare(activated.count, 1, "closing is not activating");
    }

    function test_card_without_default_or_buttons() {
        const c = createTemporaryObject(cardComp, root, { notification: note(1, { critical: true, image: "file:///nonexistent.png", body: "" }) });
        waitForRendering(c);
        const invoked = createTemporaryObject(spyComp, root, { target: c, signalName: "actionInvoked" });
        const activated = createTemporaryObject(spyComp, root, { target: c, signalName: "activated" });
        mouseClick(c, Spacing.lg, c.height - Spacing.sm);
        compare(invoked.count, 0, "no default action to invoke");
        compare(activated.count, 1);
        verify(!findChild(c, "notificationBody").visible, "no body, no room for one");
        verify(findChild(c, "notificationImage"), "the image is loaded when sent");
        compare(c.border.width, 1, "critical: an outline");
        compare(String(c.border.color), String(Colors.error));
    }

    function test_card_times_out_unless_hovered() {
        const c = createTemporaryObject(cardComp, root, { notification: note(1), timeout: 300 });
        const timedOut = createTemporaryObject(spyComp, root, { target: c, signalName: "timedOut" });
        tryCompare(timedOut, "count", 1, 2000);
        c.timeout = 0;
        wait(400);
        compare(timedOut.count, 1, "0 stays");
        c.timeout = 300;
        mouseMove(c, c.width / 2, c.height - Spacing.sm);
        tryVerify(() => c.hovered, 1000);
        wait(600);
        compare(timedOut.count, 1, "not while the pointer is over it");
        mouseMove(root, root.width - 1, root.height - 1);
        tryCompare(timedOut, "count", 2, 2000, "after it leaves");
    }

    function test_popups_come_and_go() {
        Motion.speed = 4;
        const p = createTemporaryObject(popupsComp, root);
        verify(p.empty);
        p.popups = [note(1)];
        tryVerify(() => findChild(p, "notificationPopup_1"), 1000);
        verify(!p.empty);
        p.popups = [note(1, { timeout: 60000 }), note(2)];
        tryVerify(() => findChild(p, "notificationPopup_2"), 1000);
        verify(findChild(findChild(p, "notificationPopup_1"), "notificationTimer").running, "a popup's timer runs");
        const first = findChild(p, "notificationPopup_1");
        const second = findChild(p, "notificationPopup_2");
        tryVerify(() => second.y === 0 && first.y > 0, 2000, "newest on top");
        // a replaced notification updates in place
        p.popups = [note(1, { summary: "Changed", timeout: 60000 }), note(2)];
        compare(findChild(first, "notificationSummary").text, "Changed");
        verify(findChild(p, "notificationPopup_1") === first, "the same card");
        // one leaves: it plays its motion with what it showed, then goes; the other moves up
        Motion.speed = 0.3;
        const full = first.height;
        p.popups = [note(2)];
        verify(findChild(p, "notificationPopup_1"), "still there while it leaves");
        verify(!findChild(first, "notificationTimer").running, "its timer stops");
        tryVerify(() => first.height < full * 0.8, 3000, "its room closes as it goes");
        Motion.speed = 4;
        compare(findChild(first, "notificationSummary").text, "Changed", "showing what it showed");
        tryVerify(() => !findChild(p, "notificationPopup_1"), 3000, "gone after its motion");
        tryCompare(second, "y", 0, 2000);
        // and back before it had gone
        p.popups = [];
        p.popups = [note(2)];
        wait(300);
        verify(findChild(p, "notificationPopup_2"), "it stays");
        tryCompare(findChild(p, "notificationPopup_2"), "height", findChild(p, "notificationPopup_2").children[0].implicitHeight + Spacing.sm, 2000);
        p.popups = [];
        tryVerify(() => p.empty, 3000, "empty once the last has gone");
    }

    function test_popups_report_by_id() {
        const p = createTemporaryObject(popupsComp, root, { popups: [note(5, { actions: [{ id: "a", text: "A" }] })] });
        tryVerify(() => findChild(p, "notificationPopup_5"), 1000);
        const card = findChild(p, "notificationPopup_5").children[0];
        const invoked = createTemporaryObject(spyComp, root, { target: p, signalName: "actionInvoked" });
        const dismissed = createTemporaryObject(spyComp, root, { target: p, signalName: "dismissed" });
        const activated = createTemporaryObject(spyComp, root, { target: p, signalName: "activated" });
        tryVerify(() => card.scale === 1, 2000);
        const a = findChild(card, "notificationAction_a");
        mouseClick(a, a.width / 2, a.height / 2);
        compare(invoked.signalArguments[0][0] + "," + invoked.signalArguments[0][1], "5,a");
        const close = findChild(card, "notificationClose");
        mouseClick(close, close.width / 2, close.height / 2);
        compare(dismissed.signalArguments[0][0], 5);
        mouseClick(card, Spacing.lg, card.height - Spacing.sm);
        compare(activated.signalArguments[0][0], 5);
    }

    function test_popups_time_out_by_id() {
        const p = createTemporaryObject(popupsComp, root, { popups: [note(5, { timeout: 200 })] });
        const timedOut = createTemporaryObject(spyComp, root, { target: p, signalName: "timedOut" });
        tryCompare(timedOut, "count", 1, 2000);
        compare(timedOut.signalArguments[0][0], 5);
        p.popups = [];
        p.popups = [note(6, { timeout: 0 })];
        wait(400);
        compare(timedOut.count, 1, "0 stays");
    }
}
