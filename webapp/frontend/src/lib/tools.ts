import { Snowflake, Globe, Search, FileText, Mail, Wrench, type LucideIcon } from 'lucide-react'

export interface ToolMeta {
  label: string
  Icon: LucideIcon
  color: string // tailwind text color class
  ring: string // tailwind ring/border color
}

export const TOOL_META: Record<string, ToolMeta> = {
  query_snowflake: { label: 'Snowflake Cortex', Icon: Snowflake, color: 'text-cyan-300', ring: 'border-cyan-500/40' },
  lookup_ip: { label: 'IP Geolocation', Icon: Globe, color: 'text-emerald-300', ring: 'border-emerald-500/40' },
  web_search: { label: 'Web Search', Icon: Search, color: 'text-violet-300', ring: 'border-violet-500/40' },
  write_report: { label: 'Report Writer', Icon: FileText, color: 'text-amber-300', ring: 'border-amber-500/40' },
  send_report_notification: { label: 'Email Notification', Icon: Mail, color: 'text-rose-300', ring: 'border-rose-500/40' },
}

export function toolMeta(name: string): ToolMeta {
  return TOOL_META[name] ?? { label: name, Icon: Wrench, color: 'text-slate-300', ring: 'border-slate-500/40' }
}

export const EXAMPLE_QUERIES: { short: string; prompt: string }[] = [
  {
    short: 'Investigate T104 + email report',
    prompt:
      'Analyze transaction T104 - flag any fraud patterns, look up the IP, check the merchant, and email the investigation report to the fraud team.',
  },
  { short: 'Is transaction T006 suspicious?', prompt: 'Does transaction T006 seem suspicious?' },
  { short: 'Check customer C003', prompt: 'Check customer C003 for suspicious activity.' },
  {
    short: 'Fraud summary for 2024-01-20',
    prompt: 'Show me the fraud summary for 2024-01-20 and email it to the analyst team.',
  },
]
