# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Fraud Detection Agent entry point.

Streams clean, human-friendly trace events to the UI as tools are invoked and
complete, then emits the final answer. Traces are driven by Strands'
BeforeToolCall / AfterToolCall hooks (not raw stream chunks), so each tool use
shows up exactly once with fully-resolved arguments and a short result summary.

Payload shape accepted by ``invoke`` (all fields optional except one of
``prompt`` or ``messages``):

    {
        "prompt": "Analyze transaction T004",
        "messages": [                         # prior conversation history
            {"role": "user",      "content": "..."},
            {"role": "assistant", "content": "..."}
        ]
    }

Events yielded to the client (each wrapped as an SSE frame by AgentCore):

    {"type": "trace", "event": "tool_start",  "name": "...", "id": "...", "input": {...}}
    {"type": "trace", "event": "tool_end",    "name": "...", "id": "...", "status": "...", "summary": "..."}
    {"type": "response", "text": "...", "messages": [...]}   # final answer + updated history
    {"type": "done"}                                         # terminator
"""

import asyncio
import json
import logging
import os
import re
from typing import Any

from dotenv import load_dotenv
from strands import Agent
from strands.hooks import HookProvider, HookRegistry
from strands.hooks.events import AfterToolCallEvent, BeforeToolCallEvent
from bedrock_agentcore.runtime import BedrockAgentCoreApp

from agents.prompts.system_prompt import FRAUD_ANALYST_PROMPT
from agents.tools.gateway_tools import query_snowflake, lookup_ip, web_search
from agents.tools.report_tools import write_report, send_report_notification
from agents._guardrails import build_model

load_dotenv()

logger = logging.getLogger(__name__)

app = BedrockAgentCoreApp()

MODEL_ID = os.environ.get("MODEL_ID", "global.anthropic.claude-sonnet-4-6")

TOOL_RESULT_SUMMARY_CHARS = 400


# ---------- Tool-specific result extraction ----------


_CORTEX_TEXT_REGEX = re.compile(r'"text"\s*:\s*"((?:[^"\\]|\\.)*)"')


def _regex_cortex_fallback(raw: str) -> str | None:
    """Last-ditch: pull any ``"text": "..."`` values out of a raw SSE blob.

    Used only when the structured parser can't find ``response`` or
    ``response.text`` events — for example if Cortex streams the answer as
    a series of deltas that don't match the documented shape. The extracted
    fragments are concatenated in order and returned as-is.
    """
    matches = _CORTEX_TEXT_REGEX.findall(raw)
    if not matches:
        return None
    # Ignore trivial fragments like the "planning" status messages.
    candidates = [
        m.encode("utf-8").decode("unicode_escape", errors="ignore")
        for m in matches
        if m and m not in {"planning", "reasoning", "completed"}
    ]
    joined = "".join(candidates).strip()
    return joined or None


def _parse_cortex_sse_block(raw_sse: str) -> str:
    """Extract the final human-readable answer text from a Cortex SSE payload.

    Cortex streams 11+ different event types, but for UI purposes we only
    care about the final natural-language answer. Priority order:

    1. The aggregated ``response.text`` event — single event, carries the
       complete final markdown answer in its ``text`` field.
    2. Concatenated ``response.text.delta`` tokens — fallback if the
       aggregated event isn't present (e.g. stream was cut short).
    3. Regex sweep — last-ditch for unexpected envelopes.

    Everything else (``response``, ``response.tool_*``, ``response.status``,
    ``response.thinking*``, ``response.suggested_queries``) is intentionally
    ignored. The ``response`` event in particular contains the full semantic
    model schema and SQL plan, which is not what we want to display.
    """
    final_text: str | None = None
    delta_fragments: list[str] = []

    current_event: str | None = None
    for line in raw_sse.splitlines():
        if line.startswith("event:"):
            current_event = line[len("event:"):].strip()
            continue
        if not line.startswith("data:"):
            continue
        payload_text = line[len("data:"):].strip()
        if not payload_text or payload_text == "[DONE]":
            continue
        try:
            data = json.loads(payload_text)
        except json.JSONDecodeError:
            continue

        if current_event == "response.text":
            text = data.get("text")
            if text:
                final_text = text
        elif current_event == "response.text.delta":
            text = data.get("text")
            if text:
                delta_fragments.append(text)

    if final_text:
        return final_text.strip()
    if delta_fragments:
        return "".join(delta_fragments).strip()
    fallback = _regex_cortex_fallback(raw_sse)
    if fallback:
        return fallback
    return ""


def _summarize_query_snowflake(payload: Any) -> str | None:
    """Best-effort summariser for the query_snowflake gateway envelope.

    Recursively walks every layer the Snowflake response can be wrapped in:
    Strands tool result → MCP JSON-RPC envelope → inner gateway ``content``
    field (a JSON string) → Cortex SSE stream. Returns the extracted answer
    text, or None if no Cortex SSE block is found at any depth.
    """
    if payload is None:
        return None

    # Raw SSE string — or a JSON string that wraps one. Prefer JSON decoding
    # first when the text looks like JSON, because an escaped SSE payload
    # ("event:\\ndata:\\n\\n...") still contains the substrings "event:" and
    # "data:" and would otherwise pass straight to the SSE parser, which
    # needs real newlines to split events.
    if isinstance(payload, str):
        stripped = payload.lstrip()
        if stripped.startswith("{") or stripped.startswith("["):
            try:
                return _summarize_query_snowflake(json.loads(payload))
            except (TypeError, json.JSONDecodeError):
                pass
        if "event:" in payload and "data:" in payload:
            return _parse_cortex_sse_block(payload) or None
        return None

    if isinstance(payload, list):
        for item in payload:
            extracted = _summarize_query_snowflake(item)
            if extracted:
                return extracted
        return None

    if not isinstance(payload, dict):
        return None

    # Check string-valued ``content`` first (inner Cortex wrapper shape).
    content = payload.get("content")
    if isinstance(content, str):
        extracted = _summarize_query_snowflake(content)
        if extracted:
            return extracted

    # Recurse into any nested field — dicts/lists always, strings only when
    # they could contain JSON or an SSE payload. This is essential because
    # MCP wraps the SSE inside ``content[i]["text"]`` (a JSON string), and
    # the object containing that string has no ``content`` key of its own.
    for value in payload.values():
        if isinstance(value, (dict, list)):
            extracted = _summarize_query_snowflake(value)
            if extracted:
                return extracted
        elif isinstance(value, str) and ("{" in value or "event:" in value):
            extracted = _summarize_query_snowflake(value)
            if extracted:
                return extracted

    return None


# ---------- Generic trace helpers ----------


def _summarize_tool_result(tool_name: str, result: Any) -> str:
    """Turn a ToolResult (or Exception) into a human-readable string.

    For Snowflake, returns the full ``response.text`` markdown answer so the
    UI can render it (e.g. inside an expander). Newlines are preserved.
    For other tools, collapses whitespace and clips to a short one-liner.
    """
    if isinstance(result, Exception):
        return f"error: {type(result).__name__}: {result}"

    # Snowflake: return the full final markdown answer as-is. Never collapse
    # whitespace (would destroy the markdown table) and never clip (the UI
    # decides whether to truncate for display).
    if tool_name == "query_snowflake":
        extracted = _summarize_query_snowflake(result)
        if extracted:
            return extracted
        # Fall through to generic handling only if extraction failed.

    # Generic path: peel the Strands/MCP {"content": [...]} wrapper so short
    # tool results (like lookup_ip geolocation JSON) render cleanly.
    payload: Any = result
    if isinstance(payload, dict) and "content" in payload and isinstance(payload["content"], list):
        merged_parts: list[Any] = []
        for item in payload["content"]:
            if isinstance(item, dict):
                if "json" in item:
                    merged_parts.append(item["json"])
                elif "text" in item:
                    text_val = item["text"]
                    try:
                        merged_parts.append(json.loads(text_val))
                    except (TypeError, json.JSONDecodeError):
                        merged_parts.append(text_val)
        if len(merged_parts) == 1:
            payload = merged_parts[0]
        elif merged_parts:
            payload = merged_parts

    if isinstance(payload, (dict, list)):
        try:
            text = json.dumps(payload, default=str, ensure_ascii=False)
        except (TypeError, ValueError):
            text = str(payload)
    else:
        text = str(payload)

    return _clip(text, TOOL_RESULT_SUMMARY_CHARS)


def _clip(text: str, limit: int) -> str:
    """Collapse whitespace + clip. Only use for non-markdown short previews."""
    text = " ".join(text.split()).strip()
    if len(text) > limit:
        text = text[:limit] + "…"
    return text or "(empty response)"


# ---------- Payload parsing ----------


def _coerce_messages(payload: dict) -> tuple[list[dict], str]:
    """Split incoming payload into prior history and the current user turn."""
    raw_messages = payload.get("messages") or []
    prompt = (payload.get("prompt") or "").strip()

    history: list[dict] = []
    for m in raw_messages:
        role = m.get("role")
        content = m.get("content", "")
        if role not in ("user", "assistant") or not content:
            continue
        if isinstance(content, str):
            history.append({"role": role, "content": [{"text": content}]})
        elif isinstance(content, list):
            history.append({"role": role, "content": content})

    if not prompt and history and history[-1]["role"] == "user":
        last = history.pop()
        parts = last["content"]
        prompt = " ".join(p.get("text", "") for p in parts if isinstance(p, dict))

    return history, prompt


# ---------- Hook provider ----------


class TraceHookProvider(HookProvider):
    """Pushes clean tool-boundary events onto an asyncio.Queue.

    We intentionally avoid streaming model tokens — the UI only needs to know
    "tool X started with these args" and "tool X finished with this summary".
    """

    def __init__(self, queue: asyncio.Queue, loop: asyncio.AbstractEventLoop):
        self._queue = queue
        self._loop = loop

    def register_hooks(self, registry: HookRegistry) -> None:
        registry.add_callback(BeforeToolCallEvent, self._on_before)
        registry.add_callback(AfterToolCallEvent, self._on_after)

    def _emit(self, event: dict) -> None:
        """Thread-safe put onto the async queue.

        Hook callbacks may run on the same loop or on a worker thread depending
        on how Strands schedules them, so use call_soon_threadsafe.
        """
        self._loop.call_soon_threadsafe(self._queue.put_nowait, event)

    def _on_before(self, event: BeforeToolCallEvent) -> None:
        tool_use = event.tool_use or {}
        self._emit(
            {
                "type": "trace",
                "event": "tool_start",
                "name": tool_use.get("name", "unknown"),
                "id": tool_use.get("toolUseId"),
                "input": tool_use.get("input", {}),
            }
        )

    def _on_after(self, event: AfterToolCallEvent) -> None:
        tool_use = event.tool_use or {}
        result = event.result
        status = "success"
        if isinstance(result, Exception):
            status = "error"
        elif isinstance(result, dict):
            status = result.get("status", "success")

        self._emit(
            {
                "type": "trace",
                "event": "tool_end",
                "name": tool_use.get("name", "unknown"),
                "id": tool_use.get("toolUseId"),
                "status": status,
                "summary": _summarize_tool_result(tool_use.get("name", ""), result),
            }
        )


# ---------- Response extraction ----------


def _extract_final_text(result_message: Any) -> str:
    if isinstance(result_message, dict):
        content = result_message.get("content", [])
        if isinstance(content, list):
            return "\n".join(
                item.get("text", "")
                for item in content
                if isinstance(item, dict) and item.get("text")
            )
        return str(content)
    return str(result_message)


def _messages_to_plain_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            item["text"] for item in content
            if isinstance(item, dict) and "text" in item
        ).strip()
    return str(content)


# ---------- Optional AgentCore Memory ----------


def _build_session_manager(payload: dict, context):
    """Return an AgentCore Memory session manager if AGENTCORE_MEMORY_ID is set.

    Off by default: when the env var is unset, the agent behaves exactly as before
    (conversation history is supplied via ``messages``). To enable, create a Memory
    resource in the account and set AGENTCORE_MEMORY_ID (and optionally
    AGENTCORE_MEMORY_REGION). Requires the ``bedrock-agentcore[strands-agents]`` extra.
    """
    memory_id = os.environ.get("AGENTCORE_MEMORY_ID", "").strip()
    if not memory_id:
        return None
    try:
        from bedrock_agentcore.memory.integrations.strands.config import (
            AgentCoreMemoryConfig,
            RetrievalConfig,
        )
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )
    except Exception:
        logger.warning(
            "AGENTCORE_MEMORY_ID is set but bedrock-agentcore[strands-agents] is not "
            "installed; running without memory."
        )
        return None

    import time

    session_id = (
        payload.get("session_id")
        or getattr(context, "session_id", None)
        or f"session-{int(time.time())}"
    )
    actor_id = payload.get("actor_id") or "analyst"

    # AgentCore Memory requires actor_id / session_id to match
    # [a-zA-Z0-9][a-zA-Z0-9-_/]*... — email-style actor ids (with '@' and '.')
    # otherwise fail ListEvents/CreateEvent with a ValidationException.
    def _mem_id(value: str, fallback: str) -> str:
        cleaned = re.sub(r"[^a-zA-Z0-9_/-]", "-", str(value or "")).strip("-")
        if not cleaned:
            return fallback
        if not cleaned[0].isalnum():
            cleaned = f"a{cleaned}"
        return cleaned[:200]

    session_id = _mem_id(session_id, f"session-{int(time.time())}")
    actor_id = _mem_id(actor_id, "analyst")
    region = os.environ.get("AGENTCORE_MEMORY_REGION") or os.environ.get("AWS_REGION", "us-east-1")
    # LTM retrieval: pull long-term records from the namespaces the memory was
    # created with (SessionSummarizer / AnalystPreferences / FraudFacts) so
    # cross-session summaries, analyst preferences, and fraud facts are injected
    # into context — this is what makes it STM *and* LTM (not just STM).
    try:
        retrieval_config = {
            "/summaries/{actorId}/{sessionId}": RetrievalConfig(top_k=3, relevance_score=0.3),
            "/preferences/{actorId}": RetrievalConfig(top_k=5, relevance_score=0.4),
            "/facts/{actorId}": RetrievalConfig(top_k=10, relevance_score=0.3),
        }
        cfg = AgentCoreMemoryConfig(
            memory_id=memory_id,
            session_id=str(session_id),
            actor_id=str(actor_id),
            retrieval_config=retrieval_config,
        )
        session_manager = AgentCoreMemorySessionManager(
            agentcore_memory_config=cfg, region_name=region
        )
    except Exception as exc:
        logger.warning(
            "AGENTCORE_MEMORY_ID is set (%s) but the AgentCore Memory session "
            "manager could not be built (%s); running without memory.",
            memory_id,
            exc,
        )
        return None
    logger.info("AgentCore Memory ENABLED (memory %s, session %s, actor %s)", memory_id, session_id, actor_id)
    return session_manager


# ---------- Entrypoint ----------


@app.entrypoint
async def invoke(payload, context):
    """Streaming entrypoint that surfaces tool-boundary traces and the final answer."""
    history, prompt = _coerce_messages(payload)
    if not prompt:
        yield {"type": "error", "message": "No prompt provided"}
        yield {"type": "done"}
        return

    loop = asyncio.get_running_loop()
    trace_queue: asyncio.Queue = asyncio.Queue()

    session_manager = _build_session_manager(payload, context)
    agent_kwargs: dict[str, Any] = dict(
        model=build_model(MODEL_ID),
        tools=[query_snowflake, lookup_ip, web_search, write_report, send_report_notification],
        system_prompt=FRAUD_ANALYST_PROMPT,
        hooks=[TraceHookProvider(trace_queue, loop)],
    )
    if session_manager is not None:
        # Memory manages conversation history across turns/sessions.
        agent_kwargs["session_manager"] = session_manager
    else:
        # Default: history is supplied by the caller each turn.
        agent_kwargs["messages"] = history
    agent = Agent(**agent_kwargs)

    # Drive agent.stream_async in a background task so we can race it against
    # the trace queue and yield whichever arrives first.
    done_sentinel: dict[str, Any] = {"final_text": "", "error": None}

    async def run_agent() -> None:
        try:
            async for event in agent.stream_async(prompt):
                if not isinstance(event, dict):
                    continue
                result_obj = event.get("result")
                if result_obj is not None:
                    done_sentinel["final_text"] = _extract_final_text(
                        getattr(result_obj, "message", result_obj)
                    )
        except Exception as exc:
            logger.exception("Agent execution failed")
            done_sentinel["error"] = str(exc)
        finally:
            # Push an internal marker so the main loop knows we're done.
            await trace_queue.put({"_internal": "agent_done"})

    agent_task = asyncio.create_task(run_agent())

    # Stream trace events to the client as they arrive, until the agent
    # finishes.
    while True:
        event = await trace_queue.get()
        if event.get("_internal") == "agent_done":
            break
        yield event

    await agent_task  # surface cancellations / ensure cleanup

    if done_sentinel["error"]:
        yield {"type": "error", "message": done_sentinel["error"]}
        yield {"type": "done"}
        return

    updated_messages = [
        {"role": m["role"], "content": _messages_to_plain_text(m["content"])}
        for m in agent.messages
        if m.get("role") in ("user", "assistant")
    ]

    yield {
        "type": "response",
        "text": done_sentinel["final_text"],
        "messages": updated_messages,
    }
    yield {"type": "done"}


if __name__ == "__main__":
    app.run()
