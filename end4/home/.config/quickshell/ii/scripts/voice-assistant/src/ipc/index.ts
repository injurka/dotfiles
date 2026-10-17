import type { ServerWebSocket, Socket } from 'bun'
import type { UIPayload, UIState } from '../types'
import { EventEmitter } from 'node:events'
import { existsSync, rmSync } from 'node:fs'

const SOCKET_PATH = '/tmp/voice_assistant_ipc.sock'
const WS_PORT = 8765

interface IPCClient {
  send: (message: string) => void
}

type ClientRef = Record<string, any> & {
  ipcClient?: IPCClient
}

export class IPCServer extends EventEmitter {
  private clients: IPCClient[] = []

  constructor(private uiMode: 'native' | 'external' = 'native') {
    super()
  }

  public start() {
    if (this.uiMode === 'native') {
      this.startNative()
    }
    else {
      this.startExternal()
    }
  }

  private addClient(client: IPCClient, ref: ClientRef) {
    this.clients.push(client)
    ref.ipcClient = client
  }

  private removeClient(ref: ClientRef) {
    this.clients = this.clients.filter(c => c !== ref.ipcClient)
  }

  private startNative() {
    if (existsSync(SOCKET_PATH))
      rmSync(SOCKET_PATH)

    Bun.listen({
      unix: SOCKET_PATH,
      socket: {
        data(_socket: Socket, _data: Buffer) {
          // Ignore incoming data on native socket for now
        },
        open: (socket: Socket) => this.addClient({ send: msg => socket.write(msg) }, socket),
        close: (socket: Socket) => this.removeClient(socket),
      },
    })

    console.log(`[🔌] IPC Сервер запущен (Native). Ожидание UI на: ${SOCKET_PATH}`)
  }

  private startExternal() {
    Bun.serve({
      hostname: '127.0.0.1',
      port: WS_PORT,
      fetch(req, server) {
        // Сначала пытаемся апгрейднуть запрос до WebSocket (для логики ассистента)
        if (server.upgrade(req, { data: {} }))
          return

        return Response.json({ service: 'voice-assistant', status: 'ready', client: 'quickshell' })
      },
      websocket: {
        open: (ws: ServerWebSocket<unknown>) => this.addClient({ send: msg => ws.send(msg) }, ws),
        close: (ws: ServerWebSocket<unknown>) => this.removeClient(ws),
        message: (ws: ServerWebSocket<unknown>, message: string | Buffer) => {
          try {
            const data = JSON.parse(message.toString())
            if (data.action) {
              this.emit('action', data)
            }
          }
          catch (e) {
            console.error('Failed to parse incoming WS message:', e)
          }
        },
      },
    })

    console.log(`[🔌] Quickshell WebSocket: ws://127.0.0.1:${WS_PORT}`)
  }

  public broadcastUiState(
    state: UIState,
    text?: string,
    action?: string,
    finalResponse?: string,
    id?: string,
    message_type?: 'voice' | 'user_text' | 'user_file' | 'user_image',
    llm_model?: string | null,
    tokens_in?: number | null,
    tokens_out?: number | null,
  ) {
    const payload: UIPayload = {
      id,
      state,
      text,
      action,
      finalResponse,
      message_type,
      llm_model,
      tokens_in,
      tokens_out,
    }
    this.broadcast(payload)
  }

  public broadcast(payload: Record<string, any>) {
    const message = `${JSON.stringify(payload)}\n`
    for (const client of this.clients) {
      client.send(message)
    }
  }
}
