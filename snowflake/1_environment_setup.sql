-- ============================================================
-- Script 1: Environment Setup
-- Sets up role, user, warehouse, database, schema, grants,
-- PAT token, and authentication policy.
-- Run this script as ACCOUNTADMIN.
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- =====================
-- Role & User
-- =====================

CREATE ROLE IF NOT EXISTS FRAUD_DETECTION_RL
    COMMENT = 'Role for Cortex Agents demo';

CREATE USER IF NOT EXISTS FRAUD_DETECTION_USER
    DEFAULT_ROLE = FRAUD_DETECTION_RL
    MUST_CHANGE_PASSWORD = TRUE;

-- Grant role to the user (replace YOUR_USERNAME if granting to a different user)
GRANT ROLE FRAUD_DETECTION_RL TO USER FRAUD_DETECTION_USER;

-- Grant role back to ACCOUNTADMIN for admin access
GRANT ROLE FRAUD_DETECTION_RL TO ROLE ACCOUNTADMIN;

-- =====================
-- Warehouse
-- =====================

CREATE WAREHOUSE IF NOT EXISTS FRAUD_DETECTION_WH WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for fraud detection agent';

-- =====================
-- Database & Schema
-- =====================

CREATE DATABASE IF NOT EXISTS FRAUD_DETECTION_DB;
CREATE SCHEMA IF NOT EXISTS FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA;

-- =====================
-- PAT & Auth Policy
-- =====================

-- Create PAT token — COPY THE TOKEN for future use!
ALTER USER FRAUD_DETECTION_USER ADD PROGRAMMATIC ACCESS TOKEN FRAUD_DETECTION_TOKEN
    DAYS_TO_EXPIRY = 30
    ROLE_RESTRICTION = FRAUD_DETECTION_RL;

-- To remove the PAT if needed:
-- ALTER USER FRAUD_DETECTION_USER REMOVE PROGRAMMATIC ACCESS TOKEN FRAUD_DETECTION_TOKEN;

-- Relax network policy for PAT usage (for demo/free-trial only — don't do this in production!)
ALTER USER FRAUD_DETECTION_USER
    UNSET AUTHENTICATION POLICY;

CREATE OR REPLACE AUTHENTICATION POLICY FRAUD_DETECTION_PAT_POLICY
    PAT_POLICY = (NETWORK_POLICY_EVALUATION = ENFORCED_NOT_REQUIRED);

ALTER USER FRAUD_DETECTION_USER SET AUTHENTICATION POLICY FRAUD_DETECTION_PAT_POLICY;

-- =====================
-- Ownership Grants
-- =====================

GRANT OWNERSHIP ON DATABASE FRAUD_DETECTION_DB TO ROLE FRAUD_DETECTION_RL COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA TO ROLE FRAUD_DETECTION_RL COPY CURRENT GRANTS;
GRANT OWNERSHIP ON WAREHOUSE FRAUD_DETECTION_WH TO ROLE FRAUD_DETECTION_RL COPY CURRENT GRANTS;

ALTER USER FRAUD_DETECTION_USER SET DEFAULT_WAREHOUSE = FRAUD_DETECTION_WH;

-- =====================
-- Cortex & Cross-Region
-- =====================

-- Grant Cortex database role
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE FRAUD_DETECTION_RL;

-- Enable cross-region Cortex (adjust region as needed)
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_GLOBAL';

-- =====================
-- Database-Level Grants
-- =====================

GRANT USAGE ON DATABASE FRAUD_DETECTION_DB TO ROLE FRAUD_DETECTION_RL;
GRANT USAGE ON SCHEMA FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA TO ROLE FRAUD_DETECTION_RL;

-- ============================================================
-- Done! Next: run 2_data_setup.sql as FRAUD_DETECTION_RL,
-- then 3_semantic_view_setup.sql
-- ============================================================
