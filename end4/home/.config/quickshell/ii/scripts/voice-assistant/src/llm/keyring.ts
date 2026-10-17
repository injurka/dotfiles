export async function getSharedApiKey(keyId: string): Promise<string> {
  const child = Bun.spawn(['secret-tool', 'lookup', 'application', 'illogical-impulse'], {
    env: process.env,
    stdout: 'pipe',
    stderr: 'ignore',
  })
  const timeout = setTimeout(() => child.kill(), 5000)
  try {
    const raw = await new Response(child.stdout).text()
    if (await child.exited !== 0)
      throw new Error('API-ключ Quickshell недоступен. Разблокируйте хранилище ключей.')
    let data
    try {
      data = JSON.parse(raw)
    } catch {
      throw new Error('Не удалось прочитать хранилище API-ключей Quickshell.')
    }
    const key = data?.apiKeys?.[keyId]
    if (typeof key !== 'string' || !key.trim())
      throw new Error('Для выбранного провайдера не задан API-ключ в Quickshell.')
    return key.trim()
  } finally {
    clearTimeout(timeout)
  }
}
