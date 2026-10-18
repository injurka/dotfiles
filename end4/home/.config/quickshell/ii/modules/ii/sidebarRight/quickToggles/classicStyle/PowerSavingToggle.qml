import QtQuick
import qs.services
import qs.modules.common.widgets

QuickToggleButton {
    visible: Battery.available || PowerSaving.available
    enabled: !PowerSaving.busy
    toggled: PowerSaving.active
    buttonIcon: "energy_savings_leaf"
    onClicked: PowerSaving.toggle()
    StyledToolTip {
        text: (PowerSaving.active ? "Энергосбережение включено" : "Энергосбережение выключено")
            + "\nПКМ — настроить" + (PowerSaving.errorText ? "\n" + PowerSaving.errorText : "")
    }
}
