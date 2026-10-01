# --- service users: one per tool, key-pair only (TYPE=SERVICE => no password, no MFA) ---
locals {
  service_users = {
    SVC_ETL = { key_dir = "svc_etl", role = "LOADER", purpose = "Airflow ETL DAG (Open-Meteo -> RAW)" }
    SVC_DBT = { key_dir = "svc_dbt", role = "TRANSFORMER", purpose = "dbt run/test/snapshot + ML forecast" }
    SVC_BI  = { key_dir = "svc_bi", role = "REPORTER", purpose = "Superset and Grafana (read-only)" }
  }

  # rsa_public_key wants the base64 body without the PEM header/footer lines
  public_keys = {
    for name, u in local.service_users : name => join("", [
      for line in split("\n", trimspace(file("${var.secrets_dir}/${u.key_dir}/rsa_key.pub"))) :
      line if !startswith(line, "-----")
    ])
  }
}

resource "snowflake_service_user" "this" {
  provider = snowflake.security
  for_each = local.service_users

  name              = each.key
  rsa_public_key    = local.public_keys[each.key]
  default_role      = each.value.role
  default_warehouse = snowflake_warehouse.this["pipeline"].name
  comment           = "${each.value.purpose}. Managed by Terraform."
}

resource "snowflake_grant_account_role" "service_user_role" {
  provider = snowflake.security
  for_each = local.service_users

  role_name = snowflake_account_role.this[each.value.role].name
  user_name = snowflake_service_user.this[each.key].name
}

# --- human collaborators ------------------------------------------------------------
# Snowflake does not e-mail new users. Onboarding = send the account URL + login name,
# hand over the one-time password on a separate channel (e.g. the call), and the person
# changes it and enrols MFA at first login.
resource "random_password" "developer" {
  for_each = var.developers

  length           = 20
  special          = true
  override_special = "!#%*-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "snowflake_user" "developer" {
  provider = snowflake.security
  for_each = var.developers

  name                 = each.key
  login_name           = each.key
  first_name           = each.value.first_name
  last_name            = each.value.last_name
  display_name         = "${each.value.first_name} ${each.value.last_name}"
  email                = each.value.email
  password             = random_password.developer[each.key].result
  must_change_password = "true"
  default_role         = snowflake_account_role.this["LAB_DEVELOPER"].name
  default_warehouse    = snowflake_warehouse.this["dev"].name
  default_namespace    = "${snowflake_database.weather.name}.DEV_${each.key}"
  disabled             = each.value.enabled ? "false" : "true"
  days_to_expiry       = each.value.days_to_expiry
  comment              = "Lab collaborator (access auto-expires after ${each.value.days_to_expiry} days). Managed by Terraform."

  lifecycle {
    # after the first login the person owns their password; never reset it on re-apply.
    # days_to_expiry counts down server-side, so don't fight it on every plan.
    ignore_changes = [password, must_change_password, days_to_expiry]
  }
}

resource "snowflake_grant_account_role" "developer_role" {
  provider = snowflake.security
  for_each = var.developers

  role_name = snowflake_account_role.this["LAB_DEVELOPER"].name
  user_name = snowflake_user.developer[each.key].name
}

resource "snowflake_grant_account_role" "existing_developer_role" {
  provider = snowflake.security
  for_each = toset(var.existing_developer_users)

  role_name = snowflake_account_role.this["LAB_DEVELOPER"].name
  user_name = each.value
}
