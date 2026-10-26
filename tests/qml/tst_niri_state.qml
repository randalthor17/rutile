import QtQuick
import QtTest
import "../qs/services/NiriState.js" as Niri

TestCase {
    name: "NiriState"

    // Shaped like niri 26.04's event stream.
    function ws(id, idx, output, active) {
        return { id: id, idx: idx, name: null, output: output, is_urgent: false, is_active: active, is_focused: active,
                 active_window_id: null };
    }
    function win(id, appId, wsId, col, row, focused, floating) {
        return { id: id, title: appId + " " + id, app_id: appId, pid: 1, workspace_id: wsId, is_focused: !!focused,
                 is_floating: !!floating, is_urgent: false,
                 layout: { pos_in_scrolling_layout: floating ? null : [col, row], tile_size: [1, 1] } };
    }
    function start() {
        var s = Niri.empty();
        s = Niri.apply(s, { WorkspacesChanged: { workspaces: [ws(1, 1, "DP-1", true), ws(2, 2, "DP-1", false),
                                                              ws(3, 3, "DP-1", false), ws(4, 1, "HDMI-A-1", true)] } });
        s = Niri.apply(s, { WindowsChanged: { windows: [win(10, "kitty", 1, 2, 1, true), win(11, "firefox", 1, 1, 1),
                                                         win(12, "kitty", 2, 1, 1), win(13, "mpv", 1, 0, 0, false, true),
                                                         win(14, "kitty", 1, 2, 2), win(15, "foot", 4, 1, 1)] } });
        return s;
    }
    function ids(group) { return group.windows.map(w => w.id).join(); }

    function test_groups_by_workspace_in_layout_order() {
        var g = Niri.groups(start(), "DP-1");
        compare(g.map(x => x.idx).join(), "1,2", "workspaces with windows, by index; the empty one is left out");
        compare(ids(g[0]), "11,10,14,13", "columns left to right, rows top to bottom, floating last");
        verify(g[0].active && !g[1].active);
        compare(g[0].windows.map(w => w.focused).join(), "false,true,false,false");
        compare(g[0].windows[0].appId, "firefox");
        compare(Niri.groups(start(), "HDMI-A-1").map(x => ids(x)).join("|"), "15", "only that output");
        compare(Niri.groups(start(), "").length, 3, "every output");
        compare(Niri.groups(Niri.empty(), "DP-1").length, 0);
    }

    function test_window_events() {
        var s = start();
        s = Niri.apply(s, { WindowOpenedOrChanged: { window: win(16, "gimp", 2, 0, 1, true) } });
        compare(ids(Niri.groups(s, "DP-1")[1]), "16,12", "opened, in its column");
        compare(s.focusedWindowId, 16, "and focused");
        var before = s;
        s = Niri.apply(s, { WindowOpenedOrChanged: { window: { id: 12, title: "renamed", workspace_id: null } } });
        compare(s.windows[12].workspaceId, 2, "a null workspace (being moved) keeps the last one");
        compare(s.windows[12].appId, "kitty", "fields it does not send stay");
        compare(s.windows[12].title, "renamed");
        verify(before.windows[12].title !== "renamed", "the old state is not changed in place");
        s = Niri.apply(s, { WindowOpenedOrChanged: { window: win(12, "kitty", 1, 3, 1, false) } });
        compare(ids(Niri.groups(s, "DP-1")[0]), "11,10,14,12,13", "moved to workspace 1, last column");
        s = Niri.apply(s, { WindowClosed: { id: 16 } });
        verify(!(16 in s.windows));
        compare(s.focusedWindowId, null, "the focused window closed");
        compare(Niri.groups(s, "DP-1").map(x => x.idx).join(), "1", "workspace 2 is empty now");
        compare(Niri.apply(s, { WindowClosed: { id: 99 } }), s, "an unknown window: unchanged");
        s = Niri.apply(s, { WindowFocusChanged: { id: 11 } });
        compare(s.focusedWindowId, 11);
        s = Niri.apply(s, { WindowFocusChanged: { id: null } });
        compare(s.focusedWindowId, null);
        s = Niri.apply(s, { WindowLayoutsChanged: { changes: [[11, { pos_in_scrolling_layout: [9, 1] }]] } });
        compare(ids(Niri.groups(s, "DP-1")[0]), "10,14,12,11,13", "a layout change moves it");
    }

    function test_workspace_events() {
        var s = Niri.apply(start(), { WorkspaceActivated: { id: 2, focused: true } });
        var g = Niri.groups(s, "DP-1");
        verify(!g[0].active && g[1].active, "workspace 2 active on DP-1");
        verify(Niri.groups(s, "HDMI-A-1")[0].active, "the other output keeps its active workspace");
        verify(s.workspaces[2].focused && !s.workspaces[4].focused);
        var same = start();
        compare(Niri.apply(same, { KeyboardLayoutsChanged: { keyboard_layouts: {} } }), same, "other events: unchanged");
    }

    function test_focus_requests() {
        compare(Niri.focusWindowRequest(12), '{"Action":{"FocusWindow":{"id":12}}}');
        compare(Niri.focusWorkspaceRequest(6), '{"Action":{"FocusWorkspace":{"reference":{"Id":6}}}}',
                "the shape niri 26.04 accepted");
    }

    function test_the_active_blank_workspace_shows() {
        var s = Niri.apply(start(), { WorkspaceActivated: { id: 3, focused: true } });
        var g = Niri.groups(s, "DP-1");
        compare(g.map(x => x.idx).join(), "1,2,3", "scrolled past the last: niri's blank workspace shows");
        compare(g[2].windows.length, 0);
        verify(g[2].active);
        s = Niri.apply(s, { WorkspaceActivated: { id: 1, focused: true } });
        compare(Niri.groups(s, "DP-1").map(x => x.idx).join(), "1,2", "and goes when left");
    }

    function test_neighbour_workspace() {
        var s = start();        // DP-1: 1 (active, windows), 2 (windows), 3 (empty)
        compare(Niri.neighbourWorkspace(s, "DP-1", 1), 2, "down one");
        compare(Niri.neighbourWorkspace(s, "DP-1", 2), 3, "down to the empty one");
        compare(Niri.neighbourWorkspace(s, "DP-1", 9), 3, "not past the last");
        compare(Niri.neighbourWorkspace(s, "DP-1", -1), null, "already the first");
        s = Niri.apply(s, { WorkspaceActivated: { id: 3, focused: true } });
        compare(Niri.neighbourWorkspace(s, "DP-1", -1), 2, "up one");
        compare(Niri.neighbourWorkspace(s, "DP-1", 1), null, "already the last");
        compare(Niri.neighbourWorkspace(s, "HDMI-A-1", 1), null, "one workspace there");
        compare(Niri.neighbourWorkspace(s, "nope", 1), null, "unknown output");
    }

    function test_focused_output() {
        compare(Niri.focusedOutput(Niri.empty()), "", "nothing yet");
        let s = Niri.apply(Niri.empty(), { WorkspacesChanged: { workspaces: [ws(1, 1, "DP-1", true), ws(2, 1, "HDMI-A-1", true)] } });
        s.workspaces[2].focused = false;
        compare(Niri.focusedOutput(s), "DP-1");
        s.workspaces[1].focused = false;
        s.workspaces[2].focused = true;
        compare(Niri.focusedOutput(s), "HDMI-A-1");
    }
}
