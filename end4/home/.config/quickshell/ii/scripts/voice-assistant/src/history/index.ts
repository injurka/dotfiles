import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { Database } from 'bun:sqlite'
import { stateDirectory } from '../paths'

const DATA_DIR = stateDirectory
const DB_FILE = join(DATA_DIR, 'history.sqlite')

if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true })
}

export const db = new Database(DB_FILE)

try {
  db.run(`ALTER TABLE history ADD COLUMN session_id TEXT DEFAULT 'default'`)
}
catch {
  // Column might already exist
}

try {
  db.run(`ALTER TABLE history ADD COLUMN message_type TEXT DEFAULT 'voice'`)
}
catch {
  // Column might already exist
}

try {
  db.run(`ALTER TABLE history ADD COLUMN llm_model TEXT`)
}
catch {
  // Column might already exist
}

try {
  db.run(`ALTER TABLE history ADD COLUMN tokens_in INTEGER`)
}
catch {
  // Column might already exist
}

try {
  db.run(`ALTER TABLE history ADD COLUMN tokens_out INTEGER`)
}
catch {
  // Column might already exist
}

try {
  db.run(`ALTER TABLE history ADD COLUMN image TEXT`)
}
catch {
  // Column might already exist
}

db.run(`
  CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT DEFAULT 'default',
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_input TEXT NOT NULL,
    assistant_response TEXT,
    command_executed TEXT,
    status TEXT DEFAULT 'ok',
    context JSON,
    message_type TEXT DEFAULT 'voice',
    llm_model TEXT,
    tokens_in INTEGER,
    tokens_out INTEGER,
    image TEXT
  )
`)

const sessionFile = join(DATA_DIR, 'current-session.json')
let currentSessionId = 'default'
try {
  const saved = JSON.parse(readFileSync(sessionFile, 'utf8'))
  if (typeof saved.sessionId === 'string' && saved.sessionId)
    currentSessionId = saved.sessionId
} catch {}

export function getCurrentSessionId() {
  return currentSessionId
}

export function startNewSession() {
  setSessionId(Date.now().toString() + '-' + Math.random().toString(36).slice(2))
}

export function appendHistory(
  userText: string,
  assistantResponse: string,
  commandExecuted = '',
  status = 'ok',
  context = '{}',
  messageType = 'voice',
  llmModel: string | null = null,
  tokensIn: number | null = null,
  tokensOut: number | null = null,
  image: string | null = null,
): void {
  const insert = db.prepare(`
    INSERT INTO history (session_id, user_input, assistant_response, command_executed, status, context, message_type, llm_model, tokens_in, tokens_out, image) 
    VALUES ($session_id, $user, $assistant, $command, $status, $context, $message_type, $llm_model, $tokens_in, $tokens_out, $image)
  `)
  insert.run({
    $session_id: currentSessionId,
    $user: userText,
    $assistant: assistantResponse,
    $command: commandExecuted,
    $status: status,
    $context: context,
    $message_type: messageType,
    $llm_model: llmModel,
    $tokens_in: tokensIn,
    $tokens_out: tokensOut,
    $image: image,
  })
}

export function getHistory(limit = 5): string {
  try {
    const query = db.prepare(`SELECT * FROM history WHERE session_id = $session_id ORDER BY id DESC LIMIT ${limit}`)
    const recent = query.all({ $session_id: currentSessionId }).reverse()

    if (recent.length === 0)
      return 'История пуста.'

    return JSON.stringify(recent, null, 2)
  }
  catch {
    return 'Ошибка при чтении истории.'
  }
}

export interface HistoryRecord {
  id: number
  session_id: string
  timestamp: string
  user_input: string
  assistant_response: string
  command_executed: string
  status: string
  context: string
  message_type: 'voice' | 'user_text' | 'user_file' | 'user_image'
  llm_model: string | null
  tokens_in: number | null
  tokens_out: number | null
  image: string | null
}

export function getHistoryRaw(limit = 3): HistoryRecord[] {
  try {
    const query = db.prepare(`SELECT * FROM history WHERE session_id = $session_id ORDER BY id DESC LIMIT ${limit}`)
    return query.all({ $session_id: currentSessionId }).reverse() as HistoryRecord[]
  }
  catch {
    return []
  }
}

export interface SessionMeta {
  session_id: string
  started_at: string
  count: number
  title: string
}

export function getSessionsList(): SessionMeta[] {
  try {
    const query = db.prepare(`SELECT h.session_id, MIN(h.timestamp) as started_at, COUNT(*) as count,
      (SELECT user_input FROM history first WHERE first.session_id = h.session_id ORDER BY id LIMIT 1) as title
      FROM history h GROUP BY h.session_id ORDER BY MAX(h.id) DESC LIMIT 50`)
    const sessions = query.all() as SessionMeta[]
    if (!sessions.some(session => session.session_id === currentSessionId)) {
      const current = db.prepare(`SELECT session_id, MIN(timestamp) as started_at,
        COUNT(*) as count, (SELECT user_input FROM history WHERE session_id = $id ORDER BY id LIMIT 1) as title
        FROM history WHERE session_id = $id GROUP BY session_id`).get({ $id: currentSessionId }) as SessionMeta | null
      sessions.unshift(current || { session_id: currentSessionId, started_at: new Date().toISOString(), count: 0, title: '' })
    }
    return sessions.map(session => ({
      ...session,
      title: String(session.title || '').replace(/\s+/g, ' ').trim().slice(0, 160),
    }))
  }
  catch (err) {
    console.error('Failed to get sessions list', err)
    return []
  }
}

export function setSessionId(id: string) {
  writeFileSync(sessionFile, JSON.stringify({ sessionId: id }), { mode: 0o600 })
  currentSessionId = id
}

export function getSessionHistoryRaw(id: string): HistoryRecord[] {
  try {
    const query = db.prepare(`SELECT * FROM history WHERE session_id = $session_id ORDER BY id ASC`)
    return query.all({ $session_id: id }) as HistoryRecord[]
  }
  catch {
    return []
  }
}

export function deleteSession(id: string) {
  try {
    const query = db.prepare(`DELETE FROM history WHERE session_id = $session_id`)
    query.run({ $session_id: id })
  }
  catch (err) {
    console.error('Failed to delete session', err)
  }
}

export function deleteMessage(id: number) {
  try {
    const query = db.prepare(`DELETE FROM history WHERE id = $id`)
    query.run({ $id: id })
  }
  catch (err) {
    console.error('Failed to delete message', err)
  }
}
