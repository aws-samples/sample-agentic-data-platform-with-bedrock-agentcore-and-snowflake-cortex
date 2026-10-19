# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Gateway tool wrappers for the Fraud Detection Agent.

Provides Strands @tool functions that call the AgentCore Gateway
via JSON-RPC MCP protocol. Each tool wraps a specific gateway target.
Uses Cognito OAuth for gateway authentication with auto-refresh.
"""

import hashlib
import json
import logging
import os
import re
import time
import uuid

import requests
from dotenv import load_dotenv
from strands import tool

load_dotenv()

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.DEBUG)

_settings = None
_cached_token = None
_token_expiry = 0

# In-process cache for Snowflake Cortex Agent responses.
# Each Cortex Agent call is expensive (LLM planning + text-to-SQL + warehouse
# execution), so we dedupe repeated questions within a single runtime process.
# Key: normalized question, Value: (expiry_timestamp, response_dict).
_snowflake_cache: dict[str, tuple[float, dict]] = {}
_SNOWFLAKE_CACHE_TTL = int(os.environ.get("SNOWFLAKE_CACHE_TTL_SECONDS", "300"))
_SNOWFLAKE_CACHE_MAX_ENTRIES = 128

# Per-tool request timeouts (seconds). Snowflake Cortex Agent calls run an LLM
# planner + text-to-SQL + warehouse query, so complex questions routinely take
# 60–120s. IP lookups hit a lightweight REST API and should return in < 5s.
_SNOWFLAKE_TIMEOUT = int(os.environ.get("SNOWFLAKE_TIMEOUT_SECONDS", "180"))
_DEFAULT_GATEWAY_TIMEOUT = int(os.environ.get("GATEWAY_TIMEOUT_SECONDS", "30"))


def _normalize_question(question: str) -> str:
    """Normalize a question for cache key lookup (lowercase, collapse whitespace)."""
    return re.sub(r"\s+", " ", question.strip().lower())


def _cache_key(question: str) -> str:
    return hashlib.sha256(_normalize_question(question).encode("utf-8")).hexdigest()


def _load_settings() -> dict:
    """Load gateway settings from settings.json or environment variables."""
    global _settings
    if _settings is not None:
        return _settings

    settings_path = os.environ.get("SETTINGS_FILE", "settings.json")
    if os.path.exists(settings_path):
        with open(settings_path, encoding="utf-8") as f:
            _settings = json.load(f)
    else:
        _settings = {
            "gateway_url": os.environ.get("GATEWAY_URL", ""),
            "snowflake": {
                "account_url": os.environ.get("SNOWFLAKE_ACCOUNT_URL", ""),
                "database": os.environ.get("SNOWFLAKE_DATABASE", "FRAUD_DETECTION_DB"),
                "schema": os.environ.get("SNOWFLAKE_SCHEMA", "FRAUD_DETECTION_SCHEMA"),
                "agent": os.environ.get("SNOWFLAKE_AGENT", "FRAUD_DETECTION_AGENT"),
                "model": os.environ.get("SNOWFLAKE_MODEL_ID", "claude-sonnet-4-6")
            },
            "cognito_client_info": {
                "token_endpoint": os.environ.get("COGNITO_TOKEN_ENDPOINT", ""),
                "client_id": os.environ.get("COGNITO_CLIENT_ID", ""),
                "client_secret": os.environ.get("COGNITO_CLIENT_SECRET", ""),
                "scope": os.environ.get("COGNITO_SCOPE", ""),
            },
        }
    return _settings


def _get_gateway_url() -> str:
    return _load_settings().get("gateway_url", "")


def _refresh_token() -> str:
    """Refresh the Cognito access token using client credentials."""
    global _cached_token, _token_expiry

    settings = _load_settings()
    cognito = settings.get("cognito_client_info", {})
    token_endpoint = cognito.get("token_endpoint")
    client_id = cognito.get("client_id")
    client_secret = cognito.get("client_secret")
    scope = cognito.get("scope")

    if not all([token_endpoint, client_id, client_secret, scope]):
        logger.warning("No Cognito client info available for token refresh")
        return ""

    try:
        resp = requests.post(
            token_endpoint,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data={
                "grant_type": "client_credentials",
                "client_id": client_id,
                "client_secret": client_secret,
                "scope": scope,
            },
            timeout=10,
        )
        resp.raise_for_status()
        token_data = resp.json()

        _cached_token = token_data["access_token"]
        _token_expiry = time.time() + token_data.get("expires_in", 3600) - 60
        return _cached_token
    except Exception as e:
        logger.warning(f"Token refresh failed: {e}")
        return ""


def _get_access_token() -> str:
    """Get a valid access token, refreshing if expired."""
    global _cached_token, _token_expiry
    if _cached_token and time.time() < _token_expiry:
        return _cached_token
    return _refresh_token()


def call_gateway_tool(
    gateway_url: str,
    tool_name: str,
    arguments: dict,
    timeout: int | None = None,
) -> dict:
    """Generic gateway tool caller using JSON-RPC MCP protocol.

    Automatically retries once with a refreshed token on 401 responses.

    Args:
        gateway_url: The AgentCore Gateway URL.
        tool_name: Fully-qualified gateway tool name (e.g. ``Target___op``).
        arguments: JSON-serializable arguments for the tool.
        timeout: Request timeout in seconds. Defaults to
            ``_DEFAULT_GATEWAY_TIMEOUT`` — override for slow upstream APIs.
    """
    request_timeout = timeout if timeout is not None else _DEFAULT_GATEWAY_TIMEOUT
    payload = {
        "jsonrpc": "2.0",
        "id": str(uuid.uuid4()),
        "method": "tools/call",
        "params": {"name": tool_name, "arguments": arguments},
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": f"Bearer {_get_access_token()}",
    }
    try:
        logger.debug(f"Calling gateway: {gateway_url} tool={tool_name} timeout={request_timeout}s")
        response = requests.post(gateway_url, headers=headers, json=payload, timeout=request_timeout)

        if response.status_code == 401:
            headers["Authorization"] = f"Bearer {_refresh_token()}"
            response = requests.post(gateway_url, headers=headers, json=payload, timeout=request_timeout)

        response.raise_for_status()
        return response.json()
    except requests.exceptions.Timeout:
        return {
            "error": {
                "code": "TIMEOUT",
                "message": (
                    f"Request to {tool_name} timed out after {request_timeout}s. "
                    "For complex Snowflake questions, increase SNOWFLAKE_TIMEOUT_SECONDS."
                ),
            }
        }
    except requests.exceptions.ConnectionError:
        return {"error": {"code": "CONNECTION_ERROR", "message": "Could not connect to gateway"}}
    except requests.exceptions.HTTPError as e:
        return {"error": {"code": "HTTP_ERROR", "message": str(e)}}
    except json.JSONDecodeError:
        return {"error": {"code": "INVALID_JSON", "message": "Gateway returned invalid JSON"}}
    except requests.exceptions.RequestException as e:
        return {"error": {"code": "REQUEST_ERROR", "message": str(e)}}


def build_snowflake_payload(question: str) -> dict:
    """Build the arguments for a Snowflake Cortex Agent query."""
    settings = _load_settings()
    sf = settings.get("snowflake", {})
    account_url = sf.get("account_url", "").split("://")[-1].rstrip("/")

    return {
        "account_url": account_url,
        "database": sf.get("database", "FRAUD_DETECTION_DB"),
        "schema": sf.get("schema", "FRAUD_DETECTION_SCHEMA"),
        "agent": sf.get("agent", "FRAUD_DETECTION"),
        "model": sf.get("model", "claude-sonnet-4-6"),
        "Accept": "application/json",
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]},
        ],
    }


@tool
def query_snowflake(question: str) -> dict:
    """Send a natural language question to the Snowflake Cortex Agent.

    Each call is expensive — the tool caches successful responses in-process
    (default TTL 5 minutes) keyed by normalized question, so repeated identical
    questions within the same runtime invocation do not retrigger a Cortex
    Agent run. Errors are never cached.

    Args:
        question: Natural language question about fraud data.

    Returns:
        The Cortex Agent response with query results.
    """
    key = _cache_key(question)
    now = time.time()

    cached = _snowflake_cache.get(key)
    if cached and cached[0] > now:
        logger.debug(f"Snowflake cache hit for question: {question[:80]}")
        return cached[1]

    result = call_gateway_tool(
        _get_gateway_url(),
        "SnowflakeCortexTarget___runAgent",
        build_snowflake_payload(question),
        timeout=_SNOWFLAKE_TIMEOUT,
    )

    if isinstance(result, dict) and "error" not in result:
        if len(_snowflake_cache) >= _SNOWFLAKE_CACHE_MAX_ENTRIES:
            oldest_key = min(_snowflake_cache, key=lambda k: _snowflake_cache[k][0])
            _snowflake_cache.pop(oldest_key, None)
        _snowflake_cache[key] = (now + _SNOWFLAKE_CACHE_TTL, result)

    return result


@tool
def lookup_ip(ip_address: str) -> dict:
    """Look up geographic location for an IP address using ipapi.co.

    Args:
        ip_address: The IP address to geolocate.

    Returns:
        Geolocation data including city, region, country, lat/lon.
    """
    return call_gateway_tool(
        _get_gateway_url(),
        "IPGeolocationTarget___lookupIP",
        {"ip": ip_address},
    )


_WEBSEARCH_TIMEOUT = int(os.environ.get("WEBSEARCH_TIMEOUT_SECONDS", "30"))


@tool
def web_search(query: str, max_results: int = 5) -> dict:
    """Search the public web for current information (merchant reputation, fraud reports, news).

    Backed by Amazon Bedrock AgentCore Web Search, exposed through the AgentCore
    Gateway as an MCP tool. No external API key — queries stay within AWS.

    Args:
        query: The search query.
        max_results: Maximum number of results to return (default 5).

    Returns:
        Web search results; each observation carries title, url, publishedDate, and text.
    """
    return call_gateway_tool(
        _get_gateway_url(),
        "WebSearchTarget___WebSearch",
        {"query": query, "maxResults": max_results},
        timeout=_WEBSEARCH_TIMEOUT,
    )



