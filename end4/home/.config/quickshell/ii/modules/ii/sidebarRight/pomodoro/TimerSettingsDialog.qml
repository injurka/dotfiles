pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

WindowDialog {
    id: root
    backgroundWidth: Math.min(400, width - 24)
    backgroundHeight: Math.min(760, height - 32)
    property int focusMinutes: Math.round(Config.options.time.pomodoro.focus / 60)
    property int breakMinutes: Math.round(Config.options.time.pomodoro.breakTime / 60)
    property int longBreakMinutes: Math.round(Config.options.time.pomodoro.longBreak / 60)
    property int cycles: Config.options.time.pomodoro.cyclesBeforeLongBreak
    property bool autoBreak: Config.options.time.pomodoro.autoStartBreak
    property bool autoFocus: Config.options.time.pomodoro.autoStartFocus
    property bool notifications: Config.options.time.pomodoro.notifications
    property bool sound: Config.options.sounds.pomodoro
    readonly property bool durationChanged: focusMinutes * 60 !== Config.options.time.pomodoro.focus
        || breakMinutes * 60 !== Config.options.time.pomodoro.breakTime
        || longBreakMinutes * 60 !== Config.options.time.pomodoro.longBreak
        || cycles !== Config.options.time.pomodoro.cyclesBeforeLongBreak

    WindowDialogTitle { text: Translation.tr("Timer settings") }
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 12
            WindowDialogSectionHeader { text: Translation.tr("Presets") }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        { name: "25 / 5", focus: 25, rest: 5, longRest: 15 },
                        { name: "50 / 10", focus: 50, rest: 10, longRest: 30 },
                        { name: "90 / 20", focus: 90, rest: 20, longRest: 40 }
                    ]
                    delegate: DialogButton {
                        required property var modelData
                        Layout.fillWidth: true
                        buttonText: modelData.name
                        onClicked: {
                            root.focusMinutes = modelData.focus;
                            root.breakMinutes = modelData.rest;
                            root.longBreakMinutes = modelData.longRest;
                            root.cycles = 4;
                        }
                    }
                }
            }
            WindowDialogSectionHeader { text: Translation.tr("Durations and cycles") }
            MinuteSetting {
                label: Translation.tr("Focus")
                maximum: 180
                value: root.focusMinutes
                onEdited: value => root.focusMinutes = value
            }
            MinuteSetting {
                label: Translation.tr("Short break")
                maximum: 60
                value: root.breakMinutes
                onEdited: value => root.breakMinutes = value
            }
            MinuteSetting {
                label: Translation.tr("Long break")
                maximum: 120
                value: root.longBreakMinutes
                onEdited: value => root.longBreakMinutes = value
            }
            MinuteSetting {
                label: Translation.tr("Cycles before long break")
                maximum: 12
                value: root.cycles
                minutes: false
                onEdited: value => root.cycles = value
            }
            WindowDialogSectionHeader { text: Translation.tr("Transitions") }
            ConfigSwitch {
                text: Translation.tr("Start breaks automatically")
                buttonIcon: "free_breakfast"
                checked: root.autoBreak
                onClicked: root.autoBreak = checked
            }
            ConfigSwitch {
                text: Translation.tr("Start focus automatically")
                buttonIcon: "play_arrow"
                checked: root.autoFocus
                onClicked: root.autoFocus = checked
            }
            WindowDialogSectionHeader { text: Translation.tr("Alerts") }
            ConfigSwitch {
                text: Translation.tr("Desktop notifications")
                buttonIcon: "notifications"
                checked: root.notifications
                onClicked: root.notifications = checked
            }
            ConfigSwitch {
                text: Translation.tr("Sound at the end of each phase")
                buttonIcon: "volume_up"
                checked: root.sound
                onClicked: root.sound = checked
            }
            DialogButton {
                buttonText: Translation.tr("Preview sound")
                onClicked: Audio.playSystemSound("alarm-clock-elapsed")
            }
            WindowDialogParagraph {
                Layout.fillWidth: true
                text: root.durationChanged
                    ? Translation.tr("Applying new durations or cycles resets the current session to a paused focus phase.")
                    : Translation.tr("Changes apply when you press Save. Escape or Cancel discards them.")
            }
        }
    }
    WindowDialogButtonRow {
        Layout.fillWidth: true
        DialogButton {
            buttonText: Translation.tr("Defaults")
            onClicked: {
                root.focusMinutes = 25;
                root.breakMinutes = 5;
                root.longBreakMinutes = 15;
                root.cycles = 4;
                root.autoBreak = true;
                root.autoFocus = true;
                root.notifications = true;
                root.sound = false;
            }
        }
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
        DialogButton {
            buttonText: Translation.tr("Save")
            onClicked: {
                TimerService.applySettings(root.focusMinutes, root.breakMinutes, root.longBreakMinutes,
                    root.cycles, root.autoBreak, root.autoFocus, root.notifications, root.sound);
                root.dismiss();
            }
        }
    }
    component MinuteSetting: ColumnLayout {
        id: setting
        required property string label
        required property int maximum
        required property int value
        property bool minutes: true
        signal edited(int value)
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            text: setting.minutes ? Translation.tr("%1: %2 min").arg(setting.label).arg(setting.value)
                : setting.label + ": " + setting.value
        }
        StyledSlider {
            Layout.fillWidth: true
            from: 1
            to: setting.maximum
            stepSize: 1
            snapMode: Slider.SnapAlways
            value: setting.value
            tooltipContent: Math.round(value).toString()
            onMoved: setting.edited(Math.round(value))
        }
    }
}
