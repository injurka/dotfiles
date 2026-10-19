import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

WindowDialog {
    id: root
    backgroundHeight: Math.min(700, root.height - 32)
    WindowDialogTitle { text: "Power saving" }

    ScrollView {
        id: optionsScroll
        Layout.rightMargin: -12
        rightPadding: 16
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: optionsScroll.availableWidth
            spacing: 12
            ConfigSwitch {
                id: enableSwitch
                leftPadding: 0
                rightPadding: 0
                text: "Enable now"
                buttonIcon: "energy_savings_leaf"
                checked: PowerSaving.active
                enabled: !PowerSaving.busy
                onClicked: PowerSaving.toggle()
                Connections {
                    target: PowerSaving
                    function onStateChanged() { enableSwitch.checked = PowerSaving.active; }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: "Changes apply next time power saving is enabled. Turning it off restores your previous settings."
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sectionContent1.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainer
                ColumnLayout {
                    id: sectionContent1
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: "System profile"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    SettingSwitch {
                        settingKey: "profile"
                        text: "Use power-saver system profile"
                        supported: PowerSaving.capabilities.profile ?? false
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sectionContent2.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainer
                ColumnLayout {
                    id: sectionContent2
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: "Brightness"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    SettingSwitch {
                        settingKey: "dim"
                        text: "Limit screen brightness"
                        supported: PowerSaving.capabilities.brightness ?? false
                    }
                    WindowDialogSlider {
                        Layout.fillWidth: true
                        enabled: !PowerSaving.busy && (PowerSaving.config.dim ?? false)
                        text: "Maximum brightness: " + Math.round(value) + "%"
                        from: 5
                        to: 100
                        value: PowerSaving.config.brightness ?? 35
                        tooltipContent: Math.round(value) + "%"
                        // Debounce slider writes to avoid spawning a process for every step.
                        onMoved: brightnessSave.restart()
                        Timer {
                            id: brightnessSave
                            interval: 500
                            onTriggered: PowerSaving.configure("brightness", Math.round(parent.value))
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sectionContent3.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainer
                ColumnLayout {
                    id: sectionContent3
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: "Refresh rate"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    SettingSwitch {
                        settingKey: "refresh"
                        text: "Limit built-in display refresh rate"
                        supported: PowerSaving.capabilities.refresh ?? false
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Refresh rate limit"
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: [60, 120]
                            delegate: RippleButton {
                                id: rateButton
                                required property var modelData
                                readonly property bool selected: (PowerSaving.config.hz ?? 60) === modelData
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: 40
                                enabled: !PowerSaving.busy && (PowerSaving.capabilities.refresh ?? false)
                                // Keep the saved choice readable even when hardware is unavailable.
                                opacity: 1
                                Accessible.name: modelData + " Hz refresh rate limit"
                                Accessible.role: Accessible.RadioButton
                                Accessible.checkable: true
                                Accessible.checked: selected
                                background: Rectangle {
                                    radius: Appearance.rounding.small
                                    color: rateButton.selected ? Appearance.m3colors.m3primaryContainer
                                        : rateButton.hovered ? Appearance.m3colors.m3surfaceContainerHighest
                                        : Appearance.m3colors.m3surfaceContainerHigh
                                    border.width: rateButton.selected ? 2 : 1
                                    border.color: rateButton.selected ? Appearance.m3colors.m3primary
                                        : Appearance.m3colors.m3outline
                                }
                                contentItem: StyledText {
                                    text: (rateButton.selected ? "✓ " : "") + rateButton.modelData + " Hz"
                                    horizontalAlignment: Text.AlignHCenter
                                    font.bold: rateButton.selected
                                    color: rateButton.selected ? Appearance.m3colors.m3onPrimaryContainer
                                        : Appearance.m3colors.m3onSurface
                                }
                                onClicked: PowerSaving.configure("hz", modelData)
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurfaceVariant
                        text: (PowerSaving.config.refresh ?? false)
                            ? "Uses the nearest supported rate at or below the limit, at the same resolution. Built-in display only."
                            : "Refresh rate limit is off. Choose a preset, then enable the switch above to use it."
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sectionContent4.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainer
                ColumnLayout {
                    id: sectionContent4
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: "Visual effects"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    SettingSwitch {
                        settingKey: "animations"
                        text: "Disable Hyprland animations"
                        supported: PowerSaving.capabilities.effects ?? false
                    }
                    SettingSwitch {
                        settingKey: "blur"
                        text: "Disable Hyprland blur"
                        supported: PowerSaving.capabilities.effects ?? false
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sectionContent5.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainer
                ColumnLayout {
                    id: sectionContent5
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: "Automation"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    SettingSwitch { settingKey: "autoBattery"; text: "Enable when unplugged" }
                    SettingSwitch { settingKey: "restoreAC"; text: "Restore when plugged in" }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: "While the shell is running, power source changes are detected within 15 seconds. You can override the mode until the next power source change."
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: PowerSaving.errorText.length > 0
                wrapMode: Text.WordWrap
                text: PowerSaving.errorText
                color: Appearance.m3colors.m3error
            }
        }
    }
    WindowDialogButtonRow {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        DialogButton { buttonText: "Done"; onClicked: root.dismiss() }
    }
    component SettingSwitch: ConfigSwitch {
        id: settingSwitch
        leftPadding: 0
        rightPadding: 0
        required property string settingKey
        property bool supported: true
        Layout.fillWidth: true
        checked: PowerSaving.config[settingKey] ?? false
        enabled: !PowerSaving.busy && supported
        onClicked: PowerSaving.configure(settingKey, !PowerSaving.config[settingKey])
        Connections {
            target: PowerSaving
            function onStateChanged() { settingSwitch.checked = PowerSaving.config[settingSwitch.settingKey] ?? false; }
        }
        StyledToolTip { text: parent.supported ? "" : "Unavailable: check hardware and required services" }
    }
}
