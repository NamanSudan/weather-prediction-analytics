-- =============================================================================
-- Account guardrails (ACCOUNTADMIN only; run once AFTER the first `make tf-apply`)
-- =============================================================================
-- Things only ACCOUNTADMIN can do, which is why they are here and not in Terraform
-- (SVC_TERRAFORM deliberately never holds ACCOUNTADMIN):
--   1. Hard spend cap on DEV_WH (the collaborators' warehouse)
--   2. Strip the built-in PUBLIC role (every user gets it) down so collaborators see and
--      spend only on the lab: no learning warehouse, compute pools, Cortex/AI, sample data
--   3. Account-wide statement timeout (default was 48 h)
-- Safe to re-run.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Hard cap for collaborators -----------------------------------------------
CREATE RESOURCE MONITOR IF NOT EXISTS LAB_DEV_MONITOR
  WITH CREDIT_QUOTA = 2
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 50  PERCENT DO NOTIFY
           ON 75  PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE DEV_WH SET RESOURCE_MONITOR = LAB_DEV_MONITOR;

-- 2. PUBLIC hardening (re-grant to ACCOUNTADMIN first so the owner loses nothing) ----
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER  TO ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.COPILOT_USER TO ROLE ACCOUNTADMIN;
GRANT USE AI FUNCTIONS ON ACCOUNT          TO ROLE ACCOUNTADMIN;
GRANT ROLE SNOWFLAKE_LEARNING_ROLE         TO ROLE ACCOUNTADMIN;

REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER  FROM ROLE PUBLIC;
REVOKE DATABASE ROLE SNOWFLAKE.COPILOT_USER FROM ROLE PUBLIC;
REVOKE USE AI FUNCTIONS ON ACCOUNT          FROM ROLE PUBLIC;
REVOKE ROLE SNOWFLAKE_LEARNING_ROLE         FROM ROLE PUBLIC;
REVOKE IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA FROM ROLE PUBLIC;
REVOKE USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU FROM ROLE PUBLIC;
REVOKE USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_GPU FROM ROLE PUBLIC;

-- 3. No runaway queries anywhere (warehouses have tighter limits of their own) --------
ALTER ACCOUNT SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;

-- Verify -------------------------------------------------------------------------
SHOW RESOURCE MONITORS;
SHOW GRANTS TO ROLE PUBLIC;
