// Clipboard history (D119): cliphist's list read (Clipboard.js) and the picker: search, keys, delete, clear.
import QtQuick
import QtTest
import qs.common
import qs.clipboard
import "../qs/clipboard/Clipboard.js" as Clipboard

TestCase {
    id: root
    name: "Clipboard"
    width: 600
    height: 700
    visible: true
    when: windowShown

    // as cliphist 0.7 lists them (newest first; a tab in the text shows as a space)
    readonly property string listed: "7\tgit push origin main\n6\t[[ binary data 128 B png 10x20 ]]\n" +
                                     "5\tsecond line\nnot an entry\n4\thttps://example.org/a b\n"

    Component { id: panelComp; ClipboardPanel {} }
    Component { id: spyComp; SignalSpy {} }

    function test_parse_and_filter() {
        const e = Clipboard.parse(listed);
        compare(e.map(x => x.id).join(), "7,6,5,4", "lines that are no entry left out");
        compare(e[0].line, "7\tgit push origin main", "the line, as cliphist decode and delete take it back");
        compare(e[0].text, "git push origin main");
        verify(!e[0].image);
        verify(e[1].image);
        compare(e[1].text, "PNG image, 10 × 20, 128 B");
        compare(Clipboard.imageLabel("[[ binary data 3 KiB jpeg ]]"), "JPEG image, 3 KiB");
        compare(Clipboard.imageLabel("[[ binary data ]]"), "Image");
        compare(Clipboard.parse("").length, 0);
        compare(Clipboard.filter(e, "").length, 4);
        compare(Clipboard.filter(e, "ORIGIN git").map(x => x.id).join(), "7", "every word, in any case");
        compare(Clipboard.filter(e, "png").map(x => x.id).join(), "6", "images by their kind");
        compare(Clipboard.filter(e, "nothing").length, 0);
        const copy = Clipboard.copyCommand("7\tgit push; rm -rf /");
        compare(copy.slice(0, 2).join(" "), "sh -c");
        compare(copy[4], "7\tgit push; rm -rf /", "the line as an argument, never in the script");
        compare(Clipboard.deleteCommand("4\tx")[4], "4\tx");
    }

    function test_picker() {
        const p = createTemporaryObject(panelComp, root, { entries: Clipboard.parse(listed) });
        waitForRendering(p);
        const chosen = createTemporaryObject(spyComp, root, { target: p, signalName: "chosen" });
        const removed = createTemporaryObject(spyComp, root, { target: p, signalName: "removed" });
        const closed = createTemporaryObject(spyComp, root, { target: p, signalName: "closeRequested" });
        verify(!findChild(p, "clipboardEmpty").visible);
        compare(p.listView.currentIndex, 0, "the newest marked");
        verify(findChild(p, "clipboardSearch").activeFocus, "typing goes to the search");
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(p.listView.currentIndex, 2);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Return);
        compare(chosen.count, 1);
        compare(chosen.signalArguments[0][0].id, "6", "Enter copies the current one");
        keyClick(Qt.Key_Delete);
        compare(removed.signalArguments[0][0].id, "6", "Delete in an empty field forgets it");
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_I);
        compare(p.results.map(e => e.id).join(), "7", "typing searches");
        compare(p.listView.currentIndex, 0, "the mark stays on a result");
        keyClick(Qt.Key_Delete);
        compare(removed.count, 1, "with text, Delete edits the text");
        keyClick(Qt.Key_Escape);
        compare(closed.count, 1);
        p.query = "zzz";
        verify(findChild(p, "clipboardEmpty").visible);
        compare(findChild(p, "clipboardEmpty").text, "Nothing matches");
        keyClick(Qt.Key_Return);
        compare(chosen.count, 1, "nothing to copy");
        p.query = "";
        waitForRendering(p);
        const row = findChild(p, "clipboardEntry_3");
        mouseClick(row, Spacing.xl, row.height / 2);
        compare(chosen.signalArguments[1][0].id, "4", "a click copies too");
        mouseClick(findChild(p, "clipboardDelete_0"));
        compare(removed.signalArguments[1][0].id, "7", "its row's button forgets it");
        const wipe = createTemporaryObject(spyComp, root, { target: p, signalName: "wipeRequested" });
        mouseClick(findChild(p, "clipboardClear"));
        compare(wipe.count, 1);
        p.entries = [];
        compare(findChild(p, "clipboardEmpty").text, "Nothing copied yet");
        verify(!findChild(p, "clipboardClear").visible, "nothing to clear");
    }
}
