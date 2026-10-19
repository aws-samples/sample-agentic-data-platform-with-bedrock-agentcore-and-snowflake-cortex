# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Gateway setup script for the Fraud Detection Agent.

Creates a multi-target AgentCore Gateway with Cognito OAuth auth and three
targets: Snowflake Cortex Agent, IP Geolocation, and Amazon Bedrock AgentCore
Web Search (managed connector — no external API key; queries stay within AWS).

Usage:
    python create_gateway.py
    python create_gateway.py --replace
"""

import argparse
import json
import os
import sys

import boto3
from dotenv import load_dotenv
from bedrock_agentcore_starter_toolkit.operations.gateway.client import GatewayClient

load_dotenv()

GATEWAY_NAME = "fraud-detection-gateway"
SETTINGS_FILE = "settings.json"


def _cleanup_old_cognito(region: str):
    """Delete the Cognito user pool from a previous gateway if settings.json exists."""
    if not os.path.exists(SETTINGS_FILE):
        return
    try:
        with open(SETTINGS_FILE, encoding="utf-8") as f:
            old = json.load(f)
        cognito = old.get("cognito_client_info", {})
        pool_id = cognito.get("user_pool_id")
        if not pool_id:
            return
        client = boto3.client("cognito-idp", region_name=region)
        domain = cognito.get("domain_prefix", "")
        if domain:
            try:
                client.delete_user_pool_domain(Domain=domain, UserPoolId=pool_id)
            except Exception as domain_err:
                # Domain may already be deleted or never created; log and continue
                # so the user pool itself can still be cleaned up.
                print(f"Could not delete Cognito user pool domain '{domain}': {domain_err}")
        client.delete_user_pool(UserPoolId=pool_id)
        print(f"Deleted old Cognito user pool {pool_id}")
    except Exception as e:
        print(f"Could not clean up old Cognito: {e}")


def create_fraud_detection_gateway(
    region: str,
    snowflake_account_url: str,
    snowflake_pat_token: str,
    replace: bool = False,
) -> dict:
    client = GatewayClient(region_name=region)

    if replace:
        _cleanup_old_cognito(region)
        print(f"Deleting existing gateway '{GATEWAY_NAME}'...")
        try:
            client.delete_gateway(name=GATEWAY_NAME, skip_resource_in_use=True)
            print("Deleted.")
        except Exception as e:
            print(f"No existing gateway to delete: {e}")

    # 1. Create OAuth authorizer with Cognito
    print("Creating OAuth authorizer...")
    cognito_response = client.create_oauth_authorizer_with_cognito(GATEWAY_NAME)

    # 2. Create gateway
    print("Creating MCP gateway...")
    gateway = client.create_mcp_gateway(
        name=GATEWAY_NAME,
        authorizer_config=cognito_response["authorizer_config"],
    )

    # 3. Register Snowflake Cortex Agent target
    print("Registering Snowflake Cortex Agent target...")
    with open("agents/api_schema/cortex_agents_openapi.json", encoding="utf-8") as f:
        cortex_openapi = json.load(f)
    cortex_openapi["servers"][0]["variables"]["account_url"]["default"] = snowflake_account_url
    client.create_mcp_gateway_target(
        gateway=gateway,
        name="SnowflakeCortexTarget",
        target_type="openApiSchema",
        target_payload={"inlinePayload": json.dumps(cortex_openapi)},
        credentials={
            "api_key": f"Bearer {snowflake_pat_token}",
            "credential_location": "HEADER",
            "credential_parameter_name": "Authorization",
        },
    )

    # 4. Register IP Geolocation target
    # ipapi.co requires no auth, but the starter toolkit requires a non-None
    # credentials param. We pass a User-Agent header as a workaround.
    print("Registering IP Geolocation target...")
    with open("agents/api_schema/ip_geolocation_openapi.json", encoding="utf-8") as f:
        ip_openapi = json.load(f)
    client.create_mcp_gateway_target(
        gateway=gateway,
        name="IPGeolocationTarget",
        target_type="openApiSchema",
        target_payload={"inlinePayload": json.dumps(ip_openapi)},
        credentials={
            # Not a secret — ipapi.co is keyless; the starter toolkit requires a
            # non-None credentials dict, so we pass a User-Agent string instead.
            "api_key": "AgentCore-Gateway/1.0",  # pragma: allowlist secret
            "credential_location": "HEADER",
            "credential_parameter_name": "User-Agent",
        },
    )

    # 4b. Register AgentCore Web Search target (managed MCP connector) and grant
    # the gateway's outbound role permission to invoke Web Search. This replaces
    # the former external Tavily tool — no API key, and queries stay within AWS.
    # NOTE: requires boto3 >= 1.43 (the `connector` target shape) and a region
    # where AgentCore Web Search is available (e.g. us-east-1).
    print("Registering Web Search target...")
    control = boto3.client("bedrock-agentcore-control", region_name=region)
    gw_id = gateway.get("gatewayId", "")
    gw_details = control.get_gateway(gatewayIdentifier=gw_id)
    gw_arn = gw_details["gatewayArn"]
    role_name = gw_details["roleArn"].split("/")[-1]
    boto3.client("iam").put_role_policy(
        RoleName=role_name,
        PolicyName="WebSearchOutbound",
        PolicyDocument=json.dumps({
            "Version": "2012-10-17",
            "Statement": [
                {"Sid": "InvokeGateway", "Effect": "Allow",
                 "Action": "bedrock-agentcore:InvokeGateway", "Resource": gw_arn},
                {"Sid": "InvokeWebSearch", "Effect": "Allow",
                 "Action": "bedrock-agentcore:InvokeWebSearch",
                 "Resource": f"arn:aws:bedrock-agentcore:{region}:aws:tool/web-search.v1"},
            ],
        }),
    )
    control.create_gateway_target(
        gatewayIdentifier=gw_id,
        name="WebSearchTarget",
        targetConfiguration={"mcp": {"connector": {
            "source": {"connectorId": "web-search"},
            "configurations": [{"name": "WebSearch", "parameterValues": {}}],
        }}},
        credentialProviderConfigurations=[{"credentialProviderType": "GATEWAY_IAM_ROLE"}],
    )

    # 5. Save settings (no access_token — Cognito refresh handles it at runtime)
    settings = {
        "gateway_id": gateway.get("gatewayId", ""),
        "gateway_url": gateway.get("gatewayUrl", ""),
        "gateway_name": GATEWAY_NAME,
        "region": region,
        "cognito_client_info": cognito_response.get("client_info", {}),
        "snowflake": {
            "account_url": snowflake_account_url,
            "database": os.environ.get("SNOWFLAKE_DATABASE", "FRAUD_DETECTION_DB"),
            "schema": os.environ.get("SNOWFLAKE_SCHEMA", "FRAUD_DETECTION_SCHEMA"),
            "agent": os.environ.get("SNOWFLAKE_AGENT", "FRAUD_DETECTION_AGENT"),
        },
        "targets": {
            "snowflake_cortex": {"tools": ["SnowflakeCortexTarget___runAgent"]},
            "ip_geolocation": {"tools": ["IPGeolocationTarget___lookupIP"]},
            "web_search": {"tools": ["WebSearchTarget___WebSearch"]},
        },
    }

    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
    print(f"Settings saved to {SETTINGS_FILE}")
    return settings


def main():
    parser = argparse.ArgumentParser(description="Create Fraud Detection AgentCore Gateway")
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    parser.add_argument("--snowflake-account-url", default=os.environ.get("SNOWFLAKE_ACCOUNT_URL"))
    parser.add_argument("--snowflake-pat-token", default=os.environ.get("SNOWFLAKE_PAT_TOKEN"))
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()

    for name, val in [("SNOWFLAKE_ACCOUNT_URL", args.snowflake_account_url),
                      ("SNOWFLAKE_PAT_TOKEN", args.snowflake_pat_token)]:
        if not val:
            print(f"Error: {name} required (set in .env or pass via CLI)", file=sys.stderr)
            sys.exit(1)

    try:
        settings = create_fraud_detection_gateway(
            region=args.region,
            snowflake_account_url=args.snowflake_account_url,
            snowflake_pat_token=args.snowflake_pat_token,
            replace=args.replace,
        )
        print(f"\nGateway created: {settings['gateway_url']}")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
