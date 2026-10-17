import { SAMPLE_RATE } from './vosk'

export function startMic() {
  return Bun.spawn([
    'sh',
    '-c',
    `parec --device=$(pactl get-default-sink).monitor --format=s16le --rate=${SAMPLE_RATE} --channels=1`,
  ], { stdout: 'pipe', stderr: 'ignore' })
}
