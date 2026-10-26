// The power menu's entries and the commands they run (systemd-logind and niri). Kept apart so the menu and the
// commands are tested offscreen; nothing here runs anything.
.pragma library

var actions = [
    // Locks only once a lock screen listens for logind's Lock signal (plan 2.8; until then e.g. swayidle).
    { id: "lock", text: "Lock", icon: "lock", command: ["loginctl", "lock-session"] },
    { id: "logout", text: "Sign out", icon: "logout", command: ["niri", "msg", "action", "quit", "--skip-confirmation"] },
    { id: "reboot", text: "Restart", icon: "restart_alt", command: ["systemctl", "reboot"] },
    { id: "poweroff", text: "Shut down", icon: "power_settings_new", command: ["systemctl", "poweroff"] }
];

// The command for an action id, or null for an unknown id.
function command(id) {
    for (var i = 0; i < actions.length; i++)
        if (actions[i].id === id) return actions[i].command;
    return null;
}
