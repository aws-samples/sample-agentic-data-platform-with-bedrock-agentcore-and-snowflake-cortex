-- ============================================================
-- Script 3: Semantic View Setup
-- Creates the Cortex Analyst Semantic View for fraud detection.
-- Run this script after 2_data_setup.sql as FRAUD_DETECTION_RL.
-- ============================================================

USE ROLE FRAUD_DETECTION_RL;
USE DATABASE FRAUD_DETECTION_DB;
USE SCHEMA FRAUD_DETECTION_SCHEMA;
USE WAREHOUSE FRAUD_DETECTION_WH;

-- =====================
-- Cortex Analyst Semantic View
-- =====================

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA',
  $$
name: FRAUD_DETECTION_SEMANTIC_VIEW
description: This semantic view connects fictitious data for fraud detection and includes customers, transaction, known fraud patterns and merchant blocklist
tables:
  - name: TRANSACTIONS
    description: The table contains records of financial transactions, specifically customer purchases and interactions. Each record represents a single transaction and includes details about the customer, merchant, and transaction specifics, such as date, amount, and device used.
    base_table:
      database: FRAUD_DETECTION_DB
      schema: FRAUD_DETECTION_SCHEMA
      table: TRANSACTIONS
    dimensions:
      - name: CUSTOMER_ID
        description: Unique identifier for the customer.
        expr: CUSTOMER_ID
        data_type: VARCHAR
        sample_values:
          - C002
          - C003
          - C001
      - name: DEVICE_ID
        description: Unique identifier of the device used to initiate the transaction.
        expr: DEVICE_ID
        data_type: VARCHAR
        sample_values:
          - DEV002
          - DEV005
          - DEV001
      - name: IP_ADDRESS
        description: Internet protocol addresses.
        expr: IP_ADDRESS
        data_type: VARCHAR
        sample_values:
          - 203.0.113.50
          - 198.51.100.20
          - 198.51.100.80
      - name: MERCHANT_CATEGORY
        description: The category of the merchant where the transaction took place.
        expr: MERCHANT_CATEGORY
        data_type: VARCHAR
        sample_values:
          - Electronics
          - Grocery
          - Retail
      - name: MERCHANT_NAME
        description: The name of the merchant where the transaction took place.
        expr: MERCHANT_NAME
        data_type: VARCHAR
        sample_values:
          - AnyCompany Electronics
          - AnyCompany Retail
          - AnyCompany Tech
      - name: STATUS
        description: The status of the transaction.
        expr: STATUS
        data_type: VARCHAR
        sample_values:
          - failed
          - completed
      - name: TRANSACTION_ID
        description: Unique identifier for a transaction.
        expr: TRANSACTION_ID
        data_type: VARCHAR
        sample_values:
          - T005
          - T002
          - T001
      - name: TRANSACTION_TYPE
        description: The type of transaction, such as online or in-person purchase.
        expr: TRANSACTION_TYPE
        data_type: VARCHAR
        sample_values:
          - in-store
          - online
    time_dimensions:
      - name: TRANSACTION_DATE
        description: The date and time when the transaction occurred.
        expr: TRANSACTION_DATE
        data_type: TIMESTAMP_NTZ
        sample_values:
          - 2024-01-15T10:30:00.000+0000
          - 2024-01-15T11:00:00.000+0000
          - 2024-01-15T14:00:00.000+0000
    facts:
      - name: AMOUNT
        description: The amount of the transaction.
        expr: AMOUNT
        data_type: FLOAT
        sample_values:
          - '185'
          - '120.5'
          - '450'
    primary_key:
      columns:
        - TRANSACTION_ID
    foreign_keys:
      - fkey_columns:
          - CUSTOMER_ID
        pkey_table:
          database: FRAUD_DETECTION_DB
          schema: FRAUD_DETECTION_SCHEMA
          table: CUSTOMERS
        pkey_columns:
          - CUSTOMER_ID
  - name: CUSTOMERS
    description: The table contains records of customer information, specifically details about individuals and their financial activity. Each record represents a single customer and includes demographic and transactional data, such as location and spending habits, which can be used to identify patterns and anomalies.
    base_table:
      database: FRAUD_DETECTION_DB
      schema: FRAUD_DETECTION_SCHEMA
      table: CUSTOMERS
    dimensions:
      - name: CUSTOMER_ID
        description: Unique identifier for a customer.
        expr: CUSTOMER_ID
        data_type: VARCHAR
        sample_values:
          - C002
          - C001
          - C003
      - name: CUSTOMER_NAME
        description: The full name of the customer.
        expr: CUSTOMER_NAME
        data_type: VARCHAR
        sample_values:
          - Carlos Salazar
          - Mary Major
          - Mateo Jackson
      - name: EMAIL
        description: Email addresses of customers.
        expr: EMAIL
        data_type: VARCHAR
        sample_values:
          - mary.major@anycompany.com
          - mateo.jackson@anycompany.com
          - carlos.salazar@anycompany.com
      - name: PHONE
        description: Phone numbers.
        expr: PHONE
        data_type: VARCHAR
        sample_values:
          - +44-20-5550102
          - +1-555-0101
          - +81-3-5550103
      - name: TRANSACTION_COUNT
        description: The total number of transactions made by a customer.
        expr: TRANSACTION_COUNT
        data_type: NUMBER
        sample_values:
          - '28'
          - '45'
          - '62'
      - name: TYPICAL_LOCATION
        description: The typical geographic location of a customer.
        expr: TYPICAL_LOCATION
        data_type: VARCHAR
        sample_values:
          - Tokyo, JP
          - New York, US
          - London, UK
    time_dimensions:
      - name: ACCOUNT_CREATED_DATE
        description: The date when the customer's account was created.
        expr: ACCOUNT_CREATED_DATE
        data_type: DATE
        sample_values:
          - '2023-03-10'
          - '2022-01-15'
          - '2021-06-20'
    facts:
      - name: AVERAGE_TRANSACTION_AMOUNT
        description: The average amount of a customer's transactions.
        expr: AVERAGE_TRANSACTION_AMOUNT
        data_type: FLOAT
        sample_values:
          - '150'
          - '200'
          - '500'
    primary_key:
      columns:
        - CUSTOMER_ID
  - name: FRAUD_PATTERNS
    description: The table contains records of suspicious activity patterns identified for fraud detection. Each record represents a unique pattern and includes details about its characteristics, risk level, and a brief description.
    base_table:
      database: FRAUD_DETECTION_DB
      schema: FRAUD_DETECTION_SCHEMA
      table: FRAUD_PATTERNS
    dimensions:
      - name: DESCRIPTION
        description: A brief description of the reason why a transaction was flagged as potentially fraudulent.
        expr: DESCRIPTION
        data_type: VARCHAR
        sample_values:
          - Multiple transactions in a short time window indicating automated or fraudulent activity
          - Transaction amount significantly exceeds the customer's typical spending pattern
          - Transaction originates from a location inconsistent with the customer's typical location
      - name: PATTERN_ID
        description: Unique identifier for a specific pattern of fraudulent activity.
        expr: PATTERN_ID
        data_type: VARCHAR
        sample_values:
          - FP002
          - FP005
          - FP003
      - name: PATTERN_NAME
        description: The name of the pattern indicating a potential fraudulent activity.
        expr: PATTERN_NAME
        data_type: VARCHAR
        sample_values:
          - Large Amount Anomaly
          - Geographic Mismatch
          - Rapid Transactions
      - name: PATTERN_TYPE
        description: The type of pattern used to detect fraudulent activity.
        expr: PATTERN_TYPE
        data_type: VARCHAR
        sample_values:
          - geographic
          - velocity
          - amount
      - name: RISK_SCORE
        description: A numerical score indicating the likelihood of a transaction being fraudulent.
        expr: RISK_SCORE
        data_type: NUMBER
        sample_values:
          - '30'
          - '25'
          - '20'
    primary_key:
      columns:
        - PATTERN_ID
  - name: MERCHANT_BLACKLIST
    description: The table contains records of merchants that have been flagged for suspicious activity. Each record represents a single merchant and includes details about the reason for blacklisting and the date it occurred, as well as a summary of associated fraud reports.
    base_table:
      database: FRAUD_DETECTION_DB
      schema: FRAUD_DETECTION_SCHEMA
      table: MERCHANT_BLACKLIST
    dimensions:
      - name: FRAUD_REPORTS
        description: The number of reports indicating potential fraudulent activity.
        expr: FRAUD_REPORTS
        data_type: NUMBER
        sample_values:
          - '89'
          - '234'
          - '156'
      - name: MERCHANT_NAME
        description: The name of the merchant.
        expr: MERCHANT_NAME
        data_type: VARCHAR
        sample_values:
          - AnyCompany Fraudulent Lending Services
          - AnyCompany Counterfeit Goods
          - AnyCompany Crypto Exchange
      - name: REASON
        description: The reason for adding a merchant to the blocklist.
        expr: REASON
        data_type: VARCHAR
        sample_values:
          - Predatory lending and identity theft
          - Counterfeit goods and card skimming
          - Cryptocurrency fraud scheme
    time_dimensions:
      - name: BLACKLIST_DATE
        description: The date a merchant was added to the blocklist.
        expr: BLACKLIST_DATE
        data_type: DATE
        sample_values:
          - '2023-09-15'
          - '2024-01-05'
          - '2023-11-20'
    primary_key:
      columns:
        - MERCHANT_NAME
relationships:
  - name: TRANSACTIONS_TO_CUSTOMERS
    left_table: TRANSACTIONS
    right_table: CUSTOMERS
    join_type: inner
    relationship_type: many_to_one
    relationship_columns:
      - left_column: CUSTOMER_ID
        right_column: CUSTOMER_ID
  - name: TRANSACTIONS_TO_MERCHANT_BLACKLIST
    left_table: TRANSACTIONS
    right_table: MERCHANT_BLACKLIST
    join_type: inner
    relationship_type: many_to_one
    relationship_columns:
      - left_column: MERCHANT_NAME
        right_column: MERCHANT_NAME
verified_queries:
  - name: 0;1
    question: Which transactions are flagged by fraud patterns based on high transaction amounts, blacklisted merchants, failed status, or suspicious IP addresses?
    sql: SELECT t.transaction_id, t.customer_id, t.amount, t.merchant_name, fp.pattern_name, fp.pattern_type, fp.risk_score FROM transactions AS t JOIN customers AS c ON t.customer_id = c.customer_id JOIN fraud_patterns AS fp ON (fp.pattern_type = 'amount' AND t.amount > c.average_transaction_amount * 3) OR (fp.pattern_type = 'merchant' AND t.merchant_name IN (SELECT merchant_name FROM merchant_blacklist)) OR (fp.pattern_type = 'behavioral' AND t.status = 'failed') OR (fp.pattern_type = 'geographic' AND t.ip_address LIKE '41.%') /* Africa/Middle-East IP range */ ORDER BY t.transaction_id, fp.risk_score DESC
    verified_at: 1771609985
    verified_by: Semantic Model Generator
  - name: 1;1
    question: Which customers have at least two failed transaction attempts followed by at least one successful transaction?
    sql: SELECT customer_id, COUNT_IF(status = 'failed') AS failed_attempts, COUNT_IF(status = 'completed') AS completions, MIN(transaction_date) AS first_attempt, MAX(transaction_date) AS last_attempt FROM transactions GROUP BY customer_id HAVING failed_attempts >= 2 AND completions >= 1
    verified_at: 1771609985
    verified_by: Semantic Model Generator
  - name: 2;1
    question: Which customers have made two or more transactions within a 10-minute window?
    sql: SELECT a.customer_id, a.transaction_id, b.transaction_id AS nearby_txn_id, a.transaction_date, b.transaction_date, DATEDIFF(MINUTE, a.transaction_date, b.transaction_date) AS minutes_apart FROM transactions AS a JOIN transactions AS b ON a.customer_id = b.customer_id AND a.transaction_id < b.transaction_id AND DATEDIFF(MINUTE, a.transaction_date, b.transaction_date) <= 10 ORDER BY a.customer_id, a.transaction_date
    verified_at: 1771609985
    verified_by: Semantic Model Generator
  - name: 3;1
    question: Which transactions involve merchants that are on the blocklist?
    sql: SELECT t.transaction_id, t.customer_id, t.amount, t.merchant_name, m.reason, m.fraud_reports FROM transactions AS t JOIN merchant_blacklist AS m ON t.merchant_name = m.merchant_name
    verified_at: 1771609985
    verified_by: Semantic Model Generator
  - name: 4;1
    question: Which transactions exceed 3 times the customer's average spend?
    sql: SELECT t.transaction_id, t.customer_id, t.amount, c.average_transaction_amount, ROUND(t.amount / c.average_transaction_amount, 1) AS spend_multiplier, t.merchant_name, t.transaction_date FROM transactions AS t JOIN customers AS c ON t.customer_id = c.customer_id WHERE t.amount > c.average_transaction_amount * 3 ORDER BY spend_multiplier DESC
    verified_at: 1771609985
    verified_by: Semantic Model Generator
$$
);


USE ROLE ACCOUNTADMIN;
GRANT SELECT ON VIEW FRAUD_DETECTION_DB.FRAUD_DETECTION_SCHEMA.FRAUD_DETECTION_SEMANTIC_VIEW TO ROLE FRAUD_DETECTION_RL;

-- ============================================================
-- Done! Semantic view created and access granted.
-- Next: run 4_cortex_agent_setup.sql as FRAUD_DETECTION_RL.
-- ============================================================
