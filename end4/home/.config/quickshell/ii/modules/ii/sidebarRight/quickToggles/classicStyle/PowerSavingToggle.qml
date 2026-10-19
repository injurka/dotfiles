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
        text: (PowerSaving.active ? "Power saving on" : "Power saving off")
            + "\nRight-click to configure" + (PowerSaving.errorText ? "\n" + PowerSaving.errorText : "")
    }
}
