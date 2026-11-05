// Screenshots and recording (D120): the commands and paths (Capture.js), the capture bar, the recording pill.
import QtQuick
import QtTest
import qs.common
import qs.capture
import qs.bar
import "../qs/capture/Capture.js" as Capture

TestCase {
    id: root
    name: "Capture"
    width: 700
    height: 200
    visible: true
    when: windowShown

    Component { id: barComp; CaptureBar {} }
    Component { id: pillComp; RecordPill {} }
    Component { id: spyComp; SignalSpy {} }

    function test_paths_and_commands() {
        const at = new Date(2026, 10, 5, 9, 4, 3);
        compare(Capture.stamp(at), "2026-11-05 09-04-03");
        compare(Capture.screenshotPath({ home: "/home/u", pictures: "" }, at),
                "/home/u/Pictures/Screenshots/Screenshot from 2026-11-05 09-04-03.png");
        compare(Capture.screenshotPath({ home: "/home/u", pictures: "/data/Bilder" }, at),
                "/data/Bilder/Screenshots/Screenshot from 2026-11-05 09-04-03.png", "XDG_PICTURES_DIR first");
        compare(Capture.recordingPath({ home: "/home/u", videos: "" }, at),
                "/home/u/Videos/Screencasts/Screencast from 2026-11-05 09-04-03.mp4");
        compare(Capture.niriCommand("region").join(" "), "niri msg action screenshot");
        compare(Capture.niriCommand("window").join(" "), "niri msg action screenshot-window");
        compare(Capture.niriCommand("screen").join(" "), "niri msg action screenshot-screen");
        compare(Capture.niriCommand("nope"), null);
        const grim = Capture.grimCommand("screen", "DP-1", "/p/a b.png");
        compare(grim.slice(0, 2).join(" "), "sh -c");
        compare(grim.slice(3).join("|"), "sh|/p/a b.png|screen|DP-1", "the path and output as arguments");
        compare(Capture.grimCommand("window", "DP-1", "/p"), null, "no window without niri");
        const rec = Capture.recordCommand("region", "DP-1", "/v/x.mp4", true);
        compare(rec.slice(3).join("|"), "sh|/v/x.mp4|region|DP-1|1");
        compare(Capture.recordCommand("screen", "DP-1", "/v/x.mp4", false)[7], "0", "no microphone");
        compare(Capture.recordCommand("window", "DP-1", "/v", false), null, "a window cannot be recorded");
        compare(Capture.elapsed(0), "0:00");
        compare(Capture.elapsed(75.6), "1:15");
        compare(Capture.elapsed(3725), "1:02:05");
        compare(Capture.elapsed(-3), "0:00");
        compare(Capture.fileName("/a/b/Screenshot from x.png"), "Screenshot from x.png");
    }

    function test_bar() {
        const bar = createTemporaryObject(barComp, root, { windows: true });
        waitForRendering(bar);
        const asked = createTemporaryObject(spyComp, root, { target: bar, signalName: "captureRequested" });
        verify(findChild(bar, "captureWindow").visible, "a window, on niri");
        verify(!findChild(bar, "captureAudio").visible, "no microphone for a screenshot");
        mouseClick(findChild(bar, "captureWindow"));
        compare(Array.from(asked.signalArguments[0]).join(), "screenshot,window,false");
        mouseClick(findChild(bar, "captureModeRecord"));
        verify(bar.record);
        verify(findChild(bar, "captureModeRecord").checked && !findChild(bar, "captureModeScreenshot").checked);
        verify(!findChild(bar, "captureWindow").visible, "a window cannot be recorded");
        const mic = findChild(bar, "captureAudio");
        verify(mic.visible);
        waitForItemPolished(mic.parent);
        mouseClick(mic);
        verify(bar.audio);
        compare(mic.iconName, "mic");
        mouseClick(findChild(bar, "captureRegion"));
        compare(Array.from(asked.signalArguments[1]).join(), "record,region,true");
        mouseClick(findChild(bar, "captureModeScreenshot"));
        waitForItemPolished(mic.parent);
        mouseClick(findChild(bar, "captureScreen"));
        compare(Array.from(asked.signalArguments[2]).join(), "screenshot,screen,false", "the microphone only for a recording");
        bar.windows = false;
        verify(!findChild(bar, "captureWindow").visible, "no window without niri");
        const closed = createTemporaryObject(spyComp, root, { target: bar, signalName: "closeRequested" });
        bar.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        mouseClick(findChild(bar, "captureClose"));
        compare(closed.count, 2);
    }

    function test_record_pill() {
        const pill = createTemporaryObject(pillComp, root, { recording: false });
        verify(!pill.visible);
        compare(pill.implicitWidth, 0, "no room taken");
        pill.since = Date.now() - 65000;
        pill.recording = true;
        verify(pill.visible);
        tryCompare(findChild(pill, "recordTime"), "text", "1:05", 2000);
        const stop = createTemporaryObject(spyComp, root, { target: pill, signalName: "clicked" });
        waitForRendering(pill);
        mouseClick(pill);
        compare(stop.count, 1, "a click stops it");
    }
}
