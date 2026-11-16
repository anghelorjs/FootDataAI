import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Activity, ArrowDownToLine, ArrowRight, ArrowUpRight, Bot, Check, ChevronDown, ChevronRight, CircleHelp, Clock3, Database, Filter, LayoutDashboard, LoaderCircle, Menu, Network, Newspaper, RefreshCw, Search, Settings2, ShieldCheck, Sparkles, Tags, Users, X, WifiOff } from 'lucide-react'
import { request } from './api'
import { activeCount, countBy, dailyCounts, entityCounts, exportCsv, filterArticles, periodFilters, termStats } from './analytics'
import { emptyFilters, topicLabels, type Article, type Filters, type Page, type Snapshot, type UpdateStatus } from './types'
import { GraphChartPanel, HeatmapChart, TeamsChart, TermsChart, TopicsChart, TrendChart } from './components/Charts'
import { ArticleDialog, formatDate, NewsExplorer } from './components/News'
import Chat from './components/Chat'
import System from './components/System'

const navigation = [
  { id: 'overview', label: 'Panorama general', icon: LayoutDashboard, section: 'EXPLORAR' },
  { id: 'news', label: 'Noticias', icon: Newspaper },
  { id: 'mining', label: 'Laboratorio de datos', icon: Network },
  { id: 'chat', label: 'Asistente de fútbol', icon: Bot, section: 'CONECTAR' },
  { id: 'system', label: 'Fuentes y sistema', icon: Settings2 },
] as const
const pageNames: Record<Page, string> = { overview: 'Panorama general', news: 'Explorador de noticias', mining: 'Laboratorio de datos', chat: 'Asistente de fútbol', system: 'Fuentes y sistema' }
const pageDescriptions: Record<Page, string> = { overview: 'La actualidad del fútbol, con una perspectiva más amplia.', news: 'Encuentra la noticia. Sigue el tema. Conecta las piezas.', mining: 'Descubre relaciones y patrones en las noticias recopiladas.', chat: 'Una conversación para explorar lo que dicen los datos.', system: 'Conoce las fuentes y mantén actualizado tu observatorio.' }
function initialPage(): Page { const value = window.location.hash.slice(1); return navigation.some(n => n.id === value) ? value as Page : 'overview' }
function readSaved(): string[] { try { const value = JSON.parse(localStorage.getItem('footdata-saved') ?? '[]'); return Array.isArray(value) ? value.filter(v => typeof v === 'string') : [] } catch { return [] } }
const errorMessage = (error: unknown) => error instanceof Error ? error.message : 'Ocurrió un error inesperado.'

function Pitch() {
  return <svg className="pitch-art" viewBox="0 0 360 190" fill="none" aria-hidden="true"><defs><pattern id="pitch-grid" width="30" height="30" patternUnits="userSpaceOnUse"><path d="M30 0H0V30" stroke="#b4d888" strokeOpacity=".07" /></pattern><radialGradient id="pitch-glow"><stop stopColor="#b9e685" stopOpacity=".18"/><stop offset="1" stopColor="#b9e685" stopOpacity="0"/></radialGradient></defs><path fill="url(#pitch-grid)" d="M0 0h360v190H0z"/><ellipse cx="200" cy="95" rx="160" ry="110" fill="url(#pitch-glow)"/><g transform="translate(40 30) rotate(-12 135 65)" stroke="#c8e8a5" strokeOpacity=".36"><rect width="270" height="130" rx="3"/><path d="M135 0v130M0 30h42v70H0m270-70h-42v70h42M0 47h15v36H0m270-36h-15v36h15"/><circle cx="135" cy="65" r="27"/><circle cx="135" cy="65" r="2" fill="#d5f69c"/><path d="M42 46a24 24 0 0 1 0 38m186-38a24 24 0 0 0 0 38"/><path d="m72 94 36-53 68 47 42-61" stroke="#c5f36b" strokeDasharray="4 6" strokeOpacity=".8"/><circle cx="72" cy="94" r="5" fill="#c5f36b" stroke="none"/><circle cx="108" cy="41" r="5" fill="#c5f36b" stroke="none"/><circle cx="176" cy="88" r="5" fill="#c5f36b" stroke="none"/><circle cx="218" cy="27" r="7" fill="#c5f36b" stroke="none"/><circle cx="218" cy="27" r="13" stroke="#c5f36b" strokeOpacity=".4"/></g></svg>
}
function Brand() { return <div className="brand"><span className="brand-mark"><Activity size={24} strokeWidth={2.4} /></span><div>FootData<span>AI</span><small>FOOTBALL INTELLIGENCE</small></div></div> }
export default function App() {
  const [page, setPage] = useState<Page>(initialPage)
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [status, setStatus] = useState<UpdateStatus | null>(null)
  const [filters, setFilters] = useState<Filters>(emptyFilters)
  const [period, setPeriod] = useState('all')
  const [advanced, setAdvanced] = useState(false)
  const [saved, setSaved] = useState(readSaved)
  const [selected, setSelected] = useState<Article | null>(null)
  const [mobileMenu, setMobileMenu] = useState(false)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [offline, setOffline] = useState(false)
  const [toast, setToast] = useState<{ message: string; error?: boolean } | null>(null)
  const previous = useRef<UpdateStatus | null>(null)
  const navigate = (p: Page) => { window.location.hash = p; setPage(p); setMobileMenu(false); window.scrollTo({ top: 0, behavior: 'instant' }) }
  useEffect(() => { const change = () => setPage(initialPage()); window.addEventListener('hashchange', change); return () => window.removeEventListener('hashchange', change) }, [])
  useEffect(() => { const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') setMobileMenu(false) }; window.addEventListener('keydown', escape); return () => window.removeEventListener('keydown', escape) }, [])
  useEffect(() => { if (!toast) return; const timer = setTimeout(() => setToast(null), 6000); return () => clearTimeout(timer) }, [toast])
  const loadSnapshot = useCallback(async () => { const data = await request<Snapshot>('snapshot'); setSnapshot(data); setError('') }, [])
  const loadAll = useCallback(async () => {
    setLoading(true)
    const results = await Promise.allSettled([loadSnapshot(), request<UpdateStatus>('status')])
    if (results[0].status === 'rejected') setError(errorMessage(results[0].reason))
    if (results[1].status === 'fulfilled') { setStatus(results[1].value); previous.current = results[1].value; setOffline(false) }
    else setOffline(true)
    setLoading(false)
  }, [loadSnapshot])
  useEffect(() => { void loadAll() }, [loadAll])
  useEffect(() => {
    let alive = true
    let pending = false
    const poll = async () => {
      if (pending) return
      pending = true
      try {
        const value = await request<UpdateStatus>('status')
        if (!alive) return
        setStatus(value); setOffline(false)
        if (!value.running && previous.current && (previous.current.running || previous.current.updatedAt !== value.updatedAt)) {
          try { await loadSnapshot() } catch (error) { setToast({ message: errorMessage(error), error: true }) }
          if (value.state === 'COMPLETADO') setToast({ message: 'Noticias, gráficos y chatbot actualizados.' })
          else if (value.state === 'ERROR') setToast({ message: value.detail, error: true })
        }
        previous.current = value
      } catch { if (alive) setOffline(true) }
      finally { pending = false }
    }
    const interval = setInterval(() => void poll(), 5000)
    return () => { alive = false; clearInterval(interval) }
  }, [loadSnapshot])
  const articles = snapshot?.articles ?? []
  const filtered = useMemo(() => filterArticles(articles, filters), [articles, filters])
  const teams = entityCounts(filtered, 'teams')
  const topicCount = new Set(filtered.flatMap(a => a.topics)).size
  const validDates = filtered.filter(a => a.date).length
  const coverage = filtered.length ? Math.round(validDates / filtered.length * 100) : 0
  const optionsTeams = entityCounts(articles, 'teams')
  const optionsComps = entityCounts(articles, 'competitions')
  const optionsTopics = [...new Set(articles.flatMap(a => a.topics.length ? a.topics : ['sin_clasificar']))].sort()
  const sources = [...new Set(articles.map(a => a.source))].sort()
  const totalFilters = activeCount(filters)
  const chartFilter = useCallback((key: 'topic' | 'team' | 'competition' | 'query', value: string) => {
    setFilters(f => ({ ...f, [key]: value })); setToast({ message: `Filtro aplicado: ${topicLabels[value] ?? value}` })
  }, [])
  const topicFilter = useCallback((value: string) => chartFilter('topic', value), [chartFilter])
  const teamFilter = useCallback((value: string) => chartFilter('team', value), [chartFilter])
  const wordFilter = useCallback((value: string) => chartFilter('query', value), [chartFilter])
  const selectDay = useCallback((day: string) => { setFilters(f => ({ ...f, from: day, to: day, includeUndated: false })); setPeriod('custom'); setToast({ message: `Mostrando publicaciones del ${day} (UTC).` }) }, [])
  const patchFilter = <K extends keyof Filters>(key: K, value: Filters[K]) => setFilters(f => ({ ...f, [key]: value }))
  function save(id: string) {
    const next = saved.includes(id) ? saved.filter(s => s !== id) : [...saved, id]
    setSaved(next)
    try { localStorage.setItem('footdata-saved', JSON.stringify(next)) } catch { setToast({ message: 'No se pudo persistir la selección en este navegador.', error: true }) }
  }
  async function update() {
    setBusy(true)
    try { const data = await request<{ started: boolean; message: string; status: UpdateStatus }>('update', {}); setStatus(data.status); setToast({ message: data.message }); previous.current = data.status }
    catch (e) { setToast({ message: errorMessage(e), error: true }) }
    finally { setBusy(false) }
  }
  async function auto(value: boolean) {
    setBusy(true)
    try { const next = await request<UpdateStatus>('settings', { automatic: value }); setStatus(next); setToast({ message: `Actualización automática ${value ? 'activada' : 'desactivada'}.` }) }
    catch (e) { setToast({ message: errorMessage(e), error: true }) }
    finally { setBusy(false) }
  }
  async function reload() {
    setBusy(true)
    try { await loadSnapshot(); setToast({ message: 'Archivos locales recargados.' }) }
    catch (e) { setToast({ message: errorMessage(e), error: true }) }
    finally { setBusy(false) }
  }
  async function setIntervalMinutes(value: number) {
    setBusy(true)
    try {
      const next = await request<UpdateStatus>('settings', { intervalMinutes: value })
      setStatus(next)
      setToast({ message: `Intervalo solicitado: ${value} min. Se respeta el TTL/cache de la fuente.` })
    } catch (error) { setToast({ message: errorMessage(error), error: true }) }
    finally { setBusy(false) }
  }
  function download() {
    const url = URL.createObjectURL(new Blob([exportCsv(filtered)], { type: 'text/csv;charset=utf-8;' }))
    const a = document.createElement('a'); a.href = url; a.download = `footdata-noticias-${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(url)
    setToast({ message: `Exportadas ${filtered.length} noticias con los filtros actuales.` })
  }
  return <div className="app-shell">{mobileMenu && <button className="mobile-overlay" aria-label="Cerrar navegación" onClick={() => setMobileMenu(false)} />}
    <aside className={`sidebar ${mobileMenu ? 'sidebar-open' : ''}`}><Brand /><div className="workspace-label"><span className="workspace-avatar">FD</span><div>Observatorio de fútbol<small>Proyecto de minería de datos</small></div><ChevronDown size={13} /></div><nav aria-label="Navegación principal">{navigation.map(n => <div key={n.id}>{'section' in n && <span className="nav-section">{n.section}</span>}<button className={`nav-item ${page === n.id ? 'nav-active' : ''}`} aria-current={page === n.id ? 'page' : undefined} onClick={() => navigate(n.id)}><n.icon size={18} strokeWidth={1.7} /><span>{n.label}</span>{n.id === 'news' && <small>{articles.length}</small>}{n.id === 'chat' && <span className="nav-ai">LOCAL</span>}</button></div>)}</nav><div className="sidebar-bottom"><div className="sidebar-note"><div className="sidebar-note-icon"><Sparkles size={18} /></div><h4>El dato hace la diferencia.</h4><p>Descubre las conexiones que hay detrás de cada titular.</p><button onClick={() => navigate('mining')}>Explorar el laboratorio <ArrowUpRight size={14} /></button></div><div className="sidebar-status"><span className={`dot ${offline ? 'dot-red' : ''}`} /><span>{offline ? 'API sin conexión' : status?.running ? 'Actualizando noticias' : 'Datos conectados'}<small>R + SQLite + React</small></span><span className="version">v1.0</span></div></div></aside>
    <div className="main-shell"><header className="topbar"><button className="icon-button mobile-menu-button" aria-label="Abrir navegación" onClick={() => setMobileMenu(true)}><Menu size={21} /></button><div className="breadcrumb"><span>WORKSPACE</span><ChevronRight size={12} /><strong>{pageNames[page]}</strong></div><div className="topbar-right"><span className="live-tag"><span className={`dot ${offline ? 'dot-red' : ''}`} />{offline ? 'Sin conexión' : status?.running ? 'Sincronizando' : status?.automatic ? 'Sincronización activa' : 'Modo manual'}</span><button className="help-button" aria-label="Ver información del sistema" onClick={() => navigate('system')}><CircleHelp size={18} /></button><span className="profile-avatar">FD</span></div></header>
    <main><div className="page-heading"><div><div className="page-kicker"><span className="tiny-square" />FOOTBALL INTELLIGENCE PLATFORM</div><h1>{pageNames[page]}<span className="heading-dot">.</span></h1><p>{pageDescriptions[page]}</p></div><div className="page-actions">{page !== 'system' && <button className="button secondary export-button" onClick={download} disabled={!snapshot || !filtered.length}><ArrowDownToLine size={15} />Exportar CSV</button>}<button className="button primary" onClick={() => void update()} disabled={busy || !status || status.running || status.cooldownSeconds > 0} title={status && status.cooldownSeconds > 0 ? `Próxima consulta RSS en ${Math.ceil(status.cooldownSeconds / 60)} min` : 'Consultar RSS y ejecutar las fases de R'}>{status?.running || busy ? <LoaderCircle size={15} className="spin" /> : <RefreshCw size={15} />}<span>{status?.running ? 'Actualizando…' : 'Actualizar noticias'}</span></button></div></div>
    {offline && snapshot && <div className="connection-warning" role="status"><WifiOff size={16} />Se perdió la conexión con R. Se muestra la última instantánea cargada.<button onClick={() => void loadAll()}>Reconectar</button></div>}
    {status?.running && <div className="update-progress" role="status"><LoaderCircle size={15} className="spin" /><strong>Actualización en curso</strong><span>{status.phase} · {status.detail}</span><button onClick={() => navigate('system')}>Ver progreso <ArrowUpRight size={13} /></button></div>}
    {loading && !snapshot ? <div className="loading-state"><LoaderCircle size={30} className="spin" /><h3>Preparando tu observatorio…</h3><p>Conectando con los datos procesados en R.</p></div> : error && !snapshot ? <div className="empty-state api-error" role="alert"><Database size={36} strokeWidth={1.3} /><h2>No pudimos cargar las noticias</h2><p>{error}</p><code>Rscript api.R</code><button className="button primary" onClick={() => void loadAll()}><RefreshCw size={15} />Volver a intentar</button></div> : snapshot && <>
      {page !== 'system' && <section className="filter-bar" aria-label="Filtros de noticias"><div className="filter-main"><div className="filter-search"><Search size={16} /><input aria-label="Buscar noticias" placeholder="Buscar en las noticias…" value={filters.query} onChange={e => patchFilter('query', e.target.value)} />{filters.query && <button aria-label="Limpiar búsqueda" onClick={() => patchFilter('query', '')}><X size={13} /></button>}</div><div className="filter-select"><Clock3 size={14} /><select aria-label="Período de publicación" value={period} onChange={e => { setPeriod(e.target.value); if (e.target.value === 'custom') setAdvanced(true); else setFilters(f => ({ ...f, ...periodFilters(e.target.value === 'all' ? 0 : +e.target.value) })) }}><option value="all">Todo el historial</option><option value="7">Últimos 7 días</option><option value="30">Últimos 30 días</option><option value="90">Últimos 90 días</option><option value="custom">Personalizado</option></select></div><div className="filter-select"><select aria-label="Filtrar por tema" value={filters.topic} onChange={e => patchFilter('topic', e.target.value)}><option value="">Todos los temas</option>{optionsTopics.map(t => <option key={t} value={t}>{topicLabels[t] ?? t}</option>)}</select></div><div className="filter-select"><select aria-label="Filtrar por equipo" value={filters.team} onChange={e => patchFilter('team', e.target.value)}><option value="">Todos los equipos</option>{optionsTeams.map(t => <option key={t.name}>{t.name}</option>)}</select></div><button className={`button filter-toggle ${advanced ? 'active-filter' : ''}`} aria-expanded={advanced} onClick={() => setAdvanced(!advanced)}><Filter size={15} /><span>Filtros</span>{totalFilters > 0 && <b>{totalFilters}</b>}</button></div>
      {advanced && <div className="advanced-filters"><label>Canal RSS<select value={filters.source} onChange={e => patchFilter('source', e.target.value)}><option value="">Todos los canales</option>{sources.map(s => <option key={s}>{s}</option>)}</select></label><label>Competición<select value={filters.competition} onChange={e => patchFilter('competition', e.target.value)}><option value="">Todas las competiciones</option>{optionsComps.map(c => <option key={c.name}>{c.name}</option>)}</select></label><label>Desde (UTC)<input type="date" value={filters.from} max={filters.to || undefined} onChange={e => { patchFilter('from', e.target.value); setPeriod('custom') }} /></label><label>Hasta (UTC)<input type="date" value={filters.to} min={filters.from || undefined} onChange={e => { patchFilter('to', e.target.value); setPeriod('custom') }} /></label><label className="check-label"><input type="checkbox" checked={filters.includeUndated} onChange={e => patchFilter('includeUndated', e.target.checked)} />Incluir noticias sin fecha</label></div>}
      {(totalFilters > 0 || advanced) && <div className="active-filters"><span>{filtered.length} de {articles.length} noticias</span>{Object.entries(filters).filter(([k, v]) => k !== 'includeUndated' && Boolean(v)).map(([key, value]) => <button key={key} onClick={() => { patchFilter(key as keyof Filters, ''); if (key === 'from' || key === 'to') setPeriod('custom') }}>{key === 'from' ? 'Desde: ' : key === 'to' ? 'Hasta: ' : ''}{topicLabels[String(value)] ?? value}<X size={11} /></button>)}{!filters.includeUndated && <button onClick={() => patchFilter('includeUndated', true)}>Solo fechas válidas<X size={11} /></button>}<button className="clear-filters" onClick={() => { setFilters(emptyFilters); setPeriod('all') }}>Limpiar filtros</button></div>}</section>}
      {page === 'overview' && <><section className="hero-banner"><div className="hero-copy"><span className="hero-eyebrow"><span className="dot" />EL JUEGO, MÁS ALLÁ DEL MARCADOR</span><h2>Cada noticia cuenta.<br /><span>Encuentra lo que las conecta.</span></h2><p>De los titulares a los patrones. Explora el fútbol con datos.</p><button onClick={() => navigate('mining')}>Descubrir conexiones <ArrowUpRight size={15} /></button></div><Pitch /><div className="hero-caption"><span>FUENTE DE DATOS</span><strong><b>BBC</b> SPORT</strong></div></section><div className="kpi-grid"><Kpi icon={Newspaper} label="Noticias en el radar" value={filtered.length.toLocaleString('es-BO')} detail={`${articles.length} recopiladas en total`} spark={dailyCounts(filtered).map(d => d.value)} /><Kpi icon={Users} label="Equipos detectados" value={String(teams.length).padStart(2, '0')} detail="Menciones en titulares y resúmenes" /><Kpi icon={Tags} label="Temas de conversación" value={String(topicCount).padStart(2, '0')} detail={`${new Set(filtered.flatMap(a => a.competitions)).size} competiciones identificadas`} /><Kpi icon={ShieldCheck} label="Cobertura temporal" value={`${coverage}%`} detail={`${validDates} de ${filtered.length} con fecha válida`} progress={coverage} /></div><div className="chart-grid overview-top"><TrendChart articles={filtered} onDay={selectDay} /><TopicsChart articles={filtered} onTopic={topicFilter} /></div><div className="chart-grid"><TeamsChart articles={filtered} onTeam={teamFilter} /><GraphChartPanel articles={filtered} onEntity={chartFilter} /></div><NewsExplorer articles={filtered} saved={saved} onSave={save} onOpen={setSelected} compact onMore={() => navigate('news')} /><section className="chat-invite"><div className="assistant-avatar"><Bot size={24} /></div><div><h3>¿Qué está pasando en el fútbol?</h3><p>Pregúntaselo a tus datos. Tu asistente está listo.</p></div><button className="button primary" onClick={() => navigate('chat')}>Abrir asistente<ArrowRight size={15} /></button></section></>}
      {page === 'news' && <><div className="section-meta"><span><span className="dot" />{filtered.length} noticias en tu selección</span><span>Guardadas en este navegador: {saved.length}</span></div><NewsExplorer articles={filtered} saved={saved} onSave={save} onOpen={setSelected} /></>}
      {page === 'mining' && <><div className="mining-intro"><div className="mining-icon"><Network size={23} /></div><div><h3>La historia detrás de los titulares</h3><p>{filtered.length} documentos · {filtered.reduce((n, a) => n + a.tokens.length, 0).toLocaleString('es-BO')} tokens · {termStats(filtered).length.toLocaleString('es-BO')} términos distintos. Todos los análisis responden a tus filtros.</p></div><span className="outline-tag">ANÁLISIS DESCRIPTIVO</span></div><GraphChartPanel articles={filtered} onEntity={chartFilter} large /><div className="chart-grid"><HeatmapChart articles={filtered} /><TermsChart articles={filtered} onWord={wordFilter} /></div><div className="chart-grid"><TeamsChart articles={filtered} onTeam={teamFilter} /><TopicsChart articles={filtered} onTopic={topicFilter} /></div><div className="methodology"><CircleHelp size={18} /><div><strong>Cómo leer estos datos</strong><p>La red muestra coocurrencia, no causalidad. TF-IDF mide qué distingue un término dentro de este conjunto; no su relevancia deportiva. Los equipos y temas se detectan por diccionarios, con posibles omisiones. Las publicaciones sin fecha no entran en los análisis temporales. Una muestra pequeña describe únicamente las noticias recopiladas.</p></div></div></>}
      <div hidden={page !== 'chat'}>{/* Mantiene la conversación al navegar entre secciones. */}<Chat articles={articles} filtered={filtered} filters={filters} onOpen={setSelected} /></div>
      {page === 'system' && <System snapshot={snapshot} status={status} onUpdate={() => void update()} onAuto={value => void auto(value)} onInterval={value => void setIntervalMinutes(value)} onReload={() => void reload()} busy={busy} />}
      <footer className="page-footer"><span><Activity size={13} />FootDataAI<span className="footer-separator">/</span>Del fútbol al conocimiento.</span><span>{snapshot.meta.extractedAt ? `Última extracción: ${formatDate(snapshot.meta.extractedAt, true)} UTC` : 'Sin registro de extracción'}<span className="footer-separator">·</span>BBC Sport RSS</span></footer>
    </>}
    </main></div>{selected && <ArticleDialog article={selected} onClose={() => setSelected(null)} saved={saved.includes(selected.id)} onSave={save} />}{toast && <div className={`toast ${toast.error ? 'toast-error' : ''}`} role={toast.error ? 'alert' : 'status'}>{toast.error ? <CircleHelp size={18} /> : <Check size={18} />}<span>{toast.message}</span><button aria-label="Cerrar aviso" onClick={() => setToast(null)}><X size={15} /></button></div>}
  </div>
}
function Kpi({ icon: Icon, label, value, detail, progress, spark }: { icon: typeof Newspaper; label: string; value: string; detail: string; progress?: number; spark?: number[] }) {
  const max = Math.max(...(spark ?? []), 1)
  return <section className="kpi-card"><div className="kpi-label">{label}<span><Icon size={16} strokeWidth={1.6} /></span></div><div className="kpi-value">{value}{spark && spark.length > 1 && <svg width="92" height="33" viewBox="0 0 92 33" aria-label="Miniatura de la evolución diaria"><polyline fill="none" stroke="#7eab5d" strokeWidth="2" strokeLinejoin="round" points={spark.map((v, i) => `${i / (spark.length - 1) * 90 + 1},${31 - v / max * 28}`).join(' ')} /></svg>}{progress !== undefined && <div className="kpi-progress" aria-hidden="true"><span style={{ width: `${progress}%` }} /></div>}</div><p>{detail}</p></section>
}
