// The Widgets app's data (plan 4.5, D82), as pure functions: the template categories, which template is in which,
// and what using one needs (the web address it reads, the editor to open it in).
.pragma library

// Templates are widgets/templates/<category>-<n>.json; "yours" lists the user's own widget folder.
var categories = [
    { id: "weather", title: "Weather", icon: "partly_cloudy_day", tone: "primaryContainer", summary: "Now, today's range, wind" },
    { id: "daily-update", title: "Daily update", icon: "today", tone: "secondaryContainer", summary: "Time, weather, events, battery" },
    { id: "world-clock", title: "World clock", icon: "public", tone: "tertiaryContainer", summary: "Another place's time" },
    { id: "finance", title: "Finance", icon: "payments", tone: "primaryContainer", summary: "Exchange rates, crypto" },
    { id: "countdown", title: "Countdown", icon: "timer", tone: "secondaryContainer", summary: "Days to a date" },
    { id: "sports", title: "Sports", icon: "sports_soccer", tone: "tertiaryContainer", summary: "Fixtures, results, match day" },
    { id: "system", title: "System", icon: "monitoring", tone: "secondaryContainer", summary: "CPU, GPU, memory, temperatures" },
    { id: "yours", title: "Your widgets", icon: "widgets", tone: "primaryContainer", summary: "~/.config/rutile/widgets" }
];

function category(id) {
    for (var i = 0; i < categories.length; i++)
        if (categories[i].id === id) return categories[i];
    return null;
}

function baseName(path) {
    return String(path).replace(/^.*\//, "").replace(/\.json$/, "");
}

// A template's category from its file name (weather-3.json: weather), or "".
function categoryOf(path) {
    var m = /^([a-z-]+)-([0-9]+)$/.exec(baseName(path));
    return m && category(m[1]) ? m[1] : "";
}

// The templates (from a scan: [{path, name}]) in category `id`, in their order.
function templatesIn(available, id) {
    var number = function (a) { return Number(/-([0-9]+)$/.exec(baseName(a.path))[1]); };
    return available.filter(function (a) { return categoryOf(a.path) === id; })
                    .sort(function (a, b) { return number(a) - number(b); });
}

// The beginning of the address a widget fetches (its scheme, host and a slash), as Settings > Widgets lists
// allowed ones; "" for a widget that fetches nothing.
function fetches(spec) {
    var m = /^(https?:\/\/[^\/?#]+)/.exec(url(spec));
    return m ? m[1] + "/" : "";
}
// The address itself, or "".
function url(spec) {
    var u = spec && spec.sources && spec.sources.http && spec.sources.http.url;
    return typeof u === "string" ? u : "";
}

// The command that opens `path` for editing: the `widgets.editor` setting's words and the path, or xdg-open.
function editorCommand(setting, path) {
    var words = String(setting || "").trim().split(/\s+/).filter(function (w) { return w !== ""; });
    return (words.length ? words : ["xdg-open"]).concat([path]);
}

// What a template's copy is called in the user's folder: its title in lower case with dashes (Dollar today:
// dollar-today), or the template's own name.
function fileStem(spec, path) {
    var name = spec && typeof spec.name === "string" ? spec.name : "";
    var stem = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return stem || baseName(path);
}
