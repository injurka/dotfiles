import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var sessions: []
    property string currentSessionId: ""
    property bool connected: false
    property bool loading: false
    property bool changing: false
    property bool busy: false
    property string errorText: ""
    signal back()
    signal newChat()
    signal selected(string sessionId)

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.maximumHeight: 36
            VoiceActionButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                actionIcon: "arrow_back"
                Accessible.name: Translation.tr("Back")
                ToolTip.visible: hovered
                ToolTip.text: Translation.tr("Back")
                onClicked: root.back()
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("History")
                renderType: Text.QtRendering
                font.hintingPreference: Font.PreferNoHinting
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.large
                elide: Text.ElideRight
            }
            VoiceActionButton {
                Layout.preferredHeight: 36
                actionIcon: "add"
                buttonText: Translation.tr("New chat")
                enabled: root.connected && !root.busy && !root.changing
                onClicked: root.newChat()
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.errorText || (!root.connected ? Translation.tr("Start the assistant to open saved chats")
                : root.busy ? Translation.tr("Wait for the reply before switching chats") : "")
            color: root.errorText ? Appearance.colors.colError : Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            StyledText {
                anchors.centerIn: parent
                width: parent.width - 20
                visible: root.loading || root.sessions.length === 0
                text: Translation.tr(root.loading ? "Loading chats…" : "No saved chats")
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            ListView {
                id: list
                objectName: "voiceHistoryList"
                anchors.fill: parent
                visible: !root.loading
                clip: true
                spacing: 6
                model: root.sessions
                ScrollBar.vertical: ScrollBar {}
                delegate: RippleButton {
                    id: entry
                    objectName: "voiceHistoryRow"
                    required property var modelData
                    readonly property bool current: modelData.session_id === root.currentSessionId
                    width: list.width - 8
                    height: 72
                    implicitHeight: 72
                    padding: 10
                    clip: true
                    buttonRadius: Appearance.rounding.normal
                    enabled: root.connected && !root.busy && !root.changing
                    opacity: enabled ? 1 : 0.65
                    buttonColor: current ? Appearance.colors.colSecondaryContainer
                        : hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    onClicked: root.selected(modelData.session_id)
                    contentItem: Item {
                        clip: true
                        StyledText {
                            id: title
                            objectName: "voiceHistoryTitle"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: entry.current ? 24 : 0
                            height: 24
                            text: String(entry.modelData.title || Translation.tr("New chat")).replace(/\s+/g, " ").trim()
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            visible: entry.current
                            text: "check_circle"
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: title.bottom
                            anchors.topMargin: 4
                            height: 18
                            text: String(entry.modelData.started_at || "").replace("T", " ").slice(0, 16)
                                + " · " + Translation.tr("%1 messages").arg(entry.modelData.count)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
