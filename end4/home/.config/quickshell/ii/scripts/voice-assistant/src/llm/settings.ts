import type { LlmConfig } from '../types'

export function shellModelSettings(input: Record<string, unknown>): LlmConfig {
  const endpoint = typeof input.endpoint === 'string' ? input.endpoint : ''
  const url = new URL(endpoint)
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password)
    throw new Error('Некорректный адрес модели.')
  const format = input.apiFormat || 'openai'
  if (!['openai', 'mistral', 'gemini'].includes(String(format))
    || typeof input.model !== 'string' || !input.model
    || typeof input.shellModelId !== 'string' || !input.shellModelId
    || (input.requiresKey !== false && (typeof input.keyId !== 'string' || !input.keyId)))
    throw new Error('Некорректные настройки модели.')
  return {
    provider: format === 'gemini' ? 'gemini' : 'openai',
    apiKey: '',
    apiUrl: '',
    endpoint,
    model: input.model,
    shellModelId: input.shellModelId,
    credentialsSource: 'quickshell',
    keyId: typeof input.keyId === 'string' ? input.keyId : '',
    requiresKey: input.requiresKey !== false,
    apiFormat: format as LlmConfig['apiFormat'],
    extraParams: input.extraParams && typeof input.extraParams === 'object' && !Array.isArray(input.extraParams)
      ? input.extraParams as Record<string, unknown> : {},
  }
}
