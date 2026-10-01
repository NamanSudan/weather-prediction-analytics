# Infrastructure (Snowflake as code)

| Step | Who | Command / file |
|---|---|---|
| 1. Key pairs for the service users | anyone | `make keys` → `secrets/snowflake/<user>/rsa_key.{p8,pub}` (gitignored) |
| 2. Terraform's own identity + account spend monitor | **ACCOUNTADMIN, once** | `make bootstrap-sql`, then run `snowflake/bootstrap/00_bootstrap.rendered.sql` in Snowsight (**Run All**: ⌘⇧↩) |
| 3. Everything else | account owner | `make tf-plan` (fmt, validate, plan, OPA policy check), review, then `make tf-apply` |
| 4. Collaborator cap + `PUBLIC` hardening | **ACCOUNTADMIN, once** | run `snowflake/bootstrap/01_guardrails.sql` |

Terraform (`snowflakedb/snowflake` ~> 2.21) manages these objects:
- Warehouses: `WEATHER_WH` (pipelines) and `DEV_WH` (humans)
- Database `WEATHER_DB`, with schemas RAW, STAGING, ANALYTICS, SNAPSHOTS, ML and one DEV_<user> sandbox per collaborator
- Roles LOADER, TRANSFORMER, REPORTER and LAB_DEVELOPER, and the grants between them
- Service users SVC_ETL, SVC_DBT and SVC_BI
- Collaborator users, with expiring access

It authenticates as `SVC_TERRAFORM`, a key-pair TYPE=SERVICE user, and uses two provider aliases:
SYSADMIN for objects and SECURITYADMIN for users, roles and grants.
Only ACCOUNTADMIN can create resource monitors, so they live in the bootstrap SQL.

`policies/` holds the OPA/Rego rules evaluated against every plan (`make policy`), with unit tests (`make policy-test`):
- allow-listed resource types
- XSMALL/SMALL warehouses only, with `auto_suspend` ≤ 300 s and a statement timeout ≤ 1 h
- no ACCOUNTADMIN/SECURITYADMIN grants, no account-level privileges, and USAGE-only warehouse grants
- service users must have an RSA key
- collaborators must change their password and have an expiry
- every object needs a comment
- no database or schema drops

State is local and gitignored, with a single applier.
