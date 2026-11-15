import { emptyFilters, type Article, type Filters } from './types'

export const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
export function filterArticles(articles: Article[], filters: Filters) {
  const q = normalize(filters.query)
  return articles.filter(a => {
    const date = a.date?.slice(0, 10)
    return (!q || normalize([a.title, a.summary, ...a.teams, ...a.competitions].join(' ')).includes(q)) &&
      (!filters.source || a.source === filters.source) &&
      (!filters.topic || (filters.topic === 'sin_clasificar' ? a.topic === filters.topic : a.topics.includes(filters.topic))) &&
      (!filters.team || a.teams.includes(filters.team)) &&
      (!filters.competition || a.competitions.includes(filters.competition)) &&
      (date ? ((!filters.from || date >= filters.from) && (!filters.to || date <= filters.to)) : filters.includeUndated)
  })
}
export function countBy(values: string[]): { name: string; value: number }[] {
  const map = new Map<string, number>()
  values.filter(Boolean).forEach(value => map.set(value, (map.get(value) ?? 0) + 1))
  return [...map].map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value || a.name.localeCompare(b.name))
}
export function entityCounts(articles: Article[], key: 'teams' | 'competitions') {
  return countBy(articles.flatMap(a => [...new Set(a[key])]))
}
export function dailyCounts(articles: Article[]) {
  const counts = countBy(articles.flatMap(a => a.date ? [a.date.slice(0, 10)] : []))
  if (!counts.length) return []
  const sorted = counts.sort((a, b) => a.name.localeCompare(b.name))
  const map = new Map(sorted.map(d => [d.name, d.value]))
  const first = new Date(`${sorted[0].name}T00:00:00Z`)
  const last = new Date(`${sorted.at(-1)!.name}T00:00:00Z`)
  const days: { name: string; value: number }[] = []
  for (const date = first; date <= last; date.setUTCDate(date.getUTCDate() + 1)) {
    const name = date.toISOString().slice(0, 10)
    days.push({ name, value: map.get(name) ?? 0 })
  }
  return days
}
export function heatmapData(articles: Article[]) {
  const data = Array.from({ length: 168 }, (_, i) => [i % 24, Math.floor(i / 24), 0])
  articles.forEach(a => {
    if (!a.date) return
    const d = new Date(a.date)
    if (!Number.isNaN(d.getTime())) data[((d.getUTCDay() + 6) % 7) * 24 + d.getUTCHours()][2]++
  })
  return data
}
export function entityGraph(articles: Article[], minimum = 1) {
  const counts = new Map<string, { name: string; value: number; category: number }>()
  const edges = new Map<string, { source: string; target: string; value: number }>()
  articles.forEach(a => {
    const nodes = [...new Set(a.teams.map(name => `t:${name}`).concat(a.competitions.map(name => `c:${name}`)))]
    nodes.forEach(id => counts.set(id, { name: id.slice(2), value: (counts.get(id)?.value ?? 0) + 1, category: id.startsWith('t:') ? 0 : 1 }))
    nodes.forEach((source, i) => nodes.slice(i + 1).forEach(target => {
      const pair = [source, target].sort()
      const key = JSON.stringify(pair)
      edges.set(key, { source: pair[0], target: pair[1], value: (edges.get(key)?.value ?? 0) + 1 })
    }))
  })
  const topIds = new Set([...counts].sort((a, b) => b[1].value - a[1].value).slice(0, 28).map(([id]) => id))
  const links = [...edges.values()].filter(e => e.value >= minimum && topIds.has(e.source) && topIds.has(e.target))
  const connected = new Set(links.flatMap(e => [e.source, e.target]))
  const nodes = [...counts].filter(([id]) => connected.has(id)).map(([id, n]) => ({ id, ...n, symbolSize: 20 + Math.sqrt(n.value) * 9 }))
  return { nodes, links }
}
export function termStats(articles: Article[]) {
  const map = new Map<string, { name: string; frequency: number; documents: number; maxTfidf: number }>()
  articles.forEach(a => {
    const local = countBy(a.tokens)
    local.forEach(({ name, value }) => {
      const old = map.get(name) ?? { name, frequency: 0, documents: 0, maxTfidf: 0 }
      map.set(name, { ...old, frequency: old.frequency + value, documents: old.documents + 1 })
    })
  })
  articles.forEach(a => countBy(a.tokens).forEach(({ name, value }) => {
    const term = map.get(name)!
    term.maxTfidf = Math.max(term.maxTfidf, value / a.tokens.length * Math.log(articles.length / term.documents))
  }))
  return [...map.values()].sort((a, b) => b.frequency - a.frequency || a.name.localeCompare(b.name))
}
export function periodFilters(days: number, now = new Date()): Pick<Filters, 'from' | 'to'> {
  if (!days) return { from: '', to: '' }
  const start = new Date(now)
  start.setUTCDate(start.getUTCDate() - days + 1)
  return { from: start.toISOString().slice(0, 10), to: now.toISOString().slice(0, 10) }
}
export const activeCount = (f: Filters) => Object.entries(f).filter(([k, v]) => v !== emptyFilters[k as keyof Filters]).length
export const newest = (a: Article, b: Article) => (b.date ?? '').localeCompare(a.date ?? '') || a.id.localeCompare(b.id)
export function exportCsv(articles: Article[]) {
  const escape = (value: string) => `"${(/^[=+@\-\t\r]/.test(value) ? `'${value}` : value).replace(/"/g, '""')}"`
  const rows = [['ID', 'Titular', 'Resumen', 'Fecha UTC', 'Canal', 'Tema', 'Equipos', 'Competiciones', 'URL'], ...articles.map(a => [a.id, a.title, a.summary, a.date ?? '', a.source, a.topic, a.teams.join('; '), a.competitions.join('; '), a.url])]
  return '\uFEFF' + rows.map(row => row.map(escape).join(',')).join('\r\n')
}
