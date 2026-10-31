const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const catalog = {};
vm.createContext(catalog);
vm.runInContext(fs.readFileSync(path.join(__dirname,
    '../home/.config/quickshell/ii/services/ai/ModelCatalog.js'), 'utf8').replace(/^\.pragma library\s*/, ''), catalog);
const plain = value => JSON.parse(JSON.stringify(value));

test('models endpoints retain provider prefixes and remove generation paths', () => {
    assert.equal(catalog.modelsUrl({ endpoint: 'https://provider.example/api/v1/chat/completions?key=unused' }),
        'https://provider.example/api/v1/models');
    assert.equal(catalog.modelsUrl({ endpoint: 'https://provider.example/v1/responses/' }),
        'https://provider.example/v1/models');
    assert.equal(catalog.modelsUrl({ api_format: 'gemini',
        endpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-a:streamGenerateContent' }),
        'https://generativelanguage.googleapis.com/v1beta/models');
    assert.equal(catalog.modelsUrl({ endpoint: 'http://localhost:11434/v1/chat/completions' }),
        'http://localhost:11434/v1/models');
    assert.equal(catalog.modelsUrl({ endpoint: 'https://provider.example/unknown' }), '');
    assert.equal(catalog.modelsUrl({ api_format: 'gemini', endpoint: 'https://provider.example/unknown' }), '');
});

test('connections isolate the same model ID across providers and credentials', () => {
    const seed = { endpoint: 'https://a.example/v1/chat/completions', key_id: 'a' };
    assert.notEqual(catalog.connectionId(seed),
        catalog.connectionId({ ...seed, endpoint: 'https://b.example/v1/chat/completions' }));
    assert.notEqual(catalog.connectionId(seed), catalog.connectionId({ ...seed, key_id: 'b' }));
});

test('OpenAI and Gemini catalogs parse IDs, display names and pagination', () => {
    assert.deepEqual(plain(catalog.parsePage({ data: [{ id: 'model/a' }], has_more: true }, 'openai')),
        { models: [{ id: 'model/a', name: 'model/a' }], next: 'model/a' });
    assert.deepEqual(plain(catalog.parsePage({ models: [
        { name: 'models/gemini-a', displayName: 'Gemini A', supportedGenerationMethods: ['generateContent'] },
        { name: 'models/embedding', supportedGenerationMethods: ['embedContent'] }
    ], nextPageToken: 'next/=' }, 'gemini')),
    { models: [{ id: 'gemini-a', name: 'Gemini A' }], next: 'next/=' });
    assert.equal(catalog.pageUrl('https://a/v1/models', 'gemini', 'next/='),
        'https://a/v1/models?pageToken=next%2F%3D');
    assert.throws(() => catalog.parsePage({ data: {} }, 'openai'), /invalid/);
    assert.throws(() => catalog.parsePage({ error: { message: 'private response' } }, 'openai'), /could not list/);
});

test('selected remote models use their own endpoint ID without seed-specific parameters', () => {
    const definition = plain(catalog.modelDefinition({
        endpoint: 'https://a/v1beta/models/old:streamGenerateContent',
        api_format: 'gemini', key_id: 'gemini', requires_key: true,
        extraParams: { thinkingConfig: { thinkingLevel: 'minimal' } }
    }, { id: 'new-model', name: 'New Model' }));
    assert.equal(definition.endpoint, 'https://a/v1beta/models/new-model:streamGenerateContent');
    assert.equal(definition.model, 'new-model');
    assert.equal(definition.key_id, 'gemini');
    assert.deepEqual(definition.extraParams, {});
    assert.equal(Object.hasOwn(definition, 'apiKey'), false);
});
