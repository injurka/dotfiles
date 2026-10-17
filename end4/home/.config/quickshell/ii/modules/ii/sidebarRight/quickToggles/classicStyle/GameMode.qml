import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.quickToggles

QuickToggleButton {
    id: root
    property GameModeToggle toggleModel: GameModeToggle {}
    buttonIcon: toggleModel.icon
    toggled: toggleModel.toggled

    onClicked: toggleModel.mainAction()

    StyledToolTip {
        text: root.toggleModel.tooltipText
    }
}
