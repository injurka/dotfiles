pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common

RippleButton {
    id: root
    property string selectedModelId: ""
    property alias popup: modelPopup
    property alias searchText: searchField.text
    property string connectionId: ""
    signal modelSelected(string modelId)
    readonly property var connections: AiModelCatalog.connections
    readonly property var connection: connections.find(item => item.id === connectionId) || null
    readonly property var entry: AiModelCatalog.cache[connectionId] || ({ models: [], loading: false, error: "" })
    readonly property var results: {
        if (!connection) return [];
        const rows = new Map();
        if (!entry.fetchedAt) Object.keys(Ai.models).forEach(id => {
            const model = Ai.models[id];
            if (AiModelCatalog.connectionForModel(id) === connectionId)
                rows.set(model.model, { id: model.model, name: model.name });
        });
        (entry.models || []).forEach(model => rows.set(model.id, model));
        const query = searchField.text.trim().toLowerCase();
        return Array.from(rows.values()).filter(model => !query
            || (model.name + " " + model.id).toLowerCase().includes(query));
    }
    implicitHeight: 40
    implicitWidth: 240
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    Accessible.name: Translation.tr("Model") + ": " + (Ai.models[selectedModelId]?.name || "")
    downAction: () => modelPopup.visible ? modelPopup.close() : modelPopup.open()
    contentItem: RowLayout {
        spacing: 8
        MaterialSymbol {
            text: "neurology"
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            Layout.fillWidth: true
            text: Ai.models[root.selectedModelId]?.name || Translation.tr("Model")
            color: Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideRight
        }
        MaterialSymbol {
            text: modelPopup.visible ? "expand_less" : "expand_more"
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    function choose(model) {
        if (!root.connection || !model) return;
        const id = AiModelCatalog.registerModel(root.connection, model);
        root.modelSelected(id);
        modelPopup.close();
    }

    Timer {
        id: searchDelay
        interval: 300
        onTriggered: AiModelCatalog.fetch(root.connection)
    }
    Connections {
        target: Ai
        function onApiKeysLoadedChanged() { if (modelPopup.visible) searchDelay.restart(); }
        function onApiKeysChanged() { if (modelPopup.visible) searchDelay.restart(); }
    }

    Popup {
        id: modelPopup
        y: root.height + 4
        width: Math.max(root.width, 320)
        margins: 8
        padding: 12
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            if (!Ai.apiKeysLoaded) KeyringStorage.fetchKeyringData();
            searchField.text = "";
            const selectedConnection = AiModelCatalog.connectionForModel(root.selectedModelId);
            root.connectionId = root.connections.some(item => item.id === selectedConnection)
                ? selectedConnection : (root.connections.find(item => item.hasKey)?.id || root.connections[0]?.id || "");
            AiModelCatalog.fetch(root.connection);
            Qt.callLater(() => searchField.forceActiveFocus());
        }
        background: Rectangle {
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        contentItem: ColumnLayout {
            clip: true
            spacing: 8
            StyledComboBox {
                Layout.fillWidth: true
                visible: root.connections.length > 1
                buttonIcon: "cloud"
                model: root.connections
                textRole: "name"
                valueRole: "id"
                currentIndex: root.connections.findIndex(item => item.id === root.connectionId)
                onActivated: index => {
                    root.connectionId = root.connections[index].id;
                    modelList.currentIndex = 0;
                    AiModelCatalog.fetch(root.connection);
                    searchField.forceActiveFocus();
                }
            }
            RowLayout {
                Layout.fillWidth: true
                MaterialTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search all models…")
                    onTextChanged: {
                        modelList.currentIndex = 0;
                        searchDelay.restart();
                    }
                    Keys.onDownPressed: modelList.currentIndex = Math.min(modelList.currentIndex + 1, root.results.length - 1)
                    Keys.onUpPressed: modelList.currentIndex = Math.max(0, modelList.currentIndex - 1)
                    onAccepted: root.choose(root.results[Math.max(0, modelList.currentIndex)])
                }
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    enabled: !root.entry.loading
                    Accessible.name: Translation.tr("Refresh models")
                    downAction: () => AiModelCatalog.fetch(root.connection, true)
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            color: Appearance.colors.colOnLayer2
                            iconSize: 20
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.entry.loading || !!root.entry.error || root.connections.length === 0
                text: root.entry.loading ? Translation.tr("Loading models…") : root.connections.length === 0
                    ? Translation.tr("No AI connections configured.") : root.entry.error || ""
                color: root.entry.error ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
            }
            ListView {
                id: modelList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 280)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.results
                currentIndex: 0
                ScrollBar.vertical: ScrollBar {}
                delegate: RippleButton {
                    required property var modelData
                    required property int index
                    width: modelList.width
                    implicitHeight: 54
                    buttonRadius: Appearance.rounding.small
                    colBackground: modelList.currentIndex === index ? Appearance.colors.colSecondaryContainer : "transparent"
                    downAction: () => root.choose(modelData)
                    contentItem: ColumnLayout {
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: modelData.name !== modelData.id
                            text: modelData.id
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            StyledText {
                visible: !root.entry.loading && root.results.length === 0
                text: Translation.tr("No models found.")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
