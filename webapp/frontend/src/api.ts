// Streaming client for the AgentCore fraud agent.
// Auth: user signs in to a Cognito User Pool -> ID token -> Identity Pool creds
// (authenticated) -> SigV4-presign the AWS_IAM WebSocket connection.

import { CognitoIdentityClient } from '@aws-sdk/client-cognito-identity'
import { fromCognitoIdentityPool } from '@aws-sdk/credential-provider-cognito-identity'
import { CognitoIdentityProviderClient, InitiateAuthCommand } from '@aws-sdk/client-cognito-identity-provider'
import { SignatureV4 } from '@aws-sdk/signature-v4'
import { Sha256 } from '@aws-crypto/sha256-js'
import { HttpRequest } from '@aws-sdk/protocol-http'

export type ChatMessage = { role: 'user' | 'assistant'; content: string }

export type AgentEvent =
  | { type: 'trace'; event: 'tool_start'; name: string; id: string; input: unknown }
  | { type: 'trace'; event: 'tool_end'; name: string; id: string; status: string; summary: string }
  | { type: 'response'; text: string; messages: ChatMessage[] }
  | { type: 'error'; message: string }
  | { type: 'done' }

export interface RuntimeConfig {
  wsUrl: string
  identityPoolId: string
  region: string
  userPoolId: string
  clientId: string
}

export async function loadConfig(): Promise<RuntimeConfig> {
  try {
    const res = await fetch('/config.json', { cache: 'no-store' })
    if (res.ok) {
      const d = await res.json()
      return {
        wsUrl: d.wsUrl || '',
        identityPoolId: d.identityPoolId || '',
        region: d.region || '',
        userPoolId: d.userPoolId || '',
        clientId: d.clientId || '',
      }
    }
  } catch { /* fall through */ }
  return { wsUrl: '', identityPoolId: '', region: '', userPoolId: '', clientId: '' }
}

// Sign in to the Cognito User Pool; returns the ID token.
export async function signIn(cfg: RuntimeConfig, username: string, password: string): Promise<string> {
  const idp = new CognitoIdentityProviderClient({ region: cfg.region })
  const res = await idp.send(new InitiateAuthCommand({
    AuthFlow: 'USER_PASSWORD_AUTH',
    ClientId: cfg.clientId,
    AuthParameters: { USERNAME: username, PASSWORD: password },
  }))
  const idToken = res.AuthenticationResult?.IdToken
  if (!idToken) throw new Error('Sign-in failed (no token). Check email/password.')
  return idToken
}

async function signWsUrl(cfg: RuntimeConfig, idToken: string): Promise<string> {
  const provider = `cognito-idp.${cfg.region}.amazonaws.com/${cfg.userPoolId}`
  const credentials = fromCognitoIdentityPool({
    client: new CognitoIdentityClient({ region: cfg.region }),
    identityPoolId: cfg.identityPoolId,
    logins: { [provider]: idToken },
  })
  const url = new URL(cfg.wsUrl)
  const signer = new SignatureV4({ credentials, region: cfg.region, service: 'execute-api', sha256: Sha256 })
  const request = new HttpRequest({
    method: 'GET', protocol: 'wss:', hostname: url.hostname, path: url.pathname,
    headers: { host: url.hostname },
  })
  const presigned = await signer.presign(request, { expiresIn: 300 })
  const params = new URLSearchParams()
  for (const [k, v] of Object.entries(presigned.query || {})) params.set(k, Array.isArray(v) ? v[0] : String(v))
  return `${url.protocol}//${url.hostname}${url.pathname}?${params.toString()}`
}

export interface InvokeParams {
  config: RuntimeConfig
  idToken: string
  prompt: string
  history: ChatMessage[]
  sessionId: string
  actorId: string
}

export async function* streamInvestigation(params: InvokeParams): AsyncGenerator<AgentEvent> {
  const { config, idToken, prompt, history, sessionId, actorId } = params
  let signedUrl: string
  try {
    signedUrl = await signWsUrl(config, idToken)
  } catch (e) {
    yield { type: 'error', message: `Auth/signing failed: ${e instanceof Error ? e.message : String(e)}` }
    yield { type: 'done' }
    return
  }

  const ws = new WebSocket(signedUrl)
  const queue: AgentEvent[] = []
  let wake: (() => void) | null = null
  let closed = false
  let socketError: string | null = null
  const wait = () => new Promise<void>((r) => { wake = r })
  const nudge = () => { if (wake) { const w = wake; wake = null; w() } }

  ws.onopen = () => ws.send(JSON.stringify({ action: 'invoke', prompt, messages: history, sessionId, actorId }))
  ws.onmessage = (ev) => { try { queue.push(JSON.parse(ev.data as string)) } catch { /* skip */ } nudge() }
  ws.onerror = () => { socketError = 'WebSocket connection error'; nudge() }
  ws.onclose = () => { closed = true; nudge() }

  try {
    while (true) {
      if (queue.length > 0) {
        const ev = queue.shift()!
        yield ev
        if (ev.type === 'done') return
        continue
      }
      if (socketError) { yield { type: 'error', message: socketError }; yield { type: 'done' }; return }
      if (closed) { yield { type: 'done' }; return }
      await wait()
    }
  } finally {
    try { ws.close() } catch { /* ignore */ }
  }
}
