import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Button {
    id: actionCard
    property real buttonRadius: 17
    padding: 0
    hoverEnabled: true
    background: Rectangle {
        radius: actionCard.buttonRadius
        color: actionCard.down ? Appearance.colors.colLayer1Active
            : actionCard.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    required property string label
    required property string description
    required property string symbol
    required property color accent
    required property var trigger
    implicitHeight: 76
    onClicked: trigger()
    contentItem: Item {
        Rectangle {
            x: 14; y: 18
            width: 40; height: 40; radius: 13
            color: Qt.alpha(actionCard.accent, 0.15)
            MaterialSymbol {
                renderType: Text.QtRendering
                renderTypeQuality: Text.HighRenderTypeQuality
                font.hintingPreference: Font.PreferNoHinting
                anchors.centerIn: parent
                text: actionCard.symbol
                iconSize: 24
                color: actionCard.accent
            }
        }
        Column {
            x: 67; y: 19
            width: parent.width - 80
            spacing: 4
            StyledText {
                renderType: Text.QtRendering
                renderTypeQuality: Text.HighRenderTypeQuality
                font.hintingPreference: Font.PreferNoHinting
                width: parent.width
                text: actionCard.label
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                renderType: Text.QtRendering
                renderTypeQuality: Text.HighRenderTypeQuality
                font.hintingPreference: Font.PreferNoHinting
                width: parent.width
                text: actionCard.description
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
