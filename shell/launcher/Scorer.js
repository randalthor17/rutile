// Ranks launcher results for a query. Ported from DankMaterialShell's quickshell/Modals/DLauncherV2/Scorer.js
// (MIT, Copyright (c) 2025 Avenge Media LLC; see NOTICE): exact, prefix, word-start and substring matches, a
// typo-tolerant fuzzy match, then the subtitle, keywords, generic name and desktop id at lower weights. Rutile's
// changes: no sections or pre-scored items, an in-order letter match on the name ("nvi" finds Neovide), and the
// usage (Usage.js) only ranks search results: without a query the apps stay in name order.
.pragma library

var Weights = {
    exactMatch: 10000,
    prefixMatch: 5000,
    wordBoundary: 3000,
    substring: 500,
    subsequence: 250,
    genericPrefix: 800,
    generic: 400,
    id: 350,
    fuzzy: 100,
    frecency: 2000,
    typeBonus: { app: 1000, setting: 850, action: 600 }
};

function tokenize(text) {
    return text.toLowerCase().trim().split(/[\s\-_]+/).filter(w => w.length > 0);
}

// Every query word starts consecutive words of the text ("vis stu" in "visual studio code").
function hasWordBoundaryMatch(text, query) {
    var textWords = tokenize(text);
    var queryWords = tokenize(query);
    if (queryWords.length === 0 || queryWords.length > textWords.length) return false;
    for (var i = 0; i <= textWords.length - queryWords.length; i++) {
        var all = true;
        for (var j = 0; j < queryWords.length && all; j++)
            all = textWords[i + j].startsWith(queryWords[j]);
        if (all) return true;
    }
    return false;
}

function levenshteinDistance(s1, s2) {
    var prev = [], curr = [];
    for (var j = 0; j <= s2.length; j++) prev[j] = j;
    for (var i = 1; i <= s1.length; i++) {
        curr[0] = i;
        for (j = 1; j <= s2.length; j++) {
            var cost = s1[i - 1] === s2[j - 1] ? 0 : 1;
            curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
        }
        var tmp = prev;
        prev = curr;
        curr = tmp;
    }
    return prev[s2.length];
}

// 0..1: how close the text (or one of its words) is to the query, allowing 1 to 3 typos by query length.
function fuzzyScore(text, query) {
    var maxDistance = query.length === 3 ? 1 : query.length <= 6 ? 2 : 3;
    var best = 0;
    if (Math.abs(text.length - query.length) <= maxDistance) {
        var d = levenshteinDistance(text, query);
        if (d <= maxDistance) best = 1 - d / Math.max(text.length, query.length);
    }
    var words = tokenize(text);
    for (var i = 0; i < words.length && best < 0.8; i++) {
        if (Math.abs(words[i].length - query.length) > maxDistance) continue;
        var wd = levenshteinDistance(words[i], query);
        if (wd <= maxDistance) best = Math.max(best, 1 - wd / Math.max(words[i].length, query.length));
    }
    return best;
}

// 0..1: the query's letters appear in order in the text, the first at a word start, within three times the
// query's length ("nvi" in "neovide"); denser is closer to 1. 0 when they do not.
function subsequenceScore(text, query) {
    if (query.length < 2) return 0;
    var best = 0;
    for (var start = 0; start < text.length; start++) {
        if (text[start] !== query[0] || (start > 0 && !/[\s\-_.]/.test(text[start - 1]))) continue;
        var at = start;
        for (var i = 1; i < query.length && at >= 0; i++) at = text.indexOf(query[i], at + 1);
        if (at < 0) break;
        var span = at - start + 1;
        if (span <= 3 * query.length) best = Math.max(best, query.length / span);
    }
    return best;
}

function textScore(name, query) {
    if (name === query) return Weights.exactMatch;
    if (name.startsWith(query)) return Weights.prefixMatch;
    if (hasWordBoundaryMatch(name, query)) return Weights.wordBoundary;
    if (name.includes(query)) return Weights.substring;
    if (query.length >= 3) {
        var fs = fuzzyScore(name, query);
        if (fs > 0) return fs * Weights.fuzzy;
    }
    return 0;
}

// item: {type, id, name, subtitle, keywords: [], genericName}; usageCount: how often it was opened, weighed by
// how lately (Usage.score).
// 0 means "not a result" when there is a query.
function score(item, query, usageCount) {
    var typeBonus = Weights.typeBonus[item.type] || 0;
    var uses = usageCount || 0;
    if (!query) return typeBonus + uses * 100;
    var q = query.toLowerCase();
    var name = (item.name || "").toLowerCase();
    var s = Math.max(textScore(name, q), subsequenceScore(name, q) * Weights.subsequence);
    if (s === 0 && item.subtitle) s = textScore(item.subtitle.toLowerCase(), q) * 0.5;
    if (s === 0 && item.keywords) {
        for (var i = 0; i < item.keywords.length && s === 0; i++)
            s = textScore(item.keywords[i].toLowerCase(), q) * 0.3;
    }
    if (s === 0 && item.genericName) {
        var g = item.genericName.toLowerCase();
        s = g.startsWith(q) ? Weights.genericPrefix : g.includes(q) ? Weights.generic : 0;
    }
    if (s === 0 && item.id && item.type === "app" && item.id.toLowerCase().replace(/\.desktop$/, "").includes(q))
        s = Weights.id;
    if (s === 0) return 0;
    return s + Math.min(uses * 50, Weights.frecency) + typeBonus;
}

// The items that match, best first; ties keep their given order. Without a query: every item, by name.
function rank(items, query, usageOf) {
    var q = (query || "").trim();
    if (q === "") return items.slice().sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    var scored = [];
    for (var i = 0; i < items.length; i++) {
        var s = score(items[i], q, usageOf ? usageOf(items[i]) : 0);
        if (s > 0) scored.push({ item: items[i], score: s, order: i });
    }
    scored.sort((a, b) => (b.score - a.score) || (a.order - b.order));
    return scored.map(x => x.item);
}
