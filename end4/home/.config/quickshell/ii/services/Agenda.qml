pragma Singleton
import "../modules/ii/sidebarRight/calendar/schedule.js" as Schedule
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

Singleton {
    id: root

    property var data: Schedule.initial()
    property var history: []
    property bool ready: false
    property string error: ""
    property date now: new Date()
    readonly property string path: Directories.state + "/user/agenda.json"

    property string calendarScope: "all"
    property var calendars: []
    property var calendarEvents: []
    property string calendarError: ""
    property var pendingCalendarPayload: ({})
    property int calendarActionRevision: 0
    readonly property bool calendarBusy: calendarProcess.running
    readonly property var calendarScopes: buildCalendarScopes()

    property bool reminderSettingsReady: false
    property bool remindersEnabled: true
    property bool reminderSoundEnabled: false
    property var sentReminderIds: []
    property string reminderError: ""
    readonly property string reminderSettingsPath: Directories.state + "/user/calendar-reminders.json"

    function day(value) {
        return Schedule.mergedDay(data, value, calendarEvents, calendarScope);
    }
    function buildCalendarScopes() {
        const options = [{label: Translation.tr("Personal"), value: "personal"}];
        const seen = new Set();
        calendars.forEach(calendar => {
            const key = calendar.categoryKey || "";
            if (!key || key === "personal" || seen.has(key)) return;
            seen.add(key);
            options.push({label: calendar.category, value: "category:" + key});
        });
        options.push({label: Translation.tr("All"), value: "all"});
        return options;
    }
    function calendarsForScope(scope) {
        if (scope === "all") return calendars;
        const key = scope === "personal" ? "personal" : scope.slice("category:".length);
        return calendars.filter(calendar => calendar.categoryKey === key);
    }
    function calendarStatus(scope, value) {
        const selected = calendarsForScope(scope);
        const failures = selected.filter(calendar => calendar.error);
        if (failures.length)
            return failures.map(calendar => calendar.name + ": " + calendar.error).join("\n");
        if (selected.length && selected.every(calendar => calendar.rangeStart && calendar.rangeEnd
            && (Schedule.key(value) < calendar.rangeStart || Schedule.key(value) >= calendar.rangeEnd)))
            return Translation.tr("Calendar events are outside the synced date range");
        return "";
    }
    function saveReminderState() {
        if (!reminderSettingsReady) return false;
        reminderStorage.setText(JSON.stringify({
            version: 1,
            enabled: remindersEnabled,
            sound: reminderSoundEnabled,
            sent: sentReminderIds
        }, null, 2));
        return true;
    }
    function setRemindersEnabled(value) {
        remindersEnabled = Boolean(value);
        saveReminderState();
        if (remindersEnabled) checkUpcomingActivities();
    }
    function setReminderSoundEnabled(value) {
        reminderSoundEnabled = Boolean(value);
        saveReminderState();
    }
    function reminderId(event, startAt) {
        const value = `${event.source}:${event.id}:${startAt.getTime()}`;
        let hash = 2166136261;
        for (let index = 0; index < value.length; index++) {
            hash = Math.imul(hash ^ value.charCodeAt(index), 16777619);
        }
        return `${startAt.toISOString().slice(0, 10)}:${(hash >>> 0).toString(16)}`;
    }
    function checkUpcomingActivities() {
        if (!reminderSettingsReady || !ready || !remindersEnabled) return;

        const current = new Date(now);
        const today = new Date(current.getFullYear(), current.getMonth(), current.getDate(), 12);
        const due = [];
        const earliestLead = 4.5 * 60 * 1000;
        const latestLead = 5.5 * 60 * 1000;
        Schedule.mergedDay(data, today, calendarEvents, "all").forEach(event => {
            if (event.allDay || event.continued) return;
            const startAt = event.startAt ? new Date(event.startAt)
                : new Date(current.getFullYear(), current.getMonth(), current.getDate(),
                    Math.floor(event.originalStart / 60), event.originalStart % 60);
            if (!Number.isFinite(startAt.getTime())) return;

            const lead = startAt.getTime() - current.getTime();
            if (lead < earliestLead || lead > latestLead) return;

            const reminderId = root.reminderId(event, startAt);
            if (sentReminderIds.includes(reminderId)) return;
            due.push({event, reminderId});
        });
        if (!due.length) return;

        sentReminderIds = [...sentReminderIds, ...due.map(item => item.reminderId)].slice(-1000);
        saveReminderState();
        due.forEach(item => sendActivityReminder(item.event));
    }
    function sendActivityReminder(event) {
        const summary = Translation.tr("Plot twist in five minutes");
        const body = Translation.tr("%1 starts soon. The calendar is already in starting position.").arg(event.title);
        Quickshell.execDetached(["notify-send", "--app-name=Calendar", "--expire-time=10000", summary, body]);
        if (reminderSoundEnabled) Audio.playSystemSound("complete");
    }
    function calendarAction(action, payload = {}) {
        if (calendarProcess.running) return false;
        pendingCalendarPayload = payload;
        calendarError = "";
        calendarProcess.command = ["bash", Directories.scriptPath + "/calendar/work-calendar.sh", action];
        calendarProcess.stdinEnabled = true;
        calendarProcess.running = true;
        return true;
    }
    Component.onCompleted: calendarAction("load")
    Process {
        id: calendarProcess
        onStarted: {
            write(JSON.stringify(root.pendingCalendarPayload || {}));
            root.pendingCalendarPayload = {};
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.calendars = result.calendars || [];
                    root.calendarEvents = result.events || [];
                    root.calendarError = result.error || "";
                    if (!root.calendarScopes.some(option => option.value === root.calendarScope))
                        root.calendarScope = "all";
                } catch (exception) {
                    root.calendarError = "Could not read calendar response";
                }
                root.calendarActionRevision++;
            }
        }
        onExited: (code, status) => {
            if (code !== 0) root.calendarError = "Could not start calendar helper";
            else if (command[2] === "load" && root.calendars.length)
                Qt.callLater(() => root.calendarAction("sync"));
        }
    }
    Timer {
        interval: 15 * 60 * 1000
        running: root.calendars.length > 0
        repeat: true
        onTriggered: if (!root.calendarBusy) root.calendarAction("sync")
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
    onNowChanged: checkUpcomingActivities()
    onReadyChanged: checkUpcomingActivities()
    onCalendarEventsChanged: checkUpcomingActivities()
    onRemindersEnabledChanged: if (remindersEnabled) checkUpcomingActivities()
    onReminderSettingsReadyChanged: if (reminderSettingsReady) checkUpcomingActivities()

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

    FileView {
        id: reminderStorage
        path: root.reminderSettingsPath
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (saved.version !== 1 || typeof saved.enabled !== "boolean"
                    || typeof saved.sound !== "boolean" || !Array.isArray(saved.sent)
                    || saved.sent.some(id => typeof id !== "string"))
                    throw new Error("Invalid reminder settings format");
                root.remindersEnabled = saved.enabled;
                root.reminderSoundEnabled = saved.sound;
                root.sentReminderIds = saved.sent.slice(-1000);
                root.reminderError = "";
                root.reminderSettingsReady = true;
            } catch (error) {
                root.reminderError = Translation.tr("Could not read reminder settings");
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.reminderError = "";
                root.reminderSettingsReady = true;
            } else {
                root.reminderError = Translation.tr("Could not read reminder settings");
            }
        }
        onSaveFailed: root.reminderError = Translation.tr("Could not save reminder settings")
        onSaved: root.reminderError = ""
    }
}
