// Wallhaven (D128), after Noctalia's wallhaven plugin: search wallhaven.cc, then download a wallpaper into the
// wallpaper folder and set it. search() asks the API (Wallhaven.js) and fills `wallpapers`, `page` and `pages`; an
// answer to an older search is dropped. The filters are remembered in state.json. apply() downloads the full image
// with curl and sets it as the wallpaper (WallpaperService), with a toast either way. The optional API key
// (wallhaven.apiKey) goes in a request header, never in the address, and allows NSFW results.
// RUTILE_WALLHAVEN_API: tests only (a web server of the test's own instead of wallhaven.cc).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../wallhaven/Wallhaven.js" as Wallhaven

Singleton {
    id: root

    property string base: Quickshell.env("RUTILE_WALLHAVEN_API") || Wallhaven.API
    readonly property string apiKey: String(Settings.value("wallhaven.apiKey") ?? "").trim()
    readonly property bool hasKey: apiKey !== ""
    // the wallhaven.folder setting (~ is the home folder), else Pictures/Wallpapers
    readonly property string folder: String(Settings.value("wallhaven.folder") ?? "").trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
        || ((Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")) + "/Wallpapers")

    property var filters: Object.assign(Wallhaven.defaults(), Settings.stateValue("wallhaven.filters", {}), { query: "" })
    property var wallpapers: []
    property int page: 1
    property int pages: 1
    property bool loading: false
    property string error: ""
    property string applying: ""        // the id being downloaded, "" when none
    property int searches: 0            // the newest search; older answers are dropped
    property var request: null

    // Changes the filters (any of Wallhaven.defaults()'s) and searches again from the first page.
    function setFilters(changes) {
        filters = Object.assign({}, filters, changes);
        const kept = Object.assign({}, filters);
        delete kept.query;
        Settings.setState("wallhaven.filters", kept);
        search(1);
    }

    function search(p) {
        const n = ++searches;
        if (request) {
            request.onreadystatechange = null;
            request.abort();
        }
        loading = true;
        error = "";
        const xhr = new XMLHttpRequest();
        request = xhr;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || n !== root.searches) return;
            root.request = null;
            root.loading = false;
            if (xhr.status !== 200) {
                root.wallpapers = [];
                root.error = xhr.status === 401 ? "Wallhaven refused the API key"
                           : xhr.status === 429 ? "Too many searches; wait a minute"
                           : xhr.status === 0 ? "No connection to Wallhaven" : "Wallhaven answered " + xhr.status;
                return;
            }
            const r = Wallhaven.parse(xhr.responseText, root.filters);
            root.wallpapers = r.wallpapers;
            root.pages = r.pages;
            root.page = Math.min(p, r.pages);
            root.error = r.error ?? "";
        };
        xhr.open("GET", Wallhaven.searchUrl(base, filters, p, hasKey));
        xhr.setRequestHeader("Accept", "application/json");
        if (hasKey) xhr.setRequestHeader("X-API-Key", apiKey);
        xhr.send();
    }

    // Downloads `w` (one of `wallpapers`) and sets it; false while another downloads.
    function apply(w) {
        if (applying !== "" || !w) return false;
        applying = w.id;
        downloader.dest = Wallhaven.fileName(folder, w);
        downloader.command = Wallhaven.downloadCommand(w.path, downloader.dest);
        downloader.running = true;
        return true;
    }

    Process {
        id: downloader
        property string dest: ""
        onExited: code => {
            root.applying = "";
            if (code === 0 && WallpaperService.set(dest)) {
                ToastService.show("Wallpaper set from Wallhaven", { icon: "wallpaper" });
            } else {
                ToastService.show(code === 0 ? "Wallpaper is set in your Nix configuration"
                                             : "Could not download the wallpaper", { icon: "error" });
            }
        }
    }
}
