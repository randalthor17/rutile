// Wallhaven (D128): wallhaven.cc's search API (https://wallhaven.cc/help/api), as Noctalia's wallhaven plugin uses
// it: the search address from the filters, its answer, and the download of a full image into the wallpaper folder.
// Kept apart from the QML so the offscreen tests check it.
.pragma library

var API = "https://wallhaven.cc/api/v1";

// The sort orders the API takes, as the panel offers them.
var SORTS = [
    { id: "date_added", text: "Newest" },
    { id: "toplist", text: "Top" },
    { id: "hot", text: "Hot" },
    { id: "views", text: "Most viewed" },
    { id: "favorites", text: "Most favorited" },
    { id: "random", text: "Random" },
    { id: "relevance", text: "Relevance" }
];

// The shapes offered: "" any, then the API's own ratio names.
var RATIOS = [
    { id: "", text: "Any shape" },
    { id: "landscape", text: "Wide" },
    { id: "portrait", text: "Tall" },
    { id: "16x9", text: "16:9" },
    { id: "16x10", text: "16:10" },
    { id: "21x9", text: "21:9" },
    { id: "32x9", text: "32:9" },
    { id: "4x3", text: "4:3" },
    { id: "1x1", text: "1:1" }
];

// The filters a search starts with; `atLeast` is "WxH" or "".
function defaults() {
    return { query: "", general: true, anime: true, people: true, sfw: true, sketchy: false, nsfw: false,
             sorting: "date_added", order: "desc", ratio: "", atLeast: "" };
}

// Three flags as the API writes them: "110". None at all is read as all three, as an empty choice means no filter.
function flags(a, b, c) {
    var s = (a ? "1" : "0") + (b ? "1" : "0") + (c ? "1" : "0");
    return s === "000" ? "111" : s;
}

// Wallhaven gives an empty first page when sorting by relevance without a query, so that search starts a page later.
function skipsFirstPage(f) {
    return f.sorting === "relevance" && String(f.query || "").trim() === "";
}

// The search address for filters `f` (defaults() and changes) and `page` (1 up). NSFW only with an API key.
function searchUrl(base, f, page, hasKey) {
    var purity = flags(f.sfw, f.sketchy, f.nsfw && hasKey);
    if (purity === "111" && !hasKey) purity = "110";
    var params = [
        "categories=" + flags(f.general, f.anime, f.people),
        "purity=" + purity,
        "sorting=" + encodeURIComponent(f.sorting || "date_added"),
        "order=" + (f.order === "asc" ? "asc" : "desc"),
        "page=" + (page + (skipsFirstPage(f) ? 1 : 0))
    ];
    var q = String(f.query || "").trim();
    if (q !== "") params.push("q=" + encodeURIComponent(q));
    if (/^\d+x\d+$/.test(f.atLeast || "")) params.push("atleast=" + f.atLeast);
    if (f.ratio) params.push("ratios=" + encodeURIComponent(f.ratio));
    return (base || API) + "/search?" + params.join("&");
}

// The API's answer: {wallpapers: [{id, thumb, path, resolution, purity, type}], pages} or {error}.
function parse(text, f) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { error: "Wallhaven sent something unexpected", wallpapers: [], pages: 1 };
    }
    if (!doc || !Array.isArray(doc.data))
        return { error: doc && doc.error ? String(doc.error) : "Wallhaven sent something unexpected", wallpapers: [], pages: 1 };
    var last = doc.meta && doc.meta.last_page > 0 ? Math.floor(doc.meta.last_page) : 1;
    var pages = f && skipsFirstPage(f) ? Math.max(1, last - 1) : last;
    var out = [];
    doc.data.forEach(function (w) {
        if (!w || typeof w.id !== "string" || !/^[A-Za-z0-9]+$/.test(w.id) || typeof w.path !== "string") return;
        out.push({ id: w.id, path: w.path, thumb: (w.thumbs && (w.thumbs.small || w.thumbs.large)) || "",
                   resolution: String(w.resolution || ""), purity: String(w.purity || "sfw"),
                   type: String(w.file_type || "") });
    });
    return { wallpapers: out, pages: pages };
}

// The file a wallpaper is saved as in `folder`.
function fileName(folder, w) {
    var ext = w.type === "image/png" ? ".png" : ".jpg";
    return folder.replace(/\/+$/, "") + "/wallhaven-" + w.id + ext;
}

// Downloads `url` to `dest` through curl: into a part file, moved into place only when complete, so a failed
// download never leaves a broken wallpaper. The address and path are arguments, never part of the script.
function downloadCommand(url, dest) {
    return ["sh", "-c", 'mkdir -p "$(dirname "$2")" && curl -fsSL --max-time 300 -o "$2.part" "$1" && mv -f "$2.part" "$2"'
                        + ' || { rm -f "$2.part"; exit 1; }', "sh", url, dest];
}
