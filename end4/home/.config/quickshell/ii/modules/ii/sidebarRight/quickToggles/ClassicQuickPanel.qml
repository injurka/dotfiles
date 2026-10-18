import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"
    readonly property list<string> visibleToggleTypes: Config.options.sidebar.quickToggles.classic.toggles

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        color: Appearance.colors.colLayer1

        NetworkToggle {
            visible: root.visibleToggleTypes.includes("network")
            altAction: () => {
                root.openWifiDialog();
            }
        }
        BluetoothToggle {
            visible: root.visibleToggleTypes.includes("bluetooth")
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
        NightLight { visible: root.visibleToggleTypes.includes("nightLight") }
        WaywallenToggle { visible: root.visibleToggleTypes.includes("waywallen") }
        PowerSavingToggle {
            altAction: () => root.openPowerSavingDialog()
        }
        GameMode { visible: root.visibleToggleTypes.includes("gameMode") }
        IdleInhibitor { visible: root.visibleToggleTypes.includes("idleInhibitor") }
        EasyEffectsToggle { visible: root.visibleToggleTypes.includes("easyEffects") }
        CloudflareWarp { visible: root.visibleToggleTypes.includes("cloudflareWarp") }
    }
}
