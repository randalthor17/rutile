// Default apps (the Apps page, D71): which app opens web links, folders, mail, pictures and so on, from the
// desktop files' MimeType lines and the mimeapps.list files, as the freedesktop specs read them. The backend's
// script prints the files with markers (SCAN below); no QML here, so it tests alone.
.pragma library

// The kinds of file shown, each with its MIME types; the first is the one an app must take to be offered.
var KINDS = [
    { id: "browser", title: "Web browser", icon: "language", mimes: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"] },
    { id: "files", title: "Files", icon: "folder", mimes: ["inode/directory"] },
    { id: "mail", title: "Email", icon: "mail", mimes: ["x-scheme-handler/mailto"] },
    { id: "images", title: "Pictures", icon: "image", mimes: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml"] },
    { id: "video", title: "Videos", icon: "movie", mimes: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime"] },
    { id: "music", title: "Music", icon: "music_note", mimes: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4"] },
    { id: "text", title: "Text", icon: "description", mimes: ["text/plain"] },
    { id: "pdf", title: "PDF documents", icon: "picture_as_pdf", mimes: ["application/pdf"] }
];

// The script: every desktop file in $XDG_DATA_HOME and $XDG_DATA_DIRS (their [Desktop Entry] group's keys that
// matter), then each mimeapps.list in the order the spec reads them, the user's first (and whether it is a link,
// as home-manager's is). $1 is the user's config folder.
var SCAN = 'cfg="$1"; data="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"; ' +
    'IFS=:; for d in $data; do [ -d "$d/applications" ] || continue; ' +
    'for f in "$d"/applications/*.desktop; do [ -f "$f" ] || continue; echo "@@entry ${f##*/}"; ' +
    'sed -n "/^\\[Desktop Entry\\]/,/^\\[/{/^\\(Name\\|Icon\\|MimeType\\|NoDisplay\\|Hidden\\|Type\\)=/p}" "$f"; done; done; ' +
    'u="$cfg/mimeapps.list"; if [ -L "$u" ]; then echo "@@list link $u"; else echo "@@list user $u"; fi; [ -f "$u" ] && cat "$u"; ' +
    'for d in ${XDG_CONFIG_DIRS:-/etc/xdg}; do [ -f "$d/mimeapps.list" ] && { echo "@@list other $d/mimeapps.list"; cat "$d/mimeapps.list"; }; done; ' +
    'for d in $data; do [ -f "$d/applications/mimeapps.list" ] && { echo "@@list other $d/applications/mimeapps.list"; cat "$d/applications/mimeapps.list"; }; done; ' +
    'echo "@@end"';

// "[Group]\nkey=value..." into {Group: {key: value}}
function groups(text) {
    const out = {};
    let g = null;
    for (const raw of text.split("\n")) {
        const line = raw.trim();
        if (line === "" || line.startsWith("#")) continue;
        const m = /^\[(.+)\]$/.exec(line);
        if (m) {
            g = out[m[1]] = out[m[1]] ?? {};
            continue;
        }
        const eq = line.indexOf("=");
        if (g && eq > 0) g[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    }
    return out;
}
function list(v) {
    return (v ?? "").split(";").map(s => s.trim()).filter(s => s !== "");
}

// The script's output: {entries: {id: {id, name, icon, mimes, shown}}, lists: [{path, user, link, text,
// defaults}]}, the user's list first (there even when the file is not).
// The first desktop file with an id wins (XDG_DATA_HOME before XDG_DATA_DIRS).
function parse(text) {
    const entries = {};
    const lists = [];
    let cur = null;
    let listCur = null;
    let listText = [];
    const endList = () => {
        if (listCur) {
            listCur.text = listText.join("\n");
            listCur.defaults = groups(listCur.text)["Default Applications"] ?? {};
        }
        listCur = null;
        listText = [];
    };
    for (const line of text.split("\n")) {
        if (line.startsWith("@@entry ")) {
            endList();
            const id = line.slice(8).trim();
            cur = entries[id] ? null : (entries[id] = { id: id, name: id, icon: "", mimes: [], shown: true });
            continue;
        }
        if (line.startsWith("@@list ")) {
            endList();
            cur = null;
            const [, kind, ...path] = line.split(" ");
            listCur = { path: path.join(" "), user: kind !== "other", link: kind === "link", text: "", defaults: {} };
            lists.push(listCur);
            continue;
        }
        if (line.startsWith("@@end")) {
            endList();
            cur = null;
            continue;
        }
        if (listCur) {
            listText.push(line);
            continue;
        }
        if (!cur) continue;
        const eq = line.indexOf("=");
        if (eq < 0) continue;
        const k = line.slice(0, eq), v = line.slice(eq + 1).trim();
        if (k === "Name" && cur.name === cur.id) cur.name = v;
        else if (k === "Icon") cur.icon = v;
        else if (k === "MimeType") cur.mimes = list(v);
        else if ((k === "NoDisplay" || k === "Hidden") && v === "true") cur.shown = k === "NoDisplay" ? false : cur.shown;
        if (k === "Hidden" && v === "true") cur.hidden = true;
        if (k === "Type" && v !== "Application") cur.hidden = true;
    }
    for (const id of Object.keys(entries))
        if (entries[id].hidden) delete entries[id];
    return { entries: entries, lists: lists };
}

// The default app's id for a MIME type: the first installed one a mimeapps.list names, in the spec's order.
function defaultFor(parsed, mime) {
    for (const l of parsed.lists)
        for (const id of list(l.defaults[mime]))
            if (parsed.entries[id]) return id;
    return "";
}
// A kind's default: its first MIME type's.
function kindDefault(parsed, kind) {
    return defaultFor(parsed, kind.mimes[0]);
}
// The apps that take a kind's first MIME type, shown ones, by name; the default is always among them.
function candidates(parsed, kind) {
    const def = kindDefault(parsed, kind);
    return Object.values(parsed.entries)
        .filter(e => e.mimes.indexOf(kind.mimes[0]) >= 0 && (e.shown || e.id === def))
        .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}
function userList(parsed) {
    return parsed.lists.find(l => l.user) ?? null;
}

// The user's mimeapps.list `text` with `id` the default for each of `mimes` (other groups and keys kept).
function withDefault(text, mimes, id) {
    const lines = (text ?? "").split("\n");
    if (lines.length && lines[lines.length - 1] === "") lines.pop();
    let start = lines.findIndex(l => l.trim() === "[Default Applications]");
    if (start < 0) {
        if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
        lines.push("[Default Applications]");
        start = lines.length - 1;
    }
    let end = lines.findIndex((l, i) => i > start && /^\s*\[.*\]\s*$/.test(l));
    if (end < 0) end = lines.length;
    const body = lines.slice(start + 1, end).filter(l => !mimes.some(m => l.trim().startsWith(m + "=")));
    while (body.length && body[body.length - 1].trim() === "") body.pop();
    const added = mimes.map(m => m + "=" + id + ";");
    const rest = lines.slice(end);
    return lines.slice(0, start + 1).concat(body, added, rest.length ? [""] : [], rest).join("\n") + "\n";
}
