export interface Article {
  id: string
  title: string
  summary: string
  url: string
  source: string
  medium: string
  date: string | null
  topic: string
  topics: string[]
  teams: string[]
  competitions: string[]
  tokens: string[]
}
export interface Filters {
  query: string; source: string; topic: string; team: string; competition: string
  from: string; to: string; includeUndated: boolean
}
export interface Snapshot {
  articles: Article[]
  meta: { total: number; generatedAt: string; extractedAt: string | null; validDates: number; methodology: string }
}
export interface UpdateStatus {
  running: boolean; automatic: boolean; cooldownSeconds: number
  state: string; phase: string; detail: string; updatedAt: string
}
export interface ChatResponse { text: string; type: string; scopeCount: number; articles: string[] }
export type Page = 'overview' | 'news' | 'mining' | 'chat' | 'system'
export const emptyFilters: Filters = { query: '', source: '', topic: '', team: '', competition: '', from: '', to: '', includeUndated: true }
export const topicLabels: Record<string, string> = {
  fichajes: 'Fichajes', champions: 'Champions League', premier_league: 'Premier League', laliga: 'LaLiga',
  mundial: 'Mundial', selecciones: 'Selecciones', lesiones: 'Lesiones', partidos: 'Partidos', sin_clasificar: 'Sin clasificar',
}
export const topicColors: Record<string, string> = {
  fichajes: '#729f49', champions: '#8292c6', premier_league: '#d3ac62', laliga: '#d58468', mundial: '#80ada6',
  selecciones: '#1d6656', lesiones: '#c78596', partidos: '#a9c878', sin_clasificar: '#c5cdc7',
}
