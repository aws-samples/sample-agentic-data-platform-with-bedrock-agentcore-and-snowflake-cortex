#!/usr/bin/env bash
# Deploy the Fraud Intelligence Console (Path 2 — the hosted webapp) end to end.
#
# Creates / reuses:
#   - Cognito User Pool + app client (USER_PASSWORD_AUTH) + one demo user
#   - Cognito Identity Pool (guest DISABLED) + authenticated role (execute-api:Invoke)
#   - IAM-authenticated WebSocket API + streaming Lambda (+ role) + a deployment
#   - Private S3 bucket + CloudFront (via infra/webapp.yaml)
#   - webapp/frontend/public/config.json, then builds and uploads the SPA
#
# Prereqs: the agent runtime is already deployed (see the top-level README), plus
# awscli v2, node/npm, and jq. Run from the repo root or the webapp/ dir.
#
# Usage:
#   AGENT_RUNTIME_ARN=arn:aws:bedrock-agentcore:us-east-1:<acct>:runtime/<name> \
#   [AWS_REGION=us-east-1] [PROJECT=fraud-console] \
#   DEMO_PASSWORD='<choose-a-strong-one>' \
#   [DEMO_EMAIL=analyst@example.com] \
#   ./webapp/deploy.sh
#
# DEMO_PASSWORD is required on purpose: the console is reachable over the public
# CloudFront URL, so a default password committed here would be a known
# credential for every deployment. Must satisfy the pool policy below
# (>= 8 chars, upper + lower + number + symbol).
set -euo pipefail

# ---- config ----
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-fraud-console}"
DEMO_EMAIL="${DEMO_EMAIL:-analyst@example.com}"
: "${DEMO_PASSWORD:?Set DEMO_PASSWORD (>= 8 chars, upper + lower + number + symbol). No default: the console is on a public CloudFront URL.}"
: "${AGENT_RUNTIME_ARN:?Set AGENT_RUNTIME_ARN (get it from 'agentcore status').}"

# resolve paths relative to this script so it works from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
WSBACKEND_DIR="$SCRIPT_DIR/ws-backend"
INFRA_TEMPLATE="$SCRIPT_DIR/infra/webapp.yaml"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
STACK="${PROJECT}-web"
WS_API_NAME="${PROJECT}-ws-api"
WS_FN="${PROJECT}-ws"
WS_ROLE="${PROJECT}-ws-role"
IDPOOL_NAME="${PROJECT//-/_}_idpool"
AUTH_ROLE="${PROJECT}-idpool-auth-role"

echo "== Deploying '$PROJECT' webapp to $ACCOUNT / $REGION =="
echo "   runtime: $AGENT_RUNTIME_ARN"

# ---- 1. Cognito User Pool + app client + demo user (reuse by name) ----
echo "== [1/6] Cognito User Pool =="
UP_ID="$(aws cognito-idp list-user-pools --max-results 60 --region "$REGION" \
  --query "UserPools[?Name=='${PROJECT}-users'].Id | [0]" --output text)"
if [ "$UP_ID" = "None" ] || [ -z "$UP_ID" ]; then
  UP_ID="$(aws cognito-idp create-user-pool --region "$REGION" --pool-name "${PROJECT}-users" \
    --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":true}}' \
    --query "UserPool.Id" --output text)"
  echo "   created user pool $UP_ID"
else
  echo "   reusing user pool $UP_ID"
fi
CLIENT_ID="$(aws cognito-idp list-user-pool-clients --user-pool-id "$UP_ID" --region "$REGION" \
  --query "UserPoolClients[?ClientName=='${PROJECT}-web'].ClientId | [0]" --output text)"
if [ "$CLIENT_ID" = "None" ] || [ -z "$CLIENT_ID" ]; then
  CLIENT_ID="$(aws cognito-idp create-user-pool-client --region "$REGION" --user-pool-id "$UP_ID" \
    --client-name "${PROJECT}-web" --no-generate-secret \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query "UserPoolClient.ClientId" --output text)"
  echo "   created app client $CLIENT_ID"
else
  echo "   reusing app client $CLIENT_ID"
fi
aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$UP_ID" --username "$DEMO_EMAIL" \
  --message-action SUPPRESS --user-attributes Name=email,Value="$DEMO_EMAIL" Name=email_verified,Value=true \
  >/dev/null 2>&1 || true
aws cognito-idp admin-set-user-password --region "$REGION" --user-pool-id "$UP_ID" \
  --username "$DEMO_EMAIL" --password "$DEMO_PASSWORD" --permanent
echo "   demo user: $DEMO_EMAIL"

# ---- 2. WebSocket streaming Lambda (package + role + function) ----
echo "== [2/6] WebSocket Lambda =="
( cd "$WSBACKEND_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1 \
  && rm -f ws-function.zip && zip -qr ws-function.zip index.mjs package.json node_modules )
if ! aws iam get-role --role-name "$WS_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$WS_ROLE" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  sleep 8
fi
aws iam put-role-policy --role-name "$WS_ROLE" --policy-name ws-perms --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":\"bedrock-agentcore:InvokeAgentRuntime\",\"Resource\":[\"$AGENT_RUNTIME_ARN\",\"$AGENT_RUNTIME_ARN/*\"]},
    {\"Effect\":\"Allow\",\"Action\":\"execute-api:ManageConnections\",\"Resource\":\"arn:aws:execute-api:$REGION:$ACCOUNT:*/*\"},
    {\"Effect\":\"Allow\",\"Action\":\"lambda:InvokeFunction\",\"Resource\":\"arn:aws:lambda:$REGION:$ACCOUNT:function:$WS_FN\"}
  ]}"
if aws lambda get-function --function-name "$WS_FN" --region "$REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$WS_FN" --zip-file "fileb://$WSBACKEND_DIR/ws-function.zip" --region "$REGION" >/dev/null
  aws lambda update-function-configuration --function-name "$WS_FN" --region "$REGION" \
    --environment "Variables={AGENT_RUNTIME_ARN=$AGENT_RUNTIME_ARN,AGENT_REGION=$REGION}" >/dev/null
  echo "   updated Lambda $WS_FN"
else
  aws lambda create-function --function-name "$WS_FN" --runtime nodejs22.x \
    --role "arn:aws:iam::$ACCOUNT:role/$WS_ROLE" --handler index.handler \
    --zip-file "fileb://$WSBACKEND_DIR/ws-function.zip" --timeout 180 --memory-size 256 --region "$REGION" \
    --environment "Variables={AGENT_RUNTIME_ARN=$AGENT_RUNTIME_ARN,AGENT_REGION=$REGION}" >/dev/null
  echo "   created Lambda $WS_FN"
fi

# ---- 3. WebSocket API (IAM $connect) + routes + integration + deployment ----
echo "== [3/6] WebSocket API =="
API_ID="$(aws apigatewayv2 get-apis --region "$REGION" --query "Items[?Name=='$WS_API_NAME'].ApiId | [0]" --output text)"
if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  API_ID="$(aws apigatewayv2 create-api --name "$WS_API_NAME" --protocol-type WEBSOCKET \
    --route-selection-expression '$request.body.action' --region "$REGION" --query "ApiId" --output text)"
  FN_ARN="arn:aws:lambda:$REGION:$ACCOUNT:function:$WS_FN"
  INT_ID="$(aws apigatewayv2 create-integration --api-id "$API_ID" --integration-type AWS_PROXY \
    --integration-uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$FN_ARN/invocations" \
    --integration-method POST --region "$REGION" --query "IntegrationId" --output text)"
  for R in '$connect' '$disconnect' '$default'; do
    AUTH="--authorization-type NONE"; [ "$R" = '$connect' ] && AUTH="--authorization-type AWS_IAM"
    aws apigatewayv2 create-route --api-id "$API_ID" --route-key "$R" $AUTH \
      --target "integrations/$INT_ID" --region "$REGION" >/dev/null
  done
  aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name prod --region "$REGION" >/dev/null
  aws lambda add-permission --function-name "$WS_FN" --statement-id apigw-ws --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT:$API_ID/*/*" --region "$REGION" >/dev/null 2>&1 || true
  echo "   created WS API $API_ID"
else
  echo "   reusing WS API $API_ID"
fi
# a deployment is REQUIRED for WebSocket route/auth changes to go live
DEP_ID="$(aws apigatewayv2 create-deployment --api-id "$API_ID" --stage-name prod --region "$REGION" --query "DeploymentId" --output text)"
aws apigatewayv2 update-stage --api-id "$API_ID" --stage-name prod --deployment-id "$DEP_ID" --region "$REGION" >/dev/null
WS_URL="wss://$API_ID.execute-api.$REGION.amazonaws.com/prod"
echo "   $WS_URL"

# ---- 4. Identity Pool (guest disabled) + authenticated role ----
echo "== [4/6] Cognito Identity Pool =="
PROVIDER="cognito-idp.$REGION.amazonaws.com/$UP_ID"
IDPOOL="$(aws cognito-identity list-identity-pools --max-results 60 --region "$REGION" \
  --query "IdentityPools[?IdentityPoolName=='$IDPOOL_NAME'].IdentityPoolId | [0]" --output text)"
if [ "$IDPOOL" = "None" ] || [ -z "$IDPOOL" ]; then
  IDPOOL="$(aws cognito-identity create-identity-pool --region "$REGION" \
    --identity-pool-name "$IDPOOL_NAME" --no-allow-unauthenticated-identities \
    --cognito-identity-providers ProviderName="$PROVIDER",ClientId="$CLIENT_ID",ServerSideTokenCheck=false \
    --query "IdentityPoolId" --output text)"
  echo "   created identity pool $IDPOOL"
else
  echo "   reusing identity pool $IDPOOL"
fi
if ! aws iam get-role --role-name "$AUTH_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$AUTH_ROLE" --assume-role-policy-document "{
    \"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"cognito-identity.amazonaws.com\"},
    \"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"cognito-identity.amazonaws.com:aud\":\"$IDPOOL\"},
    \"ForAnyValue:StringLike\":{\"cognito-identity.amazonaws.com:amr\":\"authenticated\"}}}]}" >/dev/null
  sleep 8
fi
aws iam put-role-policy --role-name "$AUTH_ROLE" --policy-name invoke-ws --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"execute-api:Invoke\",\"Resource\":\"arn:aws:execute-api:$REGION:$ACCOUNT:$API_ID/prod/*\"}]}"
aws cognito-identity set-identity-pool-roles --region "$REGION" --identity-pool-id "$IDPOOL" \
  --roles authenticated="arn:aws:iam::$ACCOUNT:role/$AUTH_ROLE"

# ---- 5. Static site (S3 + CloudFront) ----
echo "== [5/6] Static site (S3 + CloudFront) =="
aws cloudformation deploy --stack-name "$STACK" --template-file "$INFRA_TEMPLATE" \
  --parameter-overrides ProjectName="$PROJECT" --region "$REGION" >/dev/null
BUCKET="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)"
DIST="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text)"
SITE="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='SiteURL'].OutputValue" --output text)"

# ---- 6. config.json + build + upload ----
echo "== [6/6] config.json + build + upload =="
cat > "$FRONTEND_DIR/public/config.json" <<JSON
{
  "wsUrl": "$WS_URL",
  "identityPoolId": "$IDPOOL",
  "region": "$REGION",
  "userPoolId": "$UP_ID",
  "clientId": "$CLIENT_ID"
}
JSON
( cd "$FRONTEND_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1 && npm run build >/dev/null )
aws s3 sync "$FRONTEND_DIR/dist/" "s3://$BUCKET/" --delete --region "$REGION" >/dev/null
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" >/dev/null

echo
echo "==================== DONE ===================="
echo " URL:      $SITE"
echo " Login:    $DEMO_EMAIL / the DEMO_PASSWORD you supplied"
echo " (CloudFront can take a few minutes to serve the first request.)"
echo "=============================================="
