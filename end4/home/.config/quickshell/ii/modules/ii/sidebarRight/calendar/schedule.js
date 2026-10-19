.pragma library

function key(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
}
function date(key) {
    const parts = key.split("-").map(Number);
    return new Date(parts[0], parts[1] - 1, parts[2], 12);
}
function addDays(value, days) {
    const result = new Date(value);
    result.setDate(result.getDate() + days);
    return result;
}
function week(value) {
    const monday = addDays(value, -(value.getDay() + 6) % 7);
    return Array.from({length: 7}, (_, i) => addDays(monday, i));
}
function minutes(text) {
    if (!/^\d{2}:\d{2}$/.test(text)) return -1;
    const parts = text.split(":").map(Number);
    return parts[0] < 24 && parts[1] < 60 ? parts[0] * 60 + parts[1] : -1;
}
function time(value) {
    value = (value % 1440 + 1440) % 1440;
    return String(Math.floor(value / 60)).padStart(2, "0") + ":" + String(value % 60).padStart(2, "0");
}
function preset(translate) {
    const tr = translate || (value => value);
    return [
        {id: "exercise", title: tr("Exercise"), days: [0,1,2,3,4,5,6], start: 540, end: 570, color: "#aac66e"},
        {id: "breakfast", title: tr("Breakfast"), days: [0,1,2,3,4,5,6], start: 570, end: 600, color: "#88cbbb"},
        {id: "work-am", title: tr("Work"), days: [1,2,3,4,5], start: 630, end: 840, color: "#64bfd2"},
        {id: "lunch", title: tr("Lunch"), days: [0,1,2,3,4,5,6], start: 840, end: 870, color: "#88cbbb"},
        {id: "work-pm", title: tr("Work"), days: [1,2,3,4,5], start: 900, end: 1050, color: "#64bfd2"},
        {id: "drawing-tu", title: tr("Drawing"), days: [2], start: 1080, end: 1170, color: "#db948e"},
        {id: "english", title: tr("English"), days: [1,5], start: 1230, end: 1290, color: "#dfbd79"},
        {id: "dinner", title: tr("Dinner"), days: [0,1,2,3,4,5,6], start: 1290, end: 1320, color: "#88cbbb"}
    ];
}
function initial() {
    return {version: 1, presetEnabled: false, routines: [], events: [], exceptions: {}};
}
function valid(data) {
    const colorValid = color => color === undefined || (typeof color === "string" && /^#[0-9a-fA-F]{6}$/.test(color));
    const itemValid = item => item && typeof item.id === "string" && typeof item.title === "string"
        && Number.isInteger(item.start) && Number.isInteger(item.end) && item.start >= 0
        && item.start < 1440 && item.end > item.start && item.end <= item.start + 1440 && colorValid(item.color) && (item.description === undefined || typeof item.description === "string");
    return data && data.version === 1 && typeof data.presetEnabled === "boolean"
        && Array.isArray(data.routines) && data.routines.every(r => itemValid(r) && (!r.startsOn || (/^\d{4}-\d{2}-\d{2}$/.test(r.startsOn) && key(date(r.startsOn)) === r.startsOn)) && Array.isArray(r.days) && r.days.every(d => Number.isInteger(d) && d >= 0 && d <= 6))
        && Array.isArray(data.events) && data.events.every(e => itemValid(e) && /^\d{4}-\d{2}-\d{2}$/.test(e.date) && key(date(e.date)) === e.date)
        && data.exceptions && typeof data.exceptions === "object" && !Array.isArray(data.exceptions)
        && Object.values(data.exceptions).every(e => e && colorValid(e.color) && (e.description === undefined || typeof e.description === "string") && (e.skipped === true || (Number.isInteger(e.start) && Number.isInteger(e.end) && e.start >= 0 && e.start < 1440 && e.end > e.start && e.end <= e.start + 1440)));
}
function importPreset(data, preset) {
    if (!preset || preset.format !== "ii-agenda-preset" || preset.version !== 1
        || typeof preset.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(preset.id)
        || !Array.isArray(preset.routines) || preset.routines.length === 0)
        throw new Error("Invalid preset format or empty activity list");

    const ids = new Set();
    const routines = preset.routines.map(item => {
        if (!item || typeof item.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(item.id)
            || ids.has(item.id) || typeof item.title !== "string" || !item.title.trim()
            || !Array.isArray(item.days) || item.days.length === 0
            || item.days.some(day => !Number.isInteger(day) || day < 0 || day > 6)
            || new Set(item.days).size !== item.days.length)
            throw new Error("Check activity ID, title, and weekdays");
        ids.add(item.id);
        const start = minutes(item.start), finish = minutes(item.end);
        if (start < 0 || finish < 0 || start === finish)
            throw new Error("Time must be HH:MM; start and end must differ");
        if (item.color !== undefined && (typeof item.color !== "string" || !/^#[0-9a-fA-F]{6}$/.test(item.color)))
            throw new Error("Color must be #RRGGBB");
        if (item.startsOn !== undefined && (typeof item.startsOn !== "string"
            || !/^\d{4}-\d{2}-\d{2}$/.test(item.startsOn) || key(date(item.startsOn)) !== item.startsOn))
            throw new Error("Start date must be YYYY-MM-DD");
        if (item.description !== undefined && typeof item.description !== "string")
            throw new Error("Description must be text");
        const routine = {
            description: (item.description || "").trim(),
            id: "preset/" + preset.id + "/" + item.id,
            title: item.title.trim(),
            days: item.days.slice(),
            start,
            end: finish > start ? finish : finish + 1440,
            color: item.color || "#c9aceb"
        };
        if (item.startsOn !== undefined) routine.startsOn = item.startsOn;
        return routine;
    });
    const prefix = "preset/" + preset.id + "/";
    const next = JSON.parse(JSON.stringify(data));
    next.routines = next.routines.filter(item => !item.id.startsWith(prefix)).concat(routines);
    next.presetEnabled = true;
    if (!valid(next)) throw new Error("Preset does not match the schedule format");
    return next;
}
function occurrences(data, value) {
    const result = [];
    // Include the tail of yesterday's overnight events.
    for (let offset = -1; offset <= 0; offset++) {
        const origin = addDays(value, offset), day = key(origin);
        const routines = data.presetEnabled ? data.routines.filter(r => r.days.includes(origin.getDay()) && (!r.startsOn || day >= r.startsOn)) : [];
        const entries = routines.map(r => Object.assign({}, r, {source: "routine"}))
            .concat(data.events.filter(e => e.date === day).map(e => Object.assign({}, e, {source: "local"})));
        entries.forEach(entry => {
            const occurrenceId = entry.id + "@" + day;
            const exception = data.exceptions[occurrenceId];
            if (exception && exception.skipped) return;
            const event = Object.assign({}, entry, exception || {});
            const start = event.start + offset * 1440, end = event.end + offset * 1440;
            if (end <= 0 || start >= 1440) return;
            result.push(Object.assign({}, event, {links: activityLinks(event), occurrenceId, originDate: day, originalStart: event.start, originalEnd: event.end,
                start: Math.max(0, start), end: Math.min(1440, end), continued: offset === -1}));
        });
    }
    return layout(result);
}

function layout(result) {
    result.sort((a,b) => a.start - b.start || a.end - b.end);
    // Assign lanes per connected overlap group, so actual collisions remain readable.
    let group = [], groupEnd = -1;
    function finish() {
        const ends = [];
        group.forEach(event => {
            let lane = ends.findIndex(end => end <= event.start);
            if (lane === -1) lane = ends.length;
            ends[lane] = event.end;
            event.lane = lane;
        });
        group.forEach(event => { event.lanes = ends.length; event.conflict = ends.length > 1; });
    }
    result.forEach(event => {
        if (event.start >= groupEnd) { finish(); group = []; groupEnd = -1; }
        group.push(event); groupEnd = Math.max(groupEnd, event.end);
    });
    finish();
    return result;
}


function mergedDay(data, value, work, scope) {
    const personal = scope === "work" ? [] : occurrences(data, value);
    if (scope === "personal") return personal;
    const begin = new Date(value.getFullYear(), value.getMonth(), value.getDate());
    const finish = addDays(begin, 1);
    const external = work.filter(event => new Date(event.startAt) < finish && new Date(event.endAt) > begin).map(event => {
        const start = new Date(event.startAt), end = new Date(event.endAt);
        return Object.assign({}, event, {source: "work", color: "#64bfd2", readOnly: true,
            occurrenceId: event.id + "@" + key(value),
            start: start < begin ? 0 : start.getHours() * 60 + start.getMinutes(),
            end: end >= finish ? 1440 : end.getHours() * 60 + end.getMinutes()});
    });
    return layout(personal.concat(external));
}

function compactDescription(event) {
        return (event?.description || "").replace(/\r\n?/g, "\n").replace(/[ \t]+\n/g, "\n")
            .replace(/\n[ \t]*\n(?:[ \t]*\n)+/g, "\n\n").trim();
    }
function eventDate(event, selectedDate, uiLocale, allDayLabel) {
        if (!event) return "";
        const value = event.startAt ? new Date(event.startAt) : selectedDate;
        const date = value.toLocaleDateString(uiLocale, "ddd, d MMM");
        if (event.allDay) return date + " · " + allDayLabel;
        const start = event.startAt ? new Date(event.startAt) : null;
        const end = event.endAt ? new Date(event.endAt) : null;
        return date + " · " + (start ? start.toLocaleTimeString(uiLocale, "HH:mm") : time(event.start))
            + "–" + (end ? (key(start) !== key(end) ? end.toLocaleDateString(uiLocale, "d MMM") + " " : "")
                        + end.toLocaleTimeString(uiLocale, "HH:mm") : time(event.end));
    }
function isMeetingLink(url) {
        return /^https?:\/\/([^/]*\.)?(ktalk\.ru|teams\.microsoft\.com|teams\.live\.com|meet\.google\.com|zoom\.us)([/:]|$)/i.test(url);
    }
function linkCaption(url, joinLabel) {
        return isMeetingLink(url) ? joinLabel : url.replace(/^https?:\/\//i, "").split("/")[0];
    }


function windowSizes(value) {
    const defaults = {dayWidth: 560, weekWidth: 1040, height: 880};
    value = value || {};
    Object.keys(defaults).forEach(name => {
        if (Number.isFinite(value[name])) defaults[name] = Math.max(defaults[name], Math.round(value[name]));
    });
    return defaults;
}
function windowSize(value, weekly, screenWidth, screenHeight) {
    const sizes = windowSizes(value);
    const maxWidth = Math.max(1, screenWidth - 40), maxHeight = Math.max(1, screenHeight - 40);
    return {width: Math.min(weekly ? sizes.weekWidth : sizes.dayWidth, maxWidth),
            height: Math.min(sizes.height, maxHeight),
            minWidth: Math.min(weekly ? 1040 : 560, maxWidth), minHeight: Math.min(880, maxHeight)};
}


function escapeHtml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function descriptionHtml(event, joinLabel) {
    const description = compactDescription(event);
    const links = activityLinks(event);
    const parts = description.split(/(https?:\/\/[^\s<>"']+)/g);
    const body = parts.map((part, index) => {
        if (index % 2 === 0) return escapeHtml(part);
        const decoded = part.replace(/&amp;/g, "&");
        const link = links.slice().sort((a, b) => b.length - a.length).find(url => decoded === url
            || (decoded.startsWith(url) && /^[).,;!\]]+$/.test(decoded.slice(url.length))));
        return link ? '<a href="' + escapeHtml(link) + '">' + escapeHtml(linkCaption(link, joinLabel)) + '</a>'
                    + escapeHtml(decoded.slice(link.length)) : escapeHtml(part);
    }).join("");
    return body ? '<p style="margin-top:0; margin-bottom:12px">'
        + body.replace(/\n\n/g, '</p><p style="margin-top:0; margin-bottom:12px">').replace(/\n/g, '<br>') + '</p>' : "";
}
function extraLinksHtml(event, joinLabel) {
    const description = compactDescription(event).replace(/&amp;/g, "&");
    return activityLinks(event).filter(url => !description.includes(url) && !isMeetingLink(url))
        .map(url => '<a href="' + escapeHtml(url) + '">' + escapeHtml(linkCaption(url, joinLabel)) + '</a>').join('<br>');
}


function resizedWindow(value, weekly, width, height, screenWidth, screenHeight) {
    const limits = windowSize(value, weekly, screenWidth, screenHeight);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width < limits.minWidth || height < limits.minHeight) return null;
    const next = windowSizes(value);
    // A smaller monitor must not overwrite a larger saved preference for a clipped axis.
    if (width >= (weekly ? 1040 : 560)) next[weekly ? "weekWidth" : "dayWidth"] = Math.round(width);
    if (height >= 880) next.height = Math.round(height);
    return next;
}


function activityLinks(event) {
    const existing = (event?.links || []).slice();
    const found = (event?.description || "").match(/https?:\/\/[^\s<>"']+/g) || [];
    found.forEach(value => {
        let url = value.replace(/&amp;/g, "&").replace(/[.,;!]+$/, "");
        while (url.endsWith(")") && url.split(")").length > url.split("(").length) url = url.slice(0, -1);
        while (url.endsWith("]") && url.split("]").length > url.split("[").length) url = url.slice(0, -1);
        if (!existing.includes(url)) existing.push(url);
    });
    return existing.filter(url => typeof url === "string" && /^https?:\/\//i.test(url));
}


function overlapGroups(events, enabled) {
    const groups = [];
    events.slice().sort((a, b) => a.start - b.start || a.end - b.end).forEach(event => {
        const previous = groups[groups.length - 1];
        if (enabled && previous && event.start < previous.end) {
            previous.events.push(event);
            previous.end = Math.max(previous.end, event.end);
            previous.overlapping = true;
        } else {
            groups.push({start: event.start, end: event.end, events: [event], overlapping: false});
        }
    });
    return groups;
}
