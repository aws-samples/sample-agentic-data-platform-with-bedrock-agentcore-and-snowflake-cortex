# Fraud Intelligence Console (hosted webapp)

The browser front end for the fraud detection agent. A React SPA on CloudFront that
signs in with Amazon Cognito and streams the agent's investigation over an
**IAM-authenticated WebSocket API** — no public/unauthenticated endpoints.

```
Browser ── Cognito login (ID token) ── SigV4 ──▶ WebSocket API ($connect = AWS_IAM)
                                                        │
                                                   WS Lambda ──▶ AgentCore Runtime
                                                                 (Gateway → Snowflake Cortex,
                                                                  AgentCore Web Search, IP geo;
                                                                  AgentCore Memory; SNS email)
        Static assets ◀── CloudFront ◀── private S3 (OAC)
```

Everything is authenticated: the browser gets temporary AWS credentials from a Cognito
**Identity Pool** (guest access disabled) and SigV4-signs the WebSocket `$connect`. The
Lambda relays the runtime's streamed events back over the socket.

## Prerequisites

1. The **agent runtime is already deployed** (follow the top-level `README.md` through
   AgentCore deployment). Get its ARN:
   ```bash
   agentcore status          # copy the runtime ARN
   ```
2. Local tools: **AWS CLI v2**, **Node.js 18+ / npm**, **jq**, and `zip`.
3. AWS credentials for the target account/region.

## Deploy (one command)

From the repo root:

```bash
AGENT_RUNTIME_ARN=<your-runtime-arn> \
AWS_REGION=us-east-1 \
DEMO_EMAIL=analyst@example.com \
DEMO_PASSWORD='<choose-a-strong-password>' \
./webapp/deploy.sh
```

`DEMO_PASSWORD` is **required** — there is no default, and the script exits before making
any AWS call if it is unset. The console is reachable over the public CloudFront URL, so a
default password committed to this repo would be a known credential for every deployment.
It must satisfy the user pool policy: at least 8 characters with an uppercase letter, a
lowercase letter, a number, and a symbol.

`AWS_REGION` must be a region where **AgentCore Web Search** is available (e.g. `us-east-1`)
and must match where the runtime is deployed. Optional overrides: `PROJECT` (default
`fraud-console`), `DEMO_EMAIL` (default `analyst@example.com`).

The script is **idempotent** — it reuses the Cognito User Pool, app client, Identity Pool,
and WebSocket API by name on re-runs, and always re-uploads the freshly built SPA. On
success it prints the CloudFront URL and the login email.

What it creates:

| Resource | Notes |
|---|---|
| Cognito User Pool + app client (`USER_PASSWORD_AUTH`) + demo user | login for the console |
| Cognito Identity Pool (**guest disabled**) + authenticated role | temp creds scoped to `execute-api:Invoke` on the WS API |
| WebSocket API (`$connect = AWS_IAM`) + streaming Lambda (+ role) + deployment | relays runtime SSE to the browser |
| Private S3 bucket + CloudFront (OAC) | `infra/webapp.yaml` |
| `frontend/public/config.json` | written from the created resource IDs |

## Use it

1. Open the printed CloudFront URL and sign in with the demo credentials.
2. Run an investigation, e.g.:
   > Analyze transaction T104 — flag any fraud patterns, look up the IP, check the merchant, and email the investigation report to the fraud team.
   You'll see the live tool trace (Snowflake Cortex, IP geolocation, AgentCore Web Search),
   the report in the right panel, and an email sent via SNS.
3. **Memory:** the console sends a stable `session_id` per login and the signed-in email as
   `actor_id`, so the agent remembers within the session (STM) and, once long-term records
   consolidate, across sessions (LTM).

## Add more users

```bash
aws cognito-idp admin-create-user --user-pool-id <USER_POOL_ID> --username <email> \
  --message-action SUPPRESS --user-attributes Name=email,Value=<email> Name=email_verified,Value=true
aws cognito-idp admin-set-user-password --user-pool-id <USER_POOL_ID> --username <email> \
  --password '<password>' --permanent
```

## Tear down

```bash
AWS_REGION=us-east-1 ./webapp/teardown.sh
```

Removes only the webapp resources (Cognito, Identity Pool, WebSocket API, Lambda, S3 +
CloudFront). The agent runtime, gateway, SNS, and guardrails are left intact — see the
top-level README Cleanup section to remove those.

## Local development

```bash
cd webapp/frontend
npm install
npm run dev      # Vite dev server; expects a valid public/config.json
```
`config.json` is written by `deploy.sh`; for local dev against an existing deployment, copy
the values from the deployed `config.json` (or the Cognito / WebSocket resources).
