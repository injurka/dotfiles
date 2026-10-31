pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions as CF
import qs.services

Scope {
    id: root

    property bool busy: false
    property bool pendingWrite: false
    property string scriptContent: ""
    property string requestFormat: "openai"
    property string requestKey: ""
    property string requestUrl: ""
    property string geminiKeySuffix: ""
    signal completed(string response, string error)

    readonly property string modelId: Persistent.states.ai.activityPlannerModel || Ai.currentModelId
    readonly property var selectedModel: Ai.models[modelId] || null
    readonly property bool available: !!selectedModel && (!selectedModel.requires_key
        || (Ai.apiKeysLoaded && (Ai.apiKeys[selectedModel.key_id]?.length || 0) > 0))
    readonly property string scriptPath: "/tmp/quickshell/ai/activity-planner.sh"

    function request(systemPrompt, userPrompt) {
        if (root.busy)
            return;

        const model = root.selectedModel;
        if (!model) {
            root.completed("", "No AI model is selected.");
            return;
        }
        if (model.requires_key && !root.available) {
            if (!Ai.apiKeysLoaded)
                KeyringStorage.fetchKeyringData();
            root.completed("", "Add an API key for the selected AI model first.");
            return;
        }

        const format = model.api_format || "openai";
        const strategy = Ai.apiStrategies[format];
        if (!strategy) {
            root.completed("", "The selected AI provider is not supported.");
            return;
        }

        let body;
        if (format === "gemini") {
            body = Object.assign({}, model.extraParams || {}, {
                contents: [{role: "user", parts: [{text: userPrompt}]}],
                system_instruction: {parts: [{text: systemPrompt}]},
                generationConfig: {temperature: 0.2, responseMimeType: "application/json"}
            });
        } else {
            body = Object.assign({}, model.extraParams || {}, {
                model: model.model,
                messages: [
                    {role: "system", content: systemPrompt},
                    {role: "user", content: userPrompt}
                ],
                stream: false,
                temperature: 0.2
            });
        }

        let endpoint = strategy.buildEndpoint(model);
        if (format === "gemini")
            endpoint = endpoint.replace("streamGenerateContent", "generateContent");
        const hasGeminiKeyTemplate = endpoint.includes("${API_KEY}");
        root.requestUrl = hasGeminiKeyTemplate ? endpoint.replace("${API_KEY}", "") : endpoint;
        root.geminiKeySuffix = hasGeminiKeyTemplate && model.requires_key
            ? (Ai.apiKeys[model.key_id] || "") : "";
        root.requestKey = model.requires_key ? (Ai.apiKeys[model.key_id] || "") : "";
        root.requestFormat = format;

        const authorization = format === "gemini"
            ? "" : strategy.buildAuthorizationHeader(Ai.apiKeyEnvVarName);
        root.scriptContent = "#!/usr/bin/env bash\nset -o pipefail\ncurl --silent --show-error --fail-with-body --no-buffer \"${REQUEST_URL}${ACTIVITY_GEMINI_KEY}\" -H 'Content-Type: application/json' "
            + authorization + " --data-binary '"
            + CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(body)) + "'\n";

        root.busy = true;
        root.pendingWrite = true;
        prepareDirectory.running = true;
    }

    function finish(response, error) {
        if (!root.busy)
            return;
        root.busy = false;
        requestTimeout.stop();
        cleanupScript.running = true;
        requestProcess.environment["API_KEY"] = "";
        requestProcess.environment["ACTIVITY_GEMINI_KEY"] = "";
        root.requestKey = "";
        root.geminiKeySuffix = "";
        root.scriptContent = "";
        root.completed(response, error);
    }

    function extractText(rawResponse) {
        const payload = JSON.parse(rawResponse);
        if (payload.error)
            throw new Error(payload.error.message || JSON.stringify(payload.error));

        if (root.requestFormat === "gemini") {
            const parts = payload.candidates?.[0]?.content?.parts || [];
            return parts.map(part => part.text || "").join("").trim();
        }

        const content = payload.choices?.[0]?.message?.content ?? payload.message?.content ?? "";
        if (Array.isArray(content))
            return content.map(part => part.text || "").join("").trim();
        return String(content).trim();
    }

    FileView {
        id: scriptWriter
        path: root.scriptPath
        onLoaded: if (root.pendingWrite) setText(root.scriptContent)
        onLoadFailed: error => {
            if (!root.pendingWrite)
                return;
            if (error === FileViewError.FileNotFound)
                setText(root.scriptContent);
            else
                root.finish("", "Could not prepare the AI request.");
        }
        onSaved: {
            if (!root.pendingWrite)
                return;
            root.pendingWrite = false;
            secureScript.running = true;
        }
        onSaveFailed: error => root.finish("", `Could not prepare the AI request: ${error}`)
    }

    Process {
        id: prepareDirectory
        command: ["bash", "-c", "mkdir -p -m 700 /tmp/quickshell/ai && chmod 700 /tmp/quickshell/ai"]
        onExited: exitCode => {
            if (!root.busy)
                return;
            if (exitCode !== 0) {
                root.finish("", "Could not prepare the private AI request directory.");
                return;
            }
            scriptWriter.reload();
        }
    }

    Process {
        id: secureScript
        command: ["chmod", "600", root.scriptPath]
        onExited: exitCode => {
            if (!root.busy)
                return;
            if (exitCode !== 0) {
                root.finish("", "Could not secure the AI request file.");
                return;
            }
            requestProcess.environment["API_KEY"] = root.requestKey;
            requestProcess.environment["REQUEST_URL"] = root.requestUrl;
            requestProcess.environment["ACTIVITY_GEMINI_KEY"] = root.geminiKeySuffix;
            requestTimeout.start();
            requestProcess.running = true;
        }
    }

    Process {
        id: requestProcess
        command: ["bash", root.scriptPath]
        stdout: StdioCollector { id: responseOutput }
        stderr: StdioCollector { id: errorOutput }
        onExited: exitCode => {
            if (!root.busy)
                return;

            const response = responseOutput.text.trim();
            const stderr = errorOutput.text.trim();
            if (exitCode !== 0) {
                root.finish("", stderr || response || "The AI request failed.");
                return;
            }
            try {
                const text = root.extractText(response);
                if (!text)
                    throw new Error("The AI returned an empty response.");
                root.finish(text, "");
            } catch (error) {
                root.finish("", error.message || "Could not read the AI response.");
            }
        }
    }

    Process {
        id: cleanupScript
        command: ["rm", "-f", root.scriptPath]
    }

    Timer {
        id: requestTimeout
        interval: 90000
        repeat: false
        onTriggered: {
            requestProcess.running = false;
            root.finish("", "The AI request timed out.");
        }
    }
}
