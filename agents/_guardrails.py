# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Optional Bedrock Guardrails wiring for the fraud-detection agent.

In Strands, Guardrails are applied at the BedrockModel level (not the Agent
level). This module exposes a single helper that builds a BedrockModel with
Guardrails attached if the two Guardrail env vars are set, and a bare
BedrockModel (no guardrails) otherwise.

Environment variables:
    BEDROCK_GUARDRAIL_ID       — The Amazon Bedrock Guardrail ID
    BEDROCK_GUARDRAIL_VERSION  — The published Guardrail version number

If either is unset, the model is built without guardrail kwargs and the agent
behaves exactly as it did before this module was introduced.
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

    if not _guardrail_log_emitted:
        logger.info(
            "[fraud-agent] Amazon Bedrock Guardrails: DISABLED "
            "(BEDROCK_GUARDRAIL_ID / BEDROCK_GUARDRAIL_VERSION unset — see "
            "README 'Optional: Enable Amazon Bedrock Guardrails')"
        )
        _guardrail_log_emitted = True
    return {}


def build_model(model_id: str) -> BedrockModel:
    """Build a BedrockModel, optionally wired with Amazon Bedrock Guardrails.

    Falls back to a guardrail-free model if the required env vars are unset.
    """
    return BedrockModel(model_id=model_id, **_guardrail_kwargs())
