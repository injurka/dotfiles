import type { VoskResult } from './types'
import { CString, ptr } from 'bun:ffi'
import { config, saveConfig } from './config'
import { Assistant } from './core/assistant'
import {
  appendHistory,
  deleteMessage,
  deleteSession,
  getHistoryRaw,
  getCurrentSessionId,
  getSessionHistoryRaw,
  getSessionsList,
  setSessionId,
  startNewSession,
} from './history'
import { IPCServer } from './ipc'
import { processCommandWithLLM } from './llm'
import { shellModelSettings } from './llm/settings'
import { startMic } from './speech/mic'
import { startLocalWhisper } from './speech/local-whisper'
import { transcribeAudio } from './speech/stt'
import { libvosk, recPtr } from './speech/vosk'

const ipc = new IPCServer(config.uiMode)
export const assistant = new Assistant()
await startLocalWhisper(config)
const mic = startMic()

let isPaused = false
let currentInteractionId: string | null = null
let pendingRequests = 0

function broadcastSessionActivity() {
  ipc.broadcast({ state: 'session_activity', busy: pendingRequests > 0 })
}

function changeSession(choose: () => void) {
  if (pendingRequests > 0) {
    ipc.broadcast({ state: 'session_error', message: 'Дождитесь завершения ответа перед сменой чата.' })
    return
  }
  try {
    choose()
    assistant.reset()
    libvosk.symbols.vosk_recognizer_reset(recPtr)
    currentInteractionId = null
    const sessionId = getCurrentSessionId()
    ipc.broadcast({ state: 'session_loaded', sessionId, history: getSessionHistoryRaw(sessionId) })
  } catch {
    ipc.broadcast({ state: 'session_error', message: 'Не удалось открыть чат.' })
  }
}

// --- Bind IPC Events ---
ipc.on('action', (data) => {
  if (data.action === 'configure_llm') {
    try {
      const llm = shellModelSettings(data)
      if (JSON.stringify(config.llm) !== JSON.stringify(llm))
        saveConfig({ ...config, llm })
      ipc.broadcast({ state: 'llm_configured', shellModelId: config.llm.shellModelId })
    } catch {
      ipc.broadcast({ state: 'settings_error', message: 'Не удалось сохранить настройки модели Voice Assistance.' })
    }
  }
  else if (data.action === 'new_session') {
    changeSession(startNewSession)
    console.log('[🔌] Новая сессия начата по запросу UI/Web')
  }
  else if (data.action === 'commit') {
    assistant.forceCommit()
    console.log('[🔌] Преждевременная отправка по запросу UI/Web (forceCommit)')
  }
  else if (data.action === 'get_sessions') {
    const sessions = getSessionsList()
    ipc.broadcast({ state: 'sessions_list', sessions, busy: pendingRequests > 0 })
  }
  else if (data.action === 'load_session') {
    if (typeof data.sessionId === 'string' && getSessionsList().some(session => session.session_id === data.sessionId))
      changeSession(() => setSessionId(data.sessionId))
    else
      ipc.broadcast({ state: 'session_error', message: 'Чат не найден. Обновите историю.' })
  }
  else if (data.action === 'get_current_session') {
    const sessionId = getCurrentSessionId()
    ipc.broadcast({ state: 'session_loaded', sessionId, history: getSessionHistoryRaw(sessionId) })
    ipc.broadcast({ state: 'paused_state', isPaused })
    broadcastSessionActivity()
  }
  else if (data.action === 'delete_session') {
    deleteSession(data.sessionId)
    const sessions = getSessionsList()
    ipc.broadcast({ state: 'sessions_list', sessions, busy: pendingRequests > 0 })
  }
  else if (data.action === 'delete_interaction') {
    const id = parseInt(data.id, 10)
    if (!Number.isNaN(id)) {
      deleteMessage(id)
    }
  }
  else if (data.action === 'user_message') {
    handleUserMessage(data.text, data.image, data.id)
  }
  else if (data.action === 'toggle_pause') {
    isPaused = !isPaused
    if (isPaused) {
      assistant.reset()
      libvosk.symbols.vosk_recognizer_reset(recPtr) // Сброс Vosk
      if (currentInteractionId) {
        ipc.broadcastUiState('sleeping', undefined, undefined, undefined, currentInteractionId)
        currentInteractionId = null
      }
    }
    ipc.broadcast({ state: 'paused_state', isPaused })
    console.log(`[🔌] Распознавание аудио ${isPaused ? 'приостановлено' : 'возобновлено'}`)
  }
  else if (data.action === 'get_config') {
    ipc.broadcast({
      state: 'config_state',
      config: {
        skillsProfile: config.skillsProfile || 'frontend',
        customPrompt: config.customPrompt || '',
      },
    })
  }
  else if (data.action === 'save_config') {
    const updated = {
      ...config,
      skillsProfile: data.profile,
      customPrompt: data.customPrompt || '',
    }
    saveConfig(updated)
    ipc.broadcast({
      state: 'config_state',
      config: {
        skillsProfile: config.skillsProfile || 'frontend',
        customPrompt: config.customPrompt || '',
      },
    })
    console.log(`[🔌] Настройки профиля сохранены: ${data.profile}`)
  }
})

// --- Bind Assistant Events ---
assistant.on('speech_partial', (text) => {
  if (!currentInteractionId)
    currentInteractionId = Math.random().toString(36).slice(2)

  process.stdout.write(`\r[🗣️] Надиктовано (Vosk): ${text}\x1B[K`)
  ipc.broadcastUiState('listening', text, undefined, undefined, currentInteractionId)
})

assistant.on('speech_final', (text) => {
  if (!currentInteractionId)
    currentInteractionId = Math.random().toString(36).slice(2)

  process.stdout.write(`\r[🗣️] Надиктовано (Vosk): ${text}\x1B[K`)
  ipc.broadcastUiState('listening', text, undefined, undefined, currentInteractionId)
})

assistant.on('silence_detected', async (voskText: string, audio: Buffer) => {
  pendingRequests++
  broadcastSessionActivity()
  try {
    // Очищаем внутренний граф Vosk, чтобы он не тянул хвосты фразы в следующий запрос
    libvosk.symbols.vosk_recognizer_reset(recPtr)

    const interactionId = currentInteractionId
    currentInteractionId = null
    process.stdout.write('\n')

    if (!voskText) {
      ipc.broadcastUiState('sleeping', undefined, undefined, undefined, interactionId || undefined)
      return
    }

    const startTime = performance.now()
    let sttTime = 0
    let llmTime = 0

    const hasStt = config.stt && config.stt.provider !== 'none'
    let finalCommand = voskText

    if (hasStt) {
      ipc.broadcastUiState('thinking', 'Осмысливаю...', 'Перевожу речь в текст (STT)...', undefined, interactionId || undefined)

      try {
        const sttStart = performance.now()
        const sttText = await transcribeAudio(audio, config)
        sttTime = performance.now() - sttStart
        finalCommand = sttText.trim()

        if (!finalCommand) {
          console.log('[⚠️] STT модель вернула пустой текст.\n')
          ipc.broadcastUiState('sleeping', undefined, undefined, undefined, interactionId || undefined)
          return
        }
        console.log(`[⚡] STT распознал: "${finalCommand}"`)
      }
      catch (e) {
        console.error('[Error] STT API:', e)
        ipc.broadcastUiState('error', 'Ошибка STT', undefined, String(e), interactionId || undefined)
        return
      }
    }
    else {
      console.log(`[⚡] Тишина. Отправляю запрос: "${voskText}"`)
    }

    ipc.broadcastUiState('thinking', finalCommand, undefined, undefined, interactionId || undefined)

    try {
      const history = getHistoryRaw(3).flatMap((item) => {
        const msgs = []
        if (item.user_input)
          msgs.push({ role: 'user' as const, content: item.user_input })
        if (item.assistant_response)
          msgs.push({ role: 'assistant' as const, content: item.assistant_response })
        return msgs
      })

      const llmStart = performance.now()
      const { text: response, model, tokensIn, tokensOut } = await processCommandWithLLM(finalCommand, history, config)
      llmTime = performance.now() - llmStart

      const totalTime = performance.now() - startTime
      console.log(`\n[⏱️] Тайминги:`)
      if (sttTime > 0)
        console.log(`  - STT: ${sttTime.toFixed(2)} мс`)
      console.log(`  - LLM: ${llmTime.toFixed(2)} мс`)
      console.log(`  - Итого: ${totalTime.toFixed(2)} мс`)

      console.log('✅ Итоговый ответ:', response, '\n')
      appendHistory(finalCommand, response, '', 'ok', '{}', 'voice', model, tokensIn, tokensOut)
      ipc.broadcastUiState('success', finalCommand, undefined, response, interactionId || undefined, 'voice', model, tokensIn, tokensOut)
    }
    catch (e: any) {
      console.error('❌ Фатальная ошибка при обращении к LLM:', e)
      const errMessage = e instanceof Error ? e.message : String(e)
      const displayMsg = errMessage.includes('fetch')
        ? 'Ошибка сети. Проверьте интернет-соединение или доступность API.'
        : errMessage
      ipc.broadcastUiState('error', finalCommand, undefined, displayMsg, interactionId || undefined)
    }
  } finally {
    pendingRequests--
    broadcastSessionActivity()
  }
})

async function handleUserMessage(text: string, imageBase64?: string, id?: string) {
  pendingRequests++
  broadcastSessionActivity()
  try {
    const interactionId = id || Math.random().toString(36).slice(2)
    const messageType = imageBase64 ? 'user_image' : 'user_text'

    let content: string | import('./types').ChatMessageContentPart[] = text
    if (imageBase64) {
      content = [
        { type: 'text', text: text || 'Что на картинке?' },
        { type: 'image_url', image_url: { url: imageBase64 } },
      ]
    }

    ipc.broadcastUiState('thinking', text || 'Изображение', undefined, undefined, interactionId, messageType)

    try {
      const history = getHistoryRaw(3).flatMap((item) => {
        const msgs = []
        if (item.user_input) {
          if (item.message_type === 'user_image') {
            msgs.push({ role: 'user' as const, content: item.user_input })
          }
          else {
            msgs.push({ role: 'user' as const, content: item.user_input })
          }
        }
        if (item.assistant_response)
          msgs.push({ role: 'assistant' as const, content: item.assistant_response })
        return msgs
      })

      const { text: response, model, tokensIn, tokensOut } = await processCommandWithLLM(content, history, config)

      console.log('✅ Итоговый ответ (User UI):', response, '\n')
      appendHistory(text || 'Изображение', response, '', 'ok', '{}', messageType, model, tokensIn, tokensOut, imageBase64)
      ipc.broadcastUiState('success', text || 'Изображение', undefined, response, interactionId, messageType, model, tokensIn, tokensOut)
    }
    catch (e: any) {
      console.error('❌ Ошибка при обращении к LLM (User UI):', e)
      const errMessage = e instanceof Error ? e.message : String(e)
      ipc.broadcastUiState('error', text || 'Изображение', undefined, errMessage, interactionId, messageType)
    }
  } finally {
    pendingRequests--
    broadcastSessionActivity()
  }
}

// --- Start Application ---
ipc.start()

async function startListening() {
  for await (const chunk of mic.stdout) {
    if (isPaused)
      continue

    const buffer = Buffer.from(chunk)
    assistant.handleRawAudio(buffer)

    const isFinal = libvosk.symbols.vosk_recognizer_accept_waveform(
      recPtr,
      ptr(buffer),
      buffer.length,
    )

    let resultStr = ''
    if (isFinal) {
      const resultPtr = libvosk.symbols.vosk_recognizer_result(recPtr)!
      resultStr = new CString(resultPtr).toString()
    }
    else {
      const partialPtr = libvosk.symbols.vosk_recognizer_partial_result(recPtr)!
      resultStr = new CString(partialPtr).toString()
    }

    const result: VoskResult = JSON.parse(resultStr || '{}')
    const text = (result.text || result.partial || '').toLowerCase()
    assistant.processText(text, Boolean(isFinal))
  }
}

startListening()
console.log(`🎤 Готово! LLM: [${config.llm.provider}]. STT: [${config.stt?.provider || 'none'}]. Ожидание команды...`)
