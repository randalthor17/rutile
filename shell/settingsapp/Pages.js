// The settings app's pages (plan 5.1): the registry. Each page has an id, a title, an icon in a tonal circle
// (`tone`, a container color role), a summary for the home list, `aliases` that search also matches, and sections
// of settings by their key in settings/schema.json. A setting's title, description, limits and default come from
// the schema; `hints` here only say how to show it when the schema alone does not (D45 keeps the schema to what
// Nix and the store need). Hints: `kind` (path, list), `choices` (values offered in a menu) with `label(value)`,
// `step` for a slider, `aliases` for search, `advanced` (shown under the page's Advanced section), `filters` for a
// path's file chooser ("Name (*.ext ...)"), `requires` (another setting that must be on for this one to apply),
// `swatches` (the colors a color setting offers), `placeholder` (a typed setting's example, D79). A key that is no setting can be an action: its hint has
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
            { title: "Colors in other apps", keys: ["appColors.enabled", "appColors.niri", "appColors.gtk", "appColors.qt", "appColors.kde", "appColors.folders", "appColors.kitty", "appColors.ghostty", "appColors.btop", "appColors.nvim", "appColors.firefox", "action.flatpak"] },
            { title: "", keys: ["notice.niriInclude"] }
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
        id: "display", title: "Display", icon: "desktop_windows", tone: "tertiaryContainer",
        summary: "Resolution, size, orientation", aliases: ["monitor", "screen", "niri outputs"],
        sections: [],
        view: "pages/DisplayPage.qml", backend: "pages/DisplayBackend.qml",
        entries: [
            { key: "display.outputs", title: "Displays", description: "Resolution, refresh rate, size and orientation",
              aliases: ["resolution", "refresh rate", "hz", "scale", "rotate", "vrr", "freesync"] }
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
        id: "power", title: "Power", icon: "battery_charging_full", tone: "primaryContainer",
        summary: "Battery, power mode", aliases: ["upower", "power-profiles-daemon"],
        sections: [],
        view: "pages/PowerPage.qml", backend: "pages/PowerBackend.qml",
        entries: [
            { key: "power.battery", title: "Battery", description: "Charge, time left and health",
              aliases: ["charge", "charging", "time left"] },
            { key: "power.mode", title: "Power mode", description: "Power saver, balanced or performance",
              aliases: ["power profile", "power saver", "performance", "balanced", "energy"] }
        ]
    },
    {
        id: "input", title: "Keyboard, mouse & touchpad", icon: "keyboard", tone: "secondaryContainer",
        summary: "Key repeat, pointer speed, tap to click", aliases: ["input", "trackpad", "pointer", "niri input"],
        sections: [
            { title: "", keys: ["notice.niriInclude", "input.enabled"] },
            { title: "Keyboard", keys: ["input.keyboardLayout", "input.repeatDelay", "input.repeatRate"] },
            { title: "Touchpad", keys: ["input.touchpadTap", "input.touchpadDisableWhileTyping", "input.touchpadNaturalScroll", "input.touchpadSpeed"] },
            { title: "Mouse", keys: ["input.mouseSpeed", "input.mouseFlat", "input.mouseNaturalScroll"] }
        ]
    },
    {
        id: "apps", title: "Apps", icon: "apps", tone: "tertiaryContainer",
        summary: "Default apps", aliases: ["mimeapps", "open with", "xdg-mime"],
        sections: [],
        view: "pages/AppsPage.qml", backend: "pages/AppsBackend.qml",
        entries: [
            { key: "apps.defaults", title: "Default apps", description: "Which app opens links, folders, pictures and more",
              aliases: ["default browser", "web browser", "file manager", "email", "pdf viewer", "image viewer", "video player"] }
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
        sections: [],
        view: "pages/ShelfPage.qml", backend: "pages/ShelfPinsBackend.qml",
        entries: [
            { key: "shelf.pins", title: "Pinned apps", description: "The apps on the shelf, in order",
              aliases: ["pin", "unpin", "favorites", "dock apps"] }
        ]
    },
    {
        id: "widgets", title: "Widgets", icon: "widgets", tone: "tertiaryContainer",
        summary: "Desktop grid, weather place, web data", aliases: ["weather", "location", "http", "data sources", "desktop"],
        sections: [
            { title: "Desktop", keys: ["widgets.columns"] },
            { title: "Weather", keys: ["widgets.latitude", "widgets.longitude", "widgets.units"] },
            { title: "Web data", keys: ["widgets.httpAllow"] }
        ]
    },
    {
        id: "accessibility", title: "Accessibility", icon: "accessibility_new", tone: "primaryContainer",
        summary: "Animations", aliases: ["motion", "animation", "reduce motion"],
        sections: [{ title: "", keys: ["motion.speed", "motion.niri"] }, { title: "", keys: ["notice.niriInclude"] }]
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
    "input.enabled": { aliases: ["niri", "rutile-settings.kdl"] },
    "input.keyboardLayout": {
        requires: "input.enabled", aliases: ["xkb", "language", "qwerty", "azerty", "qwertz"],
        label: v => ({ "": "Not set", us: "English (US)", gb: "English (UK)", de: "German", fr: "French", es: "Spanish",
                       it: "Italian", pt: "Portuguese", br: "Portuguese (Brazil)", nl: "Dutch", be: "Belgian",
                       ch: "Swiss", at: "Austrian", se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish",
                       pl: "Polish", cz: "Czech", hu: "Hungarian", ro: "Romanian", tr: "Turkish", gr: "Greek",
                       ru: "Russian", ua: "Ukrainian", il: "Hebrew", ara: "Arabic", in: "Indian", jp: "Japanese",
                       kr: "Korean", latam: "Spanish (Latin America)" })[v] ?? v
    },
    "input.repeatDelay": { requires: "input.enabled", step: 50, label: v => v + " ms", aliases: ["keyboard", "typing"] },
    "input.repeatRate": { requires: "input.enabled", step: 5, label: v => v + " per second", aliases: ["keyboard", "typing"] },
    "input.touchpadTap": { requires: "input.enabled", aliases: ["click", "trackpad"] },
    "input.touchpadDisableWhileTyping": { requires: "input.enabled", aliases: ["dwt", "palm", "trackpad"] },
    "input.touchpadNaturalScroll": { requires: "input.enabled", aliases: ["reverse scrolling", "trackpad"] },
    "input.touchpadSpeed": { requires: "input.enabled", step: 0.1, label: v => (v > 0 ? "+" : "") + v.toFixed(1),
                             aliases: ["pointer speed", "sensitivity", "trackpad"] },
    "input.mouseNaturalScroll": { requires: "input.enabled", aliases: ["reverse scrolling", "wheel"] },
    "input.mouseSpeed": { requires: "input.enabled", step: 0.1, label: v => (v > 0 ? "+" : "") + v.toFixed(1),
                          aliases: ["pointer speed", "sensitivity", "dpi"] },
    "input.mouseFlat": { requires: "input.enabled", aliases: ["acceleration", "accel", "raw input", "gaming"] },
    "notifications.sound": { aliases: ["audio", "chime"] },
    // typed, not a slider: a place is a number to a few decimals
    "widgets.columns": {
        choices: [8, 12, 16, 20, 24], label: v => v + " columns", aliases: ["desktop", "grid", "size"]
    },
    "widgets.latitude": { kind: "text", placeholder: "52.52", aliases: ["location", "place", "weather"] },
    "widgets.longitude": { kind: "text", placeholder: "13.41", aliases: ["location", "place", "weather"] },
    "widgets.units": {
        label: v => v === "imperial" ? "°F, mph" : "°C, km/h", aliases: ["fahrenheit", "celsius", "temperature"]
    },
    "widgets.httpAllow": { kind: "list", placeholder: "https://api.example.org/", aliases: ["allowlist", "url", "http", "fetch", "api"] },
    "lock.idleMinutes": {
        choices: [0, 1, 2, 5, 10, 15, 30, 60],
        label: v => v === 0 ? "Never" : (v === 1 ? "After 1 minute" : "After " + v + " minutes"),
        aliases: ["timeout", "screen saver"]
    },
    "lock.beforeSleep": { aliases: ["suspend", "hibernate"] },
    "polkit.agent": { advanced: true, aliases: ["pkexec", "sudo", "authentication"] },
    "motion.niri": { aliases: ["niri", "window animations", "workspace animations"] },
    // shown only while niri's config does not include rutile.kdl (the app's `conditions`, D74)
    "notice.niriInclude": {
        kind: "notice", when: "niriNotIncluded", title: "niri does not read these yet",
        description: 'Add include optional=true "rutile.kdl" at the end of niri\'s config.kdl, or set programs.rutile.niri.includeInConfig'
    },
    "motion.speed": {
        step: 0.25,
        label: v => v === 0 ? "Off" : v + "×",
        aliases: ["speed", "fast"]
    }
};

function page(id) {
    return pages.find(p => p.id === id) ?? null;
}
