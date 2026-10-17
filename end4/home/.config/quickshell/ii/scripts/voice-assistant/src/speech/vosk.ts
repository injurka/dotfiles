import { existsSync } from 'node:fs'
import { dlopen, FFIType } from 'bun:ffi'
import { libraryPath, modelPath } from '../paths'

export const SAMPLE_RATE = 16000
const MODEL_PATH = modelPath
const LIBVOSK_PATH = libraryPath

if (!existsSync(LIBVOSK_PATH) || !existsSync(MODEL_PATH))
  throw new Error('Vosk resources are missing. Run import-local.py --from /path/to/voice-assistant first.')

console.log('⚙️ Подключение libvosk.so через Bun FFI...')

export const libvosk = dlopen(LIBVOSK_PATH, {
  vosk_set_log_level: { args: [FFIType.i32], returns: FFIType.void },
  vosk_model_new: { args: [FFIType.ptr], returns: FFIType.ptr },
  vosk_recognizer_new: { args: [FFIType.ptr, FFIType.f32], returns: FFIType.ptr },
  vosk_recognizer_accept_waveform: { args: [FFIType.ptr, FFIType.ptr, FFIType.i32], returns: FFIType.i32 },
  vosk_recognizer_result: { args: [FFIType.ptr], returns: FFIType.ptr },
  vosk_recognizer_partial_result: { args: [FFIType.ptr], returns: FFIType.ptr },
  vosk_recognizer_reset: { args: [FFIType.ptr], returns: FFIType.void },
})

libvosk.symbols.vosk_set_log_level(-1)

console.log('⏳ Загрузка языковой модели...')

const modelPathBuf = Buffer.from(`${MODEL_PATH}\0`, 'utf8')
const modelPtr = libvosk.symbols.vosk_model_new(modelPathBuf)

if (modelPtr === null || modelPtr === 0) {
  console.error(`\n❌ ОШИБКА: Модель не найдена в папке:\n${MODEL_PATH}`)
  process.exit(1)
}

export const recPtr = libvosk.symbols.vosk_recognizer_new(modelPtr, SAMPLE_RATE)

if (recPtr === null || recPtr === 0) {
  console.error('\n❌ ОШИБКА: Не удалось инициализировать распознаватель.')
  process.exit(1)
}
