-- ============================================================
-- Script 4: Cortex Agent Setup
-- Creates a Snowflake Cortex Agent that uses the semantic view
-- to answer natural-language questions about fraud detection.
--
-- The agent uses Cortex Analyst's text-to-SQL capability to
-- translate user questions into SQL queries against the
-- FRAUD_DETECTION_SEMANTIC_VIEW, which covers transactions,
-- customers, fraud patterns, and merchant blacklists.
--
-- Run this script after 3_semantic_view_setup.sql as
-- FRAUD_DETECTION_RL.
-- ============================================================

USE ROLE FRAUD_DETECTION_RL;
USE DATABASE FRAUD_DETECTION_DB;
USE SCHEMA FRAUD_DETECTION_SCHEMA;
USE WAREHOUSE FRAUD_DETECTION_WH;

-- =====================
-- Cortex Agent
-- =====================
-- Creates a lean data-retrieval agent powered by Claude Sonnet:
--   1. Accepts natural-language questions from the upstream orchestrator
--   2. Translates them to SQL via Cortex Analyst against the semantic view
--   3. Returns raw rows — no analysis, scoring, or narrative
--
-- Analysis (risk scoring, pattern detection, decisioning) lives entirely in
-- the upstream fraud-detection orchestrator agent. Keeping Cortex focused on
-- data retrieval minimizes LLM planning overhead per call.

CREATE OR REPLACE AGENT FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA.FRAUD_DETECTION_AGENT
  COMMENT = 'Data-retrieval agent for the fraud detection database. Translates natural-language questions from an upstream orchestrator into SQL via the semantic view and returns raw results. Does not perform fraud analysis or risk scoring.'
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude-sonnet-4-6

  instructions:
    response: |
      You are a data-retrieval assistant for an upstream fraud-detection
      orchestrator. Your ONLY job is to translate the caller's natural-language
      question into SQL using the FraudAnalyst tool and return the raw rows.

      Rules:
      - Always call the FraudAnalyst tool. Never answer from memory.
      - Return the data the caller asked for and nothing more.
      - Do NOT perform fraud analysis, risk scoring, pattern detection, or
        behavioural comparison. The upstream orchestrator does all of that.
      - Do NOT add interpretation, warnings, recommendations, or narrative
        summaries.
      - Do NOT reformat amounts, dates, or identifiers. Return them as stored.
      - If the question asks for multiple pieces of information (e.g. a
        transaction plus the customer profile plus blacklist status), run the
        necessary joins in a SINGLE SQL query and return one consolidated
        result set. Do not split into multiple tool calls.
      - If the question is ambiguous or refers to data outside the four tables
        (TRANSACTIONS, CUSTOMERS, FRAUD_PATTERNS, MERCHANT_BLACKLIST), respond
        with a one-line clarification request and stop.
      - Keep responses concise: the SQL result and, if helpful, one short
        sentence naming what was returned. No tables, no bullet lists, no
        commentary.

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "FraudAnalyst"
        description: |
          Queries the fraud detection semantic view using natural language.
          Backing tables: TRANSACTIONS (amount, merchant, ip_address, device_id,
          status, transaction_date, customer_id), CUSTOMERS (name,
          typical_location, average_transaction_amount, account history),
          FRAUD_PATTERNS (pattern definitions and risk scores), and
          MERCHANT_BLACKLIST (flagged merchants with reasons and report counts).
          Prefer a single joined query over multiple narrow queries.

  tool_resources:
    FraudAnalyst:
      semantic_view: "FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA.FRAUD_DETECTION_SEMANTIC_VIEW"
      execution_environment:
        type: warehouse
        warehouse: FRAUD_DETECTION_WH
  $$;

-- ============================================================
-- Done! Cortex Agent created.
--
-- You can now interact with the agent via:
--   SELECT SNOWFLAKE.CORTEX.INVOKE_AGENT(
--     'FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA.FRAUD_DETECTION_AGENT',
--     'Which transactions look suspicious?'
--   );
-- ============================================================
