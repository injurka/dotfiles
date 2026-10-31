pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "ai/ModelCatalog.js" as Catalog

Singleton {
    id: root
    property var cache: ({})
    property var pending: ({})
    readonly property var connections: {
        const result = [];
        const seen = new Set();
        for (const modelId of Object.keys(Ai.models)) {
            const model = Ai.models[modelId];
            const url = Catalog.modelsUrl(model);
            if (!url || !["openai", "mistral", "gemini"].includes(model.api_format || "openai")) continue;
            const id = Catalog.connectionId(model);
            if (seen.has(id)) continue;
            seen.add(id);
            const host = url.replace(/^https?:\/\//, "").split("/")[0];
            result.push({ id: id, name: (model.key_id || host) + " · " + host,
                seedId: modelId, url: url, format: model.api_format || "openai",
                hasKey: !model.requires_key || (Ai.apiKeysLoaded && (Ai.apiKeys[model.key_id]?.length || 0) > 0) });
        }
        return result;
    }

    function connectionForModel(modelId) {
        const model = Ai.models[modelId];
        return model ? Catalog.connectionId(model) : "";
    }

    function updateEntry(id, entry) {
        root.cache = Object.assign({}, root.cache, { [id]: entry });
    }

    function finish(connection, models, error) {
        const next = Object.assign({}, root.pending);
        delete next[connection.id];
        root.pending = next;
        root.updateEntry(connection.id, { models: models, loading: false, error: error,
            fetchedAt: error ? 0 : Date.now() });
    }

    function fetch(connection, force = false) {
        if (!connection || root.pending[connection.id]) return;
        const previous = root.cache[connection.id];
        if (!force && previous?.fetchedAt && Date.now() - previous.fetchedAt < 300000) return;
        if (!connection.hasKey) {
            root.updateEntry(connection.id, { models: [], loading: false,
                error: Translation.tr("Add an API key for the selected AI model first."), fetchedAt: 0 });
            return;
        }
        root.updateEntry(connection.id, { models: previous?.models || [], loading: true, error: "", fetchedAt: 0 });
        root.fetchPage(connection, "", [], new Set(), Date.now());
    }

    function fetchPage(connection, token, collected, seenTokens, started) {
        const xhr = new XMLHttpRequest();
        root.pending = Object.assign({}, root.pending, { [connection.id]: { xhr: xhr, started: started } });
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.pending[connection.id]?.xhr !== xhr) return;
            if (xhr.status < 200 || xhr.status >= 300) {
                const message = xhr.status === 401 || xhr.status === 403
                    ? Translation.tr("The provider rejected this API key.")
                    : Translation.tr("Could not load models (HTTP %1).").arg(xhr.status);
                root.finish(connection, collected, message);
                return;
            }
            try {
                const page = Catalog.parsePage(JSON.parse(xhr.responseText), connection.format);
                const combined = collected.concat(page.models);
                if (page.next) {
                    if (seenTokens.has(page.next)) throw new Error("Repeated model catalog page.");
                    seenTokens.add(page.next);
                    root.fetchPage(connection, page.next, combined, seenTokens, started);
                } else {
                    const unique = new Map();
                    combined.forEach(model => unique.set(model.id, model));
                    root.finish(connection, Array.from(unique.values()).sort((a, b) => a.name.localeCompare(b.name)), "");
                }
            } catch (error) {
                root.finish(connection, [], Translation.tr("The provider returned an invalid model catalog."));
            }
        };
        xhr.open("GET", Catalog.pageUrl(connection.url, connection.format, token));
        xhr.setRequestHeader("Accept", "application/json");
        const seed = Ai.models[connection.seedId];
        if (seed.requires_key) {
            const key = Ai.apiKeys[seed.key_id] || "";
            xhr.setRequestHeader(connection.format === "gemini" ? "x-goog-api-key" : "Authorization",
                connection.format === "gemini" ? key : "Bearer " + key);
        }
        xhr.send();
    }

    function registerModel(connection, remote) {
        for (const id of Object.keys(Ai.models)) {
            const model = Ai.models[id];
            if (Catalog.connectionId(model) === connection.id && model.model === remote.id) return id;
        }
        const seed = Ai.models[connection.seedId];
        const data = Catalog.modelDefinition(seed, remote);
        // The endpoint disambiguates providers that share the same model ID or key label.
        let hash = 2166136261;
        for (let i = 0; i < connection.id.length; i++) hash = Math.imul(hash ^ connection.id.charCodeAt(i), 16777619);
        const shellId = "catalog-" + (hash >>> 0).toString(16) + "-" + Ai.safeModelName(remote.id).toLowerCase();
        const persisted = Object.assign({ shellId: shellId }, data);
        const existing = Config.options.ai.extraModels || [];
        Config.options.ai.extraModels = existing.filter(model => model.shellId !== shellId).concat([persisted]);
        Ai.addModel(shellId, data);
        Ai.modelList = Object.keys(Ai.models);
        return shellId;
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.pending).length > 0
        onTriggered: {
            for (const id of Object.keys(root.pending)) {
                const request = root.pending[id];
                if (Date.now() - request.started < 20000) continue;
                const connection = root.connections.find(item => item.id === id);
                if (!connection) continue;
                root.finish(connection, [], Translation.tr("Loading models timed out."));
                request.xhr.abort();
            }
        }
    }
    Connections {
        target: Ai
        function onApiKeysChanged() {
            for (const request of Object.values(root.pending)) request.xhr.abort();
            root.pending = ({});
            root.cache = ({});
        }
    }
    Component.onDestruction: {
        for (const request of Object.values(root.pending)) request.xhr.abort();
    }
}
