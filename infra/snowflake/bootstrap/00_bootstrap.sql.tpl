-- =============================================================================
-- One-time Snowflake bootstrap (the ONLY manual step; everything else is Terraform)
-- =============================================================================
-- Run once as ACCOUNTADMIN in a Snowsight worksheet, after `make keys` + `make bootstrap-sql`.
-- It creates:
--   1. SVC_TERRAFORM: key-pair service user that Terraform authenticates as
--      (holds SYSADMIN for objects and SECURITYADMIN for users/roles/grants; never ACCOUNTADMIN)
--   2. LAB_MONTHLY_MONITOR: account-level credit monitor (only ACCOUNTADMIN can create one),
--      notify-only so the pipeline is never hard-stopped mid-demo
-- Safe to re-run: every statement is IF NOT EXISTS or an idempotent ALTER.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Terraform service identity ---------------------------------------------
CREATE USER IF NOT EXISTS SVC_TERRAFORM
  TYPE = SERVICE
  DEFAULT_ROLE = SYSADMIN
  COMMENT = 'Terraform deployer for the weather analytics lab (key-pair auth, managed outside TF)';

ALTER USER SVC_TERRAFORM SET RSA_PUBLIC_KEY = '{{TERRAFORM_PUBLIC_KEY}}';

GRANT ROLE SYSADMIN      TO USER SVC_TERRAFORM;
GRANT ROLE SECURITYADMIN TO USER SVC_TERRAFORM;

-- 2. Cost guardrail (notify only) ---------------------------------------------
CREATE RESOURCE MONITOR IF NOT EXISTS LAB_MONTHLY_MONITOR
  WITH CREDIT_QUOTA = 10
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 50  PERCENT DO NOTIFY
           ON 75  PERCENT DO NOTIFY
           ON 100 PERCENT DO NOTIFY
           ON 150 PERCENT DO NOTIFY;

ALTER ACCOUNT SET RESOURCE_MONITOR = LAB_MONTHLY_MONITOR;

-- 3. Verify --------------------------------------------------------------------
SHOW USERS LIKE 'SVC_TERRAFORM';
SHOW RESOURCE MONITORS LIKE 'LAB_MONTHLY_MONITOR';
