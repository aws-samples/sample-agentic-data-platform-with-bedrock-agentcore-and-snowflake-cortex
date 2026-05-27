# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""Report generation and notification tools.

Provides a report-writer sub-agent that produces polished plain-text fraud
investigation reports, and a notification tool that publishes them to an
Amazon SNS topic for email delivery to subscribed analysts.
"""

import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv
from strands import Agent, tool

from agents._guardrails import build_model

load_dotenv()

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Report-writer sub-agent
# ---------------------------------------------------------------------------

REPORT_WRITER_PROMPT = """\
You are a compliance report writer for a financial fraud investigation team.
You receive raw investigation data from a fraud analyst and transform it into
a polished, professional plain-text report suitable for email delivery via
Amazon SNS to analysts and compliance officers.

## Output Rules

1. Output ONLY the report content — no markdown fences, no preamble.
2. Use plain text only. No HTML tags, no markdown syntax. SNS email delivery
   does not render HTML or markdown.
3. ASCII characters ONLY. No emojis, no decorative Unicode symbols, no non-ASCII
   dashes or quotes. Use "=" lines for the main header, "-" lines for section
   separators, spaces for alignment (avoid tabs), "OK"/"FAIL" instead of check
   or cross marks, and plain dollar signs for currency.
4. Structure the report with:
   - A header banner with the report title and timestamp
   - A summary block with transaction ID, customer, amount, risk score, decision
   - A "TRIGGERED RISK FACTORS" section with each factor on its own line
   - A "GEOGRAPHIC DETAILS" section
   - A "MERCHANT REPUTATION" section
   - A "SUMMARY" section with the narrative conclusion
   - A footer with a disclaimer
5. Preserve ALL data from the input — do not omit any findings.
6. Keep line width to 72 characters or less for email readability.
7. Use professional language appropriate for a compliance audience.
"""


def _get_report_agent() -> Agent:
    """Create the report-writer sub-agent."""
    model_id = os.environ.get("MODEL_ID", "global.anthropic.claude-sonnet-4-6")
    return Agent(
        model=build_model(model_id),
        system_prompt=REPORT_WRITER_PROMPT,
    )


def _extract_text(result) -> str:
    """Extract plain text from a Strands agent result."""
    message = result.message
    if isinstance(message, dict):
        content = message.get("content", [])
        if isinstance(content, list):
            texts = [
                item.get("text", "")
                for item in content
                if isinstance(item, dict) and item.get("text")
            ]
            return "\n".join(texts)
        return str(content)
    return str(message)


@tool
def write_report(raw_investigation: str) -> str:
    """Transform raw fraud investigation findings into a polished plain-text report.

    This tool uses a specialized sub-agent to produce a professional,
    compliance-ready plain-text report from the raw investigation data,
    formatted for email delivery via SNS.

    Args:
        raw_investigation: The raw investigation output including transaction
            details, risk scores, triggered rules, geographic data, and
            merchant reputation findings.

    Returns:
        A polished plain-text report ready for SNS publication.
    """
    agent = _get_report_agent()
    result = agent(
        f"Transform the following raw fraud investigation into a polished "
        f"plain-text report. Today's date is "
        f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}.\n\n"
        f"{raw_investigation}"
    )
    return _extract_text(result)


# ---------------------------------------------------------------------------
# Notification tool (Amazon SNS)
# ---------------------------------------------------------------------------


@tool
def send_report_notification(
    subject: str,
    message: str,
    topic_arn: str = "",
) -> str:
    """Publish a fraud investigation report to an SNS topic.

    Subscribed email endpoints will receive the report. Recipients must
    confirm their subscription before they start receiving messages.

    Args:
        subject: The email subject line (max 100 chars). Example:
            "Fraud Alert: Transaction T104 - BLOCK_RECOMMENDED".
        message: The plain-text report body to send.
        topic_arn: The SNS topic ARN. Falls back to SNS_TOPIC_ARN environment
            variable if not provided.

    Returns:
        A confirmation message with the SNS message ID, or an error description.
    """
    topic = topic_arn or os.environ.get("SNS_TOPIC_ARN", "")
    region = os.environ.get("AWS_REGION", "us-east-1")

    if not topic:
        return (
            "Error: SNS topic ARN not provided. Set SNS_TOPIC_ARN in the "
            "environment or pass topic_arn explicitly."
        )

    # SNS enforces a 100-character subject limit
    safe_subject = subject[:100] if subject else "Fraud Detection Alert"

    try:
        sns = boto3.client("sns", region_name=region)
        response = sns.publish(
            TopicArn=topic,
            Subject=safe_subject,
            Message=message,
        )
        message_id = response.get("MessageId", "unknown")
        logger.info(f"Report published to {topic}, MessageId={message_id}")
        return f"Notification published to SNS topic. MessageId: {message_id}"

    # Return only the AWS error code to the agent caller. Full message +
    # exception details are logged at ERROR level for operator debugging.
    # This prevents leaking the AWS account ID and runtime role ARN — e.g.
    #   "User: arn:aws:sts::<account-id>:assumed-role/AmazonBedrockAgentCoreSDKRuntime-.../..."
    # — through the agent's conversational output.
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_msg = e.response["Error"]["Message"]
        logger.error(f"SNS error: {error_code} - {error_msg}")
        return f"Error publishing notification: {error_code}"
    except Exception:
        logger.exception("Unexpected error publishing notification")
        return "Error publishing notification: internal error (see server logs)"
