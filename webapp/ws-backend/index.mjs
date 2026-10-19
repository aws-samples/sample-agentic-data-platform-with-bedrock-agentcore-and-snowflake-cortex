// API Gateway WebSocket handler (async pattern).
// $default returns immediately (avoids the 29s WebSocket integration timeout),
// then asynchronously self-invokes a worker that runs the (60-120s) agent and
// relays each SSE event to the connection via postToConnection.

import { BedrockAgentCoreClient, InvokeAgentRuntimeCommand } from '@aws-sdk/client-bedrock-agentcore'
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from '@aws-sdk/client-apigatewaymanagementapi'
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda'
import { randomUUID } from 'node:crypto'

const REGION = process.env.AGENT_REGION || process.env.AWS_REGION || 'us-east-1'
const AGENT_RUNTIME_ARN = process.env.AGENT_RUNTIME_ARN
const SELF = process.env.AWS_LAMBDA_FUNCTION_NAME

const agent = new BedrockAgentCoreClient({ region: REGION })
const lambda = new LambdaClient({ region: REGION })

export const handler = async (event) => {
  // --- Worker invocation (async self-invoke) ---
  if (event && event.worker === true) {
    await runAgent(event)
    return { statusCode: 200 }
  }

  // --- API Gateway WebSocket routes ---
  const rc = event.requestContext || {}
  const { routeKey, connectionId, domainName, stage } = rc

  if (routeKey === '$connect') {
    // Authentication happens before this code runs: the $connect route is created with
    // --authorization-type AWS_IAM (webapp/deploy.sh), so API Gateway rejects the handshake
    // unless it carries a valid SigV4 signature. The browser signs in to Cognito, exchanges
    // the ID token for Identity Pool credentials, and SigV4-presigns the wss:// URL
    // (webapp/frontend/src/api.ts); that pool has guest access disabled and its authenticated
    // role may only execute-api:Invoke on this API's /prod/* routes. Reaching this line means
    // the caller is already an authenticated analyst — do not add a second, self-minted check.
    return { statusCode: 200, body: 'connected' }
  }
  if (routeKey === '$disconnect') {
    return { statusCode: 200, body: 'disconnected' }
  }

  // $default — kick off the worker and return immediately.
  let body = {}
  try { body = JSON.parse(event.body || '{}') } catch { /* empty */ }

  await lambda.send(new InvokeCommand({
    FunctionName: SELF,
    InvocationType: 'Event',
    Payload: Buffer.from(JSON.stringify({
      worker: true,
      connectionId, domainName, stage,
      prompt: body.prompt, messages: body.messages,
      sessionId: body.sessionId, actorId: body.actorId,
    })),
  }))
  return { statusCode: 200, body: 'accepted' }
}

async function runAgent({ connectionId, domainName, stage, prompt, messages, sessionId, actorId }) {
  const mgmt = new ApiGatewayManagementApiClient({ region: REGION, endpoint: `https://${domainName}/${stage}` })
  const post = async (obj) => {
    try {
      await mgmt.send(new PostToConnectionCommand({
        ConnectionId: connectionId,
        Data: Buffer.from(JSON.stringify(obj)),
      }))
    } catch { /* connection gone */ }
  }

  const p = (prompt || '').trim()
  const msgs = Array.isArray(messages) ? messages : []
  if (!AGENT_RUNTIME_ARN) { await post({ type: 'error', message: 'Server misconfigured' }); await post({ type: 'done' }); return }
  if (!p) { await post({ type: 'error', message: 'No prompt provided' }); await post({ type: 'done' }); return }

  try {
    const resp = await agent.send(new InvokeAgentRuntimeCommand({
      agentRuntimeArn: AGENT_RUNTIME_ARN,
      runtimeSessionId: `ws-${randomUUID().replace(/-/g, '')}${randomUUID().replace(/-/g, '').slice(0, 4)}`,
      payload: JSON.stringify({ prompt: p, messages: msgs, session_id: sessionId, actor_id: actorId }),
      contentType: 'application/json',
      accept: 'text/event-stream',
    }))

    const stream = resp.response
    let buffer = ''
    const decoder = new TextDecoder('utf-8')
    if (stream && typeof stream[Symbol.asyncIterator] === 'function') {
      for await (const chunk of stream) {
        buffer += decoder.decode(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk), { stream: true })
        let i
        while ((i = buffer.indexOf('\n')) !== -1) {
          const line = buffer.slice(0, i).replace(/\r$/, '')
          buffer = buffer.slice(i + 1)
          const t = line.trimStart()
          if (!t.startsWith('data:')) continue
          const q = t.slice(5).trim()
          if (!q || q === '[DONE]') continue
          try { await post(JSON.parse(q)) } catch { /* skip */ }
        }
      }
    }
  } catch (e) {
    await post({ type: 'error', message: String(e?.message || e) })
    await post({ type: 'done' })
  }
}
