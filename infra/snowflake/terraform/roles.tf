# Functional roles (least privilege). Every custom role rolls up to SYSADMIN so the
# object owner can always manage what these roles create.
locals {
  roles = {
    LOADER        = "Writes RAW. Used by the Airflow ETL DAG (SVC_ETL)."
    TRANSFORMER   = "Reads RAW; builds STAGING, ANALYTICS, SNAPSHOTS, ML. Used by dbt (SVC_DBT)."
    REPORTER      = "Read-only on ANALYTICS and SNAPSHOTS. Used by Superset/Grafana (SVC_BI)."
    LAB_DEVELOPER = "Human collaborators: read the lab schemas, build in DEV_* sandboxes, DEV_WH only."
  }
}

resource "snowflake_account_role" "this" {
  provider = snowflake.security
  for_each = local.roles

  name    = each.key
  comment = "${each.value} Managed by Terraform."
}

resource "snowflake_grant_account_role" "to_sysadmin" {
  provider = snowflake.security
  for_each = snowflake_account_role.this

  role_name        = each.value.name
  parent_role_name = "SYSADMIN"
}

# LAB_DEVELOPER deliberately does NOT inherit the pipeline roles: inheriting them would also
# inherit WEATHER_WH and write access to the shared schemas. Its privileges are granted directly
# in grants.tf.
