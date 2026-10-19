#!/usr/bin/env bash
# Tear down the Fraud Intelligence Console webapp resources created by deploy.sh.
# Does NOT touch the agent runtime, gateway, SNS, or guardrails (see the top-level
# README Cleanup section for those).
#
# Usage: [AWS_REGION=us-east-1] [PROJECT=fraud-console] ./webapp/teardown.sh
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-fraud-console}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
STACK="${PROJECT}-web"
WS_API_NAME="${PROJECT}-ws-api"
WS_FN="${PROJECT}-ws"
WS_ROLE="${PROJECT}-ws-role"
IDPOOL_NAME="${PROJECT//-/_}_idpool"
AUTH_ROLE="${PROJECT}-idpool-auth-role"

echo "== Tearing down '$PROJECT' webapp in $ACCOUNT / $REGION =="

# static site (empties versioned bucket first, then deletes the stack)
BUCKET="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null)"
if [ -n "${BUCKET:-}" ] && [ "$BUCKET" != "None" ]; then
  echo "-- emptying + deleting bucket $BUCKET"
  python3 - "$BUCKET" "$REGION" <<'PY' 2>/dev/null || true
import sys, boto3
boto3.resource("s3", region_name=sys.argv[2]).Bucket(sys.argv[1]).object_versions.delete()
PY
fi
echo "-- deleting stack $STACK"
aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION" 2>/dev/null
aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION" 2>/dev/null || true

# websocket api
API_ID="$(aws apigatewayv2 get-apis --region "$REGION" --query "Items[?Name=='$WS_API_NAME'].ApiId | [0]" --output text 2>/dev/null)"
[ -n "${API_ID:-}" ] && [ "$API_ID" != "None" ] && { echo "-- deleting WS API $API_ID"; aws apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION" 2>/dev/null; }

# lambda + role
echo "-- deleting Lambda $WS_FN + role"
aws lambda delete-function --function-name "$WS_FN" --region "$REGION" 2>/dev/null
for R in "$WS_ROLE" "$AUTH_ROLE"; do
  for P in $(aws iam list-role-policies --role-name "$R" --query "PolicyNames" --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$R" --policy-name "$P" 2>/dev/null
  done
  aws iam delete-role --role-name "$R" 2>/dev/null && echo "   deleted role $R"
done

# identity pool + user pool
IDPOOL="$(aws cognito-identity list-identity-pools --max-results 60 --region "$REGION" --query "IdentityPools[?IdentityPoolName=='$IDPOOL_NAME'].IdentityPoolId | [0]" --output text 2>/dev/null)"
[ -n "${IDPOOL:-}" ] && [ "$IDPOOL" != "None" ] && { echo "-- deleting identity pool $IDPOOL"; aws cognito-identity delete-identity-pool --identity-pool-id "$IDPOOL" --region "$REGION" 2>/dev/null; }
UP_ID="$(aws cognito-idp list-user-pools --max-results 60 --region "$REGION" --query "UserPools[?Name=='${PROJECT}-users'].Id | [0]" --output text 2>/dev/null)"
[ -n "${UP_ID:-}" ] && [ "$UP_ID" != "None" ] && { echo "-- deleting user pool $UP_ID"; aws cognito-idp delete-user-pool --user-pool-id "$UP_ID" --region "$REGION" 2>/dev/null; }

echo "== webapp teardown complete =="
