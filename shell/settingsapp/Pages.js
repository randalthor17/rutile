// The settings app's pages (plan 5.1): the registry. Each page has an id, a title, an icon in a tonal circle
// (`tone`, a container color role), a summary for the home list, `aliases` that search also matches, and sections
// of settings by their key in settings/schema.json. A setting's title, description, limits and default come from
// the schema; `hints` here only say how to show it when the schema alone does not (D45 keeps the schema to what
// Nix and the store need). Hints: `kind` (path, list), `choices` (values offered in a menu) with `label(value)`,
// `step` for a slider, `aliases` for search, `advanced` (shown under the page's Advanced section), `filters` for a
// path's file chooser ("Name (*.ext ...)"), `requires` (another setting that must be on for this one to apply),
// `swatches` (the colors a color setting offers). A key that is no setting can be an action: its hint has
// `kind: "action"`, a `title`, a `description` and the `button`'s text; the app asks for it (actionRequested).
// A page of its own making (plan 5.2) names its `view` (a QML file under pages/, loaded only while the page is
// open, after its sections) and may name a `backend` (the Quickshell services it shows, which the window loads
// only while the page is open; tests give the app a fake). Its `entries` ({key, title, description, aliases})
// are what search finds on it; the view names the matching item `setting_<key>`, so it can be marked.
.pragma library

var pages = [
    {
        id: "wallpaper", title: "Wallpaper & style", icon: "palette", tone: "tertiaryContainer",
        summary: "Wallpaper, colors", aliases: ["background", "theme", "colours", "palette", "matugen"],
        sections: [
            { title: "", keys: ["wallpaper.path", "wallpaper.palette"] },
            { title: "Style", keys: ["style.mode", "style.scheme", "style.contrast", "style.seed"] },
            { title: "Colors in other apps", keys: ["appColors.enabled", "appColors.niri", "appColors.gtk", "appColors.qt", "appColors.kde", "appColors.folders", "appColors.kitty", "appColors.ghostty", "appColors.btop", "appColors.nvim", "appColors.firefox", "action.flatpak"] }
        ]
    },
    {
        id: "network", title: "Network", icon: "wifi", tone: "primaryContainer",
        summary: "Wi-Fi, Ethernet", aliases: ["internet", "networkmanager"],
        sections: [],
        view: "pages/NetworkPage.qml", backend: "pages/NetworkBackend.qml",
        entries: [
            { key: "network.wifi", title: "Wi-Fi", description: "Wireless networks, and their passwords",
              aliases: ["wireless", "wlan", "password", "hotspot"] },
            { key: "network.ethernet", title: "Ethernet", description: "Wired connections",
              aliases: ["wired", "cable", "lan"] }
        ]
    },
    {
        id: "bluetooth", title: "Bluetooth", icon: "bluetooth", tone: "secondaryContainer",
        summary: "Devices", aliases: ["bluez"],
        sections: [],
        view: "pages/BluetoothPage.qml", backend: "pages/BluetoothBackend.qml",
        entries: [
            { key: "bluetooth.paired", title: "Paired devices", description: "Connect, disconnect or forget a device",
              aliases: ["earbuds", "mouse", "keyboard", "controller", "connect"] },
            { key: "bluetooth.available", title: "Available devices", description: "Pair a new device",
              aliases: ["pair", "add device", "new device"] }
        ]
    },
    {
        id: "sound", title: "Sound", icon: "volume_up", tone: "primaryContainer",
        summary: "Speakers, microphone", aliases: ["audio", "pipewire"],
        sections: [],
        view: "pages/SoundPage.qml", backend: "pages/SoundBackend.qml",
        entries: [
            { key: "sound.output", title: "Output", description: "Where sound plays, and its volume",
              aliases: ["speakers", "headphones", "volume", "mute"] },
            { key: "sound.input", title: "Input", description: "The microphone, and its volume",
              aliases: ["microphone", "mic", "recording"] }
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
        sections: [],
        view: "pages/AboutPage.qml"
    }
];

var hints = {
    "wallpaper.path": {
        kind: "path", aliases: ["image", "picture"],
        filters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
    },
    "wallpaper.palette": { aliases: ["matugen", "dynamic color"] },
    "style.mode": { label: v => v === "light" ? "Light" : "Dark", aliases: ["dark mode", "light mode", "night", "theme"] },
    "style.scheme": {
        label: v => ({ "scheme-tonal-spot": "Tonal spot", "scheme-content": "Content", "scheme-expressive": "Expressive",
                       "scheme-fidelity": "Fidelity", "scheme-fruit-salad": "Fruit salad", "scheme-monochrome": "Monochrome",
                       "scheme-neutral": "Neutral", "scheme-rainbow": "Rainbow", "scheme-vibrant": "Vibrant" })[v] ?? v,
        aliases: ["scheme", "vibrant", "monochrome", "palette style"]
    },
    "style.contrast": { step: 0.25, label: v => v === 0 ? "Standard" : (v > 0 ? "+" : "") + v, aliases: ["contrast"] },
    // Material's baseline and a few seeds around the color wheel
    "style.seed": {
        kind: "color", aliases: ["accent", "seed", "colour"],
        swatches: ["#134aae", "#6750a4", "#8e4585", "#b3261e", "#9a4600", "#7d5800", "#386a20", "#006a6a"]
    },
    "appColors.enabled": { aliases: ["matugen", "theme apps", "gtk", "qt", "terminal", "niri", "borders"] },
    "appColors.niri": { requires: "appColors.enabled", aliases: ["borders", "focus ring"] },
    "appColors.gtk": { requires: "appColors.enabled", aliases: ["gnome", "libadwaita", "nautilus"] },
    "appColors.qt": { requires: "appColors.enabled", aliases: ["kde", "qt5ct", "qt6ct"] },
    "appColors.kde": { requires: "appColors.enabled", aliases: ["dolphin", "kate", "kdeglobals"] },
    "appColors.folders": { requires: "appColors.enabled", aliases: ["icons", "papirus"] },
    "appColors.kitty": { requires: "appColors.enabled", aliases: ["terminal"] },
    "appColors.ghostty": { requires: "appColors.enabled", aliases: ["terminal"] },
    "appColors.btop": { requires: "appColors.enabled" },
    "appColors.nvim": { requires: "appColors.enabled", aliases: ["vim", "editor"] },
    "appColors.firefox": { requires: "appColors.enabled", aliases: ["pywalfox", "browser"] },
    // Flatpak apps see none of this until set up (D66): rutile-shell flatpak-theming, in a terminal
    "action.flatpak": {
        kind: "action", title: "Flatpak apps", button: "Set up…",
        description: "Install the GTK and Kvantum themes for Flatpak apps and let them read these colors",
        aliases: ["flatpak", "flathub", "sandbox", "inkscape"]
    },
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
