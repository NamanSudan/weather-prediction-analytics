# Privilege matrix (least privilege). Read it as "role -> what it may do where".
#
#                 WAREHOUSE     DB    RAW             STAGING/ANALYTICS/SNAPSHOTS   ML                 DEV_*
#   LOADER        WEATHER_WH    use   use+create tbl  -                             -                  -
#   TRANSFORMER   WEATHER_WH    use   use+select      use+create tbl/view           use+create+FORECAST -
#   REPORTER      WEATHER_WH    use   -               select (ANALYTICS,SNAPSHOTS)  -                  -
#   LAB_DEVELOPER DEV_WH        use   select          select                        select             use+create tbl/view
#
# Warehouses get USAGE only: nobody but SYSADMIN (Terraform) can resize, resume-policy-edit or
# re-own them. No custom role has any account-level privilege (no CREATE DATABASE/WAREHOUSE/
# USER/ROLE, no MANAGE GRANTS), so configuration control stays with the account owner.

locals {
  pipeline_roles = ["LOADER", "TRANSFORMER", "REPORTER"]
  all_roles      = concat(local.pipeline_roles, ["LAB_DEVELOPER"])

  warehouse_grants = merge(
    { for r in local.pipeline_roles : r => "pipeline" },
    { LAB_DEVELOPER = "dev" },
  )

  # role/schema -> schema-level privileges
  schema_grants = merge(
    {
      "LOADER/RAW"            = ["USAGE", "CREATE TABLE"]
      "TRANSFORMER/RAW"       = ["USAGE"]
      "TRANSFORMER/STAGING"   = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
      "TRANSFORMER/ANALYTICS" = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
      "TRANSFORMER/SNAPSHOTS" = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
      "TRANSFORMER/ML"        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE SNOWFLAKE.ML.FORECAST"]
      "REPORTER/ANALYTICS"    = ["USAGE"]
      "REPORTER/SNAPSHOTS"    = ["USAGE"]
    },
    { for s in keys(local.schemas) : "LAB_DEVELOPER/${s}" => ["USAGE"] },
  )

  dev_schema_privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  # role/schema -> SELECT on existing + future tables and views
  read_scopes = concat(
    ["TRANSFORMER/RAW", "REPORTER/ANALYTICS", "REPORTER/SNAPSHOTS"],
    [for s in keys(local.schemas) : "LAB_DEVELOPER/${s}"],
  )
  read_grants = {
    for combo in setproduct(local.read_scopes, ["TABLES", "VIEWS"]) : "${combo[0]}/${combo[1]}" => {
      role   = split("/", combo[0])[0]
      schema = split("/", combo[0])[1]
      type   = combo[1]
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  provider = snowflake.security
  for_each = local.warehouse_grants

  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.this[each.value].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  provider = snowflake.security
  for_each = toset(local.all_roles)

  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.weather.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema" {
  provider = snowflake.security
  for_each = local.schema_grants

  account_role_name = snowflake_account_role.this[split("/", each.key)[0]].name
  privileges        = each.value
  on_schema {
    schema_name = snowflake_schema.this[split("/", each.key)[1]].fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_schema" {
  provider = snowflake.security
  for_each = snowflake_schema.dev

  account_role_name = snowflake_account_role.this["LAB_DEVELOPER"].name
  privileges        = local.dev_schema_privileges
  on_schema {
    schema_name = each.value.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "select_existing" {
  provider = snowflake.security
  for_each = local.read_grants

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      object_type_plural = each.value.type
      in_schema          = snowflake_schema.this[each.value.schema].fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "select_future" {
  provider = snowflake.security
  for_each = local.read_grants

  account_role_name = snowflake_account_role.this[each.value.role].name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = each.value.type
      in_schema          = snowflake_schema.this[each.value.schema].fully_qualified_name
    }
  }
}
