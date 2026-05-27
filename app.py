# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Streamlit chat UI for the Fraud Detection Agent.

Talks exclusively to a deployed Amazon Bedrock AgentCore runtime — there is
no local development path. Maintains a rolling conversation in
``st.session_state`` and sends the full history back to the runtime on every
turn, so follow-ups like "now email the report" retain context. Streams trace
events (tool calls) and the final response from the runtime via Server-Sent
Events.
"""

import codecs
import json
import os
import uuid
from collections.abc import Iterator
from typing import Any

import boto3
import streamlit as st
import yaml
from botocore.config import Config
from dotenv import load_dotenv

load_dotenv()

AGENTCORE_CONFIG_FILE = ".bedrock_agentcore.yaml"

EXAMPLE_QUERIES = [
    "What is customer C003's name?",
    "Does transaction T006 seem suspicious?",
    "Check customer C003 for suspicious activity",
    "Is 'AnyCompany Fraudulent Lending Services' safe?",
    "Generate fraud risk profile for Martha Rivera and send it to the analyst team",
    "Show me the fraud summary for 2024-01-20, send it to the analyst team",
]

TOOL_LABELS = {
    "query_snowflake": "Snowflake query",
    "lookup_ip": "IP lookup",
    "tavily_search": "Web search",
    "write_report": "Write report",
    "send_report_notification": "Send notification",
}

TOOL_ICON = {
    "query_snowflake": ":snowflake:",
    "lookup_ip": ":globe_with_meridians:",
    "tavily_search": ":mag:",
    "write_report": ":memo:",
    "send_report_notification": ":email:",
}

TOOL_START_ICON = ":hammer_and_wrench:"
TOOL_SUCCESS_ICON = ":white_check_mark:"
TOOL_WARNING_ICON = ":warning:"


def load_agent_runtime_arn() -> str:
    """Read the deployed agent's runtime ARN from .bedrock_agentcore.yaml."""
    if not os.path.exists(AGENTCORE_CONFIG_FILE):
        return ""
    try:
        with open(AGENTCORE_CONFIG_FILE, encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}
    except yaml.YAMLError:
        return ""
    default_name = config.get("default_agent")
    if not default_name:
        return ""
    agent = config.get("agents", {}).get(default_name, {})
    return agent.get("bedrock_agentcore", {}).get("agent_arn") or ""


# --- SSE parsing helpers ---


def _iter_sse_events(byte_iter: Iterator[bytes]) -> Iterator[dict]:
    """Parse an arbitrary byte stream into JSON events from SSE frames.

    Reads incrementally and dispatches each ``data:`` line as soon as a
    newline is seen, so live traces actually render live.

    Uses an incremental UTF-8 decoder so multi-byte characters (em-dashes,
    emoji, accented letters) that span chunk boundaries are not replaced with
    ``U+FFFD``.
    """
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    buffer = ""
    for chunk in byte_iter:
        if not chunk:
            continue
        if isinstance(chunk, bytes):
            text = decoder.decode(chunk)
        else:
            text = chunk
        if not text:
            continue
        buffer += text
        while "\n" in buffer:
            line, buffer = buffer.split("\n", 1)
            line = line.rstrip("\r")
            if not line.startswith("data:"):
                continue
            payload = line[len("data:"):].strip()
            if not payload:
                continue
            try:
                yield json.loads(payload)
            except json.JSONDecodeError:
                continue
    # Flush any trailing bytes the decoder is holding.
    tail = decoder.decode(b"", final=True)
    if tail:
        buffer += tail
        for line in buffer.split("\n"):
            line = line.rstrip("\r")
            if line.startswith("data:"):
                payload = line[len("data:"):].strip()
                if payload:
                    try:
                        yield json.loads(payload)
                    except json.JSONDecodeError:
                        continue


def stream_runtime(agent_arn: str, region: str, session_id: str, payload: dict) -> Iterator[dict]:
    """Stream events from the deployed AgentCore runtime.

    We read in small chunks (64 bytes) rather than the boto3 default (1 KB) so
    short SSE frames surface promptly, while still being large enough to avoid
    the per-byte syscall overhead. UTF-8 boundaries are handled by the
    incremental decoder in ``_iter_sse_events``.
    """
    client = boto3.client(
        "bedrock-agentcore",
        region_name=region,
        config=Config(
            read_timeout=900,
            connect_timeout=10,
            retries={"max_attempts": 0},
        ),
    )
    response = client.invoke_agent_runtime(
        agentRuntimeArn=agent_arn,
        runtimeSessionId=session_id,
        payload=json.dumps(payload),
    )
    body = response["response"]

    def byte_iter() -> Iterator[bytes]:
        while True:
            chunk = body.read(64)
            if not chunk:
                return
            yield chunk

    yield from _iter_sse_events(byte_iter())


# --- Trace rendering ---


def _format_tool_input(value: Any) -> str:
    """Render tool input as a single short line of markdown."""
    if isinstance(value, dict):
        try:
            rendered = json.dumps(value, ensure_ascii=False)
        except (TypeError, ValueError):
            rendered = str(value)
    else:
        rendered = str(value)
    rendered = " ".join(rendered.split())
    if len(rendered) > 160:
        rendered = rendered[:160] + "…"
    return rendered


def _format_trace(event: dict, tool_state: dict) -> tuple[str, str] | None:
    """Return a (title, body) pair to render for a trace event, or None to skip."""
    kind = event.get("event")
    tool_id = event.get("id")
    name = event.get("name", "tool")
    icon = TOOL_ICON.get(name, TOOL_START_ICON)
    label = TOOL_LABELS.get(name, name)

    if kind == "tool_start":
        tool_state[tool_id] = {"name": name}
        header = f"{icon} **{label}**"
        body = _format_tool_input(event.get("input", {}))
        return header, f"`{body}`" if body else ""

    if kind == "tool_end":
        status = event.get("status", "success")
        summary = (event.get("summary") or "").strip()
        if status == "success":
            header = f"{TOOL_SUCCESS_ICON} **{label}** done"
        else:
            header = f"{TOOL_WARNING_ICON} **{label}** ({status})"
        return header, summary

    return None


def render_turn(stream: Iterator[dict], live_container) -> tuple[str, list[dict]]:
    """Consume the event stream, render traces live, and return (final_text, updated_history).

    ``live_container`` is a Streamlit container used for the live trace view.
    Each trace arrival triggers an incremental update. When the turn is
    complete, the container is collapsed into an expander summary so the
    final answer stays prominent.
    """
    tool_state: dict[str, dict] = {}
    trace_lines: list[str] = []
    final_text = ""
    updated_messages: list[dict] = []
    errored = False

    status = live_container.status("Thinking…", expanded=True)

    for event in stream:
        etype = event.get("type")
        if etype == "trace":
            rendered = _format_trace(event, tool_state)
            if rendered is None:
                continue
            title, body = rendered
            line = f"**{title}**" + (f"\n\n{body}" if body else "")
            trace_lines.append(line)
            status.markdown(line)
        elif etype == "response":
            final_text = event.get("text", "")
            updated_messages = event.get("messages", [])
        elif etype == "error":
            errored = True
            final_text = f"❌ {event.get('message', 'unknown error')}"
        elif etype == "done":
            break

    tool_calls = sum(1 for meta in tool_state.values() if meta)
    if tool_calls:
        label = f":brain: Reasoning ({tool_calls} tool call{'s' if tool_calls != 1 else ''})"
        status.update(label=label, state="complete", expanded=False)
    else:
        status.update(label="Done", state="complete", expanded=False)

    if errored:
        st.error(final_text)

    return final_text, updated_messages


# --- Page setup ---

st.set_page_config(page_title="Fraud Detection Agent", page_icon=":mag:", layout="wide")
st.title("Fraud Detection Agent")

# --- Session state init ---

if "messages" not in st.session_state:
    st.session_state["messages"] = []  # [{"role": "user"|"assistant", "content": str}]
if "runtime_session_id" not in st.session_state:
    # AgentCore requires runtimeSessionId to be 33+ chars.
    st.session_state["runtime_session_id"] = f"streamlit-{uuid.uuid4().hex}"

# --- Sidebar ---

with st.sidebar:
    st.header("⚙️ Settings")
    st.caption(
        "This UI talks to a deployed Amazon Bedrock AgentCore runtime. Run "
        "`agentcore deploy` first, then use the values below to invoke it."
    )

    region = os.environ.get("AWS_REGION", "us-east-1")
    agent_arn = st.text_input(
        "Agent Runtime ARN",
        value=load_agent_runtime_arn(),
        help="Read from .bedrock_agentcore.yaml. Override to call a different runtime.",
    )
    region = st.text_input("AWS Region", value=region)

    st.divider()
    st.subheader("Email Notifications")
    st.caption(
        "The SNS topic ARN is baked into the deployed AgentCore runtime "
        "at deploy time. To change it, redeploy with "
        "`agentcore deploy --env SNS_TOPIC_ARN=<arn>` "
        "(include every other env var you want to keep in the same command)."
    )

    st.divider()
    if st.button("New conversation"):
        st.session_state["messages"] = []
        st.session_state["runtime_session_id"] = f"streamlit-{uuid.uuid4().hex}"
        st.rerun()

# --- Quick-start buttons (only visible on an empty conversation) ---

if not st.session_state["messages"]:
    st.subheader("Quick Queries")
    cols = st.columns(3)
    pending: str | None = None
    for i, q in enumerate(EXAMPLE_QUERIES):
        if cols[i % 3].button(q, key=f"example_{i}"):
            pending = q
    if pending:
        st.session_state["pending_prompt"] = pending
        st.rerun()

# --- Render prior turns ---

for msg in st.session_state["messages"]:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

# --- Handle a new user turn ---

pending_prompt = st.session_state.pop("pending_prompt", None)
user_input = pending_prompt or st.chat_input("Ask a follow-up or start a new investigation…")

if user_input:
    if not agent_arn:
        st.error(
            "No Agent Runtime ARN configured. Run `agentcore deploy` to create the "
            "runtime, or paste an existing ARN into the sidebar."
        )
    else:
        st.session_state["messages"].append({"role": "user", "content": user_input})
        with st.chat_message("user"):
            st.markdown(user_input)

        with st.chat_message("assistant"):
            live_container = st.container()
            payload: dict[str, Any] = {
                "prompt": user_input,
                "messages": st.session_state["messages"][:-1],  # prior turns only
            }
            try:
                stream = stream_runtime(
                    agent_arn, region, st.session_state["runtime_session_id"], payload
                )
                final_text, updated_history = render_turn(stream, live_container)
            except Exception as e:
                final_text = f"❌ Runtime error: {e}"
                updated_history = []
                st.error(final_text)

            if final_text and not final_text.startswith("❌"):
                st.markdown(final_text)

        # Persist the assistant turn. Prefer the authoritative history returned
        # by the runtime (keeps tool results etc.), falling back to the plain
        # text if the runtime did not send one.
        if updated_history:
            st.session_state["messages"] = [
                {"role": m["role"], "content": m["content"]}
                for m in updated_history
                if m.get("role") in ("user", "assistant") and m.get("content")
            ]
        else:
            st.session_state["messages"].append(
                {"role": "assistant", "content": final_text or "_(no response)_"}
            )
