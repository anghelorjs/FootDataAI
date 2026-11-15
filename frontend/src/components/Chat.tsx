import { useEffect, useRef, useState, type FormEvent } from 'react'
import { ArrowUpRight, Bot, CheckCheck, CornerDownLeft, Send, Sparkles, Trash2, User, LoaderCircle, ShieldCheck } from 'lucide-react'
import { request } from '../api'
import { entityCounts } from '../analytics'
import { type Article, type ChatResponse, type Filters } from '../types'
import { formatDate } from './News'

interface Message { id: number; role: 'user' | 'assistant'; text: string; articles?: string[]; count?: number; error?: boolean }
const intro: Message = { id: 0, role: 'assistant', text: 'Hola, soy tu asistente de fútbol. Consulto las noticias recopiladas para ayudarte a encontrar titulares, explorar equipos y descubrir qué temas aparecen más. ¿Por dónde empezamos?' }
export default function Chat({ articles, filtered, filters, onOpen }: { articles: Article[]; filtered: Article[]; filters: Filters; onOpen: (a: Article) => void }) {
  const [messages, setMessages] = useState<Message[]>([intro])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [useFilters, setUseFilters] = useState(false)
  const bottom = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  const currentArticles = useFilters ? filtered : articles
  const teams = entityCounts(currentArticles, 'teams').slice(0, 3)
  const suggestions = ['Últimas noticias', '¿Cuántas noticias hay?', 'Noticias de fichajes', 'Equipos más mencionados']
  useEffect(() => { if (messages.length > 1 || busy) bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }) }, [messages, busy])
  async function send(question: string) {
    if (busy || !question.trim()) return
    setBusy(true); setInput('')
    setMessages(old => [...old, { id: Date.now(), role: 'user', text: question.trim() }])
    try {
      const data = await request<ChatResponse>('chat', { question: question.trim(), ...(useFilters ? { filters } : {}) })
      setMessages(old => [...old, { id: Date.now() + 1, role: 'assistant', text: data.text, articles: data.articles, count: data.scopeCount }])
    } catch (error) { setMessages(old => [...old, { id: Date.now() + 1, role: 'assistant', text: error instanceof Error ? error.message : 'No se pudo consultar el chatbot.', error: true }]) }
    finally { setBusy(false); inputRef.current?.focus() }
  }
  function submit(e: FormEvent) { e.preventDefault(); void send(input) }
  return <div className="chat-layout"><section className="chat-main panel"><div className="chat-top"><div className="assistant-avatar"><Bot size={23} /></div><div><h3>Tu asistente de fútbol</h3><p><span className="dot" />Conectado a la base de noticias</p></div><button className="icon-button ml-auto" disabled={busy || messages.length < 2} title="Nueva conversación" aria-label="Nueva conversación" onClick={() => setMessages([intro])}><Trash2 size={17} /></button></div><div className="chat-messages" aria-live="polite" aria-relevant="additions">{messages.map(m => <div className={`message message-${m.role} ${m.error ? 'message-error' : ''}`} key={m.id}><div className="message-avatar">{m.role === 'assistant' ? <Bot size={17} /> : <User size={16} />}</div><div className="message-body"><span className="message-author">{m.role === 'assistant' ? 'FootData · Asistente' : 'Tú'}</span><p>{m.text}</p>{m.articles && m.articles.length > 0 && <div className="chat-sources">{m.articles.map(id => { const a = articles.find(a => a.id === id); return a && <button key={id} onClick={() => onOpen(a)}><span><small>BBC SPORT · {formatDate(a.date)}</small><strong>{a.title}</strong></span><ArrowUpRight size={17} /></button> })}</div>}{m.count !== undefined && <small className="message-scope"><CheckCheck size={12} />Consultadas {m.count} noticias de la base local</small>}</div></div>)}{busy && <div className="message message-assistant"><div className="message-avatar"><Bot size={17} /></div><div className="typing"><span /><span /><span /><small>Consultando las noticias…</small></div></div>}<div ref={bottom} /></div><div className="chat-compose"><div className="chat-suggestions">{suggestions.slice(0, messages.length > 1 ? 2 : 4).map(q => <button disabled={busy} key={q} onClick={() => void send(q)}>{q}<ArrowUpRight size={12} /></button>)}</div><form onSubmit={submit}><textarea aria-label="Pregunta al asistente" ref={inputRef} value={input} maxLength={1000} placeholder="Pregunta por un equipo, un tema o las últimas noticias…" rows={2} onChange={e => setInput(e.target.value)} onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); void send(input) } }} /><button aria-label="Enviar pregunta" type="submit" disabled={busy || !input.trim()}>{busy ? <LoaderCircle className="spin" size={18} /> : <Send size={18} />}</button></form><div className="compose-hint"><span><CornerDownLeft size={11} /> Enter para enviar · Shift + Enter para nueva línea</span><span>{input.length}/1000</span></div></div></section><aside className="chat-context"><div className="context-card"><Sparkles size={23} /><span className="eyebrow">CONOCIMIENTO EN CONTEXTO</span><h3>Respuestas con los pies en la cancha.</h3><p>El asistente busca en los titulares y resúmenes recopilados. Cada resultado enlaza con su noticia.</p><div className="context-count"><strong>{currentArticles.length}</strong><span>noticias disponibles</span></div><label className="check-label"><input type="checkbox" checked={useFilters} onChange={e => setUseFilters(e.target.checked)} />Aplicar filtros del panel al chat</label></div><div className="panel context-links"><h4>Explora los protagonistas</h4>{teams.length ? teams.map(t => <button disabled={busy} onClick={() => void send(`Noticias sobre ${t.name}`)} key={t.name}><span>{t.name}<small>{t.value} noticias</small></span><ArrowUpRight size={15} /></button>) : <p>Amplía los filtros para encontrar equipos.</p>}</div><div className="chat-note"><ShieldCheck size={18} /><p>Motor local por reglas y búsqueda. No inventa resultados deportivos ni consulta un modelo de IA externo. Los titulares se conservan en su idioma original.</p></div></aside></div>
}
