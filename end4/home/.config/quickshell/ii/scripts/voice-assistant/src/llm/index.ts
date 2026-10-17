import type { ChatMessage, ChatMessageContentPart, Config, LlmResponse } from '../types'
import { getSystemPrompt } from '../config/prompts'
import { getSharedApiKey } from './keyring'

export async function processCommandWithLLM(
  userText: string | ChatMessageContentPart[],
  history: ChatMessage[],
  config: Config,
): Promise<{ text: string, model: string | null, tokensIn: number | null, tokensOut: number | null }> {
  const systemPrompt = getSystemPrompt(config.skillsProfile, config.customPrompt)
  const llm = { ...config.llm }
  const apiKey = llm.credentialsSource === 'quickshell'
    ? llm.requiresKey === false ? '' : await getSharedApiKey(llm.keyId || '')
    : llm.apiKey

  const apiUrl = llm.provider === 'ollama'
    ? (llm.apiUrl.endsWith('/v1') ? llm.apiUrl : `${llm.apiUrl}/v1`)
    : llm.apiUrl

  const gemini = llm.apiFormat === 'gemini' || llm.provider === 'gemini'
  const endpoint = (llm.endpoint || `${apiUrl.replace(/\/$/, '')}/chat/completions`)
    .replace(':streamGenerateContent', ':generateContent')
  const headers = {
    'Content-Type': 'application/json',
    ...(apiKey ? gemini ? { 'x-goog-api-key': apiKey } : { Authorization: `Bearer ${apiKey}` } : {}),
  }

  const messages: ChatMessage[] = [
    { role: 'system', content: systemPrompt },
    ...history,
    { role: 'user', content: userText },
  ]

  const res = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify(gemini ? {
      ...llm.extraParams,
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents: messages.filter(message => message.role !== 'system').map(message => ({
        role: message.role === 'assistant' ? 'model' : 'user',
        parts: typeof message.content === 'string' ? [{ text: message.content }] : (message.content || []).map(part => {
          if (part.type === 'text')
            return { text: part.text || '' }
          const match = /^data:([^;]+);base64,(.+)$/.exec(part.image_url?.url || '')
          if (!match)
            throw new Error('Для Gemini требуется изображение в формате data URL.')
          return { inline_data: { mime_type: match[1], data: match[2] } }
        }),
      })),
    } : {
      ...llm.extraParams,
      model: llm.model,
      messages,
      stream: false,
    }),
  })

  if (!res.ok)
    throw new Error(`API Error: ${res.status} ${res.statusText}`)

  if (gemini) {
    const data = await res.json() as {
      candidates?: { content?: { parts?: { text?: string }[] } }[]
      usageMetadata?: { promptTokenCount?: number, candidatesTokenCount?: number }
      modelVersion?: string
    }
    const text = data.candidates?.[0]?.content?.parts?.map(part => part.text || '').join('')
    if (!text)
      throw new Error('Модель не вернула текстовый ответ.')
    return {
      text,
      model: data.modelVersion || llm.model,
      tokensIn: data.usageMetadata?.promptTokenCount ?? null,
      tokensOut: data.usageMetadata?.candidatesTokenCount ?? null,
    }
  }
  const data = await res.json() as LlmResponse
  const message = data.choices[0]!.message

  let textContent = ''
  if (typeof message.content === 'string') {
    textContent = message.content
  }
  else if (Array.isArray(message.content)) {
    textContent = message.content.find(c => c.type === 'text')?.text || 'Готово'
  }

  return {
    text: textContent || 'Готово',
    model: data.model || llm.model || null,
    tokensIn: data.usage?.prompt_tokens ?? null,
    tokensOut: data.usage?.completion_tokens ?? null,
  }
}
