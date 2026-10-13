pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
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
    property var selectedEvent: null
    property var editingEvent: null
    property var repeatDays: [1, 2, 3, 4, 5]
    property string formError: ""
    readonly property var days: weekMode ? Schedule.week(selectedDate) : [selectedDate]
    readonly property real minuteHeight: weekMode ? 0.8 : 1.15
    visible: opened
    exclusiveZone: 0
    implicitWidth: Math.min(weekMode ? 1180 : 740, (screen?.width || 1280) - 40)
    implicitHeight: Math.min(860, (screen?.height || 1080) - 60)
    color: "transparent"
    WlrLayershell.namespace: "quickshell:agenda"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    function openDate(value) {
        selectedDate = value;
        selectedEvent = null;
        opened = true;
    }
    onSelectedDateChanged: {
        selectedEvent = null;
        cancelEdit();
    }
    function cancelEdit() {
        editingEvent = null;
        titleField.clear();
        formError = "";
    }
    function editSelection() {
        const event = selectedEvent;
        editingEvent = event;
        titleField.text = event.title;
        startField.text = Schedule.time(event.originalStart);
        endField.text = Schedule.time(event.originalEnd);
        repeatBox.checked = event.source === "routine";
        repeatDays = event.days || [selectedDate.getDay()];
        editScope.currentIndex = 0;
        timeline.contentY = Math.max(0, event.start - 60) * root.minuteHeight;
        titleField.forceActiveFocus();
    }
    onVisibleChanged: {
        if (visible) {
            GlobalFocusGrab.addDismissable(root);
            frame.forceActiveFocus();
            Qt.callLater(() => timeline.contentY = (root.weekMode || Schedule.key(root.selectedDate) !== Schedule.key(Agenda.now) ? 8 : Math.max(0, Agenda.now.getHours() - 1)) * 60 * root.minuteHeight);
        } else
            GlobalFocusGrab.removeDismissable(root);
    }
    onWeekModeChanged: Qt.callLater(() => timeline.contentY = (weekMode ? 8 : Math.max(0, Agenda.now.getHours() - 1)) * 60 * minuteHeight)
    IpcHandler {
        target: "agenda"
        function open(): void { root.openDate(new Date()); }
        function close(): void { root.opened = false; }
        function toggle(): void { if (root.opened) root.opened = false; else root.openDate(new Date()); }
    }
    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.opened = false;
        }
    }
    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1Base
        border.color: Appearance.colors.colLayer2
        focus: true
        Keys.onEscapePressed: {
            if (root.editingEvent)
                root.cancelEdit();
            else if (root.selectedEvent)
                root.selectedEvent = null;
            else
                root.opened = false;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                root.selectedDate = Schedule.addDays(root.selectedDate, (event.key === Qt.Key_PageDown ? 1 :
                                                                                                         -1) * (root.weekMode
                                                                                                                ? 7 : 1));
                event.accepted = true;
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.weekMode ? root.days[0].toLocaleDateString(Qt.locale(), "d MMM") + " — "
                                          + root.days[6].toLocaleDateString(Qt.locale(), "d MMM yyyy") :
                                          root.selectedDate.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    elide: Text.ElideRight
                }
                CalendarHeaderButton {
                    buttonText: "День"
                    downAction: () => root.weekMode = false
                }
                CalendarHeaderButton {
                    buttonText: "Неделя"
                    downAction: () => root.weekMode = true
                }
                CalendarHeaderButton {
                    buttonText: "×"
                    tooltipText: "Закрыть · Esc"
                    downAction: () => root.opened = false
                }
            }
            RowLayout {
                CalendarHeaderButton {
                    buttonText: "‹"
                    downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate, root.weekMode ?
                                                                               -7 : -1)
                }
                CalendarHeaderButton {
                    buttonText: "Сегодня"
                    downAction: () => root.selectedDate = new Date()
                }
                CalendarHeaderButton {
                    buttonText: "›"
                    downAction: () => root.selectedDate = Schedule.addDays(root.selectedDate, root.weekMode
                                                                           ? 7 : 1)
                }
                Item {
                    Layout.fillWidth: true
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: Agenda.data.presetEnabled ? "Повторения: вкл." : "Повторения: выкл."
                    tooltipText: "Показать или скрыть повторяющиеся занятия"
                    downAction: () => Agenda.togglePreset()
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: Agenda.error.length > 0 || !Agenda.ready
                text: Agenda.error || "Загрузка расписания…"
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.weekMode
                property var events: {
                    const tick = Agenda.now;
                    return Agenda.day(root.selectedDate);
                }
                text: {
                    if (!events.length)
                        return "День свободен. Добавь событие или повторяющееся занятие.";
                    if (Schedule.key(root.selectedDate) !== Schedule.key(Agenda.now))
                        return events.length + " активностей · нажми на блок для действий";
                    const minute = Agenda.now.getHours() * 60 + Agenda.now.getMinutes();
                    const current = events.filter(e => e.start <= minute && e.end > minute);
                    const next = events.find(e => e.start > minute);
                    return (current.length ? "Сейчас: " + current.map(e => e.title).join(" / ") :
                                             "Сейчас свободно") + (next ? " · Далее: " + Schedule.time(
                                                                              next.start) + " " + next.title :
                                                                          " · На сегодня больше ничего");
                }
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item {
                    implicitWidth: 48
                }
                Repeater {
                    model: root.days
                    CalendarHeaderButton {
                        required property var modelData
                        Layout.fillWidth: true
                        buttonText: modelData.toLocaleDateString(Qt.locale(), "ddd, d")
                        downAction: () => {
                            root.selectedDate = modelData;
                            root.weekMode = false;
                        }
                    }
                }
            }
            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Flickable {
                    id: timeline
                    contentWidth: width
                    contentHeight: 1440 * root.minuteHeight
                    boundsBehavior: Flickable.StopAtBounds
                    Repeater {
                        model: 24
                        Item {
                            required property int index
                            y: index * 60 * root.minuteHeight
                            width: timeline.width
                            StyledText {
                                width: 46
                                text: Schedule.time(parent.index * 60)
                                font.pixelSize: 11
                                color: Appearance.colors.colOutline
                            }
                            Rectangle {
                                x: 52
                                width: parent.width - 52
                                height: 1
                                color: Appearance.colors.colLayer2
                            }
                        }
                    }
                    Row {
                        x: 54
                        width: timeline.width - 54
                        height: timeline.contentHeight
                        Repeater {
                            model: root.days
                            Item {
                                id: dayColumn
                                required property var modelData
                                width: (timeline.width - 54) / root.days.length
                                height: timeline.contentHeight
                                readonly property var events: Agenda.day(modelData)
                                Repeater {
                                    model: dayColumn.events
                                    Rectangle {
                                        id: eventBlock
                                        required property var modelData
                                        x: modelData.lane * (dayColumn.width - 6) / modelData.lanes
                                        y: modelData.start * root.minuteHeight
                                        width: (dayColumn.width - 6) / modelData.lanes - 3
                                        height: Math.max(8, (modelData.end - modelData.start)
                                                         * root.minuteHeight - 2)
                                        radius: 7
                                        color: Qt.alpha(modelData.color || "#c9aceb", modelData.source
                                                        === "routine" ? 0.12 : 0.27)
                                        border.width: root.selectedEvent?.occurrenceId
                                                      === modelData.occurrenceId ? 2 : 1
                                        border.color: modelData.conflict ? "#db948e" : Qt.alpha(
                                                                               modelData.color || "#c9aceb",
                                                                               0.5)
                                        clip: true
                                        activeFocusOnTab: true
                                        Keys.onReturnPressed: {
                                            root.selectedDate = dayColumn.modelData;
                                            root.selectedEvent = modelData;
                                        }
                                        Keys.onSpacePressed: {
                                            root.selectedDate = dayColumn.modelData;
                                            root.selectedEvent = modelData;
                                        }
                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 2
                                            StyledText {
                                                width: parent.width
                                                text: eventBlock.modelData.title
                                                elide: Text.ElideRight
                                                font.pixelSize: 12
                                            }
                                            StyledText {
                                                width: parent.width
                                                text: Schedule.time(eventBlock.modelData.start) + "–"
                                                      + Schedule.time(eventBlock.modelData.end)
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOutline
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.selectedDate = dayColumn.modelData;
                                                root.selectedEvent = eventBlock.modelData;
                                            }
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.title + " " + Schedule.time(
                                                             modelData.start)
                                        Accessible.onPressAction: {
                                            root.selectedDate = dayColumn.modelData;
                                            root.selectedEvent = modelData;
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: Schedule.key(dayColumn.modelData) === Schedule.key(Agenda.now)
                                    y: (Agenda.now.getHours() * 60 + Agenda.now.getMinutes())
                                       * root.minuteHeight
                                    width: parent.width - 5
                                    height: 2
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                visible: root.selectedEvent !== null
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.selectedEvent ? root.selectedEvent.title + (root.selectedEvent.conflict
                                                                           ? " · Пересечение" : "") : ""
                    elide: Text.ElideRight
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: "Изменить"
                    downAction: () => root.editSelection()
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: "−30 мин"
                    downAction: () => {
                        Agenda.move(root.selectedEvent, -30);
                        root.selectedEvent = null;
                    }
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: "+30 мин"
                    downAction: () => {
                        Agenda.move(root.selectedEvent, 30);
                        root.selectedEvent = null;
                    }
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: "Пропустить"
                    downAction: () => {
                        Agenda.skip(root.selectedEvent);
                        root.selectedEvent = null;
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    visible: root.editingEvent !== null
                    text: "Редактирование"
                }
                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    placeholderText: "Название активности"
                    color: Appearance.colors.colOnLayer1
                    background: Rectangle {
                        radius: 8
                        color: Appearance.colors.colLayer2
                    }
                }
                TextField {
                    id: startField
                    implicitWidth: 72
                    placeholderText: "18:00"
                    color: Appearance.colors.colOnLayer1
                    background: Rectangle {
                        radius: 8
                        color: Appearance.colors.colLayer2
                    }
                }
                TextField {
                    id: endField
                    implicitWidth: 72
                    placeholderText: "19:00"
                    color: Appearance.colors.colOnLayer1
                    background: Rectangle {
                        radius: 8
                        color: Appearance.colors.colLayer2
                    }
                }
                CalendarHeaderButton {
                    buttonText: root.editingEvent ? "Сохранить" : "Добавить"
                    enabled: Agenda.ready
                    downAction: () => {
                        const days = repeatBox.checked ? root.repeatDays : [];
                        if (repeatBox.checked && !days.length) {
                            root.formError = "Выбери хотя бы один день повторения.";
                            return;
                        }
                        if (Agenda.store(root.selectedDate, titleField.text, startField.text, endField.text, days,
                                         root.editingEvent, editScope.currentIndex === 1)) {
                            root.cancelEdit();
                            root.selectedEvent = null;
                        } else
                            root.formError
                                    = "Укажи название и время в формате ЧЧ:ММ. Начало и конец должны различаться.";
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                CheckBox {
                    id: repeatBox
                    text: "Каждую неделю"
                    enabled: !root.editingEvent
                    contentItem: StyledText {
                        text: repeatBox.text
                        leftPadding: repeatBox.indicator.width + repeatBox.spacing
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                ComboBox {
                    id: editScope
                    visible: root.editingEvent?.source === "routine"
                    model: ["Это повторение", "Вся серия"]
                    onActivated: {
                        if (currentIndex === 1 && root.editingEvent) {
                            const original = Agenda.data.routines.find(r => r.id === root.editingEvent.id);
                            if (original) {
                                titleField.text = original.title;
                                startField.text = Schedule.time(original.start);
                                endField.text = Schedule.time(original.end);
                                root.repeatDays = original.days;
                            }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                CalendarHeaderButton {
                    buttonText: "Отменить изменение"
                    enabled: Agenda.ready && Agenda.history.length > 0
                    downAction: () => {
                        Agenda.undo();
                        root.cancelEdit();
                        root.selectedEvent = null;
                    }
                }
                CalendarHeaderButton {
                    visible: root.editingEvent !== null
                    buttonText: "Отмена"
                    downAction: () => root.cancelEdit()
                }
                CalendarHeaderButton {
                    visible: root.editingEvent !== null
                    enabled: Agenda.ready
                    buttonText: editScope.visible && editScope.currentIndex === 1 ? "Удалить серию" :
                                                                                    "Удалить событие"
                    downAction: () => {
                        Agenda.remove(root.editingEvent, editScope.currentIndex === 1);
                        root.cancelEdit();
                        root.selectedEvent = null;
                    }
                }
            }
            RowLayout {
                visible: repeatBox.checked && (!root.editingEvent || editScope.currentIndex === 1)
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
                    CheckBox {
                        id: weekdayBox
                        required property var modelData
                        checked: root.repeatDays.includes(modelData.day)
                        onClicked: root.repeatDays = checked ? root.repeatDays.concat([modelData.day]) :
                                                               root.repeatDays.filter(d => d
                                                                                           !== modelData.day)
                        contentItem: StyledText {
                            text: weekdayBox.modelData.label
                            leftPadding: weekdayBox.indicator.width + weekdayBox.spacing
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            StyledText {
                visible: root.formError.length > 0
                text: root.formError
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                CalendarHeaderButton {
                    buttonText: "Пример недели"
                    enabled: Agenda.ready
                    tooltipText: "Добавить пример рутины по мотивам скриншота"
                    downAction: () => Agenda.loadExample()
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Локальный календарь · повторения бледнее · Outlook не подключён"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOutline
                }
                CalendarHeaderButton {
                    enabled: Agenda.ready
                    buttonText: "Восстановить день"
                    tooltipText: "Вернуть пропущенные и перенесённые активности выбранной даты"
                    downAction: () => {
                        Agenda.restore(root.selectedDate);
                        root.selectedEvent = null;
                    }
                }
            }
        }
    }
}
