.pragma library

function modelsUrl(model) {
    var endpoint = String(model.endpoint || "").split("?")[0].replace(/\/+$/, "");
    if ((model.api_format || "openai") === "gemini") {
        if (/\/models\/[^/]+$/.test(endpoint)) return endpoint.replace(/\/models\/[^/]+$/, "/models");
        return /\/models$/.test(endpoint) ? endpoint : "";
    }
    if (/\/(chat\/completions|responses|completions)$/.test(endpoint))
        return endpoint.replace(/\/(chat\/completions|responses|completions)$/, "/models");
    if (/\/models$/.test(endpoint)) return endpoint;
    return "";
}

function connectionId(model) {
    return (model.api_format || "openai") + "|" + modelsUrl(model) + "|" + (model.key_id || "");
}

function parsePage(payload, format) {
    if (payload.error) throw new Error("The provider could not list models.");
    var rows = format === "gemini" ? payload.models : payload.data;
    if (!Array.isArray(rows)) throw new Error("The provider returned an invalid model catalog.");
    return {
        models: rows.filter(function(row) {
            return row && (row.id || row.name) && (format !== "gemini"
                || !row.supportedGenerationMethods || row.supportedGenerationMethods.includes("generateContent"));
        }).map(function(row) {
            var id = String(row.id || row.name).replace(/^models\//, "");
            return { id: id, name: String(row.displayName || row.name || id).replace(/^models\//, "") };
        }),
        next: format === "gemini" ? (payload.nextPageToken || "")
            : payload.has_more && rows.length ? String(payload.last_id || rows[rows.length - 1].id || "") : ""
    };
}

function pageUrl(url, format, token) {
    if (!token) return url;
    return url + (url.includes("?") ? "&" : "?")
        + (format === "gemini" ? "pageToken=" : "after=") + encodeURIComponent(token);
}

function modelDefinition(seed, remote) {
    var endpoint = seed.endpoint;
    if ((seed.api_format || "openai") === "gemini")
        endpoint = endpoint.replace(/\/models\/[^/?]+/, "/models/" + remote.id + ":streamGenerateContent");
    return {
        name: remote.name, icon: seed.icon, description: seed.description,
        homepage: seed.homepage, endpoint: endpoint, model: remote.id,
        requires_key: seed.requires_key, key_id: seed.key_id,
        key_get_link: seed.key_get_link, key_get_description: seed.key_get_description,
        api_format: seed.api_format || "openai", extraParams: {}
    };
}
