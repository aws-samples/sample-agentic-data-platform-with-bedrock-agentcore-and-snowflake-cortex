# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Bedrock Guardrails wiring for the fraud-detection agent. Required by default.

In Strands, Guardrails are applied at the BedrockModel level (not the Agent
level). This module exposes a single helper that builds a BedrockModel with
Guardrails attached.

Environment variables:
    BEDROCK_GUARDRAIL_ID       — The Amazon Bedrock Guardrail ID (required)
    BEDROCK_GUARDRAIL_VERSION  — The published Guardrail version (required)
    ALLOW_NO_GUARDRAILS        — Set to "true" to run without guardrails

Guardrails are FAIL CLOSED: if the two ids are unset, model construction raises
rather than silently dropping content filtering and PII masking. Running without
them requires the explicit ALLOW_NO_GUARDRAILS=true opt-out, which logs a
warning on every process start.
"""

import logging
import os

from strands.models import BedrockModel

logger = logging.getLogger(__name__)

_guardrail_log_emitted = False


def _guardrail_kwargs() -> dict:
    """Return the BedrockModel kwargs for Guardrails if both env vars are set.

    Logs one INFO line per process describing the mode (ENABLED vs DISABLED)
    so deployers can confirm from their logs which mode the agent is running in.
    """
    global _guardrail_log_emitted

    gid = os.environ.get("BEDROCK_GUARDRAIL_ID", "").strip()
    gver = os.environ.get("BEDROCK_GUARDRAIL_VERSION", "").strip()

    if gid and gver:
        if not _guardrail_log_emitted:
            logger.info(
                "[fraud-agent] Amazon Bedrock Guardrails: ENABLED (guardrail %s:%s)",
                gid,
                gver,
            )
            _guardrail_log_emitted = True
        return {"guardrail_id": gid, "guardrail_version": gver}

    # Fail closed: guardrails are required by default. Running a fraud-investigation
    # agent with no content filtering and no PII masking must be an explicit,
    # named decision, not the consequence of an unset variable.
    if os.environ.get("ALLOW_NO_GUARDRAILS", "").strip().lower() != "true":
        raise RuntimeError(
            "Amazon Bedrock Guardrails are required but not configured. Set "
            "BEDROCK_GUARDRAIL_ID and BEDROCK_GUARDRAIL_VERSION (see README "
            "'Guardrails setup'), or set ALLOW_NO_GUARDRAILS=true to run "
            "deliberately without them."
        )

    if not _guardrail_log_emitted:
        logger.warning(
            "[fraud-agent] Amazon Bedrock Guardrails: DISABLED via "
            "ALLOW_NO_GUARDRAILS=true — no content filtering and no PII "
            "masking is applied to any model call."
        )
        _guardrail_log_emitted = True
    return {}


def build_model(model_id: str) -> BedrockModel:
    """Build a BedrockModel, optionally wired with Amazon Bedrock Guardrails.

    Falls back to a guardrail-free model if the required env vars are unset.
    """
    return BedrockModel(model_id=model_id, **_guardrail_kwargs())
