import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebSockets
import Quickshell.Io

Item {
    id: root

    property string serviceState: "unknown"
    property bool actionPending: false
    property bool pendingTarget: false
    property string actionPhase: ""
    property string errorText: ""
    property bool socketEnabled: true
    property bool isPaused: false
    property string speechInteractionId: ""
    property string activeInteractionId: ""
    readonly property string selectedModelId: Persistent.states.voiceAssistant.model
    readonly property var selectedModel: Ai.models[selectedModelId] || null
    readonly property var modelOptions: Object.keys(Ai.models).filter(id =>
        ["openai", "mistral", "gemini"].indexOf(Ai.models[id].api_format || "openai") >= 0
    ).map(id => ({ modelId: id, name: Ai.models[id].name }))
    readonly property bool modelHasKey: selectedModel && (!selectedModel.requires_key
        || (Ai.apiKeysLoaded && (Ai.apiKeys[selectedModel.key_id] || "").length > 0))
    property bool modelConfigured: false
    property var sessions: []
    property string currentSessionId: ""
    property bool historyOpen: false
    property bool historyLoading: false
    property bool sessionChanging: false
    property bool sessionBusy: false
    property string historyError: ""

    function openHistory() {
        historyOpen = true
        historyError = ""
        historyLoading = sendCommand("get_sessions")
    }

    function chooseSession(sessionId) {
        if (sessionChanging || sessionBusy)
            return
        historyError = ""
        sessionChanging = sendCommand(sessionId ? "load_session" : "new_session",
            sessionId ? { sessionId: sessionId } : {})
    }
    readonly property bool serviceActive: serviceState === "active"
    readonly property bool connected: assistantSocket.status === WebSocket.Open
    readonly property bool speechInProgress: speechInteractionId.length > 0
    onSelectedModelIdChanged: {
        modelConfigured = false
        syncModel()
    }
    onModelOptionsChanged: Qt.callLater(initializeModel)

    function initializeModel() {
        if (!Persistent.ready || !Config.ready)
            return
        if (!Persistent.states.voiceAssistant.model)
            Persistent.states.voiceAssistant.model = Ai.currentModelId || (modelOptions[0]?.modelId || "")
        syncModel()
    }

    function syncModel() {
        if (!connected || !selectedModel)
            return
        sendCommand("configure_llm", {
            shellModelId: selectedModelId,
            model: selectedModel.model,
            endpoint: selectedModel.endpoint,
            keyId: selectedModel.key_id,
            requiresKey: selectedModel.requires_key,
            apiFormat: selectedModel.api_format || "openai",
            extraParams: selectedModel.extraParams || {}
        })
    }

    Connections {
        target: Persistent
        function onReadyChanged() { root.initializeModel() }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.initializeModel() }
    }
    onServiceActiveChanged: {
        if (!serviceActive) {
            reconnectTimer.stop()
            socketEnabled = true
            isPaused = false
            speechInteractionId = ""
            activeInteractionId = ""
            historyLoading = false
            sessionChanging = false
            sessionBusy = false
        }
    }

    function refreshServiceState() {
        if (!statusProcess.running && !failedStatusProcess.running)
            statusProcess.running = true
    }

    function setServiceState(enabled) {
        if (actionPending)
            return
        actionPending = true
        pendingTarget = enabled
        actionPhase = "reload"
        errorText = ""
        actionProcess.command = ["systemctl", "--user", "daemon-reload"]
        actionProcess.running = true
    }

    function sendCommand(action, extra) {
        if (!connected)
            return false
        assistantSocket.sendTextMessage(JSON.stringify(Object.assign({ action: action }, extra || {})))
        return true
    }

    function sendChat() {
        const message = chatInput.text.trim()
        if (!message || !modelConfigured || !modelHasKey)
            return
        const id = "quickshell-" + Date.now() + "-" + Math.random().toString(36).slice(2)
        if (sendCommand("user_message", { text: message, id: id }))
            chatInput.text = ""
    }

    function findInteraction(id) {
        if (!id)
            return -1
        for (let index = 0; index < interactions.count; index++) {
            if (interactions.get(index).interactionId === id)
                return index
        }
        return -1
    }

    function handleMessage(rawMessage) {
        let payload
        try {
            payload = JSON.parse(rawMessage.trim())
        } catch (error) {
            console.warn("Voice Assistance: invalid WebSocket message", error)
            return
        }
        if (payload.state === "paused_state") {
            isPaused = !!payload.isPaused
            return
        }
        if (payload.state === "llm_configured") {
            modelConfigured = payload.shellModelId === selectedModelId
            errorText = ""
            return
        }
        if (payload.state === "settings_error") {
            modelConfigured = false
            errorText = payload.message || ""
            return
        }
        if (payload.state === "sessions_list") {
            sessions = payload.sessions || []
            historyLoading = false
            sessionBusy = !!payload.busy
            return
        }
        if (payload.state === "session_activity") {
            sessionBusy = !!payload.busy
            return
        }
        if (payload.state === "session_error") {
            historyError = payload.message || ""
            sessionChanging = false
            return
        }
        if (payload.state === "session_loaded") {
            currentSessionId = payload.sessionId || ""
            interactions.clear()
            for (const item of payload.history || []) {
                interactions.append({
                    interactionId: String(item.id),
                    request: item.user_input || "",
                    response: item.assistant_response || "",
                    phase: item.status === "ok" ? "success" : "error",
                    modelName: item.llm_model || ""
                })
            }
            activeInteractionId = ""
            speechInteractionId = ""
            errorText = ""
            if (sessionChanging)
                historyOpen = false
            sessionChanging = false
            historyLoading = false
            historyError = ""
            Qt.callLater(() => messageList.positionViewAtEnd())
            return
        }
        if (!["listening", "thinking", "success", "error", "sleeping"].includes(payload.state))
            return

        const id = String(payload.id || activeInteractionId || "")
        let index = findInteraction(id)
        if (payload.state === "sleeping") {
            if (index >= 0)
                interactions.remove(index)
            if (activeInteractionId === id)
                activeInteractionId = ""
            if (speechInteractionId === id)
                speechInteractionId = ""
            return
        }

        const interactionId = id || "event-" + Date.now()
        if (index < 0) {
            interactions.append({
                interactionId: interactionId,
                request: payload.text && payload.text !== "Осмысливаю..." ? payload.text : "",
                response: payload.finalResponse || "",
                phase: payload.state,
                modelName: payload.llm_model || ""
            })
        } else {
            if (payload.text && payload.text !== "Осмысливаю...")
                interactions.setProperty(index, "request", payload.text)
            if (payload.finalResponse)
                interactions.setProperty(index, "response", payload.finalResponse)
            if (payload.llm_model)
                interactions.setProperty(index, "modelName", payload.llm_model)
            interactions.setProperty(index, "phase", payload.state)
        }
        if (payload.state === "listening" || payload.state === "thinking")
            activeInteractionId = interactionId
        else if (activeInteractionId === interactionId)
            activeInteractionId = ""
        if (payload.state === "listening")
            speechInteractionId = interactionId
        else if (speechInteractionId === interactionId)
            speechInteractionId = ""
        Qt.callLater(() => messageList.positionViewAtEnd())
    }

    Component.onCompleted: {
        refreshServiceState()
        initializeModel()
    }

    Process {
        id: statusProcess
        command: ["systemctl", "--user", "is-active", "--quiet", "voice-assistant.service"]
        onExited: (exitCode, exitStatus) => {
            if (!root)
                return
            if (exitCode === 3)
                failedStatusProcess.running = true
            else
                root.serviceState = exitCode === 0 ? "active" : "unknown"
        }
    }

    Process {
        id: failedStatusProcess
        command: ["systemctl", "--user", "is-failed", "--quiet", "voice-assistant.service"]
        onExited: (exitCode, exitStatus) => {
            if (root)
                root.serviceState = exitCode === 0 ? "failed" : "inactive"
        }
    }

    Process {
        id: actionProcess
        onExited: (exitCode, exitStatus) => {
            if (root.actionPhase === "reload" && exitCode === 0) {
                root.actionPhase = root.pendingTarget ? "reset" : "change"
                actionProcess.command = root.pendingTarget
                    ? ["systemctl", "--user", "reset-failed", "voice-assistant.service"]
                    : ["systemctl", "--user", "stop", "voice-assistant.service"]
                actionProcess.running = true
                return
            }
            if (root.actionPhase === "reset") {
                root.actionPhase = "change"
                actionProcess.command = ["systemctl", "--user", "start", "voice-assistant.service"]
                actionProcess.running = true
                return
            }
            root.actionPending = false
            root.actionPhase = ""
            if (exitCode !== 0)
                root.errorText = Translation.tr("Could not change the assistant service state.")
            root.refreshServiceState()
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: root.refreshServiceState()
    }

    WebSocket {
        id: assistantSocket
        url: "ws://127.0.0.1:8765"
        active: root.serviceActive && root.socketEnabled
        onStatusChanged: (status) => {
            if (status === WebSocket.Open) {
                root.errorText = ""
                root.initializeModel()
                root.sendCommand("get_current_session")
            } else if (root.serviceActive && (status === WebSocket.Closed || status === WebSocket.Error)) {
                root.modelConfigured = false
                root.historyLoading = false
                root.sessionChanging = false
                root.socketEnabled = false
                reconnectTimer.restart()
            }
        }
        onTextMessageReceived: message => root.handleMessage(message)
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        onTriggered: root.socketEnabled = true
    }

    ListModel { id: interactions }


    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: serviceRow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            RowLayout {
                id: serviceRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                MaterialSymbol {
                    text: "mic"
                    iconSize: 25
                    color: root.connected && !root.isPaused ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Voice Assistance")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.actionPending ? Translation.tr(root.pendingTarget ? "Starting…" : "Stopping…")
                            : root.connected ? Translation.tr(root.isPaused ? "Paused" : "Listening")
                            : root.serviceActive ? Translation.tr("Connecting…")
                            : root.serviceState === "failed" ? Translation.tr("Service failed")
                            : root.serviceState === "inactive" ? Translation.tr("Stopped") : Translation.tr("Status unavailable")
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                VoiceActionButton {
                    Layout.minimumHeight: 32
                    Layout.preferredHeight: 32
                    Layout.maximumHeight: 32
                    padding: 6
                    actionIcon: "history"
                    buttonText: Translation.tr("History")
                    enabled: root.connected
                    onClicked: {
                        if (root.historyOpen)
                            root.historyOpen = false
                        else
                            root.openHistory()
                    }
                }
                StyledSwitch {
                    checked: root.actionPending ? root.pendingTarget : root.serviceActive
                    enabled: !root.actionPending
                    onClicked: root.setServiceState(!root.serviceActive)
                }
            }
        }

        RowLayout {
            id: voiceControls
            visible: !root.historyOpen
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.minimumHeight: 40
            Layout.preferredHeight: 40
            Layout.maximumHeight: 40
            spacing: 8
            VoiceActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                actionIcon: root.isPaused ? "play_arrow" : "pause"
                buttonText: Translation.tr(root.isPaused ? "Resume" : "Pause")
                ToolTip.visible: hovered
                ToolTip.text: Translation.tr(root.isPaused ? "Resume listening" : "Pause listening")
                Layout.preferredHeight: 40
                enabled: root.connected
                onClicked: root.sendCommand("toggle_pause")
            }
            VoiceActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                actionIcon: "send"
                buttonText: Translation.tr("Send")
                ToolTip.visible: hovered
                ToolTip.text: Translation.tr("Send speech now")
                Layout.preferredHeight: 40
                enabled: root.connected && root.speechInProgress
                onClicked: root.sendCommand("commit")
            }
            VoiceActionButton {
                Layout.preferredWidth: 44
                Layout.minimumWidth: 44
                Layout.preferredHeight: 40
                actionIcon: "delete_sweep"
                enabled: interactions.count > 0 || root.errorText.length > 0
                Accessible.name: Translation.tr("Clear")
                ToolTip.visible: hovered
                ToolTip.text: Translation.tr("Clear")
                ToolTip.delay: 400
                onClicked: {
                    interactions.clear()
                    root.errorText = ""
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }

        Item {
            id: voiceMessages
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            VoiceHistory {
                anchors.fill: parent
                visible: root.historyOpen
                sessions: root.sessions
                currentSessionId: root.currentSessionId
                connected: root.connected
                loading: root.historyLoading
                changing: root.sessionChanging
                busy: root.sessionBusy
                errorText: root.historyError
                onBack: root.historyOpen = false
                onNewChat: root.chooseSession("")
                onSelected: sessionId => root.chooseSession(sessionId)
            }
            StyledText {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: !root.historyOpen && interactions.count === 0
                text: root.connected ? Translation.tr("Waiting for speech or a chat message…")
                    : Translation.tr("Start the assistant to see messages here.")
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            ListView {
                id: messageList
                visible: !root.historyOpen
                anchors.fill: parent
                clip: true
                spacing: 10
                model: interactions
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property string request
                    required property string response
                    required property string phase
                    required property string modelName
                    width: messageList.width - 10
                    implicitHeight: messageContent.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    ColumnLayout {
                        id: messageContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            MaterialSymbol {
                                id: interactionStatusIcon
                                text: phase === "listening" ? "graphic_eq" : phase === "thinking" ? "progress_activity"
                                    : phase === "error" ? "error" : "check_circle"
                                iconSize: 18
                                color: phase === "error" ? Appearance.colors.colError : Appearance.colors.colPrimary
                                RotationAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    running: interactionStatusIcon.visible && phase === "thinking"
                                    onStopped: interactionStatusIcon.rotation = 0
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: request || Translation.tr("Listening…")
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                            }
                        }
                        StyledTextArea {
                            Layout.fillWidth: true
                            visible: response.length > 0
                            text: response
                            color: phase === "error" ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                            wrapMode: TextEdit.Wrap
                            textFormat: phase === "error" ? TextEdit.PlainText : TextEdit.MarkdownText
                            readOnly: true
                            selectByMouse: true
                            padding: 0
                            background: null
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: modelName.length > 0
                            text: modelName
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        Rectangle {
            id: voiceComposer
            visible: !root.historyOpen
            Layout.fillWidth: true
            implicitHeight: composer.implicitHeight + 10
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: composer
                anchors.fill: parent
                anchors.margins: 5
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(36, Math.min(120, chatInput.implicitHeight))
                        clip: true
                        StyledTextArea {
                            id: chatInput
                            renderType: Text.QtRendering
                            font.hintingPreference: Font.PreferNoHinting
                            width: parent.width
                            placeholderText: Translation.tr("Message Voice Assistance…")
                            wrapMode: TextArea.Wrap
                            background: null
                            padding: 8
                            enabled: root.connected
                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true
                                    root.sendChat()
                                }
                            }
                        }
                    }
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        enabled: root.connected && root.modelConfigured && root.modelHasKey && chatInput.text.trim().length > 0
                        Accessible.name: Translation.tr("Send")
                        onClicked: root.sendChat()
                        contentItem: MaterialSymbol {
                            text: "arrow_upward"
                            iconSize: 21
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledComboBox {
                        id: voiceModelSelector
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 30
                        buttonIcon: "neurology"
                        model: root.modelOptions
                        textRole: "name"
                        valueRole: "modelId"
                        currentIndex: root.modelOptions.findIndex(option => option.modelId === root.selectedModelId)
                        displayText: root.selectedModel?.name || Translation.tr("Choose a voice model")
                        contentItem: Item {
                            implicitWidth: compactModelRow.implicitWidth + 44
                            implicitHeight: compactModelRow.implicitHeight
                            RowLayout {
                                id: compactModelRow
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 40
                                spacing: 6
                                MaterialSymbol {
                                    text: "neurology"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: voiceModelSelector.displayText
                                    renderType: Text.QtRendering
                                    font.hintingPreference: Font.PreferNoHinting
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        ToolTip.visible: hovered
                        ToolTip.text: Translation.tr("Model for Voice Assistance only")
                        onActivated: index => {
                            Persistent.states.voiceAssistant.model = root.modelOptions[index].modelId
                        }
                    }
                    MaterialSymbol {
                        text: root.modelHasKey ? "key" : "key_off"
                        iconSize: 16
                        color: root.modelHasKey ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        ToolTip.visible: keyHover.hovered
                        ToolTip.text: Translation.tr(root.modelHasKey ? "Uses the API key saved in Quickshell" : "Set this provider's API key in Intelligence")
                        HoverHandler { id: keyHover }
                    }
                    RippleButton {
                        buttonText: "/clear"
                        implicitHeight: 30
                        padding: 6
                        contentItem: StyledText {
                            text: "/clear"
                            renderType: Text.QtRendering
                            font.hintingPreference: Font.PreferNoHinting
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colOnLayer1
                        }
                        enabled: interactions.count > 0 || root.errorText.length > 0
                        onClicked: {
                            interactions.clear()
                            root.errorText = ""
                        }
                    }
                }
            }
        }
    }
}
