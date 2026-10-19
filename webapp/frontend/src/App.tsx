import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  ShieldCheck, Send, Loader2, CheckCircle2, AlertTriangle,
  Sparkles, Database, Activity, LogOut, Lock,
} from 'lucide-react'
import { loadConfig, signIn, streamInvestigation, type RuntimeConfig } from './api'
import { toolMeta, EXAMPLE_QUERIES } from './lib/tools'

interface TraceItem {
  id: string
  name: string
  status: 'running' | 'success' | 'error'
  input?: string
  summary?: string
}
interface Turn {
  user: string
  traces: TraceItem[]
  report: string
  error?: string
  running: boolean
}

export default function App() {
  const [config, setConfig] = useState<RuntimeConfig>({ wsUrl: '', identityPoolId: '', region: '', userPoolId: '', clientId: '' })
  const [loaded, setLoaded] = useState(false)
  const [idToken, setIdToken] = useState<string | null>(null)
  const [email, setEmail] = useState('')
  const [sessionId, setSessionId] = useState<string>(() => crypto.randomUUID())
  const [turns, setTurns] = useState<Turn[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => { (async () => { setConfig(await loadConfig()); setLoaded(true) })() }, [])
  useEffect(() => { scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' }) }, [turns])

  const configured = !!config.wsUrl && !!config.identityPoolId && !!config.region && !!config.userPoolId && !!config.clientId
  const latestReport = useMemo(() => {
    for (let i = turns.length - 1; i >= 0; i--) if (turns[i].report) return turns[i].report
    return ''
  }, [turns])

  const signOut = () => { setIdToken(null); setTurns([]); setEmail(''); setSessionId(crypto.randomUUID()) }

  const send = useCallback(async (prompt: string) => {
    if (!prompt.trim() || busy || !configured || !idToken) return
    const history = turns.flatMap((t) => {
      const msgs = [{ role: 'user' as const, content: t.user }]
      if (t.report) msgs.push({ role: 'assistant' as const, content: t.report })
      return msgs
    })
    setInput(''); setBusy(true)
    setTurns((prev) => [...prev, { user: prompt, traces: [], report: '', running: true }])
    const idx = turns.length
    const patch = (fn: (t: Turn) => Turn) => setTurns((prev) => prev.map((t, i) => (i === idx ? fn(t) : t)))
    try {
      for await (const ev of streamInvestigation({ config, idToken, prompt, history, sessionId, actorId: email })) {
        if (ev.type === 'trace' && ev.event === 'tool_start') {
          patch((t) => ({ ...t, traces: [...t.traces, { id: ev.id, name: ev.name, status: 'running', input: fmtInput(ev.input) }] }))
        } else if (ev.type === 'trace' && ev.event === 'tool_end') {
          patch((t) => ({ ...t, traces: t.traces.map((tr) => tr.id === ev.id ? { ...tr, status: ev.status === 'success' ? 'success' : 'error', summary: ev.summary } : tr) }))
        } else if (ev.type === 'response') {
          patch((t) => ({ ...t, report: ev.text }))
        } else if (ev.type === 'error') {
          patch((t) => ({ ...t, error: ev.message }))
        }
      }
    } catch (e) {
      patch((t) => ({ ...t, error: e instanceof Error ? e.message : String(e) }))
    } finally {
      patch((t) => ({ ...t, running: false })); setBusy(false)
    }
  }, [config, idToken, busy, configured, turns, sessionId, email])

  return (
    <div className="flex h-full flex-col">
      <Header configured={configured} email={idToken ? email : null} onSignOut={signOut} />
      {!loaded ? (
        <Centered><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Loading…</Centered>
      ) : !configured ? (
        <Centered><AlertTriangle className="mr-2 h-5 w-5 text-amber-400" /> config.json is missing required fields.</Centered>
      ) : !idToken ? (
        <Login config={config} onSignedIn={(tok, mail) => { setIdToken(tok); setEmail(mail) }} />
      ) : (
        <div className="mx-auto flex w-full max-w-[1600px] flex-1 flex-col gap-3 overflow-hidden px-3 pb-3 xl:flex-row">
          <section className="flex min-h-0 min-w-0 flex-1 flex-col rounded-2xl border border-ink-800 bg-ink-900/60 backdrop-blur xl:flex-[1.4]">
            <div ref={scrollRef} className="min-h-0 flex-1 space-y-6 overflow-y-auto p-5">
              {turns.length === 0 ? <EmptyState onPick={send} disabled={busy} /> : turns.map((t, i) => <TurnView key={i} turn={t} />)}
            </div>
            <Composer input={input} setInput={setInput} onSend={() => send(input)} busy={busy} />
          </section>
          <aside className="flex min-h-0 min-w-0 flex-col rounded-2xl border border-ink-800 bg-ink-900/60 backdrop-blur max-xl:h-[42vh] xl:flex-1">
            <div className="flex items-center gap-2 border-b border-ink-800 px-5 py-4">
              <div className="grid h-8 w-8 place-items-center rounded-lg bg-amber-500/10 ring-1 ring-amber-500/30"><ShieldCheck className="h-4 w-4 text-amber-300" /></div>
              <div><h2 className="text-sm font-semibold text-slate-100">Investigation Report</h2><p className="text-xs text-slate-500">Latest agent output</p></div>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto p-5">
              {latestReport ? (
                <div className="report-md text-sm text-slate-200"><ReactMarkdown remarkPlugins={[remarkGfm]}>{latestReport}</ReactMarkdown></div>
              ) : (
                <div className="flex h-full flex-col items-center justify-center text-center text-slate-600"><Database className="mb-3 h-10 w-10 opacity-40" /><p className="text-sm">The investigation report will appear here.</p></div>
              )}
            </div>
          </aside>
        </div>
      )}
    </div>
  )
}

function Centered({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-1 items-center justify-center text-sm text-slate-400">{children}</div>
}

function Login({ config, onSignedIn }: { config: RuntimeConfig; onSignedIn: (t: string, email: string) => void }) {
  const [u, setU] = useState('')
  const [p, setP] = useState('')
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(false)
  const submit = async () => {
    if (!u || !p) return
    setLoading(true); setErr('')
    try {
      const tok = await signIn(config, u.trim(), p)
      onSignedIn(tok, u.trim())
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally { setLoading(false) }
  }
  return (
    <div className="flex flex-1 items-center justify-center px-4">
      <div className="w-full max-w-sm rounded-2xl border border-ink-800 bg-ink-900/70 p-7 backdrop-blur">
        <div className="mb-5 flex flex-col items-center text-center">
          <div className="mb-3 grid h-12 w-12 place-items-center rounded-xl bg-gradient-to-br from-brand-teal/20 to-brand-cyan/10 ring-1 ring-brand-teal/30"><Lock className="h-5 w-5 text-brand-teal" /></div>
          <h2 className="text-lg font-bold text-slate-100">Sign in</h2>
          <p className="mt-1 text-xs text-slate-400">Fraud Intelligence Console — authorized analysts only</p>
        </div>
        <label className="mb-1 block text-xs font-medium text-slate-400">Email</label>
        <input value={u} onChange={(e) => setU(e.target.value)} autoComplete="username" type="email"
          className="mb-3 w-full rounded-lg border border-ink-700 bg-ink-850 px-3 py-2 text-sm text-slate-100 focus:border-brand-teal/50 focus:outline-none" />
        <label className="mb-1 block text-xs font-medium text-slate-400">Password</label>
        <input value={p} onChange={(e) => setP(e.target.value)} type="password" autoComplete="current-password"
          onKeyDown={(e) => { if (e.key === 'Enter') submit() }}
          className="mb-4 w-full rounded-lg border border-ink-700 bg-ink-850 px-3 py-2 text-sm text-slate-100 focus:border-brand-teal/50 focus:outline-none" />
        {err && <div className="mb-3 flex items-start gap-2 rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-xs text-rose-200"><AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />{err}</div>}
        <button onClick={submit} disabled={loading || !u || !p}
          className="flex w-full items-center justify-center gap-2 rounded-lg bg-brand-teal py-2.5 text-sm font-semibold text-ink-950 transition hover:bg-teal-300 disabled:opacity-40">
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Sign in'}
        </button>
      </div>
    </div>
  )
}

function Header({ configured, email, onSignOut }: { configured: boolean; email: string | null; onSignOut: () => void }) {
  return (
    <header className="flex items-center justify-between px-6 py-4">
      <div className="flex items-center gap-3">
        <div className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-brand-teal/20 to-brand-cyan/10 ring-1 ring-brand-teal/30"><ShieldCheck className="h-5 w-5 text-brand-teal" /></div>
        <div>
          <h1 className="text-[15px] font-bold tracking-tight text-slate-50">Fraud Intelligence Console</h1>
          <p className="text-xs text-slate-400">Amazon Bedrock AgentCore <span className="text-slate-600">×</span> Snowflake Cortex</p>
        </div>
      </div>
      <div className="flex items-center gap-3">
        {email ? (
          <>
            <span className="hidden text-xs text-slate-400 sm:inline">{email}</span>
            <button onClick={onSignOut} className="flex items-center gap-1.5 rounded-lg border border-ink-700 px-3 py-1.5 text-xs text-slate-300 transition hover:bg-ink-800"><LogOut className="h-3.5 w-3.5" /> Sign out</button>
          </>
        ) : (
          <span className={`flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ${configured ? 'bg-ink-800 text-slate-300 ring-1 ring-ink-700' : 'bg-amber-500/10 text-amber-300 ring-1 ring-amber-500/30'}`}>
            <Lock className="h-3 w-3" /> {configured ? 'Sign-in required' : 'Not configured'}
          </span>
        )}
      </div>
    </header>
  )
}

function EmptyState({ onPick, disabled }: { onPick: (p: string) => void; disabled: boolean }) {
  return (
    <div className="flex h-full flex-col items-center justify-center py-10">
      <div className="mb-2 flex items-center gap-2 rounded-full bg-ink-800/70 px-3 py-1 text-xs text-brand-teal ring-1 ring-brand-teal/20"><Sparkles className="h-3.5 w-3.5" /> Grounded in governed Snowflake data</div>
      <h2 className="mb-1 mt-3 text-center text-2xl font-bold text-slate-100">Investigate a transaction</h2>
      <p className="mb-7 max-w-md text-center text-sm text-slate-400">Ask in plain language. The agent queries Snowflake Cortex, enriches with IP geolocation and web search, writes a report, and can email the fraud team.</p>
      <div className="grid w-full max-w-2xl gap-2.5 sm:grid-cols-2">
        {EXAMPLE_QUERIES.map((q) => (
          <button key={q.short} disabled={disabled} onClick={() => onPick(q.prompt)} className="group rounded-xl border border-ink-800 bg-ink-850/60 p-3.5 text-left transition hover:border-brand-teal/40 hover:bg-ink-800 disabled:opacity-50">
            <span className="text-sm font-medium text-slate-200 group-hover:text-white">{q.short}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

function TurnView({ turn }: { turn: Turn }) {
  return (
    <div className="animate-fade-up space-y-3">
      <div className="flex justify-end"><div className="max-w-[85%] rounded-2xl rounded-br-sm bg-brand-teal/15 px-4 py-2.5 text-sm text-teal-50 ring-1 ring-brand-teal/25">{turn.user}</div></div>
      {(turn.traces.length > 0 || turn.running) && (
        <div className="rounded-2xl border border-ink-800 bg-ink-850/50 p-3">
          <div className="mb-2 flex items-center gap-2 px-1 text-xs font-medium text-slate-400"><Activity className="h-3.5 w-3.5 text-brand-teal" /> Agent activity</div>
          <div className="space-y-1.5">
            {turn.traces.map((tr) => <TraceRow key={tr.id} trace={tr} />)}
            {turn.running && turn.traces.every((t) => t.status !== 'running') && (<div className="flex items-center gap-2 px-2 py-1 text-xs text-slate-500"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Reasoning…</div>)}
          </div>
        </div>
      )}
      {turn.error && (<div className="flex items-start gap-2 rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /><div><span className="font-semibold">Error:</span> {turn.error}</div></div>)}
      {turn.report && (
        <div className="flex items-center gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-2.5 text-sm text-emerald-200"><CheckCircle2 className="h-4 w-4 shrink-0" /> Investigation report ready &mdash; see the report panel.</div>
      )}
    </div>
  )
}

function TraceRow({ trace }: { trace: TraceItem }) {
  const meta = toolMeta(trace.name)
  const { Icon } = meta
  return (
    <div className={`rounded-lg border ${meta.ring} bg-ink-900/70 px-3 py-2`}>
      <div className="flex items-center gap-2.5">
        <div className="grid h-7 w-7 shrink-0 place-items-center rounded-md bg-ink-800"><Icon className={`h-4 w-4 ${meta.color}`} /></div>
        <span className="text-sm font-medium text-slate-200">{meta.label}</span>
        <span className="ml-auto">
          {trace.status === 'running' && <Loader2 className="h-4 w-4 animate-spin text-brand-teal" />}
          {trace.status === 'success' && <CheckCircle2 className="h-4 w-4 text-emerald-400" />}
          {trace.status === 'error' && <AlertTriangle className="h-4 w-4 text-rose-400" />}
        </span>
      </div>
      {trace.input && trace.status === 'running' && <p className="mt-1 truncate pl-9 font-mono text-[11px] text-slate-500">{trace.input}</p>}
      {trace.summary && trace.status !== 'running' && <p className="mt-1 line-clamp-2 pl-9 text-[11px] text-slate-400">{trace.summary}</p>}
    </div>
  )
}

function Composer({ input, setInput, onSend, busy }: { input: string; setInput: (v: string) => void; onSend: () => void; busy: boolean }) {
  return (
    <div className="border-t border-ink-800 p-3">
      <div className="flex items-end gap-2 rounded-xl border border-ink-700 bg-ink-850 px-3 py-2 focus-within:border-brand-teal/50">
        <textarea value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); onSend() } }} rows={1}
          placeholder="Ask about a transaction, customer, or merchant…"
          className="max-h-32 flex-1 resize-none bg-transparent py-1 text-sm text-slate-100 placeholder:text-slate-500 focus:outline-none" />
        <button onClick={onSend} disabled={busy || !input.trim()} className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-brand-teal text-ink-950 transition hover:bg-teal-300 disabled:cursor-not-allowed disabled:opacity-40">
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
        </button>
      </div>
    </div>
  )
}

function fmtInput(input: unknown): string {
  if (input == null) return ''
  if (typeof input === 'string') return input
  try { return JSON.stringify(input) } catch { return String(input) }
}
