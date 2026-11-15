import { describe, expect, it } from 'vitest'
import { countBy, dailyCounts, entityGraph, exportCsv, filterArticles, heatmapData, periodFilters, termStats } from './analytics'
import { emptyFilters, type Article } from './types'

const article = (id: string, extra: Partial<Article>): Article => ({ id, title: 'Football news', summary: '', url: 'https://example.org', source: 'BBC', medium: 'BBC', date: null, topic: 'partidos', topics: ['partidos'], teams: [], competitions: [], tokens: [], ...extra })
const data = [
  article('1', { title: 'Arsenal wins', date: '2026-11-15T12:00:00Z', teams: ['Arsenal', 'Chelsea'], competitions: ['Premier League'], tokens: ['arsenal', 'wins', 'wins'] }),
  article('2', { title: 'Chelsea transfer', date: '2026-11-13T23:30:00Z', topic: 'fichajes', topics: ['fichajes', 'partidos'], teams: ['Chelsea'], competitions: ['Premier League'], tokens: ['chelsea', 'wins'], source: 'European' }),
  article('3', { title: 'Copa de fútbol', topic: 'sin_clasificar', topics: [] }),
]
describe('filtros sobre datos reales', () => {
  it('combina entidades, temas no principales y canal', () => expect(filterArticles(data, { ...emptyFilters, team: 'Chelsea', topic: 'partidos', source: 'European' }).map(a => a.id)).toEqual(['2']))
  it('incluye o excluye fechas faltantes explícitamente', () => {
    expect(filterArticles(data, { ...emptyFilters, from: '2026-11-14', to: '2026-11-15' }).map(a => a.id)).toEqual(['1', '3'])
    expect(filterArticles(data, { ...emptyFilters, from: '2026-11-14', includeUndated: false }).map(a => a.id)).toEqual(['1'])
  })
  it('normaliza tildes y respeta entidades completas', () => {
    expect(filterArticles(data, { ...emptyFilters, query: 'FÚTBOL' }).map(a => a.id)).toEqual(['3'])
    expect(filterArticles(data, { ...emptyFilters, team: 'Ars' })).toHaveLength(0)
  })
  it('calcula últimos días respecto al reloj, sin desplazarlo al último dato', () => expect(periodFilters(7, new Date('2026-11-15T00:00:00Z'))).toEqual({ from: '2026-11-09', to: '2026-11-15' }))
  it('devuelve un conjunto vacío sin datos ficticios', () => expect(filterArticles(data, { ...emptyFilters, team: 'Juventus' })).toEqual([]))
})
describe('minería y series temporales', () => {
  it('completa días intermedios con cero y excluye fechas faltantes', () => expect(dailyCounts(data)).toEqual([{ name: '2026-11-13', value: 1 }, { name: '2026-11-14', value: 0 }, { name: '2026-11-15', value: 1 }]))
  it('cuenta conexiones una vez por documento', () => {
    const graph = entityGraph(data, 2)
    expect(graph.links).toEqual([{ source: 'c:Premier League', target: 't:Chelsea', value: 2 }])
    expect(graph.nodes).toHaveLength(2)
    expect(entityGraph(data, 3).links).toHaveLength(0)
  })
  it('ubica las publicaciones en semana y hora UTC', () => { const heat = heatmapData(data); expect(heat).toHaveLength(168); expect(heat.find(v => v[0] === 12 && v[1] === 6)?.[2]).toBe(1); expect(heat.reduce((sum, v) => sum + v[2], 0)).toBe(2) })
  it('calcula TF-IDF con conteos por documento, sin dividir por cero', () => {
    const terms = termStats(data.slice(0, 2))
    const wins = terms.find(t => t.name === 'wins')!
    expect(wins.frequency).toBe(3); expect(wins.documents).toBe(2); expect(wins.maxTfidf).toBe(0)
    expect(terms.find(t => t.name === 'arsenal')!.maxTfidf).toBeCloseTo(Math.log(2) / 3)
    expect(termStats([])).toEqual([])
  })
  it('no agrupa palabras con propiedades de objetos', () => expect(countBy(['__proto__', '__proto__'])).toEqual([{ name: '__proto__', value: 2 }]))
})
describe('exportación CSV', () => {
  it('conserva UTF-8, escapa comillas y neutraliza fórmulas', () => {
    const csv = exportCsv([article('1', { title: '=SUM(1)', summary: '"Fútbol", hoy' })])
    expect(csv.startsWith('\uFEFF')).toBe(true)
    expect(csv).toContain('"\'=SUM(1)"')
    expect(csv).toContain('"""Fútbol"", hoy"')
    expect(exportCsv([]).split('\r\n')).toHaveLength(1)
  })
})
