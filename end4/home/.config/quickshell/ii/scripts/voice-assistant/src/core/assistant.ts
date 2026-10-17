import { EventEmitter } from 'node:events'

export interface AssistantEvents {
  speech_partial: (text: string) => void
  speech_final: (text: string) => void
  silence_detected: (text: string, audio: Buffer) => void
}

export class Assistant extends EventEmitter {
  private finalizedBuffer: string[] = []
  private currentPartial = ''
  private silenceTimer: Timer | null = null

  private audioChunks: Buffer[] = []
  private preBuffer: Buffer[] = []
  private preBufferLength = 0

  // 16kHz, 16-bit (2 bytes), 1 channel -> 32000 bytes/sec
  // Храним 3 секунды аудио до начала речи, чтобы не обрезать начало фразы
  private readonly MAX_PREBUFFER_BYTES = 32_000 * 3
  // Пауза 2 секунды для определения конца тезиса
  private readonly SILENCE_TIMEOUT_MS = 2_000

  public handleRawAudio(chunk: Buffer) {
    const isSpeaking = this.finalizedBuffer.length > 0 || this.currentPartial !== ''

    if (isSpeaking) {
      this.audioChunks.push(chunk)
    }
    else {
      this.preBuffer.push(chunk)
      this.preBufferLength += chunk.length

      while (this.preBufferLength > this.MAX_PREBUFFER_BYTES) {
        const shifted = this.preBuffer.shift()
        if (shifted) {
          this.preBufferLength -= shifted.length
        }
      }
    }
  }

  public processText(text: string, isFinal: boolean) {
    if (!text)
      return

    if (this.audioChunks.length === 0 && this.preBuffer.length > 0) {
      this.audioChunks = [...this.preBuffer]
      this.preBuffer = []
      this.preBufferLength = 0
    }

    this.updateBuffer(text, isFinal)
    this.resetTimer()
  }

  private updateBuffer(text: string, isFinal: boolean) {
    if (isFinal) {
      this.finalizedBuffer.push(text)
      this.currentPartial = ''
      this.emit('speech_final', this.getFullText())
    }
    else {
      this.currentPartial = text
      this.emit('speech_partial', this.getFullText())
    }
  }

  private getFullText(): string {
    return [...this.finalizedBuffer, this.currentPartial].join(' ').trim()
  }

  private resetTimer() {
    if (this.silenceTimer)
      clearTimeout(this.silenceTimer)

    const extraTime = Math.min(1000, this.finalizedBuffer.length * 200)
    const timeout = this.SILENCE_TIMEOUT_MS + extraTime

    this.silenceTimer = setTimeout(() => this.commitCommand(), timeout)
  }

  public forceCommit() {
    if (this.silenceTimer) {
      clearTimeout(this.silenceTimer)
      this.silenceTimer = null
    }
    this.commitCommand()
  }

  public reset() {
    this.resetState()
  }

  private commitCommand() {
    const text = this.getFullText()
    const capturedAudio = Buffer.concat(this.audioChunks)
    this.resetState()

    this.emit('silence_detected', text, capturedAudio)
  }

  private resetState() {
    this.finalizedBuffer = []
    this.currentPartial = ''
    this.audioChunks = []

    if (this.silenceTimer) {
      clearTimeout(this.silenceTimer)
      this.silenceTimer = null
    }
  }
}
