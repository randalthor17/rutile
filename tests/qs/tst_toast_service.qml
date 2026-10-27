// ToastService (plan 2.8): one toast at a time, in the order they came; the same text again shows the current one
// longer instead of queueing; an action runs its function; done() brings the next.
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    QsTest { id: t }

    Component.onCompleted: {
        const S = ToastService;
        t.compare(S.current, null, "none at first");
        const a = S.show("Saved");
        t.compare(S.current.text, "Saved", "the first shows");
        t.compare(S.current.icon, "", "no icon");
        t.compare(S.show("Saved"), a, "the same text: the same toast");
        t.compare(S.repeats, 1, "shown again");
        t.compare(S.queue.length, 0, "not queued");
        let ran = 0;
        const b = S.show("Unpinned", { icon: "keep", action: { text: "Undo", run: () => ran++ } });
        t.verify(b !== a, "a new id");
        S.show("Unpinned", { action: { text: "Undo", run: () => ran++ } });
        t.compare(S.queue.map(q => q.text).join(), "Unpinned,Unpinned", "queued in order; with an action, again");
        S.invoke(b);
        t.compare(ran, 0, "only the current one's action runs");
        S.done(b);
        t.compare(S.current.id, a, "done() for another one changes nothing");
        S.done(a);
        t.compare(S.current.id, b, "the next");
        t.compare(S.current.icon, "keep", "with its icon");
        t.compare(S.repeats, 0, "repeats start again");
        S.invoke(b);
        t.compare(ran, 1, "its action ran");
        const c = S.queue[0].id;
        S.invoke(c);
        t.compare(ran, 1, "a queued one's id runs nothing, not even the current one's action");
        S.done(b);
        S.done(S.current.id);
        t.compare(S.current, null, "all done");
        t.compare(S.queue.length, 0, "nothing queued");
        t.done();
    }
}
