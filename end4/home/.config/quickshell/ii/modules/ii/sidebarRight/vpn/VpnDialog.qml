import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

WindowDialog {
    id: root
    property var priority: ["Prosebya", "AmneziaVPN", "Browsec"]
    property string errorText: ""
    readonly property string helper: Qt.resolvedUrl("../../../../scripts/vpn/control.py").toString().replace("file://", "")
    backgroundHeight: content.implicitHeight + 56
    function move(index, delta) {
        const next = priority.slice();
        const target = index + delta;
        if (target < 0 || target >= next.length) return;
        [next[index], next[target]] = [next[target], next[index]];
        priority = next;
    }
    Process {
        command: ["python3", root.helper, "priority"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.priority = JSON.parse(text).priority; }
                catch (error) { root.errorText = "Не удалось загрузить приоритет"; }
            }
        }
    }
    Process {
        id: save
        command: ["python3", root.helper, "save-priority", JSON.stringify(root.priority)]
        onExited: (exitCode) => {
            if (exitCode === 0) root.dismiss();
            else root.errorText = "Не удалось сохранить приоритет";
        }
    }
    ColumnLayout {
        id: content
        Layout.fillWidth: true
        spacing: 16
        WindowDialogTitle { text: "VPN" }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: "Первый в списке подключается по нажатию кнопки VPN. Если VPN уже активен, нажатие отключит его."
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.priority
                delegate: Rectangle {
                    id: provider
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 76
                    radius: Appearance.rounding.normal
                    color: provider.index === 0 ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainer
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        MaterialSymbol {
                            text: provider.index === 0 ? "verified_user" : "vpn_lock"
                            iconSize: 22
                            color: provider.index === 0 ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: provider.modelData
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: provider.index === 0 ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                text: provider.index === 0 ? "Основной VPN" : "Приоритет " + (provider.index + 1)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                        }
                        RippleButton {
                            implicitWidth: 30; implicitHeight: 36
                            enabled: provider.index > 0 && !save.running
                            onClicked: root.move(provider.index, -1)
                            contentItem: MaterialSymbol { text: "arrow_upward"; iconSize: 18; horizontalAlignment: Text.AlignHCenter; opacity: parent.enabled ? 1 : 0.3 }
                            StyledToolTip { text: "Повысить приоритет" }
                        }
                        RippleButton {
                            implicitWidth: 30; implicitHeight: 36
                            enabled: provider.index < 2 && !save.running
                            onClicked: root.move(provider.index, 1)
                            contentItem: MaterialSymbol { text: "arrow_downward"; iconSize: 18; horizontalAlignment: Text.AlignHCenter; opacity: parent.enabled ? 1 : 0.3 }
                            StyledToolTip { text: "Понизить приоритет" }
                        }
                        RippleButton {
                            implicitWidth: 30; implicitHeight: 36
                            onClicked: Quickshell.execDetached(["python3", root.helper, "launch", provider.modelData])
                            contentItem: MaterialSymbol { text: "settings"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                            StyledToolTip { text: "Настройки " + provider.modelData }
                        }
                    }
                }
            }
        }
        WindowDialogParagraph {
            Layout.fillWidth: true
            text: "Сервер и автоподключение — в настройках соответствующего VPN-клиента."
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3error
        }
        WindowDialogButtonRow {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DialogButton { buttonText: "Отмена"; enabled: !save.running; onClicked: root.dismiss() }
            DialogButton { buttonText: "Сохранить"; enabled: !save.running; onClicked: save.running = true }
        }
    }
}
