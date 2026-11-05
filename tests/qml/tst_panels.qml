// Panel translucency (D115): the pills at the top of the screen and the panels they open take Panels.opacity as
// their background's alpha (the style.panelOpacity setting in the shell); 1, solid, by default.
import QtQuick
import QtTest
import qs.common
import qs.bar
import qs.notifications
import qs.calendar
import qs.quicksettings

TestCase {
    id: root
    name: "Panels"
    width: 600
    height: 600
    visible: true
    when: windowShown

    Component { id: status; StatusPill {} }
    Component { id: clock; ClockPill {} }
    Component { id: bell; NotificationBell {} }
    Component { id: tray; TrayPill {} }
    Component { id: notifications; NotificationPanel {} }
    Component { id: calendar; CalendarPanel {} }
    Component { id: quick; QuickSettingsPanel {} }

    function cleanup() {
        Panels.opacity = 1;
    }

    function test_tint() {
        compare(Panels.tint(Colors.surfaceContainer), Colors.surfaceContainer, "solid by default");
        Panels.opacity = 0.6;
        const c = Panels.tint(Colors.surfaceContainer);
        verify(Math.abs(c.a - 0.6) < 0.01);
        verify(Math.abs(c.r - Colors.surfaceContainer.r) < 0.01, "the same color");
    }

    function test_every_panel() {
        const all = { status: status, clock: clock, bell: bell, tray: tray, notifications: notifications,
                      calendar: calendar, quick: quick };
        const props = { status: { backend: {} }, clock: { now: new Date() }, quick: { backend: {} } };
        for (const name in all) {
            const item = createTemporaryObject(all[name], root, props[name] || {});
            verify(item, name);
            compare(item.color.a, 1, name + ": solid by default");
            Panels.opacity = 0.6;
            tryVerify(() => Math.abs(item.color.a - 0.6) < 0.01, 2000, name + ": as see-through as the panels");
            Panels.opacity = 1;
        }
    }

    function test_open_pill() {
        const pill = createTemporaryObject(status, root, { backend: {}, open: true });
        Panels.opacity = 0.6;
        tryCompare(pill, "color", Panels.tint(Colors.secondaryContainer), 2000, "open: its open color, as see-through");
    }
}
