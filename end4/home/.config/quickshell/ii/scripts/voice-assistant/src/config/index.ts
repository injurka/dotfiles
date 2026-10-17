import type { Config } from '../types'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { configPath } from '../paths'

export function loadConfig(): Config {
  const defaultConfig: Config = {
    uiMode: 'external',
    llm: {
      provider: 'openai',
      apiKey: '',
      apiUrl: '',
      model: '',
    },
    stt: {
      provider: 'none',
      apiKey: '',
      apiUrl: '',
      model: '',
    },
    skillsProfile: 'frontend',
    customPrompt: '',
  }

  if (!existsSync(configPath)) {
    throw new Error('Create the local assistant configuration at ' + configPath + ' using config.example.json')
  }

  try {
    const file = readFileSync(configPath, 'utf-8')
    const parsed = JSON.parse(file) as Config

    parsed.uiMode = 'external'
    parsed.stt = parsed.stt || defaultConfig.stt
    parsed.skillsProfile = parsed.skillsProfile || defaultConfig.skillsProfile
    parsed.customPrompt = parsed.customPrompt || defaultConfig.customPrompt

    return parsed
  }
  catch (error) {
    console.error('❌ Ошибка при чтении config.json:', error)
    process.exit(1)
  }
}

export const config = loadConfig()

export function saveConfig(newConfig: Config): void {
  try {
    writeFileSync(configPath, JSON.stringify(newConfig, null, 2), { encoding: 'utf-8', mode: 0o600 })
    Object.assign(config, newConfig)
  }
  catch (error) {
    throw new Error('Не удалось сохранить настройки Voice Assistance.')
  }
}
