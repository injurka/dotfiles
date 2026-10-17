import type { Config } from '../types'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { dataDirectory } from '../paths'

// The systemd control group also stops this child when the assistant is stopped.
export async function startLocalWhisper(config: Config): Promise<void> {
  if (!config.stt || config.stt.provider === 'none')
    return
  const url = new URL(config.stt.apiUrl)
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
    || url.pathname !== '/inference')
    return

  const health = new URL('/health', url)
  async function isReady() {
    try {
      const response = await fetch(health, { signal: AbortSignal.timeout(1000) })
      return response.ok && (await response.json() as { status?: string }).status === 'ok'
    } catch {
      return false
    }
  }
  if (await isReady())
    return

  const runtime = join(dataDirectory, 'whisper')
  const binary = join(runtime, 'whisper-server')
  const model = join(dataDirectory, 'models/ggml-large-v3-turbo-q5_0.bin')
  if (!existsSync(binary) || !existsSync(model))
    throw new Error('Локальный Whisper не установлен. Импортируйте whisper-server и модель через import-local.py или настройте другой STT.')

  const child = Bun.spawn([
    binary, '-m', model, '-l', 'ru', '--host', url.hostname === '[::1]' ? '::1' : url.hostname,
    '--port', url.port || '80',
  ], {
    cwd: runtime,
    env: { ...process.env, LD_LIBRARY_PATH: runtime + (process.env.LD_LIBRARY_PATH ? ':' + process.env.LD_LIBRARY_PATH : '') },
    stdout: 'inherit',
    stderr: 'inherit',
  })
  process.on('exit', () => child.kill())
  console.log('[STT] Запускаю локальный Whisper…')
  for (let attempt = 0; attempt < 120; attempt++) {
    if (child.exitCode !== null)
      throw new Error('Whisper завершился при запуске; подробности в журнале voice-assistant.service')
    if (await isReady()) {
      console.log('[STT] Локальный Whisper готов.')
      return
    }
    await Bun.sleep(500)
  }
  child.kill()
  throw new Error('Whisper не запустился за отведённое время.')
}
