// Our app windows' frame (plan 3.1, D88), offscreen against a stand-in window: pressing the title bar asks the
// compositor to move it, a double click, the middle button and the maximize button flip `maximized`, close asks
// the window, and each edge and corner asks for its own resize, none while maximized.
import QtQuick
import QtTest
import qs.common
import qs.components

TestCase {
    id: root
    name: "AppFrame"
    width: 800
    height: 600
    visible: true
    when: windowShown

    // what AppFrame uses of a FloatingWindow
    Component {
        id: windowComp
        QtObject {
            property string title: "Settings"
            property bool maximized: false
            property int moves: 0
            property var resizes: []
            function startSystemMove() { moves++; return true; }
            function startSystemResize(edges) { resizes = resizes.concat([edges]); return true; }
        }
    }
    Component {
        id: frameComp
        AppFrame {
            width: 600
            height: 400
            iconName: "settings"
            Rectangle { objectName: "frameBody"; anchors.fill: parent; color: "transparent" }
        }
    }
    SignalSpy { id: closeSpy; signalName: "closeRequested" }

    function make() {
        const w = createTemporaryObject(windowComp, root);
        const f = createTemporaryObject(frameComp, root, { window: w });
        closeSpy.target = f;
        closeSpy.clear();
        return { w: w, f: f };
    }

    function test_title_from_the_window() {
        const o = make();
        compare(findChild(o.f, "titleBarTitle").text, "Settings");
        o.w.title = "Widgets";
        compare(findChild(o.f, "titleBarTitle").text, "Widgets");
    }

    function test_content_goes_under_the_title_bar() {
        const o = make();
        const body = findChild(o.f, "frameBody");
        const at = body.mapToItem(o.f, 0, 0);
        compare(at.y, o.f.titleBar.height);
        compare(body.height, o.f.height - o.f.titleBar.height);
        compare(body.width, o.f.width);
    }

    function test_press_on_the_title_bar_moves() {
        const o = make();
        mousePress(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2);
        mouseRelease(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2);
        compare(o.w.moves, 1);
        mousePress(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2, Qt.MiddleButton);
        mouseRelease(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2, Qt.MiddleButton);
        compare(o.w.moves, 1, "the middle button does not move");
    }

    function test_maximize_and_restore() {
        const o = make();
        const button = findChild(o.f, "titleBarMaximize");
        compare(button.iconName, "crop_square");
        mouseClick(button);
        verify(o.w.maximized);
        verify(o.f.maximized);
        compare(button.iconName, "filter_none");
        mouseDoubleClickSequence(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2);
        verify(!o.w.maximized, "a double click restores");
        mouseClick(o.f.titleBar, o.f.titleBar.width / 2, o.f.titleBar.height / 2, Qt.MiddleButton);
        verify(o.w.maximized, "the middle button maximizes");
    }

    function test_close_asks_the_window() {
        const o = make();
        mouseClick(findChild(o.f, "titleBarClose"));
        compare(closeSpy.count, 1);
    }

    function test_edges_resize() {
        const o = make();
        const e = o.f.edge;
        const W = o.f.width, H = o.f.height;
        const points = [
            [W / 2, 1, Qt.TopEdge], [W / 2, H - 1, Qt.BottomEdge], [1, H / 2, Qt.LeftEdge], [W - 1, H / 2, Qt.RightEdge],
            [1, 1, Qt.TopEdge | Qt.LeftEdge], [W - 1, H - 1, Qt.BottomEdge | Qt.RightEdge],
            [W - 1, 1, Qt.TopEdge | Qt.RightEdge], [1, H - 1, Qt.BottomEdge | Qt.LeftEdge],
            [e + 2, 1, Qt.TopEdge | Qt.LeftEdge]          // a corner reaches twice as far along the side
        ];
        for (const p of points) {
            mousePress(o.f, p[0], p[1]);
            mouseRelease(o.f, p[0], p[1]);
        }
        compare(o.w.resizes, points.map(p => p[2]));
        compare(o.w.moves, 0, "an edge on the title bar resizes, not moves");
        mousePress(o.f, W / 2, H / 2);
        mouseRelease(o.f, W / 2, H / 2);
        compare(o.w.resizes.length, points.length, "the middle is not an edge");
    }

    function test_no_edges_while_maximized() {
        const o = make();
        o.w.maximized = true;
        verify(!findChild(o.f, "resizeEdge_" + Qt.LeftEdge).visible);
        mousePress(o.f, 1, o.f.height / 2);
        mouseRelease(o.f, 1, o.f.height / 2);
        compare(o.w.resizes.length, 0);
        o.f.resize(Qt.LeftEdge);
        compare(o.w.resizes.length, 0, "nor asked for");
    }
}
