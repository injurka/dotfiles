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
    property string formError: ""
    property string presetStatus: ""
    property string presetFilePath: ""
    readonly property var days: Schedule.week(selectedDate)
    readonly property var events: Agenda.day(selectedDate)
    readonly property int weekEventCount: days.reduce((count, day) => count + Agenda.day(day).length, 0)
    readonly property real hourHeight: 64
    visible: opened
    exclusiveZone: 0
    implicitWidth: Math.min(page === "overview" && weekMode ? 1040 : 560, (screen?.width || 1280) - 40)
    implicitHeight: Math.min(760, (screen?.height || 1080) - 60)
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
        startField.text = Schedule.time(series ? event.start : event.originalStart);
        endField.text = Schedule.time(series ? event.end : event.originalEnd);
        repeatDays = event.days;
        formError = "";
    }
    function saveEditor() {
        if (repeating && !repeatDays.length) {
            formError = "Выбери дни повторения";
            return;
        }
        if (Agenda.store(selectedDate, titleField.text, startField.text, endField.text, repeating ? repeatDays :
                                                                                                    [], editingEvent,
                         wholeSeries))
            page = "overview";
        else
            formError = "Укажи название и время ЧЧ:ММ. Начало и конец должны различаться.";
    }
    function scrollWeek() {
        Qt.callLater(() => {
            const currentWeek = root.days.some(day => Schedule.key(day) === Schedule.key(Agenda.now));
            const nowY = (Agenda.now.getHours() + Agenda.now.getMinutes() / 60) * root.hourHeight;
            const target = currentWeek ? nowY - weekScroll.height * 0.3 : 8 * root.hourHeight;
            weekScroll.contentY = Math.max(0, Math.min(target, weekScroll.contentHeight - weekScroll.height));
        });
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
        } else
            GlobalFocusGrab.removeDismissable(root);
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
        title: "Выбрать JSON-пресет"
        nameFilters: ["JSON (*.json)"]
        onVisibleChanged: if (!visible && root.opened)
                              GlobalFocusGrab.addDismissable(root)
        onAccepted: {
            const url = selectedFile.toString();
            if (!url.startsWith("file:///")) {
                root.presetStatus = "Выбери локальный JSON-файл";
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
            root.presetStatus = Agenda.importPreset(text());
            if (!root.presetStatus)
                root.presetStatus = "Пресет загружен";
        }
        onLoadFailed: if (root.presetFilePath !== "")
                          root.presetStatus = "Не удалось прочитать JSON-файл"
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
            if (root.page === "overview" && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
                root.selectedDate = Schedule.addDays(root.selectedDate, (event.key === Qt.Key_PageDown ? 1 :
                                                                                                         -1) * (root.weekMode
                                                                                                                ? 7 : 1));
                event.accepted = true;
            }
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
                    hint: "К расписанию"
                    downAction: () => root.page = "overview"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        text: "Календарь"
                        font.pixelSize: 16
                    }
                    Label {
                        text: root.page === "editor" ? (root.editingEvent ? "Изменение активности" :
                                                                            "Новая активность") : root.page
                                                       === "settings" ? "Настройки" : root.weekMode
                                                                        ? "План недели" : "Расписание дня"
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
                    hint: "Добавить активность"
                    downAction: () => root.openEditor(null)
                }
                IconButton {
                    visible: root.page === "overview"
                    symbol: "settings"
                    hint: "Настройки календаря"
                    downAction: () => root.page = "settings"
                }
                IconButton {
                    symbol: "close"
                    hint: "Закрыть"
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
                    IconButton {
                        symbol: "chevron_left"
                        hint: "Назад"
                        downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate,
                                                                               root.weekMode ? -7 : -1)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.weekMode ? root.days[0].toLocaleDateString(Qt.locale(), "d MMM") + " — "
                                              + root.days[6].toLocaleDateString(Qt.locale(), "d MMM") :
                                              root.selectedDate.toLocaleDateString(Qt.locale(), "ddd, d MMMM")
                        font.pixelSize: 20
                        elide: Text.ElideRight
                    }
                    IconButton {
                        symbol: "chevron_right"
                        hint: "Вперёд"
                        downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate,
                                                                               root.weekMode ? 7 : 1)
                    }
                    Action {
                        label: "Сегодня"
                        implicitHeight: 34
                        downAction: () => root.selectedDate = new Date()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Action {
                        Layout.fillWidth: true
                        label: "День"
                        symbol: "view_agenda"
                        selected: !root.weekMode
                        downAction: () => root.weekMode = false
                    }
                    Action {
                        Layout.fillWidth: true
                        label: "Неделя"
                        symbol: "calendar_view_week"
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
                                            text: dailyCard.modelData.conflict ? "Пересечение в расписании" :
                                                                                 dailyCard.modelData.source
                                                                                 === "routine"
                                                                                 ? "Повторяющаяся активность" :
                                                                                   "Личное событие"
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
                            text: root.weekMode ? "Неделя свободна" : "День свободен"
                            font.pixelSize: 22
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Добавь встречу, занятие\nили время для себя"
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }
                        Action {
                            Layout.alignment: Qt.AlignHCenter
                            label: "Добавить активность"
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
                                    text: dayHeader.modelData.toLocaleDateString(Qt.locale(), "ddd")
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
                Flickable {
                    id: weekScroll
                    visible: root.weekMode && root.weekEventCount > 0
                    onHeightChanged: if (visible)
                                         root.scrollWeek()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                                                text: Schedule.time(eventBlock.modelData.start)
                                                font.pixelSize: 10 * 1.1
                                                color: Appearance.colors.colSubtext
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
                        text: root.editingEvent ? "Измени активность" : "Запланируй время"
                        font.pixelSize: 22
                    }
                    Label {
                        text: root.selectedDate.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                        color: Appearance.colors.colSubtext
                    }
                    Section {
                        Label {
                            text: "Активность"
                        }
                        Field {
                            id: titleField
                            Layout.fillWidth: true
                            placeholderText: "Например, английский"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: "Начало"
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
                                    text: "Конец"
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
                    }
                    Section {
                        visible: !root.editingEvent || root.editingEvent.source === "routine"
                        Label {
                            text: root.editingEvent ? "Изменить" : "Повторение"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Action {
                                Layout.fillWidth: true
                                label: root.editingEvent ? "Этот день" : "Один раз"
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
                                label: root.editingEvent ? "Всю серию" : "По дням недели"
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
                                        label: "Пн",
                                        day: 1
                                    },
                                    {
                                        label: "Вт",
                                        day: 2
                                    },
                                    {
                                        label: "Ср",
                                        day: 3
                                    },
                                    {
                                        label: "Чт",
                                        day: 4
                                    },
                                    {
                                        label: "Пт",
                                        day: 5
                                    },
                                    {
                                        label: "Сб",
                                        day: 6
                                    },
                                    {
                                        label: "Вс",
                                        day: 0
                                    }
                                ]
                                Action {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitWidth: 40
                                    label: modelData.label
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
                            text: root.editingEvent ? root.wholeSeries ? "Изменения применятся ко всей серии" :
                                                                         "Остальные повторения останутся прежними" :
                                                                         root.repeating
                                                                         ? "Каждую неделю, начиная с выбранной даты" :
                                                                           "Только в выбранную дату"
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
                            label: root.wholeSeries ? "Удалить серию" : "Удалить активность"
                            symbol: "delete"
                            enabled: Agenda.ready
                            downAction: () => {
                                Agenda.remove(root.editingEvent, root.wholeSeries);
                                root.page = "overview";
                            }
                        }
                    }
                }
            }
            Action {
                visible: root.page === "editor"
                Layout.fillWidth: true
                label: root.editingEvent ? "Сохранить изменения" : "Добавить активность"
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
                    text: "Настрой календарь"
                    font.pixelSize: 22
                }
                Section {
                    Label {
                        text: "Повторяющиеся активности"
                    }
                    Action {
                        Layout.fillWidth: true
                        label: Agenda.data.presetEnabled ? "Показываются" : "Скрыты"
                        symbol: Agenda.data.presetEnabled ? "check_circle" : "visibility_off"
                        selected: Agenda.data.presetEnabled
                        enabled: Agenda.ready
                        downAction: () => Agenda.togglePreset()
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Встречи и разовые события видны всегда"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
                Section {
                    Label {
                        text: "Пример обычной недели"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Зарядка, работа и личные занятия. Можно добавить как основу и изменить под себя."
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }
                    Action {
                        Layout.fillWidth: true
                        label: "Добавить пример"
                        symbol: "calendar_add_on"
                        enabled: Agenda.ready
                        downAction: () => {
                            Agenda.loadExample();
                            root.page = "overview";
                        }
                    }
                }
                Section {
                    Label {
                        text: "Пресет из JSON"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Добавит занятия из файла. Повторная загрузка того же пресета обновит его занятия."
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Action {
                        Layout.fillWidth: true
                        label: "Загрузить пресет"
                        symbol: "upload_file"
                        enabled: Agenda.ready
                        downAction: () => {
                            root.presetStatus = "";
                            GlobalFocusGrab.removeDismissable(root);
                            presetDialog.open();
                        }
                    }
                    Label {
                        visible: root.presetStatus !== ""
                        Layout.fillWidth: true
                        text: root.presetStatus
                        color: root.presetStatus === "Пресет загружен" ? Appearance.colors.colPrimary :
                                                                           Appearance.m3colors.m3error
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
                Action {
                    Layout.fillWidth: true
                    label: "Восстановить выбранный день"
                    symbol: "restore"
                    enabled: Agenda.ready
                    downAction: () => Agenda.restore(root.selectedDate)
                }
                Label {
                    visible: root.confirmingClear
                    Layout.fillWidth: true
                    text: "Удалить все события и повторяющиеся активности?"
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Action {
                        visible: root.confirmingClear
                        Layout.fillWidth: true
                        label: "Отмена"
                        downAction: () => root.confirmingClear = false
                    }
                    Action {
                        Layout.fillWidth: true
                        label: root.confirmingClear ? "Очистить" : "Очистить весь календарь"
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
