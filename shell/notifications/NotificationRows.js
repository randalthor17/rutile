// Keeps a ListModel of {key} rows in the order of `keys` with the fewest changes (remove, move, insert), so a
// ListView animates what changed instead of rebuilding every card (a JS array model resets the view on each
// change). `model` needs count, get(i), remove(i), move(from, to, n) and insert(i, row): a ListModel, or a fake.
.pragma library

function sync(model, keys) {
    var want = {};
    for (var k = 0; k < keys.length; k++) want[keys[k]] = true;
    for (var i = model.count - 1; i >= 0; i--)
        if (!want[model.get(i).key]) model.remove(i);
    for (var at = 0; at < keys.length; at++) {
        if (at < model.count && model.get(at).key === keys[at]) continue;
        var from = -1;
        for (var j = at + 1; j < model.count; j++)
            if (model.get(j).key === keys[at]) { from = j; break; }
        if (from >= 0) model.move(from, at, 1);
        else model.insert(at, { key: keys[at] });
    }
}
