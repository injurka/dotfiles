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

PanelWindow {
    id: root
    property bool opened: false
    property date selectedDate: new Date()
    property bool weekMode: false
    property string page: "overview"
    property bool confirmingClear: false
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
    readonly property var days: Schedule.week(selectedDate)
    readonly property var events: Agenda.day(selectedDate)
    readonly property bool todaySelected: !weekMode && Schedule.key(selectedDate) === Schedule.key(Agenda.now)
    readonly property int weekEventCount: days.reduce((count, day) => count + Agenda.day(day).length, 0)
    property real hourHeight: 64
    readonly property var uiLocale: Qt.locale(Translation.languageCode === "he_HE" ? "he_IL" : Translation.languageCode)
    visible: opened
    exclusiveZone: 0
    implicitWidth: Math.min(page === "overview" && weekMode ? 1040 : 560, (screen?.width || 1280) - 40)
    implicitHeight: Math.min(880, (screen?.height || 1080) - 40)
    color: "transparent"
    WlrLayershell.namespace: "quickshell:agenda"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function openDate(value) {
        selectedDate = value;
        page = "overview";
        opened = true;
    }
    function openEditor(event, start) {
        editingEvent = event || null;
        wholeSeries = false;
        repeating = event ? event.source === "routine" : false;
        repeatDays = event?.days || [selectedDate.getDay()];
        titleField.text = event?.title || "";
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
                         wholeSeries, colorField.text))
            page = "overview";
        else
            formError = Translation.tr("Enter a title and HH:MM times. Start and end must differ.");
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
    onWeekModeChanged: if (weekMode)
                           scrollWeek()
    onSelectedDateChanged: if (weekMode)
                               scrollWeek()
    onPageChanged: if (page === "overview" && weekMode)
                       scrollWeek()
    onVisibleChanged: {
        if (visible) {
            GlobalFocusGrab.addDismissable(root);
            frame.forceActiveFocus();
            scrollWeek();
        } else {
            altPressed = false;
            GlobalFocusGrab.removeDismissable(root);
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
    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.opened = false;
        }
    }
    FileDialog {
        id: presetDialog
        title: Translation.tr("Choose JSON preset")
        nameFilters: ["JSON (*.json)"]
        onVisibleChanged: if (!visible && root.opened)
                              GlobalFocusGrab.addDismissable(root)
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

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
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
                        text: root.page === "editor" ? (root.editingEvent ? Translation.tr("Edit activity") :
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
                            model: root.events
                            RippleButton {
                                id: dailyCard
                                required property var modelData
                                readonly property bool activeNow: root.isActive(modelData, root.selectedDate)
                                Layout.fillWidth: true
                                implicitHeight: 90
                                buttonRadius: Appearance.rounding.normal
                                colBackground: activeNow ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                                colBackgroundHover: activeNow ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                                downAction: () => root.openEditor(modelData)
                                contentItem: RowLayout {
                                    spacing: 16
                                    Rectangle {
                                        implicitWidth: dailyCard.activeNow ? 5 : 3
                                        Layout.fillHeight: true
                                        radius: 2
                                        color: dailyCard.modelData.conflict ? Appearance.m3colors.m3error :
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
                                            text: dailyCard.modelData.conflict ? Translation.tr("Schedule conflict") :
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
                                                root.selectedDate = dayColumn.modelData;
                                                root.openEditor(modelData);
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
                                            StyledToolTip {
                                                text: eventBlock.modelData.title + "\n" + eventBlock.timeRange
                                                font.family: "Maple Mono"
                                                delay: 500
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
                visible: root.page === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                width: parent.width
                spacing: 14
                Label {
                    text: Translation.tr("Set up calendar")
                    font.pixelSize: 22
                }
                Section {
                    Label {
                        text: Translation.tr("Recurring activities")
                    }
                    Action {
                        Layout.fillWidth: true
                        label: Agenda.data.presetEnabled ? Translation.tr("Shown") : Translation.tr("Hidden")
                        symbol: Agenda.data.presetEnabled ? "check_circle" : "visibility_off"
                        selected: Agenda.data.presetEnabled
                        enabled: Agenda.ready
                        downAction: () => Agenda.togglePreset()
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Translation.tr("Meetings and one-time events are always shown")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
                Section {
                    Label {
                        text: Translation.tr("Example week")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Translation.tr("Exercise, work, and personal activities. Add them as a starting point and customize them.")
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }
                    Action {
                        Layout.fillWidth: true
                        label: Translation.tr("Add example")
                        symbol: "calendar_add_on"
                        enabled: Agenda.ready
                        downAction: () => {
                            if (Agenda.loadExample())
                                root.page = "overview";
                        }
                    }
                }
                Section {
                    Label {
                        text: Translation.tr("JSON preset")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Translation.tr("Add activities from a file. Loading the same preset again updates its activities.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Action {
                        Layout.fillWidth: true
                        label: Translation.tr("Load preset")
                        symbol: "upload_file"
                        enabled: Agenda.ready
                        downAction: () => {
                            root.presetStatus = "";
                            root.presetSucceeded = false;
                            GlobalFocusGrab.removeDismissable(root);
                            presetDialog.open();
                        }
                    }
                    Label {
                        visible: root.presetStatus !== ""
                        Layout.fillWidth: true
                        text: root.presetStatus
                        color: root.presetSucceeded ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
                Action {
                    Layout.fillWidth: true
                    label: Translation.tr("Restore selected day")
                    symbol: "restore"
                    enabled: Agenda.ready
                    downAction: () => Agenda.restore(root.selectedDate)
                }
                Label {
                    visible: root.confirmingClear
                    Layout.fillWidth: true
                    text: Translation.tr("Delete all events and recurring activities?")
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Action {
                        visible: root.confirmingClear
                        Layout.fillWidth: true
                        label: Translation.tr("Cancel")
                        downAction: () => root.confirmingClear = false
                    }
                    Action {
                        Layout.fillWidth: true
                        label: root.confirmingClear ? Translation.tr("Clear") : Translation.tr("Clear entire calendar")
                        symbol: "delete_sweep"
                        colBackground: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                        colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.2)
                        enabled: Agenda.ready && (Agenda.data.events.length > 0
                                                  || Agenda.data.routines.length > 0 || Object.keys(
                                                      Agenda.data.exceptions).length > 0)
                        downAction: () => {
                            if (!root.confirmingClear)
                                root.confirmingClear = true;
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
