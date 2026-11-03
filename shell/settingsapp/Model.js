// What the settings app shows, worked out from the registry (Pages.js) and the schema; no QML, so it tests alone.
.pragma library
.import "../services/SettingsStore.js" as Store

// How a setting is shown: switch, slider, choice (a menu), path, list, color (swatches), or text. A row can also be
// an action (a button, no setting): its hint has `kind: "action"` and the title and description the schema would;
// or a notice (no setting, no control), shown only while the app's `conditions[when]` is true.
function kind(leaf, hint) {
    hint = hint ?? {};
    if (hint.kind) return hint.kind;
    if (hint.choices || leaf.enum) return "choice";
    if (leaf.type === "boolean") return "switch";
    if ((leaf.type === "number" || leaf.type === "integer") && leaf.minimum !== undefined && leaf.maximum !== undefined)
        return "slider";
    if (leaf.type === "array") return "list";
    return "text";
}

// The rows of a page, section by section: [{title, rows: [{key, kind, title, description, advanced, ...}]}].
// Advanced settings move to a last "Advanced" section; keys the schema does not have are skipped.
function sections(page, schema, hints) {
    const leaves = Store.leaves(schema);
    const out = [];
    const advanced = [];
    for (const s of page?.sections ?? []) {
        const rows = [];
        for (const key of s.keys) {
            const hint = hints[key] ?? {};
            const leaf = hint.kind === "action" || hint.kind === "notice" ? hint : leaves[key];
            if (!leaf) continue;
            const row = {
                key: key,
                kind: kind(leaf, hint),
                title: leaf.title ?? key,
                description: leaf.description ?? "",
                advanced: !!hint.advanced,
                minimum: leaf.minimum,
                maximum: leaf.maximum,
                step: hint.step ?? (leaf.type === "integer" ? 1 : 0),
                choices: hint.choices ?? leaf.enum ?? [],
                filters: hint.filters ?? [],
                swatches: hint.swatches ?? [],
                button: hint.button ?? "",
                when: hint.when ?? "",
                requires: hint.requires ?? ""
            };
            (row.advanced ? advanced : rows).push(row);
        }
        if (rows.length) out.push({ title: s.title, rows: rows });
    }
    if (advanced.length) out.push({ title: "Advanced", rows: advanced, advanced: true });
    return out;
}

// A value as the app shows it.
function valueText(key, value, hints) {
    const hint = hints[key] ?? {};
    if (value === undefined || value === null || value === "") return hint.kind === "path" ? "None" : "Not set";
    if (hint.label) return hint.label(value);
    if (Array.isArray(value)) return value.length === 0 ? "None" : value.join(", ");
    if (typeof value === "boolean") return value ? "On" : "Off";
    return String(value);
}

function words(s) {
    return String(s ?? "").toLowerCase().split(/[^0-9a-z\u00c0-\uffff]+/).filter(w => w !== "");
}
// How well `text` matches every word of the query: 3 when it starts with the query, 2 when each query word starts
// one of its words, 1 when each is somewhere in it, 0 otherwise.
function score(text, query) {
    const t = String(text ?? "").toLowerCase();
    const q = query.toLowerCase().trim();
    if (q === "" || t === "") return 0;
    if (t.startsWith(q)) return 3;
    const qw = words(q);
    if (qw.length === 0) return 0;
    const tw = words(t);
    if (qw.every(w => tw.some(x => x.startsWith(w)))) return 2;
    if (qw.every(w => t.includes(w))) return 1;
    return 0;
}

// Search over pages and settings: titles count most, then aliases, then descriptions and summaries.
// [{page, key ("" for a page), title, detail, score}], best first, then in registry order.
function search(query, pages, schema, hints) {
    const leaves = Store.leaves(schema);
    const hits = [];
    let order = 0;
    for (const p of pages) {
        const ps = Math.max(score(p.title, query) * 10,
                            ...(p.aliases ?? []).map(a => score(a, query) * 6), score(p.summary, query) * 2);
        if (ps > 0) hits.push({ page: p.id, key: "", title: p.title, detail: p.summary, score: ps, order: order++ });
        for (const s of p.sections ?? []) {
            for (const key of s.keys) {
                const hint = hints[key] ?? {};
                const leaf = hint.kind === "action" ? hint : leaves[key];
                if (!leaf) continue;
                const ks = Math.max(score(leaf.title, query) * 10,
                                    ...(hint.aliases ?? []).map(a => score(a, query) * 6),
                                    score(s.title, query) * 4, score(leaf.description, query) * 2);
                if (ks > 0) hits.push({ page: p.id, key: key, title: leaf.title ?? key, detail: p.title, score: ks,
                                        order: order++ });
            }
        }
        for (const e of p.entries ?? []) {
            const es = Math.max(score(e.title, query) * 10, ...(e.aliases ?? []).map(a => score(a, query) * 6),
                                score(e.description, query) * 2);
            if (es > 0) hits.push({ page: p.id, key: e.key, title: e.title, detail: p.title, score: es, order: order++ });
        }
    }
    hits.sort((a, b) => b.score - a.score || a.order - b.order);
    return hits;
}

// The settings app's search as the launcher's results (type "setting", as Quick Settings' controls): the best
// `max` hits of search(), each with the page's icon as its symbol and where it is as its subtitle. Choosing one
// opens Settings on that page and rings the setting (`page`, `key`). `keywords` hold what search() matched besides
// the title, so the launcher's own ranking (Scorer.js) keeps them, worth less there than an app's own words.
function launcherItems(query, pages, schema, hints, max) {
    if (String(query ?? "").trim() === "") return [];
    const leaves = Store.leaves(schema);
    const byId = {};
    for (const p of pages) byId[p.id] = p;
    return search(query, pages, schema, hints).slice(0, max).map(h => {
        const p = byId[h.page];
        const entry = (p.entries ?? []).find(e => e.key === h.key);
        const hint = hints[h.key] ?? {};
        const leaf = entry ?? (hint.kind === "action" ? hint : leaves[h.key]) ?? {};
        const section = (p.sections ?? []).find(s => s.keys.indexOf(h.key) >= 0);
        const keywords = h.key === "" ? [].concat(p.aliases ?? [], [p.summary ?? ""])
                                      : [].concat(entry?.aliases ?? hint.aliases ?? [], [section?.title ?? "", leaf.description ?? ""]);
        return { type: "setting", id: "settings:" + h.page + (h.key ? "/" + h.key : ""), page: h.page, key: h.key,
                 name: h.title, subtitle: h.key === "" ? "Settings" : "Settings · " + p.title,
                 keywords: keywords.filter(k => k !== ""), keywordWeight: 0.1, symbol: p.icon };
    });
}
