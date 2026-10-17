import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: actionButton
    property string actionIcon
    implicitHeight: 44
    padding: 8
    buttonRadius: Appearance.rounding.normal
    opacity: enabled ? 1 : 0.5
    buttonColor: down ? Appearance.colors.colLayer2Active
        : hovered && enabled ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    contentItem: Item {
        implicitWidth: labelRow.implicitWidth
        implicitHeight: 22
        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: actionButton.buttonText.length > 0 ? 7 : 0
            MaterialSymbol {
                width: 20
                height: 22
                text: actionButton.actionIcon
                iconSize: 20
                renderType: Text.QtRendering
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                height: 22
                text: actionButton.buttonText
                visible: text.length > 0
                renderType: Text.QtRendering
                font.hintingPreference: Font.PreferNoHinting
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
                color: Appearance.colors.colOnLayer1
            }
        }
    }
}
