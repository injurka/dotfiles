import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.widgets

QuickToggleButton {
    id: root
    signal openSettings()
    property var vpnState: ({ active: [], preferred: "Prosebya", error: "" })
    readonly property string helper: Qt.resolvedUrl("../../../../../scripts/vpn/control.py").toString().replace("file://", "")
    buttonIcon: "vpn_lock"
    toggled: vpnState.active.length > 0
    enabled: !action.running
    onClicked: action.running = true
    altAction: () => root.openSettings()
    Process {
        id: status
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.vpnState = JSON.parse(text); } catch (error) {
                    root.vpnState = { active: [], preferred: "Prosebya", error: "VPN: статус недоступен" };
                }
            }
        }
    }
    Process {
        id: action
        command: ["python3", root.helper, "toggle"]
        onExited: status.running = true
    }
    Timer {
        interval: 4000
        running: root.visible && !action.running
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!status.running) status.running = true
    }
    StyledToolTip {
        text: root.vpnState.error || ((root.toggled ? "VPN: " + root.vpnState.active.join(", ") : "Подключить: " + root.vpnState.preferred) + "\nПКМ — приоритет и настройки")
    }
}
