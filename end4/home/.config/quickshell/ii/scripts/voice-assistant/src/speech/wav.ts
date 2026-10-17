/**
 * Оборачивает сырой PCM поток (16kHz, 16-bit, Mono) в валидный WAV файл.
 */
export function pcmToWav(pcmData: Buffer, sampleRate = 16000, numChannels = 1, bitsPerSample = 16): Buffer {
  const header = Buffer.alloc(44)

  // RIFF chunk
  header.write('RIFF', 0)
  header.writeUInt32LE(36 + pcmData.length, 4) // File size - 8
  header.write('WAVE', 8)

  // fmt sub-chunk
  header.write('fmt ', 12)
  header.writeUInt32LE(16, 16) // Subchunk1Size
  header.writeUInt16LE(1, 20) // AudioFormat (1 = PCM)
  header.writeUInt16LE(numChannels, 22)
  header.writeUInt32LE(sampleRate, 24)
  header.writeUInt32LE(sampleRate * numChannels * (bitsPerSample / 8), 28) // ByteRate
  header.writeUInt16LE(numChannels * (bitsPerSample / 8), 32) // BlockAlign
  header.writeUInt16LE(bitsPerSample, 34)

  // data sub-chunk
  header.write('data', 36)
  header.writeUInt32LE(pcmData.length, 40)

  return Buffer.concat([header, pcmData])
}
