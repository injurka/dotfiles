import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

WindowDialog {
    id: root
    backgroundHeight: Math.min(700, root.height - 32)
    WindowDialogTitle { text: "Энергосбережение" }

    ScrollView {
        id: optionsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: optionsScroll.availableWidth
            spacing: 4
            ConfigSwitch {
                id: enableSwitch
                text: "Включить сейчас"
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
                text: "Параметры ниже применяются при следующем включении. При выключении возвращаются прежние значения. Ручные изменения сохраняются."
            }
            SettingSwitch {
                settingKey: "profile"
                text: "Системный профиль power-saver"
                supported: PowerSaving.capabilities.profile ?? false
            }
            SettingSwitch {
                settingKey: "dim"
                text: "Ограничивать яркость экрана"
                supported: PowerSaving.capabilities.brightness ?? false
            }
            WindowDialogSlider {
                Layout.fillWidth: true
                enabled: !PowerSaving.busy && (PowerSaving.config.dim ?? false)
                text: "Максимальная яркость"
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
            SettingSwitch {
                settingKey: "refresh"
                text: "Снижать частоту встроенного экрана"
                supported: PowerSaving.capabilities.refresh ?? false
            }
            WindowDialogSlider {
                Layout.fillWidth: true
                enabled: !PowerSaving.busy && (PowerSaving.config.refresh ?? false)
                text: "Предел частоты"
                from: 30
                to: 120
                value: PowerSaving.config.hz ?? 60
                tooltipContent: Math.round(value) + " Гц"
                onMoved: refreshSave.restart()
                Timer {
                    id: refreshSave
                    interval: 500
                    onTriggered: PowerSaving.configure("hz", Math.round(parent.value))
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: "Выбирается поддерживаемая частота не выше предела с тем же разрешением. Внешние мониторы не затрагиваются; яркость не повышается."
            }
            SettingSwitch {
                settingKey: "animations"
                text: "Отключать анимации Hyprland"
                supported: PowerSaving.capabilities.effects ?? false
            }
            SettingSwitch {
                settingKey: "blur"
                text: "Отключать размытие Hyprland"
                supported: PowerSaving.capabilities.effects ?? false
            }
            SettingSwitch { settingKey: "autoBattery"; text: "Включать при отключении зарядки" }
            SettingSwitch { settingKey: "restoreAC"; text: "Восстанавливать при подключении" }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: "Автоматика реагирует на смену питания, пока запущена оболочка (до 15 с). Можно вручную переключить режим до следующей смены питания."
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
        DialogButton { buttonText: "Готово"; onClicked: root.dismiss() }
    }
    component SettingSwitch: ConfigSwitch {
        id: settingSwitch
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
        StyledToolTip { text: parent.supported ? "" : "Недоступно: проверьте оборудование и необходимые службы" }
    }
}
