// niri's workspaces and windows from its IPC event stream (`niri msg --json event-stream`; niri 26.04's format),
// as plain data so it is tested offscreen. NiriService.qml feeds each event line to apply(); the shelf asks
// groups() for one output. Follows the events Noctalia's niri backend handles (MIT, noctalia-dev).
.pragma library

function empty() {
    return { workspaces: {}, windows: {}, focusedWindowId: null };
}

function windowFrom(w, old) {
    var pos = w.layout && w.layout.pos_in_scrolling_layout;
    return {
        id: w.id,
        appId: w.app_id !== undefined ? (w.app_id || "") : (old ? old.appId : ""),
        title: w.title !== undefined ? (w.title || "") : (old ? old.title : ""),
        pid: w.pid !== undefined ? w.pid : (old ? old.pid : null),
        // null while a window is being moved: keep the last workspace
        workspaceId: w.workspace_id !== undefined && w.workspace_id !== null ? w.workspace_id : (old ? old.workspaceId : null),
        floating: w.is_floating !== undefined ? !!w.is_floating : (old ? old.floating : false),
        column: pos ? pos[0] : (old ? old.column : 0),
        row: pos ? pos[1] : (old ? old.row : 0)
    };
}

// The state after one event ({"Name": payload}); unknown events leave it as it was. Returns a new object when
// something changed, so a QML binding on it updates.
function apply(state, event) {
    var name = Object.keys(event)[0];
    var v = event[name];
    var next = { workspaces: state.workspaces, windows: state.windows, focusedWindowId: state.focusedWindowId };
    switch (name) {
    case "WorkspacesChanged":
        next.workspaces = {};
        v.workspaces.forEach(w => next.workspaces[w.id] = {
            id: w.id, idx: w.idx, name: w.name || "", output: w.output || "", active: !!w.is_active, focused: !!w.is_focused
        });
        return next;
    case "WorkspaceActivated": {
        var output = state.workspaces[v.id] ? state.workspaces[v.id].output : null;
        next.workspaces = {};
        for (var k in state.workspaces) {
            var w = Object.assign({}, state.workspaces[k]);
            if (w.output === output) w.active = w.id === v.id;
            if (v.focused) w.focused = w.id === v.id;
            next.workspaces[k] = w;
        }
        return next;
    }
    case "WindowsChanged":
        next.windows = {};
        next.focusedWindowId = null;
        v.windows.forEach(w => {
            next.windows[w.id] = windowFrom(w, null);
            if (w.is_focused) next.focusedWindowId = w.id;
        });
        return next;
    case "WindowOpenedOrChanged":
        next.windows = Object.assign({}, state.windows);
        next.windows[v.window.id] = windowFrom(v.window, state.windows[v.window.id]);
        if (v.window.is_focused) next.focusedWindowId = v.window.id;
        else if (state.focusedWindowId === v.window.id && v.window.is_focused === false) next.focusedWindowId = null;
        return next;
    case "WindowClosed":
        if (!(v.id in state.windows)) return state;
        next.windows = Object.assign({}, state.windows);
        delete next.windows[v.id];
        if (state.focusedWindowId === v.id) next.focusedWindowId = null;
        return next;
    case "WindowFocusChanged":
        next.focusedWindowId = v.id === undefined ? null : v.id;
        return next;
    case "WindowLayoutsChanged":
        next.windows = Object.assign({}, state.windows);
        v.changes.forEach(c => {
            var old = next.windows[c[0]];
            if (old) next.windows[c[0]] = windowFrom({ id: c[0], layout: c[1] }, old);
        });
        return next;
    }
    return state;
}

// The output of the focused workspace (where the keyboard is), or "" before niri has said.
function focusedOutput(state) {
    for (var k in state.workspaces)
        if (state.workspaces[k].focused) return state.workspaces[k].output;
    return "";
}

// One output's workspaces that have windows, and the active one even when empty (niri's blank workspace past the
// last, reached by scrolling), by index, each with its windows in layout order (columns left to right, top to
// bottom within a column, floating windows last):
// [{id, idx, name, active, windows: [{id, appId, title, focused}]}]. output "" means every output.
function groups(state, output) {
    var out = [];
    for (var k in state.workspaces) {
        var ws = state.workspaces[k];
        if (output && ws.output !== output) continue;
        var wins = [];
        for (var j in state.windows) {
            var w = state.windows[j];
            if (w.workspaceId === ws.id) wins.push(w);
        }
        if (wins.length === 0 && !ws.active) continue;
        wins.sort((a, b) => (a.floating - b.floating) || (a.column - b.column) || (a.row - b.row) || (a.id - b.id));
        out.push({ id: ws.id, idx: ws.idx, name: ws.name, active: ws.active,
                   windows: wins.map(w => ({ id: w.id, appId: w.appId, title: w.title,
                                            focused: w.id === state.focusedWindowId })) });
    }
    return out.sort((a, b) => a.idx - b.idx);
}

// The workspace `delta` places from the active one on `output`, in index order and counting empty ones, without
// going past the first or last; null when that is the active one (or the output has none).
function neighbourWorkspace(state, output, delta) {
    var list = [];
    for (var k in state.workspaces)
        if (state.workspaces[k].output === output) list.push(state.workspaces[k]);
    list.sort((a, b) => a.idx - b.idx);
    var at = list.findIndex(w => w.active);
    if (at < 0) return null;
    var to = Math.max(0, Math.min(list.length - 1, at + delta));
    return to === at ? null : list[to].id;
}

// The desktop shown on every output (D86; niri has no minimize): each output's last empty workspace, the focused
// output's last so the keyboard stays there. {focus: [workspace ids, in order], back: {output: the workspace it showed}};
// an output already on an empty workspace, or with none, is left alone.
function showDesktop(state) {
    var outputs = {};
    for (var k in state.workspaces) {
        var ws = state.workspaces[k];
        (outputs[ws.output] = outputs[ws.output] || []).push(ws);
    }
    var used = {};
    for (var id in state.windows) {
        var wid = state.windows[id].workspaceId;
        if (wid !== null && wid !== undefined) used[wid] = true;
    }
    var focus = [], back = {}, last = null;
    for (var output in outputs) {
        var list = outputs[output].sort((a, b) => a.idx - b.idx);
        var active = list.find(w => w.active);
        if (!active || !used[active.id]) continue;
        var blank = list.filter(w => !used[w.id]).pop();
        if (!blank) continue;
        back[output] = active.id;
        if (active.focused) last = blank.id;
        else focus.push(blank.id);
    }
    if (last !== null) focus.push(last);
    return { focus: focus, back: back };
}

// Back from showDesktop: each output that still shows the workspace it was moved to goes back to the one it showed,
// the focused output last. Ids of workspaces to focus, in order.
function hideDesktop(state, plan, moved) {
    var focus = [], last = null;
    for (var output in plan.back) {
        var now = null, focused = false;
        for (var k in state.workspaces) {
            var ws = state.workspaces[k];
            if (ws.output === output && ws.active) { now = ws.id; focused = ws.focused; }
        }
        if (now === null || moved.indexOf(now) < 0 || !state.workspaces[plan.back[output]]) continue;
        if (focused) last = plan.back[output];
        else focus.push(plan.back[output]);
    }
    if (last !== null) focus.push(last);
    return focus;
}

// The request line for focusing a workspace by id (niri's Action::FocusWorkspace).
function focusWorkspaceRequest(id) {
    return JSON.stringify({ Action: { FocusWorkspace: { reference: { Id: id } } } });
}

// The request line for focusing a window (niri's Action::FocusWindow).
function focusWindowRequest(id) {
    return JSON.stringify({ Action: { FocusWindow: { id: id } } });
}

// The id of a window of process `pid` titled `title` (the shell's own Settings window), or null.
function findWindow(state, pid, title) {
    for (var id in state.windows) {
        var w = state.windows[id];
        if (w.pid === pid && w.title === title) return w.id;
    }
    return null;
}

// The request line for closing a window (niri's Action::CloseWindow).
function closeWindowRequest(id) {
    return JSON.stringify({ Action: { CloseWindow: { id: id } } });
}
