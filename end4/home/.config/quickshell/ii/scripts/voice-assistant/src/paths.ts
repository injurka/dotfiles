import { homedir } from 'node:os'
import { isAbsolute, join } from 'node:path'

function xdgDirectory(name: string, fallback: string) {
  const value = process.env[name]
  return value && isAbsolute(value) ? value : join(homedir(), fallback)
}

export const configPath = join(xdgDirectory('XDG_CONFIG_HOME', '.config'), 'voice-assistant/config.json')
export const dataDirectory = join(xdgDirectory('XDG_DATA_HOME', '.local/share'), 'voice-assistant')
export const stateDirectory = join(xdgDirectory('XDG_STATE_HOME', '.local/state'), 'voice-assistant')
export const modelPath = join(dataDirectory, 'models/vosk')
export const libraryPath = join(dataDirectory, 'libvosk.so')
