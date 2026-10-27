pragma Singleton
// Toasts (plan 2.8): short messages from the shell, one at a time, in the order they came. show() queues one
// ({id, text, icon, action: {text, run}} with `run` a function, called when the action is clicked) and returns
// its id; the same text as the one showing does not queue again but shows it longer (`repeats` counts up). The
// window (ToastWindow) shows `current` and calls done() once it has closed; then the next one comes.
import QtQuick
import Quickshell

Singleton {
    id: root

    property var current: null
    property var queue: []
    property int repeats: 0              // the current one was shown again
    property int lastId: 0

    function show(text, opts) {
        const o = opts || {};
        if (current && current.text === text && !o.action) {
            repeats++;
            return current.id;
        }
        const toast = { id: ++lastId, text: String(text), icon: o.icon || "", action: o.action || null };
        if (current) queue = queue.concat([toast]);
        else current = toast;
        return toast.id;
    }

    // Its action was clicked.
    function invoke(id) {
        if (current?.id === id && current.action?.run) current.action.run();
    }

    // It has closed: the next one, if any.
    function done(id) {
        if (current?.id !== id) return;
        repeats = 0;
        current = queue.length > 0 ? queue[0] : null;
        queue = queue.slice(1);
    }
}
