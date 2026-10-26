// How often and how lately each app was opened from the launcher (frecency), as plain data kept in state.json
// (`launcher.usage`, D45): {appId: {count, last}}, `last` in ms since the epoch. A search ranks the apps used
// more, and more lately, higher (Scorer.js's usage bonus); the grid without a query stays in name order.
.pragma library

var maxApps = 200;                  // the least recently used are dropped past this, so the file stays small
var day = 24 * 60 * 60 * 1000;
// how much a use counts by its age, as Firefox's frecency buckets it
var buckets = [[4 * day, 1], [14 * day, 0.7], [31 * day, 0.5], [90 * day, 0.3]];
var old = 0.1;

// A copy of `usage` with one more use of `id` at `now`.
function record(usage, id, now) {
    var out = {};
    for (var k in usage) out[k] = usage[k];
    var prev = out[id];
    out[id] = { count: (prev && prev.count > 0 ? prev.count : 0) + 1, last: now };
    var ids = Object.keys(out);
    if (ids.length > maxApps) {
        ids.sort(function (a, b) { return (out[a].last || 0) - (out[b].last || 0); });
        for (var i = 0; i < ids.length - maxApps; i++) delete out[ids[i]];
    }
    return out;
}

// The uses that count for an entry at `now`: its count weighted by the age of its last use; 0 without one.
function score(entry, now) {
    if (!entry || !(entry.count > 0)) return 0;
    var age = now - (entry.last || 0);
    for (var i = 0; i < buckets.length; i++)
        if (age < buckets[i][0]) return entry.count * buckets[i][1];
    return entry.count * old;
}
