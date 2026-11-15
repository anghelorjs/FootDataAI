import { memo, useEffect, useRef, useState, type ReactNode } from 'react'
import * as echarts from 'echarts/core'
import { LineChart, PieChart, TreemapChart, GraphChart, HeatmapChart as EHeatmapChart, ScatterChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent, VisualMapComponent, DataZoomComponent, AriaComponent } from 'echarts/components'
import { SVGRenderer } from 'echarts/renderers'
import type { EChartsOption, ECElementEvent } from 'echarts'
import { Network, MoveUpRight, Info, ScanSearch } from 'lucide-react'
import { countBy, dailyCounts, entityCounts, entityGraph, heatmapData, termStats } from '../analytics'
import { topicColors, topicLabels, type Article } from '../types'

echarts.use([LineChart, PieChart, TreemapChart, GraphChart, EHeatmapChart, ScatterChart, GridComponent, TooltipComponent, LegendComponent, VisualMapComponent, DataZoomComponent, AriaComponent, SVGRenderer])
const ink = '#52645c'
const tooltip = { trigger: 'item' as const, renderMode: 'richText' as const, backgroundColor: '#122e25', borderWidth: 0, textStyle: { color: '#fff', fontSize: 12 }, padding: 12 }
export function Chart({ option, label, onClick, height = 270 }: { option: EChartsOption; label: string; onClick?: (event: ECElementEvent) => void; height?: number }) {
  const element = useRef<HTMLDivElement>(null)
  const chart = useRef<echarts.ECharts | null>(null)
  const handler = useRef(onClick)
  handler.current = onClick
  useEffect(() => {
    const instance = echarts.init(element.current!, undefined, { renderer: 'svg' })
    chart.current = instance
    instance.on('click', event => handler.current?.(event as ECElementEvent))
    const observer = new ResizeObserver(() => instance.resize())
    observer.observe(element.current!)
    return () => { observer.disconnect(); instance.dispose(); chart.current = null }
  }, [])
  useEffect(() => { chart.current?.setOption({ textStyle: { fontFamily: 'inherit', color: ink }, animationDuration: 500, aria: { enabled: true }, ...option }, true) }, [option])
  return <div ref={element} role="img" aria-label={label} style={{ height, width: '100%', minWidth: 0 }} />
}
export function Panel({ title, eyebrow, description, children, action, className = '' }: { title: string; eyebrow?: string; description?: string; children: ReactNode; action?: ReactNode; className?: string }) {
  return <section className={`panel ${className}`}><div className="panel-heading"><div>{eyebrow && <span className="eyebrow">{eyebrow}</span>}<h3>{title}</h3>{description && <p>{description}</p>}</div>{action}</div>{children}</section>
}
export function EmptyChart({ children = 'No hay datos suficientes para esta selección.' }: { children?: ReactNode }) {
  return <div className="chart-empty"><ScanSearch size={28} strokeWidth={1.3} /><p>{children}</p><span>Prueba con otro período o ajusta los filtros.</span></div>
}
function TrendChartView({ articles, onDay }: { articles: Article[]; onDay: (day: string) => void }) {
  const days = dailyCounts(articles)
  const valid = articles.filter(a => a.date).length
  return <Panel eyebrow="PULSO INFORMATIVO" title="La conversación, día a día" description="Noticias por fecha de publicación · UTC" action={<span className="chart-tag"><span className="dot" />{valid} con fecha</span>}>
    {days.length ? <Chart label="Evolución diaria de las noticias; pulsa un punto para filtrar por día" onClick={e => onDay(e.name)} option={{
      tooltip: { ...tooltip, trigger: 'axis' }, grid: { left: 36, right: 20, top: 24, bottom: 58 },
      xAxis: { type: 'category', data: days.map(d => d.name), boundaryGap: false, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: '#87958d', fontSize: 10, margin: 16, formatter: (v: string) => `${v.slice(8)}/${v.slice(5, 7)}` } },
      yAxis: { type: 'value', minInterval: 1, axisLabel: { color: '#87958d', fontSize: 10 }, splitLine: { lineStyle: { color: '#eef1ec', type: 'dashed' } } },
      dataZoom: [{ type: 'inside' }, { type: 'slider', height: 12, bottom: 8, borderColor: 'transparent', backgroundColor: '#f1f4ee', fillerColor: '#dce8cc', handleStyle: { color: '#628650' }, showDetail: false }],
      series: [{ name: 'Noticias', type: 'line', smooth: 0.35, data: days.map(d => d.value), symbol: 'circle', symbolSize: days.length < 3 ? 9 : 5, showSymbol: days.length < 15, lineStyle: { width: 3, color: '#538641' }, itemStyle: { color: '#538641' }, areaStyle: { color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [{ offset: 0, color: '#b1ce91a6' }, { offset: 1, color: '#eaf0df05' }]) } }],
    }} /> : <EmptyChart>La selección no tiene fechas de publicación válidas.</EmptyChart>}
    <div className="panel-foot"><Info size={13} />{articles.length - valid} sin fecha, excluidas de la evolución.<span className="ml-auto">Clic en un punto para explorar <MoveUpRight size={12} /></span></div>
  </Panel>
}
function TopicsChartView({ articles, onTopic }: { articles: Article[]; onTopic: (topic: string) => void }) {
  const topics = countBy(articles.map(a => a.topic))
  return <Panel eyebrow="MAPA EDITORIAL" title="¿De qué se habla?" description="Distribución del tema principal">
    {topics.length ? <div className="donut-layout"><div className="donut"><Chart label="Distribución por tema principal" height={215} onClick={e => { const topic = topics.find(t => topicLabels[t.name] === e.name); if (topic) onTopic(topic.name) }} option={{ tooltip: { ...tooltip, formatter: '{b}: {c} noticias ({d}%)' }, series: [{ type: 'pie', radius: ['67%', '86%'], center: ['50%', '50%'], padAngle: 3, itemStyle: { borderRadius: 4 }, label: { show: false }, emphasis: { scaleSize: 5 }, data: topics.map(t => ({ name: topicLabels[t.name] ?? t.name, value: t.value, itemStyle: { color: topicColors[t.name] } })) }] }} /><div className="donut-center"><strong>{articles.length}</strong><span>noticias</span></div></div>
      <div className="topic-legend">{topics.map(t => <button key={t.name} onClick={() => onTopic(t.name)}><span className="legend-dot" style={{ backgroundColor: topicColors[t.name] }} /><span>{topicLabels[t.name] ?? t.name}</span><strong>{t.value}</strong><small>{Math.round(t.value / articles.length * 100)}%</small></button>)}</div></div> : <EmptyChart />}
    <div className="panel-foot"><Info size={13} />Clasificación por reglas sobre titulares y resúmenes.</div>
  </Panel>
}
function TeamsChartView({ articles, onTeam }: { articles: Article[]; onTeam: (team: string) => void }) {
  const teams = entityCounts(articles, 'teams')
  return <Panel eyebrow="PROTAGONISTAS" title="Equipos en el radar" description="El tamaño representa noticias que mencionan al equipo" action={<span className="chart-tag">{teams.length} equipos</span>}>
    {teams.length ? <Chart label="Treemap de equipos; pulsa un bloque para filtrar" height={280} onClick={e => { if (teams.some(t => t.name === e.name)) onTeam(e.name) }} option={{ tooltip: { ...tooltip, formatter: '{b}: {c} noticias' }, series: [{ type: 'treemap', roam: false, nodeClick: false, breadcrumb: { show: false }, left: 0, top: 12, right: 0, bottom: 12, squareRatio: 1.15, label: { show: true, formatter: '{b}\n{c} noticias', fontSize: 12, lineHeight: 22, color: '#fff', overflow: 'truncate' }, itemStyle: { borderColor: '#fff', borderWidth: 3, gapWidth: 3, borderRadius: 7 }, data: teams.map((t, i) => ({ ...t, itemStyle: { color: ['#1c5444', '#37745b', '#6e9257', '#96ac6d', '#527361', '#427e73', '#8d9c61'][i % 7] } })) }] }} /> : <EmptyChart>No se detectaron equipos en esta selección.</EmptyChart>}
    <div className="panel-foot"><Info size={13} />Una noticia puede mencionar varios equipos.<span className="ml-auto">Clic en un equipo <MoveUpRight size={12} /></span></div>
  </Panel>
}
function GraphChartPanelView({ articles, onEntity, large = false }: { articles: Article[]; onEntity: (key: 'team' | 'competition', value: string) => void; large?: boolean }) {
  const [minimum, setMinimum] = useState(1)
  const graph = entityGraph(articles, minimum)
  return <Panel eyebrow="MINERÍA DE RELACIONES" title="Todo está conectado" description="Equipos y competiciones que aparecen en una misma noticia" action={<select className="mini-select" aria-label="Mínimo de noticias compartidas" value={minimum} onChange={e => setMinimum(+e.target.value)}>{[1, 2, 3, 5].map(n => <option key={n} value={n}>≥ {n} {n === 1 ? 'noticia' : 'noticias'}</option>)}</select>}>
    {graph.links.length ? <Chart label="Red de coocurrencias de equipos y competiciones; los enlaces representan noticias compartidas" height={large ? 420 : 280} onClick={e => { if (e.dataType !== 'node') return; const data = e.data as { id: string; name: string }; onEntity(data.id.startsWith('t:') ? 'team' : 'competition', data.name) }} option={{ tooltip: { ...tooltip, formatter: (p: unknown) => { const d = (p as { data: { name?: string; value: number } }).data; return d.name ? `${d.name}: ${d.value} noticias` : `${d.value} noticias compartidas` } }, series: [{ type: 'graph', layout: 'force', roam: true, draggable: true, data: graph.nodes, links: graph.links.map(e => ({ ...e, lineStyle: { width: 1 + Math.sqrt(e.value), color: '#a8bfa7', opacity: 0.6, curveness: 0.07 } })), categories: [{ name: 'Equipo', itemStyle: { color: '#8fae67' } }, { name: 'Competición', itemStyle: { color: '#2c6757' } }], force: { repulsion: large ? 320 : 210, edgeLength: [65, 130], gravity: 0.12 }, label: { show: true, position: 'bottom', fontSize: 10, color: '#4f6357', width: 110, overflow: 'truncate' }, emphasis: { focus: 'adjacency' }, scaleLimit: { min: 0.5, max: 3 } }] }} /> : <EmptyChart>No hay relaciones con este mínimo de noticias compartidas.</EmptyChart>}
    <div className="panel-foot"><Network size={13} /><span className="legend-dot" style={{ background: '#8fae67' }} /> Equipo <span className="legend-dot" style={{ background: '#2c6757' }} /> Competición <span className="ml-auto">{graph.links.length} conexiones · hasta 28 nodos</span></div>
  </Panel>
}
function HeatmapChartView({ articles }: { articles: Article[] }) {
  const data = heatmapData(articles)
  const [cell, setCell] = useState<number[] | null>(null)
  const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
  const selected = cell ? data.find(d => d[0] === cell[0] && d[1] === cell[1]) : null
  return <Panel eyebrow="RITMO DE PUBLICACIÓN" title="¿Cuándo se mueve el fútbol?" description="Noticias por día de la semana y hora · UTC">
    {articles.some(a => a.date) ? <Chart label="Mapa de calor de publicaciones por día de semana y hora UTC" height={310} onClick={e => setCell(e.value as number[])} option={{ tooltip: { ...tooltip, formatter: (p: unknown) => { const [h, d, n] = (p as { value: number[] }).value; return `${days[d]} · ${h}:00 UTC\n${n} noticias` } }, grid: { left: 42, right: 20, top: 20, bottom: 80 }, xAxis: { type: 'category', data: Array.from({ length: 24 }, (_, i) => `${i}h`), splitArea: { show: true }, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: ink, fontSize: 10, interval: 2 } }, yAxis: { type: 'category', data: days, splitArea: { show: true }, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: ink, fontSize: 11 } }, visualMap: { min: 0, max: Math.max(1, ...data.map(d => d[2])), calculable: false, orient: 'horizontal', left: 'center', bottom: 4, itemHeight: 150, itemWidth: 9, text: ['Más noticias', 'Menos'], textStyle: { color: ink, fontSize: 10 }, inRange: { color: ['#f0f4e9', '#c5d9a3', '#7eab60', '#215d47'] } }, series: [{ type: 'heatmap', data, itemStyle: { borderWidth: 3, borderColor: '#fff', borderRadius: 3 }, emphasis: { itemStyle: { borderColor: '#90ad75' } } }] }} /> : <EmptyChart>Se necesitan fechas válidas para calcular los horarios.</EmptyChart>}
    <div className="panel-foot"><Info size={13} />{selected ? `${days[selected[1]]}, ${selected[0]}:00–${selected[0]}:59 UTC: ${selected[2]} noticias en la selección.` : 'Selecciona una celda para inspeccionar su frecuencia. No se imputan fechas.'}</div>
  </Panel>
}
function TermsChartView({ articles, onWord }: { articles: Article[]; onWord: (word: string) => void }) {
  const terms = termStats(articles).slice(0, 35)
  return <Panel eyebrow="MINERÍA DE TEXTO" title="Frecuentes vs. distintivas" description="TF-IDF recalculado sobre la selección · 35 términos más frecuentes">
    {terms.length ? <Chart label="Dispersión de términos por documentos y máximo TF-IDF; pulsa para buscar el término" height={310} onClick={e => onWord(e.name)} option={{ tooltip: { ...tooltip, formatter: (p: unknown) => { const t = (p as { data: { name: string; value: number[] } }).data; return `${t.name}\n${t.value[0]} documentos · ${t.value[2]} apariciones\nTF-IDF máximo: ${t.value[1].toFixed(3)}` } }, grid: { top: 24, right: 30, left: 64, bottom: 58 }, xAxis: { type: 'value', name: 'Documentos', nameLocation: 'middle', nameGap: 32, minInterval: 1, splitLine: { lineStyle: { color: '#f0f2ec' } }, axisLabel: { fontSize: 10, color: ink } }, yAxis: { type: 'value', name: 'TF-IDF máximo', nameTextStyle: { fontSize: 10 }, splitLine: { lineStyle: { color: '#f0f2ec', type: 'dashed' } }, axisLabel: { fontSize: 10, color: ink } }, series: [{ type: 'scatter', data: terms.map(t => ({ name: t.name, value: [t.documents, t.maxTfidf, t.frequency] })), symbolSize: (v: number[]) => 12 + Math.sqrt(v[2]) * 4, itemStyle: { color: '#6a9554', opacity: 0.7, borderColor: '#fff', borderWidth: 1 }, label: { show: true, formatter: '{b}', position: 'top', fontSize: 10, color: ink }, labelLayout: { hideOverlap: true }, emphasis: { focus: 'self', itemStyle: { color: '#1e5d47', opacity: 1 } } }] }} /> : <EmptyChart>No hay tokens disponibles para analizar.</EmptyChart>}
    <div className="panel-foot"><Info size={13} />Burbuja = apariciones. TF-IDF = (n / tokens del documento) × ln(N / documentos con el término).</div>
  </Panel>
}
// El sondeo del estado no debe reiniciar el zoom ni la posición de la red.
export const TrendChart = memo(TrendChartView)
export const TopicsChart = memo(TopicsChartView)
export const TeamsChart = memo(TeamsChartView)
export const GraphChartPanel = memo(GraphChartPanelView)
export const HeatmapChart = memo(HeatmapChartView)
export const TermsChart = memo(TermsChartView)
