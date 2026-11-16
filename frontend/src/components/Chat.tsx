import { useEffect, useRef, useState, type FormEvent } from 'react'
import { ArrowUpRight, BookOpen, Bot, CheckCheck, CornerDownLeft, Send, Sparkles, Trash2, User, LoaderCircle, ShieldCheck, X } from 'lucide-react'
import { request } from '../api'
import { entityCounts } from '../analytics'
import { type Article, type ChatResponse, type Filters } from '../types'
import { formatDate } from './News'

interface Message {
  id: number; role: 'user' | 'assistant'; text: string
  articles?: string[]; count?: number; error?: boolean
}
const intro: Message = {
  id: 0, role: 'assistant',
  text: 'Hola, soy tu asistente de fútbol. Puedo encontrar noticias y mostrarte lo que indican sus titulares y resúmenes RSS. Después de una búsqueda, pide «resume estas noticias» o elige «Leer resumen» en un resultado. Si hay varios, también puedes decir «la primera» o «la segunda».',
}

export default function Chat({ articles, filtered, filters, onOpen }: {
  articles: Article[]; filtered: Article[]; filters: Filters; onOpen: (a: Article) => void
}) {
  const [messages, setMessages] = useState<Message[]>([intro])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [contextIds, setContextIds] = useState<string[]>([])
  const [useFilters, setUseFilters] = useState(false)
  const pending = useRef(false)
  const sequence = useRef(0)
  const bottom = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  const currentArticles = useFilters ? filtered : articles
  const currentIds = new Set(currentArticles.map(a => a.id))
  const availableContext = contextIds.filter(id => currentIds.has(id))
  const teams = entityCounts(currentArticles, 'teams').slice(0, 3)
  const suggestions = availableContext.length > 0
    ? [availableContext.length === 1 ? '¿Qué indica esta noticia?' : 'Resume estas noticias', 'Últimas noticias', '¿Cuántas noticias hay?']
    : ['Últimas noticias', '¿Cuántas noticias hay?', 'Noticias de fichajes', 'Equipos más mencionados']

  useEffect(() => {
    if (messages.length > 1 || busy) bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [messages, busy])

  async function send(question: string, selectedIds?: string[]) {
    if (pending.current || !question.trim()) return
    pending.current = true
    setBusy(true); setInput('')
    const questionMessage: Message = { id: ++sequence.current, role: 'user', text: question.trim() }
    setMessages(old => [...old, questionMessage])
    try {
      const data = await request<ChatResponse>('chat', {
        question: question.trim(), contextIds: selectedIds ?? contextIds,
        ...(useFilters ? { filters } : {}),
      })
      setContextIds(data.contextIds ?? data.articles)
      const answerMessage: Message = {
        id: ++sequence.current, role: 'assistant', text: data.text,
        articles: data.articles, count: data.scopeCount,
      }
      setMessages(old => [...old, answerMessage])
    } catch (error) {
      const errorMessage: Message = {
        id: ++sequence.current, role: 'assistant',
        text: error instanceof Error ? error.message : 'No se pudo consultar el chatbot.', error: true,
      }
      setMessages(old => [...old, errorMessage])
    } finally {
      pending.current = false
      setBusy(false); inputRef.current?.focus()
    }
  }
  function submit(e: FormEvent) { e.preventDefault(); void send(input) }
  function reset() { setMessages([intro]); setContextIds([]); setInput('') }

  return <div className="chat-layout">
    <section className="chat-main panel">
      <div className="chat-top">
        <div className="assistant-avatar"><Bot size={23} /></div>
        <div><h3>Tu asistente de fútbol</h3><p><span className="dot" />Búsqueda y lectura del RSS · sin modelos de IA</p></div>
        <button className="icon-button ml-auto" disabled={busy || messages.length < 2} title="Nueva conversación" aria-label="Nueva conversación" onClick={reset}><Trash2 size={17} /></button>
      </div>
      <div className="chat-messages" aria-live="polite" aria-relevant="additions">
        {messages.map(m => <div className={`message message-${m.role} ${m.error ? 'message-error' : ''}`} key={m.id}>
          <div className="message-avatar">{m.role === 'assistant' ? <Bot size={17} /> : <User size={16} />}</div>
          <div className="message-body">
            <span className="message-author">{m.role === 'assistant' ? 'FootData · Asistente' : 'Tú'}</span>
            <p>{m.text}</p>
            {m.articles && m.articles.length > 0 && <div className="chat-sources">
              {m.articles.map((id, index) => {
                const a = articles.find(a => a.id === id)
                return a && <div key={id} className="chat-source">
                  <button className="chat-source-open" onClick={() => onOpen(a)}>
                    <span><small>[{index + 1}] BBC SPORT · {formatDate(a.date)}</small><strong>{a.title}</strong></span><ArrowUpRight size={17} />
                  </button>
                  <button className="chat-read" disabled={busy} onClick={() => void send('¿Qué indica esta noticia?', [id])} aria-label={`Leer resumen de: ${a.title}`}><BookOpen size={12} />Leer resumen</button>
                </div>
              })}
            </div>}
            {m.count !== undefined && <small className="message-scope"><CheckCheck size={12} />Consultadas {m.count} noticias de la base local</small>}
          </div>
        </div>)}
        {busy && <div className="message message-assistant"><div className="message-avatar"><Bot size={17} /></div><div className="typing"><span /><span /><span /><small>Consultando las noticias…</small></div></div>}
        <div ref={bottom} />
      </div>
      <div className="chat-compose">
        {contextIds.length > 0 && <div className="chat-followup">
          <BookOpen size={13} /><span>{availableContext.length} noticia(s) en el contexto actual</span>
          <button disabled={busy} onClick={() => setContextIds([])} aria-label="Quitar contexto de noticias" title="Quitar contexto de noticias"><X size={13} /></button>
        </div>}
        <div className="chat-suggestions">{suggestions.map(q => <button disabled={busy} key={q} onClick={() => void send(q)}>{q}<ArrowUpRight size={12} /></button>)}</div>
        <form onSubmit={submit}>
          <textarea aria-label="Pregunta al asistente" ref={inputRef} value={input} maxLength={1000} placeholder={availableContext.length ? 'Pide un resumen o pregunta por la primera o la segunda noticia…' : 'Busca un equipo, una persona o un tema…'} rows={2} onChange={e => setInput(e.target.value)} onKeyDown={e => {
            if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); void send(input) }
          }} />
          <button aria-label="Enviar pregunta" type="submit" disabled={busy || !input.trim()}>{busy ? <LoaderCircle className="spin" size={18} /> : <Send size={18} />}</button>
        </form>
        <div className="compose-hint"><span><CornerDownLeft size={11} />Enter para enviar · Shift + Enter para nueva línea</span><span>{input.length}/1000</span></div>
      </div>
    </section>
    <aside className="chat-context">
      <div className="context-card">
        <Sparkles size={23} /><span className="eyebrow">CONOCIMIENTO EN CONTEXTO</span><h3>Lo que dice la noticia, con su fuente.</h3>
        <p>Busca noticias y continúa la conversación sobre sus resúmenes. Los textos se extraen del RSS y mantienen su idioma original.</p>
        <div className="context-count"><strong>{currentArticles.length}</strong><span>noticias disponibles</span></div>
        <label className="check-label"><input type="checkbox" checked={useFilters} disabled={busy} onChange={e => setUseFilters(e.target.checked)} />Aplicar filtros del panel al chat</label>
      </div>
      <div className="panel context-links"><h4>Explora los protagonistas</h4>{teams.length ? teams.map(t => <button disabled={busy} onClick={() => void send(`Noticias sobre ${t.name}`)} key={t.name}><span>{t.name}<small>{t.value} noticias</small></span><ArrowUpRight size={15} /></button>) : <p>Amplía los filtros para encontrar equipos.</p>}</div>
      <div className="chat-note"><ShieldCheck size={18} /><p>Lectura extractiva por reglas, sin modelos de IA ni traducción automática. Solo se dispone del titular y del resumen RSS. Si falta un dato o hay varias noticias posibles, el asistente lo indica.</p></div>
    </aside>
  </div>
}
