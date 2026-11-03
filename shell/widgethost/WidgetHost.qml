// A widget drawn from its spec (plan 4.3, D78): `spec` is a widget (widgets/spec.schema.json), `values` the data
// sources' values that its bindings read (by source, then field; WidgetSources fills them). The width is the
// host's (the desktop grid's cell, a preview); the height follows the content, or is the host's when that is set
// taller (the desktop grid, D83): the widget's blocks then stretch to fill it. `problems` lists what was left out
// (WidgetSpec.problems): a widget of another version draws nothing. Plain QtQuick, so it tests offscreen.
import QtQuick
import "WidgetSpec.js" as Spec

Item {
    id: root

    property var spec: null
    property var values: ({})
    property real textScale: 1                 // text and icons, e.g. 1.5 (a big desktop widget, D84)
    readonly property var problems: Spec.problems(spec)
    readonly property bool readable: !!spec && spec.version === Spec.VERSION
    readonly property var bindings: readable ? collect(spec.root) : []
    readonly property bool stretches: readable && Spec.stretches(spec.root)
    // a card or tile at the root (alone in a column or row too) brings its own surface and padding; anything else
    // is bare text
    readonly property bool bare: !readable || !Spec.surfaced(spec.root)

    // every source.field the widget reads, once each (what 4.2 must provide)
    function collect(node) {
        const out = [];
        const add = t => Spec.bindingsOf(typeof t === "string" ? t : "").forEach(b => { if (out.indexOf(b) < 0) out.push(b); });
        const walk = n => {
            if (!n || typeof n !== "object") return;
            Spec.textsOf(n).forEach(t => add(t[1]));
            (Spec.list(n.children) ?? []).forEach(walk);
        };
        walk(node);
        return out;
    }

    implicitWidth: 320
    implicitHeight: content.implicitHeight

    WidgetNode {
        id: content
        objectName: "widgetRoot"
        width: root.width
        height: Math.max(implicitHeight, root.height)
        node: root.readable ? root.spec.root : null
        values: root.values
        textScale: root.textScale
    }
}
