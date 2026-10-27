// The power menu's entries and the commands they run (systemd-logind and niri). Kept apart so the menu and the
// commands are tested offscreen; nothing here runs anything. The shell runs them (shell.qml) once the menu has gone.
.pragma library

var actions = [
    // No command: the shell locks itself (its lock screen, plan 2.8).
    { id: "lock", text: "Lock", icon: "lock", command: null },
    { id: "suspend", text: "Sleep", icon: "bedtime", command: ["systemctl", "suspend"] },
    { id: "logout", text: "Sign out", icon: "logout", command: ["niri", "msg", "action", "quit", "--skip-confirmation"] },
    { id: "reboot", text: "Restart", icon: "restart_alt", command: ["systemctl", "reboot"] },
    { id: "poweroff", text: "Shut down", icon: "power_settings_new", command: ["systemctl", "poweroff"] }
];

// The command for an action id, or null for an unknown id or one the shell does itself (lock).
function command(id) {
    for (var i = 0; i < actions.length; i++)
        if (actions[i].id === id) return actions[i].command;
    return null;
}
