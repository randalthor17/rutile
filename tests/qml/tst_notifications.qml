import QtQuick
import QtTest
import qs.common
import qs.notifications
import qs.bar
import "../qs/notifications/NotificationModel.js" as Model
import "../qs/notifications/NotificationRows.js" as Rows

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
    Component { id: bellComp; NotificationBell {} }
    Component { id: listModelComp; ListModel {} }
    Component { id: panelComp; NotificationPanel {} }

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
        mouseMove(root, root.width - 1, root.height - 1);  // an earlier test's pointer over the card would hold it
        const p = createTemporaryObject(popupsComp, root, { popups: [note(5, { timeout: 200 })] });
        const timedOut = createTemporaryObject(spyComp, root, { target: p, signalName: "timedOut" });
        tryCompare(timedOut, "count", 1, 2000);
        compare(timedOut.signalArguments[0][0], 5);
        p.popups = [];
        p.popups = [note(6, { timeout: 0 })];
        wait(400);
        compare(timedOut.count, 1, "0 stays");
    }

    function test_bell() {
        const b = createTemporaryObject(bellComp, root);
        compare(b.iconName, "notifications");
        compare(findChild(b, "bellIcon").fill, 0);
        b.count = 2;
        compare(b.iconName, "notifications_unread", "a dot while there are some");
        compare(findChild(b, "bellIcon").fill, 1);
        b.dnd = true;
        compare(b.iconName, "notifications_off", "Do not disturb wins");
        compare(findChild(b, "bellIcon").fill, 0);
        compare(String(b.color), String(Colors.surfaceContainer));
        b.open = true;
        tryCompare(b, "color", Colors.secondaryContainer, 2000, "tinted while the list is open");
        compare(String(findChild(b, "bellIcon").color), String(Colors.secondaryContainerOn));
        const clicked = createTemporaryObject(spyComp, root, { target: b, signalName: "clicked" });
        mouseClick(b);
        compare(clicked.count, 1);
    }

    function test_panel() {
        Motion.speed = 4;
        const p = createTemporaryObject(panelComp, root);
        waitForRendering(p);
        verify(findChild(p, "notificationEmpty").visible, "empty: says so");
        verify(!findChild(p, "notificationList").visible);
        verify(!findChild(p, "notificationClearAll").parent.visible, "nothing to clear");
        p.notifications = [note(3, { appName: "A", actions: [{ id: "default", text: "" }] }), note(2, { appName: "B" }),
                           note(1, { appName: "C" })];
        waitForRendering(p);
        tryVerify(() => !findChild(p, "notificationEmpty").visible, 2000, "No notifications fades out");
        const items = [3, 2, 1].map(id => findChild(p, "notificationItem_" + id));
        verify(items.every(i => !!i), "all three");
        const clipBox = findChild(p, "notificationListClip");
        tryVerify(() => clipBox.height === findChild(p, "notificationList").contentHeight, 2000, "the list opens to its cards");
        const ys = items.map(i => i.mapToItem(p, 0, 0).y);
        verify(ys[0] < ys[1] && ys[1] < ys[2], "in the given order (newest first)");
        compare(items[0].timeout, 0, "no timeout in the list");
        const dismissed = createTemporaryObject(spyComp, root, { target: p, signalName: "dismissed" });
        const cleared = createTemporaryObject(spyComp, root, { target: p, signalName: "cleared" });
        const dnd = createTemporaryObject(spyComp, root, { target: p, signalName: "dndToggled" });
        const invoked = createTemporaryObject(spyComp, root, { target: p, signalName: "actionInvoked" });
        const activated = createTemporaryObject(spyComp, root, { target: p, signalName: "activated" });
        const close = findChild(items[1], "notificationClose");
        mouseClick(close, close.width / 2, close.height / 2);
        compare(dismissed.signalArguments[0][0], 2);
        mouseClick(items[0], Spacing.lg, items[0].height - Spacing.sm);
        compare(invoked.signalArguments[0][0] + "," + invoked.signalArguments[0][1], "3,default");
        compare(activated.signalArguments[0][0], 3);
        const clear = findChild(p, "notificationClearAll");
        mouseClick(clear, clear.width / 2, clear.height / 2);
        tryCompare(cleared, "count", 1, 2000);
        compare(cleared.signalArguments[0][0].join(), "3,2,1", "what it cleared");
        const sw = findChild(p, "notificationDnd");
        mouseClick(sw, sw.width / 2, sw.height / 2);
        compare(dnd.signalArguments[0][0], true);
        verify(!sw.checked, "the switch waits for the state (controlled)");
        p.dnd = true;
        verify(sw.checked);
        // a long list scrolls instead of growing past the screen
        const many = [];
        for (let i = 0; i < 20; i++) many.push(note(100 + i, { appName: "App " + i }));
        p.notifications = many;
        waitForRendering(p);
        tryCompare(findChild(p, "notificationListClip"), "height", p.maxListHeight, 2000);
        // a drag up and down on a card scrolls the list; the swipe only takes sideways drags
        const view = findChild(p, "notificationList");
        const top = findChild(p, "notificationItem_100");
        drag(top, 0, -150);
        tryVerify(() => view.contentY > 50, 2000, "the list scrolled");
        compare(top.swipeX, 0);
        verify(!findChild(p, "notificationItem_119"), "cards far below are not created");
        // losing the keyboard after having had it closes (the window's own activation cannot move offscreen)
        const lost = createTemporaryObject(spyComp, root, { target: p, signalName: "windowFocusLost" });
        p.windowActive = false;
        p.windowActive = true;
        lost.clear();
        p.windowActive = false;
        compare(lost.count, 1, "lost after having it");
        // closing plays the motion, then hidden
        const hidden = createTemporaryObject(spyComp, root, { target: p, signalName: "hidden" });
        p.shown = false;
        tryCompare(hidden, "count", 1, 3000);
    }

    // Clear all sweeps the rows off to the side, the top one first, and then reports what it took.
    function test_panel_clear_all() {
        Motion.speed = 0.5;
        const p = createTemporaryObject(panelComp, root, { notifications: [
            note(4, { appName: "A" }), note(3, { appName: "B" }), note(2, { appName: "C" }), note(1, { appName: "A" })] });
        waitForRendering(p);
        const cleared = createTemporaryObject(spyComp, root, { target: p, signalName: "cleared" });
        const none = createTemporaryObject(panelComp, root);
        const noneCleared = createTemporaryObject(spyComp, root, { target: none, signalName: "cleared" });
        none.clearAll();
        verify(!none.clearing, "nothing to clear");
        const row = key => findChild(p, "notificationRow_" + key);
        const top = row("n4"), more = row("more:A"), bottom = row("n2");
        verify(top && more && bottom, "the rows");
        const clear = findChild(p, "notificationClearAll");
        mouseClick(clear, clear.width / 2, clear.height / 2);
        verify(p.clearing);
        compare(cleared.count, 0, "not before the sweep");
        verify(!clear.enabled, "no second Clear all meanwhile");
        tryVerify(() => top.sweep > 0.3, 2000, "the top row goes");
        verify(bottom.sweep < top.sweep, "before the bottom one: " + bottom.sweep + " < " + top.sweep);
        verify(top.item.opacity < 1, "fading");
        // one that comes meanwhile stays
        p.notifications = [note(5, { appName: "D" })].concat(p.notifications);
        p.clearAll();
        verify(p.clearingIds.indexOf(5) < 0, "one sweep at a time");
        tryCompare(cleared, "count", 1, 4000);
        compare(noneCleared.count, 0, "and nothing reported");
        compare(cleared.signalArguments[0][0].join(), "4,3,2,1", "it reports what it swept, not the new one");
        verify(more.sweep === 1 && more.item.opacity === 0, "a group's row goes too");
        tryVerify(() => findChild(p, "notificationRow_n5"), 2000);
        compare(row("n5").sweep, 0, "the new one is not swept");
        // the sender keeps one: it comes back
        p.notifications = [note(5, { appName: "D" }), note(3, { appName: "B" })];
        tryVerify(() => !p.clearing, 2000, "done");
        verify(findChild(p, "notificationRow_n4"), "the swept ones still fading out");
        compare(top.item.opacity, 0, "stay swept: no flash back");
        tryCompare(row("n3"), "sweep", 0, 2000);
        compare(row("n3").item.opacity, 1, "shown again");
        verify(clear.enabled);
        // the rest go: the list closes up while No notifications fades in
        const clipBox = findChild(p, "notificationListClip");
        const empty = findChild(p, "notificationEmpty");
        mouseClick(clear, clear.width / 2, clear.height / 2);
        tryCompare(cleared, "count", 2, 4000);
        p.notifications = [];
        wait(30);
        verify(clipBox.visible && clipBox.height > 0, "closing, not closed");
        tryVerify(() => empty.opacity > 0 && empty.opacity < 1, 2000, "fading in");
        tryCompare(clipBox, "visible", false, 3000);
        tryCompare(empty, "opacity", 1, 2000);
    }

    function test_rows_sync() {
        const m = createTemporaryObject(listModelComp, root);
        const ids = () => { const out = []; for (let i = 0; i < m.count; i++) out.push(m.get(i).key); return out.join(); };
        let ops = [];
        m.rowsInserted.connect(() => ops.push("insert"));
        m.rowsRemoved.connect(() => ops.push("remove"));
        m.rowsMoved.connect(() => ops.push("move"));
        Rows.sync(m, ["3", "2", "1"]);
        compare(ids(), "3,2,1");
        ops = [];
        Rows.sync(m, ["4", "3", "2", "1"]);
        compare(ids(), "4,3,2,1");
        compare(ops.join(), "insert", "a new one: one insert, the rest stay");
        ops = [];
        Rows.sync(m, ["4", "2", "1"]);
        compare(ids(), "4,2,1");
        compare(ops.join(), "remove", "one gone: one remove");
        ops = [];
        Rows.sync(m, ["1", "4", "2"]);
        compare(ids(), "1,4,2");
        compare(ops.join(), "move", "reordered: one move");
        ops = [];
        Rows.sync(m, ["1", "4", "2"]);
        compare(ops.length, 0, "unchanged: nothing");
        Rows.sync(m, []);
        compare(m.count, 0);
        Rows.sync(m, ["5", "5"]);
        compare(ids(), "5,5", "duplicates are kept as asked");
    }

    // A drag in the test's coordinates: the card moves under the pointer, so its own would drift (LESSONS).
    function drag(item, dx, dy) {
        const start = item.mapToItem(root, item.width / 2, item.height - Spacing.sm);
        mousePress(root, start.x, start.y);
        for (let i = 1; i <= 8; i++) mouseMove(root, start.x + dx * i / 8, start.y + dy * i / 8);
        mouseRelease(root, start.x + dx, start.y + dy);
    }

    function test_card_swipe() {
        Motion.speed = 4;
        const c = createTemporaryObject(cardComp, root, { x: 100, notification: note(1) });
        waitForRendering(c);
        const dismissed = createTemporaryObject(spyComp, root, { target: c, signalName: "dismissed" });
        const activated = createTemporaryObject(spyComp, root, { target: c, signalName: "activated" });
        // a short swipe springs back
        drag(c, c.width / 5, 0);
        tryCompare(c, "swipeX", 0, 2000, "back in place");
        compare(dismissed.count, 0);
        compare(activated.count, 0, "a swipe is not a click");
        // past a third it slides out, then asks to go
        drag(c, -c.width / 2, 0);
        verify(c.swipedAway);
        verify(!findChild(c, "notificationSwipe").enabled, "no second swipe while it slides out");
        tryCompare(dismissed, "count", 1, 2000);
        verify(c.swipeX <= -c.width, "out to the left");
        // up and down does nothing
        const d = createTemporaryObject(cardComp, root, { x: 100, notification: note(2) });
        waitForRendering(d);
        drag(d, 0, 60);
        compare(d.swipeX, 0);
    }

    // The windows size to these, not to the moving content: a layer surface resized on every frame stutters.
    function test_window_room() {
        Motion.speed = 0.5;
        const p = createTemporaryObject(popupsComp, root);
        const full = createTemporaryObject(spyComp, root, { target: p, signalName: "fullHeightChanged" });
        const moving = createTemporaryObject(spyComp, root, { target: p, signalName: "implicitHeightChanged" });
        p.popups = [note(1)];
        tryVerify(() => findChild(p, "notificationPopup_1"), 1000);
        const slot = findChild(p, "notificationPopup_1");
        tryVerify(() => p.fullHeight === slot.room, 1000, "the room it takes fully open");
        verify(p.implicitHeight < p.fullHeight, "while it is still opening");
        tryVerify(() => p.implicitHeight === p.fullHeight && p.fullHeight === slot.room, 3000, "open");
        verify(moving.count > 5, "the content moves frame by frame: " + moving.count);
        verify(full.count <= 2, "the room does not: " + full.count);
        const changes = full.count;
        const room = p.fullHeight;
        p.popups = [];
        tryVerify(() => p.implicitHeight < room * 0.8, 3000, "leaving");
        compare(p.fullHeight, room, "the room stays while it leaves");
        compare(full.count, changes);
        tryCompare(p, "fullHeight", 0, 4000, "and goes with it");
        verify(p.area.height <= p.fullHeight, "what is on screen fits");

        const panel = createTemporaryObject(panelComp, root);
        const max = panel.maxHeight;
        verify(panel.height <= max, "empty");
        const many = [];
        for (let i = 1; i <= 12; i++) many.push(note(i, { appName: "App " + i }));
        panel.notifications = many;
        waitForRendering(panel);
        tryVerify(() => findChild(panel, "notificationListClip").height === panel.maxListHeight, 3000, "a full list");
        tryCompare(panel, "height", max, 2000, "is the tallest it gets");    // the Column lays out a polish later
        compare(panel.maxHeight, max, "a fixed size");
    }

    function test_panel_list_motion() {
        Motion.speed = 0.5;
        const apps = id => note(id, { appName: "App " + id });
        const p = createTemporaryObject(panelComp, root, { notifications: [apps(3), apps(2), apps(1)] });
        waitForRendering(p);
        const two = findChild(p, "notificationItem_2");
        const one = findChild(p, "notificationItem_1");
        const yOf = item => item.mapToItem(p, 0, 0).y;
        const oneY = yOf(one);
        p.notifications = [apps(3), apps(1)];
        verify(findChild(p, "notificationItem_2"), "the gone one fades out first");
        const row2 = findChild(p, "notificationRow_n2");
        tryVerify(() => row2.opacity < 0.9 && row2.opacity > 0, 2000, "fading");
        compare(findChild(two, "notificationSummary").text, "Summary 2", "showing what it showed");
        tryVerify(() => !findChild(p, "notificationItem_2"), 4000, "then goes");
        tryVerify(() => yOf(one) < oneY, 3000, "the one below moves up");
        verify(findChild(p, "notificationItem_1") === one, "and is the same card");
        p.notifications = [apps(4), apps(3), apps(1)];
        tryVerify(() => findChild(p, "notificationItem_4"), 2000, "a new one comes in");
        compare(findChild(p, "notificationItem_1"), one, "without rebuilding the rest");
        // a reply from the list
        const replied = createTemporaryObject(spyComp, root, { target: p, signalName: "replied" });
        one.sendReply("from the list");
        compare(replied.signalArguments[0][0] + "," + replied.signalArguments[0][1], "1,from the list");
        // the bottom one goes: the list closes gradually, so its fade is not cut off
        const clipBox = findChild(p, "notificationListClip");
        tryVerify(() => clipBox.height === findChild(p, "notificationList").contentHeight, 3000);
        const before = clipBox.height;
        p.notifications = [apps(4), apps(3)];
        wait(50);
        verify(clipBox.height > findChild(p, "notificationList").contentHeight && clipBox.height <= before,
               "closing, not closed: " + clipBox.height);
        tryCompare(clipBox, "height", findChild(p, "notificationList").contentHeight, 3000);
    }

    function test_group_rows() {
        const list = [note(5, { appName: "Mail" }), note(4, { appName: "Chat" }), note(3, { appName: "Mail" }),
                      note(2, { appName: "Mail" }), note(1, { appName: "" })];
        const keys = rows => rows.map(r => r.key).join();
        compare(keys(Model.groupRows(list, {})), "n5,more:Mail,n4,n1", "each app's newest, apps by their newest");
        const more = Model.groupRows(list, {})[1];
        compare(more.kind + "," + more.app + "," + more.count + "," + more.expanded, "more,Mail,2,false");
        compare(keys(Model.groupRows(list, { Mail: true })), "n5,n3,n2,more:Mail,n4,n1", "expanded: all, then Show less");
        verify(Model.groupRows(list, { Mail: true })[3].expanded);
        compare(keys(Model.groupRows(list, null)), "n5,more:Mail,n4,n1");
        compare(keys(Model.groupRows([], {})), "");
        compare(keys(Model.groupRows([note(1, { appName: "constructor" }), note(2, { appName: "constructor" })], {})),
                "n1,more:constructor", "any app name");
        compare(Model.groupRows(list, {})[0].id, 5);
    }

    function test_panel_groups() {
        Motion.speed = 4;
        const p = createTemporaryObject(panelComp, root, { notifications: [
            note(3, { appName: "Mail" }), note(2, { appName: "Chat" }), note(1, { appName: "Mail" })] });
        waitForRendering(p);
        verify(findChild(p, "notificationItem_3") && findChild(p, "notificationItem_2"), "each app's newest");
        verify(!findChild(p, "notificationItem_1"), "the older one from Mail waits");
        const more = findChild(p, "notificationMore_Mail");
        compare(more.text, "Show 1 more from Mail");
        mouseClick(more, more.width / 2, more.height / 2);
        tryVerify(() => findChild(p, "notificationItem_1"), 2000, "shown");
        const less = findChild(p, "notificationMore_Mail");
        compare(less.text, "Show less");
        verify(findChild(p, "notificationItem_1").mapToItem(p, 0, 0).y < less.mapToItem(p, 0, 0).y, "above Show less");
        verify(findChild(p, "notificationItem_2").mapToItem(p, 0, 0).y > less.mapToItem(p, 0, 0).y, "Chat after Mail's group");
        mouseClick(less, less.width / 2, less.height / 2);
        tryVerify(() => !findChild(p, "notificationItem_1"), 3000, "folded again");
        // the group's last other one goes: no more row
        p.notifications = [note(3, { appName: "Mail" }), note(2, { appName: "Chat" })];
        tryVerify(() => !findChild(p, "notificationMore_Mail"), 3000);
    }

    function test_card_reply() {
        const c = createTemporaryObject(cardComp, root, { notification: note(1, { reply: "Message",
            actions: [{ id: "inline-reply", text: "Reply" }, { id: "open", text: "Open" }] }), timeout: 300 });
        waitForRendering(c);
        verify(c.canReply);
        compare(c.buttons.map(b => b.id).join(), "open", "the reply action is not a plain button");
        const replied = createTemporaryObject(spyComp, root, { target: c, signalName: "replied" });
        const timedOut = createTemporaryObject(spyComp, root, { target: c, signalName: "timedOut" });
        const button = findChild(c, "notificationReply");
        verify(button.visible);
        mouseClick(button, button.width / 2, button.height / 2);
        verify(c.replying);
        tryVerify(() => findChild(c, "notificationReplyField")?.activeFocus, 2000, "the field takes the keyboard");
        tryVerify(() => !findChild(c, "notificationReply"), 2000, "the buttons give way to the field");
        wait(500);
        compare(timedOut.count, 0, "it stays while replying");
        keyClick(Qt.Key_Return);
        compare(replied.count, 0, "nothing to send yet");
        verify(!findChild(c, "notificationSend").enabled);
        keyClick(Qt.Key_H);
        keyClick(Qt.Key_I);
        verify(findChild(c, "notificationSend").enabled);
        keyClick(Qt.Key_Return);
        compare(replied.count, 1);
        compare(replied.signalArguments[0][0], "hi");
        verify(!c.replying, "sent: the field closes");
        // Escape closes without sending; the send button sends
        c.replying = true;
        tryVerify(() => findChild(c, "notificationReplyField")?.activeFocus, 2000);
        keyClick(Qt.Key_Escape);
        verify(!c.replying);
        compare(replied.count, 1);
        c.replying = true;
        tryVerify(() => findChild(c, "notificationReplyField")?.activeFocus, 2000);
        keyClick(Qt.Key_O);
        keyClick(Qt.Key_K);
        const send = findChild(c, "notificationSend");
        mouseClick(send, send.width / 2, send.height / 2);
        compare(replied.signalArguments[1][0], "ok");
        // no reply offered: no button
        const plain = createTemporaryObject(cardComp, root, { y: 400, notification: note(2) });
        verify(!plain.canReply);
    }

    function test_popups_reply() {
        const p = createTemporaryObject(popupsComp, root, { popups: [note(5, { reply: "Reply" })] });
        tryVerify(() => findChild(p, "notificationPopup_5"), 1000);
        const card = findChild(p, "notificationPopup_5").children[0];
        const replied = createTemporaryObject(spyComp, root, { target: p, signalName: "replied" });
        compare(p.replyingId, -1);
        card.replying = true;
        compare(p.replyingId, 5, "the window is told it needs the keyboard");
        card.sendReply("yes");
        compare(replied.signalArguments[0][0] + "," + replied.signalArguments[0][1], "5,yes");
        compare(p.replyingId, -1, "and that it is done");
        card.replying = true;
        p.popups = [];
        tryCompare(p, "replyingId", -1, 3000, "a card that goes gives the keyboard back");
    }
}
