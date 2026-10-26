// The launcher's category chips: freedesktop main categories (and a few common additional ones) folded into
// short labels, in chip order. An app is in every chip one of its desktop `Categories` maps to; apps with none
// of these show only under All. Only chips that hold an app are shown.
.pragma library

var list = [
    { id: "internet", label: "Internet", categories: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
    { id: "media", label: "Media", categories: ["AudioVideo", "Audio", "Video"] },
    { id: "graphics", label: "Graphics", categories: ["Graphics", "Photography"] },
    { id: "office", label: "Office", categories: ["Office"] },
    { id: "development", label: "Development", categories: ["Development"] },
    { id: "games", label: "Games", categories: ["Game"] },
    { id: "education", label: "Education", categories: ["Education", "Science"] },
    { id: "system", label: "System", categories: ["System", "Settings", "Monitor"] },
    { id: "utilities", label: "Utilities", categories: ["Utility", "Accessories"] }
];

function matches(app, id) {
    var entry = list.find(c => c.id === id);
    var own = app.categories || [];
    return !!entry && entry.categories.some(c => own.indexOf(c) >= 0);
}

// The chips with at least one app, in chip order.
function present(apps) {
    return list.filter(c => apps.some(a => matches(a, c.id)));
}

// The apps of a chip; "" is All.
function filter(apps, id) {
    return id === "" ? apps : apps.filter(a => matches(a, id));
}
