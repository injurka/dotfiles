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

    function day(value) {
        return Schedule.occurrences(data, value);
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
        next.routines = next.routines.concat(Schedule.preset().filter(r => !existing.has(r.id)));
        next.presetEnabled = true;
        save(next);
    }
    function importPreset(text) {
        if (!ready || error.length > 0)
            return "Хранилище календаря недоступно";
        try {
            const next = Schedule.importPreset(data, JSON.parse(text));
            return save(next) ? "" : "Не удалось сохранить пресет";
        } catch (exception) {
            return "Не удалось загрузить пресет: " + exception.message;
        }
    }
    function togglePreset() {
        const next = JSON.parse(JSON.stringify(data));
        next.presetEnabled = !next.presetEnabled;
        save(next);
    }

    function skip(event) {
        const next = JSON.parse(JSON.stringify(data));
        next.exceptions[event.occurrenceId] = {
            "skipped": true
        };
        save(next);
    }

    function move(event, delta) {
        const next = JSON.parse(JSON.stringify(data));
        const start = event.originalStart + delta, end = event.originalEnd + delta;
        if (start < 0 || start >= 1440)
            return;

        next.exceptions[event.occurrenceId] = {
            "start": start,
            "end": end
        };
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

    function store(value, title, from, to, days, editing, wholeSeries) {
        const start = Schedule.minutes(from), finish = Schedule.minutes(to);
        if (!title.trim() || start < 0 || finish < 0 || start === finish)
            return false;

        const end = finish > start ? finish : finish + 1440;
        const next = JSON.parse(JSON.stringify(data));
        if (editing) {
            if (editing.source === "routine" && !wholeSeries) {
                next.exceptions[editing.occurrenceId] = {
                    "title": title.trim(),
                    "start": start,
                    "end": end
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
                                  "end": end
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
                "color": "#c9aceb"
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
        if (event.source === "routine" && !wholeSeries) {
            skip(event);
            return;
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
        save(next);
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
                    throw new Error("Неверный формат расписания");

                root.data = parsed;
                root.error = "";
                root.ready = true;
            } catch (error) {
                root.error = "Не удалось прочитать расписание. Файл сохранён без изменений: " + error.message;
                root.ready = false;
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.ready = true;
                root.error = "";
            } else {
                root.ready = false;
                root.error = "Не удалось открыть файл расписания";
            }
        }
        onSaveFailed: error => {
            root.error = "Не удалось сохранить расписание: " + error;
            root.ready = false;
        }
    }
}
