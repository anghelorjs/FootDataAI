export async function request<T>(path: string, body?: unknown): Promise<T> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 30000)
  try {
    const response = await fetch(`/api/${path}`, {
      signal: controller.signal,
      ...(body !== undefined ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {}),
    })
    if (!response.headers.get('content-type')?.includes('application/json')) throw new Error('No se pudo conectar con la API de R. Inicia Rscript api.R en la raíz del proyecto.')
    const data = await response.json()
    if (!response.ok) throw new Error(data.error ?? `Error de conexión (${response.status}).`)
    return data as T
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw new Error('La consulta tardó demasiado. Comprueba que la API de R esté activa.')
    throw error
  } finally { clearTimeout(timeout) }
}
