// The settings app's pages (plan 5.1): the registry. Each page has an id, a title, an icon in a tonal circle
// (`tone`, a container color role), a summary for the home list, `aliases` that search also matches, and sections
// of settings by their key in settings/schema.json. A setting's title, description, limits and default come from
// the schema; `hints` here only say how to show it when the schema alone does not (D45 keeps the schema to what
// Nix and the store need). Hints: `kind` (path, list), `choices` (values offered in a menu) with `label(value)`,
// `step` for a slider, `aliases` for search, `advanced` (shown under the page's Advanced section), `filters` for a
// path's file chooser ("Name (*.ext ...)"), `requires` (another setting that must be on for this one to apply).
.pragma library

var pages = [
    {
        id: "wallpaper", title: "Wallpaper & style", icon: "palette", tone: "tertiaryContainer",
        summary: "Wallpaper, colors", aliases: ["background", "theme", "colours", "palette", "matugen"],
        sections: [
            { title: "", keys: ["wallpaper.path", "wallpaper.palette"] },
            { title: "Colors in other apps", keys: ["appColors.enabled", "appColors.niri", "appColors.gtk", "appColors.qt", "appColors.kde", "appColors.kitty", "appColors.ghostty", "appColors.btop", "appColors.nvim", "appColors.firefox"] }
        ]
    },
    {
        id: "notifications", title: "Notifications", icon: "notifications", tone: "errorContainer",
        summary: "Sounds", aliases: ["alerts", "popups"],
        sections: [{ title: "", keys: ["notifications.sound"] }]
    },
    {
        id: "security", title: "Security & privacy", icon: "lock", tone: "primaryContainer",
        summary: "Screen lock, passwords", aliases: ["lock screen", "idle", "polkit", "admin"],
        sections: [
            { title: "Screen lock", keys: ["lock.idleMinutes", "lock.beforeSleep"] },
            { title: "Passwords", keys: ["polkit.agent"] }
        ]
    },
    {
        id: "shelf", title: "Shelf", icon: "dock_to_bottom", tone: "secondaryContainer",
        summary: "Pinned apps", aliases: ["dock", "taskbar", "pins"],
        sections: [{ title: "", keys: ["shelf.pins"] }]
    },
    {
        id: "accessibility", title: "Accessibility", icon: "accessibility_new", tone: "primaryContainer",
        summary: "Animations", aliases: ["motion", "animation", "reduce motion"],
        sections: [{ title: "", keys: ["motion.speed"] }]
    },
    {
        id: "about", title: "About Rutile", icon: "info", tone: "secondaryContainer",
        summary: "Where settings are kept", aliases: ["version", "files", "nix", "home-manager"],
        sections: []
    }
];

var hints = {
    "wallpaper.path": {
        kind: "path", aliases: ["image", "picture"],
        filters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
    },
    "wallpaper.palette": { aliases: ["matugen", "dynamic color"] },
    "appColors.enabled": { aliases: ["matugen", "theme apps", "gtk", "qt", "terminal", "niri", "borders"] },
    "appColors.gtk": { requires: "appColors.enabled", aliases: ["gnome", "libadwaita", "nautilus"] },
    "appColors.qt": { requires: "appColors.enabled", aliases: ["kde", "qt5ct", "qt6ct"] },
    "appColors.kitty": { requires: "appColors.enabled", aliases: ["terminal"] },
    "appColors.ghostty": { requires: "appColors.enabled", aliases: ["terminal"] },
    "appColors.btop": { requires: "appColors.enabled" },
    "appColors.nvim": { requires: "appColors.enabled", aliases: ["vim", "editor"] },
    "appColors.firefox": { requires: "appColors.enabled", aliases: ["pywalfox", "browser"] },
    "notifications.sound": { aliases: ["audio", "chime"] },
    "lock.idleMinutes": {
        choices: [0, 1, 2, 5, 10, 15, 30, 60],
        label: v => v === 0 ? "Never" : (v === 1 ? "After 1 minute" : "After " + v + " minutes"),
        aliases: ["timeout", "screen saver"]
    },
    "lock.beforeSleep": { aliases: ["suspend", "hibernate"] },
    "polkit.agent": { advanced: true, aliases: ["pkexec", "sudo", "authentication"] },
    "shelf.pins": { kind: "list" },
    "motion.speed": {
        step: 0.25,
        label: v => v === 0 ? "Off" : v + "×",
        aliases: ["speed", "fast"]
    }
};

function page(id) {
    return pages.find(p => p.id === id) ?? null;
}
