// Media controls (D117) as plain functions over MPRIS players (Quickshell's MprisPlayer, or the tests' fakes with the
// same members): which player the card and the media keys act on, and how times read.
.pragma library

// The player to show and control: the one with id `chosen` (its dbusName) while it is there, else the first one
// playing, else the first. null when there is none.
function current(players, chosen) {
    var list = (players || []).filter(function (p) { return !!p; });
    if (list.length === 0) return null;
    if (chosen) {
        var picked = list.filter(function (p) { return p.dbusName === chosen; })[0];
        if (picked) return picked;
    }
    return list.filter(function (p) { return p.isPlaying; })[0] || list[0];
}

// The player after `player` in `players`, round: what the card's switch goes to.
function next(players, player) {
    var list = (players || []).filter(function (p) { return !!p; });
    if (list.length === 0) return null;
    var at = list.indexOf(player);
    return list[(at + 1) % list.length];
}

// Seconds as m:ss, or h:mm:ss from an hour on; "" for none.
function time(seconds) {
    if (!(seconds >= 0) || !isFinite(seconds)) return "";
    var s = Math.floor(seconds);
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
}

// What the card says under the title: the artist(s), else the player's name.
function subtitle(player) {
    if (!player) return "";
    return player.trackArtist || player.identity || "";
}
