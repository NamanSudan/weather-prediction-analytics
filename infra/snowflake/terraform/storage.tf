# Database and medallion-style schemas. Tables inside them are created by the pipelines
# (Airflow DDL for RAW, dbt for everything downstream), not by Terraform.
resource "snowflake_database" "weather" {
  name                        = var.database_name
  data_retention_time_in_days = 1
  comment                     = "Weather prediction analytics lab. Managed by Terraform."

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  schemas = {
    RAW       = "Landing zone: Open-Meteo API data loaded as-is by the Airflow ETL DAG (owner: LOADER)."
    STAGING   = "dbt staging/intermediate models: typed, deduplicated, renamed (owner: TRANSFORMER)."
    ANALYTICS = "dbt marts: metrics, forecasts and accuracy tables read by the BI tools (owner: TRANSFORMER)."
    SNAPSHOTS = "dbt snapshots: SCD2 history of forecast revisions (owner: TRANSFORMER)."
    ML        = "SNOWFLAKE.ML.FORECAST model objects and their raw outputs (owner: TRANSFORMER)."
  }
}

# Personal sandboxes: collaborators build/test dbt models here (dbt `dev` target) and only
# the pipelines' service users write the shared schemas above.
locals {
  dev_schema_owners = toset(concat(keys(var.developers), var.existing_developer_users))
}

resource "snowflake_schema" "dev" {
  for_each = local.dev_schema_owners

  database     = snowflake_database.weather.name
  name         = "DEV_${each.key}"
  is_transient = "true"
  comment      = "Personal dbt sandbox for ${each.key} (transient: no fail-safe storage cost). Managed by Terraform."
}

resource "snowflake_schema" "this" {
  for_each = local.schemas

  database = snowflake_database.weather.name
  name     = each.key
  comment  = "${each.value} Managed by Terraform."
}
