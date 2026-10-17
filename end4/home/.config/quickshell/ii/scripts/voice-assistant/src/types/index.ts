export type LlmProvider = 'openai' | 'ollama' | 'gemini'
export type SttProvider = 'openai' | 'groq' | 'none'

export interface LlmConfig {
  provider: LlmProvider
  apiKey: string
  apiUrl: string
  model: string
  endpoint?: string
  shellModelId?: string
  credentialsSource?: 'quickshell'
  keyId?: string
  requiresKey?: boolean
  apiFormat?: 'openai' | 'mistral' | 'gemini'
  extraParams?: Record<string, unknown>
}

export interface SttConfig {
  provider: SttProvider
  apiKey: string
  apiUrl: string
  model: string
}

export interface Config {
  uiMode?: 'native' | 'external'
  llm: LlmConfig
  stt?: SttConfig
  skillsProfile?: string
  customPrompt?: string
}

export interface VoskResult {
  text?: string
  partial?: string
}

export type UIState = 'sleeping' | 'listening' | 'thinking' | 'executing' | 'success' | 'error'

export interface UIPayload {
  id?: string
  state: UIState
  text?: string
  action?: string
  finalResponse?: string
  message_type?: 'voice' | 'user_text' | 'user_file' | 'user_image'
  llm_model?: string | null
  tokens_in?: number | null
  tokens_out?: number | null
}

export type MessageRole = 'system' | 'user' | 'assistant'

export interface ChatMessageContentPart {
  type: 'text' | 'image_url'
  text?: string
  image_url?: {
    url: string
  }
}

export interface ChatMessage {
  role: MessageRole
  content: string | ChatMessageContentPart[] | null
  name?: string
}

export interface LlmResponse {
  choices: {
    message: ChatMessage
  }[]
  model?: string
  usage?: {
    prompt_tokens: number
    completion_tokens: number
    total_tokens: number
  }
}
