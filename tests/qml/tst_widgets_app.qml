// The Widgets app (plan 4.5, D82): the categories, the templates in each drawn live, what a card says about the web
// address it reads, and the signals its buttons send; Gallery.js's rules.
import QtQuick
import QtTest
import qs.common
import qs.widgetsapp
import "../qs/widgetsapp/Gallery.js" as Gallery

TestCase {
    id: root
    name: "WidgetsApp"
    width: 1200
    height: 900
    visible: true
    when: windowShown

    readonly property var names: ["weather", "daily-update", "world-clock", "finance", "countdown", "sports"]
    function readJson(rel) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(rel), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }
    // every template, as the window's scan and FileViews would give them
    readonly property var all: {
        const out = [];
        for (const c of names)
            for (let n = 5; n >= 1; n--)        // out of order: the app sorts them
                out.push({ path: "/t/" + c + "-" + n + ".json", name: c + " " + n });
        return out;
    }
    function specsFor(list) {
        const s = {};
        for (const e of list) s[e.path] = readJson("../data/widgets/templates/" + Gallery.baseName(e.path) + ".json");
        return s;
    }

    Component { id: comp; WidgetsApp { width: root.width; height: root.height } }
    function make(props) {
        const a = createTemporaryObject(comp, root, props);
        waitForRendering(a);
        return a;
    }

    function test_gallery_rules() {
        compare(Gallery.categories.map(c => c.id).join(), names.join() + ",yours");
        compare(Gallery.categoryOf("/x/world-clock-3.json"), "world-clock");
        compare(Gallery.categoryOf("/x/weather.json"), "", "an example is in no category");
        compare(Gallery.categoryOf("/x/hockey-1.json"), "", "nor an unknown category");
        compare(Gallery.templatesIn(all, "finance").map(e => Gallery.baseName(e.path)).join(),
                "finance-1,finance-2,finance-3,finance-4,finance-5", "in order");
        const fx = { sources: { http: { url: "https://api.frankfurter.dev/v1/latest?from=USD" } } };
        compare(Gallery.fetches(fx), "https://api.frankfurter.dev/");
        compare(Gallery.fetches({ sources: { clock: {} } }), "");
        compare(Gallery.editorCommand("", "/w/a.json").join(" "), "xdg-open /w/a.json");
        compare(Gallery.editorCommand("  kitty -e   nvim ", "/w/a b.json"), ["kitty", "-e", "nvim", "/w/a b.json"]);
        compare(Gallery.fileStem({ name: "Dollar to euro!" }, "/t/finance-1.json"), "dollar-to-euro");
        compare(Gallery.fileStem({ name: "***" }, "/t/finance-1.json"), "finance-1");
    }

    function test_each_category_draws_its_five_templates() {
        const a = make({ templates: all, specs: specsFor(all) });
        for (const c of names) {
            mouseClick(findChild(a, "galleryCategory_" + c));
            compare(a.currentCategory, c);
            compare(a.shown.length, 5, c);
            waitForRendering(a);
            for (let n = 1; n <= 5; n++) {
                const card = findChild(a, "galleryCard_" + c + "-" + n);
                verify(card, c + "-" + n + " has a card");
                verify(card.host.readable, c + "-" + n + " is drawn");
                compare(card.host.problems.length, 0, c + "-" + n + ": " + JSON.stringify(card.host.problems));
                verify(card.host.implicitHeight > 0);
                verify(card.x + card.width <= a.width, c + "-" + n + " fits across");
            }
        }
    }

    function test_cards_share_the_width() {
        const a = make({ templates: all, specs: specsFor(all) });
        const card = n => findChild(a, "galleryCard_weather-" + n);
        verify(card(2).y === card(1).y, "wide: cards side by side");
        verify(card(1).width >= 320);
        a.width = 640;                       // narrower than a 320 card beside the categories
        waitForRendering(a);
        verify(card(1).mapToItem(a, 0, 0).x + card(1).width <= a.width, "narrow: the card shrinks to fit");
        verify(card(2).y > card(1).y, "one card per row then");
    }

    function test_a_card_names_the_address_it_reads() {
        const fin = all.filter(e => e.path.indexOf("finance-1") >= 0);
        const a = make({ templates: fin, specs: specsFor(fin) });
        a.openCategory("finance");
        waitForRendering(a);
        const note = findChild(findChild(a, "galleryCard_finance-1"), "galleryFetches");
        verify(note.visible);
        verify(note.text.indexOf("https://api.frankfurter.dev/") > 0 && note.text.indexOf("using it allows") > 0, note.text);
        a.allow = ["https://api.frankfurter.dev/"];
        compare(note.text, "Reads https://api.frankfurter.dev/", "allowed: no more to say");
        const weather = all.filter(e => e.path.indexOf("weather-1") >= 0);
        const b = make({ templates: weather, specs: specsFor(weather) });
        waitForRendering(b);
        verify(!findChild(findChild(b, "galleryCard_weather-1"), "galleryFetches").visible, "no web address: no note");
    }

    function test_buttons() {
        const mine = [{ path: "/home/me/.config/rutile/widgets/mine.json", name: "Mine" }];
        const specs = specsFor(all.filter(e => e.path.indexOf("countdown-1") >= 0));
        specs[mine[0].path] = { version: 1, name: "Mine", root: { type: "chip", label: "{{clock.time}}" } };
        const a = make({ templates: all.filter(e => e.path.indexOf("countdown-1") >= 0), mine: mine, specs: specs });
        const used = signalSpy.createObject(root, { target: a, signalName: "useRequested" });
        const edited = signalSpy.createObject(root, { target: a, signalName: "editRequested" });
        const placed = signalSpy.createObject(root, { target: a, signalName: "placeRequested" });
        a.openCategory("countdown");
        waitForRendering(a);
        const card = findChild(a, "galleryCard_countdown-1");
        verify(!findChild(card, "galleryEdit").visible, "a template is used, not edited");
        mouseClick(findChild(card, "galleryUse"));
        compare(used.signalArguments[0][0], "/t/countdown-1.json");
        verify(!findChild(a, "galleryFolder").visible);
        mouseClick(findChild(a, "galleryCategory_yours"));
        waitForRendering(a);
        verify(findChild(a, "galleryFolder").visible);
        const own = findChild(a, "galleryCard_mine");
        verify(!findChild(own, "galleryUse").visible);
        mouseClick(findChild(own, "galleryEdit"));
        compare(edited.signalArguments[0][0], mine[0].path);
        mouseClick(findChild(own, "galleryPlace"));
        compare(placed.signalArguments[0][0], mine[0].path);
        a.mine = [];
        verify(findChild(a, "galleryEmpty").visible, "no widgets yet: it says how to get one");
        verify(!a.openCategory("nope"));
        compare(a.currentCategory, "yours");
    }

    Component { id: signalSpy; SignalSpy {} }
}
