// What every widget data source in sources/ is (plan 4.2, D79): the widget's `options` for it (its sources.<name>)
// and the `fields` it binds go in; its `value` (by field, widgets/sources.json) and an `error` (why it has
// none: no place for the weather, an address not allowed) come out. Invisible: it draws nothing.
import QtQuick

Item {
    property var options: ({})
    property var fields: []
    property var value: ({})
    property string error: ""
}
