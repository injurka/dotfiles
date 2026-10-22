pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "schedule.js" as Schedule

FloatingWindow {
    id: root
    property bool opened: false
    property date selectedDate: new Date()
    property bool weekMode: false
    property string page: "overview"
    property bool confirmingClear: false
    property bool advancedSettingsOpen: false
    property date previewDate: new Date()
    property bool replacingWorkLink: false
    property var viewingEvent: null
    property var editingEvent: null
    property var repeatDays: [1, 2, 3, 4, 5]
    property bool repeating: false
    property bool wholeSeries: false
    property bool altPressed: false
    property string formError: ""
    readonly property var activityColors: ["#c9aceb", "#aac66e", "#88cbbb", "#64bfd2", "#dfbd79", "#db948e", "#e7a0c3"]
    property string presetStatus: ""
    property bool presetSucceeded: false
    property string presetFilePath: ""
    property string exportFilePath: ""
    property string exportPayload: ""
    property string exportStatus: ""
    property bool exportSucceeded: false
    property bool exportWritePending: false
    readonly property var days: Schedule.week(selectedDate)
    readonly property var events: Agenda.day(selectedDate)
    readonly property var dailyGroups: Schedule.overlapGroups(events, Agenda.calendarScope === "all")
    readonly property bool todaySelected: !weekMode && Schedule.key(selectedDate) === Schedule.key(Agenda.now)
    readonly property int weekEventCount: days.reduce((count, day) => count + Agenda.day(day).length, 0)
    property real hourHeight: 64
    readonly property var uiLocale: Qt.locale(Translation.languageCode === "he_HE" ? "he_IL" : Translation.languageCode)
    property var windowSizes: Schedule.windowSizes(null)
    property bool sizeStorageReady: false
    property string sizeError: ""
    readonly property bool wideWindow: page === "overview" && weekMode
    readonly property var windowSize: Schedule.windowSize(windowSizes, wideWindow, screen?.width || 1280, screen?.height || 1080)
    title: "Calendar — end4"
    minimumSize: Qt.size(windowSize.minWidth, windowSize.minHeight)
    maximumSize: Qt.size(Math.max(1, (screen?.width || 1280) - 40), Math.max(1, (screen?.height || 1080) - 40))
    onClosed: {
        captureWindowSize();
        opened = false;
    }
    onWidthChanged: if (visible && sizeStorageReady && !applyingWindowSize) sizeSaveTimer.restart()
    onHeightChanged: if (visible && sizeStorageReady && !applyingWindowSize) sizeSaveTimer.restart()
    onWideWindowChanged: applyWindowSize()
    property bool applyingWindowSize: false
    visible: opened
    implicitWidth: windowSize.width
    implicitHeight: windowSize.height
    color: Appearance.m3colors.m3surfaceContainer

    function applyWindowSize() {
        applyingWindowSize = true;
        sizeSaveTimer.stop();
        Qt.callLater(() => {
            root.width = root.windowSize.width;
            root.height = root.windowSize.height;
            root.applyingWindowSize = false;
        });
    }
    function captureWindowSize() {
        if (!sizeStorageReady || applyingWindowSize || maximized || fullscreen || minimized) return;
        const next = Schedule.resizedWindow(windowSizes, wideWindow, width, height, screen?.width || 1280, screen?.height || 1080);
        if (!next) return;
        windowSizes = next;
        rememberWindowSize();
    }
    Timer {
        id: sizeSaveTimer
        interval: 400
        onTriggered: root.captureWindowSize()
    }
    function rememberWindowSize() {
        if (sizeStorageReady) windowSizeStorage.setText(JSON.stringify(windowSizes));
    }
    function resetWindowSize() {
        windowSizes = Schedule.windowSizes(null);
        applyWindowSize();
        rememberWindowSize();
    }
    FileView {
        id: windowSizeStorage
        path: Directories.state + "/user/calendar-window.json"
        onLoaded: {
            try {
                root.windowSizes = Schedule.windowSizes(JSON.parse(text()));
                root.sizeStorageReady = true;
                root.applyWindowSize();
                root.sizeError = "";
            } catch (error) {
                root.sizeError = Translation.tr("Could not read window size settings");
            }
        }
        onLoadFailed: error => {
            root.sizeStorageReady = error === FileViewError.FileNotFound;
            if (!root.sizeStorageReady) root.sizeError = Translation.tr("Could not read window size settings");
        }
        onSaveFailed: root.sizeError = Translation.tr("Could not save window size settings")
        onSaved: root.sizeError = ""
    }
    function compactDescription(event) { return Schedule.compactDescription(event); }
    function eventDate(event) { return Schedule.eventDate(event, selectedDate, uiLocale, Translation.tr("All day")); }
    function isMeetingLink(url) { return Schedule.isMeetingLink(url); }
    function linkCaption(url) { return Schedule.linkCaption(url, Translation.tr("Join meeting")); }
    function showPreview(event, item, day) {
        viewingEvent = event;
        previewDate = day;
        const point = item.mapToItem(frame, 0, 0);
        const right = point.x + item.width + 10;
        meetingPreview.x = Math.max(12, Math.min(right + meetingPreview.width <= frame.width - 12
                                   ? right : point.x - meetingPreview.width - 10, frame.width - meetingPreview.width - 12));
        meetingPreview.y = Math.max(12, Math.min(point.y, frame.height - meetingPreview.height - 12));
        meetingPreview.open();
    }
    function openDate(value) {
        selectedDate = value;
        page = "overview";
        opened = true;
    }
    function openActivity(event) {
        viewingEvent = event;
        page = "details";
    }
    function openEditor(event, start) {
        if (event?.readOnly) {
            viewingEvent = event;
            page = "details";
            return;
        }
        if (!event && Agenda.calendarScope === "work") {
            Qt.openUrlExternally("https://mail.prosebya.ru/owa/#path=/calendar");
            return;
        }
        editingEvent = event || null;
        wholeSeries = false;
        repeating = event ? event.source === "routine" : false;
        repeatDays = event?.days || [selectedDate.getDay()];
        titleField.text = event?.title || "";
        descriptionField.text = event?.description || "";
        colorField.text = event?.color || "#c9aceb";
        startField.text = Schedule.time(event ? event.originalStart : (start === undefined ? 1080 : start));
        endField.text = Schedule.time(event ? event.originalEnd : (start === undefined ? 1140 : start + 60));
        formError = "";
        page = "editor";
        Qt.callLater(() => titleField.forceActiveFocus());
    }
    function setScope(series) {
        wholeSeries = series;
        const event = series ? Agenda.data.routines.find(r => r.id === editingEvent.id) : editingEvent;
        if (!event)
            return;
        titleField.text = event.title;
        descriptionField.text = event.description || "";
        colorField.text = event.color || "#c9aceb";
        startField.text = Schedule.time(series ? event.start : event.originalStart);
        endField.text = Schedule.time(series ? event.end : event.originalEnd);
        repeatDays = event.days;
        formError = "";
    }
    function saveEditor() {
        if (repeating && !repeatDays.length) {
            formError = Translation.tr("Choose repeat days");
            return;
        }
        if (!/^#[0-9a-fA-F]{6}$/.test(colorField.text)) {
            formError = Translation.tr("Color must be #RRGGBB");
            return;
        }
        if (Agenda.store(selectedDate, titleField.text, startField.text, endField.text, repeating ? repeatDays :
                                                                                                    [], editingEvent,
                         wholeSeries, colorField.text, descriptionField.text))
            page = "overview";
        else
            formError = Translation.tr("Enter a title and HH:MM times. Start and end must differ.");
    }
    function writeCalendarExport() {
        exportWritePending = false;
        calendarExportWriter.setText(exportPayload);
    }
    function scrollWeek() {
        Qt.callLater(() => {
            const currentWeek = root.days.some(day => Schedule.key(day) === Schedule.key(Agenda.now));
            const nowY = (Agenda.now.getHours() + Agenda.now.getMinutes() / 60) * root.hourHeight;
            const target = currentWeek ? nowY - weekScroll.height * 0.3 : 8 * root.hourHeight;
            weekScroll.contentY = Math.max(0, Math.min(target, weekScroll.contentHeight - weekScroll.height));
        });
    }
    function zoomWeek(delta, pointerY) {
        if (!delta)
            return;
        const previous = hourHeight;
        const next = Math.max(32, Math.min(128, previous + Math.sign(delta) * 8));
        if (next === previous)
            return;
        const hourAtPointer = (weekScroll.contentY + pointerY) / previous;
        hourHeight = next;
        weekScroll.contentY = Math.max(0, Math.min(hourAtPointer * next - pointerY,
                                                   weekScroll.contentHeight - weekScroll.height));
    }
    function isActive(event, day) {
        if (Schedule.key(day) !== Schedule.key(Agenda.now))
            return false;
        const minute = Agenda.now.getHours() * 60 + Agenda.now.getMinutes();
        return minute >= event.start && minute < event.end;
    }
    onWeekModeChanged: {
        meetingPreview.close();
        if (weekMode) scrollWeek();
    }
    onSelectedDateChanged: {
        meetingPreview.close();
        if (weekMode) scrollWeek();
    }
    onPageChanged: {
        meetingPreview.close();
        if (page === "overview" && weekMode) scrollWeek();
    }
    onVisibleChanged: {
        if (visible) {
            applyWindowSize();
            frame.forceActiveFocus();
            scrollWeek();
        } else {
            meetingPreview.close();
            altPressed = false;
            if (sizeSaveTimer.running) {
                sizeSaveTimer.stop();
                captureWindowSize();
            }
        }
    }
    IpcHandler {
        target: "agenda"
        function open(): void {
            root.openDate(new Date());
        }
        function close(): void {
            root.opened = false;
        }
        function toggle(): void {
            if (root.opened)
                root.opened = false;
            else
                root.openDate(new Date());
        }
    }
    FileDialog {
        id: presetDialog
        title: Translation.tr("Choose JSON preset")
        nameFilters: ["JSON (*.json)"]
        onAccepted: {
            const url = selectedFile.toString();
            if (!url.startsWith("file:///")) {
                root.presetSucceeded = false;
                root.presetStatus = Translation.tr("Select a local JSON file");
                return;
            }
            const path = decodeURIComponent(url.slice(7));
            if (root.presetFilePath === path)
                presetReader.reload();
            else
                root.presetFilePath = path;
        }
    }
    FileView {
        id: presetReader
        path: root.presetFilePath
        onLoaded: {
            const result = Agenda.importPreset(text());
            root.presetSucceeded = result === "";
            root.presetStatus = root.presetSucceeded ? Translation.tr("Preset loaded") : result;
        }
        onLoadFailed: if (root.presetFilePath !== "") {
                          root.presetSucceeded = false;
                          root.presetStatus = Translation.tr("Could not read JSON file");
                      }
    }

    FileDialog {
        id: calendarExportDialog
        title: Translation.tr("Export calendar")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["JSON (*.json)"]
        onAccepted: {
            const url = selectedFile.toString();
            if (!url.startsWith("file:///")) {
                root.exportSucceeded = false;
                root.exportStatus = Translation.tr("Choose a local file location");
                return;
            }
            const previousPath = root.exportFilePath;
            const nextPath = decodeURIComponent(url.slice(7));
            root.exportPayload = JSON.stringify(Agenda.data, null, 2);
            root.exportStatus = "";
            root.exportSucceeded = false;
            root.exportWritePending = true;
            root.exportFilePath = nextPath;
            if (previousPath === root.exportFilePath)
                calendarExportWriter.reload();
        }
    }
    FileView {
        id: calendarExportWriter
        path: root.exportFilePath
        onLoaded: if (root.exportWritePending)
                      root.writeCalendarExport()
        onLoadFailed: error => {
            if (!root.exportWritePending)
                return;
            if (error === FileViewError.FileNotFound) {
                root.writeCalendarExport();
            } else {
                root.exportWritePending = false;
                root.exportSucceeded = false;
                root.exportStatus = Translation.tr("Could not export calendar: %1").arg(error);
            }
        }
        onSaved: {
            root.exportSucceeded = true;
            root.exportStatus = Translation.tr("Calendar exported");
        }
        onSaveFailed: error => {
            root.exportSucceeded = false;
            root.exportStatus = Translation.tr("Could not export calendar: %1").arg(error);
        }
    }

    component Label: StyledText {
        renderType: Text.QtRendering
        font.hintingPreference: Font.PreferNoHinting
        font.family: "Maple Mono"
        font.variableAxes: ({})
        font.pixelSize: 14
        color: Appearance.colors.colOnLayer0
    }
    component Action: RippleButton {
        id: action
        property string label: ""
        property string symbol: ""
        property bool primary: false
        property bool selected: false
        implicitHeight: 42
        implicitWidth: actionText.implicitWidth + (symbol ? 56 : 28)
        colBackground: primary ? Appearance.colors.colPrimary : selected
                                 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : selected
                                      ? Appearance.colors.colSecondaryContainerHover :
                                        Appearance.colors.colLayer1Hover
        buttonRadius: Appearance.rounding.small
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                visible: action.symbol !== ""
                text: action.symbol
                iconSize: 20
                color: action.primary ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
            }
            Label {
                id: actionText
                Layout.fillWidth: true
                text: action.label
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: !action.enabled ? Appearance.colors.colSubtext : action.primary
                                         ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
            }
        }
    }
    component IconButton: RippleButton {
        id: iconButton
        property string symbol
        property string hint
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.small
        Accessible.name: hint
        contentItem: MaterialSymbol {
            text: iconButton.symbol
            iconSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnLayer0
        }
        StyledToolTip {
            text: iconButton.hint
            font.family: "Maple Mono"
        }
    }
    component DailyActivityCard: RippleButton {
        id: dailyCard
        required property var modelData
        property bool grouped: false
        readonly property bool activeNow: root.isActive(modelData, root.selectedDate)
        Layout.fillWidth: true
        implicitHeight: grouped ? 76 : 90
        buttonRadius: Appearance.rounding.normal
        colBackground: activeNow ? Appearance.colors.colSecondaryContainer : grouped ? "transparent" : Appearance.colors.colLayer1
        colBackgroundHover: activeNow ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
        downAction: () => root.openActivity(modelData)
        contentItem: RowLayout {
            spacing: 16
            Rectangle {
                implicitWidth: dailyCard.activeNow ? 5 : 3
                Layout.fillHeight: true
                radius: 2
                color: !dailyCard.grouped && dailyCard.modelData.conflict ? Appearance.m3colors.m3error :
                                                      dailyCard.modelData.color
                                                      || Appearance.colors.colPrimary
            }
            ColumnLayout {
                spacing: 4
                Label {
                    text: Schedule.time(dailyCard.modelData.start)
                    font.pixelSize: 17
                }
                Label {
                    text: Schedule.time(dailyCard.modelData.end)
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label {
                    Layout.fillWidth: true
                    text: dailyCard.modelData.title
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }
                Label {
                    text: dailyCard.modelData.source === "work" ? Translation.tr("Work · Outlook") : !dailyCard.grouped && dailyCard.modelData.conflict ? Translation.tr("Schedule conflict") :
                                                         dailyCard.modelData.source
                                                         === "routine"
                                                         ? Translation.tr("Recurring activity") :
                                                           Translation.tr("Personal event")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialSymbol {
                text: "chevron_right"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }

    component SettingsRow: Item {
        id: setting
        property string title: ""
        property string description: ""
        property string symbol: ""
        default property alias controls: rowActions.data
        Layout.fillWidth: true
        implicitHeight: Math.max(44, rowBody.implicitHeight)
        data: [
            RowLayout {
                id: rowBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                MaterialSymbol {
                    visible: setting.symbol.length > 0
                    text: setting.symbol
                    iconSize: 22
                    color: Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        Layout.fillWidth: true
                        text: setting.title
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                    Label {
                        visible: setting.description.length > 0
                        Layout.fillWidth: true
                        text: setting.description
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                    }
                }
                RowLayout {
                    id: rowActions
                    spacing: 8
                }
            }
        ]
    }
    component SettingsDivider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.5)
    }
    component Section: Rectangle {
        id: section
        default property alias contents: body.data
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        data: [
            ColumnLayout {
                id: body
                x: 14
                y: 14
                width: section.width - 28
                spacing: 12
            }
        ]
    }
    component Field: TextField {
        id: field
        implicitHeight: 46
        padding: 12
        font.family: "Maple Mono"
        font.pixelSize: 15
        color: Appearance.colors.colOnLayer0
        placeholderTextColor: Appearance.colors.colSubtext
        selectionColor: Appearance.colors.colPrimary
        selectedTextColor: Appearance.m3colors.m3onPrimary
        background: Rectangle {
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.small
            border.width: field.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary
        }
        onTextChanged: root.formError = ""
    }

    Popup {
        id: meetingPreview
        parent: frame
        width: Math.min(360, frame.width - 24)
        height: Math.min(previewBody.implicitHeight + 32, frame.height - 24, 440)
        padding: 16
        focus: true
        onOpened: y = Math.max(12, Math.min(y, frame.height - height - 12))
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        contentItem: ScrollView {
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                id: previewBody
                width: parent.width
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: root.viewingEvent?.title || ""
                        textFormat: Text.PlainText
                        font.pixelSize: 16
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    IconButton {
                        symbol: "close"
                        hint: Translation.tr("Close")
                        implicitWidth: 30
                        implicitHeight: 30
                        downAction: () => meetingPreview.close()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: Schedule.eventDate(root.viewingEvent, root.previewDate, root.uiLocale, Translation.tr("All day"))
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.compactDescription(root.viewingEvent)
                    textFormat: Text.PlainText
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
                Action {
                    Layout.fillWidth: true
                    visible: (root.viewingEvent?.links || []).some(url => root.isMeetingLink(url))
                    symbol: "videocam"
                    label: Translation.tr("Join meeting")
                    selected: true
                    downAction: () => {
                        const url = (root.viewingEvent?.links || []).find(url => root.isMeetingLink(url));
                        if (url) Qt.openUrlExternally(url);
                    }
                }
                Action {
                    Layout.fillWidth: true
                    label: Translation.tr("View details")
                    symbol: "arrow_forward"
                    downAction: () => {
                        meetingPreview.close();
                        root.selectedDate = root.previewDate;
                        root.openActivity(root.viewingEvent);
                    }
                }
            }
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        // Hyprland owns the floating window's border and rounded corners.
        color: Appearance.m3colors.m3surfaceContainer
        focus: true
        Keys.onEscapePressed: {
            if (root.page !== "overview")
                root.page = "overview";
            else
                root.opened = false;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Alt) {
                root.altPressed = true;
                event.accepted = true;
                return;
            }
            if (root.page === "overview" && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
                root.selectedDate = Schedule.addDays(root.selectedDate, (event.key === Qt.Key_PageDown ? 1 :
                                                                                                         -1) * (root.weekMode
                                                                                                                ? 7 : 1));
                event.accepted = true;
            }
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt)
                root.altPressed = false;
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                IconButton {
                    visible: root.page !== "overview"
                    symbol: "arrow_back"
                    hint: Translation.tr("Back to schedule")
                    downAction: () => root.page = "overview"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        text: Translation.tr("Calendar")
                        font.pixelSize: 16
                    }
                    Label {
                        text: root.page === "details" ? Translation.tr("Activity details") : root.page === "editor" ? (root.editingEvent ? Translation.tr("Edit activity") :
                                                                            Translation.tr("New activity")) : root.page
                                                       === "settings" ? Translation.tr("Settings") : root.weekMode
                                                                        ? Translation.tr("Week plan") : Translation.tr("Day schedule")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 13
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledComboBox {
                    id: calendarSourcePicker
                    visible: root.page === "overview"
                    leftPadding: 10
                    rightPadding: 28
                    topPadding: 0
                    bottomPadding: 0
                    contentItem: StyledText {
                        text: calendarSourcePicker.displayText
                        color: Appearance.colors.colOnSecondaryContainer
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: MaterialSymbol {
                        x: calendarSourcePicker.width - width - 8
                        y: (calendarSourcePicker.height - height) / 2
                        text: "keyboard_arrow_down"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                        rotation: calendarSourcePicker.popup.visible ? 180 : 0
                    }
                    Layout.fillWidth: false
                    Layout.preferredWidth: Math.min(160, root.width * 0.29) * 0.65
                    textRole: "label"
                    model: [
                        {label: Translation.tr("Personal"), value: "personal"},
                        {label: Translation.tr("Work"), value: "work"},
                        {label: Translation.tr("All"), value: "all"}
                    ]
                    currentIndex: Agenda.calendarScope === "personal" ? 0 : Agenda.calendarScope === "work" ? 1 : 2
                    onActivated: index => { meetingPreview.close(); Agenda.calendarScope = model[index].value; }
                }
                IconButton {
                    visible: root.page === "overview"
                    symbol: "add"
                    hint: Translation.tr("Add activity")
                    downAction: () => root.openEditor(null)
                }
                IconButton {
                    visible: root.page === "overview"
                    symbol: "settings"
                    hint: Translation.tr("Calendar settings")
                    downAction: () => root.page = "settings"
                }
                IconButton {
                    symbol: "close"
                    hint: Translation.tr("Close")
                    downAction: () => root.opened = false
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
            Label {
                visible: Agenda.error !== ""
                Layout.fillWidth: true
                text: Agenda.error
                wrapMode: Text.Wrap
                color: Appearance.m3colors.m3error
            }

            Label {
                visible: root.page === "overview" && Agenda.calendarScope !== "personal"
                         && (!Agenda.workConfigured || Agenda.workError !== "" || Schedule.key(root.selectedDate) < Agenda.workRangeStart
                             || Schedule.key(root.selectedDate) >= Agenda.workRangeEnd)
                Layout.fillWidth: true
                text: Agenda.workError || (!Agenda.workConfigured
                      ? Translation.tr("Connect your work calendar in Settings")
                      : Translation.tr("Work events are outside the synced date range"))
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: Appearance.colors.colSubtext
            }

            ColumnLayout {
                visible: root.page === "overview"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    IconButton {
                        symbol: "chevron_left"
                        hint: Translation.tr("Previous")
                        downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate,
                                                                               root.weekMode ? -7 : -1)
                    }
                    Label {
                        Layout.minimumWidth: 80
                        Layout.maximumWidth: Math.max(80, root.width - 350)
                        text: root.weekMode ? root.days[0].toLocaleDateString(root.uiLocale, "d MMM") + " — "
                                              + root.days[6].toLocaleDateString(root.uiLocale, "d MMM") :
                                              root.selectedDate.toLocaleDateString(root.uiLocale, "ddd, d MMMM")
                        font.pixelSize: 18
                        elide: Text.ElideRight
                    }
                    IconButton {
                        symbol: "chevron_right"
                        hint: Translation.tr("Next")
                        downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate,
                                                                               root.weekMode ? 7 : 1)
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Action {
                        label: Translation.tr("Today")
                        Layout.preferredWidth: 76
                        selected: root.todaySelected
                        downAction: () => {
                            root.selectedDate = new Date();
                            root.weekMode = false;
                        }
                    }
                    Action {
                        Layout.preferredWidth: 66
                        label: Translation.tr("Day")
                        selected: !root.weekMode && !root.todaySelected
                        downAction: () => root.weekMode = false
                    }
                    Action {
                        Layout.preferredWidth: 66
                        label: Translation.tr("Week")
                        selected: root.weekMode
                        downAction: () => root.weekMode = true
                    }
                }
                // Daily agenda uses cards; creation controls live on their own page.
                ScrollView {
                    visible: !root.weekMode && root.events.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: root.dailyGroups
                            Rectangle {
                                id: groupBlock
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: groupContent.implicitHeight + (modelData.overlapping ? 24 : 0)
                                radius: Appearance.rounding.normal
                                color: modelData.overlapping ? Appearance.colors.colLayer1 : "transparent"
                                border.width: modelData.overlapping ? 1 : 0
                                border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.6)
                                ColumnLayout {
                                    id: groupContent
                                    x: groupBlock.modelData.overlapping ? 12 : 0
                                    y: groupBlock.modelData.overlapping ? 12 : 0
                                    width: parent.width - 2 * x
                                    spacing: groupBlock.modelData.overlapping ? 4 : 0
                                    RowLayout {
                                        visible: groupBlock.modelData.overlapping
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 8
                                        Layout.rightMargin: 8
                                        Layout.bottomMargin: 4
                                        spacing: 8
                                        MaterialSymbol {
                                            text: "layers"
                                            iconSize: 18
                                            color: Appearance.colors.colSubtext
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: Schedule.time(groupBlock.modelData.start) + "–" + Schedule.time(groupBlock.modelData.end)
                                            font.pixelSize: 12
                                            color: Appearance.colors.colSubtext
                                        }
                                        Label {
                                            text: Translation.tr("%1 overlapping activities").arg(groupBlock.modelData.events.length)
                                            font.pixelSize: 12
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                    Repeater {
                                        model: groupBlock.modelData.events
                                        DailyActivityCard { grouped: groupBlock.modelData.overlapping }
                                    }
                                }
                            }
                        }
                    }
                }
                Item {
                    visible: root.weekMode ? root.weekEventCount === 0 : root.events.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 14
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "event_available"
                            iconSize: 48
                            color: Appearance.colors.colPrimary
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.weekMode ? Translation.tr("Free week") : Translation.tr("Free day")
                            font.pixelSize: 22
                        }
                        Label {
                            Layout.fillWidth: true
                            text: Translation.tr("Add a meeting, activity\nor time for yourself")
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }
                        Action {
                            Layout.alignment: Qt.AlignHCenter
                            label: Translation.tr("Add activity")
                            primary: true
                            downAction: () => root.openEditor(null)
                        }
                    }
                }
                Row {
                    visible: root.weekMode && root.weekEventCount > 0
                    Layout.fillWidth: true
                    leftPadding: 50
                    Repeater {
                        model: root.days
                        RippleButton {
                            id: dayHeader
                            required property var modelData
                            width: (parent.width - 50) / 7
                            implicitHeight: 48
                            buttonRadius: Appearance.rounding.small
                            downAction: () => {
                                root.selectedDate = modelData;
                                root.weekMode = false;
                            }
                            contentItem: Column {
                                spacing: 4
                                Label {
                                    width: parent.width
                                    text: dayHeader.modelData.toLocaleDateString(root.uiLocale, "ddd")
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: 12
                                }
                                Label {
                                    width: parent.width
                                    text: dayHeader.modelData.getDate()
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: 17
                                    color: Schedule.key(dayHeader.modelData) === Schedule.key(Agenda.now)
                                           ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
                Item {
                    id: weekViewport
                    visible: root.weekMode && root.weekEventCount > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Flickable {
                        id: weekScroll
                        onContentYChanged: meetingPreview.close()
                        onHeightChanged: if (weekViewport.visible)
                                             root.scrollWeek()
                        anchors.fill: parent
                        clip: true
                        contentWidth: width
                        contentHeight: 24 * root.hourHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        Repeater {
                            model: 24
                            Item {
                                required property int index
                                y: index * root.hourHeight
                                width: weekScroll.width
                                Label {
                                    width: 45
                                    text: Schedule.time(parent.index * 60)
                                    font.pixelSize: 11 * 1.1
                                    color: Appearance.colors.colSubtext
                                }
                                Rectangle {
                                    x: 50
                                    width: parent.width - 50
                                    height: 1
                                    color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.4)
                                }
                            }
                        }
                        Row {
                            x: 50
                            width: weekScroll.width - 50
                            height: weekScroll.contentHeight
                            Repeater {
                                model: root.days
                                Item {
                                    id: dayColumn
                                    required property var modelData
                                    width: (weekScroll.width - 50) / 7
                                    height: weekScroll.contentHeight
                                    Repeater {
                                        model: Agenda.day(dayColumn.modelData)
                                        RippleButton {
                                            id: eventBlock
                                            required property var modelData
                                            readonly property bool activeNow: root.isActive(modelData, dayColumn.modelData)
                                            readonly property string timeRange: Schedule.time(modelData.start) + "–" + Schedule.time(modelData.end)
                                            x: modelData.lane * (dayColumn.width - 6) / modelData.lanes + 3
                                            y: modelData.start / 60 * root.hourHeight
                                            width: (dayColumn.width - 6) / modelData.lanes - 3
                                            height: Math.max(10, (modelData.end - modelData.start) / 60 * root.hourHeight
                                                             - 3)
                                            buttonRadius: 9
                                            leftPadding: 10
                                            rightPadding: 8
                                            topPadding: 6
                                            bottomPadding: 6
                                            clip: true
                                            colBackground: activeNow ? Appearance.colors.colSecondaryContainer :
                                                                       Qt.alpha(modelData.color || Appearance.colors.colPrimary,
                                                                                modelData.source === "routine" ? 0.12 : 0.24)
                                            colBackgroundHover: Qt.alpha(modelData.color
                                                                         || Appearance.colors.colPrimary, 0.3)
                                            downAction: () => {
                                                root.showPreview(modelData, eventBlock, dayColumn.modelData);
                                            }
                                            Rectangle {
                                                width: eventBlock.activeNow ? 5 : 3
                                                height: parent.height
                                                radius: 2
                                                color: eventBlock.modelData.conflict
                                                       ? Appearance.m3colors.m3error : eventBlock.modelData.color
                                                         || Appearance.colors.colPrimary
                                            }
                                            contentItem: Column {
                                                spacing: 3
                                                Label {
                                                    width: parent.width
                                                    text: (eventBlock.activeNow ? "● " : "") + eventBlock.modelData.title
                                                    font.pixelSize: 12 * 1.1
                                                    elide: Text.ElideRight
                                                }
                                                Label {
                                                    visible: eventBlock.height > 45
                                                    width: parent.width
                                                    text: eventBlock.timeRange
                                                    font.pixelSize: 10 * 1.1
                                                    color: Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            HoverHandler { id: eventHover }
                                            Timer {
                                                interval: 500
                                                running: eventHover.hovered && root.page === "overview" && root.weekMode && !meetingPreview.visible
                                                onTriggered: if (eventBlock.visible && root.opened) {
                                                    root.showPreview(eventBlock.modelData, eventBlock, dayColumn.modelData);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: root.days.some(day => Schedule.key(day) === Schedule.key(Agenda.now))
                            x: 50
                            y: (Agenda.now.getHours() + Agenda.now.getMinutes() / 60) * root.hourHeight
                            width: weekScroll.width - 50
                            height: 2
                            z: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        z: 1000
                        acceptedButtons: Qt.NoButton
                        onWheel: event => {
                            const angleDelta = event.angleDelta.y || event.angleDelta.x;
                            const pixelDelta = event.pixelDelta.y || event.pixelDelta.x;
                            const delta = angleDelta || pixelDelta;
                            if ((event.modifiers & Qt.AltModifier || root.altPressed) && delta) {
                                root.zoomWeek(delta, event.y);
                            } else {
                                const scrollBy = (angleDelta ? angleDelta / 120 * 160 : pixelDelta) * 0.5;
                                weekScroll.contentY = Math.max(0, Math.min(weekScroll.contentY - scrollBy,
                                                                           weekScroll.contentHeight - weekScroll.height));
                            }
                            event.accepted = true;
                        }
                    }
                }
            }

            ScrollView {
                visible: root.page === "details"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    Label {
                        Layout.fillWidth: true
                        text: root.viewingEvent?.title || ""
                        font.pixelSize: 22
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.eventDate(root.viewingEvent)
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                    }
                    Label {
                        visible: text.length > 0 && !/^https?:\/\//i.test(text)
                        Layout.fillWidth: true
                        text: root.viewingEvent?.location || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                    TextArea {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(60, contentHeight + topPadding + bottomPadding)
                        text: Schedule.descriptionHtml(root.viewingEvent, Translation.tr("Join meeting"))
                              || Schedule.escapeHtml(root.viewingEvent?.readOnly
                                  ? Translation.tr("No description. Choose Full details in Outlook calendar publishing settings, then refresh the calendar.")
                                  : Translation.tr("No description yet. Add one using Edit activity."))
                        textFormat: TextEdit.RichText
                        palette.link: Appearance.colors.colPrimary
                        onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        font.family: "Maple Mono"
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer0
                        selectedTextColor: Appearance.m3colors.m3onPrimary
                        selectionColor: Appearance.colors.colPrimary
                        padding: 0
                        background: null
                    }
                    TextArea {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        implicitHeight: contentHeight + topPadding + bottomPadding
                        text: Schedule.extraLinksHtml(root.viewingEvent, Translation.tr("Join meeting"))
                        textFormat: TextEdit.RichText
                        palette.link: Appearance.colors.colPrimary
                        onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        font.family: "Maple Mono"
                        font.pixelSize: 13
                        color: Appearance.colors.colPrimary
                        padding: 0
                        background: null
                    }
                }
            }
            ColumnLayout {
                visible: root.page === "details"
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Action {
                        Layout.fillWidth: true
                        symbol: root.viewingEvent?.readOnly ? "open_in_new" : "edit"
                        label: root.viewingEvent?.readOnly ? Translation.tr("Open Outlook") : Translation.tr("Edit activity")
                        downAction: () => {
                            if (root.viewingEvent?.readOnly)
                                Qt.openUrlExternally("https://mail.prosebya.ru/owa/#path=/calendar");
                            else root.openEditor(root.viewingEvent);
                        }
                    }
                    Action {
                        Layout.fillWidth: true
                        visible: (root.viewingEvent?.links || []).some(url => root.isMeetingLink(url))
                        symbol: "videocam"
                        label: Translation.tr("Join meeting")
                        primary: true
                        downAction: () => {
                            const url = (root.viewingEvent?.links || []).find(url => root.isMeetingLink(url));
                            if (url) Qt.openUrlExternally(url);
                        }
                    }
                }
            }

            ScrollView {
                visible: root.page === "editor"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: 14
                    Label {
                        text: root.editingEvent ? Translation.tr("Edit activity") : Translation.tr("Plan your time")
                        font.pixelSize: 22
                    }
                    Label {
                        text: root.selectedDate.toLocaleDateString(root.uiLocale, "dddd, d MMMM")
                        color: Appearance.colors.colSubtext
                    }
                    Section {
                        Label {
                            text: Translation.tr("Activity")
                        }
                        Field {
                            id: titleField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("For example, English")
                        }
                        Label {
                            text: Translation.tr("Description")
                            color: Appearance.colors.colSubtext
                        }
                        TextArea {
                            id: descriptionField
                            Layout.fillWidth: true
                            implicitHeight: Math.max(120, contentHeight + topPadding + bottomPadding)
                            placeholderText: Translation.tr("Notes, a plan or a meeting link")
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            font.family: "Maple Mono"
                            font.pixelSize: 14
                            color: Appearance.colors.colOnLayer0
                            placeholderTextColor: Appearance.colors.colSubtext
                            selectionColor: Appearance.colors.colPrimary
                            selectedTextColor: Appearance.m3colors.m3onPrimary
                            padding: 12
                            background: Rectangle {
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                border.width: descriptionField.activeFocus ? 1 : 0
                                border.color: Appearance.colors.colPrimary
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: Translation.tr("Start time")
                                    color: Appearance.colors.colSubtext
                                }
                                Field {
                                    id: startField
                                    Layout.fillWidth: true
                                    inputMethodHints: Qt.ImhTime
                                    placeholderText: "18:00"
                                    maximumLength: 5
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: Translation.tr("End")
                                    color: Appearance.colors.colSubtext
                                }
                                Field {
                                    id: endField
                                    Layout.fillWidth: true
                                    inputMethodHints: Qt.ImhTime
                                    placeholderText: "19:00"
                                    maximumLength: 5
                                }
                            }
                        }
                        Label {
                            text: Translation.tr("Color")
                            color: Appearance.colors.colSubtext
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.activityColors
                                delegate: RippleButton {
                                    required property string modelData
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    buttonRadius: 15
                                    colBackground: modelData
                                    colBackgroundHover: modelData
                                    downAction: () => colorField.text = modelData
                                    Accessible.name: Translation.tr("Color") + " " + modelData
                                    contentItem: MaterialSymbol {
                                        text: "check"
                                        visible: colorField.text.toLowerCase() === modelData
                                        color: "#242424"
                                    }
                                }
                            }
                            Field {
                                id: colorField
                                Layout.fillWidth: true
                                Layout.minimumWidth: 95
                                maximumLength: 7
                                placeholderText: "#RRGGBB"
                            }
                        }
                    }
                    Section {
                        visible: !root.editingEvent || root.editingEvent.source === "routine"
                        Label {
                            text: root.editingEvent ? Translation.tr("Edit") : Translation.tr("Repeat")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Action {
                                Layout.fillWidth: true
                                label: root.editingEvent ? Translation.tr("This day") : Translation.tr("Once")
                                selected: root.editingEvent ? !root.wholeSeries : !root.repeating
                                downAction: () => {
                                    if (root.editingEvent)
                                        root.setScope(false);
                                    else
                                        root.repeating = false;
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                label: root.editingEvent ? Translation.tr("Entire series") : Translation.tr("By weekday")
                                selected: root.editingEvent ? root.wholeSeries : root.repeating
                                downAction: () => {
                                    if (root.editingEvent)
                                        root.setScope(true);
                                    else
                                        root.repeating = true;
                                }
                            }
                        }
                        RowLayout {
                            visible: root.repeating && (!root.editingEvent || root.wholeSeries)
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: [
                                    {
                                        day: 1
                                    },
                                    {
                                        day: 2
                                    },
                                    {
                                        day: 3
                                    },
                                    {
                                        day: 4
                                    },
                                    {
                                        day: 5
                                    },
                                    {
                                        day: 6
                                    },
                                    {
                                        day: 0
                                    }
                                ]
                                Action {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitWidth: 40
                                    label: root.uiLocale.dayName(modelData.day || 7, Locale.ShortFormat)
                                    selected: root.repeatDays.includes(modelData.day)
                                    downAction: () => {
                                        root.repeatDays = selected ? root.repeatDays.filter(d => d
                                                                                                 !== modelData.day) :
                                                                     root.repeatDays.concat([modelData.day]);
                                        root.formError = "";
                                    }
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.editingEvent ? root.wholeSeries ? Translation.tr("Changes will apply to the entire series") :
                                                                         Translation.tr("Other occurrences will stay unchanged") :
                                                                         root.repeating
                                                                         ? Translation.tr("Every week starting on the selected date") :
                                                                           Translation.tr("Only on the selected date")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                    }
                    Label {
                        visible: root.formError !== ""
                        Layout.fillWidth: true
                        text: root.formError
                        color: Appearance.m3colors.m3error
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        visible: root.editingEvent !== null
                        Layout.fillWidth: true
                        Action {
                            Layout.fillWidth: true
                            label: root.wholeSeries ? Translation.tr("Delete series") : Translation.tr("Delete activity")
                            symbol: "delete"
                            enabled: Agenda.ready
                            downAction: () => {
                                if (Agenda.remove(root.editingEvent, root.wholeSeries))
                                    root.page = "overview";
                            }
                        }
                    }
                }
            }
            Action {
                visible: root.page === "editor"
                Layout.fillWidth: true
                label: root.editingEvent ? Translation.tr("Save changes") : Translation.tr("Add activity")
                primary: true
                enabled: Agenda.ready
                downAction: () => root.saveEditor()
            }
            ScrollView {
                id: settingsScroll
                visible: root.page === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                width: Math.min(settingsScroll.availableWidth, 760)
                x: (settingsScroll.availableWidth - width) / 2
                spacing: 14
                Label {
                    text: Translation.tr("Set up calendar")
                    font.pixelSize: 22
                }
                Section {
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: 12
                            color: Qt.alpha(Appearance.colors.colPrimary, 0.12)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: Agenda.workBusy ? "sync" : Agenda.workError ? "error_outline" : "calendar_month"
                                iconSize: 22
                                color: Agenda.workError ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                Layout.fillWidth: true
                                text: Translation.tr("Work calendar · Outlook")
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: (Agenda.workBusy ? Translation.tr("Syncing…") : Agenda.workConfigured
                                      ? (Agenda.workError ? Translation.tr("Connected · refresh failed") : Translation.tr("Connected"))
                                      : Translation.tr("Not connected"))
                                      + (Agenda.workConfigured ? " · " + Agenda.workEvents.length + " " + Translation.tr("events") : "")
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                                color: Agenda.workError ? Appearance.m3colors.m3error : Agenda.workConfigured
                                       ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            Label {
                                visible: Agenda.workConfigured
                                Layout.fillWidth: true
                                text: (Agenda.workUpdatedAt ? new Date(Agenda.workUpdatedAt).toLocaleString(root.uiLocale, "d MMM, HH:mm") + " · " : "")
                                      + Translation.tr("Every 15 min")
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colSubtext
                            }
                        }
                        RowLayout {
                            spacing: 2
                            IconButton {
                                visible: Agenda.workConfigured
                                symbol: "refresh"
                                hint: Translation.tr("Refresh")
                                enabled: !Agenda.workBusy
                                downAction: () => Agenda.workAction("sync")
                            }
                            IconButton {
                                symbol: "open_in_new"
                                hint: Translation.tr("Open Outlook")
                                downAction: () => Qt.openUrlExternally("https://mail.prosebya.ru/owa/#path=/calendar")
                            }
                            IconButton {
                                id: workMenuButton
                                visible: Agenda.workConfigured
                                symbol: "more_vert"
                                hint: Translation.tr("Calendar actions")
                                enabled: !Agenda.workBusy
                                downAction: () => workMenu.open()
                                Popup {
                                    id: workMenu
                                    focus: true
                                    parent: workMenuButton
                                    x: parent.width - width
                                    y: parent.height + 6
                                    width: 220
                                    padding: 8
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                    background: Rectangle {
                                        radius: Appearance.rounding.normal
                                        color: Appearance.m3colors.m3surfaceContainerHigh
                                        border.width: 1
                                        border.color: Appearance.colors.colOutlineVariant
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 4
                                        Action {
                                            Layout.fillWidth: true
                                            label: Translation.tr("Replace link")
                                            symbol: "edit_link"
                                            downAction: () => {
                                                workMenu.close();
                                                root.replacingWorkLink = true;
                                                Qt.callLater(() => workUrlField.forceActiveFocus());
                                            }
                                        }
                                        Action {
                                            Layout.fillWidth: true
                                            label: Translation.tr("Disconnect")
                                            symbol: "link_off"
                                            downAction: () => {
                                                workMenu.close();
                                                root.replacingWorkLink = false;
                                                Agenda.workAction("disconnect");
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: !Agenda.workConfigured
                        text: Translation.tr("Paste the Outlook ICS link. Choose Full details to include descriptions and meeting links.")
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                    }
                    RowLayout {
                        visible: !Agenda.workConfigured || root.replacingWorkLink
                        Layout.fillWidth: true
                        spacing: 8
                        Field {
                            id: workUrlField
                            Layout.fillWidth: true
                            Layout.minimumWidth: 80
                            placeholderText: "https://…/calendar.ics"
                            echoMode: TextInput.PasswordEchoOnEdit
                        }
                        Action {
                            label: Agenda.workConfigured ? Translation.tr("Save") : Translation.tr("Connect")
                            primary: true
                            enabled: !Agenda.workBusy && workUrlField.text.trim().length > 0
                            downAction: () => {
                                Agenda.workAction("connect", workUrlField.text.trim());
                                workUrlField.text = "";
                                root.replacingWorkLink = false;
                            }
                        }
                        IconButton {
                            visible: Agenda.workConfigured
                            symbol: "close"
                            hint: Translation.tr("Cancel")
                            downAction: () => {
                                root.replacingWorkLink = false;
                                workUrlField.text = "";
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: Agenda.workError.length > 0
                        text: Agenda.workError
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3error
                    }
                }

                Label {
                    text: Translation.tr("Reminders")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
                Section {
                    SettingsRow {
                        title: Translation.tr("Activity reminders")
                        description: Translation.tr("Send a playful notification 5 minutes before personal and work activities.")
                        symbol: "notifications_active"
                        StyledSwitch {
                            checked: Agenda.remindersEnabled
                            enabled: Agenda.reminderSettingsReady
                            onClicked: Agenda.setRemindersEnabled(checked)
                        }
                    }
                    SettingsDivider {}
                    SettingsRow {
                        title: Translation.tr("Reminder sound")
                        description: Translation.tr("Play a sound with calendar notifications.")
                        symbol: "volume_up"
                        StyledSwitch {
                            checked: Agenda.reminderSoundEnabled
                            enabled: Agenda.reminderSettingsReady && Agenda.remindersEnabled
                            onClicked: Agenda.setReminderSoundEnabled(checked)
                        }
                    }
                    Label {
                        visible: Agenda.reminderError.length > 0
                        Layout.fillWidth: true
                        text: Agenda.reminderError
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3error
                    }
                }

                Label {
                    text: Translation.tr("Display")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
                Section {
                    SettingsRow {
                        title: Translation.tr("Recurring activities")
                        description: Translation.tr("Meetings and one-time events are always shown")
                        symbol: "event_repeat"
                        StyledSwitch {
                            checked: Agenda.data.presetEnabled
                            enabled: Agenda.ready
                            onClicked: Agenda.togglePreset()
                        }
                    }
                    SettingsDivider {}
                    SettingsRow {
                        title: Translation.tr("Window size")
                        description: Translation.tr("Super + right mouse: resize · Super + left mouse: move. Saved automatically.")
                        symbol: "aspect_ratio"
                        Action {
                            label: Translation.tr("Reset")
                            implicitHeight: 36
                            downAction: () => root.resetWindowSize()
                        }
                    }
                    Label {
                        visible: root.sizeError.length > 0
                        Layout.fillWidth: true
                        text: root.sizeError
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3error
                    }
                }
                Label {
                    text: Translation.tr("Templates & backup")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
                Section {
                    SettingsRow {
                        title: Translation.tr("Example week")
                        description: Translation.tr("Start with a ready-made personal routine.")
                        symbol: "calendar_add_on"
                        Action {
                            label: Translation.tr("Add")
                            implicitHeight: 36
                            enabled: Agenda.ready
                            downAction: () => {
                                if (Agenda.loadExample()) root.page = "overview";
                            }
                        }
                    }
                    SettingsDivider {}
                    SettingsRow {
                        title: Translation.tr("Import preset")
                        description: Translation.tr("Load activities from JSON. Reimporting updates the same preset.")
                        symbol: "upload_file"
                        Action {
                            label: Translation.tr("Choose file")
                            implicitHeight: 36
                            enabled: Agenda.ready
                            downAction: () => {
                                root.presetStatus = "";
                                root.presetSucceeded = false;
                                presetDialog.open();
                            }
                        }
                    }
                    Label {
                        visible: root.presetStatus.length > 0
                        Layout.fillWidth: true
                        text: root.presetStatus
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: root.presetSucceeded ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                    }
                    SettingsDivider {}
                    SettingsRow {
                        title: Translation.tr("Personal backup")
                        description: Translation.tr("Save events, routines and changes to a JSON file.")
                        symbol: "download"
                        Action {
                            label: Translation.tr("Export")
                            implicitHeight: 36
                            enabled: Agenda.ready
                            downAction: () => {
                                root.exportStatus = "";
                                root.exportSucceeded = false;
                                calendarExportDialog.open();
                            }
                        }
                    }
                    Label {
                        visible: root.exportStatus.length > 0
                        Layout.fillWidth: true
                        text: root.exportStatus
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        color: root.exportSucceeded ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                    }
                }
                Section {
                    SettingsRow {
                        title: Translation.tr("Manage personal data")
                        description: Translation.tr("Restore a day or clear your personal schedule.")
                        symbol: "tune"
                        IconButton {
                            symbol: root.advancedSettingsOpen ? "expand_less" : "expand_more"
                            hint: Translation.tr("Manage personal data")
                            downAction: () => {
                                root.advancedSettingsOpen = !root.advancedSettingsOpen;
                                root.confirmingClear = false;
                            }
                        }
                    }
                    SettingsDivider { visible: root.advancedSettingsOpen }
                    SettingsRow {
                        visible: root.advancedSettingsOpen
                        title: Translation.tr("Restore selected day")
                        description: root.selectedDate.toLocaleDateString(root.uiLocale, "ddd, d MMM")
                        symbol: "restore"
                        Action {
                            label: Translation.tr("Restore")
                            implicitHeight: 36
                            enabled: Agenda.ready
                            downAction: () => Agenda.restore(root.selectedDate)
                        }
                    }
                    SettingsDivider { visible: root.advancedSettingsOpen }
                    SettingsRow {
                        visible: root.advancedSettingsOpen
                        title: Translation.tr("Clear personal schedule")
                        description: root.confirmingClear ? Translation.tr("Delete all events and recurring activities?")
                                     : Translation.tr("Remove personal events, routines and changes.")
                        symbol: "delete_sweep"
                        Action {
                            visible: root.confirmingClear
                            label: Translation.tr("Cancel")
                            implicitHeight: 36
                            downAction: () => root.confirmingClear = false
                        }
                        Action {
                            label: root.confirmingClear ? Translation.tr("Delete") : Translation.tr("Clear")
                            implicitHeight: 36
                            colBackground: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                            colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.2)
                            enabled: Agenda.ready && (Agenda.data.events.length > 0 || Agenda.data.routines.length > 0
                                                     || Object.keys(Agenda.data.exceptions).length > 0)
                            downAction: () => {
                                if (!root.confirmingClear) root.confirmingClear = true;
                                else if (Agenda.clearAll()) {
                                    root.confirmingClear = false;
                                    root.editingEvent = null;
                                }
                            }
                        }
                    }
                }

                }
            }
        }
    }
}
