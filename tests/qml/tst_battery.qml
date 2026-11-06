// Low battery warnings (plan 2.13 B1, D136): which is due as the charge falls, what it says, and the commands.
import QtQuick
import QtTest
import "../qs/services/Battery.js" as Battery

TestCase {
    name: "Battery"

    function key(p, warned, discharging) {
        const l = Battery.due(p, discharging ?? true, warned ?? []);
        return l ? l.key : null;
    }

    function test_due() {
        compare(key(50), null, "plenty");
        compare(key(20), "low", "at 20%");
        compare(key(19, ["low"]), null, "once");
        compare(key(10, ["low"]), "lower");
        compare(key(5, ["low", "lower"]), "critical");
        compare(key(4, ["low", "lower", "critical"]), null);
        compare(key(8), "lower", "started at 8%: the 10% one, not the 20% one");
        compare(key(3, ["low"]), "critical", "a jump past a level: the most severe");
        compare(key(3, [], false), null, "never while charging");
        compare(Battery.warnedAfter(Battery.LEVELS[1]).join(), "low,lower", "and the milder ones count as warned");
        compare(Battery.warnedAfter(Battery.LEVELS[2]).join(), "low,lower,critical");
    }

    function test_message() {
        compare(Battery.duration(0), "");
        compare(Battery.duration(40 * 60), "40 min");
        compare(Battery.duration(85 * 60), "1 h 25 min");
        compare(Battery.duration(120 * 60), "2 h");
        const low = Battery.message(Battery.LEVELS[0], 19.6, 85 * 60, "HybridSleep");
        compare(low.summary, "Battery low");
        compare(low.body, "20%, about 1 h 25 min left. Plug in soon, or turn on Power saver.");
        verify(!low.critical);
        compare(Battery.message(Battery.LEVELS[1], 9, 0, "").body, "9% left. Plug in soon, or turn on Power saver.");
        const crit = Battery.message(Battery.LEVELS[2], 4, 300, "PowerOff");
        compare(crit.summary, "Battery critically low");
        compare(crit.body, "4%, about 5 min left. Plug in now: the computer will turn off soon.");
        verify(crit.critical);
        compare(Battery.message(Battery.LEVELS[2], 4, 0, "Unknown").body, "4% left. Plug in now.");
        compare(Battery.actionText("HybridSleep"), "hibernate");
    }

    function test_commands() {
        const c = Battery.notifyCommand({ summary: "S x", body: "B: 9%.", critical: true }, 7);
        compare(c.slice(0, 9).join(" "), "busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications Notify susssasa{sv}i");
        compare(c.slice(9).join("|"), "Battery|7|battery_alert|S x|B: 9%.|0|2|urgency|y|2|category|s|device|0",
                "every text one argument; critical: urgency 2, no timeout; replacing 7");
        const n = Battery.notifyCommand({ summary: "S", body: "B", critical: false }, 0);
        compare(n.slice(10, 11).join(), "0");
        compare(n[n.length - 1], "-1", "the server's timeout");
        compare(n[n.length - 5], "1", "normal urgency");
        compare(Battery.closeCommand(7).slice(-2).join(" "), "u 7");
        compare(Battery.parseId("u 12\n"), 12);
        compare(Battery.parseId("nope"), 0);
    }
}
