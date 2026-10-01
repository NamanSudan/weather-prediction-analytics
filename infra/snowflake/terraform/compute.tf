# Two XSMALL warehouses so pipeline spend and human spend are separated and capped independently.
# Per-second billing with a 60 s minimum on resume, so aggressive auto-suspend is cheapest.
#
#   WEATHER_WH  pipelines only (service users). Covered by the account-level LAB_MONTHLY_MONITOR.
#   DEV_WH      collaborators only. Gets its own hard-capped LAB_DEV_MONITOR, assigned by
#               infra/snowflake/bootstrap/01_guardrails.sql (monitor assignment is ACCOUNTADMIN-only).
locals {
  warehouses = {
    pipeline = {
      name              = var.warehouse_name
      statement_timeout = 1800
      comment           = "Pipelines only: Airflow ETL, dbt, ML forecast, BI service users."
    }
    dev = {
      name              = var.dev_warehouse_name
      statement_timeout = 600
      comment           = "Human collaborators only; hard-capped by LAB_DEV_MONITOR."
    }
  }
}

resource "snowflake_warehouse" "this" {
  for_each = local.warehouses

  name                                = each.value.name
  warehouse_size                      = var.warehouse_size
  auto_suspend                        = 60
  auto_resume                         = "true"
  initially_suspended                 = true
  statement_timeout_in_seconds        = each.value.statement_timeout
  statement_queued_timeout_in_seconds = 300
  comment                             = "${each.value.comment} Managed by Terraform."

  lifecycle {
    # resource monitors are attached by ACCOUNTADMIN in 01_guardrails.sql, not by Terraform
    ignore_changes = [resource_monitor]
  }
}
