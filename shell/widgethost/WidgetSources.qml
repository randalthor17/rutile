// A widget's data (plan 4.2, D79): one object of sources/ for each source the widget binds (WidgetSpec.sourcesUsed),
// with the widget's options for it (`sources` in the spec) and the fields it reads; `values` holds them by name, as
// WidgetHost reads them. A source nothing binds is never created (D31), and goes when the widget does.
pragma ComponentBehavior: Bound
import QtQuick
import "WidgetSpec.js" as Spec

Item {
    id: root

    property var spec: null
    readonly property var used: Spec.sourcesUsed(spec)
    readonly property var names: Object.keys(used).sort()
    property var values: ({})
    // what a source said went wrong (no place for the weather, an address not allowed), by name
    property var errors: ({})

    function put(name, value, error) {
        const v = Object.assign({}, values);
        v[name] = value;
        values = v;
        const e = Object.assign({}, errors);
        if (error) e[name] = error;
        else delete e[name];
        errors = e;
    }
    onNamesChanged: {
        const v = {};
        for (const n of names) if (n in values) v[n] = values[n];
        values = v;
    }

    Repeater {
        model: root.names
        delegate: Loader {
            id: slot
            required property string modelData
            readonly property WidgetSource shown: item as WidgetSource
            source: Qt.resolvedUrl(Spec.sourceFile(modelData))
            onLoaded: root.put(slot.modelData, slot.shown.value, slot.shown.error)
            Binding {
                target: slot.shown
                property: "options"
                value: root.spec?.sources?.[slot.modelData] ?? {}
                when: slot.shown !== null
            }
            Binding {
                target: slot.shown
                property: "fields"
                value: root.used[slot.modelData] ?? []
                when: slot.shown !== null
            }
            Connections {
                target: slot.shown
                function onValueChanged() { root.put(slot.modelData, slot.shown.value, slot.shown.error); }
                function onErrorChanged() { root.put(slot.modelData, slot.shown.value, slot.shown.error); }
            }
        }
    }
}
