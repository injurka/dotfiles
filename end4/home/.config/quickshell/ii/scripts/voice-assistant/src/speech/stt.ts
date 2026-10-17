import type { Config } from '../types'
import { writeFileSync } from 'node:fs'
import { pcmToWav } from './wav'

export async function transcribeAudio(pcmData: Buffer, config: Config): Promise<string> {
  if (!config.stt || config.stt.provider === 'none')
    return ''

  const wavBuffer = pcmToWav(pcmData)

  // Сохраняем последний аудиозапрос в файл, чтобы ты мог его послушать (Дебаг)
  try {
    writeFileSync('/tmp/voice_assistant_debug.wav', wavBuffer)
  }
  catch {
    console.error('[Debug] Не удалось сохранить /tmp/voice_assistant_debug.wav')
  }

  // В Bun есть встроенная поддержка File/Blob/FormData для fetch запросов
  const blob = new Blob([wavBuffer], { type: 'audio/wav' })
  const formData = new FormData()

  formData.append('file', blob, 'command.wav')
  formData.append('model', config.stt.model || 'whisper-1')
  formData.append('language', 'ru')
  formData.append('temperature', '0')

  // Отключаем галлюцинации Whisper (запрещаем ему фантазировать и "отвечать")
  formData.append('temperature', '0')

  // Если в URL уже есть /inference (для whisper.cpp) или /audio/transcriptions (для OpenAI) — оставляем как есть.
  // Иначе дописываем /audio/transcriptions по умолчанию.
  const apiUrl = (config.stt.apiUrl.endsWith('/audio/transcriptions') || config.stt.apiUrl.endsWith('/inference'))
    ? config.stt.apiUrl
    : `${config.stt.apiUrl.replace(/\/$/, '')}/audio/transcriptions`

  const headers: Record<string, string> = {}
  if (config.stt.apiKey) {
    headers.Authorization = `Bearer ${config.stt.apiKey}`
  }

  const response = await fetch(apiUrl, {
    method: 'POST',
    headers,
    body: formData,
  })

  if (!response.ok) {
    throw new Error(`STT API Error: ${response.status} ${response.statusText}`)
  }

  const data = await response.json() as { text?: string }
  return data.text || ''
}
