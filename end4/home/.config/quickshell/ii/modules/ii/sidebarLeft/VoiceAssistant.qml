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
    readonly property var modelOptions: {
        const preferred = ["gemini-3.1-flash-lite", "mistral-small-4"]
        const retired = ["gemini-2.5-flash", "gemini-3-flash", "mistral-medium-3"]
        const ids = Object.keys(Ai.models).filter(id => {
            const model = Ai.models[id]
            return !retired.includes(id)
                && ["openai", "mistral", "gemini"].includes(model.api_format || "openai")
                && !/(?:\br1\b|distill|\breasoner\b)/i.test(model.name + " " + model.model)
        })
        return ids.sort((a, b) => {
            const rank = id => preferred.includes(id) ? preferred.indexOf(id) : preferred.length
            return rank(a) - rank(b)
        }).map(id => ({ modelId: id, name: Ai.models[id].name }))
    }
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
        const current = Persistent.states.voiceAssistant.model
        if (!current) {
            const available = modelOptions.find(option => {
                const model = Ai.models[option.modelId]
                return !model.requires_key || (Ai.apiKeysLoaded && (Ai.apiKeys[model.key_id] || "").length > 0)
            })
            Persistent.states.voiceAssistant.model = available?.modelId || modelOptions[0]?.modelId || ""
        }
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
                    implicitHeight: messageContent.implicitHeight + 32
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    ColumnLayout {
                        id: messageContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 14
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            MaterialSymbol {
                                id: interactionStatusIcon
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 2
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
                                text: request.replace(/\s*\n\s*/g, " ").trim() || Translation.tr("Listening…")
                                color: Appearance.colors.colSubtext
                                textFormat: Text.PlainText
                                renderType: Text.QtRendering
                                font.hintingPreference: Font.PreferNoHinting
                                lineHeight: 1.35
                                wrapMode: Text.Wrap
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            visible: response.length > 0
                            color: Appearance.colors.colLayer3
                        }
                        VoiceResponseText {
                            Layout.fillWidth: true
                            visible: response.length > 0
                            markdown: response
                            error: phase === "error"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: modelName.length > 0
                            text: {
                                const model = Object.values(Ai.models).find(item => item.model === modelName)
                                return model?.name || modelName
                            }
                            textFormat: Text.PlainText
                            renderType: Text.QtRendering
                            font.hintingPreference: Font.PreferNoHinting
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
            // Match AiChat's four-pixel outer inset within this twelve-pixel layout.
            Layout.leftMargin: -8
            Layout.rightMargin: -8
            Layout.bottomMargin: -8
            property real spacing: 5
            implicitHeight: Math.max(voiceInputRow.implicitHeight + voiceComposerControls.implicitHeight
                + voiceComposerControls.anchors.bottomMargin + spacing, 45)
            radius: Appearance.rounding.normal - 4
            color: Appearance.colors.colLayer2
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: voiceInputRow
                anchors {
                    bottom: voiceComposerControls.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 5
                }
                spacing: 0

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3/5, chatInput.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: chatInput
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg("/")
                        background: null
                        enabled: root.connected
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && !(event.modifiers & Qt.ShiftModifier)) {
                                event.accepted = true
                                if (text.trim() === "/clear") {
                                    interactions.clear()
                                    root.errorText = ""
                                    clear()
                                } else if (text.trim() === "/") {
                                    voiceCommands.open()
                                } else {
                                    root.sendChat()
                                }
                            }
                        }
                    }
                }

                RippleButton {
                    id: voiceSendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: root.connected && root.modelConfigured && root.modelHasKey && chatInput.text.trim().length > 0
                    toggled: enabled
                    Accessible.name: Translation.tr("Send")
                    onClicked: {
                        if (chatInput.text.trim() === "/clear") {
                            interactions.clear()
                            root.errorText = ""
                            chatInput.clear()
                        } else if (chatInput.text.trim() === "/") {
                            voiceCommands.open()
                        } else {
                            root.sendChat()
                        }
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: voiceSendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "arrow_upward"
                    }
                }
            }

            RowLayout {
                id: voiceComposerControls
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 5
                    leftMargin: 10
                    rightMargin: 5
                }
                spacing: 4

                AiModelSelector {
                    id: voiceModelSelector
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 34
                    selectedModelId: root.selectedModelId
                    ToolTip.visible: hovered
                    ToolTip.text: Translation.tr("Model for Voice Assistance only")
                    onModelSelected: modelId => Persistent.states.voiceAssistant.model = modelId
                }

                ApiInputBoxIndicator {
                    icon: "service_toolbox"
                    text: "Functions"
                    tooltipText: Translation.tr("Voice Assistance")
                }

                ButtonGroup {
                    padding: 0
                    ApiCommandButton {
                        buttonText: "/"
                        downAction: () => voiceCommands.open()
                        Menu {
                            id: voiceCommands
                            y: -height
                            MenuItem {
                                text: Translation.tr("Choose a voice model")
                                onTriggered: voiceModelSelector.popup.open()
                            }
                            MenuItem {
                                text: "/clear"
                                onTriggered: {
                                    interactions.clear()
                                    root.errorText = ""
                                    chatInput.clear()
                                }
                            }
                        }
                    }
                    ApiCommandButton {
                        buttonText: "/clear"
                        downAction: () => {
                            interactions.clear()
                            root.errorText = ""
                            chatInput.clear()
                        }
                    }
                }
            }
        }
    }
}
