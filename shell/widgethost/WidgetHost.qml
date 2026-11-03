// A widget drawn from its spec (plan 4.3, D78): `spec` is a widget (widgets/spec.schema.json), `values` the data
// sources' values that its bindings read ({source: {field: value}}; plan 4.2 fills them). The width is the
// host's (the desktop grid's cell, a preview); the height follows the content. `problems` lists what was left out
// (WidgetSpec.problems): a widget of another version draws nothing. Plain QtQuick, so it tests offscreen.
import QtQuick
import "WidgetSpec.js" as Spec

Item {
    id: root

    property var spec: null
    property var values: ({})
    readonly property var problems: Spec.problems(spec)
    readonly property bool readable: !!spec && spec.version === Spec.VERSION
    readonly property var bindings: readable ? collect(spec.root) : []

    // every source.field the widget reads, once each (what 4.2 must provide)
    function collect(node) {
        const out = [];
        const add = t => Spec.bindingsOf(typeof t === "string" ? t : "").forEach(b => { if (out.indexOf(b) < 0) out.push(b); });
        const walk = n => {
            if (!n || typeof n !== "object") return;
            ["title", "subtitle", "label", "value", "source"].forEach(k => add(n[k]));
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
        node: root.readable ? root.spec.root : null
        values: root.values
    }
}
