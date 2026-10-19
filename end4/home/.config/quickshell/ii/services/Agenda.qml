pragma Singleton
import "../modules/ii/sidebarRight/calendar/schedule.js" as Schedule
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var data: Schedule.initial()
    property var history: []
    property bool ready: false
    property string error: ""
    property date now: new Date()
    readonly property string path: Directories.state + "/user/agenda.json"

    property string calendarScope: "all"
    property var workEvents: []
    property bool workConfigured: false
    property string workError: ""
    property string workUpdatedAt: ""
    property string workRangeStart: ""
    property string workRangeEnd: ""
    property string pendingWorkUrl: ""
    readonly property bool workBusy: workProcess.running

    function day(value) {
        return Schedule.mergedDay(data, value, workEvents, calendarScope);
    }
    function workAction(action, url = "") {
        if (workProcess.running) return;
        pendingWorkUrl = url;
        workProcess.command = ["bash", Directories.scriptPath + "/calendar/work-calendar.sh", action];
        workProcess.stdinEnabled = action === "connect";
        workProcess.running = true;
    }
    Component.onCompleted: workAction("load")
    Process {
        id: workProcess
        onStarted: {
            if (root.pendingWorkUrl) {
                write(JSON.stringify({url: root.pendingWorkUrl}));
                root.pendingWorkUrl = "";
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.workEvents = result.events || [];
                    root.workConfigured = result.configured;
                    root.workError = result.error || "";
                    root.workUpdatedAt = result.updatedAt || "";
                    root.workRangeStart = result.rangeStart || "";
                    root.workRangeEnd = result.rangeEnd || "";
                } catch (exception) {
                    root.workError = "Could not read work calendar response";
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) root.workError = "Could not start work calendar helper";
            else if (command[2] === "load" && root.workConfigured)
                Qt.callLater(() => root.workAction("sync"));
        }
    }
    Timer {
        interval: 15 * 60 * 1000
        running: root.workConfigured
        repeat: true
        onTriggered: if (!root.workBusy) root.workAction("sync")
    }

    function save(next, remember = true) {
        if (!ready || error.length > 0)
            return false;

        if (!Schedule.valid(next)) {
            console.warn("[Agenda] Invalid change");
            return false;
        }
        if (remember)
            history = history.concat([JSON.parse(JSON.stringify(data))]).slice(-20);
        data = next;
        storage.setText(JSON.stringify(next, null, 2));
        return true;
    }

    function clearAll() {
        if (!save(Schedule.initial(), false))
            return false;
        history = [];
        return true;
    }

    function undo() {
        if (!history.length || !ready)
            return;
        const previous = history[history.length - 1];
        if (save(previous, false))
            history = history.slice(0, -1);
    }
    function loadExample() {
        const next = JSON.parse(JSON.stringify(data));
        const existing = new Set(next.routines.map(r => r.id));
        next.routines = next.routines.concat(Schedule.preset(text => Translation.tr(text)).filter(r => !existing.has(r.id)));
        next.presetEnabled = true;
        return save(next);
    }
    function importPreset(text) {
        if (!ready || error.length > 0)
            return Translation.tr("Calendar storage is unavailable");
        try {
            const next = Schedule.importPreset(data, JSON.parse(text));
            return save(next) ? "" : Translation.tr("Could not save preset");
        } catch (exception) {
            return Translation.tr("Could not load preset: %1").arg(Translation.tr(exception.message));
        }
    }
    function togglePreset() {
        const next = JSON.parse(JSON.stringify(data));
        next.presetEnabled = !next.presetEnabled;
        save(next);
    }

    function skip(event) {
        if (event.readOnly) return false;
        const next = JSON.parse(JSON.stringify(data));
        next.exceptions[event.occurrenceId] = {
            "skipped": true
        };
        return save(next);
    }

    function move(event, delta) {
        if (event.readOnly) return false;
        const next = JSON.parse(JSON.stringify(data));
        const start = event.originalStart + delta, end = event.originalEnd + delta;
        if (start < 0 || start >= 1440)
            return;

        next.exceptions[event.occurrenceId] = Object.assign({}, next.exceptions[event.occurrenceId] || {}, {
            "start": start,
            "end": end
        });
        save(next);
    }

    function restore(value) {
        const next = JSON.parse(JSON.stringify(data));
        const suffix = "@" + Schedule.key(value);
        Object.keys(next.exceptions).forEach(id => {
            if (id.endsWith(suffix))
                delete next.exceptions[id];
        });
        save(next);
    }

    function store(value, title, from, to, days, editing, wholeSeries, color, description = "") {
        if (editing?.readOnly || typeof description !== "string") return false;
        description = description.trim();
        const start = Schedule.minutes(from), finish = Schedule.minutes(to);
        if (!title.trim() || start < 0 || finish < 0 || start === finish || !/^#[0-9a-fA-F]{6}$/.test(color))
            return false;

        const end = finish > start ? finish : finish + 1440;
        color = color.toLowerCase();
        const next = JSON.parse(JSON.stringify(data));
        if (editing) {
            if (editing.source === "routine" && !wholeSeries) {
                next.exceptions[editing.occurrenceId] = {
                    "title": title.trim(),
                    "start": start,
                    "end": end,
                    "description": description,
                    "color": color
                };
            } else {
                const collection = editing.source === "routine" ? next.routines : next.events;
                const index = collection.findIndex(e => {
                    return e.id === editing.id;
                });
                if (index < 0)
                    return false;

                Object.assign(collection[index], {
                                  "title": title.trim(),
                                  "start": start,
                                  "end": end,
                                  "description": description,
                    "color": color
                              });
                if (editing.source === "routine") {
                    if (!days.length)
                        return false;

                    collection[index].days = days;
                }
            }
        } else {
            const entry = {
                "id": "local-" + Date.now() + "-" + Math.random().toString(36).slice(2),
                "title": title.trim(),
                "start": start,
                "end": end,
                "description": description,
                    "color": color
            };
            if (days.length) {
                next.routines.push(Object.assign(entry, {
                                                     "days": days,
                                                     "startsOn": Schedule.key(value)
                                                 }));
                next.presetEnabled = true;
            } else {
                next.events.push(Object.assign(entry, {
                                                   "date": Schedule.key(value)
                                               }));
            }
        }
        return save(next);
    }

    function remove(event, wholeSeries) {
        if (event.readOnly) return false;
        if (event.source === "routine" && !wholeSeries) {
            return skip(event);
        }
        const next = JSON.parse(JSON.stringify(data));
        const collection = event.source === "routine" ? "routines" : "events";
        next[collection] = next[collection].filter(e => {
            return e.id !== event.id;
        });
        Object.keys(next.exceptions).forEach(id => {
            if (id.startsWith(event.id + "@"))
                delete next.exceptions[id];
        });
        return save(next);
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    FileView {
        id: storage

        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (!Schedule.valid(parsed))
                    throw new Error(Translation.tr("Invalid schedule format"));

                root.data = parsed;
                root.error = "";
                root.ready = true;
            } catch (error) {
                root.error = Translation.tr("Could not read schedule. File was left unchanged: %1").arg(error.message);
                root.ready = false;
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.ready = true;
                root.error = "";
            } else {
                root.ready = false;
                root.error = Translation.tr("Could not open schedule file");
            }
        }
        onSaveFailed: error => {
            root.error = Translation.tr("Could not save schedule: %1").arg(error);
            root.ready = false;
        }
    }
}
